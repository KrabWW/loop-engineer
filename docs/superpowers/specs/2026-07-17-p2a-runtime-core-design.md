# Loop Engineer — P2a Runtime Core & Parallel Claim Design

Date: 2026-07-17
Status: Approved (P2a scoping)
Parent spec: [2026-07-17-loop-engineer-design.md](2026-07-17-loop-engineer-design.md)

## 1. Purpose and scope

P2a is the first half of stage P2. It turns loop-engineer from a schema-only repo (P1) into a tool that can **compile a goal into a Task DAG** and **let OMC and OMX workers claim Tasks in parallel** through a provider-neutral coordination layer.

**In scope (P2a):**

- Goal compiler: a goal file (YAML/JSON) → milestones + atomic Task DAG → a validated `Plan` (reuses P1 `Goal`/`Task`/`Plan`, including construction-time acyclicity).
- Plan CLI: `loop-engineer goal define|validate <file>`, `loop-engineer plan build|validate|show <file>`.
- Runtime core task board: persisted, provider-neutral per-Task status + claims, stored in the Git common directory outside ordinary commits (`.git/loop-engineer/<run-id>/board.json`).
- Atomic cross-process claim/release with leases. OMX processes and OMC processes are independent OS processes; mutual exclusion is by file lock (`fcntl.flock`) around a read-modify-write of the board.
- Write-scope conflict detection (parent spec §6.2, acceptance §13.8): normalized `Allowed Files` containment; a Task whose files overlap an already-active Task is rejected at claim time unless the two are ordered by a dependency path.
- Task CLI: `loop-engineer task list|claim|release|status` (`claim --provider omx|omc`), callable concurrently by external processes.
- Fake-runtime tests throughout; no real `omx`/`omc` Team launch.

**Out of scope (deferred to P2b and later):**

- Driving real `omx`/`omc` to execute the work of a claimed Task (the execution adapters).
- The finisher, serialized `main` integration, rebase, and post-merge verification.
- `loop-engineer run omx`, `run hybrid`, `status --watch`, `resume`, `stop`, `doctor`, `install-skills`.
- Hybrid OMC executor adapter, writer-fencing, recovery replay.

P2a delivers the **coordination backbone**: after P2a, two processes can concurrently claim non-overlapping Tasks and are correctly refused on overlap. P2b makes claimed Tasks actually execute.

## 2. The parallel-claim requirement

Operator requirement: **OMC and OMX must be able to claim Tasks in parallel, now.** This shapes P2a's priority. The task board and claim operation are provider-neutral; `Provider` (`omx` | `omc`) is recorded on each claim but does not gate who may claim. Parallelism is bounded only by write-scope (parent §3.8, §13.8), not by provider. This is why P2a builds the runtime core (parent §6.2) before either provider's execution adapter.

## 3. Architecture

```text
goal file (YAML/JSON)
    |
    v
Goal compiler ──► Goal + milestones + atomic Task DAG ──► Plan (P1, acyclic)
    |                                                        |
    v                                                        v
plan CLI (build/validate/show)                    runtime core: task board
                                                          |
                            claim/release (file-locked, atomic, leased)
                                                          |
              ┌───────────────────┴───────────────────┐
              v                                       v
        OMX worker process                       OMC worker process
       (loop-engineer task claim                 (loop-engineer task claim
        --provider omx)                           --provider omc)
```

The compiler and board are pure-Python and provider-neutral. The board is the single source of truth for which Task is held by whom; execution (P2b) reads the claim and drives the provider CLI.

## 4. New contracts (additive; P1 frozen surface untouched)

All new models are added under `src/loop_engineer/contracts/` and registered in the schema freeze pipeline (`scripts/export_schemas.py` `MODELS`). They are new files at schema `v1`; no existing v1 schema changes.

- `Provider(StrEnum)`: `OMX = "omx"`, `OMC = "omc"`.
- `TaskRunStatus(StrEnum)`: `PENDING`, `CLAIMED`, `RELEASED`, `DONE`, `FAILED` (board-level status; distinct from the §7.3 `CommonState` lifecycle and from `OmxTaskStatus`).
- `TaskBoardEntry`: `task_id`, `status: TaskRunStatus`, `claim: Claim | None` (P1), `lease: Lease | None` (P1), `provider: Provider | None`, `attempt_id: int >= 1`.
- `GoalDefinition`: the input file contract — `goal: Goal` fields plus `tasks: list[Task]` (each Task carrying dependencies, `allowed_files`, `verification`, etc.). The compiler builds a `Plan` from this.

The claim operation returns a P1 `Claim` (digest-only; raw token stays in permission-restricted runtime state). `expected_prior_status` on claim/release makes the operation idempotent and fail-closed (parent §6 principle 6).

## 5. Runtime core

### 5.1 Task board store

- Path: `<git-common-dir>/loop-engineer/<run-id>/board.json`, where `<git-common-dir>` is resolved via `git rev-parse --git-common-dir`. Outside ordinary commits (parent §7.5).
- Layout: `{ run_id, plan_digest, tasks: { task_id: TaskBoardEntry } }`.
- Atomic write: serialize to `board.json.tmp` in the same dir, `os.replace` over the real file. `os.replace` is atomic on the same filesystem.
- Concurrency: every mutating operation acquires an exclusive `fcntl.flock` on a sibling `board.lock` file for the whole read-modify-write. This makes concurrent OMX/OMC claims safe across processes.

