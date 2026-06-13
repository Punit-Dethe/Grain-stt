"""AppController — central session orchestrator.

Owns the IDLE → RECORDING → PROCESSING → DONE → IDLE state machine and wires
all services together.  Runs on the main Qt thread; long-running I/O (STT,
LLM) is dispatched to QThreadPool workers and results are delivered back via
Qt signals.

Implements Requirements 2.2, 2.3, 3.2, 3.3, 5.3, 6.3, 6.4, 7.3, 7.4.
"""

from __future__ import annotations

import asyncio
import uuid
from collections import deque
from datetime import datetime, timedelta
from enum import Enum, auto

from PySide6.QtCore import QObject, QRunnable, QThreadPool, QTimer, Signal, Slot

from open_voice_router.exceptions import AudioDeviceError, ProviderError, RateLimitError
from open_voice_router.logger import FallbackLogEntry, Logger
from open_voice_router.models import AppSettings, FallbackRecord, SessionLogEntry
from open_voice_router.router import ProviderPool, Router
from open_voice_router.services.llm_rotation import RotationTracker, estimate_tokens
from open_voice_router.services.audio import AudioService
from open_voice_router.services.chunked_audio import AudioChunk, ChunkedAudioService
from open_voice_router.services.clipboard import ClipboardService
from open_voice_router.services.hotkey import HotkeyService
from open_voice_router.services.llm_client import LLMClient
from open_voice_router.services.local_stt_manager import LocalSTTManager
from open_voice_router.services.stt_client import STTClient
from open_voice_router.services.transcript_merger import TimelineAssembler
from open_voice_router.services.volume_meter import VolumeMeterService
from open_voice_router.storage.credential_store import CredentialStore
from open_voice_router.storage.settings_store import SettingsStore
from open_voice_router.ui.pill.pill_viewmodel import PillViewModel

# Delay (ms) before the Pill UI is hidden after the DONE state is reached.
_PILL_HIDE_DELAY_MS = 2000

# Provider ID that triggers chunked-streaming mode
_LOCAL_PROVIDER_ID = "local-parakeet"


def _is_local_provider(p) -> bool:
    """Return True if *p* is the local Parakeet server (not a cloud provider)."""
    url = (p.base_url or "").lower()
    return p.id == _LOCAL_PROVIDER_ID or "127.0.0.1" in url or "localhost" in url


# ---------------------------------------------------------------------------
# Session state
# ---------------------------------------------------------------------------


class SessionState(Enum):
    IDLE = auto()
    RECORDING = auto()  # record-then-transcribe (cloud STT)
    STREAMING = auto()  # continuous chunked recording (local STT)
    PROCESSING = auto()
    DONE = auto()


# ---------------------------------------------------------------------------
# Worker signals
# ---------------------------------------------------------------------------


class _WorkerSignals(QObject):
    """Signals for QRunnable workers to deliver results back to the main thread."""

    stt_complete = Signal(str)  # transcript
    stt_error = Signal(str)  # error message
    llm_complete = Signal(object)  # LLMResult (text + usage/limit signals)
    llm_error = Signal(str)  # error message (non-429 failures)
    llm_rate_limited = Signal(str, float)  # (provider_id, retry_after_s)
    # Streaming chunk results carry the session generation so the controller can
    # ignore stale responses from a previous/discarded session, plus the
    # AudioChunk itself so the controller knows WHICH time range the result
    # covers (and can retry the exact chunk on failure).
    chunk_stt_complete = Signal(int, object, object)  # (generation, AudioChunk, TranscriptionResult)
    chunk_stt_error = Signal(int, object, str)  # (generation, AudioChunk, error)


# ---------------------------------------------------------------------------
# STT worker
# ---------------------------------------------------------------------------


class _STTWorker(QRunnable):
    """Runs STTClient.transcribe() in a thread-pool worker."""

    def __init__(
        self,
        stt_client: STTClient,
        provider,
        audio: bytes,
        api_key: str | None,
        signals: _WorkerSignals,
    ) -> None:
        super().__init__()
        self._stt_client = stt_client
        self._provider = provider
        self._audio = audio
        self._api_key = api_key
        self.signals = signals
        self.setAutoDelete(True)

    def run(self) -> None:
        try:
            result = asyncio.run(
                self._stt_client.transcribe(self._provider, self._audio, self._api_key)
            )
            self.signals.stt_complete.emit(result.text)
        except Exception as exc:  # noqa: BLE001
            self.signals.stt_error.emit(str(exc))


class _ChunkSTTWorker(QRunnable):
    """Transcribes a single audio chunk in streaming mode.

    Emits chunk_stt_complete(generation, chunk, result) or
    chunk_stt_error(generation, chunk, error). The generation token lets the
    controller ignore stale responses; the chunk identifies the time range.
    """

    def __init__(
        self,
        generation: int,
        stt_client: STTClient,
        provider,
        chunk: AudioChunk,
        api_key: str | None,
        signals: _WorkerSignals,
    ) -> None:
        super().__init__()
        self._generation = generation
        self._stt_client = stt_client
        self._provider = provider
        self._chunk = chunk
        self._api_key = api_key
        self.signals = signals
        self.setAutoDelete(True)

    def run(self) -> None:
        try:
            result = asyncio.run(
                self._stt_client.transcribe(
                    self._provider, self._chunk.wav_bytes, self._api_key
                )
            )
            self.signals.chunk_stt_complete.emit(self._generation, self._chunk, result)
        except Exception as exc:  # noqa: BLE001
            self.signals.chunk_stt_error.emit(self._generation, self._chunk, str(exc))


# ---------------------------------------------------------------------------
# LLM worker
# ---------------------------------------------------------------------------


class _LLMWorker(QRunnable):
    """Runs LLMClient.complete() in a thread-pool worker."""

    def __init__(
        self,
        llm_client: LLMClient,
        provider,
        transcript: str,
        api_key: str | None,
        signals: _WorkerSignals,
        system_prompt: str | None = None,
    ) -> None:
        super().__init__()
        self._llm_client = llm_client
        self._provider = provider
        self._transcript = transcript
        self._api_key = api_key
        self._system_prompt = system_prompt
        self.signals = signals
        self.setAutoDelete(True)

    def run(self) -> None:
        try:
            result = asyncio.run(
                self._llm_client.complete_detailed(
                    self._provider,
                    self._transcript,
                    self._api_key,
                    system_prompt=self._system_prompt,
                )
            )
            self.signals.llm_complete.emit(result)
        except RateLimitError as exc:
            self.signals.llm_rate_limited.emit(self._provider.id, exc.retry_after_s)
        except Exception as exc:  # noqa: BLE001
            self.signals.llm_error.emit(str(exc))


