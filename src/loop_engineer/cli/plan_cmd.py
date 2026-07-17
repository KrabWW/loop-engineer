"""`loop-engineer plan build|validate|show <file>` (spec P2a §6)."""

import argparse
import json
import sys
from pathlib import Path

from loop_engineer.cli.goal_cmd import _load_definition
from loop_engineer.compiler.compiler import compile_goal
from loop_engineer.contracts.enums import ExitCode
from loop_engineer.contracts.plan import Plan


def register(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("plan", help="plan build/validate/show")
    plan_sub = p.add_subparsers(dest="plan_cmd", required=True)

    def _build(args: argparse.Namespace) -> int:
        try:
            definition = _load_definition(args.file)
            plan = compile_goal(definition)
        except Exception:  # noqa: BLE001
            return int(ExitCode.INVALID_INPUT)
        Path(args.out).write_text(
            json.dumps(plan.model_dump(mode="json"), indent=2, sort_keys=True)
        )
        return int(ExitCode.OK)

    def _validate(args: argparse.Namespace) -> int:
        try:
            Plan.model_validate(json.loads(Path(args.file).read_text()))
        except Exception:  # noqa: BLE001
            return int(ExitCode.INVALID_INPUT)
        return int(ExitCode.OK)

    def _show(args: argparse.Namespace) -> int:
        try:
            plan = Plan.model_validate(json.loads(Path(args.file).read_text()))
        except Exception:  # noqa: BLE001
            return int(ExitCode.INVALID_INPUT)
        order = plan.topological_order()
        sys.stdout.write("topological order: " + " -> ".join(order) + "\n")
        return int(ExitCode.OK)

    b = plan_sub.add_parser("build")
    b.add_argument("file")
    b.add_argument("-o", "--out", required=True)
    b.set_defaults(func=_build)

    v = plan_sub.add_parser("validate")
    v.add_argument("file")
    v.set_defaults(func=_validate)

    s = plan_sub.add_parser("show")
    s.add_argument("file")
    s.set_defaults(func=_show)
