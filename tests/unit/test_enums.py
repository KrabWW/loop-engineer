from loop_engineer.contracts.enums import (
    CommandType,
    CommonState,
    EventType,
    ExecutorState,
    ExitCode,
    OmxTaskStatus,
)


def test_exit_code_values_match_spec_classes():
    assert ExitCode.OK == 0
    assert ExitCode.INVALID_INPUT == 2
    assert ExitCode.OWNERSHIP_AMBIGUITY == 3
    assert ExitCode.WORKER_FAILURE == 4
    assert ExitCode.VERIFICATION_SCOPE_FAILURE == 5
    assert ExitCode.GIT_INTEGRATION_CONFLICT == 6
    assert ExitCode.PARTIAL_COMPLETION == 7


def test_exit_code_excludes_one_and_eight_plus():
    values = {int(c) for c in ExitCode}
    assert 1 not in values
    assert all(v <= 7 for v in values)


def test_command_types_match_protocol_section_7_1():
    expected = {
        "START_TASK", "CONTINUE_TASK", "REQUEST_FIX", "REQUEST_EVIDENCE",
        "RELEASE_FOR_OMX_FIX", "CANCEL_TASK", "SHUTDOWN_EXECUTOR",
    }
    assert {t.value for t in CommandType} == expected


def test_event_types_match_protocol_section_7_2():
    expected = {
        "ACKNOWLEDGED", "STARTED", "PROGRESS", "HEARTBEAT", "BLOCKED",
        "READY_FOR_REVIEW", "FAILED", "CANCELLED", "SHUTDOWN_ACK",
    }
    assert {t.value for t in EventType} == expected


def test_common_state_covers_full_lifecycle_table():
    required = [
        "ready", "claimed", "omc_starting", "omc_executing", "blocked",
        "ready_for_omx_review", "omx_reviewing", "correction_requested",
        "writer_quiescing", "promoting", "post_promotion_review", "omx_fixing",
        "omx_verified", "finishing", "merged", "post_merge_verification_failed",
        "failed", "cancelled", "integration_cancelled",
    ]
    present = {s.value for s in CommonState}
    missing = set(required) - present
    assert not missing, f"lifecycle table missing states: {missing}"


def test_executor_states_match_section_7_4():
    assert {s.value for s in ExecutorState} == {
        "adapter_idle", "adapter_active", "adapter_stopping", "adapter_shutdown",
    }


def test_omx_task_status_values():
    assert {s.value for s in OmxTaskStatus} == {
        "pending", "in_progress", "completed", "failed", "cancelled",
    }