# ---------------------------------------------------------------------------
# AppController
# ---------------------------------------------------------------------------


class AppController(QObject):
    """Central orchestrator.  Owns the session state machine.

    State transitions
    -----------------
    IDLE + hotkey_pressed          → RECORDING  (start AudioService, show Pill)
    RECORDING + hotkey_pressed     → PROCESSING (stop AudioService, dispatch STT)
    RECORDING + confirm_clicked    → PROCESSING (same as hotkey second press)
    PROCESSING + stt_complete      → DONE (dictation) | dispatch LLM (voice_to_ai)
    PROCESSING + llm_complete      → DONE
    DONE + action_complete         → IDLE (schedule Pill hide 2 s)
    """

    # Signals consumed by the tray icon / main window
    show_notification = Signal(str, str)  # title, message
    open_settings_requested = Signal()
    state_changed = Signal(str)  # emits SessionState.name
    transcription_result_ready = Signal(str, str)  # (text, HH:MM timestamp)
    processing_result_ready = Signal(str, str)      # (text, HH:MM timestamp)
    llm_error_occurred = Signal(str)               # human-readable error, cleared on next success

    def __init__(
        self,
        settings: AppSettings,
        settings_store: SettingsStore,
        credential_store: CredentialStore,
        audio_service: AudioService,
        hotkey_service: HotkeyService,
        stt_client: STTClient,
        llm_client: LLMClient,
        clipboard_service: ClipboardService,
        router: Router,
        logger: Logger,
        pill_viewmodel: PillViewModel,
        tray_icon=None,  # QSystemTrayIcon — optional, for showMessage()
        local_stt_manager: LocalSTTManager | None = None,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)

        self._settings = settings
        self._settings_store = settings_store
        self._credential_store = credential_store
        self._audio_service = audio_service
        self._hotkey_service = hotkey_service
        self._stt_client = stt_client
        self._llm_client = llm_client
        self._clipboard_service = clipboard_service
        self._router = router
        self._logger = logger
        self.pill_vm = pill_viewmodel
        self._tray_icon = tray_icon

        # On-demand Model_Load coordination (single shared LocalSTTManager so the
        # settings UI and this controller drive the same process). Loaded per
        # session and unloaded when the session ends.
        self._local_stt_manager = local_stt_manager

        # Chunked audio service for local STT streaming mode
        self._chunked_audio = ChunkedAudioService()

        # Isolated volume meter for the pill visualization ONLY.
        # Opens its OWN microphone stream — completely separate from the
        # model's audio pipeline. It can NEVER affect transcription accuracy.
        self._volume_meter = VolumeMeterService()

        # Persistent result cache — survives UI open/close
        self._last_transcribed: str = ""
        self._last_processed: str = ""

        # Session state
        self._state = SessionState.IDLE

        # Per-session tracking
        self._session_id: str = ""
        self._session_start: datetime | None = None
        self._stt_start: datetime | None = None
        self._llm_start: datetime | None = None
        self._current_transcript: str = ""
        self._fallbacks: list[FallbackRecord] = []
        self._stt_provider = None
        self._llm_provider = None
        self._wav_bytes: bytes = b""
        self._pending_stt_provider_id: str = ""
        self._pending_stt_latency_ms: int = 0
        # Track which provider IDs have already been attempted this session
        self._stt_attempted_ids: set[str] = set()
        self._llm_attempted_ids: set[str] = set()

        # ── Streaming mode (10s rolling window, serialized to the server) ─────
        # Accumulated finalized transcript across chunks
        self._stream_transcript: str = ""
        self._stream_stt_latency_total_ms: int = 0
        self._stream_chunk_count: int = 0
        # FIFO queue of time-tagged AudioChunks waiting to be transcribed. We
        # send ONE at a time to the local server (it is single-threaded) — this
        # is the core fix for the "speak for minutes then it just closes" bug.
        self._stream_queue: deque[AudioChunk] = deque()
        # Time-based transcript assembly (word timings → deterministic dedup).
        self._stream_assembler = TimelineAssembler()
        # Coverage ledger: fresh time ranges whose transcription failed even
        # after retry — logged at finalize so missing speech is diagnosable.
        self._stream_coverage_gaps: list[tuple[float, float]] = []
        # True while a chunk request is in flight (waiting on the server).
        self._stream_busy: bool = False
        # True once the user has stopped recording (recording_stopped fired).
        self._stream_recording_done: bool = False
        # Last chunk error, surfaced only if the whole session ends up empty.
        self._stream_last_error: str = ""
        # Generation token — incremented every session. Worker callbacks that
        # carry a stale generation are ignored, so a late response from a
        # previous/discarded recording can never corrupt the current one.
        self._stream_generation: int = 0

        # ── On-demand Model_Load readiness gate (per-session) ────────────────
        # True once the ASR_Server reports ready this session — gates the pump.
        self._model_ready: bool = False
        # True if Model_Load errored/timed out this session.
        self._load_failed: bool = False
        # Most recent Load_Latency (ms) measured for this session, if any.
        self._load_latency_ms: int | None = None

        # Provider pools (rebuilt from settings on each session start)
        self._stt_pool: ProviderPool | None = None
        self._llm_pool: ProviderPool | None = None
        # Last LLM error message — carried to the "all exhausted" notification
        self._last_llm_error: str = ""
        # Smart-rotation tracker: learns each LLM provider's live headroom
        # from usage + rate-limit signals so selection prefers whoever has the
        # most remaining capacity for THIS request. Persists across sessions
        # (cooldowns/usage windows are time-based) so a 429 in one session
        # still steers the next.
        self._rotation = RotationTracker()

        # Wire all services and signals in setup()
        # Two hotkeys: dictation hotkey and AI hotkey
        self._hotkey_service_ai = HotkeyService()  # second service for AI hotkey
        # Track which hotkey started the current session
        self._session_mode: str = "dictation"  # "dictation" | "voice_to_ai"

        # Worker signals (single shared instance)
        self._worker_signals = _WorkerSignals()

        # Midnight quota-reset timer
        self._midnight_timer = QTimer(self)
        self._midnight_timer.setSingleShot(True)
        self._midnight_timer.timeout.connect(self._on_midnight)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def setup(self) -> None:
        """Wire all services and register the hotkey.  Call once after __init__."""
        # Connect AudioService capture signal (record-then-transcribe path).
        # NOTE: amplitude_changed is intentionally NOT connected to the pill.
        # The pill is driven by the isolated VolumeMeterService so the model's
        # audio pipeline can never influence the visualization (and vice versa).
        self._audio_service.capture_finished.connect(self._on_capture_finished)

        # Connect ChunkedAudioService signals (local streaming path).
        # amplitude_changed is intentionally NOT connected here either.
        self._chunked_audio.chunk_ready.connect(self._on_chunk_ready)
        self._chunked_audio.recording_stopped.connect(
            self._on_chunked_recording_stopped
        )

        # Isolated pill meter — its shaped level (0.0–1.0) drives the pill directly.
        self._volume_meter.level_changed.connect(self._on_meter_level)

        # Connect HotkeyService (dictation)
        self._hotkey_service.hotkey_triggered.connect(self._on_hotkey_dictation)

        # Connect AI hotkey service
        self._hotkey_service_ai.hotkey_triggered.connect(self._on_hotkey_ai)

        # Connect PillViewModel confirm button
        self.pill_vm.confirm_clicked.connect(self._on_confirm_clicked)

        # Connect worker signals
        self._worker_signals.stt_complete.connect(self._on_stt_complete)
        self._worker_signals.stt_error.connect(self._on_stt_error)
        self._worker_signals.llm_complete.connect(self._on_llm_complete)
        self._worker_signals.llm_error.connect(self._on_llm_error)
        self._worker_signals.llm_rate_limited.connect(self._on_llm_rate_limited)
        self._worker_signals.chunk_stt_complete.connect(self._on_chunk_stt_complete)
        self._worker_signals.chunk_stt_error.connect(self._on_chunk_stt_error)

        # Connect on-demand Model_Load lifecycle signals (local STT).
        if self._local_stt_manager is not None:
            self._local_stt_manager.server_ready.connect(self._on_model_ready)
            self._local_stt_manager.load_failed.connect(self._on_model_load_failed)

        # Register hotkeys (dictation + AI)
        self._register_hotkeys()

        # Schedule midnight quota reset
        self._schedule_midnight_reset()

    def get_last_transcribed(self) -> str:
        return self._last_transcribed

    def get_last_processed(self) -> str:
        return self._last_processed

    def update_settings(self, settings: AppSettings) -> None:
        """Called when the user saves settings. Re-registers hotkeys if changed."""
        old_hotkey = self._settings.hotkey
        old_hotkey_ai = self._settings.hotkey_ai
        self._settings = settings
        self._router.update_settings(settings)

        if settings.hotkey != old_hotkey or settings.hotkey_ai != old_hotkey_ai:
            self._register_hotkeys()

    # ------------------------------------------------------------------
    # Private — hotkey registration
    # ------------------------------------------------------------------

    def _register_hotkeys(self) -> None:
        """Register both the dictation and AI hotkeys."""
        ok1 = self._hotkey_service.register(self._settings.hotkey)
        if not ok1:
            self._notify(
                "Hotkey conflict",
                f"Could not register dictation hotkey '{self._settings.hotkey}'.",
            )
            self.open_settings_requested.emit()

        ok2 = self._hotkey_service_ai.register(self._settings.hotkey_ai)
        if not ok2:
            self._notify(
                "Hotkey conflict",
                f"Could not register AI hotkey '{self._settings.hotkey_ai}'.",
            )

    # ------------------------------------------------------------------
    # Private — midnight quota reset
    # ------------------------------------------------------------------

    def _schedule_midnight_reset(self) -> None:
        now = datetime.now()
        tomorrow_midnight = datetime(now.year, now.month, now.day) + timedelta(days=1)
        ms_until_midnight = int((tomorrow_midnight - now).total_seconds() * 1000)
        self._midnight_timer.start(ms_until_midnight)

    @Slot()
    def _on_midnight(self) -> None:
        self._router.reset_daily_counts()
        self._schedule_midnight_reset()

    # ------------------------------------------------------------------
    # Private — tray notifications
    # ------------------------------------------------------------------

    def _notify(self, title: str, message: str) -> None:
        self.show_notification.emit(title, message)
        if self._tray_icon is not None:
            self._tray_icon.showMessage(title, message)

    # ------------------------------------------------------------------
    # Private — state helpers
    # ------------------------------------------------------------------

    def _set_state(self, state: SessionState) -> None:
        self._state = state
        self.pill_vm.state = state.name.lower()  # type: ignore[assignment]
        self.state_changed.emit(state.name)

    # ------------------------------------------------------------------
    # Private — session lifecycle
    # ------------------------------------------------------------------

    def _start_recording(self) -> None:
        """IDLE → RECORDING or STREAMING depending on STT provider."""
        self._session_id = str(uuid.uuid4())
        self._session_start = datetime.now()
        self._fallbacks = []
        self._current_transcript = ""
        self._stt_provider = None
        self._llm_provider = None
        self._wav_bytes = b""
        self._stt_attempted_ids = set()
        self._llm_attempted_ids = set()
        self._stream_transcript = ""
        self._stream_stt_latency_total_ms = 0
        self._stream_chunk_count = 0
        self._stream_queue.clear()
        self._stream_busy = False
        self._stream_recording_done = False
        self._stream_last_error = ""
        self._stream_assembler.reset()
        self._stream_coverage_gaps = []
        # New generation — any in-flight worker from a prior session is now stale.
        self._stream_generation += 1

        # Clear any leftover overlap audio from a previous session so the new
        # recording can never be contaminated with words from the last one.
        self._chunked_audio.reset()

        # Voice processing (Process Audio toggle): applied per session so a
        # settings change takes effect on the next recording without restart.
        self._chunked_audio.set_conditioning(self._settings.process_audio)
        self._audio_service.set_conditioning(self._settings.process_audio)

        active_stt = self._active_stt_providers()
        self._stt_pool = ProviderPool(active_stt)
        self._llm_pool = ProviderPool(self._active_llm_providers())

        # Use the 10s rolling-window streaming path when the active provider
        # is the local Parakeet server. This transcribes WHILE you speak so
        # that pressing stop feels near-instant. Requests are SERIALIZED (one
        # at a time) so the single-threaded local server is never overloaded.
        # Cloud providers use single-shot record-then-send.
        use_chunked = bool(active_stt) and _is_local_provider(active_stt[0])

        self.pill_vm.transcript_text = ""  # type: ignore[assignment]
        self.pill_vm.is_visible = True  # type: ignore[assignment]

        # Start the isolated pill meter (its own mic stream — never touches the model).
        self._volume_meter.start(self._settings.microphone_device_id)

        if use_chunked:
            try:
                self._chunked_audio.start(self._settings.microphone_device_id)
            except AudioDeviceError as exc:
                self._volume_meter.stop()
                self._notify(
                    "Microphone unavailable", f"Could not open microphone: {exc}"
                )
                self.pill_vm.is_visible = False  # type: ignore[assignment]
                return
            # Strict ordering (R1.3, R1.4): capture is already running, move to
            # STREAMING, reset the readiness flags, THEN kick off Model_Load last
            # so audio is being buffered before any load work begins.
            self._set_state(SessionState.STREAMING)
            self._model_ready = False
            self._load_failed = False
            self._load_latency_ms = None
            if self._local_stt_manager is not None:
                self._local_stt_manager.load(self._settings.local_stt_load_timeout_s)
        else:
            try:
                self._audio_service.start(self._settings.microphone_device_id)
            except AudioDeviceError as exc:
                self._volume_meter.stop()
                self._notify(
                    "Microphone unavailable", f"Could not open microphone: {exc}"
                )
                self.pill_vm.is_visible = False  # type: ignore[assignment]
                return
            self._set_state(SessionState.RECORDING)

    def _stop_recording_and_process(self) -> None:
        """Stop recording. For STREAMING: stop chunked audio (last chunk fires via signal).
        For RECORDING: stop regular audio (capture_finished fires)."""
        # Stop the isolated pill meter — the pill animates on its own in PROCESSING.
        self._volume_meter.stop()

        if self._state == SessionState.STREAMING:
            # stop() will emit the final chunk then recording_stopped
            self._chunked_audio.stop()
            # Stay in STREAMING until recording_stopped fires
        else:
            self._set_state(SessionState.PROCESSING)
            self._audio_service.stop()

    # ------------------------------------------------------------------
    # Slots — external events
    # ------------------------------------------------------------------

    @Slot()
    def _on_hotkey_dictation(self) -> None:
        """Dictation hotkey: start recording (dictation mode) or stop+paste."""
        if self._state == SessionState.IDLE:
            self._session_mode = "dictation"
            self._start_recording()
        elif self._state in (SessionState.RECORDING, SessionState.STREAMING):
            self._stop_recording_and_process()

    @Slot()
    def _on_hotkey_ai(self) -> None:
        """AI hotkey: start recording (voice-to-AI mode) or stop+send to AI."""
        if self._state == SessionState.IDLE:
            self._session_mode = "voice_to_ai"
            self._start_recording()
        elif self._state in (SessionState.RECORDING, SessionState.STREAMING):
            self._stop_recording_and_process()

    @Slot()
    def _on_confirm_clicked(self) -> None:
        if self._state in (SessionState.RECORDING, SessionState.STREAMING):
            self._stop_recording_and_process()

    @Slot(float)
    def _on_meter_level(self, level: float) -> None:
        """Receives the already-shaped 0.0–1.0 level from the isolated meter."""
        self.pill_vm.amplitude_level = level  # type: ignore[assignment]

    @Slot(bytes)
    def _on_capture_finished(self, wav_bytes: bytes) -> None:
        self._wav_bytes = wav_bytes
        self._dispatch_stt()

    # ------------------------------------------------------------------
    # Streaming mode — chunk handling
    # ------------------------------------------------------------------

    # ------------------------------------------------------------------
    # Streaming mode — serialized 10s rolling-window chunk handling
    #
    # Design contract (production-grade, unbreakable):
    #   * At most ONE chunk request is in flight at any moment (_stream_busy).
    #     New chunks queue in _stream_queue and are sent strictly in order.
    #     This prevents overloading the single-threaded local server, which was
    #     the root cause of "speak for minutes, press stop, it just closes".
    #   * Every worker result carries the session generation. Results from a
    #     stale generation are dropped, so a late response can never corrupt a
    #     new session or trigger a phantom finalize.
    #   * The session finalizes only when recording has stopped AND the queue is
    #     empty AND nothing is in flight — so the final (possibly mid-sentence)
    #     chunk is always transcribed before we finish.
    #   * If anything was transcribed, we paste it — even if a later chunk
    #     failed. We only show an empty-result message when truly nothing came
    #     back, and we distinguish "server down" from "no speech".
    # ------------------------------------------------------------------

    @Slot(object)
    def _on_chunk_ready(self, chunk: AudioChunk) -> None:
        """A finalized audio chunk is ready. Enqueue it and pump the queue."""
        if self._state not in (SessionState.STREAMING, SessionState.PROCESSING):
            return
        if not chunk or not chunk.wav_bytes:
            return
        self._stream_queue.append(chunk)
        self._pump_stream_queue()

    def _pump_stream_queue(self) -> None:
        """Dispatch the next queued chunk IF nothing is currently in flight.

        This is the serialization gate: exactly one request to the server at a
        time. Called whenever a chunk is enqueued or a request completes.

        Readiness gate (R2.1, R2.5, R6.1, R6.3): while the ASR_Server is not yet
        ready, finalized chunks remain queued in capture order and nothing is
        dispatched. Draining begins only once `_on_model_ready` fires.
        """
        if not self._model_ready:
            return
        if self._stream_busy:
            return
        if not self._stream_queue:
            # Nothing left to send — maybe we're done.
            self._maybe_finalize_streaming_session()
            return
        if not self._settings.stt_providers:
            return

        chunk = self._stream_queue.popleft()
        provider = self._settings.stt_providers[0]
        api_key = self._credential_store.get_key(provider.id)
        self._stream_busy = True
        self._stt_start = datetime.now()

        worker = _ChunkSTTWorker(
            generation=self._stream_generation,
            stt_client=self._stt_client,
            provider=provider,
            chunk=chunk,
            api_key=api_key,
            signals=self._worker_signals,
        )
        QThreadPool.globalInstance().start(worker)

    @Slot()
    def _on_model_ready(self) -> None:
        """ASR_Server reported ready (R2.2, R6.3). Open the readiness gate,
        record the measured Load_Latency for this session, and begin draining
        any chunks buffered while the model was loading."""
        self._model_ready = True
        if self._local_stt_manager is not None:
            self._load_latency_ms = self._local_stt_manager.last_load_latency_ms
        self._pump_stream_queue()

    @Slot(str)
    def _on_model_load_failed(self, reason: str) -> None:
        """Model_Load could not complete this session (R7.1, R7.3–R7.6).

        Surface a clear notification, mark the failure, clear any buffered audio
        and stream state (R7.6), request unload so no half-started subprocess
        lingers (R7.5), and return to IDLE via ``_discard_session`` (R7.4). All
        of this runs synchronously on the main thread in direct reaction to the
        ``load_failed`` signal, so it completes well within the 1 s bound.
        """
        self._load_failed = True

        # Map the machine-readable reason to a sensible user-facing message.
        title, message = self._load_failure_message(reason)
        self._notify(title, message)

        # When the model is missing (venv present but weights deleted), open the
        # settings panel so the user immediately sees the START/INSTALL button
        # that triggers the download, rather than just a tray notification.
        if reason in ("missing-cache", "not-installed"):
            self.open_settings_requested.emit()

        # Drop everything we buffered while waiting for the model so the next
        # session starts clean (R7.6). The generation bump in _discard_session
        # additionally invalidates any in-flight worker.
        self._stream_queue.clear()
        self._stream_busy = False
        self._stream_recording_done = False
        self._stream_last_error = ""

        # Return to IDLE. _discard_session applies the configured unload policy;
        # the manager has already torn down any half-started subprocess on
        # timeout/crash, so no extra unload is needed here.
        self._discard_session()

    @staticmethod
    def _load_failure_message(reason: str) -> tuple[str, str]:
        """Translate a ``load_failed`` reason code into (title, message)."""
        if reason == "missing-cache":
            return (
                "Local model not found",
                "The local speech-to-text model files are missing. Open Settings "
                "\u2192 Local STT and reinstall the model, then try again.",
            )
        if reason == "not-installed":
            return (
                "Local STT not installed",
                "The local speech-to-text engine is not installed. Open Settings "
                "\u2192 Local STT to install it, then try again.",
            )
        if reason == "timeout":
            return (
                "Model load timed out",
                "The local speech-to-text model took too long to load. Try again, "
                "or increase the load timeout in Settings \u2192 Local STT.",
            )
        if reason == "launch":
            return (
                "Could not start local STT",
                "The local speech-to-text server failed to start. Open Settings "
                "\u2192 Local STT and check the installation, then try again.",
            )
        return (
            "Local STT load failed",
            "The local speech-to-text model could not be loaded. Open Settings "
            "\u2192 Local STT to check it, then try again.",
        )

    @Slot()
    def _on_chunked_recording_stopped(self) -> None:
        """User stopped recording. The final chunk has already been enqueued via
        chunk_ready (emitted before recording_stopped). Move to PROCESSING and
        let the queue drain to completion."""
        self._stream_recording_done = True
        if self._state == SessionState.STREAMING:
            self._set_state(SessionState.PROCESSING)
        # Pump in case the queue is idle (e.g. nothing was in flight).
        self._pump_stream_queue()

    @Slot(int, object, object)
    def _on_chunk_stt_complete(
        self, generation: int, chunk: AudioChunk, result
    ) -> None:
        """A chunk transcript arrived. Merge it, then send the next queued chunk."""
        if generation != self._stream_generation:
            return  # stale result from a previous session — ignore
        if self._state not in (SessionState.STREAMING, SessionState.PROCESSING):
            return

        self._stream_busy = False

        if result.text.strip() or result.has_word_timings:
            self._stream_transcript = self._stream_assembler.add_chunk(
                chunk_start_sec=chunk.start_sec,
                fresh_start_sec=chunk.fresh_start_sec,
                text=result.text,
                words=result.words,
            )
            self.pill_vm.transcript_text = self._stream_transcript  # type: ignore[assignment]
            self._stream_chunk_count += 1
            if self._stt_start:
                self._stream_stt_latency_total_ms += int(
                    (datetime.now() - self._stt_start).total_seconds() * 1000
                )

        # Send the next queued chunk (or finalize if done).
        self._pump_stream_queue()

    @Slot(int, object, str)
    def _on_chunk_stt_error(self, generation: int, chunk: AudioChunk, error: str) -> None:
        """A chunk failed. Retry it once (the audio is still in hand), then
        continue with the next queued chunk — a single failed chunk must never
        abort the whole session."""
        if generation != self._stream_generation:
            return  # stale result — ignore
        if self._state not in (SessionState.STREAMING, SessionState.PROCESSING):
            return

        self._stream_busy = False

        # One retry per chunk: transient hiccups (server warm-up, socket reset)
        # shouldn't cost the user that time range. Re-queue at the FRONT so
        # capture order — and therefore assembly order — is preserved.
        if chunk.attempts < 1:
            chunk.attempts += 1
            self._stream_queue.appendleft(chunk)
            self._pump_stream_queue()
            return

        # Retry exhausted — record the lost fresh range in the coverage ledger
        # so the gap is visible in the logs instead of silently missing.
        self._stream_coverage_gaps.append((chunk.fresh_start_sec, chunk.end_sec))
        self._stream_last_error = error
        try:
            self._logger.log_fallback(
                FallbackLogEntry(
                    session_id=self._session_id,
                    timestamp=datetime.now().isoformat(),
                    original_provider_id=(
                        self._settings.stt_providers[0].id
                        if self._settings.stt_providers
                        else "local"
                    ),
                    reason=(
                        f"{error} [lost audio "
                        f"{chunk.fresh_start_sec:.1f}s-{chunk.end_sec:.1f}s "
                        f"after retry]"
                    ),
                    fallback_provider_id="none",
                )
            )
        except Exception:  # noqa: BLE001
            pass

        # Keep going — drain the rest of the queue, then finalize.
        self._pump_stream_queue()

    def _maybe_finalize_streaming_session(self) -> None:
        """Finalize only when: recording stopped, queue empty, nothing in flight."""
        if not self._stream_recording_done:
            return
        if self._stream_busy:
            return
        if self._stream_queue:
            return
        # While Model_Load is still in progress after recording stopped, the
        # queue may momentarily be empty — but we must NOT finalize-as-empty
        # (R6.2). Only finalize once the model is ready (so buffered chunks have
        # been transcribed) or the load has failed (R6.6).
        if not (self._model_ready or self._load_failed):
            return
        if self._state != SessionState.PROCESSING:
            return
        self._finalize_streaming_session()

    def _finalize_streaming_session(self) -> None:
        """Called when recording stopped and the chunk queue is fully drained."""
        if self._state != SessionState.PROCESSING:
            return

        final_transcript = self._stream_transcript.strip()
        self._current_transcript = final_transcript
        stt_latency_ms = self._stream_stt_latency_total_ms // max(
            self._stream_chunk_count, 1
        )

        # Surface coverage gaps: the user should know a range went missing
        # rather than discovering truncated text later (production guarantee —
        # no silent loss).
        if final_transcript and self._stream_coverage_gaps:
            ranges = ", ".join(
                f"{start:.0f}–{end:.0f}s" for start, end in self._stream_coverage_gaps
            )
            self._notify(
                "Partial transcription",
                f"Some audio could not be transcribed ({ranges} into the "
                "recording). The rest was pasted.",
            )

        # If we got ANY text, use it — even if a later chunk failed. Losing a
        # tail is far better than discarding everything the user said.
        if not final_transcript:
            if self._stream_last_error:
                self._notify(
                    "Transcription failed",
                    "The local speech-to-text server did not respond. Open "
                    "Settings \u2192 Local STT and make sure it is running, then try again.",
                )
            else:
                self._notify(
                    "No speech detected",
                    "Nothing was transcribed from this recording.",
                )
            self._discard_session()
            return

        if not self._settings.stt_providers:
            self._discard_session()
            return

        # Record transcription \u2014 available to tray + UI regardless of mode
        self._last_transcribed = final_transcript
        self.transcription_result_ready.emit(final_transcript, datetime.now().strftime("%H:%M"))

        provider = self._settings.stt_providers[0]

        if self._session_mode == "dictation":
            self._clipboard_service.paste(final_transcript)
            self._log_session(
                stt_provider_id=provider.id,
                stt_latency_ms=stt_latency_ms,
                stt_outcome="success",
            )
            self._finish_session()
        else:
            self._dispatch_llm(
                transcript=final_transcript,
                stt_provider_id=provider.id,
                stt_latency_ms=stt_latency_ms,
            )

    # ------------------------------------------------------------------
    # Private — provider selection
    # ------------------------------------------------------------------

    def _active_stt_providers(self) -> list:
        """Return the providers that should be used for routing this session.

        Smart rotation ON  → all enabled *cloud* providers (round-robin pool).
        Smart rotation OFF → the single enabled provider (local or cloud).
        """
        s = self._settings
        if s.stt_smart_rotation:
            return [p for p in s.stt_providers if p.enabled and not _is_local_provider(p)]
        else:
            return [p for p in s.stt_providers if p.enabled][:1]

    def _active_llm_providers(self) -> list:
        """Return the LLM providers that should be used for routing.

        Smart rotation ON  → all enabled providers (round-robin pool).
        Smart rotation OFF → the single enabled provider.
        """
        s = self._settings
        if s.llm_smart_rotation:
            return [p for p in s.llm_providers if p.enabled]
        else:
            return [p for p in s.llm_providers if p.enabled][:1]

    # ------------------------------------------------------------------
    # Private — STT dispatch and fallback
    # ------------------------------------------------------------------

    def _dispatch_stt(self) -> None:
        assert self._stt_pool is not None
        # Find the next provider we haven't tried yet this session
        provider = None
        for _ in range(len(self._stt_pool.providers)):
            try:
                candidate = self._router.next_provider(self._stt_pool)
            except ProviderError:
                break
            if candidate.id not in self._stt_attempted_ids:
                provider = candidate
                break
            # Already tried this one — keep cycling

        if provider is None:
            # Distinguish a local-server-down failure from a general one so the
            # user knows exactly what to check.
            local_in_pool = any(
                (
                    "127.0.0.1" in (p.base_url or "").lower()
                    or "localhost" in (p.base_url or "").lower()
                )
                for p in self._stt_pool.providers
            )
            if local_in_pool:
                self._notify(
                    "Transcription failed",
                    "The local speech-to-text server did not respond. Open "
                    "Settings \u2192 Local STT and make sure it is running, then try again.",
                )
            else:
                self._notify(
                    "Transcription failed",
                    "All speech-to-text providers failed. Check your network and "
                    "provider settings, then try again.",
                )
            self._discard_session()
            return

        self._stt_attempted_ids.add(provider.id)
        self._stt_provider = provider
        self._stt_start = datetime.now()
        api_key = self._credential_store.get_key(provider.id)
        worker = _STTWorker(
            self._stt_client, provider, self._wav_bytes, api_key, self._worker_signals
        )
        QThreadPool.globalInstance().start(worker)

    @Slot(str)
    def _on_stt_complete(self, transcript: str) -> None:
        if self._state != SessionState.PROCESSING:
            return

        assert self._stt_provider is not None
        assert self._stt_start is not None

        self._router.record_usage(self._stt_provider.id)
        stt_latency_ms = int((datetime.now() - self._stt_start).total_seconds() * 1000)
        self._current_transcript = transcript
        self.pill_vm.transcript_text = transcript  # type: ignore[assignment]

        # Empty transcript → do NOT paste. Pasting "" is a no-op on Windows,
        # so Ctrl+V would paste whatever was already on the clipboard (the last
        # transcription). Surface a clear message instead.
        if not transcript.strip():
            self._notify(
                "No speech detected",
                "Nothing was transcribed from this recording.",
            )
            self._log_session(
                stt_provider_id=self._stt_provider.id,
                stt_latency_ms=stt_latency_ms,
                stt_outcome="empty",
            )
            self._discard_session()
            return

        # Record transcription — available to tray + UI regardless of mode
        self._last_transcribed = transcript
        self.transcription_result_ready.emit(transcript, datetime.now().strftime("%H:%M"))

        if self._session_mode == "dictation":
            self._clipboard_service.paste(transcript)
            self._log_session(
                stt_provider_id=self._stt_provider.id,
                stt_latency_ms=stt_latency_ms,
                stt_outcome="success",
            )
            self._finish_session()
        else:
            self._dispatch_llm(
                transcript=transcript,
                stt_provider_id=self._stt_provider.id,
                stt_latency_ms=stt_latency_ms,
            )

    @Slot(str)
    def _on_stt_error(self, error: str) -> None:
        if self._state != SessionState.PROCESSING:
            return

        assert self._stt_provider is not None

        # Log the failure
        self._logger.log_fallback(
            FallbackLogEntry(
                session_id=self._session_id,
                timestamp=datetime.now().isoformat(),
                original_provider_id=self._stt_provider.id,
                reason=error,
                fallback_provider_id="next",
            )
        )

        # Try the next untried provider
        self._dispatch_stt()

    # ------------------------------------------------------------------
    # Private — LLM dispatch and fallback
    # ------------------------------------------------------------------

    def _dispatch_llm(
        self, transcript: str, stt_provider_id: str, stt_latency_ms: int
    ) -> None:
        assert self._llm_pool is not None
        self._pending_stt_provider_id = stt_provider_id
        self._pending_stt_latency_ms = stt_latency_ms

        # No providers configured or enabled at all
        if not self._llm_pool.providers:
            msg = "No LLM providers are configured or enabled. Add a provider in Settings → Transcription."
            self._notify("Processing skipped", msg)
            self.llm_error_occurred.emit(msg)
            self._log_session(
                stt_provider_id=stt_provider_id,
                stt_latency_ms=stt_latency_ms,
                stt_outcome="success",
                llm_provider_id=None,
                llm_latency_ms=None,
                llm_outcome="no_providers",
            )
            self._finish_session()
            return

        # Candidates: enabled providers not yet tried this session and within
        # the user's hard daily quota (a real cap — the tracker only reorders,
        # it never excludes, so quota stays an explicit hard gate here).
        untried = [
            p
            for p in self._llm_pool.providers
            if p.id not in self._llm_attempted_ids and self._router.is_eligible(p)
        ]

        system_prompt = self._build_system_prompt()
        provider = None
        if untried:
            if self._settings.llm_smart_rotation and len(untried) > 1:
                # Smart rotation: order by live headroom for THIS request size.
                # estimate_tokens already includes a completion reserve.
                est = estimate_tokens(transcript + (system_prompt or ""))
                provider = self._rotation.select(untried, est)[0]
            else:
                provider = untried[0]

        if provider is None:
            # All providers tried and failed — surface the last actual error
            detail = f" Last error: {self._last_llm_error}" if self._last_llm_error else ""
            msg = f"All LLM providers failed.{detail}"
            self._notify("Processing failed", msg)
            self.llm_error_occurred.emit(msg)
            self._log_session(
                stt_provider_id=stt_provider_id,
                stt_latency_ms=stt_latency_ms,
                stt_outcome="success",
                llm_provider_id=None,
                llm_latency_ms=None,
                llm_outcome="all_providers_exhausted",
            )
            self._finish_session()
            return

        self._llm_attempted_ids.add(provider.id)
        self._llm_provider = provider
        self._llm_start = datetime.now()
        api_key = self._credential_store.get_key(provider.id)
        worker = _LLMWorker(
            self._llm_client,
            provider,
            transcript,
            api_key,
            self._worker_signals,
            system_prompt=system_prompt,
        )
        QThreadPool.globalInstance().start(worker)

    def _build_system_prompt(self) -> str | None:
        """Build the effective system prompt, injecting vocabulary if present.

        Priority: active directive prompt → global_system_prompt → None.
        """
        active_prompt = next(
            (p for p in self._settings.prompts if p.is_active), None
        )
        raw_base = (active_prompt.text if active_prompt else self._settings.global_system_prompt) or ""
        base = raw_base.strip()
        words = getattr(self._settings, "word_dictionary", [])
        if not words:
            return base or None
        word_list = "\n".join(f"  • {w}" for w in words)
        addendum = (
            "\n\n---\n"
            "The user has a custom vocabulary dictionary. These words are often "
            "mis-transcribed by speech-to-text — they may be proper nouns, technical "
            "terms, or words that sound like common phrases:\n"
            f"{word_list}\n\n"
            "When processing the transcript: if a word or phrase phonetically or "
            "visually resembles an entry from the dictionary and the context makes "
            "that meaning plausible, prefer the dictionary form. Only substitute "
            "when confident (above ~70%) — do not force a correction when the "
            "original is unambiguous."
        )
        return (base + addendum) if base else addendum.lstrip()

    @Slot(object)
    def _on_llm_complete(self, result) -> None:
        if self._state != SessionState.PROCESSING:
            return

        assert self._llm_provider is not None
        assert self._llm_start is not None

        response = result.text
        self._router.record_usage(self._llm_provider.id)
        # Feed the smart-rotation tracker the live usage + limit signals this
        # response carried, so the next request prefers whoever has headroom.
        self._rotation.record_success(
            self._llm_provider.id,
            total_tokens=result.total_tokens,
            remaining_requests=result.remaining_requests,
            remaining_tokens=result.remaining_tokens,
        )
        llm_latency_ms = int((datetime.now() - self._llm_start).total_seconds() * 1000)

        # Guard against empty LLM output — pasting "" would leave the old
        # clipboard contents and Ctrl+V would paste something stale.
        if not response.strip():
            self._notify(
                "Empty AI response",
                "The AI returned no text. Your transcript is kept in the pill.",
            )
            self.pill_vm.transcript_text = self._current_transcript  # type: ignore[assignment]
            self._log_session(
                stt_provider_id=self._pending_stt_provider_id,
                stt_latency_ms=self._pending_stt_latency_ms,
                stt_outcome="success",
                llm_provider_id=self._llm_provider.id,
                llm_latency_ms=llm_latency_ms,
                llm_outcome="empty",
            )
            self._finish_session()
            return

        # Record processed result — available to tray + UI
        self._last_processed = response
        self._last_llm_error = ""  # clear any previous error on success
        self.processing_result_ready.emit(response, datetime.now().strftime("%H:%M"))

        self._clipboard_service.paste(response)
        self.pill_vm.transcript_text = response  # type: ignore[assignment]

        self._log_session(
            stt_provider_id=self._pending_stt_provider_id,
            stt_latency_ms=self._pending_stt_latency_ms,
            stt_outcome="success",
            llm_provider_id=self._llm_provider.id,
            llm_latency_ms=llm_latency_ms,
            llm_outcome="success",
        )
        self._finish_session()

    @Slot(str, float)
    def _on_llm_rate_limited(self, provider_id: str, retry_after_s: float) -> None:
        """A provider returned HTTP 429 — put it on cooldown and fall back.

        The cooldown steers selection away from this provider for the stated
        Retry-After window, across this and future sessions, until a success
        clears it. This is the core of free-tier juggling."""
        if self._state != SessionState.PROCESSING:
            return
        assert self._llm_provider is not None

        self._rotation.record_rate_limited(provider_id, retry_after_s)
        self._last_llm_error = f"{self._llm_provider.name}: rate limited (429)"
        self.llm_error_occurred.emit(self._last_llm_error)
        self._logger.log_fallback(
            FallbackLogEntry(
                session_id=self._session_id,
                timestamp=datetime.now().isoformat(),
                original_provider_id=provider_id,
                reason=f"rate-limited; cooldown {retry_after_s:.0f}s",
                fallback_provider_id="next",
            )
        )
        self._dispatch_llm(
            transcript=self._current_transcript,
            stt_provider_id=self._pending_stt_provider_id,
            stt_latency_ms=self._pending_stt_latency_ms,
        )

    @Slot(str)
    def _on_llm_error(self, error: str) -> None:
        if self._state != SessionState.PROCESSING:
            return

        assert self._llm_provider is not None

        # Non-429 failure (network, 5xx, timeout): brief cooldown so the next
        # session fans out, but never a hard exclusion.
        self._rotation.record_error(self._llm_provider.id)

        # Capture error for the exhaustion notification and emit immediately
        # so the UI can show which provider and what went wrong.
        provider_label = self._llm_provider.name
        self._last_llm_error = f"{provider_label}: {error}"
        self.llm_error_occurred.emit(self._last_llm_error)

        # Log the failure
        self._logger.log_fallback(
            FallbackLogEntry(
                session_id=self._session_id,
                timestamp=datetime.now().isoformat(),
                original_provider_id=self._llm_provider.id,
                reason=error,
                fallback_provider_id="next",
            )
        )

        # Try the next untried provider (dispatch_llm handles exhaustion)
        self._dispatch_llm(
            transcript=self._current_transcript,
            stt_provider_id=self._pending_stt_provider_id,
            stt_latency_ms=self._pending_stt_latency_ms,
        )

    # ------------------------------------------------------------------
    # Private — session completion helpers
    # ------------------------------------------------------------------

    def _request_model_unload(self) -> None:
        """Request Model_Unload according to the configured auto-unload policy.

        Reads ``local_stt_unload_idle_ms``: a negative value means "never"
        (keep the model loaded until quit), 0 means unload immediately, and a
        positive value defers the unload by that many milliseconds of idle
        time. Starting a new session calls ``load()``, which cancels any
        pending deferred unload. This runs entirely in the backend so the
        policy is honoured even when the UI is closed.
        """
        if self._local_stt_manager is None:
            return
        self._local_stt_manager.request_unload(self._settings.local_stt_unload_idle_ms)

    def _finish_session(self) -> None:
        # Initiate Model_Unload for local sessions per the configured idle
        # policy after a successful paste / LLM-send (R3.1, R3.3, R6.5).
        self._request_model_unload()
        self._set_state(SessionState.DONE)
        QTimer.singleShot(_PILL_HIDE_DELAY_MS, self._on_action_complete)

    @Slot()
    def _on_action_complete(self) -> None:
        self._volume_meter.stop()
        self.pill_vm.is_visible = False  # type: ignore[assignment]
        self.pill_vm.amplitude_level = 0.0  # type: ignore[assignment]
        self._stream_transcript = ""
        # Invalidate any stray in-flight workers so they can't touch a new session.
        self._stream_generation += 1
        self._stream_busy = False
        self._stream_queue.clear()
        self._set_state(SessionState.IDLE)

    def _discard_session(self) -> None:
        # Initiate Model_Unload for local sessions per the configured idle
        # policy on every discard path — no-speech, ready-then-empty, error,
        # and load-failure (R3.1, R3.4, R6.6, R7.5).
        self._request_model_unload()
        self._volume_meter.stop()
        self.pill_vm.is_visible = False  # type: ignore[assignment]
        self.pill_vm.amplitude_level = 0.0  # type: ignore[assignment]
        self._stream_transcript = ""
        # Invalidate any stray in-flight workers so they can't touch a new session.
        self._stream_generation += 1
        self._stream_busy = False
        self._stream_queue.clear()
        self._set_state(SessionState.IDLE)

    # ------------------------------------------------------------------
    # Private — logging
    # ------------------------------------------------------------------

    def _log_session(
        self,
        stt_provider_id: str,
        stt_latency_ms: int,
        stt_outcome: str,
        llm_provider_id: str | None = None,
        llm_latency_ms: int | None = None,
        llm_outcome: str | None = None,
    ) -> None:
        entry = SessionLogEntry(
            session_id=self._session_id,
            timestamp=(self._session_start or datetime.now()).isoformat(),
            mode=self._session_mode,
            stt_provider_id=stt_provider_id,
            stt_latency_ms=stt_latency_ms,
            stt_outcome=stt_outcome,
            llm_provider_id=llm_provider_id,
            llm_latency_ms=llm_latency_ms,
            llm_outcome=llm_outcome,
            fallbacks=list(self._fallbacks),
        )
        try:
            self._logger.log_session(entry)
        except Exception:  # noqa: BLE001
            pass
