#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd "$(dirname "$0")" && pwd -P)
bundle=$(cd "$test_dir/.." && pwd -P)
source_launcher="$bundle/start-omc-task"
source_status="$bundle/status-omc-task"
source_tmux_shim="$bundle/omc-runtime-bin/tmux"
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/status-omc-task.XXXXXX")
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
  cat > "$fake_bin/omc" <<'OMC_FAKE'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  -V|--version) printf 'fake omc 0.0\n'; exit 0 ;;
  doctor) exit 0 ;;
  launch)
    printf '%s\n' "$@" > "${FAKE_OMC_LAUNCH_CAPTURE:?}"
    prompt=${!#}
    workers=$(printf '%s\n' "$prompt" | sed -n 's/.*omc team \([0-9][0-9]*\):claude:executor.*/\1/p')
    [ -n "$workers" ] || exit 9
    base=${OMC_STATE_DIR:?}
    team_dir="$base/fake-project/state/team/fake-team"
    mkdir -p "$team_dir/workers/worker-1"
    : > "$team_dir/workers/worker-1/.ready"
    printf '{"worker":"worker-1","ts":%s}\n' "$(date +%s)" > "$team_dir/workers/worker-1/heartbeat.json"
    exit 0
    ;;
  team)
    sub=${2:-}
    case "$sub" in
      api)
        op=${3:-}
        input=
        while [ "$#" -gt 0 ]; do case "$1" in --input) input=$2; break ;; esac; shift; done
        name=$(printf '%s\n' "$input" | sed -n 's/.*"team_name":"\([^"]*\)".*/\1/p')
        base=${OMC_STATE_DIR:?}
        team_dir="$base/fake-project/state/team/$name"
        case "$op" in
          get-summary)
            if [ ! -d "$team_dir/workers" ]; then printf '{"ok":false,"operation":"get-summary","data":{}}\n'; exit 0; fi
            if [ -f "$team_dir/unregistered" ]; then printf '{"ok":false,"operation":"get-summary","error":{"code":"team_not_found"}}\n'; exit 0; fi
            if [ -f "$team_dir/terminal" ]; then
              printf '{"ok":true,"data":{"summary":{"teamName":"%s","workerCount":1,"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":0,"completed":1,"failed":0},"workers":[{"name":"worker-1","alive":true}],"nonReportingWorkers":[]}}}\n' "$name"
            else
              printf '{"ok":true,"data":{"summary":{"teamName":"%s","workerCount":1,"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":1,"completed":0,"failed":0},"workers":[{"name":"worker-1","alive":true}],"nonReportingWorkers":[]}}}\n' "$name"
            fi
            ;;
          read-worker-status) printf '{"ok":true,"data":{"worker":"worker-1","status":{"state":"idle"}}}\n' ;;
          read-worker-heartbeat) printf '{"ok":true,"data":{"worker":"worker-1","heartbeat":%s}}\n' "$(cat "$team_dir/workers/worker-1/heartbeat.json")" ;;
          *) exit 2 ;;
        esac
        ;;
      shutdown)
        name=${3:-}; base=${OMC_STATE_DIR:?}
        rm -rf "$base"/fake-project/state/team/"$name" 2>/dev/null || true
        printf 'shutdown complete\n'
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
state=${FAKE_TMUX_STATE:?}
mkdir -p "$state/sessions" "$state/panes" "$state/commands"
case "${1:-}" in
  -V) printf 'tmux fake\n' ;;
  has-session) shift; [ "${1:-}" = -t ] && shift; [ -f "$state/sessions/${1:?}" ] ;;
  list-sessions) for f in "$state/sessions"/*; do [ -f "$f" ] && basename "$f"; done ;;
  new-session)
    shift; session=; cwd=; print_info=0; format=
    while [ "$#" -gt 0 ]; do case "$1" in -d) shift;; -P) print_info=1; shift;; -F) format=$2; shift 2;; -x|-y) shift 2;; -s) session=$2; shift 2;; -c) cwd=$2; shift 2;; *) break;; esac; done
    printf '%s\n' "$1" > "$state/commands/$session"
    : > "$state/sessions/$session"
    leader_pane=%42
    printf '%s\n' "$session" > "$state/panes/$leader_pane"
    set +e; (cd "$cwd" && bash -c "$1"); rc=$?; set -e
    [ "$rc" -ne 0 ] && rm -f "$state/sessions/$session" "$state/panes/$leader_pane"
    [ "$print_info" -eq 0 ] || { [ "$format" = "#{pane_id}" ] || exit 4; printf '%s\n' "$leader_pane"; }
    exit 0 ;;
  display-message) shift; [ "${1:-}" = -p ] && shift; [ "${1:-}" = -t ] && shift; pane=${1:?}; [ -f "$state/panes/$pane" ] || exit 1; printf '0\n' ;;
  capture-pane) printf 'claude ready\n' ;;
  send-keys) exit 0 ;;
  set-window-option|resize-window) exit 0 ;;
  kill-session) shift; [ "${1:-}" = -t ] && shift; session=${1:?}; rm -f "$state/sessions/$session"; for pf in "$state/panes"/*; do [ -f "$pf" ] || continue; read -r ps < "$pf"; [ "$ps" != "$session" ] || rm -f "$pf"; done ;;
  attach) exit 0 ;;
  *) exit 2 ;;
esac
TMUX_FAKE
  chmod +x "$fake_bin/tmux"
}

make_fixture() {
  fixture_name=$1
  repo="$tmp_root/$fixture_name"
  mkdir -p "$repo/docs/tasks/contracts" "$repo/scripts/omc-runtime-bin"
  cp "$source_launcher" "$repo/scripts/start-omc-task"
  cp "$source_status" "$repo/scripts/status-omc-task"
  cp "$source_tmux_shim" "$repo/scripts/omc-runtime-bin/tmux"
  chmod +x "$repo/scripts/start-omc-task" "$repo/scripts/status-omc-task" "$repo/scripts/omc-runtime-bin/tmux"
  printf '# DEP-001\n\n- Status: `done`\n- Depends on: none\n\n## Goal\n\nx.\n' > "$repo/docs/tasks/contracts/DEP-001.md"
  printf '# PROTO-SAMPLE-001\n\n- Status: `ready`\n- Depends on: `DEP-001`\n\n## Goal\n\nx.\n\n## Allowed Files\n\n- `docs/tasks/contracts/PROTO-SAMPLE-001.md`\n' > "$repo/docs/tasks/contracts/PROTO-SAMPLE-001.md"
  git -C "$repo" init -b main -q
  printf 'refer/\n' > "$repo/.gitignore"; mkdir -p "$repo/refer"; echo ref > "$repo/refer/reference.txt"
  printf '.omc/\n' >> "$repo/.git/info/exclude"
  git -C "$repo" config user.name t; git -C "$repo" config user.email t@t
  git -C "$repo" add .; git -C "$repo" commit -qm init
  printf '%s\n' "$repo"
}

run_in() {
  repo=$1; shift
  fake_bin="$tmp_root/fake-bin"
  fake_state="${repo}-fake-tmux"
  mkdir -p "$fake_state"
  (
    cd "$repo"
    export PATH="$fake_bin:$PATH"
    FAKE_TMUX_STATE="$fake_state" FAKE_OMC_MODE="${FAKE_OMC_MODE:-success}" \
      FAKE_OMC_PROMPT_CAPTURE="${repo}-p" FAKE_OMC_LAUNCH_CAPTURE="${repo}-l" \
      OMC_BIN="$fake_bin/omc" TMUX_BIN="$fake_bin/tmux" \
      OMC_MIN_FREE_KIB=1 OMC_START_TIMEOUT_SECONDS=2 \
      "$@"
  )
}

make_fake_bins "$tmp_root/fake-bin"

# --- success: start then status ---
repo=$(make_fixture started)
run_in "$repo" ./scripts/start-omc-task PROTO-SAMPLE-001 >/dev/null
base=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/omc-task-state/proto-sample-001
before=$(find "$base" -type f | sort | md5)
output=$(run_in "$repo" ./scripts/status-omc-task PROTO-SAMPLE-001); rc=$?
[ "$rc" -eq 0 ] || fail "status exited $rc on a fresh running team"
assert_contains "$output" 'team_name=fake-team'
assert_contains "$output" 'phase=active'
assert_contains "$output" 'leader_alive=true'
assert_contains "$output" 'heartbeat=fresh'
assert_contains "$output" 'workers_total=1 alive=1 dead=0 non_reporting=0'
assert_contains "$output" 'attach=tmux attach -t omc-qs-proto-sample-001'
assert_contains "$output" 'finish=./scripts/finish-omc-task PROTO-SAMPLE-001'
assert_contains "$output" "state_base=$base"
after=$(find "$base" -type f | sort | md5)
[ "$before" = "$after" ] || fail 'status mutated team state'

# --- duplicate state layouts must not trip pipefail/SIGPIPE (exit 141) ---
repo=$(make_fixture duplicate-layout)
run_in "$repo" ./scripts/start-omc-task PROTO-SAMPLE-001 >/dev/null
dbase=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/omc-task-state/proto-sample-001
for index in $(seq 1 1200); do
  mkdir -p "$dbase/duplicate-layout-${index}/state/team/fake-team/workers"
done
mkdir -p "$tmp_root/duplicate-layout-task-worktrees/omc-proto-sample-001/.omc/state/team/fake-team/workers"
set +e
output=$(run_in "$repo" ./scripts/status-omc-task PROTO-SAMPLE-001 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "status should tolerate duplicate state layouts without SIGPIPE, got ${rc}"
assert_contains "$output" 'team_name=fake-team'
assert_contains "$output" 'phase=active'

# --- no team ---
repo=$(make_fixture noteam)
if run_in "$repo" ./scripts/status-omc-task PROTO-SAMPLE-001 >/dev/null 2>&1; then
  fail 'status unexpectedly succeeded with no team state'
fi

# --- stale retry directory: select the unique queryable team, never newest mtime ---
repo=$(make_fixture stale-retry-team)
run_in "$repo" ./scripts/start-omc-task PROTO-SAMPLE-001 >/dev/null
mbase=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/omc-task-state/proto-sample-001
mkdir -p "$mbase/fake-project/state/team/second-team/workers/worker-1"
: > "$mbase/fake-project/state/team/second-team/workers/worker-1/.ready"
: > "$mbase/fake-project/state/team/second-team/unregistered"
rm -f "$mbase/launch.json"
set +e
output=$(run_in "$repo" ./scripts/status-omc-task PROTO-SAMPLE-001 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "status should select the unique queryable team, got ${rc}"
assert_contains "$output" 'team_name=fake-team'
assert_contains "$output" 'multiple OMC teams'

# --- multiple queryable teams remain ambiguous and must fail closed ---
repo=$(make_fixture multiple-live-teams)
run_in "$repo" ./scripts/start-omc-task PROTO-SAMPLE-001 >/dev/null
lbase=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/omc-task-state/proto-sample-001
mkdir -p "$lbase/fake-project/state/team/second-team/workers/worker-1"
: > "$lbase/fake-project/state/team/second-team/workers/worker-1/.ready"
rm -f "$lbase/launch.json"
if output=$(run_in "$repo" ./scripts/status-omc-task PROTO-SAMPLE-001 2>&1); then
  fail 'status unexpectedly guessed between multiple queryable teams'
fi
assert_contains "$output" 'multiple live OMC teams'

# --- stale heartbeat fail-closed (exit 2) ---
repo=$(make_fixture stale)
run_in "$repo" ./scripts/start-omc-task PROTO-SAMPLE-001 >/dev/null
sbase=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/omc-task-state/proto-sample-001
printf '{"worker":"worker-1","ts":1}\n' > "$sbase/fake-project/state/team/fake-team/workers/worker-1/heartbeat.json"
set +e
output=$(run_in "$repo" ./scripts/status-omc-task --freshness 300 PROTO-SAMPLE-001)
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "stale heartbeat should exit 2, got $rc"
assert_contains "$output" 'heartbeat=stale'

# --- --watch reaches terminal and exits 0 ---
repo=$(make_fixture watchterm)
run_in "$repo" ./scripts/start-omc-task PROTO-SAMPLE-001 >/dev/null
wbase=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/omc-task-state/proto-sample-001
: > "$wbase/fake-project/state/team/fake-team/terminal"
run_in "$repo" ./scripts/status-omc-task --watch --interval 1 PROTO-SAMPLE-001 >/dev/null; rc=$?
[ "$rc" -eq 0 ] || fail "--watch should exit 0 at complete, got $rc"

# --- --watch exits non-zero on derived failed phase ---
repo=$(make_fixture watchfail)
run_in "$repo" ./scripts/start-omc-task PROTO-SAMPLE-001 >/dev/null
fbase=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/omc-task-state/proto-sample-001
printf '{"ok":true,"data":{"summary":{"teamName":"fake-team","workerCount":1,"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":0,"completed":0,"failed":1},"workers":[{"name":"worker-1","alive":true}],"nonReportingWorkers":[]}}}\n' > "$fbase/forced-summary.json"
# override the fake to return the forced failed summary
cat > "$tmp_root/fake-bin/omc" <<'OMC_OVERRIDE'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  -V|--version) echo fake; exit 0 ;;
  team)
    sub=${2:-}; op=${3:-}
    case "$sub" in
      api)
        case "$op" in
          get-summary) cat "${OMC_STATE_DIR:?}/forced-summary.json" ;;
          read-worker-heartbeat) printf '{"ok":true,"data":{"worker":"worker-1","heartbeat":{"ts":%s}}}\n' "$(date +%s)" ;;
          *) exit 0 ;;
        esac ;;
      *) exit 0 ;;
    esac ;;
  *) exit 0 ;;
esac
OMC_OVERRIDE
chmod +x "$tmp_root/fake-bin/omc"
if run_in "$repo" ./scripts/status-omc-task --watch --interval 1 PROTO-SAMPLE-001 >/dev/null 2>&1; then
  fail '--watch should exit non-zero on failed phase'
fi

printf 'PASS status-omc-task discovery counts heartbeat liveness watch terminal stale\n'
