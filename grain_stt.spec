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

    # Local ASR server is spawned as a subprocess under the user's own venv
    # Python (not the bundled interpreter), so it must live as a plain .py
    # file that the venv Python can execute directly.
    (str(ROOT / "open_voice_router" / "local_asr" / "server.py"),
     "open_voice_router/local_asr"),
    (str(ROOT / "open_voice_router" / "local_asr" / "requirements.txt"),
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
    ],
    noarchive=False,
    optimize=0,
)

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
    # icon="assets/grain.ico",  # uncomment when you have an icon file
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
