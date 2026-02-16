//
//  MenuBarController.swift
//  AutoSub
//
//  AppKit Menu Bar 控制器（NSStatusItem + NSMenu）
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var lifecycleController: AppLifecycleController?

    func configure(
        appState: AppState,
        audioService: AudioCaptureService,
        pythonBridge: PythonBridgeService?,
        subtitleWindowController: SubtitleWindowController
    ) {
        MenuActionHandler.shared.configure(appState: appState)
        if let existing = MenuBarController.shared {
            menuBarController = existing
        } else {
            menuBarController = MenuBarController(
                appState: appState,
                audioService: audioService,
                pythonBridge: pythonBridge,
                subtitleWindowController: subtitleWindowController,
                settingsTarget: MenuActionHandler.shared
            )
        }
        if lifecycleController == nil, let menuBarController {
            lifecycleController = AppLifecycleController(
                appState: appState,
                subtitleWindowController: subtitleWindowController,
                toggleCaptureHandler: { menuBarController.toggleCaptureFromShortcut() }
            )
            lifecycleController?.start()
        }
    }
}

@MainActor
final class MenuActionHandler: NSObject {
    static let shared = MenuActionHandler()

    private var appState: AppState?
    private var settingsWindowController: SettingsWindowController?

    func configure(appState: AppState) {
        self.appState = appState
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: appState)
        }
    }

    @objc func openSettings(_ sender: Any?) {
        if let appState, settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: appState)
        }
        settingsWindowController?.show()
    }
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static var shared: MenuBarController?

    private let appState: AppState
    private let audioService: AudioCaptureService
    private let pythonBridge: PythonBridgeService?
    private let subtitleWindowController: SubtitleWindowController

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()
    private var recoveryTask: Task<Void, Never>?
    private let maxRecoveryAttempts = 3
    private let recoveryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
    private var menuUpdateTimer: Timer?

    private let statusMenuItem = NSMenuItem()
    private let profileMenuItem = NSMenuItem()
    private let captureMenuItem = NSMenuItem()
    private let exportMenuItem = NSMenuItem()
    private let settingsMenuItem = NSMenuItem()
    private let subtitleLockMenuItem = NSMenuItem()
    private let resetSubtitleMenuItem = NSMenuItem()
    private let quitMenuItem = NSMenuItem()

    private let statusRowView = StatusMenuItemView()
    private let profileSubmenu = NSMenu()
    private let exportSubmenu = NSMenu()
    private let settingsTarget: MenuActionHandler
    private let exportTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private enum ErrorSource {
        case audio
        case python
    }

    init(
        appState: AppState,
        audioService: AudioCaptureService,
        pythonBridge: PythonBridgeService?,
        subtitleWindowController: SubtitleWindowController,
        settingsTarget: MenuActionHandler
    ) {
        self.appState = appState
        self.audioService = audioService
        self.pythonBridge = pythonBridge
        self.subtitleWindowController = subtitleWindowController
        self.settingsTarget = settingsTarget
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        MenuBarController.shared = self
        setupStatusItem()
        buildMenu()
        bindAppState()
        refreshAll()
    }



    func toggleCaptureFromShortcut() {
        handleToggleCapture(nil)
    }

    // MARK: - Menu Setup

    private func setupStatusItem() {
        statusItem.button?.image = NSImage(systemSymbolName: menuBarIconName, accessibilityDescription: nil)
    }

    private func buildMenu() {
        menu.autoenablesItems = false

        statusRowView.frame = NSRect(x: 0, y: 0, width: 220, height: 22)
        statusMenuItem.view = statusRowView
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        profileMenuItem.submenu = profileSubmenu
        profileMenuItem.image = NSImage(systemSymbolName: "person.text.rectangle", accessibilityDescription: nil)
        menu.addItem(profileMenuItem)

        captureMenuItem.target = self
        captureMenuItem.action = #selector(handleToggleCapture(_:))
        menu.addItem(captureMenuItem)

        // 匯出選項（最近 5 筆 transcription 子選單）
        exportMenuItem.title = "匯出 transcription（SRT）"
        exportMenuItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        exportMenuItem.submenu = exportSubmenu
        menu.addItem(exportMenuItem)

        menu.addItem(.separator())

        settingsMenuItem.title = "設定..."
        settingsMenuItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsMenuItem.target = settingsTarget
        settingsMenuItem.action = #selector(MenuActionHandler.openSettings(_:))
        menu.addItem(settingsMenuItem)

        subtitleLockMenuItem.target = self
        subtitleLockMenuItem.action = #selector(toggleSubtitleLock(_:))
        menu.addItem(subtitleLockMenuItem)

        resetSubtitleMenuItem.title = "重設字幕位置"
        resetSubtitleMenuItem.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        resetSubtitleMenuItem.target = self
        resetSubtitleMenuItem.action = #selector(resetSubtitlePosition(_:))
        menu.addItem(resetSubtitleMenuItem)

        menu.addItem(.separator())

        quitMenuItem.title = "結束 Auto-Sub"
        quitMenuItem.target = self
        quitMenuItem.action = #selector(quitApp(_:))
        menu.addItem(quitMenuItem)

        menu.delegate = self
        statusItem.menu = menu
    }

    private func bindAppState() {
        appState.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshStatus()
            }
            .store(in: &cancellables)

        appState.$statusMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshStatus()
            }
            .store(in: &cancellables)

        appState.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshStatus()
            }
            .store(in: &cancellables)

        appState.$isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCaptureItem()
                self?.refreshProfileMenu()
            }
            .store(in: &cancellables)

        appState.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshProfileMenu()
            }
            .store(in: &cancellables)

        appState.$selectedProfileId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshProfileMenu()
            }
            .store(in: &cancellables)

        appState.$deepgramApiKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCaptureItem()
            }
            .store(in: &cancellables)

        appState.$geminiApiKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCaptureItem()
            }
            .store(in: &cancellables)

        appState.$isSubtitleLocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSubtitleLockItem()
            }
            .store(in: &cancellables)

        appState.$recentTranscriptions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshExportItem()
            }
            .store(in: &cancellables)

        appState.$isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshExportItem()
            }
            .store(in: &cancellables)
    }

    private func refreshAll() {
        refreshStatus()
        refreshProfileMenu()
        refreshCaptureItem()
        refreshExportItem()
        refreshSubtitleLockItem()
    }

    private func refreshStatus() {
        statusRowView.update(text: statusText, color: statusColor)
        statusItem.button?.image = NSImage(systemSymbolName: menuBarIconName, accessibilityDescription: nil)
    }

    private func refreshProfileMenu() {
        profileMenuItem.title = "Profile：\(appState.currentProfile.displayName)"
        profileMenuItem.isEnabled = !appState.isCapturing
        profileSubmenu.removeAllItems()

        for profile in appState.profiles {
            let item = NSMenuItem(title: profile.displayName, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == appState.selectedProfileId ? .on : .off
            profileSubmenu.addItem(item)
        }
    }

    private func refreshCaptureItem() {
        let shouldRestart = appState.status == .error && !appState.isCapturing
        captureMenuItem.title = appState.isCapturing
            ? "停止擷取"
            : (shouldRestart ? "重新開始擷取" : "開始擷取")
        captureMenuItem.image = NSImage(
            systemSymbolName: appState.isCapturing ? "stop.fill" : "play.fill",
            accessibilityDescription: nil
        )
        captureMenuItem.isEnabled = appState.isReady
    }

    private func refreshSubtitleLockItem() {
        subtitleLockMenuItem.title = "鎖定字幕位置"
        subtitleLockMenuItem.state = appState.isSubtitleLocked ? .on : .off
        subtitleLockMenuItem.image = NSImage(
            systemSymbolName: appState.isSubtitleLocked ? "lock.fill" : "lock.open",
            accessibilityDescription: nil
        )
    }

    private func refreshExportItem() {
        let sessions = Array(appState.recentTranscriptions.prefix(5))
        let hasContent = !sessions.isEmpty
        exportMenuItem.isEnabled = hasContent && !appState.isCapturing
        exportMenuItem.title = hasContent
            ? "匯出 transcription（最近 5 筆）"
            : "匯出 transcription（無內容）"

        exportSubmenu.removeAllItems()

        guard hasContent else {
            let emptyItem = NSMenuItem(title: "無可匯出的 transcription", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            exportSubmenu.addItem(emptyItem)
            return
        }

        for session in sessions {
            let title = exportTimeFormatter.string(from: session.startTime)
            let item = NSMenuItem(title: title, action: #selector(handleExportRecentSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = session.id
            exportSubmenu.addItem(item)
        }
    }

    // MARK: - Menu Actions

    @objc private func handleToggleCapture(_ sender: Any?) {
        Task { @MainActor in
            if appState.isCapturing {
                await stopCapture()
            } else {
                await startCapture()
            }
        }
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let profileId = sender.representedObject as? UUID else { return }
        appState.selectProfile(id: profileId)
    }

    @objc private func toggleSubtitleLock(_ sender: NSMenuItem) {
        appState.isSubtitleLocked.toggle()
        subtitleWindowController.updateMouseEventHandling()
        appState.saveSubtitlePosition()
    }

    @objc private func resetSubtitlePosition(_ sender: NSMenuItem) {
        appState.resetSubtitlePosition()
        subtitleWindowController.resetPosition()
    }

    @objc private func handleExportRecentSession(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? UUID,
              let session = appState.recentTranscriptions.first(where: { $0.id == sessionId }) else {
            return
        }
        exportSession(session)
    }

    private func exportSession(_ session: TranscriptionSession) {
        // Menu Bar App 先啟用前景，避免 Save Panel 被其他視窗壓在後方。
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)

        // 避免在 NSMenu tracking loop 內直接開 panel，下一個 runloop 再顯示更穩定。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let panel = NSSavePanel()
            panel.title = "匯出字幕"
            panel.message = "選擇儲存位置與匯出內容"

            // 預設檔名：使用該 session 的開始時間（與匯出子選單顯示時間一致）
            let menuTimestamp = self.exportTimeFormatter.string(from: session.startTime)
            let filenameTimestamp = menuTimestamp.replacingOccurrences(of: ":", with: "-")
            panel.nameFieldStringValue = "AutoSub_\(filenameTimestamp).srt"

            panel.allowedContentTypes = [.init(filenameExtension: "srt")!]
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            panel.canCreateDirectories = true

            // 建立 accessory view（Popup Button）
            let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))

            let label = NSTextField(labelWithString: "匯出內容：")
            label.frame = NSRect(x: 0, y: 6, width: 75, height: 20)
            label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            accessoryView.addSubview(label)

            let popup = NSPopUpButton(frame: NSRect(x: 80, y: 4, width: 210, height: 24))
            popup.addItems(withTitles: ExportMode.allCases.map { $0.rawValue })
            popup.selectItem(at: 0)  // 預設選「雙語」
            accessoryView.addSubview(popup)

            panel.accessoryView = accessoryView

            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return }

            let mode = ExportMode.allCases[popup.indexOfSelectedItem]
            let content = ExportService.exportToSRT(session.subtitles, startTime: session.startTime, mode: mode)
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                print("[MenuBarController] Exported to: \(url.path)")
            } catch {
                print("[MenuBarController] Export failed: \(error)")
            }
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private var statusText: String {
        if let statusMessage = appState.statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        switch appState.status {
        case .idle: return "待機中"
        case .capturing:
            if let startTime = appState.captureStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                return "擷取中 · \(formatDuration(elapsed))"
            }
            return "擷取中"
        case .warning: return "警告"
        case .error: return appState.errorMessage ?? "錯誤"
        }
    }

    /// 格式化時長為 MM:SS 或 H:MM:SS
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    private var statusColor: NSColor {
        switch appState.status {
        case .idle: return .labelColor
        case .capturing: return .systemGreen
        case .warning: return .systemYellow
        case .error: return .systemRed
        }
    }

    private var menuBarIconName: String {
        switch appState.status {
        case .idle: return "captions.bubble"
        case .capturing: return "captions.bubble.fill"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        Task { @MainActor in
            refreshStatus()
        }
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            startMenuUpdateTimer()
        }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        Task { @MainActor in
            stopMenuUpdateTimer()
        }
    }

    @MainActor
    private func startMenuUpdateTimer() {
        stopMenuUpdateTimer()
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
        RunLoop.current.add(menuUpdateTimer!, forMode: .common)
    }

    @MainActor
    private func stopMenuUpdateTimer() {
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = nil
    }

    // MARK: - Error Handling & Recovery

    private func makePythonBridgeError(_ message: String) -> NSError {
        NSError(domain: "PythonBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func handleCaptureError(_ error: Error, source: ErrorSource) {
        if appState.isRecovering {
            if source == .python {
                return
            }
            return
        }

        guard appState.isCapturing else {
            appState.status = .error
            appState.statusMessage = "錯誤已發生"
            appState.errorMessage = error.localizedDescription
            return
        }

        appState.status = .error
        appState.statusMessage = "錯誤已發生"
        appState.errorMessage = error.localizedDescription

        startRecoveryFlow()
    }

    private func startRecoveryFlow() {
        recoveryTask?.cancel()
        appState.isRecovering = true
        appState.recoveryAttempt = 0

        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self.runRecoveryLoop()
        }
    }

    private func runRecoveryLoop() async {
        for attempt in 1...maxRecoveryAttempts {
            if Task.isCancelled { return }

            await stopCapture()

            appState.recoveryAttempt = attempt
            appState.status = .warning
            appState.statusMessage = "正在重新連線 (\(attempt)/\(maxRecoveryAttempts))"

            await startCapture()

            if appState.isCapturing {
                appState.isRecovering = false
                appState.recoveryAttempt = 0
                appState.status = .capturing
                appState.statusMessage = "已恢復音訊擷取"
                scheduleStatusMessageClear(expectedMessage: "已恢復音訊擷取", afterSeconds: 3)
                return
            }

            appState.status = .warning

            if attempt < maxRecoveryAttempts {
                let delay = recoveryDelay(for: attempt)
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        appState.isRecovering = false
        appState.recoveryAttempt = 0
        appState.status = .error
        appState.statusMessage = "音訊擷取失敗，點此重新開始"
        appState.isCapturing = false
    }

    private func recoveryDelay(for attempt: Int) -> UInt64 {
        let index = max(0, min(attempt - 1, recoveryDelays.count - 1))
        return recoveryDelays[index]
    }

    private func scheduleStatusMessageClear(expectedMessage: String, afterSeconds seconds: UInt64) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self else { return }
            if self.appState.statusMessage == expectedMessage {
                self.appState.statusMessage = nil
            }
        }
    }

    // MARK: - Capture Helper Methods (Tier 1-2 重構)

    /// 從 AppState 建構 Configuration 物件
    private func buildConfiguration(from state: AppState) -> Configuration {
        let profile = state.currentProfile
        return Configuration(
            deepgramApiKey: state.deepgramApiKey,
            geminiApiKey: state.geminiApiKey,
            geminiModel: state.geminiModel,
            geminiMaxContextTokens: state.geminiMaxContextTokens,
            subtitleFontSize: state.subtitleFontSize,
            showOriginalText: state.showOriginalText,
            deepgramEndpointingMs: profile.deepgramEndpointingMs,
            deepgramUtteranceEndMs: profile.deepgramUtteranceEndMs,
            deepgramMaxBufferChars: profile.deepgramMaxBufferChars,
            profiles: state.profiles,
            selectedProfileId: state.selectedProfileId,
            translationContext: profile.translationContext,
            deepgramKeyterms: profile.keyterms,
            sourceLanguage: profile.sourceLanguage,
            targetLanguage: profile.targetLanguage
        )
    }

    /// 設定 bridge 和 audioService 的回呼
    private func setupBridgeCallbacks(bridge: PythonBridgeService, state: AppState) {
        // Audio 錯誤回呼
        audioService.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleCaptureError(error, source: .audio)
            }
        }

        // Bridge 錯誤回呼
        bridge.onError = { [weak self] message in
            Task { @MainActor in
                let error = self?.makePythonBridgeError(message)
                    ?? NSError(domain: "PythonBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
                self?.handleCaptureError(error, source: .python)
            }
        }

        // 轉錄回呼
        bridge.onTranscript = { [weak state] id, text in
            print("[MenuBarController] onTranscript callback received: id=\(id), text=\(text)")
            Task { @MainActor in
                state?.addTranscript(id: id, text: text)
            }
        }

        // 字幕回呼
        bridge.onSubtitle = { [weak state] subtitle in
            print("[MenuBarController] onSubtitle callback received: id=\(subtitle.id), translation=\(subtitle.translatedText ?? "nil")")
            Task { @MainActor in
                state?.updateTranslation(id: subtitle.id, translation: subtitle.translatedText ?? "")
            }
        }

        // Interim 回呼
        bridge.onInterim = { [weak state] text in
            Task { @MainActor in
                state?.updateInterim(text)
            }
        }

        // 翻譯修正回呼
        bridge.onTranslationUpdate = { [weak state] id, translation in
            print("[MenuBarController] onTranslationUpdate callback received: id=\(id), translation=\(translation)")
            Task { @MainActor in
                state?.updateTranslation(id: id, translation: translation, wasRevised: true)
            }
        }

        // Streaming 翻譯回呼
        bridge.onTranslationStreaming = { [weak state] id, partial in
            print("[MenuBarController] Translation streaming - id: \(id), \(partial.count) chars")
            Task { @MainActor in
                state?.updateStreamingTranslation(id: id, partial: partial)
            }
        }

        // 狀態變更回呼
        bridge.onStatusChange = { status in
            print("[MenuBarController] Python status: \(status)")
        }
    }

    /// 設定音訊資料回呼（必須在 bridge.start() 之後呼叫）
    private func setupAudioDataCallback(bridge: PythonBridgeService) {
        audioService.onAudioData = { [weak bridge] data in
            bridge?.sendAudio(data)
        }
    }

    /// 清除所有回呼
    private func clearCallbacks(bridge: PythonBridgeService) {
        audioService.onAudioData = nil
        audioService.onError = nil
        bridge.onTranscript = nil
        bridge.onSubtitle = nil
        bridge.onInterim = nil
        bridge.onTranslationUpdate = nil
        bridge.onTranslationStreaming = nil
        bridge.onError = nil
        bridge.onStatusChange = nil
    }

    private func startCapture() async {
        print("[MenuBarController] startCapture called")

        // 清空舊的 Session（開始新 Session）
        appState.clearSession()

        // 取消任何正在進行的淡出動畫
        subtitleWindowController.cancelFadeOutIfNeeded()
        print("[MenuBarController] pythonBridge is \(pythonBridge == nil ? "nil" : "available")")

        guard let bridge = pythonBridge else {
            print("[MenuBarController] ERROR: Python Bridge is nil!")
            appState.status = .error
            appState.errorMessage = "Python Bridge 未初始化"
            return
        }
        print("[MenuBarController] Python Bridge found, starting...")

        let state = appState
        if !state.isRecovering {
            state.statusMessage = nil
        }

        do {
            // 1. 建構配置
            let config = buildConfiguration(from: state)

            // 2. 設定回呼
            setupBridgeCallbacks(bridge: bridge, state: state)

            // 3. 啟動 bridge
            try await bridge.start(config: config)

            // 4. 設定音訊資料回呼（必須在 bridge.start() 之後）
            setupAudioDataCallback(bridge: bridge)

            // 5. 啟動音訊擷取
            do {
                try await audioService.startCapture()
            } catch {
                bridge.stop()
                throw error
            }

            // 6. 更新狀態
            state.isCapturing = true
            state.captureStartTime = Date()
            state.status = .capturing

        } catch {
            // 錯誤處理：清除所有回呼
            clearCallbacks(bridge: bridge)

            state.status = .error
            state.errorMessage = error.localizedDescription
            state.clearInterim()
        }
    }

    private func stopCapture() async {
        await audioService.stopCapture()
        pythonBridge?.stop()
        subtitleWindowController.hide()

        // 清除所有回呼
        if let bridge = pythonBridge {
            clearCallbacks(bridge: bridge)
        }

        appState.archiveCurrentSessionIfNeeded()
        appState.isCapturing = false
        // 保留 captureStartTime 給匯出功能使用
        appState.status = .idle
        appState.currentSubtitle = nil
        appState.clearInterim()
        // 不再延遲清空字幕歷史（sessionSubtitles 會保留完整內容）
    }
}

