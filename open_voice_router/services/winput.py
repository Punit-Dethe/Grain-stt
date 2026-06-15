"""winput — minimal Win32 keyboard helpers that install NO hooks.

The third-party ``keyboard`` library installs a global WH_KEYBOARD_LL hook the
first time you call ``is_pressed`` / ``send``, routing every system keystroke
through a Python callback — the same GIL-stall hazard HotkeyService avoids.
These helpers use ``GetAsyncKeyState`` (a passive query) and ``keybd_event``
(a one-shot injection) instead, so nothing ever sits in the global input path.
"""

from __future__ import annotations

import sys

if sys.platform == "win32":
    import ctypes

    _user32 = ctypes.WinDLL("user32", use_last_error=True)

    _VK_CONTROL = 0x11
    _VK_SHIFT   = 0x10
    _VK_MENU    = 0x12  # Alt
    _VK_LWIN    = 0x5B
    _VK_RWIN    = 0x5C
    _KEYEVENTF_KEYUP = 0x0002

    _MODIFIER_VKS = (_VK_CONTROL, _VK_SHIFT, _VK_MENU, _VK_LWIN, _VK_RWIN)

    def modifiers_held() -> bool:
        """True if any Ctrl/Shift/Alt/Win key is physically down right now."""
        return any(
            bool(_user32.GetAsyncKeyState(vk) & 0x8000) for vk in _MODIFIER_VKS
        )

    def _tap_combo(modifier_vk: int, key_vk: int) -> None:
        """Press modifier+key then release both (no hook required)."""
        _user32.keybd_event(modifier_vk, 0, 0, 0)
        _user32.keybd_event(key_vk, 0, 0, 0)
        _user32.keybd_event(key_vk, 0, _KEYEVENTF_KEYUP, 0)
        _user32.keybd_event(modifier_vk, 0, _KEYEVENTF_KEYUP, 0)

    def send_ctrl_v() -> None:
        _tap_combo(_VK_CONTROL, 0x56)  # 'V'

    def send_ctrl_c() -> None:
        _tap_combo(_VK_CONTROL, 0x43)  # 'C'

else:  # pragma: no cover - non-Windows stubs

    def modifiers_held() -> bool:
        return False

    def send_ctrl_v() -> None:
        pass

    def send_ctrl_c() -> None:
        pass
