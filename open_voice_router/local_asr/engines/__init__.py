"""Engine factory — maps a registry ModelSpec to a loaded-able engine.

Engine modules are imported lazily so the sidecar venv only needs the
dependencies of the engine actually selected (e.g. choosing Parakeet never
imports faster_whisper).
"""

from __future__ import annotations


def create_engine(spec, *, cpu_threads: int = 4, models_dir: str | None = None):
    """Instantiate (but do not load) the engine for *spec*.

    *spec* is duck-typed (registry.ModelSpec or anything with the same
    fields) so this package never has to import the registry module —
    keeping the dual-context import story simple.
    """
    engine = spec.engine
    if engine == "onnx_asr":
        try:
            from engines.onnx_asr_engine import OnnxAsrEngine
        except ImportError:
            from open_voice_router.local_asr.engines.onnx_asr_engine import OnnxAsrEngine
        return OnnxAsrEngine(
            model_ref=spec.model_ref,
            quantization=spec.quantization,
            intra_threads=cpu_threads,
        )
    if engine == "faster_whisper":
        try:
            from engines.faster_whisper_engine import FasterWhisperEngine
        except ImportError:
            from open_voice_router.local_asr.engines.faster_whisper_engine import (
                FasterWhisperEngine,
            )
        return FasterWhisperEngine(
            model_ref=spec.model_ref,
            compute_type=spec.quantization,
            cpu_threads=cpu_threads,
            models_dir=models_dir,
        )
    if engine == "sherpa_onnx":
        try:
            from engines.sherpa_onnx_engine import SherpaOnnxEngine
        except ImportError:
            from open_voice_router.local_asr.engines.sherpa_onnx_engine import (
                SherpaOnnxEngine,
            )
        return SherpaOnnxEngine(
            model_ref=spec.model_ref,
            kind=dict(spec.engine_options).get("kind", ""),
            num_threads=cpu_threads,
        )
    raise ValueError(f"Unknown engine: {engine!r}")
