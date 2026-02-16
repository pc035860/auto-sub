# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

Auto-Sub 是一款 macOS Menu Bar 應用程式，即時擷取系統音訊進行語音辨識並翻譯成繁體中文。

**流程**：系統音訊（日語）→ ScreenCaptureKit 擷取 → Deepgram STT → Gemini 翻譯 → 螢幕字幕覆蓋層

**project_name**: `auto-sub`

## 開發哲學與慣例

- **Menu Bar 行為以 AppKit 為準**：涉及 Menu、Window、焦點、層級時，優先使用 `NSStatusItem`、`NSMenu`、`NSWindow` 原生能力。
- **單一責任狀態更新**：同一份 UI 狀態盡量只保留一個權威來源，避免多路徑同時寫入造成競態或抖動。
- **字幕資料預設保真**：`sessionSubtitles` 與 SRT 匯出預設保留原始事件序列，不做自動去重或語意合併；若要合併必須有明確需求與規格。
- **重構最小改動原則**：helper 函數 > 新類別 > 新檔案 > 新架構。優先提取同檔案的 helper，避免過度抽象。
- **YAGNI 原則**：不為「可能的未來需求」設計。等有 3+ 相似模式再抽象。

## 開發指令

### macOS 應用程式（Swift）

```bash
# 從 project.yml 產生 Xcode 專案（XcodeGen）
cd AutoSub && xcodegen generate

# 建構應用程式
xcodebuild -project AutoSub/AutoSub.xcodeproj -scheme AutoSub -configuration Debug build

# 執行應用程式（使用 DerivedData 產物）
open "$(find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/AutoSub.app' | head -n 1)"
```

### Python Backend 測試

```bash
# 設定 venv（首次）
cd AutoSub/AutoSub/Resources/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 執行 CLI 測試（需要 DEEPGRAM_API_KEY 和 GEMINI_API_KEY 環境變數）
DEEPGRAM_API_KEY=xxx GEMINI_API_KEY=xxx python test_cli.py

# 執行 backend 單元測試（含 context correction 與 transcriber watchdog）
python test_context_correction_flow.py
```

### PoC（概念驗證）

```bash
# 安裝依賴（使用 uv）
cd poc && uv sync

# 編譯系統音訊擷取工具（首次）
cd poc/systemAudioDump && swift build -c release && cd ..

# 執行 PoC
cd poc && uv run python poc.py
```

## 環境設定

應用程式內建 API Key 設定 UI（儲存在 Keychain）。開發測試時需設定環境變數：
- `DEEPGRAM_API_KEY` - Deepgram API key
- `GEMINI_API_KEY` - Google Gemini API key

## 架構

```
auto-sub/
├── AutoSub/                    # macOS 應用程式 (Swift 6.0, AppKit + SwiftUI)
│   ├── project.yml            # XcodeGen 組態
│   └── AutoSub/
│       ├── AutoSubApp.swift   # 應用入口點，初始化核心服務
│       ├── MenuBar/           # AppKit MenuBar 控制器
│       │   └── MenuBarController.swift  # NSStatusItem、AppDelegate、設定視窗
│       ├── Services/          # 核心服務
│       │   ├── AudioCaptureService.swift    # ScreenCaptureKit 音訊擷取
│       │   ├── PythonBridgeService.swift    # Python 子程序 IPC
│       │   ├── ConfigurationService.swift   # 設定 + Keychain
│       │   └── ExportService.swift          # SRT 匯出
│       ├── Models/            # 資料模型
│       │   ├── AppState.swift       # 應用狀態 (ObservableObject)
│       │   ├── Configuration.swift  # 設定模型 (含 Profile 遷移)
│       │   ├── Profile.swift        # 轉譯/翻譯場景 Profile
│       │   └── SubtitleEntry.swift  # 字幕條目 (支援翻譯中狀態)
│       ├── Views/             # SwiftUI 視圖
│       │   ├── SubtitleOverlay.swift   # 字幕顯示 (歷史+透明度遞減)
│       │   ├── SettingsView.swift      # Tab 式設定介面
│       │   ├── MenuBarView.swift       # MenuBar 選單內容
│       │   ├── AudioTestView.swift     # 音訊測試
│       │   └── OnboardingView.swift    # 首次設定引導
│       ├── Utilities/         # 工具類
│       │   ├── KeyboardShortcuts.swift        # 全域快捷鍵 (⌘⇧S/⌘⇧H)
│       │   ├── NotificationNames.swift        # 統一通知定義
│       │   └── SubtitleWindowController.swift # 字幕視窗管理 (原生縮放+拖動+鎖定)
│       └── Resources/backend/  # Python 後端（內嵌）
│           ├── main.py        # 主程式，stdin/stdout IPC
│           ├── transcriber.py # Deepgram SDK v5 即時轉錄
│           └── translator.py  # Gemini 翻譯 + context 管理 + 上下文修正
│
├── poc/                       # 概念驗證（獨立執行）
│   ├── poc.py                # PoC 主程式
│   └── systemAudioDump/      # Swift 音訊擷取工具
│
└── specs/                     # 規格文件
    ├── 001-initial-implementation/
    │   ├── PRD.md            # 產品需求文件
    │   └── SPEC.md           # 技術規格
    └── 002-subtitle-display-improvements/
        ├── PRD.md            # 字幕顯示改進需求
        └── SPEC.md           # 字幕顯示改進規格
```

