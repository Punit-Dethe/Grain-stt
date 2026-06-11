"""Tests for backend startup registration of the local STT provider.

These cover the decoupling fix: the local provider must be registered at
startup (independent of the settings window) so the hotkey drives on-demand
load/unload even when the UI is never opened (tray mode).
"""

from __future__ import annotations

from pathlib import Path

import pytest

from open_voice_router.main import _ensure_local_provider_registered
from open_voice_router.models import AppSettings, ProviderConfig
from open_voice_router.services.local_stt_manager import LocalSTTManager
from open_voice_router.storage.settings_store import SettingsStore


@pytest.fixture
def store(tmp_path: Path) -> SettingsStore:
    return SettingsStore(path=tmp_path / "settings.json")


def test_registers_local_provider_when_absent(store: SettingsStore) -> None:
    """The local provider is prepended (made active) and persisted."""
    settings = AppSettings.defaults()
    settings.stt_providers = []

    updated = _ensure_local_provider_registered(settings, store, LocalSTTManager())

    assert updated.stt_providers[0].id == LocalSTTManager.PROVIDER_ID
    # Persisted to disk so the controller and UI agree.
    assert any(
        p.id == LocalSTTManager.PROVIDER_ID for p in store.load().stt_providers
    )


def test_registration_is_idempotent(store: SettingsStore) -> None:
    """Calling twice does not add a duplicate provider."""
    settings = AppSettings.defaults()
    settings.stt_providers = []

    once = _ensure_local_provider_registered(settings, store, LocalSTTManager())
    twice = _ensure_local_provider_registered(once, store, LocalSTTManager())

    ids = [p.id for p in twice.stt_providers]
    assert ids.count(LocalSTTManager.PROVIDER_ID) == 1


def test_local_provider_is_first_so_chunked_mode_engages(store: SettingsStore) -> None:
    """Local must be the first STT provider so AppController uses streaming mode."""
    existing = ProviderConfig(
        id="cloud-1",
        name="Deepgram",
        base_url="https://api.deepgram.com",
        model="nova-3",
        quota_limit=None,
        quota_used_today=0,
    )
    settings = AppSettings.defaults()
    settings.stt_providers = [existing]

    updated = _ensure_local_provider_registered(settings, store, LocalSTTManager())

    assert updated.stt_providers[0].id == LocalSTTManager.PROVIDER_ID
    assert updated.stt_providers[1].id == "cloud-1"
