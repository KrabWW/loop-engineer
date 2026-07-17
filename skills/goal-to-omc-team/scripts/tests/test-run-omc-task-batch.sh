#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd "$(dirname "$0")" && pwd -P)
source_runner=$(cd "$test_dir/.." && pwd -P)/run-omc-task-batch
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/run-omc-task-batch.XXXXXX")
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  haystack=$1
  needle=$2
  printf '%s\n' "$haystack" | rg -F -- "$needle" >/dev/null || fail "missing output: ${needle}"
}

make_fake_bins() {
  fake_bin=$1
  mkdir -p "$fake_bin"

  cat > "$fake_bin/start" <<'START_FAKE'
#!/usr/bin/env bash
set -euo pipefail
allow_derived_ready=0
while [[ "${1:-}" = --* ]]; do
  case "$1" in
    --allow-derived-ready) allow_derived_ready=1 ;;
    *) printf "unknown option: %s\n" "$1" >&2; exit 2 ;;
  esac
  shift
done
[ "$allow_derived_ready" -eq 1 ] || { printf "missing derived-ready\n" >&2; exit 2; }
task=${1:?}
slug=$(printf '%s' "$task" | tr '[:upper:]_' '[:lower:]-')
worktree="${FAKE_BATCH_ROOT:?}/worktrees/$slug"
mkdir -p "$worktree"
printf 'start %s\n' "$task" >> "${FAKE_BATCH_EVENTS:?}"
printf 'mode=started\n'
printf 'task_id=%s\n' "$task"
printf 'task_file=docs/tasks/%s.md\n' "$task"
printf 'branch=codex/omc-qs-%s\n' "$slug"
printf 'worktree=%s\n' "$worktree"
printf 'tmux_session=omc-qs-%s\n' "$slug"
printf 'leader_pane=%%42\n'
printf 'team_name=team-%s\n' "$slug"
printf 'state_base=%s/state-%s\n' "${FAKE_BATCH_ROOT}" "$slug"
START_FAKE
  chmod +x "$fake_bin/start"

  cat > "$fake_bin/finish" <<'FINISH_FAKE'
#!/usr/bin/env bash
set -euo pipefail
task=${1:?}
printf 'finish %s\n' "$task" >> "${FAKE_BATCH_EVENTS:?}"
[ "${FAKE_FINISH_FAIL_TASK:-}" != "$task" ] || { printf 'finish failed\n' >&2; exit 19; }
git commit --allow-empty -qm "finish $task"
printf 'mode=finished\n'
printf 'main_after=%s\n' "$(git rev-parse HEAD)"
FINISH_FAKE
  chmod +x "$fake_bin/finish"

  cat > "$fake_bin/omc" <<'OMC_FAKE'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = team ] || exit 2
sub=${2:-}
case "$sub" in
  api)
    op=${3:-}
    input=
    while [ "$#" -gt 0 ]; do case "$1" in --input) input=$2; break ;; esac; shift; done
    team=$(printf '%s\n' "$input" | sed -n 's/.*"team_name":"\([^"]*\)".*/\1/p')
    case "$op" in
      get-summary)
        if [ "${FAKE_STATUS_FAIL_TEAM:-}" = "$team" ]; then
          printf '{"ok":true,"data":{"summary":{"teamName":"%s","workerCount":1,"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":0,"completed":0,"failed":1},"workers":[{"name":"worker-1","alive":true}],"nonReportingWorkers":[]}}}\n' "$team"
        else
          printf '{"ok":true,"data":{"summary":{"teamName":"%s","workerCount":1,"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":0,"completed":1,"failed":0},"workers":[{"name":"worker-1","alive":true}],"nonReportingWorkers":[]}}}\n' "$team"
        fi
        ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
