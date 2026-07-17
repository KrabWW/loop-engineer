import pytest
from pydantic import ValidationError

from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task_run import TaskBoardEntry, TaskRunStatus


def test_provider_values():
    assert {p.value for p in Provider} == {"omx", "omc"}


def test_task_run_status_values():
    assert {s.value for s in TaskRunStatus} == {
        "pending", "claimed", "released", "done", "failed",
    }


def test_entry_defaults_to_pending():
    e = TaskBoardEntry(task_id="T1")
    assert e.status == TaskRunStatus.PENDING
    assert e.attempt_id == 1
    assert e.claim is None and e.provider is None


def test_entry_rejects_empty_task_id():
    with pytest.raises(ValidationError):
        TaskBoardEntry(task_id="")


def test_entry_rejects_non_positive_attempt():
    with pytest.raises(ValidationError):
        TaskBoardEntry(task_id="T1", attempt_id=0)
