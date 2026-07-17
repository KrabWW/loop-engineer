from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.contracts.task_run import TaskBoardEntry, TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.scheduler.eligibility import eligible_tasks
from loop_engineer.scheduler.models import ConflictDimension, PlannerConfig


def _task(tid, deps=None, files=None):
    return Task(
        id=tid, owner_domain="omx", dependencies=deps or [],
        allowed_files=files or [f"src/{tid}.py"], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["t"], working_dir="."), required_evidence=["c"],
    )


def _plan(tasks):
    edges = [DependencyEdge(from_id=dep, to_id=t.id) for t in tasks for dep in t.dependencies]
    return Plan(goal_id="G", nodes=[TaskNode(task=t) for t in tasks], edges=edges)


def _board(statuses):
    return BoardState(
        run_id="r", plan_digest="sha256:" + "0" * 64,
        tasks={tid: TaskBoardEntry(task_id=tid, status=st) for tid, st in statuses.items()},
    )


def test_pending_with_done_deps_is_eligible():
    plan = _plan([_task("T1"), _task("T2", deps=["T1"])])
    board = _board({"T1": TaskRunStatus.DONE, "T2": TaskRunStatus.PENDING})
    eligible, blocked = eligible_tasks(plan, board, PlannerConfig())
    assert eligible == {"T2"} and blocked == []


def test_dep_done_only_on_branch_not_eligible():
    plan = _plan([_task("T1"), _task("T2", deps=["T1"])])
    board = _board({"T1": TaskRunStatus.PENDING, "T2": TaskRunStatus.PENDING})
    eligible, _ = eligible_tasks(plan, board, PlannerConfig())
    assert eligible == {"T1"}


def test_claimed_and_done_excluded():
    plan = _plan([_task("T1"), _task("T2"), _task("T3")])
    board = _board({
        "T1": TaskRunStatus.CLAIMED, "T2": TaskRunStatus.DONE, "T3": TaskRunStatus.PENDING,
    })
    eligible, _ = eligible_tasks(plan, board, PlannerConfig())
    assert eligible == {"T3"}


def test_protected_zone_blocked():
    plan = _plan([_task("T1", files=["refer/x.md"]), _task("T2", files=["src/a.py"])])
    board = _board({"T1": TaskRunStatus.PENDING, "T2": TaskRunStatus.PENDING})
    eligible, blocked = eligible_tasks(plan, board, PlannerConfig())
    assert eligible == {"T2"}
    assert [b.candidate for b in blocked] == ["T1"]
    assert blocked[0].dimension == ConflictDimension.PROTECTED
