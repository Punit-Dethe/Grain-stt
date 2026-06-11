"""Unit tests for Router — round-robin selection and quota enforcement.

Covers task 3.1 requirements: 8.1, 8.2, 8.3, 8.4, 8.5.
"""

from __future__ import annotations

import pytest

from open_voice_router.exceptions import ProviderError
from open_voice_router.models import AppSettings, ProviderConfig
from open_voice_router.router import ProviderPool, Router


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_provider(
    pid: str,
    quota_limit: int | None = None,
    quota_used_today: int = 0,
) -> ProviderConfig:
    return ProviderConfig(
        id=pid,
        name=pid,
        base_url="https://example.com",
        model="test-model",
        quota_limit=quota_limit,
        quota_used_today=quota_used_today,
    )


def _make_settings(
    stt_providers: list[ProviderConfig] | None = None,
    llm_providers: list[ProviderConfig] | None = None,
) -> AppSettings:
    return AppSettings(
        active_mode="dictation",
        hotkey="ctrl+shift+space",
        microphone_device_id=None,
        stt_providers=stt_providers or [],
        llm_providers=llm_providers or [],
        log_file_path="/tmp/test.jsonl",
    )


class _FakeSettingsStore:
    """In-memory stand-in for SettingsStore — records save() calls."""

    def __init__(self) -> None:
        self.save_count = 0
        self.last_saved: AppSettings | None = None

    def save(self, settings: AppSettings) -> None:
        self.save_count += 1
        self.last_saved = settings


# ---------------------------------------------------------------------------
# Round-robin tests
# ---------------------------------------------------------------------------

def test_round_robin_cycles_through_all_providers():
    """3 providers, 3 calls → each returned exactly once."""
    p1 = _make_provider("p1")
    p2 = _make_provider("p2")
    p3 = _make_provider("p3")
    pool = ProviderPool([p1, p2, p3])
    router = Router(_make_settings(stt_providers=[p1, p2, p3]), _FakeSettingsStore())

    results = [router.next_provider(pool) for _ in range(3)]

    assert results == [p1, p2, p3]


def test_round_robin_wraps_around():
    """2 providers, 4 calls → [p1, p2, p1, p2]."""
    p1 = _make_provider("p1")
    p2 = _make_provider("p2")
    pool = ProviderPool([p1, p2])
    router = Router(_make_settings(stt_providers=[p1, p2]), _FakeSettingsStore())

    results = [router.next_provider(pool) for _ in range(4)]

    assert results == [p1, p2, p1, p2]


# ---------------------------------------------------------------------------
# Quota / eligibility tests
# ---------------------------------------------------------------------------

def test_exhausted_provider_is_skipped():
    """A provider with quota_used_today >= quota_limit is never returned."""
    p_full = _make_provider("full", quota_limit=5, quota_used_today=5)
    p_ok = _make_provider("ok", quota_limit=10, quota_used_today=0)
    pool = ProviderPool([p_full, p_ok])
    router = Router(_make_settings(stt_providers=[p_full, p_ok]), _FakeSettingsStore())

    # Call multiple times — should always get p_ok, never p_full
    for _ in range(5):
        result = router.next_provider(pool)
        assert result is p_ok


def test_all_exhausted_raises_provider_error():
    """All providers at quota → ProviderError raised."""
    p1 = _make_provider("p1", quota_limit=3, quota_used_today=3)
    p2 = _make_provider("p2", quota_limit=1, quota_used_today=1)
    pool = ProviderPool([p1, p2])
    router = Router(_make_settings(stt_providers=[p1, p2]), _FakeSettingsStore())

    with pytest.raises(ProviderError, match="All providers exhausted"):
        router.next_provider(pool)


def test_unlimited_quota_never_exhausted():
    """A provider with quota_limit=None is always eligible."""
    p = _make_provider("unlimited", quota_limit=None, quota_used_today=9999)
    pool = ProviderPool([p])
    router = Router(_make_settings(stt_providers=[p]), _FakeSettingsStore())

    for _ in range(10):
        result = router.next_provider(pool)
        assert result is p


