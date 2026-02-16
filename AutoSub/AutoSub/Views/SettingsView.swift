//
//  SettingsView.swift
//  AutoSub
//
//  設定視窗
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            // Profile 設定
            ProfileSettingsView()
                .tabItem {
                    Label("Profile", systemImage: "person.text.rectangle")
                }

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

            // 快捷鍵設定
            ShortcutSettingsView()
                .tabItem {
                    Label("快捷鍵", systemImage: "keyboard")
                }
        }
        .frame(width: 500, height: 560)
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

// MARK: - Profile 設定

struct ProfileSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var nameDraft: String = ""
    @State private var translationContextDraft: String = ""
    @State private var keytermsDraft: String = ""
    @State private var lastSelectedProfileId: UUID?

    private var selectedProfileBinding: Binding<UUID> {
        Binding(
            get: { appState.selectedProfileId },
            set: { newValue in
                appState.selectProfile(id: newValue)
            }
        )
    }

    private var sourceLanguageBinding: Binding<String> {
        Binding(
            get: { appState.currentProfile.sourceLanguage },
            set: { newValue in
                appState.updateCurrentProfile { $0.sourceLanguage = newValue }
            }
        )
    }

    private var targetLanguageBinding: Binding<String> {
        Binding(
            get: { appState.currentProfile.targetLanguage },
            set: { newValue in
                appState.updateCurrentProfile { $0.targetLanguage = newValue }
            }
        )
    }

    private var endpointingBinding: Binding<Int> {
        Binding(
            get: { appState.currentProfile.deepgramEndpointingMs },
            set: { newValue in
                appState.updateCurrentProfile { $0.deepgramEndpointingMs = newValue }
            }
        )
    }

    private var utteranceEndBinding: Binding<Int> {
        Binding(
            get: { appState.currentProfile.deepgramUtteranceEndMs },
            set: { newValue in
                appState.updateCurrentProfile { $0.deepgramUtteranceEndMs = newValue }
            }
        )
    }

    private var maxBufferCharsBinding: Binding<Int> {
        Binding(
            get: { appState.currentProfile.deepgramMaxBufferChars },
            set: { newValue in
                appState.updateCurrentProfile { $0.deepgramMaxBufferChars = newValue }
            }
        )
    }

    private var keytermsDraftCount: Int {
        keytermsDraft
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private func loadDrafts() {
        let profile = appState.currentProfile
        nameDraft = profile.name
        translationContextDraft = profile.translationContext
        keytermsDraft = profile.keyterms.joined(separator: "\n")
    }

    private func commitName(to profileId: UUID) {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "未命名 Profile" : nameDraft
        if finalName != nameDraft {
            nameDraft = finalName
        }
        appState.updateProfile(id: profileId) { $0.name = finalName }
    }

    private func commitTranslationContext(to profileId: UUID) {
        appState.updateProfile(id: profileId) { $0.translationContext = translationContextDraft }
    }

    private func commitKeyterms(to profileId: UUID) {
        let terms = keytermsDraft
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        appState.updateProfile(id: profileId) { $0.keyterms = terms }
    }

    private func commitDrafts(to profileId: UUID) {
        commitName(to: profileId)
        commitTranslationContext(to: profileId)
        commitKeyterms(to: profileId)
    }

    var body: some View {
        Form {
            Section {
                Picker("目前 Profile", selection: selectedProfileBinding) {
                    ForEach(appState.profiles) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }

                HStack {
                    Button("新增") {
                        appState.addProfile()
                    }
                    .disabled(appState.isCapturing)

                    Button("刪除") {
                        appState.deleteSelectedProfile()
                    }
                    .disabled(appState.isCapturing || appState.profiles.count <= 1)

                    Spacer()

                    Button("匯出") {
                        exportSelectedProfile()
                    }
                    .disabled(appState.isCapturing)

                    Button("匯入") {
                        importProfileFromFile()
                    }
                    .disabled(appState.isCapturing)
                }
            } header: {
                Text("Profile")
            } footer: {
                Text("擷取中無法切換或編輯 Profile")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .disabled(appState.isCapturing)

            Section {
                TextField(
                    "名稱",
                    text: $nameDraft,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            commitDrafts(to: appState.selectedProfileId)
                        }
                    },
                    onCommit: {
                        commitDrafts(to: appState.selectedProfileId)
                    }
                )
            } header: {
                Text("基本資訊")
            }
            .disabled(appState.isCapturing)

            Section {
                Picker("原文語言", selection: sourceLanguageBinding) {
                    Text("日文").tag("ja")
                    Text("英文").tag("en")
                    Text("韓文").tag("ko")
                }

                Picker("翻譯語言", selection: targetLanguageBinding) {
                    Text("繁體中文").tag("zh-TW")
                    Text("簡體中文").tag("zh-CN")
                    Text("英文").tag("en")
                }
            } header: {
                Text("語言設定")
            }
            .disabled(appState.isCapturing)

            Section {
                ProfileTextView(
                    text: $translationContextDraft,
                    isEditable: !appState.isCapturing,
                    onEndEditing: {
                        commitDrafts(to: appState.selectedProfileId)
                    }
                )
                    .frame(minHeight: 180)
            } header: {
                Text("翻譯背景資訊")
            } footer: {
                Text("可輸入人物、節目或領域背景，提升翻譯一致性。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .disabled(appState.isCapturing)

            Section {
                ProfileTextView(
                    text: $keytermsDraft,
                    isEditable: !appState.isCapturing,
                    onEndEditing: {
                        commitDrafts(to: appState.selectedProfileId)
                    }
                )
                    .frame(minHeight: 180)
                HStack {
                    Text("目前：\(keytermsDraftCount) 個")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("建議 20–50 個，總 token 上限 500")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            } header: {
                Text("Deepgram Keyterms（每行一個）")
            }
            .disabled(appState.isCapturing)

            Section {
                Stepper(value: endpointingBinding, in: 10...1000, step: 10) {
                    Text("Endpointing：\(appState.currentProfile.deepgramEndpointingMs) ms")
                }
                Text("越小越快切句，但更容易斷得太碎。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Stepper(value: utteranceEndBinding, in: 1000...5000, step: 100) {
                    Text("Utterance End：\(appState.currentProfile.deepgramUtteranceEndMs) ms")
                }
                Text("最小 1000ms；越大越完整，但延遲更高。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Stepper(value: maxBufferCharsBinding, in: 20...120, step: 5) {
                    Text("Max Buffer：\(appState.currentProfile.deepgramMaxBufferChars) chars")
                }
                Text("累積字數上限，達到就強制送出翻譯。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Deepgram 斷句參數")
            }
            .disabled(appState.isCapturing)
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            lastSelectedProfileId = appState.selectedProfileId
            loadDrafts()
        }
        .onChange(of: appState.selectedProfileId) { _ in
            if let previousId = lastSelectedProfileId {
                commitDrafts(to: previousId)
            }
            lastSelectedProfileId = appState.selectedProfileId
            loadDrafts()
        }
        .onDisappear {
            commitDrafts(to: appState.selectedProfileId)
        }
    }

    // MARK: - 匯出匯入

    private func exportSelectedProfile() {
        // Menu Bar App 先啟用前景，避免 Save Panel 被其他視窗壓在後方
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)

        // 避免在 SwiftUI 事件處理中直接開 panel，下一個 runloop 再顯示更穩定
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.title = "匯出 Profile"
            panel.nameFieldStringValue = "\(appState.currentProfile.displayName).json"
            panel.allowedContentTypes = [UTType.json]
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                let data = try appState.exportCurrentProfile()
                try data.write(to: url)
            } catch {
                showErrorAlert(title: "匯出失敗", message: error.localizedDescription)
            }
        }
    }

    private func importProfileFromFile() {
        // Menu Bar App 先啟用前景，避免 Open Panel 被其他視窗壓在後方
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)

        // 避免在 SwiftUI 事件處理中直接開 panel，下一個 runloop 再顯示更穩定
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "匯入 Profile"
            panel.allowedContentTypes = [UTType.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false

            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                let data = try Data(contentsOf: url)
                if !appState.importProfile(from: data) {
                    showErrorAlert(title: "匯入失敗", message: "無效的 Profile 格式，或擷取中無法匯入。")
                }
                // 注意：不手動呼叫 loadDrafts()，因為 onChange(of: selectedProfileId) 會自動處理
            } catch {
                showErrorAlert(title: "匯入失敗", message: error.localizedDescription)
            }
        }
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "確定")
        alert.runModal()
    }
}

private struct ProfileTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var onEndEditing: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.backgroundColor = isEditable ? NSColor.textBackgroundColor : NSColor.controlBackgroundColor
        textView.textColor = isEditable ? NSColor.labelColor : NSColor.secondaryLabelColor
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        if textView.isSelectable != isEditable {
            textView.isSelectable = isEditable
        }
        textView.backgroundColor = isEditable ? NSColor.textBackgroundColor : NSColor.controlBackgroundColor
        textView.textColor = isEditable ? NSColor.labelColor : NSColor.secondaryLabelColor
        if !isEditable, textView.window?.firstResponder == textView {
            textView.window?.makeFirstResponder(nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: ProfileTextView

        init(_ parent: ProfileTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEndEditing?()
        }
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

                Toggle("文字外框（1px 黑色）", isOn: $appState.subtitleTextOutlineEnabled)
                    .onChangeCompat(of: appState.subtitleTextOutlineEnabled) {
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

    var body: some View {
        Form {
            Section {
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
            } footer: {
                Text("解鎖字幕後可直接拖曳右下角調整大小")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Stepper("歷史列數：\(appState.subtitleHistoryLimit)", value: $appState.subtitleHistoryLimit, in: 1...30)
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
