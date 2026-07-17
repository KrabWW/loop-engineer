import pytest
from pydantic import ValidationError

from loop_engineer.contracts.enums import OmxTaskStatus
from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.task import Task, VerificationSpec


def _task(tid: str, deps: list[str] | None = None) -> Task:
    return Task(
        id=tid, owner_domain="omx", status=OmxTaskStatus.PENDING,
        dependencies=deps or [], allowed_files=[f"src/{tid}.py"],
        non_goals=[], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
        required_evidence=["commit"], downstream_handoff=[],
    )


def test_plan_accepts_acyclic_dag():
    t1 = _task("T1")
    t2 = _task("T2", deps=["T1"])
    nodes = [TaskNode(task=t) for t in (t1, t2)]
    edges = [DependencyEdge(from_id="T1", to_id="T2")]
    p = Plan(goal_id="G1", nodes=nodes, edges=edges)
    assert p.is_acyclic() is True


def test_plan_rejects_cycle_at_construction():
    t1 = _task("T1", deps=["T2"])
    t2 = _task("T2", deps=["T1"])
    nodes = [TaskNode(task=t) for t in (t1, t2)]
    edges = [DependencyEdge(from_id="T1", to_id="T2"), DependencyEdge(from_id="T2", to_id="T1")]
    with pytest.raises(ValidationError):
        Plan(goal_id="G1", nodes=nodes, edges=edges)


def test_plan_rejects_edge_to_unknown_node():
    t1 = _task("T1")
    with pytest.raises(ValidationError):
        Plan(
            goal_id="G1",
            nodes=[TaskNode(task=t1)],
            edges=[DependencyEdge(from_id="T1", to_id="NOPE")],
        )


def test_plan_rejects_duplicate_node_ids():
    t1 = _task("T1")
    with pytest.raises(ValidationError):
        Plan(goal_id="G1", nodes=[TaskNode(task=t1), TaskNode(task=t1)], edges=[])


def test_topological_order_respects_dependencies():
    t1, t2, t3 = _task("T1"), _task("T2", deps=["T1"]), _task("T3", deps=["T2"])
    nodes = [TaskNode(task=t) for t in (t3, t2, t1)]  # deliberately out of order
    edges = [DependencyEdge(from_id="T1", to_id="T2"), DependencyEdge(from_id="T2", to_id="T3")]
    p = Plan(goal_id="G1", nodes=nodes, edges=edges)
    order = p.topological_order()
    assert order.index("T1") < order.index("T2") < order.index("T3")
