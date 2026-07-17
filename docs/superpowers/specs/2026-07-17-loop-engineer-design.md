# Loop Engineer Design

Date: 2026-07-17
Status: Draft for review

## 1. Purpose

Loop Engineer is a CLI-first personal engineering arsenal that converts a measurable Goal into an atomic Task DAG and executes that DAG through recoverable multi-agent loops.

It must expose two visibly different execution lanes while sharing the same Goal, Task, evidence, verification, recovery, and integration contracts:

1. Pure OMX: a persistent Codex leader directs an OMX Team and owns review, verification, and integration.
2. Hybrid: a persistent Codex/OMX leader directs an OMX Team whose executor adapter controls a long-running OMC Team and reports through the OMX mailbox protocol in real time.

The system is not a generic autonomous-agent framework. Version 1 is a Git-worktree-based engineering lifecycle for repositories whose Tasks define exact write scope and executable verification.

## 2. Product Boundaries

### In scope

- Goal definition with measurable evidence, scope, exclusions, and stop conditions.
- Goal compilation into staged milestones and an acyclic atomic Task DAG.
- Exact `Allowed Files`, dependencies, acceptance criteria, and verification commands per Task.
- Pure OMX execution.
- OMX-led, real-time OMC executor-adapter execution.
- Persistent tmux leaders, Git worktree isolation, event journals, resume, and fail-closed recovery.
- OMX-owned final review, approval, verification, and serialized `main` integration.
- Fake runtime tests for Git, tmux, OMX, OMC, Codex, and Claude processes.
- Installable Codex and Claude Skills that call deterministic CLI surfaces.

### Out of scope for version 1

- A hosted control plane or multi-user service.
- Arbitrary workflow graphs unrelated to engineering Tasks.
- Direct production deployment.
- OMC approval of repository completion or direct OMC integration into `main`.
- Simultaneous OMX and OMC writes to the same Task worktree.
- Secrets embedded in Task documents, prompts, events, or logs.
- Automatic licensing assumptions for locally installed or third-party scripts.

## 3. Design Principles

1. The CLI and state machine are authoritative; Skills teach agents when and how to call them.
2. A Goal is compiled before execution. Milestones are release gates, never Team execution units.
3. One atomic Task owns one integration branch, one integration worktree, one persistent leader, and one execution lifecycle.
4. Task documents are runtime authority for dependencies, `Allowed Files`, acceptance, and verification.
5. State-first communication is authoritative. tmux keystrokes may wake a process but never carry canonical state.
6. Every mutating operation is idempotent or guarded by an explicit lease and expected prior state.
7. Active or ambiguous ownership fails closed. Recovery never guesses a leader, Team, worktree, or commit.
8. Team execution may overlap across independent Tasks. Shutdown, rebase, merge, and `main` integration are serialized.
9. OMC is Claude-owned execution; OMX is Codex-owned control, review, approval, and integration.
10. Runtime imports require provenance and license review before publication.

## 4. Operator Interface

### Goal and plan

```bash
loop-engineer goal define
loop-engineer goal validate <goal-file>
loop-engineer plan build <goal-file>
loop-engineer plan validate <plan-file>
loop-engineer plan show <plan-file>
```

### Pure OMX lane

```bash
loop-engineer run omx --plan <plan-file>
./scripts/run-omx-task-batch --mode custom <plan-file>
```

The pure lane must never start OMC or silently select Claude workers.

### Hybrid lane

```bash
loop-engineer run hybrid --plan <plan-file>
./scripts/run-omx-omc-task-batch --mode custom <plan-file>
```

The hybrid lane must require the OMC adapter contract and must not degrade silently into a plain Claude CLI worker.

### Lifecycle operations

```bash
loop-engineer status [--watch]
loop-engineer resume [--plan <plan-file>]
loop-engineer stop [--task <task-id>]
loop-engineer task inspect <task-id>
loop-engineer task logs <task-id>
loop-engineer task retry <task-id>
loop-engineer doctor
loop-engineer install-skills --codex|--claude|--all
```

## 5. Architecture

```text
Goal source
    |
    v
Goal compiler -> milestones + atomic Task DAG + execution plan
    |
    v
Durable scheduler and journal
    |-------------------------------|
    v                               v
Pure OMX lane                    Hybrid lane
Codex leader                     Codex/OMX leader
    |                               |
OMX Team                            | OMX mailbox and task protocol
    |                               v
Codex workers                    OMC executor adapter
    |                               |
    |                               v
    |                            Claude leader
    |                               |
    |                            OMC Team
    |                               |
    |                            Claude workers
    |                               |
    |<------- evidence/events -------|
    v
OMX review -> fix -> verify -> serialized finisher -> main
```

The scheduler is deterministic orchestration code and should not consume model tokens. Model processes execute bounded Tasks and make review decisions inside declared authority.

## 6. Core Components

### 6.1 Goal compiler

Produces a measurable Goal and staged milestones. Each milestone has a binary exit. It then emits atomic Task documents and proves that the dependency graph is acyclic.

Every Task contains:

