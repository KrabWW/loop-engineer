#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd "$(dirname "$0")" && pwd -P)
source_launcher=$(cd "$test_dir/.." && pwd -P)/start-omx-task
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/start-omx-task.XXXXXX")
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
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case "${1:-}" in' \
    '  doctor) printf "fake doctor ok\\n" ;;' \
    '  exec)' \
    '    printf "%s\\n" "$@" > "${FAKE_OMX_LAUNCH_CAPTURE:?}"' \
    '    prompt=${!#}' \
    '    printf "%s\\n" "$prompt" > "${FAKE_OMX_PROMPT_CAPTURE:?}"' \
    '    if [ "${FAKE_OMX_MODE:-success}" = fail ]; then printf "fake leader failure\\n" >&2; exit 7; fi' \
    '    if [ "${FAKE_OMX_MODE:-success}" = exit-before-state ]; then exit 0; fi' \
    '    workers=$(printf "%s\\n" "$prompt" | sed -n "s/.*omx team \\([0-9][0-9]*\\):executor.*/\\1/p")' \
    '    [ -n "$workers" ] || { printf "fake leader could not find atomic team command\\n" >&2; exit 9; }' \
    '    root=${OMX_ROOT:?}' \
    '    mkdir -p "$root/.omx/state/team/fake-team"' \
    '    printf "{\\\"workers\\\":%s}\\n" "$workers" > "$root/.omx/state/team/fake-team/config.json"' \
    '    : > "$root/.omx/fake-team-active"' \
    '    ;;' \
    '  team)' \
    '    operation=${2:-}' \
    '    name=${3:-}' \
    '    if [ "$name" != fake-team ] || [ "${OMX_ROOT:-}" != "$PWD" ] || [ ! -f "$PWD/.omx/fake-team-active" ]; then' \
    '      printf "{\\\"team_name\\\":\\\"%s\\\",\\\"status\\\":\\\"missing\\\"}\\n" "$name"' \
    '      exit 0' \
    '    fi' \
    '    workers=$(sed -n "s/.*\\\"workers\\\":\\([0-9][0-9]*\\).*/\\1/p" "$PWD/.omx/state/team/fake-team/config.json")' \
    '    case "$operation" in' \
    '      status)' \
    '        phase=${FAKE_OMX_TEAM_PHASE:-team-exec}' \
    '        if [ "$phase" = complete ]; then pending=0; completed=1; else pending=1; completed=0; fi' \
    '        printf "{\\\"team_name\\\":\\\"fake-team\\\",\\\"status\\\":\\\"ok\\\",\\\"phase\\\":\\\"%s\\\",\\\"workers\\\":{\\\"total\\\":%s,\\\"dead\\\":0,\\\"non_reporting\\\":0},\\\"tasks\\\":{\\\"total\\\":1,\\\"pending\\\":%s,\\\"blocked\\\":0,\\\"in_progress\\\":0,\\\"completed\\\":%s,\\\"failed\\\":0}}\\n" "$phase" "$workers" "$pending" "$completed"' \
    '        ;;' \
    '      await) printf "{\\\"team_name\\\":\\\"fake-team\\\",\\\"status\\\":\\\"ok\\\",\\\"event\\\":null}\\n" ;;' \
    '      shutdown) rm -rf "$PWD/.omx/state/team/fake-team" "$PWD/.omx/fake-team-active"; printf "shutdown complete\\n" ;;' \
    '      *) printf "unexpected fake team operation: %s\\n" "$operation" >&2; exit 2 ;;' \
    '    esac' \
    '    ;;' \
    '  *) printf "unexpected fake omx command: %s\\n" "${1:-}" >&2; exit 2 ;;' \
    'esac' > "$fake_bin/omx"
  chmod +x "$fake_bin/omx"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'state=${FAKE_TMUX_STATE:?}' \
    'mkdir -p "$state/sessions" "$state/panes" "$state/commands"' \
    'case "${1:-}" in' \
    '  -V) printf "tmux fake\\n" ;;' \
    '  has-session)' \
    '    shift; [ "${1:-}" = -t ] && shift; [ -f "$state/sessions/${1:?}" ]' \
    '    ;;' \
    '  list-sessions)' \
    '    for file in "$state/sessions"/*; do [ -f "$file" ] && basename "$file"; done' \
    '    ;;' \
    '  new-session)' \
    '    shift; session=; cwd=; print_info=0; format=' \
    '    while [ "$#" -gt 0 ]; do' \
    '      case "$1" in' \
    '        -d) shift ;;' \
    '        -P) print_info=1; shift ;;' \
    '        -F) format=$2; shift 2 ;;' \
    '        -s) session=$2; shift 2 ;;' \
    '        -c) cwd=$2; shift 2 ;;' \
    '        *) break ;;' \
    '      esac' \
    '    done' \
    '    : "${session:?}" "${cwd:?}"' \
    '    [ "$#" -eq 1 ] || { printf "fake tmux expected one shell command\\n" >&2; exit 3; }' \
    '    printf "%s\\n" "$1" > "$state/commands/$session"' \
    '    : > "$state/sessions/$session"' \
    '    leader_pane=%42' \
    '    printf "%s\\n%s\\n" "$session" "$cwd" > "$state/panes/$leader_pane"' \
    '    if [ "${FAKE_TMUX_MODE:-run}" = timeout ]; then [ "$print_info" -eq 0 ] || printf "%s\\n" "$leader_pane"; exit 0; fi' \
    '    set +e' \
    '    (cd "$cwd" && bash -c "$1")' \
    '    rc=$?' \
    '    set -e' \
    '    if [ "$rc" -ne 0 ]; then rm -f "$state/sessions/$session" "$state/panes/$leader_pane"; fi' \
    '    if [ "${FAKE_OMX_MODE:-success}" = exit-before-state ] || [ "${FAKE_OMX_MODE:-success}" = exit-after-state ]; then rm -f "$state/panes/$leader_pane"; fi' \
    '    [ "$print_info" -eq 0 ] || { [ "$format" = "#{pane_id}" ] || exit 4; printf "%s\\n" "$leader_pane"; }' \
    '    exit 0' \
    '    ;;' \
    '  new-window)' \
    '    shift; session=; cwd=; print_info=0; format=' \
    '    while [ "$#" -gt 0 ]; do' \
    '      case "$1" in' \
    '        -d) shift ;;' \
    '        -P) print_info=1; shift ;;' \
    '        -F) format=$2; shift 2 ;;' \
    '        -t) session=$2; shift 2 ;;' \
    '        -c) cwd=$2; shift 2 ;;' \
    '        *) printf "unexpected fake new-window arg: %s\\n" "$1" >&2; exit 3 ;;' \
    '      esac' \
    '    done' \
    '    : "${session:?}" "${cwd:?}"' \
    '    [ -f "$state/sessions/$session" ] || exit 1' \
    '    recovery_pane=%43' \
    '    printf "%s\\n%s\\n" "$session" "$cwd" > "$state/panes/$recovery_pane"' \
    '    [ "$print_info" -eq 0 ] || { [ "$format" = "#{pane_id}" ] || exit 4; printf "%s\\n" "$recovery_pane"; }' \
    '    ;;' \
    '  display-message)' \
    '    shift; [ "${1:-}" = -p ] && shift; [ "${1:-}" = -t ] && shift; pane=${1:?}; shift' \
    '    [ "${1:-}" = "#{pane_dead}" ] || exit 5' \
    '    [ -f "$state/panes/$pane" ] || exit 1' \
    '    printf "0\\n"' \
    '    ;;' \
    '  list-panes)' \
    '    shift; [ "${1:-}" = -a ] && shift; [ "${1:-}" = -F ] && shift; format=${1:?}' \
    '    [ "$format" = "#{pane_id}|#{session_name}|#{pane_dead}|#{pane_current_path}|#{pane_start_command}" ] || exit 5' \
    '    for pane_file in "$state/panes"/*; do' \
    '      [ -f "$pane_file" ] || continue' \
    '      pane_session=$(sed -n "1p" "$pane_file")' \
    '      pane_cwd=$(sed -n "2p" "$pane_file")' \
    '      pane_start=$(sed -n "3p" "$pane_file")' \
    '      [ -n "$pane_start" ] || pane_start="omx exec leader"' \
    '      printf "%s|%s|0|%s|%s\\n" "$(basename "$pane_file")" "$pane_session" "$pane_cwd" "$pane_start"' \
    '    done' \
    '    ;;' \
    '  kill-session)' \
    '    shift; [ "${1:-}" = -t ] && shift; session=${1:?}; rm -f "$state/sessions/$session"' \
    '    for pane_file in "$state/panes"/*; do [ -f "$pane_file" ] || continue; read -r pane_session < "$pane_file"; [ "$pane_session" != "$session" ] || rm -f "$pane_file"; done' \
    '    ;;' \
    '  attach)' \
    '    exit 0' \
    '    ;;' \
    '  *) printf "unexpected fake tmux command: %s\\n" "${1:-}" >&2; exit 2 ;;' \
    'esac' > "$fake_bin/tmux"
  chmod +x "$fake_bin/tmux"
}

