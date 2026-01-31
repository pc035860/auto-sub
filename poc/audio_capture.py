"""音訊擷取模組 - 使用 systemAudioDump 擷取系統音訊"""

import subprocess
from pathlib import Path
from typing import Generator

SYSTEM_AUDIO_DUMP_PATH = Path(__file__).parent / "systemAudioDump" / ".build" / "release" / "SystemAudioDump"

# systemAudioDump 輸出格式：16-bit int, 24000 Hz, 2 channels, interleaved
SAMPLE_RATE = 24000
CHANNELS = 2
BYTES_PER_SAMPLE = 2  # 16-bit int
CHUNK_DURATION_MS = 100  # 每次讀取 100ms 的音訊
CHUNK_SIZE = int(SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE * CHUNK_DURATION_MS / 1000)


class AudioCapture:
    def __init__(self):
        self.process: subprocess.Popen | None = None

    def start(self) -> None:
        if not SYSTEM_AUDIO_DUMP_PATH.exists():
            raise FileNotFoundError(f"systemAudioDump not found at {SYSTEM_AUDIO_DUMP_PATH}")

        self.process = subprocess.Popen(
            [str(SYSTEM_AUDIO_DUMP_PATH)],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )

    def stop(self) -> None:
        if self.process:
            self.process.terminate()
            self.process.wait()
            self.process = None

    def read_chunks(self) -> Generator[bytes, None, None]:
        if not self.process or not self.process.stdout:
            raise RuntimeError("AudioCapture not started")

        while True:
            chunk = self.process.stdout.read(CHUNK_SIZE)
            if not chunk:
                break
            yield chunk

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()
