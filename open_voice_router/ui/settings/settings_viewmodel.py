"""SettingsViewModel — Qt context property for the Settings window.

Backed by SettingsStore and CredentialStore. Exposes provider list models,
hotkey binding, microphone selector, and mode selector to the Settings QML
window. Validates URL and non-empty API key before persisting; surfaces
KeychainError as an inline error property.
"""

from __future__ import annotations

import dataclasses
import uuid
from typing import Any

from PySide6.QtCore import Property, QObject, Signal, Slot

from open_voice_router.exceptions import KeychainError
from open_voice_router.local_asr import registry as model_registry
from open_voice_router.models import (
    PROVIDER_PRESETS,
    AppSettings,
    PromptConfig,
    ProviderConfig,
)
from open_voice_router.services.local_stt_manager import LocalSTTManager
from open_voice_router.storage.credential_store import CredentialStore
from open_voice_router.storage.settings_store import SettingsStore
from open_voice_router.validation import validate_provider_url

# Pre-built preset list — PROVIDER_PRESETS is a module-level constant so we
# only pay the serialization cost once at import time, not on every QML call.
_PRESETS_CACHE: list[dict[str, Any]] = []  # reset whenever PROVIDER_PRESETS changes


def _build_presets_cache() -> list[dict[str, Any]]:
    return [
        {
            "key": key,
            "name": preset.name,
            "base_url": preset.base_url,
            "model": preset.model,
            "provider_type": preset.provider_type,
        }
        for key, preset in PROVIDER_PRESETS.items()
    ]


def _provider_to_dict(p: ProviderConfig) -> dict[str, Any]:
    """Serialize a ProviderConfig to a plain dict for QML consumption.

    API keys are intentionally excluded — they live in the credential store.
    """
    return {
        "id": p.id,
        "name": p.name,
        "base_url": p.base_url,
        "model": p.model,
        "quota_limit": p.quota_limit if p.quota_limit is not None else -1,
        "quota_used_today": p.quota_used_today,
        "system_prompt": p.system_prompt or "",
        "kind": p.kind,
        "enabled": p.enabled,
    }