## 資料流

```
AudioCaptureService (Swift, ScreenCaptureKit)
    ↓ PCM 24kHz/16-bit/stereo (9600 bytes/chunk)
PythonBridgeService.stdin
    ↓
main.py → transcriber.py (Deepgram WebSocket)
    ↓ transcript (id, text) + interim (即時文字)
translator.py (Gemini Streaming API, Structured Output)
    ↓ JSON Lines (streaming + final)
PythonBridgeService.stdout
    ↓ {"type":"translation_streaming","id":"...","partial":"..."} (即時更新)
    ↓ {"type":"subtitle","id":"...","original":"...","translation":"..."} (完成)
    ↓ {"type":"interim","text":"..."}
AppState
    ├─ addTranscript()           → subtitleHistory (最多 N 筆)
    ├─ updateStreamingTranslation() → 即時更新 (monotonic growth check)
    ├─ updateTranslation()       → 最終翻譯 + 可選上下文修正
    └─ updateInterim()           → currentInterim (即時顯示)
    ↓
SubtitleOverlay (SwiftUI in NSWindow)
    ├─ 歷史字幕堆疊 (透明度遞減)
    ├─ 即時原文 (interim)
    └─ 自動捲動 + 拖曳定位 + 原生視窗縮放
```

## 字幕視窗開發慣例（重要）

- **優先使用 AppKit 原生視窗能力**：拖動與縮放優先交給 `NSWindow` / `NSWindowDelegate`，避免用 SwiftUI `DragGesture` 重造輪子。
- **單一 frame 控制來源**：同一時間只能有一條路徑改 `window.setFrame`。避免「observer + gesture + notification」多路徑互搶。
- **Live resize 期間避免程式化回寫 frame**：使用者正在拖拉時，暫停 `applyRenderSettings()` 之類程式化尺寸套用，避免抖動。
- **尺寸限制放在視窗層**：最小/最大尺寸用 `contentMinSize` / `contentMaxSize`；不要在 `SubtitleOverlay` 根視圖用固定 `maxWidth/maxHeight` 限制視窗縮放。
- **鎖定策略固定**：鎖定字幕時 `ignoresMouseEvents = true`（click-through）；解鎖後才允許互動與移動。
- **縮放持久化時機**：在 `windowDidEndLiveResize` 再儲存設定，避免拖拉過程高頻寫入。

## Menu Bar 視窗/Panel Gotchas

- **本專案為 `LSUIElement`（Agent App）**：開啟設定窗、儲存對話框等系統 UI 前，需先確保 App 被 activate，否則視窗可能不在前景。
- **避免在 menu tracking 期間直接彈出系統 Panel**：應在下一個 main runloop 週期顯示，降低被其他視窗蓋住或焦點異常的機率。
- **匯出檔名時間語意**：SRT 預設檔名使用「該 session 開始時間」並與匯出子選單一致，不使用匯出當下時間。

