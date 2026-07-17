# Loop Engineer Design

Date: 2026-07-17
Status: Approved

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

Rerunning the original `loop-engineer run <lane> --plan <plan-file>` command is the canonical resume operation. `loop-engineer resume` is only a convenience alias that resolves one existing run journal and re-invokes the recorded lane and plan; zero or multiple matching journals fail closed.

All commands use these stable exit classes:

- `0`: requested state reached or an already-reached idempotent state confirmed.
- `2`: invalid input, schema, plan, dependency, or unsupported provider version.
- `3`: ownership, lease, leader, Team, worktree, or recovery ambiguity.
- `4`: runtime or worker terminal failure.
- `5`: verification, scope, provenance, or protected-path failure.
- `6`: Git integration conflict or `main` drift.
- `7`: partial completion preserved for same-command recovery.

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
- Normalized-path write-scope conflict detection.
- Deterministic names for branch, worktree, tmux session, and journals.
- Process leases and heartbeats.
- Durable event append and replay.
- Resume and cleanup decisions.
- Serialized finisher locking.

The runtime core does not import OMX- or OMC-specific state directly. Runtime adapters translate provider state into common events.

Before scheduling a wave, the compiler normalizes every exact `Allowed Files` entry against the repository root, resolves file-versus-directory containment, and compares every Task pair. Overlap is legal only when the Tasks are ordered by a dependency path. Unordered overlap is rejected with exit `2`; the scheduler never silently serializes an invalid plan because that would hide a missing ownership decision.

### 6.3 Pure OMX runtime adapter

Starts a detached Task integration worktree and persistent Codex leader. The leader launches exactly one OMX Team for the atomic Task, assigns non-overlapping work, integrates worker results, reviews the integrated HEAD, and produces evidence.

The finisher requires a healthy terminal Team, a live or legally recovered leader, committed evidence, clean scope, OMX Task status `completed`, an unchanged protected reference fingerprint, and three verification runs: before shutdown, after rebase, and after fast-forward integration.

### 6.4 OMC executor adapter

The OMC executor adapter participates as a real OMX worker while owning a persistent Claude leader and OMC Team. Version 1 uses a standard OMX Codex worker pane with the `omc-adapter` role. That worker immediately starts the deterministic `loop-engineer adapter serve` sidecar in the foreground and performs no product coding. The sidecar uses the worker identity and claim token; the Codex worker remains the supervised OMX pane. Native custom worker executables are deferred until OMX supports them without patching.

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

The adapter retains its OMX claim across OMC execution, blocking, review, correction, provider quiescence, promotion, and OMX repair. Writer transfer changes filesystem authority but does not release the Task claim. The adapter renews its generation-scoped lease while the claim is held, performs no product writes after quiescence begins, and releases the claim only when the OMX leader approves and transitions the OMX Task to `completed`, or when claim-safe cancellation/failure ends the worker Task. Review does not complete the OMX Task.

### 6.5 Finisher

The OMX-side finisher is the only component allowed to integrate into `main`. It validates ownership and evidence, shuts down active runtimes, rebases with merge topology preserved, reruns authoritative verification, fast-forwards `main`, verifies merged `main`, and removes exact lifecycle resources.

In Hybrid mode, the finisher accepts only the Task integration branch HEAD recorded by the OMX leader after provider quiescence and deterministic promotion. It never integrates an OMC provider branch directly. OMC completion pins `omc_result_commit`; after the provider process group is gone, the runtime core promotes that exact tree into the Task integration branch and records `review_base_commit`. The adapter no longer writes after quiescence begins. Any tree mismatch fails with exit `5`.

If failure occurs before fast-forwarding `main`, main remains unchanged and all exact recovery resources are retained. A rebase conflict or main drift returns exit `6`. If merged-main verification fails after `main` advanced, the finisher never resets or rewrites `main`; it writes `post_merge_verification_failed`, retains the evidence journal, branch, and worktree, blocks later waves, and returns exit `7`. Recovery requires a new repair Task based on the current `main`, followed by normal forward-only integration.

## 7. Hybrid Protocol

### 7.1 Command envelope

Each leader-to-adapter command includes:

- Protocol version.
- Run ID, Task ID, OMX Team name, and worker identity.
- Unique `command_id`, optional parent `causation_id`, and monotonic `command_revision` within the Task run.
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
- `RELEASE_FOR_OMX_FIX`
- `CANCEL_TASK`
- `SHUTDOWN_EXECUTOR`

