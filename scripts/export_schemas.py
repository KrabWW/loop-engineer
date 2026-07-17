#!/usr/bin/env python3
"""Export pydantic models to frozen JSON Schemas + a digest manifest.

Run after any contract change: `python scripts/export_schemas.py`.
The drift test (tests/contract/test_schema_freeze_drift.py) then fails until the
regenerated files are committed, making schema changes reviewable.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from loop_engineer.compiler.definition import GoalDefinition
from loop_engineer.contracts.claim import Claim
from loop_engineer.contracts.command import CommandEnvelope
from loop_engineer.contracts.event import EventEnvelope
from loop_engineer.contracts.evidence import Evidence
from loop_engineer.contracts.fence import WriterFence
from loop_engineer.contracts.goal import Goal
from loop_engineer.contracts.handoff import Handoff
from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.provenance import ProvenanceManifest
from loop_engineer.contracts.recovery import RecoveryRecord
from loop_engineer.contracts.task import Task
from loop_engineer.contracts.task_run import TaskBoardEntry
from loop_engineer.scheduler.models import TaskExecutionMeta

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_DIR = ROOT / "schemas" / "v1"
MANIFEST = ROOT / "schemas" / "manifest.json"

MODELS = {
    "goal": Goal,
    "goal_definition": GoalDefinition,
    "task": Task,
    "plan": Plan,
    "command": CommandEnvelope,
    "event": EventEnvelope,
    "claim": Claim,
    "lease": Lease,
    "evidence": Evidence,
    "handoff": Handoff,
    "fence": WriterFence,
    "recovery": RecoveryRecord,
    "task_board_entry": TaskBoardEntry,
    "provenance": ProvenanceManifest,
    "task_execution_meta": TaskExecutionMeta,
}


def export() -> dict:
    SCHEMA_DIR.mkdir(parents=True, exist_ok=True)
    registry: dict[str, dict] = {}
    for name, model in MODELS.items():
        schema = model.model_json_schema()
        path = SCHEMA_DIR / f"{name}.schema.json"
        path.write_text(json.dumps(schema, indent=2, sort_keys=True) + "\n")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        registry[name] = {
            "file": f"v1/{name}.schema.json",
            "version": 1,
            "sha256": digest,
        }
    MANIFEST.write_text(
        json.dumps({"version": 1, "schemas": registry}, indent=2, sort_keys=True) + "\n"
    )
    return registry


if __name__ == "__main__":
    export()
    print(f"exported {len(MODELS)} schemas to {SCHEMA_DIR}")