## STT/Interim Gotchas

- **Deepgram idle timeout (`NET0001`) 常見於長時間無音訊**：維持 keepalive 與閒置 watchdog，避免連線被動中斷。
- **interim 清理必須走 `clearInterim()`**：不要直接寫 `currentInterim = nil`，避免遺留計時任務造成 UI 卡住或狀態不同步。
- **未完成句標記流程**：backend 會把過期 interim 落地為帶 `[暫停]` 的 transcript；前端只負責顯示與翻譯結果同步，不做隱性改寫。

## Swift 開發注意事項

- **struct value type 同步問題**：當 struct 被加入多個陣列時（如 `subtitleHistory` 和 `sessionSubtitles`），更新其中一個陣列中的 entry **不會**自動同步到另一個陣列。必須在 `updateTranslation()` 等更新方法中，同時更新所有相關陣列中對應的 entry。
- **SwiftUI onChange + loadDrafts 競態**：當 `@Published` 屬性改變觸發 `onChange` 時，`onChange` 內的 `commitDrafts` 會使用當前的 `@State` 值。若在 `onChange` 之前手動呼叫 `loadDrafts()` 更新 `@State`，會導致舊資料被新值覆蓋。**解法**：讓 `onChange` 自己處理 `loadDrafts()`，不要手動呼叫。

## 近期重大變更

- **Profile 匯出匯入功能 (2026-02-17)**：
  - 設定視窗 Profile Tab 新增匯出/匯入按鈕
  - 匯出：單一 Profile → `.json` 檔案（不含 id）
  - 匯入：自動生成新 UUID、同名衝突加後綴 `(2)`、參數範圍 clamp
  - 詳見 `specs/brainstorm/profile-import-export.md`
- **Tier 1 重構完成 (2026-02-16)**：
  - `main.py` `on_transcript` 從 93 行縮減至 46 行，提取 4 個 helper 函數（`translate_with_retry`、`send_subtitle`、`send_translation_update`、`send_translation_error`）
  - `MenuBarController.swift` `startCapture()` 從 123 行縮減至 58 行，提取 4 個 helper 方法（`buildConfiguration`、`setupBridgeCallbacks`、`setupAudioDataCallback`、`clearCallbacks`）
  - 詳見 `specs/brainstorm/refactor-260216.md`
- **字幕匯出功能 (2026-02-16)**：新增 SRT 匯出，支援雙語/僅原文/僅翻譯三種模式。Menu Bar → 「匯出為 SRT...」。使用 `sessionSubtitles` 儲存完整 Session（不受 `subtitleHistoryLimit` 限制）。
- **匯出檔名語意對齊 (2026-02-16)**：SRT 預設檔名改為使用 `session.startTime`，與匯出子選單時間一致。
- **暫停/恢復資料策略調整 (2026-02-16)**：移除 AppState 與 ExportService 的自動去重，恢復為完整保留原始字幕事件序列。
- **Deepgram 閒置穩定性強化 (2026-02-16)**：transcriber 新增 keepalive + stale interim watchdog；backend error payload 支援 `detail_code`（如 `NET0001_IDLE_TIMEOUT`）。
- **Streaming Translation (2026-02-15)**：翻譯改用 Gemini Streaming API，邊收到回應邊更新 UI，大幅改善使用者體驗。詳見 [`docs/streaming-translation-guide.md`](docs/streaming-translation-guide.md)。
- **Streaming 品質提升發現**：Streaming 模式下 Gemini 2.5 Flash Lite 翻譯品質從 ~60 分提升到 ~80 分，接近 Flash 3 水準。
- 字幕視窗已從「自製 `ResizeHandle` + resize 通知」遷移為 **原生 `NSWindow` 可縮放**。
- `LockStateIcon` 已移除，改由 `OpacityQuickMenu` 的顯示/隱藏來指示鎖定狀態。

