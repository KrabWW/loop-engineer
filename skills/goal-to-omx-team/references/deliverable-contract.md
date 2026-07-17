# Deliverable Contract

Use repository-native locations when they already exist. For repositories following `docs/tasks`, produce the following equivalent artifact set.

## 1. Evidence and goal

- Source inventory: scenario website, supplied documents, reference-project paths, target architecture, current contracts, and accessed revisions or dates.
- Measurable goal: expected system truth, required evidence, scope, exclusions, and direction-changing stop condition.
- Coverage matrix: every user scenario step maps to an Operator, preconditions, inputs, outputs, owner, durable authority, read/write boundaries, permission, audit fact, success, failure, and recovery path.

Reference sources are read-only. Never modify `refer/` or claim reference behavior is already implemented.

## 2. Stage map

For every G stage record:

- business closure and binary exit criterion;
- incoming and outgoing dependencies;
- included atomic Task IDs;
- required protocol decisions;
- migration or other serialization constraints;
- executable acceptance evidence.

G0 freezes multi-domain semantics before downstream implementation. G stages organize outcomes; Tasks are the only Team execution units.

## 3. Atomic Task schema

Every Task file must contain:

- `Status`, Owner, and `Depends on`;
- one-domain goal and one verifiable result;
- exact `Allowed Files` paths;
- explicit Non-goals;
- authoritative inputs, outputs, interfaces, events, errors, retries, cancellation, idempotency, and security constraints relevant to that Task;
- Acceptance Criteria with observable evidence;
- exact Verification Commands runnable from a named directory;
- downstream handoff and any serialized migration predecessor.

Task IDs and file ownership must be unique. Every dependency must resolve to a Task. The directed graph must be acyclic. A Task is `ready` only when all dependencies are `done`; otherwise it is `blocked`.

## 4. OMX execution guide

Document one integration branch, one integration worktree, and one OMX team per Task. State separately that OMX worker worktrees are runtime implementation lanes created by Team mode; they do not replace the Task integration worktree.

Each generated leader prompt must require:

- authoritative Task and repository instructions first;
- dependency and status checks before writes;
- exact Allowed Files only;
- non-overlapping writer, test/evidence, and independent verifier lanes;
- repository commit protocol and all Verification Commands;
- final commit, changed paths, evidence, skipped checks, risks, and downstream handoff;
- no plan-only completion and no mutation of reference sources, credentials, logs, or runtime data.

These rich controls belong in the leader prompt. The nested Team task remains one atomic sentence that names the Task and outcome; after startup the leader sends detailed, non-overlapping worker assignments through Team state or mailbox.

## 5. Executable launcher

The supported operator surface is self-contained and never requires a shell-local `task_prompt` or similar helper:

```sh
./scripts/start-omx-task --dry-run <TASK_ID>
./scripts/start-omx-task <TASK_ID>
./scripts/start-omx-task --allow-derived-ready <TASK_ID>
./scripts/start-omx-task --resume-existing --allow-derived-ready <TASK_ID>
```

Generate the launcher and its tests under exact task-owned paths. It must fail closed before mutation unless:

- it runs from the clean integration base branch and repository root;
- the Task ID resolves to exactly one Task file;
- Task status is `ready` and all `Depends on` Tasks are `done`;
- required tools, disk budget, concurrency limit, branch, worktree, and tmux names are safe;
- the complete leader prompt is non-empty and passed as one argument to a persistent non-interactive `omx exec --dangerously-bypass-approvals-and-sandbox` process.

Manual launches accept only explicit `ready`. `--allow-derived-ready` is reserved for the strict queue and batch runners: it may accept `blocked` only when every dependency is `done`, the Task file is inside its own Allowed Files, and the generated Team prompt requires that Task to perform and commit its own legal status transition before other writes. This flag is not a dependency or status bypass.

The launcher must create a detached tmux session rooted in the Task integration worktree, capture its initial leader pane with `-P -F '#{pane_id}'`, and run:

```sh
env OMX_ROOT=<absolute-task-worktree> OMX_AUTO_UPDATE=0 \
  omx exec --dangerously-bypass-approvals-and-sandbox <leader-prompt>
```

The persistent Codex leader invokes exactly one `omx team N:executor "<atomic-task>"` command. `<atomic-task>` is one atomic sentence without semicolons, bullets, newlines, or unrelated clauses because OMX may decompose compound text into multiple runtime tasks. The leader stays alive to assign non-overlapping work, integrate worker commits, verify the exact integrated HEAD, and produce final evidence.

Startup is successful only when exactly one `.omx/state/team/*/config.json` exists under the Task worktree, cwd-bound JSON status reports the expected worker total, zero dead and non-reporting workers, and at least one runtime task, every worker has ACKed in the leader mailbox, and the captured leader pane still reports `pane_dead=0`. A live tmux session alone is not sufficient: a worker-backed session can remain after the leader exits.

