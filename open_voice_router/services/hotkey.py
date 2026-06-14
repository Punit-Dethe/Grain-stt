"""HotkeyService — global hotkeys via WH_KEYBOARD_LL low-level keyboard hook.

Implemented directly with ctypes (no third-party keyboard library) so it works
reliably in frozen PyInstaller builds.  A WH_KEYBOARD_LL hook intercepts keys
before Windows processes them, bypassing system-reserved combo reservations
(e.g. Windows IME switcher on Ctrl+Shift+Space).

A single daemon thread runs the required GetMessage pump to keep the hook
alive.  The hook callback fires on that thread; Qt cross-thread auto-connections
marshal signal delivery to the main Qt event-loop thread.
"""

from __future__ import annotations

import sys
import threading
from PySide6.QtCore import QObject, Signal

# ---------------------------------------------------------------------------
# Windows implementation
# ---------------------------------------------------------------------------

if sys.platform == "win32":
    import ctypes
    import ctypes.wintypes

    _user32 = ctypes.WinDLL("user32", use_last_error=True)
    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    # Hook type and message constants
    WH_KEYBOARD_LL = 13
    WM_KEYDOWN     = 0x0100
    WM_SYSKEYDOWN  = 0x0104
    WM_QUIT        = 0x0012
    HC_ACTION      = 0

    # Virtual key codes for modifier keys
    VK_SHIFT   = 0x10
    VK_CONTROL = 0x11
    VK_MENU    = 0x12   # Alt
    VK_LWIN    = 0x5B
    VK_RWIN    = 0x5C

    class _KBDLLHOOKSTRUCT(ctypes.Structure):
        _fields_ = [
            ("vkCode",      ctypes.wintypes.DWORD),
            ("scanCode",    ctypes.wintypes.DWORD),
            ("flags",       ctypes.wintypes.DWORD),
            ("time",        ctypes.wintypes.DWORD),
            ("dwExtraInfo", ctypes.c_ulong),
        ]

    _HOOKPROC = ctypes.WINFUNCTYPE(
        ctypes.c_long,
        ctypes.c_int,
        ctypes.wintypes.WPARAM,
        ctypes.wintypes.LPARAM,
    )

    # Maps modifier token → list of VK codes (any must be pressed)
    _MOD_VK: dict[str, list[int]] = {
        "ctrl":    [VK_CONTROL],
        "control": [VK_CONTROL],
        "shift":   [VK_SHIFT],
        "alt":     [VK_MENU],
        "win":     [VK_LWIN, VK_RWIN],
        "windows": [VK_LWIN, VK_RWIN],
        "super":   [VK_LWIN, VK_RWIN],
    }

    _SPECIAL_VK: dict[str, int] = {
        "space": 0x20, "spacebar": 0x20,
        "enter": 0x0D, "return": 0x0D,
        "tab": 0x09,
        "backspace": 0x08,
        "escape": 0x1B, "esc": 0x1B,
        "delete": 0x2E, "del": 0x2E,
        "insert": 0x2D, "ins": 0x2D,
        "home": 0x24, "end": 0x23,
        "pageup": 0x21, "pgup": 0x21,
        "pagedown": 0x22, "pgdn": 0x22,
        "left": 0x25, "right": 0x27, "up": 0x26, "down": 0x28,
        "f1":  0x70, "f2":  0x71, "f3":  0x72, "f4":  0x73,
        "f5":  0x74, "f6":  0x75, "f7":  0x76, "f8":  0x77,
        "f9":  0x78, "f10": 0x79, "f11": 0x7A, "f12": 0x7B,
        "f13": 0x7C, "f14": 0x7D, "f15": 0x7E, "f16": 0x7F,
        "f17": 0x80, "f18": 0x81, "f19": 0x82, "f20": 0x83,
        "f21": 0x84, "f22": 0x85, "f23": 0x86, "f24": 0x87,
        "numpad0": 0x60, "numpad1": 0x61, "numpad2": 0x62, "numpad3": 0x63,
        "numpad4": 0x64, "numpad5": 0x65, "numpad6": 0x66, "numpad7": 0x67,
        "numpad8": 0x68, "numpad9": 0x69,
        "multiply": 0x6A, "add": 0x6B, "subtract": 0x6D,
        "decimal": 0x6E, "divide": 0x6F,
        "capslock": 0x14, "numlock": 0x90, "scrolllock": 0x91,
        "pause": 0x13, "printscreen": 0x2C, "prtsc": 0x2C,
    }

    def _parse_combo(key_combo: str) -> tuple[frozenset[str], int] | None:
        """'ctrl+shift+space' → (frozenset{'ctrl','shift'}, 0x20) or None.

        Bare keys with no modifiers (e.g. 'esc') return an empty frozenset;
        the hook fires whenever that VK is pressed regardless of modifier state.
        """
        parts = [p.strip().lower() for p in key_combo.split("+")]
        mods: set[str] = set()
        vk: int | None = None
        for part in parts:
            if part in _MOD_VK:
                mods.add(part)
            elif part in _SPECIAL_VK:
                vk = _SPECIAL_VK[part]
            elif len(part) == 1:
                result = _user32.VkKeyScanW(ord(part))
                low = result & 0xFF
                if low == 0xFF:
                    return None
                vk = low
            else:
                return None
        if vk is None:
            return None
        return frozenset(mods), vk

    def _mod_held(mod: str) -> bool:
        """True if any VK for *mod* is physically pressed right now."""
        return any(
            bool(_user32.GetAsyncKeyState(v) & 0x8000)
            for v in _MOD_VK.get(mod, [])
        )

    # ---------------------------------------------------------------------------
    # Global hook state
    # ---------------------------------------------------------------------------

    _lock = threading.Lock()

    # Each entry: (modifier_set, vk_code, HotkeyService)
    _registered: list[tuple[frozenset[str], int, "HotkeyService"]] = []

    _hook_handle: ctypes.c_void_p | None = None
    _hook_thread_id: int | None = None
    _hook_proc_ref: object = None   # prevent GC of ctypes callback

    def _low_level_proc(nCode: int, wParam: int, lParam: int) -> int:
        if nCode == HC_ACTION and wParam in (WM_KEYDOWN, WM_SYSKEYDOWN):
            event = ctypes.cast(lParam, ctypes.POINTER(_KBDLLHOOKSTRUCT)).contents
            vk = event.vkCode
            with _lock:
                for mod_set, req_vk, svc in _registered:
                    if vk != req_vk:
                        continue
                    if all(_mod_held(m) for m in mod_set):
                        svc.hotkey_triggered.emit()
                        return 1   # suppress key — prevents Windows from acting on it
        return _user32.CallNextHookEx(None, nCode, wParam, lParam)

    def _hook_thread_main() -> None:
        global _hook_handle, _hook_thread_id, _hook_proc_ref

        proc = _HOOKPROC(_low_level_proc)
        _hook_proc_ref = proc   # keep alive for the duration of the thread

        handle = _user32.SetWindowsHookExW(WH_KEYBOARD_LL, proc, None, 0)
        _hook_handle = handle
        _hook_thread_id = _kernel32.GetCurrentThreadId()

        # Pump messages — required to keep WH_KEYBOARD_LL alive and receive
        # hook notifications on this thread.
        msg = ctypes.wintypes.MSG()
        while _user32.GetMessageW(ctypes.byref(msg), None, 0, 0) != 0:
            _user32.TranslateMessage(ctypes.byref(msg))
            _user32.DispatchMessageW(ctypes.byref(msg))

        # Cleanup after WM_QUIT
        if _hook_handle:
            _user32.UnhookWindowsHookEx(_hook_handle)
            _hook_handle = None

    _hook_started = False

    def _ensure_hook() -> None:
        global _hook_started
        if not _hook_started:
            _hook_started = True
            t = threading.Thread(
                target=_hook_thread_main,
                name="grain-hotkey-hook",
                daemon=True,
            )
            t.start()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

class HotkeyService(QObject):
    """Registers one global hotkey and emits ``hotkey_triggered`` when pressed."""

    hotkey_triggered = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._combo: tuple[frozenset[str], int] | None = None

    def register(self, key_combo: str) -> bool:
        """Register *key_combo* (e.g. 'ctrl+shift+space').  Returns True on success."""
        self.unregister()

        if sys.platform != "win32":
            return False

        parsed = _parse_combo(key_combo)
        if parsed is None:
            return False

        _ensure_hook()

        with _lock:
            _registered.append((parsed[0], parsed[1], self))

        self._combo = parsed
        return True

    def unregister(self) -> None:
        """Remove this service's hotkey.  No-op if none registered."""
        if self._combo is None:
            return
        if sys.platform == "win32":
            mod_set, vk = self._combo
            with _lock:
                _registered[:] = [
                    e for e in _registered
                    if not (e[0] == mod_set and e[1] == vk and e[2] is self)
                ]
        self._combo = None
