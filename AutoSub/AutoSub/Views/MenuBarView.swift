//
//  MenuBarView.swift
//  AutoSub
//
//  Menu Bar 下拉選單
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            // 狀態顯示
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
            }
            .padding(.bottom, 8)

            Divider()

            // 開始/停止按鈕
            Button(action: toggleCapture) {
                Label(
                    appState.isCapturing ? "停止字幕" : "開始字幕",
                    systemImage: appState.isCapturing ? "stop.circle" : "play.circle"
                )
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            // 設定
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Label("設定...", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            } else {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("設定...", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            Divider()

            // 結束
            Button("結束 AutoSub") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle: return .gray
        case .capturing: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.status {
        case .idle: return "待機中"
        case .capturing: return "擷取中"
        case .warning: return "連線不穩"
        case .error: return "錯誤"
        }
    }

    private func toggleCapture() {
        // TODO: Phase 3 實作
        appState.isCapturing.toggle()
        appState.status = appState.isCapturing ? .capturing : .idle
    }
}
