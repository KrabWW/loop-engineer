import json
from pathlib import Path

from loop_engineer.cli import main
from loop_engineer.contracts.enums import ExitCode


def _write_goal(tmp_path: Path) -> Path:
    p = tmp_path / "goal.json"
    p.write_text(json.dumps({
        "goal": {
            "id": "G1", "title": "t", "measurable_evidence": "ok", "scope": ["x"],
            "exclusions": [], "stop_conditions": [],
            "milestones": [{"id": "M", "title": "m", "evidence_condition": "c"}],
        },
        "tasks": [
            {"id": "T1", "owner_domain": "omx", "dependencies": [], "allowed_files": ["src/a.py"],
             "non_goals": [], "acceptance_criteria": ["x"],
             "verification": {"commands": ["t"], "working_dir": "."},
             "required_evidence": ["c"], "downstream_handoff": []},
            {"id": "T2", "owner_domain": "omx", "dependencies": ["T1"],
             "allowed_files": ["src/b.py"], "non_goals": [], "acceptance_criteria": ["x"],
             "verification": {"commands": ["t"], "working_dir": "."},
             "required_evidence": ["c"], "downstream_handoff": []},
        ],
    }))
    return p


def test_plan_build_writes_plan(tmp_path):
    goal = _write_goal(tmp_path)
    out = tmp_path / "plan.json"
    rc = main(["plan", "build", str(goal), "-o", str(out)])
    assert rc == int(ExitCode.OK)
    plan = json.loads(out.read_text())
    assert plan["goal_id"] == "G1"
    ids = {n["task"]["id"] for n in plan["nodes"]}
    assert ids == {"T1", "T2"}


def test_plan_validate_ok(tmp_path):
    goal = _write_goal(tmp_path)
    out = tmp_path / "plan.json"
    main(["plan", "build", str(goal), "-o", str(out)])
    assert main(["plan", "validate", str(out)]) == int(ExitCode.OK)


def test_plan_validate_bad(tmp_path):
    bad = tmp_path / "plan.json"
    bad.write_text("{}")
    assert main(["plan", "validate", str(bad)]) == int(ExitCode.INVALID_INPUT)
