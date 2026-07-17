# Loop Engineer — P2b-1 (Conflict Graph + Planner) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use `- [ ]` checkboxes.

**Goal:** Pure-logic scheduling brain — given a Plan, board state, per-task execution metadata, and a capacity config, compute eligibility, the pairwise conflict graph with reasons, engine recommendation, and a capacity-respecting launch plan. No subprocess, no real `omx`/`omc`.

**Architecture:** `scheduler/eligibility.py` (derived-ready + protected-zone block), `scheduler/conflicts.py` (six dimensions), `scheduler/engine.py` (routing heuristic), `scheduler/planner.py` (capacity + launch plan), `scheduler/models.py` (config + output models). Reuses P2a `Plan`/`BoardStore`/`scope`.

**Tech Stack:** Python ≥ 3.11, pydantic v2, pytest, ruff. **Spec:** [2026-07-17-p2b1-conflict-graph-design.md](../specs/2026-07-17-p2b1-conflict-graph-design.md). **Worktree:** `.worktrees/p2b1-conflict-graph`, branch `p2b1-conflict-graph`. **Python:** `python3.11`. Activate `.venv` (recreate — fresh worktree).

**Key decisions:** `TaskExecutionMeta` is the only new frozen contract (additive); it is a **separate planner input**, NOT added to `GoalDefinition` (P2a model untouched). `global_max` is the combined OMX+OMC cap. Protected-zone (`refer/`) is a task-level hard block computed in eligibility, not a pairwise dimension.

---

## File structure (additive)

```
src/loop_engineer/scheduler/
├── __init__.py
├── models.py        # TaskExecutionMeta, CapacityConfig, PlannerConfig, Conflict, Launch, LaunchPlan, ConflictDimension
├── eligibility.py   # eligible_tasks(...) -> (eligible set, blocked conflicts); protected-zone
├── conflicts.py     # conflicts_for(candidate, ...) -> list[Conflict]; dims A-E
├── engine.py        # recommend_engine(task, meta) -> Provider
└── planner.py       # plan_launch(...) -> LaunchPlan
tests/scheduler/
├── __init__.py
├── test_eligibility.py
├── test_conflicts.py
├── test_engine.py
└── test_planner.py
```

---

## Task 0: scaffolding

**Files:** Create `src/loop_engineer/scheduler/__init__.py`, `tests/scheduler/__init__.py` (markers); create the venv.

- [ ] **Step 1: markers** — both files: `"""Package marker."""`
- [ ] **Step 2: venv + verify**
```bash
cd /Users/xielaoban/Documents/loop-engineer/.worktrees/p2b1-conflict-graph
python3.11 -m venv .venv && . .venv/bin/activate
pip install -e ".[dev]"
pytest -q   # P1+P2a 168 tests pass
ruff check .
```
- [ ] **Step 3: commit**
```bash
git add src/loop_engineer/scheduler/__init__.py tests/scheduler/__init__.py
git commit -m "chore(p2b1): scaffold scheduler package

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 1: scheduler models (`models.py`) + freeze TaskExecutionMeta

**Files:** Create `src/loop_engineer/scheduler/models.py`; Test `tests/scheduler/test_models.py`; register `TaskExecutionMeta` in `scripts/export_schemas.py`.

- [ ] **Step 1: failing test — `tests/scheduler/test_models.py`**
```python
from loop_engineer.contracts.provider import Provider
from loop_engineer.scheduler.models import (
    CapacityConfig, Conflict, ConflictDimension, Launch, LaunchPlan,
    PlannerConfig, TaskExecutionMeta,
)


def test_capacity_defaults_match_operator_spec():
    c = CapacityConfig()
    assert (c.omx_max, c.omc_max, c.global_max, c.finish_max, c.burst_max) == (3, 3, 3, 1, 4)


def test_planner_config_default_protected_refer():
    assert PlannerConfig().protected_paths == ["refer/"]


def test_task_execution_meta_defaults():
    m = TaskExecutionMeta(task_id="T1")
    assert m.migration_dir is None and m.ports == [] and m.engine_hint is None


def test_conflict_and_launch_models():
    c = Conflict(candidate="T2", other="T1", dimension=ConflictDimension.ALLOWED_FILES, reason="x")
    l = Launch(task_id="T2", provider=Provider.OMC)
    lp = LaunchPlan(launch=[l], skipped=[c], blocked=[], active_omx=1, active_omc=0, remaining_global=2, burst=False)
    assert lp.launch[0].provider == Provider.OMC
