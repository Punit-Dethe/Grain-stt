"""AssistController — the Grain Assist agent workflow.

Select text in ANY application, press the assist hotkey (default
Ctrl+Shift+G), and a centered input palette appears with the cursor already
in it. Type an instruction ("summarize this", "make it polite", "convert to
an email") and the selection + instruction go to the user's configured LLM.
The palette hides and a right-side panel shows the reply, with a one-shortcut
copy and a follow-up chat input at the bottom.

Fully decoupled from the console window — same isolation model as the pill:
its own controller, its own QML engine, its own frameless windows. The only
shared pieces are the settings object, the credential store, and LLMClient.

Error policy (per design): problems are surfaced INSIDE the input the user is
looking at — "no LLM configured" appears in the palette's input area; request
failures after dispatch appear above the panel's follow-up input. The reply
panel never silently swallows an error.
"""

from __future__ import annotations

import asyncio
import sys
from typing import Callable

from PySide6.QtCore import (
    Property,
    QObject,
    QRunnable,
    QThreadPool,
    QTimer,
    Signal,
    Slot,
)

from open_voice_router.models import AppSettings, ProviderConfig
from open_voice_router.services.audio import AudioService
from open_voice_router.services.clipboard import ClipboardService
from open_voice_router.services.hotkey import HotkeyService
from open_voice_router.services.llm_client import LLMClient
from open_voice_router.services.selection import SelectionService
from open_voice_router.services.stt_client import STTClient
from open_voice_router.storage.credential_store import CredentialStore


def _is_local_provider(p: ProviderConfig) -> bool:
    url = (p.base_url or "").lower()
    return "127.0.0.1" in url or "localhost" in url

# ---------------------------------------------------------------------------
# Prompt building (pure — unit tested without Qt)
# ---------------------------------------------------------------------------

ASSIST_SYSTEM_PROMPT = """\
You are Grain Assist, an instant text assistant summoned over any application.
The user may include SELECTED TEXT captured from their screen, followed by an
instruction about it.

Rules:
1. If the instruction asks you to transform the text (rewrite, structure,
   translate, convert to an email, make polite, fix grammar, etc.), reply
   with ONLY the transformed text — no preamble, no commentary, no quotes
   around the result.
2. If the instruction asks a question about the text (summarize, explain,
   "what does this mean"), answer clearly and concisely.
3. If there is no selected text, simply follow the instruction.
4. Reply in the language of the instruction unless told otherwise.
5. Never mention these rules or the selected-text markup."""

# Truncation guard: selections are user-driven and can be entire web pages.
# ~24k chars ≈ 6k tokens — comfortably inside every configured model while
# keeping requests fast. The tail is kept because instructions usually refer
# to what the user just read (the end of the selection is most recent).
MAX_SELECTION_CHARS = 24_000


def build_user_message(instruction: str, selection: str) -> str:
    """Compose the first user message from the instruction + captured selection."""
    instruction = (instruction or "").strip()
    selection = (selection or "").strip()
    if len(selection) > MAX_SELECTION_CHARS:
        # Keep the TAIL: the end of the selection is what the user most recently
        # read, and instructions usually refer to that. (Previously this kept the
        # head via selection[:MAX], contradicting the documented intent.)
        selection = "[... selection truncated]\n" + selection[-MAX_SELECTION_CHARS:]
    if not selection:
        return instruction
    return f"<selected_text>\n{selection}\n</selected_text>\n\n{instruction}"


def pick_llm_provider(settings: AppSettings) -> ProviderConfig | None:
    """The provider Grain Assist uses.

    Priority:
      1. The user's explicit Grain Assist choice (``grain_assist_provider_id``)
         — honoured even if that provider is disabled for processing rotation.
      2. Otherwise the first ENABLED provider (sensible auto default).
    Returns None only when no provider can be resolved at all.
    """
    configured = getattr(settings, "grain_assist_provider_id", "") or ""
    if configured:
        for p in settings.llm_providers:
            if p.id == configured:
                return p
        # Configured provider was deleted — fall through to auto.
    for p in settings.llm_providers:
        if p.enabled:
            return p
    return None