class SettingsViewModel(QObject):
    """View model for the Settings window.

    Properties exposed to QML (all notify via signals):
    - active_mode: str — "dictation" | "voice_to_ai"
    - hotkey: str — current hotkey binding
    - microphone_device_id: int — device ID (-1 = system default / None)
    - stt_providers: list[dict] — serialized ProviderConfig dicts (no API keys)
    - llm_providers: list[dict] — serialized ProviderConfig dicts (no API keys)
    - error_message: str — inline validation/keychain error ("" = no error)

    Signals:
    - settings_changed: emitted after any successful save
    - error_occurred(str): emitted alongside error_message changes
    """

    settings_changed = Signal()
    error_occurred = Signal(str)
    transcription_history_changed = Signal()
    processing_history_changed = Signal()

    active_mode_changed = Signal(str)
    hotkey_changed = Signal(str)
    hotkey_ai_changed = Signal(str)
    hotkey_grain_changed = Signal(str)
    hotkey_batch_changed = Signal(str)
    hotkey_prompt_prev_changed = Signal(str)
    hotkey_prompt_next_changed = Signal(str)
    microphone_device_id_changed = Signal(int)
    available_microphones_changed = Signal()
    microphone_combo_index_changed = Signal(int)
    close_to_tray_changed = Signal(bool)
    launch_on_boot_changed = Signal(bool)
    start_minimized_changed = Signal(bool)
    play_sound_changed = Signal(bool)
    process_audio_changed = Signal(bool)
    stt_providers_changed = Signal()
    llm_providers_changed = Signal()
    error_message_changed = Signal(str)
    global_system_prompt_changed = Signal(str)
    prompts_changed = Signal()
    word_dictionary_changed = Signal()

    stt_smart_rotation_changed = Signal(bool)
    rolling_window_s_changed = Signal(int)
    stt_local_enabled_changed = Signal(bool)
    llm_smart_rotation_changed = Signal(bool)
    grain_assist_provider_changed = Signal(str)
    llm_error_message_changed = Signal(str)
    ui_dark_mode_changed = Signal(bool)

    # Local STT signals
    local_stt_status_changed = Signal(str)
    local_stt_install_path_changed = Signal(str)
    local_stt_install_progress = Signal(str)
    local_stt_install_finished = Signal(bool, str)
    local_stt_unload_idle_changed = Signal(int)
    local_stt_load_on_startup_changed = Signal(bool)
    local_stt_model_changed = Signal(str)
    # Fired when the model catalog's volatile bits (installed flags) may have
    # changed — after installs, status transitions, or a model switch.
    local_stt_models_changed = Signal()

    def __init__(
        self,
        settings_store: SettingsStore | None = None,
        credential_store: CredentialStore | None = None,
        local_stt_manager: LocalSTTManager | None = None,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self._settings_store = settings_store or SettingsStore()
        self._credential_store = credential_store or CredentialStore()

        # Internal state — populated by load()
        self._settings: AppSettings = AppSettings.defaults()
        self._transcription_history: list[dict] = []
        self._processing_history: list[dict] = []
        self._active_mode: str = self._settings.active_mode
        self._hotkey: str = self._settings.hotkey
        self._hotkey_ai: str = self._settings.hotkey_ai
        self._hotkey_grain: str = self._settings.hotkey_grain
        self._hotkey_batch: str = self._settings.hotkey_batch
        self._hotkey_prompt_prev: str = self._settings.hotkey_prompt_prev
        self._hotkey_prompt_next: str = self._settings.hotkey_prompt_next
        self._microphone_device_id: int = (
            self._settings.microphone_device_id
            if self._settings.microphone_device_id is not None
            else -1
        )
        self._available_microphones: list[str] = ["System Default"]
        self._mic_device_ids: list[int] = [-1]
        self._microphone_combo_index: int = 0
        self._close_to_tray: bool = self._settings.close_to_tray
        self._launch_on_boot: bool = self._settings.launch_on_boot
        self._start_minimized: bool = self._settings.start_minimized
        self._play_sound: bool = self._settings.play_sound
        self._process_audio: bool = self._settings.process_audio
        self._stt_providers: list[dict[str, Any]] = []
        self._llm_providers: list[dict[str, Any]] = []
        self._error_message: str = ""
        self._global_system_prompt: str = self._settings.global_system_prompt
        self._prompts: list[dict[str, Any]] = []
        self._word_dictionary: list[str] = list(self._settings.word_dictionary)
        self._stt_smart_rotation: bool = self._settings.stt_smart_rotation
        self._stt_local_enabled: bool = True
        self._llm_smart_rotation: bool = self._settings.llm_smart_rotation
        self._llm_error_message: str = ""
        self._ui_dark_mode: bool = self._settings.ui_dark_mode

        # Local STT manager. Injected by the backend (main.py) so the same
        # single instance is shared with AppController and its lifecycle is
        # fully decoupled from this view model / the QML front-end. A default
        # instance is created when none is injected (e.g. in unit tests).
        self._local_stt = local_stt_manager or LocalSTTManager()
        self._local_stt.status_changed.connect(self.local_stt_status_changed)
        # Installed flags can flip on any status transition (install finished,
        # first load completed a download, uninstall) — refresh the catalog.
        self._local_stt.status_changed.connect(
            lambda _s: self.local_stt_models_changed.emit()
        )
        self._local_stt.install_progress.connect(self.local_stt_install_progress)
        self._local_stt.install_finished.connect(self._on_local_stt_install_finished)
        self._local_stt.server_ready.connect(self._on_local_stt_server_ready)
        self._local_stt.server_stopped.connect(self._on_local_stt_server_stopped)

    # ------------------------------------------------------------------
    # Public initializer
    # ------------------------------------------------------------------

    @Slot()
    def load(self) -> None:
        """Load settings from SettingsStore and populate internal state."""
        self._settings = self._settings_store.load()
        self._set_active_mode(self._settings.active_mode)
        self._set_hotkey(self._settings.hotkey)
        self._set_hotkey_ai(self._settings.hotkey_ai)
        self._set_hotkey_grain(self._settings.hotkey_grain)
        self._set_hotkey_batch(self._settings.hotkey_batch)
        self._set_hotkey_prompt_prev(self._settings.hotkey_prompt_prev)
        self._set_hotkey_prompt_next(self._settings.hotkey_prompt_next)
        self._set_microphone_device_id(
            self._settings.microphone_device_id
            if self._settings.microphone_device_id is not None
            else -1
        )
        self._load_microphone_devices()
        self._set_close_to_tray(self._settings.close_to_tray)
        self._set_launch_on_boot(self._settings.launch_on_boot)
        self._set_start_minimized(self._settings.start_minimized)
        self._set_play_sound(self._settings.play_sound)
        self._set_process_audio(self._settings.process_audio)
        self._set_stt_providers(
            [_provider_to_dict(p) for p in self._settings.stt_providers]
        )
        self._set_llm_providers(
            [_provider_to_dict(p) for p in self._settings.llm_providers]
        )
        self._set_error_message("")
        self._set_global_system_prompt(self._settings.global_system_prompt)
        self._set_prompts([self._prompt_to_dict(p) for p in self._settings.prompts])
        self._set_word_dictionary(list(self._settings.word_dictionary))
        self._set_stt_smart_rotation(self._settings.stt_smart_rotation)
        self._set_stt_local_enabled(self._local_provider_enabled())
        self._set_llm_smart_rotation(self._settings.llm_smart_rotation)
        self._set_ui_dark_mode(self._settings.ui_dark_mode)
        self._transcription_history = list(self._settings.transcription_history)
        self._processing_history = list(self._settings.processing_history)

        # Decouple provider registration from server readiness (R1.1, R1.2):
        # with on-demand load/unload the ASR_Server is stopped most of the time,
        # so the local provider must stay selectable while installed regardless
        # of whether the server is currently running. AppController drives the
        # per-session load/unload.
        if self._local_stt.is_installed():
            self._register_local_stt_provider()

    # ------------------------------------------------------------------
    # global_system_prompt
    # ------------------------------------------------------------------

    @Property(str, notify=global_system_prompt_changed)
    def global_system_prompt(self) -> str:
        return self._global_system_prompt

    def _set_global_system_prompt(self, value: str) -> None:
        if self._global_system_prompt != value:
            self._global_system_prompt = value
            self.global_system_prompt_changed.emit(value)

    @Slot(str)
    def save_system_prompt(self, prompt: str) -> None:
        """Persist the global system prompt."""
        self._settings = self._updated_settings(global_system_prompt=prompt)
        self._settings_store.save(self._settings)
        self._set_global_system_prompt(prompt)
        self.settings_changed.emit()

    def _updated_settings(self, **overrides) -> AppSettings:
        """Return a copy of current settings with the given fields overridden."""
        return AppSettings(
            active_mode=overrides.get("active_mode", self._settings.active_mode),
            hotkey=overrides.get("hotkey", self._settings.hotkey),
            hotkey_ai=overrides.get("hotkey_ai", self._settings.hotkey_ai),
            hotkey_grain=overrides.get("hotkey_grain", self._settings.hotkey_grain),
            hotkey_batch=overrides.get("hotkey_batch", self._settings.hotkey_batch),
            hotkey_prompt_prev=overrides.get(
                "hotkey_prompt_prev", self._settings.hotkey_prompt_prev
            ),
            hotkey_prompt_next=overrides.get(
                "hotkey_prompt_next", self._settings.hotkey_prompt_next
            ),
            close_to_tray=overrides.get("close_to_tray", self._settings.close_to_tray),
            microphone_device_id=overrides.get(
                "microphone_device_id", self._settings.microphone_device_id
            ),
            stt_providers=overrides.get("stt_providers", self._settings.stt_providers),
            llm_providers=overrides.get("llm_providers", self._settings.llm_providers),
            log_file_path=overrides.get("log_file_path", self._settings.log_file_path),
            global_system_prompt=overrides.get(
                "global_system_prompt", self._settings.global_system_prompt
            ),
            prompts=overrides.get("prompts", self._settings.prompts),
            word_dictionary=overrides.get("word_dictionary", self._settings.word_dictionary),
            launch_on_boot=overrides.get("launch_on_boot", self._settings.launch_on_boot),
            start_minimized=overrides.get("start_minimized", self._settings.start_minimized),
            play_sound=overrides.get("play_sound", self._settings.play_sound),
            process_audio=overrides.get("process_audio", self._settings.process_audio),
            local_stt_load_timeout_s=overrides.get(
                "local_stt_load_timeout_s", self._settings.local_stt_load_timeout_s
            ),
            local_stt_unload_idle_ms=overrides.get(
                "local_stt_unload_idle_ms", self._settings.local_stt_unload_idle_ms
            ),
            local_stt_load_on_startup=overrides.get(
                "local_stt_load_on_startup", self._settings.local_stt_load_on_startup
            ),
            local_stt_model_id=overrides.get(
                "local_stt_model_id", self._settings.local_stt_model_id
            ),
            rolling_window_s=overrides.get(
                "rolling_window_s", self._settings.rolling_window_s
            ),
            stt_smart_rotation=overrides.get(
                "stt_smart_rotation", self._settings.stt_smart_rotation
            ),
            llm_smart_rotation=overrides.get(
                "llm_smart_rotation", self._settings.llm_smart_rotation
            ),
            grain_assist_provider_id=overrides.get(
                "grain_assist_provider_id", self._settings.grain_assist_provider_id
            ),
            ui_dark_mode=overrides.get(
                "ui_dark_mode", self._settings.ui_dark_mode
            ),
            transcription_history=overrides.get(
                "transcription_history", self._settings.transcription_history
            ),
            processing_history=overrides.get(
                "processing_history", self._settings.processing_history
            ),
        )

    # ------------------------------------------------------------------
    # active_mode  ("dictation" | "voice_to_ai")
    # ------------------------------------------------------------------

    @Property(str, notify=active_mode_changed)
    def active_mode(self) -> str:
        return self._active_mode

    def _set_active_mode(self, value: str) -> None:
        if self._active_mode != value:
            self._active_mode = value
            self.active_mode_changed.emit(value)

    @Slot(str)
    def save_mode(self, mode: str) -> None:
        """Persist the active mode and emit settings_changed."""
        self._settings = self._updated_settings(active_mode=mode)
        self._settings_store.save(self._settings)
        self._set_active_mode(mode)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # hotkey
    # ------------------------------------------------------------------

    @Property(str, notify=hotkey_changed)
    def hotkey(self) -> str:
        return self._hotkey

    def _set_hotkey(self, value: str) -> None:
        if self._hotkey != value:
            self._hotkey = value
            self.hotkey_changed.emit(value)

    @Slot(str)
    def save_hotkey(self, hotkey: str) -> None:
        """Persist the hotkey binding and emit settings_changed."""
        self._settings = self._updated_settings(hotkey=hotkey)
        self._settings_store.save(self._settings)
        self._set_hotkey(hotkey)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # hotkey_ai  (voice-to-AI hotkey)
    # ------------------------------------------------------------------

    @Property(str, notify=hotkey_ai_changed)
    def hotkey_ai(self) -> str:
        return self._hotkey_ai

    def _set_hotkey_ai(self, value: str) -> None:
        if self._hotkey_ai != value:
            self._hotkey_ai = value
            self.hotkey_ai_changed.emit(value)

    @Slot(str)
    def save_hotkey_ai(self, hotkey: str) -> None:
        """Persist the AI hotkey binding."""
        self._settings = self._updated_settings(hotkey_ai=hotkey)
        self._settings_store.save(self._settings)
        self._set_hotkey_ai(hotkey)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # hotkey_grain  (Grain Assist — stored but feature is coming soon)
    # ------------------------------------------------------------------

    @Property(str, notify=hotkey_grain_changed)
    def hotkey_grain(self) -> str:
        return self._hotkey_grain

    def _set_hotkey_grain(self, value: str) -> None:
        if self._hotkey_grain != value:
            self._hotkey_grain = value
            self.hotkey_grain_changed.emit(value)

    @Slot(str)
    def save_hotkey_grain(self, hotkey: str) -> None:
        """Persist the Grain Assist hotkey binding."""
        self._settings = self._updated_settings(hotkey_grain=hotkey)
        self._settings_store.save(self._settings)
        self._set_hotkey_grain(hotkey)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # hotkey_batch  (non-real-time / record-then-transcribe session)
    # ------------------------------------------------------------------

    @Property(str, notify=hotkey_batch_changed)
    def hotkey_batch(self) -> str:
        return self._hotkey_batch

    def _set_hotkey_batch(self, value: str) -> None:
        if self._hotkey_batch != value:
            self._hotkey_batch = value
            self.hotkey_batch_changed.emit(value)

    @Slot(str)
    def save_hotkey_batch(self, hotkey: str) -> None:
        """Persist the batch (non-real-time) dictation hotkey binding."""
        self._settings = self._updated_settings(hotkey_batch=hotkey)
        self._settings_store.save(self._settings)
        self._set_hotkey_batch(hotkey)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # hotkey_prompt_prev / hotkey_prompt_next  (cycle active prompt profile
    # while recording in Voice-to-AI mode)
    # ------------------------------------------------------------------

    @Property(str, notify=hotkey_prompt_prev_changed)
    def hotkey_prompt_prev(self) -> str:
        return self._hotkey_prompt_prev

    def _set_hotkey_prompt_prev(self, value: str) -> None:
        if self._hotkey_prompt_prev != value:
            self._hotkey_prompt_prev = value
            self.hotkey_prompt_prev_changed.emit(value)

    @Slot(str)
    def save_hotkey_prompt_prev(self, hotkey: str) -> None:
        """Persist the 'previous prompt' navigation hotkey binding."""
        self._settings = self._updated_settings(hotkey_prompt_prev=hotkey)
        self._settings_store.save(self._settings)
        self._set_hotkey_prompt_prev(hotkey)
        self.settings_changed.emit()

    @Property(str, notify=hotkey_prompt_next_changed)
    def hotkey_prompt_next(self) -> str:
        return self._hotkey_prompt_next

    def _set_hotkey_prompt_next(self, value: str) -> None:
        if self._hotkey_prompt_next != value:
            self._hotkey_prompt_next = value
            self.hotkey_prompt_next_changed.emit(value)

    @Slot(str)
    def save_hotkey_prompt_next(self, hotkey: str) -> None:
        """Persist the 'next prompt' navigation hotkey binding."""
        self._settings = self._updated_settings(hotkey_prompt_next=hotkey)
        self._settings_store.save(self._settings)
        self._set_hotkey_prompt_next(hotkey)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # microphone_device_id  (-1 = system default)
    # ------------------------------------------------------------------

    @Property(int, notify=microphone_device_id_changed)
    def microphone_device_id(self) -> int:
        return self._microphone_device_id

    def _set_microphone_device_id(self, value: int) -> None:
        if self._microphone_device_id != value:
            self._microphone_device_id = value
            self.microphone_device_id_changed.emit(value)

    @Slot(int)
    def save_microphone(self, device_id: int) -> None:
        """Persist the microphone device selection. Pass -1 for system default."""
        stored_id: int | None = None if device_id == -1 else device_id
        self._settings = self._updated_settings(microphone_device_id=stored_id)
        self._settings_store.save(self._settings)
        self._set_microphone_device_id(device_id)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # available_microphones  (display names for the ComboBox)
    # microphone_combo_index (currently selected index in that list)
    # ------------------------------------------------------------------

    @Property("QStringList", notify=available_microphones_changed)
    def available_microphones(self) -> list[str]:
        return self._available_microphones

    def _set_available_microphones(self, names: list[str], ids: list[int]) -> None:
        self._available_microphones = names
        self._mic_device_ids = ids
        self.available_microphones_changed.emit()

    @Property(int, notify=microphone_combo_index_changed)
    def microphone_combo_index(self) -> int:
        return self._microphone_combo_index

    def _set_microphone_combo_index(self, idx: int) -> None:
        if self._microphone_combo_index != idx:
            self._microphone_combo_index = idx
            self.microphone_combo_index_changed.emit(idx)

    @Slot(int)
    def save_microphone_by_index(self, idx: int) -> None:
        """Save the microphone selection by its ComboBox index."""
        if 0 <= idx < len(self._mic_device_ids):
            self._set_microphone_combo_index(idx)
            self.save_microphone(self._mic_device_ids[idx])

    # ------------------------------------------------------------------
    # close_to_tray  (True → hide to tray on close; False → quit)
    # ------------------------------------------------------------------

    @Property(bool, notify=close_to_tray_changed)
    def close_to_tray(self) -> bool:
        return self._close_to_tray

    def _set_close_to_tray(self, value: bool) -> None:
        if self._close_to_tray != value:
            self._close_to_tray = value
            self.close_to_tray_changed.emit(value)

    @Slot(bool)
    def save_close_to_tray(self, enabled: bool) -> None:
        """Persist the close-to-tray preference."""
        self._settings = self._updated_settings(close_to_tray=enabled)
        self._settings_store.save(self._settings)
        self._set_close_to_tray(enabled)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # launch_on_boot
    # ------------------------------------------------------------------

    @Property(bool, notify=launch_on_boot_changed)
    def launch_on_boot(self) -> bool:
        return self._launch_on_boot

    def _set_launch_on_boot(self, value: bool) -> None:
        if self._launch_on_boot != value:
            self._launch_on_boot = value
            self.launch_on_boot_changed.emit(value)

    @Slot(bool)
    def save_launch_on_boot(self, enabled: bool) -> None:
        from open_voice_router.startup_registry import apply_launch_on_boot
        apply_launch_on_boot(enabled)
        self._settings = self._updated_settings(launch_on_boot=enabled)
        self._settings_store.save(self._settings)
        self._set_launch_on_boot(enabled)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # start_minimized  (True = stay in tray; False = open console on launch)
    # ------------------------------------------------------------------

    @Property(bool, notify=start_minimized_changed)
    def start_minimized(self) -> bool:
        return self._start_minimized

    def _set_start_minimized(self, value: bool) -> None:
        if self._start_minimized != value:
            self._start_minimized = value
            self.start_minimized_changed.emit(value)

    @Slot(bool)
    def save_start_minimized(self, enabled: bool) -> None:
        self._settings = self._updated_settings(start_minimized=enabled)
        self._settings_store.save(self._settings)
        self._set_start_minimized(enabled)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # play_sound
    # ------------------------------------------------------------------

    @Property(bool, notify=play_sound_changed)
    def play_sound(self) -> bool:
        return self._play_sound

    def _set_play_sound(self, value: bool) -> None:
        if self._play_sound != value:
            self._play_sound = value
            self.play_sound_changed.emit(value)

    @Slot(bool)
    def save_play_sound(self, enabled: bool) -> None:
        self._settings = self._updated_settings(play_sound=enabled)
        self._settings_store.save(self._settings)
        self._set_play_sound(enabled)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # process_audio
    # ------------------------------------------------------------------

    @Property(bool, notify=process_audio_changed)
    def process_audio(self) -> bool:
        return self._process_audio

    def _set_process_audio(self, value: bool) -> None:
        if self._process_audio != value:
            self._process_audio = value
            self.process_audio_changed.emit(value)

    @Slot(bool)
    def save_process_audio(self, enabled: bool) -> None:
        self._settings = self._updated_settings(process_audio=enabled)
        self._settings_store.save(self._settings)
        self._set_process_audio(enabled)
        self.settings_changed.emit()

    def _load_microphone_devices(self) -> None:
        """Query sounddevice for input devices on a background thread."""
        import threading

        current_device_id = self._microphone_device_id

        def _query() -> None:
            try:
                import sounddevice as _sd
                devices = _sd.query_devices()
                names: list[str] = ["System Default"]
                ids: list[int] = [-1]
                for i, d in enumerate(devices):
                    if d["max_input_channels"] > 0:
                        names.append(str(d["name"]))
                        ids.append(i)
            except Exception:
                names = ["System Default"]
                ids = [-1]

            # Find the ComboBox index that matches the saved device ID.
            try:
                combo_idx = ids.index(current_device_id)
            except ValueError:
                combo_idx = 0

            # Both signals fire from the bg thread; Qt queues them to the main thread.
            self._available_microphones = names
            self._mic_device_ids = ids
            self.available_microphones_changed.emit()
            self._microphone_combo_index = combo_idx
            self.microphone_combo_index_changed.emit(combo_idx)

        threading.Thread(target=_query, daemon=True, name="mic-query").start()

    # ------------------------------------------------------------------
    # stt_providers  (list[dict], no API keys)
    # ------------------------------------------------------------------

    @Property("QVariantList", notify=stt_providers_changed)  # type: ignore[arg-type]
    def stt_providers(self) -> list[dict[str, Any]]:
        return self._stt_providers

    def _set_stt_providers(self, value: list[dict[str, Any]]) -> None:
        if self._stt_providers == value:
            return
        self._stt_providers = value
        self.stt_providers_changed.emit()

    # ------------------------------------------------------------------
    # llm_providers  (list[dict], no API keys)
    # ------------------------------------------------------------------

    @Property("QVariantList", notify=llm_providers_changed)  # type: ignore[arg-type]
    def llm_providers(self) -> list[dict[str, Any]]:
        return self._llm_providers

    def _set_llm_providers(self, value: list[dict[str, Any]]) -> None:
        if self._llm_providers == value:
            return
        self._llm_providers = value
        self.llm_providers_changed.emit()

    # ------------------------------------------------------------------
    # error_message  (inline validation / keychain error)
    # ------------------------------------------------------------------

    @Property(str, notify=error_message_changed)
    def error_message(self) -> str:
        return self._error_message

    def _set_error_message(self, value: str) -> None:
        if self._error_message != value:
            self._error_message = value
            self.error_message_changed.emit(value)
            if value:
                self.error_occurred.emit(value)

    # ------------------------------------------------------------------
    # Provider CRUD
    # ------------------------------------------------------------------

    @Slot(str, str, str, str, str, int, str)
    def add_provider(
        self,
        provider_type: str,
        name: str,
        base_url: str,
        model: str,
        api_key: str,
        quota_limit: int,
        system_prompt: str,
    ) -> None:
        """Validate and add a new provider."""
        if not self._validate_provider_fields(base_url, api_key):
            return

        provider_id = str(uuid.uuid4())
        # Classify as "cloud" if URL matches a known preset; otherwise "custom"
        _preset_urls = {p.base_url.rstrip("/") for p in PROVIDER_PRESETS.values()}
        detected_kind = "cloud" if base_url.rstrip("/") in _preset_urls else "custom"
        config = ProviderConfig(
            id=provider_id,
            name=name,
            base_url=base_url,
            model=model,
            quota_limit=None if quota_limit == -1 else quota_limit,
            quota_used_today=0,
            system_prompt=system_prompt or None,
            kind=detected_kind,
        )

        try:
            self._credential_store.set_key(provider_id, api_key)
        except KeychainError as exc:
            self._set_error_message(str(exc))
            return

        if provider_type == "stt":
            self._settings = self._updated_settings(
                stt_providers=list(self._settings.stt_providers) + [config]
            )
        else:
            self._settings = self._updated_settings(
                llm_providers=list(self._settings.llm_providers) + [config]
            )

        self._settings_store.save(self._settings)
        self._refresh_provider_lists()
        self._set_error_message("")
        self.settings_changed.emit()

    @Slot(str, str, str, str, str, int, str)
    def update_provider(
        self,
        provider_id: str,
        name: str,
        base_url: str,
        model: str,
        api_key: str,
        quota_limit: int,
        system_prompt: str,
    ) -> None:
        """Validate and update an existing provider."""
        if not validate_provider_url(base_url):
            self._set_error_message(
                "Base URL must be a well-formed HTTPS URL (e.g. https://api.example.com)."
            )
            return

        if api_key:
            try:
                self._credential_store.set_key(provider_id, api_key)
            except KeychainError as exc:
                self._set_error_message(str(exc))
                return

        def _update(providers: list[ProviderConfig]) -> list[ProviderConfig]:
            result = []
            for p in providers:
                if p.id == provider_id:
                    # Preserve kind + enabled (and quota usage): an edit changes
                    # only the user-facing fields, never the routing state. A
                    # plain ProviderConfig(...) would silently reset kind→"cloud"
                    # and enabled→True, dropping a custom endpoint out of its
                    # category and re-enabling a provider the user had turned off.
                    result.append(
                        dataclasses.replace(
                            p,
                            name=name,
                            base_url=base_url,
                            model=model,
                            quota_limit=None if quota_limit == -1 else quota_limit,
                            system_prompt=system_prompt or None,
                        )
                    )
                else:
                    result.append(p)
            return result

        self._settings = self._updated_settings(
            stt_providers=_update(self._settings.stt_providers),
            llm_providers=_update(self._settings.llm_providers),
        )
        self._settings_store.save(self._settings)
        self._refresh_provider_lists()
        self._set_error_message("")
        self.settings_changed.emit()

    @Slot(str)
    def remove_provider(self, provider_id: str) -> None:
        """Remove a provider from settings and delete its stored API key."""
        self._settings = self._updated_settings(
            stt_providers=[
                p for p in self._settings.stt_providers if p.id != provider_id
            ],
            llm_providers=[
                p for p in self._settings.llm_providers if p.id != provider_id
            ],
        )
        self._settings_store.save(self._settings)

        try:
            self._credential_store.delete_key(provider_id)
        except KeychainError as exc:
            self._set_error_message(str(exc))

        self._refresh_provider_lists()
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # Credential retrieval
    # ------------------------------------------------------------------

    @Slot(str, result=str)
    def get_provider_api_key(self, provider_id: str) -> str:
        """Retrieve the stored API key for a provider. Returns "" if not found."""
        try:
            key = self._credential_store.get_key(provider_id)
            return key if key is not None else ""
        except KeychainError as exc:
            self._set_error_message(str(exc))
            return ""

    # ------------------------------------------------------------------
    # Preset helpers
    # ------------------------------------------------------------------

    @Slot(result="QVariantList")
    def get_presets(self) -> list[dict[str, Any]]:
        """Return built-in provider preset dicts for the add-provider UI."""
        global _PRESETS_CACHE
        if not _PRESETS_CACHE:
            _PRESETS_CACHE = _build_presets_cache()
        return _PRESETS_CACHE

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _validate_provider_fields(self, base_url: str, api_key: str) -> bool:
        if not validate_provider_url(base_url):
            self._set_error_message(
                "Base URL must be a well-formed HTTPS URL (e.g. https://api.example.com)."
            )
            return False
        if not api_key.strip():
            self._set_error_message("API key must not be empty.")
            return False
        return True

    def _refresh_provider_lists(self) -> None:
        self._set_stt_providers(
            [_provider_to_dict(p) for p in self._settings.stt_providers]
        )
        self._set_llm_providers(
            [_provider_to_dict(p) for p in self._settings.llm_providers]
        )

    # ------------------------------------------------------------------
    # Local STT — properties and slots
    # ------------------------------------------------------------------

    @Property(str, notify=local_stt_status_changed)
    def local_stt_status(self) -> str:
        """One of: not_installed, installing, stopped, starting, running, error."""
        return self._local_stt.status

    @Property(str, notify=local_stt_install_path_changed)
    def local_stt_install_path(self) -> str:
        return self._local_stt.install_path

    @Property(int, notify=local_stt_unload_idle_changed)
    def local_stt_unload_idle_ms(self) -> int:
        """Auto-unload idle policy in ms (-1 Never, 0 Instant, else idle delay)."""
        return self._settings.local_stt_unload_idle_ms

    @Slot(int)
    def save_unload_idle_ms(self, value: int) -> None:
        """Persist the auto-unload idle policy chosen in Settings.

        The value is validated by the store on the next load; the backend
        (AppController) reads it per session, so changing it takes effect
        immediately without restarting the server or the app.
        """
        self._settings = self._updated_settings(local_stt_unload_idle_ms=int(value))
        self._settings_store.save(self._settings)
        self.local_stt_unload_idle_changed.emit(int(value))
        self.settings_changed.emit()

    @Property(bool, notify=local_stt_load_on_startup_changed)
    def local_stt_load_on_startup(self) -> bool:
        """Whether the selected local model is pre-loaded at app launch."""
        return self._settings.local_stt_load_on_startup

    @Slot(bool)
    def save_load_on_startup(self, enabled: bool) -> None:
        """Persist the load-on-startup preference.

        Takes effect at the next app launch (main.py warms the model when this
        is on and the model is installed). Unloading still follows the idle
        policy, so turning this on only changes WHEN the first load happens.
        """
        self._settings = self._updated_settings(
            local_stt_load_on_startup=bool(enabled)
        )
        self._settings_store.save(self._settings)
        self.local_stt_load_on_startup_changed.emit(bool(enabled))
        self.settings_changed.emit()

    @Property("QVariantList", notify=local_stt_models_changed)
    def local_stt_models(self) -> list:
        """The model catalog from the registry, for the model pickers.

        ``installed`` reflects whether the model's weights are already in the
        local cache (a model can be selected without being downloaded yet —
        it downloads on its first load).
        """
        engine_ready = self._local_stt.is_installed()
        # Resolve every model's cached state in ONE filesystem walk rather than
        # one walk per model — this property is re-read on each status change
        # (several per load), so N walks here stalled the Qt main thread.
        cached_ids = self._local_stt.cached_model_ids() if engine_ready else set()
        return [
            {
                "id": m.id,
                "name": m.display_name,
                "engine": m.engine,
                "ramMb": m.ram_estimate_mb,
                "languages": m.languages,
                "description": m.description,
                "wer": m.wer_hint,
                "wordTimestamps": m.supports_word_timestamps,
                "installed": m.id in cached_ids,
            }
            for m in model_registry.all_models()
        ]

    @Property(str, notify=local_stt_model_changed)
    def local_stt_model_id(self) -> str:
        return self._settings.local_stt_model_id

    @Slot(str)
    def save_local_stt_model(self, model_id: str) -> None:
        """Select a different local STT model.

        Persists the choice, points the manager at the new model (stopping a
        running server so the next session loads the right one), installs any
        missing engine packages, and keeps the registered provider entry in
        sync so the pill/router immediately reflect the new model.
        """
        spec = model_registry.get_model(model_id)
        if spec.id == self._settings.local_stt_model_id:
            return
        self._settings = self._updated_settings(local_stt_model_id=spec.id)
        self._settings_store.save(self._settings)
        self._local_stt.set_model(spec.id)
        self._sync_local_provider_entry()
        # Engine packages for the new model may not be in the venv yet; the
        # install is idempotent and a no-op when everything is present.
        if self._local_stt.is_installed():
            self._local_stt.install()
        self.local_stt_model_changed.emit(spec.id)
        self.local_stt_models_changed.emit()
        self.settings_changed.emit()

    @Slot()
    def install_local_stt(self) -> None:
        """Start one-click install of the Groxaxo server + dependencies."""
        self._local_stt.install()

    @Slot()
    def start_local_stt(self) -> None:
        """Start the local STT server subprocess."""
        self._local_stt.start()

    @Slot()
    def stop_local_stt(self) -> None:
        """Stop the local STT server subprocess."""
        self._local_stt.stop()

    @Slot(str)
    def delete_local_stt_model_cache(self, model_id: str) -> None:
        """Delete only the cached weights for *model_id* — venv stays intact.

        The server is stopped first if it was running this model. The provider
        registration is preserved so the user can re-download without
        re-installing the whole venv.
        """
        self._local_stt.delete_model_cache(model_id)

    @Slot()
    def uninstall_local_stt(self) -> None:
        """Stop the server and delete the venv + ALL model data from disk.

        Removes the local provider from the STT pool so it is no longer
        offered to the Router after uninstall.
        """
        self._local_stt.uninstall()  # stop + rmtree + status → not_installed
        self._unregister_local_stt_provider()  # remove from settings + save

    @Slot()
    def open_local_stt_folder(self) -> None:
        """Open the install folder in the OS file manager."""
        import subprocess
        import sys

        p = self._local_stt.install_path
        if sys.platform == "win32":
            subprocess.Popen(["explorer", p])
        elif sys.platform == "darwin":
            subprocess.Popen(["open", p])
        else:
            subprocess.Popen(["xdg-open", p])

    def _on_local_stt_install_finished(self, success: bool, message: str) -> None:
        self.local_stt_install_finished.emit(success, message)
        if success:
            # Register the provider as soon as it is installed so it is
            # selectable even before/without the server running (R1.1, R1.2).
            # NOTE: do NOT call self._local_stt.start() here — the manager's
            # _on_install_finished already calls start() before emitting
            # install_finished. A second start() here spawns a second server
            # process that races for port 5092 and crashes.
            self._register_local_stt_provider()

    def _on_local_stt_server_ready(self) -> None:
        """Register the local provider in the active STT pool.

        Registration is idempotent and primarily driven by installation; this
        handler is a safety net for the case where the provider was not yet
        registered when the server came up.
        """
        self._register_local_stt_provider()

    def _on_local_stt_server_stopped(self) -> None:
        """Server went down (e.g. on-demand Model_Unload).

        The provider stays registered/selectable while the model is unloaded —
        AppController drives load/unload per session, so a stopped server does
        NOT remove the provider from the pool (R1.1, R1.2). Removal happens only
        on explicit uninstall.
        """
        return

    def _register_local_stt_provider(self) -> None:
        """Add the local STT provider if not already present (kept in sync
        with the selected registry model)."""
        pid = LocalSTTManager.PROVIDER_ID
        if any(p.id == pid for p in self._settings.stt_providers):
            self._sync_local_provider_entry()
            return
        spec = self._local_stt.model_spec
        provider = ProviderConfig(
            id=pid,
            name=f"Local ({spec.display_name})",
            base_url=LocalSTTManager.SERVER_URL,
            model=spec.id,
            quota_limit=None,
            quota_used_today=0,
        )
        self._settings = self._updated_settings(
            stt_providers=[provider] + list(self._settings.stt_providers)
        )
        self._settings_store.save(self._settings)
        self._refresh_provider_lists()
        self.settings_changed.emit()

    def _sync_local_provider_entry(self) -> None:
        """Update the registered local provider's name/model after a model
        switch. No-op when absent or already in sync."""
        pid = LocalSTTManager.PROVIDER_ID
        spec = self._local_stt.model_spec
        existing = next(
            (p for p in self._settings.stt_providers if p.id == pid), None
        )
        if existing is None:
            return
        wanted_name = f"Local ({spec.display_name})"
        if existing.model == spec.id and existing.name == wanted_name:
            return
        updated = dataclasses.replace(existing, model=spec.id, name=wanted_name)
        providers = [
            updated if p.id == pid else p for p in self._settings.stt_providers
        ]
        self._settings = self._updated_settings(stt_providers=providers)
        self._settings_store.save(self._settings)
        self._refresh_provider_lists()
        self.settings_changed.emit()

    def _unregister_local_stt_provider(self) -> None:
        """Remove Local Parakeet from the STT pool when the server stops."""
        pid = LocalSTTManager.PROVIDER_ID
        filtered = [p for p in self._settings.stt_providers if p.id != pid]
        if len(filtered) == len(self._settings.stt_providers):
            return  # wasn't there
        self._settings = self._updated_settings(stt_providers=filtered)
        self._settings_store.save(self._settings)
        self._refresh_provider_lists()
        self.settings_changed.emit()

    @property
    def local_stt_manager(self) -> LocalSTTManager:
        """Expose the manager so main.py can call stop() on app quit."""
        return self._local_stt

    # ------------------------------------------------------------------
    # Prompts — named reusable system prompts
    # ------------------------------------------------------------------

    @staticmethod
    def _prompt_to_dict(p: PromptConfig) -> dict[str, Any]:
        return {"id": p.id, "name": p.name, "text": p.text, "is_active": p.is_active}

    @Property("QVariantList", notify=prompts_changed)  # type: ignore[arg-type]
    def prompts(self) -> list[dict[str, Any]]:
        return self._prompts

    def _set_prompts(self, value: list[dict[str, Any]]) -> None:
        self._prompts = value
        self.prompts_changed.emit()

    @Slot(str, str)
    def add_prompt(self, name: str, text: str) -> None:
        """Add a new named prompt."""
        new_prompt = PromptConfig(
            id=str(uuid.uuid4()), name=name, text=text, is_active=False
        )
        updated = list(self._settings.prompts) + [new_prompt]
        self._settings = self._updated_settings(prompts=updated)
        self._settings_store.save(self._settings)
        self._set_prompts([self._prompt_to_dict(p) for p in self._settings.prompts])
        self.settings_changed.emit()

    @Slot(str, str, str)
    def update_prompt(self, prompt_id: str, name: str, text: str) -> None:
        """Update an existing prompt's name and text."""
        updated = [
            PromptConfig(id=p.id, name=name, text=text, is_active=p.is_active)
            if p.id == prompt_id
            else p
            for p in self._settings.prompts
        ]
        self._settings = self._updated_settings(prompts=updated)
        self._settings_store.save(self._settings)
        self._set_prompts([self._prompt_to_dict(p) for p in self._settings.prompts])
        self.settings_changed.emit()

    @Slot(str)
    def delete_prompt(self, prompt_id: str) -> None:
        """Delete a prompt by ID."""
        updated = [p for p in self._settings.prompts if p.id != prompt_id]
        self._settings = self._updated_settings(prompts=updated)
        self._settings_store.save(self._settings)
        self._set_prompts([self._prompt_to_dict(p) for p in self._settings.prompts])
        self.settings_changed.emit()

    @Slot(str)
    def set_active_prompt(self, prompt_id: str) -> None:
        """Mark one prompt as active (used as system prompt for Voice to AI)."""
        updated = [
            PromptConfig(
                id=p.id, name=p.name, text=p.text, is_active=(p.id == prompt_id)
            )
            for p in self._settings.prompts
        ]
        # Also update global_system_prompt to the selected prompt's text
        active_text = next(
            (p.text for p in self._settings.prompts if p.id == prompt_id),
            self._settings.global_system_prompt,
        )
        self._settings = self._updated_settings(
            prompts=updated, global_system_prompt=active_text
        )
        self._settings_store.save(self._settings)
        self._set_prompts([self._prompt_to_dict(p) for p in self._settings.prompts])
        self._set_global_system_prompt(active_text)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # word_dictionary  (vocabulary correction list)
    # ------------------------------------------------------------------

    @Property("QStringList", notify=word_dictionary_changed)
    def word_dictionary(self) -> list[str]:
        return self._word_dictionary

    def _set_word_dictionary(self, words: list[str]) -> None:
        if self._word_dictionary != words:
            self._word_dictionary = words
            self.word_dictionary_changed.emit()

    @Slot(str)
    def add_word(self, word: str) -> None:
        """Add a word to the vocabulary dictionary."""
        word = word.strip()
        if not word or word in self._settings.word_dictionary:
            return
        updated = list(self._settings.word_dictionary) + [word]
        self._settings = self._updated_settings(word_dictionary=updated)
        self._settings_store.save(self._settings)
        self._set_word_dictionary(updated)
        self.settings_changed.emit()

    @Slot(str)
    def remove_word(self, word: str) -> None:
        """Remove a word from the vocabulary dictionary."""
        updated = [w for w in self._settings.word_dictionary if w != word]
        if len(updated) == len(self._settings.word_dictionary):
            return
        self._settings = self._updated_settings(word_dictionary=updated)
        self._settings_store.save(self._settings)
        self._set_word_dictionary(updated)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # stt_smart_rotation + stt_local_enabled — provider routing config
    # ------------------------------------------------------------------

    @Property(bool, notify=stt_smart_rotation_changed)
    def stt_smart_rotation(self) -> bool:
        return self._stt_smart_rotation

    def _set_stt_smart_rotation(self, value: bool) -> None:
        if self._stt_smart_rotation != value:
            self._stt_smart_rotation = value
            self.stt_smart_rotation_changed.emit(value)

    # ------------------------------------------------------------------
    # rolling_window_s — real-time chunk length (seconds), local model
    # ------------------------------------------------------------------

    @Property(int, notify=rolling_window_s_changed)
    def rolling_window_s(self) -> int:
        """Rolling-window duration in seconds for the real-time streaming path."""
        return self._settings.rolling_window_s

    @Slot(int)
    def save_rolling_window_s(self, value: int) -> None:
        """Persist the rolling-window duration chosen in Settings.

        The value is clamped to [15, 60] by the store on the next load; the
        backend (AppController → ChunkedAudioService) reads it per session, so a
        change takes effect on the next recording without a restart.
        """
        self._settings = self._updated_settings(rolling_window_s=int(value))
        self._settings_store.save(self._settings)
        self.rolling_window_s_changed.emit(int(value))
        self.settings_changed.emit()

    @Property(bool, notify=stt_local_enabled_changed)
    def stt_local_enabled(self) -> bool:
        return self._stt_local_enabled

    def _set_stt_local_enabled(self, value: bool) -> None:
        if self._stt_local_enabled != value:
            self._stt_local_enabled = value
            self.stt_local_enabled_changed.emit(value)

    def _local_provider_enabled(self) -> bool:
        """Return the enabled state of the local Parakeet provider."""
        pid = LocalSTTManager.PROVIDER_ID
        for p in self._settings.stt_providers:
            if p.id == pid:
                return p.enabled
        return True

    def _with_provider_enabled(
        self, providers: list[ProviderConfig], provider_id: str, enabled: bool
    ) -> list[ProviderConfig]:
        return [
            dataclasses.replace(p, enabled=enabled) if p.id == provider_id else p
            for p in providers
        ]

    @Slot(bool)
    def set_stt_smart_rotation(self, enabled: bool) -> None:
        """Toggle smart rotation.

        When turning OFF, all cloud providers are disabled so the user can
        manually choose exactly one provider (radio behaviour).
        """
        pid = LocalSTTManager.PROVIDER_ID
        if enabled:
            # Local provider is excluded from smart rotation — disable it
            new_providers = [
                dataclasses.replace(p, enabled=False) if p.id == pid else p
                for p in self._settings.stt_providers
            ]
        else:
            # Clear all cloud providers; user picks one manually
            new_providers = [
                dataclasses.replace(p, enabled=False) if p.id != pid else p
                for p in self._settings.stt_providers
            ]
        self._settings = self._updated_settings(
            stt_smart_rotation=enabled,
            stt_providers=new_providers,
        )
        self._settings_store.save(self._settings)
        self._set_stt_smart_rotation(enabled)
        self._set_stt_local_enabled(self._local_provider_enabled())
        self._refresh_provider_lists()
        self.settings_changed.emit()

    @Slot(str, bool)
    def set_stt_provider_enabled(self, provider_id: str, enabled: bool) -> None:
        """Enable or disable a cloud STT provider.

        When smart rotation is OFF and enabling a provider, all other providers
        (including local) are disabled first — only one may be active.
        """
        if enabled and not self._settings.stt_smart_rotation:
            # Radio behaviour: disable everything, then enable just this one
            new_providers = [
                dataclasses.replace(p, enabled=(p.id == provider_id))
                for p in self._settings.stt_providers
            ]
        else:
            new_providers = self._with_provider_enabled(
                self._settings.stt_providers, provider_id, enabled
            )
        self._settings = self._updated_settings(stt_providers=new_providers)
        self._settings_store.save(self._settings)
        self._set_stt_local_enabled(self._local_provider_enabled())
        self._refresh_provider_lists()
        self.settings_changed.emit()

    @Slot(bool)
    def set_stt_local_enabled(self, enabled: bool) -> None:
        """Enable or disable the local Parakeet provider.

        Ignored when smart rotation is ON (local is not used in rotation).
        When enabling with smart rotation OFF, all cloud providers are disabled.
        """
        if self._settings.stt_smart_rotation:
            return
        pid = LocalSTTManager.PROVIDER_ID
        if enabled:
            # Radio: disable all cloud providers, enable local
            new_providers = [
                dataclasses.replace(p, enabled=(p.id == pid))
                for p in self._settings.stt_providers
            ]
        else:
            new_providers = self._with_provider_enabled(
                self._settings.stt_providers, pid, False
            )
        self._settings = self._updated_settings(stt_providers=new_providers)
        self._settings_store.save(self._settings)
        self._set_stt_local_enabled(enabled if enabled else self._local_provider_enabled())
        self._refresh_provider_lists()
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # ui_dark_mode — console panel light/dark appearance (persisted)
    # ------------------------------------------------------------------

    @Property(bool, notify=ui_dark_mode_changed)
    def ui_dark_mode(self) -> bool:
        return self._ui_dark_mode

    def _set_ui_dark_mode(self, value: bool) -> None:
        if self._ui_dark_mode != value:
            self._ui_dark_mode = value
            self.ui_dark_mode_changed.emit(value)

    @Slot(bool)
    def save_ui_dark_mode(self, enabled: bool) -> None:
        """Persist the console light/dark preference so it survives restarts."""
        self._settings = self._updated_settings(ui_dark_mode=bool(enabled))
        self._settings_store.save(self._settings)
        self._set_ui_dark_mode(bool(enabled))

    # ------------------------------------------------------------------
    # llm_smart_rotation — provider routing config for LLM
    # ------------------------------------------------------------------

    @Property(bool, notify=llm_smart_rotation_changed)
    def llm_smart_rotation(self) -> bool:
        return self._llm_smart_rotation

    def _set_llm_smart_rotation(self, value: bool) -> None:
        if self._llm_smart_rotation != value:
            self._llm_smart_rotation = value
            self.llm_smart_rotation_changed.emit(value)

    @Slot(bool)
    def set_llm_smart_rotation(self, enabled: bool) -> None:
        """Toggle LLM smart rotation.

        When turning OFF, all providers are disabled so the user picks one
        manually (radio behaviour).
        """
        if enabled:
            # All providers stay as-is; user can toggle each in/out
            new_providers = list(self._settings.llm_providers)
        else:
            # Clear all; user must pick exactly one
            new_providers = [
                dataclasses.replace(p, enabled=False)
                for p in self._settings.llm_providers
            ]
        self._settings = self._updated_settings(
            llm_smart_rotation=enabled,
            llm_providers=new_providers,
        )
        self._settings_store.save(self._settings)
        self._set_llm_smart_rotation(enabled)
        self._refresh_provider_lists()
        self.settings_changed.emit()

    @Slot(str, bool)
    def set_llm_provider_enabled(self, provider_id: str, enabled: bool) -> None:
        """Enable or disable an LLM provider.

        When smart rotation is OFF and enabling a provider, all other providers
        are disabled first — only one may be active (radio behaviour).
        """
        if enabled and not self._settings.llm_smart_rotation:
            new_providers = [
                dataclasses.replace(p, enabled=(p.id == provider_id))
                for p in self._settings.llm_providers
            ]
        else:
            new_providers = self._with_provider_enabled(
                self._settings.llm_providers, provider_id, enabled
            )
        self._settings = self._updated_settings(llm_providers=new_providers)
        self._settings_store.save(self._settings)
        self._refresh_provider_lists()
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # grain_assist_provider_id — which LLM the Grain Assist agent uses
    # ------------------------------------------------------------------

    @Property(str, notify=grain_assist_provider_changed)
    def grain_assist_provider_id(self) -> str:
        """The provider id Grain Assist uses ("" = auto / first enabled)."""
        return self._settings.grain_assist_provider_id

    @Slot(str)
    def save_grain_assist_provider(self, provider_id: str) -> None:
        """Persist the Grain Assist provider choice (independent of rotation).

        An empty string means "auto" — let the agent fall back to the first
        enabled provider. A non-empty id is honoured even if that provider is
        disabled for processing rotation.
        """
        pid = provider_id or ""
        if pid == self._settings.grain_assist_provider_id:
            return
        self._settings = self._updated_settings(grain_assist_provider_id=pid)
        self._settings_store.save(self._settings)
        self.grain_assist_provider_changed.emit(pid)
        self.settings_changed.emit()

    # ------------------------------------------------------------------
    # llm_error_message — last runtime LLM error, shown in the Processing panel
    # ------------------------------------------------------------------

    @Property(str, notify=llm_error_message_changed)
    def llm_error_message(self) -> str:
        return self._llm_error_message

    @Slot(str)
    def set_llm_error_message(self, message: str) -> None:
        if self._llm_error_message != message:
            self._llm_error_message = message
            self.llm_error_message_changed.emit(message)

    # ------------------------------------------------------------------
    # History  (transcription + processing, UI-side ring buffer, max 10)
    # ------------------------------------------------------------------

    _MAX_HISTORY = 10

    @Property("QVariantList", notify=transcription_history_changed)
    def transcription_history(self) -> list[dict]:
        return self._transcription_history

    @Property("QVariantList", notify=processing_history_changed)
    def processing_history(self) -> list[dict]:
        return self._processing_history

    @Slot(str, str)
    def add_transcription_entry(self, text: str, timestamp: str) -> None:
        """Append a new transcription result to the history ring buffer."""
        self._transcription_history = (
            self._transcription_history[-(self._MAX_HISTORY - 1):] + [{"time": timestamp, "text": text}]
        )
        self._settings = self._updated_settings(transcription_history=self._transcription_history)
        self._settings_store.save(self._settings)
        self.transcription_history_changed.emit()

    @Slot(str, str)
    def add_processing_entry(self, text: str, timestamp: str) -> None:
        """Append a new processing result to the history ring buffer."""
        self._processing_history = (
            self._processing_history[-(self._MAX_HISTORY - 1):] + [{"time": timestamp, "text": text}]
        )
        self._settings = self._updated_settings(processing_history=self._processing_history)
        self._settings_store.save(self._settings)
        self.processing_history_changed.emit()

    @Slot(str)
    def copy_to_clipboard(self, text: str) -> None:
        from PySide6.QtWidgets import QApplication
        if text:
            QApplication.clipboard().setText(text)
