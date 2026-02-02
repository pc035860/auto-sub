# 字幕顯示系統改進 - 實作計畫

## 概述

本計畫基於 [PRD.md](./PRD.md) 和 [SPEC.md](./SPEC.md)，將改進分為兩個 Session 執行。

### 複雜度評估

| 指標 | 評估 |
|------|------|
| 估計時間 | 2-3 天 |
| 主要步驟 | 4 個 Phase（合併為 2 個 Session） |
| 涉及檔案 | 8 個（Swift 6 + Python 2） |
| 驗證點 | 4 個獨立功能區塊 |

### Session 策略

| Session | 內容 | 預估時間 |
|---------|------|----------|
| Session 1 | Phase 1 + 2：資料模型、IPC、字幕顯示 | 1-1.5 天 |
| Session 2 | Phase 3 + 4：視窗控制、Menu Bar 整合 | 1 天 |

### 技術環境

- **Python**：≥3.11
- **Swift**：6.0
- **macOS**：13.0+

---

## ⚠️ 相容性檢查（實作前必讀）

### SubtitleEntry 破壞性改動

`translatedText` 從 `String` 改為 `String?` 會影響現有程式碼。

**檢查清單**（Session 1 開始前執行）：

- [ ] 搜尋所有使用 `SubtitleEntry` 的地方：
  ```bash
  grep -r "SubtitleEntry" AutoSub/AutoSub --include="*.swift"
  ```
- [ ] 檢查 `currentSubtitle` 賦值的地點
- [ ] 確認所有 `translatedText` 存取處都處理 Optional

**已知需修改的地方**：
- `AppState.swift`：`currentSubtitle` 賦值
- `SubtitleOverlay.swift`：顯示翻譯文字
- `PythonBridgeService.swift`：建立 `SubtitleEntry`

### 依賴注入說明

**PythonBridgeService 取得方式**（MenuBarView 中）：
```swift
@Environment(\.pythonBridge) var pythonBridge
```

**SubtitleWindowController 取得方式**：
- 需在 App 層級建立並透過 Environment 傳遞
- 或使用 Singleton pattern

---

## Session 1：資料流與字幕顯示

### 目標

- 建立支援「翻譯中」狀態的資料模型
- 新增 `transcript` IPC 訊息類型
- 實作歷史字幕顯示（3 筆、透明度遞減）

### Phase 1：資料模型與 IPC

#### 1.1 修改 SubtitleEntry.swift

**檔案**：`AutoSub/AutoSub/Models/SubtitleEntry.swift`

變更：
- [ ] `translatedText` 改為 `String?`（Optional）
- [ ] 新增 `isTranslating` 計算屬性
- [ ] 新增兩個 initializer（transcript 用、subtitle 用）

程式碼參考：SPEC.md Section 2.1

#### 1.2 修改 AppState.swift

**檔案**：`AutoSub/AutoSub/Models/AppState.swift`

新增屬性：
- [ ] `subtitleHistory: [SubtitleEntry]` - 最多 3 筆
- [ ] `isSubtitleLocked: Bool` - 預設 true
- [ ] `subtitlePositionX: CGFloat?`
- [ ] `subtitlePositionY: CGFloat?`
- [ ] `maxHistoryCount = 3` 常數

新增方法：
- [ ] `addTranscript(id:text:)` - 新增原文條目
- [ ] `updateTranslation(id:translation:)` - 更新翻譯
- [ ] `loadSubtitlePosition()` - 從 UserDefaults 載入
- [ ] `saveSubtitlePosition()` - 儲存到 UserDefaults
- [ ] `resetSubtitlePosition()` - 重設位置

程式碼參考：SPEC.md Section 2.2

#### 1.3 修改 Python Backend

> **⚠️ UUID 生成位置澄清**：UUID 在 `transcriber.py` 的 `_flush_buffer()` 中生成，並作為參數傳遞給 `main.py` 的回呼。

**檔案**：`AutoSub/AutoSub/Resources/backend/transcriber.py`

變更（先改這個）：
- [ ] `import uuid`
- [ ] 回呼簽名改為 `Callable[[str, str], None]`（id, text）
- [ ] `_flush_buffer()` 內生成 UUID：`transcript_id = str(uuid.uuid4())`
- [ ] 呼叫回呼時傳入 id：`self.on_transcript(transcript_id, full_transcript)`

**檔案**：`AutoSub/AutoSub/Resources/backend/main.py`

