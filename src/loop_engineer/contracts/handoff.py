"""Integration and downstream handoff constraints (spec §6.1)."""

from pydantic import BaseModel, Field


class Handoff(BaseModel):
    integration_branch: str = Field(min_length=1)
    integration_worktree: str | None = None
    downstream_task_ids: list[str] = Field(default_factory=list)
    constraints: list[str] = Field(default_factory=list)