def test_is_eligible_returns_false_when_at_limit():
    p = _make_provider("p", quota_limit=5, quota_used_today=5)
    router = Router(_make_settings(), _FakeSettingsStore())
    assert router.is_eligible(p) is False


def test_is_eligible_returns_true_when_below_limit():
    p = _make_provider("p", quota_limit=5, quota_used_today=4)
    router = Router(_make_settings(), _FakeSettingsStore())
    assert router.is_eligible(p) is True


def test_is_eligible_returns_true_for_unlimited():
    p = _make_provider("p", quota_limit=None, quota_used_today=10000)
    router = Router(_make_settings(), _FakeSettingsStore())
    assert router.is_eligible(p) is True


# ---------------------------------------------------------------------------
# record_usage tests
# ---------------------------------------------------------------------------

def test_record_usage_increments_counter():
    """After record_usage, quota_used_today increases by 1."""
    p = _make_provider("p1", quota_limit=10, quota_used_today=2)
    settings = _make_settings(stt_providers=[p])
    store = _FakeSettingsStore()
    router = Router(settings, store)

    router.record_usage("p1")

    assert p.quota_used_today == 3


def test_record_usage_persists_to_store():
    """record_usage calls settings_store.save() exactly once."""
    p = _make_provider("p1")
    settings = _make_settings(stt_providers=[p])
    store = _FakeSettingsStore()
    router = Router(settings, store)

    router.record_usage("p1")

    assert store.save_count == 1
    assert store.last_saved is settings


def test_record_usage_unknown_provider_is_noop():
    """record_usage with an unknown provider_id does not raise."""
    settings = _make_settings()
    store = _FakeSettingsStore()
    router = Router(settings, store)

    router.record_usage("nonexistent")  # should not raise

    # save is still called (quota state is persisted even if nothing changed)
    assert store.save_count == 1


def test_record_usage_works_for_llm_providers():
    """record_usage finds providers in llm_providers list too."""
    p = _make_provider("llm1", quota_limit=5, quota_used_today=0)
    settings = _make_settings(llm_providers=[p])
    store = _FakeSettingsStore()
    router = Router(settings, store)

    router.record_usage("llm1")

    assert p.quota_used_today == 1


# ---------------------------------------------------------------------------
# reset_daily_counts tests
# ---------------------------------------------------------------------------

def test_reset_daily_counts_zeroes_all():
    """After reset, all quota_used_today = 0 for every provider."""
    p1 = _make_provider("p1", quota_limit=10, quota_used_today=7)
    p2 = _make_provider("p2", quota_limit=5, quota_used_today=5)
    p3 = _make_provider("p3", quota_limit=None, quota_used_today=3)
    settings = _make_settings(stt_providers=[p1, p2], llm_providers=[p3])
    store = _FakeSettingsStore()
    router = Router(settings, store)

    router.reset_daily_counts()

    assert p1.quota_used_today == 0
    assert p2.quota_used_today == 0
    assert p3.quota_used_today == 0


def test_reset_daily_counts_persists_to_store():
    """reset_daily_counts calls settings_store.save()."""
    p = _make_provider("p1", quota_used_today=5)
    settings = _make_settings(stt_providers=[p])
    store = _FakeSettingsStore()
    router = Router(settings, store)

    router.reset_daily_counts()

    assert store.save_count == 1


# ---------------------------------------------------------------------------
# update_settings test
# ---------------------------------------------------------------------------

def test_update_settings_replaces_provider_list():
    """update_settings causes next_provider to use the new pool contents."""
    p_old = _make_provider("old")
    p_new = _make_provider("new")
    old_settings = _make_settings(stt_providers=[p_old])
    new_settings = _make_settings(stt_providers=[p_new])
    store = _FakeSettingsStore()
    router = Router(old_settings, store)

    router.update_settings(new_settings)
    pool = ProviderPool([p_new])
    result = router.next_provider(pool)

    assert result is p_new
