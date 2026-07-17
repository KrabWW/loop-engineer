"""Engine routing heuristic (spec P2b-1 §5)."""

from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task
from loop_engineer.scheduler.models import TaskExecutionMeta

_OMC_MARKERS = ("frontend/", "ui/", "component", "page", "playwright", "browser", "docs/", ".md")
_OMX_MARKERS = ("backend/", "actuator", "migration", "migrations", "durable", "postgres", "db/")


def recommend_engine(task: Task, meta: TaskExecutionMeta | None) -> Provider:
    if meta is not None and meta.engine_hint is not None:
        return meta.engine_hint
    blob = " ".join(task.allowed_files).lower()
    if any(m in blob for m in _OMC_MARKERS):
        return Provider.OMC
    if any(m in blob for m in _OMX_MARKERS):
        return Provider.OMX
    return Provider.OMX
