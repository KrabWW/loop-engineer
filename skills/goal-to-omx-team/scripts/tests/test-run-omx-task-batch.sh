#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd "$(dirname "$0")" && pwd -P)
source_runner=$(cd "$test_dir/.." && pwd -P)/run-omx-task-batch
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/run-omx-task-batch.XXXXXX")
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

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'resume_existing=0' \
    'allow_derived_ready=0' \
    'while [[ "${1:-}" = --* ]]; do' \
    '  case "$1" in' \
    '    --resume-existing) resume_existing=1 ;;' \
    '    --allow-derived-ready) allow_derived_ready=1 ;;' \
    '    *) printf "unknown option: %s\n" "$1" >&2; exit 2 ;;' \
    '  esac' \
    '  shift' \
    'done' \
    '[ "$allow_derived_ready" -eq 1 ] || { printf "missing derived-ready\n" >&2; exit 2; }' \
    'task=${1:?}' \
    'slug=$(printf "%s" "$task" | tr "[:upper:]_" "[:lower:]-")' \
    'worktree="${FAKE_BATCH_ROOT:?}/worktrees/$slug"' \
    'finished="${FAKE_BATCH_ROOT:?}/finished-$slug"' \
    'if [ -e "$finished" ]; then' \
    '  [ "$resume_existing" -eq 1 ] || { printf "Task already finished: %s\n" "$task" >&2; exit 18; }' \
    '  printf "skip %s\n" "$task" >> "${FAKE_BATCH_EVENTS:?}"' \
    '  printf "mode=already-finished\ntask_id=%s\nmain_after=%s\n" "$task" "$(git rev-parse HEAD)"' \
    '  exit 0' \
    'fi' \
    'mkdir -p "$worktree/.omx/context"' \
    'team="team-$slug"' \
    'if [ "${FAKE_DELAY_FINAL_EVIDENCE_TEAM:-}" != "$team" ]; then' \
    '  printf "%s\n" "- Final HEAD: \`0000000000000000000000000000000000000000\`" > "$worktree/.omx/context/${slug}-final-evidence.md"' \
    'fi' \
    'state="${FAKE_BATCH_ROOT:?}/started-$slug"' \
    'if [ -e "$state" ]; then' \
    '  [ "$resume_existing" -eq 1 ] || { printf "branch already exists: codex/qs-%s\n" "$slug" >&2; exit 17; }' \
    '  mode=resumed' \
    '  event=resume' \
    'else' \
    '  : > "$state"' \
    '  mode=started' \
    '  event=start' \
    'fi' \
    'printf "%s %s\n" "$event" "$task" >> "${FAKE_BATCH_EVENTS:?}"' \
    'printf "mode=%s\ntask_id=%s\ntask_file=docs/tasks/%s.md\nbranch=codex/qs-%s\nworktree=%s\ntmux_session=qs-%s\nleader_pane=%%42\nteam_name=team-%s\n" "$mode" "$task" "$task" "$slug" "$worktree" "$slug" "$slug"' > "$fake_bin/start"
  chmod +x "$fake_bin/start"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'task=${1:?}' \
    'printf "finish %s\n" "$task" >> "${FAKE_BATCH_EVENTS:?}"' \
    '[ "${FAKE_FINISH_FAIL_TASK:-}" != "$task" ] || { printf "finish failed\n" >&2; exit 19; }' \
    'git commit --allow-empty -qm "finish $task"' \
    'slug=$(printf "%s" "$task" | tr "[:upper:]_" "[:lower:]-")' \
    'rm -f "${FAKE_BATCH_ROOT:?}/started-$slug"' \
    ': > "${FAKE_BATCH_ROOT:?}/finished-$slug"' \
    'printf "mode=finished\nmain_after=%s\n" "$(git rev-parse HEAD)"' > "$fake_bin/finish"
  chmod +x "$fake_bin/finish"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '[ "${1:-}" = team ] || exit 2' \
    'operation=${2:-}' \
    'team=${3:-}' \
    'case "$operation" in' \
    '  status)' \
    '    if [ "${FAKE_STATUS_FAIL_TEAM:-}" = "$team" ]; then' \
    '      printf "{\"status\":\"ok\",\"phase\":\"failed\",\"workers\":{\"dead\":0,\"non_reporting\":0},\"tasks\":{\"total\":1,\"pending\":0,\"blocked\":0,\"in_progress\":0,\"completed\":0,\"failed\":1}}\n"' \
    '    elif [ "${FAKE_STATUS_UNHEALTHY_TEAM:-}" = "$team" ]; then' \
    '      printf "{\"status\":\"ok\",\"phase\":\"team-exec\",\"workers\":{\"dead\":1,\"non_reporting\":0},\"tasks\":{\"total\":1,\"pending\":1,\"blocked\":0,\"in_progress\":0,\"completed\":0,\"failed\":0}}\n"' \
    '    elif [ "${FAKE_STATUS_TRANSIENT_TEAM:-}" = "$team" ] && [ ! -e "${FAKE_BATCH_ROOT:?}/healthy-$team" ]; then' \
    '      : > "${FAKE_BATCH_ROOT:?}/healthy-$team"' \
    '      printf "{\"status\":\"ok\",\"phase\":\"team-exec\",\"workers\":{\"dead\":1,\"non_reporting\":0},\"tasks\":{\"total\":1,\"pending\":1,\"blocked\":0,\"in_progress\":0,\"completed\":0,\"failed\":0}}\n"' \
    '    else' \
    '      printf "{\"status\":\"ok\",\"phase\":\"complete\",\"workers\":{\"dead\":0,\"non_reporting\":0},\"tasks\":{\"total\":1,\"pending\":0,\"blocked\":0,\"in_progress\":0,\"completed\":1,\"failed\":0}}\n"' \
    '    fi' \
    '    ;;' \
    '  await)' \
    '    if [ "${FAKE_DELAY_FINAL_EVIDENCE_TEAM:-}" = "$team" ] && [ ! -e ".omx/context/${team#team-}-final-evidence.md" ]; then' \
    '      printf "evidence-ready %s\n" "$team" >> "${FAKE_BATCH_EVENTS:?}"' \
    '      printf "%s\n" "- Final HEAD: \`0000000000000000000000000000000000000000\`" > ".omx/context/${team#team-}-final-evidence.md"' \
    '    fi' \
    '    printf "{\"status\":\"ok\",\"event\":null}\n"' \
    '    ;;' \
    '  *) exit 2 ;;' \
    'esac' > "$fake_bin/omx"
  chmod +x "$fake_bin/omx"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case "${1:-}" in' \
    '  display-message)' \
    '    shift; [ "${1:-}" = -p ] && shift; [ "${1:-}" = -t ] && shift; pane=${1:?}; shift' \
    '    [ "${1:-}" = "#{pane_dead}" ] || exit 2' \
    '    case "${FAKE_TMUX_MODE:-stable}" in' \
    '      stable|leader-with-hud) [ "$pane" = %42 ] || exit 1 ;;' \
    '      replaced|multiple|dead) [ "$pane" != %42 ] || exit 1; [ "$pane" = %77 ] || [ "$pane" = %78 ] || exit 1 ;;' \
    '      reused) [ "$pane" = %42 ] || [ "$pane" = %77 ] || exit 1 ;;' \
    '      *) exit 2 ;;' \
    '    esac' \
    '    printf "0\n"' \
    '    ;;' \
    '  list-panes)' \
    '    shift; [ "${1:-}" = -a ] && shift; [ "${1:-}" = -F ] && shift; format=${1:?}' \
    '    [ "$format" = "#{pane_id}|#{session_name}|#{pane_dead}|#{pane_current_path}|#{pane_start_command}" ] || exit 2' \
    '    for worktree in "${FAKE_BATCH_ROOT:?}"/worktrees/*; do' \
    '      [ -d "$worktree" ] || continue' \
    '      slug=$(basename "$worktree"); session=qs-$slug' \
    '      case "${FAKE_TMUX_MODE:-stable}" in' \
    '        stable) printf "%%42|%s|0|%s|omx exec leader\n" "$session" "$worktree" ;;' \
    '        leader-with-hud) printf "%%42|%s|0|%s|omx exec leader\n%%47|%s|0|%s|env OMX_TMUX_HUD_OWNER=1 omx hud --watch\n" "$session" "$worktree" "$session" "$worktree" ;;' \
    '        replaced) printf "%%77|%s|0|%s|omx exec leader\n" "$session" "$worktree" ;;' \
    '        reused) printf "%%42|%s|0|%s/.omx/team/foreign|foreign\n%%77|%s|0|%s|omx exec leader\n" "$session" "$worktree" "$session" "$worktree" ;;' \
    '        multiple) printf "%%77|%s|0|%s|omx exec leader\n%%78|%s|0|%s|shell\n" "$session" "$worktree" "$session" "$worktree" ;;' \
    '        dead) printf "%%77|%s|0|%s/.omx/team/worker-1|worker\n" "$session" "$worktree" ;;' \
    '        *) exit 2 ;;' \
    '      esac' \
    '    done' \
    '    ;;' \
    '  *) exit 2 ;;' \
    'esac' > "$fake_bin/tmux"
  chmod +x "$fake_bin/tmux"
}

make_repo() {
  name=$1
  repo="$tmp_root/$name"
  mkdir -p "$repo/scripts"
  cp "$source_runner" "$repo/scripts/run-omx-task-batch"
  chmod +x "$repo/scripts/run-omx-task-batch"
  git -C "$repo" init -b main -q
  git -C "$repo" config user.name 'Batch Test'
  git -C "$repo" config user.email batch@example.invalid
  printf '.omx/\n' > "$repo/.gitignore"
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
      FAKE_STATUS_UNHEALTHY_TEAM="${FAKE_STATUS_UNHEALTHY_TEAM:-}" \
      FAKE_STATUS_TRANSIENT_TEAM="${FAKE_STATUS_TRANSIENT_TEAM:-}" \
      FAKE_DELAY_FINAL_EVIDENCE_TEAM="${FAKE_DELAY_FINAL_EVIDENCE_TEAM:-}" \
      FAKE_FINISH_FAIL_TASK="${FAKE_FINISH_FAIL_TASK:-}" \
      FAKE_TMUX_MODE="${FAKE_TMUX_MODE:-stable}" \
      OMX_TASK_STARTER="$tmp_root/fake-bin/start" \
      OMX_TASK_FINISHER="$tmp_root/fake-bin/finish" \
      OMX_BIN="$tmp_root/fake-bin/omx" \
      TMUX_BIN="$tmp_root/fake-bin/tmux" \
      OMX_BATCH_AWAIT_MS=1 \
      OMX_BATCH_FINALIZATION_POLL_SECONDS=0 \
      OMX_BATCH_UNHEALTHY_GRACE_SECONDS=1 \
      ./scripts/run-omx-task-batch "$@"
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
test "$(<"$tmp_root/parallel.events")" = $'start PROTO-A-001\nstart PROTO-B-001\nfinish PROTO-A-001\nfinish PROTO-B-001\nstart PROTO-C-001\nfinish PROTO-C-001' || fail 'parallel chunking or merge serialization is wrong'

repo=$(make_repo custom)
output=$(run_batch "$repo" --mode custom "$tmp_root/custom.plan")
assert_contains "$output" 'batch_status=complete'
test "$(<"$tmp_root/custom.events")" = $'start PROTO-A-001\nstart PROTO-B-001\nfinish PROTO-A-001\nfinish PROTO-B-001\nstart PROTO-C-001\nfinish PROTO-C-001' || fail 'custom wave barrier is wrong'

repo=$(make_repo replaced-leader-pane)
output=$(FAKE_TMUX_MODE=replaced run_batch "$repo" --mode serial "$tmp_root/list.plan")
assert_contains "$output" 'leader_pane_recovered=PROTO-A-001 old=%42 new=%77'
assert_contains "$output" 'batch_status=complete'

repo=$(make_repo leader-with-hud)
output=$(FAKE_TMUX_MODE=leader-with-hud run_batch "$repo" --mode serial "$tmp_root/list.plan")
assert_contains "$output" 'batch_status=complete'

repo=$(make_repo delayed-final-evidence)
output=$(FAKE_DELAY_FINAL_EVIDENCE_TEAM=team-proto-a-001 run_batch "$repo" --mode serial "$tmp_root/list.plan")
assert_contains "$output" 'task_finalization_wait=PROTO-A-001'
test "$(<"$tmp_root/delayed-final-evidence.events")" = $'start PROTO-A-001\nevidence-ready team-proto-a-001\nfinish PROTO-A-001\nstart PROTO-B-001\nfinish PROTO-B-001\nstart PROTO-C-001\nfinish PROTO-C-001' || fail 'batch did not wait for leader final evidence before finishing'

repo=$(make_repo reused-leader-pane)
output=$(FAKE_TMUX_MODE=reused run_batch "$repo" --mode serial "$tmp_root/list.plan")
assert_contains "$output" 'leader_pane_recovered=PROTO-A-001 old=%42 new=%77'
assert_contains "$output" 'batch_status=complete'

repo=$(make_repo dead-leader-pane)
if output=$(FAKE_TMUX_MODE=dead run_batch "$repo" --mode serial "$tmp_root/list.plan" 2>&1); then fail 'true leader death unexpectedly advanced'; fi
assert_contains "$output" 'no live exact-cwd leader pane for PROTO-A-001 in qs-proto-a-001'
assert_contains "$output" 'recovery_command=./scripts/finish-omx-task PROTO-A-001'

repo=$(make_repo multiple-leader-panes)
if output=$(FAKE_TMUX_MODE=multiple run_batch "$repo" --mode serial "$tmp_root/list.plan" 2>&1); then fail 'ambiguous replacement leader unexpectedly advanced'; fi
assert_contains "$output" 'multiple live exact-cwd leader panes for PROTO-A-001 in qs-proto-a-001'
assert_contains "$output" 'recovery_command=./scripts/finish-omx-task PROTO-A-001'

repo=$(make_repo terminal-failure)
if output=$(FAKE_STATUS_FAIL_TEAM=team-proto-b-001 run_batch "$repo" --mode custom "$tmp_root/custom.plan" 2>&1); then fail 'terminal failure unexpectedly advanced'; fi
assert_contains "$output" 'team reached terminal failure phase failed'
assert_contains "$output" 'recovery_command=./scripts/finish-omx-task PROTO-A-001'
test "$(<"$tmp_root/terminal-failure.events")" = $'start PROTO-A-001\nstart PROTO-B-001' || fail 'terminal failure started or finished another wave'

repo=$(make_repo transient-worker-health)
output=$(FAKE_STATUS_TRANSIENT_TEAM=team-proto-a-001 run_batch "$repo" --mode serial "$tmp_root/list.plan")
assert_contains "$output" 'task_health_wait=PROTO-A-001'
assert_contains "$output" 'batch_status=complete'

repo=$(make_repo persistent-worker-death)
if output=$(FAKE_STATUS_UNHEALTHY_TEAM=team-proto-a-001 run_batch "$repo" --mode serial "$tmp_root/list.plan" 2>&1); then fail 'persistent worker death unexpectedly advanced'; fi
assert_contains "$output" 'team worker health did not recover within 1 seconds for PROTO-A-001'

repo=$(make_repo finish-failure)
if output=$(FAKE_FINISH_FAIL_TASK=PROTO-A-001 run_batch "$repo" --mode serial "$tmp_root/list.plan" 2>&1); then fail 'finisher failure unexpectedly advanced'; fi
assert_contains "$output" 'finisher failed for PROTO-A-001'
assert_contains "$output" 'recovery_command=./scripts/finish-omx-task PROTO-A-001'
test "$(<"$tmp_root/finish-failure.events")" = $'start PROTO-A-001\nfinish PROTO-A-001' || fail 'finisher failure advanced to another Task'

output=$(run_batch "$repo" --mode serial "$tmp_root/list.plan")
assert_contains "$output" 'task_resumed=PROTO-A-001 wave=1'
assert_contains "$output" 'batch_status=complete'
test "$(<"$tmp_root/finish-failure.events")" = $'resume PROTO-A-001\nfinish PROTO-A-001\nstart PROTO-B-001\nfinish PROTO-B-001\nstart PROTO-C-001\nfinish PROTO-C-001' || fail 'rerun did not resume the interrupted Task before continuing'

output=$(run_batch "$repo" --mode serial "$tmp_root/list.plan")
assert_contains "$output" 'task_already_finished=PROTO-A-001 wave=1'
assert_contains "$output" 'task_already_finished=PROTO-B-001 wave=2'
assert_contains "$output" 'task_already_finished=PROTO-C-001 wave=3'
assert_contains "$output" 'batch_status=complete'
test "$(<"$tmp_root/finish-failure.events")" = $'skip PROTO-A-001\nskip PROTO-B-001\nskip PROTO-C-001' || fail 'rerun did not skip Tasks already merged into main'

printf 'PASS run-omx-task-batch serial parallel custom resume pane recovery wave barriers failures\n'
