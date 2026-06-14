"""PillViewModel — Qt context property for the Pill UI."""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal, Slot


class PillViewModel(QObject):
    """Exposes recording state and transcript to the Pill QML window.

    Properties (all notify QML via signals):
    - amplitude_level: float (0.0–1.0) — current microphone RMS amplitude
    - transcript_text: str — transcript shown after processing completes
    - state: str — one of "idle", "recording", "processing", "done"
    - is_visible: bool — whether the pill should be shown
    """

    amplitude_level_changed = Signal(float)
    transcript_text_changed = Signal(str)
    state_changed = Signal(str)
    is_visible_changed = Signal(bool)
    active_prompt_name_changed = Signal(str)

    # Emitted when the confirm button is clicked in QML
    confirm_clicked = Signal()

    # Emitted each time the user cycles the active prompt profile mid-recording.
    # QML reacts by showing the prompt "riser" above the pill and restarting its
    # auto-hide timer. The name itself is read from active_prompt_name.
    prompt_nav_pulse = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._amplitude_level: float = 0.0
        self._transcript_text: str = ""
        self._state: str = "idle"
        self._is_visible: bool = False
        self._active_prompt_name: str = ""

    # ------------------------------------------------------------------
    # amplitude_level  (0.0–1.0 RMS, updated at ~20 Hz during recording)
    # ------------------------------------------------------------------

    @Property(float, notify=amplitude_level_changed)
    def amplitude_level(self) -> float:
        return self._amplitude_level

    @amplitude_level.setter
    def amplitude_level(self, value: float) -> None:
        if self._amplitude_level != value:
            self._amplitude_level = value
            self.amplitude_level_changed.emit(value)

    # ------------------------------------------------------------------
    # transcript_text
    # ------------------------------------------------------------------

    @Property(str, notify=transcript_text_changed)
    def transcript_text(self) -> str:
        return self._transcript_text

    @transcript_text.setter
    def transcript_text(self, value: str) -> None:
        if self._transcript_text != value:
            self._transcript_text = value
            self.transcript_text_changed.emit(value)

    # ------------------------------------------------------------------
    # state  ("idle" | "recording" | "processing" | "done")
    # ------------------------------------------------------------------

    @Property(str, notify=state_changed)
    def state(self) -> str:
        return self._state

    @state.setter
    def state(self, value: str) -> None:
        if self._state != value:
            self._state = value
            self.state_changed.emit(value)

    # ------------------------------------------------------------------
    # is_visible
    # ------------------------------------------------------------------

    @Property(bool, notify=is_visible_changed)
    def is_visible(self) -> bool:
        return self._is_visible

    @is_visible.setter
    def is_visible(self, value: bool) -> None:
        if self._is_visible != value:
            self._is_visible = value
            self.is_visible_changed.emit(value)

    # ------------------------------------------------------------------
    # active_prompt_name  (name of the currently selected prompt profile)
    # ------------------------------------------------------------------

    @Property(str, notify=active_prompt_name_changed)
    def active_prompt_name(self) -> str:
        return self._active_prompt_name

    @active_prompt_name.setter
    def active_prompt_name(self, value: str) -> None:
        if self._active_prompt_name != value:
            self._active_prompt_name = value
            self.active_prompt_name_changed.emit(value)

    # ------------------------------------------------------------------
    # Slots
    # ------------------------------------------------------------------

    @Slot()
    def on_confirm_clicked(self) -> None:
        """Called from QML when the tick button is pressed."""
        self.confirm_clicked.emit()

    def pulse_prompt_nav(self, name: str) -> None:
        """Set the active prompt name and tell QML to show the prompt riser.

        Called from the controller when the user cycles the active prompt
        profile during a recording. Updates the displayed name first, then
        emits the pulse so QML reads a fresh name when it reveals the riser.
        """
        self.active_prompt_name = name  # type: ignore[assignment]
        self.prompt_nav_pulse.emit()
