"""onnx_asr engine — NeMo (Parakeet/Canary), GigaAM, Zipformer, Whisper-ONNX.

Wraps the ``onnx_asr`` library (numpy + onnxruntime, no PyTorch). Token-level
timestamps come from the model's decoder and are grouped into words.

This is the engine the app shipped with originally — keep its behavior
(session options, provider selection) byte-for-byte to avoid regressions.
"""

from __future__ import annotations

try:  # sidecar context (server.py puts local_asr/ on sys.path)
    from engines.base import BaseEngine, EngineResult, group_tokens_into_words
except ImportError:  # app/package context (tests)
    from open_voice_router.local_asr.engines.base import (
        BaseEngine,
        EngineResult,
        group_tokens_into_words,
    )


def _build_session_options(ort, intra_threads: int, inter_threads: int):
    """ORT SessionOptions tuned for fast load and efficient CPU inference.

    ORT_ENABLE_EXTENDED rather than ORT_ENABLE_ALL: the ALL level adds the
    NchwcTransformer (a Windows-specific memory-layout pass) which takes ~2-3 s
    on every cold start and whose output is never reused between restarts.
    EXTENDED keeps operator fusion and constant folding, so inference quality
    and throughput are unchanged.
    """
    sess_options = ort.SessionOptions()
    sess_options.intra_op_num_threads = intra_threads
    sess_options.inter_op_num_threads = inter_threads
    sess_options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_EXTENDED
    sess_options.add_session_config_entry("session.set_denormal_as_zero", "1")
    sess_options.add_session_config_entry("session.intra_op.allow_spinning", "1")
    sess_options.add_session_config_entry("session.inter_op.allow_spinning", "0")
    return sess_options


class OnnxAsrEngine(BaseEngine):
    def __init__(
        self,
        model_ref: str,
        quantization: str | None = None,
        intra_threads: int = 4,
        inter_threads: int = 1,
    ) -> None:
        self._model_ref = model_ref
        self._quantization = quantization
        self._intra_threads = intra_threads
        self._inter_threads = inter_threads
        self._model = None

    def load(self) -> None:
        import onnx_asr
        import onnxruntime as ort

        providers = []
        available = ort.get_available_providers()
        if "TensorrtExecutionProvider" in available:
            providers.append("TensorrtExecutionProvider")
        if "CUDAExecutionProvider" in available:
            providers.append("CUDAExecutionProvider")
        providers.append("CPUExecutionProvider")

        self._model = onnx_asr.load_model(
            self._model_ref,
            quantization=self._quantization,
            providers=providers,
            sess_options=_build_session_options(
                ort, self._intra_threads, self._inter_threads
            ),
        ).with_timestamps()

    def transcribe(self, samples) -> EngineResult:
        if self._model is None:
            raise RuntimeError("OnnxAsrEngine.transcribe() called before load()")
        result = self._model.recognize(samples)
        if not result or not result.text:
            return EngineResult(text="")
        words: list[dict] = []
        if result.tokens and result.timestamps:
            segment_end = (
                result.timestamps[-1] if len(result.timestamps) > 1
                else result.timestamps[0] + 0.1
            )
            words = group_tokens_into_words(
                list(result.tokens), list(result.timestamps), segment_end
            )
        return EngineResult(text=result.text, words=words)