make_fixture() {
  fixture_name=$1
  task_status=${2:-ready}
  dependency_status=${3:-done}
  repo="$tmp_root/$fixture_name"
  mkdir -p "$repo/docs/tasks/contracts" "$repo/scripts"
  cp "$source_launcher" "$repo/scripts/start-omx-task"
  chmod +x "$repo/scripts/start-omx-task"
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
  printf '.omx/\n' >> "$repo/.git/info/exclude"
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
  (
    cd "$repo"
    FAKE_TMUX_STATE="$fake_state" \
      FAKE_TMUX_MODE="${FAKE_TMUX_MODE:-run}" \
      FAKE_OMX_MODE="${FAKE_OMX_MODE:-success}" \
      FAKE_OMX_TEAM_PHASE="${FAKE_OMX_TEAM_PHASE:-team-exec}" \
      FAKE_OMX_PROMPT_CAPTURE="${repo}-fake-omx-prompt" \
      FAKE_OMX_LAUNCH_CAPTURE="${repo}-fake-omx-launch" \
      OMX_BIN="$fake_bin/omx" \
      TMUX_BIN="$fake_bin/tmux" \
      OMX_MIN_FREE_KIB=1 \
      OMX_START_TIMEOUT_SECONDS=2 \
      ./scripts/start-omx-task "$@"
  )
}