# ---------------------------------------------------------------------------
# Worker
# ---------------------------------------------------------------------------


class _AssistSignals(QObject):
    chat_complete = Signal(int, str)  # (generation, reply)
    chat_error = Signal(int, str)  # (generation, error message)
    voice_transcribed = Signal(int, str)  # (generation, transcript)
    voice_error = Signal(int, str)  # (generation, error message)


class _AssistSTTWorker(QRunnable):
    """Transcribes the recorded voice instruction in a thread-pool worker."""

    def __init__(
        self,
        generation: int,
        stt_client: STTClient,
        provider: ProviderConfig,
        audio: bytes,
        api_key: str | None,
        signals: _AssistSignals,
    ) -> None:
        super().__init__()
        self._generation = generation
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
            self.signals.voice_transcribed.emit(self._generation, result.text)
        except Exception as exc:  # noqa: BLE001
            self.signals.voice_error.emit(self._generation, str(exc))


class _AssistChatWorker(QRunnable):
    """Runs one LLMClient.chat() call in a thread-pool worker."""

    def __init__(
        self,
        generation: int,
        llm_client: LLMClient,
        provider: ProviderConfig,
        messages: list[dict],
        api_key: str | None,
        signals: _AssistSignals,
    ) -> None:
        super().__init__()
        self._generation = generation
        self._llm_client = llm_client
        self._provider = provider
        self._messages = messages
        self._api_key = api_key
        self.signals = signals
        self.setAutoDelete(True)

    def run(self) -> None:
        try:
            reply = asyncio.run(
                self._llm_client.chat(self._provider, self._messages, self._api_key)
            )
            self.signals.chat_complete.emit(self._generation, reply)
        except Exception as exc:  # noqa: BLE001
            self.signals.chat_error.emit(self._generation, str(exc))


# ---------------------------------------------------------------------------
# Controller / view-model (exposed to QML as `assistViewModel`)
# ---------------------------------------------------------------------------


