"""
Gemini 翻譯模組
使用 Google GenAI SDK 1.61.0
"""

from google import genai


TRANSLATION_PROMPT = """你是專業的日文翻譯。請將以下日文翻譯成繁體中文。

規則：
- 保持原意，語句通順自然
- 人名保留日文發音的中文音譯
- 作品名、專有名詞使用台灣常見譯法
- 只輸出翻譯結果，不要加任何解釋

日文原文：
{text}
"""


class Translator:
    """Gemini 翻譯器"""

    def __init__(self, api_key: str, model: str = "gemini-2.5-flash-lite"):
        """
        初始化翻譯器

        Args:
            api_key: Gemini API Key
            model: 模型名稱 (預設 gemini-2.5-flash-lite)
        """
        self.client = genai.Client(api_key=api_key)
        self.model = model

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

        response = self.client.models.generate_content(
            model=self.model,
            contents=TRANSLATION_PROMPT.format(text=text),
        )

        return response.text.strip()
