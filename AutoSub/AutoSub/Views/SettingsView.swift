//
//  SettingsView.swift
//  AutoSub
//
//  設定視窗
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            // API 設定
            APISettingsView()
                .tabItem {
                    Label("API", systemImage: "key")
                }

            // 字幕設定
            SubtitleSettingsView()
                .tabItem {
                    Label("字幕", systemImage: "captions.bubble")
                }
        }
        .frame(width: 450, height: 300)
        .environmentObject(appState)
    }
}

// MARK: - API 設定

struct APISettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                SecureField("Deepgram API Key", text: $appState.deepgramApiKey)
                SecureField("Gemini API Key", text: $appState.geminiApiKey)
            } header: {
                Text("API Keys")
            } footer: {
                Text("API Keys 會安全儲存在 Keychain 中")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Picker("原文語言", selection: $appState.sourceLanguage) {
                    Text("日文").tag("ja")
                    Text("英文").tag("en")
                    Text("韓文").tag("ko")
                }
            } header: {
                Text("語言設定")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 字幕設定

struct SubtitleSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Slider(value: $appState.subtitleFontSize, in: 16...48, step: 2) {
                    Text("字體大小")
                } minimumValueLabel: {
                    Text("16")
                } maximumValueLabel: {
                    Text("48")
                }

                Toggle("顯示原文", isOn: $appState.showOriginalText)
            } header: {
                Text("顯示設定")
            }

            Section {
                Slider(value: $appState.subtitleDisplayDuration, in: 2...10, step: 0.5) {
                    Text("顯示時間")
                } minimumValueLabel: {
                    Text("2s")
                } maximumValueLabel: {
                    Text("10s")
                }
            } header: {
                Text("時間設定")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
