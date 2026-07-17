"""Repo + git-common-dir resolution, plan digest, run-id (spec P2a §5.1)."""

import hashlib
import json
import subprocess
from pathlib import Path

from loop_engineer.contracts.plan import Plan


def _git(args: list[str], cwd: Path) -> str:
    proc = subprocess.run(
        ["git", *args], cwd=str(cwd), capture_output=True, text=True, check=False
    )
    if proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed at {cwd}: {proc.stderr.strip()}")
    return proc.stdout.strip()


def repo_root(start: Path | None = None) -> Path:
    cwd = Path(start) if start else Path.cwd()
    return Path(_git(["rev-parse", "--show-toplevel"], cwd))


def git_common_dir(start: Path | None = None) -> Path:
    cwd = Path(start) if start else Path.cwd()
    out = _git(["rev-parse", "--git-common-dir"], cwd)
    p = Path(out)
    return p.resolve() if p.is_absolute() else (cwd / out).resolve()


def board_dir(common_dir: Path, run_id: str) -> Path:
    return Path(common_dir) / "loop-engineer" / run_id


def plan_digest(plan: Plan) -> str:
    canonical = json.dumps(plan.model_dump(mode="json"), sort_keys=True)
    return "sha256:" + hashlib.sha256(canonical.encode()).hexdigest()


def derive_run_id(plan_digest_hex: str) -> str:
    hexpart = plan_digest_hex.split(":", 1)[-1]
    return hexpart[:12]
