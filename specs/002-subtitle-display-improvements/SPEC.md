# SPEC：字幕顯示系統改進 - 技術規格

## 1. 概述

本文件定義字幕顯示系統改進的技術實作規格，基於 [PRD.md](./PRD.md) 的需求。

### 1.1 變更範圍

| 層級 | 變更檔案 | 變更類型 |
|------|---------|---------|
| Swift Models | `SubtitleEntry.swift` | 修改 |
| Swift Models | `AppState.swift` | 修改 |
| Swift Views | `SubtitleOverlay.swift` | 重寫 |
| Swift Utilities | `SubtitleWindowController.swift` | 重寫 |
| Swift Services | `PythonBridgeService.swift` | 修改 |
| Swift Views | `MenuBarView.swift` | 修改 |
| Python | `main.py` | 修改 |
| Python | `transcriber.py` | 修改（回呼簽名變更） |

### 1.2 技術棧（維持現有）

| 類別 | 技術 | 版本 |
|------|------|------|
| Swift | Swift | 6.0 |
| UI 框架 | SwiftUI | macOS 13+ |
| 視窗管理 | AppKit (NSWindow) | macOS 13+ |
| Python | Python | ≥3.11 |
| 語音辨識 | Deepgram SDK | 5.3.2 |
| 翻譯 | Google GenAI SDK | 1.61.0 |

---

## 2. 資料模型變更

### 2.1 SubtitleEntry.swift

**現有結構**：
```swift
struct SubtitleEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let originalText: String
    let translatedText: String
    let timestamp: Date
}
```

**新結構**：
```swift
struct SubtitleEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var originalText: String
    var translatedText: String?  // nil 表示翻譯中
    let timestamp: Date

    /// 是否正在翻譯中
    var isTranslating: Bool {
        translatedText == nil
    }

    /// 建立僅含原文的條目（收到 transcript 時）
    init(id: UUID = UUID(), originalText: String, timestamp: Date = Date()) {
        self.id = id
        self.originalText = originalText
        self.translatedText = nil
        self.timestamp = timestamp
    }

    /// 建立完整條目（收到 subtitle 時，用於更新）
    init(id: UUID, originalText: String, translatedText: String, timestamp: Date = Date()) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.timestamp = timestamp
    }
}
```

**變更說明**：
- `translatedText` 改為 Optional，支援「翻譯中」狀態
- 新增 `isTranslating` 計算屬性
- 新增兩個初始化器，分別用於 transcript 和 subtitle

### 2.2 AppState.swift

**新增屬性**：
```swift
@MainActor
class AppState: ObservableObject {
    // ... 現有屬性 ...

    // MARK: - 字幕歷史
    /// 字幕歷史記錄（最多保留 3 筆）
    @Published var subtitleHistory: [SubtitleEntry] = []

    // MARK: - 字幕位置
    /// 字幕框是否鎖定
    @Published var isSubtitleLocked: Bool = true

    /// 字幕框位置 X（nil 表示使用預設位置）
    @Published var subtitlePositionX: CGFloat?

    /// 字幕框位置 Y（nil 表示使用預設位置）
    @Published var subtitlePositionY: CGFloat?

    // MARK: - 常數
    /// 最大歷史記錄數量
    static let maxHistoryCount = 3
}
```

