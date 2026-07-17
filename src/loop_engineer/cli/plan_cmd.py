"""`loop-engineer plan ...` — stub; filled in a later task."""

import argparse


def register(sub: argparse._SubParsersAction) -> None:
    sub.add_parser("plan", help="plan build/validate/show (later)")
