# Deliverable Contract

Use repository-native locations when they already exist. For repositories following `docs/tasks`, produce the following artifact set. This contract mirrors the OMX contract with the OMC `omc` CLI surface; where it differs from OMX the OMC form is authoritative.

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

## 4. OMC execution guide

Document one integration branch (`codex/omc-qs-<slug>`), one integration worktree (`<root>/omc-<slug>`), and one OMC team per Task. State separately that OMC worker worktrees are runtime implementation lanes created by Team mode; they do not replace the Task integration worktree.

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

The supported operator surface is self-contained and never requires a shell-local helper:

```sh
./scripts/start-omc-task --dry-run <TASK_ID>
./scripts/start-omc-task <TASK_ID>
./scripts/start-omc-task --allow-derived-ready <TASK_ID>
```

Generate the launcher and its tests under exact task-owned paths. It must fail closed before mutation unless:

- it runs from the clean integration base branch and repository root;
- the Task ID resolves to exactly one Task file;
- Task status is `ready` and all `Depends on` Tasks are `done`;
- required tools, disk budget, concurrency limit, branch, worktree, tmux names, and the Task-isolated state base are safe;
- the complete leader prompt is non-empty and passed as one argument to a persistent `omc launch --madmax --notify false` process.

Manual launches accept only explicit `ready`. `--allow-derived-ready` is reserved for the strict batch runner: it may accept `blocked` only when every dependency is `done`, the Task file is inside its own Allowed Files, and the generated Team prompt requires that Task to perform and commit its own legal status transition before other writes. This flag is not a dependency or status bypass.

The launcher must create a detached tmux session rooted in the Task integration worktree, capture its initial leader pane with `-P -F '#{pane_id}'`, and run, using `exec` so pane liveness is process liveness:

```sh
exec env OMC_RUNTIME_V2=1 OMC_STATE_DIR=<absolute-task-state-base> OMC_TEAM_WORKTREE_MODE=branch OMC_TEAM_NO_RC=1 \
  omc launch --madmax --notify false <leader-prompt>
```

The persistent Claude leader invokes exactly one `omc team 1:claude:executor --auto-merge --no-decompose "<atomic-task>"` command. `<atomic-task>` is one atomic sentence without semicolons, bullets, newlines, or unrelated clauses because `--no-decompose` treats the text as fixed worker scope. The leader stays alive to assign non-overlapping work, integrate worker commits via runtime auto-merge, verify the exact integrated HEAD, and produce final evidence.

The Task-isolated state base is `<git-common-dir>/omc-task-state/<slug>`; OMC may append a project identifier beneath it, so team discovery finds `*/state/team/<team-name>/workers` directories recursively but never scans outside that base. Create a manual-size `480x60` leader window and prepend the bundled `omc-runtime-bin/tmux` shim to the leader PATH. On tmux builds whose literal input truncates near 1024 characters, the shim stages only long OMC worker literals as private mode-700 self-deleting launchers, proxies the original literal during delivery verification, and clears proxy state when OMC submits Enter; all other tmux operations pass through to the captured real binary. Persist the exact `leader_pane` to launch JSON immediately after tmux creation, before polling Team readiness. As soon as discovery sees a Team candidate, persist its `team_name` even if its worker is not ready yet; a timeout must leave status and finisher recovery enough authority to inspect that partial launch. Startup is successful only when exactly one API-queryable Team is identified, `omc team api get-summary` reports exactly one worker, zero dead and non-reporting workers, at least one runtime task, and the captured leader pane still reports `pane_dead=0`. On success, extend deterministic launch JSON with `omc_version`, `refer_fingerprint_version=content-v2`, and a content-stable fingerprint of the repository-root `refer/` tree. If retries leave multiple Team directories, query every candidate through exact cwd and state-base-bound `get-summary`: select only a unique valid candidate and never guess by mtime; zero or multiple valid candidates fail closed. The fingerprint ignores mtime plus nested `.git`, `.omc`, `.omx`, and `.DS_Store` metadata while still hashing protected paths, types, permissions, file content, and symlink targets. Print Task, base commit, branch, integration worktree, tmux session, leader pane, state base, Team name, monitoring commands, and `./scripts/finish-omc-task <TASK_ID>`. Keep the contract adapter-neutral.

## 6. Required launcher tests

Use temporary Git repositories and fake OMC/tmux binaries. Prove:

- successful creation and a captured non-empty authoritative prompt;
- persistent leader argv includes `exec`, `OMC_RUNTIME_V2=1`, `OMC_STATE_DIR=`, `OMC_TEAM_WORKTREE_MODE=branch`, `OMC_TEAM_NO_RC=1`, `omc launch --madmax --notify false`, and never `omx`;
- persistent leader argv prepends the bundled tmux shim, records the real tmux binary, and locks a `480x60` manual-size launch window;
- a real-tmux regression proves a worker literal longer than 1024 characters survives delivery verification and executes through the private self-deleting launcher;
- one atomic sentence reaches `omc team 1:claude:executor --auto-merge --no-decompose` as one task;
- dry-run creates no branch, worktree, tmux session, or OMC state;
- invalid or ambiguous Task ID rejection;
- blocked status or unfinished dependency rejection;
- dirty base, duplicate resource, insufficient disk, excess concurrency, and stale-state-base rejection;
- exact leader pane success even when worker panes keep the session alive;
- leader exit before state cleans only when the entire session is gone;
- leader exit after state, a worker-backed session, and startup timeout preserve explicit recovery state including the captured leader pane and any discovered Team name;
- `omc team api get-summary` remains cwd- and state-base-bound;
- a sentinel fails the suite if the real `omc` binary is reached.

