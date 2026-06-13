"""Transcript merging — deduplicates overlapping chunk transcripts.

Two strategies, in order of preference:

1. :class:`TimelineAssembler` (time-based, deterministic). Each chunk carries
   its absolute position on the session timeline (from OUR frame counter) and
   word-level timings from the model. A word is accepted iff its absolute
   midpoint falls in the chunk's fresh (not-previously-covered) region. Dedup
   becomes arithmetic — a repeated phrase can never be over-stripped and a
   differently-transcribed overlap can never eat new words.

2. :func:`merge_transcript` (text-based, fallback). For models that provide
   no word timestamps: longest suffix/prefix word match over a 30-word window.

With 2 seconds of audio overlap at 16 kHz, consecutive chunks share ~3–8 words
at their boundaries.
"""

from __future__ import annotations

import re
import string

from open_voice_router.models import WordTiming

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


# ---------------------------------------------------------------------------
# Time-based assembly (preferred when word timings are available)
# ---------------------------------------------------------------------------

# Model word timestamps jitter by roughly one acoustic frame (~80 ms) plus
# decoding slack; ±250 ms tolerance absorbs that without re-admitting whole
# words from the 2 s overlap region.
_BOUNDARY_TOLERANCE_SEC = 0.25
# How many committed tail words to compare for seam dedup of boundary words
# that the tolerance window let through twice.
_SEAM_SEARCH_WORDS = 3


class TimelineAssembler:
    """Builds the session transcript from time-tagged chunk results.

    The session timeline is ground truth from the audio layer's frame cursor:
    chunk N's fresh region is [fresh_start, end) and is covered by NO other
    chunk, while [start, fresh_start) is overlap context that chunk N-1
    already transcribed. Words are accepted iff their absolute midpoint lies
    in the fresh region (with a small tolerance for model timing jitter), so
    overlap dedup never depends on the model transcribing the same audio the
    same way twice.

    Falls back to :func:`merge_transcript` for chunks without word timings,
    so mixed-capability sessions still assemble correctly.
    """

    def __init__(self) -> None:
        self._text: str = ""

    @property
    def text(self) -> str:
        """The assembled transcript so far."""
        return self._text

    def reset(self) -> None:
        self._text = ""

    def add_chunk(
        self,
        *,
        chunk_start_sec: float,
        fresh_start_sec: float,
        text: str,
        words: tuple[WordTiming, ...] | None = None,
    ) -> str:
        """Merge one chunk's transcription and return the updated transcript.

        Args:
            chunk_start_sec: Absolute session time where the chunk AUDIO begins
                (word timings in *words* are relative to this point).
            fresh_start_sec: Absolute session time where the chunk's fresh
                (not-previously-covered) audio begins.
            text:  The chunk's plain transcript (used for the fallback path).
            words: Word timings relative to the chunk start, when available.
        """
        if not words:
            if text.strip():
                self._text = merge_transcript(self._text, text)
            return self._text

        cutoff = fresh_start_sec - _BOUNDARY_TOLERANCE_SEC
        accepted = [
            w for w in words if (chunk_start_sec + w.midpoint) >= cutoff and w.word
        ]
        # Seam cleanup: the tolerance window can re-admit a word that the
        # previous chunk already committed right at the boundary. Drop leading
        # accepted words that exactly repeat the committed tail AND sit inside
        # the tolerance window — never anything beyond it.
        existing_words = self._text.split()
        for n in range(min(_SEAM_SEARCH_WORDS, len(accepted), len(existing_words)), 0, -1):
            head = accepted[:n]
            if any(
                (chunk_start_sec + w.midpoint) >= fresh_start_sec + _BOUNDARY_TOLERANCE_SEC
                for w in head
            ):
                continue  # extends past the jitter window — real new speech
            if [_normalize(w.word) for w in head] == [
                _normalize(w) for w in existing_words[-n:]
            ]:
                accepted = accepted[n:]
                break

        if accepted:
            addition = " ".join(w.word for w in accepted)
            self._text = f"{self._text} {addition}".strip() if self._text else addition
        return self._text
