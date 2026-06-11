"""LoadLifecycle — a pure, framework-free state machine for on-demand Model_Load /
Model_Unload.

This module extracts the *decision logic* that ``LocalSTTManager`` uses to drive the
ASR_Server subprocess into a small, dependency-free object so the feature's correctness
properties can be exercised with property-based testing without spawning a real
subprocess, opening a socket, or importing Qt.

It models the manager's existing status string:

    not_installed | installing | stopped | starting | running | error

and the behavioural rules described in the design document:

* **Single-process / reuse rule (Properties 9):** a ``load()`` issued while the server is
  ``running`` or ``starting`` reuses the existing process and never spawns a second one;
  only ``stopped`` / ``error`` may spawn.
* **Cancellable pending unload (Property 11):** ``unload()`` arms a deferred unload that a
  later ``load()`` cancels before it fires.
* **Idempotent unload (Property 10):** requesting an unload while nothing is loaded leaves
  the status unchanged and never raises.
* **Successful unload (Property 13):** completing an unload from ``running`` transitions to
  ``stopped``.
* **Effective timeout clamping (Property 14):** the timeout used by ``load()`` is an
  in-range value as-is, otherwise it falls back to the default of 30 seconds.
* **Idle stays unloaded (Property 1):** with no ``load()`` the status never becomes
  resident.

The object is deliberately Qt-free; ``LocalSTTManager`` (task 2.8) wraps it and connects
its transitions to real ``QTimer`` / subprocess / health-poller machinery.
"""

from __future__ import annotations

from typing import Final

# ---------------------------------------------------------------------------
# Status string values (mirror LocalSTTManager.status_changed values)
# ---------------------------------------------------------------------------

NOT_INSTALLED: Final = "not_installed"
INSTALLING: Final = "installing"
STOPPED: Final = "stopped"
STARTING: Final = "starting"
RUNNING: Final = "running"
ERROR: Final = "error"

VALID_STATUSES: Final = frozenset(
    {NOT_INSTALLED, INSTALLING, STOPPED, STARTING, RUNNING, ERROR}
)

# A model is "resident" (occupies RAM / a live process exists) exactly while the server is
# starting up or running.
_RESIDENT_STATUSES: Final = frozenset({STARTING, RUNNING})

# Statuses from which a fresh Model_Load may spawn a new subprocess.
_SPAWNABLE_STATUSES: Final = frozenset({STOPPED, ERROR})

# ---------------------------------------------------------------------------
# Load-timeout bounds (Requirement 7.2 / Property 14)
# ---------------------------------------------------------------------------

DEFAULT_TIMEOUT_S: Final = 30
MIN_TIMEOUT_S: Final = 10
MAX_TIMEOUT_S: Final = 120


