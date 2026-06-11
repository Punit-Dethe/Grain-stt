"""HotkeyService — global hotkey registration via the keyboard library."""

from __future__ import annotations

import keyboard
from PySide6.QtCore import QMetaObject, QObject, Qt, Signal


class HotkeyService(QObject):
    """Registers a global hotkey and delivers presses to the Qt main thread.

    The ``keyboard`` library runs its listener on a daemon thread internally.
    When the hotkey fires, the callback uses ``QMetaObject.invokeMethod`` with
    ``QueuedConnection`` to safely marshal the signal emission onto the main
    Qt event loop thread.
    """

    hotkey_triggered = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._registered_combo: str | None = None

    def register(self, key_combo: str) -> bool:
        """Register *key_combo* as the global hotkey.

        Returns ``True`` on success, ``False`` if the hotkey is already claimed
        (i.e. ``keyboard.add_hotkey`` raises any exception).
        """
        # Unregister any previously registered hotkey first.
        self.unregister()

        try:
            keyboard.add_hotkey(key_combo, self._on_hotkey_fired)
        except Exception:
            return False

        self._registered_combo = key_combo
        return True

    def unregister(self) -> None:
        """Unregister the currently active hotkey, if any.

        No-op when no hotkey is registered.
        """
        if self._registered_combo is not None:
            try:
                keyboard.remove_hotkey(self._registered_combo)
            except Exception:
                pass
            finally:
                self._registered_combo = None

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _on_hotkey_fired(self) -> None:
        """Callback invoked on the keyboard library's background thread.

        Marshals the ``hotkey_triggered`` signal emission onto the main Qt
        thread via a queued connection so Qt's thread-safety rules are
        respected.
        """
        QMetaObject.invokeMethod(
            self,
            "hotkey_triggered",
            Qt.ConnectionType.QueuedConnection,
        )