變更（配合上面的修改）：
- [ ] 修改 `on_transcript` 回呼簽名為 `(id: str, text: str)`
- [ ] 先送 `transcript` 訊息（含 id）
- [ ] 翻譯完成後送 `subtitle` 訊息（含相同 id）

**資料流**：
```
transcriber._flush_buffer()
    → 生成 UUID
    → on_transcript(id, text)
    → main.py:
        1. output_json({"type": "transcript", "id": id, "text": text})
        2. translator.translate(text)
        3. output_json({"type": "subtitle", "id": id, ...})
```

程式碼參考：SPEC.md Section 4

#### 1.4 修改 PythonBridgeService.swift

**檔案**：`AutoSub/AutoSub/Services/PythonBridgeService.swift`

變更：
- [ ] 新增 `onTranscript: ((UUID, String) -> Void)?` 回呼
- [ ] `parseAndDispatch` 新增 `"transcript"` case
- [ ] 修改 `"subtitle"` case 解析 `id` 欄位

程式碼參考：SPEC.md Section 5.1

#### 1.5 修改 MenuBarView.swift（回呼設定）

**檔案**：`AutoSub/AutoSub/Views/MenuBarView.swift`

變更：
- [ ] 新增 `bridge.onTranscript` 回呼設定
- [ ] 修改 `bridge.onSubtitle` 呼叫 `updateTranslation`

程式碼參考：SPEC.md Section 5.2

### Phase 2：字幕顯示

#### 2.1 重寫 SubtitleOverlay.swift

**檔案**：`AutoSub/AutoSub/Views/SubtitleOverlay.swift`

新功能：
- [ ] 歷史字幕顯示（ForEach `subtitleHistory`）
- [ ] 透明度遞減（最新 100%、次新 60%、最舊 30%）
- [ ] 「翻譯中...」狀態顯示（灰色斜體）
- [ ] 動態尺寸（maxWidth 80%、maxHeight 20%）
- [ ] 捲軸支援（ScrollView + ScrollViewReader）
- [ ] 新字幕自動捲到底部
- [ ] 拖曳把手 UI（解鎖時顯示）
- [ ] `SubtitleRow` 子元件
- [ ] `DragHandle` 子元件
- [ ] `onChangeCompat` 相容性擴展
- [ ] `Notification.Name.subtitleLockStateChanged` 定義

**捲軸智慧捲動邏輯**（PRD 補充需求）：
- [ ] 新增 `@State private var isUserScrolling: Bool = false`
- [ ] 用戶手動捲動時，設 `isUserScrolling = true`（暫停自動捲動）
- [ ] 用戶捲到底部時，設 `isUserScrolling = false`（恢復自動捲動）
- [ ] 只在 `!isUserScrolling` 時自動捲到底部

程式碼參考：SPEC.md Section 6.1

### Session 1 驗證

#### 編譯驗證

```bash
# 建構專案
cd AutoSub && xcodegen generate
xcodebuild -project AutoSub.xcodeproj -scheme AutoSub -configuration Debug build
```

#### Python 後端驗證

```bash
# 確認 Python 版本
python3 --version  # 應為 ≥3.11

# 測試 IPC 訊息輸出（需要 API Keys）
cd AutoSub/AutoSub/Resources/backend
source .venv/bin/activate
DEEPGRAM_API_KEY=xxx GEMINI_API_KEY=xxx python test_cli.py
```

**IPC 訊息驗證**：
- [ ] 確認 `transcript` 訊息先輸出
- [ ] 確認 `subtitle` 訊息後輸出
- [ ] 確認兩者 `id` 欄位相同

#### 功能驗證

- [ ] App 編譯成功
- [ ] 字幕顯示最近 3 筆
- [ ] 超過 3 筆時，最舊的正確移除
- [ ] 透明度正確遞減
- [ ] 原文先顯示「翻譯中...」
- [ ] 翻譯完成後正確更新

#### 錯誤場景驗證

- [ ] 翻譯失敗時，原文保持顯示「翻譯中...」
- [ ] 連續快速多筆字幕時，ID 配對正確

---

## Session 2：視窗控制與 Menu Bar 整合

### 目標

- 實作字幕框拖曳移動功能
- 實作鎖定/解鎖機制
- 新增 Menu Bar 控制選項
- 位置持久化

### Phase 3：視窗控制

#### 3.1 重寫 SubtitleWindowController.swift

**檔案**：`AutoSub/AutoSub/Utilities/SubtitleWindowController.swift`

