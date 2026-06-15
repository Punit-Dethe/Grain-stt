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

from open_voice_router.local_asr import registry as _model_registry
from open_voice_router.models import (
    AppSettings,
    DEFAULT_CODING_PROMPT,
    DEFAULT_EMAIL_PROMPT,
    DEFAULT_SYSTEM_PROMPT,
    DEFAULT_WORD_DICTIONARY,
    PromptConfig,
    ProviderConfig,
)

import uuid as _uuid

# The original built-in "Clean & Format" prompt text. Used only to detect an
# UNMODIFIED legacy default so the migration can retire it (replaced by the
# Email + Coding directives) without clobbering a user who customised it.
_LEGACY_CLEAN_FORMAT_PROMPT = (
    "You are a precise text editor. Take the transcribed speech and: "
    "(1) fix all grammar and punctuation, "
    "(2) structure into clear paragraphs if the content warrants it, "
    "(3) remove filler words and false starts, "
    "(4) preserve technical terms and proper nouns exactly as spoken. "
    "Return only the formatted text with no commentary."
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


# Rolling-window bounds (seconds) for the real-time streaming path. Values
# outside this range are rejected and fall back to the default.
_ROLLING_WINDOW_MIN_S = 15
_ROLLING_WINDOW_MAX_S = 60
_ROLLING_WINDOW_DEFAULT_S = 20


def _validate_rolling_window(value: Any) -> int:
    """Validate the real-time rolling-window duration (seconds).

    Returns the value unchanged when it is an integer within [15, 60]. Any
    out-of-range, non-integer (incl. bool), or missing value falls back to the
    default of 20.
    """
    if isinstance(value, bool) or not isinstance(value, int):
        return _ROLLING_WINDOW_DEFAULT_S
    if value < _ROLLING_WINDOW_MIN_S or value > _ROLLING_WINDOW_MAX_S:
        return _ROLLING_WINDOW_DEFAULT_S
    return value


def _validate_local_model_id(value: Any) -> str:
    """Validate the selected local STT model id against the model registry.

    Unknown, missing, or non-string values fall back to the registry default
    so a settings file written by a newer/older app version still loads into
    a working configuration.
    """
    if isinstance(value, str) and _model_registry.is_known_model(value):
        return value
    return _model_registry.DEFAULT_MODEL_ID


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
    """Bring a persisted prompt list up to the current canonical set.

    Three migrations, all conservative (user customisations are preserved):
      1. Upgrade the built-in 'General' prompt text when it's still an old
         flat-text default (no <role_definition>), not a user customisation.
      2. Retire the legacy 'Clean & Format' prompt, but ONLY when its text is
         the unmodified built-in — a user who edited it keeps theirs.
      3. Additively ensure the 'Email' and 'Coding' directives exist (append by
         name if absent), mirroring _migrate_word_dictionary's additive style.

    Finally, guarantee exactly one active prompt: if retiring Clean & Format (or
    a pre-existing file) left none active, activate 'General' (or the first).
    """
    result: list[PromptConfig] = []
    dropped_active = False
    for p in prompts:
        # (1) Upgrade an old flat-text General default.
        if p.name == "General" and "<role_definition>" not in p.text:
            result.append(
                PromptConfig(id=p.id, name=p.name, text=DEFAULT_SYSTEM_PROMPT, is_active=p.is_active)
            )
            continue
        # (2) Retire the unmodified legacy Clean & Format prompt.
        if p.name == "Clean & Format" and p.text.strip() == _LEGACY_CLEAN_FORMAT_PROMPT:
            if p.is_active:
                dropped_active = True
            continue
        result.append(p)

    # (3) Additively ensure Email + Coding exist (match by name) — but only for
    # a non-empty prompt set. An empty list is a deliberate state (a user who
    # cleared all prompts, or a minimal config) we must not silently re-seed.
    if result:
        present = {p.name for p in result}
        if "Email" not in present:
            result.append(
                PromptConfig(id=str(_uuid.uuid4()), name="Email", text=DEFAULT_EMAIL_PROMPT, is_active=False)
            )
        if "Coding" not in present:
            result.append(
                PromptConfig(id=str(_uuid.uuid4()), name="Coding", text=DEFAULT_CODING_PROMPT, is_active=False)
            )

    # Guarantee exactly one active prompt.
    if result and (dropped_active or not any(p.is_active for p in result)):
        general_idx = next((i for i, p in enumerate(result) if p.name == "General"), 0)
        result = [
            dataclasses.replace(p, is_active=(i == general_idx))
            for i, p in enumerate(result)
        ]

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
        hotkey_batch=d.get("hotkey_batch", "ctrl+shift+z"),
        hotkey_prompt_prev=d.get("hotkey_prompt_prev", "alt+left"),
        hotkey_prompt_next=d.get("hotkey_prompt_next", "alt+right"),
        close_to_tray=bool(d.get("close_to_tray", True)),
        microphone_device_id=d.get("microphone_device_id"),
        stt_providers=stt_providers,
        llm_providers=llm_providers,
        log_file_path=d.get("log_file_path", defaults.log_file_path),
        global_system_prompt=_migrate_global_prompt(raw_prompt),
        prompts=_migrate_prompts(prompts),
        word_dictionary=_migrate_word_dictionary(raw_words),
        launch_on_boot=bool(d.get("launch_on_boot", False)),
        start_minimized=bool(d.get("start_minimized", True)),
        play_sound=bool(d.get("play_sound", True)),
        process_audio=bool(d.get("process_audio", True)),
        local_stt_load_timeout_s=_validate_load_timeout(
            d.get("local_stt_load_timeout_s", _LOAD_TIMEOUT_DEFAULT_S)
        ),
        local_stt_unload_idle_ms=_validate_unload_idle(
            d.get("local_stt_unload_idle_ms", _UNLOAD_IDLE_DEFAULT_MS)
        ),
        local_stt_load_on_startup=bool(d.get("local_stt_load_on_startup", False)),
        local_stt_model_id=_validate_local_model_id(d.get("local_stt_model_id")),
        rolling_window_s=_validate_rolling_window(
            d.get("rolling_window_s", _ROLLING_WINDOW_DEFAULT_S)
        ),
        stt_smart_rotation=bool(d.get("stt_smart_rotation", False)),
        llm_smart_rotation=bool(d.get("llm_smart_rotation", False)),
        grain_assist_provider_id=str(d.get("grain_assist_provider_id", "")),
        ui_dark_mode=bool(d.get("ui_dark_mode", False)),
        ui_dark_mode_advanced=bool(d.get("ui_dark_mode_advanced", False)),
        onboarding_complete=bool(d.get("onboarding_complete", False)),
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
