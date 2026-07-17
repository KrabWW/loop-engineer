"""Goal file input contract (spec P2a §4): a Goal plus the atomic Tasks."""

from pydantic import BaseModel, Field, model_validator

from loop_engineer.contracts.goal import Goal
from loop_engineer.contracts.task import Task


class GoalDefinition(BaseModel):
    goal: Goal
    tasks: list[Task] = Field(min_length=1)

    @model_validator(mode="after")
    def _unique_task_ids(self) -> "GoalDefinition":
        ids = [t.id for t in self.tasks]
        if len(ids) != len(set(ids)):
            raise ValueError("duplicate task ids in goal definition")
        return self