class AssistController(QObject):
    palette_visible_changed = Signal(bool)
    panel_visible_changed = Signal(bool)
    busy_changed = Signal(bool)
    error_text_changed = Signal(str)
    selection_changed = Signal()
    messages_changed = Signal()
    recording_changed = Signal(bool)
    amplitude_changed = Signal(float)
    # Asks the QML palette to focus its input (fired after activation).
    focus_input_requested = Signal()

    def __init__(
        self,
        settings: AppSettings,
        credential_store: CredentialStore,
        llm_client: LLMClient,
        clipboard_service: ClipboardService,
        parent: QObject | None = None,
        selection_service: SelectionService | None = None,
        hotkey_service: HotkeyService | None = None,
        audio_service: AudioService | None = None,
        stt_client: STTClient | None = None,
        local_stt_manager=None,
    ) -> None:
        super().__init__(parent)
        self._settings = settings
        self._credential_store = credential_store
        self._llm_client = llm_client
        self._clipboard = clipboard_service
        self._selection_service = selection_service or SelectionService(self)
        self._hotkey = hotkey_service or HotkeyService(self)
        self._hotkey.hotkey_triggered.connect(self._on_hotkey)

        # Voice input (optional): when an AudioService + STTClient are provided,
        # the palette records as soon as it appears and Enter transcribes the
        # speech into the instruction. Without them, the palette is text-only.
        self._audio_service = audio_service
        self._stt_client = stt_client
        self._local_stt_manager = local_stt_manager
        if self._audio_service is not None:
            self._audio_service.amplitude_changed.connect(self._on_amplitude)
            self._audio_service.capture_finished.connect(self._on_capture_finished)
        self._recording = False
        self._amplitude = 0.0
        self._transcribing = False
        # One-shot connection to the local server's ready signal (set when a
        # voice transcription is waiting on a cold local model load).
        self._pending_voice_wav: bytes | None = None
        self._ready_conn = None

        # Transient GLOBAL shortcuts, live only while assist UI is on screen:
        # Global shortcuts active while the assist UI is visible.
        # The panel rarely has keyboard focus (user is still in their app),
        # so these must be true global hotkeys, not window-focus key events.
        self._close_hotkey = HotkeyService(self)
        self._close_hotkey.hotkey_triggered.connect(self._on_global_escape)
        self._copy_hotkey = HotkeyService(self)
        self._copy_hotkey.hotkey_triggered.connect(self._on_global_copy)
        # Enter stops voice recording and submits (or submits typed text when
        # the palette has focus via QML onAccepted — both paths call submit_instruction).
        self._enter_hotkey = HotkeyService(self)
        self._enter_hotkey.hotkey_triggered.connect(self._on_global_enter)
        self._transient_hotkeys_active = False

        self._signals = _AssistSignals()
        self._signals.chat_complete.connect(self._on_chat_complete)
        self._signals.chat_error.connect(self._on_chat_error)
        self._signals.voice_transcribed.connect(self._on_voice_transcribed)
        self._signals.voice_error.connect(self._on_voice_error)

        # Stale-result token: bumped on dismiss/new session so a late reply
        # from an abandoned conversation can never surface in a new one.
        self._generation = 0

        self._palette_visible = False
        self._panel_visible = False
        self._busy = False
        self._error_text = ""
        self._selection = ""
        # Full OpenAI-style history (system + turns). Display list derives.
        self._chat: list[dict] = []

        # Windows attached by main.py so the controller can force focus.
        self._palette_window = None
        self._panel_window = None
        # Lazy-UI hooks (set by main.py): the QML engine is created on the
        # first summon and torn down after dismissal, so an idle app pays
        # ZERO RAM for assist beyond this controller object.
        self._ensure_ui: Callable[[], None] | None = None
        self._release_ui: Callable[[], None] | None = None

        self._registered_combo: str | None = None
        self.update_settings(settings)

    # ------------------------------------------------------------------
    # Wiring (called from main.py)
    # ------------------------------------------------------------------

    def attach_windows(self, palette_window, panel_window) -> None:
        """Receive the QML window handles so activation can force focus."""
        self._palette_window = palette_window
        self._panel_window = panel_window

    def set_ui_hooks(
        self, ensure_ui: Callable[[], None], release_ui: Callable[[], None]
    ) -> None:
        """Install the lazy create/destroy callbacks for the QML engine."""
        self._ensure_ui = ensure_ui
        self._release_ui = release_ui

    def update_settings(self, settings: AppSettings) -> None:
        """Adopt new settings; (re)register the assist hotkey if it changed."""
        self._settings = settings
        combo = (settings.hotkey_grain or "").strip()
        if combo and combo != self._registered_combo:
            if self._hotkey.register(combo):
                self._registered_combo = combo

    # ------------------------------------------------------------------
    # QML properties
    # ------------------------------------------------------------------

    @Property(bool, notify=palette_visible_changed)
    def palette_visible(self) -> bool:
        return self._palette_visible

    @Property(bool, notify=panel_visible_changed)
    def panel_visible(self) -> bool:
        return self._panel_visible

    @Property(bool, notify=busy_changed)
    def busy(self) -> bool:
        return self._busy

    @Property(str, notify=error_text_changed)
    def error_text(self) -> str:
        return self._error_text

    @Property(bool, notify=recording_changed)
    def recording(self) -> bool:
        """True while the palette is capturing voice (drives the waveform)."""
        return self._recording

    @Property(float, notify=amplitude_changed)
    def amplitude_level(self) -> float:
        """0.0–1.0 mic level for the palette's recording waveform."""
        return self._amplitude

    @Property(bool, notify=busy_changed)
    def voice_available(self) -> bool:
        """True when voice input is wired AND an STT provider is enabled."""
        return (
            self._audio_service is not None
            and self._stt_client is not None
            and self._active_stt_provider() is not None
        )

    @Property(int, notify=selection_changed)
    def selection_char_count(self) -> int:
        return len(self._selection)

    @Property(str, notify=selection_changed)
    def selection_preview(self) -> str:
        """First line of the captured selection, trimmed for the palette chip."""
        first_line = self._selection.strip().splitlines()[0] if self._selection.strip() else ""
        return first_line[:80]

    @Property("QVariantList", notify=messages_changed)
    def chat_messages(self) -> list:
        """Display turns (system prompt and selection markup excluded)."""
        out = []
        for i, m in enumerate(self._chat):
            if m["role"] == "system":
                continue
            text = m["content"]
            # The first user turn carries the selection markup — show only
            # the instruction the user actually typed.
            if m["role"] == "user" and i == 1 and text.startswith("<selected_text>"):
                text = text.rsplit("\n\n", 1)[-1]
            out.append({"role": m["role"], "text": text})
        return out

    @Property(str, notify=messages_changed)
    def last_reply(self) -> str:
        for m in reversed(self._chat):
            if m["role"] == "assistant":
                return m["content"]
        return ""

    # ------------------------------------------------------------------
    # Hotkey → palette
    # ------------------------------------------------------------------

    @Slot()
    def _on_hotkey(self) -> None:
        if self._palette_visible:
            self._activate_window(self._palette_window)
            self.focus_input_requested.emit()
            return
        # Capture whatever is selected in the (still-focused) target app,
        # THEN show the palette — order matters, the palette steals focus.
        self._selection_service.capture(self._on_selection_captured)

    def _on_selection_captured(self, text: str) -> None:
        self._selection = text
        self.selection_changed.emit()
        self._set_error("")
        # Fresh conversation per summon; the panel (if open) is superseded.
        self._generation += 1
        self._chat = []
        self._busy = False
        self.busy_changed.emit(False)
        self._transcribing = False
        self._pending_voice_wav = None
        self.messages_changed.emit()
        # Lazily build the QML engine + windows on first use.
        if self._ensure_ui is not None:
            self._ensure_ui()
        self._set_panel_visible(False)
        self._set_palette_visible(True)
        self._activate_window(self._palette_window)
        self.focus_input_requested.emit()
        # Start recording immediately so the user can just speak. The text
        # input stays available — whichever the user provides on Enter wins.
        self._maybe_start_recording()

    # ------------------------------------------------------------------
    # QML slots
    # ------------------------------------------------------------------

    @Slot(str)
    def submit_instruction(self, instruction: str) -> None:
        """Enter in the palette. Typed text wins; otherwise transcribe the
        voice recording and use that as the instruction."""
        instruction = (instruction or "").strip()
        if instruction:
            # Typed text takes priority — drop any recording and proceed.
            self._cancel_recording()
            self._begin_chat(instruction)
            return
        # No typed text: use the voice recording if one is in progress.
        if self._recording:
            if pick_llm_provider(self._settings) is None:
                self._set_error(
                    "No LLM configured — add one in Settings → Processing, then try again."
                )
                return
            # Stop recording → _on_capture_finished dispatches transcription.
            self._transcribing = True
            self._set_busy(True)
            self._set_error("")
            self._audio_service.stop()

    def _begin_chat(self, instruction: str) -> None:
        """Start the LLM conversation from a resolved instruction (typed or
        transcribed). Shared by the text and voice paths."""
        provider = pick_llm_provider(self._settings)
        if provider is None:
            self._set_error(
                "No LLM configured — add one in Settings → Processing, then try again."
            )
            self._set_busy(False)
            return
        self._set_error("")
        self._chat = [
            {"role": "system", "content": ASSIST_SYSTEM_PROMPT},
            {"role": "user", "content": build_user_message(instruction, self._selection)},
        ]
        self.messages_changed.emit()
        # Palette disappears, panel takes over in the busy state.
        self._set_palette_visible(False)
        self._set_panel_visible(True)
        self._activate_window(self._panel_window)
        self._dispatch(provider)

    @Slot(str)
    def submit_followup(self, message: str) -> None:
        """Follow-up turn from the panel's bottom input."""
        message = (message or "").strip()
        if not message or self._busy or not self._chat:
            return
        provider = pick_llm_provider(self._settings)
        if provider is None:
            self._set_error("No LLM configured — add one in Settings → Processing.")
            return
        self._set_error("")
        self._chat.append({"role": "user", "content": message})
        self.messages_changed.emit()
        self._dispatch(provider)

    @Slot()
    def copy_reply(self) -> None:
        """Copy the latest assistant reply to the clipboard (no paste)."""
        reply = self.last_reply
        if reply:
            self._clipboard.set(reply)

    @Slot()
    def clear_error(self) -> None:
        """User started typing again — retract the inline error."""
        self._set_error("")

    @Slot()
    def stop_recording(self) -> None:
        """User started typing — abandon voice capture entirely and let them
        type. Idempotent and safe to call when not recording."""
        if self._recording or self._transcribing:
            self._cancel_recording()

    @Slot()
    def start_recording(self) -> None:
        """Restart voice capture — e.g. the user clicked Speak after typing by
        mistake. No-op if already recording or the palette is closed."""
        if self._recording or not self._palette_visible:
            return
        self._set_error("")
        self._maybe_start_recording()

    @Slot()
    def hide_palette(self) -> None:
        """Esc in the palette — cancel the summon entirely."""
        self._cancel_recording()
        self._set_palette_visible(False)
        self._set_error("")
        self._maybe_release_ui()

    @Slot()
    def dismiss(self) -> None:
        """Close everything and invalidate any in-flight request."""
        self._generation += 1
        self._cancel_recording()
        self._set_busy(False)
        self._set_palette_visible(False)
        self._set_panel_visible(False)
        self._set_error("")
        self._maybe_release_ui()

    # ------------------------------------------------------------------
    # Voice input
    # ------------------------------------------------------------------

    def _active_stt_provider(self) -> ProviderConfig | None:
        """The STT provider Grain Assist records with: the first enabled one
        (local or cloud — whichever the user has selected)."""
        for p in self._settings.stt_providers:
            if p.enabled:
                return p
        return None

    def _maybe_start_recording(self) -> None:
        """Begin mic capture as the palette appears, if voice is available.

        For a local provider we also kick off the on-demand model load so the
        server is ready (or close to it) by the time the user presses Enter.
        Any failure silently degrades to the text-only path.
        """
        if self._audio_service is None or self._stt_client is None:
            return
        provider = self._active_stt_provider()
        if provider is None:
            return
        if _is_local_provider(provider) and self._local_stt_manager is not None:
            try:
                self._local_stt_manager.load(self._settings.local_stt_load_timeout_s)
            except Exception:  # noqa: BLE001
                pass
        try:
            self._audio_service.start(self._settings.microphone_device_id)
            self._set_recording(True)
        except Exception:  # noqa: BLE001
            self._set_recording(False)

    def _cancel_recording(self) -> None:
        """Stop and discard any in-progress recording (no transcription)."""
        self._transcribing = False
        self._pending_voice_wav = None
        self._disconnect_ready()
        if self._recording and self._audio_service is not None:
            try:
                self._audio_service.stop()  # emits capture_finished; guard ignores
            except Exception:  # noqa: BLE001
                pass
        self._set_recording(False)
        self._set_amplitude(0.0)

    @Slot(float)
    def _on_amplitude(self, level: float) -> None:
        if self._recording:
            self._set_amplitude(level)

    @Slot(bytes)
    def _on_capture_finished(self, wav_bytes: bytes) -> None:
        self._set_recording(False)
        self._set_amplitude(0.0)
        if not self._transcribing:
            return  # recording was cancelled — ignore the flushed audio
        if not wav_bytes:
            self._fail_voice("Nothing was recorded — try again or type.")
            return
        provider = self._active_stt_provider()
        if provider is None:
            self._fail_voice("No speech-to-text provider is enabled.")
            return
        # For a cold local server, wait for ready before dispatching so the
        # request doesn't 503. Cloud providers dispatch immediately.
        if (
            _is_local_provider(provider)
            and self._local_stt_manager is not None
            and not self._local_stt_manager.is_running()
        ):
            self._pending_voice_wav = wav_bytes
            self._wait_for_local_ready()
            return
        self._dispatch_voice_stt(wav_bytes, provider)

    def _wait_for_local_ready(self) -> None:
        """Dispatch the pending voice STT once the local server reports ready,
        with a timeout fallback so we never hang."""
        gen = self._generation

        def _on_ready() -> None:
            self._disconnect_ready()
            if gen != self._generation or self._pending_voice_wav is None:
                return
            provider = self._active_stt_provider()
            if provider is not None:
                wav = self._pending_voice_wav
                self._pending_voice_wav = None
                self._dispatch_voice_stt(wav, provider)

        try:
            self._ready_conn = self._local_stt_manager.server_ready.connect(_on_ready)
        except Exception:  # noqa: BLE001
            self._ready_conn = None
        # Fallback: if still not ready after the load timeout, surface an error.
        QTimer.singleShot(
            max(1000, self._settings.local_stt_load_timeout_s * 1000),
            lambda: self._voice_ready_timeout(gen),
        )

    def _voice_ready_timeout(self, gen: int) -> None:
        if gen != self._generation or self._pending_voice_wav is None:
            return
        self._disconnect_ready()
        self._pending_voice_wav = None
        self._fail_voice("The local model is still loading — try again in a moment.")

    def _disconnect_ready(self) -> None:
        if self._ready_conn is not None and self._local_stt_manager is not None:
            try:
                self._local_stt_manager.server_ready.disconnect(self._ready_conn)
            except Exception:  # noqa: BLE001
                pass
        self._ready_conn = None

    def _dispatch_voice_stt(self, wav_bytes: bytes, provider: ProviderConfig) -> None:
        api_key = self._credential_store.get_key(provider.id)
        worker = _AssistSTTWorker(
            generation=self._generation,
            stt_client=self._stt_client,
            provider=provider,
            audio=wav_bytes,
            api_key=api_key,
            signals=self._signals,
        )
        QThreadPool.globalInstance().start(worker)

    @Slot(int, str)
    def _on_voice_transcribed(self, generation: int, transcript: str) -> None:
        if generation != self._generation:
            return
        self._transcribing = False
        transcript = (transcript or "").strip()
        if not transcript:
            self._fail_voice("Didn't catch that — try again or type your instruction.")
            return
        # Proceed exactly as if the user had typed this instruction.
        self._begin_chat(transcript)

    @Slot(int, str)
    def _on_voice_error(self, generation: int, error: str) -> None:
        if generation != self._generation:
            return
        self._transcribing = False
        self._fail_voice("Transcription failed — try again or type your instruction.")

    def _fail_voice(self, message: str) -> None:
        """Voice path failed — drop back to the palette so the user can retry
        or type instead."""
        self._transcribing = False
        self._set_busy(False)
        self._set_panel_visible(False)
        self._set_palette_visible(True)
        self._activate_window(self._palette_window)
        self._set_error(message)
        self.focus_input_requested.emit()

    def _maybe_release_ui(self) -> None:
        """Tear down the QML engine once nothing is on screen.

        Deferred to the next event-loop tick: this is reached from QML signal
        handlers, and the engine must never be destroyed while its JS frame is
        on the stack.
        """
        if self._palette_visible or self._panel_visible:
            return
        if self._release_ui is None:
            return
        self._palette_window = None
        self._panel_window = None
        QTimer.singleShot(0, self._release_ui)

    # ------------------------------------------------------------------
    # Transient global shortcuts (active only while assist UI is visible)
    # ------------------------------------------------------------------

    def _update_transient_hotkeys(self) -> None:
        should_be_active = self._palette_visible or self._panel_visible
        if should_be_active and not self._transient_hotkeys_active:
            self._close_hotkey.register("esc")
            self._copy_hotkey.register("ctrl+shift+c")
            self._enter_hotkey.register("enter")
            self._transient_hotkeys_active = True
        elif not should_be_active and self._transient_hotkeys_active:
            self._close_hotkey.unregister()
            self._copy_hotkey.unregister()
            self._enter_hotkey.unregister()
            self._transient_hotkeys_active = False

    @Slot()
    def _on_global_escape(self) -> None:
        if self._palette_visible:
            self.hide_palette()
        elif self._panel_visible:
            self.dismiss()

    @Slot()
    def _on_global_copy(self) -> None:
        if self._panel_visible:
            self.copy_reply()

    @Slot()
    def _on_global_enter(self) -> None:
        if self._palette_visible:
            # Stops voice recording and transcribes it (or submits typed text
            # if the palette happens to have focus — QML onAccepted fires first
            # in that case, making this a no-op).
            self.submit_instruction("")

    # ------------------------------------------------------------------
    # LLM dispatch
    # ------------------------------------------------------------------

    def _dispatch(self, provider: ProviderConfig) -> None:
        self._set_busy(True)
        api_key = self._credential_store.get_key(provider.id)
        worker = _AssistChatWorker(
            generation=self._generation,
            llm_client=self._llm_client,
            provider=provider,
            messages=list(self._chat),
            api_key=api_key,
            signals=self._signals,
        )
        QThreadPool.globalInstance().start(worker)

    @Slot(int, str)
    def _on_chat_complete(self, generation: int, reply: str) -> None:
        if generation != self._generation:
            return  # stale — conversation was dismissed/superseded
        self._set_busy(False)
        self._chat.append({"role": "assistant", "content": reply})
        self.messages_changed.emit()
        # Every reply lands on the clipboard automatically — the most common
        # next action is pasting it where the selection came from.
        if reply.strip():
            self._clipboard.set(reply)

    @Slot(int, str)
    def _on_chat_error(self, generation: int, error: str) -> None:
        if generation != self._generation:
            return
        self._set_busy(False)
        # Drop the unanswered user turn so a retry doesn't double it.
        if self._chat and self._chat[-1]["role"] == "user" and len(self._chat) > 2:
            self._chat.pop()
            self.messages_changed.emit()
        self._set_error(self._friendly_error(error))

    @staticmethod
    def _friendly_error(error: str) -> str:
        lowered = error.lower()
        if "401" in error or "unauthorized" in lowered or "invalid api key" in lowered:
            return "The LLM rejected the API key — check it in Settings → Processing."
        if "429" in error or "rate limit" in lowered or "quota" in lowered:
            return "Rate limit reached on the LLM provider — try again in a moment."
        if "timed out" in lowered or "timeout" in lowered:
            return "The LLM did not respond in time — try again."
        # Keep it short: the first line of whatever the provider said.
        first = error.strip().splitlines()[0] if error.strip() else "Unknown error"
        return f"LLM error: {first[:160]}"

    # ------------------------------------------------------------------
    # Window state helpers
    # ------------------------------------------------------------------

    def _set_busy(self, busy: bool) -> None:
        if self._busy != busy:
            self._busy = busy
            self.busy_changed.emit(busy)

    def _set_recording(self, recording: bool) -> None:
        if self._recording != recording:
            self._recording = recording
            self.recording_changed.emit(recording)

    def _set_amplitude(self, level: float) -> None:
        self._amplitude = level
        self.amplitude_changed.emit(level)

    def _set_palette_visible(self, visible: bool) -> None:
        if self._palette_visible != visible:
            self._palette_visible = visible
            self.palette_visible_changed.emit(visible)
            self._update_transient_hotkeys()

    def _set_panel_visible(self, visible: bool) -> None:
        if self._panel_visible != visible:
            self._panel_visible = visible
            self.panel_visible_changed.emit(visible)
            self._update_transient_hotkeys()

    def _set_error(self, text: str) -> None:
        if self._error_text != text:
            self._error_text = text
            self.error_text_changed.emit(text)

    @staticmethod
    def _activate_window(window) -> None:
        """Bring a frameless tool window to the foreground with focus.

        Windows refuses SetForegroundWindow to background processes; tapping
        ALT first satisfies the foreground-lock heuristic (the standard
        launcher-app workaround, used by PowerToys Run and peers).
        """
        if window is None:
            return
        try:
            window.show()
            window.raise_()
        except Exception:
            pass
        if sys.platform == "win32":
            try:
                import ctypes

                user32 = ctypes.windll.user32
                _VK_MENU, _KEYUP = 0x12, 0x0002
                user32.keybd_event(_VK_MENU, 0, 0, 0)
                user32.keybd_event(_VK_MENU, 0, _KEYUP, 0)
                user32.SetForegroundWindow(int(window.winId()))
            except Exception:
                pass
        try:
            window.requestActivate()
        except Exception:
            pass
