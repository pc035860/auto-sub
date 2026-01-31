# Phase 1: Python Backend

## Goal

建立 Python Backend 程式，從 stdin 讀取 PCM 音訊資料，透過 Deepgram 進行語音辨識，再用 Gemini 翻譯，最後將結果輸出到 stdout。

## Prerequisites

- [ ] Phase 0 完成（Xcode 專案已建立）
- [ ] PoC 程式碼可參考（`poc/transcriber.py`、`poc/translator.py`）

## Tasks

### 1.1 複製並調整 PoC 程式碼

- [ ] 複製 `poc/transcriber.py` → `AutoSub/AutoSub/Resources/backend/transcriber.py`
- [ ] 複製 `poc/translator.py` → `AutoSub/AutoSub/Resources/backend/translator.py`
- [ ] 調整程式碼以符合 SPEC 規格

### 1.2 建立 main.py

- [ ] 建立 `AutoSub/AutoSub/Resources/backend/main.py`
- [ ] 實作 stdin 讀取 PCM 音訊
- [ ] 實作 stdout JSON Lines 輸出
- [ ] 整合 transcriber 和 translator

### 1.3 建立 requirements.txt

- [ ] 建立 `AutoSub/AutoSub/Resources/backend/requirements.txt`
- [ ] 列出所有依賴套件及版本

### 1.4 測試 Backend

- [ ] 使用測試音訊檔案驗證
- [ ] 確認 JSON 輸出格式正確

## Code Examples

### main.py 核心結構

```python
#!/usr/bin/env python3
"""
Auto-Sub Python Backend
從 stdin 讀取 PCM 音訊，輸出翻譯後的字幕到 stdout
"""

import sys
import os
import json
import asyncio
from transcriber import Transcriber
from translator import Translator

# 確保即時輸出
sys.stdout.reconfigure(line_buffering=True)

# 音訊格式常數
SAMPLE_RATE = 24000
CHANNELS = 2
BYTES_PER_SAMPLE = 2
CHUNK_DURATION_MS = 100
CHUNK_SIZE = SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE * CHUNK_DURATION_MS // 1000


def output_json(data: dict):
    """輸出 JSON 到 stdout"""
    print(json.dumps(data, ensure_ascii=False), flush=True)


async def main():
    # 從環境變數讀取設定
    deepgram_key = os.environ.get("DEEPGRAM_API_KEY")
    gemini_key = os.environ.get("GEMINI_API_KEY")
    source_lang = os.environ.get("SOURCE_LANGUAGE", "ja")

    if not deepgram_key or not gemini_key:
        output_json({"type": "error", "message": "Missing API keys", "code": "CONFIG_ERROR"})
        sys.exit(1)

    # 初始化翻譯器
    translator = Translator(api_key=gemini_key)

    # 翻譯回呼（含重試）
    async def on_transcript(text: str):
        max_retries = 3
        for attempt in range(max_retries):
            try:
                translated = translator.translate(text)
                if translated:
                    output_json({
                        "type": "subtitle",
                        "original": text,
                        "translation": translated
                    })
                    return
            except Exception as e:
                if attempt == max_retries - 1:
                    output_json({
                        "type": "error",
                        "message": f"Translation failed: {str(e)}",
                        "code": "TRANSLATE_ERROR"
                    })

    # 初始化轉錄器
    async with Transcriber(
        api_key=deepgram_key,
        language=source_lang,
        on_transcript=on_transcript
    ) as transcriber:
        output_json({"type": "status", "status": "connected"})

        # 從 stdin 讀取音訊
        while True:
            try:
                audio_data = sys.stdin.buffer.read(CHUNK_SIZE)
                if not audio_data:
                    break
                await transcriber.send_audio(audio_data)
            except Exception as e:
                output_json({
                    "type": "error",
                    "message": str(e),
                    "code": "AUDIO_ERROR"
                })
                break


if __name__ == "__main__":
    asyncio.run(main())
```

### JSON Protocol

**Swift → Python (stdin)**：原始 PCM 音訊資料（二進位）

**Python → Swift (stdout)**：JSON Lines 格式

```json
{"type": "subtitle", "original": "こんにちは", "translation": "你好"}
{"type": "status", "status": "connected"}
{"type": "error", "message": "API connection failed", "code": "DEEPGRAM_ERROR"}
```

### requirements.txt

```
deepgram-sdk>=5.3.2
google-genai>=1.61.0
python-dotenv>=1.2.1
```

## Verification

### 測試命令

```bash
cd AutoSub/AutoSub/Resources/backend

# 建立測試用虛擬環境
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 設定環境變數
export DEEPGRAM_API_KEY="your-key"
export GEMINI_API_KEY="your-key"

# 使用測試音訊（需準備一個 PCM 音訊檔）
cat test_audio.pcm | python3 main.py
```

### Expected Outcomes

- [ ] `main.py` 可從 stdin 讀取二進位資料
- [ ] 連線成功後輸出 `{"type": "status", "status": "connected"}`
- [ ] 辨識到文字後輸出 `{"type": "subtitle", ...}`
- [ ] 錯誤時輸出 `{"type": "error", ...}`
- [ ] 翻譯失敗會重試 3 次

## Files Created/Modified

- `AutoSub/AutoSub/Resources/backend/main.py` (new)
- `AutoSub/AutoSub/Resources/backend/transcriber.py` (new - 從 PoC 複製調整)
- `AutoSub/AutoSub/Resources/backend/translator.py` (new - 從 PoC 複製調整)
- `AutoSub/AutoSub/Resources/backend/requirements.txt` (new)

## Notes

### PoC 程式碼差異

| 項目 | PoC | 正式版 |
|------|-----|--------|
| 音訊來源 | systemAudioDump subprocess | stdin |
| 輸出方式 | print/console | JSON Lines stdout |
| 錯誤處理 | 簡單 | 結構化 error JSON |

### 音訊格式

- Sample Rate: 24000 Hz
- Channels: 2 (Stereo)
- Bit Depth: 16-bit
- Chunk Size: 24000 * 2 * 2 * 100 / 1000 = 9600 bytes per 100ms

### 安全性考量

- 不在 stdout 輸出包含 API Key 的錯誤訊息
- 使用 error code 而非 raw exception message
