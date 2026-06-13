"""Tests for transcript_merger — the overlap dedup that prevents repeated words.

These lock in the production guarantees for the 10s rolling-window + 2s overlap
streaming architecture: consecutive chunks share boundary words, and the merger
must strip the duplicated region so the final transcript never repeats words.
"""

from __future__ import annotations

from open_voice_router.models import WordTiming
from open_voice_router.services.transcript_merger import (
    TimelineAssembler,
    merge_transcript,
)


def test_empty_existing_returns_new():
    assert merge_transcript("", "hello world") == "hello world"


def test_empty_new_returns_existing():
    assert merge_transcript("hello world", "") == "hello world"


def test_both_empty():
    assert merge_transcript("", "") == ""


def test_no_overlap_appends_with_space():
    assert merge_transcript("hello world", "how are you") == "hello world how are you"


def test_simple_overlap_deduplicated():
    # "world" is the boundary overlap word — must appear once, not twice.
    result = merge_transcript("hello world", "world how are you")
    assert result == "hello world how are you"


def test_multi_word_overlap_deduplicated():
    existing = "the quick brown fox jumps"
    new = "brown fox jumps over the lazy dog"
    result = merge_transcript(existing, new)
    assert result == "the quick brown fox jumps over the lazy dog"


def test_overlap_is_case_insensitive():
    result = merge_transcript("Hello World", "world how are you")
    # Original casing of existing is preserved; the dup "world" is stripped.
    assert result == "Hello World how are you"


def test_overlap_ignores_punctuation():
    result = merge_transcript("hello world,", "world how are you")
    assert result == "hello world, how are you"


def test_full_duplicate_chunk_adds_nothing():
    # If the new chunk is entirely contained in the tail, nothing is appended.
    result = merge_transcript("hello world", "hello world")
    assert result == "hello world"


def test_whitespace_only_new_segment():
    assert merge_transcript("hello world", "   ") == "hello world"


def test_longest_overlap_is_preferred():
    # Both "fox" and "brown fox" match; the longer overlap must win so we don't
    # leave a partial duplicate.
    existing = "a brown fox"
    new = "brown fox runs"
    assert merge_transcript(existing, new) == "a brown fox runs"


def test_realistic_streaming_sequence():
    # Simulate three overlapping chunks merged in order.
    t = ""
    t = merge_transcript(t, "I went to the store")
    t = merge_transcript(t, "to the store to buy some milk")
    t = merge_transcript(t, "to buy some milk and eggs")
    assert t == "I went to the store to buy some milk and eggs"


# ---------------------------------------------------------------------------
# TimelineAssembler — time-based dedup (preferred path)
# ---------------------------------------------------------------------------


def _words(spec: str, start: float, per_word: float = 0.4) -> tuple[WordTiming, ...]:
    """Build evenly spaced WordTimings from 'a b c', starting at *start* sec
    (chunk-relative)."""
    out = []
    t = start
    for w in spec.split():
        out.append(WordTiming(word=w, start=t, end=t + per_word))
        t += per_word
    return tuple(out)


def test_assembler_first_chunk_accepts_everything():
    a = TimelineAssembler()
    text = a.add_chunk(
        chunk_start_sec=0.0,
        fresh_start_sec=0.0,
        text="hello world how are you",
        words=_words("hello world how are you", 0.1),
    )
    assert text == "hello world how are you"


def test_assembler_drops_overlap_words_by_time():
    """Chunk 2 carries 2s of overlap audio (0-2s chunk-relative = 10-12s abs).
    Words inside the overlap must be dropped regardless of their text."""
    a = TimelineAssembler()
    a.add_chunk(
        chunk_start_sec=0.0,
        fresh_start_sec=0.0,
        text="one two three",
        words=_words("one two three", 10.5),  # abs 10.5-11.7 (end of chunk 1)
    )
    # Chunk 2: audio range [10, 22), fresh from 12. Overlap re-transcribed
    # DIFFERENTLY ("won too tree") — text merge would fail here, time must not.
    text = a.add_chunk(
        chunk_start_sec=10.0,
        fresh_start_sec=12.0,
        text="won too tree four five",
        words=_words("won too tree four five", 0.5),  # abs 10.5..12.5+
    )
    result_words = text.split()
    assert "won" not in result_words
    assert "too" not in result_words
    assert "tree" not in result_words
    assert text == "one two three four five"


def test_assembler_repeated_phrase_is_not_over_stripped():
    """The user really said the same words twice — text merge over-strips,
    time-based accept must keep both occurrences."""
    a = TimelineAssembler()
    a.add_chunk(
        chunk_start_sec=0.0,
        fresh_start_sec=0.0,
        text="yes yes",
        words=_words("yes yes", 9.0),
    )
    # New chunk, fresh region starts at 10s; the SAME words spoken again,
    # clearly inside the fresh region (abs 13s+).
    text = a.add_chunk(
        chunk_start_sec=8.0,
        fresh_start_sec=10.0,
        text="yes yes",
        words=_words("yes yes", 5.0),  # abs 13.0+
    )
    assert text == "yes yes yes yes"


def test_assembler_seam_dedup_drops_boundary_double():
    """A word whose midpoint jitters just inside the tolerance window and that
    exactly repeats the committed tail is dropped — but only at the seam."""
    a = TimelineAssembler()
    a.add_chunk(
        chunk_start_sec=0.0,
        fresh_start_sec=0.0,
        text="we should ship it",
        words=_words("we should ship it", 8.5),  # last word ~10.1s abs
    )
    # Next chunk fresh from 10.0; "it" re-appears at abs ~9.95 (inside ±0.25).
    text = a.add_chunk(
        chunk_start_sec=8.0,
        fresh_start_sec=10.0,
        text="it today",
        words=(
            WordTiming(word="it", start=1.85, end=2.05),   # abs mid 9.95
            WordTiming(word="today", start=2.1, end=2.5),  # abs mid 10.3
        ),
    )
    assert text == "we should ship it today"


def test_assembler_falls_back_to_text_merge_without_words():
    a = TimelineAssembler()
    a.add_chunk(chunk_start_sec=0.0, fresh_start_sec=0.0, text="hello world", words=None)
    text = a.add_chunk(
        chunk_start_sec=8.0, fresh_start_sec=10.0, text="world how are you", words=None
    )
    assert text == "hello world how are you"


def test_assembler_empty_chunk_is_noop():
    a = TimelineAssembler()
    a.add_chunk(
        chunk_start_sec=0.0, fresh_start_sec=0.0, text="hello", words=_words("hello", 0.1)
    )
    text = a.add_chunk(chunk_start_sec=8.0, fresh_start_sec=10.0, text="", words=None)
    assert text == "hello"


def test_assembler_reset_clears_state():
    a = TimelineAssembler()
    a.add_chunk(
        chunk_start_sec=0.0, fresh_start_sec=0.0, text="hello", words=_words("hello", 0.1)
    )
    a.reset()
    assert a.text == ""
