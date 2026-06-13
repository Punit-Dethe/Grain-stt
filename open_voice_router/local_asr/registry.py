"""Model registry — the single source of truth for local STT models.

Adding support for a new model is ONE entry here (plus, at most, a new engine
wrapper if no existing engine runs it). Nothing in the app proper changes:
the app always talks OpenAI-compatible HTTP to the sidecar, and the sidecar
loads whichever engine/model this registry describes.

DUAL-CONTEXT MODULE — imported two ways:
  * by the app:      ``from open_voice_router.local_asr import registry``
  * by the sidecar:  ``import registry`` (server.py puts its dir on sys.path)
Therefore this module must stay PURE STDLIB: no Qt, no numpy, no app imports.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Mapping

# Engine identifiers — each maps to a wrapper module in local_asr/engines/.
ENGINE_ONNX_ASR = "onnx_asr"
ENGINE_FASTER_WHISPER = "faster_whisper"
ENGINE_SHERPA_ONNX = "sherpa_onnx"

# Per-engine pip requirements, installed into the sidecar venv on demand.
# The Flask/waitress base requirements (requirements.txt) are always installed.
_ENGINE_PIP: dict[str, tuple[str, ...]] = {
    ENGINE_ONNX_ASR: ("onnx-asr>=0.4.0", "onnxruntime>=1.18.0"),
    ENGINE_FASTER_WHISPER: ("faster-whisper>=1.1.0",),
    ENGINE_SHERPA_ONNX: ("sherpa-onnx>=1.12.0",),
}

# Modules the import warmer / install verifier should try per engine.
_ENGINE_IMPORTS: dict[str, tuple[str, ...]] = {
    ENGINE_ONNX_ASR: ("onnxruntime", "onnx_asr"),
    ENGINE_FASTER_WHISPER: ("faster_whisper",),
    ENGINE_SHERPA_ONNX: ("sherpa_onnx",),
}


@dataclass(frozen=True)
class ModelSpec:
    """Everything the app and the sidecar need to know about one model."""

    id: str                    # stable id — stored in settings, sent as MODEL_ID
    display_name: str          # shown in the settings UI
    engine: str                # ENGINE_* constant
    model_ref: str             # engine-specific reference (HF repo id or alias)
    quantization: str | None = None  # engine-specific precision hint
    # Free-form engine knobs (e.g. sherpa recognizer kind). Keep JSON-simple.
    engine_options: Mapping[str, str] = field(default_factory=dict)
    # True when the engine reliably yields word-level timestamps for this
    # model. Informational (UI/registry); the client always adapts to what a
    # response actually contains.
    supports_word_timestamps: bool = True
    ram_estimate_mb: int = 1500
    languages: str = "multilingual"
    description: str = ""
    # Approximate English word error rate for the UI (Open ASR leaderboard
    # average where published; "est." marks values extrapolated to the
    # quantized build — int8 typically costs <0.3% absolute over FP).
    wer_hint: str = ""
    # Cache detection: a model counts as installed when a directory whose name
    # contains `cache_dir_fragment` exists under the models dir AND contains a
    # file matching `cache_weight_glob`.
    cache_dir_fragment: str = ""
    cache_weight_glob: str = "*.onnx"

    @property
    def pip_requirements(self) -> tuple[str, ...]:
        return _ENGINE_PIP.get(self.engine, ())

    @property
    def import_check_modules(self) -> tuple[str, ...]:
        return _ENGINE_IMPORTS.get(self.engine, ())


DEFAULT_MODEL_ID = "parakeet-tdt-0.6b-v3"

# Catalog ordering = recommended order in the UI: default first, then by
# accuracy-per-MB within each tier. WER figures are Open ASR leaderboard
# English averages where published; "est." marks values extrapolated to the
# quantized build we actually run.
_MODELS: tuple[ModelSpec, ...] = (
    ModelSpec(
        id="parakeet-tdt-0.6b-v3",
        display_name="Parakeet TDT 0.6B v3 (INT8)",
        engine=ENGINE_ONNX_ASR,
        model_ref="nemo-parakeet-tdt-0.6b-v3",
        quantization="int8",
        supports_word_timestamps=True,
        ram_estimate_mb=1200,
        languages="25 European languages",
        description="Fast and accurate. The recommended default.",
        wer_hint="≈6.4% WER (en, est.)",
        cache_dir_fragment="parakeet-tdt-0.6b-v3",
        cache_weight_glob="*.onnx",
    ),
    ModelSpec(
        id="parakeet-tdt-0.6b-v2",
        display_name="Parakeet TDT 0.6B v2 — English (INT8)",
        engine=ENGINE_ONNX_ASR,
        model_ref="nemo-parakeet-tdt-0.6b-v2",
        quantization="int8",
        supports_word_timestamps=True,
        ram_estimate_mb=1200,
        languages="English only",
        description="English-tuned Parakeet — best English accuracy in its size class.",
        wer_hint="≈6.1% WER (en, est.)",
        cache_dir_fragment="parakeet-tdt-0.6b-v2",
        cache_weight_glob="*.onnx",
    ),
    ModelSpec(
        id="canary-180m-flash",
        display_name="Canary 180M Flash (INT8)",
        engine=ENGINE_ONNX_ASR,
        model_ref="istupakov/canary-180m-flash-onnx",
        quantization="int8",
        supports_word_timestamps=True,
        ram_estimate_mb=350,
        languages="English, German, French, Spanish",
        description="Parakeet-class accuracy at a third of the RAM. Best efficiency pick.",
        wer_hint="≈6.6% WER (en, est.)",
        cache_dir_fragment="canary-180m-flash",
        cache_weight_glob="*.onnx",
    ),
    ModelSpec(
        id="moonshine-tiny-en",
        display_name="Moonshine Tiny — English (INT8)",
        engine=ENGINE_SHERPA_ONNX,
        model_ref="csukuangfj/sherpa-onnx-moonshine-tiny-en-int8",
        quantization="int8",
        engine_options={"kind": "moonshine"},
        # Moonshine is encoder-decoder; sherpa-onnx does not emit reliable
        # token timestamps for it — the text-merge fallback handles overlap.
        supports_word_timestamps=False,
        ram_estimate_mb=250,
        languages="English",
        description="Smallest usable model — for very low-end hardware.",
        wer_hint="≈12.7% WER (en, est.)",
        cache_dir_fragment="moonshine-tiny-en",
        cache_weight_glob="*.onnx",
    ),
    ModelSpec(
        id="moonshine-base-en",
        display_name="Moonshine Base — English (INT8)",
        engine=ENGINE_SHERPA_ONNX,
        model_ref="csukuangfj/sherpa-onnx-moonshine-base-en-int8",
        quantization="int8",
        engine_options={"kind": "moonshine"},
        supports_word_timestamps=False,
        ram_estimate_mb=700,
        languages="English",
        description="Tiny, very fast English-only model for low-end hardware.",
        wer_hint="≈10.1% WER (en, est.)",
        cache_dir_fragment="moonshine-base-en",
        cache_weight_glob="*.onnx",
    ),
    ModelSpec(
        id="whisper-base-ct2",
        display_name="Whisper Base (INT8)",
        engine=ENGINE_FASTER_WHISPER,
        model_ref="base",  # faster-whisper alias → Systran/faster-whisper-base
        quantization="int8",
        supports_word_timestamps=True,
        ram_estimate_mb=600,
        languages="99 languages",
        description="Small and multilingual. Good low-RAM choice.",
        wer_hint="≈10.3% WER (en, est.)",
        cache_dir_fragment="faster-whisper-base",
        cache_weight_glob="*.bin",
    ),
    ModelSpec(
        id="whisper-small-ct2",
        display_name="Whisper Small (INT8)",
        engine=ENGINE_FASTER_WHISPER,
        model_ref="small",
        quantization="int8",
        supports_word_timestamps=True,
        ram_estimate_mb=1200,
        languages="99 languages",
        description="Better accuracy than Base, still edge-friendly.",
        wer_hint="≈8.6% WER (en, est.)",
        cache_dir_fragment="faster-whisper-small",
        cache_weight_glob="*.bin",
    ),
    ModelSpec(
        id="distil-whisper-large-v3.5-ct2",
        display_name="Distil-Whisper Large v3.5 (INT8)",
        engine=ENGINE_FASTER_WHISPER,
        model_ref="distil-whisper/distil-large-v3.5-ct2",
        quantization="int8",
        supports_word_timestamps=True,
        ram_estimate_mb=1600,
        languages="English (distilled)",
        description="Large-class English accuracy at half the RAM and ~1.5x the speed.",
        wer_hint="≈7.1% WER (en, est.)",
        cache_dir_fragment="distil-large-v3.5",
        cache_weight_glob="*.bin",
    ),
    ModelSpec(
        id="whisper-large-v3-turbo-ct2",
        display_name="Whisper Large v3 Turbo (INT8)",
        engine=ENGINE_FASTER_WHISPER,
        model_ref="deepdml/faster-whisper-large-v3-turbo-ct2",
        quantization="int8",
        supports_word_timestamps=True,
        ram_estimate_mb=3000,
        languages="99 languages",
        description="Best multilingual accuracy that still fits a ~3 GB RAM budget.",
        wer_hint="≈7.8% WER (en, est.)",
        cache_dir_fragment="faster-whisper-large-v3-turbo",
        cache_weight_glob="*.bin",
    ),
    ModelSpec(
        id="parakeet-tdt-0.6b-v3-fp32",
        display_name="Parakeet TDT 0.6B v3 (FP32)",
        engine=ENGINE_ONNX_ASR,
        model_ref="istupakov/parakeet-tdt-0.6b-v3-onnx",
        quantization=None,
        supports_word_timestamps=True,
        ram_estimate_mb=2600,
        languages="25 European languages",
        description="Full precision — slightly higher accuracy, slower on CPU.",
        wer_hint="≈6.3% WER (en)",
        cache_dir_fragment="parakeet-tdt-0.6b-v3",
        cache_weight_glob="*.onnx",
    ),
    ModelSpec(
        id="sense-voice-small",
        display_name="SenseVoice Small (INT8)",
        engine=ENGINE_SHERPA_ONNX,
        model_ref="csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17",
        quantization="int8",
        engine_options={"kind": "sense_voice"},
        supports_word_timestamps=False,
        ram_estimate_mb=1500,
        languages="Chinese, English, Japanese, Korean, Cantonese",
        description="Strong Asian-language coverage.",
        wer_hint="optimized for zh/ja/ko",
        cache_dir_fragment="sense-voice",
        cache_weight_glob="*.onnx",
    ),
)

_BY_ID: dict[str, ModelSpec] = {m.id: m for m in _MODELS}


def all_models() -> tuple[ModelSpec, ...]:
    """All registered models, default first."""
    return _MODELS


def get_model(model_id: str | None) -> ModelSpec:
    """Resolve a model id to its spec, falling back to the default.

    Unknown/empty ids resolve to the default rather than raising so a stale
    settings file (e.g. a model removed from the registry) degrades to a
    working configuration instead of breaking startup.
    """
    if model_id and model_id in _BY_ID:
        return _BY_ID[model_id]
    return _BY_ID[DEFAULT_MODEL_ID]


def is_known_model(model_id: str | None) -> bool:
    return bool(model_id) and model_id in _BY_ID
