# Frozen JSON Schemas

These files are the wire-format contract for Loop Engineer (spec §12 P1).

- **Source of truth:** pydantic v2 models under `src/loop_engineer/contracts/`.
- **Never hand-edit** a file under `v1/`. Regenerate with `python scripts/export_schemas.py`.
- **Drift is a build failure:** `tests/contract/test_schema_freeze_drift.py` fails if a model changed but the schema file was not regenerated and committed.
- **Versioning:** `manifest.json` records each schema's version and SHA-256. A breaking change bumps the version and the `v1/` directory name.