```

- [ ] **Step 2: FAIL** (`ModuleNotFoundError: No module named 'loop_engineer.scheduler.models'`).

- [ ] **Step 3: implementation — `src/loop_engineer/scheduler/models.py`**
```python
"""Scheduler config, per-task execution metadata, and planner output models (spec P2b-1 §2/§6)."""

from enum import StrEnum

from pydantic import BaseModel, Field

from loop_engineer.contracts.provider import Provider


class TaskExecutionMeta(BaseModel):
    """Optional per-Task metadata for conflict dimensions P2a's Task does not carry.

    This is a separate planner input; it is NOT added to GoalDefinition.
    """

    task_id: str = Field(min_length=1)
    migration_dir: str | None = None
    migration_after: list[str] = Field(default_factory=list)
    ports: list[int] = Field(default_factory=list)
    db_name: str | None = None
    browser_profile: str | None = None
    engine_hint: Provider | None = None


class CapacityConfig(BaseModel):
    omx_max: int = 3
    omc_max: int = 3
    global_max: int = 3  # combined OMX+OMC cap, not omx_max + omc_max
    finish_max: int = 1
    burst_max: int = 4


class PlannerConfig(BaseModel):
    capacity: CapacityConfig = Field(default_factory=CapacityConfig)
    protected_paths: list[str] = Field(default_factory=lambda: ["refer/"])
    target_omc: int = 2
    target_omx: int = 1
    # Burst preconditions that the caller (P2b-3 rolling loop) must verify:
    # main clean, no finisher, no recovery. Default False = never burst.
    burst_eligible: bool = False


class ConflictDimension(StrEnum):
    DEPENDENCY = "dependency"
    ALLOWED_FILES = "allowed_files"
    MIGRATION = "migration"
    RESOURCE = "resource"
    LIFECYCLE = "lifecycle"
    PROTECTED = "protected"


class Conflict(BaseModel):
    candidate: str
    other: str | None = None  # None for task-level (protected) blocks
    dimension: ConflictDimension
    reason: str


class Launch(BaseModel):
    task_id: str
    provider: Provider


class LaunchPlan(BaseModel):
    launch: list[Launch]
    skipped: list[Conflict]       # eligible but conflicts with an active task
    blocked: list[Conflict]       # task-level hard block (protected zone)
    active_omx: int
    active_omc: int
    remaining_global: int
    burst: bool
```

- [ ] **Step 4: register `TaskExecutionMeta` in the freeze pipeline** — `scripts/export_schemas.py`: add `from loop_engineer.scheduler.models import TaskExecutionMeta` and `"task_execution_meta": TaskExecutionMeta,` to `MODELS`. Add a `"task_execution_meta": {"task_id": "T1"}` payload to `tests/contract/test_schema_roundtrip.py::PAYLOADS`. Regenerate:
```bash
python scripts/export_schemas.py
pytest tests/contract/test_schema_freeze_drift.py tests/contract/test_schema_roundtrip.py tests/scheduler/test_models.py -v
```
- [ ] **Step 5: full + ruff, commit**
```bash
pytest -q && ruff check .
git add src/loop_engineer/scheduler/models.py tests/scheduler/test_models.py scripts/export_schemas.py tests/contract/test_schema_roundtrip.py schemas/
git commit -m "feat(scheduler): add planner config, execution meta, and output models

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 2: eligibility + protected-zone (`eligibility.py`)

**Files:** Create `src/loop_engineer/scheduler/eligibility.py`; Test `tests/scheduler/test_eligibility.py`.

