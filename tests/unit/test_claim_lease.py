import pytest
from pydantic import ValidationError

from loop_engineer.contracts.claim import Claim
from loop_engineer.contracts.lease import Lease

_CLAIM_DIGEST = "sha256:" + "0" * 64


def test_claim_accepts_digest_not_raw_token():
    c = Claim(
        omx_task_id="T1",
        holder="adapter-gen-0",
        generation=0,
        token_digest=_CLAIM_DIGEST,
    )
    assert c.token_digest.startswith("sha256:")


def test_claim_rejects_bad_digest_format():
    with pytest.raises(ValidationError):
        Claim(
            omx_task_id="T1",
            holder="x",
            generation=0,
            token_digest="raw-secret-never-stored",
        )


def test_claim_generation_non_negative():
    with pytest.raises(ValidationError):
        Claim(omx_task_id="T1", holder="x", generation=-1, token_digest=_CLAIM_DIGEST)


def test_lease_requires_future_expiry_and_heartbeat():
    lease = Lease(
        generation=0,
        expires_at="2099-01-01T00:00:00Z",
        last_heartbeat_at="2099-01-01T00:00:00Z",
    )
    assert lease.generation == 0


def test_lease_rejects_negative_generation():
    with pytest.raises(ValidationError):
        Lease(
            generation=-1,
            expires_at="2099-01-01T00:00:00Z",
            last_heartbeat_at="2099-01-01T00:00:00Z",
        )
