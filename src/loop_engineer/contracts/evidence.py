"""Evidence contract (spec §6.3, §13)."""

from enum import StrEnum

from pydantic import BaseModel, Field


class EvidenceType(StrEnum):
    COMMIT = "commit"
    TEST_RUN = "test_run"
    VERIFICATION_RUN = "verification_run"
    SCOPE_PROOF = "scope_proof"
    TREE_HASH = "tree_hash"


class Evidence(BaseModel):
    kind: EvidenceType
    digest: str = Field(min_length=1)
    ref: str = Field(min_length=1)
    produced_at: str | None = None
