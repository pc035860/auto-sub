"""
Gemini 翻譯模組
使用 Google GenAI SDK 1.61.0
採用 Chat Session 保持翻譯上下文一致性，最大化隱式快取效益
支援上下文修正：翻譯時可同時修正前句翻譯
"""

import concurrent.futures
import json
import sys
from typing import Optional, Tuple
from google import genai
from google.genai import types
from pydantic import BaseModel

# API 呼叫 timeout（秒）
API_TIMEOUT_SECONDS = 10


class TranslationResult(BaseModel):
    current: str
    correction: Optional[str] = None


SYSTEM_INSTRUCTION_TEMPLATE = """你是專業的{source_label}即時字幕翻譯員。請將{source_label}翻譯成{target_label}。

翻譯規則：
1. 保持原意，語句通順自然
2. 人名保留原文發音的音譯，前後文中同一人名請保持一致
3. 作品名、專有名詞使用常見譯法
4. 只輸出翻譯結果，不要加任何解釋
5. 若句子明顯不完整，可根據上下文適當補充或延續前句{keyterms_block}
注意：這是即時字幕翻譯，請參考之前的對話歷史保持翻譯一致性。{context_block}"""

SUMMARIZE_PROMPT_TEMPLATE = """請根據以上翻譯歷史，整理：
1. 人名/專有名詞對照清單（格式：{source_label} → {target_label}，每行一個）
2. 這個對話的主題或背景（一句話）

只輸出整理結果，不要其他說明。"""

CONTEXT_HANDOVER_TEMPLATE = """延續之前的翻譯工作。以下是已確定的翻譯對照和背景：

{summary}

請繼續保持翻譯一致性。"""


CONTEXT_CORRECTION_PROMPT_TEMPLATE = """翻譯以下{source_label}句子，並根據上下文判斷是否需要修正前句翻譯。

當前句子：「{current_text}」

前句原文（{source_label}）：「{prev_text}」
前句翻譯（{target_label}）：「{prev_translation}」

翻譯結果放入 "current"，若需修正前句翻譯則填入 "correction"，否則設為 null。

修正時機：
- 發現前句翻譯有誤譯或語意不通
- 當前句子提供了新的上下文使前句翻譯更清晰
- 人名/專有名詞在前句翻譯不一致
- 如果前句翻譯沒問題，correction 設為 null"""

SIMPLE_TRANSLATE_PROMPT_TEMPLATE = """翻譯以下{source_label}句子：

「{text}」

翻譯結果放入 "current"，correction 設為 null。"""


LANGUAGE_LABELS = {
    "ja": "日文",
    "en": "英文",
    "ko": "韓文",
    "zh-TW": "繁體中文",
    "zh-CN": "簡體中文",
}


