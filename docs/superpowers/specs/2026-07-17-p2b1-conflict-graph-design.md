# Loop Engineer — P2b-1 Conflict Graph + Planner Design

Date: 2026-07-17
Status: Approved (P2b sub-stage 1)
Parent: [2026-07-17-loop-engineer-design.md](2026-07-17-loop-engineer-design.md); scheduler source-of-truth: operator Hybrid Scheduler prompt (§5/§6/§7/§8).

## 1. Purpose and scope

P2b-1 is the **pure-logic scheduling brain** — no subprocess, no real `omx`/`omc`. Given a Plan, the board state, per-task execution metadata, a capacity config, and protected paths, it computes: which Tasks are eligible, the pairwise conflict graph with reasons, an engine recommendation per Task, and a capacity-respecting launch plan.

This is the "治本" replacement for the parts of the operator prompt that must be deterministic (§5 eligibility, §6 conflict graph, §7 engine routing, §8 capacity). The rolling loop (§10), adapter launch (§9), finisher (§11), and recovery (§2/§13) are P2b-2..5 and consume this planner's output.

**In scope:** eligibility, six conflict dimensions, engine-routing heuristic, capacity/balance, launch-plan output — all as tested pure Python over P2a's `Plan`/`BoardStore` + a new `TaskExecutionMeta`.

**Out of scope (P2b-2..5):** launching real adapter scripts, the rolling driver loop, finisher/integration, lease-expiry/force-release recovery, OS resource probing.

## 2. New input contracts (additive; P1/P2a frozen surface untouched)

- `TaskExecutionMeta` — optional per-Task metadata for the conflict dimensions P2a's `Task` doesn't carry:
  - `migration_dir: str | None` (e.g. `migrations/versions`)
  - `migration_after: list[str]` (task_ids whose migration must merge first — same `migration_head`)
  - `ports: list[int]`, `db_name: str | None`, `browser_profile: str | None`
  - `engine_hint: Provider | None`
- `CapacityConfig` — `omx_max`, `omc_max`, `global_max`, `finish_max`, `burst_max` (ints). Defaults from operator prompt §8: `OMX_MAX=3, OMC_MAX=3, GLOBAL_MAX=3, FINISH_MAX=1, BURST_MAX=4`. **`global_max` is the combined cap, not omx+omc.**
- `PlannerConfig` — wraps `CapacityConfig` + `protected_paths: list[str]` (default `["refer/"]`) + `target_omc: int = 2`, `target_omx: int = 1` (balance target).

`TaskExecutionMeta` is carried in `GoalDefinition.execution_meta: dict[str, TaskExecutionMeta]` (default empty) — additive, does not modify P2a's `Task`. The compiler passes it through opaquely; the planner consumes it.

## 3. Eligibility (operator §5)

`eligible_tasks(plan, board, meta) -> dict[task_id, EligibilityReason]` returns Tasks that satisfy ALL of:

1. Not `DONE` on the board (done is defined on `main`, i.e. board status `DONE`).
2. **derived-ready**: every dependency has board status `DONE` (a dependency done only on a task branch, not merged, does NOT count — operator §5).
3. Not currently `CLAIMED`.
4. No `TaskExecutionMeta`-level hard block (e.g. `engine_hint` for an unavailable adapter is a P2b-2 concern; P2b-1 treats adapter availability as assumed-true).

Recovery (§5.4) and OS resources (§5.6) are deferred to P2b-5; P2b-1 vacuously assumes no unresolved recovery and resources-OK, and emits a note where it would check.

## 4. Conflict graph (operator §6)

`conflicts(plan, board, meta, protected_paths) -> dict[task_id, list[Conflict]]` — for each **candidate** (eligible, unclaimed) Task vs each **active** (`CLAIMED`) Task, plus task-level blocks. A `Conflict` carries `{candidate, other, dimension, reason}`. Dimensions:

