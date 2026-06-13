"""Tests for the voice-processing layer (high-pass + noise-gated AGC).

Lock in the production guarantees: sample counts are never altered (the
absolute frame-cursor timeline depends on this), silence is never amplified,
quiet speech is boosted without clipping, and loud audio passes through.
"""

from __future__ import annotations

import numpy as np
import pytest

from open_voice_router.services.audio_conditioner import (
    AGC_MAX_GAIN,
    AGC_PEAK_CEILING,
    AGC_TARGET_RMS,
    AudioConditioner,
    normalize_chunk,
)

SR = 16_000


def _tone(freq: float, seconds: float, amplitude: float) -> np.ndarray:
    """Mono int16 sine block shaped (n, 1) like sounddevice delivers."""
    t = np.arange(int(seconds * SR)) / SR
    samples = (amplitude * 32767.0 * np.sin(2 * np.pi * freq * t)).astype(np.int16)
    return samples.reshape(-1, 1)


def _rms(arr: np.ndarray) -> float:
    f = arr.astype(np.float64).reshape(-1) / 32768.0
    return float(np.sqrt(np.mean(f**2)))


# ---------------------------------------------------------------------------
# High-pass filter
# ---------------------------------------------------------------------------


def test_highpass_preserves_shape_and_dtype():
    c = AudioConditioner()
    block = _tone(440, 0.05, 0.3)
    out = c.process_block(block)
    assert out.shape == block.shape
    assert out.dtype == np.int16


def test_highpass_kills_rumble_keeps_voice():
    c = AudioConditioner()
    rumble = _tone(40, 0.5, 0.3)    # sub-vocal HVAC-style rumble
    out_rumble = c.process_block(rumble)
    c.reset()
    voice = _tone(300, 0.5, 0.3)    # well inside the vocal band
    out_voice = c.process_block(voice)

    # 40 Hz attenuated hard (2nd-order HP at 85 Hz ≈ -13 dB at 40 Hz).
    assert _rms(out_rumble) < _rms(rumble) * 0.4
    # 300 Hz passes essentially untouched (<1 dB loss).
    assert _rms(out_voice) > _rms(voice) * 0.85


def test_highpass_removes_dc_offset():
    c = AudioConditioner()
    block = np.full((SR // 2, 1), 5000, dtype=np.int16)  # pure DC
    out = c.process_block(block)
    # After the transient settles, DC is gone.
    tail = out[-1000:]
    assert float(np.abs(tail).mean()) < 100


def test_highpass_state_carries_across_blocks():
    """Filtering block-by-block must equal filtering the whole signal at once
    — no discontinuities at block boundaries."""
    sig = _tone(300, 0.2, 0.3)
    whole = AudioConditioner().process_block(sig)
    c = AudioConditioner()
    parts = [c.process_block(sig[i : i + 800]) for i in range(0, sig.shape[0], 800)]
    blockwise = np.concatenate(parts)
    assert np.array_equal(whole, blockwise)


# ---------------------------------------------------------------------------
# AGC
# ---------------------------------------------------------------------------


def test_agc_boosts_quiet_speech():
    quiet = [_tone(300, 1.0, 0.01)]  # RMS ≈ 0.007 — far below target
    out = normalize_chunk(quiet)
    assert _rms(out[0]) > _rms(quiet[0]) * 2
    assert _rms(out[0]) <= AGC_TARGET_RMS * 1.1


def test_agc_never_amplifies_pure_silence():
    silence = [np.zeros((SR, 1), dtype=np.int16)]
    out = normalize_chunk(silence)
    assert np.array_equal(out[0], silence[0])


def test_agc_leaves_loud_audio_untouched():
    loud = [_tone(300, 1.0, 0.5)]
    out = normalize_chunk(loud)
    assert out is loud  # boost-only: returned as-is


def test_agc_gain_capped_and_no_clipping():
    # Mostly silence with one very quiet word and one moderate transient.
    sig = np.zeros(SR, dtype=np.int16)
    sig[1000:4200] = _tone(300, 0.2, 0.008).reshape(-1)
    sig[8000:8160] = 20000  # a pre-existing pop near full scale
    out = normalize_chunk([sig.reshape(-1, 1)])
    peak = float(np.max(np.abs(out[0].astype(np.float32)))) / 32768.0
    assert peak <= AGC_PEAK_CEILING + 0.01  # never clips
    # Gain stayed within the cap.
    boosted_rms = _rms(out[0][1000:4200])
    original_rms = _rms(sig[1000:4200].reshape(-1, 1))
    assert boosted_rms / original_rms <= AGC_MAX_GAIN + 0.01


def test_agc_preserves_frame_counts():
    frames = [_tone(300, 0.05, 0.01), _tone(300, 0.03, 0.01)]
    out = normalize_chunk(frames)
    assert [f.shape for f in out] == [f.shape for f in frames]


def test_agc_does_not_mutate_input():
    frames = [_tone(300, 0.5, 0.01)]
    before = frames[0].copy()
    normalize_chunk(frames)
    assert np.array_equal(frames[0], before)


def test_agc_empty_input():
    assert normalize_chunk([]) == []
