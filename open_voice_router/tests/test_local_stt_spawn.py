"""Tests for LocalSTTManager's async (non-blocking) server-spawn continuation.

The blocking launch work (cache walk, stale-port release, Popen) runs on a
worker thread so the Qt main thread — and the Pill animation — is never blocked
during an on-demand Model_Load. ``_on_spawn_finished`` is the main-thread
continuation; these tests pin down its failure routing and the "superseded"
guard without launching a real server.

Signals are connected to plain Python callables (direct delivery), so no
QApplication / event loop is required.
"""

from __future__ import annotations

from open_voice_router.services.local_stt_manager import LocalSTTManager


def _manager_with_capture():
    m = LocalSTTManager()
    events: dict[str, list] = {"load_failed": [], "crashed": []}
    m.load_failed.connect(lambda r: events["load_failed"].append(r))
    m.server_crashed.connect(lambda r: events["crashed"].append(r))
    return m, events


def test_missing_cache_during_load_routes_to_load_failed():
    m, events = _manager_with_capture()
    m._is_loading = True
    m._set_status("starting")
    m._on_spawn_finished(None, "missing-cache")
    assert events["load_failed"] == ["missing-cache"]
    assert events["crashed"] == []
    assert m.status == "error"
    assert m._is_loading is False


def test_launch_error_during_load_routes_to_load_failed():
    m, events = _manager_with_capture()
    m._is_loading = True
    m._set_status("starting")
    m._on_spawn_finished(None, "launch::boom")
    assert events["load_failed"] == ["launch"]
    assert events["crashed"] == []


def test_launch_error_during_start_routes_to_server_crashed():
    m, events = _manager_with_capture()
    m._is_loading = False  # install-time start, not an on-demand load
    m._set_status("starting")
    m._on_spawn_finished(None, "launch::cannot-exec")
    assert events["load_failed"] == []
    assert events["crashed"] and "cannot-exec" in events["crashed"][-1]


def test_superseded_result_is_discarded_and_process_terminated():
    """If stop()/uninstall flips status away from 'starting' while a spawn is in
    flight, a late success must NOT install the process — the orphan is killed."""
    m, events = _manager_with_capture()

    class _FakeProc:
        def __init__(self):
            self.terminated = False

        def terminate(self):
            self.terminated = True

    proc = _FakeProc()
    m._set_status("stopped")  # superseded
    m._on_spawn_finished(proc, "")
    assert proc.terminated is True
    assert m._process is None
    assert events["load_failed"] == []
    assert events["crashed"] == []
