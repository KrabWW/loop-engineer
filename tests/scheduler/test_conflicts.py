from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.contracts.task_run import TaskBoardEntry, TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.scheduler.conflicts import conflicts_for
from loop_engineer.scheduler.models import ConflictDimension


def _task(tid, deps=None, files=None):
    return Task(
        id=tid, owner_domain="omx", dependencies=deps or [],
        allowed_files=files or [f"src/{tid}.py"], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["t"], working_dir="."), required_evidence=["c"],
    )


def _plan(tasks):
    edges = [DependencyEdge(from_id=d, to_id=t.id) for t in tasks for d in t.dependencies]
    return Plan(goal_id="G", nodes=[TaskNode(task=t) for t in tasks], edges=edges)


def _board(claimed):
    return BoardState(
        run_id="r", plan_digest="sha256:" + "0" * 64,
        tasks={tid: TaskBoardEntry(task_id=tid, status=TaskRunStatus.CLAIMED, provider=Provider.OMX)
               for tid in claimed},
    )


def test_dependency_conflict():
    plan = _plan([_task("T1"), _task("T2", deps=["T1"])])
    board = _board(["T1"])  # T1 active, T2 depends on it
    confs = conflicts_for("T2", plan, board, {})
    assert any(c.dimension == ConflictDimension.DEPENDENCY and c.other == "T1" for c in confs)


def test_allowed_files_conflict():
    plan = _plan([_task("T1", files=["src/a.py"]), _task("T2", files=["src/a.py"])])
    board = _board(["T1"])
    confs = conflicts_for("T2", plan, board, {})
    assert any(c.dimension == ConflictDimension.ALLOWED_FILES for c in confs)


def test_allowed_files_conflict_allowed_when_dependency_ordered():
    plan = _plan([_task("T1", files=["src/a.py"]), _task("T2", deps=["T1"], files=["src/a.py"])])
    board = _board(["T1"])
    confs = conflicts_for("T2", plan, board, {})
    # T2 depends on T1 -> ordered overlap allowed; no ALLOWED_FILES conflict
    assert not any(c.dimension == ConflictDimension.ALLOWED_FILES for c in confs)
