#!/usr/bin/env python3
"""
即時系統音訊字幕翻譯 PoC

流程：系統音訊（日語） → Deepgram 轉文字 → Gemini 翻譯 → 終端機顯示
"""

import signal
import sys
import time

# 強制無緩衝輸出，確保即時顯示
sys.stdout.reconfigure(line_buffering=True)

from dotenv import load_dotenv

from audio_capture import AudioCapture
from transcriber import Transcriber
from translator import Translator

load_dotenv()


class SubtitlePipeline:
    def __init__(self):
        self.translator = Translator()
        self.running = False
        self.transcript_count = 0
        self.start_time = 0.0

    def on_transcript(self, text: str, audio_ts: float) -> None:
        """處理轉錄結果"""
        self.transcript_count += 1

        # 翻譯
        translated, translate_elapsed = self.translator.translate(text)

        # 計算延遲
        total_elapsed = time.time() - self.start_time - audio_ts

        # 顯示結果
        print()
        print(f"[#{self.transcript_count}] ───────────────────────────────────")
        print(f"原文：{text}")
        print(f"翻譯：{translated}")
        print(f"翻譯延遲: {translate_elapsed:.2f}s | 總延遲: {total_elapsed:.2f}s")

    def run(self) -> None:
        self.running = True
        self.start_time = time.time()

        print("=" * 50)
        print("即時字幕翻譯 PoC")
        print("=" * 50)
        print("等待系統音訊... (按 Ctrl+C 停止)")
        print()

        with AudioCapture() as audio:
            with Transcriber(self.on_transcript) as transcriber:
                try:
                    for chunk in audio.read_chunks():
                        if not self.running:
                            break
                        transcriber.send_audio(chunk)
                except KeyboardInterrupt:
                    print("\n\n停止中...")

        print("完成！")


def main():
    pipeline = SubtitlePipeline()

    def signal_handler(sig, frame):
        pipeline.running = False

    signal.signal(signal.SIGINT, signal_handler)
    pipeline.run()


if __name__ == "__main__":
    main()