**新增方法**：
```swift
extension AppState {
    /// 新增字幕（原文，翻譯中狀態）
    func addTranscript(id: UUID, text: String) {
        let entry = SubtitleEntry(id: id, originalText: text)
        subtitleHistory.append(entry)

        // 超過最大數量時移除最舊的
        if subtitleHistory.count > Self.maxHistoryCount {
            subtitleHistory.removeFirst()
        }

        // 同步更新 currentSubtitle（最新的）
        currentSubtitle = entry
    }

    /// 更新字幕翻譯
    func updateTranslation(id: UUID, translation: String) {
        if let index = subtitleHistory.firstIndex(where: { $0.id == id }) {
            subtitleHistory[index].translatedText = translation

            // 若是最新的，也更新 currentSubtitle
            if subtitleHistory[index].id == currentSubtitle?.id {
                currentSubtitle = subtitleHistory[index]
            }
        }
    }

    /// 載入儲存的字幕位置
    func loadSubtitlePosition() {
        if let x = UserDefaults.standard.object(forKey: "subtitlePositionX") as? CGFloat,
           let y = UserDefaults.standard.object(forKey: "subtitlePositionY") as? CGFloat {
            subtitlePositionX = x
            subtitlePositionY = y
        }
        isSubtitleLocked = UserDefaults.standard.bool(forKey: "isSubtitleLocked")
    }

    /// 儲存字幕位置
    func saveSubtitlePosition() {
        if let x = subtitlePositionX, let y = subtitlePositionY {
            UserDefaults.standard.set(x, forKey: "subtitlePositionX")
            UserDefaults.standard.set(y, forKey: "subtitlePositionY")
        }
        UserDefaults.standard.set(isSubtitleLocked, forKey: "isSubtitleLocked")
    }

    /// 重設字幕位置到預設
    func resetSubtitlePosition() {
        subtitlePositionX = nil
        subtitlePositionY = nil
        UserDefaults.standard.removeObject(forKey: "subtitlePositionX")
        UserDefaults.standard.removeObject(forKey: "subtitlePositionY")
    }
}
```

---

## 3. IPC 協議變更

### 3.1 新增訊息類型：transcript

**格式**：
```json
{"type": "transcript", "id": "uuid-string", "text": "日文原文"}
```

**欄位說明**：

| 欄位 | 類型 | 必填 | 說明 |
|------|------|------|------|
| type | string | ✓ | 固定為 `"transcript"` |
| id | string | ✓ | UUID 字串，用於配對翻譯結果 |
| text | string | ✓ | 語音辨識的原文 |

### 3.2 修改訊息類型：subtitle

**新格式**：
```json
{"type": "subtitle", "id": "uuid-string", "original": "日文原文", "translation": "翻譯結果"}
```

**欄位變更**：

| 欄位 | 變更 | 說明 |
|------|------|------|
| id | 新增 | UUID 字串，與 transcript 配對 |

### 3.3 完整協議定義

```
Python → Swift (stdout, JSON Lines):

1. transcript - 原文即時送出
   {"type": "transcript", "id": "...", "text": "..."}

2. subtitle - 翻譯完成
   {"type": "subtitle", "id": "...", "original": "...", "translation": "..."}

3. status - 狀態變更（維持現有）
   {"type": "status", "status": "connected"}

4. error - 錯誤訊息（維持現有）
   {"type": "error", "message": "...", "code": "..."}
```

---

## 4. Python Backend 變更

### 4.1 main.py

**變更位置**：`AutoSub/AutoSub/Resources/backend/main.py`

**新增 transcript 輸出**：

```python
import uuid

def on_transcript(text: str) -> None:
    """語音辨識分段完成時的回呼"""
    transcript_id = str(uuid.uuid4())

    # 1. 立即送出原文
    output_json({
        "type": "transcript",
        "id": transcript_id,
        "text": text
    })

    # 2. 進行翻譯
    try:
        translation = translator.translate(text)

        # 3. 送出翻譯結果
        output_json({
            "type": "subtitle",
            "id": transcript_id,
            "original": text,
            "translation": translation
        })
    except Exception as e:
        output_json({
            "type": "error",
            "message": f"Translation failed: {str(e)}",
            "code": "TRANSLATE_ERROR"
        })
```

### 4.2 transcriber.py 變更

**變更位置**：`AutoSub/AutoSub/Resources/backend/transcriber.py`

**回呼簽名變更**：

```python
# 之前：回呼只接收文字
self.on_transcript: Callable[[str], None] | None = None

# 之後：回呼接收 id 和文字
self.on_transcript: Callable[[str, str], None] | None = None  # (id, text)
```

**_flush_buffer 方法變更**：

```python
def _flush_buffer(self) -> None:
    if not self._utterance_buffer:
        return

    full_transcript = "".join(self._utterance_buffer)
    self._utterance_buffer.clear()

    if self.on_transcript and full_transcript.strip():
        # 生成 UUID 並傳給回呼
        transcript_id = str(uuid.uuid4())
        self.on_transcript(transcript_id, full_transcript)
```

### 4.3 資料流變更

