"""Board-level run status and entry (spec P2a §4).

Deliberately separate from the §7.3 CommonState Hybrid lifecycle: P2a only
coordinates claiming, not Hybrid-phase transitions.
"""

from enum import StrEnum

from pydantic import BaseModel, Field

from loop_engineer.contracts.claim import Claim
from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.provider import Provider


class TaskRunStatus(StrEnum):
    PENDING = "pending"
    CLAIMED = "claimed"
    RELEASED = "released"
    DONE = "done"
    FAILED = "failed"


class TaskBoardEntry(BaseModel):
    task_id: str = Field(min_length=1)
    status: TaskRunStatus = TaskRunStatus.PENDING
    claim: Claim | None = None
    lease: Lease | None = None
    provider: Provider | None = None
    attempt_id: int = Field(default=1, ge=1)
