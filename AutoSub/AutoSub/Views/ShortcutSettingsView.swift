//
//  ShortcutSettingsView.swift
//  AutoSub
//
//  快捷鍵設定
//

import SwiftUI
import KeyboardShortcuts

struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("開始/停止擷取", name: .toggleCapture)
                KeyboardShortcuts.Recorder("顯示/隱藏字幕", name: .toggleSubtitle)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("未設定則不啟用快捷鍵。")
                    Text("按 Delete/Backspace 清除已綁定的快捷鍵。")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
