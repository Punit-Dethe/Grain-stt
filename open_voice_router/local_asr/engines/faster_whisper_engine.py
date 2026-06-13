"""faster-whisper engine — the Whisper family via CTranslate2 (no PyTorch).

Chosen over sherpa-onnx for Whisper because sherpa's Whisper export drops the
cross-attention alignment heads, so it cannot produce word timestamps —
faster-whisper can (``word_timestamps=True``), which the app's time-based
overlap dedup depends on.
"""

from __future__ import annotations

import os

try:  # sidecar context
    from engines.base import BaseEngine, EngineResult
except ImportError:  # app/package context (tests)
    from open_voice_router.local_asr.engines.base import BaseEngine, EngineResult


class FasterWhisperEngine(BaseEngine):
    def __init__(
        self,
        model_ref: str,
        compute_type: str | None = "int8",
        cpu_threads: int = 4,
        models_dir: str | None = None,
    ) -> None:
        self._model_ref = model_ref
        self._compute_type = compute_type or "default"
        self._cpu_threads = cpu_threads
        # Keep all model snapshots in the shared models dir (same HF cache the
        # other engines use) so install/cache detection is uniform.
        self._download_root = models_dir or os.environ.get("MODELS_DIR")
        self._model = None

    def load(self) -> None:
        from faster_whisper import WhisperModel

        self._model = WhisperModel(
            self._model_ref,
            device="cpu",
            compute_type=self._compute_type,
            cpu_threads=self._cpu_threads,
            download_root=self._download_root,
        )

    def transcribe(self, samples) -> EngineResult:
        if self._model is None:
            raise RuntimeError("FasterWhisperEngine.transcribe() called before load()")
        segments, _info = self._model.transcribe(
            samples,
            word_timestamps=True,
            # The app's chunker already does VAD/segmentation; let Whisper see
            # the full chunk so trailing partial words are not trimmed.
            vad_filter=False,
            # Chunks are independent — carrying text context across requests
            # would let one chunk's content bias another's.
            condition_on_previous_text=False,
        )
        texts: list[str] = []
        words: list[dict] = []
        for segment in segments:  # generator — consumes the transcription
            seg_text = segment.text.strip()
            if seg_text:
                texts.append(seg_text)
            for w in segment.words or []:
                word = w.word.strip()
                if word:
                    words.append(
                        {"word": word, "start": round(w.start, 3), "end": round(w.end, 3)}
                    )
        return EngineResult(text=" ".join(texts), words=words)
