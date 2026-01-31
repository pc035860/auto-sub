# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

即時系統音訊字幕翻譯 PoC - 擷取 macOS 系統音訊，透過 Deepgram 進行即時語音轉文字，再用 Gemini 翻譯成繁體中文。

流程：系統音訊（日語）→ Deepgram STT → Gemini 翻譯 → 終端機顯示

## 開發指令

```bash
# 安裝依賴（使用 uv）
uv sync

# 編譯系統音訊擷取工具（首次需要）
cd systemAudioDump && swift build -c release && cd ..

# 執行
uv run python poc.py
```

## 環境設定

複製 `.env.example` 到 `.env` 並填入：
- `DEEPGRAM_API_KEY` - Deepgram API key
- `GEMINI_API_KEY` - Google Gemini API key

## 架構

```
poc.py              # 主程式，SubtitlePipeline 串接各模組
├── audio_capture   # 呼叫 systemAudioDump 擷取音訊
├── transcriber     # Deepgram SDK v5 即時轉錄（WebSocket）
└── translator      # Gemini 2.5 Flash Lite 翻譯
```

### 音訊格式
- 格式：16-bit signed int, little-endian
- 取樣率：24kHz
- 聲道：雙聲道（立體聲）

### systemAudioDump
Swift 工具，使用 ScreenCaptureKit 擷取系統音訊。需要 macOS 13+ 和螢幕錄製權限。

## 技術細節

- Deepgram 使用 `nova-2` 模型，語言設定 `ja`（日語），endpointing 300ms
- Translator 使用 `gemini-2.5-flash-lite` 模型，針對日文→繁中優化的 prompt
