"""
Gemini 翻譯模組
使用 Google GenAI SDK 1.61.0
採用 Chat Session 保持翻譯上下文一致性，最大化隱式快取效益
支援上下文修正：翻譯時可同時修正前句翻譯
"""

import json
import sys
from typing import Optional, Tuple
from google import genai
from google.genai import types
from pydantic import BaseModel


class TranslationResult(BaseModel):
    current: str
    correction: Optional[str] = None


SYSTEM_INSTRUCTION_TEMPLATE = """你是專業的{source_label}即時字幕翻譯員。請將{source_label}翻譯成{target_label}。

翻譯規則：
1. 保持原意，語句通順自然
2. 人名保留原文發音的音譯，前後文中同一人名請保持一致
3. 作品名、專有名詞使用常見譯法
4. 只輸出翻譯結果，不要加任何解釋或標點符號說明
5. 若句子明顯不完整，可根據上下文適當補充或延續前句

注意：這是即時字幕翻譯，請參考之前的對話歷史保持翻譯一致性。"""

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
        max_context_tokens: int = 100_000,
    ):
        """
        初始化翻譯器

        Args:
            api_key: Gemini API Key
            model: 模型名稱 (預設 gemini-2.5-flash-lite-preview-09-2025)
            source_language: 原文語言
            target_language: 翻譯目標語言
            max_context_tokens: 最大 context tokens 閾值 (預設 100K)
        """
        self.client = genai.Client(api_key=api_key)
        self.model = model
        self.max_context_tokens = max_context_tokens
        self.source_language = source_language
        self.target_language = target_language

        source_label = LANGUAGE_LABELS.get(source_language, source_language)
        target_label = LANGUAGE_LABELS.get(target_language, target_language)
        self._system_instruction = SYSTEM_INSTRUCTION_TEMPLATE.format(
            source_label=source_label,
            target_label=target_label,
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
            response = self._chat.send_message(
                self._simple_translate_template.format(
                    source_label=self._source_label,
                    text=text,
                )
            )

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

            # Chat 全面 JSON mode，解析回應取 current 欄位
            response_text = response.text.strip()
            try:
                result = json.loads(response_text)
                return result.get("current", "")
            except json.JSONDecodeError:
                print(f"[Translator] JSON parse error in translate(), using fallback",
                      file=sys.stderr, flush=True)
                return self._fallback_translate(text)

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
            summary_response = self.client.models.generate_content(
                model=self.model,
                contents=summary_contents,
                config=self._plain_config,  # 無 JSON schema，自由格式文字
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
                contents=(
                    f"將以下{self._source_label}翻譯成{self._target_label}，"
                    f"只輸出翻譯結果：\n{text}"
                ),
                config=types.GenerateContentConfig(temperature=0.2),
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
            if prev_text and prev_translation:
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

            response = self._chat.send_message(prompt)

            # 追蹤 token 使用量
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

            # 超過閾值就摘要並重建 session
            if self._total_tokens > self.max_context_tokens:
                print(f"[Translator] Token limit reached ({self._total_tokens}), summarizing...",
                      file=sys.stderr, flush=True)
                self._summarize_and_rebuild()

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

                return (current_trans, correction)

            except json.JSONDecodeError as e:
                print(f"[Translator] JSON parse error: {e}, using fallback",
                      file=sys.stderr, flush=True)
                fallback = self._fallback_translate(current_text)
                return (fallback, None)

        except Exception as e:
            print(f"[Translator] Context correction error: {e}", file=sys.stderr, flush=True)
            # 發生錯誤時，嘗試用舊方法翻譯
            fallback = self._fallback_translate(current_text)
            return (fallback, None)
