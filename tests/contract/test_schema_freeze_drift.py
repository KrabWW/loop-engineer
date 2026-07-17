"""Schema drift detector (spec §12 P1).

If a model changes but schemas/v1 is not regenerated, this fails so the change
is visible in review.
"""

import hashlib
import json
from pathlib import Path

import pytest

from scripts.export_schemas import MODELS  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = ROOT / "schemas" / "v1"
MANIFEST = ROOT / "schemas" / "manifest.json"


@pytest.mark.parametrize("name,model", list(MODELS.items()))
def test_committed_schema_matches_model(name, model):
    path = SCHEMA_DIR / f"{name}.schema.json"
    assert path.exists(), f"missing schema {path}; run scripts/export_schemas.py"
    expected = json.loads(path.read_text())
    actual = model.model_json_schema()
    assert expected == actual, (
        f"schema drift for {name}: run `python scripts/export_schemas.py` and commit the diff"
    )


@pytest.mark.parametrize("name,model", list(MODELS.items()))
def test_manifest_digest_matches_file(name, model):
    manifest = json.loads(MANIFEST.read_text())
    entry = manifest["schemas"][name]
    path = SCHEMA_DIR / f"{name}.schema.json"
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert entry["sha256"] == digest, f"manifest digest stale for {name}"
