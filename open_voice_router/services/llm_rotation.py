"""Smart LLM rotation — live-signal provider selection.

Why not a static model/limit table? Providers host hundreds of models with
shifting quotas; any hardcoded table is wrong within weeks. Instead the
tracker learns from three LIVE signals, best first:

1. **Rate-limit headers** — Groq, OpenAI, Mistral, OpenRouter return
   ``x-ratelimit-remaining-requests`` / ``x-ratelimit-remaining-tokens`` on
   every response. When fresh, these are ground truth.
2. **Observed usage** — every OpenAI-compatible response carries
   ``usage.total_tokens``. We keep a sliding 60 s token window (effective
   TPM) and daily request/token counters per provider.
3. **Real 429s** — a rate-limited provider goes on cooldown for the
   server-stated ``retry-after`` (or a default), then returns automatically.

For providers that send no headers (Gemini's OpenAI compat layer), known
FREE-TIER caps act as conservative defaults for the local estimates.

THE SAFETY RULE: static caps and our own estimates only affect ORDERING —
they can never exclude a provider. A paid-tier key with wrong static caps is
merely tried later, not blocked. Only a real 429 (cooldown) or the user's own
daily request quota excludes, and even cooldowns degrade to ordering when
every provider is cooling down (we never hard-fail on our own bookkeeping).

Selection: score = headroom fraction of the provider's BOTTLENECK resource
(min of request- and token-headroom). A request whose estimated tokens
exceed a provider's remaining per-minute token window (e.g. a whole web page
against Groq's free 6k TPM) sinks that provider to the back — this is the
"effective context" routing. Equal scores tie-break round-robin so load
spreads. Latency is deliberately NOT a factor.

Pure Python (no Qt) so the policy is property-testable.
"""

from __future__ import annotations

import time
from collections import deque
from dataclasses import dataclass, field

from open_voice_router.models import ProviderConfig

# ---------------------------------------------------------------------------
# Static free-tier defaults (ORDERING hints only — see THE SAFETY RULE above)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class TierCaps:
    tokens_per_minute: int | None = None
    requests_per_minute: int | None = None
    requests_per_day: int | None = None


# Keyed by a substring of the provider's base_url host. Values are
# deliberately CONSERVATIVE free-tier figures (mid-2026); being wrong only
# reorders candidates, never blocks them.
FREE_TIER_DEFAULTS: dict[str, TierCaps] = {
    "api.groq.com": TierCaps(
        tokens_per_minute=6_000, requests_per_minute=30, requests_per_day=14_400
    ),
    "generativelanguage.googleapis.com": TierCaps(
        tokens_per_minute=250_000, requests_per_minute=10, requests_per_day=250
    ),
    "api.cerebras.ai": TierCaps(
        tokens_per_minute=60_000, requests_per_minute=30, requests_per_day=14_400
    ),
    "openrouter.ai": TierCaps(requests_per_minute=20, requests_per_day=50),
    "api.mistral.ai": TierCaps(tokens_per_minute=500_000, requests_per_minute=30),
}

# Headers considered fresh for this long; after that we fall back to local
# estimates (the remote state has drifted too far to trust).
_HEADER_TTL_S = 300.0
_WINDOW_S = 60.0
_DEFAULT_COOLDOWN_S = 60.0
# Reserved completion-token allowance added to every request estimate.
COMPLETION_RESERVE_TOKENS = 800


