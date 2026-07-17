#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd "$(dirname "$0")" && pwd -P)
source_launcher=$(cd "$test_dir/.." && pwd -P)/start-omc-task
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/start-omc-task.XXXXXX")
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

output_value() {
  key=$1
  content=$2
  printf '%s\n' "$content" | sed -n "s/^${key}=//p" | tail -1
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
    : > "${FAKE_OMC_RAN:?}"
    printf '%s\n' "$@" > "${FAKE_OMC_LAUNCH_CAPTURE:?}"
    prompt=${!#}
    printf '%s\n' "$prompt" > "${FAKE_OMC_PROMPT_CAPTURE:?}"
    if [ "${FAKE_OMC_MODE:-success}" = fail ]; then printf 'fake leader failure\n' >&2; exit 7; fi
    if [ "${FAKE_OMC_MODE:-success}" = exit-before-state ]; then exit 0; fi
    workers=$(printf '%s\n' "$prompt" | sed -n 's/.*omc team \([0-9][0-9]*\):claude:executor.*/\1/p')
    [ -n "$workers" ] || { printf 'fake leader could not find atomic team command\n' >&2; exit 9; }
    base=${OMC_STATE_DIR:?}
    team_dir="$base/fake-project/state/team/fake-team"
    mkdir -p "$team_dir/workers/worker-1"
    : > "$team_dir/workers/worker-1/.ready"
    printf '{"worker":"worker-1","ts":0}\n' > "$team_dir/workers/worker-1/heartbeat.json"
    exit 0
    ;;
  team)
    sub=${2:-}
    case "$sub" in
      api)
        op=${3:-}
        input=
        while [ "$#" -gt 0 ]; do case "$1" in --input) input=$2; break ;; esac; shift; done
        [ -n "$input" ] || { printf 'fake omc api missing --input\n' >&2; exit 2; }
        name=$(printf '%s\n' "$input" | sed -n 's/.*"team_name":"\([^"]*\)".*/\1/p')
        base=${OMC_STATE_DIR:?}
        team_dir="$base/fake-project/state/team/$name"
        case "$op" in
          get-summary)
            if [ ! -d "$team_dir/workers" ]; then printf '{"ok":false,"operation":"get-summary","data":{}}\n'; exit 0; fi
            printf '{"ok":true,"operation":"get-summary","data":{"summary":{"teamName":"%s","workerCount":1,"tasks":{"total":1,"pending":0,"blocked":0,"in_progress":1,"completed":0,"failed":0},"workers":[{"name":"worker-1","alive":true}],"nonReportingWorkers":[]}}}\n' "$name"
            ;;
          read-worker-status)
            [ -d "$team_dir/workers" ] || exit 1
            printf '{"ok":true,"data":{"worker":"worker-1","status":{"state":"idle","updated_at":"2026-07-17T00:00:00.000Z"}}}\n'
            ;;
          read-worker-heartbeat)
            [ -d "$team_dir/workers" ] || exit 1
            printf '{"ok":true,"data":{"worker":"worker-1","heartbeat":{"ts":%s}}}\n' "$(date +%s)"
            ;;
          *) printf 'unexpected fake omc api op: %s\n' "$op" >&2; exit 2 ;;
        esac
        ;;
      shutdown)
        name=${3:-}
        base=${OMC_STATE_DIR:?}
        rm -rf "$base"/fake-project/state/team/"$name" 2>/dev/null || true
        printf 'shutdown complete\n'
        ;;
      *) printf 'unexpected fake omc team subcommand: %s\n' "$sub" >&2; exit 2 ;;
    esac
    ;;
  *) printf 'unexpected fake omc command: %s\n' "${1:-}" >&2; exit 2 ;;
esac
OMC_FAKE
  chmod +x "$fake_bin/omc"

  cat > "$fake_bin/tmux" <<'TMUX_FAKE'
