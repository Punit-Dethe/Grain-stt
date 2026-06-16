"""Entry point for Open Voice Router.

Responsibilities:
- Create QApplication
- Load persisted settings before any other initialization (Requirement 11.2)
- Instantiate all services, Router, AppController, view models, and QML engine
- Register PillViewModel and SettingsViewModel as QML context properties
- Set up the system tray icon and context menu (Requirements 1.1, 1.2)
- Show tray notification on corrupt config (Requirement 11.3)
- Start the Qt event loop
- No foreground window is opened on startup (Requirement 1.3)
"""

from __future__ import annotations

import dataclasses
import os
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QTimer, QUrl
from PySide6.QtGui import QFontDatabase, QWindow
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

from open_voice_router.app_controller import AppController
from open_voice_router.logger import Logger
from open_voice_router.models import AppSettings, ProviderConfig
from open_voice_router.router import Router
from open_voice_router.services.audio import AudioService
from open_voice_router.services.clipboard import ClipboardService
from open_voice_router.services.hotkey import HotkeyService
from open_voice_router.services.llm_client import LLMClient
from open_voice_router.services.local_stt_manager import LocalSTTManager
from open_voice_router.services.stt_client import STTClient
from open_voice_router.storage.credential_store import CredentialStore
from open_voice_router.storage.settings_store import SettingsStore
from open_voice_router.ui.pill.pill_viewmodel import PillViewModel
from open_voice_router.ui.settings.settings_viewmodel import SettingsViewModel

# Path to the QML UI files.
# In a PyInstaller frozen build the entry-point script's __file__ does not
# reliably resolve to its in-package location, so we detect the frozen case
# explicitly and anchor from sys._MEIPASS (the extraction root).
if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
    _PKG_DIR = Path(sys._MEIPASS) / "open_voice_router"
else:
    _PKG_DIR = Path(__file__).parent
_UI_DIR = _PKG_DIR / "ui"
_FONTS_DIR = _PKG_DIR / "assets" / "fonts"
_ICON_PATH = _PKG_DIR / "assets" / "grain.ico"
_PILL_QML = _UI_DIR / "pill" / "PillWindow.qml"
_CONSOLE_QML = _UI_DIR / "console" / "ConsoleWindow.qml"
_ASSIST_PALETTE_QML = _UI_DIR / "assist" / "AssistPalette.qml"
_ASSIST_PANEL_QML = _UI_DIR / "assist" / "AssistPanel.qml"
_ONBOARDING_QML = _UI_DIR / "onboarding" / "Onboarding.qml"


def _load_bundled_fonts() -> None:
    """Register bundled TTF files with Qt before any QML loads.

    Syne and JetBrains Mono are not guaranteed to be installed on the host
    system; loading them from the bundle ensures every QML font.family
    reference resolves to the correct typeface.
    """
    for ttf in _FONTS_DIR.glob("*.ttf"):
        QFontDatabase.addApplicationFont(str(ttf))


def _write_qml_error(msg: str) -> None:
    """Write a QML load error to a file so it is visible without a console."""
    try:
        import platformdirs
        log_dir = Path(platformdirs.user_log_dir("GrainSTT", "GrainSTT"))
        log_dir.mkdir(parents=True, exist_ok=True)
        with open(log_dir / "qml_error.log", "a", encoding="utf-8") as f:
            from datetime import datetime
            f.write(f"{datetime.now().isoformat()} {msg}")
    except Exception:
        pass


def _open_log_path(log_file_path: str) -> None:
    """Open the log file's containing folder in the OS file manager."""
    import subprocess  # lazy — only needed when user clicks "View Log"

    if not log_file_path:
        return
    folder = os.path.dirname(log_file_path)
    if not os.path.exists(folder):
        return
    if sys.platform == "win32":
        if os.path.exists(log_file_path):
            subprocess.Popen(["explorer", "/select,", log_file_path])
        else:
            subprocess.Popen(["explorer", folder])
    elif sys.platform == "darwin":
        subprocess.Popen(
            ["open", "-R", log_file_path]
            if os.path.exists(log_file_path)
            else ["open", folder]
        )
    else:
        subprocess.Popen(["xdg-open", folder])


