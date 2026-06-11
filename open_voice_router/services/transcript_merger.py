"""TranscriptMerger — deduplicates overlapping chunk transcripts.

With 2 seconds of audio overlap at 16 kHz, consecutive chunks share ~3–8 words
at their boundaries. The merger strips that duplicated region before appending.

Strategy (applied in order):
  1. Normalize both tails for comparison (lowercase, strip punctuation).
  2. Find the longest suffix of the existing transcript that matches a prefix
     of the new chunk (case-insensitive, punctuation-stripped comparison).
  3. Strip the matched prefix from the new chunk.
  4. Append only the non-overlapping remainder, preserving the original casing.

If no overlap is found (e.g. the user was silent at the boundary), append normally.
Search window: 30 words — covers ~10s of speech at 3 words/sec with margin.
"""

from __future__ import annotations

import re
import string

_OVERLAP_SEARCH_WORDS = 30  # cover ~10s of potential overlap at 3 words/sec


def _normalize(word: str) -> str:
    """Strip punctuation and lowercase a single word for comparison."""
    return word.strip(string.punctuation).lower()


def merge_transcript(existing: str, new_segment: str) -> str:
    """Append *new_segment* to *existing*, deduplicating overlap words.

    Comparison is case-insensitive and punctuation-stripped so that
    'Hello,' and 'hello' are treated as the same boundary word.
    The original casing from *existing* is preserved.

    Returns the merged transcript string.
    """
    new_segment = new_segment.strip()
    if not new_segment:
        return existing

    existing = existing.strip()
    if not existing:
        return new_segment

    existing_words = existing.split()
    new_words = new_segment.split()

    if not new_words:
        return existing

    # Normalized forms for comparison
    existing_norm = [_normalize(w) for w in existing_words]
    new_norm = [_normalize(w) for w in new_words]

    # Take the last N words of existing as the candidate overlap tail
    tail_norm = existing_norm[-_OVERLAP_SEARCH_WORDS:]
    search_limit = min(len(tail_norm), len(new_norm))

    # Find the longest prefix of new_norm that matches a suffix of tail_norm
    best_overlap = 0
    for length in range(search_limit, 0, -1):
        if tail_norm[-length:] == new_norm[:length]:
            best_overlap = length
            break

    remainder_words = new_words[best_overlap:] if best_overlap > 0 else new_words

    if not remainder_words:
        return existing

    return existing + " " + " ".join(remainder_words)
