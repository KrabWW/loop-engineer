import pytest
from pydantic import ValidationError

from loop_engineer.compiler.definition import GoalDefinition
from loop_engineer.contracts.goal import Goal, Milestone
from loop_engineer.contracts.task import Task, VerificationSpec


def _goal() -> Goal:
    return Goal(
        id="G1", title="t", measurable_evidence="ok", scope=["x"],
        exclusions=[], stop_conditions=[],
        milestones=[Milestone(id="M", title="m", evidence_condition="c")],
    )


def _task(tid: str, deps: list[str] | None = None) -> Task:
    return Task(
        id=tid, owner_domain="omx", dependencies=deps or [],
        allowed_files=[f"src/{tid}.py"], non_goals=[], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
        required_evidence=["commit"], downstream_handoff=[],
    )


def test_definition_accepts_goal_and_tasks():
    d = GoalDefinition(goal=_goal(), tasks=[_task("T1")])
    assert d.tasks[0].id == "T1"


def test_definition_requires_tasks():
    with pytest.raises(ValidationError):
        GoalDefinition(goal=_goal(), tasks=[])


def test_definition_rejects_duplicate_task_ids():
    with pytest.raises(ValidationError):
        GoalDefinition(goal=_goal(), tasks=[_task("T"), _task("T")])