- [ ] **Step 1: failing test — `tests/scheduler/test_eligibility.py`**
```python
from loop_engineer.contracts.plan import Plan, TaskNode
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.contracts.task_run import TaskBoardEntry, TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.scheduler.eligibility import eligible_tasks
from loop_engineer.scheduler.models import ConflictDimension, PlannerConfig


def _task(tid, deps=None, files=None):
    return Task(
        id=tid, owner_domain="omx", dependencies=deps or [],
        allowed_files=files or [f"src/{tid}.py"], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["t"], working_dir="."), required_evidence=["c"],
    )


def _plan(tasks):
    return Plan(goal_id="G", nodes=[TaskNode(task=t) for t in tasks], edges=[])


def _board(statuses):
    return BoardState(
        run_id="r", plan_digest="sha256:" + "0" * 64,
        tasks={tid: TaskBoardEntry(task_id=tid, status=st) for tid, st in statuses.items()},
    )


def test_pending_with_done_deps_is_eligible():
    plan = _plan([_task("T1"), _task("T2", deps=["T1"])])
    board = _board({"T1": TaskRunStatus.DONE, "T2": TaskRunStatus.PENDING})
    eligible, blocked = eligible_tasks(plan, board, PlannerConfig())
    assert eligible == {"T2"} and blocked == []


def test_dep_done_only_on_branch_not_eligible():
    # T1 not DONE on board -> T2 not derived-ready
    plan = _plan([_task("T1"), _task("T2", deps=["T1"])])
    board = _board({"T1": TaskRunStatus.PENDING, "T2": TaskRunStatus.PENDING})
    eligible, _ = eligible_tasks(plan, board, PlannerConfig())
    assert eligible == {"T1"}


def test_claimed_and_done_excluded():
    plan = _plan([_task("T1"), _task("T2"), _task("T3")])
    board = _board({"T1": TaskRunStatus.CLAIMED, "T2": TaskRunStatus.DONE, "T3": TaskRunStatus.PENDING})
    eligible, _ = eligible_tasks(plan, board, PlannerConfig())
    assert eligible == {"T3"}


def test_protected_zone_blocked():
    plan = _plan([_task("T1", files=["refer/x.md"]), _task("T2", files=["src/a.py"])])
    board = _board({"T1": TaskRunStatus.PENDING, "T2": TaskRunStatus.PENDING})
    eligible, blocked = eligible_tasks(plan, board, PlannerConfig())
    assert eligible == {"T2"}
    assert [b.candidate for b in blocked] == ["T1"]
    assert blocked[0].dimension == ConflictDimension.PROTECTED
```

- [ ] **Step 2: FAIL** (`ModuleNotFoundError`).

- [ ] **Step 3: implementation — `src/loop_engineer/scheduler/eligibility.py`**
```python
"""Task eligibility + protected-zone hard block (spec P2b-1 §3, §4.F)."""

from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.task_run import TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.runtime.scope import overlaps
from loop_engineer.scheduler.models import Conflict, ConflictDimension, PlannerConfig


def eligible_tasks(
    plan: Plan, board: BoardState, config: PlannerConfig
) -> tuple[set[str], list[Conflict]]:
    """Return (eligible task_ids, task-level blocked conflicts).

    Eligible = not DONE, derived-ready (deps DONE on board), not CLAIMED, not
    protected-zone. Protected-zone Tasks are returned in `blocked`.
    """
    eligible: set[str] = set()
    blocked: list[Conflict] = []
    for node in plan.nodes:
        tid = node.task.id
        entry = board.tasks.get(tid)
        if entry is not None and entry.status == TaskRunStatus.DONE:
            continue
        if overlaps(node.task.allowed_files, config.protected_paths):
            blocked.append(Conflict(
                candidate=tid, other=None, dimension=ConflictDimension.PROTECTED,
                reason=f"allowed_files intersect protected paths {config.protected_paths}",
            ))
            continue
        deps_done = all(
            (d in board.tasks) and (board.tasks[d].status == TaskRunStatus.DONE)
            for d in node.task.dependencies
        )
        if not deps_done:
            continue
        if entry is not None and entry.status == TaskRunStatus.CLAIMED:
            continue
        eligible.add(tid)
    return eligible, blocked
```

- [ ] **Step 4: PASS, ruff, commit**
```bash
pytest tests/scheduler/test_eligibility.py -v && ruff check .
git add src/loop_engineer/scheduler/eligibility.py tests/scheduler/test_eligibility.py
git commit -m "feat(scheduler): add eligibility + protected-zone block

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 3: conflicts A (dependency) + B (allowed-files)

**Files:** Create `src/loop_engineer/scheduler/conflicts.py`; Test `tests/scheduler/test_conflicts.py`.

- [ ] **Step 1: failing test — `tests/scheduler/test_conflicts.py`** (first half)
```python
from loop_engineer.contracts.plan import Plan, TaskNode
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.contracts.task_run import TaskBoardEntry, TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.scheduler.conflicts import conflicts_for
from loop_engineer.scheduler.models import ConflictDimension, TaskExecutionMeta


def _task(tid, deps=None, files=None):
    return Task(
        id=tid, owner_domain="omx", dependencies=deps or [],
        allowed_files=files or [f"src/{tid}.py"], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["t"], working_dir="."), required_evidence=["c"],
    )


def _plan(tasks):
    return Plan(goal_id="G", nodes=[TaskNode(task=t) for t in tasks], edges=[])


def _board(claimed):
    return BoardState(
        run_id="r", plan_digest="sha256:" + "0" * 64,
        tasks={tid: TaskBoardEntry(task_id=tid, status=TaskRunStatus.CLAIMED, provider=Provider.OMX)
               for tid in claimed},
    )


