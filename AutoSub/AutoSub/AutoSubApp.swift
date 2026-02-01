//
//  AutoSubApp.swift
//  AutoSub
//
//  即時字幕翻譯 macOS Menu Bar App
//

import SwiftUI

@main
struct AutoSubApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Menu Bar App
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: menuBarIcon)
        }

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
}
