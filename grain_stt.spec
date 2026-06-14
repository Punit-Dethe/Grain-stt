# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for Grain STT
# Build from the project root:  pyinstaller grain_stt.spec

from pathlib import Path
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

ROOT = Path(".").resolve()

# ---------------------------------------------------------------------------
# Data files — non-Python assets that must be available at runtime
# ---------------------------------------------------------------------------
datas = [
    # All custom QML UI files (pill + console).
    # Destination mirrors the source tree so Path(__file__) references in
    # main.py and local_stt_manager.py resolve without any code changes.
    (str(ROOT / "open_voice_router" / "ui"), "open_voice_router/ui"),

    # Bundled TTF fonts — loaded at startup via QFontDatabase.addApplicationFont()
    # so Syne and JetBrains Mono are available even on systems where they are
    # not installed.
    (str(ROOT / "open_voice_router" / "assets" / "fonts"), "open_voice_router/assets/fonts"),

    # App icon — bundled so the tray can load it at runtime from sys._MEIPASS
    (str(ROOT / "open_voice_router" / "assets" / "grain.ico"), "open_voice_router/assets"),

    # Local ASR sidecar is spawned as a subprocess under the user's own venv
    # Python (not the bundled interpreter), so it must live as plain .py
    # files that the venv Python can execute directly. The whole tree is
    # bundled: server.py (HTTP layer), registry.py (model catalog),
    # engines/ (per-engine wrappers), requirements.txt (base deps).
    (str(ROOT / "open_voice_router" / "local_asr"),
     "open_voice_router/local_asr"),
]

# ---------------------------------------------------------------------------
# Hidden imports — things PyInstaller's static analysis misses
# ---------------------------------------------------------------------------
hidden = [
    # keyring: Windows Credential Manager backend is selected at runtime
    "keyring.backends.Windows",
    "keyring.backends.fail",

    # httpx transport is dynamically loaded
    "httpx._transports.default",
    "httpx._transports.asgi",

    # keyboard: clipboard.py / selection.py use keyboard.send() and
    # keyboard.is_pressed() for paste/copy automation — bundle the backend.
    "keyboard._winkeyboard",

    # All open_voice_router submodules (belt-and-suspenders; analysis usually
    # catches these but listing them avoids surprises with lazy imports)
    *collect_submodules("open_voice_router"),
]

# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------
a = Analysis(
    [str(ROOT / "open_voice_router" / "main.py")],
    pathex=[str(ROOT)],
    binaries=[],
    datas=datas,
    hiddenimports=hidden,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Test dependencies — not needed at runtime
        "hypothesis",
        "pytest",
        "_pytest",
        "open_voice_router.tests",
        # Local ASR server deps live in a separate user venv, not bundled here
        "flask",
        "waitress",
        "onnxruntime",
        "werkzeug",
        "huggingface_hub",
        # Unused PySide6 / Qt modules — exclude the Python wrappers so their
        # hooks don't pull the corresponding DLLs into the bundle.
        "PySide6.QtWebEngineCore",
        "PySide6.QtWebEngineWidgets",
        "PySide6.QtWebEngineQuick",
        "PySide6.Qt3DCore",
        "PySide6.Qt3DRender",
        "PySide6.Qt3DInput",
        "PySide6.Qt3DAnimation",
        "PySide6.Qt3DExtras",
        "PySide6.Qt3DLogic",
        "PySide6.QtQuick3D",
        "PySide6.QtGraphs",
        "PySide6.QtPdf",
        "PySide6.QtPdfWidgets",
        "PySide6.QtDataVisualization",
        "PySide6.QtCharts",
        "PySide6.QtLocation",
        "PySide6.QtPositioning",
        "PySide6.QtRemoteObjects",
        "PySide6.QtScxml",
        "PySide6.QtSensors",
        "PySide6.QtStateMachine",
        "PySide6.QtTextToSpeech",
        "PySide6.QtVirtualKeyboard",
        # PIL/Pillow — not used by this app; pulled in transitively
        "PIL",
    ],
    noarchive=False,
    # -O level 1: strips asserts/__debug__ blocks from all bundled bytecode.
    # (Level 2 also strips docstrings but is riskier with numpy — not worth it.)
    optimize=1,
)

# ---------------------------------------------------------------------------
# Drop Qt DLLs that were pulled in despite the excludes above.
# PyInstaller's PySide6 hooks sometimes collect DLLs via dependency scanning
# even when the Python wrapper module is excluded.  Belt-and-suspenders filter.
# ---------------------------------------------------------------------------
_QT_DLL_EXCLUDE_PREFIXES = (
    "Qt6WebEngine",       # Chromium — 195 MB, not used
    "Qt63D",              # 3D rendering, not used
    "Qt6Quick3D",
    "Qt6Graphs",
    "Qt6Pdf",
    "Qt6DataVisualization",
    "Qt6Charts",
    "Qt6Location",
    "Qt6Positioning",
    "Qt6RemoteObjects",
    "Qt6Scxml",
    "Qt6Sensors",
    "Qt6StateMachine",
    "Qt6TextToSpeech",
    "Qt6VirtualKeyboard",
    "opengl32sw",         # 20 MB software GL fallback — not needed
)
a.binaries = [
    b for b in a.binaries
    if not any(Path(b[0]).name.startswith(p) for p in _QT_DLL_EXCLUDE_PREFIXES)
]

pyz = PYZ(a.pure)

# ---------------------------------------------------------------------------
# EXE — windowed (no console) because this is a system-tray app
# ---------------------------------------------------------------------------
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="GrainSTT",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,          # tray app — suppress the black console window
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=str(ROOT / "open_voice_router" / "assets" / "grain.ico"),
)

# ---------------------------------------------------------------------------
# COLLECT — one-folder output (dist/GrainSTT/)
# One-folder is easier to debug and sidesteps antivirus false-positives that
# plague self-extracting one-file bundles.  Zip it up for distribution.
# ---------------------------------------------------------------------------
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="GrainSTT",
)
