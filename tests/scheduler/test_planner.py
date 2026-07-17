from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.contracts.task_run import TaskBoardEntry, TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.scheduler.models import PlannerConfig
from loop_engineer.scheduler.planner import plan_launch


def _task(tid, files):
    return Task(
        id=tid, owner_domain="omx", allowed_files=files, acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["t"], working_dir="."), required_evidence=["c"],
    )


def _plan(tasks):
    edges = [DependencyEdge(from_id=d, to_id=t.id) for t in tasks for d in t.dependencies]
    return Plan(goal_id="G", nodes=[TaskNode(task=t) for t in tasks], edges=edges)


def _board(claimed_with_provider, pending=None):
    tasks = {tid: TaskBoardEntry(task_id=tid, status=TaskRunStatus.CLAIMED, provider=prov)
             for tid, prov in claimed_with_provider.items()}
    for tid in pending or []:
        tasks[tid] = TaskBoardEntry(task_id=tid)
    return BoardState(run_id="r", plan_digest="sha256:" + "0" * 64, tasks=tasks)


def test_launches_up_to_global_cap():
    plan = _plan([_task(f"T{i}", [f"src/{i}.py"]) for i in range(5)])
    board = _board({}, pending=["T0", "T1", "T2", "T3", "T4"])
    lp = plan_launch(plan, board, {}, PlannerConfig())
    assert len(lp.launch) == 3  # global_max=3
    assert lp.remaining_global == 3 and lp.active_omx + lp.active_omc == 0


def test_global_cap_is_combined_not_per_engine():
    plan = _plan([_task(f"T{i}", [f"frontend/{i}.py"]) for i in range(5)])
    board = _board({"X": Provider.OMC, "Y": Provider.OMC}, pending=["T0", "T1", "T2"])
    lp = plan_launch(plan, board, {}, PlannerConfig())
    # active_total=2, global_max=3 -> only 1 more launch despite omc_max=3
    assert len(lp.launch) == 1


def test_overlapping_task_skipped():
    plan = _plan([_task("T1", ["src/a.py"]), _task("T2", ["src/a.py"])])
    board = _board({"T1": Provider.OMX}, pending=["T2"])
    lp = plan_launch(plan, board, {}, PlannerConfig())
    assert [item.task_id for item in lp.launch] == []
    assert any(c.candidate == "T2" for c in lp.skipped)


def test_burst_denied_by_default():
    plan = _plan([_task(f"T{i}", [f"src/{i}.py"]) for i in range(5)])
    board = _board({}, pending=["T0", "T1", "T2", "T3"])
    lp = plan_launch(plan, board, {}, PlannerConfig())  # burst_eligible=False
    assert len(lp.launch) == 3 and lp.burst is False


def test_burst_allowed_when_eligible_and_clean():
    tasks = [_task("F0", ["frontend/0.py"]), _task("F1", ["frontend/1.py"]),
             _task("B0", ["backend/0.py"]), _task("B1", ["backend/1.py"])]
    plan = _plan(tasks)
    board = _board({}, pending=["F0", "F1", "B0", "B1"])
    cfg = PlannerConfig(burst_eligible=True)
    lp = plan_launch(plan, board, {}, cfg)
    assert len(lp.launch) == 4 and lp.burst is True