@MainActor
final class StatusMenuItemView: NSView {
    private let dotView = NSView()
    private let textField = NSTextField(labelWithString: "")
    private let stackView: NSStackView

    override init(frame frameRect: NSRect) {
        stackView = NSStackView()
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        stackView = NSStackView()
        super.init(coder: coder)
        setupView()
    }

    override var allowsVibrancy: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 22) }

    func update(text: String, color: NSColor) {
        textField.stringValue = text
        dotView.layer?.backgroundColor = color.cgColor
    }

    private func setupView() {
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.layer?.masksToBounds = true
        dotView.translatesAutoresizingMaskIntoConstraints = false

        textField.font = NSFont.menuFont(ofSize: 0)
        textField.textColor = .labelColor
        textField.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        stackView.addArrangedSubview(dotView)
        stackView.addArrangedSubview(textField)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)

        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),

            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func show() {
        if window == nil {
            createWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func createWindow() {
        let rootView = SettingsView().environmentObject(appState)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "設定"
        window.center()
        window.identifier = NSUserInterfaceItemIdentifier("AutoSubSettingsWindow")
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 500, height: 560))
        window.contentMinSize = NSSize(width: 500, height: 560)
        window.contentMaxSize = NSSize(width: 500, height: 560)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

@MainActor
final class AppLifecycleController {
    private let appState: AppState
    private let subtitleWindowController: SubtitleWindowController
    private let toggleCaptureHandler: () -> Void
    private var isSubtitleVisible = true
    private var hasInitialized = false
    private var cancellables = Set<AnyCancellable>()

    init(
        appState: AppState,
        subtitleWindowController: SubtitleWindowController,
        toggleCaptureHandler: @escaping () -> Void
    ) {
        self.appState = appState
        self.subtitleWindowController = subtitleWindowController
        self.toggleCaptureHandler = toggleCaptureHandler
    }

    func start() {
        guard !hasInitialized else { return }
        hasInitialized = true

        loadConfiguration()
        subtitleWindowController.configure(appState: appState)
        setupKeyboardShortcuts()
        setupSubtitleObserver()
        setupCaptureStateObserver()
        setupSubtitleRenderObserver()
        setupLockStateObserver()

        print("[AppLifecycle] Initialization completed")
    }

    private func loadConfiguration() {
        let config = ConfigurationService.shared.loadConfiguration()
        appState.deepgramApiKey = config.deepgramApiKey
        appState.geminiApiKey = config.geminiApiKey
        appState.geminiModel = config.geminiModel
        appState.geminiMaxContextTokens = config.geminiMaxContextTokens
        appState.subtitleFontSize = config.subtitleFontSize
        appState.subtitleWindowWidth = config.subtitleWindowWidth
        appState.subtitleWindowHeight = config.subtitleWindowHeight
        appState.subtitleWindowOpacity = config.subtitleWindowOpacity
        appState.subtitleHistoryLimit = config.subtitleHistoryLimit
        appState.subtitleAutoOpacityByCount = config.subtitleAutoOpacityByCount
        appState.showOriginalText = config.showOriginalText
        appState.subtitleTextOutlineEnabled = config.subtitleTextOutlineEnabled
        appState.applyProfiles(config.profiles, selectedProfileId: config.selectedProfileId)
    }

    private func setupKeyboardShortcuts() {
        ShortcutManager.shared.register()

        NotificationCenter.default.addObserver(
            forName: .toggleCapture,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.toggleCaptureHandler()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .toggleSubtitle,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSubtitleVisible.toggle()
                if self.isSubtitleVisible {
                    self.updateSubtitleWindow()
                } else {
                    self.subtitleWindowController.hide()
                }
            }
        }
    }

    private func setupSubtitleObserver() {
        print("[AppLifecycle] Setting up subtitle observer...")
        appState.$currentSubtitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subtitle in
                guard let self else { return }
                print("[AppLifecycle] Subtitle observer triggered, subtitle: \(subtitle?.translatedText ?? "nil"), isCapturing: \(self.appState.isCapturing)")
                if subtitle != nil && self.appState.isCapturing {
                    self.updateSubtitleWindow()
                }
            }
            .store(in: &cancellables)
    }

    private func setupCaptureStateObserver() {
        appState.$isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCapturing in
                guard let self else { return }
                if isCapturing && self.isSubtitleVisible {
                    self.updateSubtitleWindow()
                }
            }
            .store(in: &cancellables)
    }

    private func setupSubtitleRenderObserver() {
        appState.$subtitleWindowWidth
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.subtitleWindowController.applyRenderSettings()
            }
            .store(in: &cancellables)

        appState.$subtitleWindowHeight
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.subtitleWindowController.applyRenderSettings()
            }
            .store(in: &cancellables)
    }

    private func setupLockStateObserver() {
        NotificationCenter.default.addObserver(
            forName: .subtitleLockStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.subtitleWindowController.updateMouseEventHandling()
            }
        }
    }

    private func updateSubtitleWindow() {
        let overlay = SubtitleOverlay()
            .environmentObject(appState)
        subtitleWindowController.show(content: overlay)
    }
}