## 音訊格式

- 格式：16-bit signed int, little-endian
- 取樣率：24kHz
- 聲道：雙聲道（立體聲）
- 區塊大小：9600 bytes（100ms）

## Python Backend IPC 協議

**stdin (Swift → Python)**：二進位 PCM 音訊資料

**stdout (Python → Swift)**：JSON Lines
```json
{"type": "transcript", "id": "uuid", "text": "原文"}
{"type": "translation_streaming", "id": "uuid", "partial": "部分翻譯（即時更新）"}
{"type": "subtitle", "id": "uuid", "original": "原文", "translation": "翻譯"}
{"type": "translation_update", "id": "prev-uuid", "translation": "修正後的前句翻譯"}
{"type": "interim", "text": "正在說的話（即時）"}
{"type": "status", "status": "connected"}
{"type": "error", "message": "...", "code": "...", "detail_code": "..."}
```

## 技術細節

### Deepgram（transcriber.py）
- 模型：`nova-3`，語言：可配置（預設 `ja`）
- endpointing：可配置（預設 200ms），utterance_end：可配置（預設 1000ms）
- 分段邏輯：is_final buffer + speech_final 觸發 + 超過 max_buffer_chars（預設 50）強制 flush + UtteranceEnd 觸發
- 支援 keyterm 提示詞（透過 Profile 設定）
- 支援 interim 即時回饋（on_interim callback）
- 空閒期間自動送 KeepAlive，並在 interim 長時間無更新時落地為 `[暫停]` 未完成句
- 追蹤前句資訊以支援上下文修正

### Gemini（translator.py）
- 預設模型：`gemini-2.5-flash-lite-preview-09-2025`，可在設定中切換
- **Streaming API**：使用 `send_message_stream()` 即時返回翻譯結果，支援 50ms debounce UI 更新
- 使用 Structured Output (Pydantic `TranslationResult`) 確保 JSON 回應格式
- Chat Session 保持上下文，context 超過可配置上限（預設 20K token）自動摘要重建
- 翻譯策略：人名音譯一致性、台灣常見譯法
- 上下文修正：翻譯時可同時修正前句翻譯（誤譯、語意不通、人名不一致）
- Thinking 配置：Gemini 3 使用 `thinking_level="minimal"`，Gemini 2.5 使用 `thinking_budget=0`
- 詳細文件：[`docs/streaming-translation-guide.md`](docs/streaming-translation-guide.md)

### Profile 系統
- 每個 Profile 包含：翻譯背景、keyterm 提示詞、來源/目標語言、Deepgram 斷句參數
- 支援多場景切換（日劇、日漫、教學等）
- 舊配置自動遷移為預設 Profile
- **匯出匯入**：設定視窗 → Profile Tab → 匯出/匯入按鈕。匯入時自動生成新 UUID、處理同名衝突、clamp 參數範圍。

### 全域快捷鍵
- `⌘ + Shift + S`：開始/停止擷取
- `⌘ + Shift + H`：隱藏/顯示字幕

### 字幕顯示
- 歷史字幕堆疊（可調保留筆數），透明度遞減
- 即時原文顯示（interim），翻譯中狀態
- 字幕視窗支援原生縮放、拖曳、鎖定、持久化（UserDefaults + Configuration）
- 文字邊框（outline）支援，智能自動捲動
- 解鎖時顯示 `OpacityQuickMenu`（透明度快速切換 dropdown），鎖定時隱藏；鎖定/解鎖狀態以此 UI 有無來辨識，已移除獨立的 `LockStateIcon`

### macOS 要求
- macOS 13.0+（需要 ScreenCaptureKit）
- 需要螢幕錄製權限
- App Sandbox 已禁用（需要音訊存取）

### 設定儲存
- **Keychain**：API Keys（deepgramApiKey, geminiApiKey）
- **Application Support**：`~/Library/Application Support/AutoSub/config.json`（Profiles、字幕參數等）
- **UserDefaults**：字幕位置 (X/Y)、鎖定狀態
