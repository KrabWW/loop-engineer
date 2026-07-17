import pytest
from pydantic import ValidationError

from loop_engineer.contracts.goal import Goal, Milestone


def test_milestone_requires_binary_evidence_condition():
    m = Milestone(id="M1", title="contracts frozen", evidence_condition="all contract tests green")
    assert m.id == "M1"
    with pytest.raises(ValidationError):
        Milestone(id="M2", title="x", evidence_condition="")


def test_goal_accepts_full_authoritative_shape():
    g = Goal(
        id="G1",
        title="ship loop-engineer v1",
        measurable_evidence="tag v1.0.0 after P7 gates pass",
        scope=["cli", "contracts", "runtime"],
        exclusions=["hosted control plane", "multi-user service"],
        stop_conditions=["main red", "license blocked"],
        milestones=[Milestone(id="M1", title="contracts", evidence_condition="green")],
    )
    assert g.measurable_evidence
    assert g.milestones[0].id == "M1"


def test_goal_rejects_empty_scope_or_evidence():
    with pytest.raises(ValidationError):
        Goal(
            id="G", title="t", measurable_evidence="",
            scope=["x"], exclusions=[], stop_conditions=[],
        )
    with pytest.raises(ValidationError):
        Goal(
            id="G", title="t", measurable_evidence="ok",
            scope=[], exclusions=[], stop_conditions=[],
        )


def test_goal_rejects_duplicate_milestone_ids():
    dup = [Milestone(id="M", title="a", evidence_condition="x"),
           Milestone(id="M", title="b", evidence_condition="y")]
    with pytest.raises(ValidationError):
        Goal(id="G", title="t", measurable_evidence="ok", scope=["x"],
             exclusions=[], stop_conditions=[], milestones=dup)
