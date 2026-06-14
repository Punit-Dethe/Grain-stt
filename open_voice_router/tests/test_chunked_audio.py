"""Tests for ChunkedAudioService's absolute-cursor model.

These prove the core guarantee: every captured frame past the send-cursor is
included in a chunk, so the trailing audio (the user's last words) can never be
dropped — regardless of where auto-finalize boundaries fell.

We drive the service synthetically: feed known blocks, capture emitted chunks by
connecting to the internal signals, and assert exact frame coverage. No real
audio device or Qt event loop is needed because we call the internal helpers
directly under the same lock contract the callback uses.
"""

from __future__ import annotations

import io
import wave

import numpy as np
import pytest

from open_voice_router.services import chunked_audio as ca
from open_voice_router.services.chunked_audio import AudioChunk, ChunkedAudioService


def _wav_frame_count(chunk: AudioChunk) -> int:
    with wave.open(io.BytesIO(chunk.wav_bytes), "rb") as wf:
        return wf.getnframes()


def _block(n: int, value: int = 1000) -> np.ndarray:
    """A mono int16 block of n frames, shaped (n, 1) like sounddevice delivers."""
    return np.full((n, 1), value, dtype=np.int16)


@pytest.fixture
def svc():
    s = ChunkedAudioService()
    s.reset()
    return s


def _collect_chunks(svc):
    """Attach a collector to the internal chunk signal. Returns the list."""
    chunks: list[AudioChunk] = []
    svc._chunk_ready_internal.connect(chunks.append)
    return chunks


def test_set_rolling_window_sets_max_frames(svc):
    svc.set_rolling_window(30)
    assert svc._max_frames == 30 * ca._FRAMES_PER_SECOND


@pytest.mark.parametrize(
    "given,expected_s",
    [(5, 15), (14, 15), (15, 15), (60, 60), (120, 60), (10.0, 15)],
)
def test_set_rolling_window_clamps(svc, given, expected_s):
    svc.set_rolling_window(given)
    assert svc._max_frames == expected_s * ca._FRAMES_PER_SECOND


def test_slice_is_frame_exact(svc):
    with svc._lock:
        svc._all_blocks = [_block(100), _block(100), _block(100)]
        svc._total_frames = 300
        frames = svc._slice_frames_locked(50, 250)
    total = sum(b.shape[0] for b in frames)
    assert total == 200  # exactly [50, 250)


def test_slice_within_single_block(svc):
    with svc._lock:
        svc._all_blocks = [_block(100)]
        svc._total_frames = 100
        frames = svc._slice_frames_locked(20, 60)
    assert sum(b.shape[0] for b in frames) == 40


def test_emit_chunk_advances_cursor(svc):
    chunks = _collect_chunks(svc)
    with svc._lock:
        svc._all_blocks = [_block(ca._FRAMES_PER_SECOND)] * 12  # 12s of audio
        svc._total_frames = 12 * ca._FRAMES_PER_SECOND
        svc._emit_chunk_locked()
    assert len(chunks) == 1
    # Cursor advanced to the end of all captured audio.
    assert svc._sent_frames == 12 * ca._FRAMES_PER_SECOND


def test_stop_flushes_trailing_audio(svc):
    """The key guarantee: audio captured after the last chunk is flushed on stop."""
    chunks = _collect_chunks(svc)
    fps = ca._FRAMES_PER_SECOND

    # Simulate: 12s already sent (cursor at 12s), then 3 more seconds captured
    # that were never chunked (the user's final words before pressing stop).
    with svc._lock:
        svc._all_blocks = [_block(fps) for _ in range(15)]  # 15s total
        svc._total_frames = 15 * fps
        svc._sent_frames = 12 * fps  # 3s unsent tail

    # stop() has no stream/thread here; it should still flush the tail.
    svc.stop()

    assert len(chunks) == 1
    tail_frames = _wav_frame_count(chunks[0])
    # Tail = unsent 3s + 2s overlap context = 5s.
    expected = (3 + 2) * fps
    assert tail_frames == expected
    # Everything is now marked sent.
    assert svc._sent_frames == svc._total_frames


def test_stop_with_no_unsent_audio_still_safe(svc):
    """If the cursor already covers everything, stop sends only overlap context."""
    chunks = _collect_chunks(svc)
    fps = ca._FRAMES_PER_SECOND
    with svc._lock:
        svc._all_blocks = [_block(fps) for _ in range(10)]
        svc._total_frames = 10 * fps
        svc._sent_frames = 10 * fps  # nothing unsent
    svc.stop()
    # It emits the trailing overlap window (already-transcribed; merge dedups it).
    assert len(chunks) == 1
    assert _wav_frame_count(chunks[0]) == ca._OVERLAP_FRAMES


