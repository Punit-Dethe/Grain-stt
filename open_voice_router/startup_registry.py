"""Windows startup registry helpers for the Launch on Boot setting.

Writes/removes HKCU\Software\Microsoft\Windows\CurrentVersion\Run so that
Grain starts automatically at Windows login.  All operations are no-ops on
non-Windows platforms and swallow exceptions so a registry hiccup never
crashes the app.
"""
from __future__ import annotations

import sys

_STARTUP_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
_APP_NAME = "Grain"


def apply_launch_on_boot(enabled: bool) -> None:
    """Add or remove the Windows startup registry entry.

    Uses sys.executable which is the installed GrainSTT.exe path in frozen
    builds. The value is quoted so paths with spaces work correctly.
    """
    if sys.platform != "win32":
        return
    try:
        import winreg  # type: ignore[import]
        if enabled:
            exe = sys.executable
            with winreg.OpenKey(
                winreg.HKEY_CURRENT_USER, _STARTUP_KEY, 0, winreg.KEY_SET_VALUE
            ) as key:
                winreg.SetValueEx(key, _APP_NAME, 0, winreg.REG_SZ, f'"{exe}"')
        else:
            try:
                with winreg.OpenKey(
                    winreg.HKEY_CURRENT_USER, _STARTUP_KEY, 0, winreg.KEY_SET_VALUE
                ) as key:
                    winreg.DeleteValue(key, _APP_NAME)
            except FileNotFoundError:
                pass  # key was already absent — nothing to do
    except Exception:
        pass


def is_registered() -> bool:
    """Return True if the Grain startup registry entry currently exists."""
    if sys.platform != "win32":
        return False
    try:
        import winreg  # type: ignore[import]
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, _STARTUP_KEY) as key:
            winreg.QueryValueEx(key, _APP_NAME)
            return True
    except (FileNotFoundError, OSError):
        return False
