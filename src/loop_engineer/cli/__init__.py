"""loop-engineer CLI entry point (spec P2a §6)."""

import argparse
import sys

from loop_engineer.contracts.enums import ExitCode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="loop-engineer")
    sub = parser.add_subparsers(dest="cmd", required=True)

    from loop_engineer.cli import goal_cmd, plan_cmd, scheduler_cmd, task_cmd
    goal_cmd.register(sub)
    plan_cmd.register(sub)
    scheduler_cmd.register(sub)
    task_cmd.register(sub)

    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except SystemExit as e:  # argparse error exit
        return e.code if isinstance(e.code, int) else int(ExitCode.INVALID_INPUT)


if __name__ == "__main__":
    sys.exit(main())
