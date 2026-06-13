"""AudioService — microphone capture via sounddevice."""

from __future__ import annotations

import io
import threading
import wave
from dataclasses import dataclass

import numpy as np
import sounddevice as sd
from sounddevice import PortAudioError

from PySide6.QtCore import QObject, Qt, Signal

from open_voice_router.exceptions import AudioDeviceError
from open_voice_router.services.audio_conditioner import AudioConditioner, normalize_chunk

# Audio capture constants
SAMPLE_RATE = 16_000   # Hz — compatible with Deepgram and AssemblyAI
CHANNELS = 1           # mono
DTYPE = "int16"
AMPLITUDE_HZ = 20      # target emit rate for amplitude_changed
# Number of frames per callback so that we emit at ~20 Hz
BLOCKSIZE = SAMPLE_RATE // AMPLITUDE_HZ  # 800 frames per block


@dataclass
class AudioDevice:
    id: int
    name: str
    is_default: bool


class AudioService(QObject):
    """Wraps sounddevice for background microphone capture.

    Emits ``amplitude_changed`` at ~20 Hz during recording (0.0–1.0 RMS).
    Emits ``capture_finished`` with WAV-encoded bytes when ``stop()`` is called.

    Thread safety: ``start()`` and ``stop()`` must be called from the main Qt
    thread.  The sounddevice callback runs on a private audio thread; it
    delivers values to the main thread via internal queued signals.
    """

    amplitude_changed = Signal(float)   # 0.0–1.0 RMS
    capture_finished = Signal(bytes)    # WAV-encoded PCM

    # Internal signals used to cross the thread boundary safely.
    # The audio callback emits these; they are connected with QueuedConnection
    # so Qt delivers them on the main thread.
    _amplitude_ready = Signal(float)
    _capture_ready = Signal(bytes)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._stream: sd.InputStream | None = None
        self._chunks: list[bytes] = []
        self._capture_thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._lock = threading.Lock()

        # Smoothed amplitude — exponential moving average across callbacks.
        # Reduces jitter so the display feels fluid rather than jittery.
        self._smoothed_amplitude: float = 0.0

        # Voice processing (Process Audio toggle): 85 Hz high-pass per block
        # + noise-gated AGC on the final capture. Timing-exact.
        self._conditioning_enabled: bool = True
        self._conditioner = AudioConditioner(sample_rate=SAMPLE_RATE)

        # Wire internal signals → public signals with QueuedConnection so that
        # delivery always happens on the thread that owns this QObject (main).
        self._amplitude_ready.connect(
            self.amplitude_changed, Qt.ConnectionType.QueuedConnection
        )
        self._capture_ready.connect(
            self.capture_finished, Qt.ConnectionType.QueuedConnection
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def set_conditioning(self, enabled: bool) -> None:
        """Enable/disable voice processing for the NEXT capture session."""
        self._conditioning_enabled = bool(enabled)

    def start(self, device_id: int | None) -> None:
        """Begin audio capture on *device_id* (``None`` = system default).

        Raises:
            AudioDeviceError: if *device_id* is not available or sounddevice
                raises ``PortAudioError`` when opening the stream.
        """
        if device_id is not None:
            self._validate_device(device_id)

        self._chunks = []
        self._stop_event.clear()
        self._smoothed_amplitude = 0.0
        self._conditioner.reset()

        try:
            self._stream = sd.InputStream(
                samplerate=SAMPLE_RATE,
                channels=CHANNELS,
                dtype=DTYPE,
                blocksize=BLOCKSIZE,
                device=device_id,
                callback=self._audio_callback,
            )
        except PortAudioError as exc:
            raise AudioDeviceError(str(exc)) from exc

        self._capture_thread = threading.Thread(
            target=self._run_stream, daemon=True, name="audio-capture"
        )
        self._capture_thread.start()

    def stop(self) -> None:
        """Stop capture and emit ``capture_finished`` with the WAV bytes."""
        self._stop_event.set()

        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None

        if self._capture_thread is not None:
            self._capture_thread.join(timeout=5.0)
            self._capture_thread = None

        wav_bytes = self._encode_wav()
        # Emit via the internal queued signal so delivery is on the main thread
        self._capture_ready.emit(wav_bytes)

    def enumerate_devices(self) -> list[AudioDevice]:
        """Return all available input audio devices."""
        try:
            default_info = sd.query_devices(kind="input")
            default_name: str = default_info["name"] if default_info else ""
        except Exception:
            default_name = ""

        devices: list[AudioDevice] = []
        for idx, dev in enumerate(sd.query_devices()):
            if dev["max_input_channels"] > 0:
                devices.append(
                    AudioDevice(
                        id=idx,
                        name=dev["name"],
                        is_default=(dev["name"] == default_name),
                    )
                )
        return devices

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _validate_device(self, device_id: int) -> None:
        """Raise ``AudioDeviceError`` if *device_id* is not a valid input device."""
        try:
            all_devices = sd.query_devices()
        except Exception as exc:
            raise AudioDeviceError(f"Cannot query audio devices: {exc}") from exc

        if device_id < 0 or device_id >= len(all_devices):
            raise AudioDeviceError(
                f"Audio device {device_id} does not exist."
            )

        dev = all_devices[device_id]
        if dev["max_input_channels"] < 1:
            raise AudioDeviceError(
                f"Audio device {device_id} ({dev['name']!r}) has no input channels."
            )

    def _run_stream(self) -> None:
        """Open and run the InputStream until the stop event is set."""
        assert self._stream is not None
        try:
            with self._stream:
                self._stop_event.wait()
        except PortAudioError:
            # Stream already closed by stop(); ignore
            pass

    def _audio_callback(
        self,
        indata: np.ndarray,
        frames: int,
        time_info: object,
        status: sd.CallbackFlags,
    ) -> None:
        """Called by sounddevice on the audio thread for each block.

        Stores the raw PCM chunk and emits the RMS amplitude via the internal
        queued signal so it is delivered on the main Qt thread.
        """
        # Voice processing stage 1: high-pass before storing, so the captured
        # WAV is free of sub-vocal rumble and DC offset.
        block = indata
        if self._conditioning_enabled:
            block = self._conditioner.process_block(indata)

        # Store raw bytes
        chunk = block.tobytes()
        with self._lock:
            self._chunks.append(chunk)

        # Compute RMS amplitude, normalised to 0.0–1.0 (int16 full-scale).
        samples = block.astype(np.float32) / 32768.0
        rms = float(np.sqrt(np.mean(samples ** 2)))

        # --- Noise floor gate ---
        # Typical ambient noise RMS is 0.001–0.006; speech starts around 0.015.
        # Below the floor we output 0.0 so silence shows no activity.
        _NOISE_FLOOR = 0.010
        if rms < _NOISE_FLOOR:
            rms = 0.0
        else:
            # Rescale so that the floor maps to 0 and full-scale stays at 1.
            rms = min((rms - _NOISE_FLOOR) / (1.0 - _NOISE_FLOOR), 1.0)

        # --- Exponential moving average (EMA) for smoothing ---
        # Alpha = 0.35: fast enough to track speech syllables (~50–100 ms),
        # smooth enough to eliminate frame-to-frame jitter.
        _ALPHA = 0.35
        self._smoothed_amplitude = _ALPHA * rms + (1.0 - _ALPHA) * self._smoothed_amplitude

        # Deliver to main thread via queued signal
        self._amplitude_ready.emit(self._smoothed_amplitude)

    def _encode_wav(self) -> bytes:
        """Encode all collected PCM chunks as an in-memory WAV file."""
        with self._lock:
            chunks = list(self._chunks)

        # Voice processing stage 2: noise-gated AGC over the whole capture.
        if self._conditioning_enabled and chunks:
            frames = [np.frombuffer(c, dtype=np.int16) for c in chunks]
            chunks = [f.tobytes() for f in normalize_chunk(frames)]

        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(CHANNELS)
            wf.setsampwidth(2)  # int16 = 2 bytes
            wf.setframerate(SAMPLE_RATE)
            for chunk in chunks:
                wf.writeframes(chunk)

        return buf.getvalue()
