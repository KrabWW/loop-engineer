import json
from pathlib import Path

from loop_engineer.cli import main
from loop_engineer.contracts.enums import ExitCode


def _goal(tmp_path: Path) -> Path:
    p = tmp_path / "goal.json"
    p.write_text(json.dumps({
        "goal": {"id": "G1", "title": "t", "measurable_evidence": "ok", "scope": ["x"],
                 "exclusions": [], "stop_conditions": [],
                 "milestones": [{"id": "M", "title": "m", "evidence_condition": "c"}]},
        "tasks": [
            {"id": "T1", "owner_domain": "omx", "dependencies": [], "allowed_files": ["src/a.py"],
             "non_goals": [], "acceptance_criteria": ["x"],
             "verification": {"commands": ["t"], "working_dir": "."},
             "required_evidence": ["c"], "downstream_handoff": []},
        ],
    }))
    return p


def test_task_claim_and_list(tmp_path, capsys, monkeypatch):
    plan_path = tmp_path / "plan.json"
    assert main(["plan", "build", str(_goal(tmp_path)), "-o", str(plan_path)]) == int(ExitCode.OK)
    monkeypatch.setenv("LOOP_ENGINEER_COMMON_DIR", str(tmp_path))
    assert main(["task", "init", str(plan_path)]) == int(ExitCode.OK)
    rc = main(["task", "claim", "T1", "--provider", "omx"])
    assert rc == int(ExitCode.OK)
    assert main(["task", "list"]) == int(ExitCode.OK)
    out = capsys.readouterr().out
    assert "T1" in out and "claimed" in out
