import json
from pathlib import Path

from loop_engineer.cli import main
from loop_engineer.contracts.enums import ExitCode


def _goal_file(tmp_path: Path) -> Path:
    data = {
        "goal": {
            "id": "G1", "title": "t", "measurable_evidence": "ok", "scope": ["x"],
            "exclusions": [], "stop_conditions": [],
            "milestones": [{"id": "M", "title": "m", "evidence_condition": "c"}],
        },
        "tasks": [
            {
                "id": "T1", "owner_domain": "omx", "dependencies": [],
                "allowed_files": ["src/a.py"], "non_goals": [], "acceptance_criteria": ["x"],
                "verification": {"commands": ["pytest -q"], "working_dir": "."},
                "required_evidence": ["commit"], "downstream_handoff": [],
            }
        ],
    }
    p = tmp_path / "goal.json"
    p.write_text(json.dumps(data))
    return p


def test_goal_validate_ok(tmp_path):
    rc = main(["goal", "validate", str(_goal_file(tmp_path))])
    assert rc == int(ExitCode.OK)


def test_goal_validate_bad(tmp_path):
    bad = tmp_path / "goal.json"
    bad.write_text("{}")
    rc = main(["goal", "validate", str(bad)])
    assert rc == int(ExitCode.INVALID_INPUT)
