"""Scheduler config, per-task execution metadata, and planner output models (spec P2b-1 §2/§6)."""

from enum import StrEnum

from pydantic import BaseModel, Field

from loop_engineer.contracts.provider import Provider


class TaskExecutionMeta(BaseModel):
    """Optional per-Task metadata for conflict dimensions P2a's Task does not carry.

    This is a separate planner input; it is NOT added to GoalDefinition.
    """

    task_id: str = Field(min_length=1)
    migration_dir: str | None = None
    migration_after: list[str] = Field(default_factory=list)
    ports: list[int] = Field(default_factory=list)
    db_name: str | None = None
    browser_profile: str | None = None
    engine_hint: Provider | None = None


class CapacityConfig(BaseModel):
    omx_max: int = 3
    omc_max: int = 3
    global_max: int = 3  # combined OMX+OMC cap, not omx_max + omc_max
    finish_max: int = 1
    burst_max: int = 4


class PlannerConfig(BaseModel):
    capacity: CapacityConfig = Field(default_factory=CapacityConfig)
    protected_paths: list[str] = Field(default_factory=lambda: ["refer/"])
    target_omc: int = 2
    target_omx: int = 1
    # Burst preconditions the caller (P2b-3 rolling loop) must certify:
    # main clean, no finisher, no recovery. Default False = never burst.
    burst_eligible: bool = False


class ConflictDimension(StrEnum):
    DEPENDENCY = "dependency"
    ALLOWED_FILES = "allowed_files"
    MIGRATION = "migration"
    RESOURCE = "resource"
    LIFECYCLE = "lifecycle"
    PROTECTED = "protected"


class Conflict(BaseModel):
    candidate: str
    other: str | None = None  # None for task-level (protected) blocks
    dimension: ConflictDimension
    reason: str


class Launch(BaseModel):
    task_id: str
    provider: Provider


class LaunchPlan(BaseModel):
    launch: list[Launch]
    skipped: list[Conflict]       # eligible but conflicts with an active task
    blocked: list[Conflict]       # task-level hard block (protected zone)
    active_omx: int
    active_omc: int
    remaining_global: int
    burst: bool
