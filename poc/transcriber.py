"""Deepgram 即時語音轉文字模組 (SDK v5)"""

import os
import threading
import time
from typing import Callable

from deepgram import DeepgramClient
from deepgram.core.events import EventType
from deepgram.extensions.types.sockets import ListenV1MediaMessage


class Transcriber:
    def __init__(self, on_transcript: Callable[[str, float], None]):
        """
        初始化 Deepgram 轉錄器

        Args:
            on_transcript: 回調函數，接收 (transcript, audio_timestamp) 參數
        """
        api_key = os.getenv("DEEPGRAM_API_KEY")
        if not api_key:
            raise ValueError("DEEPGRAM_API_KEY not set")

        self.client = DeepgramClient(api_key=api_key)
        self._context_manager = None
        self.connection = None
        self.on_transcript = on_transcript
        self.start_time: float = 0
        self._listener_thread: threading.Thread | None = None
        self._running = False

    def start(self) -> None:
        self.start_time = time.time()
        self._running = True

        self._context_manager = self.client.listen.v1.connect(
            model="nova-2",
            language="ja",  # 日語
            smart_format=True,
            interim_results=True,
            endpointing=300,  # 300ms 靜音視為結束
            encoding="linear16",
            sample_rate=24000,
            channels=2,
        )
        self.connection = self._context_manager.__enter__()

        def on_message(message) -> None:
            msg_type = getattr(message, "type", "Unknown")
            if msg_type == "Results":
                channel = getattr(message, "channel", None)
                if channel:
                    alternatives = getattr(channel, "alternatives", [])
                    if alternatives:
                        transcript = getattr(alternatives[0], "transcript", "")
                        is_final = getattr(message, "is_final", False)
                        if transcript.strip() and is_final:
                            audio_ts = time.time() - self.start_time
                            self.on_transcript(transcript, audio_ts)

        def on_error(error) -> None:
            if self._running:  # 只在運行中才報錯
                print(f"[Deepgram Error] {error}")

        self.connection.on(EventType.MESSAGE, on_message)
        self.connection.on(EventType.ERROR, on_error)

        # 在背景線程中運行 start_listening
        def listen_loop():
            try:
                self.connection.start_listening()
            except Exception as e:
                if self._running:
                    print(f"[Listener Error] {e}")

        self._listener_thread = threading.Thread(target=listen_loop, daemon=True)
        self._listener_thread.start()

        # 給 WebSocket 一點時間建立連線
        time.sleep(0.1)

    def send_audio(self, audio_data: bytes) -> None:
        if self.connection and self._running:
            try:
                self.connection.send_media(ListenV1MediaMessage(audio_data))
            except Exception:
                pass  # 連線已關閉時忽略

    def stop(self) -> None:
        self._running = False
        if self._context_manager:
            try:
                self._context_manager.__exit__(None, None, None)
            except Exception:
                pass
            self._context_manager = None
            self.connection = None

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()
