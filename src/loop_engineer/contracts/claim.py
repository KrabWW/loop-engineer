"""OMX Task claim (spec §6.4, §7.3).

Raw claim tokens are NEVER serialized into models, logs, events, or committed
evidence. Only the digest is stored. The raw token lives in permission-restricted
runtime state (P2).
"""

import re

from pydantic import BaseModel, Field, field_validator

_DIGEST_RE = r"^sha256:[0-9a-f]{64}$"


class Claim(BaseModel):
    omx_task_id: str = Field(min_length=1)
    holder: str = Field(min_length=1)
    generation: int = Field(ge=0)
    token_digest: str

    @field_validator("token_digest")
    @classmethod
    def _digest_shape(cls, v: str) -> str:
        if not re.match(_DIGEST_RE, v):
            raise ValueError("token_digest must be 'sha256:<64 hex>'")
        return v