- Task ID and owner domain.
- Status and dependencies.
- Exact `Allowed Files`.
- Non-goals.
- Acceptance criteria.
- Exact verification commands and working directory.
- Required evidence.
- Integration and downstream handoff constraints.

### 6.2 Runtime core

Owns:

- Plan parsing and wave barriers.
- Task state machine.
- Deterministic names for branch, worktree, tmux session, and journals.
- Process leases and heartbeats.
- Durable event append and replay.
- Resume and cleanup decisions.
- Serialized finisher locking.

The runtime core does not import OMX- or OMC-specific state directly. Runtime adapters translate provider state into common events.

### 6.3 Pure OMX runtime adapter

Starts a detached Task integration worktree and persistent Codex leader. The leader launches exactly one OMX Team for the atomic Task, assigns non-overlapping work, integrates worker results, reviews the integrated HEAD, and produces evidence.

The finisher requires a healthy terminal Team, a live or legally recovered leader, committed evidence, clean scope, Task status `done`, an unchanged protected reference fingerprint, and three verification runs: before shutdown, after rebase, and after fast-forward integration.

### 6.4 OMC executor adapter

The OMC executor adapter participates as a real OMX worker while owning a persistent Claude leader and OMC Team.

It must:

1. Parse its OMX worker identity and send startup ACK to `leader-fixed`.
2. Read assigned OMX Tasks from canonical Team state.
3. Claim the Task through the OMX claim-safe API.
4. Start or resume exactly one Task-bound Claude leader and OMC Team.
5. Translate the bounded OMX assignment into OMC Task state without widening file scope.
6. Poll OMC summary, status, heartbeat, commits, tests, and evidence.
7. Emit normalized progress events and concise mailbox messages to the OMX leader.
8. Accept follow-up instructions from the same OMX Team lifecycle and route them to the active OMC Team.
9. Transition the OMX Task only with the claim token and expected prior state.
10. Preserve recovery coordinates on ambiguity or process failure.

The adapter is not the final approver. An OMC `complete` result becomes `READY_FOR_REVIEW`, not repository completion. The OMX leader may approve, request another correction round, perform direct OMX fixes, or fail the Task.

### 6.5 Finisher

The OMX-side finisher is the only component allowed to integrate into `main`. It validates ownership and evidence, shuts down active runtimes, rebases with merge topology preserved, reruns authoritative verification, fast-forwards `main`, verifies merged `main`, and removes exact lifecycle resources.

## 7. Hybrid Protocol

### 7.1 Command envelope

Each leader-to-adapter command includes:

- Protocol version.
- Run ID, Task ID, OMX Team name, and worker identity.
- Message ID and causation ID.
- Expected Task state and current claim/lease generation.
- Command type.
- Atomic instruction.
- Allowed file scope hash.
- Evidence and verification requirements.
- Deadline or cancellation policy when applicable.

Command types in version 1:

- `START_TASK`
- `CONTINUE_TASK`
- `REQUEST_FIX`
- `REQUEST_EVIDENCE`
- `CANCEL_TASK`
- `SHUTDOWN_EXECUTOR`

### 7.2 Event envelope

Adapter-to-leader events include the same correlation identity and one of:

- `ACKNOWLEDGED`
- `STARTED`
- `PROGRESS`
- `HEARTBEAT`
- `BLOCKED`
- `READY_FOR_REVIEW`
- `FAILED`
- `CANCELLED`
- `SHUTDOWN_ACK`

Events are append-only and idempotent by message ID. A summarized mailbox notification points at durable evidence rather than embedding large logs.

### 7.3 State machine

```text
ready
  -> claimed
  -> omc_starting
  -> omc_executing
  -> ready_for_omx_review
  -> omx_reviewing
  -> correction_requested -> omc_executing
  -> omx_fixing
  -> omx_verified
  -> finishing
  -> merged
```

Terminal alternatives are `failed` and `cancelled`. `blocked` is a reviewable hold, not implicit failure.

### 7.4 Recovery rules

- Replaying a command with the same message ID must not start a second OMC Team.
- A live lease prevents a second adapter from claiming the same OMX Task.
- A stale lease is recoverable only when exact Task, worktree, Team, and process evidence identify one owner.
- Zero or multiple candidates fail closed.
- OMC completion without a commit/evidence match cannot become `READY_FOR_REVIEW`.
- An adapter restart replays the event journal before reading new mailbox commands.
- A leader restart reconstructs active Tasks from Team state and adapter heartbeats.
- Main integration is protected by a repository-wide finisher lock.

## 8. Isolation and Git Model

Pure OMX and Hybrid Tasks both use a Task integration branch and worktree. In Hybrid mode, the OMC Team works only inside the adapter-owned execution worktree or its provider-created worker worktrees. OMC auto-merge targets the adapter execution branch, never `main`.

For a single Task, OMC writing must stop before OMX performs direct repair in the same integration surface. Across independent Tasks, OMC execution and OMX review may overlap when their exact write scopes do not conflict. Shared migrations and protocol predecessors remain serialized by the DAG.

