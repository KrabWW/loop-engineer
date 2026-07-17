import pytest

from loop_engineer.contracts.enums import EventType
from loop_engineer.contracts.event import EventEnvelope
from loop_engineer.state.journal import JsonlJournal, StaleEventError


def _evt(seq: int, eid: str) -> EventEnvelope:
    return EventEnvelope(
        run_id="r",
        task_id="T1",
        command_id="c",
        event_id=eid,
        event_sequence=seq,
        provider_observation_revision=1,
        lease_generation=0,
        event_type=EventType.PROGRESS,
        payload={},
    )


def test_append_in_order(tmp_path):
    j = JsonlJournal(tmp_path / "journal.jsonl")
    j.append(_evt(1, "a"))
    j.append(_evt(2, "b"))
    assert [e.event_id for e in j.replay()] == ["a", "b"]


def test_duplicate_event_id_is_idempotent(tmp_path):
    j = JsonlJournal(tmp_path / "journal.jsonl")
    j.append(_evt(1, "a"))
    j.append(_evt(1, "a"))  # same id, same sequence -> ignored
    assert [e.event_id for e in j.replay()] == ["a"]


def test_future_sequence_gap_is_held_not_rejected(tmp_path):
    j = JsonlJournal(tmp_path / "journal.jsonl")
    j.append(_evt(1, "a"))
    held = j.append(_evt(3, "c"))  # gap: 2 missing
    assert held is False
    assert [e.event_id for e in j.replay()] == ["a"]


def test_gap_fills_and_replays_in_order(tmp_path):
    j = JsonlJournal(tmp_path / "journal.jsonl")
    j.append(_evt(1, "a"))
    j.append(_evt(3, "c"))
    j.append(_evt(2, "b"))  # fills the gap
    assert [e.event_id for e in j.replay()] == ["a", "b", "c"]


def test_lower_unseen_sequence_is_rejected_as_stale(tmp_path):
    j = JsonlJournal(tmp_path / "journal.jsonl")
    j.append(_evt(1, "a"))
    j.append(_evt(2, "b"))  # committed prefix is now 1,2 -> next_sequence = 3
    with pytest.raises(StaleEventError):
        j.append(_evt(1, "late"))  # fresh event below the high-water mark -> stale