#!/usr/bin/env bash
set -euo pipefail
state=${FAKE_TMUX_STATE:?}
mkdir -p "$state/sessions" "$state/panes" "$state/commands" "$state/dimensions"
case "${1:-}" in
  -V) printf 'tmux fake\n' ;;
  has-session)
    shift; [ "${1:-}" = -t ] && shift; [ -f "$state/sessions/${1:?}" ]
    ;;
  list-sessions)
    for file in "$state/sessions"/*; do [ -f "$file" ] && basename "$file"; done
    ;;
  new-session)
    shift; session=; cwd=; print_info=0; format=; columns=; rows=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -d) shift ;;
        -P) print_info=1; shift ;;
        -F) format=$2; shift 2 ;;
        -s) session=$2; shift 2 ;;
        -c) cwd=$2; shift 2 ;;
        -x) columns=$2; shift 2 ;;
        -y) rows=$2; shift 2 ;;
        *) break ;;
      esac
    done
    : "${session:?}" "${cwd:?}"
    [ "$#" -eq 1 ] || { printf 'fake tmux expected one shell command\n' >&2; exit 3; }
    printf '%s\n' "$1" > "$state/commands/$session"
    printf '%sx%s\n' "$columns" "$rows" > "$state/dimensions/$session"
    : > "$state/sessions/$session"
    leader_pane=%42
    printf '%s\n' "$session" > "$state/panes/$leader_pane"
    if [ "${FAKE_TMUX_MODE:-run}" = timeout ]; then [ "$print_info" -eq 0 ] || printf '%s\n' "$leader_pane"; exit 0; fi
    set +e
    (cd "$cwd" && bash -c "$1")
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then rm -f "$state/sessions/$session" "$state/panes/$leader_pane"; fi
    if [ "${FAKE_OMC_MODE:-success}" = exit-before-state ] || [ "${FAKE_OMC_MODE:-success}" = exit-after-state ]; then rm -f "$state/panes/$leader_pane"; fi
    [ "$print_info" -eq 0 ] || { [ "$format" = "#{pane_id}" ] || exit 4; printf '%s\n' "$leader_pane"; }
    exit 0
    ;;
  display-message)
    shift; [ "${1:-}" = -p ] && shift; [ "${1:-}" = -t ] && shift; pane=${1:?}; shift
    [ "${1:-}" = "#{pane_dead}" ] || exit 5
    [ -f "$state/panes/$pane" ] || exit 1
    printf '0\n'
    ;;
  kill-session)
    shift; [ "${1:-}" = -t ] && shift; session=${1:?}; rm -f "$state/sessions/$session"
    for pane_file in "$state/panes"/*; do [ -f "$pane_file" ] || continue; read -r pane_session < "$pane_file"; [ "$pane_session" != "$session" ] || rm -f "$pane_file"; done
    ;;
  attach)
    exit 0
    ;;
  *) printf 'unexpected fake tmux command: %s\n' "${1:-}" >&2; exit 2 ;;
esac
TMUX_FAKE
  chmod +x "$fake_bin/tmux"
}

make_fixture() {
  fixture_name=$1
  task_status=${2:-ready}
  dependency_status=${3:-done}
  repo="$tmp_root/$fixture_name"
  mkdir -p "$repo/docs/tasks/contracts" "$repo/scripts"
  cp "$source_launcher" "$repo/scripts/start-omc-task"
  chmod +x "$repo/scripts/start-omc-task"
  {
    printf '# DEP-001 prerequisite\n\n'
    printf -- '- Status: `%s`\n' "$dependency_status"
    printf -- '- Depends on: none\n\n'
    printf '## Goal\n\nFreeze the prerequisite.\n'
  } > "$repo/docs/tasks/contracts/DEP-001.md"
  {
    printf '# PROTO-SAMPLE-001 sample task\n\n'
    printf -- '- Status: `%s`\n' "$task_status"
    printf -- '- Depends on: `DEP-001`\n\n'
    printf '## Goal\n\nFreeze a deterministic sample protocol.\n'
    printf '\n## Allowed Files\n\n'
    printf -- '- `docs/tasks/contracts/PROTO-SAMPLE-001.md`\n'
  } > "$repo/docs/tasks/contracts/PROTO-SAMPLE-001.md"
  {
    printf '# BE-SAMPLE-001 sample backend task\n\n'
    printf -- '- Status: `%s`\n' "$task_status"
    printf -- '- Depends on: `DEP-001`\n\n'
    printf '## Goal\n\nImplement one deterministic backend result.\n'
    printf '\n## Allowed Files\n\n'
    printf -- '- `docs/tasks/contracts/BE-SAMPLE-001.md`\n'
  } > "$repo/docs/tasks/contracts/BE-SAMPLE-001.md"
  git -C "$repo" init -b main -q
  printf 'refer/\n' > "$repo/.gitignore"
  mkdir -p "$repo/refer"
  printf 'read-only reference\n' > "$repo/refer/reference.txt"
  printf '.omc/\n' >> "$repo/.git/info/exclude"
  git -C "$repo" config user.name 'Launcher Test'
  git -C "$repo" config user.email launcher-test@example.invalid
  git -C "$repo" add .
  git -C "$repo" commit -qm 'test fixture'
  printf '%s\n' "$repo"
}

run_launcher() {
  repo=$1
  shift
  fake_bin="$tmp_root/fake-bin"
  fake_state="${repo}-fake-tmux"
  mkdir -p "$fake_state"
  sentinel="$tmp_root/fake-omc-ran"
  rm -f "$sentinel"
  (
    cd "$repo"
    export PATH="$fake_bin:$PATH"
    FAKE_TMUX_STATE="$fake_state" \
      FAKE_TMUX_MODE="${FAKE_TMUX_MODE:-run}" \
      FAKE_OMC_MODE="${FAKE_OMC_MODE:-success}" \
      FAKE_OMC_RAN="$sentinel" \
      FAKE_OMC_PROMPT_CAPTURE="${repo}-fake-omc-prompt" \
      FAKE_OMC_LAUNCH_CAPTURE="${repo}-fake-omc-launch" \
      OMC_BIN="$fake_bin/omc" \
      TMUX_BIN="$fake_bin/tmux" \
      OMC_MIN_FREE_KIB=1 \
      OMC_START_TIMEOUT_SECONDS=2 \
      ./scripts/start-omc-task "$@"
  )
}

make_fake_bins "$tmp_root/fake-bin"

repo=$(make_fixture success)
output=$(run_launcher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=started'
assert_contains "$output" 'team_name=fake-team'
assert_contains "$output" 'leader_pane=%42'
assert_contains "$output" "base_commit=$(git -C "$repo" rev-parse main)"
assert_contains "$output" 'branch=codex/omc-qs-proto-sample-001'
assert_contains "$output" 'tmux_session=omc-qs-proto-sample-001'
assert_contains "$output" 'workers=1'
assert_contains "$output" 'finish=./scripts/finish-omc-task PROTO-SAMPLE-001'
success_worktree=$(cd "$tmp_root/success-task-worktrees/omc-proto-sample-001" && pwd -P)
assert_contains "$output" "worktree=$success_worktree"
success_base=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/omc-task-state/proto-sample-001
assert_contains "$output" "state_base=$success_base"
assert_contains "$output" 'get-summary --input'
prompt=$(<"${repo}-fake-omc-prompt")
assert_contains "$prompt" 'PROTO-SAMPLE-001: act as the persistent Claude leader'
assert_contains "$prompt" 'Authoritative task file: docs/tasks/contracts/PROTO-SAMPLE-001.md'
assert_contains "$prompt" 'omc team 1:claude:executor --auto-merge --no-decompose "Execute PROTO-SAMPLE-001 from docs/tasks/contracts/PROTO-SAMPLE-001.md as one atomic delivery with committed worker evidence held READY_FOR_LEADER_REVIEW until leader approval"'
assert_contains "$prompt" 'Never modify refer/'
assert_contains "$prompt" 'operator will run ./scripts/finish-omc-task PROTO-SAMPLE-001'
launch_args=$(<"${repo}-fake-omc-launch")
assert_contains "$launch_args" 'launch'
assert_contains "$launch_args" '--madmax'
assert_contains "$launch_args" '--notify'
assert_contains "$launch_args" 'false'
leader_command=$(<"${repo}-fake-tmux/commands/omc-qs-proto-sample-001")
assert_contains "$leader_command" 'exec'
assert_contains "$leader_command" 'OMC_RUNTIME_V2=1'
assert_contains "$leader_command" 'OMC_STATE_DIR='
assert_contains "$leader_command" 'OMC_TEAM_WORKTREE_MODE=branch'
assert_contains "$leader_command" 'OMC_TEAM_NO_RC=1'
assert_contains "$leader_command" '--madmax'
[ "$(<"${repo}-fake-tmux/dimensions/omc-qs-proto-sample-001")" = '240x60' ] || fail 'OMC leader tmux session did not reserve a wide startup surface'
if printf '%s\n' "$leader_command" | rg -F -- 'omx ' >/dev/null; then
  fail 'OMC leader launch unexpectedly used omx'
fi
test -f "$tmp_root/fake-omc-ran" || fail 'sentinel: fake omc was not invoked (real omc may have been reached)'
test -d "$tmp_root/success-task-worktrees/omc-proto-sample-001" || fail 'success worktree missing'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/omc-qs-proto-sample-001 || fail 'success branch missing'
test -f "${repo}-fake-tmux/sessions/omc-qs-proto-sample-001" || fail 'success tmux session missing'
test -f "${repo}-fake-tmux/panes/%42" || fail 'success leader pane missing'
launch_state="$success_base/launch.json"
test -f "$launch_state" || fail 'success did not record launch state'
rg -n '"derived_ready": false|"refer_fingerprint": "[0-9a-f]{64}"|"refer_fingerprint_version": "content-v2"' "$launch_state" >/dev/null || fail 'launch state omitted derived-ready, refer baseline, or version'
test -z "$(git -C "$tmp_root/success-task-worktrees/omc-proto-sample-001" status --porcelain)" || fail 'success worktree is dirty'
summary_missing=$(cd "$repo" && OMC_STATE_DIR="$repo/.git/omc-task-state/wrong-slug" "$tmp_root/fake-bin/omc" team api get-summary --input '{"team_name":"fake-team"}' --json)
assert_contains "$summary_missing" '"ok":false'
(cd "$success_worktree" && OMC_RUNTIME_V2=1 OMC_STATE_DIR="$success_base" OMC_TEAM_WORKTREE_MODE=branch "$tmp_root/fake-bin/omc" team shutdown fake-team >/dev/null)
FAKE_TMUX_STATE="${repo}-fake-tmux" "$tmp_root/fake-bin/tmux" kill-session -t omc-qs-proto-sample-001
test ! -f "${repo}-fake-tmux/sessions/omc-qs-proto-sample-001" || fail 'success cleanup left tmux session'
test ! -f "${repo}-fake-tmux/panes/%42" || fail 'success cleanup left leader pane'

repo=$(make_fixture dry-run)
output=$(run_launcher "$repo" --dry-run PROTO-SAMPLE-001)
assert_contains "$output" 'mode=dry-run'
assert_contains "$output" 'result=no resources created'
assert_contains "$output" 'workers=1'
test ! -e "$tmp_root/dry-run-task-worktrees/omc-proto-sample-001" || fail 'dry-run created worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/omc-qs-proto-sample-001 && fail 'dry-run created branch'
test ! -f "${repo}-fake-tmux/sessions/omc-qs-proto-sample-001" || fail 'dry-run created tmux session'
output=$(run_launcher "$repo" --dry-run BE-SAMPLE-001)
assert_contains "$output" 'workers=1'
assert_contains "$output" 'launch=persistent Claude leader -> omc team 1:claude:executor --auto-merge --no-decompose <atomic-task>'

repo=$(make_fixture stable-refer-fingerprint)
mkdir -p "$repo/refer/nested"
output=$(run_launcher "$repo" --dry-run PROTO-SAMPLE-001)
fingerprint_before=$(output_value refer_fingerprint "$output")
test -n "$fingerprint_before" || fail 'dry-run omitted refer fingerprint'
touch -t 202001010000 "$repo/refer/reference.txt"
mkdir -p "$repo/refer/nested/.git" "$repo/refer/nested/.omc/state"
printf 'volatile git metadata\n' > "$repo/refer/nested/.git/index"
printf 'volatile omc state\n' > "$repo/refer/nested/.omc/state/runtime.json"
printf 'finder metadata\n' > "$repo/refer/.DS_Store"
output=$(run_launcher "$repo" --dry-run PROTO-SAMPLE-001)
fingerprint_after_metadata=$(output_value refer_fingerprint "$output")
test "$fingerprint_after_metadata" = "$fingerprint_before" || fail 'refer fingerprint changed for mtime or ignored runtime metadata'
printf 'protected content changed\n' >> "$repo/refer/reference.txt"
output=$(run_launcher "$repo" --dry-run PROTO-SAMPLE-001)
fingerprint_after_content=$(output_value refer_fingerprint "$output")
test "$fingerprint_after_content" != "$fingerprint_before" || fail 'refer fingerprint ignored protected content change'

repo=$(make_fixture dependency-blocked ready ready)
if output=$(run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'dependency-blocked launch unexpectedly succeeded'
fi
assert_contains "$output" 'dependency DEP-001 must be done'
test ! -e "$tmp_root/dependency-blocked-task-worktrees/omc-proto-sample-001" || fail 'dependency failure created worktree'

repo=$(make_fixture derived-ready blocked done)
if output=$(run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'blocked manual launch unexpectedly succeeded without derived-ready gate'
fi
assert_contains "$output" 'status must be ready'
output=$(run_launcher "$repo" --allow-derived-ready PROTO-SAMPLE-001)
assert_contains "$output" 'mode=started'
assert_contains "$output" 'derived_ready=true'
derived_base=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/omc-task-state/proto-sample-001
rg -n '"derived_ready": true' "$derived_base/launch.json" >/dev/null || fail 'derived launch state not recorded'
assert_contains "$(<"${repo}-fake-omc-prompt")" 'commit the legal Task status transition from blocked to ready before any other Task write'

repo=$(make_fixture dirty)
printf 'dirty\n' > "$repo/untracked.txt"
if output=$(run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'dirty launch unexpectedly succeeded'
fi
assert_contains "$output" 'main worktree is not clean'
test ! -e "$tmp_root/dirty-task-worktrees/omc-proto-sample-001" || fail 'dirty failure created worktree'

repo=$(make_fixture duplicate)
git -C "$repo" branch codex/omc-qs-proto-sample-001
if output=$(run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'duplicate launch unexpectedly succeeded'
fi
assert_contains "$output" 'branch already exists'
test ! -e "$tmp_root/duplicate-task-worktrees/omc-proto-sample-001" || fail 'duplicate failure created worktree'

repo=$(make_fixture locked)
mkdir "$repo/.git/start-omc-task.lock"
if output=$(run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'locked launch unexpectedly succeeded'
fi
assert_contains "$output" 'another start-omc-task preflight is active or stale'
test ! -e "$tmp_root/locked-task-worktrees/omc-proto-sample-001" || fail 'lock failure created worktree'

repo=$(make_fixture launch-failed)
if output=$(FAKE_OMC_MODE=fail run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'OMC failure unexpectedly succeeded'
fi
assert_contains "$output" 'persistent Claude leader exited before creating OMC team state'
test ! -e "$tmp_root/launch-failed-task-worktrees/omc-proto-sample-001" || fail 'pre-team failure left worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/omc-qs-proto-sample-001 && fail 'pre-team failure left branch'
test ! -f "${repo}-fake-tmux/sessions/omc-qs-proto-sample-001" || fail 'pre-team failure left session'

repo=$(make_fixture leader-exited-after-state)
if output=$(FAKE_OMC_MODE=exit-after-state run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'leader-exited-after-state launch unexpectedly succeeded'
fi
assert_contains "$output" 'persistent Claude leader exited after OMC team state appeared'
test -d "$tmp_root/leader-exited-after-state-task-worktrees/omc-proto-sample-001" || fail 'post-state leader exit removed recovery worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/omc-qs-proto-sample-001 || fail 'post-state leader exit removed recovery branch'
test -f "${repo}-fake-tmux/sessions/omc-qs-proto-sample-001" || fail 'post-state leader exit did not retain worker-backed session'
test ! -f "${repo}-fake-tmux/panes/%42" || fail 'post-state leader exit retained dead leader pane'

repo=$(make_fixture leader-exited-before-state-with-session)
if output=$(FAKE_OMC_MODE=exit-before-state run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'leader-exited-before-state-with-session launch unexpectedly succeeded'
fi
assert_contains "$output" 'leader pane exited before OMC team state appeared while omc-qs-proto-sample-001 still has panes'
test -d "$tmp_root/leader-exited-before-state-with-session-task-worktrees/omc-proto-sample-001" || fail 'live-session leader exit removed recovery worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/omc-qs-proto-sample-001 || fail 'live-session leader exit removed recovery branch'
test -f "${repo}-fake-tmux/sessions/omc-qs-proto-sample-001" || fail 'live-session leader exit removed recovery session'
test ! -f "${repo}-fake-tmux/panes/%42" || fail 'live-session leader exit retained dead leader pane'

repo=$(make_fixture timeout)
if output=$(FAKE_TMUX_MODE=timeout run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'OMC timeout unexpectedly succeeded'
fi
assert_contains "$output" 'persistent Claude leader did not produce a ready OMC team within 2 seconds'
assert_contains "$output" 'mode=recovery-required'
test -d "$tmp_root/timeout-task-worktrees/omc-proto-sample-001" || fail 'timeout removed recovery worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/omc-qs-proto-sample-001 || fail 'timeout removed recovery branch'
test -f "${repo}-fake-tmux/sessions/omc-qs-proto-sample-001" || fail 'timeout removed recovery session'
timeout_base=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/omc-task-state/proto-sample-001
rg -n '"leader_pane": "%42"' "$timeout_base/launch.json" >/dev/null || fail 'timeout launch state omitted the recoverable leader pane'

printf 'PASS start-omc-task persistent-leader stable-refer-fingerprint cwd-cleanup dry-run dependency dirty duplicate lock failure timeout\n'
