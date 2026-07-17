"""External JSON validated by frozen JSON Schema validates the pydantic model
too (spec §11 contract tests: schema compatibility)."""

import json
from pathlib import Path

import jsonschema
import pytest

from scripts.export_schemas import MODELS  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = ROOT / "schemas" / "v1"

_HEX64 = "a" * 64

PAYLOADS = {
    "goal": {
        "id": "G", "title": "t", "measurable_evidence": "ok", "scope": ["x"],
        "exclusions": [], "stop_conditions": [],
        "milestones": [{"id": "M", "title": "m", "evidence_condition": "c"}],
    },
    "task": {
        "id": "T", "owner_domain": "omx", "status": "pending", "dependencies": [],
        "allowed_files": ["src/a.py"], "non_goals": [], "acceptance_criteria": ["x"],
        "verification": {"commands": ["pytest -q"], "working_dir": "."},
        "required_evidence": ["commit"], "downstream_handoff": [],
    },
    "plan": {
        "goal_id": "G",
        "nodes": [{"task": {
            "id": "T", "owner_domain": "omx", "status": "pending", "dependencies": [],
            "allowed_files": ["src/a.py"], "non_goals": [], "acceptance_criteria": ["x"],
            "verification": {"commands": ["pytest -q"], "working_dir": "."},
            "required_evidence": ["commit"], "downstream_handoff": [],
        }}],
        "edges": [],
    },
    "command": {
        "protocol_version": 1, "run_id": "r", "task_id": "T", "omx_team_name": "tm",
        "worker_identity": "w", "command_id": "c", "command_revision": 1,
        "expected_task_state": "ready", "claim_generation": 0, "lease_generation": 0,
        "command_type": "START_TASK", "instruction": "go",
        "allowed_file_scope_hash": f"sha256:{_HEX64}",
        "evidence_requirements": ["commit"], "verification_requirements": ["pytest -q"],
    },
    "event": {
        "run_id": "r", "task_id": "T", "command_id": "c", "event_id": "e",
        "event_sequence": 1, "provider_observation_revision": 1, "lease_generation": 0,
        "event_type": "ACKNOWLEDGED", "payload": {},
    },
    "claim": {
        "omx_task_id": "T", "holder": "h", "generation": 0,
        "token_digest": f"sha256:{_HEX64}",
    },
    "lease": {
        "generation": 0,
        "expires_at": "2099-01-01T00:00:00Z",
        "last_heartbeat_at": "2099-01-01T00:00:00Z",
    },
    "evidence": {"kind": "commit", "digest": f"sha256:{_HEX64}", "ref": "abc"},
    "handoff": {"integration_branch": "task/T1", "downstream_task_ids": ["T2"]},
    "fence": {"writer_generation": 1, "fenced_paths": [".git/worktrees/t1"]},
    "recovery": {
        "repo_identity": "repo", "run_id": "r", "task_id": "T", "lane": "hybrid",
        "protocol_version": 1, "base_commit": "abc", "integration_branch": "task/T1",
        "integration_worktree": "/wt", "adapter_exec_branch": "exec/T1",
        "adapter_exec_worktree": "/exec", "omx_team_name": "tm", "leader_session": "s",
        "worker_identity": "w", "claim_token_digest": f"sha256:{_HEX64}",
        "lease_generation": 0, "claude_leader_pane": "p", "claude_leader_pid": 1,
        "claude_leader_start_time": "2026-01-01T00:00:00Z", "claude_leader_executable": "claude",
        "omc_state_root": "/omc", "omc_team_name": "otm", "last_command_revision": 1,
        "last_event_sequence": 1, "journal_checksum": f"sha256:{_HEX64}",
        "current_phase": "omc_executing", "writer_fencing_generation": 0, "shutdown_acks": [],
    },
    "provenance": {"entries": []},
}


@pytest.mark.parametrize("name,model", list(MODELS.items()))
def test_payload_validates_against_frozen_schema(name, model):
    schema = json.loads((SCHEMA_DIR / f"{name}.schema.json").read_text())
    payload = PAYLOADS[name]
    jsonschema.validate(payload, schema)  # external JSON accepted by schema
    model(**payload)                      # ...and accepted by the model


@pytest.mark.parametrize("name", list(MODELS))
def test_model_dump_validates_against_schema(name):
    schema = json.loads((SCHEMA_DIR / f"{name}.schema.json").read_text())
    model = MODELS[name]
    instance = model(**PAYLOADS[name])
    jsonschema.validate(json.loads(instance.model_dump_json()), schema)
