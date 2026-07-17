"""Leader-to-adapter command envelope (spec §7.1)."""

from pydantic import BaseModel, Field, field_validator

from loop_engineer.contracts.enums import CommandType, CommonState

_SCOPE_HASH_RE = r"^sha256:[0-9a-f]{64}$"


class CommandEnvelope(BaseModel):
    protocol_version: int = Field(ge=1)
    run_id: str = Field(min_length=1)
    task_id: str = Field(min_length=1)
    omx_team_name: str = Field(min_length=1)
    worker_identity: str = Field(min_length=1)
    command_id: str = Field(min_length=1)
    causation_id: str | None = None
    command_revision: int = Field(ge=1)  # monotonic within the Task run
    expected_task_state: CommonState
    claim_generation: int = Field(ge=0)
    lease_generation: int = Field(ge=0)
    command_type: CommandType
    instruction: str = Field(min_length=1)
    allowed_file_scope_hash: str
    evidence_requirements: list[str] = Field(min_length=1)
    verification_requirements: list[str] = Field(min_length=1)
    deadline: str | None = None
    cancellation_policy: str | None = None

    @field_validator("allowed_file_scope_hash")
    @classmethod
    def _scope_hash_shape(cls, v: str) -> str:
        import re

        if not re.match(_SCOPE_HASH_RE, v):
            raise ValueError("allowed_file_scope_hash must be 'sha256:<64 hex>'")
        return v
