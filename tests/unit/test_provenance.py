import pytest
from pydantic import ValidationError

from loop_engineer.contracts.provenance import ProvenanceEntry, ProvenanceManifest


def test_empty_manifest_is_valid_original_only():
    m = ProvenanceManifest(entries=[])
    assert m.redistribution_allowed("src/loop_engineer/contracts/goal.py") is True


def test_entry_requires_all_four_fields():
    with pytest.raises(ValidationError):
        ProvenanceEntry(
            path="scripts/x.sh",
            source_origin="local",
            source_license="",
            transformation="none",
            approved=True,
        )


def test_manifest_blocks_unapproved_redistribution():
    entry = ProvenanceEntry(
        path="scripts/imported.sh",
        source_origin="vendor/foo",
        source_license="unknown",
        transformation="verbatim",
        approved=False,
    )
    m = ProvenanceManifest(entries=[entry])
    assert m.redistribution_allowed("scripts/imported.sh") is False


def test_manifest_allows_approved_entry():
    entry = ProvenanceEntry(
        path="scripts/imported.sh",
        source_origin="vendor/foo",
        source_license="MIT",
        transformation="adapted",
        approved=True,
    )
    m = ProvenanceManifest(entries=[entry])
    assert m.redistribution_allowed("scripts/imported.sh") is True


def test_manifest_rejects_duplicate_paths():
    e = ProvenanceEntry(
        path="x", source_origin="o", source_license="MIT", transformation="none", approved=True
    )
    with pytest.raises(ValidationError):
        ProvenanceManifest(entries=[e, e])
