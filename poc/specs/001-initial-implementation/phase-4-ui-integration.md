# Phase 4: UI 整合

## Goal

建立完整的 SwiftUI 使用者介面，包括 Menu Bar、設定視窗、字幕覆蓋層，並整合所有 Services。

## Prerequisites

- [ ] Phase 3 完成（Swift-Python 橋接就緒）
- [ ] AudioCaptureService 可正常運作
- [ ] PythonBridgeService 可正常運作

## Tasks

### 4.1 建立 AppState

- [ ] 建立 `AutoSub/AutoSub/Models/AppState.swift`
- [ ] 定義應用程式狀態（idle, capturing, warning, error）
- [ ] 整合設定和字幕狀態

### 4.2 建立 AutoSubApp（App 入口）

- [ ] 修改 `AutoSub/AutoSub/AutoSubApp.swift`
- [ ] 配置 `MenuBarExtra` Scene
- [ ] 配置 Settings Scene
- [ ] 整合 Services

### 4.3 建立 MenuBarView

- [ ] 建立 `AutoSub/AutoSub/Views/MenuBarView.swift`
- [ ] 實作開始/停止控制
- [ ] 顯示狀態資訊
- [ ] 開啟設定視窗

### 4.4 建立 SettingsView

- [ ] 建立 `AutoSub/AutoSub/Views/SettingsView.swift`
- [ ] API Keys 輸入
- [ ] 語言設定
- [ ] 字幕樣式設定

### 4.5 建立 SubtitleOverlay

- [ ] 建立 `AutoSub/AutoSub/Views/SubtitleOverlay.swift`
- [ ] 雙語字幕顯示
- [ ] 自動顯示/隱藏動畫

### 4.6 建立 SubtitleWindowController

- [ ] 建立 `AutoSub/AutoSub/Utilities/SubtitleWindowController.swift`
- [ ] 建立透明無邊框視窗
- [ ] 設定置頂和點擊穿透

### 4.7 建立 ConfigurationService

- [ ] 建立 `AutoSub/AutoSub/Services/ConfigurationService.swift`
- [ ] 實作設定讀寫
- [ ] 實作 Keychain 儲存 API Keys

### 4.8 實作快捷鍵

- [ ] 建立 `AutoSub/AutoSub/Utilities/KeyboardShortcuts.swift`
- [ ] 實作全域快捷鍵（開始/停止、隱藏字幕）

## Code Examples

### AppState.swift

```swift
import SwiftUI
import Combine

enum AppStatus {
    case idle           // 待機
    case capturing      // 擷取中
    case warning        // 警告
    case error          // 錯誤
}

@MainActor
class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var isCapturing: Bool = false
    @Published var currentSubtitle: SubtitleEntry?
    @Published var isConfigured: Bool = false
    @Published var errorMessage: String?

    // 設定
    @Published var deepgramApiKey: String = ""
    @Published var geminiApiKey: String = ""
    @Published var sourceLanguage: String = "ja"
    @Published var targetLanguage: String = "zh-TW"

    // 字幕設定
    @Published var subtitleFontSize: CGFloat = 24
    @Published var subtitleDisplayDuration: TimeInterval = 4.0
    @Published var showOriginalText: Bool = true

    var isReady: Bool {
        !deepgramApiKey.isEmpty && !geminiApiKey.isEmpty
    }
}
```

### AutoSubApp.swift

```swift
import SwiftUI

@main
struct AutoSubApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var audioService = AudioCaptureService()
    @StateObject private var pythonBridge = PythonBridgeService()

    var body: some Scene {
        // Menu Bar App
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(audioService)
                .environmentObject(pythonBridge)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

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
```

### MenuBarView.swift

```swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var audioService: AudioCaptureService
    @EnvironmentObject var pythonBridge: PythonBridgeService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 狀態顯示
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
            }
            .padding(.horizontal)

            Divider()

            // 開始/停止按鈕
            Button(action: toggleCapture) {
                Label(
                    appState.isCapturing ? "停止擷取" : "開始擷取",
                    systemImage: appState.isCapturing ? "stop.fill" : "play.fill"
                )
            }
            .disabled(!appState.isReady)

            Divider()

            // 設定
            SettingsLink {
                Label("設定...", systemImage: "gear")
            }

            Divider()

            // 結束
            Button("結束 Auto-Sub") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 200)
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle: return .primary  // 與 SPEC 一致，適應系統主題
        case .capturing: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.status {
        case .idle: return "待機中"
        case .capturing: return "擷取中"
        case .warning: return "警告"
        case .error: return appState.errorMessage ?? "錯誤"
        }
    }

    private func toggleCapture() {
        Task {
            if appState.isCapturing {
                await stopCapture()
            } else {
                await startCapture()
            }
        }
    }

    private func startCapture() async {
        // 實作啟動邏輯...
    }

    private func stopCapture() async {
        // 實作停止邏輯...
    }
}
```

