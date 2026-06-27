"""Regression test: the prompt-cycle hotkey must not clobber unrelated settings.

The settings file has two in-memory owners — AppController (a snapshot frozen at
startup) and SettingsViewModel (re-loaded each time its window opens). A blind
whole-blob save from AppController's stale snapshot used to overwrite any setting
the user changed in the UI during the same session, so those changes vanished on
the next launch. `_cycle_active_prompt` now does a read-modify-write that flips
ONLY the active prompt, leaving every other field as the UI last wrote it.

NOTE: SettingsStore.load() applies prompt migrations (it upgrades marker-less
prompt text and additively appends the canonical Email/Coding prompts), so these
tests use `<role_definition>` markers and match prompts by stable id rather than
by list position to stay robust against that normalisation.
"""

from __future__ import annotations

from dataclasses import replace
from pathlib import Path
from unittest.mock import MagicMock

from open_voice_router.app_controller import AppController, SessionState
from open_voice_router.models import AppSettings, PromptConfig
from open_voice_router.storage.settings_store import SettingsStore


def _marker(text: str) -> str:
    """Wrap text so the prompt migration treats it as already-upgraded."""
    return f"<role_definition>{text}</role_definition>"


def _controller_with(store: SettingsStore, settings: AppSettings) -> AppController:
    """Build an AppController without running its heavy __init__.

    `_cycle_active_prompt` only touches these attributes, so injecting them
    directly exercises the real method without standing up audio/hotkey/STT
    services.
    """
    c = AppController.__new__(AppController)
    c._state = SessionState.RECORDING
    c._settings = settings
    c._settings_store = store
    c._session_mode = "dictation"
    c.pill_vm = MagicMock()
    return c


def _by_id(settings: AppSettings, pid: str) -> PromptConfig:
    return next(p for p in settings.prompts if p.id == pid)


def test_cycle_prompt_preserves_concurrent_ui_edit(tmp_path: Path) -> None:
    config = tmp_path / "settings.json"
    store = SettingsStore(path=config)

    prompts = [
        PromptConfig(id="p1", name="General", text=_marker("general"), is_active=True),
        PromptConfig(id="p2", name="Email", text=_marker("email"), is_active=False),
    ]
    # Startup snapshot the controller froze (dark mode OFF).
    startup = replace(
        AppSettings.defaults(),
        prompts=prompts,
        global_system_prompt=_marker("general"),
        ui_dark_mode=False,
    )

    # The user changes dark mode in the Settings UI mid-session: the ViewModel
    # writes the WHOLE blob to disk with dark mode ON.
    store.save(replace(startup, ui_dark_mode=True))

    # Now the user cycles the prompt during recording using the stale controller.
    controller = _controller_with(store, startup)
    controller._cycle_active_prompt(1)

    reloaded = store.load()
    # The prompt selection advanced from p1 to p2 (matched by id)...
    assert _by_id(reloaded, "p1").is_active is False
    assert _by_id(reloaded, "p2").is_active is True
    assert reloaded.global_system_prompt == _marker("email")
    # ...and the UI's dark-mode change survived (the bug would reset it to False).
    assert reloaded.ui_dark_mode is True


def test_cycle_prompt_uses_on_disk_prompt_edits(tmp_path: Path) -> None:
    """If the user edited a prompt's text in the UI, the persisted active prompt
    reflects the on-disk text, not the controller's stale copy."""
    config = tmp_path / "settings.json"
    store = SettingsStore(path=config)

    startup = replace(
        AppSettings.defaults(),
        prompts=[
            PromptConfig(id="p1", name="General", text=_marker("general"), is_active=True),
            PromptConfig(id="p2", name="Email", text=_marker("OLD email"), is_active=False),
        ],
        global_system_prompt=_marker("general"),
    )
    # UI edits the Email prompt text on disk.
    store.save(
        replace(
            startup,
            prompts=[
                PromptConfig(id="p1", name="General", text=_marker("general"), is_active=True),
                PromptConfig(id="p2", name="Email", text=_marker("NEW email"), is_active=False),
            ],
        )
    )

    controller = _controller_with(store, startup)
    controller._cycle_active_prompt(1)  # advance to Email

    reloaded = store.load()
    active = next(p for p in reloaded.prompts if p.is_active)
    assert active.id == "p2"
    assert active.text == _marker("NEW email")
    assert reloaded.global_system_prompt == _marker("NEW email")
