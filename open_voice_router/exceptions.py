"""Custom exceptions for Open Voice Router."""

from __future__ import annotations


class ProviderError(Exception):
    """Raised by STTClient or LLMClient on HTTP errors or request timeouts."""


class RateLimitError(ProviderError):
    """Raised on HTTP 429 — carries the provider's requested backoff.

    ``retry_after_s`` is parsed from the Retry-After header when present,
    otherwise a sensible default; the rotation tracker uses it to put the
    provider on cooldown instead of hammering it.
    """

    def __init__(self, message: str, retry_after_s: float = 60.0) -> None:
        super().__init__(message)
        self.retry_after_s = retry_after_s


class AudioDeviceError(Exception):
    """Raised by AudioService when the requested audio device is unavailable."""


class KeychainError(Exception):
    """Raised by CredentialStore when the OS keychain is unavailable."""
