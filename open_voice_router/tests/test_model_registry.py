"""Tests for the local STT model registry and engine factory.

These lock in the Phase-2 contract: adding a model is one well-formed registry
entry, every entry resolves to a constructible engine (construction is cheap —
heavy imports happen only in load()), and unknown ids degrade to the default.
"""

from __future__ import annotations

import pytest

from open_voice_router.local_asr import registry
from open_voice_router.local_asr.engines import create_engine
from open_voice_router.local_asr.engines.base import (
    BaseEngine,
    group_tokens_into_words,
)


# ---------------------------------------------------------------------------
# Registry well-formedness
# ---------------------------------------------------------------------------


def test_default_model_exists():
    assert registry.is_known_model(registry.DEFAULT_MODEL_ID)
    assert registry.get_model(registry.DEFAULT_MODEL_ID).id == registry.DEFAULT_MODEL_ID


def test_model_ids_are_unique():
    ids = [m.id for m in registry.all_models()]
    assert len(ids) == len(set(ids))


@pytest.mark.parametrize("spec", registry.all_models(), ids=lambda m: m.id)
def test_spec_is_well_formed(spec):
    assert spec.id and spec.display_name and spec.model_ref
    assert spec.engine in (
        registry.ENGINE_ONNX_ASR,
        registry.ENGINE_FASTER_WHISPER,
        registry.ENGINE_SHERPA_ONNX,
    )
    # Every engine must declare its pip packages and import-check modules.
    assert spec.pip_requirements
    assert spec.import_check_modules
    # Cache detection must be possible for every model.
    assert spec.cache_dir_fragment
    assert spec.cache_weight_glob
    assert spec.ram_estimate_mb > 0
    # The UI shows accuracy/memory for every model — never ship a blank hint.
    assert spec.wer_hint


def test_unknown_model_falls_back_to_default():
    assert registry.get_model("no-such-model").id == registry.DEFAULT_MODEL_ID
    assert registry.get_model(None).id == registry.DEFAULT_MODEL_ID
    assert registry.get_model("").id == registry.DEFAULT_MODEL_ID
    assert not registry.is_known_model("no-such-model")
    assert not registry.is_known_model(None)


# ---------------------------------------------------------------------------
# Effective-default resolution (honors what is actually installed)
# ---------------------------------------------------------------------------


def test_resolve_prefers_installed_over_absent_catalog_default():
    """The stored default (Parakeet v3) must not win when it isn't installed
    and another model is — the whole point of the bug fix."""
    installed = registry.get_model("parakeet-tdt-0.6b-v2").id
    result = registry.resolve_default_model_id(
        registry.DEFAULT_MODEL_ID, cached_ids={installed}
    )
    assert result == installed


def test_resolve_honors_explicit_installed_selection():
    """An explicit selection that IS installed is always kept, even when other
    models are also installed."""
    chosen = "whisper-base-ct2"
    result = registry.resolve_default_model_id(
        chosen, cached_ids={chosen, registry.DEFAULT_MODEL_ID}
    )
    assert result == chosen


def test_resolve_picks_catalog_order_among_installed():
    """With several installed and no valid selection, the earliest catalog
    (recommended) entry wins."""
    all_ids = {m.id for m in registry.all_models()}
    result = registry.resolve_default_model_id(None, cached_ids=all_ids)
    assert result == registry.all_models()[0].id


def test_resolve_keeps_known_persisted_when_nothing_installed():
    """Nothing cached → keep the intended model so the install flow targets it."""
    assert (
        registry.resolve_default_model_id("whisper-base-ct2", cached_ids=set())
        == "whisper-base-ct2"
    )


def test_resolve_falls_back_to_default_when_nothing_known_or_installed():
    assert (
        registry.resolve_default_model_id("no-such-model", cached_ids=set())
        == registry.DEFAULT_MODEL_ID
    )
    assert (
        registry.resolve_default_model_id(None, cached_ids=set())
        == registry.DEFAULT_MODEL_ID
    )


def test_resolve_ignores_unknown_cached_id():
    """A cached id not in the registry is never selected."""
    result = registry.resolve_default_model_id(None, cached_ids={"garbage-model"})
    assert result == registry.DEFAULT_MODEL_ID


# ---------------------------------------------------------------------------
# Engine factory — every registry entry must construct (no heavy imports)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("spec", registry.all_models(), ids=lambda m: m.id)
def test_every_registry_model_constructs_an_engine(spec):
    engine = create_engine(spec, cpu_threads=2, models_dir="X:/nowhere")
    assert isinstance(engine, BaseEngine)


def test_unknown_engine_raises():
    class FakeSpec:
        engine = "no-such-engine"
        model_ref = "x"
        quantization = None
        engine_options: dict = {}

    with pytest.raises(ValueError):
        create_engine(FakeSpec())