### SubtitleOverlay.swift

```swift
import SwiftUI

struct SubtitleOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var isVisible: Bool = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            if let subtitle = appState.currentSubtitle, isVisible {
                if appState.showOriginalText {
                    // 原文
                    Text(subtitle.originalText)
                        .font(.system(size: appState.subtitleFontSize * 0.85))
                        .foregroundColor(.white.opacity(0.8))
                }

                // 翻譯
                Text(subtitle.translatedText)
                    .font(.system(size: appState.subtitleFontSize))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .onChange(of: appState.currentSubtitle) { _, newSubtitle in
            if newSubtitle != nil {
                showSubtitle()
            }
        }
    }

    private func showSubtitle() {
        hideTask?.cancel()

        withAnimation {
            isVisible = true
        }

        hideTask = Task {
            try? await Task.sleep(for: .seconds(appState.subtitleDisplayDuration))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
        }
    }
}
```

### SubtitleWindowController.swift

```swift
import AppKit
import SwiftUI

class SubtitleWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    func show<Content: View>(content: Content) {
        if window == nil {
            createWindow()
        }

        hostingView?.rootView = AnyView(content)
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func createWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // 字幕位置：螢幕底部，寬度 80%
        let width = screenFrame.width * 0.8
        let height: CGFloat = 120
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + 50

        let frame = NSRect(x: x, y: y, width: width, height: height)

        window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = false
        window?.level = .statusBar + 1
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window?.ignoresMouseEvents = true

        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        window?.contentView = hostingView
    }
}
```

## Verification

### 測試步驟

1. 啟動 App，確認 Menu Bar 圖示出現
2. 開啟設定，輸入 API Keys
3. 點擊「開始擷取」
4. 播放日語音訊
5. 確認字幕顯示

### Expected Outcomes

- [ ] Menu Bar 圖示正確顯示
- [ ] 狀態變化時圖示會改變
- [ ] 設定視窗可輸入 API Keys
- [ ] API Keys 儲存到 Keychain
- [ ] 字幕覆蓋層正確顯示
- [ ] 字幕自動隱藏
- [ ] 快捷鍵正常運作

## Files Created/Modified

- `AutoSub/AutoSub/AutoSubApp.swift` (modified)
- `AutoSub/AutoSub/Models/AppState.swift` (new)
- `AutoSub/AutoSub/Views/MenuBarView.swift` (new)
- `AutoSub/AutoSub/Views/SettingsView.swift` (new)
- `AutoSub/AutoSub/Views/SubtitleOverlay.swift` (new)
- `AutoSub/AutoSub/Utilities/SubtitleWindowController.swift` (new)
- `AutoSub/AutoSub/Services/ConfigurationService.swift` (new)
- `AutoSub/AutoSub/Utilities/KeyboardShortcuts.swift` (new)

## Notes

### Menu Bar App 行為

- `LSUIElement = true`：不顯示 Dock 圖示
- 使用 `MenuBarExtra` 建立 Menu Bar 項目
- `.menuBarExtraStyle(.window)` 提供更豐富的 UI

### 字幕視窗特性

- `level = .statusBar + 1`：置頂顯示
- `ignoresMouseEvents = true`：點擊穿透
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`：所有桌面可見

### Keychain 儲存

API Keys 必須使用 Keychain 儲存，不要明文存在 config.json。

```swift
import Security

enum KeychainError: Error {
    case saveFailed
    case loadFailed
    case deleteFailed
}

class KeychainService {
    static let shared = KeychainService()
    private init() {}

    func save(key: String, value: String) throws {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.yourcompany.AutoSub",
            kSecValueData as String: data
        ]

        // 先刪除舊值
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.yourcompany.AutoSub",
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.yourcompany.AutoSub"
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed
        }
    }
}
```
