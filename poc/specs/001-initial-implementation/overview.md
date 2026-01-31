# Auto-Sub Implementation Plan

## Overview

Auto-Sub 是一款 macOS Menu Bar 應用程式，能即時擷取系統音訊、進行日語語音辨識並翻譯成繁體中文，以字幕覆蓋層顯示。

**架構**：Swift App + Python Backend（stdin/stdout IPC）

**目標**：完成 MVP Phase 1 功能，實現基本的即時字幕翻譯功能。

## Phase Summary

| Phase | Name | Duration | Key Deliverables |
|-------|------|----------|------------------|
| 0 | 專案設置 | 0.5 day | Xcode 專案、目錄結構、Bundle 配置 |
| 1 | Python Backend | 1-1.5 day | main.py、transcriber.py、translator.py（複用 PoC）|
| 2 | Swift 音訊擷取 | 1.5-2 day | AudioCaptureService、格式驗證 |
| 3 | Swift-Python 橋接 | 0.5-1 day | PythonBridgeService、JSON Lines 緩衝 |
| 4 | UI 整合 | 1.5 day | MenuBar、Settings、Keychain、SubtitleOverlay |
| 5 | 測試與收尾 | 1-1.5 day | 整合測試、效能驗證、文件 |

**總預估時間**：6-8 天（含 buffer）

> ⚠️ **時間調整說明**：根據驗證評估，Phase 1（串流邏輯）、Phase 2（ScreenCaptureKit）、Phase 4（Keychain）較預期複雜，建議預留 1.5-2x buffer。

## Dependencies

```
Phase 0 ──▶ Phase 1 ──▶ Phase 3 ──▶ Phase 4 ──▶ Phase 5
       └──▶ Phase 2 ──┘
```

**說明**：
- Phase 0 完成後，Phase 1（Python）和 Phase 2（Swift 音訊）可平行開發
- Phase 3 需要 Phase 1 和 Phase 2 都完成
- Phase 4 需要 Phase 3 完成
- Phase 5 需要 Phase 4 完成

## Session Strategy

### 推薦 Session 分組

| Session | Phases | 內容 | 預估時間 |
|---------|--------|------|----------|
| 1 | 0 + 1 | 專案設置 + Python Backend | 1 day |
| 2 | 2 | Swift 音訊擷取 | 1 day |
| 3 | 3 + 4 | 橋接 + UI 整合 | 1.5 day |
| 4 | 5 | 測試與收尾 | 0.5-1 day |

### Session Handoff 提示

**Session 1 → 2**：
- 確認 Python backend 可獨立運行測試
- 確認 Xcode 專案 build 成功

**Session 2 → 3**：
- 確認 AudioCaptureService 可輸出 PCM 資料
- 測試權限請求流程

**Session 3 → 4**：
- 確認 Swift 可成功啟動 Python 子程序
- 確認 stdin/stdout 通訊正常

## Technical Stack

| 組件 | 技術 | 版本 |
|------|------|------|
| Swift | Swift | 6.0+ |
| UI | SwiftUI | macOS 13+ |
| 音訊 | ScreenCaptureKit | macOS 13+ |
| Python | Python | 3.11+ |
| STT | Deepgram SDK | 5.3.2 |
| 翻譯 | Google GenAI | 1.61.0 |

## Verification Criteria

### MVP 完成標準

- [ ] 可擷取系統音訊
- [ ] 語音辨識延遲 < 1 秒
- [ ] 翻譯延遲 < 2 秒（總延遲）
- [ ] 字幕正確顯示（雙語）
- [ ] Menu Bar 控制正常
- [ ] 設定視窗可輸入 API Keys
- [ ] 錯誤狀態有視覺回饋
- [ ] 連續運行 1 小時無崩潰

### 各 Phase 驗證

- Phase 0：`xcodebuild` 成功
- Phase 1：Python backend 可處理測試音訊
- Phase 2：可輸出 PCM 資料到 console
- Phase 3：Swift ↔ Python 通訊正常
- Phase 4：完整 UI 流程可操作
- Phase 5：所有功能整合測試通過

## Project Structure

```
AutoSub/
├── AutoSub.xcodeproj/
├── AutoSub/
│   ├── AutoSubApp.swift
│   ├── Models/
│   │   ├── AppState.swift
│   │   ├── SubtitleEntry.swift
│   │   └── Configuration.swift
│   ├── Views/
│   │   ├── MenuBarView.swift
│   │   ├── SettingsView.swift
│   │   ├── SubtitleOverlay.swift
│   │   └── OnboardingView.swift
│   ├── Services/
│   │   ├── AudioCaptureService.swift
│   │   ├── PythonBridgeService.swift
│   │   └── ConfigurationService.swift
│   ├── Utilities/
│   │   ├── SubtitleWindowController.swift
│   │   └── KeyboardShortcuts.swift
│   └── Resources/
│       └── backend/
│           ├── main.py
│           ├── transcriber.py
│           ├── translator.py
│           └── requirements.txt
└── AutoSubTests/
```

## Related Documents

- `PRD.md` - 產品需求文件
- `SPEC.md` - 技術規格書
- `poc/` - PoC 驗證程式碼

## Notes

### 已知風險

1. **Python 環境依賴**：用戶需先安裝 Python 3.11+
2. **螢幕錄製權限**：首次使用需授權
3. **API 成本**：Deepgram + Gemini 月成本約 $5-7

### 從 PoC 複用

- `poc/transcriber.py` → `AutoSub/Resources/backend/transcriber.py`
- `poc/translator.py` → `AutoSub/Resources/backend/translator.py`
- 新建 `main.py` 作為 stdin/stdout 橋接入口