def test_dependency_conflict():
    plan = _plan([_task("T1"), _task("T2", deps=["T1"])])
    board = _board(["T1"])  # T1 active, T2 depends on it
    confs = conflicts_for("T2", plan, board, {})
    assert any(c.dimension == ConflictDimension.DEPENDENCY and c.other == "T1" for c in confs)


def test_allowed_files_conflict():
    plan = _plan([_task("T1", files=["src/a.py"]), _task("T2", files=["src/a.py"])])
    board = _board(["T1"])
    confs = conflicts_for("T2", plan, board, {})
    assert any(c.dimension == ConflictDimension.ALLOWED_FILES for c in confs)


def test_allowed_files_conflict_allowed_when_dependency_ordered():
    plan = _plan([_task("T1", files=["src/a.py"]), _task("T2", deps=["T1"], files=["src/a.py"])])
    board = _board(["T1"])
    confs = conflicts_for("T2", plan, board, {})
    # T2 depends on T1 -> ordered overlap allowed; no ALLOWED_FILES conflict
    assert not any(c.dimension == ConflictDimension.ALLOWED_FILES for c in confs)
```

- [ ] **Step 2: FAIL** (`ModuleNotFoundError`).

- [ ] **Step 3: implementation — `src/loop_engineer/scheduler/conflicts.py`** (dims A, B now; C–E added Task 4)
```python
"""Pairwise conflict detection vs active (CLAIMED) Tasks (spec P2b-1 §4)."""

from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.task_run import TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.runtime.scope import overlaps
from loop_engineer.scheduler.models import Conflict, ConflictDimension, TaskExecutionMeta


def _task_files(plan: Plan, task_id: str) -> list[str]:
    for n in plan.nodes:
        if n.task.id == task_id:
            return list(n.task.allowed_files)
    return []


def _ancestors_in_plan(plan: Plan, task_id: str) -> set[str]:
    direct = {n.task.id: set(n.task.dependencies) for n in plan.nodes}
    seen: set[str] = set()
    stack = list(direct.get(task_id, set()))
    while stack:
        d = stack.pop()
        if d in seen:
            continue
        seen.add(d)
        stack.extend(direct.get(d, set()))
    return seen


def conflicts_for(
    candidate_id: str,
    plan: Plan,
    board: BoardState,
    meta_map: dict[str, TaskExecutionMeta],
) -> list[Conflict]:
    """Conflicts between candidate and every CLAIMED Task (dims A-E)."""
    out: list[Conflict] = []
    candidate_node = next((n for n in plan.nodes if n.task.id == candidate_id), None)
    if candidate_node is None:
        return out
    candidate = candidate_node.task
    ancestors = _ancestors_in_plan(plan, candidate_id)
    for other_id, entry in board.tasks.items():
        if other_id == candidate_id or entry.status != TaskRunStatus.CLAIMED:
            continue
        ordered = other_id in ancestors  # candidate is downstream of other
        # A. dependency
        if other_id in candidate.dependencies or candidate_id in {
            d for n in plan.nodes if n.task.id == other_id for d in n.task.dependencies
        }:
            out.append(Conflict(candidate_id, other_id, ConflictDimension.DEPENDENCY,
                                f"{candidate_id} and {other_id} are dependency-coupled"))
            continue
        # B. allowed files (skip if dependency-ordered)
        if not ordered and overlaps(candidate.allowed_files, _task_files(plan, other_id)):
            out.append(Conflict(candidate_id, other_id, ConflictDimension.ALLOWED_FILES,
                                "allowed_files overlap"))
    return out
```

- [ ] **Step 4: PASS (3), ruff, commit**
```bash
pytest tests/scheduler/test_conflicts.py -v && ruff check .
git add src/loop_engineer/scheduler/conflicts.py tests/scheduler/test_conflicts.py
git commit -m "feat(scheduler): add dependency + allowed-files conflict detection

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 4: conflicts C (migration) + D (resource) + E (lifecycle)

**Files:** Modify `src/loop_engineer/scheduler/conflicts.py` (add C/D/E to `conflicts_for`); extend `tests/scheduler/test_conflicts.py`.

