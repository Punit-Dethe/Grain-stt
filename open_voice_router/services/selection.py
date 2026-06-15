"""SelectionService — capture the text currently selected in ANY application.

There is no portable OS API for "give me the foreign app's selection", so the
production-standard approach (PowerToys, Raycast, etc.) is a clipboard round
trip:

  1. Remember the user's current clipboard text.
  2. Wait for the hotkey's modifier keys to be physically released — sending
     Ctrl+C while Ctrl+Shift is still held would deliver Ctrl+Shift+C to the
     target app (same failure mode ClipboardService.paste guards against).
  3. Clear the clipboard, send a clean Ctrl+C to the still-focused target app.
  4. Poll briefly for the copy to land.
  5. Restore the user's original clipboard text, then deliver the captured
     selection via callback.

Everything runs on the Qt main thread using chained QTimers — no blocking
sleeps, the UI stays responsive throughout (~100–600 ms total).

Limitations (accepted): non-text clipboard content (images, files) is not
restored, and apps that ignore Ctrl+C with no selection yield "".
"""

from __future__ import annotations

from typing import Callable

from PySide6.QtCore import QObject, QTimer
from PySide6.QtGui import QClipboard
from PySide6.QtWidgets import QApplication

from open_voice_router.services import winput

_MODIFIER_RELEASE_TIMEOUT_MS = 1200
_POLL_INTERVAL_MS = 35
# How long to wait for the target app to service the Ctrl+C.
_COPY_WAIT_TIMEOUT_MS = 420


class SelectionService(QObject):
    """Captures the foreign-app text selection via a clipboard round trip."""

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._busy = False

    def capture(self, on_done: Callable[[str], None]) -> None:
        """Capture the current selection and call ``on_done(text)``.

        ``text`` is "" when nothing was selected (or the app ignored Ctrl+C).
        Re-entrant calls while a capture is in flight return "" immediately.
        Must be called on the Qt main thread.
        """
        if self._busy:
            on_done("")
            return
        self._busy = True
        original = self._clipboard_text()
        self._wait_modifiers_clear(0, original, on_done)

    # ------------------------------------------------------------------
    # Private — chained-timer state machine
    # ------------------------------------------------------------------

    @staticmethod
    def _clipboard_text() -> str:
        try:
            clipboard: QClipboard = QApplication.clipboard()
            return clipboard.text(QClipboard.Mode.Clipboard) or ""
        except Exception:
            return ""

    @staticmethod
    def _set_clipboard(text: str) -> None:
        try:
            QApplication.clipboard().setText(text, QClipboard.Mode.Clipboard)
        except Exception:
            pass

    @staticmethod
    def _modifiers_held() -> bool:
        return winput.modifiers_held()

    def _wait_modifiers_clear(
        self, elapsed_ms: int, original: str, on_done: Callable[[str], None]
    ) -> None:
        if elapsed_ms < _MODIFIER_RELEASE_TIMEOUT_MS and self._modifiers_held():
            QTimer.singleShot(
                _POLL_INTERVAL_MS,
                lambda: self._wait_modifiers_clear(
                    elapsed_ms + _POLL_INTERVAL_MS, original, on_done
                ),
            )
            return
        self._send_copy(original, on_done)

    def _send_copy(self, original: str, on_done: Callable[[str], None]) -> None:
        # Clear first so we can tell a successful copy apart from stale content.
        self._set_clipboard("")
        try:
            winput.send_ctrl_c()
        except Exception:
            self._finish(original, "", on_done)
            return
        QTimer.singleShot(
            _POLL_INTERVAL_MS, lambda: self._poll_copy(0, original, on_done)
        )

    def _poll_copy(
        self, elapsed_ms: int, original: str, on_done: Callable[[str], None]
    ) -> None:
        captured = self._clipboard_text()
        if captured:
            self._finish(original, captured, on_done)
            return
        if elapsed_ms >= _COPY_WAIT_TIMEOUT_MS:
            self._finish(original, "", on_done)
            return
        QTimer.singleShot(
            _POLL_INTERVAL_MS,
            lambda: self._poll_copy(elapsed_ms + _POLL_INTERVAL_MS, original, on_done),
        )

    def _finish(
        self, original: str, captured: str, on_done: Callable[[str], None]
    ) -> None:
        # Give the user their clipboard back — the capture is ours to keep.
        if original or captured:
            self._set_clipboard(original)
        self._busy = False
        on_done(captured)