- **A. Dependency** — candidate depends on the active Task, or active depends on candidate (cannot run concurrently).
- **B. Allowed Files** — `runtime.scope.overlaps(candidate_files, active_files)` AND not dependency-ordered (reuses P2a; operator §6.B's public-contract/shared-file intent is approximated by exact file match + directory containment).
- **C. Migration** — same `migration_dir`; OR both `migration_after` the same unfinished task; OR both would create the next revision in one dir (operator §6.C). Migration Tasks serialize per dir; the next may start only after the previous merges to `main` and the head is re-read.
- **D. Resource** — overlapping `ports`, same `db_name` (exclusive), same `browser_profile`.
- **E. Lifecycle** — same task_id/branch/worktree (defensive; normally precluded by claim).
- **F. Protected zone** — candidate's `allowed_files` intersects `protected_paths` (e.g. `refer/`). This is a **task-level hard block** (not pairwise): such a Task is `BLOCKED`, never eligible, regardless of active set.

A Task with any A–E conflict against an active Task is not launchable **now** (skipped, reason recorded). F makes it never launchable.

## 5. Engine routing (operator §7)

`recommend_engine(task, meta) -> Provider` — heuristic, overridable by `engine_hint`. Defaults:

- OMC: `allowed_files` under `frontend/`, UI/page/component/style, browser/Playwright, docs/protocol, no migration.
- OMX: `backend/`, `actuator/`, execution/durable state, PostgreSQL/migration, cross-backend integration.

Routing priority (operator §7) is honored: dependencies and conflict graph outrank engine preference; an existing claim's engine is kept on recovery (P2b-5). P2b-1 only computes the **recommendation**; the launch plan respects it subject to capacity and the no-engine-switch-on-reclaim rule (vacuous here since P2b-1 doesn't reclaim).

## 6. Capacity + launch plan (operator §8)

`plan_launch(plan, board, meta, config) -> LaunchPlan`:

1. Count active by provider from the board (`CLAIMED`, still-writing).
2. `remaining_global = global_max - active_total`; `remaining_omx = omx_max - active_omx`; `remaining_omc = omc_max - active_omc`.
3. From eligible + non-conflicting candidates, select up to `remaining_global`, respecting per-engine caps and the balance target (`target_omc=2, target_omx=1`), choosing by operator §10 tie-breaks (unblocks most downstream; migration precursor; long-running first).
4. Burst to `burst_max` only if all operator §8 burst conditions hold (no finisher, main clean, no recovery, fully conflict-free 4th, no exclusive db/browser). P2b-1 models the **logic**; main-cleanliness/finisher state are inputs the caller (P2b-3) provides.

`LaunchPlan = {launch: list[(task_id, Provider)], skipped: list[(task_id, reason)], blocked: list[(task_id, reason)], capacity: {active_omx, active_omc, active_total, remaining_global, burst}}`.

## 7. Testing

Pure-logic, fake board states under `tmp_path`. One test per conflict dimension (A–F), eligibility (derived-ready vs branch-only-done), engine routing (frontend→OMC, backend/migration→OMX, hint override), capacity (global cap vs omx+omc; balance; burst conditions; burst denied when conflict), and a combined end-to-end `plan_launch` over a small DAG with mixed conflicts. No subprocess, no real teams.

## 8. Acceptance for P2b-1

1. Every §6 dimension has a passing test with a concrete conflict + a non-conflicting control.
2. Protected-zone (`refer/`) Tasks are `BLOCKED`, never in `launch`.
3. `global_max` is enforced as the combined cap (launch count never exceeds it), distinct from per-engine caps.
4. Burst is granted only under all §8 conditions and denied on any conflict/overlap.
5. Derived-ready uses `main`/board `DONE` only; a dependency done on a task branch does not unlock downstream.
6. Engine routing respects `engine_hint` and the frontend/backend/migration defaults.
7. New contracts (`task_execution_meta`) frozen in `schemas/v1/`; P1+P2a tests unchanged.

## 9. Boundary with P2b-2..5

P2b-1 produces a `LaunchPlan`; it launches nothing. P2b-2 (adapter shims) turns each `(task_id, Provider)` into a real `start-omx-task`/`start-omc-task` call + status read. P2b-3 (rolling loop) calls P2b-1 each tick, dispatches via P2b-2, and feeds main-cleanliness/finisher state into the burst check. P2b-4 (finisher) consumes `DONE` candidates. P2b-5 (recovery) supplies the "no unresolved recovery" input P2b-1 currently assumes.
