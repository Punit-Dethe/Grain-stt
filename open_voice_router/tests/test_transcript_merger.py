"""Tests for transcript_merger — the overlap dedup that prevents repeated words.

These lock in the production guarantees for the 10s rolling-window + 2s overlap
streaming architecture: consecutive chunks share boundary words, and the merger
must strip the duplicated region so the final transcript never repeats words.
"""

from __future__ import annotations

from open_voice_router.services.transcript_merger import merge_transcript


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