- [ ] **Step 1: add failing tests** (append to `tests/scheduler/test_conflicts.py`)
```python
def test_migration_same_dir_conflict():
    plan = _plan([_task("T1"), _task("T2")])
    board = _board(["T1"])
    meta = {"T2": TaskExecutionMeta(task_id="T2", migration_dir="migrations/versions"),
            "T1": TaskExecutionMeta(task_id="T1", migration_dir="migrations/versions")}
    confs = conflicts_for("T2", plan, board, meta)
    assert any(c.dimension == ConflictDimension.MIGRATION for c in confs)


def test_resource_port_conflict():
    plan = _plan([_task("T1"), _task("T2")])
    board = _board(["T1"])
    meta = {"T1": TaskExecutionMeta(task_id="T1", ports=[8000]),
            "T2": TaskExecutionMeta(task_id="T2", ports=[8000])}
    confs = conflicts_for("T2", plan, board, meta)
    assert any(c.dimension == ConflictDimension.RESOURCE for c in confs)


def test_resource_db_conflict():
    plan = _plan([_task("T1"), _task("T2")])
    board = _board(["T1"])
    meta = {"T1": TaskExecutionMeta(task_id="T1", db_name="app"),
            "T2": TaskExecutionMeta(task_id="T2", db_name="app")}
    assert any(c.dimension == ConflictDimension.RESOURCE for c in conflicts_for("T2", plan, board, meta))


def test_resource_browser_profile_conflict():
    plan = _plan([_task("T1"), _task("T2")])
    board = _board(["T1"])
    meta = {"T1": TaskExecutionMeta(task_id="T1", browser_profile="p"),
            "T2": TaskExecutionMeta(task_id="T2", browser_profile="p")}
    assert any(c.dimension == ConflictDimension.RESOURCE for c in conflicts_for("T2", plan, board, meta))


def test_no_conflict_disjoint_meta():
    plan = _plan([_task("T1", files=["a.py"]), _task("T2", files=["b.py"])])
    board = _board(["T1"])
    meta = {"T1": TaskExecutionMeta(task_id="T1", ports=[8000], db_name="a"),
            "T2": TaskExecutionMeta(task_id="T2", ports=[9000], db_name="b")}
    assert conflicts_for("T2", plan, board, meta) == []
```

- [ ] **Step 2: run, FAIL** (C/D/E not implemented).

- [ ] **Step 3: append C/D/E checks inside the loop in `conflicts_for`** (after the B block, still inside the `for other_id, entry` loop):
```python
        cmeta = meta_map.get(candidate_id)
        ometa = meta_map.get(other_id)
        # C. migration
        if cmeta and ometa and cmeta.migration_dir and cmeta.migration_dir == ometa.migration_dir:
            out.append(Conflict(candidate_id, other_id, ConflictDimension.MIGRATION,
                                f"shared migration_dir {cmeta.migration_dir}"))
        elif cmeta and ometa and (set(cmeta.migration_after) & set(ometa.migration_after)):
            out.append(Conflict(candidate_id, other_id, ConflictDimension.MIGRATION,
                                "shared migration_after precursor"))
        # D. resource
        if cmeta and ometa:
            if set(cmeta.ports) & set(ometa.ports):
                out.append(Conflict(candidate_id, other_id, ConflictDimension.RESOURCE, "port clash"))
            if cmeta.db_name and cmeta.db_name == ometa.db_name:
                out.append(Conflict(candidate_id, other_id, ConflictDimension.RESOURCE,
                                    f"exclusive db {cmeta.db_name}"))
            if cmeta.browser_profile and cmeta.browser_profile == ometa.browser_profile:
                out.append(Conflict(candidate_id, other_id, ConflictDimension.RESOURCE,
                                    f"exclusive browser_profile {cmeta.browser_profile}"))
        # E. lifecycle (same branch derivation): skipped — distinct task_ids yield distinct
        # branches by construction; defensive check belongs to the claim layer (P2a).
```

- [ ] **Step 4: PASS (all conflict tests), ruff, commit**
```bash
pytest tests/scheduler/test_conflicts.py -v && ruff check .
git add src/loop_engineer/scheduler/conflicts.py tests/scheduler/test_conflicts.py
git commit -m "feat(scheduler): add migration + resource conflict dimensions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 5: engine routing (`engine.py`)

**Files:** Create `src/loop_engineer/scheduler/engine.py`; Test `tests/scheduler/test_engine.py`.

- [ ] **Step 1: failing test — `tests/scheduler/test_engine.py`**
```python
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.scheduler.engine import recommend_engine
from loop_engineer.scheduler.models import TaskExecutionMeta


def _task(tid, files):
    return Task(
        id=tid, owner_domain="omx", allowed_files=files, acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["t"], working_dir="."), required_evidence=["c"],
    )


def test_frontend_routes_to_omc():
    assert recommend_engine(_task("T", ["frontend/src/App.tsx"]), None) == Provider.OMC


def test_backend_migration_routes_to_omx():
    assert recommend_engine(_task("T", ["backend/migrations/0001.py"]), None) == Provider.OMX


def test_engine_hint_overrides():
    t = _task("T", ["backend/x.py"])
    meta = TaskExecutionMeta(task_id="T", engine_hint=Provider.OMC)
    assert recommend_engine(t, meta) == Provider.OMC


