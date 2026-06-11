"""ChunkedAudioService — low-latency continuous recording with an ABSOLUTE
send-cursor so the trailing audio is never lost.

Design (cursor model — the robust fix for "the last few seconds get cut off"):
  - The ENTIRE session's audio is kept as an ordered list of blocks
    (`_all_blocks`) with a running frame count (`_total_frames`).
  - A single absolute cursor, `_sent_frames`, marks how many leading frames
    have already been dispatched in a chunk.
  - A chunk covers frames [cursor - overlap, current_end). After emitting it,
    the cursor advances to current_end.
  - On stop(), the remaining tail is exactly frames[cursor, end). We send it —
    so EVERY captured frame past the cursor is guaranteed to reach the model.
    There is no rolling buffer to mis-juggle, so the tail can never be dropped.

  Chunk boundaries (while recording):
    * ~10s of unsent audio accumulated (target), OR
    * 15s hard cut if no silence found, OR
    * 600ms of silence after >=5s unsent (early finalize).
  A 2s overlap protects boundary words; merge_transcript() dedups it.

Signals:
  amplitude_changed(float)     — 0.0–1.0 RMS, for waveform display
  chunk_ready(bytes)           — finalized WAV chunk ready for STT
  recording_stopped()          — user stopped; final tail already emitted first
"""

from __future__ import annotations

import io
import threading
import wave

import numpy as np
import sounddevice as sd
from sounddevice import PortAudioError

from PySide6.QtCore import QObject, Qt, Signal

from open_voice_router.exceptions import AudioDeviceError
from open_voice_router.services.audio import SAMPLE_RATE, CHANNELS, DTYPE, BLOCKSIZE

# ---------------------------------------------------------------------------
# Chunking configuration (all tunable)
# ---------------------------------------------------------------------------

MAX_CHUNK_SECONDS: float = 15.0          # hard cut if no silence found
OVERLAP_SECONDS: float = 2.0             # overlap to protect boundary words
SILENCE_THRESHOLD_RMS: float = 0.008     # below this = silence (0–1 scale)
SILENCE_MIN_DURATION: float = 0.6        # seconds of silence → early finalize

# Derived constants (frames)
_FRAMES_PER_SECOND = SAMPLE_RATE
_MAX_FRAMES = int(MAX_CHUNK_SECONDS * _FRAMES_PER_SECOND)
_OVERLAP_FRAMES = int(OVERLAP_SECONDS * _FRAMES_PER_SECOND)
_SILENCE_FRAMES = int(SILENCE_MIN_DURATION * _FRAMES_PER_SECOND)
_EARLY_MIN_FRAMES = int(10.0 * _FRAMES_PER_SECOND)  # >=10s unsent before early finalize
_EARLY_GUARD_FRAMES = int(3.0 * _FRAMES_PER_SECOND)  # >=3s unsent absolute floor


