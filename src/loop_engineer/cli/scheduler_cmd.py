"""`loop-engineer scheduler plan <plan-file>` — surface the planner (spec P2b-1, visibility)."""

import argparse
import json
import os
import sys
from pathlib import Path

from loop_engineer.contracts.enums import ExitCode
from loop_engineer.contracts.plan import Plan
from loop_engineer.runtime.board import BoardStore
from loop_engineer.scheduler.models import PlannerConfig
from loop_engineer.scheduler.planner import plan_launch


def _common_dir() -> Path:
    override = os.environ.get("LOOP_ENGINEER_COMMON_DIR")
    return Path(override) if override else Path.cwd()


def register(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("scheduler", help="scheduler plan/show")
    sch_sub = p.add_subparsers(dest="scheduler_cmd", required=True)

    def _plan(args: argparse.Namespace) -> int:
        try:
            plan = Plan.model_validate(json.loads(Path(args.plan).read_text()))
            base = _common_dir() / "loop-engineer"
            runs = [d for d in base.glob("*") if (d / "board.json").exists()]
            if len(runs) != 1:
                return int(ExitCode.OWNERSHIP_AMBIGUITY)
            store = BoardStore.open(runs[0])
            lp = plan_launch(plan, store.load_state(), {}, PlannerConfig())
        except Exception:  # noqa: BLE001
            return int(ExitCode.INVALID_INPUT)
        sys.stdout.write(lp.model_dump_json(indent=2) + "\n")
        return int(ExitCode.OK)

    pp = sch_sub.add_parser("plan")
    pp.add_argument("plan")
    pp.set_defaults(func=_plan)
