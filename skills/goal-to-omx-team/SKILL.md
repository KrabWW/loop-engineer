---
name: goal-to-omx-team
description: Use when evidence must become staged goals, tasks, and OMX lifecycle entrypoints.
---

# Goal to OMX Team

## Overview

Produce verified lifecycle artifacts, not product code.

**REQUIRED SUB-SKILLS:** Use define-goal for the objective. Use team for OMX lifecycle and worker-worktree semantics.

## Workflow

1. **Establish authority.** Read repository authority and checks. Keep references read-only and preserve `refer/`.

2. **Freeze the goal.** Apply `define-goal`: outcome, evidence, scope, exclusions, and one direction-changing stop condition.

3. **Define stages.** Derive G0-Gn from dependencies. G0 freezes shared semantics; every G has a binary exit. **G is a milestone, never an OMX execution unit.**

4. **Build the atomic DAG.** Each one-domain Task needs an ID, owner, dependencies, exact `Allowed Files`, non-goals, acceptance, and commands. Freeze three-domain semantics first; prove acyclicity and mark only unblocked Tasks `ready`.

5. **Package OMX execution.** Freeze `one Task -> one integration branch -> one integration worktree -> one persistent Codex leader -> one OMX team`. Recover stale panes only from a unique live session-and-worktree match. If a healthy `complete` Team has none, create one exact-worktree terminal recovery pane for the finisher; active Teams fail closed. OMX worker worktrees remain internal.

6. **Generate artifacts.** Follow [the contract](references/deliverable-contract.md): graph, Tasks, guide, launcher, resumable finisher, batch runner, installer, and fakes. Never use temporary shell helpers. The leader binds `OMX_ROOT`, disables updates, and invokes `omx team N:executor` with one atomic sentence.

7. **Verify.** Check IDs, DAG, shell syntax, leader pane, links, and protected paths. The batch runner waits for `phase=complete` plus one canonical full-SHA final-evidence file before invoking the finisher. The finisher keeps Task-branch `refer/` changes forbidden while treating concurrent main-worktree reference drift as an audit warning; it verifies before shutdown, after `--rebase-merges`, and after ff-only merge. Fakes cover delayed final evidence, stale replacement, terminal recreation, active death, and ambiguity. Do not launch a real team.

8. **Hand off waves.** Report counts, blockers, serialization, commands, and queue. Close a stage only when its Tasks are `done`.

## Bundled Lifecycle Tools

Run `scripts/install-omx-task-lifecycle <REPOSITORY>` to install lifecycle tools and fakes. Batch waves overlap Teams, serialize main, resume active Tasks, and skip cleaned completions. `scripts/run-omx-task-queue` delegates to `scripts/finish-omx-task`.

## Direction-Changing Stop Conditions

Ask one question when evidence cannot determine execution semantics, durable ownership, or a DAG-changing choice. Do not stop for adapter-neutral choices or invent capability.

## Red Flags

- Task lacks exact files or executable validation.
- Cross-domain direct database writes.
- Cyclic dependencies or parallel migrations sharing one head.
- Secrets in prompts, logs, browser storage, or ordinary fields.
- A real Team starts during graph/launcher generation.
- Startup reports success without a ready Team and the captured leader pane at `pane_dead=0`.
- Finishing asks for a random Team name, scans outside the Task worktree, uses plain rebase, or skips any of the three verification runs.
- Batch runs finisher/main integration in parallel or crosses a custom wave barrier.
- A queue duplicates shutdown/merge logic or advances before the finisher reports `mode=finished`.

Any red flag blocks handoff until repaired.