OMC_FAKE
  chmod +x "$fake_bin/omc"

  cat > "$fake_bin/tmux" <<'TMUX_FAKE'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  display-message)
    shift; [ "${1:-}" = -p ] && shift; [ "${1:-}" = -t ] && shift; pane=${1:?}; shift
    [ "${1:-}" = "#{pane_dead}" ] || exit 2
    case "${FAKE_TMUX_MODE:-stable}" in
      stable) [ "$pane" = %42 ] || exit 1 ;;
      replaced|multiple|dead) [ "$pane" != %42 ] || exit 1; [ "$pane" = %77 ] || [ "$pane" = %78 ] || exit 1 ;;
      *) exit 2 ;;
    esac
    printf '0\n'
    ;;
  list-panes)
    shift; [ "${1:-}" = -t ] && shift; session=${1:?}; shift; [ "${1:-}" = -F ] && shift; format=${1:?}
    [ "$format" = "#{pane_id}\t#{pane_dead}\t#{pane_current_path}" ] || exit 2
    slug=${session#omc-qs-}
    worktree="${FAKE_BATCH_ROOT:?}/worktrees/$slug"
    case "${FAKE_TMUX_MODE:-stable}" in
      stable) printf '%%42\t0\t%s\n' "$worktree" ;;
      replaced) printf '%%77\t0\t%s\n' "$worktree" ;;
      multiple) printf '%%77\t0\t%s\n%%78\t0\t%s\n' "$worktree" "$worktree" ;;
      dead) printf '%%77\t0\t%s/.omc/team/worker-1\n' "$worktree" ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
TMUX_FAKE
  chmod +x "$fake_bin/tmux"
}

make_repo() {
  name=$1
  repo="$tmp_root/$name"
  mkdir -p "$repo/scripts"
  cp "$source_runner" "$repo/scripts/run-omc-task-batch"
  chmod +x "$repo/scripts/run-omc-task-batch"
  git -C "$repo" init -b main -q
  git -C "$repo" config user.name 'Batch Test'
  git -C "$repo" config user.email batch@example.invalid
  printf '.omc/\n' > "$repo/.gitignore"
  git -C "$repo" add .
  git -C "$repo" commit -qm base
  printf '%s\n' "$repo"
}

run_batch() {
  repo=$1
  shift
  name=$(basename "$repo")
  : > "$tmp_root/$name.events"
  (
    cd "$repo"
    FAKE_BATCH_ROOT="$tmp_root/$name-runtime" \
      FAKE_BATCH_EVENTS="$tmp_root/$name.events" \
      FAKE_STATUS_FAIL_TEAM="${FAKE_STATUS_FAIL_TEAM:-}" \
      FAKE_FINISH_FAIL_TASK="${FAKE_FINISH_FAIL_TASK:-}" \
      FAKE_TMUX_MODE="${FAKE_TMUX_MODE:-stable}" \
      OMC_TASK_STARTER="$tmp_root/fake-bin/start" \
      OMC_TASK_FINISHER="$tmp_root/fake-bin/finish" \
      OMC_BIN="$tmp_root/fake-bin/omc" \
      TMUX_BIN="$tmp_root/fake-bin/tmux" \
      OMC_BATCH_POLL_SECONDS=1 \
      ./scripts/run-omc-task-batch "$@"
  )
}

make_fake_bins "$tmp_root/fake-bin"
printf 'PROTO-A-001\nPROTO-B-001\nPROTO-C-001\n' > "$tmp_root/list.plan"
printf 'PROTO-A-001, PROTO-B-001\nPROTO-C-001\n' > "$tmp_root/custom.plan"

repo=$(make_repo dry-run)
output=$(run_batch "$repo" --dry-run --mode custom "$tmp_root/custom.plan")
assert_contains "$output" 'mode=dry-run'
assert_contains "$output" 'wave_1=PROTO-A-001,PROTO-B-001'
assert_contains "$output" 'wave_2=PROTO-C-001'
test ! -s "$tmp_root/dry-run.events" || fail 'dry-run invoked lifecycle tools'

