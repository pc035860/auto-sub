//
//  SettingsView.swift
//  AutoSub
//
//  設定視窗
//

import SwiftUI
import AppKit

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

            // 字幕渲染設定
            SubtitleRenderSettingsView()
                .tabItem {
                    Label("字幕渲染", systemImage: "rectangle.on.rectangle")
                }
        }
        .frame(width: 450, height: 440)
        .background(SettingsWindowIdentifier())
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
    private let contextTokenRange: ClosedRange<Int> = 10_000...100_000

    private var contextTokenBinding: Binding<Double> {
        Binding(
            get: { Double(appState.geminiMaxContextTokens) },
            set: { newValue in
                appState.geminiMaxContextTokens = Int(newValue)
            }
        )
    }

    var body: some View {
        Form {
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

                HStack {
                    Text("自動壓縮上限")
                    Spacer()
                    Text("\(appState.geminiMaxContextTokens)")
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: contextTokenBinding,
                    in: Double(contextTokenRange.lowerBound)...Double(contextTokenRange.upperBound),
                    step: 1_000
                )
                .onChangeCompat(of: appState.geminiMaxContextTokens) {
                    appState.saveConfiguration()
                }
            } header: {
                Text("Gemini 設定")
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

// MARK: - 字幕渲染設定

struct SubtitleRenderSettingsView: View {
    @EnvironmentObject var appState: AppState

    private var screenWidth: CGFloat {
        NSScreen.main?.visibleFrame.width ?? 1200
    }

    private var screenHeight: CGFloat {
        NSScreen.main?.visibleFrame.height ?? 800
    }

    private var widthRange: ClosedRange<CGFloat> {
        let minWidth: CGFloat = 400
        let maxWidth = max(minWidth, screenWidth * 0.95)
        return minWidth...maxWidth
    }

    private var heightRange: ClosedRange<CGFloat> {
        let minHeight: CGFloat = 120
        let maxHeight = max(minHeight, screenHeight * 0.6)
        return minHeight...maxHeight
    }

    private var widthBinding: Binding<CGFloat> {
        Binding(
            get: {
                let defaultWidth = screenWidth * 0.8
                return appState.subtitleWindowWidth > 0 ? appState.subtitleWindowWidth : defaultWidth
            },
            set: { newValue in
                appState.subtitleWindowWidth = newValue
            }
        )
    }

    private var heightBinding: Binding<CGFloat> {
        Binding(
            get: {
                let defaultHeight = screenHeight * 0.2
                return appState.subtitleWindowHeight > 0 ? appState.subtitleWindowHeight : defaultHeight
            },
            set: { newValue in
                appState.subtitleWindowHeight = newValue
            }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("視窗寬度")
                    Spacer()
                    Text("\(Int(widthBinding.wrappedValue)) px")
                        .foregroundColor(.secondary)
                }
                Slider(value: widthBinding, in: widthRange, step: 20)
                    .onChangeCompat(of: appState.subtitleWindowWidth) {
                        appState.saveConfiguration()
                    }

                HStack {
                    Text("視窗高度")
                    Spacer()
                    Text("\(Int(heightBinding.wrappedValue)) px")
                        .foregroundColor(.secondary)
                }
                Slider(value: heightBinding, in: heightRange, step: 10)
                    .onChangeCompat(of: appState.subtitleWindowHeight) {
                        appState.saveConfiguration()
                    }

                HStack {
                    Text("視窗透明度")
                    Spacer()
                    Text(String(format: "%.2f", appState.subtitleWindowOpacity))
                        .foregroundColor(.secondary)
                }
                Slider(value: $appState.subtitleWindowOpacity, in: 0...1, step: 0.05)
                    .onChangeCompat(of: appState.subtitleWindowOpacity) {
                        appState.saveConfiguration()
                    }
            } header: {
                Text("視窗")
            }

            Section {
                Stepper("歷史列數：\(appState.subtitleHistoryLimit)", value: $appState.subtitleHistoryLimit, in: 1...6)
                    .onChangeCompat(of: appState.subtitleHistoryLimit) {
                        appState.saveConfiguration()
                    }

                Toggle("隨列數調整文字透明度", isOn: $appState.subtitleAutoOpacityByCount)
                    .onChangeCompat(of: appState.subtitleAutoOpacityByCount) {
                        appState.saveConfiguration()
                    }
            } header: {
                Text("歷史文字")
            } footer: {
                Text("最小透明度 0.30")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Settings Window Identifier

private struct SettingsWindowIdentifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.identifier = NSUserInterfaceItemIdentifier("AutoSubSettingsWindow")
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.identifier = NSUserInterfaceItemIdentifier("AutoSubSettingsWindow")
        }
    }
}
