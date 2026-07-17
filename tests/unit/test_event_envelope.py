import pytest
from pydantic import ValidationError

from loop_engineer.contracts.enums import EventType
from loop_engineer.contracts.event import EventEnvelope


def _minimal_event(**overrides) -> dict:
    base = dict(
        run_id="run-1",
        task_id="T1",
        command_id="cmd-1",
        event_id="evt-1",
        event_sequence=1,
        provider_observation_revision=1,
        lease_generation=0,
        event_type=EventType.ACKNOWLEDGED,
        payload={},
    )
    base.update(overrides)
    return base


def test_event_accepts_full_envelope():
    e = EventEnvelope(**_minimal_event())
    assert e.event_type == EventType.ACKNOWLEDGED


def test_event_sequence_must_be_positive():
    with pytest.raises(ValidationError):
        EventEnvelope(**_minimal_event(event_sequence=0))


def test_provider_observation_revision_must_be_positive():
    with pytest.raises(ValidationError):
        EventEnvelope(**_minimal_event(provider_observation_revision=0))