class LoadLifecycle:
    """Pure state machine over the ASR_Server status used for on-demand load/unload.

    Transitions are intentionally explicit rather than driven by side effects so they can
    be replayed deterministically in tests:

    * ``load(timeout_s)``    — request Model_Load (cancels any pending unload, reuses a
                               running/starting server, or spawns from stopped/error).
    * ``ready()``            — server reported ready: ``starting -> running``.
    * ``fail()``             — load errored/timed out: ``starting``/``running`` -> ``error``.
    * ``unload(delay_ticks)``— arm a cancellable Model_Unload.
    * ``tick()``             — advance the pending-unload timer by one step.
    * ``unload_completes()`` — the unload finished: resident -> ``stopped``.
    """

    def __init__(self, status: str = STOPPED) -> None:
        if status not in VALID_STATUSES:
            raise ValueError(f"invalid status: {status!r}")
        self._status: str = status
        self._spawn_count: int = 0
        self._effective_timeout_s: int = DEFAULT_TIMEOUT_S
        self._unload_pending: bool = False
        self._unload_ticks_remaining: int = 0

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------

    @property
    def status(self) -> str:
        """Current status string (one of ``VALID_STATUSES``)."""
        return self._status

    @property
    def spawn_count(self) -> int:
        """Cumulative number of subprocess spawns performed by ``load()``.

        Reuse of a running/starting server does not increment this.
        """
        return self._spawn_count

    @property
    def effective_timeout_s(self) -> int:
        """The clamped timeout most recently applied by ``load()``."""
        return self._effective_timeout_s

    @property
    def unload_pending(self) -> bool:
        """True while a deferred Model_Unload is armed but has not yet fired."""
        return self._unload_pending

    @property
    def is_resident(self) -> bool:
        """True while the model occupies RAM (status ``starting`` or ``running``)."""
        return self._status in _RESIDENT_STATUSES

    @property
    def is_busy_loading(self) -> bool:
        """True while a load is in flight (status ``starting``)."""
        return self._status == STARTING

    @property
    def live_process_count(self) -> int:
        """Number of live ASR_Server processes implied by the status (always 0 or 1).

        By construction this never exceeds one, which is the invariant Property 9 checks.
        """
        return 1 if self._status in _RESIDENT_STATUSES else 0

    # ------------------------------------------------------------------
    # Effective timeout (Requirement 7.2 / Property 14)
    # ------------------------------------------------------------------

    @staticmethod
    def effective_timeout(timeout_s: object) -> int:
        """Return the effective load timeout for a requested value.

        In-range values (``[MIN_TIMEOUT_S, MAX_TIMEOUT_S]``) are used as-is; any
        out-of-range, missing, or non-integer value falls back to ``DEFAULT_TIMEOUT_S``.
        """
        try:
            value = int(timeout_s)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            return DEFAULT_TIMEOUT_S
        if MIN_TIMEOUT_S <= value <= MAX_TIMEOUT_S:
            return value
        return DEFAULT_TIMEOUT_S

    # ------------------------------------------------------------------
    # Load
    # ------------------------------------------------------------------

    def load(self, timeout_s: object = DEFAULT_TIMEOUT_S) -> bool:
        """Request Model_Load.

        Returns ``True`` iff a new subprocess spawn occurred.

        Behaviour:
        * Always cancels any pending Model_Unload first, so a re-trigger during unload
          supersedes the unload (Property 11) and the server is not stopped out from under
          the new session.
        * Records the clamped effective timeout (Property 14).
        * Reuses a ``running`` or ``starting`` server without spawning (Property 9).
        * Spawns from ``stopped`` or ``error`` (``-> starting``) and increments the spawn
          counter.
        * Is a no-op from ``not_installed`` / ``installing`` (nothing can be loaded).
        """
        # A new load always supersedes a pending unload.
        self._cancel_pending_unload()
        self._effective_timeout_s = self.effective_timeout(timeout_s)

        if self._status in _RESIDENT_STATUSES:
            # Reuse the running/starting server — no second process (Property 9).
            return False
        if self._status in _SPAWNABLE_STATUSES:
            self._status = STARTING
            self._spawn_count += 1
            return True
        # not_installed / installing: cannot load; leave status unchanged.
        return False

    def ready(self) -> None:
        """Mark a load complete: ``starting -> running``.

        Represents the ASR_Server passing its health check. No-op from any other status.
        """
        if self._status == STARTING:
            self._status = RUNNING

    def fail(self) -> None:
        """Mark a load failure/timeout: ``starting`` / ``running`` -> ``error``.

        Also cancels any pending unload since the failed session is torn down explicitly.
        """
        if self._status in _RESIDENT_STATUSES:
            self._status = ERROR
        self._cancel_pending_unload()

    # ------------------------------------------------------------------
    # Unload
    # ------------------------------------------------------------------

    def unload(self, delay_ticks: int = 0) -> None:
        """Arm a cancellable Model_Unload.

        If nothing is loaded (status not ``starting`` / ``running``) this is an idempotent
        no-op that leaves the status unchanged and never raises (Property 10).

        Otherwise it arms a pending unload that fires after ``delay_ticks`` calls to
        ``tick()`` (or immediately via ``unload_completes()``). A delay of ``0`` still
        routes through the cancellable timer — it completes on the next ``tick()`` — so a
        same-tick ``load()`` can still cancel it (Property 11).
        """
        if self._status not in _RESIDENT_STATUSES:
            return
        self._unload_pending = True
        self._unload_ticks_remaining = max(0, int(delay_ticks))

    def tick(self) -> bool:
        """Advance the pending-unload timer by one step.

        Returns ``True`` if the unload fired (completed) on this tick. A no-op returning
        ``False`` when no unload is pending.
        """
        if not self._unload_pending:
            return False
        if self._unload_ticks_remaining > 0:
            self._unload_ticks_remaining -= 1
        if self._unload_ticks_remaining <= 0:
            self._complete_unload()
            return True
        return False

    def unload_completes(self) -> None:
        """Complete the Model_Unload now.

        Transitions a resident status (``starting`` / ``running``) to ``stopped``
        (Property 13) and clears any pending-unload timer. If nothing is loaded this only
        clears a stray pending flag and leaves the status unchanged (Property 10).
        """
        if self._status in _RESIDENT_STATUSES:
            self._complete_unload()
        else:
            self._cancel_pending_unload()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _complete_unload(self) -> None:
        self._unload_pending = False
        self._unload_ticks_remaining = 0
        if self._status in _RESIDENT_STATUSES:
            self._status = STOPPED

    def _cancel_pending_unload(self) -> None:
        self._unload_pending = False
        self._unload_ticks_remaining = 0

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return (
            f"LoadLifecycle(status={self._status!r}, spawn_count={self._spawn_count}, "
            f"unload_pending={self._unload_pending}, "
            f"effective_timeout_s={self._effective_timeout_s})"
        )
