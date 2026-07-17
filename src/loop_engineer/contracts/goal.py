"""Goal and Milestone contracts (spec §2, §6.1).

A Goal is compiled before execution. Milestones are release gates with binary
exits, never Team execution units.
"""

from pydantic import BaseModel, Field, field_validator, model_validator


class Milestone(BaseModel):
    """A release gate. Exit is binary: evidence condition met or not."""

    id: str = Field(min_length=1)
    title: str = Field(min_length=1)
    # Machine-checkable condition is finalized in P2; the string is the contract.
    evidence_condition: str = Field(min_length=1)


class Goal(BaseModel):
    id: str = Field(min_length=1)
    title: str = Field(min_length=1)
    measurable_evidence: str = Field(min_length=1)
    scope: list[str] = Field(min_length=1)
    exclusions: list[str] = Field(default_factory=list)
    stop_conditions: list[str] = Field(default_factory=list)
    milestones: list[Milestone] = Field(min_length=1)

    @field_validator("scope")
    @classmethod
    def _scope_nonempty_entries(cls, v: list[str]) -> list[str]:
        if any(not entry.strip() for entry in v):
            raise ValueError("scope entries must be non-empty")
        return v

    @model_validator(mode="after")
    def _unique_milestone_ids(self) -> "Goal":
        ids = [m.id for m in self.milestones]
        if len(ids) != len(set(ids)):
            raise ValueError("milestone ids must be unique")
        return self