def test_default_when_unclear():
    assert recommend_engine(_task("T", ["src/x.py"]), None) == Provider.OMX
```

- [ ] **Step 2: FAIL** (`ModuleNotFoundError`).

- [ ] **Step 3: implementation — `src/loop_engineer/scheduler/engine.py`**
```python
"""Engine routing heuristic (spec P2b-1 §5)."""

from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task
from loop_engineer.scheduler.models import TaskExecutionMeta

_OMC_MARKERS = ("frontend/", "ui/", "component", "page", "playwright", "browser", "docs/", ".md")
_OMX_MARKERS = ("backend/", "actuator", "migration", "migrations", "durable", "postgres", "db/")


def recommend_engine(task: Task, meta: TaskExecutionMeta | None) -> Provider:
    if meta is not None and meta.engine_hint is not None:
        return meta.engine_hint
    blob = " ".join(task.allowed_files).lower()
    if any(m in blob for m in _OMC_MARKERS):
        return Provider.OMC
    if any(m in blob for m in _OMX_MARKERS):
        return Provider.OMX
    return Provider.OMX
```

- [ ] **Step 4: PASS, ruff, commit**
```bash
pytest tests/scheduler/test_engine.py -v && ruff check .
git add src/loop_engineer/scheduler/engine.py tests/scheduler/test_engine.py
git commit -m "feat(scheduler): add engine routing heuristic

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 6: capacity + launch plan (`planner.py`)

**Files:** Create `src/loop_engineer/scheduler/planner.py`; Test `tests/scheduler/test_planner.py`.

- [ ] **Step 1: failing test — `tests/scheduler/test_planner.py`**
```python
from loop_engineer.contracts.plan import Plan, TaskNode
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.contracts.task_run import TaskBoardEntry, TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.scheduler.models import PlannerConfig, TaskExecutionMeta
from loop_engineer.scheduler.planner import plan_launch


def _task(tid, files):
    return Task(
        id=tid, owner_domain="omx", allowed_files=files, acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["t"], working_dir="."), required_evidence=["c"],
    )


def _plan(tasks):
    return Plan(goal_id="G", nodes=[TaskNode(task=t) for t in tasks], edges=[])


def _board(claimed_with_provider, pending=None):
    tasks = {tid: TaskBoardEntry(task_id=tid, status=TaskRunStatus.CLAIMED, provider=prov)
             for tid, prov in claimed_with_provider.items()}
    for tid in pending or []:
        tasks[tid] = TaskBoardEntry(task_id=tid)
    return BoardState(run_id="r", plan_digest="sha256:" + "0" * 64, tasks=tasks)


def test_launches_up_to_global_cap():
    plan = _plan([_task(f"T{i}", [f"src/{i}.py"]) for i in range(5)])
    board = _board({}, pending=["T0", "T1", "T2", "T3", "T4"])
    lp = plan_launch(plan, board, {}, PlannerConfig())
    assert len(lp.launch) == 3  # global_max=3
    assert lp.remaining_global == 3 and lp.active_omx + lp.active_omc == 0


def test_global_cap_is_combined_not_per_engine():
    plan = _plan([_task(f"T{i}", [f"frontend/{i}.py"]) for i in range(5)])
    board = _board({"X": Provider.OMC, "Y": Provider.OMC}, pending=["T0", "T1", "T2"])
    lp = plan_launch(plan, board, {}, PlannerConfig())
    # active_total=2, global_max=3 -> only 1 more launch despite omc_max=3
    assert len(lp.launch) == 1


def test_overlapping_task_skipped():
    plan = _plan([_task("T1", ["src/a.py"]), _task("T2", ["src/a.py"])])
    board = _board({"T1": Provider.OMX}, pending=["T2"])
    lp = plan_launch(plan, board, {}, PlannerConfig())
    assert [l.task_id for l in lp.launch] == []
    assert any(c.candidate == "T2" for c in lp.skipped)


def test_burst_denied_by_default():
    plan = _plan([_task(f"T{i}", [f"src/{i}.py"]) for i in range(5)])
    board = _board({}, pending=["T0", "T1", "T2", "T3"])
    lp = plan_launch(plan, board, {}, PlannerConfig())  # burst_eligible=False
    assert len(lp.launch) == 3 and lp.burst is False


def test_burst_allowed_when_eligible_and_clean():
    plan = _plan([_task(f"T{i}", [f"src/{i}.py"]) for i in range(5)])
    board = _board({}, pending=["T0", "T1", "T2", "T3"])
    cfg = PlannerConfig(burst_eligible=True)
    lp = plan_launch(plan, board, {}, cfg)
    assert len(lp.launch) == 4 and lp.burst is True
```

