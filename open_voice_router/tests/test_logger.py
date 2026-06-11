"""Unit tests for Logger (task 2.4).

Covers Requirements 10.1 – 10.5.
"""

from __future__ import annotations

import json
import os

import pytest

from open_voice_router.logger import FallbackLogEntry, Logger
from open_voice_router.models import FallbackRecord, SessionLogEntry


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_dictation_entry() -> SessionLogEntry:
    return SessionLogEntry(
        session_id="sess-001",
        timestamp="2024-01-15T10:30:00Z",
        mode="dictation",
        stt_provider_id="provider-stt-1",
        stt_latency_ms=450,
        stt_outcome="success",
    )


def _make_voice_to_ai_entry() -> SessionLogEntry:
    return SessionLogEntry(
        session_id="sess-002",
        timestamp="2024-01-15T11:00:00Z",
        mode="voice_to_ai",
        stt_provider_id="provider-stt-1",
        stt_latency_ms=380,
        stt_outcome="success",
        llm_provider_id="provider-llm-1",
        llm_latency_ms=1200,
        llm_outcome="success",
    )


def _make_fallback_entry() -> FallbackLogEntry:
    return FallbackLogEntry(
        session_id="sess-003",
        timestamp="2024-01-15T12:00:00Z",
        original_provider_id="provider-stt-1",
        reason="timeout",
        fallback_provider_id="provider-stt-2",
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_log_session_writes_jsonl(tmp_path):
    """log_session appends a valid JSON line with all required fields."""
    log_file = str(tmp_path / "sessions.jsonl")
    logger = Logger(log_file)
    entry = _make_dictation_entry()

    logger.log_session(entry)

    lines = open(log_file, encoding="utf-8").readlines()
    assert len(lines) == 1

    record = json.loads(lines[0])
    assert record["session_id"] == "sess-001"
    assert record["timestamp"] == "2024-01-15T10:30:00Z"
    assert record["mode"] == "dictation"
    assert record["stt_provider_id"] == "provider-stt-1"
    assert record["stt_latency_ms"] == 450
    assert record["stt_outcome"] == "success"
    assert record["entry_type"] == "session"


def test_log_session_voice_to_ai_has_llm_fields(tmp_path):
    """Voice-to-AI session entries include llm_provider_id, llm_latency_ms, llm_outcome."""
    log_file = str(tmp_path / "sessions.jsonl")
    logger = Logger(log_file)
    entry = _make_voice_to_ai_entry()

    logger.log_session(entry)

    record = json.loads(open(log_file, encoding="utf-8").read())
    assert record["llm_provider_id"] == "provider-llm-1"
    assert record["llm_latency_ms"] == 1200
    assert record["llm_outcome"] == "success"


def test_log_fallback_writes_jsonl(tmp_path):
    """log_fallback appends a valid JSON line with correct fields."""
    log_file = str(tmp_path / "sessions.jsonl")
    logger = Logger(log_file)
    entry = _make_fallback_entry()

    logger.log_fallback(entry)

    lines = open(log_file, encoding="utf-8").readlines()
    assert len(lines) == 1

    record = json.loads(lines[0])
    assert record["session_id"] == "sess-003"
    assert record["original_provider_id"] == "provider-stt-1"
    assert record["reason"] == "timeout"
    assert record["fallback_provider_id"] == "provider-stt-2"
    assert record["entry_type"] == "fallback"


def test_no_audio_data_in_log(tmp_path):
    """Serialised log entries must not contain an 'audio' key (Req 10.5)."""
    log_file = str(tmp_path / "sessions.jsonl")
    logger = Logger(log_file)

    logger.log_session(_make_dictation_entry())
    logger.log_fallback(_make_fallback_entry())

    raw = open(log_file, encoding="utf-8").read()
    for line in raw.splitlines():
        record = json.loads(line)
        assert "audio" not in record, f"'audio' key found in log record: {record}"


def test_multiple_entries_are_separate_lines(tmp_path):
    """Logging two entries produces exactly two parseable JSON lines."""
    log_file = str(tmp_path / "sessions.jsonl")
    logger = Logger(log_file)

    logger.log_session(_make_dictation_entry())
    logger.log_session(_make_voice_to_ai_entry())

    lines = [l for l in open(log_file, encoding="utf-8").readlines() if l.strip()]
    assert len(lines) == 2

    for line in lines:
        record = json.loads(line)   # must not raise
        assert "session_id" in record


def test_log_creates_parent_dirs(tmp_path):
    """Logger creates missing parent directories when writing the first entry."""
    nested_path = str(tmp_path / "a" / "b" / "c" / "sessions.jsonl")
    assert not os.path.exists(os.path.dirname(nested_path))

    logger = Logger(nested_path)
    logger.log_session(_make_dictation_entry())

    assert os.path.isfile(nested_path)
    record = json.loads(open(nested_path, encoding="utf-8").read())
    assert record["session_id"] == "sess-001"
