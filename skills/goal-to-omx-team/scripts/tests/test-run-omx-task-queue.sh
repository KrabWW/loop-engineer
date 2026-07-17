#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd "$(dirname "$0")" && pwd -P)
source_runner=$(cd "$test_dir/.." && pwd -P)/run-omx-task-queue
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/omx-task-queue.XXXXXX")
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  printf '%s\n' "$1" | rg -F -- "$2" >/dev/null || fail "missing output: $2"
}

make_fixture() {
  name=$1
  repo="$tmp_root/$name"
  mkdir -p "$repo/docs/tasks/contracts" "$repo/scripts" "$repo/fake-bin"
  cp "$source_runner" "$repo/scripts/run-omx-task-queue"
  chmod +x "$repo/scripts/run-omx-task-queue"

  for task in PROTO-ONE-001 PROTO-TWO-001; do
    cat > "$repo/docs/tasks/contracts/$task.md" <<EOF
# $task fixture

- Status: \`blocked\`
- Depends on: none

## Allowed Files

- \`docs/tasks/contracts/$task.md\`
- \`${task}.result\`
EOF
  done

  cat > "$repo/scripts/start-omx-task" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = --allow-derived-ready ] || { printf 'missing derived-ready flag\n' >&2; exit 2; }
task=${2:?}
printf '%s\n' "$task" >> "${FAKE_START_LOG:?}"
[ "${FAKE_START_FAIL_TASK:-}" != "$task" ] || exit 17
root=$(git rev-parse --show-toplevel)
slug=$(printf '%s' "$task" | tr '[:upper:]_' '[:lower:]-')
branch="codex/qs-$slug"
worktree="$(dirname "$root")/$(basename "$root")-task-worktrees/$slug"
session="qs-$slug"
team="team-$slug"
mkdir -p "$(dirname "$worktree")"
git worktree add -q -b "$branch" "$worktree" main
task_file=$(rg -l --glob '*.md' -- "^# $task( |$)" "$worktree/docs/tasks")
perl -0pi -e 's/- Status: `blocked`/- Status: `done`/' "$task_file"
printf '%s\n' "$task" > "$worktree/$task.result"
git -C "$worktree" add .
git -C "$worktree" commit -qm "complete $task"
mkdir -p "${FAKE_TMUX_STATE:?}"
: > "${FAKE_TMUX_STATE}/$session"
mkdir -p "${FAKE_TMUX_STATE}/panes"
printf '%s\n' "$session" > "${FAKE_TMUX_STATE}/panes/${FAKE_LEADER_PANE:?}"
if [ "${FAKE_DIVERGE_TASK:-}" = "$task" ]; then
  printf '%s\n' diverged > "$root/diverged.txt"
  git -C "$root" add diverged.txt
  git -C "$root" commit -qm 'diverge main'
fi
printf 'mode=started\n'
printf 'task_id=%s\n' "$task"
printf 'task_file=%s\n' "${task_file#"$worktree/"}"
printf 'branch=%s\n' "$branch"
printf 'worktree=%s\n' "$worktree"
printf 'tmux_session=%s\n' "$session"
printf 'leader_pane=%s\n' "$FAKE_LEADER_PANE"
printf 'team_name=%s\n' "$team"
EOF
  chmod +x "$repo/scripts/start-omx-task"

  cat > "$repo/scripts/finish-omx-task" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
task=${1:?}
root=$(git rev-parse --show-toplevel)
slug=$(printf '%s' "$task" | tr '[:upper:]_' '[:lower:]-')
branch="codex/qs-$slug"
worktree="$(dirname "$root")/$(basename "$root")-task-worktrees/$slug"
session="qs-$slug"
if [ "${FAKE_STATUS_MODE:-success}" = shutdown-failed ]; then
  printf 'team shutdown failed\n' >&2
  exit 23
fi
if [ "${FAKE_TMUX_KILL_MODE:-success}" = fail-live ]; then
  printf 'tmux session remains after cleanup: %s\n' "$session" >&2
  exit 24
fi
printf 'team-%s\n' "$slug" >> "${FAKE_SHUTDOWN_LOG:?}"
rm -f "${FAKE_TMUX_STATE:?}/$session"
for pane in "${FAKE_TMUX_STATE}/panes"/*; do
  [ -f "$pane" ] || continue
  [ "$(cat "$pane")" != "$session" ] || rm -f "$pane"
done
git -C "$worktree" rebase --rebase-merges main >/dev/null
git merge --ff-only "$branch" >/dev/null
git worktree remove "$worktree" >/dev/null
git branch -d "$branch" >/dev/null
printf 'mode=finished\n'
printf 'main_after=%s\n' "$(git rev-parse HEAD)"
EOF
  chmod +x "$repo/scripts/finish-omx-task"

  cat > "$repo/fake-bin/omx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = team ] || exit 2
[ "${OMX_AUTO_UPDATE:-}" = 0 ] || { printf 'OMX_AUTO_UPDATE must be 0\n' >&2; exit 19; }
[ "${OMX_ROOT:-}" = "$PWD" ] || { printf 'OMX_ROOT must equal cwd\n' >&2; exit 20; }
case "${2:-}" in
  await)
    if [ "${FAKE_STATUS_MODE:-success}" = never-complete ]; then
      sleep 0.1
    fi
    : > "${FAKE_AWAIT_STATE:?}"
    printf '{"status":"event","cursor":"1","event":{"type":"worker_state_changed"}}\n'
    ;;
  status)
    if [ "${FAKE_STATUS_MODE:-success}" = failed ]; then
      printf '{"status":"ok","phase":"failed","workers":{"dead":0,"non_reporting":0},"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":0,"completed":0,"failed":1}}\n'
    elif [ "${FAKE_STATUS_MODE:-success}" = cancelled ]; then
      printf '{"status":"ok","phase":"cancelled","workers":{"dead":0,"non_reporting":0},"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":0,"completed":1,"failed":0}}\n'
    elif [ "${FAKE_STATUS_MODE:-success}" = non-reporting ]; then
      printf '{"status":"ok","phase":"complete","workers":{"dead":0,"non_reporting":1},"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":0,"completed":1,"failed":0}}\n'
    elif [ "${FAKE_STATUS_MODE:-success}" = await-once ] && [ ! -f "${FAKE_AWAIT_STATE:?}" ]; then
      printf '{"status":"ok","phase":"team-exec","workers":{"dead":0,"non_reporting":0},"tasks":{"total":1,"pending":1,"blocked":0,"in_progress":0,"completed":0,"failed":0}}\n'
    elif [ "${FAKE_STATUS_MODE:-success}" = verify-once ] && [ ! -f "${FAKE_AWAIT_STATE:?}" ]; then
      printf '{"status":"ok","phase":"team-verify","workers":{"dead":0,"non_reporting":0},"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":0,"completed":1,"failed":0}}\n'
    elif [ "${FAKE_STATUS_MODE:-success}" = dead ]; then
      printf '{"status":"ok","phase":"team-exec","workers":{"dead":1,"non_reporting":0},"tasks":{"total":1,"pending":1,"blocked":0,"in_progress":0,"completed":0,"failed":0}}\n'
    elif [ "${FAKE_STATUS_MODE:-success}" = blocked ]; then
      printf '{"status":"ok","phase":"team-exec","workers":{"dead":0,"non_reporting":0},"tasks":{"total":1,"pending":0,"blocked":1,"in_progress":0,"completed":0,"failed":0}}\n'
    elif [ "${FAKE_STATUS_MODE:-success}" = invalid-json ]; then
      printf 'not-json\n'
    elif [ "${FAKE_STATUS_MODE:-success}" = leader-dies ]; then
      rm -f "${FAKE_TMUX_STATE:?}/panes/${FAKE_LEADER_PANE:?}"
      printf '{"status":"ok","phase":"complete","workers":{"dead":0,"non_reporting":0},"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":0,"completed":1,"failed":0}}\n'
    elif [ "${FAKE_STATUS_MODE:-success}" = never-complete ]; then
      printf '{"status":"ok","phase":"team-exec","workers":{"dead":0,"non_reporting":0},"tasks":{"total":1,"pending":1,"blocked":0,"in_progress":0,"completed":0,"failed":0}}\n'
    else
      printf '{"status":"ok","phase":"complete","workers":{"dead":0,"non_reporting":0},"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":0,"completed":1,"failed":0}}\n'
    fi
    ;;
  shutdown)
    [ "${FAKE_STATUS_MODE:-success}" != shutdown-failed ] || { printf 'fake shutdown failed\n' >&2; exit 23; }
    printf '%s\n' "${3:?}" >> "${FAKE_SHUTDOWN_LOG:?}"
    ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$repo/fake-bin/omx"

  cat > "$repo/fake-bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  has-session)
    shift
    [ "${1:-}" = -t ] && shift
    [ -f "${FAKE_TMUX_STATE:?}/${1:?}" ]
    ;;
  kill-session)
    shift
    [ "${1:-}" = -t ] && shift
    session=${1:?}
    [ "${FAKE_TMUX_KILL_MODE:-success}" != fail-live ] || exit 24
    rm -f "${FAKE_TMUX_STATE:?}/$session"
    for pane in "${FAKE_TMUX_STATE}/panes"/*; do
      [ -f "$pane" ] || continue
      [ "$(cat "$pane")" != "$session" ] || rm -f "$pane"
    done
    ;;
  display-message)
    shift
    [ "${1:-}" = -p ] && shift
    [ "${1:-}" = -t ] && shift
    pane=${1:?}
    shift
    [ "${1:-}" = '#{pane_dead}' ] || exit 3
    [ -f "${FAKE_TMUX_STATE:?}/panes/$pane" ] || exit 1
    printf '0\n'
    ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$repo/fake-bin/tmux"

  cat > "$repo/fake-bin/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${FAKE_DATE_MODE:-real}" = deadline-after-one ] && [ "${1:-}" = +%s ]; then
  count=0
  [ ! -f "${FAKE_DATE_COUNTER:?}" ] || count=$(cat "$FAKE_DATE_COUNTER")
  printf '%s\n' "$((count + 1))" > "$FAKE_DATE_COUNTER"
  if [ "$count" -lt 2 ]; then printf '1000\n'; else printf '1002\n'; fi
  exit 0
fi
exec /bin/date "$@"
EOF
  chmod +x "$repo/fake-bin/date"

  git -C "$repo" init -b main -q
  printf '.omx/\n' >> "$repo/.git/info/exclude"
  git -C "$repo" config user.name 'Queue Test'
  git -C "$repo" config user.email queue-test@example.invalid
  git -C "$repo" add .
  git -C "$repo" commit -qm 'fixture'
  printf '%s\n' "$repo"
}

run_queue_process() {
  repo=$1
  shift
  mkdir -p "${repo}-tmux"
  cd "$repo"
  exec env \
      PATH="$repo/fake-bin:$PATH" \
      OMX_BIN="$repo/fake-bin/omx" \
      TMUX_BIN="$repo/fake-bin/tmux" \
      OMX_TASK_STARTER="$repo/scripts/start-omx-task" \
      OMX_TASK_FINISHER="$repo/scripts/finish-omx-task" \
      OMX_QUEUE_AWAIT_MS=1 \
      OMX_QUEUE_DURATION_SECONDS="${OMX_QUEUE_DURATION_SECONDS:-3600}" \
      FAKE_START_LOG="${repo}-start.log" \
      FAKE_SHUTDOWN_LOG="${repo}-shutdown.log" \
      FAKE_TMUX_STATE="${repo}-tmux" \
      FAKE_TMUX_KILL_MODE="${FAKE_TMUX_KILL_MODE:-success}" \
      FAKE_LEADER_PANE='%42' \
      FAKE_STATUS_MODE="${FAKE_STATUS_MODE:-success}" \
      FAKE_AWAIT_STATE="${repo}-await-state" \
      FAKE_DATE_MODE="${FAKE_DATE_MODE:-real}" \
      FAKE_DATE_COUNTER="${repo}-date-counter" \
      FAKE_DIVERGE_TASK="${FAKE_DIVERGE_TASK:-}" \
      ./scripts/run-omx-task-queue "$@"
}

run_queue() {
  (run_queue_process "$@")
}

repo=$(make_fixture success)
printf '%s\n' PROTO-ONE-001 PROTO-TWO-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
output=$(run_queue "$repo" --hours 12 --finish-current queue.txt)
assert_contains "$output" 'queue_status=complete'
test "$(git -C "$repo" branch --list 'codex/qs-*' | wc -l | tr -d ' ')" -eq 0 || fail 'success branches remain'
test "$(git -C "$repo" worktree list --porcelain | rg -c '^worktree ')" -eq 1 || fail 'success worktrees remain'
test -f "$repo/PROTO-ONE-001.result" || fail 'first result not merged'
test -f "$repo/PROTO-TWO-001.result" || fail 'second result not merged'
test "$(cat "${repo}-start.log")" = $'PROTO-ONE-001\nPROTO-TWO-001' || fail 'queue order changed'
test "$(wc -l < "${repo}-shutdown.log" | tr -d ' ')" -eq 2 || fail 'teams not shut down'

repo=$(make_fixture dry-run)
printf '%s\n' PROTO-ONE-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
output=$(run_queue "$repo" --dry-run --hours 12 queue.txt)
assert_contains "$output" 'queue_status=dry-run'
test ! -e "${repo}-start.log" || fail 'dry-run started a task'

repo=$(make_fixture await-once)
printf '%s\n' PROTO-ONE-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
output=$(FAKE_STATUS_MODE=await-once run_queue "$repo" --hours 12 queue.txt)
assert_contains "$output" 'queue_status=complete'
test -f "${repo}-await-state" || fail 'queue did not await an in-progress team'

repo=$(make_fixture verify-once)
printf '%s\n' PROTO-ONE-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
output=$(FAKE_STATUS_MODE=verify-once run_queue "$repo" --hours 12 queue.txt)
assert_contains "$output" 'queue_status=complete'
test -f "${repo}-await-state" || fail 'queue advanced before phase=complete'

repo=$(make_fixture deadline)
printf '%s\n' PROTO-ONE-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
output=$(OMX_QUEUE_DURATION_SECONDS=0 run_queue "$repo" --hours 12 queue.txt)
assert_contains "$output" 'queue_status=deadline'
test ! -e "${repo}-start.log" || fail 'deadline started a task'

repo=$(make_fixture finish-current)
printf '%s\n' PROTO-ONE-001 PROTO-TWO-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
output=$(OMX_QUEUE_DURATION_SECONDS=1 FAKE_DATE_MODE=deadline-after-one run_queue "$repo" --hours 12 --finish-current queue.txt)
assert_contains "$output" 'queue_status=deadline'
assert_contains "$output" 'completed=1'
test -f "$repo/PROTO-ONE-001.result" || fail 'active Task did not finish after deadline'
test ! -f "$repo/PROTO-TWO-001.result" || fail 'new Task started after deadline'
test "$(cat "${repo}-start.log")" = 'PROTO-ONE-001' || fail 'queue advanced after deadline'

repo=$(make_fixture team-failed)
printf '%s\n' PROTO-ONE-001 PROTO-TWO-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
if output=$(FAKE_STATUS_MODE=failed run_queue "$repo" --hours 12 queue.txt 2>&1); then
  fail 'failed team advanced the queue'
fi
assert_contains "$output" 'team reported failed tasks'
test -d "$tmp_root/team-failed-task-worktrees/proto-one-001" || fail 'failed worktree removed'
test "$(cat "${repo}-start.log")" = 'PROTO-ONE-001' || fail 'queue advanced after failure'

repo=$(make_fixture diverged)
printf '%s\n' PROTO-ONE-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
output=$(FAKE_DIVERGE_TASK=PROTO-ONE-001 run_queue "$repo" --hours 12 queue.txt)
assert_contains "$output" 'queue_status=complete'
test -f "$repo/PROTO-ONE-001.result" || fail 'finisher did not rebase and merge after main advanced'
test ! -d "$tmp_root/diverged-task-worktrees/proto-one-001" || fail 'rebased worktree remains'

repo=$(make_fixture non-reporting)
printf '%s\n' PROTO-ONE-001 PROTO-TWO-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
if output=$(FAKE_STATUS_MODE=non-reporting run_queue "$repo" --hours 12 queue.txt 2>&1); then
  fail 'non-reporting worker advanced the queue'
fi
assert_contains "$output" 'team reported non-reporting workers'
test -d "$tmp_root/non-reporting-task-worktrees/proto-one-001" || fail 'non-reporting worktree removed'
test "$(cat "${repo}-start.log")" = 'PROTO-ONE-001' || fail 'queue advanced after non-reporting worker'

for mode in cancelled dead blocked invalid-json leader-dies shutdown-failed; do
  repo=$(make_fixture "$mode")
  printf '%s\n' PROTO-ONE-001 PROTO-TWO-001 > "$repo/queue.txt"
  git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
  if output=$(FAKE_STATUS_MODE="$mode" run_queue "$repo" --hours 12 queue.txt 2>&1); then
    fail "$mode advanced the queue"
  fi
  test -d "$tmp_root/${mode}-task-worktrees/proto-one-001" || fail "$mode worktree removed"
  test "$(cat "${repo}-start.log")" = 'PROTO-ONE-001' || fail "queue advanced after $mode"
done

repo=$(make_fixture interrupt)
printf '%s\n' PROTO-ONE-001 PROTO-TWO-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
output_file="${repo}-interrupt-output.log"
FAKE_STATUS_MODE=never-complete run_queue_process "$repo" --hours 12 queue.txt > "$output_file" 2>&1 &
queue_pid=$!
for (( attempt = 0; attempt < 100; attempt += 1 )); do
  [ -f "$output_file" ] && rg -F 'task_started=PROTO-ONE-001' "$output_file" >/dev/null && break
  sleep 0.05
done
[ -f "$output_file" ] && rg -F 'task_started=PROTO-ONE-001' "$output_file" >/dev/null || fail 'interrupt queue never started'
kill -TERM "$queue_pid"
set +e
wait "$queue_pid"
interrupt_rc=$?
set -e
[ "$interrupt_rc" -eq 130 ] || fail "interrupt exit code was $interrupt_rc"
output=$(cat "$output_file")
assert_contains "$output" 'queue interrupted; active resources were preserved'
assert_contains "$output" 'recovery_task=PROTO-ONE-001'
assert_contains "$output" 'recovery_worktree='
assert_contains "$output" 'recovery_team=team-proto-one-001'
assert_contains "$output" 'recovery_tmux_session=qs-proto-one-001'
assert_contains "$output" 'recovery_leader_pane=%42'
test -d "$tmp_root/interrupt-task-worktrees/proto-one-001" || fail 'interrupt worktree removed'
test "$(cat "${repo}-start.log")" = 'PROTO-ONE-001' || fail 'queue advanced after interrupt'

repo=$(make_fixture tmux-kill-failed)
printf '%s\n' PROTO-ONE-001 PROTO-TWO-001 > "$repo/queue.txt"
git -C "$repo" add queue.txt && git -C "$repo" commit -qm 'add queue'
if output=$(FAKE_TMUX_KILL_MODE=fail-live run_queue "$repo" --hours 12 queue.txt 2>&1); then
  fail 'live tmux session survived cleanup and queue still advanced'
fi
assert_contains "$output" 'tmux session remains after cleanup'
test -f "${repo}-tmux/qs-proto-one-001" || fail 'tmux failure did not preserve session evidence'
test -d "$tmp_root/tmux-kill-failed-task-worktrees/proto-one-001" || fail 'tmux failure removed worktree'
test ! -f "$repo/PROTO-ONE-001.result" || fail 'tmux failure integrated task into main'
test "$(cat "${repo}-start.log")" = 'PROTO-ONE-001' || fail 'queue advanced after tmux cleanup failure'

printf 'PASS run-omx-task-queue success dry-run await verify deadline finish-current failure divergence worker-health leader-liveness shutdown interrupt tmux-cleanup\n'
