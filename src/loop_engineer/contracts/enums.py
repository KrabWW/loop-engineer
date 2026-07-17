"""Frozen enums for exit codes and the Hybrid lifecycle (spec §4, §7.3, §7.4).

Adding a value here is a wire-format change: bump SCHEMA_VERSION in every
envelope that carries one of these enums and regenerate schemas/.
"""

from enum import IntEnum, StrEnum


class ExitCode(IntEnum):
    """Stable process exit classes (spec §4)."""

    OK = 0                       # requested state reached / idempotent confirmation
    INVALID_INPUT = 2            # bad input, schema, plan, dependency, version
    OWNERSHIP_AMBIGUITY = 3      # lease/leader/team/worktree/recovery ambiguity
    WORKER_FAILURE = 4           # runtime or worker terminal failure
    VERIFICATION_SCOPE_FAILURE = 5  # verification, scope, provenance, protected path
    GIT_INTEGRATION_CONFLICT = 6 # rebase conflict or main drift
    PARTIAL_COMPLETION = 7       # preserved for same-command recovery


class OmxTaskStatus(StrEnum):
    """OMX worker Task status column (spec §7.3)."""

    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class CommonState(StrEnum):
    """Sole normative common-state lifecycle (spec §7.3)."""

    READY = "ready"
    CLAIMED = "claimed"
    OMC_STARTING = "omc_starting"
    OMC_EXECUTING = "omc_executing"
    BLOCKED = "blocked"
    READY_FOR_OMX_REVIEW = "ready_for_omx_review"
    OMX_REVIEWING = "omx_reviewing"
    CORRECTION_REQUESTED = "correction_requested"
    WRITER_QUIESCING = "writer_quiescing"
    PROMOTING = "promoting"
    POST_PROMOTION_REVIEW = "post_promotion_review"
    OMX_FIXING = "omx_fixing"
    OMX_VERIFIED = "omx_verified"
    FINISHING = "finishing"
    MERGED = "merged"
    POST_MERGE_VERIFICATION_FAILED = "post_merge_verification_failed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    INTEGRATION_CANCELLED = "integration_cancelled"


class ExecutorState(StrEnum):
    """Adapter executor lifecycle (spec §7.4)."""

    ADAPTER_IDLE = "adapter_idle"
    ADAPTER_ACTIVE = "adapter_active"
    ADAPTER_STOPPING = "adapter_stopping"
    ADAPTER_SHUTDOWN = "adapter_shutdown"


class CommandType(StrEnum):
    """Leader-to-adapter command types (spec §7.1)."""

    START_TASK = "START_TASK"
    CONTINUE_TASK = "CONTINUE_TASK"
    REQUEST_FIX = "REQUEST_FIX"
    REQUEST_EVIDENCE = "REQUEST_EVIDENCE"
    RELEASE_FOR_OMX_FIX = "RELEASE_FOR_OMX_FIX"
    CANCEL_TASK = "CANCEL_TASK"
    SHUTDOWN_EXECUTOR = "SHUTDOWN_EXECUTOR"


class EventType(StrEnum):
    """Adapter-to-leader event types (spec §7.2)."""

    ACKNOWLEDGED = "ACKNOWLEDGED"
    STARTED = "STARTED"
    PROGRESS = "PROGRESS"
    HEARTBEAT = "HEARTBEAT"
    BLOCKED = "BLOCKED"
    READY_FOR_REVIEW = "READY_FOR_REVIEW"
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"
    SHUTDOWN_ACK = "SHUTDOWN_ACK"
