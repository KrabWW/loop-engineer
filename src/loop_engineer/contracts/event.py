"""Adapter-to-leader event envelope (spec §7.2).

Events are append-only and idempotent by event_id. The journal enforces
sequence ordering; this model only freezes the wire shape.
"""

from pydantic import BaseModel, Field

from loop_engineer.contracts.enums import EventType


class EventEnvelope(BaseModel):
    run_id: str = Field(min_length=1)
    task_id: str = Field(min_length=1)
    command_id: str = Field(min_length=1)
    event_id: str = Field(min_length=1)
    event_sequence: int = Field(ge=1)  # monotonic per Task run
    provider_observation_revision: int = Field(ge=1)
    lease_generation: int = Field(ge=0)
    event_type: EventType
    payload: dict = Field(default_factory=dict)
