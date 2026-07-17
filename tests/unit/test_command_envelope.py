import pytest
from pydantic import ValidationError

from loop_engineer.contracts.command import CommandEnvelope
from loop_engineer.contracts.enums import CommandType, CommonState


def _minimal_command(**overrides) -> dict:
    base = dict(
        protocol_version=1,
        run_id="run-1",
        task_id="T1",
        omx_team_name="team-1",
        worker_identity="omx-worker-1",
        command_id="cmd-1",
        command_revision=1,
        expected_task_state=CommonState.READY,
        claim_generation=0,
        lease_generation=0,
        command_type=CommandType.START_TASK,
        instruction="begin",
        allowed_file_scope_hash="sha256:" + "a" * 64,
        evidence_requirements=["commit"],
        verification_requirements=["pytest -q"],
    )
    base.update(overrides)
    return base


def test_command_accepts_full_envelope():
    c = CommandEnvelope(**_minimal_command())
    assert c.command_type == CommandType.START_TASK


def test_command_revision_must_be_positive():
    with pytest.raises(ValidationError):
        CommandEnvelope(**_minimal_command(command_revision=0))


def test_causation_id_optional():
    c = CommandEnvelope(**_minimal_command(causation_id="cmd-0"))
    assert c.causation_id == "cmd-0"


def test_scope_hash_format_enforced():
    with pytest.raises(ValidationError):
        CommandEnvelope(**_minimal_command(allowed_file_scope_hash="not-a-hash"))


def test_protocol_version_must_be_positive():
    with pytest.raises(ValidationError):
        CommandEnvelope(**_minimal_command(protocol_version=0))