def test_no_frames_dropped_across_chunk_and_stop(svc):
    """End-to-end coverage: union of all emitted chunk ranges covers every frame
    from 0 to total, so no captured audio is ever missing."""
    chunks = _collect_chunks(svc)
    fps = ca._FRAMES_PER_SECOND

    with svc._lock:
        # 25s of audio in 1s blocks.
        svc._all_blocks = [_block(fps) for _ in range(25)]
        svc._total_frames = 25 * fps
        # Emit one chunk at the 12s mark (simulating a mid-session finalize).
        # Temporarily pretend only 12s exists so the chunk ends at 12s.
        saved_blocks = svc._all_blocks
        saved_total = svc._total_frames
        svc._all_blocks = saved_blocks[:12]
        svc._total_frames = 12 * fps
        svc._emit_chunk_locked()
        # Restore the full 25s (the remaining 13s are the unsent tail).
        svc._all_blocks = saved_blocks
        svc._total_frames = saved_total

    svc.stop()

    # Two emissions: the 12s chunk, then the tail flush.
    assert len(chunks) == 2
    # The tail must cover from cursor(12s) - overlap(2s) to 25s = 15s.
    tail_frames = _wav_frame_count(chunks[1])
    assert tail_frames == (25 - 12 + 2) * fps


def _reference_slice(blocks, start_frame, end_frame):
    """Full-scan reference slicer (the pre-optimization algorithm) — used to
    prove the cached-cursor version returns byte-identical frames."""
    if end_frame <= start_frame:
        return []
    out = []
    pos = 0
    for blk in blocks:
        blk_len = blk.shape[0]
        blk_start, blk_end = pos, pos + blk_len
        pos = blk_end
        if blk_end <= start_frame:
            continue
        if blk_start >= end_frame:
            break
        lo = max(0, start_frame - blk_start)
        hi = min(blk_len, end_frame - blk_start)
        if hi > lo:
            out.append(blk[lo:hi] if (lo != 0 or hi != blk_len) else blk)
    return out


def test_cursor_slice_matches_full_scan_over_long_session(svc):
    """The cached-cursor slicer must return exactly the same frames as a full
    scan for a long sequence of forward-moving ranges (the production pattern)."""
    import numpy as np

    # 1000 blocks of varying lengths — a long session.
    rng = np.random.default_rng(7)
    blocks = [_block(int(n), value=int(v))
              for n, v in zip(rng.integers(700, 900, size=1000),
                              rng.integers(-5000, 5000, size=1000))]
    with svc._lock:
        svc._all_blocks = blocks
        svc._total_frames = sum(b.shape[0] for b in blocks)

    # Walk forward in overlapping windows, exactly like emit/stop do.
    cursor = 0
    step = 800 * 20  # ~20s of unsent audio per chunk
    overlap = ca._OVERLAP_FRAMES
    while cursor < svc._total_frames:
        end = min(cursor + step, svc._total_frames)
        start = max(0, cursor - overlap)
        with svc._lock:
            got = svc._slice_frames_locked(start, end)
        ref = _reference_slice(blocks, start, end)
        got_cat = np.concatenate(got) if got else np.empty((0, 1), np.int16)
        ref_cat = np.concatenate(ref) if ref else np.empty((0, 1), np.int16)
        assert np.array_equal(got_cat, ref_cat), f"mismatch at [{start},{end})"
        cursor = end


def test_chunks_carry_exact_timeline_metadata(svc):
    """Each AudioChunk's time tags must match its true frame range, and the
    fresh regions must tile the session with no gap and no overlap — the
    invariant the time-based transcript assembler depends on."""
    chunks = _collect_chunks(svc)
    fps = ca._FRAMES_PER_SECOND

    with svc._lock:
        saved = [_block(fps) for _ in range(25)]
        svc._all_blocks = saved[:12]
        svc._total_frames = 12 * fps
        svc._emit_chunk_locked()
        svc._all_blocks = saved
        svc._total_frames = 25 * fps
    svc.stop()

    first, tail = chunks
    # First chunk: no overlap context exists yet — starts at 0.
    assert first.start_sec == 0.0
    assert first.fresh_start_sec == 0.0
    assert first.end_sec == 12.0
    # Tail: 2s overlap context before the cursor, fresh audio from 12s to 25s.
    assert tail.start_sec == 12.0 - ca.OVERLAP_SECONDS
    assert tail.fresh_start_sec == 12.0
    assert tail.end_sec == 25.0
    # Fresh regions tile the whole session exactly.
    assert first.fresh_start_sec == 0.0 and tail.fresh_start_sec == first.end_sec
    # WAV payload length matches the tagged range.
    assert _wav_frame_count(first) == int((first.end_sec - first.start_sec) * fps)
    assert _wav_frame_count(tail) == int((tail.end_sec - tail.start_sec) * fps)
