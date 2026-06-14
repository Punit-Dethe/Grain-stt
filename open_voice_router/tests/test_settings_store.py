"""Unit tests for SettingsStore."""

from __future__ import annotations

import json
from dataclasses import replace
from pathlib import Path

import pytest

from open_voice_router.models import AppSettings, ProviderConfig
from open_voice_router.storage.settings_store import SettingsStore


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_settings_with_providers() -> AppSettings:
    """Return an AppSettings with one STT and one LLM provider."""
    stt = ProviderConfig(
        id="stt-uuid-1",
        name="Deepgram",
        base_url="https://api.deepgram.com",
        model="nova-2",
        quota_limit=100,
        quota_used_today=42,
        system_prompt=None,
    )
    llm = ProviderConfig(
        id="llm-uuid-1",
        name="Cerebras",
        base_url="https://api.cerebras.ai/v1",
        model="llama-4-scout-17b-16e-instruct",
        quota_limit=None,
        quota_used_today=0,
        system_prompt="You are a helpful assistant.",
    )
    defaults = AppSettings.defaults()
    return AppSettings(
        active_mode="voice_to_ai",
        hotkey="ctrl+alt+r",
        microphone_device_id=2,
        stt_providers=[stt],
        llm_providers=[llm],
        log_file_path=defaults.log_file_path,
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_save_and_load_round_trip(tmp_path: Path) -> None:
    """Saving an AppSettings and loading it back should produce an equal object."""
    config_file = tmp_path / "settings.json"
    store = SettingsStore(path=config_file)

    original = _make_settings_with_providers()
    store.save(original)
    loaded = store.load()

    assert loaded == original


def _assert_equals_defaults(result: AppSettings) -> None:
    """Compare against fresh defaults, ignoring prompt ids — each
    AppSettings.defaults() call generates new random prompt UUIDs by design."""
    defaults = AppSettings.defaults()
    result_prompts = [replace(p, id="") for p in result.prompts]
    default_prompts = [replace(p, id="") for p in defaults.prompts]
    assert result_prompts == default_prompts
    assert replace(result, prompts=[]) == replace(defaults, prompts=[])


def test_load_missing_file_returns_defaults(tmp_path: Path) -> None:
    """Loading from a non-existent path should return AppSettings.defaults()."""
    config_file = tmp_path / "nonexistent" / "settings.json"
    store = SettingsStore(path=config_file)

    result = store.load()

    _assert_equals_defaults(result)


def test_load_corrupt_file_returns_defaults(tmp_path: Path) -> None:
    """Loading from a file with invalid JSON should return AppSettings.defaults()."""
    config_file = tmp_path / "settings.json"
    config_file.write_text("{ this is not valid json !!!", encoding="utf-8")

    store = SettingsStore(path=config_file)
    result = store.load()

    _assert_equals_defaults(result)


def test_quota_counters_persist(tmp_path: Path) -> None:
    """Providers with quota_used_today > 0 should have those counters preserved after reload."""
    config_file = tmp_path / "settings.json"
    store = SettingsStore(path=config_file)

    settings = _make_settings_with_providers()
    # Ensure the STT provider has a non-zero counter
    assert settings.stt_providers[0].quota_used_today == 42

    store.save(settings)
    loaded = store.load()

    assert loaded.stt_providers[0].quota_used_today == 42
    assert loaded.llm_providers[0].quota_used_today == 0


def test_save_creates_parent_dirs(tmp_path: Path) -> None:
    """Saving to a path whose parent directories don't exist should create them."""
    config_file = tmp_path / "a" / "b" / "c" / "settings.json"
    store = SettingsStore(path=config_file)

    settings = AppSettings.defaults()
    store.save(settings)

    assert config_file.exists()
    loaded = store.load()
    assert loaded == settings


def test_none_fields_round_trip(tmp_path: Path) -> None:
    """None fields (quota_limit, system_prompt, microphone_device_id) should survive round-trip."""
    config_file = tmp_path / "settings.json"
    store = SettingsStore(path=config_file)

    provider = ProviderConfig(
        id="p1",
        name="Test",
        base_url="https://example.com",
        model="test-model",
        quota_limit=None,
        quota_used_today=0,
        system_prompt=None,
    )
    defaults = AppSettings.defaults()
    settings = AppSettings(
        active_mode=defaults.active_mode,
        hotkey=defaults.hotkey,
        microphone_device_id=None,
        stt_providers=[provider],
        llm_providers=[],
        log_file_path=defaults.log_file_path,
    )

    store.save(settings)
    loaded = store.load()

    assert loaded.microphone_device_id is None
    assert loaded.stt_providers[0].quota_limit is None
    assert loaded.stt_providers[0].system_prompt is None


def test_save_is_atomic(tmp_path: Path) -> None:
    """The saved file should be valid JSON (no partial writes)."""
    config_file = tmp_path / "settings.json"
    store = SettingsStore(path=config_file)

    store.save(AppSettings.defaults())

    raw = config_file.read_text(encoding="utf-8")
    parsed = json.loads(raw)  # should not raise
    assert "active_mode" in parsed


def test_load_on_startup_round_trips(tmp_path: Path) -> None:
    """The local_stt_load_on_startup flag should survive a save/load round-trip."""
    config_file = tmp_path / "settings.json"
    store = SettingsStore(path=config_file)

    settings = replace(AppSettings.defaults(), local_stt_load_on_startup=True)
    store.save(settings)

    assert store.load().local_stt_load_on_startup is True


def test_prompt_migration_replaces_clean_and_format(tmp_path: Path) -> None:
    """A legacy file (General + unmodified Clean & Format) migrates to
    General + Email + Coding, with exactly one active prompt."""
    from open_voice_router.storage.settings_store import _LEGACY_CLEAN_FORMAT_PROMPT

    config_file = tmp_path / "settings.json"
    legacy = {
        "active_mode": "dictation",
        "hotkey": "ctrl+shift+space",
        "microphone_device_id": None,
        "stt_providers": [],
        "llm_providers": [],
        "log_file_path": "x.jsonl",
        "prompts": [
            {"id": "g", "name": "General", "text": "<role_definition>x", "is_active": False},
            {"id": "c", "name": "Clean & Format", "text": _LEGACY_CLEAN_FORMAT_PROMPT, "is_active": True},
        ],
    }
    config_file.write_text(json.dumps(legacy), encoding="utf-8")

    loaded = SettingsStore(path=config_file).load()
    names = [p.name for p in loaded.prompts]

    assert names == ["General", "Email", "Coding"]
    assert "Clean & Format" not in names
    # The dropped prompt was active → General becomes the single active one.
    assert [p.name for p in loaded.prompts if p.is_active] == ["General"]


def test_prompt_migration_keeps_customized_clean_and_format(tmp_path: Path) -> None:
    """A user-customised 'Clean & Format' is preserved (not retired)."""
    config_file = tmp_path / "settings.json"
    legacy = {
        "active_mode": "dictation",
        "hotkey": "ctrl+shift+space",
        "microphone_device_id": None,
        "stt_providers": [],
        "llm_providers": [],
        "log_file_path": "x.jsonl",
        "prompts": [
            {"id": "g", "name": "General", "text": "<role_definition>x", "is_active": True},
            {"id": "c", "name": "Clean & Format", "text": "my own edited prompt", "is_active": False},
        ],
    }
    config_file.write_text(json.dumps(legacy), encoding="utf-8")

    loaded = SettingsStore(path=config_file).load()
    names = [p.name for p in loaded.prompts]

    assert "Clean & Format" in names
    assert names == ["General", "Clean & Format", "Email", "Coding"]


# ---------------------------------------------------------------------------
# local_stt_load_timeout_s validation (R7.2)
# ---------------------------------------------------------------------------

def test_load_timeout_defaults_to_30() -> None:
    """A fresh AppSettings should default the load timeout to 30 seconds."""
    assert AppSettings.defaults().local_stt_load_timeout_s == 30


def test_load_timeout_in_range_persists(tmp_path: Path) -> None:
    """An in-range load timeout should survive a save/load round-trip."""
    config_file = tmp_path / "settings.json"
    store = SettingsStore(path=config_file)

    settings = AppSettings.defaults()
    settings.local_stt_load_timeout_s = 45
    store.save(settings)

    assert store.load().local_stt_load_timeout_s == 45


def _write_settings_with_timeout(config_file: Path, value: object) -> None:
    """Write a minimal settings file with a given load-timeout value."""
    defaults = AppSettings.defaults()
    data = {
        "active_mode": defaults.active_mode,
        "hotkey": defaults.hotkey,
        "microphone_device_id": None,
        "stt_providers": [],
        "llm_providers": [],
        "log_file_path": defaults.log_file_path,
        "local_stt_load_timeout_s": value,
    }
    config_file.write_text(json.dumps(data), encoding="utf-8")


@pytest.mark.parametrize("bad_value", [9, 0, -5, 121, 1000])
def test_load_timeout_out_of_range_falls_back_to_default(
    tmp_path: Path, bad_value: int
) -> None:
    """Out-of-range timeouts are rejected and fall back to the default of 30."""
    config_file = tmp_path / "settings.json"
    _write_settings_with_timeout(config_file, bad_value)

    loaded = SettingsStore(path=config_file).load()

    assert loaded.local_stt_load_timeout_s == 30


@pytest.mark.parametrize("boundary_value", [10, 120])
def test_load_timeout_boundary_values_accepted(
    tmp_path: Path, boundary_value: int
) -> None:
    """The boundary values 10 and 120 are within range and accepted as-is."""
    config_file = tmp_path / "settings.json"
    _write_settings_with_timeout(config_file, boundary_value)

    loaded = SettingsStore(path=config_file).load()

    assert loaded.local_stt_load_timeout_s == boundary_value


@pytest.mark.parametrize("bad_value", ["30", 30.0, None, True])
def test_load_timeout_non_integer_falls_back_to_default(
    tmp_path: Path, bad_value: object
) -> None:
    """Non-integer values are rejected and fall back to the default of 30."""
    config_file = tmp_path / "settings.json"
    _write_settings_with_timeout(config_file, bad_value)

    loaded = SettingsStore(path=config_file).load()

    assert loaded.local_stt_load_timeout_s == 30


def test_load_timeout_missing_field_uses_default(tmp_path: Path) -> None:
    """A settings file without the field loads with the default of 30."""
    config_file = tmp_path / "settings.json"
    defaults = AppSettings.defaults()
    data = {
        "active_mode": defaults.active_mode,
        "hotkey": defaults.hotkey,
        "microphone_device_id": None,
        "stt_providers": [],
        "llm_providers": [],
        "log_file_path": defaults.log_file_path,
    }
    config_file.write_text(json.dumps(data), encoding="utf-8")

    loaded = SettingsStore(path=config_file).load()

    assert loaded.local_stt_load_timeout_s == 30


# ---------------------------------------------------------------------------
# local_stt_unload_idle_ms validation (auto-unload idle policy)
# ---------------------------------------------------------------------------

def test_unload_idle_defaults_to_5_minutes() -> None:
    """A fresh AppSettings should default the auto-unload idle policy to 5 min."""
    assert AppSettings.defaults().local_stt_unload_idle_ms == 300_000


@pytest.mark.parametrize(
    "value",
    [-1, 0, 300_000, 600_000, 900_000, 1_800_000, 3_600_000, 86_400_000],
)
def test_unload_idle_allowed_values_persist(tmp_path: Path, value: int) -> None:
    """Each allowed preset (Never, Instant, 5/10/15/30 min, 1 hr, 24 hr) round-trips."""
    store = SettingsStore(path=tmp_path / "settings.json")
    settings = AppSettings.defaults()
    settings.local_stt_unload_idle_ms = value
    store.save(settings)
    assert store.load().local_stt_unload_idle_ms == value


def _write_settings_with_unload_idle(config_file: Path, value: object) -> None:
    defaults = AppSettings.defaults()
    data = {
        "active_mode": defaults.active_mode,
        "hotkey": defaults.hotkey,
        "hotkey_ai": defaults.hotkey_ai,
        "microphone_device_id": defaults.microphone_device_id,
        "stt_providers": [],
        "llm_providers": [],
        "log_file_path": defaults.log_file_path,
        "local_stt_unload_idle_ms": value,
    }
    config_file.write_text(json.dumps(data), encoding="utf-8")


@pytest.mark.parametrize("bad_value", [123, 1, 60_000, -2, "300000", 300000.0, None, True])
def test_unload_idle_invalid_falls_back_to_default(
    tmp_path: Path, bad_value: object
) -> None:
    """Out-of-set or non-integer idle values fall back to the 5-minute default."""
    config_file = tmp_path / "settings.json"
    _write_settings_with_unload_idle(config_file, bad_value)
    assert SettingsStore(path=config_file).load().local_stt_unload_idle_ms == 300_000


def test_unload_idle_missing_field_uses_default(tmp_path: Path) -> None:
    """A settings file without the field loads with the 5-minute default."""
    config_file = tmp_path / "settings.json"
    _write_settings_with_unload_idle(config_file, 0)
    # Remove the field entirely.
    data = json.loads(config_file.read_text(encoding="utf-8"))
    del data["local_stt_unload_idle_ms"]
    config_file.write_text(json.dumps(data), encoding="utf-8")
    assert SettingsStore(path=config_file).load().local_stt_unload_idle_ms == 300_000


# ---------------------------------------------------------------------------
# local_stt_model_id validation (model-agnostic local STT)
# ---------------------------------------------------------------------------


def test_local_stt_model_default():
    from open_voice_router.local_asr import registry

    assert AppSettings.defaults().local_stt_model_id == registry.DEFAULT_MODEL_ID


def test_local_stt_model_round_trip(tmp_path: Path) -> None:
    from open_voice_router.local_asr import registry

    config_file = tmp_path / "settings.json"
    store = SettingsStore(path=config_file)
    settings = AppSettings.defaults()
    # Pick any non-default registered model.
    other = next(m.id for m in registry.all_models() if m.id != registry.DEFAULT_MODEL_ID)
    settings.local_stt_model_id = other
    store.save(settings)
    assert store.load().local_stt_model_id == other


def test_local_stt_model_unknown_falls_back_to_default(tmp_path: Path) -> None:
    from open_voice_router.local_asr import registry

    config_file = tmp_path / "settings.json"
    store = SettingsStore(path=config_file)
    settings = AppSettings.defaults()
    store.save(settings)
    data = json.loads(config_file.read_text(encoding="utf-8"))
    data["local_stt_model_id"] = "model-removed-from-registry"
    config_file.write_text(json.dumps(data), encoding="utf-8")
    assert store.load().local_stt_model_id == registry.DEFAULT_MODEL_ID


def test_local_stt_model_missing_key_falls_back_to_default(tmp_path: Path) -> None:
    from open_voice_router.local_asr import registry

    config_file = tmp_path / "settings.json"
    store = SettingsStore(path=config_file)
    settings = AppSettings.defaults()
    store.save(settings)
    data = json.loads(config_file.read_text(encoding="utf-8"))
    del data["local_stt_model_id"]
    config_file.write_text(json.dumps(data), encoding="utf-8")
    assert store.load().local_stt_model_id == registry.DEFAULT_MODEL_ID


# ---------------------------------------------------------------------------
# hotkey_batch (non-real-time / record-then-transcribe start key)
# ---------------------------------------------------------------------------


def test_hotkey_batch_default() -> None:
    """The batch hotkey has a sensible default binding."""
    assert AppSettings.defaults().hotkey_batch == "ctrl+shift+z"


def test_hotkey_batch_round_trip(tmp_path: Path) -> None:
    """A non-default batch hotkey survives a save/load cycle."""
    store = SettingsStore(path=tmp_path / "settings.json")
    settings = AppSettings.defaults()
    settings.hotkey_batch = "ctrl+alt+b"
    store.save(settings)

    assert store.load().hotkey_batch == "ctrl+alt+b"


def test_hotkey_batch_missing_key_uses_default(tmp_path: Path) -> None:
    """A settings file predating the batch hotkey loads with its default."""
    config_file = tmp_path / "settings.json"
    store = SettingsStore(path=config_file)
    store.save(AppSettings.defaults())
    data = json.loads(config_file.read_text(encoding="utf-8"))
    data.pop("hotkey_batch", None)
    config_file.write_text(json.dumps(data), encoding="utf-8")

    assert store.load().hotkey_batch == "ctrl+shift+z"


# ---------------------------------------------------------------------------
# rolling_window_s validation (real-time chunk length, [15, 60] default 20)
# ---------------------------------------------------------------------------


def test_rolling_window_defaults_to_20() -> None:
    assert AppSettings.defaults().rolling_window_s == 20


@pytest.mark.parametrize("value", [15, 20, 30, 45, 60])
def test_rolling_window_in_range_round_trip(tmp_path: Path, value: int) -> None:
    store = SettingsStore(path=tmp_path / "settings.json")
    settings = AppSettings.defaults()
    settings.rolling_window_s = value
    store.save(settings)
    assert store.load().rolling_window_s == value


def _write_settings_with_rolling_window(config_file: Path, value: object) -> None:
    defaults = AppSettings.defaults()
    data = {
        "active_mode": defaults.active_mode,
        "hotkey": defaults.hotkey,
        "microphone_device_id": None,
        "stt_providers": [],
        "llm_providers": [],
        "log_file_path": defaults.log_file_path,
        "rolling_window_s": value,
    }
    config_file.write_text(json.dumps(data), encoding="utf-8")


@pytest.mark.parametrize("bad_value", [14, 0, -5, 61, 1000, "20", 20.0, None, True])
def test_rolling_window_invalid_falls_back_to_default(
    tmp_path: Path, bad_value: object
) -> None:
    config_file = tmp_path / "settings.json"
    _write_settings_with_rolling_window(config_file, bad_value)
    assert SettingsStore(path=config_file).load().rolling_window_s == 20


@pytest.mark.parametrize("boundary", [15, 60])
def test_rolling_window_boundaries_accepted(tmp_path: Path, boundary: int) -> None:
    config_file = tmp_path / "settings.json"
    _write_settings_with_rolling_window(config_file, boundary)
    assert SettingsStore(path=config_file).load().rolling_window_s == boundary


def test_rolling_window_missing_field_uses_default(tmp_path: Path) -> None:
    config_file = tmp_path / "settings.json"
    _write_settings_with_rolling_window(config_file, 30)
    data = json.loads(config_file.read_text(encoding="utf-8"))
    del data["rolling_window_s"]
    config_file.write_text(json.dumps(data), encoding="utf-8")
    assert SettingsStore(path=config_file).load().rolling_window_s == 20
