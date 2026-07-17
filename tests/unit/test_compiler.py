import pytest
from pydantic import ValidationError

from loop_engineer.compiler.compiler import compile_goal
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


def test_compile_builds_acyclic_plan():
    d = GoalDefinition(goal=_goal(), tasks=[_task("T1"), _task("T2", ["T1"])])
    plan = compile_goal(d)
    assert plan.goal_id == "G1"
    order = plan.topological_order()
    assert order.index("T1") < order.index("T2")


def test_compile_rejects_cycle_via_plan_validation():
    d = GoalDefinition(
        goal=_goal(),
        tasks=[_task("T1", ["T2"]), _task("T2", ["T1"])],
    )
    with pytest.raises(ValidationError):
        compile_goal(d)
