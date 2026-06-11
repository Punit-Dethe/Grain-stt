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
from open_voice_router.services.chunked_audio import ChunkedAudioService


def _wav_frame_count(wav_bytes: bytes) -> int:
    with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
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
    chunks: list[bytes] = []
    svc._chunk_ready_internal.connect(chunks.append)
    return chunks


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
