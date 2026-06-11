"""Tests for SettingsViewModel local-STT provider registration.

Covers task 8.2: the local provider registration is decoupled from server
readiness — it is registered when the local STT is installed/selected and stays
selectable while the model is unloaded (server stopped).

Validates: Requirements 1.1, 1.2
"""

from __future__ import annotations

import pytest

from open_voice_router.models import AppSettings
from open_voice_router.services.local_stt_manager import LocalSTTManager
from open_voice_router.storage.settings_store import SettingsStore
from open_voice_router.ui.settings.settings_viewmodel import SettingsViewModel

# A QApplication/QGuiApplication is not required to instantiate plain QObjects,
# but signals/timers need an event loop owner. Guard the import so the suite is
# skipped cleanly if the Qt platform cannot be initialised in CI.
QtWidgets = pytest.importorskip("PySide6.QtWidgets")


@pytest.fixture(scope="module")
def qapp():
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    yield app


@pytest.fixture
def store(tmp_path):
    return SettingsStore(path=tmp_path / "settings.json")


def _provider_ids(vm: SettingsViewModel) -> list[str]:
    return [p["id"] for p in vm.stt_providers]


def test_load_registers_local_provider_when_installed(qapp, store, monkeypatch):
    """On load(), an installed local STT registers its provider (server not running)."""
    monkeypatch.setattr(LocalSTTManager, "is_installed", lambda self: True)
    store.save(AppSettings.defaults())

    vm = SettingsViewModel(settings_store=store)
    vm.load()

    assert LocalSTTManager.PROVIDER_ID in _provider_ids(vm)
    # Persisted so the selection survives restarts.
    assert any(
        p.id == LocalSTTManager.PROVIDER_ID for p in store.load().stt_providers
    )


def test_load_does_not_register_when_not_installed(qapp, store, monkeypatch):
    """An uninstalled local STT must not appear in the provider pool."""
    monkeypatch.setattr(LocalSTTManager, "is_installed", lambda self: False)
    store.save(AppSettings.defaults())

    vm = SettingsViewModel(settings_store=store)
    vm.load()

    assert LocalSTTManager.PROVIDER_ID not in _provider_ids(vm)


def test_provider_stays_registered_when_server_stops(qapp, store, monkeypatch):
    """A stopped server (on-demand unload) keeps the provider selectable."""
    monkeypatch.setattr(LocalSTTManager, "is_installed", lambda self: True)
    store.save(AppSettings.defaults())

    vm = SettingsViewModel(settings_store=store)
    vm.load()
    assert LocalSTTManager.PROVIDER_ID in _provider_ids(vm)

    # Simulate the server going down (Model_Unload between sessions).
    vm._on_local_stt_server_stopped()

    assert LocalSTTManager.PROVIDER_ID in _provider_ids(vm)


def test_registration_is_idempotent(qapp, store, monkeypatch):
    """Repeated registration (e.g. server_ready after install) adds no duplicate."""
    monkeypatch.setattr(LocalSTTManager, "is_installed", lambda self: True)
    store.save(AppSettings.defaults())

    vm = SettingsViewModel(settings_store=store)
    vm.load()
    vm._on_local_stt_server_ready()
    vm._register_local_stt_provider()

    ids = _provider_ids(vm)
    assert ids.count(LocalSTTManager.PROVIDER_ID) == 1
