"""
Deepgram 即時語音轉文字模組
使用 Deepgram SDK v5.3.2
基於 PoC 驗證成功的同步實作
"""

import sys
import threading
import time
import uuid
from typing import Callable, Optional

from deepgram import DeepgramClient
from deepgram.core.events import EventType
from deepgram.extensions.types.sockets import (
    ListenV1ControlMessage,
    ListenV1MediaMessage,
)


class Transcriber:
    """
    Deepgram 即時轉錄器

    使用 context manager 模式：
        with Transcriber(api_key, on_transcript=callback) as t:
            t.send_audio(data)
    """

    KEEPALIVE_INTERVAL_SEC = 3.0
    AUDIO_IDLE_THRESHOLD_SEC = 2.0
    WATCHDOG_TICK_SEC = 0.5
    INCOMPLETE_SUFFIX = " [暫停]"

    def __init__(
        self,
        api_key: str,
        language: str = "ja",
        on_transcript: Optional[Callable[..., None]] = None,
        on_interim: Optional[Callable[[str], None]] = None,
        on_error: Optional[Callable[..., None]] = None,
        endpointing_ms: int = 200,
        utterance_end_ms: int = 1000,
        max_buffer_chars: int = 50,
        interim_stale_timeout_sec: float = 4.0,
        keyterms: Optional[list[str]] = None,
    ):
        """
        初始化轉錄器

        Args:
            api_key: Deepgram API Key
            language: 語言代碼 (預設 "ja" 日語)
            on_transcript: 轉錄完成回呼，支援兩種簽名：
                           - (id: str, text: str) -> None（無前句資訊）
                           - (id: str, text: str, prev_id: str|None, prev_text: str|None, prev_translation: str|None) -> None
            on_interim: 即時結果回呼 (text: str) -> None，顯示正在說的話
            on_error: 錯誤回呼，支援兩種簽名：
                      - (message: str) -> None
                      - (message: str, detail_code: str|None) -> None
            endpointing_ms: 靜音判定時間 (毫秒)，預設 200ms（減半以縮短延遲）
            utterance_end_ms: utterance 超時時間 (毫秒)，預設 1000ms（Deepgram 最小值為 1000）
            max_buffer_chars: 最大累積字數，預設 50（減少 38%）
            interim_stale_timeout_sec: interim 無更新超過此秒數即落地為 [暫停]，預設 4.0 秒
            keyterms: Deepgram keyterm 提示詞清單（可為 None）
        """
        self.api_key = api_key
        self.language = language
        self.on_transcript = on_transcript
        self.on_interim = on_interim
        self.on_error = on_error
        self.endpointing_ms = endpointing_ms
        self.utterance_end_ms = utterance_end_ms
        self._interim_stale_timeout_sec = interim_stale_timeout_sec
        self.keyterms = keyterms or []

        self._client: Optional[DeepgramClient] = None
        self._context_manager = None
        self._connection = None
        self._listener_thread: Optional[threading.Thread] = None
        self._keepalive_thread: Optional[threading.Thread] = None
        self._keepalive_stop_event = threading.Event()
        self._state_lock = threading.Lock()
        self._running = False
        self._start_time: float = 0
        self._last_audio_sent_at: float = 0
        self._last_keepalive_sent_at: float = 0
        self._last_interim_text: Optional[str] = None
        self._last_interim_updated_at: float = 0
        self._utterance_buffer: list[str] = []  # 累積 buffer
        self._max_buffer_chars: int = max_buffer_chars  # 最大累積字數，超過就強制 flush

        # Phase 2: 追蹤前一句資訊（用於上下文修正）
        # 格式: (id, text, translation)
        self._previous_transcript: Optional[tuple[str, str, Optional[str]]] = None

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
        connect_kwargs = dict(
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
        if self.keyterms:
            connect_kwargs["keyterm"] = self.keyterms
        self._context_manager = self._client.listen.v1.connect(**connect_kwargs)
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

        now = time.time()
        self._last_audio_sent_at = now
        self._last_keepalive_sent_at = now
        self._clear_interim_state()
        self._keepalive_stop_event.clear()
        self._keepalive_thread = threading.Thread(target=self._keepalive_loop, daemon=True)
        self._keepalive_thread.start()

        self._listener_thread = threading.Thread(target=listen_loop, daemon=True)
        self._listener_thread.start()

        # 等待連線建立
        time.sleep(0.1)

    def stop(self) -> None:
        """停止 Deepgram 連線"""
        self._running = False
        self._keepalive_stop_event.set()
        if self._keepalive_thread and self._keepalive_thread.is_alive():
            self._keepalive_thread.join(timeout=0.5)
        self._keepalive_thread = None
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
                self._last_audio_sent_at = time.time()
            except Exception:
                pass  # 連線已關閉時忽略

    def _keepalive_loop(self) -> None:
        """在無音訊期間送 keepalive，並將長時間卡住的 interim 強制落地。"""
        while self._running and not self._keepalive_stop_event.wait(self.WATCHDOG_TICK_SEC):
            stale_interim = self._take_stale_interim_text()
            if stale_interim:
                self._emit_incomplete_transcript(stale_interim)

            if not self._connection:
                continue

            idle_seconds = time.time() - self._last_audio_sent_at
            if idle_seconds < self.AUDIO_IDLE_THRESHOLD_SEC:
                continue

            try:
                now = time.time()
                if now - self._last_keepalive_sent_at < self.KEEPALIVE_INTERVAL_SEC:
                    continue
                self._connection.send_control(ListenV1ControlMessage(type="KeepAlive"))
                self._last_keepalive_sent_at = now
            except Exception as e:
                if self._running:
                    self._report_error(e)
                return

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
                            self._clear_interim_state()
                            # 累積到 buffer
                            self._utterance_buffer.append(transcript)
                            buffer_chars = sum(len(t) for t in self._utterance_buffer)
                            print(f"[Transcriber] Added to buffer (items: {len(self._utterance_buffer)}, chars: {buffer_chars})", file=sys.stderr, flush=True)

                            # 超過最大字數限制，強制 flush
                            if buffer_chars >= self._max_buffer_chars:
                                print(f"[Transcriber] Max buffer chars reached, forced flush", file=sys.stderr, flush=True)
                                self._flush_buffer()

                            # speech_final=True 表示說話者停頓，flush buffer
                            if speech_final and self._utterance_buffer:
                                print(f"[Transcriber] speech_final triggered flush", file=sys.stderr, flush=True)
                                self._flush_buffer()
                        else:
                            # is_final=False：輸出 interim result（buffer + 當前 interim）
                            buffer_text = "".join(self._utterance_buffer)
                            combined = buffer_text + transcript
                            self._update_interim_state(combined)
                            if self.on_interim:
                                self.on_interim(combined)
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
        self._clear_interim_state()

        full_transcript = "".join(self._utterance_buffer)
        self._utterance_buffer.clear()

        print(f"[Transcriber] FLUSH - Sending to callback: {full_transcript}", file=sys.stderr, flush=True)
        if self.on_transcript and full_transcript.strip():
            # 生成 UUID 並傳給回呼
            transcript_id = str(uuid.uuid4())
            previous = self._previous_transcript

            # 先記錄當前句，讓 callback 內 update_previous_translation()
            # 可以正確更新到「當前句」的 translation。
            self._previous_transcript = (transcript_id, full_transcript, None)

            # Phase 2: 傳遞前一句資訊（若有）
            if previous:
                prev_id, prev_text, prev_translation = previous
                self.on_transcript(
                    transcript_id, full_transcript,
                    prev_id, prev_text, prev_translation
                )
            else:
                # 第一句或無前句資訊時
                self.on_transcript(
                    transcript_id, full_transcript,
                    None, None, None
                )

    def _emit_incomplete_transcript(self, text: str) -> None:
        """將長時間卡住的 interim 強制落地為未完成句，進入正常翻譯流程。"""
        if not self.on_transcript:
            return

        trimmed = text.strip()
        if not trimmed:
            return

        full_transcript = trimmed + self.INCOMPLETE_SUFFIX
        transcript_id = str(uuid.uuid4())
        previous = self._previous_transcript
        self._previous_transcript = (transcript_id, full_transcript, None)

        if previous:
            prev_id, prev_text, prev_translation = previous
            self.on_transcript(
                transcript_id, full_transcript,
                prev_id, prev_text, prev_translation
            )
        else:
            self.on_transcript(
                transcript_id, full_transcript,
                None, None, None
            )

    def _update_interim_state(self, text: str) -> None:
        with self._state_lock:
            self._last_interim_text = text
            self._last_interim_updated_at = time.time()

    def _clear_interim_state(self) -> None:
        with self._state_lock:
            self._last_interim_text = None
            self._last_interim_updated_at = 0

    def _take_stale_interim_text(self) -> Optional[str]:
        with self._state_lock:
            if not self._last_interim_text:
                return None
            if time.time() - self._last_interim_updated_at < self._interim_stale_timeout_sec:
                return None

            text = self._last_interim_text
            self._last_interim_text = None
            self._last_interim_updated_at = 0
            return text

    def update_previous_translation(self, translation: str) -> None:
        """更新前一句的翻譯結果（由 main.py 呼叫）"""
        if self._previous_transcript:
            prev_id, prev_text, _ = self._previous_transcript
            self._previous_transcript = (prev_id, prev_text, translation)

    def _on_error(self, error) -> None:
        """處理錯誤"""
        if self._running:
            print(f"[Deepgram Error] {error}", file=sys.stderr)
            self._report_error(error)

    @staticmethod
    def _extract_detail_code(error_text: str) -> Optional[str]:
        lowered = error_text.lower()
        if "net0001" in lowered or "did not receive audio data" in lowered:
            return "NET0001_IDLE_TIMEOUT"
        return None

    def _report_error(self, error) -> None:
        if not self.on_error:
            return

        error_text = str(error)
        detail_code = self._extract_detail_code(error_text)
        try:
            self.on_error(error_text, detail_code)
        except TypeError:
            self.on_error(error_text)

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()
