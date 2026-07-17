import pytest

from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.runtime.board import BoardStore


def _plan(task_files: dict[str, list[str]], deps: dict[str, list[str]] | None = None) -> Plan:
    deps = deps or {}
    nodes = []
    for tid, files in task_files.items():
        nodes.append(TaskNode(task=Task(
            id=tid, owner_domain="omx", dependencies=deps.get(tid, []),
            allowed_files=files, acceptance_criteria=["x"],
            verification=VerificationSpec(commands=["t"], working_dir="."),
            required_evidence=["c"],
        )))
    return Plan(goal_id="G1", nodes=nodes, edges=[
        DependencyEdge(from_id=d, to_id=tid) for tid, ds in deps.items() for d in ds
    ])


def test_from_plan_initializes_all_pending(tmp_path):
    plan = _plan({"T1": ["src/a.py"], "T2": ["src/b.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    state = store.load_state()
    assert set(state.tasks) == {"T1", "T2"}
    assert all(e.status.value == "pending" for e in state.tasks.values())


def test_open_existing_board_roundtrips(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    s1 = BoardStore.from_plan(plan, tmp_path)
    s2 = BoardStore.open(s1.dir)
    assert set(s2.load_state().tasks) == {"T1"}


def test_open_missing_board_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        BoardStore.open(tmp_path / "nope")
