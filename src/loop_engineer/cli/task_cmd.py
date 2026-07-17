"""`loop-engineer task init|list|claim|release|status` (spec P2a §6)."""

import argparse
import json
import os
import sys
from pathlib import Path

from loop_engineer.contracts.enums import ExitCode
from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.provider import Provider
from loop_engineer.runtime import paths as paths_mod
from loop_engineer.runtime.board import (
    BoardStore,
    PriorStateError,
    ScopeOverlapError,
    WrongTokenError,
)


def _common_dir() -> Path:
    override = os.environ.get("LOOP_ENGINEER_COMMON_DIR")
    if override:
        return Path(override)
    return paths_mod.git_common_dir()


def _open_for(args: argparse.Namespace) -> BoardStore:
    base = _common_dir() / "loop-engineer"
    if getattr(args, "run", None):
        return BoardStore.open(base / args.run)
    runs = [d for d in base.glob("*") if (d / "board.json").exists()]
    if len(runs) != 1:
        raise SystemExit(int(ExitCode.OWNERSHIP_AMBIGUITY))
    return BoardStore.open(runs[0])


def register(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("task", help="task init/list/claim/release/status")
    task_sub = p.add_subparsers(dest="task_cmd", required=True)

    def _init(args: argparse.Namespace) -> int:
        try:
            plan = Plan.model_validate(json.loads(Path(args.plan).read_text()))
            BoardStore.from_plan(plan, _common_dir())
        except Exception:  # noqa: BLE001
            return int(ExitCode.INVALID_INPUT)
        return int(ExitCode.OK)

    def _list(args: argparse.Namespace) -> int:
        store = _open_for(args)
        for tid, e in store.load_state().tasks.items():
            prov = e.provider.value if e.provider else "-"
            sys.stdout.write(f"{tid}\t{e.status.value}\t{prov}\n")
        return int(ExitCode.OK)

    def _claim(args: argparse.Namespace) -> int:
        store = _open_for(args)
        lease = Lease(
            generation=0,
            expires_at="2099-01-01T00:00:00Z",
            last_heartbeat_at="2099-01-01T00:00:00Z",
        )
        try:
            token = store.claim(args.task_id, Provider(args.provider), lease)
        except PriorStateError:
            return int(ExitCode.OWNERSHIP_AMBIGUITY)
        except ScopeOverlapError:
            return int(ExitCode.VERIFICATION_SCOPE_FAILURE)
        sys.stdout.write(token + "\n")
        return int(ExitCode.OK)

    def _release(args: argparse.Namespace) -> int:
        store = _open_for(args)
        try:
            store.release(args.task_id, args.token)
        except (PriorStateError, WrongTokenError):
            return int(ExitCode.OWNERSHIP_AMBIGUITY)
        return int(ExitCode.OK)

    def _status(args: argparse.Namespace) -> int:
        store = _open_for(args)
        e = store.load_state().tasks.get(args.task_id)
        if e is None:
            return int(ExitCode.INVALID_INPUT)
        sys.stdout.write(json.dumps(e.model_dump(mode="json"), indent=2) + "\n")
        return int(ExitCode.OK)

    i = task_sub.add_parser("init")
    i.add_argument("plan")
    i.set_defaults(func=_init)

    lst = task_sub.add_parser("list")
    lst.add_argument("--run")
    lst.set_defaults(func=_list, run=None)

    c = task_sub.add_parser("claim")
    c.add_argument("task_id")
    c.add_argument("--provider", choices=["omx", "omc"], required=True)
    c.add_argument("--run")
    c.set_defaults(func=_claim)

    r = task_sub.add_parser("release")
    r.add_argument("task_id")
    r.add_argument("--token", required=True)
    r.add_argument("--run")
    r.set_defaults(func=_release)

    s = task_sub.add_parser("status")
    s.add_argument("task_id")
    s.add_argument("--run")
    s.set_defaults(func=_status)
