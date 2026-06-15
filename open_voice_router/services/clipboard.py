"""ClipboardService — clipboard access and robust paste simulation.

The paste is the most failure-prone step in the whole pipeline, because the
app simulates Ctrl+V while the user may still be physically holding the hotkey
modifier keys (e.g. ctrl+shift). If we fire Ctrl+V then, the OS actually sees
Ctrl+Shift+V — which is NOT paste in most apps. That is the #1 cause of
"it didn't paste, I had to Ctrl+V manually".

Strategy:
  1. Always set the clipboard first (synchronously). This guarantees that even
     if the simulated keystroke fails for any reason, the user can paste
     manually — the text is never lost.
  2. Wait for the user to RELEASE all modifier keys before sending Ctrl+V, so
     the keystroke is a clean paste. Poll briefly with a timeout.
  3. Send Ctrl+V once modifiers are clear (or after a safety timeout).
"""

from __future__ import annotations

from PySide6.QtCore import QObject, QTimer
from PySide6.QtGui import QClipboard
from PySide6.QtWidgets import QApplication

from open_voice_router.services import winput

# How long to wait (total) for the user to release modifier keys before we
# give up waiting and paste anyway.
_MODIFIER_RELEASE_TIMEOUT_MS = 1500
_POLL_INTERVAL_MS = 40


class ClipboardService(QObject):
    """Wraps QClipboard and provides a robust paste helper."""

    def set(self, text: str) -> None:
        """Copy text to the system clipboard without pasting."""
        clipboard: QClipboard = QApplication.clipboard()
        clipboard.setText(text, QClipboard.Mode.Clipboard)

    def paste(self, text: str) -> None:
        """Copy text to the clipboard, then simulate Ctrl+V once the user has
        released any held modifier keys.

        The clipboard is set immediately and synchronously, so the text is
        always available for a manual paste even if the simulated keystroke
        cannot fire.
        """
        if not text:
            return
        self.set(text)
        # Begin the release-aware paste sequence on the main thread.
        QTimer.singleShot(_POLL_INTERVAL_MS, lambda: self._paste_when_clear(0))

    # ------------------------------------------------------------------
    # Private
    # ------------------------------------------------------------------

    def _modifiers_held(self) -> bool:
        """Return True if any paste-corrupting modifier key is physically held."""
        return winput.modifiers_held()

    def _paste_when_clear(self, elapsed_ms: int) -> None:
        """Wait for modifier keys to release (up to a timeout), then send Ctrl+V."""
        if elapsed_ms < _MODIFIER_RELEASE_TIMEOUT_MS and self._modifiers_held():
            # User is still holding the hotkey — poll again shortly.
            QTimer.singleShot(
                _POLL_INTERVAL_MS,
                lambda: self._paste_when_clear(elapsed_ms + _POLL_INTERVAL_MS),
            )
            return
        self._send_paste()

    def _send_paste(self) -> None:
        """Fire a clean Ctrl+V. Clipboard already holds the text as a fallback."""
        try:
            winput.send_ctrl_v()
        except Exception:
            # Swallow — the text is already on the clipboard for manual paste.
            pass
