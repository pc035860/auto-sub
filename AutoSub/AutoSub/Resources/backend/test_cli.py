#!/usr/bin/env python3
"""
快速驗證腳本 - 直接測試改進效果，無需編譯 Swift UI

用法:
    cd AutoSub/AutoSub/Resources/backend
    DEEPGRAM_API_KEY=xxx GEMINI_API_KEY=xxx python test_cli.py

需要: poc/systemAudioDump 已編譯
"""

import os
import signal
import subprocess
import sys
import time

from transcriber import Transcriber
from translator import Translator

# 音訊格式常數
SAMPLE_RATE = 24000
CHANNELS = 2
BYTES_PER_SAMPLE = 2
CHUNK_DURATION_MS = 100
CHUNK_SIZE = SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE * CHUNK_DURATION_MS // 1000


class TestCLI:
    def __init__(self):
        self.deepgram_key = os.environ.get("DEEPGRAM_API_KEY")
        self.gemini_key = os.environ.get("GEMINI_API_KEY")

        if not self.deepgram_key or not self.gemini_key:
            print("錯誤: 請設定 DEEPGRAM_API_KEY 和 GEMINI_API_KEY 環境變數")
            sys.exit(1)

        self.translator = Translator(
            api_key=self.gemini_key,
            max_context_tokens=100_000,
        )
        self.running = False
        self.count = 0
        self.start_time = 0.0

    def on_transcript(self, text: str) -> None:
        """處理轉錄結果"""
        self.count += 1
        elapsed = time.time() - self.start_time

        print(f"\n[#{self.count}] @ {elapsed:.1f}s ─────────────────")
        print(f"原文：{text}")

        try:
            translated = self.translator.translate(text)
            print(f"翻譯：{translated}")
        except Exception as e:
            print(f"翻譯錯誤：{e}")

    def run(self) -> None:
        self.running = True
        self.start_time = time.time()

        # 找到 systemAudioDump
        script_dir = os.path.dirname(os.path.abspath(__file__))
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(script_dir))))
        dump_path = os.path.join(project_root, "poc/systemAudioDump/.build/release/systemAudioDump")

        if not os.path.exists(dump_path):
            print(f"錯誤: 找不到 systemAudioDump，請先編譯:")
            print(f"  cd {project_root}/poc/systemAudioDump && swift build -c release")
            sys.exit(1)

        print("=" * 50)
        print("翻譯斷句改進測試")
        print("=" * 50)
        print(f"endpointing_ms: 400, utterance_end_ms: 1200")
        print(f"Gemini Context: 啟用 (max_context_tokens=100K, 隱式快取)")
        print("等待系統音訊... (按 Ctrl+C 停止)")
        print()

        # 啟動 systemAudioDump
        audio_proc = subprocess.Popen(
            [dump_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )

        with Transcriber(
            api_key=self.deepgram_key,
            language="ja",
            on_transcript=self.on_transcript,
            endpointing_ms=400,
            utterance_end_ms=1200,
        ) as transcriber:
            try:
                while self.running:
                    chunk = audio_proc.stdout.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    transcriber.send_audio(chunk)
            except KeyboardInterrupt:
                print("\n\n停止中...")
            finally:
                audio_proc.terminate()

        print("完成！")


def main():
    cli = TestCLI()

    def signal_handler(sig, frame):
        cli.running = False

    signal.signal(signal.SIGINT, signal_handler)
    cli.run()


if __name__ == "__main__":
    main()