`CANCEL_TASK` is valid only while the adapter holds the OMX Task claim. The public `stop` command routes pre-claim cancellation to the runtime-core `CANCEL_PENDING` operation and post-approval/pre-fast-forward cancellation to runtime-core `CANCEL_INTEGRATION`; these are journal operations, not leader-to-adapter commands.

### 7.2 Event envelope

Adapter-to-leader events include `run_id`, `task_id`, `command_id`, a unique `event_id`, monotonic `event_sequence`, provider observation revision, lease generation, and one of:

- `ACKNOWLEDGED`
- `STARTED`
- `PROGRESS`
- `HEARTBEAT`
- `BLOCKED`
- `READY_FOR_REVIEW`
- `FAILED`
- `CANCELLED`
- `SHUTDOWN_ACK`

Events are append-only and idempotent by `event_id`. Multiple progress and heartbeat events for one command remain distinct. The journal accepts only the next `event_sequence`; duplicate event IDs are ignored, future sequence gaps are held for replay, and a lower unseen sequence is rejected as stale. Provider observation revisions prevent an older OMC snapshot from overwriting a newer one. A summarized mailbox notification points at durable evidence rather than embedding large logs.

### 7.3 Authoritative transition and ownership table

This table is the sole normative lifecycle map. Provider adapters may expose more detailed observations, but they cannot introduce additional common-state transitions.

| Common state | OMX Task | Claim holder | Filesystem writer | OMC observation | Accepted command or trigger | Legal next state | Exit/terminality |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `ready` | `pending` | none | none | absent | `START_TASK` / runtime `CANCEL_PENDING` | `claimed` / `cancelled` | cancel terminal |
| `claimed` | `in_progress` | adapter generation N | none | absent | claim success / `CANCEL_TASK` | `omc_starting` / `cancelled` | cancel releases claim and is terminal |
| `omc_starting` | `in_progress` | adapter N | provider process group N | starting | readiness success / startup hold / `CANCEL_TASK` | `omc_executing` / `blocked` / `cancelled` | hold `7`; cancel terminal |
| `omc_executing` | `in_progress` | adapter N | provider process group N | active | provider complete / provider hold / provider failure / `CANCEL_TASK` | `ready_for_omx_review` / `blocked` / `failed` / `cancelled` | failure `4`; terminal only for failed/cancelled |
| `blocked` | `in_progress` | adapter N, lease renewed | provider process group N or none as journaled | blocked evidence | `CONTINUE_TASK` / `REQUEST_FIX` / `CANCEL_TASK` / leader fail decision | `omc_executing` / `correction_requested` / `cancelled` / `failed` | hold `7`; terminal only for failed/cancelled |
| `ready_for_omx_review` | `in_progress` | adapter N | provider process group N; OMX read-only | complete, pinned result | leader begins review / `CANCEL_TASK` | `omx_reviewing` / `cancelled` | cancel terminal after provider shutdown |
| `omx_reviewing` | `in_progress` | adapter N | provider process group N; OMX read-only | complete and idle | `REQUEST_FIX` / `REQUEST_EVIDENCE` / `RELEASE_FOR_OMX_FIX` / `CANCEL_TASK` | `correction_requested` / `omx_reviewing` / `writer_quiescing` / `cancelled` | non-terminal; cancel terminal after provider shutdown |
| `correction_requested` | `in_progress` | adapter N | provider process group N | resumable same Team | accepted follow-up / failure / `CANCEL_TASK` | `omc_executing` / `failed` / `cancelled` | terminal only for failed/cancelled |
| `writer_quiescing` | `in_progress` | adapter N | provider process group N until fence proof, then none | shutdown requested | full fence proof / timeout or ambiguity / `CANCEL_TASK` | `promoting` / `blocked` / `cancelled` | hold `7`; cancel terminal after cleanup proof |
| `promoting` | `in_progress` | adapter N | runtime core only | process group absent, frozen commit | tree promotion success / mismatch / `CANCEL_TASK` | `post_promotion_review` / `failed` / `cancelled` | mismatch `5`; cancel terminal with branch retained |
| `post_promotion_review` | `in_progress` | adapter N, no write authority | OMX generation N+1 | provider absent | review finds fixes / review and verification pass / review failure / `CANCEL_TASK` | `omx_fixing` / `omx_verified` / `failed` / `cancelled` | verification required before verified; terminal only for failed/cancelled |
| `omx_fixing` | `in_progress` | adapter N, no write authority | OMX generation N+1 | provider absent | fix verified / fix failure / `CANCEL_TASK` | `omx_verified` / `failed` / `cancelled` | terminal only for failed/cancelled |
| `omx_verified` | `completed` after leader approval and claim release | none | none | provider absent | finisher lock acquired / runtime `CANCEL_INTEGRATION` | `finishing` / `integration_cancelled` | integration cancellation terminal before finisher starts |
| `finishing` | `completed` | none | finisher only | provider absent | pre-merge failure / main fast-forward / runtime `CANCEL_INTEGRATION` before fast-forward | `finishing` / `merged` / `integration_cancelled` | integration failure `6` or resumable `7`; cancellation terminal only before fast-forward |
| `merged` | `completed` | none | none | absent | merged-main verification pass / fail / runtime stop | `merged` / `post_merge_verification_failed` / reject | success terminal; stop rejected `2` |
| `post_merge_verification_failed` | `completed` | none | none; later waves blocked | absent | create forward repair Task / runtime stop | `post_merge_verification_failed` / reject | non-terminal incident; stop rejected `2` |
| `failed` | `failed` | none | none | retained evidence | retry reset transaction / runtime stop | `ready` / `failed` | retry creates new attempt in `pending`; stop idempotent `0` |
| `cancelled` | `cancelled` | none | none | absent or quarantined evidence | retry reset transaction / runtime stop | `ready` / `cancelled` | retry creates new attempt in `pending`; stop idempotent `0` |
| `integration_cancelled` | `completed` | none | none | provider absent | retry integration or create repair Task | `finishing` or new Task | terminal for the current integration attempt; main unchanged |

