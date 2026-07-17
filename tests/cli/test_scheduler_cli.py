import json

from loop_engineer.cli import main
from loop_engineer.contracts.enums import ExitCode


def _files(tmp_path):
    plan = tmp_path / "plan.json"
    plan.write_text(json.dumps({
        "goal_id": "G",
        "nodes": [{"task": {
            "id": "T1", "owner_domain": "omx", "status": "pending", "dependencies": [],
            "allowed_files": ["src/a.py"], "non_goals": [], "acceptance_criteria": ["x"],
            "verification": {"commands": ["t"], "working_dir": "."},
            "required_evidence": ["c"], "downstream_handoff": []}}],
        "edges": [],
    }))
    board_dir = tmp_path / "loop-engineer" / "deadbeef"
    board_dir.mkdir(parents=True)
    (board_dir / "board.json").write_text(json.dumps({
        "run_id": "deadbeef", "plan_digest": "sha256:" + "0" * 64,
        "tasks": {"T1": {"task_id": "T1", "status": "pending", "attempt_id": 1}},
        "scope": {"T1": ["src/a.py"]}, "ancestors": {"T1": []},
    }))
    return plan


def test_scheduler_plan_outputs_launch(tmp_path, capsys, monkeypatch):
    plan = _files(tmp_path)
    monkeypatch.setenv("LOOP_ENGINEER_COMMON_DIR", str(tmp_path))
    rc = main(["scheduler", "plan", str(plan)])
    assert rc == int(ExitCode.OK)
    out = capsys.readouterr().out
    assert "T1" in out and "launch" in out