def _ensure_local_provider_registered(
    settings: AppSettings,
    settings_store: SettingsStore,
    manager: LocalSTTManager,
) -> AppSettings:
    """Register the bundled local STT provider at startup if it is installed.

    This is a backend concern, intentionally decoupled from the settings
    window: previously the provider was only registered when the UI opened,
    so the hotkey did nothing in tray mode. Here we prepend the local provider
    (making it the active STT engine) and persist it, so a fresh launch with
    the UI never opened still drives on-demand load/unload via the hotkey.

    Idempotent: if the provider is already present, returns settings unchanged.
    """
    pid = LocalSTTManager.PROVIDER_ID
    spec = manager.model_spec
    existing = next((p for p in settings.stt_providers if p.id == pid), None)
    if existing is not None:
        # Keep the registered provider in sync with the selected registry
        # model (the user may have switched models since registration).
        if existing.model == spec.id and existing.name == f"Local ({spec.display_name})":
            return settings
        updated_provider = dataclasses.replace(
            existing, model=spec.id, name=f"Local ({spec.display_name})"
        )
        providers = [
            updated_provider if p.id == pid else p for p in settings.stt_providers
        ]
        updated = dataclasses.replace(settings, stt_providers=providers)
        settings_store.save(updated)
        return updated
    provider = ProviderConfig(
        id=pid,
        name=f"Local ({spec.display_name})",
        base_url=LocalSTTManager.SERVER_URL,
        model=spec.id,
        quota_limit=None,
        quota_used_today=0,
    )
    updated = dataclasses.replace(
        settings, stt_providers=[provider] + list(settings.stt_providers)
    )
    settings_store.save(updated)
    return updated


class _PillStallProbe(QObject):
    """Diagnostic (env GRAIN_PILL_DIAG=1): pinpoint what stalls the GUI thread.

    A QTimer asks to fire every 8 ms ON THE GUI THREAD. If it actually fires far
    later, the GUI thread was blocked for that long — the same blockage that
    freezes the pill. For each stall we also log the process page-fault delta and
    working-set size, so we can tell the cause apart:

      * gap spikes WITH a large page-fault delta  -> memory hard-faults (the
        model-load allocation evicted our pages; the separate-process pill or a
        bigger working-set floor is the fix).
      * gap spikes with NO fault delta            -> pure CPU/scheduling or a
        GPU/compositor stall (a different, cheaper fix).

    Zero cost when the env flag is unset (never instantiated). Logs to stderr,
    which the app already redirects into the server/app log.
    """

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._last = time.monotonic()
        self._last_faults = self._page_faults()
        self._timer = QTimer(self)
        self._timer.setInterval(8)
        self._timer.timeout.connect(self._tick)
        self._timer.start()
        print("[pill-diag] stall probe armed (8 ms tick)", file=sys.stderr, flush=True)

    @staticmethod
    def _mem_counters() -> tuple[int, int]:
        """(PageFaultCount, WorkingSetSize) for this process, or (0, 0)."""
        if sys.platform != "win32":
            return (0, 0)
        try:
            import ctypes
            from ctypes import wintypes

            class _PMC(ctypes.Structure):
                _fields_ = [
                    ("cb", wintypes.DWORD),
                    ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t),
                    ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t),
                    ("PeakPagefileUsage", ctypes.c_size_t),
                ]

            pmc = _PMC()
            pmc.cb = ctypes.sizeof(_PMC)
            h = ctypes.windll.kernel32.GetCurrentProcess()
            if ctypes.windll.psapi.GetProcessMemoryInfo(h, ctypes.byref(pmc), pmc.cb):
                return (int(pmc.PageFaultCount), int(pmc.WorkingSetSize))
        except Exception:
            pass
        return (0, 0)

    def _page_faults(self) -> int:
        return self._mem_counters()[0]

    def _tick(self) -> None:
        now = time.monotonic()
        gap_ms = (now - self._last) * 1000.0
        self._last = now
        faults, ws = self._mem_counters()
        d_faults = faults - self._last_faults
        self._last_faults = faults
        # The timer asks for 8 ms; anything past ~60 ms is a real GUI-thread stall.
        if gap_ms > 60.0:
            print(
                f"[pill-stall] gui_blocked={gap_ms:.0f}ms  pagefaults+={d_faults}  "
                f"ws={ws // (1024 * 1024)}MB",
                file=sys.stderr,
                flush=True,
            )


