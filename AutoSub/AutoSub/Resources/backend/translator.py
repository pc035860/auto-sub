"""
Gemini 翻譯模組
使用 Google GenAI SDK 1.61.0
採用 Chat Session 保持翻譯上下文一致性
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


class Translator:
    """Gemini 翻譯器（使用 Chat Session 保持上下文）"""

    def __init__(
        self,
        api_key: str,
        model: str = "gemini-2.5-flash-lite",
        max_history_pairs: int = 20,
    ):
        """
        初始化翻譯器

        Args:
            api_key: Gemini API Key
            model: 模型名稱 (預設 gemini-2.5-flash-lite)
            max_history_pairs: 保留的最大對話對數 (預設 20)
        """
        self.client = genai.Client(api_key=api_key)
        self.model = model
        self.max_history_pairs = max_history_pairs

        self._config = types.GenerateContentConfig(
            system_instruction=SYSTEM_INSTRUCTION,
            temperature=0.2,
        )
        self._chat = self.client.chats.create(
            model=self.model,
            config=self._config,
        )
        self._turn_count = 0

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
            self._turn_count += 1

            # 檢查是否需要壓縮歷史
            if self._turn_count > self.max_history_pairs * 2:
                self._compact_history()

            return response.text.strip()

        except Exception as e:
            print(f"[Translator] Error: {e}, rebuilding session...", file=sys.stderr, flush=True)
            self._rebuild_session()
            return self._fallback_translate(text)

    def _compact_history(self) -> None:
        """壓縮歷史：保留最近的對話"""
        try:
            recent_history = self._chat.get_history(curated=True)
            keep_turns = self.max_history_pairs * 2
            if len(recent_history) > keep_turns:
                recent_history = recent_history[-keep_turns:]

            self._chat = self.client.chats.create(
                model=self.model,
                config=self._config,
                history=recent_history,
            )
            self._turn_count = len(recent_history) // 2
            print(f"[Translator] History compacted to {self._turn_count} pairs", file=sys.stderr, flush=True)
        except Exception as e:
            print(f"[Translator] Compact failed: {e}, rebuilding...", file=sys.stderr, flush=True)
            self._rebuild_session()

    def _rebuild_session(self) -> None:
        """錯誤恢復：重建空的 session"""
        self._chat = self.client.chats.create(
            model=self.model,
            config=self._config,
        )
        self._turn_count = 0
        print("[Translator] Session rebuilt", file=sys.stderr, flush=True)

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
        """重置對話上下文"""
        self._rebuild_session()