Pane discovery must scan all tmux windows and filter by both deterministic session name and exact integration-worktree cwd.

Every lifecycle call must first enter the integration worktree, set `OMX_ROOT=<absolute-task-worktree>` and `OMX_AUTO_UPDATE=0`, and name the discovered Team explicitly: `omx team status <team> --json`, `omx team await <team> --timeout-ms 30000 --json`, and `omx team shutdown <team>`. On resume, a missing exact-cwd leader remains fatal for an active Team; only a healthy `phase=complete` Team with positive fully-completed task counts and zero failed/dead/non-reporting state may create one detached exact-worktree terminal recovery pane in the deterministic session for the finisher. On success, write deterministic launch JSON with the derived-ready decision, `refer_fingerprint_version=content-v2`, and a content-stable fingerprint of the repository-root `refer/` tree. The fingerprint ignores mtime plus nested `.git`, `.omx`, and `.DS_Store` metadata while still hashing protected paths, types, permissions, file content, and symlink targets. Print Task, base commit, branch, integration worktree, tmux session, leader pane, Team name, monitoring commands, and `./scripts/finish-omx-task <TASK_ID>`. On failure before Team state exists, remove the branch and worktree only when both the leader pane and entire session are absent. Preserve and print recovery coordinates whenever Team state exists or the session still has panes. Do not bind the contract to a queue, storage, vector database, Secret Manager, or other provider; keep it adapter-neutral.

## 6. Required launcher tests

Use temporary Git repositories and fake OMX/tmux binaries. Prove:

- successful creation and a captured non-empty authoritative prompt;
- persistent leader argv, Task-worktree cwd, `OMX_ROOT`, and `OMX_AUTO_UPDATE=0`;
- one atomic sentence reaches `omx team` as one task rather than compound task text;
- worker panes and leader mailbox ACKs are ready before startup succeeds;
- dry-run creates no branch, worktree, tmux session, or OMX state;
- invalid or ambiguous Task ID rejection;
- blocked status or unfinished dependency rejection;
- dirty base, duplicate resource, insufficient disk, and excess concurrency rejection;
- exact leader pane success even when worker panes keep the session alive, plus terminal-only recreation when the leader has exited;
- leader exit before state cleans only when the entire session is gone;
- leader exit after state, a worker-backed session, and startup timeout preserve explicit recovery state;
- status, await, and shutdown remain cwd-bound and update-prompt-free;
- no real Team starts during verification.

## 7. Executable finisher

Generate `./scripts/finish-omx-task <TASK_ID>` and fake-runtime tests. It runs only from clean `main`, derives the deterministic branch/worktree/session, and discovers exactly one random Team name from that Task worktree's `.omx/state/team/*/config.json`. Never scan globally or ask the operator for Team, worktree, session, or branch.

Before shutdown it must require the configured leader pane alive or recover a unique live exact-cwd pane from the deterministic Task session, excluding explicit HUD panes; zero or multiple candidates fail closed. It must also require `phase=complete`, positive task count, all tasks completed, zero pending/blocked/in-progress/failed/dead/non-reporting, one final evidence file with exactly one full `Final HEAD` field (accepting historical `Final leader HEAD`) whose commit is an ancestor with the same tree, Task status `done`, a clean worktree, controlled Task-file lifecycle changes only (Status plus existing Acceptance Criteria markers from unchecked to checked without text/order/count changes), Allowed Files confinement, an unconditional ban on `refer/` Allowed Files or Task-branch changes, whitespace/links, and the authoritative Task Verification Commands from the pre-integration main commit. Compare the launch-time versioned repository-root `refer/` fingerprint for audit and warn on external main-worktree drift, but do not block an otherwise clean Task merely because the user edited ignored reference documentation in parallel. New leaders must emit the canonical `Final HEAD` field.

Shutdown is cwd-bound and may add content-neutral checkpoint history only. Reject history rewrite, dirty state, or any changed tree. Kill only the deterministic Task session and prove it absent; a live tmux session after cleanup is a hard failure. If main advanced since launch, run `git rebase --rebase-merges main`; never use plain rebase, force, or automatic conflict resolution. Preserve approved Task blobs, rerun all gates on the rebased HEAD, require main unchanged during the transaction, then `git merge --ff-only`. Run the same gates on merged main before removing the exact worktree and deleting the merged branch with `-d`. These are the required three verification runs.

