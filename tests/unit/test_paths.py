import subprocess

from loop_engineer.contracts.plan import Plan, TaskNode
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.runtime import paths


def _plan() -> Plan:
    t = Task(
        id="T1", owner_domain="omx", allowed_files=["src/a.py"],
        acceptance_criteria=["x"], verification=VerificationSpec(commands=["t"], working_dir="."),
        required_evidence=["c"],
    )
    return Plan(goal_id="G1", nodes=[TaskNode(task=t)], edges=[])


def test_plan_digest_is_deterministic():
    assert paths.plan_digest(_plan()) == paths.plan_digest(_plan())


def test_derive_run_id_is_short_prefix():
    d = paths.plan_digest(_plan())
    rid = paths.derive_run_id(d)
    assert rid == d.split(":", 1)[-1][:12]
    assert len(rid) == 12


def test_board_dir_under_common(tmp_path):
    bd = paths.board_dir(tmp_path, "run123")
    assert bd == tmp_path / "loop-engineer" / "run123"


def test_repo_root_and_common_dir_in_tmp_git(tmp_path):
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.email", "a@b.c"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)
    root = paths.repo_root(tmp_path)
    common = paths.git_common_dir(tmp_path)
    assert root.resolve() == tmp_path.resolve()
    assert common.exists() and common.is_dir()