## 9. Repository Layout

```text
loop-engineer/
├── src/loop_engineer/
│   ├── cli/
│   ├── contracts/
│   ├── runtime/core/
│   ├── runtime/omx/
│   ├── runtime/omc/
│   ├── runtime/hybrid/
│   ├── adapters/omc_executor/
│   └── state/
├── skills/
│   ├── define-goal/
│   ├── goal-to-omx-team/
│   └── goal-to-omx-omc-team/
├── scripts/
├── schemas/
├── tests/unit/
├── tests/contract/
├── tests/fake-runtime/
├── tests/recovery/
└── docs/
```

Python is the preferred CLI and protocol implementation language. Existing shell lifecycle scripts remain narrow process/Git/tmux adapters until equivalent tested Python boundaries exist. Skills remain concise and delegate deterministic operations to the CLI.

## 10. Security and Publication

- Never serialize credentials into prompts, state files, events, fixtures, or repositories.
- Redact environment-derived secrets before storing process diagnostics.
- Refuse broad recursive cleanup targets and unresolved worktree paths.
- Require explicit opt-in for permission-bypass flags and record their use without recording tokens.
- Add a provenance manifest before importing existing local scripts.
- Audit OMX, OMC, Codex, Claude, and Skill source licenses before redistribution.
- Do not publish copied implementation until provenance and redistribution rights are documented.

## 11. Testing Strategy

### Contract tests

- Goal and Task schema validation.
- DAG acyclicity and wave legality.
- Command/event envelope compatibility.
- Claim, lease, transition, and idempotency behavior.
- Cross-version rejection and migration behavior.

### Fake-runtime tests

Inject fake Git, tmux, OMX, OMC, Codex, and Claude binaries. No test may launch a real Team.

Cover:

- Pure OMX success, failure, resume, leader loss, and serialized integration.
- Adapter ACK, claim, OMC startup, progress, review, correction, and completion.
- At least three follow-up rounds in one live Hybrid Team lifecycle.
- Duplicate and out-of-order mailbox messages.
- Adapter, Claude leader, OMC worker, OMX leader, and tmux restart scenarios.
- Stale leases and zero/multiple recovery candidates.
- Scope escape, dirty worktree, protected reference, and verification mutation rejection.
- Rebase conflict, main drift, shutdown failure, and post-merge verification failure.

### Forward tests

Before version 1 release, verify:

1. One atomic Task through pure OMX.
2. One Hybrid Task with three review/correction rounds without restarting OMC Team.
3. A three-Task DAG with two parallel Tasks and one dependency barrier.
4. Same-command resume after interruption in every lifecycle stage.

## 12. Delivery Stages

### P0: repository and design baseline

Create the public repository, publish this reviewed design, define provenance policy, and configure basic documentation validation.

### P1: pure OMX baseline

Port or reimplement the Goal compiler and pure OMX lifecycle after provenance review. Expose `loop-engineer run omx` and retain script compatibility.

### P2: common contracts

Freeze versioned Goal, Task, plan, event, claim, lease, evidence, handoff, and recovery schemas.

### P3: OMC executor-adapter MVP

Implement one adapter, one persistent Claude leader, one OMC Team, and one atomic Task with real-time progress mapped to one OMX worker lifecycle.

### P4: review/correction loop

Support repeated OMX follow-up commands in the same active Team lifecycle and prove at least three correction rounds.

### P5: Hybrid batch runtime

Expose `loop-engineer run hybrid`, overlap independent Task execution, serialize finishers, and resume interrupted plans.

### P6: Skill packaging

Publish concise `define-goal`, `goal-to-omx-team`, and `goal-to-omx-omc-team` Skills with deterministic installers for Codex and Claude environments.

### P7: release qualification

Run contract, fake-runtime, recovery, and three real-project forward scenarios. Publish only after provenance, security, and compatibility gates pass.

## 13. Acceptance Criteria

The first stable release is complete only when:

1. Pure OMX and Hybrid commands are visibly distinct and cannot silently switch lanes.
2. The Hybrid adapter is a claim-safe OMX worker controlling a persistent OMC Team.
3. OMX can issue at least three real-time follow-up assignments without restarting the OMC Team.
4. OMC cannot approve repository completion or merge `main`.
5. OMX owns review, correction decisions, final verification, and integration.
6. All runtime stages resume through the same operator command after interruption.
7. Independent Tasks can overlap while finishers and `main` integration remain serialized.
8. Fake-runtime tests launch no real Team and cover ambiguity, stale ownership, failure, and recovery.
9. Published code has documented provenance and redistribution permission.
10. Skills contain workflow guidance while deterministic lifecycle behavior remains in tested code.

## 14. Open Design Decisions

These decisions belong in the implementation plan after this specification is approved:

- Exact Python packaging and minimum supported Python version.
- JSON Schema draft and event journal storage format.
- Whether the adapter process is launched as a dedicated OMX worker CLI mode or as a wrapper around a standard worker pane.
- Compatibility policy across OMX and OMC versions.
- Initial public license after third-party provenance review.