def _pcm_to_wav(pcm_frames: list[np.ndarray]) -> bytes:
    """Encode a list of int16 PCM arrays as an in-memory WAV file."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(2)  # int16
        wf.setframerate(SAMPLE_RATE)
        for arr in pcm_frames:
            wf.writeframes(arr.tobytes())
    return buf.getvalue()


class ChunkedAudioService(QObject):
    """Continuous recording with an absolute send-cursor.

    Drop-in for the local STT path. chunk_ready fires whenever a chunk is ready
    while recording continues. On stop, the trailing audio past the cursor is
    flushed as the final chunk before recording_stopped — guaranteed.
    """

    amplitude_changed = Signal(float)   # waveform display
    chunk_ready = Signal(bytes)         # finalized WAV chunk
    recording_stopped = Signal()        # user pressed stop

    _amplitude_ready = Signal(float)
    _chunk_ready_internal = Signal(bytes)
    _stopped_internal = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)

        self._stream: sd.InputStream | None = None
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._lock = threading.Lock()

        # The ENTIRE session's audio, in capture order.
        self._all_blocks: list[np.ndarray] = []
        self._total_frames: int = 0
        # Absolute cursor: number of leading frames already dispatched.
        self._sent_frames: int = 0
        # Frames of contiguous trailing silence (raw RMS based).
        self._silence_frames: int = 0

        self._smoothed_amplitude: float = 0.0

        self._amplitude_ready.connect(self.amplitude_changed, Qt.ConnectionType.QueuedConnection)
        self._chunk_ready_internal.connect(self.chunk_ready, Qt.ConnectionType.QueuedConnection)
        self._stopped_internal.connect(self.recording_stopped, Qt.ConnectionType.QueuedConnection)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def reset(self) -> None:
        """Clear all state so a new session starts completely fresh."""
        with self._lock:
            self._all_blocks = []
            self._total_frames = 0
            self._sent_frames = 0
            self._silence_frames = 0
        self._smoothed_amplitude = 0.0

    def start(self, device_id: int | None) -> None:
        """Begin continuous recording from a clean slate."""
        self._stop_event.clear()
        with self._lock:
            self._all_blocks = []
            self._total_frames = 0
            self._sent_frames = 0
            self._silence_frames = 0
        self._smoothed_amplitude = 0.0

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

        self._thread = threading.Thread(target=self._run_stream, daemon=True, name="chunked-audio")
        self._thread.start()

    def stop(self) -> None:
        """Stop recording and flush the trailing audio past the cursor.

        Because we track an absolute cursor, the tail is exactly the frames in
        [_sent_frames, _total_frames). We include OVERLAP_FRAMES of context
        before the cursor (merge dedups it) so boundary words are protected.
        This makes losing the final words impossible — any captured frame past
        the cursor is in this flush.
        """
        # 1. Stop accepting new audio.
        self._stop_event.set()

        # 2. Close the stream — blocks until the audio callback exits.
        if self._stream is not None:
            try:
                self._stream.stop()
                self._stream.close()
            except Exception:  # noqa: BLE001
                pass
            self._stream = None

        # 3. Join the capture thread — no callback can touch state after this.
        if self._thread is not None:
            self._thread.join(timeout=5.0)
            self._thread = None

        # 4. Flush the trailing audio (everything past the cursor, plus overlap).
        with self._lock:
            start_frame = max(0, self._sent_frames - _OVERLAP_FRAMES)
            tail = self._slice_frames_locked(start_frame, self._total_frames)
            # Cursor now covers the whole session — nothing left unsent.
            self._sent_frames = self._total_frames

        if tail:
            self._chunk_ready_internal.emit(_pcm_to_wav(tail))

        # 5. Signal completion AFTER the final chunk (ordered queued delivery).
        self._stopped_internal.emit()

    # ------------------------------------------------------------------
    # Private — stream runner
    # ------------------------------------------------------------------

    def _run_stream(self) -> None:
        if self._stream is None:
            return
        try:
            with self._stream:
                self._stop_event.wait()
        except PortAudioError:
            pass
        except Exception:  # noqa: BLE001
            pass

    # ------------------------------------------------------------------
    # Private — audio callback (runs on sounddevice audio thread)
    # ------------------------------------------------------------------

    def _audio_callback(
        self,
        indata: np.ndarray,
        frames: int,
        time_info: object,
        status: sd.CallbackFlags,
    ) -> None:
        block = indata.copy()  # copy before sounddevice reuses the buffer

        samples_f = block.astype(np.float32) / 32768.0
        raw_rms = float(np.sqrt(np.mean(samples_f ** 2)))

        # Display amplitude (visual only) — noise-gated + EMA smoothed.
        _NOISE_FLOOR = 0.010
        display_rms = 0.0 if raw_rms < _NOISE_FLOOR else min(
            (raw_rms - _NOISE_FLOOR) / (1.0 - _NOISE_FLOOR), 1.0
        )
        _ALPHA = 0.35
        self._smoothed_amplitude = _ALPHA * display_rms + (1.0 - _ALPHA) * self._smoothed_amplitude
        self._amplitude_ready.emit(self._smoothed_amplitude)

        with self._lock:
            self._all_blocks.append(block)
            self._total_frames += block.shape[0]

            # Silence tracking uses RAW rms so quiet end-of-sentence speech is
            # not mistaken for silence.
            if raw_rms < SILENCE_THRESHOLD_RMS:
                self._silence_frames += block.shape[0]
            else:
                self._silence_frames = 0

            unsent = self._total_frames - self._sent_frames
            should_finalize = (
                # Hard cut: too much unsent audio.
                unsent >= _MAX_FRAMES
                or
                # Early finalize: enough unsent speech + a silence gap.
                (
                    unsent >= _EARLY_MIN_FRAMES
                    and self._silence_frames >= _SILENCE_FRAMES
                    and unsent >= _EARLY_GUARD_FRAMES
                )
            )

            # stop() owns the final flush — never auto-finalize while stopping.
            if should_finalize and not self._stop_event.is_set():
                self._emit_chunk_locked()

    def _emit_chunk_locked(self) -> None:
        """Emit frames [cursor - overlap, total) as a chunk and advance cursor.

        Called with self._lock held. The overlap before the cursor protects
        boundary words; merge_transcript() removes the duplicated region.
        """
        end = self._total_frames
        if end <= self._sent_frames:
            return
        start_frame = max(0, self._sent_frames - _OVERLAP_FRAMES)
        chunk = self._slice_frames_locked(start_frame, end)
        if not chunk:
            return
        self._chunk_ready_internal.emit(_pcm_to_wav(chunk))
        # Advance the cursor to the end of what we just sent.
        self._sent_frames = end
        self._silence_frames = 0

    # ------------------------------------------------------------------
    # Private — frame slicing helpers (call with lock held)
    # ------------------------------------------------------------------

    def _slice_frames_locked(self, start_frame: int, end_frame: int) -> list[np.ndarray]:
        """Return the blocks covering absolute frame range [start_frame, end_frame).

        Blocks are sliced at the boundaries so the range is exact to the frame.
        We keep the WHOLE session in memory (no trimming) so the absolute cursor
        is never re-based — this keeps the "no frame past the cursor is ever
        lost" invariant trivially correct. ~1.9 MB/minute is negligible.
        """
        if end_frame <= start_frame:
            return []
        out: list[np.ndarray] = []
        pos = 0  # absolute frame index of the start of the current block
        for blk in self._all_blocks:
            blk_len = blk.shape[0]
            blk_start = pos
            blk_end = pos + blk_len
            pos = blk_end
            if blk_end <= start_frame:
                continue  # entirely before the range
            if blk_start >= end_frame:
                break     # entirely after the range
            lo = max(0, start_frame - blk_start)
            hi = min(blk_len, end_frame - blk_start)
            if hi > lo:
                out.append(blk[lo:hi] if (lo != 0 or hi != blk_len) else blk)
        return out