```
之前：
transcriber._flush_buffer()
    → on_transcript(text)
    → translator.translate(text)
    → output_json(subtitle)

之後：
transcriber._flush_buffer()
    → on_transcript(id, text)
    → main.py:
        1. output_json(transcript)  ← 立即送出原文
        2. translator.translate(text)
        3. output_json(subtitle)    ← 翻譯完成後送出
```

---

## 5. Swift 端變更

### 5.1 PythonBridgeService.swift

**變更位置**：`AutoSub/AutoSub/Services/PythonBridgeService.swift`

**新增回呼**：
```swift
/// 收到原文時的回呼（id, text）
var onTranscript: ((UUID, String) -> Void)?
```

**修改 parseAndDispatch**：
```swift
private nonisolated func parseAndDispatch(_ jsonLine: String) {
    guard let jsonData = jsonLine.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let type = json["type"] as? String else {
        return
    }

    Task { @MainActor [weak self] in
        switch type {
        case "transcript":
            // 新增：處理原文
            if let idString = json["id"] as? String,
               let id = UUID(uuidString: idString),
               let text = json["text"] as? String {
                self?.onTranscript?(id, text)
            }

        case "subtitle":
            // 修改：包含 id
            if let idString = json["id"] as? String,
               let id = UUID(uuidString: idString),
               let original = json["original"] as? String,
               let translation = json["translation"] as? String {
                let entry = SubtitleEntry(
                    id: id,
                    originalText: original,
                    translatedText: translation
                )
                self?.onSubtitle?(entry)
            }

        case "status":
            if let status = json["status"] as? String {
                self?.onStatusChange?(status)
            }

        case "error":
            if let message = json["message"] as? String {
                self?.onError?(message)
            }

        default:
            print("[PythonBridge] Unknown message type: \(type)")
        }
    }
}
```

### 5.2 MenuBarView.swift

**修改回呼設定**：
```swift
// 新增：transcript 回呼
bridge.onTranscript = { [weak state] id, text in
    Task { @MainActor in
        state?.addTranscript(id: id, text: text)
    }
}

// 修改：subtitle 回呼（更新翻譯）
bridge.onSubtitle = { [weak state] subtitle in
    Task { @MainActor in
        state?.updateTranslation(id: subtitle.id, translation: subtitle.translatedText ?? "")
    }
}
```

---

## 6. SubtitleOverlay.swift 重寫

### 6.1 完整實作

```swift
import SwiftUI

struct SubtitleOverlay: View {
    @EnvironmentObject var appState: AppState

    /// 歷史字幕的透明度
    private let opacityLevels: [Double] = [0.3, 0.6, 1.0]  // 最舊 → 最新

    var body: some View {
        VStack(spacing: 0) {
            // 解鎖時顯示拖曳把手
            if !appState.isSubtitleLocked {
                HStack {
                    Spacer()
                    DragHandle {
                        // 點擊把手鎖定字幕
                        appState.isSubtitleLocked = true
                        appState.saveSubtitlePosition()
                        // 通知視窗控制器更新滑鼠事件處理
                        NotificationCenter.default.post(name: .subtitleLockStateChanged, object: nil)
                    }
                }
                .padding(.trailing, 8)
                .padding(.top, 4)
            }

            // 字幕內容（帶捲軸）
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(Array(appState.subtitleHistory.enumerated()), id: \.element.id) { index, entry in
                            SubtitleRow(entry: entry, showOriginal: appState.showOriginalText)
                                .opacity(opacityForIndex(index))
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .onChangeCompat(of: appState.subtitleHistory.count) {
                    // 新字幕進來時自動捲到底部
                    if let lastId = appState.subtitleHistory.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
    }

    /// 最大寬度（螢幕 80%）
    private var maxWidth: CGFloat {
        (NSScreen.main?.visibleFrame.width ?? 1920) * 0.8
    }

    /// 最大高度（螢幕 20%）
    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 1080) * 0.2
    }

    /// 根據索引計算透明度
    private func opacityForIndex(_ index: Int) -> Double {
        let count = appState.subtitleHistory.count
        let reversedIndex = count - 1 - index  // 0 = 最新, count-1 = 最舊

        if reversedIndex < opacityLevels.count {
            return opacityLevels[opacityLevels.count - 1 - reversedIndex]
        }
        return opacityLevels.first ?? 0.3
    }
}

/// 單筆字幕列
struct SubtitleRow: View {
    let entry: SubtitleEntry
    let showOriginal: Bool

    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 原文
            if showOriginal {
                Text(entry.originalText)
                    .font(.system(size: appState.subtitleFontSize * 0.85))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(nil)  // 不限制行數
                    .fixedSize(horizontal: false, vertical: true)  // 允許垂直擴展
            }

            // 翻譯（或翻譯中提示）
            if let translation = entry.translatedText {
                Text(translation)
                    .font(.system(size: appState.subtitleFontSize))
                    .foregroundColor(.white)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("翻譯中...")
                    .font(.system(size: appState.subtitleFontSize))
                    .foregroundColor(.gray)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 拖曳把手（點擊可切換鎖定狀態）
struct DragHandle: View {
    @EnvironmentObject var appState: AppState
    var onLockToggle: () -> Void

    var body: some View {
        Button(action: onLockToggle) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .help("點擊鎖定字幕位置")
    }
}

// MARK: - Notification 定義

extension Notification.Name {
    /// 字幕鎖定狀態變更通知
    static let subtitleLockStateChanged = Notification.Name("subtitleLockStateChanged")
}

// MARK: - macOS 相容性擴展
// 注意：此擴展統一定義在 SubtitleOverlay.swift
// 若 SettingsView.swift 已有相同定義，請移除以避免重複

extension View {
    /// macOS 13/14 相容的 onChange
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, _ in action() }
        } else {
            self.onChange(of: value) { _ in action() }
        }
    }
}
```

