"""Task eligibility + protected-zone hard block (spec P2b-1 §3, §4.F)."""

from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.task_run import TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.runtime.scope import overlaps
from loop_engineer.scheduler.models import Conflict, ConflictDimension, PlannerConfig


def eligible_tasks(
    plan: Plan, board: BoardState, config: PlannerConfig
) -> tuple[set[str], list[Conflict]]:
    """Return (eligible task_ids, task-level blocked conflicts).

    Eligible = not DONE, derived-ready (deps DONE on board), not CLAIMED, not
    protected-zone. Protected-zone Tasks are returned in `blocked`.
    """
    eligible: set[str] = set()
    blocked: list[Conflict] = []
    for node in plan.nodes:
        tid = node.task.id
        entry = board.tasks.get(tid)
        if entry is not None and entry.status == TaskRunStatus.DONE:
            continue
        if overlaps(node.task.allowed_files, config.protected_paths):
            blocked.append(Conflict(
                candidate=tid, other=None, dimension=ConflictDimension.PROTECTED,
                reason=f"allowed_files intersect protected paths {config.protected_paths}",
            ))
            continue
        deps_done = all(
            (d in board.tasks) and (board.tasks[d].status == TaskRunStatus.DONE)
            for d in node.task.dependencies
        )
        if not deps_done:
            continue
        if entry is not None and entry.status == TaskRunStatus.CLAIMED:
            continue
        eligible.add(tid)
    return eligible, blocked
