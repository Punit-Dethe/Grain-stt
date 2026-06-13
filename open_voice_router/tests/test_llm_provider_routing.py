"""Tests for LLM provider enable/disable workflow in the Processing tab.

Locks in the behaviour the user specified:
  * Smart rotation OFF → exactly ONE provider enabled (radio): enabling one
    disables every other, no matter how many times you toggle.
  * Smart rotation ON  → many providers may be enabled simultaneously.
  * Turning rotation OFF clears every selection (user then picks one).
"""

from __future__ import annotations

import uuid

import pytest

from open_voice_router.models import AppSettings, ProviderConfig
from open_voice_router.storage.settings_store import SettingsStore
from open_voice_router.ui.settings.settings_viewmodel import SettingsViewModel

QtWidgets = pytest.importorskip("PySide6.QtWidgets")


@pytest.fixture(scope="module")
def qapp():
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    yield app


def _llm(pid: str, enabled: bool = False) -> ProviderConfig:
    return ProviderConfig(
        id=pid, name=pid, base_url="https://api.example.com/v1", model="m",
        quota_limit=None, enabled=enabled,
    )


def _make_vm(tmp_path, providers, rotation=False):
    store = SettingsStore(path=tmp_path / "settings.json")
    settings = AppSettings.defaults()
    settings.llm_providers = providers
    settings.llm_smart_rotation = rotation
    store.save(settings)
    vm = SettingsViewModel(settings_store=store)
    vm.load()
    return vm, store


def _enabled_ids(vm) -> set[str]:
    return {p["id"] for p in vm.llm_providers if p["enabled"]}


def test_rotation_off_is_radio(qapp, tmp_path):
    """With rotation OFF, enabling each provider in turn keeps exactly one on —
    the 'both end up ON' bug must never happen."""
    vm, _ = _make_vm(tmp_path, [_llm("a", enabled=True), _llm("b"), _llm("c")], rotation=False)
    assert _enabled_ids(vm) == {"a"}

    vm.set_llm_provider_enabled("b", True)
    assert _enabled_ids(vm) == {"b"}  # a auto-disabled

    vm.set_llm_provider_enabled("c", True)
    assert _enabled_ids(vm) == {"c"}  # b auto-disabled — still exactly one

    vm.set_llm_provider_enabled("a", True)
    assert _enabled_ids(vm) == {"a"}  # never two at once


def test_rotation_on_allows_multiple(qapp, tmp_path):
    vm, _ = _make_vm(tmp_path, [_llm("a"), _llm("b"), _llm("c")], rotation=True)
    vm.set_llm_provider_enabled("a", True)
    vm.set_llm_provider_enabled("b", True)
    assert _enabled_ids(vm) == {"a", "b"}
    vm.set_llm_provider_enabled("c", True)
    assert _enabled_ids(vm) == {"a", "b", "c"}
    # Disabling one leaves the rest on.
    vm.set_llm_provider_enabled("b", False)
    assert _enabled_ids(vm) == {"a", "c"}


def test_turning_rotation_off_clears_selection(qapp, tmp_path):
    """Rotation ON with several enabled → turning it OFF disables all, so the
    user makes a single deliberate pick (avoids an ambiguous 'which one?')."""
    vm, _ = _make_vm(
        tmp_path, [_llm("a", enabled=True), _llm("b", enabled=True)], rotation=True
    )
    assert _enabled_ids(vm) == {"a", "b"}
    vm.set_llm_smart_rotation(False)
    assert _enabled_ids(vm) == set()  # cleared — user now picks exactly one
    vm.set_llm_provider_enabled("a", True)
    assert _enabled_ids(vm) == {"a"}
