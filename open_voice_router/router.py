"""Router — round-robin provider selection with quota enforcement.

Implements Requirements 8.1, 8.2, 8.3, 8.4, 8.5.

The Router does NOT own a QTimer itself — the midnight reset timer is set up
externally in AppController to avoid a Qt dependency in this module.
"""

from __future__ import annotations

from open_voice_router.exceptions import ProviderError
from open_voice_router.models import AppSettings, ProviderConfig


class ProviderPool:
    """Ordered list of ProviderConfig objects for one layer (STT or LLM)."""

    def __init__(self, providers: list[ProviderConfig]) -> None:
        self.providers = list(providers)


class Router:
    """Round-robin provider selection with per-provider daily quota enforcement.

    - Maintains a per-pool round-robin index (keyed by pool object identity).
    - is_eligible(provider): returns True if quota_limit is None OR
      quota_used_today < quota_limit.
    - next_provider(pool): returns the next eligible provider in round-robin
      order.  Raises ProviderError("All providers exhausted") if no eligible
      providers remain.
    - record_usage(provider_id): increments quota_used_today for that provider
      in the in-memory settings, then calls settings_store.save() to persist.
    - reset_daily_counts(): sets quota_used_today = 0 for all providers in all
      pools.
    - update_settings(settings): replaces the in-memory AppSettings (e.g. after
      the user edits provider configuration in the Settings window).
    """

    def __init__(self, settings: AppSettings, settings_store) -> None:
        """Initialise the Router.

        Args:
            settings:       The current AppSettings (holds provider lists and
                            quota counters).
            settings_store: A SettingsStore instance used to persist quota
                            state after every record_usage() call.
        """
        self._settings = settings
        self._settings_store = settings_store
        # Maps pool object id → current round-robin index (int)
        self._rr_indices: dict[int, int] = {}

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def next_provider(self, pool: ProviderPool) -> ProviderConfig:
        """Return the next eligible provider from *pool* using round-robin.

        The index advances past the returned provider so that the next call
        starts from the provider after it.

        Raises:
            ProviderError: if every provider in the pool has exceeded its
                           daily quota.
        """
        providers = pool.providers
        n = len(providers)
        if n == 0:
            raise ProviderError("All providers exhausted")

        pool_key = id(pool)
        start = self._rr_indices.get(pool_key, 0)

        for offset in range(n):
            idx = (start + offset) % n
            candidate = providers[idx]
            if self.is_eligible(candidate):
                # Advance the index past this provider for the next call
                self._rr_indices[pool_key] = (idx + 1) % n
                return candidate

        raise ProviderError("All providers exhausted")

    def record_usage(self, provider_id: str) -> None:
        """Increment quota_used_today for *provider_id* and persist to disk.

        Searches both stt_providers and llm_providers in the in-memory
        AppSettings.  If the provider is not found the call is a no-op.
        """
        all_providers = (
            self._settings.stt_providers + self._settings.llm_providers
        )
        for provider in all_providers:
            if provider.id == provider_id:
                provider.quota_used_today += 1
                break

        self._settings_store.save(self._settings)

    def is_eligible(self, provider: ProviderConfig) -> bool:
        """Return True if *provider* has not exceeded its daily quota.

        A provider with quota_limit=None is always eligible (unlimited).
        """
        if provider.quota_limit is None:
            return True
        return provider.quota_used_today < provider.quota_limit

    def reset_daily_counts(self) -> None:
        """Reset quota_used_today to 0 for every provider in all pools.

        Called at midnight (timer set up externally in AppController).
        Persists the reset state to disk.
        """
        all_providers = (
            self._settings.stt_providers + self._settings.llm_providers
        )
        for provider in all_providers:
            provider.quota_used_today = 0

        self._settings_store.save(self._settings)

    def update_settings(self, settings: AppSettings) -> None:
        """Replace the in-memory AppSettings.

        Called by AppController when the user saves changes in the Settings
        window so that the Router picks up new provider lists and quota limits.
        """
        self._settings = settings
