"""Process lease with heartbeat and expiry (spec §6.2, §7.3)."""

from pydantic import BaseModel, Field


class Lease(BaseModel):
    generation: int = Field(ge=0)
    # ISO-8601 UTC strings keep the model JSON-serializable without a tz engine.
    expires_at: str = Field(min_length=1)
    last_heartbeat_at: str = Field(min_length=1)
