import pytest
from pydantic import ValidationError

from loop_engineer.contracts.recovery import RecoveryRecord


def _minimal_record(**overrides) -> dict:
    base = dict(
        repo_identity="repo-1",
        run_id="run-1",
        task_id="T1",
        lane="hybrid",
        protocol_version=1,
        base_commit="abc123",
        integration_branch="task/T1",
        integration_worktree="/tmp/wt",
        adapter_exec_branch="exec/T1",
        adapter_exec_worktree="/tmp/exec",
        omx_team_name="team-1",
        leader_session="sess-1",
        worker_identity="omx-worker-1",
        claim_token_digest="sha256:" + "0" * 64,
        lease_generation=0,
        claude_leader_pane="claude-pane-1",
        claude_leader_pid=4321,
        claude_leader_start_time="2026-01-01T00:00:00Z",
        claude_leader_executable="claude",
        omc_state_root="/tmp/omc",
        omc_team_name="omc-team-1",
        last_command_revision=1,
        last_event_sequence=1,
        journal_checksum="sha256:" + "2" * 64,
        current_phase="omc_executing",
        cleanup_phase=None,
        writer_fencing_generation=0,
        shutdown_acks=[],
    )
    base.update(overrides)
    return base


def test_recovery_record_accepts_full_coordinate_set():
    r = RecoveryRecord(**_minimal_record())
    assert r.task_id == "T1"


def test_recovery_record_rejects_missing_field():
    bad = _minimal_record()
    bad.pop("journal_checksum")
    with pytest.raises(ValidationError):
        RecoveryRecord(**bad)


def test_recovery_record_protocol_version_positive():
    with pytest.raises(ValidationError):
        RecoveryRecord(**_minimal_record(protocol_version=0))
