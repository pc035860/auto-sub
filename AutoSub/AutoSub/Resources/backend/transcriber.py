"""
Deepgram 即時語音轉文字模組
使用 Deepgram SDK v5.3.2
基於 PoC 驗證成功的同步實作
"""

import sys
import threading
import time
from typing import Callable, Optional

from deepgram import DeepgramClient
from deepgram.core.events import EventType
from deepgram.extensions.types.sockets import ListenV1MediaMessage


class Transcriber:
    """
    Deepgram 即時轉錄器

    使用 context manager 模式：
        with Transcriber(api_key, on_transcript=callback) as t:
            t.send_audio(data)
    """

    def __init__(
        self,
        api_key: str,
        language: str = "ja",
        on_transcript: Optional[Callable[[str], None]] = None,
        endpointing_ms: int = 300,
    ):
        """
        初始化轉錄器

        Args:
            api_key: Deepgram API Key
            language: 語言代碼 (預設 "ja" 日語)
            on_transcript: 轉錄完成回呼
            endpointing_ms: 靜音判定時間 (毫秒)
        """
        self.api_key = api_key
        self.language = language
        self.on_transcript = on_transcript
        self.endpointing_ms = endpointing_ms

        self._client: Optional[DeepgramClient] = None
        self._context_manager = None
        self._connection = None
        self._listener_thread: Optional[threading.Thread] = None
        self._running = False
        self._start_time: float = 0

    def start(self) -> None:
        """啟動 Deepgram 連線"""
        self._start_time = time.time()
        self._running = True

        # 建立客戶端
        self._client = DeepgramClient(api_key=self.api_key)

        # 建立 WebSocket 連線
        self._context_manager = self._client.listen.v1.connect(
            model="nova-2",
            language=self.language,
            smart_format=True,
            interim_results=True,
            endpointing=self.endpointing_ms,
            encoding="linear16",
            sample_rate=24000,
            channels=2,
        )
        self._connection = self._context_manager.__enter__()

        # 註冊事件處理
        self._connection.on(EventType.MESSAGE, self._on_message)
        self._connection.on(EventType.ERROR, self._on_error)

        # 在背景線程中運行監聽
        def listen_loop():
            try:
                self._connection.start_listening()
            except Exception as e:
                if self._running:
                    print(f"[Listener Error] {e}", file=sys.stderr)

        self._listener_thread = threading.Thread(target=listen_loop, daemon=True)
        self._listener_thread.start()

        # 等待連線建立
        time.sleep(0.1)

    def stop(self) -> None:
        """停止 Deepgram 連線"""
        self._running = False
        if self._context_manager:
            try:
                self._context_manager.__exit__(None, None, None)
            except Exception:
                pass
            self._context_manager = None
            self._connection = None

    def send_audio(self, audio_data: bytes) -> None:
        """發送音訊資料到 Deepgram"""
        if self._connection and self._running:
            try:
                self._connection.send_media(ListenV1MediaMessage(audio_data))
            except Exception:
                pass  # 連線已關閉時忽略

    def _on_message(self, message) -> None:
        """處理轉錄訊息"""
        msg_type = getattr(message, "type", "Unknown")
        if msg_type == "Results":
            channel = getattr(message, "channel", None)
            if channel:
                alternatives = getattr(channel, "alternatives", [])
                if alternatives:
                    transcript = getattr(alternatives[0], "transcript", "")
                    is_final = getattr(message, "is_final", False)
                    if transcript.strip() and is_final:
                        if self.on_transcript:
                            self.on_transcript(transcript)

    def _on_error(self, error) -> None:
        """處理錯誤"""
        if self._running:
            print(f"[Deepgram Error] {error}", file=sys.stderr)

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()