The adapter may transition `pending -> in_progress` only through claim-safe OMX API. It may transition to `failed` or `cancelled` with the live claim token. Only the OMX leader may approve `in_progress -> completed`, and only after provider quiescence, promoted-tree review, and verification evidence. Retry is an atomic runtime-core transaction: require terminal attempt state and no live claim or writer, increment `attempt_id` and lease generation, preserve prior evidence, reset the OMX Task to `pending`, then enter `ready`; the next `START_TASK` performs a new claim.

Cancellation is accepted only before `main` fast-forward. `CANCEL_PENDING` handles `ready`; `CANCEL_TASK` handles claim-owned states from `claimed` through `omx_fixing`; `CANCEL_INTEGRATION` handles `omx_verified` and pre-fast-forward `finishing` without changing the already-completed OMX worker Task. During `writer_quiescing`, `promoting`, or pre-fast-forward `finishing`, cancellation first completes the current atomic safety step, preserves the integration branch and journal, prevents main integration, and then records `cancelled` or `integration_cancelled` as appropriate. After `main` fast-forward, all cancellation operations return exit `2`; merged-main verification must finish and any defect is handled by a forward repair Task.

### 7.4 Executor lifecycle

`SHUTDOWN_EXECUTOR` controls the adapter executor, not a Task state:

| Executor state | Active Task condition | `SHUTDOWN_EXECUTOR` result |
| --- | --- | --- |
| `adapter_idle` | no adapter-held claim and no provider process, regardless of later OMX integration or incident state | transition to `adapter_stopping`, remove exact sidecar/session resources, emit one `SHUTDOWN_ACK`, then `adapter_shutdown` |
| `adapter_active` | adapter holds a Task claim or an adapter-owned provider process exists | reject with exit `2`; caller must use `CANCEL_TASK` or finish the worker Task first |
| `adapter_stopping` | no active Task | duplicate command is idempotent; resume the journaled cleanup step and emit no duplicate ACK event ID |
| `adapter_shutdown` | no active Task | return exit `0` with the existing `SHUTDOWN_ACK` evidence |

Executor shutdown never releases an active claim implicitly and never substitutes for Task cancellation.

### 7.5 Recovery coordinate record

Each Task stores a versioned recovery record in the Git common directory, outside ordinary commits. It includes:

