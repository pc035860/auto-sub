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
    private let geminiModels: [(id: String, label: String)] = [
        ("gemini-2.5-flash-lite-preview-09-2025", "2.5 flash-lite"),
        ("gemini-2.5-flash-preview-09-2025", "2.5 flash"),
        ("gemini-3-flash-preview", "3 flash")
    ]

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
            .disabled(appState.isCapturing)

            Section {
                Picker("Gemini 模型", selection: $appState.geminiModel) {
                    ForEach(geminiModels, id: \.id) { model in
                        Text(model.label).tag(model.id)
                    }
                }
                .onChangeCompat(of: appState.geminiModel) {
                    appState.saveConfiguration()
                }
            } header: {
                Text("Gemini 設定")
            }
            .disabled(appState.isCapturing)

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
            .disabled(appState.isCapturing)
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
        }
        .formStyle(.grouped)
        .padding()
    }
}
