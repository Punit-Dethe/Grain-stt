"""HotkeyService — global hotkeys via the Win32 RegisterHotKey API.

Why NOT a WH_KEYBOARD_LL low-level hook:
    A low-level keyboard hook routes EVERY keystroke in the whole OS
    synchronously through a Python ctypes callback, which must take the GIL
    for every key.  While any other thread (e.g. the Qt main thread during
    startup or model loading) holds the GIL, the callback cannot run, and
    Windows stalls *all* keyboard input system-wide until it does.  The result
    is "my keyboard is dead while the app is launching".

RegisterHotKey has none of that exposure: the kernel matches the combo and
posts WM_HOTKEY to our message-only thread ONLY when our specific combo is
pressed.  It installs no system-wide input filter, so it can never block or
delay any other keystroke.  The matched combo is consumed (not delivered to
the foreground app), which is exactly what we want for an app hotkey.

A single daemon thread owns every registration (RegisterHotKey is thread-
affine — the thread that registers is the thread that receives WM_HOTKEY) and
runs the GetMessage pump.  Registration requests from other threads are handed
to it via PostThreadMessage and executed on the pump thread.
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

    # ── Win32 constants ──────────────────────────────────────────────────────
    MOD_ALT      = 0x0001
    MOD_CONTROL  = 0x0002
    MOD_SHIFT    = 0x0004
    MOD_WIN      = 0x0008
    MOD_NOREPEAT = 0x4000  # don't fire repeatedly while the key is held

    WM_HOTKEY = 0x0312
    WM_APP    = 0x8000
    _WM_COMMAND_WAKE = WM_APP + 1   # "drain the pending command queue"
    PM_NOREMOVE = 0x0000

    VK_SHIFT   = 0x10
    VK_CONTROL = 0x11
    VK_MENU    = 0x12   # Alt
    VK_LWIN    = 0x5B

    # Modifier token → RegisterHotKey modifier bit.
    _MOD_BITS: dict[str, int] = {
        "ctrl": MOD_CONTROL, "control": MOD_CONTROL,
        "shift": MOD_SHIFT,
        "alt": MOD_ALT,
        "win": MOD_WIN, "windows": MOD_WIN, "super": MOD_WIN,
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

    _user32.RegisterHotKey.restype = ctypes.wintypes.BOOL
    _user32.RegisterHotKey.argtypes = [
        ctypes.wintypes.HWND, ctypes.c_int,
        ctypes.wintypes.UINT, ctypes.wintypes.UINT,
    ]
    _user32.UnregisterHotKey.restype = ctypes.wintypes.BOOL
    _user32.UnregisterHotKey.argtypes = [ctypes.wintypes.HWND, ctypes.c_int]
    _user32.PostThreadMessageW.restype = ctypes.wintypes.BOOL
    _user32.PostThreadMessageW.argtypes = [
        ctypes.wintypes.DWORD, ctypes.wintypes.UINT,
        ctypes.wintypes.WPARAM, ctypes.wintypes.LPARAM,
    ]

    def _parse_combo(key_combo: str) -> tuple[int, int] | None:
        """'ctrl+shift+space' → (MOD_CONTROL|MOD_SHIFT, 0x20), or None if invalid.

        Bare keys with no modifiers (e.g. 'esc') return (0, vk).
        """
        parts = [p.strip().lower() for p in key_combo.split("+") if p.strip()]
        if not parts:
            return None
        mods = 0
        vk: int | None = None
        for part in parts:
            if part in _MOD_BITS:
                mods |= _MOD_BITS[part]
            elif part in _SPECIAL_VK:
                vk = _SPECIAL_VK[part]
            elif len(part) == 1:
                low = _user32.VkKeyScanW(ord(part)) & 0xFF
                if low == 0xFF:
                    return None
                vk = low
            else:
                return None
        if vk is None:
            return None
        return mods, vk

    # ── Shared pump-thread state ─────────────────────────────────────────────
    _lock = threading.Lock()
    _id_to_service: dict[int, "HotkeyService"] = {}
    _next_id = 1
    _pending: list[dict] = []          # command queue drained on the pump thread
    _thread_id: int | None = None
    _ready = threading.Event()
    _pump_started = False

    def _drain_commands() -> None:
        """Run on the pump thread: perform queued (un)register calls."""
        with _lock:
            cmds = _pending[:]
            _pending.clear()
        for cmd in cmds:
            if cmd["op"] == "reg":
                ok = bool(
                    _user32.RegisterHotKey(None, cmd["id"], cmd["mods"], cmd["vk"])
                )
                if ok:
                    with _lock:
                        _id_to_service[cmd["id"]] = cmd["svc"]
                cmd["res"][0] = ok
            else:  # "unreg"
                _user32.UnregisterHotKey(None, cmd["id"])
                with _lock:
                    _id_to_service.pop(cmd["id"], None)
                cmd["res"][0] = True
            cmd["ev"].set()

    def _pump_main() -> None:
        global _thread_id
        _thread_id = _kernel32.GetCurrentThreadId()
        # Force the thread message queue into existence before anyone posts to it.
        msg = ctypes.wintypes.MSG()
        _user32.PeekMessageW(ctypes.byref(msg), None, WM_APP, WM_APP, PM_NOREMOVE)
        _ready.set()

        while True:
            ret = _user32.GetMessageW(ctypes.byref(msg), None, 0, 0)
            if ret in (0, -1):
                break
            if msg.message == WM_HOTKEY:
                with _lock:
                    svc = _id_to_service.get(int(msg.wParam))
                if svc is not None:
                    svc.hotkey_triggered.emit()
            elif msg.message == _WM_COMMAND_WAKE:
                _drain_commands()

    def _ensure_pump() -> None:
        global _pump_started
        if _pump_started:
            return
        _pump_started = True
        threading.Thread(
            target=_pump_main, name="grain-hotkey-pump", daemon=True
        ).start()
        _ready.wait(2.0)  # wait until the thread message queue exists

    def _submit(op: str, **kw) -> bool:
        """Hand a register/unregister command to the pump thread and wait."""
        _ensure_pump()
        ev = threading.Event()
        res = [False]
        with _lock:
            _pending.append({"op": op, "ev": ev, "res": res, **kw})
        if _thread_id is not None:
            _user32.PostThreadMessageW(_thread_id, _WM_COMMAND_WAKE, 0, 0)
        ev.wait(2.0)
        return res[0]

    def _alloc_id() -> int:
        global _next_id
        with _lock:
            hid = _next_id
            _next_id += 1
        return hid


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

class HotkeyService(QObject):
    """Registers one global hotkey and emits ``hotkey_triggered`` when pressed."""

    hotkey_triggered = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._id: int | None = None

    def register(self, key_combo: str) -> bool:
        """Register *key_combo* (e.g. 'ctrl+shift+space').  Returns True on success."""
        self.unregister()

        if sys.platform != "win32":
            return False

        parsed = _parse_combo(key_combo)
        if parsed is None:
            return False

        mods, vk = parsed
        hid = _alloc_id()
        ok = _submit("reg", id=hid, mods=mods | MOD_NOREPEAT, vk=vk, svc=self)
        if ok:
            self._id = hid
        return ok

    def unregister(self) -> None:
        """Remove this service's hotkey.  No-op if none registered."""
        if self._id is None:
            return
        if sys.platform == "win32":
            _submit("unreg", id=self._id)
        self._id = None
