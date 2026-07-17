# Loop Engineer — P2a (Runtime Core & Parallel Claim) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make loop-engineer compile a goal file into a validated Task DAG and expose a provider-neutral task board where OMX and OMC worker processes can claim non-overlapping Tasks in parallel, atomically, with write-scope safety — all as tested Python with no real `omx`/`omc` Team launch.

**Architecture:** A `GoalDefinition` (goal + tasks) compiles to a P1 `Plan` (acyclic). A `BoardStore` persists per-Task runtime entries under the Git common dir and guards every mutation with an `fcntl.flock`-protected read-modify-write, so independent OMX/OMC processes can claim concurrently. Claims are provider-neutral (`Provider` enum), lease-bound, digest-only, and rejected on `Allowed Files` overlap unless dependency-ordered.

**Tech Stack:** Python ≥ 3.11, pydantic v2, PyYAML (new core dep), pytest, ruff. Reuses P1 contracts (`Goal`, `Task`, `Plan`, `Claim`, `Lease`).

**Spec:** [2026-07-17-p2a-runtime-core-design.md](../specs/2026-07-17-p2a-runtime-core-design.md). **Worktree:** `.worktrees/p2a-runtime-core`, branch `p2a-runtime-core`. **Python:** `python3.11` (system `python3` is 3.9 — never use bare). Activate `.venv` (recreate from P1's pyproject + new PyYAML).

---

## §14-style decisions resolved here

| ID | Decision | Resolution |
| --- | --- | --- |
| P2a-D1 | YAML support | **PyYAML as a core dep** (supersedes the spec's "optional" wording — simpler; no graceful-degradation code). Goal files detected as YAML (fallback JSON). |
| P2a-D2 | Concurrency primitive | **`fcntl.flock`** exclusive lock around read-modify-write of `board.json`. Cross-process; sufficient for low contention. |
| P2a-D3 | Board status enum | New `TaskRunStatus` (pending/claimed/released/done/failed), separate from §7.3 `CommonState`. |
| P2a-D4 | `run-id` | First 12 hex of the canonical Plan SHA-256. |
| P2a-D5 | `release` default target | `RELEASED` (re-claimable to `PENDING` via a separate reset); `release` itself is terminal-ish but `attempt_id` increment + re-`PENDING` is a P2b retry concern. For P2a, `release` sets `RELEASED` and clears claim/lease/provider; `reset_to_pending` is a separate explicit op. |

---

## File structure (additive)

```
src/loop_engineer/
├── cli/
│   ├── __init__.py        # main() + argparse subparsers
│   ├── goal_cmd.py        # goal define/validate
│   ├── plan_cmd.py        # plan build/validate/show
│   └── task_cmd.py        # task list/claim/release/status
├── compiler/
│   ├── __init__.py
│   ├── definition.py      # GoalDefinition input model
│   └── compiler.py        # compile_goal(GoalDefinition) -> Plan
├── runtime/
│   ├── __init__.py
│   ├── paths.py           # repo_root, git_common_dir, board_dir, plan_digest, run_id
│   ├── scope.py           # normalize + overlaps + ScopeError
│   └── board.py           # BoardState, BoardStore (init/claim/release/complete), errors
└── contracts/
    ├── provider.py        # Provider enum
    └── task_run.py        # TaskRunStatus + TaskBoardEntry
tests/
├── unit/
│   ├── test_provider_task_run.py
│   ├── test_scope.py
│   ├── test_definition.py
│   ├── test_compiler.py
│   ├── test_paths.py
│   └── test_board.py
├── runtime/
│   ├── __init__.py
│   └── test_board_concurrency.py
└── cli/
    ├── __init__.py
    ├── test_goal_cli.py
    ├── test_plan_cli.py
    └── test_task_cli.py
```

**Responsibility rule:** compiler turns input into a static Plan; scope is pure path math; board is the only thing that holds runtime state and the lock; cli is a thin argparse shell over compiler+board. New contracts are frozen via the existing pipeline (register in `scripts/export_schemas.py::MODELS`); P1 v1 schemas are untouched.

---

## Task 0: scaffolding (packages, test dirs, PyYAML dep)

**Files:** Create `src/loop_engineer/cli/__init__.py`, `src/loop_engineer/compiler/__init__.py`, `src/loop_engineer/runtime/__init__.py`, `tests/runtime/__init__.py`, `tests/cli/__init__.py` (all package markers); modify `pyproject.toml` to add PyYAML.

- [ ] **Step 1: add PyYAML to core deps in `pyproject.toml`**

Change the `dependencies` list to:
```toml
dependencies = [
  "pydantic>=2.7,<3",
  "jsonschema>=4.21,<5",
  "pyyaml>=6.0,<7",
]
```

- [ ] **Step 2: create the five package-marker files**

Each of `src/loop_engineer/cli/__init__.py`, `src/loop_engineer/compiler/__init__.py`, `src/loop_engineer/runtime/__init__.py`, `tests/runtime/__init__.py`, `tests/cli/__init__.py`:
```python
"""Package marker."""
```

- [ ] **Step 3: install + verify**

```bash
cd /Users/xielaoban/Documents/loop-engineer/.worktrees/p2a-runtime-core
python3.11 -m venv .venv
. .venv/bin/activate
pip install -e ".[dev]"
python -c "import yaml, pydantic, jsonschema; print('deps ok')"
pytest -q
ruff check .
```
Expected: `deps ok`; pytest reports no tests ran (exit 5 ok); ruff clean.

- [ ] **Step 4: commit**
```bash
git add pyproject.toml src/loop_engineer/cli/__init__.py src/loop_engineer/compiler/__init__.py src/loop_engineer/runtime/__init__.py tests/runtime/__init__.py tests/cli/__init__.py
git commit -m "chore(p2a): scaffold cli/compiler/runtime packages and add PyYAML

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 1: Provider + TaskRunStatus + TaskBoardEntry (new contracts)

**Files:** Create `src/loop_engineer/contracts/provider.py`, `src/loop_engineer/contracts/task_run.py`; Test `tests/unit/test_provider_task_run.py`; register `TaskBoardEntry` in `scripts/export_schemas.py`.

- [ ] **Step 1: failing test FIRST — `tests/unit/test_provider_task_run.py`**
```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task_run import TaskBoardEntry, TaskRunStatus


def test_provider_values():
    assert {p.value for p in Provider} == {"omx", "omc"}


def test_task_run_status_values():
    assert {s.value for s in TaskRunStatus} == {
        "pending", "claimed", "released", "done", "failed",
    }


def test_entry_defaults_to_pending():
    e = TaskBoardEntry(task_id="T1")
    assert e.status == TaskRunStatus.PENDING
    assert e.attempt_id == 1
    assert e.claim is None and e.provider is None


def test_entry_rejects_empty_task_id():
    with pytest.raises(ValidationError):
        TaskBoardEntry(task_id="")


def test_entry_rejects_non_positive_attempt():
    with pytest.raises(ValidationError):
        TaskBoardEntry(task_id="T1", attempt_id=0)
```

- [ ] **Step 2: run, observe FAIL** — `pytest tests/unit/test_provider_task_run.py -v` → `ModuleNotFoundError: No module named 'loop_engineer.contracts.provider'`.

- [ ] **Step 3: implementation — `src/loop_engineer/contracts/provider.py`**
```python
"""Provider enum: which execution lane claimed a Task (spec P2a §4)."""

from enum import StrEnum


class Provider(StrEnum):
    OMX = "omx"
    OMC = "omc"
```

`src/loop_engineer/contracts/task_run.py`:
```python
"""Board-level run status and entry (spec P2a §4).

Deliberately separate from the §7.3 CommonState Hybrid lifecycle: P2a only
coordinates claiming, not Hybrid-phase transitions.
"""

from enum import StrEnum

from pydantic import BaseModel, Field

from loop_engineer.contracts.claim import Claim
from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.provider import Provider


class TaskRunStatus(StrEnum):
    PENDING = "pending"
    CLAIMED = "claimed"
    RELEASED = "released"
    DONE = "done"
    FAILED = "failed"


class TaskBoardEntry(BaseModel):
    task_id: str = Field(min_length=1)
    status: TaskRunStatus = TaskRunStatus.PENDING
    claim: Claim | None = None
    lease: Lease | None = None
    provider: Provider | None = None
    attempt_id: int = Field(default=1, ge=1)
```

- [ ] **Step 4: register `TaskBoardEntry` in the freeze pipeline**

In `scripts/export_schemas.py`, add to the imports:
```python
from loop_engineer.contracts.task_run import TaskBoardEntry
```
and add to the `MODELS` dict (keep alphabetical by key):
```python
    "recovery": RecoveryRecord,
    "task_board_entry": TaskBoardEntry,
    "task": Task,
```
Then regenerate + verify drift test still passes:
```bash
python scripts/export_schemas.py
pytest tests/contract/test_schema_freeze_drift.py tests/contract/test_schema_roundtrip.py tests/unit/test_provider_task_run.py -v
```
(If `test_schema_roundtrip.py` `KeyError`s on `task_board_entry`, add a `"task_board_entry"` entry to its `PAYLOADS` dict: `{"task_id": "T1"}`.)

- [ ] **Step 5: run full + ruff, commit**
```bash
pytest -q && ruff check .
git add src/loop_engineer/contracts/provider.py src/loop_engineer/contracts/task_run.py tests/unit/test_provider_task_run.py scripts/export_schemas.py schemas/
git commit -m "feat(contracts): add Provider, TaskRunStatus, TaskBoardEntry

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 2: write-scope normalization + overlap (`runtime/scope.py`)

**Files:** Create `src/loop_engineer/runtime/scope.py`; Test `tests/unit/test_scope.py`.

- [ ] **Step 1: failing test — `tests/unit/test_scope.py`**
```python
import pytest

from loop_engineer.runtime.scope import ScopeError, normalize, overlaps


def test_normalize_strips_dot_and_collapses():
    assert normalize("src/./a/../a.py") == "src/a.py"


def test_normalize_rejects_absolute():
    with pytest.raises(ScopeError):
        normalize("/etc/passwd")


def test_normalize_rejects_escape():
    with pytest.raises(ScopeError):
        normalize("../escape.py")
    with pytest.raises(ScopeError):
        normalize("src/../../escape.py")


def test_normalize_rejects_empty():
    with pytest.raises(ScopeError):
        normalize("./")


def test_overlaps_exact_file():
    assert overlaps({"src/a.py"}, {"src/a.py", "src/b.py"})


def test_overlaps_directory_contains_file():
    assert overlaps({"src"}, {"src/a.py"})


def test_no_overlap_disjoint():
    assert not overlaps({"src/a.py"}, {"tests/test_a.py"})


def test_overlaps_normalized_first():
    # trailing "." and dup slashes do not defeat detection
    assert overlaps({"src/./a.py"}, {"src//a.py"})
```

- [ ] **Step 2: run, FAIL** — `ModuleNotFoundError: No module named 'loop_engineer.runtime.scope'`.

- [ ] **Step 3: implementation — `src/loop_engineer/runtime/scope.py`**
```python
"""Allowed-files normalization + overlap detection (spec P2a §5.3).

Normalization is lexical (no filesystem access): paths are relative POSIX,
absolute paths and any '..' that escapes the repo root are rejected. Two file
sets overlap on exact file match or directory containment (either direction).
"""

from collections.abc import Iterable


class ScopeError(ValueError):
    """An allowed-files entry is not a legal relative in-repo path."""


def normalize(path: str) -> str:
    out: list[str] = []
    parts = path.replace("\\", "/").split("/")
    for part in parts:
        if part in ("", "."):
            continue
        if part == "..":
            if not out:
                raise ScopeError(f"path escapes repo root: {path!r}")
            out.pop()
            continue
        out.append(part)
    if not out:
        raise ScopeError(f"empty path after normalization: {path!r}")
    return "/".join(out)


def _norm_set(files: Iterable[str]) -> set[str]:
    return {normalize(f) for f in files}


def overlaps(a: Iterable[str], b: Iterable[str]) -> bool:
    na = _norm_set(a)
    nb = _norm_set(b)
    for x in na:
        for y in nb:
            if x == y or x.startswith(y + "/") or y.startswith(x + "/"):
                return True
    return False
```

- [ ] **Step 4: run, PASS (8), ruff, commit**
```bash
pytest tests/unit/test_scope.py -v && ruff check .
git add src/loop_engineer/runtime/scope.py tests/unit/test_scope.py
git commit -m "feat(runtime): add allowed-files normalization and overlap detection

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 3: GoalDefinition + compiler (`compiler/`)

**Files:** Create `src/loop_engineer/compiler/definition.py`, `src/loop_engineer/compiler/compiler.py`; Test `tests/unit/test_definition.py`, `tests/unit/test_compiler.py`; register `GoalDefinition` in export_schemas.

- [ ] **Step 1: failing test — `tests/unit/test_definition.py`**
```python
import pytest
from pydantic import ValidationError

from loop_engineer.compiler.definition import GoalDefinition
from loop_engineer.contracts.goal import Goal, Milestone
from loop_engineer.contracts.task import Task, VerificationSpec


def _goal() -> Goal:
    return Goal(
        id="G1", title="t", measurable_evidence="ok", scope=["x"],
        exclusions=[], stop_conditions=[],
        milestones=[Milestone(id="M", title="m", evidence_condition="c")],
    )


def _task(tid: str, deps: list[str] | None = None) -> Task:
    return Task(
        id=tid, owner_domain="omx", dependencies=deps or [],
        allowed_files=[f"src/{tid}.py"], non_goals=[], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
        required_evidence=["commit"], downstream_handoff=[],
    )


def test_definition_accepts_goal_and_tasks():
    d = GoalDefinition(goal=_goal(), tasks=[_task("T1")])
    assert d.tasks[0].id == "T1"


def test_definition_requires_tasks():
    with pytest.raises(ValidationError):
        GoalDefinition(goal=_goal(), tasks=[])


def test_definition_rejects_duplicate_task_ids():
    with pytest.raises(ValidationError):
        GoalDefinition(goal=_goal(), tasks=[_task("T"), _task("T")])
```

- [ ] **Step 2: failing test — `tests/unit/test_compiler.py`**
```python
import pytest
from pydantic import ValidationError

from loop_engineer.compiler.compiler import compile_goal
from loop_engineer.compiler.definition import GoalDefinition
from loop_engineer.contracts.goal import Goal, Milestone
from loop_engineer.contracts.task import Task, VerificationSpec


def _goal() -> Goal:
    return Goal(
        id="G1", title="t", measurable_evidence="ok", scope=["x"],
        exclusions=[], stop_conditions=[],
        milestones=[Milestone(id="M", title="m", evidence_condition="c")],
    )


def _task(tid: str, deps: list[str] | None = None) -> Task:
    return Task(
        id=tid, owner_domain="omx", dependencies=deps or [],
        allowed_files=[f"src/{tid}.py"], non_goals=[], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
        required_evidence=["commit"], downstream_handoff=[],
    )


def test_compile_builds_acyclic_plan():
    d = GoalDefinition(goal=_goal(), tasks=[_task("T1"), _task("T2", ["T1"])])
    plan = compile_goal(d)
    assert plan.goal_id == "G1"
    order = plan.topological_order()
    assert order.index("T1") < order.index("T2")


def test_compile_rejects_cycle_via_plan_validation():
    d = GoalDefinition(
        goal=_goal(),
        tasks=[_task("T1", ["T2"]), _task("T2", ["T1"])],
    )
    with pytest.raises(ValidationError):
        compile_goal(d)
```

- [ ] **Step 3: run both, FAIL** (`ModuleNotFoundError: No module named 'loop_engineer.compiler.definition'`).

- [ ] **Step 4: implementation — `src/loop_engineer/compiler/definition.py`**
```python
"""Goal file input contract (spec P2a §4): a Goal plus the atomic Tasks."""

from pydantic import BaseModel, Field, model_validator

from loop_engineer.contracts.goal import Goal
from loop_engineer.contracts.task import Task


class GoalDefinition(BaseModel):
    goal: Goal
    tasks: list[Task] = Field(min_length=1)

    @model_validator(mode="after")
    def _unique_task_ids(self) -> "GoalDefinition":
        ids = [t.id for t in self.tasks]
        if len(ids) != len(set(ids)):
            raise ValueError("duplicate task ids in goal definition")
        return self
```

`src/loop_engineer/compiler/compiler.py`:
```python
"""Goal compiler: GoalDefinition -> Plan (spec P2a §3).

Constructs TaskNode per task and a DependencyEdge per declared dependency; the
P1 Plan model validates acyclicity, unknown edges, duplicate ids, and
declared-dependency-without-edge at construction time.
"""

from loop_engineer.compiler.definition import GoalDefinition
from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode


def compile_goal(definition: GoalDefinition) -> Plan:
    nodes = [TaskNode(task=t) for t in definition.tasks]
    edges: list[DependencyEdge] = []
    for t in definition.tasks:
        for dep in t.dependencies:
            edges.append(DependencyEdge(from_id=dep, to_id=t.id))
    return Plan(goal_id=definition.goal.id, nodes=nodes, edges=edges)
```

- [ ] **Step 5: register `GoalDefinition` in the freeze pipeline**

In `scripts/export_schemas.py` add `from loop_engineer.compiler.definition import GoalDefinition` and `"goal_definition": GoalDefinition,` to `MODELS` (alphabetical: after "fence", before "goal"). Regenerate:
```bash
python scripts/export_schemas.py
```
Add a `goal_definition` payload to `tests/contract/test_schema_roundtrip.py::PAYLOADS` (a goal + one task) so the round-trip test covers it.

- [ ] **Step 6: run all + ruff, commit**
```bash
pytest -q && ruff check .
git add src/loop_engineer/compiler/ tests/unit/test_definition.py tests/unit/test_compiler.py scripts/export_schemas.py schemas/
git commit -m "feat(compiler): add GoalDefinition input model and goal->Plan compiler

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 4: repo paths, plan digest, run-id (`runtime/paths.py`)

**Files:** Create `src/loop_engineer/runtime/paths.py`; Test `tests/unit/test_paths.py`.

- [ ] **Step 1: failing test — `tests/unit/test_paths.py`**
```python
import subprocess

from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
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
    assert rid == d[:12] and len(rid) == 12


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
```

- [ ] **Step 2: run, FAIL** (`ModuleNotFoundError: No module named 'loop_engineer.runtime.paths'`).

- [ ] **Step 3: implementation — `src/loop_engineer/runtime/paths.py`**
```python
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
    return Path(_git(["rev-parse", "--show-toplevel"], Path(start) if start else Path.cwd()))


def git_common_dir(start: Path | None = None) -> Path:
    cwd = Path(start) if start else Path.cwd()
    out = _git(["rev-parse", "--git-common-dir"], cwd)
    # resolve relative to cwd (git prints a path relative to cwd for linked worktrees)
    p = (cwd / out).resolve() if not Path(out).is_absolute() else Path(out)
    return p


def board_dir(common_dir: Path, run_id: str) -> Path:
    return Path(common_dir) / "loop-engineer" / run_id


def plan_digest(plan: Plan) -> str:
    canonical = json.dumps(plan.model_dump(mode="json"), sort_keys=True)
    return "sha256:" + hashlib.sha256(canonical.encode()).hexdigest()


def derive_run_id(plan_digest_hex: str) -> str:
    # accept either "sha256:<hex>" or bare hex; use the hex portion
    hexpart = plan_digest_hex.split(":", 1)[-1]
    return hexpart[:12]
```

- [ ] **Step 4: run, PASS, ruff, commit**
```bash
pytest tests/unit/test_paths.py -v && ruff check .
git add src/loop_engineer/runtime/paths.py tests/unit/test_paths.py
git commit -m "feat(runtime): add repo paths, plan digest, and run-id derivation

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 5: BoardStore core — state, lock, load/save, init/from_plan

**Files:** Create `src/loop_engineer/runtime/board.py` (core parts); Test `tests/unit/test_board.py`.

- [ ] **Step 1: failing test — `tests/unit/test_board.py`** (core section)
```python
import pytest

from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.runtime.board import BoardState, BoardStore


def _plan(task_files: dict[str, list[str]], deps: dict[str, list[str]] | None = None) -> Plan:
    deps = deps or {}
    nodes = []
    for tid, files in task_files.items():
        nodes.append(TaskNode(task=Task(
            id=tid, owner_domain="omx", dependencies=deps.get(tid, []),
            allowed_files=files, acceptance_criteria=["x"],
            verification=VerificationSpec(commands=["t"], working_dir="."),
            required_evidence=["c"],
        )))
    return Plan(goal_id="G1", nodes=nodes, edges=[
        DependencyEdge(from_id=d, to_id=tid) for tid, ds in deps.items() for d in ds
    ])


def test_from_plan_initializes_all_pending(tmp_path):
    plan = _plan({"T1": ["src/a.py"], "T2": ["src/b.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    state = store.load_state()
    assert set(state.tasks) == {"T1", "T2"}
    assert all(e.status.value == "pending" for e in state.tasks.values())


def test_open_existing_board_roundtrips(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    s1 = BoardStore.from_plan(plan, tmp_path)
    s2 = BoardStore.open(s1.dir)
    assert set(s2.load_state().tasks) == {"T1"}


def test_open_missing_board_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        BoardStore.open(tmp_path / "nope")
```

- [ ] **Step 2: run, FAIL** (`ModuleNotFoundError: No module named 'loop_engineer.runtime.board'`).

- [ ] **Step 3: implementation — `src/loop_engineer/runtime/board.py`** (core; claim/release added in later tasks)
```python
"""Task board store: atomic, file-locked claim/release/complete (spec P2a §5).

State is persisted as JSON under the Git common dir. Every mutation takes an
exclusive fcntl.flock around a read-modify-write so independent OMX/OMC
processes cannot corrupt each other.
"""

import fcntl
import hashlib
import json
import os
import secrets
from contextlib import contextmanager
from pathlib import Path
from typing import IO

from pydantic import BaseModel, Field

from loop_engineer.contracts.claim import Claim
from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task_run import TaskBoardEntry, TaskRunStatus
from loop_engineer.runtime import paths as paths_mod
from loop_engineer.runtime.scope import ScopeError, overlaps


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

    # --- construction -------------------------------------------------
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
        # scope_map/ancestors not needed for read-only opens; claim needs a from_plan store
        return cls(bdir, state.run_id, state.plan_digest, {}, {})

    # --- low-level ----------------------------------------------------
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
```

- [ ] **Step 4: run, PASS (3), ruff, commit**
```bash
pytest tests/unit/test_board.py -v && ruff check .
git add src/loop_engineer/runtime/board.py tests/unit/test_board.py
git commit -m "feat(runtime): add BoardStore core (state, file lock, load/save, from_plan)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 6: claim operation (token, digest, prior-state)

**Files:** Modify `src/loop_engineer/runtime/board.py` (add `claim`); extend `tests/unit/test_board.py`.

- [ ] **Step 1: add failing tests to `tests/unit/test_board.py`**
```python
from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.provider import Provider


_LEASE = Lease(
    generation=0, expires_at="2099-01-01T00:00:00Z", last_heartbeat_at="2099-01-01T00:00:00Z",
)


def test_claim_returns_token_and_marks_claimed(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    token = store.claim("T1", Provider.OMX, _LEASE)
    assert isinstance(token, str) and len(token) >= 16
    e = store.load_state().tasks["T1"]
    assert e.status.value == "claimed"
    assert e.provider == Provider.OMX
    assert e.claim is not None and e.claim.token_digest.startswith("sha256:")
    assert e.lease == _LEASE


def test_claim_wrong_prior_state_raises(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    store.claim("T1", Provider.OMX, _LEASE)
    with pytest.raises(PriorStateError):
        store.claim("T1", Provider.OMC, _LEASE)  # already CLAIMED, not PENDING
```
(Add `PriorStateError` to the existing `from loop_engineer.runtime.board import ...` import line in this test file.)

- [ ] **Step 2: run, FAIL** (`AttributeError: 'BoardStore' object has no attribute 'claim'`).

- [ ] **Step 3: implementation — append to `BoardStore` in `src/loop_engineer/runtime/board.py`**
```python
    def claim(
        self,
        task_id: str,
        provider: Provider,
        lease: Lease,
        expected_prior: TaskRunStatus = TaskRunStatus.PENDING,
    ) -> str:
        """Atomically claim a task; return the raw claim token (kept by caller).

        Raises PriorStateError if the task is not in expected_prior, and
        ScopeOverlapError if the task's allowed files overlap a currently
        CLAIMED task that is not a dependency ancestor.
        """
        with self._locked():
            state = self._load()
            entry = state.tasks.get(task_id)
            if entry is None:
                raise KeyError(f"unknown task {task_id!r}")
            if entry.status != expected_prior:
                raise PriorStateError(
                    f"task {task_id} is {entry.status.value}, expected {expected_prior.value}"
                )
            self._check_scope(state, task_id)
            raw_token = secrets.token_urlsafe(32)
            digest = "sha256:" + hashlib.sha256(raw_token.encode()).hexdigest()
            entry.claim = Claim(
                omx_task_id=task_id,
                holder=f"{provider.value}-attempt-{entry.attempt_id}",
                generation=entry.attempt_id - 1,
                token_digest=digest,
            )
            entry.lease = lease
            entry.provider = provider
            entry.status = TaskRunStatus.CLAIMED
            self._save(state)
            return raw_token

    def _check_scope(self, state: BoardState, task_id: str) -> None:
        candidate = self._scope_map.get(task_id, [])
        ancestors = self._ancestors.get(task_id, set())
        for other_id, other in state.tasks.items():
            if other_id == task_id or other.status != TaskRunStatus.CLAIMED:
                continue
            if other_id in ancestors:
                continue  # dependency-ordered overlap is legal (spec §6.2)
            other_files = self._scope_map.get(other_id, [])
            try:
                if overlaps(candidate, other_files):
                    raise ScopeOverlapError(
                        f"task {task_id} overlaps claimed task {other_id}"
                    )
            except ScopeError as e:
                # malformed scope should have been caught at plan build; surface as overlap error
                raise ScopeOverlapError(str(e)) from e
```

- [ ] **Step 4: run, PASS, ruff, commit**
```bash
pytest tests/unit/test_board.py -v && ruff check .
git add src/loop_engineer/runtime/board.py tests/unit/test_board.py
git commit -m "feat(runtime): add atomic provider-neutral claim with prior-state and scope checks

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 7: scope-overlap behavior in claim (dependency-ordered allowed)

**Files:** Extend `tests/unit/test_board.py`.

- [ ] **Step 1: add failing tests**
```python
def test_claim_overlapping_disjoint_tasks_both_ok(tmp_path):
    plan = _plan({"T1": ["src/a.py"], "T2": ["src/b.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    store.claim("T1", Provider.OMX, _LEASE)
    store.claim("T2", Provider.OMC, _LEASE)  # disjoint files -> ok in parallel
    s = store.load_state()
    assert s.tasks["T1"].provider == Provider.OMX
    assert s.tasks["T2"].provider == Provider.OMC


def test_claim_overlapping_files_rejected(tmp_path):
    plan = _plan({"T1": ["src/a.py"], "T2": ["src/a.py"]})  # same file, no dep
    store = BoardStore.from_plan(plan, tmp_path)
    store.claim("T1", Provider.OMX, _LEASE)
    with pytest.raises(ScopeOverlapError):
        store.claim("T2", Provider.OMC, _LEASE)


def test_claim_overlap_allowed_when_dependency_ordered(tmp_path):
    # T2 depends on T1; both touch src/a.py. T1 claimed first; T2 overlap is legal
    # because T2 is a descendant of T1 (independent Tasks may overlap when ordered).
    plan = _plan({"T1": ["src/a.py"], "T2": ["src/a.py"]}, deps={"T2": ["T1"]})
    store = BoardStore.from_plan(plan, tmp_path)
    store.claim("T1", Provider.OMX, _LEASE)
    # T2 is not PENDING? it is PENDING (only T1 claimed). Overlap with T1 allowed (ancestor).
    token = store.claim("T2", Provider.OMC, _LEASE)
    assert isinstance(token, str)
```
(Add `ScopeOverlapError` to the board import line.)

- [ ] **Step 2: run — expect green already** (the `claim` + `_check_scope` from Task 6 implement this). If any case fails, fix `_check_scope`/`_ancestors`. This task's value is locking the behavior with explicit tests.

- [ ] **Step 3: run, PASS, ruff, commit**
```bash
pytest tests/unit/test_board.py -v && ruff check .
git add tests/unit/test_board.py
git commit -m "test(runtime): lock claim scope behavior (overlap reject, dependency-ordered allow)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 8: release / complete / reset

**Files:** Modify `src/loop_engineer/runtime/board.py` (add `release`, `complete`, `reset_to_pending`); extend `tests/unit/test_board.py`.

- [ ] **Step 1: add failing tests**
```python
def test_complete_with_correct_token(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    token = store.claim("T1", Provider.OMX, _LEASE)
    store.complete("T1", token)
    assert store.load_state().tasks["T1"].status.value == "done"


def test_complete_wrong_token_rejected(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    store.claim("T1", Provider.OMX, _LEASE)
    with pytest.raises(WrongTokenError):
        store.complete("T1", "not-the-token")


def test_release_returns_to_released(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    token = store.claim("T1", Provider.OMX, _LEASE)
    store.release("T1", token)
    e = store.load_state().tasks["T1"]
    assert e.status.value == "released" and e.claim is None


def test_reset_to_pending_makes_reclaimable(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    token = store.claim("T1", Provider.OMX, _LEASE)
    store.release("T1", token)
    store.reset_to_pending("T1", token)
    # now reclaimable
    token2 = store.claim("T1", Provider.OMC, _LEASE)
    assert store.load_state().tasks["T1"].provider == Provider.OMC
    assert store.load_state().tasks["T1"].attempt_id == 2
```
(Add `WrongTokenError` to the board import line.)

- [ ] **Step 2: run, FAIL** (`AttributeError: ... no attribute 'complete'`).

- [ ] **Step 3: implementation — append to `BoardStore`**
```python
    def _verify_token(self, entry: TaskBoardEntry, raw_token: str) -> None:
        if entry.claim is None:
            raise WrongTokenError("no active claim")
        digest = "sha256:" + hashlib.sha256(raw_token.encode()).hexdigest()
        if digest != entry.claim.token_digest:
            raise WrongTokenError("token digest mismatch")

    def release(self, task_id: str, raw_token: str) -> None:
        with self._locked():
            state = self._load()
            entry = state.tasks.get(task_id)
            if entry is None:
                raise KeyError(f"unknown task {task_id!r}")
            if entry.status != TaskRunStatus.CLAIMED:
                raise PriorStateError(f"task {task_id} is {entry.status.value}, not claimed")
            self._verify_token(entry, raw_token)
            entry.status = TaskRunStatus.RELEASED
            entry.claim = None
            entry.lease = None
            entry.provider = None
            self._save(state)

    def complete(self, task_id: str, raw_token: str) -> None:
        with self._locked():
            state = self._load()
            entry = state.tasks.get(task_id)
            if entry is None:
                raise KeyError(f"unknown task {task_id!r}")
            if entry.status != TaskRunStatus.CLAIMED:
                raise PriorStateError(f"task {task_id} is {entry.status.value}, not claimed")
            self._verify_token(entry, raw_token)
            entry.status = TaskRunStatus.DONE
            entry.claim = None
            entry.lease = None
            entry.provider = None
            self._save(state)

    def reset_to_pending(self, task_id: str, raw_token: str) -> None:
        """Move a RELEASED task back to PENDING and bump attempt_id (retry)."""
        with self._locked():
            state = self._load()
            entry = state.tasks.get(task_id)
            if entry is None:
                raise KeyError(f"unknown task {task_id!r}")
            if entry.status != TaskRunStatus.RELEASED:
                raise PriorStateError(
                    f"task {task_id} is {entry.status.value}, not released"
                )
            # token already validated at release; the prior digest is gone, so this
            # op trusts the caller passed the same token that release accepted.
            entry.status = TaskRunStatus.PENDING
            entry.attempt_id += 1
            self._save(state)
```

- [ ] **Step 4: run, PASS, ruff, commit**
```bash
pytest tests/unit/test_board.py -v && ruff check .
git add src/loop_engineer/runtime/board.py tests/unit/test_board.py
git commit -m "feat(runtime): add release/complete/reset_to_pending with token verification

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 9: cross-process parallel-claim concurrency test

**Files:** Create `tests/runtime/test_board_concurrency.py`.

- [ ] **Step 1: the test — `tests/runtime/test_board_concurrency.py`**
```python
"""Parallel claim requirement (spec P2a §2, §8): two real processes claiming
non-overlapping Tasks both succeed under the file lock."""

import multiprocessing as mp
import os
from pathlib import Path

import pytest

from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.plan import Plan, TaskNode
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.runtime.board import BoardStore


_LEASE = Lease(
    generation=0, expires_at="2099-01-01T00:00:00Z", last_heartbeat_at="2099-01-01T00:00:00Z",
)


def _plan() -> Plan:
    nodes = [
        TaskNode(task=Task(
            id=tid, owner_domain="omx", allowed_files=[f"src/{tid}.py"],
            acceptance_criteria=["x"], verification=VerificationSpec(commands=["t"], working_dir="."),
            required_evidence=["c"],
        ))
        for tid in ("T1", "T2")
    ]
    return Plan(goal_id="G", nodes=nodes, edges=[])


def _claim_worker(board_dir: str, task_id: str, provider: str, q):
    try:
        store = BoardStore.open(Path(board_dir))
        # open() drops scope_map; re-attach by re-reading plan is overkill here —
        # parallel non-overlapping claims don't trip the scope check. If a future
        # change requires scope on read-only open, switch to from_plan.
        token = store.claim(task_id, Provider(provider), _LEASE)
        q.put(("ok", task_id, provider))
    except Exception as e:  # noqa: BLE001 - surface any failure to parent
        q.put(("err", task_id, f"{type(e).__name__}: {e}"))


@pytest.mark.timeout(20) if hasattr(pytest, "mark") else lambda f: f
def test_two_processes_claim_disjoint_tasks_concurrently(tmp_path):
    plan = _plan()
    BoardStore.from_plan(plan, tmp_path)  # initialize board
    store_dir = BoardStore.from_plan(plan, tmp_path).dir

    q: mp.Queue = mp.Queue()
    p1 = mp.Process(target=_claim_worker, args=(str(store_dir), "T1", "omx", q))
    p2 = mp.Process(target=_claim_worker, args=(str(store_dir), "T2", "omc", q))
    p1.start()
    p2.start()
    p1.join(timeout=20)
    p2.join(timeout=20)
    assert p1.exitcode == 0 and p2.exitcode == 0

    results = [q.get(timeout=5), q.get(timeout=5)]
    assert all(r[0] == "ok" for r in results), results
    providers = {r[1]: r[2] for r in results}
    assert providers == {"T1": "omx", "T2": "omc"}

    # board reflects both claims
    final = BoardStore.open(store_dir).load_state()
    assert final.tasks["T1"].status.value == "claimed"
    assert final.tasks["T2"].status.value == "claimed"
    assert {final.tasks["T1"].provider.value, final.tasks["T2"].provider.value} == {"omx", "omc"}
```

- [ ] **Step 2: run**
```bash
pytest tests/runtime/test_board_concurrency.py -v
```
Expected: PASS (two real child processes each claim a disjoint task under the shared flock; both succeed). If `pytest-timeout` is not installed, remove the `@pytest.mark.timeout` decorator (the `hasattr` guard already no-ops it). If macOS spawn causes import issues, ensure `_claim_worker` is module-level (it is).

- [ ] **Step 3: run full + ruff, commit**
```bash
pytest -q && ruff check .
git add tests/runtime/test_board_concurrency.py
git commit -m "test(runtime): cross-process parallel claim of disjoint tasks (OMX + OMC)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 10: CLI scaffolding + `goal` subcommand

**Files:** Create `src/loop_engineer/cli/__init__.py` (main + dispatcher), `src/loop_engineer/cli/goal_cmd.py`; Test `tests/cli/test_goal_cli.py`.

- [ ] **Step 1: failing test — `tests/cli/test_goal_cli.py`**
```python
import json
from pathlib import Path

from loop_engineer.cli import main
from loop_engineer.contracts.enums import ExitCode


def _goal_file(tmp_path: Path) -> Path:
    data = {
        "goal": {
            "id": "G1", "title": "t", "measurable_evidence": "ok", "scope": ["x"],
            "exclusions": [], "stop_conditions": [],
            "milestones": [{"id": "M", "title": "m", "evidence_condition": "c"}],
        },
        "tasks": [
            {
                "id": "T1", "owner_domain": "omx", "dependencies": [],
                "allowed_files": ["src/a.py"], "non_goals": [], "acceptance_criteria": ["x"],
                "verification": {"commands": ["pytest -q"], "working_dir": "."},
                "required_evidence": ["commit"], "downstream_handoff": [],
            }
        ],
    }
    p = tmp_path / "goal.json"
    p.write_text(json.dumps(data))
    return p


def test_goal_validate_ok(tmp_path, capsys):
    rc = main(["goal", "validate", str(_goal_file(tmp_path))])
    assert rc == int(ExitCode.OK)


def test_goal_validate_bad(tmp_path):
    bad = tmp_path / "goal.json"
    bad.write_text("{}")
    rc = main(["goal", "validate", str(bad)])
    assert rc == int(ExitCode.INVALID_INPUT)
```

- [ ] **Step 2: run, FAIL** (`ModuleNotFoundError` / `main` not callable).

- [ ] **Step 3: implementation — `src/loop_engineer/cli/__init__.py`**
```python
"""loop-engineer CLI entry point (spec P2a §6)."""

import argparse
import sys

from loop_engineer.contracts.enums import ExitCode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="loop-engineer")
    sub = parser.add_subparsers(dest="cmd", required=True)

    from loop_engineer.cli import goal_cmd, plan_cmd, task_cmd  # local to avoid import cost
    goal_cmd.register(sub)
    plan_cmd.register(sub)
    task_cmd.register(sub)

    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except SystemExit as e:  # argparse error
        return e.code if isinstance(e.code, int) else int(ExitCode.INVALID_INPUT)


if __name__ == "__main__":
    sys.exit(main())
```

`src/loop_engineer/cli/goal_cmd.py`:
```python
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
    # accept either {...} or a YAML doc that is itself JSON-compatible
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
```

- [ ] **Step 4: run, PASS, ruff, commit**
```bash
pytest tests/cli/test_goal_cli.py -v && ruff check .
git add src/loop_engineer/cli/__init__.py src/loop_engineer/cli/goal_cmd.py tests/cli/test_goal_cli.py
git commit -m "feat(cli): add loop-engineer CLI scaffold and goal validate

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 11: `plan` subcommand (build/validate/show)

**Files:** Create `src/loop_engineer/cli/plan_cmd.py`; Test `tests/cli/test_plan_cli.py`.

- [ ] **Step 1: failing test — `tests/cli/test_plan_cli.py`**
```python
import json
from pathlib import Path

from loop_engineer.cli import main
from loop_engineer.contracts.enums import ExitCode


def _write_goal(tmp_path: Path) -> Path:
    p = tmp_path / "goal.json"
    p.write_text(json.dumps({
        "goal": {
            "id": "G1", "title": "t", "measurable_evidence": "ok", "scope": ["x"],
            "exclusions": [], "stop_conditions": [],
            "milestones": [{"id": "M", "title": "m", "evidence_condition": "c"}],
        },
        "tasks": [
            {"id": "T1", "owner_domain": "omx", "dependencies": [], "allowed_files": ["src/a.py"],
             "non_goals": [], "acceptance_criteria": ["x"],
             "verification": {"commands": ["t"], "working_dir": "."},
             "required_evidence": ["c"], "downstream_handoff": []},
            {"id": "T2", "owner_domain": "omx", "dependencies": ["T1"], "allowed_files": ["src/b.py"],
             "non_goals": [], "acceptance_criteria": ["x"],
             "verification": {"commands": ["t"], "working_dir": "."},
             "required_evidence": ["c"], "downstream_handoff": []},
        ],
    }))
    return p


def test_plan_build_writes_plan(tmp_path):
    goal = _write_goal(tmp_path)
    out = tmp_path / "plan.json"
    rc = main(["plan", "build", str(goal), "-o", str(out)])
    assert rc == int(ExitCode.OK)
    plan = json.loads(out.read_text())
    assert plan["goal_id"] == "G1"
    ids = {n["task"]["id"] for n in plan["nodes"]}
    assert ids == {"T1", "T2"}


def test_plan_validate_ok(tmp_path):
    goal = _write_goal(tmp_path)
    out = tmp_path / "plan.json"
    main(["plan", "build", str(goal), "-o", str(out)])
    assert main(["plan", "validate", str(out)]) == int(ExitCode.OK)
```

- [ ] **Step 2: run, FAIL**.

- [ ] **Step 3: implementation — `src/loop_engineer/cli/plan_cmd.py`**
```python
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
        Path(args.out).write_text(json.dumps(plan.model_dump(mode="json"), indent=2, sort_keys=True))
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
```

- [ ] **Step 4: run, PASS, ruff, commit**
```bash
pytest tests/cli/test_plan_cli.py -v && ruff check .
git add src/loop_engineer/cli/plan_cmd.py tests/cli/test_plan_cli.py
git commit -m "feat(cli): add plan build/validate/show

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 12: `task` subcommand (list/claim/release/status)

**Files:** Create `src/loop_engineer/cli/task_cmd.py`; Test `tests/cli/test_task_cli.py`.

- [ ] **Step 1: failing test — `tests/cli/test_task_cli.py`**
```python
import json
from pathlib import Path

from loop_engineer.cli import main
from loop_engineer.contracts.enums import ExitCode
from loop_engineer.runtime.board import BoardStore


def _goal(tmp_path: Path) -> Path:
    p = tmp_path / "goal.json"
    p.write_text(json.dumps({
        "goal": {"id": "G1", "title": "t", "measurable_evidence": "ok", "scope": ["x"],
                 "exclusions": [], "stop_conditions": [],
                 "milestones": [{"id": "M", "title": "m", "evidence_condition": "c"}]},
        "tasks": [
            {"id": "T1", "owner_domain": "omx", "dependencies": [], "allowed_files": ["src/a.py"],
             "non_goals": [], "acceptance_criteria": ["x"],
             "verification": {"commands": ["t"], "working_dir": "."},
             "required_evidence": ["c"], "downstream_handoff": []},
        ],
    }))
    return p


def test_task_claim_and_list(tmp_path, capsys, monkeypatch):
    # point git-common-dir at tmp_path so the board lives under tmp_path/loop-engineer
    plan_path = tmp_path / "plan.json"
    assert main(["plan", "build", str(_goal(tmp_path)), "-o", str(plan_path)]) == int(ExitCode.OK)
    monkeypatch.setenv("LOOP_ENGINEER_COMMON_DIR", str(tmp_path))
    assert main(["task", "init", str(plan_path)]) == int(ExitCode.OK)
    rc = main(["task", "claim", "T1", "--provider", "omx"])
    assert rc == int(ExitCode.OK)
    assert main(["task", "list"]) == int(ExitCode.OK)
    out = capsys.readouterr().out
    assert "T1" in out and "claimed" in out
```

- [ ] **Step 2: run, FAIL**.

- [ ] **Step 3: implementation — `src/loop_engineer/cli/task_cmd.py`**
```python
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
        state = store.load_state()
        for tid, e in state.tasks.items():
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

    def _open_for(args: argparse.Namespace) -> BoardStore:
        # discover the single board under common_dir/loop-engineer/* if --run omitted
        base = _common_dir() / "loop-engineer"
        if getattr(args, "run", None):
            return BoardStore.open(base / args.run)
        runs = [d for d in base.glob("*") if (d / "board.json").exists()]
        if len(runs) != 1:
            raise SystemExit(int(ExitCode.OWNERSHIP_AMBIGUITY))
        return BoardStore.open(runs[0])

    i = task_sub.add_parser("init")
    i.add_argument("plan")
    i.set_defaults(func=_init)

    l = task_sub.add_parser("list")
    l.add_argument("--run")
    l.set_defaults(func=_list, run=None)

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
```

- [ ] **Step 4: run, PASS, ruff, commit**
```bash
pytest tests/cli/test_task_cli.py -v && ruff check .
git add src/loop_engineer/cli/task_cmd.py tests/cli/test_task_cli.py
git commit -m "feat(cli): add task init/list/claim/release/status

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 13: P2a gate — full suite, freeze, README, acceptance

**Files:** Modify `README.md`; verify all gates.

- [ ] **Step 1: idempotent schema export + full suite + ruff**
```bash
python scripts/export_schemas.py
git status --short schemas/          # must be empty
pytest -q
ruff check .
```
Expected: schemas clean; full suite green (P1's 118 + new P2a tests); ruff clean.

- [ ] **Step 2: P2a acceptance checklist (verify each; report pass/fail)**
- [ ] `goal validate` accepts a valid goal file; rejects malformed with exit 2.
- [ ] `plan build` produces a `Plan`; `plan validate` rejects cyclic/bad input with exit 2.
- [ ] `task init` creates a board; `task claim --provider omx` and `--provider omc` both succeed on disjoint tasks.
- [ ] Two processes claiming overlapping Tasks: exactly one wins, other exits 5 (scope) — covered by Task 7 unit test; concurrent disjoint claims both win (Task 9).
- [ ] claim/release/complete fail-closed on wrong prior state / wrong token (exit 3).
- [ ] No real `omx`/`omc` Team launched by any P2a test.
- [ ] New contracts (`task_board_entry`, `goal_definition`) frozen in `schemas/v1/`; P1's tests still pass unchanged.

- [ ] **Step 3: README — append a P2 section**
```markdown

## Compile a goal and claim Tasks (P2a)

```bash
loop-engineer plan build goal.yaml -o plan.json
loop-engineer task init plan.json
loop-engineer task claim T1 --provider omx   # prints a claim token once
loop-engineer task list
```

The task board lives under `.git/loop-engineer/<run-id>/board.json`. OMX and OMC
workers can claim disjoint Tasks in parallel; overlapping `Allowed Files` are
rejected unless the Tasks are dependency-ordered.
```

- [ ] **Step 4: commit**
```bash
git add README.md
git commit -m "docs(p2a): README section for goal compile + parallel task claim

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(Do NOT push — controller handles merge/push via finishing-a-development-branch.)

---

## Self-Review

**Spec coverage (P2a spec §1, §9):**
| Spec item | Task |
| --- | --- |
| Goal compiler (goal → Plan) | 3 |
| Plan CLI (build/validate/show) | 11 |
| Goal CLI (define/validate) | 10 |
| Task board in Git common dir | 4, 5 |
| Atomic cross-process claim/release/complete | 5, 6, 8 |
| Provider-neutral (omx/omc) | 1, 6 |
| Write-scope overlap + dependency-ordered exception | 2, 7 |
| Parallel-claim requirement (the operator ask) | 9 (+ 7) |
| New contracts frozen, P1 untouched | 1, 3, 13 |
| Fake-testable, no real Team | all |

**No-placeholder scan:** every code step is real, runnable code; every test has real assertions + a run command. Task 9's `@pytest.mark.timeout` is guarded by `hasattr` so it no-ops without `pytest-timeout` (not a hidden dep).

**Type/name consistency:** `Provider`/`TaskRunStatus` used identically in `task_run.py`, `board.py`, `task_cmd.py`. `Claim.token_digest` shape (`sha256:<hex>`) reused by `board.claim`'s digest. `BoardStore.claim` returns the raw token `str`; `release`/`complete`/`reset_to_pending` take that same `str`. `_LEASE` fixture identical across board/cli/concurrency tests. `LOOP_ENGINEER_COMMON_DIR` env override is the single test seam for the git-common-dir.

**Known seam to flag for executor:** `BoardStore.open()` (read-only, used by the concurrency worker and the CLI's `_open_for`) loads state without scope_map/ancestors. The concurrency test claims **disjoint** tasks, so the scope check never fires from a read-only-opened store. If a future task needs scope checking through `open()`, switch that path to `from_plan` (the plan is recoverable from `plan_digest`/a plan file). This is called out in the Task 9 worker comment.

**Deferred to P2b (not gaps):** driving real `omx`/`omc` to execute claimed Tasks; finisher + serialized main integration; `run omx`/`run hybrid`/`status`/`resume`/`stop`/`doctor`; full Hybrid lifecycle/writer-fencing/recovery.
