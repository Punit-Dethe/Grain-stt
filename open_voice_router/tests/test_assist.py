"""Tests for Grain Assist's pure logic (prompt building, provider pick,
error mapping) plus the voice STT-provider resolution."""

from __future__ import annotations

import pytest

from open_voice_router.assist_controller import (
    ASSIST_SYSTEM_PROMPT,
    MAX_SELECTION_CHARS,
    AssistController,
    build_user_message,
    pick_llm_provider,
)
from open_voice_router.models import AppSettings, ProviderConfig


@pytest.fixture(scope="module")
def qapp_assist():
    QtWidgets = pytest.importorskip("PySide6.QtWidgets")
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    yield app


def _provider(enabled: bool = True, pid: str = "llm-1") -> ProviderConfig:
    return ProviderConfig(
        id=pid,
        name="Test LLM",
        base_url="https://api.example.com/v1",
        model="test-model",
        quota_limit=None,
        enabled=enabled,
    )


# ---------------------------------------------------------------------------
# build_user_message
# ---------------------------------------------------------------------------


def test_message_with_selection_wraps_in_markup():
    msg = build_user_message("summarize this", "Some selected text.")
    assert msg.startswith("<selected_text>\nSome selected text.\n</selected_text>")
    assert msg.endswith("summarize this")


def test_message_without_selection_is_just_instruction():
    assert build_user_message("what is a biquad filter?", "") == "what is a biquad filter?"
    assert build_user_message("hello", "   ") == "hello"


def test_message_truncates_huge_selection():
    huge = "x" * (MAX_SELECTION_CHARS + 5000)
    msg = build_user_message("summarize", huge)
    assert "[... selection truncated]" in msg
    assert len(msg) < MAX_SELECTION_CHARS + 200


def test_system_prompt_demands_clean_transforms():
    assert "ONLY the transformed text" in ASSIST_SYSTEM_PROMPT


# ---------------------------------------------------------------------------
# pick_llm_provider
# ---------------------------------------------------------------------------


def test_picks_first_enabled_llm():
    settings = AppSettings.defaults()
    settings.llm_providers = [
        _provider(enabled=False, pid="a"),
        _provider(enabled=True, pid="b"),
        _provider(enabled=True, pid="c"),
    ]
    picked = pick_llm_provider(settings)
    assert picked is not None and picked.id == "b"


def test_no_enabled_llm_returns_none():
    settings = AppSettings.defaults()
    settings.llm_providers = [_provider(enabled=False)]
    assert pick_llm_provider(settings) is None
    settings.llm_providers = []
    assert pick_llm_provider(settings) is None


# ---------------------------------------------------------------------------
# Friendly error mapping (shown inline in the input the user is looking at)
# ---------------------------------------------------------------------------


def test_error_mapping_auth():
    msg = AssistController._friendly_error("LLM HTTP error 401: unauthorized")
    assert "API key" in msg


def test_error_mapping_rate_limit():
    msg = AssistController._friendly_error("LLM HTTP error 429: rate limit exceeded")
    assert "Rate limit" in msg


def test_error_mapping_timeout():
    msg = AssistController._friendly_error("LLM request timed out: read timeout")
    assert "did not respond" in msg


def test_error_mapping_generic_is_single_line_and_bounded():
    msg = AssistController._friendly_error("Something odd\nwith many\nlines " + "x" * 500)
    assert "\n" not in msg
    assert len(msg) <= 180


# ---------------------------------------------------------------------------
# Grain Assist provider selection (explicit choice vs auto)
# ---------------------------------------------------------------------------


def test_explicit_grain_provider_wins_even_if_disabled():
    settings = AppSettings.defaults()
    settings.llm_providers = [
        _provider(enabled=True, pid="enabled-one"),
        _provider(enabled=False, pid="my-choice"),
    ]
    settings.grain_assist_provider_id = "my-choice"
    picked = pick_llm_provider(settings)
    assert picked is not None and picked.id == "my-choice"  # disabled, still chosen


def test_grain_provider_auto_falls_back_to_first_enabled():
    settings = AppSettings.defaults()
    settings.llm_providers = [
        _provider(enabled=False, pid="a"),
        _provider(enabled=True, pid="b"),
    ]
    settings.grain_assist_provider_id = ""  # auto
    picked = pick_llm_provider(settings)
    assert picked is not None and picked.id == "b"


def test_grain_provider_deleted_choice_falls_back_to_auto():
    settings = AppSettings.defaults()
    settings.llm_providers = [_provider(enabled=True, pid="b")]
    settings.grain_assist_provider_id = "deleted-id"  # no longer exists
    picked = pick_llm_provider(settings)
    assert picked is not None and picked.id == "b"


# ---------------------------------------------------------------------------
# Active STT provider resolution for voice input
# ---------------------------------------------------------------------------


def test_active_stt_provider_is_first_enabled(qapp_assist):
    from open_voice_router.assist_controller import AssistController
    from open_voice_router.services.clipboard import ClipboardService

    settings = AppSettings.defaults()
    settings.stt_providers = [
        ProviderConfig(id="a", name="A", base_url="https://api.deepgram.com",
                       model="nova-3", quota_limit=None, enabled=False),
        ProviderConfig(id="b", name="B", base_url="https://api.assemblyai.com",
                       model="best", quota_limit=None, enabled=True),
    ]

    class _Creds:
        def get_key(self, pid): return "k"

    ctl = AssistController(
        settings=settings, credential_store=_Creds(), llm_client=object(),
        clipboard_service=ClipboardService(),
    )
    assert ctl._active_stt_provider().id == "b"


def test_voice_unavailable_without_audio_or_stt(qapp_assist):
    from open_voice_router.assist_controller import AssistController
    from open_voice_router.services.clipboard import ClipboardService

    settings = AppSettings.defaults()
    settings.stt_providers = [
        ProviderConfig(id="b", name="B", base_url="https://api.deepgram.com",
                       model="nova-3", quota_limit=None, enabled=True),
    ]

    class _Creds:
        def get_key(self, pid): return "k"

    # No audio_service/stt_client injected → voice disabled even with provider.
    ctl = AssistController(
        settings=settings, credential_store=_Creds(), llm_client=object(),
        clipboard_service=ClipboardService(),
    )
    assert ctl.voice_available is False


def test_stop_recording_is_idempotent_when_not_recording(qapp_assist):
    """stop_recording must be safe to call when nothing is recording (the QML
    onTextEdited handler calls it on every keystroke)."""
    from open_voice_router.assist_controller import AssistController
    from open_voice_router.services.clipboard import ClipboardService

    class _Creds:
        def get_key(self, pid): return "k"

    ctl = AssistController(
        settings=AppSettings.defaults(), credential_store=_Creds(),
        llm_client=object(), clipboard_service=ClipboardService(),
    )
    # No audio service, not recording — must not raise.
    ctl.stop_recording()
    assert ctl.recording is False