def estimate_tokens(text: str) -> int:
    """Rough request-size estimate: ~4 chars/token + completion reserve."""
    return max(1, len(text) // 4) + COMPLETION_RESERVE_TOKENS


def caps_for(base_url: str) -> TierCaps:
    base = (base_url or "").lower()
    for fragment, caps in FREE_TIER_DEFAULTS.items():
        if fragment in base:
            return caps
    return TierCaps()


def parse_rate_limit_headers(headers) -> tuple[int | None, int | None]:
    """Extract (remaining_requests, remaining_tokens) from response headers.

    Standard across OpenAI/Groq/Mistral/OpenRouter; absent elsewhere.
    Returns None for anything missing/unparseable.
    """
    def _int(name: str) -> int | None:
        try:
            value = headers.get(name)
            return int(float(value)) if value is not None else None
        except (TypeError, ValueError):
            return None

    return (
        _int("x-ratelimit-remaining-requests"),
        _int("x-ratelimit-remaining-tokens"),
    )


# ---------------------------------------------------------------------------
# Per-provider live state
# ---------------------------------------------------------------------------


@dataclass
class _ProviderHealth:
    # Sliding window of (timestamp, total_tokens) for effective-TPM tracking.
    token_events: deque = field(default_factory=deque)
    request_events: deque = field(default_factory=deque)  # timestamps
    requests_today: int = 0
    day_stamp: int = 0  # day ordinal the daily counter belongs to
    # Last live rate-limit headers (ground truth while fresh).
    remaining_requests: int | None = None
    remaining_tokens: int | None = None
    header_time: float = 0.0
    # Real-429 cooldown.
    cooldown_until: float = 0.0

    def prune(self, now: float) -> None:
        while self.token_events and now - self.token_events[0][0] > _WINDOW_S:
            self.token_events.popleft()
        while self.request_events and now - self.request_events[0] > _WINDOW_S:
            self.request_events.popleft()

    def tokens_in_window(self, now: float) -> int:
        self.prune(now)
        return sum(t for _, t in self.token_events)

    def requests_in_window(self, now: float) -> int:
        self.prune(now)
        return len(self.request_events)


class RotationTracker:
    """Live usage/limit state for every LLM provider + the selection policy."""

    def __init__(self) -> None:
        self._health: dict[str, _ProviderHealth] = {}
        self._tiebreak = 0  # round-robin offset for equal-score groups

    def _h(self, provider_id: str) -> _ProviderHealth:
        return self._health.setdefault(provider_id, _ProviderHealth())

    # ------------------------------------------------------------------
    # Feedback from completed requests
    # ------------------------------------------------------------------

    def record_success(
        self,
        provider_id: str,
        total_tokens: int | None,
        remaining_requests: int | None = None,
        remaining_tokens: int | None = None,
        now: float | None = None,
    ) -> None:
        now = time.monotonic() if now is None else now
        h = self._h(provider_id)
        self._roll_day(h)
        h.request_events.append(now)
        h.requests_today += 1
        if total_tokens:
            h.token_events.append((now, int(total_tokens)))
        if remaining_requests is not None or remaining_tokens is not None:
            h.remaining_requests = remaining_requests
            h.remaining_tokens = remaining_tokens
            h.header_time = now
        # A successful call proves any cooldown is over.
        h.cooldown_until = 0.0

    def record_rate_limited(
        self,
        provider_id: str,
        retry_after_s: float | None = None,
        now: float | None = None,
    ) -> None:
        now = time.monotonic() if now is None else now
        h = self._h(provider_id)
        delay = retry_after_s if retry_after_s and retry_after_s > 0 else _DEFAULT_COOLDOWN_S
        # Cap pathological Retry-After values so a provider can always return.
        h.cooldown_until = now + min(delay, 15 * 60.0)
        h.remaining_tokens = 0
        h.remaining_requests = 0
        h.header_time = now

    def record_error(self, provider_id: str, now: float | None = None) -> None:
        """Non-429 failure (5xx, timeout) — brief cooldown so retries fan out."""
        now = time.monotonic() if now is None else now
        h = self._h(provider_id)
        h.cooldown_until = max(h.cooldown_until, now + 20.0)

    def is_cooling_down(self, provider_id: str, now: float | None = None) -> bool:
        """True while *provider_id* is on post-429 cooldown."""
        now = time.monotonic() if now is None else now
        return self._h(provider_id).cooldown_until > now

    @staticmethod
    def _roll_day(h: _ProviderHealth) -> None:
        today = int(time.time() // 86_400)
        if h.day_stamp != today:
            h.day_stamp = today
            h.requests_today = 0

    # ------------------------------------------------------------------
    # Selection
    # ------------------------------------------------------------------

    def headroom_score(
        self, provider: ProviderConfig, est_tokens: int, now: float
    ) -> float:
        """Headroom of the provider's bottleneck resource, in [0, 1].

        Providers that (by best knowledge) cannot fit *est_tokens* in their
        remaining per-minute token budget score near zero — the "effective
        context" rule that routes long inputs away from low-TPM free tiers.
        """
        h = self._h(provider.id)
        self._roll_day(h)
        caps = caps_for(provider.base_url)
        headers_fresh = (now - h.header_time) <= _HEADER_TTL_S and h.header_time > 0

        # --- token headroom -------------------------------------------------
        if headers_fresh and h.remaining_tokens is not None:
            tokens_left = h.remaining_tokens
            tokens_cap = max(h.remaining_tokens + h.tokens_in_window(now), 1)
        elif caps.tokens_per_minute is not None:
            tokens_left = caps.tokens_per_minute - h.tokens_in_window(now)
            tokens_cap = caps.tokens_per_minute
        else:
            tokens_left, tokens_cap = None, None

        if tokens_left is not None:
            if tokens_left < est_tokens:
                return 0.0  # request does not fit the remaining minute budget
            token_frac = max(0.0, min(1.0, tokens_left / max(tokens_cap, 1)))
        else:
            token_frac = 1.0  # unknown = assume plenty (ordering only)

        # --- request headroom -----------------------------------------------
        req_fracs: list[float] = []
        if headers_fresh and h.remaining_requests is not None:
            denom = max(h.remaining_requests + h.requests_in_window(now), 1)
            req_fracs.append(max(0.0, min(1.0, h.remaining_requests / denom)))
        else:
            if caps.requests_per_minute is not None:
                left = caps.requests_per_minute - h.requests_in_window(now)
                req_fracs.append(max(0.0, left / caps.requests_per_minute))
            if caps.requests_per_day is not None:
                left = caps.requests_per_day - h.requests_today
                req_fracs.append(max(0.0, left / caps.requests_per_day))
        req_frac = min(req_fracs) if req_fracs else 1.0

        return min(token_frac, req_frac)

    def select(
        self,
        providers: list[ProviderConfig],
        est_tokens: int,
        now: float | None = None,
    ) -> list[ProviderConfig]:
        """Return *providers* ordered best-first for this request.

        Cooling-down providers go to the back (ordered by soonest recovery) —
        present but deprioritized, so the caller's fallback chain still
        reaches them if everything else fails.
        """
        now = time.monotonic() if now is None else now
        ready: list[tuple[float, ProviderConfig]] = []
        cooling: list[tuple[float, ProviderConfig]] = []

        for p in providers:
            h = self._h(p.id)
            if h.cooldown_until > now:
                cooling.append((h.cooldown_until, p))
            else:
                ready.append((self.headroom_score(p, est_tokens, now), p))

        # Stable sort by score desc; rotate equal-top groups round-robin so
        # equally-healthy providers share the load.
        ready.sort(key=lambda sp: -sp[0])
        if len(ready) > 1 and ready[0][0] == ready[1][0]:
            top_score = ready[0][0]
            group = [sp for sp in ready if sp[0] == top_score]
            rest = [sp for sp in ready if sp[0] != top_score]
            k = self._tiebreak % len(group)
            self._tiebreak += 1
            ready = group[k:] + group[:k] + rest

        cooling.sort(key=lambda cp: cp[0])
        return [p for _, p in ready] + [p for _, p in cooling]
