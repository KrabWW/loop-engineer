from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.scheduler.engine import recommend_engine
from loop_engineer.scheduler.models import TaskExecutionMeta


def _task(tid, files):
    return Task(
        id=tid, owner_domain="omx", allowed_files=files, acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["t"], working_dir="."), required_evidence=["c"],
    )


def test_frontend_routes_to_omc():
    assert recommend_engine(_task("T", ["frontend/src/App.tsx"]), None) == Provider.OMC


def test_backend_migration_routes_to_omx():
    assert recommend_engine(_task("T", ["backend/migrations/0001.py"]), None) == Provider.OMX


def test_engine_hint_overrides():
    t = _task("T", ["backend/x.py"])
    meta = TaskExecutionMeta(task_id="T", engine_hint=Provider.OMC)
    assert recommend_engine(t, meta) == Provider.OMC


def test_default_when_unclear():
    assert recommend_engine(_task("T", ["src/x.py"]), None) == Provider.OMX
