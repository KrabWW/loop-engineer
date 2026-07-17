"""Atomic Task contract (spec §6.1).

A Task document is runtime authority for dependencies, Allowed Files,
acceptance, and verification. Exact `allowed_files` entries are normalized by
the scheduler in P2; here they are frozen as exact strings.
"""

from pydantic import BaseModel, Field, field_validator, model_validator

from loop_engineer.contracts.enums import OmxTaskStatus


class VerificationSpec(BaseModel):
    commands: list[str] = Field(min_length=1)
    working_dir: str = Field(min_length=1)


class Task(BaseModel):
    id: str = Field(min_length=1)
    owner_domain: str = Field(min_length=1)
    status: OmxTaskStatus = OmxTaskStatus.PENDING
    dependencies: list[str] = Field(default_factory=list)
    allowed_files: list[str] = Field(min_length=1)
    non_goals: list[str] = Field(default_factory=list)
    acceptance_criteria: list[str] = Field(min_length=1)
    verification: VerificationSpec
    required_evidence: list[str] = Field(min_length=1)
    downstream_handoff: list[str] = Field(default_factory=list)

    @field_validator("allowed_files")
    @classmethod
    def _allowed_files_nonempty(cls, v: list[str]) -> list[str]:
        if any(not p.strip() for p in v):
            raise ValueError("allowed_files entries must be non-empty")
        return v

    @model_validator(mode="after")
    def _unique_and_self_cycle_free(self) -> "Task":
        if len(self.allowed_files) != len(set(self.allowed_files)):
            raise ValueError("allowed_files must be unique")
        if self.id in self.dependencies:
            raise ValueError("a task cannot depend on itself")
        return self
