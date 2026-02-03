//
//  AutoSubApp.swift
//  AutoSub
//
//  即時字幕翻譯 macOS Menu Bar App
//

import SwiftUI

@main
struct AutoSubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var appState: AppState

    /// PythonBridgeService 初始化（處理可能的錯誤）
    @State private var pythonBridge: PythonBridgeService?

    var body: some Scene {
        // 設定視窗
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    @MainActor
    init() {
        let appState = AppState()
        _appState = StateObject(wrappedValue: appState)

        let audioService = AudioCaptureService()
        let subtitleWindowController = SubtitleWindowController()

        // 只初始化 PythonBridgeService（不需要存取 StateObject）
        let bridge: PythonBridgeService?
        do {
            let instance = try PythonBridgeService()
            bridge = instance
            _pythonBridge = State(initialValue: instance)
        } catch {
            bridge = nil
            print("[AutoSubApp] Failed to initialize PythonBridgeService: \(error)")
        }

        appDelegate.configure(
            appState: appState,
            audioService: audioService,
            pythonBridge: bridge,
            subtitleWindowController: subtitleWindowController
        )
    }
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

// MARK: - Environment Key for SubtitleWindowController

private struct SubtitleWindowControllerKey: EnvironmentKey {
    static let defaultValue: SubtitleWindowController? = nil
}

extension EnvironmentValues {
    var subtitleWindowController: SubtitleWindowController? {
        get { self[SubtitleWindowControllerKey.self] }
        set { self[SubtitleWindowControllerKey.self] = newValue }
    }
}
