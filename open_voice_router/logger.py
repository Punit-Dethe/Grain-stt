"""Structured JSON Lines logger for Open Voice Router.

Appends one JSON object per line to a .jsonl file.  Audio data and API keys
are never written — only the fields defined on the log entry dataclasses are
serialised.
"""

from __future__ import annotations

import dataclasses
import json
import os
from dataclasses import dataclass

from open_voice_router.models import SessionLogEntry


@dataclass
class FallbackLogEntry:
    """Structured log entry for a single provider fallback event."""

    session_id: str
    timestamp: str              # ISO 8601
    original_provider_id: str
    reason: str
    fallback_provider_id: str


class Logger:
    """Appends structured log entries to a .jsonl file.

    Each call to ``log_session`` or ``log_fallback`` appends exactly one JSON
    object followed by a newline.  The file is opened in append mode so
    concurrent readers always see complete lines.

    Audio data and API keys are never written — the serialised dicts contain
    only the fields declared on the entry dataclasses.
    """

    def __init__(self, log_file_path: str) -> None:
        """Initialise with the path to the .jsonl log file.

        The parent directory is created automatically if it does not exist.
        """
        self._path = log_file_path

    def _ensure_parent_dir(self) -> None:
        """Create parent directories for the log file if they don't exist."""
        parent = os.path.dirname(self._path)
        if parent:
            os.makedirs(parent, exist_ok=True)

    def log_session(self, entry: SessionLogEntry) -> None:
        """Append a session log entry as a JSON Lines record.

        The entry is serialised via ``dataclasses.asdict``, which recursively
        converts nested dataclasses (e.g. ``FallbackRecord`` items in the
        ``fallbacks`` list).  An ``entry_type`` field is added to distinguish
        record types when reading the log.

        Audio data and API keys are never written.
        """
        self._ensure_parent_dir()
        d = dataclasses.asdict(entry)
        d["entry_type"] = "session"
        with open(self._path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(d) + "\n")

    def log_fallback(self, entry: FallbackLogEntry) -> None:
        """Append a fallback log entry as a JSON Lines record.

        Same serialisation pattern as ``log_session``; ``entry_type`` is set
        to ``"fallback"`` so consumers can filter by record type.
        """
        self._ensure_parent_dir()
        d = dataclasses.asdict(entry)
        d["entry_type"] = "fallback"
        with open(self._path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(d) + "\n")
