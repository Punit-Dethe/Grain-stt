"""CredentialStore — OS-native secret storage via keyring.

Keys are namespaced as ``open-voice-router/{provider_id}``.
"""

from __future__ import annotations

import keyring
import keyring.errors

from open_voice_router.exceptions import KeychainError


class CredentialStore:
    """Thin wrapper around keyring for per-provider API key storage."""

    SERVICE_NAME = "open-voice-router"

    def set_key(self, provider_id: str, api_key: str) -> None:
        """Store *api_key* for *provider_id* in the OS credential store."""
        try:
            keyring.set_password(self.SERVICE_NAME, provider_id, api_key)
        except keyring.errors.KeyringError as exc:
            raise KeychainError(
                f"Keychain unavailable while storing key for '{provider_id}'"
            ) from exc

    def get_key(self, provider_id: str) -> str | None:
        """Retrieve the API key for *provider_id*, or None if not set."""
        try:
            return keyring.get_password(self.SERVICE_NAME, provider_id)
        except keyring.errors.KeyringError as exc:
            raise KeychainError(
                f"Keychain unavailable while retrieving key for '{provider_id}'"
            ) from exc

    def delete_key(self, provider_id: str) -> None:
        """Remove the stored API key for *provider_id*. No-op if not found."""
        try:
            keyring.delete_password(self.SERVICE_NAME, provider_id)
        except keyring.errors.PasswordDeleteError:
            # Key was not present — treat as a no-op.
            pass
        except keyring.errors.KeyringError as exc:
            raise KeychainError(
                f"Keychain unavailable while deleting key for '{provider_id}'"
            ) from exc
