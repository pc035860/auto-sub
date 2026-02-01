//
//  AutoSubApp.swift
//  AutoSub
//
//  即時字幕翻譯 macOS Menu Bar App
//

import SwiftUI
import Combine

@main
struct AutoSubApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var audioService = AudioCaptureService()

    /// PythonBridgeService 初始化（處理可能的錯誤）
    @State private var pythonBridge: PythonBridgeService?
    @State private var pythonBridgeError: Error?

    /// 字幕視窗控制器
    @State private var subtitleWindowController = SubtitleWindowController()

    /// 字幕是否顯示
    @State private var isSubtitleVisible = true

    var body: some Scene {
        // Menu Bar App
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(audioService)
                .environment(\.pythonBridge, pythonBridge)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        // 設定視窗
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    private var menuBarIcon: String {
        switch appState.status {
        case .idle: return "captions.bubble"
        case .capturing: return "captions.bubble.fill"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    init() {
        // 1. 初始化 PythonBridgeService（可能失敗）
        do {
            _pythonBridge = State(initialValue: try PythonBridgeService())
        } catch {
            _pythonBridgeError = State(initialValue: error)
            print("[AutoSubApp] Failed to initialize PythonBridgeService: \(error)")
        }

        // 2. 載入設定
        loadConfiguration()

        // 3. 註冊全域快捷鍵
        setupKeyboardShortcuts()

        // 4. 監聽字幕變化
        setupSubtitleObserver()
    }

    /// 載入設定到 AppState
    private func loadConfiguration() {
        Task { @MainActor in
            let config = ConfigurationService.shared.loadConfiguration()
            appState.deepgramApiKey = config.deepgramApiKey
            appState.geminiApiKey = config.geminiApiKey
            appState.sourceLanguage = config.sourceLanguage
            appState.targetLanguage = config.targetLanguage
            appState.subtitleFontSize = config.subtitleFontSize
            appState.subtitleDisplayDuration = config.subtitleDisplayDuration
            appState.showOriginalText = config.showOriginalText
        }
    }

    /// 設定全域快捷鍵
    private func setupKeyboardShortcuts() {
        Task { @MainActor in
            KeyboardShortcuts.shared.register()

            // 監聽快捷鍵事件
            NotificationCenter.default.addObserver(
                forName: .toggleCapture,
                object: nil,
                queue: .main
            ) { _ in
                // toggleCapture 由 MenuBarView 處理
            }

            NotificationCenter.default.addObserver(
                forName: .toggleSubtitle,
                object: nil,
                queue: .main
            ) { [self] _ in
                Task { @MainActor in
                    isSubtitleVisible.toggle()
                    if isSubtitleVisible {
                        updateSubtitleWindow()
                    } else {
                        subtitleWindowController.hide()
                    }
                }
            }
        }
    }

    /// 監聯字幕變化
    private func setupSubtitleObserver() {
        Task { @MainActor in
            // 使用 Combine 監聽 currentSubtitle 變化
            // 注意：AutoSubApp 是 struct，使用值語義，不需要 weak self
            appState.$currentSubtitle
                .receive(on: DispatchQueue.main)
                .sink { [appState, subtitleWindowController] subtitle in
                    if subtitle != nil && appState.isCapturing {
                        let overlay = SubtitleOverlay()
                            .environmentObject(appState)
                        subtitleWindowController.show(content: overlay)
                    }
                }
                .store(in: &cancellables)
        }
    }

    /// 更新字幕視窗
    private func updateSubtitleWindow() {
        let overlay = SubtitleOverlay()
            .environmentObject(appState)
        subtitleWindowController.show(content: overlay)
    }

    /// Combine cancellables
    @State private var cancellables = Set<AnyCancellable>()
}

// MARK: - Environment Key for PythonBridge

private struct PythonBridgeKey: EnvironmentKey {
    static let defaultValue: PythonBridgeService? = nil
}

extension EnvironmentValues {
    var pythonBridge: PythonBridgeService? {
        get { self[PythonBridgeKey.self] }
        set { self[PythonBridgeKey.self] = newValue }
    }
}