### 5.2 Claim operation

`claim(task_id, provider, lease, expected_prior_status=PENDING) -> Claim`:

1. Acquire board lock.
2. Read board. Confirm task exists and `status == expected_prior_status` (else exit `3`, parent §4).
3. Write-scope check (§5.3). Reject overlap with any `CLAIMED` task (exit `5`).
4. Mint a claim token (secrets-grade random); store only its sha256 digest on the board (`Claim.token_digest`); record `provider`, `lease`, set `status=CLAIMED`.
5. Atomic write + release lock.
6. Return the raw `Claim` (with token) to the caller once; the caller must keep it to release/transition.

`release(task_id, claim_token, expected_prior_status=CLAIMED)` validates the token digest, resets status to `PENDING` or `FAILED`, clears claim/lease/provider. `complete(task_id, claim_token)` → `DONE`.

### 5.3 Write-scope conflict detection

Normalize each `allowed_files` entry to a POSIX path relative to the repo root (resolve `.`, `..`, repeated slashes; reject absolute paths and any path escaping the repo root, exit `2`). Two file sets overlap when either contains the other's path as a prefix (directory containment) or exact file match. A claim is rejected (exit `5`) if the candidate Task overlaps any currently `CLAIMED` Task, **unless** the candidate is a dependency descendant of the held Task (ordered overlap is legal, parent §6.2 last paragraph). This satisfies acceptance §13.8.

## 6. CLI

`argparse` subparsers (stdlib; no new dependency). Exit classes map to P1 `ExitCode`.

- `loop-engineer goal define` / `goal validate <file>` — parse + validate a `GoalDefinition`.
- `loop-engineer plan build <goal-file> -o <plan-file>` — compile to a `Plan`; write JSON. `plan validate <plan-file>` / `plan show <plan-file>`.
- `loop-engineer task list [--run <run-id>]` — board summary.
- `loop-engineer task claim <task-id> --provider omx|omc [--run <run-id>]` — prints the claim token (once) and exit `0`; exit `5` on overlap; exit `3` on wrong prior state.
- `loop-engineer task release <task-id> --token <token>` / `task status <task-id>`.

The `loop-engineer.cli:main` entry point from P1's `pyproject.toml` is implemented here.

## 7. Key decisions

- **File-locked JSON board** over SQLite: no new dependency, sufficient for low-contention cross-process claims, transparent on-disk format. SQLite remains a P2+ option behind the `BoardStore` interface if contention grows.
- **`Provider` as a new enum**, not a field on the frozen `Claim`; the board entry carries provider separately.
- **argparse** over click/typer: stdlib, zero new deps, adequate for this subcommand surface.
- **Board status (`TaskRunStatus`)** is deliberately separate from the §7.3 `CommonState` Hybrid lifecycle: P2a only coordinates claiming, not Hybrid-phase transitions.
- **Goal file is YAML or JSON** (try YAML if PyYAML is available, else JSON). PyYAML is added as an optional dependency so JSON-only operation needs no new dep.

## 8. Testing

- Contract/unit: compiler (goal → Plan, acyclic, rejects bad input), write-scope normalization + overlap (containment, escaping-path rejection, dependency-ordered overlap allowed), board entry/claim/lease validation.
- Runtime (fake, no real subprocess): in-process board claim/release/complete; idempotency via `expected_prior_status`; stale/wrong-token release rejected (exit `3`).
- **Concurrency**: spawn two real child processes (or two threads each holding the lock briefly) that claim different Tasks concurrently → both succeed; claim two overlapping Tasks concurrently → exactly one succeeds, the other exits `5`. This is the direct test of the parallel-claim requirement.
- CLI smoke via `subprocess`/`CliRunner`-style argv against fake board dirs under `tmp_path`.

## 9. Acceptance for P2a

1. A goal file compiles to a validated `Plan`; `plan validate` rejects cyclic / malformed input with exit `2`. Unordered `Allowed Files` overlap is rejected at **claim time** (exit `5`, §5.2) in P2a; compile/scheduler-time overlap detection (parent §13.8, exit `2`) is deferred to P2b when the full scheduler + conflict graph land.
2. `task claim --provider omx` and `--provider omc` both succeed on independent Tasks; the board records the provider and a digest-only claim.
3. Two processes claiming overlapping Tasks concurrently: exactly one wins, the other exits `5`; the board never holds two overlapping active Tasks.
4. Claim/release/complete are idempotent and fail-closed on wrong prior state / wrong token (exit `3`).
5. No real `omx`/`omc` Team is launched by any P2a test.
6. New contracts are frozen in `schemas/v1/` with passing drift + round-trip tests; P1's 118 tests still pass unchanged.

## 10. Open decisions for the implementation plan

- Exact `run-id` derivation (e.g., plan digest short hash) and board discovery when `--run` is omitted.
- Whether `release` defaults to `PENDING` (re-claimable) or `FAILED`, and the retry/`attempt_id` increment rule (parent §7.3 retry transaction is the reference, but full retry lands in P2b).