repo=$(make_repo serial)
output=$(run_batch "$repo" --mode serial "$tmp_root/list.plan")
assert_contains "$output" 'batch_status=complete'
test "$(<"$tmp_root/serial.events")" = $'start PROTO-A-001\nfinish PROTO-A-001\nstart PROTO-B-001\nfinish PROTO-B-001\nstart PROTO-C-001\nfinish PROTO-C-001' || fail 'serial order is wrong'

repo=$(make_repo parallel)
output=$(run_batch "$repo" --mode parallel --max-parallel 2 "$tmp_root/list.plan")
assert_contains "$output" 'batch_status=complete'
test "$(<"$tmp_root/parallel.events")" = $'start PROTO-A-001\nstart PROTO-B-001\nfinish PROTO-A-001\nfinish PROTO-B-001\nstart PROTO-C-001\nfinish PROTO-C-001' || fail 'parallel chunking or finish serialization is wrong'

repo=$(make_repo custom)
output=$(run_batch "$repo" --mode custom "$tmp_root/custom.plan")
assert_contains "$output" 'batch_status=complete'
test "$(<"$tmp_root/custom.events")" = $'start PROTO-A-001\nstart PROTO-B-001\nfinish PROTO-A-001\nfinish PROTO-B-001\nstart PROTO-C-001\nfinish PROTO-C-001' || fail 'custom wave barrier is wrong'

repo=$(make_repo replaced-leader-pane)
output=$(FAKE_TMUX_MODE=replaced run_batch "$repo" --mode serial "$tmp_root/list.plan")
assert_contains "$output" 'leader_pane_recovered=PROTO-A-001 old=%42 new=%77'
assert_contains "$output" 'batch_status=complete'

repo=$(make_repo dead-leader-pane)
if output=$(FAKE_TMUX_MODE=dead run_batch "$repo" --mode serial "$tmp_root/list.plan" 2>&1); then fail 'true leader death unexpectedly advanced'; fi
assert_contains "$output" 'no live exact-cwd leader pane for PROTO-A-001 in omc-qs-proto-a-001'
assert_contains "$output" 'recovery_command=./scripts/finish-omc-task PROTO-A-001'

repo=$(make_repo multiple-leader-panes)
if output=$(FAKE_TMUX_MODE=multiple run_batch "$repo" --mode serial "$tmp_root/list.plan" 2>&1); then fail 'ambiguous replacement leader unexpectedly advanced'; fi
assert_contains "$output" 'multiple live exact-cwd leader panes for PROTO-A-001 in omc-qs-proto-a-001'
assert_contains "$output" 'recovery_command=./scripts/finish-omc-task PROTO-A-001'

repo=$(make_repo terminal-failure)
if output=$(FAKE_STATUS_FAIL_TEAM=team-proto-b-001 run_batch "$repo" --mode custom "$tmp_root/custom.plan" 2>&1); then fail 'terminal failure unexpectedly advanced'; fi
assert_contains "$output" 'team reached terminal failure phase failed'
assert_contains "$output" 'recovery_command=./scripts/finish-omc-task PROTO-A-001'
test "$(<"$tmp_root/terminal-failure.events")" = $'start PROTO-A-001\nstart PROTO-B-001' || fail 'terminal failure started or finished another wave'

repo=$(make_repo finish-failure)
if output=$(FAKE_FINISH_FAIL_TASK=PROTO-A-001 run_batch "$repo" --mode serial "$tmp_root/list.plan" 2>&1); then fail 'finisher failure unexpectedly advanced'; fi
assert_contains "$output" 'finisher failed for PROTO-A-001'
assert_contains "$output" 'recovery_command=./scripts/finish-omc-task PROTO-A-001'
test "$(<"$tmp_root/finish-failure.events")" = $'start PROTO-A-001\nfinish PROTO-A-001' || fail 'finisher failure advanced to another Task'

printf 'PASS run-omc-task-batch serial parallel custom pane recovery wave barriers failures\n'
