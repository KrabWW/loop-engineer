"""Pairwise conflict detection vs active (CLAIMED) Tasks (spec P2b-1 §4)."""

from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.task_run import TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.runtime.scope import overlaps
from loop_engineer.scheduler.models import Conflict, ConflictDimension, TaskExecutionMeta


def _task_files(plan: Plan, task_id: str) -> list[str]:
    for n in plan.nodes:
        if n.task.id == task_id:
            return list(n.task.allowed_files)
    return []


def _ancestors_in_plan(plan: Plan, task_id: str) -> set[str]:
    direct = {n.task.id: set(n.task.dependencies) for n in plan.nodes}
    seen: set[str] = set()
    stack = list(direct.get(task_id, set()))
    while stack:
        d = stack.pop()
        if d in seen:
            continue
        seen.add(d)
        stack.extend(direct.get(d, set()))
    return seen


def conflicts_for(
    candidate_id: str,
    plan: Plan,
    board: BoardState,
    meta_map: dict[str, TaskExecutionMeta],
) -> list[Conflict]:
    """Conflicts between candidate and every CLAIMED Task (dims A-E)."""
    out: list[Conflict] = []
    candidate_node = next((n for n in plan.nodes if n.task.id == candidate_id), None)
    if candidate_node is None:
        return out
    candidate = candidate_node.task
    ancestors = _ancestors_in_plan(plan, candidate_id)
    for other_id, entry in board.tasks.items():
        if other_id == candidate_id or entry.status != TaskRunStatus.CLAIMED:
            continue
        ordered = other_id in ancestors  # candidate is downstream of other
        # A. dependency
        other_deps = next(
            (set(n.task.dependencies) for n in plan.nodes if n.task.id == other_id), set()
        )
        if other_id in candidate.dependencies or candidate_id in other_deps:
            out.append(Conflict(
                candidate=candidate_id, other=other_id, dimension=ConflictDimension.DEPENDENCY,
                reason=f"{candidate_id} and {other_id} are dependency-coupled",
            ))
            continue
        # B. allowed files (skip if dependency-ordered)
        if not ordered and overlaps(candidate.allowed_files, _task_files(plan, other_id)):
            out.append(Conflict(
                candidate=candidate_id, other=other_id, dimension=ConflictDimension.ALLOWED_FILES,
                reason="allowed_files overlap",
            ))
        cmeta = meta_map.get(candidate_id)
        ometa = meta_map.get(other_id)
        # C. migration
        if cmeta and ometa and cmeta.migration_dir and cmeta.migration_dir == ometa.migration_dir:
            out.append(Conflict(
                candidate=candidate_id, other=other_id,
                dimension=ConflictDimension.MIGRATION,
                reason=f"shared migration_dir {cmeta.migration_dir}",
            ))
        elif cmeta and ometa and (set(cmeta.migration_after) & set(ometa.migration_after)):
            out.append(Conflict(
                candidate=candidate_id, other=other_id,
                dimension=ConflictDimension.MIGRATION,
                reason="shared migration_after precursor",
            ))
        # D. resource
        if cmeta and ometa:
            if set(cmeta.ports) & set(ometa.ports):
                out.append(Conflict(
                    candidate=candidate_id, other=other_id,
                    dimension=ConflictDimension.RESOURCE, reason="port clash",
                ))
            if cmeta.db_name and cmeta.db_name == ometa.db_name:
                out.append(Conflict(
                    candidate=candidate_id, other=other_id,
                    dimension=ConflictDimension.RESOURCE,
                    reason=f"exclusive db {cmeta.db_name}",
                ))
            if cmeta.browser_profile and cmeta.browser_profile == ometa.browser_profile:
                out.append(Conflict(
                    candidate=candidate_id, other=other_id,
                    dimension=ConflictDimension.RESOURCE,
                    reason=f"exclusive browser_profile {cmeta.browser_profile}",
                ))
    return out
