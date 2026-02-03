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
    target_lang = os.environ.get("TARGET_LANGUAGE", "zh-TW")
    gemini_model = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash-lite-preview-09-2025")
    translation_context = os.environ.get("TRANSLATION_CONTEXT", "")
    keyterms_raw = os.environ.get("DEEPGRAM_KEYTERMS", "")
    keyterms = [line.strip() for line in keyterms_raw.splitlines() if line.strip()]

    # Deepgram 斷句設定（Phase 1 調整後的新預設值）
    endpointing_ms = int(os.environ.get("DEEPGRAM_ENDPOINTING_MS", "200"))
    utterance_end_ms = int(os.environ.get("DEEPGRAM_UTTERANCE_END_MS", "1000"))
    max_buffer_chars = int(os.environ.get("DEEPGRAM_MAX_BUFFER_CHARS", "50"))

    # 新增：Gemini Context 設定（有預設值）
    max_context_tokens = int(os.environ.get("GEMINI_MAX_CONTEXT_TOKENS", "20000"))

    print(f"[Python] API keys present: deepgram={bool(deepgram_key)}, gemini={bool(gemini_key)}", file=sys.stderr, flush=True)
    print(f"[Python] Deepgram config: endpointing_ms={endpointing_ms}, utterance_end_ms={utterance_end_ms}, max_buffer_chars={max_buffer_chars}", file=sys.stderr, flush=True)
    print(f"[Python] Deepgram keyterms: {len(keyterms)} items", file=sys.stderr, flush=True)
    print(
        f"[Python] Gemini config: model={gemini_model}, max_context_tokens={max_context_tokens}",
        file=sys.stderr,
        flush=True,
    )
    if translation_context.strip():
        print(f"[Python] Translation context length: {len(translation_context)}", file=sys.stderr, flush=True)

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
        model=gemini_model,
        source_language=source_lang,
        target_language=target_lang,
        max_context_tokens=max_context_tokens,
        translation_context=translation_context,
    )
    print("[Python] Translator initialized", file=sys.stderr, flush=True)

    # Interim 回呼（即時顯示正在說的話）
    def on_interim(text: str):
        output_json({
            "type": "interim",
            "text": text
        })

    # 儲存 transcriber 參考（用於更新前句翻譯）
    transcriber_ref = [None]

    # Phase 2: 翻譯回呼（支援上下文修正）
    def on_transcript(
        transcript_id: str,
        text: str,
        prev_id: str | None = None,
        prev_text: str | None = None,
        prev_translation: str | None = None
    ):
        print(f"[Python] on_transcript called with id={transcript_id}, text={text}", file=sys.stderr, flush=True)
        if prev_id:
            print(f"[Python] Previous context: prev_id={prev_id}, prev_text={prev_text}, prev_translation={prev_translation}", file=sys.stderr, flush=True)

        # 1. 立即送出原文（翻譯中狀態）
        output_json({
            "type": "transcript",
            "id": transcript_id,
            "text": text
        })
        print(f"[Python] Transcript sent to stdout!", file=sys.stderr, flush=True)

        # 2. 進行翻譯（帶上下文修正）
        max_retries = 3
        translation_success = False

        for attempt in range(max_retries):
            try:
                print(f"[Python] Translating with context (attempt {attempt + 1})...", file=sys.stderr, flush=True)

                # 使用上下文修正翻譯
                current_trans, prev_correction = translator.translate_with_context_correction(
                    text, prev_text, prev_translation
                )

                print(f"[Python] Translation result: current={current_trans}, correction={prev_correction}", file=sys.stderr, flush=True)

                # 確保 current_trans 是有效字串
                if current_trans and isinstance(current_trans, str) and current_trans.strip():
                    # 3. 送出當前翻譯結果
                    output_json({
                        "type": "subtitle",
                        "id": transcript_id,
                        "original": text,
                        "translation": current_trans
                    })
                    print(f"[Python] Subtitle sent to stdout!", file=sys.stderr, flush=True)

                    # 4. 若有前句修正，送出更新
                    if prev_correction and prev_id:
                        output_json({
                            "type": "translation_update",
                            "id": prev_id,
                            "translation": prev_correction
                        })
                        print(f"[Python] Translation update sent for prev_id={prev_id}!", file=sys.stderr, flush=True)

                    # 5. 更新 transcriber 的前句翻譯記錄
                    if transcriber_ref[0]:
                        transcriber_ref[0].update_previous_translation(current_trans)

                    translation_success = True
                    return
                else:
                    # 翻譯結果為空或無效，視為需要重試
                    print(f"[Python] Empty or invalid translation result, retrying...", file=sys.stderr, flush=True)
                    continue

            except Exception as e:
                print(f"[Python] Translation error: {e}", file=sys.stderr, flush=True)

        # 重試結束仍未成功，送出失敗字幕（帶 id 讓 UI 不會卡在「翻譯中…」）
        if not translation_success:
            print(f"[Python] Translation failed after {max_retries} attempts", file=sys.stderr, flush=True)
            # 送出帶 id 的失敗字幕，讓 UI 可以更新該條目
            output_json({
                "type": "subtitle",
                "id": transcript_id,
                "original": text,
                "translation": "[翻譯失敗]"
            })
            # 同時送出錯誤通知
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
            max_buffer_chars=max_buffer_chars,
            keyterms=keyterms,
        ) as transcriber:
            # 儲存 transcriber 參考
            transcriber_ref[0] = transcriber
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

    except Exception as e:
        print(f"[Python] Deepgram connection error: {type(e).__name__}: {e}", file=sys.stderr, flush=True)
        import traceback
        traceback.print_exc(file=sys.stderr)
        output_json({
            "type": "error",
            "message": f"Failed to connect to speech service: {e}",
            "code": "DEEPGRAM_ERROR"
        })
        sys.exit(1)


if __name__ == "__main__":
    main()