- Repository identity, run ID, Task ID, lane, and protocol version.
- Base commit, integration branch/worktree, adapter execution branch/worktree, and pinned result/review commits.
- OMX Team name, leader session/pane, worker identity, task ID, claim token digest, lease generation, and lease expiry.
- Claude leader session/pane/PID start time and executable identity.
- OMC state root, Team name, worker identities, provider task IDs, and last summary revision.
- Last command revision, event sequence, journal checksum, current phase, and cleanup phase.
- Writer fencing generation and shutdown acknowledgments.

Raw claim tokens and credentials are stored in permission-restricted runtime state, never in logs or committed evidence.

### 7.6 Recovery matrix

| Failure point | Required ownership proof | Permitted recovery | Otherwise |
| --- | --- | --- | --- |
| Before OMC config exists | exact adapter lease plus exact Claude pane/PID start identity | resume startup or remove only wholly absent runtime | exit `3`, preserve coordinates |
| OMC config exists, startup incomplete | one exact state root, Team config, leader pane, and matching worktree | reconnect and continue readiness probe | exit `3` |
| Claude leader lost, OMC Team active | one exact Task-bound Team and no competing leader | recreate one exact-worktree Claude recovery leader without starting a Team | exit `3` |
| OMC worker lost | exact Team plus provider summary proving one failed worker | record `blocked`, preserve claim and evidence, and wait for OMX retry/fail instruction; no duplicate Team | exit `7` |
| Adapter sidecar lost | live OMX worker pane, matching lease generation, replayable journal | restart sidecar and replay before mailbox reads | exit `3` |
| OMX worker pane lost | stale lease plus one exact adapter/OMC runtime and no competing pane | create one recovery worker controller and increment fencing generation | exit `3` |
| tmux session lost | process identities absent and provider state terminal or safely resumable | recreate only the exact missing controller session | exit `3` |
| PID reused | PID start time or executable identity mismatch | treat as absent, never signal it | exit `3` |
| Shutdown partially complete | journaled cleanup phase and exact remaining resources | resume next idempotent cleanup step | exit `7` |
| After main fast-forward | merged commit equals journaled integration commit | rerun merged-main verification only | block waves and exit `7` on failure |

### 7.7 Recovery rules

- Replaying a command with the same `command_id` must not start a second OMC Team.
- A live lease prevents a second adapter from claiming the same OMX Task.
- A stale lease is recoverable only when exact Task, worktree, Team, and process evidence identify one owner.
- Zero or multiple candidates fail closed.
- OMC completion without a commit/evidence match cannot become `READY_FOR_REVIEW`.
- An adapter restart replays the event journal before reading new mailbox commands.
- A leader restart reconstructs active Tasks from Team state and adapter heartbeats.
- Main integration is protected by a repository-wide finisher lock.

## 8. Isolation and Git Model

Pure OMX and Hybrid Tasks both use a Task integration branch and worktree. In Hybrid mode, the OMC Team works only inside the adapter-owned execution worktree or its provider-created worker worktrees. OMC auto-merge targets the adapter execution branch, never `main`.

OMC-to-OMX promotion is a four-step protocol:

1. Freeze: record the exact `omc_result_commit`, provider worker HEADs, clean state, scope proof, and evidence tree.
2. Quiesce: increment `writer_generation`, send shutdown, require every OMC worker and Claude leader shutdown acknowledgment, terminate and prove absence of the dedicated provider process group including descendants by PID start identity, and prove provider worktrees clean.
3. Promote and revoke: with no provider process alive, the deterministic runtime core promotes the exact frozen commit tree into the Task integration branch, records `review_base_commit` and equal tree hashes, removes the adapter-owned execution worktree and all provider-created worktrees, and deletes or read-only quarantines every provider-writable path. The adapter performs no promotion write.
4. Transfer writer authority: retain the adapter's non-writing Task claim, grant the OMX leader generation N+1 filesystem write ownership, and journal the split authorities. OMX must not write before provider paths are absent or read-only quarantined. The adapter releases its claim only when the leader later approves `omx_verified`, or through claim-safe cancellation/failure.

A delayed event holding generation N is rejected. Direct filesystem fencing is provided by proving the full provider process group absent and removing its worktrees before generation N+1 exists; shutdown acknowledgment alone is insufficient. Any unknown descendant process, open provider worktree, or filesystem change blocks transfer and returns exit `3`.

Across independent Tasks, OMC execution and OMX review may overlap only after normalized `Allowed Files` conflict checks pass. Shared migrations and protocol predecessors remain serialized by the DAG.

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