make_fake_bins "$tmp_root/fake-bin"

repo=$(make_fixture success)
output=$(run_launcher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=started'
assert_contains "$output" 'team_name=fake-team'
assert_contains "$output" 'leader_pane=%42'
assert_contains "$output" "base_commit=$(git -C "$repo" rev-parse main)"
assert_contains "$output" 'finish=./scripts/finish-omx-task PROTO-SAMPLE-001'
success_worktree=$(cd "$tmp_root/success-task-worktrees/proto-sample-001" && pwd -P)
assert_contains "$output" "(cd $success_worktree && OMX_AUTO_UPDATE=0 OMX_ROOT=$success_worktree omx team status fake-team --json)"
assert_contains "$output" "(cd $success_worktree && OMX_AUTO_UPDATE=0 OMX_ROOT=$success_worktree omx team await fake-team --timeout-ms 30000 --json)"
prompt=$(<"${repo}-fake-omx-prompt")
assert_contains "$prompt" 'PROTO-SAMPLE-001: act as the persistent Codex leader'
assert_contains "$prompt" 'Authoritative task file: docs/tasks/contracts/PROTO-SAMPLE-001.md'
assert_contains "$prompt" 'omx team 1:executor "Execute PROTO-SAMPLE-001 from docs/tasks/contracts/PROTO-SAMPLE-001.md as one atomic delivery with committed worker evidence held READY_FOR_LEADER_REVIEW until leader approval"'
assert_contains "$prompt" 'change existing Acceptance Criteria markers from unchecked to checked without editing their text, order, or count'
assert_contains "$prompt" 'Write the final evidence report to exactly .omx/context/proto-sample-001-final-evidence.md'
assert_contains "$prompt" "exactly one canonical bullet of the form '- Final HEAD: <full 40-character commit SHA in backticks>'"
assert_contains "$prompt" 'Never modify refer/'
assert_contains "$prompt" 'operator will run ./scripts/finish-omx-task PROTO-SAMPLE-001'
launch_args=$(<"${repo}-fake-omx-launch")
assert_contains "$launch_args" 'exec'
assert_contains "$launch_args" '--dangerously-bypass-approvals-and-sandbox'
if printf '%s\n' "$launch_args" | rg -F -- '--direct' >/dev/null; then
  fail 'non-interactive leader launch unexpectedly used --direct'
fi
leader_command=$(<"${repo}-fake-tmux/commands/qs-proto-sample-001")
assert_contains "$leader_command" 'OMX_AUTO_UPDATE=0'
test -d "$tmp_root/success-task-worktrees/proto-sample-001" || fail 'success worktree missing'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/qs-proto-sample-001 || fail 'success branch missing'
test -f "${repo}-fake-tmux/sessions/qs-proto-sample-001" || fail 'success tmux session missing'
test -f "${repo}-fake-tmux/panes/%42" || fail 'success leader pane missing'
launch_state="$success_worktree/.omx/context/proto-sample-001-launch.json"
test -f "$launch_state" || fail 'success did not record launch state'
rg -n '"derived_ready": false|"refer_fingerprint": "[0-9a-f]{64}"' "$launch_state" >/dev/null || fail 'launch state omitted derived-ready or refer baseline'
test -z "$(git -C "$tmp_root/success-task-worktrees/proto-sample-001" status --porcelain)" || fail 'success worktree is dirty'
main_status=$(cd "$repo" && OMX_ROOT="$repo" "$tmp_root/fake-bin/omx" team status fake-team --json)
assert_contains "$main_status" '"status":"missing"'
worktree_status=$(cd "$success_worktree" && OMX_ROOT="$success_worktree" "$tmp_root/fake-bin/omx" team status fake-team --json)
assert_contains "$worktree_status" '"status":"ok"'
resumed_output=$(run_launcher "$repo" --resume-existing --allow-derived-ready PROTO-SAMPLE-001)
assert_contains "$resumed_output" 'mode=resumed'
assert_contains "$resumed_output" 'team_name=fake-team'
assert_contains "$resumed_output" 'leader_pane=%42'
assert_contains "$resumed_output" "worktree=$success_worktree"
rg -n '"team_name": "fake-team"|"leader_pane": "%42"' "$launch_state" >/dev/null || fail 'launch state omitted resumable runtime ownership'
printf '%s\n%s\n%s\n' 'qs-proto-sample-001' "$success_worktree" 'env OMX_TMUX_HUD_OWNER=1 omx hud --watch' > "${repo}-fake-tmux/panes/%47"
resumed_output=$(run_launcher "$repo" --resume-existing --allow-derived-ready PROTO-SAMPLE-001)
assert_contains "$resumed_output" 'mode=resumed'
assert_contains "$resumed_output" 'leader_pane=%42'
rm -f "${repo}-fake-tmux/panes/%47"
rm -f "${repo}-fake-tmux/panes/%42"
if run_launcher "$repo" --resume-existing --allow-derived-ready PROTO-SAMPLE-001 >/dev/null 2>&1; then
  fail 'active Team without a leader unexpectedly created a recovery pane'
fi
test ! -f "${repo}-fake-tmux/panes/%43" || fail 'active Team failure created a recovery pane'
terminal_resumed_output=$(FAKE_OMX_TEAM_PHASE=complete run_launcher "$repo" --resume-existing --allow-derived-ready PROTO-SAMPLE-001)
assert_contains "$terminal_resumed_output" 'mode=resumed'
assert_contains "$terminal_resumed_output" 'leader_pane=%43'
assert_contains "$terminal_resumed_output" 'recovery=terminal leader pane recreated'
test -f "${repo}-fake-tmux/panes/%43" || fail 'terminal resume did not create a recovery leader pane'
rg -n '"leader_pane": "%43"' "$launch_state" >/dev/null || fail 'terminal resume did not persist recovery leader ownership'
(cd "$success_worktree" && OMX_ROOT="$success_worktree" "$tmp_root/fake-bin/omx" team shutdown fake-team >/dev/null)
FAKE_TMUX_STATE="${repo}-fake-tmux" "$tmp_root/fake-bin/tmux" kill-session -t qs-proto-sample-001
test ! -f "${repo}-fake-tmux/sessions/qs-proto-sample-001" || fail 'success cleanup left tmux session'
test ! -f "${repo}-fake-tmux/panes/%43" || fail 'success cleanup left recovery leader pane'

repo=$(make_fixture dry-run)
output=$(run_launcher "$repo" --dry-run PROTO-SAMPLE-001)
assert_contains "$output" 'mode=dry-run'
assert_contains "$output" 'result=no resources created'
assert_contains "$output" 'workers=1'
test ! -e "$tmp_root/dry-run-task-worktrees/proto-sample-001" || fail 'dry-run created worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/qs-proto-sample-001 && fail 'dry-run created branch'
test ! -f "${repo}-fake-tmux/sessions/qs-proto-sample-001" || fail 'dry-run created tmux session'
output=$(run_launcher "$repo" --dry-run BE-SAMPLE-001)
assert_contains "$output" 'workers=2'
assert_contains "$output" 'launch=persistent Codex leader -> omx team 2:executor <atomic-task>'

repo=$(make_fixture already-finished done done)
output=$(run_launcher "$repo" --resume-existing --allow-derived-ready PROTO-SAMPLE-001)
assert_contains "$output" 'mode=already-finished'
assert_contains "$output" "main_after=$(git -C "$repo" rev-parse main)"
test ! -e "$tmp_root/already-finished-task-worktrees/proto-sample-001" || fail 'already-finished recovery created a worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/qs-proto-sample-001 && fail 'already-finished recovery created a branch'
test ! -f "${repo}-fake-tmux/sessions/qs-proto-sample-001" || fail 'already-finished recovery created a session'

repo=$(make_fixture stable-refer-fingerprint)
mkdir -p "$repo/refer/nested"
output=$(run_launcher "$repo" --dry-run PROTO-SAMPLE-001)
fingerprint_before=$(output_value refer_fingerprint "$output")
test -n "$fingerprint_before" || fail 'dry-run omitted refer fingerprint'
touch -t 202001010000 "$repo/refer/reference.txt"
mkdir -p "$repo/refer/nested/.git" "$repo/refer/nested/.omx/state"
printf 'volatile git metadata\n' > "$repo/refer/nested/.git/index"
printf 'volatile omx state\n' > "$repo/refer/nested/.omx/state/runtime.json"
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
test ! -e "$tmp_root/dependency-blocked-task-worktrees/proto-sample-001" || fail 'dependency failure created worktree'

repo=$(make_fixture derived-ready blocked done)
if output=$(run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'blocked manual launch unexpectedly succeeded without derived-ready gate'
fi
assert_contains "$output" 'status must be ready'
output=$(run_launcher "$repo" --allow-derived-ready PROTO-SAMPLE-001)
assert_contains "$output" 'mode=started'
assert_contains "$output" 'derived_ready=true'
derived_worktree="$tmp_root/derived-ready-task-worktrees/proto-sample-001"
rg -n '"derived_ready": true' "$derived_worktree/.omx/context/proto-sample-001-launch.json" >/dev/null || fail 'derived launch state not recorded'
assert_contains "$(<"${repo}-fake-omx-prompt")" 'commit the legal Task status transition from blocked to ready before any other Task write'

repo=$(make_fixture dirty)
printf 'dirty\n' > "$repo/untracked.txt"
if output=$(run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'dirty launch unexpectedly succeeded'
fi
assert_contains "$output" 'main worktree is not clean'
test ! -e "$tmp_root/dirty-task-worktrees/proto-sample-001" || fail 'dirty failure created worktree'

repo=$(make_fixture duplicate)
git -C "$repo" branch codex/qs-proto-sample-001
if output=$(run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'duplicate launch unexpectedly succeeded'
fi
assert_contains "$output" 'branch already exists'
test ! -e "$tmp_root/duplicate-task-worktrees/proto-sample-001" || fail 'duplicate failure created worktree'

repo=$(make_fixture locked)
mkdir "$repo/.git/start-omx-task.lock"
if output=$(run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'locked launch unexpectedly succeeded'
fi
assert_contains "$output" 'another start-omx-task preflight is active or stale'
test ! -e "$tmp_root/locked-task-worktrees/proto-sample-001" || fail 'lock failure created worktree'

repo=$(make_fixture launch-failed)
if output=$(FAKE_OMX_MODE=fail run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'OMX failure unexpectedly succeeded'
fi
assert_contains "$output" 'persistent Codex leader exited before creating OMX team state'
test ! -e "$tmp_root/launch-failed-task-worktrees/proto-sample-001" || fail 'pre-team failure left worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/qs-proto-sample-001 && fail 'pre-team failure left branch'
test ! -f "${repo}-fake-tmux/sessions/qs-proto-sample-001" || fail 'pre-team failure left session'

repo=$(make_fixture leader-exited-after-state)
if output=$(FAKE_OMX_MODE=exit-after-state run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'leader-exited-after-state launch unexpectedly succeeded'
fi
assert_contains "$output" 'persistent Codex leader exited after OMX team state appeared'
test -d "$tmp_root/leader-exited-after-state-task-worktrees/proto-sample-001" || fail 'post-state leader exit removed recovery worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/qs-proto-sample-001 || fail 'post-state leader exit removed recovery branch'
test -f "${repo}-fake-tmux/sessions/qs-proto-sample-001" || fail 'post-state leader exit did not retain worker-backed session'
test ! -f "${repo}-fake-tmux/panes/%42" || fail 'post-state leader exit retained dead leader pane'

repo=$(make_fixture leader-exited-before-state-with-session)
if output=$(FAKE_OMX_MODE=exit-before-state run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'leader-exited-before-state-with-session launch unexpectedly succeeded'
fi
assert_contains "$output" 'leader pane exited before OMX team state appeared while qs-proto-sample-001 still has panes'
test -d "$tmp_root/leader-exited-before-state-with-session-task-worktrees/proto-sample-001" || fail 'live-session leader exit removed recovery worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/qs-proto-sample-001 || fail 'live-session leader exit removed recovery branch'
test -f "${repo}-fake-tmux/sessions/qs-proto-sample-001" || fail 'live-session leader exit removed recovery session'
test ! -f "${repo}-fake-tmux/panes/%42" || fail 'live-session leader exit retained dead leader pane'

repo=$(make_fixture timeout)
if output=$(FAKE_TMUX_MODE=timeout run_launcher "$repo" PROTO-SAMPLE-001 2>&1); then
  fail 'OMX timeout unexpectedly succeeded'
fi
assert_contains "$output" 'persistent Codex leader did not produce a ready OMX team within 2 seconds'
assert_contains "$output" 'mode=recovery-required'
test -d "$tmp_root/timeout-task-worktrees/proto-sample-001" || fail 'timeout removed recovery worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/qs-proto-sample-001 || fail 'timeout removed recovery branch'
test -f "${repo}-fake-tmux/sessions/qs-proto-sample-001" || fail 'timeout removed recovery session'

printf 'PASS start-omx-task persistent-leader resume stable-refer-fingerprint update-prompt liveness cwd-cleanup dry-run dependency dirty duplicate lock failure timeout\n'
