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
    print("[Python] main() started", file=sys.stderr, flush=True)

    # 從環境變數讀取設定
    deepgram_key = os.environ.get("DEEPGRAM_API_KEY")
    gemini_key = os.environ.get("GEMINI_API_KEY")
    source_lang = os.environ.get("SOURCE_LANGUAGE", "ja")

    # 新增：Deepgram 斷句設定（有預設值）
    endpointing_ms = int(os.environ.get("DEEPGRAM_ENDPOINTING_MS", "400"))
    utterance_end_ms = int(os.environ.get("DEEPGRAM_UTTERANCE_END_MS", "1200"))

    # 新增：Gemini Context 設定（有預設值）
    max_context_tokens = int(os.environ.get("GEMINI_MAX_CONTEXT_TOKENS", "100000"))

    print(f"[Python] API keys present: deepgram={bool(deepgram_key)}, gemini={bool(gemini_key)}", file=sys.stderr, flush=True)
    print(f"[Python] Deepgram config: endpointing_ms={endpointing_ms}, utterance_end_ms={utterance_end_ms}", file=sys.stderr, flush=True)
    print(f"[Python] Gemini config: max_context_tokens={max_context_tokens}", file=sys.stderr, flush=True)

    if not deepgram_key or not gemini_key:
        output_json({
            "type": "error",
            "message": "Missing API keys",
            "code": "CONFIG_ERROR"
        })
        sys.exit(1)

    # 初始化翻譯器
    print("[Python] Initializing translator...", file=sys.stderr, flush=True)
    translator = Translator(
        api_key=gemini_key,
        max_context_tokens=max_context_tokens,
    )
    print("[Python] Translator initialized", file=sys.stderr, flush=True)

    # Interim 回呼（即時顯示正在說的話）
    def on_interim(text: str):
        output_json({
            "type": "interim",
            "text": text
        })

    # 翻譯回呼（含重試）
    def on_transcript(transcript_id: str, text: str):
        print(f"[Python] on_transcript called with id={transcript_id}, text={text}", file=sys.stderr, flush=True)

        # 1. 立即送出原文（翻譯中狀態）
        output_json({
            "type": "transcript",
            "id": transcript_id,
            "text": text
        })
        print(f"[Python] Transcript sent to stdout!", file=sys.stderr, flush=True)

        # 2. 進行翻譯
        max_retries = 3
        for attempt in range(max_retries):
            try:
                print(f"[Python] Translating (attempt {attempt + 1})...", file=sys.stderr, flush=True)
                translated = translator.translate(text)
                print(f"[Python] Translation result: {translated}", file=sys.stderr, flush=True)
                if translated:
                    # 3. 送出翻譯結果
                    output_json({
                        "type": "subtitle",
                        "id": transcript_id,
                        "original": text,
                        "translation": translated
                    })
                    print(f"[Python] Subtitle sent to stdout!", file=sys.stderr, flush=True)
                    return
            except Exception as e:
                print(f"[Python] Translation error: {e}", file=sys.stderr, flush=True)
                if attempt == max_retries - 1:
                    output_json({
                        "type": "error",
                        "message": "Translation failed",
                        "code": "TRANSLATE_ERROR"
                    })

    # 初始化轉錄器並開始處理
    print("[Python] Initializing transcriber...", file=sys.stderr, flush=True)
    try:
        with Transcriber(
            api_key=deepgram_key,
            language=source_lang,
            on_transcript=on_transcript,
            on_interim=on_interim,
            endpointing_ms=endpointing_ms,
            utterance_end_ms=utterance_end_ms,
        ) as transcriber:
            print("[Python] Transcriber connected!", file=sys.stderr, flush=True)
            output_json({"type": "status", "status": "connected"})
            print("[Python] Now reading audio from stdin...", file=sys.stderr, flush=True)

            # 從 stdin 讀取音訊
            audio_chunks_received = 0
            while True:
                try:
                    audio_data = sys.stdin.buffer.read(CHUNK_SIZE)
                    if not audio_data:
                        print("[Python] stdin EOF received, exiting...", file=sys.stderr, flush=True)
                        break
                    audio_chunks_received += 1
                    if audio_chunks_received % 100 == 1:  # 每 100 chunks 輸出一次
                        print(f"[Python] Audio chunks received: {audio_chunks_received}", file=sys.stderr, flush=True)
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
