"""Dev tool — preview the first-run onboarding wizard in isolation.

    python run_onboarding.py

Boots ONLY the SettingsViewModel (the same object the real app injects as
`consoleViewModel`) plus the Onboarding QML — no tray, no hotkey daemon, no
model server — so it opens instantly for fast UI iteration. The provider/preset
data flow is real (presets, mic list, add-provider all work against your actual
settings); only the live mic→transcription test needs the full app.

This does NOT touch the persisted `onboarding_complete` flag, so it never
affects whether the real app shows onboarding. To exercise the genuine first-run
path end-to-end (live mic test included), launch the real app with the override:

    PowerShell:  $env:GRAIN_FORCE_ONBOARDING=1; python -m open_voice_router.main
"""

from __future__ import annotations

import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from open_voice_router.main import _UI_DIR, _load_bundled_fonts
from open_voice_router.services.local_stt_manager import LocalSTTManager
from open_voice_router.storage.credential_store import CredentialStore
from open_voice_router.storage.settings_store import SettingsStore
from open_voice_router.ui.settings.settings_viewmodel import SettingsViewModel


def main() -> None:
    app = QGuiApplication(sys.argv)
    _load_bundled_fonts()

    settings_store = SettingsStore()
    settings = settings_store.load()
    vm = SettingsViewModel(
        settings_store=settings_store,
        credential_store=CredentialStore(),
        local_stt_manager=LocalSTTManager(model_id=settings.local_stt_model_id),
    )

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("consoleViewModel", vm)
    engine.load(QUrl.fromLocalFile(str(Path(_UI_DIR) / "onboarding" / "Onboarding.qml")))
    roots = engine.rootObjects()
    if not roots:
        print("Failed to load Onboarding.qml", file=sys.stderr)
        sys.exit(1)

    win = roots[0]
    win.setProperty("visible", True)
    # Quit when the wizard finishes or its window closes.
    try:
        win.finished.connect(app.quit)  # type: ignore[attr-defined]
    except Exception:
        pass
    win.visibleChanged.connect(lambda: app.quit() if not win.isVisible() else None)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
