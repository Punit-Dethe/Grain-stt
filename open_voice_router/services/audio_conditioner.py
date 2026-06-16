"""AudioConditioner — acoustic signal conditioning before VAD + STT.

Two timing-exact stages (sample count is NEVER altered, so the absolute
frame-cursor timeline and chunk boundaries stay valid):

1. High-pass biquad at 85 Hz (RBJ cookbook, Q=0.707), applied per capture
   block with filter state carried across blocks. Strips DC offset, HVAC
   rumble, and mic-handling thumps — energy that sits below the human voice
   but above the silence-detection RMS threshold, causing missed chunk
   splits and wasted model attention.

2. Noise-gated, boost-only AGC applied per finalized chunk. Quiet/distant
   speakers cost STT models real accuracy; this measures RMS over the
   ACTIVE (above-gate) frames only — so silence is never amplified — and
   applies one uniform gain to the whole chunk, capped so the loudest
   sample stays below clipping. Uniform gain preserves the speech envelope
   (no pumping artifacts), and loud audio is left untouched.

Deliberately NOT included: AI denoising (DeepFilterNet/DTLN/spectral
gating). Modern ASR encoders are trained on noisy speech; denoiser
artifacts frequently RAISE WER on moderately noisy input, and the ONNX
runtime + model would live in the main app process. If a denoiser is ever
added, it slots in between the two stages here.

Pure numpy — no scipy, no new dependencies.
"""

from __future__ import annotations

import math

import numpy as np

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------

HIGHPASS_HZ: float = 85.0          # below the lowest male fundamental (~90 Hz)
HIGHPASS_Q: float = 0.707          # Butterworth response

AGC_TARGET_RMS: float = 0.06       # ≈ -24 dBFS — comfortable level for STT
AGC_MAX_GAIN: float = 8.0          # never boost more than +18 dB
AGC_PEAK_CEILING: float = 0.95     # post-gain sample peak must stay below this
AGC_GATE_RMS: float = 0.0045       # frames quieter than this don't count as speech
_AGC_FRAME = 320                   # 20 ms @ 16 kHz — activity-measurement window


class AudioConditioner:
    """Stateful streaming high-pass filter for int16 mono capture blocks.

    One instance per recording session (state is reset by :meth:`reset`).
    ``process_block`` runs on the audio callback thread; it is allocation-
    light and operates on the small (~800-frame) capture blocks.
    """

    def __init__(
        self,
        sample_rate: int = 16_000,
        cutoff_hz: float = HIGHPASS_HZ,
        q: float = HIGHPASS_Q,
    ) -> None:
        # RBJ audio-EQ-cookbook high-pass biquad coefficients.
        w0 = 2.0 * math.pi * cutoff_hz / sample_rate
        alpha = math.sin(w0) / (2.0 * q)
        cos_w0 = math.cos(w0)
        a0 = 1.0 + alpha
        self._b0 = ((1.0 + cos_w0) / 2.0) / a0
        self._b1 = (-(1.0 + cos_w0)) / a0
        self._b2 = ((1.0 + cos_w0) / 2.0) / a0
        self._a1 = (-2.0 * cos_w0) / a0
        self._a2 = (1.0 - alpha) / a0
        # Direct-form-II-transposed state (carried across blocks).
        self._z1 = 0.0
        self._z2 = 0.0

    def reset(self) -> None:
        """Clear filter state for a fresh recording session."""
        self._z1 = 0.0
        self._z2 = 0.0

    def process_block(self, block: np.ndarray) -> np.ndarray:
        """High-pass one int16 capture block, preserving shape and dtype.

        ``block`` is shaped (n, 1) as delivered by sounddevice. Returns a new
        array — the input is never mutated.
        """
        # A biquad's feedback (each output depends on prior outputs) can't be
        # vectorised, so this stays a per-sample loop. But iterating a Python
        # list is ~5-10x faster than indexing the ndarray element-by-element
        # (which boxes a numpy scalar per access) — and this runs on the audio
        # callback thread, so the saved time is glitch headroom. The math is
        # bit-identical: .tolist() widens float32->float exactly like float(x[i]),
        # and only the output array is rounded back to float32 (the feedback
        # path uses the full-precision yi in both forms).
        x = (block.astype(np.float32).reshape(-1) / 32768.0).tolist()
        b0, b1, b2, a1, a2 = self._b0, self._b1, self._b2, self._a1, self._a2
        z1, z2 = self._z1, self._z2
        y: list[float] = []
        append = y.append
        for xi in x:
            yi = b0 * xi + z1
            z1 = b1 * xi - a1 * yi + z2
            z2 = b2 * xi - a2 * yi
            append(yi)
        self._z1, self._z2 = z1, z2
        out = np.clip(
            np.asarray(y, dtype=np.float32) * 32768.0, -32768.0, 32767.0
        ).astype(np.int16)
        return out.reshape(block.shape)


def normalize_chunk(frames: list[np.ndarray]) -> list[np.ndarray]:
    """Noise-gated, boost-only AGC over one finalized chunk.

    Measures RMS over 20 ms windows that exceed the activity gate (i.e. the
    speech, not the silence). If that speech level is below the target, the
    WHOLE chunk is scaled up by one uniform gain — capped at +18 dB and at
    whatever keeps the loudest sample under the clipping ceiling. Silence
    inside the chunk scales too, but from near-zero it stays near-zero, so
    the chunk-split silence detection downstream of the model is unaffected.

    Returns new arrays; never mutates the input (the caller's frames may be
    views into the session's master buffer).
    """
    if not frames:
        return frames

    samples = np.concatenate([f.reshape(-1) for f in frames]).astype(np.float32) / 32768.0
    if samples.size == 0:
        return frames

    # Active-frame RMS: ignore windows that are essentially silence.
    n_windows = samples.size // _AGC_FRAME
    if n_windows == 0:
        active_rms = float(np.sqrt(np.mean(samples**2)))
    else:
        windows = samples[: n_windows * _AGC_FRAME].reshape(n_windows, _AGC_FRAME)
        rms_per_window = np.sqrt(np.mean(windows**2, axis=1))
        active = rms_per_window[rms_per_window > AGC_GATE_RMS]
        if active.size == 0:
            return frames  # pure silence — nothing to normalize
        active_rms = float(np.sqrt(np.mean(active**2)))

    if active_rms <= 0.0 or active_rms >= AGC_TARGET_RMS:
        return frames  # already loud enough — boost-only by design

    gain = min(AGC_TARGET_RMS / active_rms, AGC_MAX_GAIN)
    peak = float(np.max(np.abs(samples)))
    if peak > 0.0:
        gain = min(gain, AGC_PEAK_CEILING / peak)
    if gain <= 1.0:
        return frames

    return [
        np.clip(f.astype(np.float32) * gain, -32768.0, 32767.0).astype(np.int16)
        for f in frames
    ]
