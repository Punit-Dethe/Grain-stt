"""ChunkPump — a pure, framework-free model of the streaming chunk pump.

This module extracts the orchestration logic that lives in ``AppController``
(``_stream_queue`` + ``_stream_busy`` + ``_model_ready`` + ``_stream_recording_done``
+ the ``_stream_generation`` token) into a small, Qt-free state machine so the
on-demand-load correctness properties can be exercised with property-based
testing without spawning a real subprocess, microphone, or HTTP server.

It mirrors the production contract enforced in ``AppController``:

  * **Readiness gate (R2.1, R2.5, R6.1).** While the ASR_Server is not yet ready
    (``model_ready`` is False), finalized chunks accumulate in capture order and
    nothing is dispatched. Draining begins only once :meth:`mark_ready` fires.
  * **Serialization (R2.3, R9.4).** At most one chunk request is in flight at a
    time. The next chunk is dispatched only after the in-flight request
    completes (:meth:`complete`) or fails (:meth:`fail`).
  * **Capture order (R2.2).** Chunks are dispatched strictly in the order they
    were enqueued (FIFO).
  * **Failure never aborts the drain (R2.6).** A failed chunk frees the in-flight
    slot and draining continues with the remaining queued chunks.
  * **Stale-generation discard (R8.4).** Each result carries the generation token
    it was dispatched under; a result whose generation does not match the current
    generation is ignored and cannot affect the pump.
  * **No finalize-as-empty while loading (R6.2).** The finalize guard refuses to
    finalize an empty session while the model is neither ready nor failed.
  * **Load-failure clears buffered audio (R7.6).** :meth:`clear` empties the queue
    and bumps the generation so no stale audio carries into the next session.

The pump is intentionally agnostic about what a "chunk" is — it stores whatever
opaque value is enqueued (bytes, an id, a test sentinel) so it can be driven by
arbitrary generated inputs.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from typing import Any, Deque, List, Optional


@dataclass
class ChunkPump:
    """Pure model of the serialized, readiness-gated streaming chunk pump.

    State fields mirror the ``AppController`` members of the same name:

    - ``generation``       — the stale-result discard token (``_stream_generation``).
    - ``_queue``           — FIFO of enqueued-but-not-yet-dispatched chunks (``_stream_queue``).
    - ``_busy``            — True while one request is in flight (``_stream_busy``).
    - ``_model_ready``     — True once the ASR_Server reported ready (``_model_ready``).
    - ``_recording_done``  — True once recording has stopped (``_stream_recording_done``).
    - ``_in_flight``       — the chunk currently being transcribed, or ``None``.

    Observation logs (not present in production, used for property assertions):

    - ``dispatched``  — every chunk in the order it left the queue (capture order).
    - ``succeeded``   — chunks whose transcription completed successfully.
    - ``failed``      — chunks whose transcription failed.
    """

    generation: int = 0
    _queue: Deque[Any] = field(default_factory=deque)
    _busy: bool = False
    _model_ready: bool = False
    _recording_done: bool = False
    _in_flight: Optional[Any] = None

    # Observation logs for verification.
    dispatched: List[Any] = field(default_factory=list)
    succeeded: List[Any] = field(default_factory=list)
    failed: List[Any] = field(default_factory=list)

    # ------------------------------------------------------------------
    # Read-only views
    # ------------------------------------------------------------------
    @property
    def queued(self) -> List[Any]:
        """Snapshot of the chunks still waiting in the queue, in capture order."""
        return list(self._queue)

    @property
    def busy(self) -> bool:
        """True while exactly one chunk request is in flight."""
        return self._busy

    @property
    def model_ready(self) -> bool:
        """True once the ASR_Server reported ready this session."""
        return self._model_ready

    @property
    def recording_done(self) -> bool:
        """True once recording has stopped (``recording_stopped`` fired)."""
        return self._recording_done

    @property
    def in_flight(self) -> Optional[Any]:
        """The chunk currently in flight, or ``None`` when idle."""
        return self._in_flight

    @property
    def in_flight_count(self) -> int:
        """Number of requests in flight — invariant: never exceeds 1."""
        return 1 if self._in_flight is not None else 0

    @property
    def is_idle(self) -> bool:
        """True when the queue is empty and nothing is in flight."""
        return not self._queue and not self._busy

    # ------------------------------------------------------------------
    # Mutations
    # ------------------------------------------------------------------
    def enqueue(self, chunk: Any) -> None:
        """Append a finalized chunk in capture order, then attempt a dispatch.

        Mirrors ``_on_chunk_ready`` → ``_pump_stream_queue``. While the model is
        not ready the chunk simply accumulates (the readiness gate in
        :meth:`dispatch` returns early).
        """
        self._queue.append(chunk)
        self.dispatch()

    def mark_ready(self) -> None:
        """Mark the ASR_Server ready and begin draining the queue.

        Mirrors ``_on_model_ready``: setting the flag then pumping the queue.
        Idempotent — calling it again while already ready just re-pumps.
        """
        self._model_ready = True
        self.dispatch()

    def mark_recording_done(self) -> None:
        """Record that recording has stopped, then pump.

        Mirrors ``_on_chunked_recording_stopped``: the final tail chunk has
        already been enqueued, so we only flip the flag and pump in case the
        queue is idle.
        """
        self._recording_done = True
        self.dispatch()

    def dispatch(self) -> bool:
        """The serialization gate: dispatch the next queued chunk if allowed.

        Mirrors ``_pump_stream_queue``. Returns ``True`` if a chunk was
        dispatched, ``False`` otherwise. Dispatch is refused when:
          * the model is not yet ready (readiness gate — R2.1/R6.1), or
          * a request is already in flight (serialization — R2.3/R9.4), or
          * the queue is empty.
        """
        if not self._model_ready:
            # Readiness gate: chunks remain queued in capture order until ready.
            return False
        if self._busy:
            # At most one request in flight at any time.
            return False
        if not self._queue:
            return False

        chunk = self._queue.popleft()
        self._in_flight = chunk
        self._busy = True
        self.dispatched.append(chunk)
        return True

    def complete(self, generation: int, transcript: str = "") -> bool:
        """Complete the in-flight request successfully, then pump the next chunk.

        Mirrors ``_on_chunk_stt_complete``. Results carrying a stale generation
        token are ignored (R8.4). Returns ``True`` if the result was applied.
        """
        if generation != self.generation:
            return False  # stale result from a previous/discarded session
        if not self._busy:
            return False  # nothing in flight to complete
        finished = self._in_flight
        self._in_flight = None
        self._busy = False
        self.succeeded.append((finished, transcript) if transcript else finished)
        self.dispatch()
        return True

    def fail(self, generation: int, error: str = "") -> bool:
        """Fail the in-flight request, then continue draining the queue.

        Mirrors ``_on_chunk_stt_error``. A single failed chunk must never abort
        the session (R2.6/R9.5). Stale-generation results are ignored (R8.4).
        Returns ``True`` if the failure was applied.
        """
        if generation != self.generation:
            return False  # stale result — ignore
        if not self._busy:
            return False  # nothing in flight to fail
        finished = self._in_flight
        self._in_flight = None
        self._busy = False
        self.failed.append((finished, error) if error else finished)
        self.dispatch()
        return True

    def clear(self) -> None:
        """Discard all buffered audio and start a fresh generation.

        Mirrors ``_discard_session`` / load-failure handling: empties the queue,
        frees the in-flight slot, and bumps the generation token so any result
        still in flight from the cleared session becomes stale and cannot affect
        the next session (R7.6, R8.4).
        """
        self._queue.clear()
        self._busy = False
        self._in_flight = None
        self.generation += 1

    # ------------------------------------------------------------------
    # Finalize guard
    # ------------------------------------------------------------------
    def can_finalize(self, *, load_failed: bool = False) -> bool:
        """Whether the session may finalize now.

        Mirrors ``_maybe_finalize_streaming_session`` with the on-demand gate:
        finalize only when recording has stopped, nothing is in flight, the
        queue is drained, AND the model is either ready or the load has failed.

        The final clause is the R6.2 guard: while the model is still loading
        (not ready and not failed) the session must NOT finalize-as-empty even
        though the queue is momentarily empty — it stays in PROCESSING.
        """
        if not self._recording_done:
            return False
        if self._busy:
            return False
        if self._queue:
            return False
        if not (self._model_ready or load_failed):
            return False
        return True
