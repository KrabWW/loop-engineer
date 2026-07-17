"""Capacity-aware launch planning (spec P2b-1 §6)."""

from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task_run import TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.scheduler.conflicts import conflicts_for
from loop_engineer.scheduler.eligibility import eligible_tasks
from loop_engineer.scheduler.engine import recommend_engine
from loop_engineer.scheduler.models import Launch, LaunchPlan, PlannerConfig, TaskExecutionMeta


def plan_launch(
    plan: Plan,
    board: BoardState,
    meta_map: dict[str, TaskExecutionMeta],
    config: PlannerConfig,
) -> LaunchPlan:
    eligible, blocked = eligible_tasks(plan, board, config)
    active = {tid: e for tid, e in board.tasks.items() if e.status == TaskRunStatus.CLAIMED}
    active_omx = sum(1 for e in active.values() if e.provider == Provider.OMX)
    active_omc = sum(1 for e in active.values() if e.provider == Provider.OMC)
    active_total = len(active)

    skipped = []
    clean_candidates = []
    for tid in eligible:
        confs = conflicts_for(tid, plan, board, meta_map)
        if confs:
            skipped.extend(confs)
        else:
            clean_candidates.append(tid)

    cap = config.capacity
    base_remaining = max(0, cap.global_max - active_total)
    can_burst = config.burst_eligible and len(clean_candidates) > base_remaining
    max_launch = max(0, cap.burst_max - active_total) if can_burst else base_remaining

    chosen = clean_candidates[:max_launch]
    launch: list[Launch] = []
    for tid in chosen:
        node = next(n for n in plan.nodes if n.task.id == tid)
        launch.append(Launch(task_id=tid, provider=recommend_engine(node.task, meta_map.get(tid))))

    launch = _trim_per_engine(launch, active_omx, active_omc, cap)

    return LaunchPlan(
        launch=launch,
        skipped=skipped,
        blocked=blocked,
        active_omx=active_omx,
        active_omc=active_omc,
        remaining_global=base_remaining,
        burst=can_burst and len(launch) > base_remaining,
    )


def _trim_per_engine(
    launch: list[Launch], active_omx: int, active_omc: int, cap
) -> list[Launch]:
    out: list[Launch] = []
    omx = active_omx
    omc = active_omc
    for item in launch:
        if item.provider == Provider.OMX:
            if omx < cap.omx_max:
                out.append(item)
                omx += 1
        else:
            if omc < cap.omc_max:
                out.append(item)
                omc += 1
    return out
