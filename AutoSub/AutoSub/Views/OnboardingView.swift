//
//  OnboardingView.swift
//  AutoSub
//
//  首次使用引導視窗
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 20) {
            // 標題
            Text("歡迎使用 AutoSub")
                .font(.largeTitle)
                .fontWeight(.bold)

            // 步驟內容
            TabView(selection: $currentStep) {
                WelcomeStepView()
                    .tag(0)

                PermissionStepView()
                    .tag(1)

                APIKeyStepView()
                    .tag(2)
            }
            .tabViewStyle(.automatic)

            // 導航按鈕
            HStack {
                if currentStep > 0 {
                    Button("上一步") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                }

                Spacer()

                if currentStep < 2 {
                    Button("下一步") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("完成") {
                        appState.isConfigured = true
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.deepgramApiKey.isEmpty || appState.geminiApiKey.isEmpty)
                }
            }
        }
        .padding(40)
        .frame(width: 500, height: 400)
    }
}

// MARK: - 步驟視圖

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("即時字幕翻譯")
                .font(.title2)

            Text("AutoSub 可以擷取系統音訊，自動辨識日文並翻譯成繁體中文")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct PermissionStepView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("螢幕錄製權限")
                .font(.title2)

            Text("AutoSub 需要螢幕錄製權限才能擷取系統音訊。\n請在系統偏好設定中授權。")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("開啟系統偏好設定") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding()
    }
}

struct APIKeyStepView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("設定 API Keys")
                .font(.title2)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Deepgram API Key")
                        .font(.caption)
                    SecureField("dg_...", text: $appState.deepgramApiKey)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("Gemini API Key")
                        .font(.caption)
                    SecureField("AIza...", text: $appState.geminiApiKey)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .frame(maxWidth: 300)
        }
        .padding()
    }
}
