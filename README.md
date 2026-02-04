# Auto-Sub

macOS Menu Bar 即時字幕翻譯應用程式。擷取系統音訊，進行語音辨識後翻譯成繁體中文，以浮動字幕覆蓋層顯示。

## 功能

- **即時語音辨識**：透過 ScreenCaptureKit 擷取系統音訊，使用 Deepgram 進行即時語音轉文字
- **即時翻譯**：使用 Google Gemini 將辨識結果翻譯成繁體中文，支援上下文修正
- **浮動字幕**：可拖曳、鎖定的字幕覆蓋層，支援歷史記錄堆疊與透明度遞減
- **Profile 多場景**：針對不同場景（日劇、日漫、教學等）設定不同的翻譯參數
- **全域快捷鍵**：`⌘⇧S` 開始/停止擷取、`⌘⇧H` 隱藏/顯示字幕

## 系統需求

- macOS 13.0+
- 螢幕錄製權限（用於擷取系統音訊）
- Python 3.10+（內嵌 backend 使用，建議 3.12）
- API Keys：[Deepgram](https://deepgram.com) + [Google Gemini](https://ai.google.dev)

## 建構與執行

### 前置需求

- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Xcode 15.0+

### 建構步驟

```bash
# 1. 產生 Xcode 專案
cd AutoSub && xcodegen generate

# 2. 建構
xcodebuild -project AutoSub/AutoSub.xcodeproj -scheme AutoSub -configuration Debug build

# 3. 執行
open AutoSub/build/Debug/AutoSub.app
```

首次啟動時，應用程式會引導設定 API Keys（儲存於 Keychain）。

## 架構概覽

```
系統音訊 → ScreenCaptureKit → PCM 音訊
    → Python Backend (stdin/stdout IPC)
        → Deepgram STT (即時轉錄)
        → Gemini (翻譯 + 上下文修正)
    → 字幕覆蓋層 (SwiftUI in NSWindow)
```

### Swift 前端

| 模組 | 說明 |
|------|------|
| `MenuBar/` | AppKit NSStatusItem 菜單控制器、AppDelegate |
| `Services/` | 音訊擷取、Python IPC、設定管理 |
| `Models/` | AppState、Configuration、Profile、SubtitleEntry |
| `Views/` | 字幕覆蓋層、設定介面、MenuBar 選單 |
| `Utilities/` | 全域快捷鍵、通知定義、字幕視窗管理 |

### Python 後端

| 模組 | 說明 |
|------|------|
| `main.py` | IPC 協議處理，stdin 讀取 PCM、stdout 輸出 JSON Lines |
| `transcriber.py` | Deepgram SDK v5 WebSocket 即時轉錄，支援 interim 與 keyterm |
| `translator.py` | Gemini Chat API 翻譯，Structured Output，上下文摘要管理 |

## 技術棧

- **Swift 6.0** + AppKit + SwiftUI
- **Python 3.10+** + Deepgram SDK v5 + Google GenAI SDK
- **Deepgram nova-3** 即時語音辨識
- **Google Gemini** 翻譯（預設 `gemini-2.5-flash-lite-preview-09-2025`）
- **ScreenCaptureKit** 系統音訊擷取
- **XcodeGen** 專案管理

## 授權

Private - All Rights Reserved