def test_transcribe_before_load_raises():
    engine = create_engine(registry.get_model(registry.DEFAULT_MODEL_ID))
    with pytest.raises(RuntimeError):
        engine.transcribe(None)


# ---------------------------------------------------------------------------
# Token → word grouping (shared by token-based engines)
# ---------------------------------------------------------------------------


def test_group_tokens_merges_subwords():
    tokens = ["▁Hel", "lo", "▁wor", "ld"]
    timestamps = [0.0, 0.2, 0.5, 0.7]
    words = group_tokens_into_words(tokens, timestamps, segment_end=1.0)
    assert [w["word"] for w in words] == ["Hello", "world"]
    # Word start = first subword's timestamp; end = next word's start.
    assert words[0]["start"] == 0.0 and words[0]["end"] == 0.5


def test_group_tokens_word_boundaries_and_times():
    tokens = ["▁Hi", "▁there"]
    timestamps = [0.1, 0.6]
    words = group_tokens_into_words(tokens, timestamps, segment_end=1.0)
    assert words == [
        {"word": "Hi", "start": 0.1, "end": 0.6},
        {"word": "there", "start": 0.6, "end": 1.0},
    ]


def test_group_tokens_applies_offset():
    tokens = ["▁go"]
    timestamps = [0.5]
    words = group_tokens_into_words(tokens, timestamps, segment_end=0.9, offset=10.0)
    assert words == [{"word": "go", "start": 10.5, "end": 10.9}]


def test_group_tokens_empty_input():
    assert group_tokens_into_words([], [], segment_end=0.0) == []


# ---------------------------------------------------------------------------
# Per-model cache detection (drives the "installed" flags in the UI)
# ---------------------------------------------------------------------------


def test_cache_detection_is_per_model(tmp_path, monkeypatch):
    """A cached Parakeet must not make Whisper look installed, and vice versa."""
    import open_voice_router.services.local_stt_manager as mgr

    # Synthetic HF-style cache: only the Parakeet v3 snapshot is present.
    snap = tmp_path / "models--istupakov--parakeet-tdt-0.6b-v3-onnx" / "snapshots" / "abc"
    snap.mkdir(parents=True)
    (snap / "encoder.int8.onnx").write_bytes(b"\x00")
    monkeypatch.setattr(mgr, "_MODELS_DIR", tmp_path)

    parakeet = registry.get_model("parakeet-tdt-0.6b-v3")
    whisper = registry.get_model("whisper-base-ct2")
    canary = registry.get_model("canary-180m-flash")

    assert mgr.LocalSTTManager._cache_present_for(parakeet) is True
    assert mgr.LocalSTTManager._cache_present_for(whisper) is False
    assert mgr.LocalSTTManager._cache_present_for(canary) is False


def test_cache_detection_matches_ct2_layout(tmp_path, monkeypatch):
    """faster-whisper snapshots use model.bin, not .onnx — the spec's glob
    must find them."""
    import open_voice_router.services.local_stt_manager as mgr

    snap = tmp_path / "models--Systran--faster-whisper-base" / "snapshots" / "x"
    snap.mkdir(parents=True)
    (snap / "model.bin").write_bytes(b"\x00")
    monkeypatch.setattr(mgr, "_MODELS_DIR", tmp_path)

    assert mgr.LocalSTTManager._cache_present_for(
        registry.get_model("whisper-base-ct2")
    ) is True


def test_cache_detection_missing_dir(tmp_path, monkeypatch):
    import open_voice_router.services.local_stt_manager as mgr

    monkeypatch.setattr(mgr, "_MODELS_DIR", tmp_path / "nope")
    assert mgr.LocalSTTManager._cache_present_for(
        registry.get_model(registry.DEFAULT_MODEL_ID)
    ) is False


def test_cached_model_ids_matches_per_model(tmp_path, monkeypatch):
    """The single-walk cached_model_ids() must agree, model-for-model, with
    the per-model _cache_present_for() it replaces in the UI hot path."""
    import open_voice_router.services.local_stt_manager as mgr

    # Two distinct snapshots present (Parakeet v3 + faster-whisper base).
    p_snap = tmp_path / "models--istupakov--parakeet-tdt-0.6b-v3-onnx" / "snapshots" / "a"
    p_snap.mkdir(parents=True)
    (p_snap / "encoder.int8.onnx").write_bytes(b"\x00")
    w_snap = tmp_path / "models--Systran--faster-whisper-base" / "snapshots" / "b"
    w_snap.mkdir(parents=True)
    (w_snap / "model.bin").write_bytes(b"\x00")
    monkeypatch.setattr(mgr, "_MODELS_DIR", tmp_path)

    expected = {
        m.id
        for m in registry.all_models()
        if mgr.LocalSTTManager._cache_present_for(m)
    }
    assert mgr.LocalSTTManager.cached_model_ids() == expected
    # Sanity: at least the two we seeded are present.
    assert "parakeet-tdt-0.6b-v3" in expected
    assert "whisper-base-ct2" in expected