class Translator:
    """Gemini 翻譯器（使用 Chat Session 保持上下文，最大化隱式快取效益）"""

    def _resolve_thinking_config(self) -> Optional[types.ThinkingConfig]:
        if self.model.startswith("gemini-3"):
            return types.ThinkingConfig(thinking_level="minimal")
        if self.model.startswith("gemini-2.5"):
            return types.ThinkingConfig(thinking_budget=0)
        return None

    def __init__(
        self,
        api_key: str,
        model: str = "gemini-2.5-flash-lite-preview-09-2025",
        source_language: str = "ja",
        target_language: str = "zh-TW",
        max_context_tokens: int = 20_000,
        translation_context: str = "",
        keyterms: Optional[list[str]] = None,
    ):
        """
        初始化翻譯器

        Args:
            api_key: Gemini API Key
            model: 模型名稱 (預設 gemini-2.5-flash-lite-preview-09-2025)
            source_language: 原文語言
            target_language: 翻譯目標語言
            max_context_tokens: 最大 context tokens 閾值 (預設 20K)
            translation_context: 翻譯背景資訊（可空）
            keyterms: 重要詞彙提示清單（可空）
        """
        self.client = genai.Client(api_key=api_key)
        self.model = model
        self.max_context_tokens = max_context_tokens
        self.source_language = source_language
        self.target_language = target_language

        source_label = LANGUAGE_LABELS.get(source_language, source_language)
        target_label = LANGUAGE_LABELS.get(target_language, target_language)

        # 處理背景資訊
        context_block = ""
        if translation_context and translation_context.strip():
            context_block = f"\n\n背景資訊：\n{translation_context.strip()}"

        # 處理 keyterms（取前 10 個，注入翻譯規則）
        keyterms_block = ""
        if keyterms:
            top_keyterms = keyterms[:10]
            keyterms_text = "、".join(top_keyterms)
            keyterms_block = f"\n6. 重要詞彙提示：{keyterms_text}，請在翻譯中保持這些詞彙的一致性。\n"

        self._system_instruction = SYSTEM_INSTRUCTION_TEMPLATE.format(
            source_label=source_label,
            target_label=target_label,
            keyterms_block=keyterms_block,
            context_block=context_block,
        )
        self._summarize_prompt = SUMMARIZE_PROMPT_TEMPLATE.format(
            source_label=source_label,
            target_label=target_label,
        )
        self._context_correction_template = CONTEXT_CORRECTION_PROMPT_TEMPLATE
        self._simple_translate_template = SIMPLE_TRANSLATE_PROMPT_TEMPLATE
        self._source_label = source_label
        self._target_label = target_label

        thinking_config = self._resolve_thinking_config()
        config_kwargs = dict(
            system_instruction=self._system_instruction,
            temperature=0.2,
            response_mime_type="application/json",
            response_schema=TranslationResult,
        )
        if thinking_config is not None:
            config_kwargs["thinking_config"] = thinking_config
        self._config = types.GenerateContentConfig(**config_kwargs)
        # Summarization 用的 plain text config（不帶 JSON schema）
        plain_kwargs = dict(
            system_instruction=self._system_instruction,
            temperature=0.2,
        )
        if thinking_config is not None:
            plain_kwargs["thinking_config"] = thinking_config
        self._plain_config = types.GenerateContentConfig(**plain_kwargs)
        self._chat = self.client.chats.create(
            model=self.model,
            config=self._config,
        )
        self._total_tokens = 0
        self._context_summary: str = ""  # 上一個 session 的摘要
        self._executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)

    def _send_message_with_timeout(self, prompt: str, timeout: int = API_TIMEOUT_SECONDS):
        """發送訊息到 chat session，帶 timeout 機制"""
        future = self._executor.submit(self._chat.send_message, prompt)
        try:
            return future.result(timeout=timeout)
        except concurrent.futures.TimeoutError:
            print(f"[Translator] API call timed out after {timeout} seconds",
                  file=sys.stderr, flush=True)
            raise TimeoutError(f"Gemini API call timed out after {timeout} seconds")

    def _send_message_stream_with_timeout(
        self,
        prompt: str,
        timeout: int = API_TIMEOUT_SECONDS,
        on_chunk=None
    ):
        """Streaming 版本，每收到 chunk 呼叫 callback，支援 timeout 和 token 追蹤

        使用 producer-consumer 模式確保 timeout 在 iterator 阻塞時也能生效。
        Timeout 後會等待 producer 收斂並重建 session，避免並發存取問題。
        """
        import time
        import threading
        import queue

        accumulated = ""
        last_chunk = None
        chunk_queue = queue.Queue()
        exception_holder = [None]  # 用 list 共享例外
        done_flag = [False]
        cancel_flag = [False]  # 用於通知 producer 取消

        # 重要：在啟動 thread 前先 capture chat reference
        # 避免 producer 在 rebuild 後存取到新的 chat
        chat_ref = self._chat

        def producer():
            """在背景執行緒中迭代 streaming response"""
            try:
                # 在呼叫 send_message_stream 前先檢查是否已取消
                if cancel_flag[0]:
                    chunk_queue.put(('cancelled', None))
                    return

                response = chat_ref.send_message_stream(prompt)
                for chunk in response:
                    # 檢查是否被取消
                    if cancel_flag[0]:
                        chunk_queue.put(('cancelled', None))
                        return
                    chunk_queue.put(('chunk', chunk))
                chunk_queue.put(('done', None))
            except Exception as e:
                if not cancel_flag[0]:  # 只在非取消狀態下記錄例外
                    exception_holder[0] = e
                    chunk_queue.put(('error', None))
            finally:
                done_flag[0] = True

        # 啟動 producer 執行緒
        thread = threading.Thread(target=producer, daemon=True)
        thread.start()
        start_time = time.time()

        try:
            # Consumer: 從 queue 取出 chunks，並檢查 timeout
            while True:
                # 檢查 timeout（即使 queue.get 阻塞也會在每次迭代檢查）
                if time.time() - start_time > timeout:
                    raise TimeoutError(f"Streaming exceeded {timeout}s")

                try:
                    # 使用短 timeout 的 get，讓我們可以定期檢查超時
                    msg_type, data = chunk_queue.get(timeout=0.1)
                except queue.Empty:
                    # Queue 空且 producer 已結束 → 異常結束
                    if done_flag[0]:
                        if exception_holder[0]:
                            raise exception_holder[0]
                        break
                    continue

                if msg_type == 'done':
                    break
                elif msg_type == 'error':
                    if exception_holder[0]:
                        raise exception_holder[0]
                    break
                elif msg_type == 'cancelled':
                    break
                elif msg_type == 'chunk':
                    chunk = data
                    chunk_text = chunk.text or ""
                    accumulated += chunk_text
                    if on_chunk and chunk_text:
                        on_chunk(chunk_text)
                    last_chunk = chunk

            # Token 追蹤（在最後一個 chunk）
            usage_metadata = None
            if last_chunk and hasattr(last_chunk, 'usage_metadata'):
                usage_metadata = last_chunk.usage_metadata

            return accumulated, usage_metadata

        except TimeoutError:
            # Timeout 後：通知 producer 取消並等待收斂
            cancel_flag[0] = True
            # 等待 producer 結束（最多 0.5 秒）
            thread.join(timeout=0.5)
            # 重建 session 確保狀態乾淨
            print("[Translator] Streaming timeout, rebuilding session...", file=sys.stderr, flush=True)
            self._rebuild_session()
            raise

    def _extract_partial_current(self, accumulated_json: str) -> Optional[str]:
        """從不完整 JSON 中提取 current 欄位（用於 streaming 更新）"""
        import re
        # 嘗試解析完整 JSON
        try:
            result = json.loads(accumulated_json.strip())
            return result.get("current", "")
        except json.JSONDecodeError:
            pass

        # 用正則提取 current 欄位
        # 匹配 "current": "..." 或 "current":'...'
        match = re.search(r'"current"\s*:\s*"((?:[^"\\]|\\.)*)', accumulated_json)
        if match:
            # 取得目前累積的字串（可能不完整）
            partial_value = match.group(1)
            # 處理轉義字元
            try:
                # 嘗試解碼 JSON 字串轉義
                partial_value = json.loads(f'"{partial_value}"')
            except json.JSONDecodeError:
                pass
            return partial_value

        return None

    def _generate_content_with_timeout(self, contents, config, timeout: int = API_TIMEOUT_SECONDS):
        """呼叫 generate_content，帶 timeout 機制"""
        def do_generate():
            return self.client.models.generate_content(
                model=self.model,
                contents=contents,
                config=config,
            )
        future = self._executor.submit(do_generate)
        try:
            return future.result(timeout=timeout)
        except concurrent.futures.TimeoutError:
            print(f"[Translator] generate_content timed out after {timeout} seconds",
                  file=sys.stderr, flush=True)
            raise TimeoutError(f"Gemini generate_content timed out after {timeout} seconds")

    def translate(self, text: str) -> str:
        """
        翻譯原文到目標語言

        Args:
            text: 原文文字

        Returns:
            翻譯後的目標語言文字
        """
        if not text.strip():
            return ""

        try:
            prompt = self._simple_translate_template.format(
                source_label=self._source_label,
                text=text,
            )
            print(f"[Translator] Sending message (translate)...", file=sys.stderr, flush=True)
            response = self._send_message_with_timeout(prompt)

            # 追蹤 token 使用量
            needs_rebuild = False
            if hasattr(response, 'usage_metadata') and response.usage_metadata:
                usage = response.usage_metadata
                total = getattr(usage, 'total_token_count', None)
                input_tokens = getattr(usage, 'prompt_token_count', None)
                output_tokens = getattr(usage, 'candidates_token_count', None)

                if total is not None:
                    self._total_tokens = total

                # Debug log: 每次翻譯的 token 統計
                print(f"[Translator] Tokens - total: {self._total_tokens}, "
                      f"input: {input_tokens}, output: {output_tokens}, "
                      f"limit: {self.max_context_tokens}",
                      file=sys.stderr, flush=True)

                # 標記是否需要重建（但先返回結果）
                if self._total_tokens > self.max_context_tokens:
                    needs_rebuild = True

            # Chat 全面 JSON mode，解析回應取 current 欄位
            response_text = response.text.strip()
            try:
                result = json.loads(response_text)
                translation = result.get("current", "")
            except json.JSONDecodeError:
                print(f"[Translator] JSON parse error in translate(), using fallback",
                      file=sys.stderr, flush=True)
                translation = self._fallback_translate(text)

            # 返回結果後才做 context rebuild（避免阻塞翻譯結果返回）
            if needs_rebuild:
                print(f"[Translator] Token limit reached ({self._total_tokens}), summarizing and rebuilding...",
                      file=sys.stderr, flush=True)
                self._summarize_and_rebuild()

            return translation

        except Exception as e:
            print(f"[Translator] Error: {e}, rebuilding session...", file=sys.stderr, flush=True)
            self._rebuild_session()
            return self._fallback_translate(text)

    def _summarize_and_rebuild(self) -> None:
        """萃取摘要後重建 session，保持翻譯一致性"""
        print(f"[Translator] === Starting context rebuild (tokens: {self._total_tokens}) ===",
              file=sys.stderr, flush=True)

        # Step 1: 用 generate_content() + chat history 做摘要（不經過 JSON mode chat）
        print("[Translator] Step 1: Requesting summary via generate_content...",
              file=sys.stderr, flush=True)
        try:
            history = self._chat.get_history()
            summary_contents = list(history) + [
                types.Content(
                    role="user",
                    parts=[types.Part.from_text(text=self._summarize_prompt)]
                )
            ]
            # 使用 timeout 機制避免卡住
            summary_response = self._generate_content_with_timeout(
                contents=summary_contents,
                config=self._plain_config,  # 無 JSON schema，自由格式文字
                timeout=20,  # 摘要可能需要較長時間
            )
            self._context_summary = summary_response.text.strip()
            print(f"[Translator] Summary received ({len(self._context_summary)} chars):\n"
                  f"---\n{self._context_summary}\n---", file=sys.stderr, flush=True)
        except Exception as e:
            print(f"[Translator] Summarization failed: {e}", file=sys.stderr, flush=True)
            self._context_summary = ""

        # Step 2: 重建 session（自動帶 JSON mode config）
        print("[Translator] Step 2: Creating new session...", file=sys.stderr, flush=True)
        self._chat = self.client.chats.create(
            model=self.model,
            config=self._config,
        )
        self._total_tokens = 0
        print("[Translator] New session created, tokens reset to 0", file=sys.stderr, flush=True)

        # Step 3: 帶入摘要作為上下文（handover 回應是 JSON，忽略即可）
        if self._context_summary:
            print("[Translator] Step 3: Handing over context to new session...",
                  file=sys.stderr, flush=True)
            handover_msg = CONTEXT_HANDOVER_TEMPLATE.format(summary=self._context_summary)
            try:
                self._send_message_with_timeout(handover_msg)
                print("[Translator] Context handover successful", file=sys.stderr, flush=True)
            except Exception as e:
                print(f"[Translator] Handover failed: {e}", file=sys.stderr, flush=True)
        else:
            print("[Translator] Step 3: Skipped (no summary available)", file=sys.stderr, flush=True)

        print("[Translator] === Context rebuild complete ===", file=sys.stderr, flush=True)

    def _rebuild_session(self) -> None:
        """重建空的 session（無摘要，用於錯誤恢復）"""
        self._chat = self.client.chats.create(
            model=self.model,
            config=self._config,
        )
        self._total_tokens = 0
        print("[Translator] Session rebuilt (no context)", file=sys.stderr, flush=True)

    def _fallback_translate(self, text: str) -> str:
        """降級翻譯：不使用 history"""
        try:
            print(f"[Translator] Fallback translate...", file=sys.stderr, flush=True)
            contents = (
                f"將以下{self._source_label}翻譯成{self._target_label}，"
                f"只輸出翻譯結果：\n{text}"
            )
            config = types.GenerateContentConfig(temperature=0.2)
            response = self._generate_content_with_timeout(
                contents=contents,
                config=config,
                timeout=API_TIMEOUT_SECONDS,
            )
            return response.text.strip()
        except Exception as e:
            print(f"[Translator] Fallback also failed: {e}", file=sys.stderr, flush=True)
            return ""

    def reset_context(self) -> None:
        """重置對話上下文（切換影片時呼叫）"""
        self._rebuild_session()

    def translate_with_context_correction(
        self,
        current_text: str,
        prev_text: Optional[str] = None,
        prev_translation: Optional[str] = None
    ) -> Tuple[str, Optional[str]]:
        """
        翻譯當前文字，並根據上下文可能修正前句翻譯

        Args:
            current_text: 當前要翻譯的原文
            prev_text: 前句原文（可選）
            prev_translation: 前句翻譯（可選）

        Returns:
            (current_translation, corrected_previous_translation or None)
        """
        if not current_text.strip():
            return ("", None)

        try:
            # 根據是否有前句決定使用哪個 prompt
            if prev_text is not None and prev_translation is not None:
                prompt = self._context_correction_template.format(
                    source_label=self._source_label,
                    target_label=self._target_label,
                    current_text=current_text,
                    prev_text=prev_text,
                    prev_translation=prev_translation
                )
            else:
                prompt = self._simple_translate_template.format(
                    source_label=self._source_label,
                    text=current_text,
                )

            print(f"[Translator] Sending message (context correction)...", file=sys.stderr, flush=True)
            response = self._send_message_with_timeout(prompt)

            # 追蹤 token 使用量
            needs_rebuild = False
            if hasattr(response, 'usage_metadata') and response.usage_metadata:
                usage = response.usage_metadata
                total = getattr(usage, 'total_token_count', None)
                input_tokens = getattr(usage, 'prompt_token_count', None)
                output_tokens = getattr(usage, 'candidates_token_count', None)

                if total is not None:
                    self._total_tokens = total

                print(f"[Translator] Context correction - total: {self._total_tokens}, "
                      f"input: {input_tokens}, output: {output_tokens}",
                      file=sys.stderr, flush=True)

                # 標記是否需要重建（但先返回結果）
                if self._total_tokens > self.max_context_tokens:
                    needs_rebuild = True

            # 解析 JSON 回應（structured output 保證合法 JSON）
            response_text = response.text.strip()
            print(f"[Translator] Raw response: {response_text}", file=sys.stderr, flush=True)

            try:
                result = json.loads(response_text)
                current_trans = result.get("current", "")
                correction = result.get("correction")

                # 空字串視為無修正
                if isinstance(correction, str) and correction.strip() == "":
                    correction = None

                print(f"[Translator] Parsed - current: {current_trans}, correction: {correction}",
                      file=sys.stderr, flush=True)

                # 返回結果後才做 context rebuild（避免阻塞翻譯結果返回）
                if needs_rebuild:
                    print(f"[Translator] Token limit reached ({self._total_tokens}), summarizing...",
                          file=sys.stderr, flush=True)
                    self._summarize_and_rebuild()

                return (current_trans, correction)

            except json.JSONDecodeError as e:
                print(f"[Translator] JSON parse error: {e}, using fallback",
                      file=sys.stderr, flush=True)
                fallback = self._fallback_translate(current_text)

                # 即使解析失敗，也要處理 rebuild
                if needs_rebuild:
                    print(f"[Translator] Token limit reached ({self._total_tokens}), summarizing...",
                          file=sys.stderr, flush=True)
                    self._summarize_and_rebuild()

                return (fallback, None)

        except Exception as e:
            print(f"[Translator] Context correction error: {e}", file=sys.stderr, flush=True)
            # 發生錯誤時，嘗試用舊方法翻譯
            fallback = self._fallback_translate(current_text)
            return (fallback, None)

    def translate_with_context_correction_streaming(
        self,
        current_text: str,
        prev_text: Optional[str] = None,
        prev_translation: Optional[str] = None,
        on_streaming_update=None
    ) -> Tuple[str, Optional[str]]:
        """
        Streaming 翻譯，支援即時回饋 + token 追蹤

        Args:
            current_text: 當前要翻譯的原文
            prev_text: 前句原文（可選）
            prev_translation: 前句翻譯（可選）
            on_streaming_update: callback(partial_translation, correction) 用於即時更新

        Returns:
            (current_translation, corrected_previous_translation or None)
        """
        import time

        if not current_text.strip():
            return ("", None)

        # 根據是否有前句決定使用哪個 prompt
        if prev_text is not None and prev_translation is not None:
            prompt = self._context_correction_template.format(
                source_label=self._source_label,
                target_label=self._target_label,
                current_text=current_text,
                prev_text=prev_text,
                prev_translation=prev_translation
            )
        else:
            prompt = self._simple_translate_template.format(
                source_label=self._source_label,
                text=current_text,
            )

        # 嘗試 streaming，失敗則降級為 blocking
        try:
            accumulated_json = ""
            last_update_time = time.time()
            DEBOUNCE_MS = 0.05  # 50ms debounce

            def on_chunk(chunk_text: str):
                nonlocal accumulated_json, last_update_time
                accumulated_json += chunk_text

                # Debounce: 50ms 內不重複更新
                if time.time() - last_update_time < DEBOUNCE_MS:
                    return

                # 嘗試解析或用正則提取 current 欄位
                partial = self._extract_partial_current(accumulated_json)
                if partial and on_streaming_update:
                    on_streaming_update(partial, None)
                    last_update_time = time.time()

            print(f"[Translator] Streaming message (context correction)...", file=sys.stderr, flush=True)
            response_text, usage_metadata = self._send_message_stream_with_timeout(
                prompt, timeout=API_TIMEOUT_SECONDS, on_chunk=on_chunk
            )

            # 解析完整 JSON
            result = json.loads(response_text.strip())
            current_trans = result.get("current", "")
            correction = result.get("correction")

            # 空字串視為無修正
            if isinstance(correction, str) and correction.strip() == "":
                correction = None

            print(f"[Translator] Streaming complete - current: {current_trans}, correction: {correction}",
                  file=sys.stderr, flush=True)

            # Token 追蹤（維持同等管理）
            if usage_metadata:
                total = getattr(usage_metadata, 'total_token_count', None)
                if total is not None:
                    self._total_tokens = total
                    print(f"[Translator] Streaming tokens: {self._total_tokens}", file=sys.stderr, flush=True)
                    if self._total_tokens > self.max_context_tokens:
                        print(f"[Translator] Token limit reached ({self._total_tokens}), summarizing...",
                              file=sys.stderr, flush=True)
                        self._summarize_and_rebuild()

            return (current_trans, correction)

        except Exception as e:
            print(f"[Translator] Streaming failed: {e}, falling back to blocking...",
                  file=sys.stderr, flush=True)
            # 降級為 blocking
            return self.translate_with_context_correction(
                current_text, prev_text, prev_translation
            )
