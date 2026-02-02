"""
Gemini 翻譯模組
使用 Google GenAI SDK 1.61.0
採用 Chat Session 保持翻譯上下文一致性，最大化隱式快取效益
"""

import sys
from google import genai
from google.genai import types


SYSTEM_INSTRUCTION = """你是專業的日文即時字幕翻譯員。請將日文翻譯成繁體中文。

翻譯規則：
1. 保持原意，語句通順自然
2. 人名保留日文發音的中文音譯，前後文中同一人名請保持一致
3. 作品名、專有名詞使用台灣常見譯法
4. 只輸出翻譯結果，不要加任何解釋或標點符號說明
5. 若句子明顯不完整，可根據上下文適當補充或延續前句

注意：這是即時字幕翻譯，請參考之前的對話歷史保持翻譯一致性。"""

SUMMARIZE_PROMPT = """請根據以上翻譯歷史，整理：
1. 人名/專有名詞對照清單（格式：日文 → 中文，每行一個）
2. 這個對話的主題或背景（一句話）

只輸出整理結果，不要其他說明。"""

CONTEXT_HANDOVER_TEMPLATE = """延續之前的翻譯工作。以下是已確定的翻譯對照和背景：

{summary}

請繼續保持翻譯一致性。"""


class Translator:
    """Gemini 翻譯器（使用 Chat Session 保持上下文，最大化隱式快取效益）"""

    def __init__(
        self,
        api_key: str,
        model: str = "gemini-2.5-flash-lite",
        max_context_tokens: int = 100_000,
    ):
        """
        初始化翻譯器

        Args:
            api_key: Gemini API Key
            model: 模型名稱 (預設 gemini-2.5-flash-lite)
            max_context_tokens: 最大 context tokens 閾值 (預設 100K)
        """
        self.client = genai.Client(api_key=api_key)
        self.model = model
        self.max_context_tokens = max_context_tokens

        self._config = types.GenerateContentConfig(
            system_instruction=SYSTEM_INSTRUCTION,
            temperature=0.2,
        )
        self._chat = self.client.chats.create(
            model=self.model,
            config=self._config,
        )
        self._total_tokens = 0
        self._context_summary: str = ""  # 上一個 session 的摘要

    def translate(self, text: str) -> str:
        """
        翻譯日文到繁體中文

        Args:
            text: 日文文字

        Returns:
            翻譯後的繁體中文
        """
        if not text.strip():
            return ""

        try:
            response = self._chat.send_message(f"翻譯：{text}")

            # 追蹤 token 使用量
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

            # 超過閾值就摘要並重建 session
            if self._total_tokens > self.max_context_tokens:
                print(f"[Translator] Token limit reached ({self._total_tokens}), summarizing and rebuilding...",
                      file=sys.stderr, flush=True)
                self._summarize_and_rebuild()

            return response.text.strip()

        except Exception as e:
            print(f"[Translator] Error: {e}, rebuilding session...", file=sys.stderr, flush=True)
            self._rebuild_session()
            return self._fallback_translate(text)

    def _summarize_and_rebuild(self) -> None:
        """萃取摘要後重建 session，保持翻譯一致性"""
        print(f"[Translator] === Starting context rebuild (tokens: {self._total_tokens}) ===",
              file=sys.stderr, flush=True)

        # Step 1: 請求摘要（用即將被丟棄的 session）
        print("[Translator] Step 1: Requesting summary from current session...",
              file=sys.stderr, flush=True)
        try:
            summary_response = self._chat.send_message(SUMMARIZE_PROMPT)
            self._context_summary = summary_response.text.strip()
            print(f"[Translator] Summary received ({len(self._context_summary)} chars):\n"
                  f"---\n{self._context_summary}\n---", file=sys.stderr, flush=True)
        except Exception as e:
            print(f"[Translator] Summarization failed: {e}", file=sys.stderr, flush=True)
            self._context_summary = ""

        # Step 2: 重建 session
        print("[Translator] Step 2: Creating new session...", file=sys.stderr, flush=True)
        self._chat = self.client.chats.create(
            model=self.model,
            config=self._config,
        )
        self._total_tokens = 0
        print("[Translator] New session created, tokens reset to 0", file=sys.stderr, flush=True)

        # Step 3: 帶入摘要作為上下文
        if self._context_summary:
            print("[Translator] Step 3: Handing over context to new session...",
                  file=sys.stderr, flush=True)
            handover_msg = CONTEXT_HANDOVER_TEMPLATE.format(summary=self._context_summary)
            try:
                self._chat.send_message(handover_msg)
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
            response = self.client.models.generate_content(
                model=self.model,
                contents=f"將以下日文翻譯成繁體中文，只輸出翻譯結果：\n{text}",
                config=types.GenerateContentConfig(temperature=0.2),
            )
            return response.text.strip()
        except Exception as e:
            print(f"[Translator] Fallback also failed: {e}", file=sys.stderr, flush=True)
            return ""

    def reset_context(self) -> None:
        """重置對話上下文（切換影片時呼叫）"""
        self._rebuild_session()
