"""DeepL 翻譯模組 - 日文到繁體中文"""

import os
import time

import deepl


class Translator:
    def __init__(self):
        api_key = os.getenv("DEEPL_API_KEY")
        if not api_key:
            raise ValueError("DEEPL_API_KEY not set")

        self.translator = deepl.Translator(api_key)

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
        result = self.translator.translate_text(
            text,
            source_lang="JA",
            target_lang="ZH-HANT",
        )
        elapsed = time.time() - start

        return result.text, elapsed
