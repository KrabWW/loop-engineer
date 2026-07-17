# Loop Engineer

Loop Engineer is a durable orchestration toolkit for turning measurable goals into recoverable engineering loops.

The project is being designed around two explicit execution lanes:

- `loop-engineer run omx`: a pure OMX/Codex Team lifecycle.
- `loop-engineer run hybrid`: an OMX-led lifecycle whose real-time executor adapter controls a persistent OMC/Claude Team.

The architecture specification is approved. Runtime code and imported lifecycle scripts will be added only after their contracts, provenance, and licensing are verified.

See [the design specification](docs/superpowers/specs/2026-07-17-loop-engineer-design.md).

## Develop

Requires Python ≥ 3.11.

```bash
python3.11 -m venv .venv
. .venv/bin/activate
pip install -e ".[dev]"
pytest -q
ruff check .
```

## Contracts (P1)

Versioned schemas live under [`schemas/v1/`](schemas/v1/) with a digest
[`manifest.json`](schemas/manifest.json). The pydantic models in
`src/loop_engineer/contracts/` are the source of truth.

After changing a contract, regenerate and commit the frozen schema:

```bash
python scripts/export_schemas.py
```

The drift test (`tests/contract/test_schema_freeze_drift.py`) fails until the
regenerated files are committed, so every schema change shows up in review.
