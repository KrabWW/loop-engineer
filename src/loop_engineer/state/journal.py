"""Append-only event journal (spec §7.2).

Contract:
  - append-only and idempotent by event_id (duplicates ignored),
  - the journal accepts only the next event_sequence,
  - a future sequence gap is held for replay (not persisted until the gap fills),
  - a sequence below the committed high-water mark is rejected as stale.

P1 ships the contract + a minimal JSONL file implementation. The durable engine
default is locked here (D5); a different engine may swap in behind `Journal`.
"""

import json
from pathlib import Path

from loop_engineer.contracts.event import EventEnvelope


class StaleEventError(Exception):
    """An event arrived with a sequence below the committed high-water mark."""


class Journal:
    """Interface for append-only, sequence-ordered event journals."""

    def append(self, event: EventEnvelope) -> bool:
        raise NotImplementedError

    def replay(self) -> list[EventEnvelope]:
        raise NotImplementedError


class JsonlJournal(Journal):
    """File-backed append-only journal with hold-for-gap semantics.

    Held (out-of-order, future-sequence) events live only in memory until their
    gap fills, so the on-disk file is always a gap-free prefix.
    """

    def __init__(self, path: str | Path) -> None:
        self._path = Path(path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._path.touch(exist_ok=True)
        self._seen_ids: set[str] = set()
        self._next_sequence: int = 1
        self._held: dict[int, EventEnvelope] = {}
        for e in self._read_all():
            self._seen_ids.add(e.event_id)
            self._next_sequence = max(self._next_sequence, e.event_sequence + 1)

    def _read_all(self) -> list[EventEnvelope]:
        events: list[EventEnvelope] = []
        for line in self._path.read_text().splitlines():
            line = line.strip()
            if line:
                events.append(EventEnvelope(**json.loads(line)))
        return events

    def _persist(self, event: EventEnvelope) -> None:
        with self._path.open("a") as fh:
            fh.write(json.dumps(event.model_dump()) + "\n")

    def append(self, event: EventEnvelope) -> bool:
        if event.event_id in self._seen_ids:
            return True
        if event.event_sequence < self._next_sequence:
            raise StaleEventError(
                f"event {event.event_id} seq {event.event_sequence} < next {self._next_sequence}"
            )
        if event.event_sequence > self._next_sequence:
            self._held[event.event_sequence] = event
            return False
        self._commit(event)
        self._drain_held()
        return True

    def _commit(self, event: EventEnvelope) -> None:
        self._persist(event)
        self._seen_ids.add(event.event_id)
        self._next_sequence = event.event_sequence + 1

    def _drain_held(self) -> None:
        while self._next_sequence in self._held:
            nxt = self._held.pop(self._next_sequence)
            self._commit(nxt)

    def replay(self) -> list[EventEnvelope]:
        return self._read_all()