---

## 7. SubtitleWindowController.swift 重寫

### 7.1 完整實作

```swift
import AppKit
import SwiftUI

/// 字幕視窗控制器
@MainActor
final class SubtitleWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var windowDelegate: SubtitleWindowDelegate?
    private weak var appState: AppState?

    /// 初始化
    init() {}

    /// 設定 AppState 參考
    func configure(appState: AppState) {
        self.appState = appState
    }

    /// 顯示字幕視窗
    func show<Content: View>(content: Content) {
        if window == nil {
            createWindow()
        }

        hostingView?.rootView = AnyView(content)

        // 恢復儲存的位置
        restorePosition()

        // 更新滑鼠事件處理
        updateMouseEventHandling()

        window?.orderFront(nil)
    }

    /// 隱藏字幕視窗
    func hide() {
        window?.orderOut(nil)
    }

    /// 更新滑鼠事件處理（鎖定狀態變更時呼叫）
    func updateMouseEventHandling() {
        guard let appState = appState else { return }
        window?.ignoresMouseEvents = appState.isSubtitleLocked
    }

    /// 重設位置到預設
    func resetPosition() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let width = min(screenFrame.width * 0.8, window?.frame.width ?? 600)
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + 50

        window?.setFrameOrigin(NSPoint(x: x, y: y))

        appState?.subtitlePositionX = x
        appState?.subtitlePositionY = y
        appState?.saveSubtitlePosition()
    }

    // MARK: - Private

    private func createWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // 計算初始位置和尺寸
        let maxWidth = screenFrame.width * 0.8
        let maxHeight = screenFrame.height * 0.2
        let x = screenFrame.origin.x + (screenFrame.width - maxWidth) / 2
        let y = screenFrame.origin.y + 50

        let frame = NSRect(x: x, y: y, width: maxWidth, height: maxHeight)

        // 建立視窗
        window = SubtitleWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = false
        window?.level = NSWindow.Level(rawValue: 1000)  // 高於 screenSaver，確保覆蓋全螢幕 app
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]  // 移除 .stationary 以允許拖動
        window?.ignoresMouseEvents = true  // 預設鎖定
        window?.isMovableByWindowBackground = true  // 允許拖動

        // 設定視窗委派（偵測拖動結束）
        windowDelegate = SubtitleWindowDelegate()
        windowDelegate?.onDragEnd = { [weak self] in
            self?.saveCurrentPosition()
        }
        window?.delegate = windowDelegate

        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        window?.contentView = hostingView
    }

    private func restorePosition() {
        guard let window = window,
              let appState = appState else { return }

        appState.loadSubtitlePosition()

        if let x = appState.subtitlePositionX,
           let y = appState.subtitlePositionY {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func saveCurrentPosition() {
        guard let window = window,
              let appState = appState else { return }

        appState.subtitlePositionX = window.frame.origin.x
        appState.subtitlePositionY = window.frame.origin.y
        appState.saveSubtitlePosition()
    }
}

/// 自訂視窗類別
class SubtitleWindow: NSWindow {
    // 使用 NSWindowDelegate 偵測拖動結束（見 SubtitleWindowDelegate）
}

/// 視窗委派，處理拖動結束事件
class SubtitleWindowDelegate: NSObject, NSWindowDelegate {
    var onDragEnd: (() -> Void)?

    func windowDidMove(_ notification: Notification) {
        // 視窗移動結束時觸發
        onDragEnd?()
    }
}
```

