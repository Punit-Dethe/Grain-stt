"""sherpa-onnx engine — Moonshine, SenseVoice (and future k2-fsa models).

sherpa-onnx is a single pip wheel (C++ core, no PyTorch) covering a large
catalog of pre-converted models. Model bundles are resolved from Hugging Face
via the same cache dir the other engines use; file layout differs per model
family, so each supported ``kind`` has a small discovery + construction step.

Word timings: emitted when the recognizer returns token timestamps (CTC
models like SenseVoice); encoder-decoder models (Moonshine) yield none and
the app falls back to text-based overlap merging automatically.
"""

from __future__ import annotations

import glob
import os

try:  # sidecar context
    from engines.base import BaseEngine, EngineResult, group_tokens_into_words
except ImportError:  # app/package context (tests)
    from open_voice_router.local_asr.engines.base import (
        BaseEngine,
        EngineResult,
        group_tokens_into_words,
    )

SAMPLE_RATE = 16000


def _find_one(snapshot_dir: str, *patterns: str) -> str:
    """Return the first file in *snapshot_dir* matching any of *patterns*."""
    for pattern in patterns:
        matches = sorted(glob.glob(os.path.join(snapshot_dir, pattern)))
        if matches:
            return matches[0]
    raise FileNotFoundError(
        f"No file matching {patterns} in {snapshot_dir} — model bundle incomplete"
    )


class SherpaOnnxEngine(BaseEngine):
    def __init__(
        self,
        model_ref: str,
        kind: str,
        num_threads: int = 4,
    ) -> None:
        if kind not in ("moonshine", "sense_voice"):
            raise ValueError(f"Unsupported sherpa-onnx model kind: {kind!r}")
        self._model_ref = model_ref
        self._kind = kind
        self._num_threads = num_threads
        self._recognizer = None

    def load(self) -> None:
        import sherpa_onnx
        from huggingface_hub import snapshot_download

        # Resolves from the local HF cache (HF_HUB_CACHE / HF_HUB_OFFLINE are
        # set by LocalSTTManager); downloads on the install/first-start path.
        snapshot_dir = snapshot_download(self._model_ref)
        tokens = _find_one(snapshot_dir, "tokens.txt")

        if self._kind == "moonshine":
            self._recognizer = sherpa_onnx.OfflineRecognizer.from_moonshine(
                preprocessor=_find_one(snapshot_dir, "preprocess.onnx"),
                encoder=_find_one(snapshot_dir, "encode.int8.onnx", "encode.onnx"),
                uncached_decoder=_find_one(
                    snapshot_dir, "uncached_decode.int8.onnx", "uncached_decode.onnx"
                ),
                cached_decoder=_find_one(
                    snapshot_dir, "cached_decode.int8.onnx", "cached_decode.onnx"
                ),
                tokens=tokens,
                num_threads=self._num_threads,
            )
        else:  # sense_voice
            self._recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
                model=_find_one(snapshot_dir, "model.int8.onnx", "model.onnx"),
                tokens=tokens,
                num_threads=self._num_threads,
                use_itn=True,
            )

    def transcribe(self, samples) -> EngineResult:
        if self._recognizer is None:
            raise RuntimeError("SherpaOnnxEngine.transcribe() called before load()")
        stream = self._recognizer.create_stream()
        stream.accept_waveform(SAMPLE_RATE, samples)
        self._recognizer.decode_stream(stream)
        result = stream.result
        text = (result.text or "").strip()
        if not text:
            return EngineResult(text="")
        words: list[dict] = []
        tokens = list(getattr(result, "tokens", []) or [])
        timestamps = list(getattr(result, "timestamps", []) or [])
        if tokens and timestamps and len(tokens) == len(timestamps):
            segment_end = timestamps[-1] if len(timestamps) > 1 else timestamps[0] + 0.1
            words = group_tokens_into_words(tokens, timestamps, segment_end)
        return EngineResult(text=text, words=words)
