"""Windows startup registry helpers for the Launch on Boot setting.

Writes/removes HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run so that
Grain starts automatically at Windows login.  All operations are no-ops on
non-Windows platforms and swallow exceptions so a registry hiccup never
crashes the app.

Two production rules:
  * Only a FROZEN build registers itself — in dev, sys.executable is
    python.exe and a bare "python.exe" Run entry would do nothing useful
    (or worse, flash a console at every login).
  * The entry is re-applied on every app start while the setting is ON
    (see main.py), so it self-heals if the user moves or renames the
    installed app folder.
"""
from __future__ import annotations

import sys

_STARTUP_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
_APP_NAME = "Grain"


def _is_frozen() -> bool:
    return bool(getattr(sys, "frozen", False))


def apply_launch_on_boot(enabled: bool) -> None:
    """Add or remove the Windows startup registry entry.

    Uses sys.executable, which is the installed GrainSTT.exe path in frozen
    builds. The value is quoted so paths with spaces work correctly.
    Enabling from a non-frozen (dev) run is a no-op; disabling always removes
    the entry so a stale registration can be cleared from anywhere.
    """
    if sys.platform != "win32":
        return
    try:
        import winreg  # type: ignore[import]

        if enabled and _is_frozen():
            exe = sys.executable
            with winreg.OpenKey(
                winreg.HKEY_CURRENT_USER, _STARTUP_KEY, 0, winreg.KEY_SET_VALUE
            ) as key:
                winreg.SetValueEx(key, _APP_NAME, 0, winreg.REG_SZ, f'"{exe}"')
        elif not enabled:
            try:
                with winreg.OpenKey(
                    winreg.HKEY_CURRENT_USER, _STARTUP_KEY, 0, winreg.KEY_SET_VALUE
                ) as key:
                    winreg.DeleteValue(key, _APP_NAME)
            except FileNotFoundError:
                pass  # key was already absent — nothing to do
    except Exception:
        pass


def reconcile_launch_on_boot(enabled: bool) -> None:
    """Make the registry agree with the persisted setting at app start.

    Called once on every launch: when the setting is ON, the entry is
    rewritten with THIS executable's path (healing moved/renamed installs and
    upgrades); when OFF, any stale entry is removed.
    """
    apply_launch_on_boot(enabled)


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