Each verification run must prove its commands did not change HEAD or leave the repository dirty. Any pre-shutdown failure leaves runtime and main untouched. After successful shutdown, persist a phase journal in the Git common directory; any later failure preserves branch/worktree, prints `recovery_*` plus the exact same finish command, and resumes without requiring a live Team/session/leader. Post-merge failure never resets main or removes recovery resources. Fake tests cover success with a random Team, unrelated main advance, merge topology, shutdown empty commit, a foreign live Team, zero/multiple configs, non-complete state, missing/stale evidence, dirty/scope/`refer/`/verification failures, zero-exit dirty verification, shutdown/tmux failures, same-command resume, rebase conflict, main drift, and lock contention.

## 8. Sequential 12-hour queue

Install the bundled runner and test from this Skill into equivalent target paths:

```sh
./scripts/run-omx-task-queue --dry-run --hours 12 path/to/queue.txt
./scripts/run-omx-task-queue --hours 12 --finish-current path/to/queue.txt
```

The queue is strict ordered input, one Task ID per line. It must:

1. start exactly one Task through `start-omx-task --allow-derived-ready`;
2. parse the launcher's exact `leader_pane`, require that pane to remain at `pane_dead=0` during polling and before terminal evidence, and never substitute session liveness;
3. call cwd-bound `OMX_AUTO_UPDATE=0 OMX_ROOT=<worktree> omx team status <team> --json`, using similarly bound `omx team await <team> ... --json` only as an event wake-up;
4. advance only at `phase=complete` with positive task count and pending, blocked, in-progress, failed, dead-worker, and non-reporting-worker counts all zero; `failed` or `cancelled` phases stop and preserve recovery state;
5. journal terminal JSON, then delegate Task-done, clean, committed-change, Allowed Files, `refer/`, evidence, and verification gates to the finisher;
6. invoke `OMX_TASK_FINISHER` (default `./scripts/finish-omx-task`) and advance only when it reports `mode=finished` with `main_after` equal to current main; never duplicate shutdown, rebase, merge, or cleanup logic in the queue;
7. stop and print recovery coordinates on signals, invalid JSON, non-complete terminal phase, blocked/dead/non-reporting worker, dead leader pane, or any finisher failure;
8. after the deadline, start no new Task; `--finish-current` lets the active Task reach its normal terminal gate before stopping.

This 12-hour policy limits new starts, not the duration of an already-running Task. Never hard-kill an active Team merely because the wall-clock deadline arrived.

Fake starter/OMX/tmux/finisher tests must prove ordered multi-Task success, dry-run, deadline-before-start, await through `team-verify` until `complete`, terminal failure/cancellation, dead/non-reporting workers, exact leader-pane death, invalid JSON, signal recovery coordinates, finisher shutdown failure, tmux failure, and successful finisher rebase when main advances. Tests must never launch a real Team.

## 9. Integrated batch runner

Generate `./scripts/run-omx-task-batch --mode serial|parallel|custom <PLAN_FILE>` and fake tests. Serial makes one Task per wave. Parallel chunks independent Tasks by `--max-parallel`. Custom treats each non-empty plan line as one parallel wave and lines as strict barriers. For every wave, invoke the launcher with `--resume-existing`: start new Teams, resume complete existing branch/worktree/session/Team ownership, and skip Tasks already merged into main with lifecycle resources cleaned. Require each exact leader/Team to reach valid terminal state and one `${slug}*final-evidence*.md` file containing exactly one canonical full 40-character `Final HEAD` before declaring `task_terminal`; recover a stale pane only from the unique live exact-cwd candidate, or create one exact-cwd terminal recovery pane only after a healthy complete snapshot, then invoke the finisher sequentially. A single dead/non-reporting sample must receive a bounded leader recovery grace; blocked review and leader closeout holds continue waiting, while terminal failure, active or ambiguous leader loss, incomplete ownership, multiple evidence files, or persistent unhealthy workers fail closed. Team execution may overlap; shutdown/rebase/merge/main integration never overlaps. Any failure starts no later wave and prints a finish recovery command for every unfinished Task. Fake tests prove delayed final evidence, interrupted same-plan resume, already-finished skipping, terminal leader recreation, transient health recovery, and persistent-health failure. Never duplicate finisher internals.

## 10. One-command lifecycle installer

Bundle `scripts/install-omx-task-lifecycle <REPOSITORY>`. It preflights all targets, installs the launcher, finisher, batch runner, examples, and fake tests, is idempotent for identical files, refuses differing targets unless `--force`, preserves executable modes, and runs shell syntax checks. Its success output prints the exact start, finish, and custom-batch commands.

## 11. Final validation

The bundle is ready only when source paths exist, all scenario steps have unique authority, all task IDs and launcher commands match one-to-one, dependencies are acyclic, every Task has exact Allowed Files and executable checks, no unexplained placeholder remains, installer/start/finish/batch/queue scripts pass syntax and fake-runtime tests, document links resolve, `git diff --check` passes, and protected reference or credential paths remain clean.
