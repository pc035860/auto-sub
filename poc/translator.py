"""Gemini 翻譯模組 - 日文到繁體中文"""

import os
import time

from google import genai

TRANSLATION_PROMPT = """你是專業的日文翻譯。請將以下日文翻譯成繁體中文。

規則：
- 保持原意，語句通順自然
- 人名保留日文發音的中文音譯（如：夏吉裕子 → 夏吉裕子）
- 作品名、專有名詞使用台灣常見譯法
- 只輸出翻譯結果，不要加任何解釋

日文：{text}
翻譯："""


class Translator:
    def __init__(self):
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY not set")

        self.client = genai.Client(api_key=api_key)

    def translate(self, text: str) -> tuple[str, float]:
        """
        翻譯日文到繁體中文

        Args:
            text: 日文文字

        Returns:
            (翻譯結果, 翻譯耗時秒數)
        """
        if not text.strip():
            return "", 0.0

        start = time.time()
        response = self.client.models.generate_content(
            model="gemini-2.5-flash-lite",
            contents=TRANSLATION_PROMPT.format(text=text),
        )
        elapsed = time.time() - start

        return response.text.strip(), elapsed
