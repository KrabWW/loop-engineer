"""Writer-fence contract for OMC->OMX promotion (spec §8).

Shutdown acknowledgment alone is insufficient. Promotion requires every OMC
worker + Claude leader shutdown ack, the full provider process group proven
absent by PID start identity, provider worktrees proven clean, and equal tree
hashes between the pinned result and the promoted integration tree.
"""

from pydantic import BaseModel, Field, model_validator


class ProcessGroupIdentity(BaseModel):
    pid: int = Field(ge=1)
    start_time: str = Field(min_length=1)
    executable: str = Field(min_length=1)


class FencingProof(BaseModel):
    provider_process_group: list[ProcessGroupIdentity] = Field(min_length=1)
    shutdown_acks: list[str] = Field(min_length=1)
    absence_proofs: list[str] = Field(min_length=1)
    provider_worktrees_clean: bool
    result_tree_hash: str = Field(min_length=1)
    integration_tree_hash: str = Field(min_length=1)

    @model_validator(mode="after")
    def _trees_must_match(self) -> "FencingProof":
        if self.result_tree_hash != self.integration_tree_hash:
            raise ValueError(
                "result_tree_hash and integration_tree_hash must be equal at promotion"
            )
        return self


class WriterFence(BaseModel):
    writer_generation: int = Field(ge=0)
    fenced_paths: list[str] = Field(min_length=1)
    proof: FencingProof | None = None
