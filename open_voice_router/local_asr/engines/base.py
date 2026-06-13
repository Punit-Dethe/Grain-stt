"""BaseEngine — the strategy interface every local ASR engine implements.

The sidecar HTTP layer (server.py) is engine-agnostic: it decodes the upload
to 16 kHz mono float32 PCM and hands it to ``transcribe()``. Engines normalize
their native output into :class:`EngineResult` — text plus optional word
timings — which the HTTP layer serializes as an OpenAI-compatible response.

DUAL-CONTEXT PACKAGE: imported by the sidecar venv (as ``engines.base``) and
optionally by the app for tests (as ``open_voice_router.local_asr.engines.base``).
Keep imports to stdlib + numpy; engine-specific libraries are imported lazily
inside each wrapper module so only the installed engine's deps are required.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field

SAMPLE_RATE = 16000


@dataclass
class EngineResult:
    """Normalized transcription output for one piece of audio.

    ``words`` entries are ``{"word": str, "start": float, "end": float}`` with
    times in seconds relative to the start of the transcribed audio. Engines
    that cannot produce word timings return an empty list.
    """

    text: str
    words: list[dict] = field(default_factory=list)


class BaseEngine(ABC):
    """One loaded ASR model, ready to transcribe.

    Lifecycle: construct with engine-specific parameters (cheap), then
    ``load()`` once (expensive — reads weights), then ``transcribe()`` per
    request. Engines are used from a single request at a time (the app
    serializes chunk requests), so implementations need not be thread-safe
    across concurrent transcribe calls.
    """

    @abstractmethod
    def load(self) -> None:
        """Load model weights into memory. Called once before any transcribe."""

    @abstractmethod
    def transcribe(self, samples) -> EngineResult:
        """Transcribe ``samples`` (np.float32 mono PCM at 16 kHz)."""


def group_tokens_into_words(
    tokens: list[str],
    timestamps: list[float],
    segment_end: float,
    offset: float = 0.0,
) -> list[dict]:
    """Merge subword tokens ("▁Hel", "lo") into word entries with start/end
    times. A token starting with "▁" (or whitespace) begins a new word; a
    word's end is the next word's start (or the segment end).

    Shared by token-based engines (onnx_asr transducers, sherpa CTC models).
    """
    words: list[dict] = []
    current = ""
    current_start: float | None = None
    for token, ts in zip(tokens, timestamps):
        starts_word = token.startswith("▁") or token.startswith(" ")
        piece = token.replace("▁", " ")
        if starts_word and current.strip():
            words.append({"word": current.strip(), "start": current_start, "end": ts})
            current = ""
            current_start = None
        if current_start is None:
            current_start = ts
        current += piece
    if current.strip():
        words.append({"word": current.strip(), "start": current_start, "end": segment_end})
    for w in words:
        w["start"] = round(float(w["start"]) + offset, 3)
        w["end"] = round(float(w["end"]) + offset, 3)
    return words
