import pytest
from pydantic import ValidationError

from loop_engineer.contracts.enums import OmxTaskStatus
from loop_engineer.contracts.task import Task, VerificationSpec


def test_verification_spec_requires_commands_and_cwd():
    v = VerificationSpec(commands=["pytest -q"], working_dir=".")
    assert v.commands
    with pytest.raises(ValidationError):
        VerificationSpec(commands=[], working_dir=".")


def test_task_authoritative_shape():
    t = Task(
        id="T1",
        owner_domain="omx",
        status=OmxTaskStatus.PENDING,
        dependencies=[],
        allowed_files=["src/a.py", "tests/test_a.py"],
        non_goals=["touching main"],
        acceptance_criteria=["a.py exports foo"],
        verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
        required_evidence=["commit", "test_run"],
        downstream_handoff=["T2"],
    )
    assert t.allowed_files == ["src/a.py", "tests/test_a.py"]


def test_task_rejects_empty_allowed_files():
    with pytest.raises(ValidationError):
        Task(
            id="T", owner_domain="omx", status=OmxTaskStatus.PENDING,
            dependencies=[], allowed_files=[], non_goals=[],
            acceptance_criteria=["x"],
            verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
            required_evidence=["commit"], downstream_handoff=[],
        )


def test_task_rejects_duplicate_allowed_files():
    with pytest.raises(ValidationError):
        Task(
            id="T", owner_domain="omx", status=OmxTaskStatus.PENDING,
            dependencies=[], allowed_files=["src/a.py", "src/a.py"],
            non_goals=[], acceptance_criteria=["x"],
            verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
            required_evidence=["commit"], downstream_handoff=[],
        )


def test_task_self_dependency_rejected():
    with pytest.raises(ValidationError):
        Task(
            id="T1", owner_domain="omx", status=OmxTaskStatus.PENDING,
            dependencies=["T1"], allowed_files=["src/a.py"],
            non_goals=[], acceptance_criteria=["x"],
            verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
            required_evidence=["commit"], downstream_handoff=[],
        )
