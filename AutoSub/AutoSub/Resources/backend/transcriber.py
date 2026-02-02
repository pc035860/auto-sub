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
        endpointing_ms: int = 400,
        utterance_end_ms: int = 1200,
    ):
        """
        初始化轉錄器

        Args:
            api_key: Deepgram API Key
            language: 語言代碼 (預設 "ja" 日語)
            on_transcript: 轉錄完成回呼
            endpointing_ms: 靜音判定時間 (毫秒)，預設 400ms（日語句子較長）
            utterance_end_ms: utterance 超時時間 (毫秒)，預設 1200ms
        """
        self.api_key = api_key
        self.language = language
        self.on_transcript = on_transcript
        self.endpointing_ms = endpointing_ms
        self.utterance_end_ms = utterance_end_ms

        self._client: Optional[DeepgramClient] = None
        self._context_manager = None
        self._connection = None
        self._listener_thread: Optional[threading.Thread] = None
        self._running = False
        self._start_time: float = 0
        self._utterance_buffer: list[str] = []  # 累積 buffer
        self._max_buffer_chars: int = 80  # 最大累積字數，超過就強制 flush

    def start(self) -> None:
        """啟動 Deepgram 連線"""
        print("[Transcriber] start() called", file=sys.stderr, flush=True)
        self._start_time = time.time()
        self._running = True

        # 建立客戶端
        print("[Transcriber] Creating DeepgramClient...", file=sys.stderr, flush=True)
        self._client = DeepgramClient(api_key=self.api_key)
        print("[Transcriber] DeepgramClient created", file=sys.stderr, flush=True)

        # 建立 WebSocket 連線
        print("[Transcriber] Connecting to Deepgram...", file=sys.stderr, flush=True)
        self._context_manager = self._client.listen.v1.connect(
            model="nova-3",
            language=self.language,
            smart_format=True,
            interim_results=True,
            endpointing=self.endpointing_ms,
            utterance_end_ms=self.utterance_end_ms,
            vad_events=True,
            encoding="linear16",
            sample_rate=24000,
            channels=2,
        )
        print("[Transcriber] Entering context manager...", file=sys.stderr, flush=True)

        # 使用 timeout 機制來診斷連線問題
        import concurrent.futures
        def connect_with_timeout():
            return self._context_manager.__enter__()

        try:
            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(connect_with_timeout)
                self._connection = future.result(timeout=10)  # 10 秒超時
            print("[Transcriber] WebSocket connected!", file=sys.stderr, flush=True)
        except concurrent.futures.TimeoutError:
            print("[Transcriber] ERROR: Connection timed out after 10 seconds!", file=sys.stderr, flush=True)
            raise Exception("Deepgram connection timeout")

        # 註冊事件處理
        # 注意：SDK v5.x 沒有獨立的 UTTERANCE_END 事件
        # 所有訊息類型都透過 MESSAGE 事件接收，需檢查 message.type
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
        """處理轉錄訊息（SDK v5.x 所有訊息類型都透過此 callback）"""
        msg_type = getattr(message, "type", "Unknown")

        if msg_type == "Results":
            channel = getattr(message, "channel", None)
            if channel:
                alternatives = getattr(channel, "alternatives", [])
                if alternatives:
                    transcript = getattr(alternatives[0], "transcript", "")
                    is_final = getattr(message, "is_final", False)
                    speech_final = getattr(message, "speech_final", False)

                    # 只有在有 transcript 內容時才處理
                    if transcript.strip():
                        print(f"[Transcriber] transcript='{transcript}', is_final={is_final}, speech_final={speech_final}", file=sys.stderr, flush=True)

                        if is_final:
                            # 累積到 buffer
                            self._utterance_buffer.append(transcript)
                            buffer_chars = sum(len(t) for t in self._utterance_buffer)
                            print(f"[Transcriber] Added to buffer (items: {len(self._utterance_buffer)}, chars: {buffer_chars})", file=sys.stderr, flush=True)

                            # 超過最大字數限制，強制 flush
                            if buffer_chars >= self._max_buffer_chars:
                                print(f"[Transcriber] Max buffer chars reached, forced flush", file=sys.stderr, flush=True)
                                self._flush_buffer()

                        # speech_final=True 表示說話者停頓，flush buffer
                        elif speech_final and self._utterance_buffer:
                            print(f"[Transcriber] speech_final triggered flush", file=sys.stderr, flush=True)
                            self._flush_buffer()
                else:
                    print(f"[Transcriber] No alternatives in channel", file=sys.stderr, flush=True)
            else:
                print(f"[Transcriber] No channel in message", file=sys.stderr, flush=True)

        elif msg_type == "UtteranceEnd":
            # UtteranceEnd 事件：基於 utterance_end_ms 的超時觸發
            print(f"[Transcriber] UtteranceEnd event received", file=sys.stderr, flush=True)
            if self._utterance_buffer:
                print(f"[Transcriber] UtteranceEnd triggered flush", file=sys.stderr, flush=True)
                self._flush_buffer()

    def _flush_buffer(self) -> None:
        """輸出累積的 buffer 並清空"""
        if not self._utterance_buffer:
            return

        full_transcript = "".join(self._utterance_buffer)
        self._utterance_buffer.clear()

        print(f"[Transcriber] FLUSH - Sending to callback: {full_transcript}", file=sys.stderr, flush=True)
        if self.on_transcript and full_transcript.strip():
            self.on_transcript(full_transcript)

    def _on_error(self, error) -> None:
        """處理錯誤"""
        if self._running:
            print(f"[Deepgram Error] {error}", file=sys.stderr)

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()
