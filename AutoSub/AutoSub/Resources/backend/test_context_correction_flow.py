import importlib.util
import sys
import types
import unittest
from pathlib import Path


def _install_deepgram_stubs() -> None:
    """Install minimal stubs so transcriber.py can be imported without deepgram-sdk."""
    deepgram_module = types.ModuleType("deepgram")

    class DummyDeepgramClient:
        pass

    deepgram_module.DeepgramClient = DummyDeepgramClient

    events_module = types.ModuleType("deepgram.core.events")

    class DummyEventType:
        MESSAGE = "MESSAGE"
        ERROR = "ERROR"

    events_module.EventType = DummyEventType

    sockets_module = types.ModuleType("deepgram.extensions.types.sockets")

    class DummyListenV1MediaMessage:
        def __init__(self, data):
            self.data = data

    sockets_module.ListenV1MediaMessage = DummyListenV1MediaMessage

    sys.modules["deepgram"] = deepgram_module
    sys.modules["deepgram.core"] = types.ModuleType("deepgram.core")
    sys.modules["deepgram.core.events"] = events_module
    sys.modules["deepgram.extensions"] = types.ModuleType("deepgram.extensions")
    sys.modules["deepgram.extensions.types"] = types.ModuleType("deepgram.extensions.types")
    sys.modules["deepgram.extensions.types.sockets"] = sockets_module


def _install_translator_stubs() -> None:
    """Install minimal stubs so translator.py can be imported without external deps."""
    pydantic_module = types.ModuleType("pydantic")

    class DummyBaseModel:
        pass

    pydantic_module.BaseModel = DummyBaseModel
    sys.modules["pydantic"] = pydantic_module

    google_module = sys.modules.get("google") or types.ModuleType("google")
    genai_module = types.ModuleType("google.genai")
    types_module = types.ModuleType("google.genai.types")

    class DummyThinkingConfig:
        def __init__(self, **kwargs):
            self.kwargs = kwargs

    class DummyGenerateContentConfig:
        def __init__(self, **kwargs):
            self.kwargs = kwargs

    class DummyContent:
        def __init__(self, **kwargs):
            self.kwargs = kwargs

    class DummyPart:
        @staticmethod
        def from_text(text):
            return text

    class DummyClient:
        pass

    types_module.ThinkingConfig = DummyThinkingConfig
    types_module.GenerateContentConfig = DummyGenerateContentConfig
    types_module.Content = DummyContent
    types_module.Part = DummyPart

    genai_module.Client = DummyClient
    genai_module.types = types_module

    google_module.genai = genai_module
    sys.modules["google"] = google_module
    sys.modules["google.genai"] = genai_module
    sys.modules["google.genai.types"] = types_module


def _load_module(module_name: str, file_name: str):
    backend_dir = Path(__file__).resolve().parent
    module_path = backend_dir / file_name
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class TranscriberContextCorrectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _install_deepgram_stubs()
        cls.transcriber_module = _load_module("transcriber_under_test", "transcriber.py")

    def test_prev_translation_is_available_from_second_sentence(self):
        transcriber = self.transcriber_module.Transcriber(api_key="dummy")
        seen = []

        def on_transcript(transcript_id, text, prev_id=None, prev_text=None, prev_translation=None):
            seen.append((text, prev_text, prev_translation))
            transcriber.update_previous_translation(f"TR-{text}")

        transcriber.on_transcript = on_transcript

        for text in ("A", "B", "C"):
            transcriber._utterance_buffer = [text]
            transcriber._flush_buffer()

        self.assertEqual(seen[0], ("A", None, None))
        self.assertEqual(seen[1], ("B", "A", "TR-A"))
        self.assertEqual(seen[2], ("C", "B", "TR-B"))

    def test_first_sentence_has_no_previous_context(self):
        transcriber = self.transcriber_module.Transcriber(api_key="dummy")
        seen = []

        def on_transcript(transcript_id, text, prev_id=None, prev_text=None, prev_translation=None):
            seen.append((prev_id, prev_text, prev_translation))

        transcriber.on_transcript = on_transcript
        transcriber._utterance_buffer = ["HELLO"]
        transcriber._flush_buffer()

        self.assertEqual(len(seen), 1)
        self.assertEqual(seen[0], (None, None, None))

    def test_prev_translation_remains_none_if_not_updated(self):
        transcriber = self.transcriber_module.Transcriber(api_key="dummy")
        seen = []

        def on_transcript(transcript_id, text, prev_id=None, prev_text=None, prev_translation=None):
            seen.append((text, prev_text, prev_translation))

        transcriber.on_transcript = on_transcript

        for text in ("A", "B"):
            transcriber._utterance_buffer = [text]
            transcriber._flush_buffer()

        self.assertEqual(seen[0], ("A", None, None))
        self.assertEqual(seen[1], ("B", "A", None))


class TranslatorPromptBranchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _install_translator_stubs()
        cls.translator_module = _load_module("translator_under_test", "translator.py")

    def _make_translator_without_init(self):
        translator = self.translator_module.Translator.__new__(self.translator_module.Translator)
        translator._source_label = "source"
        translator._target_label = "target"
        translator._context_correction_template = "CTX:{current_text}|{prev_text}|{prev_translation}"
        translator._simple_translate_template = "SIMPLE:{text}"
        translator._total_tokens = 0
        translator.max_context_tokens = 999999
        translator._summarize_and_rebuild = lambda: None
        translator._fallback_translate = lambda text: f"FB:{text}"
        return translator

    def test_blocking_uses_context_template_when_prev_translation_empty_string(self):
        translator = self._make_translator_without_init()
        observed = {}

        class DummyResponse:
            text = '{"current":"ok","correction":null}'
            usage_metadata = None

        def fake_send(prompt, timeout=10):
            observed["prompt"] = prompt
            return DummyResponse()

        translator._send_message_with_timeout = fake_send
        current, correction = translator.translate_with_context_correction(
            current_text="now",
            prev_text="before",
            prev_translation="",
        )

        self.assertEqual(current, "ok")
        self.assertIsNone(correction)
        self.assertTrue(observed["prompt"].startswith("CTX:"))

    def test_streaming_uses_simple_template_when_prev_is_none(self):
        translator = self._make_translator_without_init()
        observed = {}

        def fake_stream(prompt, timeout=10, on_chunk=None):
            observed["prompt"] = prompt
            return ('{"current":"ok","correction":null}', None)

        translator._send_message_stream_with_timeout = fake_stream
        current, correction = translator.translate_with_context_correction_streaming(
            current_text="now",
            prev_text=None,
            prev_translation=None,
        )

        self.assertEqual(current, "ok")
        self.assertIsNone(correction)
        self.assertTrue(observed["prompt"].startswith("SIMPLE:"))


if __name__ == "__main__":
    unittest.main()
