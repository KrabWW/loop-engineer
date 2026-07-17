"""`loop-engineer task ...` — stub; filled in a later task."""

import argparse


def register(sub: argparse._SubParsersAction) -> None:
    sub.add_parser("task", help="task init/list/claim/... (later)")