def main() -> None:
    """Application entry point."""
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName("Open Voice Router")
    app.setOrganizationName("OpenVoiceRouter")

    _load_bundled_fonts()

    # ------------------------------------------------------------------
    # 1. Load settings FIRST (Requirement 11.2)
    # ------------------------------------------------------------------
    settings_store = SettingsStore()
    # Fresh-install detection MUST happen before load() (which materialises
    # defaults): the settings file is absent only on a true first run, which is
    # the single trigger for the one-time onboarding wizard. Existing users —
    # whose file predates the onboarding_complete flag — are never re-onboarded.
    _config_existed = settings_store._path.exists()
    _config_was_corrupt = False

    try:
        settings = settings_store.load()
        # Detect corrupt/missing by comparing to defaults (load() never raises)
        # We detect it by checking if the file exists but returned defaults
        config_path = settings_store._path
        if config_path.exists():
            import json

            try:
                json.loads(config_path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, Exception):
                _config_was_corrupt = True
                settings = AppSettings.defaults()
    except Exception:
        _config_was_corrupt = True
        settings = AppSettings.defaults()

    # ------------------------------------------------------------------
    # 2. Instantiate infrastructure
    # ------------------------------------------------------------------
    # Launch on Boot self-heal: rewrite (or clear) the Run registry entry on
    # every start so it always points at THIS executable — a moved/renamed
    # install or an upgrade can never leave a stale entry behind.
    from open_voice_router.startup_registry import reconcile_launch_on_boot

    reconcile_launch_on_boot(settings.launch_on_boot)

    credential_store = CredentialStore()

    # Ensure log directory exists
    log_dir = os.path.dirname(settings.log_file_path)
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)
    logger = Logger(settings.log_file_path)

    # ------------------------------------------------------------------
    # 3. Instantiate services
    # ------------------------------------------------------------------
    audio_service = AudioService()
    hotkey_service = HotkeyService()
    stt_client = STTClient()
    llm_client = LLMClient()
    clipboard_service = ClipboardService()

    # ------------------------------------------------------------------
    # Local STT manager — created here in the backend so its lifecycle is
    # fully decoupled from the QML front-end (it must work in tray mode with
    # the UI closed). Shared by the settings UI and the session controller so
    # both drive the same process (single-process invariant — R8.5).
    # ------------------------------------------------------------------
    local_stt_manager = LocalSTTManager(model_id=settings.local_stt_model_id)

    # Register the local provider at startup if installed, so the hotkey works
    # with the UI never opened (registration is no longer gated on the settings
    # window). Makes the local engine the active STT provider and persists it.
    # Done before Router/AppController so every consumer sees the same settings.
    if local_stt_manager.is_installed():
        settings = _ensure_local_provider_registered(
            settings, settings_store, local_stt_manager
        )

    # ------------------------------------------------------------------
    # 4. Instantiate Router
    # ------------------------------------------------------------------
    router = Router(settings, settings_store)

    # ------------------------------------------------------------------
    # 5. Instantiate view models
    # ------------------------------------------------------------------
    pill_vm = PillViewModel()

    settings_vm = SettingsViewModel(
        settings_store=settings_store,
        credential_store=credential_store,
        local_stt_manager=local_stt_manager,
    )

    # ------------------------------------------------------------------
    # 6. Instantiate AppController
    # ------------------------------------------------------------------
    controller = AppController(
        settings=settings,
        settings_store=settings_store,
        credential_store=credential_store,
        audio_service=audio_service,
        hotkey_service=hotkey_service,
        stt_client=stt_client,
        llm_client=llm_client,
        clipboard_service=clipboard_service,
        router=router,
        logger=logger,
        pill_viewmodel=pill_vm,
        local_stt_manager=local_stt_manager,
    )

    # ------------------------------------------------------------------
    # 7. Set up QML engine and register context properties
    # ------------------------------------------------------------------
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("pillViewModel", pill_vm)
    engine.rootContext().setContextProperty("settingsViewModel", settings_vm)

    # Load the Pill UI
    engine.load(QUrl.fromLocalFile(str(_PILL_QML)))
    if not engine.rootObjects():
        _qml_err = f"[ERROR] Failed to load Pill QML from {_PILL_QML}\n"
        print(_qml_err, file=sys.stderr)
        _write_qml_error(_qml_err)
    else:
        # The pill loads exactly once — release the QML compilation caches
        # its engine no longer needs (the instantiated tree keeps working).
        engine.trimComponentCache()
        engine.collectGarbage()

    # ------------------------------------------------------------------
    # 7b. Grain Assist — decoupled agent workflow (own controller + engine,
    # same isolation model as the pill; the console window is never involved).
    #
    # The QML engine is LAZY: created on the first summon, destroyed after
    # dismissal (same dispose-and-trim pattern as the console window), so the
    # idle app pays no RAM for assist beyond the lightweight controller.
    # ------------------------------------------------------------------
    from open_voice_router.assist_controller import AssistController

    assist_controller = AssistController(
        settings=settings,
        credential_store=credential_store,
        llm_client=llm_client,
        clipboard_service=clipboard_service,
        # Voice input: a dedicated AudioService (so it never races the dictation
        # capture), the shared stateless STTClient, and the SHARED LocalSTTManager
        # (single-process invariant — both paths must drive the same server).
        audio_service=AudioService(),
        stt_client=stt_client,
        local_stt_manager=local_stt_manager,
    )
    _assist_engine: QQmlApplicationEngine | None = None

    def _ensure_assist_ui() -> None:
        nonlocal _assist_engine
        if _assist_engine is not None:
            return
        _assist_engine = QQmlApplicationEngine()
        _assist_engine.rootContext().setContextProperty(
            "assistViewModel", assist_controller
        )
        _assist_engine.load(QUrl.fromLocalFile(str(_ASSIST_PALETTE_QML)))
        _assist_engine.load(QUrl.fromLocalFile(str(_ASSIST_PANEL_QML)))
        roots = _assist_engine.rootObjects()
        if len(roots) >= 2:
            assist_controller.attach_windows(roots[0], roots[1])
        else:
            _qml_err = "[ERROR] Failed to load Grain Assist QML windows\n"
            print(_qml_err, file=sys.stderr)
            _write_qml_error(_qml_err)
            _assist_engine = None

    def _release_assist_ui() -> None:
        nonlocal _assist_engine
        if _assist_engine is None:
            return
        doomed = _assist_engine
        _assist_engine = None
        # Run the V4 JS-heap GC before teardown (complements clearComponentCache;
        # mirrors the pill load path's trimComponentCache + collectGarbage pair)
        # so QML/JS objects are reclaimed rather than waiting on a later GC tick.
        try:
            doomed.collectGarbage()
        except Exception:
            pass
        try:
            doomed.clearComponentCache()
        except Exception:
            pass
        try:
            doomed.deleteLater()
        except Exception:
            pass
        # Trim AFTER the deferred delete has been processed (next-next tick).
        QTimer.singleShot(0, lambda: QTimer.singleShot(0, _trim_working_set))

    assist_controller.set_ui_hooks(_ensure_assist_ui, _release_assist_ui)

    # The console window gets its own isolated engine created on demand.
    # All QML types it loads (ModuleA/B/C, panels, etc.) live inside that
    # engine and are fully freed when the engine is destroyed on close.
    _console_engine: QQmlApplicationEngine | None = None
    _console_window: QWindow | None = None

    def _trim_working_set() -> None:
        """Release pages freed by Qt's heap back to the OS working set.

        After the Qt engine is deleted, the C runtime heap holds the freed
        pages internally. EmptyWorkingSet forces Windows to page them out,
        so the process footprint returns to baseline in monitoring tools.
        Only called on Windows; no-op on other platforms.
        """
        if sys.platform != "win32":
            return
        try:
            import ctypes

            psapi = ctypes.windll.psapi  # type: ignore[attr-defined]
            kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
            psapi.EmptyWorkingSet(kernel32.GetCurrentProcess())
        except Exception:
            pass

    def _dispose_settings_window() -> None:
        """Tear down the console engine and free all its QML types."""
        nonlocal _console_engine, _console_window

        _console_window = None  # drop window ref first; engine owns the C++ object

        if _console_engine is not None:
            doomed = _console_engine
            _console_engine = None  # release Python reference immediately
            # Run the V4 JS-heap GC before teardown (complements
            # clearComponentCache; mirrors the pill load path) so the console's
            # QML/JS objects are reclaimed promptly instead of on a later tick.
            try:
                doomed.collectGarbage()
            except Exception:
                pass
            try:
                doomed.clearComponentCache()
            except Exception:
                pass
            try:
                doomed.deleteLater()  # schedule C++ destruction via event loop
            except Exception:
                pass
            # Chain a second zero-delay timer so _trim fires in the tick AFTER
            # the DeferredDelete event has been processed (not the same tick).
            QTimer.singleShot(0, lambda: QTimer.singleShot(0, _trim_working_set))

    def _open_settings() -> None:
        nonlocal _console_engine, _console_window

        if _console_engine is None:
            _console_engine = QQmlApplicationEngine()
            _console_engine.rootContext().setContextProperty(
                "consoleViewModel", settings_vm
            )
            _console_engine.load(QUrl.fromLocalFile(str(_CONSOLE_QML)))
            if not _console_engine.rootObjects():
                _qml_err = f"[ERROR] Failed to load Console QML from {_CONSOLE_QML}\n"
                print(_qml_err, file=sys.stderr)
                _write_qml_error(_qml_err)
                _console_engine = None
                return

            from typing import cast as _cast

            _console_window = _cast(QWindow, _console_engine.rootObjects()[0])

            def _on_visibility_changed() -> None:
                if _console_window is not None and not _console_window.isVisible():
                    if not settings_vm._settings.close_to_tray:
                        # "Close to System Tray" is OFF — closing means quit.
                        app.quit()
                    else:
                        QTimer.singleShot(0, _dispose_settings_window)

            _console_window.visibleChanged.connect(_on_visibility_changed)

        settings_vm.load()
        if _console_window is not None:
            _console_window.show()
            _console_window.raise_()
            _console_window.requestActivate()

    # ------------------------------------------------------------------
    # 7c. First-run onboarding — summon-once, destroy-completely.
    #
    # The wizard runs on its OWN throwaway QML engine (same isolation as the
    # console/assist windows). The moment it finishes it is disposed with the
    # identical dispose-and-trim sequence — collectGarbage → clearComponentCache
    # → deleteLater → EmptyWorkingSet — so every byte of the wizard's QML/JS
    # object tree, component cache, and freed heap pages is returned to the OS.
    # The idle app then carries ZERO onboarding footprint; nothing of it is ever
    # re-created (the persisted onboarding_complete flag guarantees a single
    # lifetime). The QML asset stays on disk for a possible "redo setup" later —
    # deleting bundled files from a frozen install would break repair/upgrade
    # for negligible disk savings, so we free RAM only, by design.
    # ------------------------------------------------------------------
    _onboarding_engine: QQmlApplicationEngine | None = None
    _onboarding_window: QWindow | None = None

    def _dispose_onboarding() -> None:
        nonlocal _onboarding_engine, _onboarding_window
        _onboarding_window = None
        if _onboarding_engine is None:
            return
        doomed = _onboarding_engine
        _onboarding_engine = None
        try:
            doomed.collectGarbage()
        except Exception:
            pass
        try:
            doomed.clearComponentCache()
        except Exception:
            pass
        try:
            doomed.deleteLater()
        except Exception:
            pass
        QTimer.singleShot(0, lambda: QTimer.singleShot(0, _trim_working_set))

    def _finish_onboarding() -> None:
        """Persist completion, tear the wizard down, return to the idle tray app."""
        settings_vm.complete_onboarding()
        _dispose_onboarding()

    def _open_onboarding() -> None:
        nonlocal _onboarding_engine, _onboarding_window
        if _onboarding_engine is not None:
            return
        _onboarding_engine = QQmlApplicationEngine()
        # Reuse the SettingsViewModel for every operation (mic, model install,
        # providers, hotkeys, live-test history) so onboarding adds NO backend
        # object — only a transient view tree that is freed on finish.
        _onboarding_engine.rootContext().setContextProperty(
            "consoleViewModel", settings_vm
        )
        _onboarding_engine.load(QUrl.fromLocalFile(str(_ONBOARDING_QML)))
        roots = _onboarding_engine.rootObjects()
        if not roots:
            _qml_err = f"[ERROR] Failed to load Onboarding QML from {_ONBOARDING_QML}\n"
            print(_qml_err, file=sys.stderr)
            _write_qml_error(_qml_err)
            _onboarding_engine = None
            # Don't trap the user on a broken wizard — mark it done so the app
            # proceeds normally on this and every future launch.
            settings_vm.complete_onboarding()
            return
        from typing import cast as _cast

        _onboarding_window = _cast(QWindow, roots[0])
        # The wizard emits finished() on "Done"; closing the window (X / Esc)
        # also completes onboarding so it is never shown twice.
        try:
            _onboarding_window.finished.connect(_finish_onboarding)  # type: ignore[attr-defined]
        except Exception:
            pass

        def _on_ob_visibility() -> None:
            if _onboarding_window is not None and not _onboarding_window.isVisible():
                _finish_onboarding()

        _onboarding_window.visibleChanged.connect(_on_ob_visibility)
        settings_vm.load()
        _onboarding_window.show()
        _onboarding_window.raise_()
        _onboarding_window.requestActivate()

    # ------------------------------------------------------------------
    # 8. System tray icon and context menu (Requirements 1.1, 1.2)
    # ------------------------------------------------------------------
    from PySide6.QtGui import QIcon
    if _ICON_PATH.exists():
        icon = QIcon(str(_ICON_PATH))
    else:
        icon = app.style().standardIcon(app.style().StandardPixmap.SP_ComputerIcon)
    app.setWindowIcon(icon)
    tray = QSystemTrayIcon(icon, parent=app)
    tray.setToolTip("Grain")

    menu = QMenu()

    open_settings_action = menu.addAction("Settings…")
    open_settings_action.triggered.connect(_open_settings)

    view_log_action = menu.addAction("View Log")
    # Capture the log path once — it doesn't change at runtime.
    _log_file_path = settings.log_file_path
    view_log_action.triggered.connect(lambda: _open_log_path(_log_file_path))

    menu.addSeparator()

    copy_transcribed_action = menu.addAction("Copy last transcribed")
    copy_processed_action   = menu.addAction("Copy last processed")

    def _copy_to_clipboard(text: str, label: str) -> None:
        if text:
            app.clipboard().setText(text)
            preview = text[:60] + ("…" if len(text) > 60 else "")
            tray.showMessage(f"Copied {label}", preview, QSystemTrayIcon.MessageIcon.Information, 2000)

    copy_transcribed_action.triggered.connect(
        lambda: _copy_to_clipboard(controller.get_last_transcribed(), "transcription")
    )
    copy_processed_action.triggered.connect(
        lambda: _copy_to_clipboard(controller.get_last_processed(), "processed text")
    )

    menu.addSeparator()

    quit_action = menu.addAction("Quit")
    quit_action.triggered.connect(app.quit)

    tray.setContextMenu(menu)
    tray.show()

    # Wire AppController tray notification signal
    controller.show_notification.connect(
        lambda title, msg: tray.showMessage(title, msg)
    )
    # Wire open settings request (e.g. hotkey conflict)
    controller.open_settings_requested.connect(_open_settings)

    # Wire SettingsViewModel settings_changed → AppController.update_settings.
    # settings_vm._settings is already the freshly saved AppSettings object —
    # no need to hit the disk again with settings_store.load().
    settings_vm.settings_changed.connect(
        lambda: controller.update_settings(settings_vm._settings)
    )
    # Grain Assist follows the same live-settings stream (hotkey rebinds,
    # provider changes take effect on the next summon).
    settings_vm.settings_changed.connect(
        lambda: assist_controller.update_settings(settings_vm._settings)
    )

    # Wire history signals → SettingsViewModel so UI + tray stay in sync
    controller.transcription_result_ready.connect(settings_vm.add_transcription_entry)
    controller.processing_result_ready.connect(settings_vm.add_processing_entry)
    controller.llm_error_occurred.connect(settings_vm.set_llm_error_message)
    # Clear the error banner when processing succeeds
    controller.processing_result_ready.connect(lambda _t, _ts: settings_vm.set_llm_error_message(""))

    # ------------------------------------------------------------------
    # 9. Wire AppController to tray icon for notifications
    # ------------------------------------------------------------------
    controller._tray_icon = tray

    # ------------------------------------------------------------------
    # 10. Setup (registers both hotkeys, wires signals, schedules midnight reset)
    # ------------------------------------------------------------------
    controller.setup()

    # Sync the startup registry entry with the persisted setting so the app
    # stays consistent even after reinstalls or profile migrations.
    from open_voice_router.startup_registry import apply_launch_on_boot
    apply_launch_on_boot(settings.launch_on_boot)

    # ------------------------------------------------------------------
    # 11. Local STT lifecycle wiring (no preload — Requirements 1.1, 1.2)
    # ------------------------------------------------------------------
    # The model is loaded on demand per session by AppController, not at
    # launch. We share the single SettingsViewModel-owned manager instance so
    # the settings UI and the session controller drive the same process
    # (single-process invariant — Requirement 8.5).
    local_mgr = local_stt_manager

    # Surface local STT crashes/startup failures to the user via the tray —
    # otherwise a dead server just makes every transcription silently fail.
    local_mgr.server_crashed.connect(
        lambda reason: tray.showMessage(
            "Local STT stopped",
            "The local speech-to-text server is not running. "
            "Open Settings → Local STT to restart it.\n" + (reason or ""),
        )
    )

    # Stop local STT cleanly when app quits
    app.aboutToQuit.connect(local_mgr.stop)

    # Load-on-startup: when the user has opted in AND the engine is installed,
    # pre-warm the selected model at launch so the first dictation is instant
    # instead of paying the cold Model_Load latency. Deferred so the tray/UI
    # come up first; load() is async and cache-guarded, so a missing snapshot or
    # an uninstalled engine is a safe no-op. Unloading still follows the idle
    # policy (a session end arms request_unload), so this only changes WHEN the
    # first load happens, not whether the model is eventually released.
    if settings.local_stt_load_on_startup and local_mgr.is_installed():
        QTimer.singleShot(
            800, lambda: local_mgr.load(settings.local_stt_load_timeout_s)
        )

    # ------------------------------------------------------------------
    # 11. First run → onboarding wizard; otherwise honour "Launch Minimized".
    # ------------------------------------------------------------------
    # GRAIN_FORCE_ONBOARDING=1 re-triggers the wizard on demand (dev/testing)
    # without wiping the install — completion still just sets the flag.
    _force_onboarding = os.environ.get("GRAIN_FORCE_ONBOARDING") == "1"
    _show_onboarding = _force_onboarding or (
        (not _config_existed) and (not settings.onboarding_complete)
    )
    if _show_onboarding:
        # True fresh install: greet the user with the one-time setup wizard.
        # Deferred so tray + services are fully live (the wizard's live mic test
        # needs the hotkey listener and the model install pipeline running).
        QTimer.singleShot(400, _open_onboarding)
    elif not settings.start_minimized:
        # Defer slightly so the tray icon is fully initialised before the
        # console window appears (avoids a brief flash of the window before
        # the tray icon is ready on slower machines).
        QTimer.singleShot(300, _open_settings)

    # ------------------------------------------------------------------
    # 12. Show tray notification if config was corrupt (Requirement 11.3)
    # ------------------------------------------------------------------
    if _config_was_corrupt:
        tray.showMessage(
            "Configuration reset",
            "The settings file was missing or corrupt. Starting with default settings.",
        )

    # ------------------------------------------------------------------
    # 13. Protect the main process's working set from OS trimming.
    #
    # When the ASR sidecar allocates ~1.2 GB during model load, the Windows
    # Memory Manager satisfies that demand by trimming OTHER processes' working
    # sets — including ours. The pill animates via per-frame JavaScript on the
    # Qt GUI thread (rollDots) reading QML-heap pages; if those pages have been
    # pushed to standby and then repurposed for the model, the GUI thread
    # HARD-FAULTS them back from disk and the pill freezes for the whole load.
    #
    # The floor must therefore cover the LIVE UI hot set — Python runtime +
    # Qt/QML engine + the permanent pill window + its FrameAnimation/dot-state
    # JS heap — NOT a token amount. The previous 80 MB was far below a
    # PySide6+QML app's real ~150-250 MB footprint, so everything above 80 MB
    # (the pill's own pages included) stayed evictable: the app was paging out
    # the very pill it needed resident. 320 MB keeps the whole pill UI pinned
    # through the load storm. A hard minimum only PREVENTS trimming below this
    # size; it does not pad usage, so an app that genuinely uses less is simply
    # never trimmed. Tune via GRAIN_UI_WS_FLOOR_MB on very low-RAM targets.
    # BELOW_NORMAL_PRIORITY_CLASS on the subprocess + reserving a CPU core for
    # the engine (server.py) are the complementary CPU-side fixes.
    # ------------------------------------------------------------------
    if sys.platform == "win32":
        try:
            import ctypes
            _QUOTA_LIMITS_HARDWS_MIN_ENABLE = 0x00000001
            _QUOTA_LIMITS_HARDWS_MAX_DISABLE = 0x00000008
            try:
                _ws_floor_mb = int(os.environ.get("GRAIN_UI_WS_FLOOR_MB", "320"))
            except (TypeError, ValueError):
                _ws_floor_mb = 320
            _ws_floor_mb = max(80, _ws_floor_mb)  # never below the old token floor
            ctypes.windll.kernel32.SetProcessWorkingSetSizeEx(
                ctypes.windll.kernel32.GetCurrentProcess(),
                _ws_floor_mb * 1024 * 1024,  # hard minimum: UI hot set stays resident
                0,                            # maximum: not enforced
                _QUOTA_LIMITS_HARDWS_MIN_ENABLE | _QUOTA_LIMITS_HARDWS_MAX_DISABLE,
            )
        except Exception:
            pass

    # Optional GUI-thread stall probe (env GRAIN_PILL_DIAG=1) — measures what
    # actually freezes the pill during a cold model load. Kept alive for the
    # app's lifetime by this reference; no-op overhead when the flag is unset.
    _pill_probe = None
    if os.environ.get("GRAIN_PILL_DIAG") == "1":
        _pill_probe = _PillStallProbe()

    # ------------------------------------------------------------------
    # 14. Run the event loop
    # ------------------------------------------------------------------
    # One-shot working-set trim once startup has settled: import-time and
    # QML-compilation transients are released back to the OS so the idle
    # footprint monitoring tools report reflects what the app actually holds.
    QTimer.singleShot(8000, _trim_working_set)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
