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
                        saveConfiguration()
                    }
                SecureField("Gemini API Key", text: $appState.geminiApiKey)
                    .onChangeCompat(of: appState.geminiApiKey) {
                        saveConfiguration()
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
                    saveConfiguration()
                }

                Picker("翻譯語言", selection: $appState.targetLanguage) {
                    Text("繁體中文").tag("zh-TW")
                    Text("簡體中文").tag("zh-CN")
                    Text("英文").tag("en")
                }
                .onChangeCompat(of: appState.targetLanguage) {
                    saveConfiguration()
                }
            } header: {
                Text("語言設定")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func saveConfiguration() {
        let config = Configuration(
            deepgramApiKey: appState.deepgramApiKey,
            geminiApiKey: appState.geminiApiKey,
            sourceLanguage: appState.sourceLanguage,
            targetLanguage: appState.targetLanguage,
            subtitleFontSize: appState.subtitleFontSize,
            subtitleDisplayDuration: appState.subtitleDisplayDuration,
            showOriginalText: appState.showOriginalText
        )
        try? ConfigurationService.shared.saveConfiguration(config)
    }
}

// MARK: - onChange Compatibility Extension

extension View {
    /// macOS 13/14 相容的 onChange
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, _ in
                action()
            }
        } else {
            self.onChange(of: value) { _ in
                action()
            }
        }
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
                .onChangeCompat(of: appState.subtitleFontSize) {
                    saveConfiguration()
                }

                Toggle("顯示原文", isOn: $appState.showOriginalText)
                    .onChangeCompat(of: appState.showOriginalText) {
                        saveConfiguration()
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
                    saveConfiguration()
                }
            } header: {
                Text("時間設定")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func saveConfiguration() {
        let config = Configuration(
            deepgramApiKey: appState.deepgramApiKey,
            geminiApiKey: appState.geminiApiKey,
            sourceLanguage: appState.sourceLanguage,
            targetLanguage: appState.targetLanguage,
            subtitleFontSize: appState.subtitleFontSize,
            subtitleDisplayDuration: appState.subtitleDisplayDuration,
            showOriginalText: appState.showOriginalText
        )
        try? ConfigurationService.shared.saveConfiguration(config)
    }
}
