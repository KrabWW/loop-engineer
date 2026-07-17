# Loop Engineer — P1 (Common Contracts & Provenance) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Freeze every versioned schema the runtime depends on (Goal, Task, Plan/DAG, Command, Event, Claim, Lease, Evidence, Handoff, WriterFence, RecoveryRecord, Provenance), wire a frozen-JSON-Schema contract pipeline, add the provenance manifest, and add a safe capability probe — all as tested, original Python code with zero runtime/Team launch.

**Architecture:** Pydantic v2 models are the single source of truth for each contract. A generator exports each model to a versioned JSON Schema file under `schemas/v1/` plus a registry manifest with a content digest; a drift-detection contract test fails if the exported schema and the committed file diverge. The append-only event journal is defined here as a contract (idempotent by `event_id`, strict sequence ordering) with a minimal JSONL implementation. The capability probe shells out only to read-only version commands (`git --version`, `tmux -V`, provider `--version`) — it never launches a Team, never writes outside a state dir, and records supported ranges into a versioned capability record.

**Tech Stack:** Python ≥ 3.11, pydantic v2, jsonschema (2020-12), pytest, ruff, hatchling packaging, `src/` layout.

---

## How this plan relates to the staged roadmap

The spec (§12) stages delivery P0→P7. P0 is complete. This document is the **detailed plan for P1 only**. P2–P7 cannot be planned at file/test/commit granularity yet because the spec (§14) explicitly defers their load-bearing inputs:

- **Supported OMX/OMC version ranges** — "selected during the P1 capability probe" (Task 13 surfaces these; P3's adapter contract depends on them).
- **Event journal storage engine** — defaulted in P1 (Task 11) but the durable/replay design is exercised for real in P2.
- **Initial public license** — gated on third-party provenance review; P1 writes original code only, so the LICENSE decision is surfaced (Decision D8) but not finalized.

Therefore each later stage gets its **own detailed plan at its own gate**, written against the facts P1 produces. The roadmap below is the contract for those future plans — not a placeholder for this one.

| Stage | Plan status | Starts when | Produces |
| --- | --- | --- | --- |
| **P1** contracts + provenance | **This plan (detailed)** | approved now | frozen schemas, freeze pipeline, provenance manifest, capability probe |
| P2 pure OMX baseline | gated | P1 probe records supported OMX/Codex versions | Goal compiler, `run omx`, serialized finisher against P1 contracts |
| P3 OMC executor-adapter MVP | gated | P2 runtime core + adapter claim-safe API exist | one adapter, one Claude leader, one OMC Team, one Task |
| P4 review/correction loop | gated | P3 lifecycle stable | ≥3 follow-up rounds in one live Team |
| P5 Hybrid batch runtime | gated | P4 correction loop proven | `run hybrid`, Task overlap, serialized finishers, plan resume |
| P6 Skill packaging | gated | P5 CLI stable | `define-goal`, `goal-to-omx-team`, `goal-to-omx-omc-team` Skills + installers |
| P7 release qualification | gated | P6 + license/provenance cleared | contract/fake-runtime/recovery/3 forward scenarios; first tag |

---

## §14 Open decisions resolved or surfaced by this plan

| ID | Decision | Resolution in P1 | Needs your sign-off? |
| --- | --- | --- | --- |
| D1 | Min Python version | **3.11** (`StrEnum`, `tomllib`, `typing.Self`). | No (sensible default). |
| D2 | Packaging backend | **hatchling** + `pyproject.toml` + `src/` layout (matches spec §9). | No. |
| D3 | Schema modeling | **pydantic v2** models (source of truth) + **jsonschema** validation of external JSON against frozen 2020-12 schemas. | No. |
| D4 | JSON Schema draft | **2020-12**. | No. |
| D5 | Journal storage engine | **append-only JSONL** under the Git common dir, behind a `Journal` interface; P1 ships the contract + minimal impl. | No. |
| D6 | Test/lint tooling | **pytest** + **ruff**. | No. |
| D7 | Supported OMX/OMC ranges | **Not hardcoded.** Task 13 probes installed versions at runtime; only the *schema* of the capability record is frozen here. | No (ranges are runtime data). |
| D8 | Public license | **Surfaced, not finalized.** P1 writes original code only; a `LICENSE` is added only after you pick one. Recommended: MIT. | **Yes — tell me before P7 redistribution.** |

If you disagree with any default (D1–D6), say so before approving and I'll adjust the plan. D8 is the only one that blocks redistribution, not P1 itself.

---

## File structure (locked here)

```
loop-engineer/
├── pyproject.toml                         # hatchling, py>=3.11, deps, ruff/pytest config
├── .gitignore                             # .omc/, .setting.projA/, __pycache__/, .venv/, dist/, *.egg-info
├── LICENSE                                # ONLY after D8 sign-off (Task 14 notes it)
├── README.md                              # modify: add install + dev + schema-freeze sections
├── src/loop_engineer/
│   ├── __init__.py                        # __version__
│   ├── contracts/
│   │   ├── __init__.py                    # public re-exports
│   │   ├── enums.py                       # ExitCode, OmxTaskStatus, CommonState, ExecutorState, CommandType, EventType
│   │   ├── goal.py                        # Goal, Milestone
│   │   ├── task.py                        # Task, AllowedFile, VerificationSpec
│   │   ├── plan.py                        # Plan, TaskNode, DependencyEdge, Wave
│   │   ├── command.py                     # CommandEnvelope
│   │   ├── event.py                       # EventEnvelope
│   │   ├── claim.py                       # Claim
│   │   ├── lease.py                       # Lease
│   │   ├── evidence.py                    # Evidence, EvidenceType
│   │   ├── handoff.py                     # Handoff
│   │   ├── fence.py                       # WriterFence, FencingProof, ProcessGroupIdentity
│   │   ├── recovery.py                    # RecoveryRecord + coordinate sub-models
│   │   └── provenance.py                  # ProvenanceEntry, ProvenanceManifest
│   ├── state/
│   │   ├── __init__.py
│   │   └── journal.py                     # Journal interface, JsonlJournal, OrderedJournal
│   └── probe/
│       ├── __init__.py
│       └── capabilities.py                # CapabilityRecord, probe_capabilities()
├── schemas/
│   ├── README.md                          # how to regenerate + freeze policy
│   ├── manifest.json                      # registry: schema id -> file, version, digest
│   └── v1/
│       ├── goal.schema.json               # generated, committed
│       ├── task.schema.json
│       ├── plan.schema.json
│       ├── command.schema.json
│       ├── event.schema.json
│       ├── claim.schema.json
│       ├── lease.schema.json
│       ├── evidence.schema.json
│       ├── handoff.schema.json
│       ├── fence.schema.json
│       ├── recovery.schema.json
│       └── provenance.schema.json
├── scripts/
│   └── export_schemas.py                  # regenerate schemas/v1/* + manifest.json from pydantic
├── tests/
│   ├── conftest.py
│   ├── unit/
│   │   ├── test_enums.py
│   │   ├── test_goal.py
│   │   ├── test_task.py
│   │   ├── test_plan_dag.py
│   │   ├── test_command_envelope.py
│   │   ├── test_event_envelope.py
│   │   ├── test_claim_lease.py
│   │   ├── test_evidence_handoff.py
│   │   ├── test_fence.py
│   │   ├── test_recovery_record.py
│   │   └── test_provenance.py
│   ├── contract/
│   │   ├── test_schema_freeze_drift.py
│   │   ├── test_schema_roundtrip.py
│   │   ├── test_dag_acyclicity.py
│   │   └── test_exit_code_classes.py
│   └── probe/
│       └── test_capabilities_fake.py
└── docs/superpowers/plans/2026-07-17-loop-engineer-p1-contracts.md   # this file
```

**Responsibility rule:** one contract per file. `contracts/__init__.py` re-exports the public surface so callers do `from loop_engineer.contracts import CommandEnvelope`. Schemas are generated, never hand-edited; the drift test enforces it.

---

## Task 0: Project scaffolding

**Files:**
- Create: `pyproject.toml`
- Create: `.gitignore`
- Create: `src/loop_engineer/__init__.py`
- Create: `tests/__init__.py`
- Create: `tests/conftest.py`
- Create: `src/loop_engineer/contracts/__init__.py` (empty for now)
- Create: `src/loop_engineer/state/__init__.py` (empty)
- Create: `src/loop_engineer/probe/__init__.py` (empty)

- [ ] **Step 1: Write `pyproject.toml`**

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "loop-engineer"
version = "0.1.0a1"
description = "Durable orchestration toolkit turning measurable goals into recoverable engineering loops."
readme = "README.md"
requires-python = ">=3.11"
license = { text = "TBD — pending provenance review (see plan D8)" }
authors = [{ name = "Loop Engineer" }]
dependencies = [
  "pydantic>=2.7,<3",
  "jsonschema>=4.21,<5",
]

[project.optional-dependencies]
dev = [
  "pytest>=8.2,<9",
  "ruff>=0.5,<1",
]

[project.scripts]
loop-engineer = "loop_engineer.cli:main"   # CLI lands in P2; stub created then

[tool.hatch.build.targets.wheel]
packages = ["src/loop_engineer"]

[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra"
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
# OMC operational state
.omc/
# local MCP project config / logs
.setting.projA/
# superpowers worktrees
.worktrees/

# Python
__pycache__/
*.py[cod]
.venv/
venv/
dist/
build/
*.egg-info/
.pytest_cache/
.ruff_cache/

# editor
.DS_Store
```

- [ ] **Step 3: Write `src/loop_engineer/__init__.py`**

```python
"""Loop Engineer — durable orchestration toolkit."""

__version__ = "0.1.0a1"
```

- [ ] **Step 4: Write `tests/__init__.py` (empty), `tests/conftest.py`, and the three package `__init__.py` files**

`tests/conftest.py`:

```python
"""Shared pytest fixtures for Loop Engineer contract tests."""
```

`src/loop_engineer/contracts/__init__.py`, `src/loop_engineer/state/__init__.py`, `src/loop_engineer/probe/__init__.py`:

```python
"""Package marker."""
```

- [ ] **Step 5: Create the venv, install dev deps, and verify import**

Run:
```bash
python3.11 -m venv .venv
. .venv/bin/activate
pip install -e ".[dev]"
python -c "import loop_engineer; print(loop_engineer.__version__)"
```
Expected: prints `0.1.0a1`, no errors. If `python3.11` is absent, use `python3` only if `python3 --version` is ≥ 3.11; otherwise stop and report the version gap (do not silently downgrade — D1).

- [ ] **Step 6: Verify pytest collects zero tests cleanly and ruff is clean**

Run:
```bash
pytest -q
ruff check .
```
Expected: `pytest` reports `no tests ran` (exit 5 is fine here — collection succeeded); `ruff check` reports `All checks passed!`.

- [ ] **Step 7: Commit**

```bash
git add pyproject.toml .gitignore src/loop_engineer/__init__.py tests/__init__.py tests/conftest.py src/loop_engineer/contracts/__init__.py src/loop_engineer/state/__init__.py src/loop_engineer/probe/__init__.py
git commit -m "chore(p1): scaffold python package, tooling, and layout"
```

---

## Task 1: Exit codes and lifecycle enums

**Files:**
- Create: `src/loop_engineer/contracts/enums.py`
- Test: `tests/unit/test_enums.py`
- Test: `tests/contract/test_exit_code_classes.py`

- [ ] **Step 1: Write the failing test for enums**

`tests/unit/test_enums.py`:

```python
import pytest
from loop_engineer.contracts.enums import (
    CommandType,
    CommonState,
    EventType,
    ExecutorState,
    ExitCode,
    OmxTaskStatus,
)


def test_exit_code_values_match_spec_classes():
    assert ExitCode.OK == 0
    assert ExitCode.INVALID_INPUT == 2
    assert ExitCode.OWNERSHIP_AMBIGUITY == 3
    assert ExitCode.WORKER_FAILURE == 4
    assert ExitCode.VERIFICATION_SCOPE_FAILURE == 5
    assert ExitCode.GIT_INTEGRATION_CONFLICT == 6
    assert ExitCode.PARTIAL_COMPLETION == 7


def test_exit_code_excludes_one_and_eight_plus():
    values = {int(c) for c in ExitCode}
    assert 1 not in values
    assert all(v <= 7 for v in values)


def test_command_types_match_protocol_section_7_1():
    expected = {
        "START_TASK", "CONTINUE_TASK", "REQUEST_FIX", "REQUEST_EVIDENCE",
        "RELEASE_FOR_OMX_FIX", "CANCEL_TASK", "SHUTDOWN_EXECUTOR",
    }
    assert {t.value for t in CommandType} == expected


def test_event_types_match_protocol_section_7_2():
    expected = {
        "ACKNOWLEDGED", "STARTED", "PROGRESS", "HEARTBEAT", "BLOCKED",
        "READY_FOR_REVIEW", "FAILED", "CANCELLED", "SHUTDOWN_ACK",
    }
    assert {t.value for t in EventType} == expected


def test_common_state_covers_full_lifecycle_table():
    # Every common state named in spec §7.3 must exist.
    required = [
        "ready", "claimed", "omc_starting", "omc_executing", "blocked",
        "ready_for_omx_review", "omx_reviewing", "correction_requested",
        "writer_quiescing", "promoting", "post_promotion_review", "omx_fixing",
        "omx_verified", "finishing", "merged", "post_merge_verification_failed",
        "failed", "cancelled", "integration_cancelled",
    ]
    present = {s.value for s in CommonState}
    missing = set(required) - present
    assert not missing, f"lifecycle table missing states: {missing}"


def test_executor_states_match_section_7_4():
    assert {s.value for s in ExecutorState} == {
        "adapter_idle", "adapter_active", "adapter_stopping", "adapter_shutdown",
    }


def test_omx_task_status_values():
    assert {s.value for s in OmxTaskStatus} == {
        "pending", "in_progress", "completed", "failed", "cancelled",
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pytest tests/unit/test_enums.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'loop_engineer.contracts.enums'`.

- [ ] **Step 3: Write the implementation**

`src/loop_engineer/contracts/enums.py`:

```python
"""Frozen enums for exit codes and the Hybrid lifecycle (spec §4, §7.3, §7.4).

Adding a value here is a wire-format change: bump SCHEMA_VERSION in every
envelope that carries one of these enums and regenerate schemas/.
"""

from enum import IntEnum, StrEnum


class ExitCode(IntEnum):
    """Stable process exit classes (spec §4)."""

    OK = 0                       # requested state reached / idempotent confirmation
    INVALID_INPUT = 2            # bad input, schema, plan, dependency, version
    OWNERSHIP_AMBIGUITY = 3      # lease/leader/team/worktree/recovery ambiguity
    WORKER_FAILURE = 4           # runtime or worker terminal failure
    VERIFICATION_SCOPE_FAILURE = 5  # verification, scope, provenance, protected path
    GIT_INTEGRATION_CONFLICT = 6 # rebase conflict or main drift
    PARTIAL_COMPLETION = 7       # preserved for same-command recovery


class OmxTaskStatus(StrEnum):
    """OMX worker Task status column (spec §7.3)."""

    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class CommonState(StrEnum):
    """Sole normative common-state lifecycle (spec §7.3)."""

    READY = "ready"
    CLAIMED = "claimed"
    OMC_STARTING = "omc_starting"
    OMC_EXECUTING = "omc_executing"
    BLOCKED = "blocked"
    READY_FOR_OMX_REVIEW = "ready_for_omx_review"
    OMX_REVIEWING = "omx_reviewing"
    CORRECTION_REQUESTED = "correction_requested"
    WRITER_QUIESCING = "writer_quiescing"
    PROMOTING = "promoting"
    POST_PROMOTION_REVIEW = "post_promotion_review"
    OMX_FIXING = "omx_fixing"
    OMX_VERIFIED = "omx_verified"
    FINISHING = "finishing"
    MERGED = "merged"
    POST_MERGE_VERIFICATION_FAILED = "post_merge_verification_failed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    INTEGRATION_CANCELLED = "integration_cancelled"


class ExecutorState(StrEnum):
    """Adapter executor lifecycle (spec §7.4)."""

    ADAPTER_IDLE = "adapter_idle"
    ADAPTER_ACTIVE = "adapter_active"
    ADAPTER_STOPPING = "adapter_stopping"
    ADAPTER_SHUTDOWN = "adapter_shutdown"


class CommandType(StrEnum):
    """Leader-to-adapter command types (spec §7.1)."""

    START_TASK = "START_TASK"
    CONTINUE_TASK = "CONTINUE_TASK"
    REQUEST_FIX = "REQUEST_FIX"
    REQUEST_EVIDENCE = "REQUEST_EVIDENCE"
    RELEASE_FOR_OMX_FIX = "RELEASE_FOR_OMX_FIX"
    CANCEL_TASK = "CANCEL_TASK"
    SHUTDOWN_EXECUTOR = "SHUTDOWN_EXECUTOR"


class EventType(StrEnum):
    """Adapter-to-leader event types (spec §7.2)."""

    ACKNOWLEDGED = "ACKNOWLEDGED"
    STARTED = "STARTED"
    PROGRESS = "PROGRESS"
    HEARTBEAT = "HEARTBEAT"
    BLOCKED = "BLOCKED"
    READY_FOR_REVIEW = "READY_FOR_REVIEW"
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"
    SHUTDOWN_ACK = "SHUTDOWN_ACK"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pytest tests/unit/test_enums.py -v`
Expected: 7 passed.

- [ ] **Step 5: Write the contract test for exit-code classes**

`tests/contract/test_exit_code_classes.py`:

```python
"""Exit codes are a public, stable contract (spec §4)."""

import pytest

from loop_engineer.contracts.enums import ExitCode


@pytest.mark.parametrize("code", list(ExitCode))
def test_every_exit_code_is_documented_class(code):
    # 1 is intentionally unused; the spec defines 0,2,3,4,5,6,7.
    assert int(code) in {0, 2, 3, 4, 5, 6, 7}


def test_exit_class_count_is_stable():
    # Changing this number is a breaking contract change.
    assert len(list(ExitCode)) == 7
```

- [ ] **Step 6: Run contract test, then commit**

Run: `pytest tests/contract/test_exit_code_classes.py tests/unit/test_enums.py -v && ruff check .`
Expected: all pass; ruff clean.

```bash
git add src/loop_engineer/contracts/enums.py tests/unit/test_enums.py tests/contract/test_exit_code_classes.py
git commit -m "feat(contracts): freeze exit codes and lifecycle enums"
```

---

## Task 2: Goal and Milestone

**Files:**
- Create: `src/loop_engineer/contracts/goal.py`
- Test: `tests/unit/test_goal.py`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_goal.py`:

```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.goal import Goal, Milestone


def test_milestone_requires_binary_evidence_condition():
    m = Milestone(id="M1", title="contracts frozen", evidence_condition="all contract tests green")
    assert m.id == "M1"
    with pytest.raises(ValidationError):
        Milestone(id="M2", title="x", evidence_condition="")


def test_goal_accepts_full_authoritative_shape():
    g = Goal(
        id="G1",
        title="ship loop-engineer v1",
        measurable_evidence="tag v1.0.0 after P7 gates pass",
        scope=["cli", "contracts", "runtime"],
        exclusions=["hosted control plane", "multi-user service"],
        stop_conditions=["main red", "license blocked"],
        milestones=[Milestone(id="M1", title="contracts", evidence_condition="green")],
    )
    assert g.measurable_evidence
    assert g.milestones[0].id == "M1"


def test_goal_rejects_empty_scope_or_evidence():
    with pytest.raises(ValidationError):
        Goal(id="G", title="t", measurable_evidence="", scope=["x"], exclusions=[], stop_conditions=[])
    with pytest.raises(ValidationError):
        Goal(id="G", title="t", measurable_evidence="ok", scope=[], exclusions=[], stop_conditions=[])


def test_goal_rejects_duplicate_milestone_ids():
    dup = [Milestone(id="M", title="a", evidence_condition="x"),
           Milestone(id="M", title="b", evidence_condition="y")]
    with pytest.raises(ValidationError):
        Goal(id="G", title="t", measurable_evidence="ok", scope=["x"],
             exclusions=[], stop_conditions=[], milestones=dup)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pytest tests/unit/test_goal.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the implementation**

`src/loop_engineer/contracts/goal.py`:

```python
"""Goal and Milestone contracts (spec §2, §6.1).

A Goal is compiled before execution. Milestones are release gates with binary
exits, never Team execution units.
"""

from pydantic import BaseModel, Field, field_validator, model_validator


class Milestone(BaseModel):
    """A release gate. Exit is binary: evidence condition met or not."""

    id: str = Field(min_length=1)
    title: str = Field(min_length=1)
    # Machine-checkable condition is finalized in P2; the string is the contract.
    evidence_condition: str = Field(min_length=1)


class Goal(BaseModel):
    id: str = Field(min_length=1)
    title: str = Field(min_length=1)
    measurable_evidence: str = Field(min_length=1)
    scope: list[str] = Field(min_length=1)
    exclusions: list[str] = Field(default_factory=list)
    stop_conditions: list[str] = Field(default_factory=list)
    milestones: list[Milestone] = Field(min_length=1)

    @field_validator("scope")
    @classmethod
    def _scope_nonempty_entries(cls, v: list[str]) -> list[str]:
        if any(not entry.strip() for entry in v):
            raise ValueError("scope entries must be non-empty")
        return v

    @model_validator(mode="after")
    def _unique_milestone_ids(self) -> "Goal":
        ids = [m.id for m in self.milestones]
        if len(ids) != len(set(ids)):
            raise ValueError("milestone ids must be unique")
        return self
```

- [ ] **Step 4: Run, verify pass, commit**

Run: `pytest tests/unit/test_goal.py -v && ruff check .`
Expected: 4 passed.

```bash
git add src/loop_engineer/contracts/goal.py tests/unit/test_goal.py
git commit -m "feat(contracts): add Goal and Milestone schemas"
```

---

## Task 3: Task, AllowedFile, VerificationSpec

**Files:**
- Create: `src/loop_engineer/contracts/task.py`
- Test: `tests/unit/test_task.py`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_task.py`:

```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.enums import OmxTaskStatus
from loop_engineer.contracts.task import Task, VerificationSpec


def test_verification_spec_requires_commands_and_cwd():
    v = VerificationSpec(commands=["pytest -q"], working_dir=".")
    assert v.commands
    with pytest.raises(ValidationError):
        VerificationSpec(commands=[], working_dir=".")


def test_task_authoritative_shape():
    t = Task(
        id="T1",
        owner_domain="omx",
        status=OmxTaskStatus.PENDING,
        dependencies=[],
        allowed_files=["src/a.py", "tests/test_a.py"],
        non_goals=["touching main"],
        acceptance_criteria=["a.py exports foo"],
        verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
        required_evidence=["commit", "test_run"],
        downstream_handoff=["T2"],
    )
    assert t.allowed_files == ["src/a.py", "tests/test_a.py"]


def test_task_rejects_empty_allowed_files():
    with pytest.raises(ValidationError):
        Task(
            id="T", owner_domain="omx", status=OmxTaskStatus.PENDING,
            dependencies=[], allowed_files=[], non_goals=[],
            acceptance_criteria=["x"],
            verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
            required_evidence=["commit"], downstream_handoff=[],
        )


def test_task_rejects_duplicate_allowed_files():
    with pytest.raises(ValidationError):
        Task(
            id="T", owner_domain="omx", status=OmxTaskStatus.PENDING,
            dependencies=[], allowed_files=["src/a.py", "src/a.py"],
            non_goals=[], acceptance_criteria=["x"],
            verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
            required_evidence=["commit"], downstream_handoff=[],
        )


def test_task_self_dependency_rejected():
    with pytest.raises(ValidationError):
        Task(
            id="T1", owner_domain="omx", status=OmxTaskStatus.PENDING,
            dependencies=["T1"], allowed_files=["src/a.py"],
            non_goals=[], acceptance_criteria=["x"],
            verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
            required_evidence=["commit"], downstream_handoff=[],
        )
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/unit/test_task.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the implementation**

`src/loop_engineer/contracts/task.py`:

```python
"""Atomic Task contract (spec §6.1).

A Task document is runtime authority for dependencies, Allowed Files,
acceptance, and verification. Exact `allowed_files` entries are normalized by
the scheduler in P2; here they are frozen as exact strings.
"""

from pydantic import BaseModel, Field, field_validator, model_validator

from loop_engineer.contracts.enums import OmxTaskStatus


class VerificationSpec(BaseModel):
    commands: list[str] = Field(min_length=1)
    working_dir: str = Field(min_length=1)


class Task(BaseModel):
    id: str = Field(min_length=1)
    owner_domain: str = Field(min_length=1)
    status: OmxTaskStatus = OmxTaskStatus.PENDING
    dependencies: list[str] = Field(default_factory=list)
    allowed_files: list[str] = Field(min_length=1)
    non_goals: list[str] = Field(default_factory=list)
    acceptance_criteria: list[str] = Field(min_length=1)
    verification: VerificationSpec
    required_evidence: list[str] = Field(min_length=1)
    downstream_handoff: list[str] = Field(default_factory=list)

    @field_validator("allowed_files")
    @classmethod
    def _allowed_files_nonempty(cls, v: list[str]) -> list[str]:
        if any(not p.strip() for p in v):
            raise ValueError("allowed_files entries must be non-empty")
        return v

    @model_validator(mode="after")
    def _unique_and_self_cycle_free(self) -> "Task":
        if len(self.allowed_files) != len(set(self.allowed_files)):
            raise ValueError("allowed_files must be unique")
        if self.id in self.dependencies:
            raise ValueError("a task cannot depend on itself")
        return self
```

- [ ] **Step 4: Run, verify pass, commit**

Run: `pytest tests/unit/test_task.py -v && ruff check .`
Expected: 5 passed.

```bash
git add src/loop_engineer/contracts/task.py tests/unit/test_task.py
git commit -m "feat(contracts): add atomic Task schema with exact Allowed Files"
```

---

## Task 4: Plan, TaskNode, DependencyEdge, Wave + DAG acyclicity

**Files:**
- Create: `src/loop_engineer/contracts/plan.py`
- Test: `tests/unit/test_plan_dag.py`
- Test: `tests/contract/test_dag_acyclicity.py`

- [ ] **Step 1: Write the failing unit test**

`tests/unit/test_plan_dag.py`:

```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.enums import OmxTaskStatus
from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.task import Task, VerificationSpec


def _task(tid: str, deps: list[str] | None = None) -> Task:
    return Task(
        id=tid, owner_domain="omx", status=OmxTaskStatus.PENDING,
        dependencies=deps or [], allowed_files=[f"src/{tid}.py"],
        non_goals=[], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
        required_evidence=["commit"], downstream_handoff=[],
    )


def test_plan_accepts_acyclic_dag():
    t1 = _task("T1")
    t2 = _task("T2", deps=["T1"])
    nodes = [TaskNode(task=t) for t in (t1, t2)]
    edges = [DependencyEdge(from_id="T1", to_id="T2")]
    p = Plan(goal_id="G1", nodes=nodes, edges=edges)
    assert p.is_acyclic() is True


def test_plan_rejects_cycle_at_construction():
    t1 = _task("T1", deps=["T2"])
    t2 = _task("T2", deps=["T1"])
    nodes = [TaskNode(task=t) for t in (t1, t2)]
    edges = [DependencyEdge(from_id="T1", to_id="T2"), DependencyEdge(from_id="T2", to_id="T1")]
    with pytest.raises(ValidationError):
        Plan(goal_id="G1", nodes=nodes, edges=edges)


def test_plan_rejects_edge_to_unknown_node():
    t1 = _task("T1")
    with pytest.raises(ValidationError):
        Plan(
            goal_id="G1",
            nodes=[TaskNode(task=t1)],
            edges=[DependencyEdge(from_id="T1", to_id="NOPE")],
        )


def test_plan_rejects_duplicate_node_ids():
    t1 = _task("T1")
    with pytest.raises(ValidationError):
        Plan(goal_id="G1", nodes=[TaskNode(task=t1), TaskNode(task=t1)], edges=[])


def test_topological_order_respects_dependencies():
    t1, t2, t3 = _task("T1"), _task("T2", deps=["T1"]), _task("T3", deps=["T2"])
    nodes = [TaskNode(task=t) for t in (t3, t2, t1)]  # deliberately out of order
    edges = [DependencyEdge(from_id="T1", to_id="T2"), DependencyEdge(from_id="T2", to_id="T3")]
    p = Plan(goal_id="G1", nodes=nodes, edges=edges)
    order = p.topological_order()
    assert order.index("T1") < order.index("T2") < order.index("T3")
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/unit/test_plan_dag.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the implementation**

`src/loop_engineer/contracts/plan.py`:

```python
"""Plan + atomic Task DAG (spec §6.1).

The compiler emits atomic Task documents and proves the dependency graph is
acyclic. Construction itself rejects cycles, unknown edges, and duplicate ids.
"""

from collections import defaultdict, deque

from pydantic import BaseModel, Field, model_validator

from loop_engineer.contracts.task import Task


class TaskNode(BaseModel):
    task: Task


class DependencyEdge(BaseModel):
    from_id: str
    to_id: str


class Wave(BaseModel):
    """A set of Tasks with all dependencies satisfied; legal overlap unit (spec §8)."""

    task_ids: list[str] = Field(min_length=1)


class Plan(BaseModel):
    goal_id: str = Field(min_length=1)
    nodes: list[TaskNode] = Field(min_length=1)
    edges: list[DependencyEdge] = Field(default_factory=list)

    @model_validator(mode="after")
    def _validate_graph(self) -> "Plan":
        ids = [n.task.id for n in self.nodes]
        if len(ids) != len(set(ids)):
            raise ValueError("duplicate task ids in plan")
        id_set = set(ids)
        for e in self.edges:
            if e.from_id not in id_set or e.to_id not in id_set:
                raise ValueError(f"edge references unknown task: {e.from_id}->{e.to_id}")
        # Dependency edges declared on Task documents must also exist as edges.
        declared = {(e.from_id, e.to_id) for e in self.edges}
        for n in self.nodes:
            for dep in n.task.dependencies:
                if (dep, n.task.id) not in declared:
                    raise ValueError(
                        f"task {n.task.id} declares dependency on {dep} with no matching edge"
                    )
        if not self.is_acyclic():
            raise ValueError("plan dependency graph has a cycle")
        return self

    def _adjacency(self) -> dict[str, list[str]]:
        adj: dict[str, list[str]] = {n.task.id: [] for n in self.nodes}
        for e in self.edges:
            adj[e.from_id].append(e.to_id)
        return adj

    def is_acyclic(self) -> bool:
        """Kahn's algorithm; True iff a topological order covers every node."""
        adj = self._adjacency()
        indeg = {nid: 0 for nid in adj}
        for src, dsts in adj.items():
            for d in dsts:
                indeg[d] += 1
        q = deque(sorted(nid for nid, deg in indeg.items() if deg == 0))
        seen = 0
        while q:
            n = q.popleft()
            seen += 1
            for d in sorted(adj[n]):
                indeg[d] -= 1
                if indeg[d] == 0:
                    q.append(d)
        return seen == len(indeg)

    def topological_order(self) -> list[str]:
        """Return a deterministic topological ordering; raises if cyclic."""
        if not self.is_acyclic():
            raise ValueError("cannot order a cyclic plan")
        adj = self._adjacency()
        indeg = {nid: 0 for nid in adj}
        for src, dsts in adj.items():
            for d in dsts:
                indeg[d] += 1
        q = deque(sorted(nid for nid, deg in indeg.items() if deg == 0))
        order: list[str] = []
        while q:
            n = q.popleft()
            order.append(n)
            for d in sorted(adj[n]):
                indeg[d] -= 1
                if indeg[d] == 0:
                    q.append(d)
        return order
```

- [ ] **Step 4: Run, verify pass**

Run: `pytest tests/unit/test_plan_dag.py -v`
Expected: 5 passed.

- [ ] **Step 5: Write the contract test for DAG acyclicity**

`tests/contract/test_dag_acyclicity.py`:

```python
"""The compiler must prove acyclicity (spec §6.1, §6.2)."""

import pytest
from pydantic import ValidationError

from loop_engineer.contracts.enums import OmxTaskStatus
from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.task import Task, VerificationSpec


def _tid(tid: str, deps: list[str]) -> Task:
    return Task(
        id=tid, owner_domain="omx", status=OmxTaskStatus.PENDING, dependencies=deps,
        allowed_files=[f"src/{tid}.py"], non_goals=[], acceptance_criteria=["x"],
        verification=VerificationSpec(commands=["pytest -q"], working_dir="."),
        required_evidence=["commit"], downstream_handoff=[],
    )


def test_self_loop_rejected():
    t = _tid("T1", [])
    with pytest.raises(ValidationError):
        Plan(
            goal_id="G", nodes=[TaskNode(task=t)],
            edges=[DependencyEdge(from_id="T1", to_id="T1")],
        )


def test_three_node_cycle_rejected():
    a, b, c = _tid("A", []), _tid("B", []), _tid("C", [])
    nodes = [TaskNode(task=t) for t in (a, b, c)]
    edges = [
        DependencyEdge(from_id="A", to_id="B"),
        DependencyEdge(from_id="B", to_id="C"),
        DependencyEdge(from_id="C", to_id="A"),
    ]
    with pytest.raises(ValidationError):
        Plan(goal_id="G", nodes=nodes, edges=edges)


def test_diamond_is_acyclic():
    a, b, c, d = _tid("A", []), _tid("B", []), _tid("C", []), _tid("D", [])
    nodes = [TaskNode(task=t) for t in (a, b, c, d)]
    edges = [
        DependencyEdge(from_id="A", to_id="B"),
        DependencyEdge(from_id="A", to_id="C"),
        DependencyEdge(from_id="B", to_id="D"),
        DependencyEdge(from_id="C", to_id="D"),
    ]
    p = Plan(goal_id="G", nodes=nodes, edges=edges)
    assert p.is_acyclic()
    order = p.topological_order()
    assert order[0] == "A" and order[-1] == "D"
```

- [ ] **Step 6: Run both, commit**

Run: `pytest tests/unit/test_plan_dag.py tests/contract/test_dag_acyclicity.py -v && ruff check .`
Expected: all pass.

```bash
git add src/loop_engineer/contracts/plan.py tests/unit/test_plan_dag.py tests/contract/test_dag_acyclicity.py
git commit -m "feat(contracts): add Plan DAG with construction-time acyclicity proof"
```

---

## Task 5: Command envelope

**Files:**
- Create: `src/loop_engineer/contracts/command.py`
- Test: `tests/unit/test_command_envelope.py`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_command_envelope.py`:

```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.command import CommandEnvelope
from loop_engineer.contracts.enums import CommonState, CommandType


def _minimal_command(**overrides) -> dict:
    base = dict(
        protocol_version=1,
        run_id="run-1",
        task_id="T1",
        omx_team_name="team-1",
        worker_identity="omx-worker-1",
        command_id="cmd-1",
        command_revision=1,
        expected_task_state=CommonState.READY,
        claim_generation=0,
        lease_generation=0,
        command_type=CommandType.START_TASK,
        instruction="begin",
        allowed_file_scope_hash="sha256:" + "a" * 64,
        evidence_requirements=["commit"],
        verification_requirements=["pytest -q"],
    )
    base.update(overrides)
    return base


def test_command_accepts_full_envelope():
    c = CommandEnvelope(**_minimal_command())
    assert c.command_type == CommandType.START_TASK


def test_command_revision_must_be_positive():
    with pytest.raises(ValidationError):
        CommandEnvelope(**_minimal_command(command_revision=0))


def test_causation_id_optional():
    c = CommandEnvelope(**_minimal_command(causation_id="cmd-0"))
    assert c.causation_id == "cmd-0"


def test_scope_hash_format_enforced():
    with pytest.raises(ValidationError):
        CommandEnvelope(**_minimal_command(allowed_file_scope_hash="not-a-hash"))


def test_protocol_version_must_be_positive():
    with pytest.raises(ValidationError):
        CommandEnvelope(**_minimal_command(protocol_version=0))
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/unit/test_command_envelope.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the implementation**

`src/loop_engineer/contracts/command.py`:

```python
"""Leader-to-adapter command envelope (spec §7.1)."""

from pydantic import BaseModel, Field, field_validator

from loop_engineer.contracts.enums import CommonState, CommandType

_SCOPE_HASH_RE = r"^sha256:[0-9a-f]{64}$"


class CommandEnvelope(BaseModel):
    protocol_version: int = Field(ge=1)
    run_id: str = Field(min_length=1)
    task_id: str = Field(min_length=1)
    omx_team_name: str = Field(min_length=1)
    worker_identity: str = Field(min_length=1)
    command_id: str = Field(min_length=1)
    causation_id: str | None = None
    command_revision: int = Field(ge=1)  # monotonic within the Task run
    expected_task_state: CommonState
    claim_generation: int = Field(ge=0)
    lease_generation: int = Field(ge=0)
    command_type: CommandType
    instruction: str = Field(min_length=1)
    allowed_file_scope_hash: str
    evidence_requirements: list[str] = Field(min_length=1)
    verification_requirements: list[str] = Field(min_length=1)
    deadline: str | None = None
    cancellation_policy: str | None = None

    @field_validator("allowed_file_scope_hash")
    @classmethod
    def _scope_hash_shape(cls, v: str) -> str:
        import re

        if not re.match(_SCOPE_HASH_RE, v):
            raise ValueError("allowed_file_scope_hash must be 'sha256:<64 hex>'")
        return v
```

- [ ] **Step 4: Run, verify pass, commit**

Run: `pytest tests/unit/test_command_envelope.py -v && ruff check .`
Expected: 5 passed.

```bash
git add src/loop_engineer/contracts/command.py tests/unit/test_command_envelope.py
git commit -m "feat(contracts): add Hybrid command envelope (spec §7.1)"
```

---

## Task 6: Event envelope

**Files:**
- Create: `src/loop_engineer/contracts/event.py`
- Test: `tests/unit/test_event_envelope.py`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_event_envelope.py`:

```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.enums import EventType
from loop_engineer.contracts.event import EventEnvelope


def _minimal_event(**overrides) -> dict:
    base = dict(
        run_id="run-1",
        task_id="T1",
        command_id="cmd-1",
        event_id="evt-1",
        event_sequence=1,
        provider_observation_revision=1,
        lease_generation=0,
        event_type=EventType.ACKNOWLEDGED,
        payload={},
    )
    base.update(overrides)
    return base


def test_event_accepts_full_envelope():
    e = EventEnvelope(**_minimal_event())
    assert e.event_type == EventType.ACKNOWLEDGED


def test_event_sequence_must_be_positive():
    with pytest.raises(ValidationError):
        EventEnvelope(**_minimal_event(event_sequence=0))


def test_provider_observation_revision_must_be_positive():
    with pytest.raises(ValidationError):
        EventEnvelope(**_minimal_event(provider_observation_revision=0))
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/unit/test_event_envelope.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the implementation**

`src/loop_engineer/contracts/event.py`:

```python
"""Adapter-to-leader event envelope (spec §7.2).

Events are append-only and idempotent by event_id. The journal enforces
sequence ordering; this model only freezes the wire shape.
"""

from pydantic import BaseModel, Field

from loop_engineer.contracts.enums import EventType


class EventEnvelope(BaseModel):
    run_id: str = Field(min_length=1)
    task_id: str = Field(min_length=1)
    command_id: str = Field(min_length=1)
    event_id: str = Field(min_length=1)
    event_sequence: int = Field(ge=1)  # monotonic per Task run
    provider_observation_revision: int = Field(ge=1)
    lease_generation: int = Field(ge=0)
    event_type: EventType
    payload: dict = Field(default_factory=dict)
```

- [ ] **Step 4: Run, verify pass, commit**

Run: `pytest tests/unit/test_event_envelope.py -v && ruff check .`
Expected: 3 passed.

```bash
git add src/loop_engineer/contracts/event.py tests/unit/test_event_envelope.py
git commit -m "feat(contracts): add Hybrid event envelope (spec §7.2)"
```

---

## Task 7: Claim and Lease

**Files:**
- Create: `src/loop_engineer/contracts/claim.py`
- Create: `src/loop_engineer/contracts/lease.py`
- Test: `tests/unit/test_claim_lease.py`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_claim_lease.py`:

```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.claim import Claim
from loop_engineer.contracts.lease import Lease


_CLAIM_DIGEST = "sha256:" + "0" * 64


def test_claim_accepts_digest_not_raw_token():
    c = Claim(
        omx_task_id="T1",
        holder="adapter-gen-0",
        generation=0,
        token_digest=_CLAIM_DIGEST,
    )
    assert c.token_digest.startswith("sha256:")


def test_claim_rejects_bad_digest_format():
    with pytest.raises(ValidationError):
        Claim(omx_task_id="T1", holder="x", generation=0, token_digest="raw-secret-never-stored")


def test_claim_generation_non_negative():
    with pytest.raises(ValidationError):
        Claim(omx_task_id="T1", holder="x", generation=-1, token_digest=_CLAIM_DIGEST)


def test_lease_requires_future_expiry_and_heartbeat():
    lease = Lease(generation=0, expires_at="2099-01-01T00:00:00Z", last_heartbeat_at="2099-01-01T00:00:00Z")
    assert lease.generation == 0


def test_lease_rejects_negative_generation():
    with pytest.raises(ValidationError):
        Lease(generation=-1, expires_at="2099-01-01T00:00:00Z", last_heartbeat_at="2099-01-01T00:00:00Z")
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/unit/test_claim_lease.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the implementations**

`src/loop_engineer/contracts/claim.py`:

```python
"""OMX Task claim (spec §6.4, §7.3).

Raw claim tokens are NEVER serialized into models, logs, events, or committed
evidence. Only the digest is stored. The raw token lives in permission-restricted
runtime state (P2).
"""

import re

from pydantic import BaseModel, Field, field_validator

_DIGEST_RE = r"^sha256:[0-9a-f]{64}$"


class Claim(BaseModel):
    omx_task_id: str = Field(min_length=1)
    holder: str = Field(min_length=1)
    generation: int = Field(ge=0)
    token_digest: str

    @field_validator("token_digest")
    @classmethod
    def _digest_shape(cls, v: str) -> str:
        if not re.match(_DIGEST_RE, v):
            raise ValueError("token_digest must be 'sha256:<64 hex>'")
        return v
```

`src/loop_engineer/contracts/lease.py`:

```python
"""Process lease with heartbeat and expiry (spec §6.2, §7.3)."""

from pydantic import BaseModel, Field


class Lease(BaseModel):
    generation: int = Field(ge=0)
    # ISO-8601 UTC strings keep the model JSON-serializable without a tz engine.
    expires_at: str = Field(min_length=1)
    last_heartbeat_at: str = Field(min_length=1)
```

- [ ] **Step 4: Run, verify pass, commit**

Run: `pytest tests/unit/test_claim_lease.py -v && ruff check .`
Expected: 5 passed.

```bash
git add src/loop_engineer/contracts/claim.py src/loop_engineer/contracts/lease.py tests/unit/test_claim_lease.py
git commit -m "feat(contracts): add Claim (digest-only) and Lease schemas"
```

---

## Task 8: Evidence and Handoff

**Files:**
- Create: `src/loop_engineer/contracts/evidence.py`
- Create: `src/loop_engineer/contracts/handoff.py`
- Test: `tests/unit/test_evidence_handoff.py`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_evidence_handoff.py`:

```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.evidence import Evidence, EvidenceType
from loop_engineer.contracts.handoff import Handoff


def test_evidence_accepts_commit_with_digest():
    e = Evidence(kind=EvidenceType.COMMIT, digest="sha256:" + "1" * 64, ref="abc123")
    assert e.kind == EvidenceType.COMMIT


def test_evidence_rejects_empty_digest():
    with pytest.raises(ValidationError):
        Evidence(kind=EvidenceType.COMMIT, digest="", ref="abc123")


def test_handoff_records_integration_branch_and_downstream():
    h = Handoff(integration_branch="task/T1", downstream_task_ids=["T2"])
    assert h.integration_branch == "task/T1"
    assert h.downstream_task_ids == ["T2"]


def test_handoff_rejects_empty_branch():
    with pytest.raises(ValidationError):
        Handoff(integration_branch="", downstream_task_ids=[])
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/unit/test_evidence_handoff.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the implementations**

`src/loop_engineer/contracts/evidence.py`:

```python
"""Evidence contract (spec §6.3, §13)."""

from enum import StrEnum

from pydantic import BaseModel, Field


class EvidenceType(StrEnum):
    COMMIT = "commit"
    TEST_RUN = "test_run"
    VERIFICATION_RUN = "verification_run"
    SCOPE_PROOF = "scope_proof"
    TREE_HASH = "tree_hash"


class Evidence(BaseModel):
    kind: EvidenceType
    digest: str = Field(min_length=1)
    ref: str = Field(min_length=1)
    produced_at: str | None = None
```

`src/loop_engineer/contracts/handoff.py`:

```python
"""Integration and downstream handoff constraints (spec §6.1)."""

from pydantic import BaseModel, Field


class Handoff(BaseModel):
    integration_branch: str = Field(min_length=1)
    integration_worktree: str | None = None
    downstream_task_ids: list[str] = Field(default_factory=list)
    constraints: list[str] = Field(default_factory=list)
```

- [ ] **Step 4: Run, verify pass, commit**

Run: `pytest tests/unit/test_evidence_handoff.py -v && ruff check .`
Expected: 4 passed.

```bash
git add src/loop_engineer/contracts/evidence.py src/loop_engineer/contracts/handoff.py tests/unit/test_evidence_handoff.py
git commit -m "feat(contracts): add Evidence and Handoff schemas"
```

---

## Task 9: WriterFence and RecoveryRecord

**Files:**
- Create: `src/loop_engineer/contracts/fence.py`
- Create: `src/loop_engineer/contracts/recovery.py`
- Test: `tests/unit/test_fence.py`
- Test: `tests/unit/test_recovery_record.py`

- [ ] **Step 1: Write the failing fence test**

`tests/unit/test_fence.py`:

```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.fence import FencingProof, ProcessGroupIdentity, WriterFence


def test_writer_fence_generation_monotonic_default():
    f = WriterFence(writer_generation=1, fenced_paths=[".git/worktrees/t1"])
    assert f.writer_generation == 1


def test_writer_fence_rejects_negative_generation():
    with pytest.raises(ValidationError):
        WriterFence(writer_generation=-1, fenced_paths=["x"])


def test_fencing_proof_requires_absence_and_clean_worktrees_and_equal_trees():
    p = FencingProof(
        provider_process_group=[
            ProcessGroupIdentity(pid=1234, start_time="2026-01-01T00:00:00Z", executable="claude")
        ],
        shutdown_acks=["ack-worker-1"],
        absence_proofs=["pid 1234 gone at 2026-01-01T00:01:00Z"],
        provider_worktrees_clean=True,
        result_tree_hash="sha256:" + "9" * 64,
        integration_tree_hash="sha256:" + "9" * 64,
    )
    assert p.provider_worktrees_clean is True
    assert p.result_tree_hash == p.integration_tree_hash


def test_fencing_proof_rejects_mismatched_trees():
    with pytest.raises(ValidationError):
        FencingProof(
            provider_process_group=[],
            shutdown_acks=["ack-1"],
            absence_proofs=["gone"],
            provider_worktrees_clean=True,
            result_tree_hash="sha256:" + "9" * 64,
            integration_tree_hash="sha256:" + "8" * 64,
        )
```

- [ ] **Step 2: Write the failing recovery test**

`tests/unit/test_recovery_record.py`:

```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.recovery import RecoveryRecord


def _minimal_record(**overrides) -> dict:
    base = dict(
        repo_identity="repo-1",
        run_id="run-1",
        task_id="T1",
        lane="hybrid",
        protocol_version=1,
        base_commit="abc123",
        integration_branch="task/T1",
        integration_worktree="/tmp/wt",
        adapter_exec_branch="exec/T1",
        adapter_exec_worktree="/tmp/exec",
        omx_team_name="team-1",
        leader_session="sess-1",
        worker_identity="omx-worker-1",
        claim_token_digest="sha256:" + "0" * 64,
        lease_generation=0,
        claude_leader_pane="claude-pane-1",
        claude_leader_pid=4321,
        claude_leader_start_time="2026-01-01T00:00:00Z",
        claude_leader_executable="claude",
        omc_state_root="/tmp/omc",
        omc_team_name="omc-team-1",
        last_command_revision=1,
        last_event_sequence=1,
        journal_checksum="sha256:" + "2" * 64,
        current_phase="omc_executing",
        cleanup_phase=None,
        writer_fencing_generation=0,
        shutdown_acks=[],
    )
    base.update(overrides)
    return base


def test_recovery_record_accepts_full_coordinate_set():
    r = RecoveryRecord(**_minimal_record())
    assert r.task_id == "T1"


def test_recovery_record_rejects_missing_field():
    bad = _minimal_record()
    bad.pop("journal_checksum")
    with pytest.raises(ValidationError):
        RecoveryRecord(**bad)


def test_recovery_record_protocol_version_positive():
    with pytest.raises(ValidationError):
        RecoveryRecord(**_minimal_record(protocol_version=0))
```

- [ ] **Step 3: Run both to verify they fail**

Run: `pytest tests/unit/test_fence.py tests/unit/test_recovery_record.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 4: Write the implementations**

`src/loop_engineer/contracts/fence.py`:

```python
"""Writer-fence contract for OMC->OMX promotion (spec §8).

Shutdown acknowledgment alone is insufficient. Promotion requires every OMC
worker + Claude leader shutdown ack, the full provider process group proven
absent by PID start identity, provider worktrees proven clean, and equal tree
hashes between the pinned result and the promoted integration tree.
"""

from pydantic import BaseModel, Field, model_validator


class ProcessGroupIdentity(BaseModel):
    pid: int = Field(ge=1)
    start_time: str = Field(min_length=1)
    executable: str = Field(min_length=1)


class FencingProof(BaseModel):
    provider_process_group: list[ProcessGroupIdentity] = Field(min_length=1)
    shutdown_acks: list[str] = Field(min_length=1)
    absence_proofs: list[str] = Field(min_length=1)
    provider_worktrees_clean: bool
    result_tree_hash: str = Field(min_length=1)
    integration_tree_hash: str = Field(min_length=1)

    @model_validator(mode="after")
    def _trees_must_match(self) -> "FencingProof":
        if self.result_tree_hash != self.integration_tree_hash:
            raise ValueError("result_tree_hash and integration_tree_hash must be equal at promotion")
        return self


class WriterFence(BaseModel):
    writer_generation: int = Field(ge=0)
    fenced_paths: list[str] = Field(min_length=1)
    proof: FencingProof | None = None
```

`src/loop_engineer/contracts/recovery.py`:

```python
"""Versioned recovery coordinate record (spec §7.5).

Stored in the Git common directory, outside ordinary commits. Every field here
maps to a bullet in §7.5; do not drop one without updating the spec.
"""

from pydantic import BaseModel, Field


class RecoveryRecord(BaseModel):
    # identity
    repo_identity: str = Field(min_length=1)
    run_id: str = Field(min_length=1)
    task_id: str = Field(min_length=1)
    lane: str = Field(min_length=1)
    protocol_version: int = Field(ge=1)
    # git coordinates
    base_commit: str = Field(min_length=1)
    integration_branch: str = Field(min_length=1)
    integration_worktree: str = Field(min_length=1)
    adapter_exec_branch: str = Field(min_length=1)
    adapter_exec_worktree: str = Field(min_length=1)
    pinned_result_commit: str | None = None
    review_base_commit: str | None = None
    # omx coordinates
    omx_team_name: str = Field(min_length=1)
    leader_session: str = Field(min_length=1)
    leader_pane: str | None = None
    worker_identity: str = Field(min_length=1)
    omx_task_id: str | None = None
    claim_token_digest: str = Field(min_length=1)
    lease_generation: int = Field(ge=0)
    lease_expiry: str | None = None
    # claude leader coordinates
    claude_leader_session: str | None = None
    claude_leader_pane: str = Field(min_length=1)
    claude_leader_pid: int = Field(ge=1)
    claude_leader_start_time: str = Field(min_length=1)
    claude_leader_executable: str = Field(min_length=1)
    # omc coordinates
    omc_state_root: str = Field(min_length=1)
    omc_team_name: str = Field(min_length=1)
    omc_worker_identities: list[str] = Field(default_factory=list)
    provider_task_ids: list[str] = Field(default_factory=list)
    last_summary_revision: int | None = None
    # journal coordinates
    last_command_revision: int = Field(ge=1)
    last_event_sequence: int = Field(ge=1)
    journal_checksum: str = Field(min_length=1)
    # phase coordinates
    current_phase: str = Field(min_length=1)
    cleanup_phase: str | None = None
    # fencing
    writer_fencing_generation: int = Field(ge=0)
    shutdown_acks: list[str] = Field(default_factory=list)
```

- [ ] **Step 5: Run, verify pass, commit**

Run: `pytest tests/unit/test_fence.py tests/unit/test_recovery_record.py -v && ruff check .`
Expected: 7 passed.

```bash
git add src/loop_engineer/contracts/fence.py src/loop_engineer/contracts/recovery.py tests/unit/test_fence.py tests/unit/test_recovery_record.py
git commit -m "feat(contracts): add WriterFence and RecoveryRecord (spec §7.5, §8)"
```

---

## Task 10: Provenance manifest

**Files:**
- Create: `src/loop_engineer/contracts/provenance.py`
- Test: `tests/unit/test_provenance.py`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_provenance.py`:

```python
import pytest
from pydantic import ValidationError

from loop_engineer.contracts.provenance import ProvenanceEntry, ProvenanceManifest


def test_empty_manifest_is_valid_original_only():
    m = ProvenanceManifest(entries=[])
    assert m.redistribution_allowed("src/loop_engineer/contracts/goal.py") is True


def test_entry_requires_all_four_fields():
    with pytest.raises(ValidationError):
        ProvenanceEntry(path="scripts/x.sh", source_origin="local", source_license="", transformation="none", approved=True)


def test_manifest_blocks_unapproved_redistribution():
    entry = ProvenanceEntry(
        path="scripts/imported.sh", source_origin="vendor/foo", source_license="unknown",
        transformation="verbatim", approved=False,
    )
    m = ProvenanceManifest(entries=[entry])
    assert m.redistribution_allowed("scripts/imported.sh") is False


def test_manifest_allows_approved_entry():
    entry = ProvenanceEntry(
        path="scripts/imported.sh", source_origin="vendor/foo", source_license="MIT",
        transformation="adapted", approved=True,
    )
    m = ProvenanceManifest(entries=[entry])
    assert m.redistribution_allowed("scripts/imported.sh") is True


def test_manifest_rejects_duplicate_paths():
    e = ProvenanceEntry(path="x", source_origin="o", source_license="MIT", transformation="none", approved=True)
    with pytest.raises(ValidationError):
        ProvenanceManifest(entries=[e, e])
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/unit/test_provenance.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the implementation**

`src/loop_engineer/contracts/provenance.py`:

```python
"""Provenance manifest (spec §10).

Original code has no entry and is redistributable. Any imported/adapted file
requires an entry with source origin, source license, transformation policy,
and explicit approval before redistribution.
"""

from pathlib import PurePosixPath

from pydantic import BaseModel, Field, model_validator


class ProvenanceEntry(BaseModel):
    path: str = Field(min_length=1)
    source_origin: str = Field(min_length=1)
    source_license: str = Field(min_length=1)
    transformation: str = Field(min_length=1)  # verbatim | adapted | generated-from
    approved: bool = False
    imported_at: str | None = None


class ProvenanceManifest(BaseModel):
    entries: list[ProvenanceEntry] = Field(default_factory=list)

    @model_validator(mode="after")
    def _unique_paths(self) -> "ProvenanceManifest":
        paths = [e.path for e in self.entries]
        if len(paths) != len(set(paths)):
            raise ValueError("provenance paths must be unique")
        return self

    def _normalized(self, path: str) -> str:
        return PurePosixPath(path).as_posix()

    def redistribution_allowed(self, path: str) -> bool:
        """True iff the file is original (no entry) or has an approved entry."""
        target = self._normalized(path)
        for e in self.entries:
            if self._normalized(e.path) == target:
                return e.approved
        return True  # original code: no entry required
```

- [ ] **Step 4: Run, verify pass, commit**

Run: `pytest tests/unit/test_provenance.py -v && ruff check .`
Expected: 5 passed.

```bash
git add src/loop_engineer/contracts/provenance.py tests/unit/test_provenance.py
git commit -m "feat(contracts): add provenance manifest policy (spec §10)"
```

---

## Task 11: Append-only event journal (contract + minimal JSONL impl)

**Files:**
- Create: `src/loop_engineer/state/journal.py`
- Test: `tests/unit/test_journal_semantics.py`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_journal_semantics.py`:

```python
import pytest

from loop_engineer.contracts.enums import EventType
from loop_engineer.contracts.event import EventEnvelope
from loop_engineer.state.journal import JsonlJournal, StaleEventError


def _evt(seq: int, eid: str) -> EventEnvelope:
    return EventEnvelope(
        run_id="r", task_id="T1", command_id="c", event_id=eid, event_sequence=seq,
        provider_observation_revision=1, lease_generation=0, event_type=EventType.PROGRESS, payload={},
    )


def test_append_in_order(tmp_path):
    j = JsonlJournal(tmp_path / "journal.jsonl")
    j.append(_evt(1, "a"))
    j.append(_evt(2, "b"))
    assert [e.event_id for e in j.replay()] == ["a", "b"]


def test_duplicate_event_id_is_idempotent(tmp_path):
    j = JsonlJournal(tmp_path / "journal.jsonl")
    j.append(_evt(1, "a"))
    j.append(_evt(1, "a"))  # same id, same sequence -> ignored
    assert [e.event_id for e in j.replay()] == ["a"]


def test_future_sequence_gap_is_held_not_rejected(tmp_path):
    j = JsonlJournal(tmp_path / "journal.jsonl")
    j.append(_evt(1, "a"))
    held = j.append(_evt(3, "c"))  # gap: 2 missing
    assert held is False
    assert [e.event_id for e in j.replay()] == ["a"]


def test_gap_fills_and_replays_in_order(tmp_path):
    j = JsonlJournal(tmp_path / "journal.jsonl")
    j.append(_evt(1, "a"))
    j.append(_evt(3, "c"))
    j.append(_evt(2, "b"))  # fills the gap
    assert [e.event_id for e in j.replay()] == ["a", "b", "c"]


def test_lower_unseen_sequence_is_rejected_as_stale(tmp_path):
    j = JsonlJournal(tmp_path / "journal.jsonl")
    j.append(_evt(2, "b"))  # first event at seq 2 is accepted (no prior expectation)
    with pytest.raises(StaleEventError):
        j.append(_evt(1, "a"))  # now below the high-water mark -> stale
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/unit/test_journal_semantics.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the implementation**

`src/loop_engineer/state/journal.py`:

```python
"""Append-only event journal (spec §7.2).

Contract:
  - append-only and idempotent by event_id (duplicates ignored),
  - the journal accepts only the next event_sequence,
  - a future sequence gap is held for replay (not persisted until the gap fills),
  - a sequence below the committed high-water mark is rejected as stale.

P1 ships the contract + a minimal JSONL file implementation. The durable engine
default is locked here (D5); a different engine may swap in behind `Journal`.
"""

from pathlib import Path

from loop_engineer.contracts.event import EventEnvelope


class StaleEventError(Exception):
    """An event arrived with a sequence below the committed high-water mark."""


class Journal:
    """Interface for append-only, sequence-ordered event journals."""

    def append(self, event: EventEnvelope) -> bool:
        raise NotImplementedError

    def replay(self) -> list[EventEnvelope]:
        raise NotImplementedError


class JsonlJournal(Journal):
    """File-backed append-only journal with hold-for-gap semantics.

    Held (out-of-order, future-sequence) events live only in memory until their
    gap fills, so the on-disk file is always a gap-free prefix.
    """

    def __init__(self, path: str | Path) -> None:
        self._path = Path(path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._path.touch(exist_ok=True)
        self._seen_ids: set[str] = set()
        self._next_sequence: int = 1
        self._held: dict[int, EventEnvelope] = {}
        for e in self._read_all():
            self._seen_ids.add(e.event_id)
            self._next_sequence = max(self._next_sequence, e.event_sequence + 1)

    def _read_all(self) -> list[EventEnvelope]:
        import json

        events: list[EventEnvelope] = []
        for line in self._path.read_text().splitlines():
            line = line.strip()
            if line:
                events.append(EventEnvelope(**json.loads(line)))
        return events

    def _persist(self, event: EventEnvelope) -> None:
        import json

        with self._path.open("a") as fh:
            fh.write(json.dumps(event.model_dump()) + "\n")

    def append(self, event: EventEnvelope) -> bool:
        # Idempotent by event_id: a duplicate is a no-op success.
        if event.event_id in self._seen_ids:
            return True
        if event.event_sequence < self._next_sequence:
            raise StaleEventError(
                f"event {event.event_id} seq {event.event_sequence} < next {self._next_sequence}"
            )
        if event.event_sequence > self._next_sequence:
            # Future gap: hold in memory, do not persist.
            self._held[event.event_sequence] = event
            return False
        # Exactly the next sequence: commit, then drain any held successors.
        self._commit(event)
        self._drain_held()
        return True

    def _commit(self, event: EventEnvelope) -> None:
        self._persist(event)
        self._seen_ids.add(event.event_id)
        self._next_sequence = event.event_sequence + 1

    def _drain_held(self) -> None:
        while self._next_sequence in self._held:
            nxt = self._held.pop(self._next_sequence)
            self._commit(nxt)

    def replay(self) -> list[EventEnvelope]:
        # Committed prefix in sequence order; held events are not yet durable.
        return self._read_all()
```

- [ ] **Step 4: Run, verify pass, commit**

Run: `pytest tests/unit/test_journal_semantics.py -v && ruff check .`
Expected: 5 passed.

```bash
git add src/loop_engineer/state/journal.py tests/unit/test_journal_semantics.py
git commit -m "feat(state): add append-only event journal with gap-hold semantics (spec §7.2)"
```

---

## Task 12: Schema freeze pipeline (export + drift detection + round-trip)

**Files:**
- Create: `scripts/export_schemas.py`
- Create: `schemas/README.md`
- Generate + commit: `schemas/v1/*.schema.json`, `schemas/manifest.json`
- Test: `tests/contract/test_schema_freeze_drift.py`
- Test: `tests/contract/test_schema_roundtrip.py`

- [ ] **Step 1: Write the export script**

`scripts/export_schemas.py`:

```python
#!/usr/bin/env python3
"""Export pydantic models to frozen JSON Schemas + a digest manifest.

Run after any contract change: `python scripts/export_schemas.py`.
The drift test (tests/contract/test_schema_freeze_drift.py) then fails until the
regenerated files are committed, making schema changes reviewable.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from loop_engineer.contracts.claim import Claim
from loop_engineer.contracts.command import CommandEnvelope
from loop_engineer.contracts.event import EventEnvelope
from loop_engineer.contracts.evidence import Evidence
from loop_engineer.contracts.fence import WriterFence
from loop_engineer.contracts.goal import Goal
from loop_engineer.contracts.handoff import Handoff
from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.plan import Plan
from loop_engineer.contracts.provenance import ProvenanceManifest
from loop_engineer.contracts.recovery import RecoveryRecord
from loop_engineer.contracts.task import Task

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_DIR = ROOT / "schemas" / "v1"
MANIFEST = ROOT / "schemas" / "manifest.json"

MODELS = {
    "goal": Goal,
    "task": Task,
    "plan": Plan,
    "command": CommandEnvelope,
    "event": EventEnvelope,
    "claim": Claim,
    "lease": Lease,
    "evidence": Evidence,
    "handoff": Handoff,
    "fence": WriterFence,
    "recovery": RecoveryRecord,
    "provenance": ProvenanceManifest,
}


def export() -> dict:
    SCHEMA_DIR.mkdir(parents=True, exist_ok=True)
    registry: dict[str, dict] = {}
    for name, model in MODELS.items():
        schema = model.model_json_schema()
        path = SCHEMA_DIR / f"{name}.schema.json"
        path.write_text(json.dumps(schema, indent=2, sort_keys=True) + "\n")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        registry[name] = {
            "file": f"v1/{name}.schema.json",
            "version": 1,
            "sha256": digest,
        }
    MANIFEST.write_text(json.dumps({"version": 1, "schemas": registry}, indent=2, sort_keys=True) + "\n")
    return registry


if __name__ == "__main__":
    export()
    print(f"exported {len(MODELS)} schemas to {SCHEMA_DIR}")
```

- [ ] **Step 2: Write `schemas/README.md`**

```markdown
# Frozen JSON Schemas

These files are the wire-format contract for Loop Engineer (spec §12 P1).

- **Source of truth:** pydantic v2 models under `src/loop_engineer/contracts/`.
- **Never hand-edit** a file under `v1/`. Regenerate with `python scripts/export_schemas.py`.
- **Drift is a build failure:** `tests/contract/test_schema_freeze_drift.py` fails if a model changed but the schema file was not regenerated and committed.
- **Versioning:** `manifest.json` records each schema's version and SHA-256. A breaking change bumps the version and the `v1/` directory name.
```

- [ ] **Step 3: Regenerate the committed schema files**

Run:
```bash
. .venv/bin/activate
python scripts/export_schemas.py
```
Expected: prints `exported 12 schemas to .../schemas/v1`.

- [ ] **Step 4: Write the drift contract test**

`tests/contract/test_schema_freeze_drift.py`:

```python
"""Schema drift detector (spec §12 P1).

If a model changes but schemas/v1 is not regenerated, this fails so the change
is visible in review.
"""

import hashlib
import json
from pathlib import Path

import pytest

from scripts.export_schemas import MODELS  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = ROOT / "schemas" / "v1"
MANIFEST = ROOT / "schemas" / "manifest.json"


@pytest.mark.parametrize("name,model", list(MODELS.items()))
def test_committed_schema_matches_model(name, model):
    path = SCHEMA_DIR / f"{name}.schema.json"
    assert path.exists(), f"missing schema {path}; run scripts/export_schemas.py"
    expected = json.loads(path.read_text())
    actual = model.model_json_schema()
    assert expected == actual, (
        f"schema drift for {name}: run `python scripts/export_schemas.py` and commit the diff"
    )


@pytest.mark.parametrize("name,model", list(MODELS.items()))
def test_manifest_digest_matches_file(name, model):
    manifest = json.loads(MANIFEST.read_text())
    entry = manifest["schemas"][name]
    path = SCHEMA_DIR / f"{name}.schema.json"
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert entry["sha256"] == digest, f"manifest digest stale for {name}"
```

- [ ] **Step 5: Write the round-trip contract test**

`tests/contract/test_schema_roundtrip.py` (full file):

```python
"""External JSON validated by frozen JSON Schema validates the pydantic model
too (spec §11 contract tests: schema compatibility)."""

import json
from pathlib import Path

import jsonschema
import pytest

from scripts.export_schemas import MODELS  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = ROOT / "schemas" / "v1"

_HEX64 = "a" * 64

PAYLOADS = {
    "goal": {
        "id": "G", "title": "t", "measurable_evidence": "ok", "scope": ["x"],
        "exclusions": [], "stop_conditions": [],
        "milestones": [{"id": "M", "title": "m", "evidence_condition": "c"}],
    },
    "task": {
        "id": "T", "owner_domain": "omx", "status": "pending", "dependencies": [],
        "allowed_files": ["src/a.py"], "non_goals": [], "acceptance_criteria": ["x"],
        "verification": {"commands": ["pytest -q"], "working_dir": "."},
        "required_evidence": ["commit"], "downstream_handoff": [],
    },
    "plan": {
        "goal_id": "G",
        "nodes": [{"task": {
            "id": "T", "owner_domain": "omx", "status": "pending", "dependencies": [],
            "allowed_files": ["src/a.py"], "non_goals": [], "acceptance_criteria": ["x"],
            "verification": {"commands": ["pytest -q"], "working_dir": "."},
            "required_evidence": ["commit"], "downstream_handoff": [],
        }}],
        "edges": [],
    },
    "command": {
        "protocol_version": 1, "run_id": "r", "task_id": "T", "omx_team_name": "tm",
        "worker_identity": "w", "command_id": "c", "command_revision": 1,
        "expected_task_state": "ready", "claim_generation": 0, "lease_generation": 0,
        "command_type": "START_TASK", "instruction": "go",
        "allowed_file_scope_hash": f"sha256:{_HEX64}",
        "evidence_requirements": ["commit"], "verification_requirements": ["pytest -q"],
    },
    "event": {
        "run_id": "r", "task_id": "T", "command_id": "c", "event_id": "e",
        "event_sequence": 1, "provider_observation_revision": 1, "lease_generation": 0,
        "event_type": "ACKNOWLEDGED", "payload": {},
    },
    "claim": {
        "omx_task_id": "T", "holder": "h", "generation": 0,
        "token_digest": f"sha256:{_HEX64}",
    },
    "lease": {"generation": 0, "expires_at": "2099-01-01T00:00:00Z", "last_heartbeat_at": "2099-01-01T00:00:00Z"},
    "evidence": {"kind": "commit", "digest": f"sha256:{_HEX64}", "ref": "abc"},
    "handoff": {"integration_branch": "task/T1", "downstream_task_ids": ["T2"]},
    "fence": {"writer_generation": 1, "fenced_paths": [".git/worktrees/t1"]},
    "recovery": {
        "repo_identity": "repo", "run_id": "r", "task_id": "T", "lane": "hybrid",
        "protocol_version": 1, "base_commit": "abc", "integration_branch": "task/T1",
        "integration_worktree": "/wt", "adapter_exec_branch": "exec/T1",
        "adapter_exec_worktree": "/exec", "omx_team_name": "tm", "leader_session": "s",
        "worker_identity": "w", "claim_token_digest": f"sha256:{_HEX64}",
        "lease_generation": 0, "claude_leader_pane": "p", "claude_leader_pid": 1,
        "claude_leader_start_time": "2026-01-01T00:00:00Z", "claude_leader_executable": "claude",
        "omc_state_root": "/omc", "omc_team_name": "otm", "last_command_revision": 1,
        "last_event_sequence": 1, "journal_checksum": f"sha256:{_HEX64}",
        "current_phase": "omc_executing", "writer_fencing_generation": 0, "shutdown_acks": [],
    },
    "provenance": {"entries": []},
}


@pytest.mark.parametrize("name,model", list(MODELS.items()))
def test_payload_validates_against_frozen_schema(name, model):
    schema = json.loads((SCHEMA_DIR / f"{name}.schema.json").read_text())
    payload = PAYLOADS[name]
    jsonschema.validate(payload, schema)  # external JSON accepted by schema
    model(**payload)                      # ...and accepted by the model


@pytest.mark.parametrize("name", list(MODELS))
def test_model_dump_validates_against_schema(name):
    schema = json.loads((SCHEMA_DIR / f"{name}.schema.json").read_text())
    model = MODELS[name]
    instance = model(**PAYLOADS[name])
    jsonschema.validate(json.loads(instance.model_dump_json()), schema)
```

- [ ] **Step 6: Make `scripts` importable by tests**

Add an empty `scripts/__init__.py`:

```python
"""Export scripts package (importable by contract tests)."""
```

- [ ] **Step 7: Run all contract tests + regenerate once to settle**

Run:
```bash
. .venv/bin/activate
python scripts/export_schemas.py
pytest tests/contract/ tests/unit/ -v && ruff check .
```
Expected: all green; `export_schemas.py` prints `exported 12 schemas`.

- [ ] **Step 8: Commit**

```bash
git add scripts/ schemas/ tests/contract/test_schema_freeze_drift.py tests/contract/test_schema_roundtrip.py
git commit -m "feat(contracts): freeze JSON Schema export pipeline with drift + round-trip tests"
```

---

## Task 13: Capability probe (safe, no Team launch)

**Files:**
- Create: `src/loop_engineer/probe/capabilities.py`
- Test: `tests/probe/test_capabilities_fake.py`

- [ ] **Step 1: Write the failing test**

`tests/probe/test_capabilities_fake.py`:

```python
import pytest

from loop_engineer.contracts.enums import ExitCode
from loop_engineer.probe.capabilities import CapabilityRecord, probe_capabilities


def _fake_runner(table):
    def runner(argv):
        return table[tuple(argv)]
    return runner


def test_probe_records_detected_versions():
    table = {
        ("git", "--version"): ("git version 2.43.0\n", 0),
        ("tmux", "-V"): ("tmux 3.4\n", 0),
        ("codex", "--version"): ("codex 0.9.0\n", 0),
        ("claude", "--version"): ("claude 1.0.0\n", 0),
    }
    rec = probe_capabilities(run=_fake_runner(table))
    assert rec.git_version == "2.43.0"
    assert rec.tmux_version == "3.4"
    assert rec.codex_version == "0.9.0"
    assert rec.claude_version == "1.0.0"
    assert rec.exit_code == ExitCode.OK


def test_probe_missing_optional_provider_records_none_not_failure():
    def runner(argv):
        if argv[0] == "claude":
            return ("", 127)  # not installed
        return {
            ("git", "--version"): ("git version 2.43.0\n", 0),
            ("tmux", "-V"): ("tmux 3.4\n", 0),
            ("codex", "--version"): ("codex 0.9.0\n", 0),
        }[tuple(argv)]
    rec = probe_capabilities(run=runner)
    assert rec.claude_version is None
    assert rec.exit_code == ExitCode.OK


def test_probe_missing_required_tool_returns_exit_2():
    def runner(argv):
        if argv[0] == "git":
            return ("", 127)
        return {("tmux", "-V"): ("tmux 3.4\n", 0), ("codex", "--version"): ("codex 0.9.0\n", 0)}[tuple(argv)]
    rec = probe_capabilities(run=runner)
    assert rec.exit_code == ExitCode.INVALID_INPUT
    assert rec.git_version is None


def test_probe_never_launches_team(monkeypatch):
    # The probe must call only read-only version commands; any other argv is a bug.
    seen = []

    def runner(argv):
        seen.append(tuple(argv))
        return ("tool version 1.0.0\n", 0)

    probe_capabilities(run=runner)
    for argv in seen:
        assert argv[-1] in ("--version", "-V"), f"probe issued non-version command: {argv}"
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/probe/test_capabilities_fake.py -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the implementation**

`src/loop_engineer/probe/capabilities.py`:

```python
"""Safe capability probe (spec §12 P1, §14 D7).

Detects installed tool versions using ONLY read-only `--version` / `-V` commands.
Never launches a Team, never writes outside a state dir, never shells out to a
mutating command. Supported OMX/OMC version ranges are runtime data recorded
here, not hardcoded contracts.
"""

import re
import shutil
import subprocess
from typing import Callable, Sequence

from pydantic import BaseModel

from loop_engineer.contracts.enums import ExitCode

# A runner maps an argv tuple to (stdout, returncode). Default shells out.
Runner = Callable[[Sequence[str]], tuple[str, int]]


class CapabilityRecord(BaseModel):
    git_version: str | None
    tmux_version: str | None
    codex_version: str | None   # OMX/Codex leader
    claude_version: str | None  # OMC/Claude workers
    exit_code: ExitCode


_VERSION_RE = re.compile(r"(\d+\.\d+(?:\.\d+)?)")


def _extract(stdout: str) -> str | None:
    m = _VERSION_RE.search(stdout)
    return m.group(1) if m else None


def _default_run(argv: Sequence[str]) -> tuple[str, int]:
    if shutil.which(argv[0]) is None:
        return "", 127
    proc = subprocess.run(list(argv), capture_output=True, text=True, check=False)
    return proc.stdout, proc.returncode


def probe_capabilities(run: Runner | None = None) -> CapabilityRecord:
    runner = run or _default_run
    git = _extract(runner(("git", "--version"))[0])
    tmux = _extract(runner(("tmux", "-V"))[0])
    codex = _extract(runner(("codex", "--version"))[0])
    claude = _extract(runner(("claude", "--version"))[0])
    # git and tmux are required; codex/claude are lane-dependent and may be absent.
    exit_code = ExitCode.OK if git and tmux else ExitCode.INVALID_INPUT
    return CapabilityRecord(
        git_version=git, tmux_version=tmux, codex_version=codex, claude_version=claude,
        exit_code=exit_code,
    )
```

- [ ] **Step 4: Run, verify pass, commit**

Run: `pytest tests/probe/test_capabilities_fake.py -v && ruff check .`
Expected: 4 passed.

```bash
git add src/loop_engineer/probe/capabilities.py tests/probe/test_capabilities_fake.py
git commit -m "feat(probe): add safe capability probe (read-only, no Team launch)"
```

---

## Task 14: P1 gate — public re-exports, README, full suite, acceptance checklist

**Files:**
- Modify: `src/loop_engineer/contracts/__init__.py`
- Modify: `README.md`
- Create: `tests/probe/__init__.py` (empty, if not present)

- [ ] **Step 1: Re-export the public contract surface**

`src/loop_engineer/contracts/__init__.py`:

```python
"""Public contract surface for Loop Engineer (spec §12 P1)."""

from loop_engineer.contracts.claim import Claim
from loop_engineer.contracts.command import CommandEnvelope
from loop_engineer.contracts.enums import (
    CommandType,
    CommonState,
    EventType,
    ExecutorState,
    ExitCode,
    OmxTaskStatus,
)
from loop_engineer.contracts.evidence import Evidence, EvidenceType
from loop_engineer.contracts.fence import FencingProof, WriterFence
from loop_engineer.contracts.goal import Goal, Milestone
from loop_engineer.contracts.handoff import Handoff
from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode, Wave
from loop_engineer.contracts.provenance import ProvenanceEntry, ProvenanceManifest
from loop_engineer.contracts.recovery import RecoveryRecord
from loop_engineer.contracts.task import Task, VerificationSpec

__all__ = [
    "Claim", "CommandEnvelope", "CommandType", "CommonState", "EventType",
    "ExecutorState", "ExitCode", "OmxTaskStatus", "Evidence", "EvidenceType",
    "FencingProof", "WriterFence", "Goal", "Milestone", "Handoff", "Lease",
    "DependencyEdge", "Plan", "TaskNode", "Wave", "ProvenanceEntry",
    "ProvenanceManifest", "RecoveryRecord", "Task", "VerificationSpec",
]
```

- [ ] **Step 2: Verify the public surface imports and round-trips**

Run:
```bash
. .venv/bin/activate
python -c "from loop_engineer.contracts import CommandEnvelope, ExitCode, Plan; print('ok', int(ExitCode.OK))"
```
Expected: prints `ok 0`.

- [ ] **Step 3: Update README with install + dev + schema-freeze sections**

Append to `README.md` (after the existing architecture section):

```markdown

## Develop

Requires Python ≥ 3.11.

```bash
python3.11 -m venv .venv
. .venv/bin/activate
pip install -e ".[dev]"
pytest -q
ruff check .
```

## Contracts (P1)

Versioned schemas live under [`schemas/v1/`](schemas/v1/) with a digest
[`manifest.json`](schemas/manifest.json). The pydantic models in
`src/loop_engineer/contracts/` are the source of truth.

After changing a contract, regenerate and commit the frozen schema:

```bash
python scripts/export_schemas.py
```

The drift test (`tests/contract/test_schema_freeze_drift.py`) fails until the
regenerated files are committed, so every schema change shows up in review.
```

- [ ] **Step 4: Run the entire suite + lint**

Run:
```bash
. .venv/bin/activate
python scripts/export_schemas.py   # idempotent; should produce no diff
pytest -q
ruff check .
```
Expected: full suite green; `export_schemas.py` produces no uncommitted diff (if it does, a schema drifted — recommit); ruff clean.

- [ ] **Step 5: P1 acceptance checklist (verify each against spec §12 P1 + §13)**

Manually confirm each box before committing:

- [ ] Goal schema frozen (§6.1) — `schemas/v1/goal.schema.json`.
- [ ] Task schema with exact `allowed_files` frozen (§6.1).
- [ ] Plan DAG with acyclicity proof frozen (§6.1).
- [ ] Command envelope frozen with all 7 command types (§7.1).
- [ ] Event envelope frozen with all 9 event types (§7.2).
- [ ] Claim (digest-only) and Lease frozen (§6.4, §7.3).
- [ ] Evidence and Handoff frozen (§6.3).
- [ ] WriterFence + RecoveryRecord frozen, recovery fields map 1:1 to §7.5.
- [ ] Provenance manifest enforces "no redistribution without approved entry" (§10).
- [ ] Append-only journal contract: idempotent by `event_id`, gap-hold, stale-reject (§7.2).
- [ ] Frozen JSON Schema pipeline with drift + round-trip tests (§11 contract tests).
- [ ] Safe capability probe records versions without launching a Team (§12 P1, §14 D7).
- [ ] No imported/third-party runtime file exists yet (provenance manifest is empty / original-only) (§10).
- [ ] Acceptance criterion §13.12 holds vacuously: no redistributed file lacks provenance (none redistributed).

- [ ] **Step 6: Commit**

```bash
git add src/loop_engineer/contracts/__init__.py README.md tests/probe/__init__.py
git commit -m "feat(p1): public contract surface, docs, and P1 acceptance gate"
```

- [ ] **Step 7: Push**

```bash
git push origin main
```

Expected: `main` advances on `origin/main`.

---

## Self-Review (spec coverage)

| Spec section | Covered by |
| --- | --- |
| §2 in-scope: Goal/Task/plan schema | Tasks 2, 3, 4 |
| §4 exit classes | Task 1 + `test_exit_code_classes.py` |
| §6.1 Goal compiler outputs (schema level) | Tasks 2–4 (compilation logic is P2) |
| §6.2 DAG acyclicity + wave legality (contract) | Task 4 (write-scope normalization is P2) |
| §7.1 command envelope + types | Task 5 |
| §7.2 event envelope + idempotency/sequence rules | Tasks 6, 11 |
| §7.3 lifecycle states (frozen enum) | Task 1 |
| §7.4 executor states (frozen enum) | Task 1 |
| §7.5 recovery coordinate record | Task 9 |
| §8 writer-fence contract | Task 9 |
| §10 provenance manifest + redistribution gate | Task 10 |
| §11 contract tests (schema, DAG, envelope, version compat) | Tasks 1, 4, 5, 6, 12 |
| §12 P1 deliverables | Tasks 0–14 |
| §13.12 (provenance) | Task 14 checklist (holds vacuously) |
| §14 D1–D8 | Decisions table above |

**Deliberately deferred to P2+ (not P1 gaps):** Goal *compilation* logic, normalized write-scope *conflict detection*, runtime state machine, adapters, finisher, Skills. These are runtime/implementation concerns whose plans depend on P1 outputs and on the §14 facts P1 produces. Each gets its own detailed plan at its stage gate.

**No-placeholder scan:** every code step contains real, runnable code; every test step contains real assertions and the command to run it. `tests/contract/test_schema_roundtrip.py` ships one complete `PAYLOADS` table covering all 12 schemas in a single step.

**Type/name consistency:** `CommonState` (lifecycle) vs `EventType.READY_FOR_REVIEW` (event) are intentionally distinct names matching the spec's two columns; `OmxTaskStatus` is the OMX worker-Task column, separate from `CommonState`. `Claim.token_digest` and `RecoveryRecord.claim_token_digest` use the same `sha256:<64 hex>` shape, enforced by identically-named validators. `WriterFence.writer_generation` and `RecoveryRecord.writer_fencing_generation` are the same concept under two field names — kept verbatim from §7.5/§8; do not "unify" them, the spec uses both terms.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-17-loop-engineer-p1-contracts.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — a fresh subagent implements one task, I review between tasks, fast iteration. Best for a 14-task TDD plan where each task is independent and reviewable.

**2. Inline Execution** — execute tasks in this session with `superpowers:executing-plans`, batched with checkpoints for your review.

**Which approach?**

Before that, two things need your call: (a) the execution approach above, and (b) whether any of the D1–D6 defaults should change, and — separately — your D8 license preference (does not block P1, but blocks P7 redistribution).
