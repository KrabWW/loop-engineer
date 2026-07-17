import pytest
from pydantic import ValidationError

from loop_engineer.contracts.fence import FencingProof, ProcessGroupIdentity, WriterFence


def test_writer_fence_generation_monotonic_default():
    f = WriterFence(writer_generation=1, fenced_paths=[".git/worktrees/t1"])
    assert f.writer_generation == 1


def test_writer_fence_rejects_negative_generation():
    with pytest.raises(ValidationError):
        WriterFence(writer_generation=-1, fenced_paths=["x"])


def test_fencing_proof_requires_absence_and_clean_worktrees_and_equal_trees():
    p = FencingProof(
        provider_process_group=[
            ProcessGroupIdentity(
                pid=1234, start_time="2026-01-01T00:00:00Z", executable="claude"
            )
        ],
        shutdown_acks=["ack-worker-1"],
        absence_proofs=["pid 1234 gone at 2026-01-01T00:01:00Z"],
        provider_worktrees_clean=True,
        result_tree_hash="sha256:" + "9" * 64,
        integration_tree_hash="sha256:" + "9" * 64,
    )
    assert p.provider_worktrees_clean is True
    assert p.result_tree_hash == p.integration_tree_hash


def test_fencing_proof_rejects_mismatched_trees():
    with pytest.raises(ValidationError):
        FencingProof(
            provider_process_group=[
                ProcessGroupIdentity(
                    pid=1234, start_time="2026-01-01T00:00:00Z", executable="claude"
                )
            ],
            shutdown_acks=["ack-1"],
            absence_proofs=["gone"],
            provider_worktrees_clean=True,
            result_tree_hash="sha256:" + "9" * 64,
            integration_tree_hash="sha256:" + "8" * 64,
        )
