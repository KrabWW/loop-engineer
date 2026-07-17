from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.contracts.task_run import TaskBoardEntry, TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.scheduler.conflicts import conflicts_for
from loop_engineer.scheduler.models import ConflictDimension, TaskExecutionMeta


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


def test_migration_same_dir_conflict():
    plan = _plan([_task("T1"), _task("T2")])
    board = _board(["T1"])
    meta = {"T2": TaskExecutionMeta(task_id="T2", migration_dir="migrations/versions"),
            "T1": TaskExecutionMeta(task_id="T1", migration_dir="migrations/versions")}
    confs = conflicts_for("T2", plan, board, meta)
    assert any(c.dimension == ConflictDimension.MIGRATION for c in confs)


def test_resource_port_conflict():
    plan = _plan([_task("T1"), _task("T2")])
    board = _board(["T1"])
    meta = {"T1": TaskExecutionMeta(task_id="T1", ports=[8000]),
            "T2": TaskExecutionMeta(task_id="T2", ports=[8000])}
    confs = conflicts_for("T2", plan, board, meta)
    assert any(c.dimension == ConflictDimension.RESOURCE for c in confs)


def test_resource_db_conflict():
    plan = _plan([_task("T1"), _task("T2")])
    board = _board(["T1"])
    meta = {"T1": TaskExecutionMeta(task_id="T1", db_name="app"),
            "T2": TaskExecutionMeta(task_id="T2", db_name="app")}
    confs = conflicts_for("T2", plan, board, meta)
    assert any(c.dimension == ConflictDimension.RESOURCE for c in confs)


def test_resource_browser_profile_conflict():
    plan = _plan([_task("T1"), _task("T2")])
    board = _board(["T1"])
    meta = {"T1": TaskExecutionMeta(task_id="T1", browser_profile="p"),
            "T2": TaskExecutionMeta(task_id="T2", browser_profile="p")}
    confs = conflicts_for("T2", plan, board, meta)
    assert any(c.dimension == ConflictDimension.RESOURCE for c in confs)


def test_no_conflict_disjoint_meta():
    plan = _plan([_task("T1", files=["a.py"]), _task("T2", files=["b.py"])])
    board = _board(["T1"])
    meta = {"T1": TaskExecutionMeta(task_id="T1", ports=[8000], db_name="a"),
            "T2": TaskExecutionMeta(task_id="T2", ports=[9000], db_name="b")}
    assert conflicts_for("T2", plan, board, meta) == []
