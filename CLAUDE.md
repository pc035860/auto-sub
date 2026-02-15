# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

Auto-Sub 是一款 macOS Menu Bar 應用程式，即時擷取系統音訊進行語音辨識並翻譯成繁體中文。

**流程**：系統音訊（日語）→ ScreenCaptureKit 擷取 → Deepgram STT → Gemini 翻譯 → 螢幕字幕覆蓋層

**project_name**: `auto-sub`

## 開發哲學與慣例

- **Menu Bar 行為以 AppKit 為準**：涉及 Menu、Window、焦點、層級時，優先使用 `NSStatusItem`、`NSMenu`、`NSWindow` 原生能力。
- **單一責任狀態更新**：同一份 UI 狀態盡量只保留一個權威來源，避免多路徑同時寫入造成競態或抖動。

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

## Swift 開發注意事項

- **struct value type 同步問題**：當 struct 被加入多個陣列時（如 `subtitleHistory` 和 `sessionSubtitles`），更新其中一個陣列中的 entry **不會**自動同步到另一個陣列。必須在 `updateTranslation()` 等更新方法中，同時更新所有相關陣列中對應的 entry。

## 近期重大變更

- **字幕匯出功能 (2026-02-16)**：新增 SRT 匯出，支援雙語/僅原文/僅翻譯三種模式。Menu Bar → 「匯出為 SRT...」。使用 `sessionSubtitles` 儲存完整 Session（不受 `subtitleHistoryLimit` 限制）。
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
{"type": "error", "message": "...", "code": "..."}
```

## 技術細節

### Deepgram（transcriber.py）
- 模型：`nova-3`，語言：可配置（預設 `ja`）
- endpointing：可配置（預設 200ms），utterance_end：可配置（預設 1000ms）
- 分段邏輯：is_final buffer + speech_final 觸發 + 超過 max_buffer_chars（預設 50）強制 flush + UtteranceEnd 觸發
- 支援 keyterm 提示詞（透過 Profile 設定）
- 支援 interim 即時回饋（on_interim callback）
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
