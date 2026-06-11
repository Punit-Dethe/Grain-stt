"""Custom exceptions for Open Voice Router."""

from __future__ import annotations


class ProviderError(Exception):
    """Raised by STTClient or LLMClient on HTTP errors or request timeouts."""


class AudioDeviceError(Exception):
    """Raised by AudioService when the requested audio device is unavailable."""


class KeychainError(Exception):
    """Raised by CredentialStore when the OS keychain is unavailable."""