---

## 8. Menu Bar 變更

### 8.1 MenuBarView.swift 新增選項

```swift
// 在現有選單中新增：

Divider()

// 鎖定字幕位置
Toggle(isOn: $appState.isSubtitleLocked) {
    Label("鎖定字幕位置", systemImage: appState.isSubtitleLocked ? "lock.fill" : "lock.open")
}
.onChange(of: appState.isSubtitleLocked) { _ in
    subtitleWindowController.updateMouseEventHandling()
    appState.saveSubtitlePosition()
}

// 重設字幕位置
Button {
    appState.resetSubtitlePosition()
    subtitleWindowController.resetPosition()
} label: {
    Label("重設字幕位置", systemImage: "arrow.counterclockwise")
}
```

---

## 9. 驗收測試案例

### 9.1 功能測試

| ID | 測試項目 | 步驟 | 預期結果 |
|----|---------|------|---------|
| T01 | 長文字換行 | 輸入超過視窗寬度的文字 | 自動換行，無截斷符號 |
| T02 | 動態高度 | 輸入多行文字 | 視窗高度自動調整 |
| T03 | 捲軸顯示 | 累積超過最大高度的字幕 | 出現捲軸 |
| T04 | 自動捲動 | 新字幕進入 | 自動捲到底部 |
| T05 | 歷史記錄 | 連續輸入 4 筆字幕 | 只保留最新 3 筆 |
| T06 | 透明度遞減 | 觀察 3 筆字幕 | 最新 100%、次新 60%、最舊 30% |
| T07 | 翻譯中狀態 | 收到 transcript | 顯示「翻譯中...」 |
| T08 | 翻譯完成 | 收到 subtitle | 更新為翻譯結果 |
| T09 | 解鎖移動 | 解鎖後拖動字幕框 | 可自由移動 |
| T10 | 鎖定穿透 | 鎖定後點擊字幕框 | 點擊穿透到下方視窗 |
| T11 | 位置保存 | 移動後重啟 App | 恢復到上次位置 |
| T12 | 位置重設 | 點擊「重設字幕位置」| 回到螢幕底部中央 |

### 9.2 效能測試

| ID | 測試項目 | 標準 |
|----|---------|------|
| P01 | 字幕更新延遲 | < 100ms |
| P02 | 拖動流暢度 | 60fps |
| P03 | 記憶體增量 | < 10MB |

---

## 10. 實作順序

### Phase 1：資料模型與 IPC

1. 修改 `SubtitleEntry.swift`
2. 修改 `AppState.swift`（新增屬性和方法）
3. 修改 `main.py`（transcript 輸出）
4. 修改 `PythonBridgeService.swift`（解析 transcript）
5. 修改 `MenuBarView.swift`（回呼設定）

### Phase 2：字幕顯示

1. 重寫 `SubtitleOverlay.swift`
2. 測試歷史記錄和透明度
3. 測試翻譯中狀態

### Phase 3：視窗控制

1. 重寫 `SubtitleWindowController.swift`
2. 實作拖動功能
3. 實作鎖定/解鎖
4. 實作位置持久化

### Phase 4：Menu Bar 整合

1. 新增 Menu Bar 選項
2. 整合測試
3. 修正問題

---

## 11. 相關文件

- [PRD.md](./PRD.md) - 產品需求文件
- [../001-initial-implementation/SPEC.md](../001-initial-implementation/SPEC.md) - 初始實作技術規格