- [ ] **Step 2: FAIL** (`ModuleNotFoundError`).

- [ ] **Step 3: implementation — `src/loop_engineer/scheduler/planner.py`**
```python
"""Capacity-aware launch planning (spec P2b-1 §6)."""

from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task_run import TaskRunStatus
from loop_engineer.runtime.board import BoardState
from loop_engineer.scheduler.conflicts import conflicts_for
from loop_engineer.scheduler.eligibility import eligible_tasks
from loop_engineer.scheduler.engine import recommend_engine
from loop_engineer.scheduler.models import Launch, LaunchPlan, PlannerConfig, TaskExecutionMeta


def plan_launch(
    plan: Plan,
    board: BoardState,
    meta_map: dict[str, TaskExecutionMeta],
    config: PlannerConfig,
) -> LaunchPlan:
    eligible, blocked = eligible_tasks(plan, board, config)
    active = {tid: e for tid, e in board.tasks.items() if e.status == TaskRunStatus.CLAIMED}
    active_omx = sum(1 for e in active.values() if e.provider == Provider.OMX)
    active_omc = sum(1 for e in active.values() if e.provider == Provider.OMC)
    active_total = len(active)

    skipped = []
    clean_candidates = []
    for tid in eligible:
        confs = conflicts_for(tid, plan, board, meta_map)
        if confs:
            skipped.extend(confs)
        else:
            clean_candidates.append(tid)

    cap = config.capacity
    base_remaining = max(0, cap.global_max - active_total)
    # burst only if caller-certified eligible AND every base slot could fill + the extra is clean
    can_burst = config.burst_eligible and len(clean_candidates) > base_remaining
    max_launch = cap.burst_max - active_total if can_burst else base_remaining
    max_launch = max(0, max_launch)

    # tie-break: fewest remaining dependents-first is complex; keep deterministic by task order
    chosen = clean_candidates[:max_launch]

    launch: list[Launch] = []
    for tid in chosen:
        node = next(n for n in plan.nodes if n.task.id == tid)
        launch.append(Launch(task_id=tid, provider=recommend_engine(node.task, meta_map.get(tid))))

    # per-engine cap enforcement (global is the binding cap; trim per-engine overflow)
    launch = _trim_per_engine(launch, active_omx, active_omc, cap)

    return LaunchPlan(
        launch=launch,
        skipped=skipped,
        blocked=blocked,
        active_omx=active_omx,
        active_omc=active_omc,
        remaining_global=max(0, cap.global_max - active_total),
        burst=can_burst and len(launch) > base_remaining,
    )


def _trim_per_engine(launch, active_omx, active_omc, cap):
    out = []
    omx = active_omx
    omc = active_omc
    for l in launch:
        if l.provider == Provider.OMX:
            if omx < cap.omx_max:
                out.append(l); omx += 1
        else:
            if omc < cap.omc_max:
                out.append(l); omc += 1
    return out
```

- [ ] **Step 4: PASS (5), ruff, commit**
```bash
pytest tests/scheduler/test_planner.py -v && ruff check .
git add src/loop_engineer/scheduler/planner.py tests/scheduler/test_planner.py
git commit -m "feat(scheduler): add capacity-aware launch planner

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 7: scheduler CLI subcommand (visibility)

**Files:** Create `src/loop_engineer/cli/scheduler_cmd.py`; register in `cli/__init__.py`; Test `tests/cli/test_scheduler_cli.py`.

- [ ] **Step 1: failing test — `tests/cli/test_scheduler_cli.py`**
```python
import json
from pathlib import Path

from loop_engineer.cli import main
from loop_engineer.contracts.enums import ExitCode


def _files(tmp_path):
    plan = tmp_path / "plan.json"
    plan.write_text(json.dumps({
        "goal_id": "G",
        "nodes": [{"task": {
            "id": "T1", "owner_domain": "omx", "status": "pending", "dependencies": [],
            "allowed_files": ["src/a.py"], "non_goals": [], "acceptance_criteria": ["x"],
            "verification": {"commands": ["t"], "working_dir": "."},
            "required_evidence": ["c"], "downstream_handoff": []}}],
        "edges": [],
    }))
    board_dir = tmp_path / "loop-engineer" / "deadbeef"
    board_dir.mkdir(parents=True)
    (board_dir / "board.json").write_text(json.dumps({
        "run_id": "deadbeef", "plan_digest": "sha256:" + "0" * 64,
        "tasks": {"T1": {"task_id": "T1", "status": "pending", "attempt_id": 1}},
        "scope": {"T1": ["src/a.py"]}, "ancestors": {"T1": []},
    }))
    return plan, board_dir


