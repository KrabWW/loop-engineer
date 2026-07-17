---
name: goal-to-omc-team
description: Use when an evidence-backed goal and atomic Task DAG must become a safe OMC (Claude-worker) team lifecycle — start, status, finish, and batch Tasks through the omc CLI without hand-composing shutdown, rebase, or merge.
---

# Goal to OMC Team

## Overview

Drive the locally installed OMC `omc` CLI to execute repository Tasks as Claude-worker teams. The skill and its bundled tools pass fake OMC/Claude/tmux/Git tests without ever launching a real Team during verification; the operator surfaces (`start`, `status`, `finish`, `batch`) drive the real `omc` when run for production.

A detached `omc team` shell is not a persistent leader. OMC has no `omc exec`; the leader is a persistent `omc launch --madmax --notify false` process whose pane liveness is process liveness. OMC has no `team await`; progress is polled through `omc team api get-summary`.

## Runtime authority

Target the OMC `omc` CLI (not the Claude native `/team` skill and not OMX). Authoritative OMC facts:

- Persistent leader: `omc launch --madmax --notify false "<leader-prompt>"` (no `omc exec`).
- One atomic worker per Task: `omc team 1:claude:executor --auto-merge --no-decompose "<atomic-task>"`. `--no-decompose` assigns the same task text to every requested worker, so v1 always uses exactly one worker; parallelism is across independent Tasks in batch waves.
- Runtime env on the leader and every child call: `OMC_RUNTIME_V2=1 OMC_STATE_DIR=<task-state-base> OMC_TEAM_WORKTREE_MODE=branch`. Auto-merge requires the leader branch to be neither `main` nor `master`.
- Progress: `omc team api get-summary`, `read-worker-status`, and `read-worker-heartbeat` (each `--input '<json>' --json`). There is no `team await`; poll on an interval.

## Workflow

1. **Establish authority.** Read repository rules, architecture, tasks, contracts, and checks. Keep references read-only and preserve `refer/`.

2. **Freeze the goal.** Define outcome, evidence, scope, exclusions, and one direction-changing stop condition.

3. **Define stages.** Derive G0-Gn from dependencies. G0 freezes shared semantics; every G has a binary exit. A G is a milestone, never an OMC execution unit.

4. **Build the atomic DAG.** Each one-domain Task needs an ID, owner, dependencies, exact `Allowed Files`, non-goals, acceptance, and authoritative `Verification Commands`. Prove acyclicity and mark only unblocked Tasks `ready`.

5. **Package OMC execution.** Freeze `one Task -> one integration branch (codex/omc-qs-<slug>) -> one integration worktree -> one persistent Claude leader -> one OMC team`. Capture the exact tmux leader pane. Team state is centralized under a Task-isolated base (`<git-common-dir>/omc-task-state/<slug>`, passed as `OMC_STATE_DIR`); the leader and all lifecycle calls bind the same runtime env.

6. **Generate artifacts.** Follow [the contract](references/deliverable-contract.md): graph, Tasks, guide, launcher, status, resumable finisher, batch runner, installer, and fakes. The leader invokes exactly one `omc team 1:claude:executor --auto-merge --no-decompose` with one atomic sentence.

7. **Verify.** Check IDs, DAG, commands, shell syntax, leader pane, fakes, links, whitespace, and protected paths. The finisher requires `phase=complete`, idle + fresh worker evidence, and the content-stable `refer/` baseline; it verifies before shutdown, after `--rebase-merges`, and after ff-only merge. Fakes cover stale pane replacement, true death, ambiguous candidates, and stale-heartbeat rejection. Do not launch a real Team during verification.

8. **Hand off waves.** Report counts, blockers, serialization, commands, and queue. Close a stage only when its Tasks are `done`.

## Bundled lifecycle tools

Run `scripts/install-omc-task-lifecycle <REPOSITORY>` to install start, status, finish, batch, examples, and fake tests into repository-native paths. The installer is idempotent for identical content, refuses differing targets unless `--force`, preserves executable modes, and runs shell syntax checks.

```sh
./scripts/start-omc-task <TASK_ID>                      # launch one Task team
./scripts/status-omc-task <TASK_ID>                     # read-only team inspection
./scripts/finish-omc-task <TASK_ID>                     # verify, shutdown, rebase, ff-only merge, clean
./scripts/run-omc-task-batch --mode custom <PLAN_FILE>  # serial/parallel/custom waves
```

Batch waves may run Teams in parallel but serialize shutdown, rebase, merge, and `main` integration. Never duplicate finisher internals in the batch runner.

## Direction-changing stop conditions

Ask one question when evidence cannot determine execution semantics, durable ownership, or a DAG-changing choice. Do not stop for adapter-neutral choices or invent capability.

## Red flags

- Task lacks exact `Allowed Files` or executable validation.
- Cross-domain direct database writes.
- Cyclic dependencies or parallel migrations sharing one head.
- Secrets in prompts, logs, browser storage, or ordinary fields.
- A real Team starts during graph/launcher generation.
- Startup reports success without a ready Team and the captured leader pane at `pane_dead=0`.
- Finishing asks for a random Team name, scans outside the Task state base, uses plain rebase, omits any of the three verification runs, or trusts a stale worker heartbeat.
- Batch runs finisher/main integration in parallel or crosses a custom wave barrier.
- Lifecycle calls omit `OMC_RUNTIME_V2=1`, `OMC_STATE_DIR=<base>`, or `OMC_TEAM_WORKTREE_MODE=branch`.

Any red flag blocks handoff until repaired.
