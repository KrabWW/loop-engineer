"""Versioned recovery coordinate record (spec §7.5).

Stored in the Git common directory, outside ordinary commits. Every field here
maps to a bullet in §7.5; do not drop one without updating the spec.
"""

from pydantic import BaseModel, Field


class RecoveryRecord(BaseModel):
    # identity
    repo_identity: str = Field(min_length=1)
    run_id: str = Field(min_length=1)
    task_id: str = Field(min_length=1)
    lane: str = Field(min_length=1)
    protocol_version: int = Field(ge=1)
    # git coordinates
    base_commit: str = Field(min_length=1)
    integration_branch: str = Field(min_length=1)
    integration_worktree: str = Field(min_length=1)
    adapter_exec_branch: str = Field(min_length=1)
    adapter_exec_worktree: str = Field(min_length=1)
    pinned_result_commit: str | None = None
    review_base_commit: str | None = None
    # omx coordinates
    omx_team_name: str = Field(min_length=1)
    leader_session: str = Field(min_length=1)
    leader_pane: str | None = None
    worker_identity: str = Field(min_length=1)
    omx_task_id: str | None = None
    claim_token_digest: str = Field(min_length=1)
    lease_generation: int = Field(ge=0)
    lease_expiry: str | None = None
    # claude leader coordinates
    claude_leader_session: str | None = None
    claude_leader_pane: str = Field(min_length=1)
    claude_leader_pid: int = Field(ge=1)
    claude_leader_start_time: str = Field(min_length=1)
    claude_leader_executable: str = Field(min_length=1)
    # omc coordinates
    omc_state_root: str = Field(min_length=1)
    omc_team_name: str = Field(min_length=1)
    omc_worker_identities: list[str] = Field(default_factory=list)
    provider_task_ids: list[str] = Field(default_factory=list)
    last_summary_revision: int | None = None
    # journal coordinates
    last_command_revision: int = Field(ge=1)
    last_event_sequence: int = Field(ge=1)
    journal_checksum: str = Field(min_length=1)
    # phase coordinates
    current_phase: str = Field(min_length=1)
    cleanup_phase: str | None = None
    # fencing
    writer_fencing_generation: int = Field(ge=0)
    shutdown_acks: list[str] = Field(default_factory=list)
