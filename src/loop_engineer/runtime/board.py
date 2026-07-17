"""Task board store: atomic, file-locked claim/release/complete (spec P2a §5).

State is persisted as JSON under the Git common dir. Every mutation takes an
exclusive fcntl.flock around a read-modify-write so independent OMX/OMC
processes cannot corrupt each other.
"""

import fcntl
import json
import os
from contextlib import contextmanager
from pathlib import Path
from typing import IO

from pydantic import BaseModel, Field

from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.task_run import TaskBoardEntry
from loop_engineer.runtime import paths as paths_mod


class PriorStateError(Exception):
    """A task was not in the expected prior status."""


class ScopeOverlapError(Exception):
    """A claim would overlap an already-claimed task's allowed files."""


class WrongTokenError(Exception):
    """A release/complete token does not match the stored claim digest."""


def _ancestors(plan: Plan) -> dict[str, set[str]]:
    """task_id -> transitive dependency ancestors (including direct deps)."""
    direct: dict[str, set[str]] = {n.task.id: set(n.task.dependencies) for n in plan.nodes}
    result: dict[str, set[str]] = {}
    for tid in direct:
        seen: set[str] = set()
        stack = list(direct[tid])
        while stack:
            d = stack.pop()
            if d in seen:
                continue
            seen.add(d)
            stack.extend(direct.get(d, set()))
        result[tid] = seen
    return result


class BoardState(BaseModel):
    run_id: str = Field(min_length=1)
    plan_digest: str = Field(min_length=1)
    tasks: dict[str, TaskBoardEntry]


class BoardStore:
    def __init__(
        self,
        board_dir: Path,
        run_id: str,
        plan_digest: str,
        scope_map: dict[str, list[str]],
        ancestors: dict[str, set[str]],
    ) -> None:
        self.dir = Path(board_dir)
        self.dir.mkdir(parents=True, exist_ok=True)
        self.board_path = self.dir / "board.json"
        self.lock_path = self.dir / "board.lock"
        self._run_id = run_id
        self._plan_digest = plan_digest
        self._scope_map = scope_map
        self._ancestors = ancestors

    @classmethod
    def from_plan(cls, plan: Plan, common_dir: Path, run_id: str | None = None) -> "BoardStore":
        digest = paths_mod.plan_digest(plan)
        rid = run_id or paths_mod.derive_run_id(digest)
        bdir = paths_mod.board_dir(Path(common_dir), rid)
        scope_map = {n.task.id: list(n.task.allowed_files) for n in plan.nodes}
        ancestors = _ancestors(plan)
        store = cls(bdir, rid, digest, scope_map, ancestors)
        if not store.board_path.exists():
            state = BoardState(
                run_id=rid,
                plan_digest=digest,
                tasks={n.task.id: TaskBoardEntry(task_id=n.task.id) for n in plan.nodes},
            )
            store._save(state)
        return store

    @classmethod
    def open(cls, board_dir: Path) -> "BoardStore":
        bdir = Path(board_dir)
        board_path = bdir / "board.json"
        if not board_path.exists():
            raise FileNotFoundError(f"no board at {board_path}")
        state = BoardState(**json.loads(board_path.read_text()))
        return cls(bdir, state.run_id, state.plan_digest, {}, {})

    @contextmanager
    def _locked(self):
        self.lock_path.touch(exist_ok=True)
        fh: IO[str] = open(self.lock_path, "r+")
        try:
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
            yield
        finally:
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
            fh.close()

    def _load(self) -> BoardState:
        return BoardState(**json.loads(self.board_path.read_text()))

    def _save(self, state: BoardState) -> None:
        tmp = self.board_path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(state.model_dump(mode="json"), indent=2, sort_keys=True))
        os.replace(tmp, self.board_path)

    def load_state(self) -> BoardState:
        return self._load()