變更：
- [ ] 新增 `appState` 參考
- [ ] 新增 `configure(appState:)` 方法
- [ ] 新增 `updateMouseEventHandling()` 方法
- [ ] 新增 `resetPosition()` 方法
- [ ] 修改 `createWindow()` 支援拖動
- [ ] 新增 `restorePosition()` 從 AppState 恢復
- [ ] 新增 `saveCurrentPosition()` 拖動結束時儲存
- [ ] 新增 `SubtitleWindowDelegate` 處理 `windowDidMove`

視窗配置：
- [ ] `isMovableByWindowBackground = true`
- [ ] `ignoresMouseEvents` 根據鎖定狀態切換
- [ ] 移除 `.stationary` collection behavior

**預設位置計算**（若無儲存位置）：
```swift
let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2  // 水平居中
let y = screenFrame.origin.y + 50  // 距離底部 50pt
```

**拖動預覽效果**（PRD 需求）：
- [ ] 拖動開始時：`window.alphaValue = 0.7`（半透明）
- [ ] 拖動結束時：`window.alphaValue = 1.0`（恢復）
- [ ] 使用 `NSWindowDelegate` 的 `windowWillMove` / `windowDidMove`

程式碼參考：SPEC.md Section 7.1

### Phase 4：Menu Bar 整合

#### 4.1 修改 MenuBarView.swift（新增選項）

**檔案**：`AutoSub/AutoSub/Views/MenuBarView.swift`

新增 UI：
- [ ] 「鎖定字幕位置」Toggle（含 lock.fill / lock.open 圖示）
- [ ] 「重設字幕位置」Button
- [ ] Divider 分隔

新增邏輯：
- [ ] Toggle onChange 呼叫 `updateMouseEventHandling()`
- [ ] 重設按鈕呼叫 `resetSubtitlePosition()` + `resetPosition()`

程式碼參考：SPEC.md Section 8.1

#### 4.2 整合與連接

**檔案**：需確認 `SubtitleWindowController` 的注入方式

- [ ] 確保 `MenuBarView` 可存取 `SubtitleWindowController`
- [ ] 確保 App 啟動時呼叫 `loadSubtitlePosition()`
- [ ] 監聽 `.subtitleLockStateChanged` 通知

### Session 2 驗證

```bash
# 建構並執行
cd AutoSub && xcodegen generate
xcodebuild -project AutoSub.xcodeproj -scheme AutoSub -configuration Debug build
open build/Debug/AutoSub.app
```

#### 功能驗證

- [ ] 解鎖時顯示拖曳把手
- [ ] 可拖動字幕框
- [ ] 拖動時字幕框半透明
- [ ] 鎖定時點擊穿透
- [ ] Menu Bar 顯示鎖定選項
- [ ] 位置重啟後保持（含鎖定狀態）
- [ ] 重設功能正常（回到螢幕底部中央）

#### 多螢幕驗證（若適用）

- [ ] 切換螢幕後位置合理
- [ ] 若儲存的位置超出當前螢幕，使用預設位置

---

## 完整驗收清單

### 功能驗收

- [ ] 長文字自動換行，不顯示截斷符號
- [ ] 字幕框高度隨內容動態調整
- [ ] 超出最大高度時出現捲軸
- [ ] 新字幕自動捲到底部
- [ ] 顯示最近 3 筆字幕，透明度遞減
- [ ] 原文先顯示，翻譯後補上
- [ ] 翻譯中顯示「翻譯中...」提示
- [ ] 解鎖時可拖動字幕框
- [ ] 鎖定時點擊穿透
- [ ] 位置跨 session 保存
- [ ] Menu Bar 可切換鎖定狀態
- [ ] 可重設字幕位置到預設

### 效能驗收

- [ ] 字幕更新延遲 < 100ms (P01)
- [ ] 拖動流暢度 60fps (P02)
- [ ] 記憶體增量 < 10MB (P03)

---

## 相關檔案

| 檔案 | 變更類型 | Session |
|------|---------|---------|
| `SubtitleEntry.swift` | 修改 | 1 |
| `AppState.swift` | 修改 | 1 |
| `main.py` | 修改 | 1 |
| `transcriber.py` | 修改 | 1 |
| `PythonBridgeService.swift` | 修改 | 1 |
| `SubtitleOverlay.swift` | 重寫 | 1 |
| `MenuBarView.swift` | 修改 | 1, 2 |
| `SubtitleWindowController.swift` | 重寫 | 2 |

---

## 參考文件

- [PRD.md](./PRD.md) - 產品需求
- [SPEC.md](./SPEC.md) - 技術規格（含完整程式碼範例）
