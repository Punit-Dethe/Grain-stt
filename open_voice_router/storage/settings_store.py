"""SettingsStore — JSON configuration file persistence.

Uses platformdirs for a platform-appropriate config directory.
API keys are never stored here; only provider metadata is persisted.
"""

from __future__ import annotations

import dataclasses
import json
import os
import tempfile
from pathlib import Path
from typing import Any

import platformdirs

from open_voice_router.models import (
    AppSettings,
    DEFAULT_SYSTEM_PROMPT,
    DEFAULT_WORD_DICTIONARY,
    PromptConfig,
    ProviderConfig,
)

# Model_Load timeout bounds (R7.2). Values outside this range are rejected and
# fall back to the default.
_LOAD_TIMEOUT_MIN_S = 10
_LOAD_TIMEOUT_MAX_S = 120
_LOAD_TIMEOUT_DEFAULT_S = 30

# Auto-unload idle policy (milliseconds). The model's auto-unload behaviour is
# enforced by the backend so it works with the UI fully closed. Allowed values
# correspond to the Settings combo box: Instant, 5/10/15/30 min, 1 hr, 24 hr,
# and Never (-1). Any other value falls back to the default of 5 minutes.
_UNLOAD_IDLE_DEFAULT_MS = 300_000  # 5 minutes
_UNLOAD_IDLE_ALLOWED_MS = frozenset(
    {
        -1,  # Never
        0,  # Instant
        5 * 60_000,  # 5 minutes
        10 * 60_000,  # 10 minutes
        15 * 60_000,  # 15 minutes
        30 * 60_000,  # 30 minutes
        60 * 60_000,  # 1 hour
        24 * 60 * 60_000,  # 24 hours
    }
)


def _config_path() -> Path:
    """Return the platform-appropriate path for the settings JSON file."""
    return Path(platformdirs.user_config_dir("open-voice-router")) / "settings.json"


def _validate_load_timeout(value: Any) -> int:
    """Validate the local STT Model_Load timeout.

    Returns the value unchanged when it is an integer within
    [10, 120] seconds. Any out-of-range, non-integer, or missing value is
    rejected and falls back to the default of 30 (R7.2).
    """
    # Reject bools (which are ints in Python) and non-integers.
    if isinstance(value, bool) or not isinstance(value, int):
        return _LOAD_TIMEOUT_DEFAULT_S
    if value < _LOAD_TIMEOUT_MIN_S or value > _LOAD_TIMEOUT_MAX_S:
        return _LOAD_TIMEOUT_DEFAULT_S
    return value


def _validate_unload_idle(value: Any) -> int:
    """Validate the local STT auto-unload idle policy (milliseconds).

    Returns the value unchanged when it is one of the allowed presets
    (Instant, 5/10/15/30 min, 1 hr, 24 hr, or Never = -1). Any out-of-set,
    non-integer, or missing value falls back to the default of 5 minutes.
    """
    if isinstance(value, bool) or not isinstance(value, int):
        return _UNLOAD_IDLE_DEFAULT_MS
    if value not in _UNLOAD_IDLE_ALLOWED_MS:
        return _UNLOAD_IDLE_DEFAULT_MS
    return value


def _provider_config_from_dict(d: dict[str, Any]) -> ProviderConfig:
    """Reconstruct a ProviderConfig from a plain dict."""
    return ProviderConfig(
        id=d["id"],
        name=d["name"],
        base_url=d["base_url"],
        model=d["model"],
        quota_limit=d.get("quota_limit"),  # None = unlimited
        quota_used_today=d.get("quota_used_today", 0),
        system_prompt=d.get("system_prompt"),
        kind=d.get("kind", "cloud"),
        enabled=bool(d.get("enabled", True)),
    )


def _migrate_prompts(prompts: list[PromptConfig]) -> list[PromptConfig]:
    """Upgrade the built-in 'General' prompt to the current canonical version.

    Only replaces the text when it doesn't already contain <role_definition> —
    meaning it's an old flat-text default, not a user customisation.
    """
    result = []
    for p in prompts:
        if p.name == "General" and "<role_definition>" not in p.text:
            result.append(PromptConfig(id=p.id, name=p.name, text=DEFAULT_SYSTEM_PROMPT, is_active=p.is_active))
        else:
            result.append(p)
    return result


def _migrate_global_prompt(text: str) -> str:
    """Upgrade the global_system_prompt field if it's an old flat-text default."""
    return DEFAULT_SYSTEM_PROMPT if "<role_definition>" not in text else text


