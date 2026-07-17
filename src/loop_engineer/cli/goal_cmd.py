"""`loop-engineer goal define|validate <file>` (spec P2a §6)."""

import argparse
import json
from pathlib import Path

import yaml

from loop_engineer.compiler.definition import GoalDefinition
from loop_engineer.contracts.enums import ExitCode


def _load_definition(path: str) -> GoalDefinition:
    text = Path(path).read_text()
    data = yaml.safe_load(text) if path.endswith((".yaml", ".yml")) else json.loads(text)
    return GoalDefinition.model_validate(data)


def register(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("goal", help="goal define/validate")
    goal_sub = p.add_subparsers(dest="goal_cmd", required=True)

    def _validate(args: argparse.Namespace) -> int:
        try:
            _load_definition(args.file)
        except Exception:  # noqa: BLE001 - any parse/validation failure is exit 2
            return int(ExitCode.INVALID_INPUT)
        return int(ExitCode.OK)

    v = goal_sub.add_parser("validate")
    v.add_argument("file")
    v.set_defaults(func=_validate)

    d = goal_sub.add_parser("define")
    d.add_argument("file")
    d.set_defaults(func=_validate)  # define re-validates for now (editor-driven)
