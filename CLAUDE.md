# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

Auto-Sub 是一款 macOS Menu Bar 應用程式，即時擷取系統音訊進行語音辨識並翻譯成繁體中文。

**流程**：系統音訊（日語）→ ScreenCaptureKit 擷取 → Deepgram STT → Gemini 翻譯 → 螢幕字幕覆蓋層

**project_name**: `auto-sub`

## 開發指令

### macOS 應用程式（Swift）

```bash
# 從 project.yml 產生 Xcode 專案（XcodeGen）
cd AutoSub && xcodegen generate

# 建構應用程式
xcodebuild -project AutoSub/AutoSub.xcodeproj -scheme AutoSub -configuration Debug build

# 執行應用程式
open AutoSub/build/Debug/AutoSub.app
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
├── AutoSub/                    # macOS 應用程式 (Swift 6.0, SwiftUI)
│   ├── project.yml            # XcodeGen 組態
│   └── AutoSub/
│       ├── Services/          # 3 核心服務
│       │   ├── AudioCaptureService.swift    # ScreenCaptureKit 音訊擷取
│       │   ├── PythonBridgeService.swift    # Python 子程序 IPC
│       │   └── ConfigurationService.swift   # 設定 + Keychain
│       ├── Models/            # 資料模型
│       │   └── AppState.swift               # 應用狀態 (ObservableObject)
│       ├── Views/             # SwiftUI 視圖
│       │   └── SubtitleOverlay.swift        # 字幕顯示
│       └── Resources/backend/  # Python 後端（內嵌）
│           ├── main.py        # 主程式，stdin/stdout IPC
│           ├── transcriber.py # Deepgram SDK v5 即時轉錄
│           └── translator.py  # Gemini 翻譯 + context 管理
│
├── poc/                       # 概念驗證（獨立執行）
│   ├── poc.py                # PoC 主程式
│   └── systemAudioDump/      # Swift 音訊擷取工具
│
└── specs/                     # 規格文件
    └── 001-initial-implementation/
        ├── PRD.md            # 產品需求文件
        └── SPEC.md           # 技術規格
```

## 資料流

```
AudioCaptureService (Swift)
    ↓ PCM 24kHz/16-bit/stereo (9600 bytes/chunk)
PythonBridgeService.stdin
    ↓
main.py → transcriber.py (Deepgram WebSocket)
    ↓ 分段文字
translator.py (Gemini Chat API)
    ↓ JSON Lines
PythonBridgeService.stdout
    ↓ {"type":"subtitle","original":"...","translation":"..."}
AppState.currentSubtitle
    ↓
SubtitleOverlay (NSWindow)
```

## 音訊格式

- 格式：16-bit signed int, little-endian
- 取樣率：24kHz
- 聲道：雙聲道（立體聲）
- 區塊大小：9600 bytes（100ms）

## Python Backend IPC 協議

**stdin (Swift → Python)**：二進位 PCM 音訊資料

**stdout (Python → Swift)**：JSON Lines
```json
{"type": "subtitle", "original": "日文原文", "translation": "翻譯"}
{"type": "status", "status": "connected"}
{"type": "error", "message": "...", "code": "..."}
```

## 技術細節

### Deepgram（transcriber.py）
- 模型：`nova-3`，語言：`ja`
- endpointing：400ms，utterance_end：1200ms
- 分段邏輯：is_final buffer + speech_final 觸發 + 超過 80 字強制 flush + UtteranceEnd 觸發

### Gemini（translator.py）
- 模型：`gemini-2.5-flash-lite`
- Chat Session 保持上下文，context 超過 100K token 自動摘要重建
- 翻譯策略：人名音譯一致性、台灣常見譯法

### macOS 要求
- macOS 13.0+（需要 ScreenCaptureKit）
- 需要螢幕錄製權限
- App Sandbox 已禁用（需要音訊存取）