The public repository initially contains original design-only material. “Publication” in P0 means publishing that original specification. “Redistribution” means committing imported or adapted implementation from OMX, OMC, local Skills, or other sources; redistribution is forbidden until each file has a provenance entry, source license, transformation policy, and approval. The repository may remain public while implementation directories stay empty.

## 11. Testing Strategy

### Contract tests

- Goal and Task schema validation.
- DAG acyclicity and wave legality.
- Command/event envelope compatibility.
- Claim, lease, transition, and idempotency behavior.
- Exact supported-version acceptance and unsupported-version rejection. Cross-version state migration is deferred from version 1.

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
- Exit-code, retained-resource, journal-phase, Git-HEAD, and no-duplicate-runtime assertions for each recovery matrix row.

### Forward tests

Before version 1 release, verify:

1. One atomic Task through pure OMX.
2. One Hybrid Task with three review/correction rounds without restarting OMC Team.
3. A three-Task DAG with two parallel Tasks and one dependency barrier.
4. Same-command resume after interruption in every lifecycle stage.

## 12. Delivery Stages

### P0: repository and design baseline

Create the public repository, publish this reviewed design, define provenance policy, and configure basic documentation validation.

### P1: common contracts and provenance

Freeze versioned Goal, Task, plan, command, event, claim, lease, evidence, handoff, writer-fence, and recovery schemas. Establish the provenance manifest and supported OMX/OMC version probe before importing runtime implementation.

### P2: pure OMX baseline

Port or reimplement the Goal compiler and pure OMX lifecycle against P1 contracts. Expose `loop-engineer run omx` and retain script compatibility.

### P3: OMC executor-adapter MVP

Implement one adapter, one persistent Claude leader, one OMC Team, and one atomic Task with real-time progress mapped to one OMX worker lifecycle.

### P4: review/correction loop

Support repeated OMX follow-up commands in the same active Team lifecycle and prove at least three correction rounds.

### P5: Hybrid batch runtime

Expose `loop-engineer run hybrid`, overlap independent Task execution, serialize finishers, and resume interrupted plans.

### P6: Skill packaging

Publish concise `define-goal`, `goal-to-omx-team`, and `goal-to-omx-omc-team` Skills with deterministic installers for Codex and Claude environments.

### P7: release qualification

Run contract, fake-runtime, recovery, and three real-project forward scenarios. Tag the first stable release only after provenance, security, and compatibility gates pass.

## 13. Acceptance Criteria

The first stable release is complete only when:

1. Pure OMX and Hybrid commands are visibly distinct and cannot silently switch lanes.
2. The Hybrid adapter is a claim-safe OMX worker controlling a persistent OMC Team.
3. OMX can issue at least three real-time follow-up assignments without restarting the OMC Team.
4. OMC cannot approve repository completion or merge `main`.
5. OMX owns review, correction decisions, final verification, and integration.
6. Rerunning the original `run` command after every recovery-matrix failure either reaches the next legal phase with exit `0` or returns the specified fail-closed exit while preserving the required journal and resources.
7. `resume` resolves exactly one recorded run or exits `3`; it is behaviorally equivalent to rerunning that run command.
8. The scheduler rejects unordered normalized `Allowed Files` overlap with exit `2`; independent non-overlapping Tasks can overlap while finishers and `main` integration remain serialized.
9. Every successful writer transfer proves OMC shutdown acknowledgments, a new fencing generation, identical pinned tree hashes, and no later old-generation mutation.
10. Rebase conflict and main drift leave main unchanged; post-merge verification failure leaves main forward-only, blocks later waves, and retains repair evidence with exit `7`.
11. Fake-runtime tests launch no real Team and assert journal, lease, process, Git, exit-code, and no-duplicate-runtime outcomes for every recovery stage.
12. Every redistributed implementation file has documented provenance and redistribution permission.
13. Skills contain workflow guidance while deterministic lifecycle behavior remains in tested code.

## 14. Open Design Decisions

These decisions belong in the implementation plan after this specification is approved:

- Exact Python packaging and minimum supported Python version.
- JSON Schema draft and append-only event journal storage engine.
- Exact initial supported OMX and OMC version ranges, selected during the P1 capability probe.
- Initial public implementation license after third-party provenance review.
