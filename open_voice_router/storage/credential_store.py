"""CredentialStore — OS-native secret storage via keyring.

Keys are namespaced as ``open-voice-router/{provider_id}``.

NOTE: ``keyring`` (and its backend stack) costs ~8 MB resident, but it is only
needed once the user actually reads or writes a cloud-provider API key. It is
therefore imported LAZILY inside the methods rather than at module load — a
purely-local-STT install that never touches a cloud key never pays for it, and
even cloud users only pay on first credential access, not at startup. Python
caches the module in ``sys.modules`` so every call after the first is a dict
lookup. This store is instantiated during app startup, so the saving is real.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from open_voice_router.exceptions import KeychainError

if TYPE_CHECKING:  # import only for type checkers — no runtime cost
    import keyring


class CredentialStore:
    """Thin wrapper around keyring for per-provider API key storage."""

    SERVICE_NAME = "open-voice-router"

    @staticmethod
    def _keyring() -> "keyring":
        """Import keyring on demand (see module docstring)."""
        import keyring
        import keyring.errors  # noqa: F401 — registers the .errors attribute

        return keyring

    def set_key(self, provider_id: str, api_key: str) -> None:
        """Store *api_key* for *provider_id* in the OS credential store."""
        keyring = self._keyring()
        try:
            keyring.set_password(self.SERVICE_NAME, provider_id, api_key)
        except keyring.errors.KeyringError as exc:
            raise KeychainError(
                f"Keychain unavailable while storing key for '{provider_id}'"
            ) from exc

    def get_key(self, provider_id: str) -> str | None:
        """Retrieve the API key for *provider_id*, or None if not set."""
        keyring = self._keyring()
        try:
            return keyring.get_password(self.SERVICE_NAME, provider_id)
        except keyring.errors.KeyringError as exc:
            raise KeychainError(
                f"Keychain unavailable while retrieving key for '{provider_id}'"
            ) from exc

    def delete_key(self, provider_id: str) -> None:
        """Remove the stored API key for *provider_id*. No-op if not found."""
        keyring = self._keyring()
        try:
            keyring.delete_password(self.SERVICE_NAME, provider_id)
        except keyring.errors.PasswordDeleteError:
            # Key was not present — treat as a no-op.
            pass
        except keyring.errors.KeyringError as exc:
            raise KeychainError(
                f"Keychain unavailable while deleting key for '{provider_id}'"
            ) from exc
