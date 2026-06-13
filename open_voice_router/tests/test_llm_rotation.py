"""Tests for smart LLM rotation — the live-signal selection policy.

These lock in the design guarantees: selection prefers live headroom, a 429
puts a provider on cooldown (the only hard exclusion), our own estimates only
REORDER (never brick a provider), long requests route away from low-TPM tiers,
and equal-headroom providers share load round-robin.
"""

from __future__ import annotations

from open_voice_router.models import ProviderConfig
from open_voice_router.services.llm_rotation import (
    RotationTracker,
    caps_for,
    estimate_tokens,
    parse_rate_limit_headers,
)


def _p(pid: str, base_url: str = "https://api.example.com/v1") -> ProviderConfig:
    return ProviderConfig(
        id=pid, name=pid, base_url=base_url, model="m", quota_limit=None
    )


GROQ = "https://api.groq.com/openai/v1"
GEMINI = "https://generativelanguage.googleapis.com/v1beta/openai"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def test_estimate_tokens_includes_reserve():
    assert estimate_tokens("") > 0  # completion reserve even for empty input
    assert estimate_tokens("a" * 400) > estimate_tokens("a" * 4)


def test_caps_lookup_by_host():
    assert caps_for(GROQ).tokens_per_minute == 6_000
    assert caps_for(GEMINI).tokens_per_minute == 250_000
    assert caps_for("https://unknown.example.com").tokens_per_minute is None


def test_parse_rate_limit_headers():
    headers = {
        "x-ratelimit-remaining-requests": "12",
        "x-ratelimit-remaining-tokens": "3450",
    }
    assert parse_rate_limit_headers(headers) == (12, 3450)
    assert parse_rate_limit_headers({}) == (None, None)
    assert parse_rate_limit_headers({"x-ratelimit-remaining-tokens": "junk"}) == (None, None)


def test_parse_retry_after_formats():
    from open_voice_router.services.llm_client import _parse_retry_after

    assert _parse_retry_after({"retry-after": "30"}) == 30.0
    assert _parse_retry_after({"retry-after": "2.5s"}) == 2.5
    assert _parse_retry_after({"retry-after": "1m"}) == 60.0
    # Sub-second resets clamp to a 1 s floor (never retry faster than 1 s).
    assert _parse_retry_after({"x-ratelimit-reset-tokens": "500ms"}) == 1.0
    assert _parse_retry_after({}) == 60.0  # default when absent
    assert _parse_retry_after({"retry-after": "garbage"}) == 60.0


# ---------------------------------------------------------------------------
# Cooldown = the only hard exclusion
# ---------------------------------------------------------------------------


def test_429_puts_provider_at_back_until_retry_after():
    t = RotationTracker()
    a, b = _p("a"), _p("b")
    t.record_rate_limited("a", retry_after_s=30, now=1000.0)
    order = t.select([a, b], est_tokens=100, now=1000.0)
    assert order[0].id == "b"  # healthy provider first
    assert order[-1].id == "a"  # cooling-down provider last
    assert t.is_cooling_down("a", now=1000.0)
    # Still present (fallback can reach it), and recovers after the window.
    assert {p.id for p in order} == {"a", "b"}
    assert not t.is_cooling_down("a", now=1031.0)


def test_success_clears_cooldown():
    t = RotationTracker()
    t.record_rate_limited("a", retry_after_s=300, now=0.0)
    assert t.is_cooling_down("a", now=10.0)
    t.record_success("a", total_tokens=50, now=10.0)
    assert not t.is_cooling_down("a", now=10.0)


def test_all_cooling_down_still_returns_all():
    """Never hard-fail on our own bookkeeping — if everyone is cooling down,
    selection still returns the full set (soonest-recovery first)."""
    t = RotationTracker()
    a, b = _p("a"), _p("b")
    t.record_rate_limited("a", retry_after_s=10, now=0.0)
    t.record_rate_limited("b", retry_after_s=60, now=0.0)
    order = t.select([a, b], est_tokens=100, now=0.0)
    assert [p.id for p in order] == ["a", "b"]  # a recovers sooner → first


# ---------------------------------------------------------------------------
# Headroom ordering
# ---------------------------------------------------------------------------


def test_live_headers_drive_ordering():
    """Between two same-tier providers, the one whose live headers report more
    remaining capacity is preferred — headers are the ground-truth signal."""
    t = RotationTracker()
    a, b = _p("a", GROQ), _p("b", GROQ)
    t.record_success("a", total_tokens=10, remaining_tokens=5900, remaining_requests=29, now=100.0)
    t.record_success("b", total_tokens=10, remaining_tokens=200, remaining_requests=2, now=100.0)
    order = t.select([b, a], est_tokens=100, now=100.0)
    assert order[0].id == "a"  # more headroom per the headers


def test_long_request_routes_away_from_low_tpm_tier():
    """A request larger than Groq's free TPM must prefer the roomier Gemini —
    the 'effective context limit' rule."""
    t = RotationTracker()
    groq, gem = _p("groq", GROQ), _p("gem", GEMINI)
    big = 20_000  # >> Groq free 6k TPM, well within Gemini's 250k
    order = t.select([groq, gem], est_tokens=big, now=0.0)
    assert order[0].id == "gem"


def test_wrong_estimate_never_excludes_only_reorders():
    """Even with a request that fits nobody's known cap, both providers are
    still returned — ordering changes, eligibility never does."""
    t = RotationTracker()
    groq, gem = _p("groq", GROQ), _p("gem", GEMINI)
    order = t.select([groq, gem], est_tokens=10_000_000, now=0.0)
    assert {p.id for p in order} == {"groq", "gem"}


def test_unknown_provider_assumed_healthy():
    """A provider with no caps and no headers scores full headroom (ordering
    only) — we never penalise an unknown/self-hosted endpoint."""
    t = RotationTracker()
    custom = _p("custom", "https://my-llm.local/v1")
    order = t.select([custom], est_tokens=5000, now=0.0)
    assert order == [custom]


def test_equal_headroom_rotates_round_robin():
    t = RotationTracker()
    a, b, c = _p("a"), _p("b"), _p("c")  # all unknown host → equal full score
    firsts = [t.select([a, b, c], est_tokens=10, now=0.0)[0].id for _ in range(3)]
    # Round-robin tie-break means the front rotates rather than sticking.
    assert len(set(firsts)) > 1


def test_sliding_window_usage_lowers_headroom():
    t = RotationTracker()
    groq = _p("groq", GROQ)
    base = t.headroom_score(groq, est_tokens=100, now=0.0)
    # Burn most of Groq's per-minute token budget.
    t.record_success("groq", total_tokens=5500, now=0.0)
    after = t.headroom_score(groq, est_tokens=100, now=1.0)
    assert after < base


def test_tracker_leaves_user_quota_to_the_caller():
    """The user's per-provider daily quota is the CALLER's hard gate
    (is_eligible), not part of the tracker's score — so a near-quota provider
    on an unknown host still scores full headroom and is never excluded here."""
    t = RotationTracker()
    p = ProviderConfig(
        id="q", name="q", base_url="https://x/v1", model="m",
        quota_limit=100, quota_used_today=99,
    )
    assert t.headroom_score(p, est_tokens=10, now=0.0) == 1.0
    assert t.select([p], est_tokens=10, now=0.0) == [p]
