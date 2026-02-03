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
        if menuBarController == nil {
            menuBarController = MenuBarController(
                appState: appState,
                audioService: audioService,
                pythonBridge: pythonBridge,
                subtitleWindowController: subtitleWindowController
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
final class MenuBarController: NSObject {
    private let appState: AppState
    private let audioService: AudioCaptureService
    private let pythonBridge: PythonBridgeService?
    private let subtitleWindowController: SubtitleWindowController

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    private let statusMenuItem = NSMenuItem()
    private let profileMenuItem = NSMenuItem()
    private let captureMenuItem = NSMenuItem()
    private let settingsMenuItem = NSMenuItem()
    private let subtitleLockMenuItem = NSMenuItem()
    private let resetSubtitleMenuItem = NSMenuItem()
    private let quitMenuItem = NSMenuItem()

    private let statusRowView = StatusMenuItemView()
    private let profileSubmenu = NSMenu()
    private let settingsWindowController: SettingsWindowController

    init(
        appState: AppState,
        audioService: AudioCaptureService,
        pythonBridge: PythonBridgeService?,
        subtitleWindowController: SubtitleWindowController
    ) {
        self.appState = appState
        self.audioService = audioService
        self.pythonBridge = pythonBridge
        self.subtitleWindowController = subtitleWindowController
        self.settingsWindowController = SettingsWindowController(appState: appState)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
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

        menu.addItem(.separator())

        settingsMenuItem.title = "設定..."
        settingsMenuItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsMenuItem.target = self
        settingsMenuItem.action = #selector(openSettings(_:))
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

        statusItem.menu = menu
    }

    private func bindAppState() {
        appState.$status
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
    }

    private func refreshAll() {
        refreshStatus()
        refreshProfileMenu()
        refreshCaptureItem()
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
        captureMenuItem.title = appState.isCapturing ? "停止擷取" : "開始擷取"
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

    @objc private func openSettings(_ sender: Any?) {
        settingsWindowController.show()
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

    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private var statusText: String {
        switch appState.status {
        case .idle: return "待機中"
        case .capturing: return "擷取中"
        case .warning: return "警告"
        case .error: return appState.errorMessage ?? "錯誤"
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

    private func startCapture() async {
        print("[MenuBarController] startCapture called")
        print("[MenuBarController] pythonBridge is \(pythonBridge == nil ? "nil" : "available")")

        guard let bridge = pythonBridge else {
            print("[MenuBarController] ERROR: Python Bridge is nil!")
            appState.status = .error
            appState.errorMessage = "Python Bridge 未初始化"
            return
        }
        print("[MenuBarController] Python Bridge found, starting...")

        let state = appState

        do {
            let profile = state.currentProfile
            let config = Configuration(
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

            audioService.onError = { [weak state] error in
                Task { @MainActor in
                    state?.status = .error
                    state?.errorMessage = error.localizedDescription
                }
            }
            bridge.onError = { [weak state] message in
                Task { @MainActor in
                    state?.status = .warning
                    state?.errorMessage = message
                }
            }

            bridge.onTranscript = { [weak state] id, text in
                print("[MenuBarController] onTranscript callback received: id=\(id), text=\(text)")
                Task { @MainActor in
                    state?.addTranscript(id: id, text: text)
                }
            }
            bridge.onSubtitle = { [weak state] subtitle in
                print("[MenuBarController] onSubtitle callback received: id=\(subtitle.id), translation=\(subtitle.translatedText ?? "nil")")
                Task { @MainActor in
                    state?.updateTranslation(id: subtitle.id, translation: subtitle.translatedText ?? "")
                }
            }
            bridge.onInterim = { [weak state] text in
                Task { @MainActor in
                    state?.updateInterim(text)
                }
            }
            bridge.onTranslationUpdate = { [weak state] id, translation in
                print("[MenuBarController] onTranslationUpdate callback received: id=\(id), translation=\(translation)")
                Task { @MainActor in
                    state?.updateTranslation(id: id, translation: translation, wasRevised: true)
                }
            }
            bridge.onStatusChange = { status in
                print("[MenuBarController] Python status: \(status)")
            }

            try await bridge.start(config: config)

            audioService.onAudioData = { [weak bridge] data in
                bridge?.sendAudio(data)
            }

            do {
                try await audioService.startCapture()
            } catch {
                bridge.stop()
                throw error
            }

            state.isCapturing = true
            state.status = .capturing

        } catch {
            audioService.onAudioData = nil
            audioService.onError = nil
            bridge.onTranscript = nil
            bridge.onSubtitle = nil
            bridge.onInterim = nil
            bridge.onTranslationUpdate = nil
            bridge.onError = nil
            bridge.onStatusChange = nil

            state.status = .error
            state.errorMessage = error.localizedDescription
            state.currentInterim = nil
        }
    }

    private func stopCapture() async {
        await audioService.stopCapture()
        pythonBridge?.stop()
        subtitleWindowController.hide()

        audioService.onAudioData = nil
        audioService.onError = nil
        pythonBridge?.onTranscript = nil
        pythonBridge?.onSubtitle = nil
        pythonBridge?.onInterim = nil
        pythonBridge?.onTranslationUpdate = nil
        pythonBridge?.onError = nil
        pythonBridge?.onStatusChange = nil

        appState.isCapturing = false
        appState.status = .idle
        appState.currentSubtitle = nil
        appState.currentInterim = nil
        appState.subtitleHistory.removeAll()
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
final class SettingsWindowController {
    private let appState: AppState
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
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
        let hostingView = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "設定"
        window.center()
        window.identifier = NSUserInterfaceItemIdentifier("AutoSubSettingsWindow")
        window.contentView = hostingView
        self.window = window
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
        KeyboardShortcuts.shared.register()

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
                self?.subtitleWindowController.applyRenderSettings()
            }
            .store(in: &cancellables)

        appState.$subtitleWindowHeight
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.subtitleWindowController.applyRenderSettings()
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
