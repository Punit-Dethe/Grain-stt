"""ConsoleViewModel — Qt context property for the modular Console window.

This is a lightweight wrapper around SettingsViewModel that provides the same
interface for the new console UI. It delegates all operations to the existing
settings backend, ensuring compatibility and data consistency.
"""

from __future__ import annotations

from PySide6.QtCore import QObject

from open_voice_router.ui.settings.settings_viewmodel import SettingsViewModel


class ConsoleViewModel(SettingsViewModel):
    """View model for the modular Console window.
    
    Inherits all functionality from SettingsViewModel to ensure the new
    console UI uses the same backend, storage, and business logic as the
    original settings window.
    """
    
    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent=parent)
