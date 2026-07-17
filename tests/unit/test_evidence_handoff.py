import pytest
from pydantic import ValidationError

from loop_engineer.contracts.evidence import Evidence, EvidenceType
from loop_engineer.contracts.handoff import Handoff


def test_evidence_accepts_commit_with_digest():
    e = Evidence(kind=EvidenceType.COMMIT, digest="sha256:" + "1" * 64, ref="abc123")
    assert e.kind == EvidenceType.COMMIT


def test_evidence_rejects_empty_digest():
    with pytest.raises(ValidationError):
        Evidence(kind=EvidenceType.COMMIT, digest="", ref="abc123")


def test_handoff_records_integration_branch_and_downstream():
    h = Handoff(integration_branch="task/T1", downstream_task_ids=["T2"])
    assert h.integration_branch == "task/T1"
    assert h.downstream_task_ids == ["T2"]


def test_handoff_rejects_empty_branch():
    with pytest.raises(ValidationError):
        Handoff(integration_branch="", downstream_task_ids=[])
