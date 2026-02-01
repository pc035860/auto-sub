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

    /// 初始化標記（確保只執行一次）
    @State private var hasInitialized = false

    var body: some Scene {
        // Menu Bar App
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(audioService)
                .environment(\.pythonBridge, pythonBridge)
                .task {
                    await performInitializationOnce()
                }
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
        // 只初始化 PythonBridgeService（不需要存取 StateObject）
        do {
            _pythonBridge = State(initialValue: try PythonBridgeService())
        } catch {
            _pythonBridgeError = State(initialValue: error)
            print("[AutoSubApp] Failed to initialize PythonBridgeService: \(error)")
        }
    }

    /// 執行一次性初始化（在 SwiftUI lifecycle 中呼叫）
    @MainActor
    private func performInitializationOnce() async {
        guard !hasInitialized else { return }
        hasInitialized = true

        // 1. 載入設定
        loadConfiguration()

        // 2. 註冊全域快捷鍵
        setupKeyboardShortcuts()

        // 3. 監聽字幕變化
        setupSubtitleObserver()

        print("[AutoSubApp] Initialization completed")
    }

    /// 載入設定到 AppState
    @MainActor
    private func loadConfiguration() {
        let config = ConfigurationService.shared.loadConfiguration()
        appState.deepgramApiKey = config.deepgramApiKey
        appState.geminiApiKey = config.geminiApiKey
        appState.sourceLanguage = config.sourceLanguage
        appState.targetLanguage = config.targetLanguage
        appState.subtitleFontSize = config.subtitleFontSize
        appState.subtitleDisplayDuration = config.subtitleDisplayDuration
        appState.showOriginalText = config.showOriginalText
    }

    /// 設定全域快捷鍵
    @MainActor
    private func setupKeyboardShortcuts() {
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

    /// 監聽字幕變化
    @MainActor
    private func setupSubtitleObserver() {
        print("[AutoSubApp] Setting up subtitle observer...")
        // 使用 Combine 監聯 currentSubtitle 變化
        appState.$currentSubtitle
            .receive(on: DispatchQueue.main)
            .sink { [appState, subtitleWindowController] subtitle in
                print("[AutoSubApp] Subtitle observer triggered, subtitle: \(subtitle?.translatedText ?? "nil"), isCapturing: \(appState.isCapturing)")
                if subtitle != nil && appState.isCapturing {
                    print("[AutoSubApp] Showing subtitle window!")
                    let overlay = SubtitleOverlay()
                        .environmentObject(appState)
                    subtitleWindowController.show(content: overlay)
                }
            }
            .store(in: &cancellables)
        print("[AutoSubApp] Subtitle observer setup complete")
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
