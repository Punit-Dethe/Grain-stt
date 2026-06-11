"""VolumeMeterService — ISOLATED audio level meter for the pill visualization ONLY.

This service is completely separate from the model's audio pipeline:
  - It opens its OWN sounddevice InputStream.
  - It computes a display-scaled level (with gain + curve) purely for the pill.
  - It NEVER touches AudioService or ChunkedAudioService.
  - It NEVER stores audio or feeds anything to STT.
  - If it fails to open (e.g. device busy), it silently does nothing —
    the model recording continues unaffected.

This guarantees the pill animation cannot influence transcription accuracy,
predictability, or any other model behavior in any way.

The level emitted is already fully shaped for display:
  0.0 = silence, 1.0 = loud speech. The pill renders it close to directly.
"""

from __future__ import annotations

import threading

import numpy as np
import sounddevice as sd
from sounddevice import PortAudioError

from PySide6.QtCore import QObject, Qt, Signal

# Capture config — independent of the model's capture settings
_METER_SAMPLE_RATE = 16_000
_METER_CHANNELS = 1
_METER_DTYPE = "int16"
_METER_HZ = 30                      # 30 updates/sec for snappy visuals
_METER_BLOCKSIZE = _METER_SAMPLE_RATE // _METER_HZ  # ~533 frames

# Display shaping constants
_NOISE_GATE = 0.011                 # below this = treated as silence (kills hiss/wind)
_LOUD_REFERENCE = 0.11              # RMS that maps to a "full" display — lower = more reactive
_CURVE_EXP = 0.42                   # <0.5 strongly boosts low-volume reactivity
_SMOOTH_ALPHA = 0.6                 # 60% new sample — fast attack, light smoothing


class VolumeMeterService(QObject):
    """Standalone microphone level meter for the pill. Isolated from the model."""

    level_changed = Signal(float)   # 0.0–1.0, fully display-shaped
    _level_ready = Signal(float)    # internal, crosses thread boundary

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._stream: sd.InputStream | None = None
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._smoothed: float = 0.0

        self._level_ready.connect(self.level_changed, Qt.ConnectionType.QueuedConnection)

    def start(self, device_id: int | None) -> None:
        """Open the dedicated meter stream. Fails silently if the device is busy."""
        self._stop_event.clear()
        self._smoothed = 0.0
        try:
            self._stream = sd.InputStream(
                samplerate=_METER_SAMPLE_RATE,
                channels=_METER_CHANNELS,
                dtype=_METER_DTYPE,
                blocksize=_METER_BLOCKSIZE,
                device=device_id,
                callback=self._callback,
            )
        except PortAudioError:
            # Device busy or unavailable — meter just won't run. Model is unaffected.
            self._stream = None
            return
        except Exception:
            self._stream = None
            return

        self._thread = threading.Thread(target=self._run, daemon=True, name="volume-meter")
        self._thread.start()

    def stop(self) -> None:
        """Stop the meter stream."""
        self._stop_event.set()
        if self._stream is not None:
            try:
                self._stream.stop()
                self._stream.close()
            except Exception:
                pass
            self._stream = None
        if self._thread is not None:
            self._thread.join(timeout=2.0)
            self._thread = None
        # Emit a final 0 so the pill settles to dark
        self._level_ready.emit(0.0)

    def _run(self) -> None:
        if self._stream is None:
            return
        try:
            with self._stream:
                self._stop_event.wait()
        except PortAudioError:
            pass
        except Exception:
            pass

    def _callback(self, indata, frames, time_info, status) -> None:
        # Raw RMS on a private float copy — never alters anything else
        samples = indata.astype(np.float32) / 32768.0
        rms = float(np.sqrt(np.mean(samples ** 2)))

        # Noise gate
        if rms <= _NOISE_GATE:
            level = 0.0
        else:
            # Normalize against a loud-speech reference, then curve for low-end boost
            norm = (rms - _NOISE_GATE) / (_LOUD_REFERENCE - _NOISE_GATE)
            norm = min(max(norm, 0.0), 1.0)
            level = norm ** _CURVE_EXP

        # Light smoothing — fast attack so it feels instant
        self._smoothed = _SMOOTH_ALPHA * level + (1.0 - _SMOOTH_ALPHA) * self._smoothed
        self._level_ready.emit(self._smoothed)
