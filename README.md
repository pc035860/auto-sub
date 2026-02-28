# Auto-Sub

macOS Menu Bar 即時字幕翻譯應用程式。擷取系統音訊，進行語音辨識後翻譯成繁體中文，以浮動字幕覆蓋層顯示。

## 功能

- **即時語音辨識**：透過 ScreenCaptureKit 擷取系統音訊，使用 Deepgram 進行即時語音轉文字
- **即時串流翻譯**：使用 Google Gemini Streaming API 將辨識結果翻譯成繁體中文，邊收到回應邊更新 UI
- **上下文修正**：翻譯時自動檢查並修正前句翻譯（人名一致性、語意不通等）
- **浮動字幕**：可拖曳、鎖定、縮放的字幕覆蓋層，支援歷史記錄堆疊與透明度遞減
- **透明度快速切換**：解鎖狀態下可快速調整字幕透明度
- **Profile 多場景**：針對不同場景（日劇、日漫、教學等）設定不同的翻譯參數
- **Profile 匯出/匯入**：可將 Profile 匯出為 `.json` 檔案分享或備份，匯入時自動處理同名衝突
- **SRT 匯出**：支援雙語、僅原文、僅翻譯三種匯出模式
- **全域快捷鍵**：使用 sindresorhus/KeyboardShortcuts 套件，可自訂快捷鍵

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
        → Deepgram STT (即時轉錄 + interim)
        → Gemini Streaming API (翻譯 + 上下文修正)
    → 字幕覆蓋層 (SwiftUI in NSWindow)
```

### Swift 前端

| 模組 | 說明 |
|------|------|
| `MenuBar/` | AppKit NSStatusItem 菜單控制器、AppDelegate |
| `Services/` | 音訊擷取、Python IPC、設定管理、SRT 匯出 |
| `Models/` | AppState、Configuration、Profile、SubtitleEntry |
| `Views/` | 字幕覆蓋層、設定介面、MenuBar 選單、快捷鍵設定 |
| `Utilities/` | KeyboardShortcuts 整合、通知定義、字幕視窗管理 |

### Python 後端

| 模組 | 說明 |
|------|------|
| `main.py` | IPC 協議處理，stdin 讀取 PCM、stdout 輸出 JSON Lines |
| `transcriber.py` | Deepgram SDK v5 WebSocket 即時轉錄，支援 interim 與 keyterm |
| `translator.py` | Gemini Streaming API 翻譯，Structured Output，上下文摘要管理 |

## 技術棧

- **Swift 6.0** + AppKit + SwiftUI
- **Python 3.10+** + Deepgram SDK v5 + Google GenAI SDK
- **Deepgram nova-3** 即時語音辨識
- **Google Gemini** 翻譯
  - 預設：`gemini-2.5-flash-lite`
  - 可選：`gemini-2.5-flash`、`gemini-3-flash-preview`
- **ScreenCaptureKit** 系統音訊擷取
- **XcodeGen** 專案管理
- **KeyboardShortcuts** (sindresorhus) 全域快捷鍵

## 授權

[MIT License](LICENSE)