## 7. Executable finisher

Generate `./scripts/finish-omc-task <TASK_ID>` and fake-runtime tests. It runs only from clean `main`, derives the deterministic branch/worktree/session/state base, and discovers exactly one random Team name from the Task-isolated state base. Never scan globally or ask the operator for Team, worktree, session, or branch.

Before shutdown it must require the configured leader pane alive or recover a unique live exact-cwd pane from the deterministic Task session; zero or multiple candidates fail closed. It must also require `phase=complete`, positive task count, all tasks completed, zero pending/blocked/in-progress/failed/dead/non-reporting, every worker idle and heart-fresh through `read-worker-status` and `read-worker-heartbeat`, one final evidence file whose HEAD is an ancestor with the same tree, Task status `done`, a clean worktree, Status-only Task-file change, Allowed Files confinement, an unconditional ban on `refer/` Allowed Files or branch changes, the launch-time versioned `refer/` fingerprint, whitespace/links, and the authoritative Task Verification Commands from the pre-integration main commit.

Shutdown is cwd- and state-base-bound and may add content-neutral checkpoint history only. Reject history rewrite, dirty state, or any changed tree. Kill only the deterministic Task session and prove it absent; a live tmux session after cleanup is a hard failure. If main advanced since launch, run `git rebase --rebase-merges main`; never use plain rebase, force, or automatic conflict resolution. Preserve approved Task blobs, rerun all gates on the rebased HEAD, require main unchanged during the transaction, then `git merge --ff-only`. Run the same gates on merged main before removing the exact worktree and deleting the merged branch with `-d`. These are the required three verification runs.

Each verification run must prove its commands did not change HEAD or leave the repository dirty. Any pre-shutdown failure leaves runtime and main untouched. After successful shutdown, persist a phase journal in the Git common directory; any later failure preserves branch/worktree, prints `recovery_*` plus the exact same finish command, and resumes without requiring a live Team/session/leader. Post-merge failure never resets main or removes recovery resources. Fake tests cover success with a random Team, unrelated main advance, merge topology, shutdown empty commit, a foreign live Team, zero/multiple configs, non-complete state, stale heartbeat, missing/stale evidence, dirty/scope/`refer/`/verification failures, zero-exit dirty verification, shutdown/tmux failures, same-command resume, rebase conflict, main drift, and lock contention.

## 8. Read-only status

Generate `./scripts/status-omc-task <TASK_ID>` and tests. It discovers the unique Team under the Task state base; when stale retry directories coexist, it resumes only the single candidate whose exact state-base-bound `get-summary` returns a matching positive-task summary. It never selects by mtime, and multiple live candidates fail closed. It prints task/branch/worktree/session/state-base/leader/Team, task counts, worker counts, heartbeat age, leader liveness, and the exact `tmux attach` and finish commands. `--watch` refreshes on a configurable interval and exits only at a valid terminal state or an explicit error. It never mutates Team state.

## 9. Integrated batch runner

Generate `./scripts/run-omc-task-batch --mode serial|parallel|custom <PLAN_FILE>` and fake tests. Serial makes one Task per wave. Parallel chunks independent Tasks by `--max-parallel`. Custom treats each non-empty plan line as one parallel wave and lines are strict barriers. For every wave, start all Teams, require each exact leader/Team to reach a valid terminal state via `omc team api get-summary` polling (OMC has no `team await`), and if a recorded pane is stale recover only the unique live exact-cwd pane in that Task session, then invoke the finisher sequentially. Team execution may overlap; shutdown/rebase/merge/main integration never overlaps. Any failure starts no later wave and prints a finish recovery command for every unfinished Task. Never duplicate finisher internals.

## 10. One-command lifecycle installer

Bundle `scripts/install-omc-task-lifecycle <REPOSITORY>`. It preflights all targets, installs the launcher, status, finisher, batch runner, examples, and fake tests, is idempotent for identical files, refuses differing targets unless `--force`, preserves executable modes, and runs shell syntax checks. Its success output prints the exact start, status, finish, and custom-batch commands.

## 11. Final validation

The bundle is ready only when source paths exist, all scenario steps have unique authority, all task IDs and launcher commands match one-to-one, dependencies are acyclic, every Task has exact Allowed Files and executable checks, no unexplained placeholder remains, installer/start/status/finish/batch scripts pass syntax and fake-runtime tests, document links resolve, `git diff --check` passes, the real `omc` binary cannot be reached by the fake-runtime suite, and protected reference or credential paths remain clean.