def test_scheduler_plan_outputs_launch(tmp_path, capsys, monkeypatch):
    plan, _ = _files(tmp_path)
    monkeypatch.setenv("LOOP_ENGINEER_COMMON_DIR", str(tmp_path))
    rc = main(["scheduler", "plan", str(plan)])
    assert rc == int(ExitCode.OK)
    out = capsys.readouterr().out
    assert "T1" in out and "launch" in out
```

- [ ] **Step 2: FAIL** (no `scheduler` subcommand).

- [ ] **Step 3: implementation — `src/loop_engineer/cli/scheduler_cmd.py`**
```python
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
```

Register it in `src/loop_engineer/cli/__init__.py` — add `from loop_engineer.cli import goal_cmd, plan_cmd, scheduler_cmd, task_cmd` and `scheduler_cmd.register(sub)`.

- [ ] **Step 4: PASS, ruff, commit**
```bash
pytest tests/cli/test_scheduler_cli.py -v && ruff check .
git add src/loop_engineer/cli/scheduler_cmd.py src/loop_engineer/cli/__init__.py tests/cli/test_scheduler_cli.py
git commit -m "feat(cli): add scheduler plan subcommand for planner visibility

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 8: P2b-1 gate — full suite, freeze, README, acceptance

**Files:** modify `README.md`. **Do NOT push.**

- [ ] **Step 1: idempotent schema export + full suite + ruff**
```bash
python scripts/export_schemas.py
git status --short schemas/          # empty
pytest -q
ruff check .
```
Expected: schemas clean; P1+P2a 168 + new scheduler tests green; ruff clean.

- [ ] **Step 2: P2b-1 acceptance checklist (§8)** — verify each with evidence:
- [ ] Every §6 dimension has a passing conflict test + a disjoint control (`test_conflicts.py`).
- [ ] Protected-zone (`refer/`) Tasks are blocked, never in launch (`test_eligibility.py::test_protected_zone_blocked`).
- [ ] `global_max` enforced as combined cap (`test_planner.py::test_global_cap_is_combined_not_per_engine`).
- [ ] Burst granted only when `burst_eligible` (`test_burst_*`).
- [ ] Derived-ready uses board DONE only (`test_dep_done_only_on_branch_not_eligible`).
- [ ] Engine routing honors hint + markers (`test_engine.py`).
- [ ] `task_execution_meta` frozen; P1+P2a tests unchanged.
- [ ] No subprocess/real team in any P2b-1 test: `grep -rE "subprocess|omx team|omc " tests/scheduler/ src/loop_engineer/scheduler/` → nothing.

- [ ] **Step 3: README — append a `## Scheduler (P2b-1)` section**
```markdown

## Scheduler planner (P2b-1)

Pure-logic planner: given a compiled `Plan` + task board + per-task execution
metadata, compute eligible Tasks, the conflict graph (dependency / allowed-files
/ migration / resource / lifecycle / protected-zone), engine routing, and a
capacity-respecting launch plan.

```bash
loop-engineer scheduler plan plan.json   # prints the LaunchPlan JSON
```
```

- [ ] **Step 4: commit**
```bash
git add README.md
git commit -m "docs(p2b1): README section for the scheduler planner

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (P2b-1 spec §3/§4/§5/§6/§8):** eligibility §3 (Task 2), conflict dims A-F §4 (Tasks 3-4 + protected §4.F in Task 2), engine routing §5 (Task 5), capacity §6 (Task 6), CLI visibility (Task 7), acceptance §8 (Task 8). E (lifecycle) is intentionally minimal — distinct task_ids yield distinct branches by construction; the defensive same-branch check lives in P2a's claim layer.

**No-placeholder scan:** every step has real code + real assertions + a run command. Task 4's E dimension is a documented intentional non-implementation (lifecycle handled by claim layer), not a TODO.

**Type/name consistency:** `Conflict`/`ConflictDimension`/`Launch`/`LaunchPlan` defined once (Task 1), used identically in eligibility/conflicts/planner/CLI. `Provider` reused from P2a. `global_max` semantics (combined cap) consistent across models, planner tests, and spec §2/§6/§8. `TaskExecutionMeta.task_id` matches the keys of the `meta_map` dict passed everywhere.

**Deferred to P2b-2..5 (not gaps):** launching adapter scripts (P2b-2), the rolling driver loop that supplies `burst_eligible`/main-cleanliness (P2b-3), finisher/integration (P2b-4), recovery/lease-expiry feeding the "no unresolved recovery" input (P2b-5).