def _migrate_word_dictionary(words: list[str]) -> list[str]:
    """Ensure all DEFAULT_WORD_DICTIONARY entries are present (additive only)."""
    word_set = set(words)
    extras = [w for w in DEFAULT_WORD_DICTIONARY if w not in word_set]
    return words + extras if extras else words


def _app_settings_from_dict(d: dict[str, Any]) -> AppSettings:
    """Reconstruct an AppSettings from a plain dict."""
    stt_providers = [
        _provider_config_from_dict(p) for p in d.get("stt_providers", [])
    ]
    llm_providers = [
        _provider_config_from_dict(p) for p in d.get("llm_providers", [])
    ]
    prompts = [
        PromptConfig(
            id=p["id"],
            name=p.get("name", ""),
            text=p.get("text", ""),
            is_active=p.get("is_active", False),
        )
        for p in d.get("prompts", [])
    ]
    raw_prompt = d.get("global_system_prompt", DEFAULT_SYSTEM_PROMPT)
    raw_words = [str(w) for w in d.get("word_dictionary", []) if isinstance(w, str)]

    defaults = AppSettings.defaults()
    return AppSettings(
        active_mode=d.get("active_mode", defaults.active_mode),
        hotkey=d.get("hotkey", defaults.hotkey),
        hotkey_ai=d.get("hotkey_ai", "ctrl+shift+enter"),
        hotkey_grain=d.get("hotkey_grain", "ctrl+shift+g"),
        close_to_tray=bool(d.get("close_to_tray", True)),
        microphone_device_id=d.get("microphone_device_id"),
        stt_providers=stt_providers,
        llm_providers=llm_providers,
        log_file_path=d.get("log_file_path", defaults.log_file_path),
        global_system_prompt=_migrate_global_prompt(raw_prompt),
        prompts=_migrate_prompts(prompts),
        word_dictionary=_migrate_word_dictionary(raw_words),
        launch_on_boot=bool(d.get("launch_on_boot", False)),
        play_sound=bool(d.get("play_sound", True)),
        process_audio=bool(d.get("process_audio", True)),
        local_stt_load_timeout_s=_validate_load_timeout(
            d.get("local_stt_load_timeout_s", _LOAD_TIMEOUT_DEFAULT_S)
        ),
        local_stt_unload_idle_ms=_validate_unload_idle(
            d.get("local_stt_unload_idle_ms", _UNLOAD_IDLE_DEFAULT_MS)
        ),
        stt_smart_rotation=bool(d.get("stt_smart_rotation", False)),
        llm_smart_rotation=bool(d.get("llm_smart_rotation", False)),
        ui_dark_mode=bool(d.get("ui_dark_mode", False)),
        transcription_history=[
            e for e in d.get("transcription_history", [])
            if isinstance(e, dict) and "time" in e and "text" in e
        ][-10:],
        processing_history=[
            e for e in d.get("processing_history", [])
            if isinstance(e, dict) and "time" in e and "text" in e
        ][-10:],
    )


class SettingsStore:
    """Reads and writes AppSettings to a JSON file.

    API keys are never stored here; only provider metadata is persisted.
    On load failure (missing or corrupt file) returns AppSettings.defaults().
    """

    def __init__(self, path: Path | None = None) -> None:
        """Create a SettingsStore.

        Args:
            path: Override the config file path (useful for testing).
                  Defaults to the platform-appropriate user config directory.
        """
        self._path: Path = path if path is not None else _config_path()

    def load(self) -> AppSettings:
        """Load settings from disk.

        Returns AppSettings.defaults() if the file is missing or contains
        invalid JSON — never raises.
        """
        try:
            text = self._path.read_text(encoding="utf-8")
            data = json.loads(text)
            return _app_settings_from_dict(data)
        except (FileNotFoundError, json.JSONDecodeError, KeyError, TypeError):
            return AppSettings.defaults()

    def save(self, settings: AppSettings) -> None:
        """Persist *settings* to disk atomically.

        Writes to a temporary file in the same directory, then renames it
        over the target path so that a crash mid-write never leaves a
        partially-written (corrupt) config file.
        """
        self._path.parent.mkdir(parents=True, exist_ok=True)

        data = dataclasses.asdict(settings)
        text = json.dumps(data, indent=2, ensure_ascii=False)

        # Atomic write: temp file → rename
        fd, tmp_path = tempfile.mkstemp(
            dir=self._path.parent, prefix=".settings_tmp_", suffix=".json"
        )
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(text)
            os.replace(tmp_path, self._path)
        except Exception:
            # Clean up the temp file if anything goes wrong
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise
