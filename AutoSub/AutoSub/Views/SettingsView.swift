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
        // 設定已在 AutoSubApp 啟動時載入，不需要重複載入
    }
}

// MARK: - API 設定

struct APISettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                SecureField("Deepgram API Key", text: $appState.deepgramApiKey)
                    .onChangeCompat(of: appState.deepgramApiKey) {
                        appState.saveConfiguration()
                    }
                SecureField("Gemini API Key", text: $appState.geminiApiKey)
                    .onChangeCompat(of: appState.geminiApiKey) {
                        appState.saveConfiguration()
                    }
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
                .onChangeCompat(of: appState.sourceLanguage) {
                    appState.saveConfiguration()
                }

                Picker("翻譯語言", selection: $appState.targetLanguage) {
                    Text("繁體中文").tag("zh-TW")
                    Text("簡體中文").tag("zh-CN")
                    Text("英文").tag("en")
                }
                .onChangeCompat(of: appState.targetLanguage) {
                    appState.saveConfiguration()
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
// 注意：onChangeCompat 擴展已移至 SubtitleOverlay.swift

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
                .onChangeCompat(of: appState.subtitleFontSize) {
                    appState.saveConfiguration()
                }

                Toggle("顯示原文", isOn: $appState.showOriginalText)
                    .onChangeCompat(of: appState.showOriginalText) {
                        appState.saveConfiguration()
                    }
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
                .onChangeCompat(of: appState.subtitleDisplayDuration) {
                    appState.saveConfiguration()
                }
            } header: {
                Text("時間設定")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
