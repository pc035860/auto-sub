//
//  MenuBarView.swift
//  AutoSub
//
//  Menu Bar 下拉選單
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var audioService: AudioCaptureService
    @Environment(\.pythonBridge) var pythonBridge: PythonBridgeService?
    @Environment(\.subtitleWindowController) var subtitleWindowController: SubtitleWindowController?

    var body: some View {
        Group {
            statusItem
            Divider()
            profileMenu
            captureItem
            Divider()
            settingsItem
            subtitleLockItem
            resetSubtitleItem
            Divider()
            quitItem
        }
    }

    private var statusItem: some View {
        Button(action: {}) {
            Label {
                Text(statusText)
            } icon: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(statusColor)
            }
        }
        .disabled(true)
    }

    private var profileMenu: some View {
        Menu {
            ForEach(appState.profiles) { profile in
                Button {
                    appState.selectProfile(id: profile.id)
                } label: {
                    if profile.id == appState.selectedProfileId {
                        Label(profile.displayName, systemImage: "checkmark")
                    } else {
                        Text(profile.displayName)
                    }
                }
            }
        } label: {
            Label("Profile：\(appState.currentProfile.displayName)", systemImage: "person.text.rectangle")
        }
        .disabled(appState.isCapturing)
    }

    private var captureItem: some View {
        Button(action: toggleCapture) {
            Label(
                appState.isCapturing ? "停止擷取" : "開始擷取",
                systemImage: appState.isCapturing ? "stop.fill" : "play.fill"
            )
        }
        .disabled(!appState.isReady)
    }

    @ViewBuilder
    private var settingsItem: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Label("設定...", systemImage: "gear")
            }
            .simultaneousGesture(TapGesture().onEnded {
                bringSettingsToFront()
            })
        } else {
            Button {
                openSettings()
            } label: {
                Label("設定...", systemImage: "gear")
            }
        }
    }

    private var subtitleLockItem: some View {
        Toggle(isOn: $appState.isSubtitleLocked) {
            Label("鎖定字幕位置", systemImage: appState.isSubtitleLocked ? "lock.fill" : "lock.open")
        }
        .onChangeCompat(of: appState.isSubtitleLocked) {
            subtitleWindowController?.updateMouseEventHandling()
            appState.saveSubtitlePosition()
        }
    }

    private var resetSubtitleItem: some View {
        Button {
            appState.resetSubtitlePosition()
            subtitleWindowController?.resetPosition()
        } label: {
            Label("重設字幕位置", systemImage: "arrow.counterclockwise")
        }
    }

    private var quitItem: some View {
        Button("結束 Auto-Sub") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle: return .primary
        case .capturing: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.status {
        case .idle: return "待機中"
        case .capturing: return "擷取中"
        case .warning: return "警告"
        case .error: return appState.errorMessage ?? "錯誤"
        }
    }

    private func toggleCapture() {
        Task { @MainActor in
            if appState.isCapturing {
                await stopCapture()
            } else {
                await startCapture()
            }
        }
    }

    private func openSettings() {
        // 顯示設定視窗後，強制啟用並把視窗帶到前景
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        bringSettingsToFront()
    }

    private func bringSettingsToFront() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let settingsWindow = NSApp.windows.first(where: {
                $0.identifier?.rawValue == "AutoSubSettingsWindow"
            }) {
                settingsWindow.makeKeyAndOrderFront(nil)
                return
            }
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func startCapture() async {
        print("[MenuBarView] startCapture called")
        print("[MenuBarView] pythonBridge is \(pythonBridge == nil ? "nil" : "available")")

        guard let bridge = pythonBridge else {
            print("[MenuBarView] ERROR: Python Bridge is nil!")
            appState.status = .error
            appState.errorMessage = "Python Bridge 未初始化"
            return
        }
        print("[MenuBarView] Python Bridge found, starting...")

        // 捕獲 appState 的弱引用避免循環參考
        let state = appState

        do {
            let profile = state.currentProfile

            // 1. 建立設定（使用當前 Profile）
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

            // 2. 先設定錯誤回呼（在啟動前）
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

            // 3. 設定 Python Bridge 回呼
            // 新增：transcript 回呼（顯示原文，翻譯中狀態）
            bridge.onTranscript = { [weak state] id, text in
                print("[MenuBarView] onTranscript callback received: id=\(id), text=\(text)")
                Task { @MainActor in
                    state?.addTranscript(id: id, text: text)
                }
            }
            // 修改：subtitle 回呼（更新翻譯結果）
            bridge.onSubtitle = { [weak state] subtitle in
                print("[MenuBarView] onSubtitle callback received: id=\(subtitle.id), translation=\(subtitle.translatedText ?? "nil")")
                Task { @MainActor in
                    state?.updateTranslation(id: subtitle.id, translation: subtitle.translatedText ?? "")
                }
            }
            // 新增：interim 回呼（正在說的話）
            bridge.onInterim = { [weak state] text in
                Task { @MainActor in
                    state?.updateInterim(text)
                }
            }
            // Phase 2: translation_update 回呼（前句翻譯被修正）
            bridge.onTranslationUpdate = { [weak state] id, translation in
                print("[MenuBarView] onTranslationUpdate callback received: id=\(id), translation=\(translation)")
                Task { @MainActor in
                    // wasRevised = true 表示這是上下文修正
                    state?.updateTranslation(id: id, translation: translation, wasRevised: true)
                }
            }
            bridge.onStatusChange = { status in
                print("[MenuBarView] Python status: \(status)")
            }

            // 4. 啟動 Python Backend
            try await bridge.start(config: config)

            // 5. 設定音訊回呼並開始擷取
            audioService.onAudioData = { [weak bridge] data in
                bridge?.sendAudio(data)
            }

            do {
                try await audioService.startCapture()
            } catch {
                // 音訊擷取失敗，回滾 Python Bridge
                bridge.stop()
                throw error
            }

            // 6. 更新狀態
            state.isCapturing = true
            state.status = .capturing

        } catch {
            // 清理回呼
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
        // 1. 停止音訊擷取
        await audioService.stopCapture()

        // 2. 停止 Python Bridge
        pythonBridge?.stop()

        // 3. 關閉字幕視窗
        subtitleWindowController?.hide()

        // 4. 清理回呼
        audioService.onAudioData = nil
        audioService.onError = nil
        pythonBridge?.onTranscript = nil
        pythonBridge?.onSubtitle = nil
        pythonBridge?.onInterim = nil
        pythonBridge?.onTranslationUpdate = nil
        pythonBridge?.onError = nil
        pythonBridge?.onStatusChange = nil

        // 5. 更新狀態
        appState.isCapturing = false
        appState.status = .idle
        appState.currentSubtitle = nil
        appState.currentInterim = nil
        appState.subtitleHistory.removeAll()
    }
}
