#!/usr/bin/env python3
"""
Auto-Sub Python Backend
從 stdin 讀取 PCM 音訊，輸出翻譯後的字幕到 stdout

協議：
- 輸入 (stdin)：二進位 PCM 音訊 (24kHz, 16-bit, stereo)
- 輸出 (stdout)：JSON Lines 格式
"""

import sys
import os
import json
from transcriber import Transcriber
from translator import Translator

# 確保即時輸出
sys.stdout.reconfigure(line_buffering=True)

# 音訊格式常數
SAMPLE_RATE = 24000
CHANNELS = 2
BYTES_PER_SAMPLE = 2
CHUNK_DURATION_MS = 100
CHUNK_SIZE = SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE * CHUNK_DURATION_MS // 1000  # 9600 bytes


def output_json(data: dict):
    """輸出 JSON 到 stdout"""
    print(json.dumps(data, ensure_ascii=False), flush=True)


def main():
    """主程式"""
    # 從環境變數讀取設定
    deepgram_key = os.environ.get("DEEPGRAM_API_KEY")
    gemini_key = os.environ.get("GEMINI_API_KEY")
    source_lang = os.environ.get("SOURCE_LANGUAGE", "ja")

    if not deepgram_key or not gemini_key:
        output_json({
            "type": "error",
            "message": "Missing API keys",
            "code": "CONFIG_ERROR"
        })
        sys.exit(1)

    # 初始化翻譯器
    translator = Translator(api_key=gemini_key)

    # 翻譯回呼（含重試）
    def on_transcript(text: str):
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
            except Exception:
                if attempt == max_retries - 1:
                    output_json({
                        "type": "error",
                        "message": "Translation failed",
                        "code": "TRANSLATE_ERROR"
                    })

    # 初始化轉錄器並開始處理
    try:
        with Transcriber(
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
                    transcriber.send_audio(audio_data)
                except Exception as e:
                    output_json({
                        "type": "error",
                        "message": str(e),
                        "code": "AUDIO_ERROR"
                    })
                    break

    except Exception:
        output_json({
            "type": "error",
            "message": "Failed to connect to speech service",
            "code": "DEEPGRAM_ERROR"
        })
        sys.exit(1)


if __name__ == "__main__":
    main()
