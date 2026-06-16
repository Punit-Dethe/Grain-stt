"""LocalSTTManager — lifecycle manager for the vendored local ASR sidecar.

Architecture (model-agnostic):
  - The sidecar (HTTP layer + engine wrappers) is VENDORED inside the app at
    open_voice_router/local_asr/ — no external download needed.
  - Which model to serve comes from the model registry
    (open_voice_router/local_asr/registry.py) — adding a model is one registry
    entry; this manager reads everything (pip deps, cache layout, RAM hints)
    from the selected ModelSpec.
  - The user only installs:
      1. Python dependencies (base HTTP deps + the selected engine's packages)
         into a venv
      2. The model files — downloaded automatically by the engine on first
         server start from Hugging Face into the shared models dir.
  - The server runs on localhost:5092 and exposes an OpenAI-compatible
    endpoint; the model is selected via the MODEL_ID environment variable.
  - The existing STTClient generic adapter handles all HTTP — no new protocol code.

Install location: <user_data_dir>/open-voice-router/local-stt/
  venv/       ← isolated Python environment with all ASR dependencies
  models/     ← model files (HF cache layout, shared by all engines)

Signals (Qt main thread):
  install_progress(str)       — progress line during dep install
  install_finished(bool, str) — success + message
  server_ready()              — server passed health check
  server_stopped()            — server process exited
  status_changed(str)         — not_installed | installing | stopped | starting | running | error
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

# Windows: keep every child process windowless. Console apps (python -m venv,
# pip, the ASR server, netstat/taskkill) otherwise flash a command-prompt
# window. 0 on other platforms so the kwarg is a harmless no-op.
CREATE_NO_WINDOW = 0x08000000 if sys.platform == "win32" else 0
BELOW_NORMAL_PRIORITY_CLASS = 0x00004000 if sys.platform == "win32" else 0

import platformdirs
from PySide6.QtCore import (
    QObject,
    QRunnable,
    QThread,
    QThreadPool,
    QTimer,
    Signal,
    Slot,
)

from open_voice_router.local_asr import registry
from open_voice_router.local_asr.registry import ModelSpec
from open_voice_router.services.load_lifecycle import LoadLifecycle

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

_DATA_DIR = Path(platformdirs.user_data_dir("open-voice-router")) / "local-stt"
_VENV_DIR = _DATA_DIR / "venv"
_MODELS_DIR = _DATA_DIR / "models"
# Server stdout/stderr is captured here so crashes/model-load errors are visible.
_SERVER_LOG = _DATA_DIR / "server.log"

if sys.platform == "win32":
    _VENV_PYTHON = _VENV_DIR / "Scripts" / "python.exe"
else:
    _VENV_PYTHON = _VENV_DIR / "bin" / "python"

# The vendored server script inside our package
_SERVER_SCRIPT = Path(__file__).parent.parent / "local_asr" / "server.py"
_LOCAL_ASR_REQ = Path(__file__).parent.parent / "local_asr" / "requirements.txt"

_SERVER_PORT = 5092
_SERVER_HOST = "127.0.0.1"
_SERVER_URL = f"http://{_SERVER_HOST}:{_SERVER_PORT}"
_HEALTH_ENDPOINT = f"{_SERVER_URL}/health"

# Stable provider id. Historic value kept ("local-parakeet") so existing user
# settings keep routing to the local sidecar regardless of the selected model.
_PROVIDER_ID = "local-parakeet"


def _find_system_python() -> str:
    """Return a real Python interpreter for venv creation.

    In a frozen PyInstaller build sys.executable is GrainSTT.exe, not Python.
    Search PATH for an actual interpreter instead.
    """
    if not getattr(sys, "frozen", False):
        return sys.executable
    for name in ("python", "python3", "python3.12", "python3.11", "python3.10", "python3.9"):
        found = shutil.which(name)
        if found:
            return found
    raise RuntimeError(
        "Python 3.9+ not found in PATH.\n"
        "Please install Python from https://python.org and check "
        "'Add Python to PATH' during setup."
    )


# ---------------------------------------------------------------------------
# Install worker
# ---------------------------------------------------------------------------


class _InstallSignals(QObject):
    progress = Signal(str)
    finished = Signal(bool, str)


class _InstallWorker(QRunnable):
    """Installs Python deps into an isolated venv. Model is downloaded on first run.

    Installs the base HTTP-layer requirements plus the SELECTED model's engine
    packages (from its registry spec) — so choosing Parakeet never pulls in
    faster-whisper and vice versa.
    """

    def __init__(self, signals: _InstallSignals, spec: ModelSpec) -> None:
        super().__init__()
        self.signals = signals
        self._spec = spec
        self.setAutoDelete(True)

    def _emit(self, msg: str) -> None:
        self.signals.progress.emit(msg)

    def run(self) -> None:
        try:
            self._install()
            self.signals.finished.emit(
                True,
                f"Local STT ready. {self._spec.display_name} downloads on "
                "first start.",
            )
        except Exception as exc:
            self.signals.finished.emit(False, f"Install failed: {exc}")

    def _install(self) -> None:
        _DATA_DIR.mkdir(parents=True, exist_ok=True)
        _MODELS_DIR.mkdir(parents=True, exist_ok=True)

        # 1. Create venv if not present
        if not _VENV_PYTHON.exists():
            self._emit("Creating isolated Python environment…")
            result = subprocess.run(
                [_find_system_python(), "-m", "venv", str(_VENV_DIR)],
                capture_output=True,
                text=True,
                creationflags=CREATE_NO_WINDOW,
            )
            if result.returncode != 0:
                raise RuntimeError(f"venv creation failed:\n{result.stderr[-1000:]}")
        else:
            self._emit("Python environment already exists.")

        # 2. Upgrade pip silently
        self._emit("Updating package manager…")
        self._pip(["install", "--upgrade", "pip", "-q"])

        # 3. Base HTTP-layer dependencies (flask, waitress, numpy, …)
        self._emit("Installing server dependencies…")
        self._pip(["install", "-r", str(_LOCAL_ASR_REQ), "-q"])

        # 4. Engine packages for the selected model
        if self._spec.pip_requirements:
            self._emit(
                f"Installing {self._spec.engine} engine "
                f"({', '.join(self._spec.pip_requirements)})…"
            )
            self._emit("This may take 2–5 minutes on first install.")
            self._pip(["install", *self._spec.pip_requirements, "-q"])

        self._emit("Dependencies installed.")
        self._emit(
            f"{self._spec.display_name} downloads automatically on first start."
        )

    def _pip(self, args: list[str]) -> None:
        result = subprocess.run(
            [str(_VENV_PYTHON), "-m", "pip"] + args,
            capture_output=True,
            text=True,
            creationflags=CREATE_NO_WINDOW,
        )
        if result.returncode != 0:
            raise RuntimeError(f"pip {args[0]} failed:\n{result.stderr[-2000:]}")


# ---------------------------------------------------------------------------
# Spawn worker — runs the blocking server launch OFF the Qt main thread
# ---------------------------------------------------------------------------


class _SpawnSignals(QObject):
    # (process_or_None, error_reason). error_reason == "" on success.
    finished = Signal(object, str)


class _SpawnWorker(QRunnable):
    """Performs the blocking parts of a server launch on a thread-pool thread.

    The Qt main thread must never run the model-cache walk, ``netstat``/
    ``taskkill`` or ``subprocess.Popen`` directly: together they block for
    100-500 ms and freeze the Pill animation at the exact moment a recording
    starts (when the on-demand Model_Load fires). This worker does that work
    off-thread and reports back via ``finished``, delivered (queued) to a
    main-thread slot which then starts the health poller.
    """

    def __init__(
        self,
        *,
        cmd: list[str],
        popen_kwargs: dict,
        release_port,
        check_cache,
        signals: _SpawnSignals,
    ) -> None:
        super().__init__()
        self._cmd = cmd
        self._popen_kwargs = popen_kwargs
        self._release_port = release_port
        self._check_cache = check_cache
        self._signals = signals
        self.setAutoDelete(True)

    def run(self) -> None:
        try:
            # Local-cache-only guard (R10.4): fail fast WITHOUT spawning when the
            # model snapshot is absent. Done here so the filesystem walk never
            # touches the main thread.
            if self._check_cache is not None and not self._check_cache():
                self._signals.finished.emit(None, "missing-cache")
                return
            # Kill any stale server still holding the port (netstat + taskkill +
            # a short settle sleep) — the heaviest main-thread offender.
            self._release_port()
            proc = subprocess.Popen(self._cmd, **self._popen_kwargs)
        except Exception as exc:  # noqa: BLE001
            self._signals.finished.emit(None, f"launch::{exc}")
            return
        self._signals.finished.emit(proc, "")


# ---------------------------------------------------------------------------
# Health poller
# ---------------------------------------------------------------------------


class _HealthPoller(QThread):
    """Background thread that polls the health endpoint until it responds."""

    ready = Signal()
    timed_out = Signal()

    def __init__(self, timeout_s: int = 300, interval_s: float = 2.0) -> None:
        super().__init__()
        self._timeout = timeout_s
        self._interval = interval_s

    def run(self) -> None:
        import urllib.request

        deadline = time.monotonic() + self._timeout
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(_HEALTH_ENDPOINT, timeout=3) as resp:
                    if resp.status == 200:
                        self.ready.emit()
                        return
            except Exception:
                pass
            time.sleep(self._interval)
        self.timed_out.emit()


# ---------------------------------------------------------------------------
# LocalSTTManager
# ---------------------------------------------------------------------------


class LocalSTTManager(QObject):
    """Manages installation and lifecycle of the local ASR server.

    The ASR server code is BUNDLED inside the app — no download required.
    Only the Python dependencies and the ONNX model need to be installed.
    """

    install_progress = Signal(str)
    install_finished = Signal(bool, str)
    server_ready = Signal()
    server_stopped = Signal()
    server_crashed = Signal(
        str
    )  # emitted with a short reason when the process dies unexpectedly
    status_changed = Signal(str)

    # --- on-demand Model_Load / Model_Unload signals (R7.1, R10.6) ---
    load_failed = Signal(str)  # load could not complete: error | timeout | missing-cache
    load_latency_measured = Signal(int)  # elapsed Load_Latency in milliseconds (R10.6)

    SERVER_URL = _SERVER_URL
    # Default model id — kept as a class attribute for backwards compatibility
    # with callers that read MODEL_NAME; per-instance selection via set_model().
    MODEL_NAME = registry.DEFAULT_MODEL_ID
    PROVIDER_ID = _PROVIDER_ID

    def __init__(
        self, parent: QObject | None = None, model_id: str | None = None
    ) -> None:
        super().__init__(parent)
        # Selected model — resolved through the registry (unknown → default).
        self._spec: ModelSpec = registry.get_model(model_id)
        self._process: subprocess.Popen | None = None
        self._health_poller: _HealthPoller | None = None
        self._log_handle = None  # open file object for server.log
        self._install_signals = _InstallSignals()
        self._install_signals.progress.connect(self.install_progress)
        self._install_signals.finished.connect(self._on_install_finished)
        self._status = "not_installed" if not self.is_installed() else "stopped"

        # Pre-warm OS file cache and Python import DLL cache so the first
        # on-demand Model_Load hits warm memory instead of cold disk.  Only
        # started when both the venv and the model files are already present;
        # skipped on first install (warmers are useless before the model is cached).
        if self.is_installed() and self._model_cache_present():
            self._start_warmers()

        # Liveness monitor — once the server is running, poll the process so a
        # crash is detected and surfaced instead of silently failing every
        # subsequent transcription against a dead server.
        self._liveness_timer = QTimer(self)
        self._liveness_timer.setInterval(3000)
        self._liveness_timer.timeout.connect(self._check_liveness)

        # On-demand Model_Unload — a single-shot, cancellable timer. request_unload()
        # arms it; load() cancels it first so a re-trigger during a pending unload
        # supersedes the unload (R8.2).
        self._unload_timer = QTimer(self)
        self._unload_timer.setSingleShot(True)
        self._unload_timer.timeout.connect(self._on_unload_timeout)

        # Load_Latency instrumentation (R10.6) and on-demand load tracking.
        self._is_loading: bool = False
        self._load_start_monotonic: float | None = None
        self._last_load_latency_ms: int | None = None

        # Async spawn plumbing: the blocking launch work (cache check, stale-port
        # release, Popen) runs on a thread-pool worker and reports back here, so
        # the Qt main thread is never blocked during an on-demand Model_Load.
        # finished is emitted from the worker thread → delivered queued to the
        # main thread, where _on_spawn_finished starts the health poller.
        self._spawn_signals = _SpawnSignals()
        self._spawn_signals.finished.connect(self._on_spawn_finished)
        self._pending_timeout_s: int = 30
        self._pending_interval_s: float = 0.15

    # ------------------------------------------------------------------
    # Background pre-warming (reduces cold Model_Load latency)
    # ------------------------------------------------------------------

    def _start_warmers(self) -> None:
        """Start OS file-cache and Python import warmers in daemon threads.

        Called once at startup when the model is already installed and cached.
        Neither warmer blocks the main thread or holds the model in RAM — they
        only pre-populate OS-level caches so that the first on-demand Model_Load
        hits warm memory instead of cold disk or cold DLL pages.
        """
        self._start_file_cache_warmer()
        self._start_import_warmer()

    def _start_file_cache_warmer(self) -> None:
        """Prime the OS page cache for the large model blob files.

        Reads each blob sequentially in 8 MB blocks via readinto() on a daemon
        thread. file.readinto() RELEASES the GIL during the read syscall, which
        is essential: the main thread runs QML that reads Python properties (the
        pill's per-frame amplitude_level), so it must take the GIL — any warmer
        that holds the GIL for seconds freezes the pill. (The earlier mmap
        per-page touch loop did exactly that and was the cold-load freeze.) The
        read pages land in the shared OS cache for the server subprocess; only a
        single reused 8 MB buffer touches our heap, trimmed away below.
        """
        def _warm() -> None:
            # Reusable 8 MB buffer: readinto() reuses it, so warming the cache
            # adds no per-iteration heap allocation (constant 8 MB transient).
            buf = bytearray(8 * 1024 * 1024)
            try:
                if not _MODELS_DIR.exists():
                    return
                for blob in _MODELS_DIR.rglob("*"):
                    if not blob.is_file():
                        continue
                    try:
                        if blob.stat().st_size < 1024 * 1024:
                            continue  # skip tiny metadata files
                        # Sequential block reads pull the file into the OS page
                        # cache (warming it for the server subprocess) while
                        # RELEASING the GIL during each read syscall.
                        #
                        # The previous mmap per-page loop (`mm[offset]` for every
                        # 4 KB page) HELD the GIL across hundreds of thousands of
                        # disk-faulting accesses. Because the pill's QML reads a
                        # Python property (amplitude_level) every frame and so must
                        # take the GIL, that loop froze the pill for the entire
                        # multi-second warm — the long-standing cold-load freeze.
                        # readinto() yields the GIL on every read, so the GUI
                        # thread stays live and the pill animates throughout.
                        with open(blob, "rb") as fh:
                            while fh.readinto(buf):
                                pass
                    except OSError:
                        pass
            except Exception:
                pass
            finally:
                # The touched pages are MAPPED-FILE pages: they sit in this
                # process's working set (inflating Task Manager's number by up
                # to the full model size) even though the goal is only to
                # populate the OS standby cache. Trim our working set so the
                # pages move to standby — still warm for the server subprocess,
                # no longer charged to the app.
                if sys.platform == "win32":
                    try:
                        import ctypes

                        psapi = ctypes.windll.psapi
                        kernel32 = ctypes.windll.kernel32
                        psapi.EmptyWorkingSet(kernel32.GetCurrentProcess())
                    except Exception:
                        pass

        threading.Thread(target=_warm, daemon=True, name="stt-file-warmer").start()

    def _start_import_warmer(self) -> None:
        """Spawn a throwaway subprocess that imports onnxruntime + onnx_asr then exits.

        On Windows the DLL pages for onnxruntime (and all its native dependencies)
        remain in the OS standby-memory pool after a process exits.  The next
        subprocess that imports those same DLLs finds them already mapped and avoids
        re-reading ~100 MB from disk.  On macOS/Linux the shared-library pages stay
        in the kernel page cache for the same reason.

        The subprocess runs at below-normal priority so it never competes with the
        main app or with a real server spawn triggered by an early hotkey press.
        """
        def _run() -> None:
            if not _VENV_PYTHON.exists():
                return
            env = os.environ.copy()
            env["HF_HUB_OFFLINE"] = "1"
            env["TRANSFORMERS_OFFLINE"] = "1"
            env["MODELS_DIR"] = str(_MODELS_DIR)
            env["HF_HOME"] = str(_MODELS_DIR)
            env["HF_HUB_CACHE"] = str(_MODELS_DIR)

            kwargs: dict = {
                "capture_output": True,
                "env": env,
                "timeout": 120,
            }
            if sys.platform == "win32":
                # Below-normal priority (preempted by foreground work) AND
                # windowless so the warm-up flash never appears at launch.
                kwargs["creationflags"] = (
                    BELOW_NORMAL_PRIORITY_CLASS | CREATE_NO_WINDOW
                )

            modules = self._spec.import_check_modules
            if not modules:
                return
            import_stmt = "; ".join(f"import {m}" for m in modules)
            try:
                subprocess.run(
                    [str(_VENV_PYTHON), "-c", import_stmt],
                    **kwargs,
                )
            except Exception:
                pass

        threading.Thread(target=_run, daemon=True, name="stt-import-warmer").start()

    # ------------------------------------------------------------------
    # Public queries
    # ------------------------------------------------------------------

    @property
    def model_id(self) -> str:
        """The currently selected model's registry id."""
        return self._spec.id

    @property
    def model_spec(self) -> ModelSpec:
        return self._spec

    @Slot(str)
    def set_model(self, model_id: str) -> None:
        """Select a different registry model.

        If the server is running (or loading) with the old model it is stopped
        — the next load() spawns it with the new MODEL_ID. Selecting the
        already-active model is a no-op so callers can set unconditionally.
        """
        new_spec = registry.get_model(model_id)
        if new_spec.id == self._spec.id:
            return
        self._spec = new_spec
        if self.is_running() or self._status == "starting":
            self.stop()

    def is_installed(self) -> bool:
        """True if the venv has the required packages installed."""
        return _VENV_PYTHON.exists()

    def is_running(self) -> bool:
        return self._process is not None and self._process.poll() is None

    @property
    def status(self) -> str:
        return self._status

    @property
    def is_busy_loading(self) -> bool:
        """True while a Model_Load is in flight (status ``starting``)."""
        return self._status == "starting"

    @property
    def last_load_latency_ms(self) -> int | None:
        """Most recently measured Load_Latency in ms, or None if never loaded."""
        return self._last_load_latency_ms

    @property
    def install_path(self) -> str:
        return str(_DATA_DIR)

    @property
    def server_url(self) -> str:
        return _SERVER_URL

    # ------------------------------------------------------------------
    # Install
    # ------------------------------------------------------------------

    @Slot()
    def install(self) -> None:
        """Install Python dependencies for the selected model's engine.

        Emits install_progress and install_finished. Re-running after a model
        switch installs only the missing engine packages (pip is idempotent)."""
        self._set_status("installing")
        worker = _InstallWorker(self._install_signals, self._spec)
        QThreadPool.globalInstance().start(worker)

    @Slot(bool, str)
    def _on_install_finished(self, success: bool, message: str) -> None:
        self._set_status("stopped" if success else "error")
        self.install_finished.emit(success, message)
        if success:
            # Auto-start after install (downloads the model on first run).
            # After the server completes its first load the DLL/file warmers
            # become useful, so start them once the model cache is present.
            self.start()
            if self._model_cache_present():
                self._start_warmers()

    # ------------------------------------------------------------------
    # Start / stop
    # ------------------------------------------------------------------

    @Slot()
    def start(self) -> None:
        """Start the local ASR server subprocess."""
        if not self.is_installed():
            return
        if self.is_running():
            self.server_ready.emit()
            return
        if self._status == "starting":
            return  # spawn already in flight — ignore duplicate call

        # Install-time / manual start: very generous timeout because the model
        # may still be downloading (~400 MB–1.5 GB) on a slow connection.
        # 1800 s (30 min) covers the worst-case first-download scenario so a
        # slow connection doesn't look like a crash to the user.
        self._begin_spawn(
            timeout_s=1800, interval_s=2.0, offline=False, check_cache=False
        )

    # ------------------------------------------------------------------
    # On-demand Model_Load / Model_Unload (R8.2, R8.3, R8.6, R7.1, R7.2, R10.x)
    # ------------------------------------------------------------------

    @Slot()
    def load(self, timeout_s: int = 30) -> None:
        """On-demand Model_Load.

        Cancels any pending Model_Unload (R8.2), reuses a running/starting server
        without spawning a second process (R8.3, R8.6), otherwise spawns the server
        with a short, configurable timeout and a fast ready-detection interval.
        Records the start time for Load_Latency (R10.6) and loads strictly from the
        local cache (R10.3, R10.4).
        """
        # A new load always supersedes a pending unload (R8.2).
        self._cancel_pending_unload()

        if not self.is_installed():
            self.load_failed.emit("not-installed")
            return

        # Reject a duplicate spawn while a load is already in flight (R8.6).
        if self.is_busy_loading:
            return

        # Reuse an already-running server (R8.3) — duplicate start is a no-op.
        if self.is_running():
            self.server_ready.emit()
            return

        # Clamp the configurable timeout to [10, 120] (default 30) via LoadLifecycle
        # so the manager and the pure model agree on the effective value (R7.2).
        timeout = LoadLifecycle.effective_timeout(timeout_s)

        # Everything blocking — the local-cache-only guard (R10.4), stale-port
        # release and Popen — runs on a worker thread (see _begin_spawn), so the
        # Qt main thread (and therefore the Pill animation) is never blocked while
        # a recording is starting. A missing cache / launch failure comes back via
        # _on_spawn_finished → load_failed.
        self._is_loading = True
        self._load_start_monotonic = time.monotonic()
        self._begin_spawn(
            timeout_s=timeout, interval_s=0.15, offline=True, check_cache=True
        )

    @Slot()
    def request_unload(self, delay_ms: int = 0) -> None:
        """Schedule a cancellable Model_Unload.

        Arms a single-shot timer that stops the subprocess after ``delay_ms``. A
        later ``load()`` cancels the timer before it fires (R8.2). A negative
        ``delay_ms`` means "never auto-unload" — any pending unload is cancelled
        and the model is kept resident until an explicit stop / app quit. If no
        model is loaded the call is an idempotent no-op that leaves status
        unchanged and never raises (R3.7).
        """
        # Negative delay == "Never": cancel any pending unload and keep loaded.
        if int(delay_ms) < 0:
            self._cancel_pending_unload()
            return
        # Idempotent when nothing is loaded — do not touch status or arm a timer.
        if not self.is_running() and self._status not in ("starting", "running"):
            return
        self._unload_timer.start(max(0, int(delay_ms)))

    @Slot()
    def _on_unload_timeout(self) -> None:
        """The deferred Model_Unload fired — stop the server if still resident."""
        if self.is_running() or self._status in ("starting", "running"):
            self.stop()

    def _cancel_pending_unload(self) -> None:
        if self._unload_timer.isActive():
            self._unload_timer.stop()

    def _begin_spawn(
        self, *, timeout_s: int, interval_s: float, offline: bool, check_cache: bool
    ) -> None:
        """Start an ASR server launch ASYNCHRONOUSLY.

        Sets status to ``starting`` and builds the (cheap) env + log handle on the
        main thread, then offloads the BLOCKING work — the model-cache walk, the
        stale-port release (``netstat``/``taskkill``/sleep) and ``subprocess.Popen``
        — to a thread-pool worker. The main thread returns immediately, so the
        Pill animation never freezes. Completion (or failure) is delivered to
        ``_on_spawn_finished`` on the main thread, which starts the health poller.

        ``check_cache`` is True for on-demand load (fail fast if the model
        snapshot is absent) and False for the install-time start (the model is
        downloaded on first run). Shared by ``start()`` and ``load()``.
        """
        self._set_status("starting")
        self._pending_timeout_s = timeout_s
        self._pending_interval_s = interval_s

        env = os.environ.copy()
        env["MODEL_ID"] = self._spec.id
        env["MODELS_DIR"] = str(_MODELS_DIR)
        env["TEMP_DIR"] = str(_DATA_DIR / "temp_uploads")
        env["PORT"] = str(_SERVER_PORT)
        env["HOST"] = _SERVER_HOST
        # Point HuggingFace cache at our models dir
        env["HF_HOME"] = str(_MODELS_DIR)
        env["HF_HUB_CACHE"] = str(_MODELS_DIR)
        if offline:
            # Local-cache-only resolution — no network HEAD for cache freshness
            # (R10.3, R10.4). Only set on the on-demand load path so the initial
            # install download still works when the cache is absent.
            env["HF_HUB_OFFLINE"] = "1"
            env["TRANSFORMERS_OFFLINE"] = "1"

        # Capture server output to a log file so model-load errors and crashes
        # are visible (previously sent to DEVNULL — failures were invisible).
        try:
            _DATA_DIR.mkdir(parents=True, exist_ok=True)
            self._log_handle = open(
                _SERVER_LOG, "w", encoding="utf-8", errors="replace"
            )
        except Exception:
            self._log_handle = None

        popen_kwargs: dict = {
            "cwd": str(_DATA_DIR),
            "env": env,
            "stdout": (self._log_handle or subprocess.DEVNULL),
            "stderr": subprocess.STDOUT,
        }
        if sys.platform == "win32":
            # Spawn at BELOW_NORMAL_PRIORITY_CLASS so Windows does not trim the
            # main UI process's working set while the 640 MB model is being mapped
            # into the subprocess's RAM.  Priority is restored to normal in
            # _on_server_ready once the model is fully loaded.
            # CREATE_NO_WINDOW (0x08000000) prevents a console flash on Windows.
            popen_kwargs["creationflags"] = 0x00004000 | 0x08000000

        worker = _SpawnWorker(
            cmd=[str(_VENV_PYTHON), str(_SERVER_SCRIPT)],
            popen_kwargs=popen_kwargs,
            release_port=self._release_stale_port,
            check_cache=(self._model_cache_present if check_cache else None),
            signals=self._spawn_signals,
        )
        QThreadPool.globalInstance().start(worker)

    @Slot(object, str)
    def _on_spawn_finished(self, proc: object, error: str) -> None:
        """Main-thread continuation of an async launch (see ``_begin_spawn``).

        Runs on the main thread (queued delivery from the worker), so creating
        and starting the ``_HealthPoller`` here keeps clean thread affinity.
        """
        # Superseded while we were spawning (stop()/uninstall flipped status):
        # discard the result and clean up any orphaned process.
        if self._status != "starting":
            if proc is not None:
                try:
                    proc.terminate()  # type: ignore[union-attr]
                except Exception:  # noqa: BLE001
                    pass
            self._close_log_handle()
            return

        if error:
            was_loading = self._is_loading
            self._is_loading = False
            self._load_start_monotonic = None
            self._set_status("error")
            self._close_log_handle()
            if error == "missing-cache":
                # On-demand load against an absent snapshot (R10.4).
                if was_loading:
                    self.load_failed.emit("missing-cache")
                else:
                    self.server_crashed.emit("The local model files are missing.")
            else:
                reason = error[len("launch::"):] if error.startswith("launch::") else error
                if was_loading:
                    self.load_failed.emit("launch")
                else:
                    self.server_crashed.emit(f"Could not launch server: {reason}")
            return

        # Success: keep the process and begin health polling on the main thread.
        self._process = proc  # type: ignore[assignment]
        poller = _HealthPoller(
            timeout_s=self._pending_timeout_s, interval_s=self._pending_interval_s
        )
        poller.ready.connect(self._on_server_ready)
        poller.timed_out.connect(self._on_server_timeout)
        self._health_poller = poller
        poller.start()

    def _close_log_handle(self) -> None:
        """Close the server-log file handle if open. Idempotent."""
        if self._log_handle is not None:
            try:
                self._log_handle.close()
            except Exception:  # noqa: BLE001
                pass
            self._log_handle = None

    @staticmethod
    def _cache_present_for(spec: ModelSpec) -> bool:
        """True if *spec*'s model snapshot is present in the models dir.

        Engines resolve models from the HuggingFace-style cache under
        ``MODELS_DIR``. Presence means: some directory whose name contains the
        spec's ``cache_dir_fragment`` holds at least one file matching its
        ``cache_weight_glob``. Per-model detection matters now that several
        models can coexist in the cache — a cached Parakeet must not make a
        newly selected Whisper look installed.
        """
        try:
            if not _MODELS_DIR.exists():
                return False
            fragment = spec.cache_dir_fragment.lower()
            for directory in _MODELS_DIR.rglob("*"):
                if not directory.is_dir():
                    continue
                if fragment and fragment not in directory.name.lower():
                    continue
                for _ in directory.rglob(spec.cache_weight_glob):
                    return True
            return False
        except Exception:
            return False

    def is_model_cached(self, model_id: str) -> bool:
        """True if *model_id*'s weights are downloaded (regardless of selection)."""
        return self._cache_present_for(registry.get_model(model_id))

    @staticmethod
    def cached_model_ids() -> set[str]:
        """Return the ids of all registry models whose weights are cached.

        Single-pass equivalent of calling ``is_model_cached`` for every model:
        the expensive full recursive walk of the models dir runs ONCE here
        instead of once per model. The settings UI reads the model catalog
        (which needs every model's installed flag) on each status change — doing
        N walks there stalled the Qt main thread during a load, when status
        flips several times in quick succession.
        """
        result: set[str] = set()
        try:
            if not _MODELS_DIR.exists():
                return result
            # Materialise the directory listing once; reuse it for every spec.
            directories = [d for d in _MODELS_DIR.rglob("*") if d.is_dir()]
            for spec in registry.all_models():
                fragment = spec.cache_dir_fragment.lower()
                for directory in directories:
                    if fragment and fragment not in directory.name.lower():
                        continue
                    if next(directory.rglob(spec.cache_weight_glob), None) is not None:
                        result.add(spec.id)
                        break
        except Exception:
            pass
        return result

    def _model_cache_present(self) -> bool:
        """True if the SELECTED model's snapshot is present. Used to fail
        Model_Load fast with ``missing-cache`` instead of triggering a network
        download (R10.4)."""
        return self._cache_present_for(self._spec)

    @Slot()
    def stop(self) -> None:
        """Stop the server subprocess cleanly."""
        self._liveness_timer.stop()
        self._cancel_pending_unload()

        # Abandon any in-flight load tracking — the server is going away.
        self._is_loading = False
        self._load_start_monotonic = None

        if self._health_poller and self._health_poller.isRunning():
            self._health_poller.quit()
            self._health_poller.wait(2000)
            self._health_poller = None

        if self._process:
            self._process.terminate()
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
            self._process = None

        self._close_log_handle()

        self._set_status("stopped")
        self.server_stopped.emit()

    @Slot(str)
    def delete_model_cache(self, model_id: str) -> None:
        """Delete the cached weights for *model_id* without touching the venv.

        If the currently-selected model is the one being deleted and the server
        is running, the server is stopped first so the files are not locked.
        After deletion the status is refreshed so the UI reflects the change.
        """
        import shutil

        spec = registry.get_model(model_id)
        if spec.id == self._spec.id and (self.is_running() or self._status in ("starting",)):
            self.stop()

        if not _MODELS_DIR.exists():
            self.status_changed.emit(self._status)  # refresh UI installed flags
            return

        fragment = spec.cache_dir_fragment.lower()
        try:
            for directory in list(_MODELS_DIR.rglob("*")):
                if not directory.is_dir():
                    continue
                if fragment and fragment not in directory.name.lower():
                    continue
                if next(directory.rglob(spec.cache_weight_glob), None) is not None:
                    shutil.rmtree(directory, ignore_errors=True)
        except Exception:
            pass

        # Always re-emit so the UI re-evaluates installed flags via
        # local_stt_models_changed (connected to status_changed in the VM).
        self.status_changed.emit(self._status)

    @Slot()
    def uninstall(self) -> None:
        """Stop the server and delete the entire local-STT data directory.

        After this call `is_installed()` returns False and status is
        ``not_installed``.  The model weights and venv are fully removed.
        """
        import shutil

        self.stop()  # terminates process, sets status → "stopped"
        # Also kill any externally-started server (e.g. from a previous app
        # instance) so the data dir is not locked during rmtree.
        self._release_stale_port()
        try:
            if _DATA_DIR.exists():
                shutil.rmtree(_DATA_DIR, ignore_errors=True)
        except Exception:
            pass
        self._set_status("not_installed")

    @Slot()
    def _on_server_ready(self) -> None:
        self._set_status("running")
        # The server was spawned at BELOW_NORMAL_PRIORITY_CLASS to avoid UI jank
        # during the 640 MB model load.  Now that the model is resident, restore
        # normal priority so transcription latency is not penalised.
        if sys.platform == "win32" and self._process is not None:
            import ctypes
            try:
                _PROCESS_SET_INFORMATION = 0x0200
                _NORMAL_PRIORITY_CLASS = 0x00000020
                handle = ctypes.windll.kernel32.OpenProcess(
                    _PROCESS_SET_INFORMATION, False, self._process.pid
                )
                if handle:
                    ctypes.windll.kernel32.SetPriorityClass(handle, _NORMAL_PRIORITY_CLASS)
                    ctypes.windll.kernel32.CloseHandle(handle)
            except Exception:
                pass
        # Begin watching the process for unexpected exits.
        self._liveness_timer.start()
        # Measure Load_Latency for the on-demand load path (R10.6).
        if self._is_loading:
            self._is_loading = False
            if self._load_start_monotonic is not None:
                elapsed_ms = int(
                    (time.monotonic() - self._load_start_monotonic) * 1000
                )
                self._load_start_monotonic = None
                self._last_load_latency_ms = elapsed_ms
                self.load_latency_measured.emit(elapsed_ms)
        self.server_ready.emit()

    @Slot()
    def _on_server_timeout(self) -> None:
        self._set_status("error")
        reason = self._read_log_tail() or "Server did not become ready in time."
        was_loading = self._is_loading
        self.stop()  # resets loading flags, stops process, status -> stopped
        if was_loading:
            # On-demand Model_Load timed out (R7.2): surface as a load failure.
            self.load_failed.emit("timeout")
        else:
            self.server_crashed.emit(reason)

    @Slot()
    def _check_liveness(self) -> None:
        """Detect an unexpected server exit and surface it instead of letting
        every subsequent transcription fail silently against a dead process."""
        if self._process is None:
            self._liveness_timer.stop()
            return
        if self._process.poll() is not None:
            # Process exited on its own — crashed.
            self._liveness_timer.stop()
            reason = (
                self._read_log_tail() or "The local STT server stopped unexpectedly."
            )
            self.stop()
            self._set_status("error")
            self.server_crashed.emit(reason)

    def _read_log_tail(self, max_chars: int = 600) -> str:
        """Return the last chunk of the server log for diagnostics."""
        try:
            if self._log_handle is not None:
                self._log_handle.flush()
        except Exception:
            pass
        try:
            text = _SERVER_LOG.read_text(encoding="utf-8", errors="replace").strip()
            if not text:
                return ""
            tail = text[-max_chars:]
            # Keep it to the last few lines for a readable notification.
            lines = [ln for ln in tail.splitlines() if ln.strip()]
            return " | ".join(lines[-3:]) if lines else ""
        except Exception:
            return ""

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _release_stale_port(self) -> None:
        """Kill any stale process listening on the ASR port from a previous session.

        On Windows: uses netstat + taskkill to find and terminate the holder.
        A short sleep after killing gives the OS time to reclaim the socket so
        the fresh server can bind immediately.  Failures are silently swallowed —
        if the kill doesn't work the Popen will fail with a clear bind error.
        """
        if sys.platform != "win32":
            return
        try:
            result = subprocess.run(
                ["netstat", "-ano"],
                capture_output=True,
                text=True,
                timeout=5,
                creationflags=0x08000000,
            )
            pids: set[int] = set()
            port_tag = f":{_SERVER_PORT}"
            for line in result.stdout.splitlines():
                if "LISTENING" not in line:
                    continue
                parts = line.split()
                # netstat -ano columns: Proto, Local Address, Foreign Address,
                # State, PID. Match the LOCAL ADDRESS port exactly via endswith —
                # a substring test on the whole line would also catch ephemeral
                # ports like :50921 (which contains ":5092").
                if len(parts) < 5 or not parts[1].endswith(port_tag):
                    continue
                try:
                    pids.add(int(parts[-1]))
                except ValueError:
                    pass
            for pid in pids:
                try:
                    subprocess.run(
                        ["taskkill", "/F", "/PID", str(pid)],
                        capture_output=True,
                        timeout=5,
                        creationflags=0x08000000,
                    )
                except Exception:
                    pass
            if pids:
                time.sleep(0.5)  # let the OS release the socket
        except Exception:
            pass

    def _set_status(self, status: str) -> None:
        if self._status != status:
            self._status = status
            self.status_changed.emit(status)
