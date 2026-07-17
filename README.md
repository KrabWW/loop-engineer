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

## Compile a goal and claim Tasks (P2a)

```bash
loop-engineer plan build goal.yaml -o plan.json
loop-engineer task init plan.json
loop-engineer task claim T1 --provider omx   # prints a claim token once
loop-engineer task list
```

The task board lives under `.git/loop-engineer/<run-id>/board.json`. OMX and OMC
workers can claim disjoint Tasks in parallel; overlapping `Allowed Files` are
rejected unless the Tasks are dependency-ordered.

## Scheduler planner (P2b-1)

Pure-logic planner: given a compiled `Plan` + task board + per-task execution
metadata, compute eligible Tasks, the conflict graph (dependency / allowed-files
/ migration / resource / lifecycle / protected-zone), engine routing, and a
capacity-respecting launch plan.

```bash
loop-engineer scheduler plan plan.json   # prints the LaunchPlan JSON
```
