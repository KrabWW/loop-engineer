"""The compiler must prove acyclicity (spec §6.1, §6.2)."""

import pytest
from pydantic import ValidationError

from loop_engineer.contracts.enums import OmxTaskStatus
from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.task import Task, VerificationSpec


def _tid(tid: str, deps: list[str]) -> Task:
    return Task(
        id=tid, owner_domain="omx", status=OmxTaskStatus.PENDING, dependencies=deps,
        allowed_files=[f"src/{tid}.py"], non_goals=[], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
        required_evidence=["commit"], downstream_handoff=[],
    )


def test_self_loop_rejected():
    t = _tid("T1", [])
    with pytest.raises(ValidationError):
        Plan(
            goal_id="G", nodes=[TaskNode(task=t)],
            edges=[DependencyEdge(from_id="T1", to_id="T1")],
        )


def test_three_node_cycle_rejected():
    a, b, c = _tid("A", []), _tid("B", []), _tid("C", [])
    nodes = [TaskNode(task=t) for t in (a, b, c)]
    edges = [
        DependencyEdge(from_id="A", to_id="B"),
        DependencyEdge(from_id="B", to_id="C"),
        DependencyEdge(from_id="C", to_id="A"),
    ]
    with pytest.raises(ValidationError):
        Plan(goal_id="G", nodes=nodes, edges=edges)


def test_diamond_is_acyclic():
    a, b, c, d = _tid("A", []), _tid("B", []), _tid("C", []), _tid("D", [])
    nodes = [TaskNode(task=t) for t in (a, b, c, d)]
    edges = [
        DependencyEdge(from_id="A", to_id="B"),
        DependencyEdge(from_id="A", to_id="C"),
        DependencyEdge(from_id="B", to_id="D"),
        DependencyEdge(from_id="C", to_id="D"),
    ]
    p = Plan(goal_id="G", nodes=nodes, edges=edges)
    assert p.is_acyclic()
    order = p.topological_order()
    assert order[0] == "A" and order[-1] == "D"
