#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd "$(dirname "$0")" && pwd -P)
source_finisher=$(cd "$test_dir/.." && pwd -P)/finish-omx-task
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/finish-omx-task.XXXXXX")
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

assert_not_contains() {
  haystack=$1
  needle=$2
  if printf '%s\n' "$haystack" | rg -F -- "$needle" >/dev/null; then
    fail "unexpected output: ${needle}"
  fi
}

test -x "$source_finisher" || fail "missing executable finisher: ${source_finisher}"

make_fake_bins() {
  fake_bin=$1
  mkdir -p "$fake_bin"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "%s\\n" "$*" >> "${FAKE_OMX_LOG:?}"' \
    '[ "${OMX_ROOT:-}" = "$PWD" ] || { printf "wrong OMX_ROOT\\n" >&2; exit 8; }' \
    '[ "${OMX_AUTO_UPDATE:-}" = 0 ] || { printf "updates not disabled\\n" >&2; exit 8; }' \
    '[ "${1:-}" = team ] || exit 2' \
    'operation=${2:-}' \
    'team=${3:-}' \
    '[ "$team" = "random-team-7f3a" ] || { printf "wrong team: %s\\n" "$team" >&2; exit 9; }' \
    'case "$operation" in' \
    '  status)' \
    '    case "${FAKE_OMX_MODE:-complete}" in' \
    '      active) phase=team-exec; pending=0; in_progress=1; completed=0; failed=0 ;;' \
    '      failed) phase=complete; pending=0; in_progress=0; completed=0; failed=1 ;;' \
    '      *) phase=complete; pending=0; in_progress=0; completed=1; failed=0 ;;' \
    '    esac' \
    '    printf "{\\\"status\\\":\\\"ok\\\",\\\"phase\\\":\\\"%s\\\",\\\"workers\\\":{\\\"total\\\":1,\\\"dead\\\":0,\\\"non_reporting\\\":0},\\\"tasks\\\":{\\\"total\\\":1,\\\"pending\\\":%s,\\\"blocked\\\":0,\\\"in_progress\\\":%s,\\\"completed\\\":%s,\\\"failed\\\":%s}}\\n" "$phase" "$pending" "$in_progress" "$completed" "$failed"' \
    '    ;;' \
    '  shutdown)' \
    '    [ "${FAKE_OMX_MODE:-complete}" != shutdown-fail ] || { printf "shutdown failed\\n" >&2; exit 17; }' \
    '    if [ "${FAKE_OMX_MODE:-complete}" = shutdown-content-change ]; then' \
    '      printf "shutdown mutation\\n" >> docs/contracts/sample/README.md' \
    '      git add docs/contracts/sample/README.md' \
    '      git commit -qm "simulate shutdown content mutation"' \
    '    else' \
    '      git commit --allow-empty -qm "simulate OMX shutdown checkpoint"' \
    '    fi' \
    '    if [ "${FAKE_OMX_MODE:-complete}" = main-drift ]; then' \
    '      printf "drift\\n" >> "${FAKE_MAIN_REPO:?}/main-drift.txt"' \
    '      git -C "$FAKE_MAIN_REPO" add main-drift.txt' \
    '      git -C "$FAKE_MAIN_REPO" commit -qm "simulate concurrent main advance"' \
    '    fi' \
    '    printf "shutdown complete\\n"' \
    '    ;;' \
    '  *) exit 2 ;;' \
    'esac' > "$fake_bin/omx"
  chmod +x "$fake_bin/omx"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'state=${FAKE_TMUX_STATE:?}' \
    'printf "%s\\n" "$*" >> "${FAKE_TMUX_LOG:?}"' \
    'case "${1:-}" in' \
    '  has-session)' \
    '    shift; [ "${1:-}" = -t ] && shift; [ -f "$state/session-${1:?}" ]' \
    '    ;;' \
    '  display-message)' \
    '    shift; [ "${1:-}" = -p ] && shift; [ "${1:-}" = -t ] && shift; pane=${1:?}; shift' \
    '    [ "${1:-}" = "#{pane_dead}" ] || exit 2' \
    '    case "${FAKE_TMUX_MODE:-ok}" in' \
    '      ok|kill-stuck|leader-with-hud) [ "$pane" = %42 ] && [ -f "$state/pane-%42" ] ;;' \
    '      replaced-pane|multiple-panes|missing-pane) [ "$pane" != %42 ] || exit 1; [ "$pane" = %77 ] || [ "$pane" = %78 ] || exit 1 ;;' \
    '      reused-pane) [ "$pane" = %42 ] || [ "$pane" = %77 ] || exit 1 ;;' \
    '      *) exit 2 ;;' \
    '    esac' \
    '    printf "0\\n"' \
    '    ;;' \
    '  list-panes)' \
    '    shift; [ "${1:-}" = -a ] && shift; [ "${1:-}" = -F ] && shift; format=${1:?}' \
    '    [ "$format" = "#{pane_id}|#{session_name}|#{pane_dead}|#{pane_current_path}|#{pane_start_command}" ] || exit 2' \
    '    worktree=${FAKE_TASK_WORKTREE:?}' \
    '    case "${FAKE_TMUX_MODE:-ok}" in' \
    '      ok|kill-stuck) printf "%%42|qs-proto-sample-001|0|%s|omx exec leader\\n" "$worktree" ;;' \
    '      leader-with-hud) printf "%%42|qs-proto-sample-001|0|%s|omx exec leader\\n%%47|qs-proto-sample-001|0|%s|env OMX_TMUX_HUD_OWNER=1 omx hud --watch\\n" "$worktree" "$worktree" ;;' \
    '      replaced-pane) printf "%%77|qs-proto-sample-001|0|%s|omx exec leader\\n" "$worktree" ;;' \
    '      reused-pane) printf "%%42|qs-proto-sample-001|0|%s/.omx/team/foreign|foreign\\n%%77|qs-proto-sample-001|0|%s|omx exec leader\\n" "$worktree" "$worktree" ;;' \
    '      multiple-panes) printf "%%77|qs-proto-sample-001|0|%s|omx exec leader\\n%%78|qs-proto-sample-001|0|%s|shell\\n" "$worktree" "$worktree" ;;' \
    '      missing-pane) printf "%%77|qs-proto-sample-001|0|%s/.omx/team/worker-1|worker\\n" "$worktree" ;;' \
    '      *) exit 2 ;;' \
    '    esac' \
    '    ;;' \
    '  kill-session)' \
    '    shift; [ "${1:-}" = -t ] && shift; session=${1:?}' \
    '    [ "${FAKE_TMUX_MODE:-ok}" != kill-stuck ] || exit 23' \
    '    rm -f "$state/session-$session" "$state/pane-%42"' \
    '    ;;' \
    '  *) exit 2 ;;' \
    'esac' > "$fake_bin/tmux"
  chmod +x "$fake_bin/tmux"
}

write_task() {
  path=$1
  status=$2
  allow_refer=${3:-0}
  mkdir -p "$(dirname "$path")"
  {
    printf '%s\n' \
      '# PROTO-SAMPLE-001 sample lifecycle task' \
      '' \
      "- Status: \`${status}\`" \
      '- Owner: `docs/contracts/sample`' \
      '- Depends on: `none`' \
      '' \
      '## Goal' \
      '' \
      'Freeze one sample contract.' \
      '' \
      '## Allowed Files' \
      '' \
      '- `docs/contracts/sample/README.md`' \
      '- `docs/tasks/contracts/PROTO-SAMPLE-001.md`'
    [ "$allow_refer" -eq 0 ] || printf '%s\n' '- `refer/**`'
    printf '%s\n' \
      '' \
      '## Acceptance Criteria' \
      '' \
      '- [ ] Contract remains append-only.' \
      '' \
      '## Verification Commands' \
      '' \
      '```sh' \
      'test -f docs/contracts/sample/README.md' \
      "rg -n 'append-only' docs/contracts/sample/README.md" \
      "rg -n '^- Status: \`done\`$' docs/tasks/contracts/PROTO-SAMPLE-001.md" \
      'if [ -n "${FAKE_VERIFY_COUNTER:-}" ]; then' \
      '  count=$(($(cat "$FAKE_VERIFY_COUNTER" 2>/dev/null || printf 0) + 1))' \
      '  printf "%s\n" "$count" > "$FAKE_VERIFY_COUNTER"' \
      '  if [ "${FAKE_VERIFY_DIRTY_ON_RUN:-0}" -eq "$count" ]; then printf "verification dirt\n" > verification-dirty.txt; fi' \
      'fi' \
      '```'
  } > "$path"
}

reference_fingerprint() {
  python3 - "$1" <<'PY'
import hashlib
import os
from pathlib import Path
import stat
import sys

root = Path(sys.argv[1])
digest = hashlib.sha256()
digest.update(b"content-v2\n")
if not root.exists():
    digest.update(b"absent\n")
else:
    for current, dirs, files in os.walk(root):
        dirs[:] = sorted(name for name in dirs if name not in {".git", ".omx"})
        files = sorted(name for name in files if name != ".DS_Store")
        current_path = Path(current)
        for name in dirs + files:
            path = current_path / name
            info = os.lstat(path)
            relative = path.relative_to(root).as_posix()
            mode = stat.S_IMODE(info.st_mode)
            if stat.S_ISLNK(info.st_mode):
                record = f"link\0{relative}\0{mode:o}\0{os.readlink(path)}\n".encode()
            elif stat.S_ISREG(info.st_mode):
                content = hashlib.sha256(path.read_bytes()).hexdigest()
                record = f"file\0{relative}\0{mode:o}\0{content}\n".encode()
            elif stat.S_ISDIR(info.st_mode):
                record = f"dir\0{relative}\0{mode:o}\n".encode()
            else:
                record = f"special\0{relative}\0{info.st_mode}\n".encode()
            digest.update(record)
print(digest.hexdigest())
PY
}

write_launch_state() {
  wt=$1
  repo=$2
  fingerprint=$(reference_fingerprint "$repo/refer")
  mkdir -p "$wt/.omx/context"
  printf '{"task_id":"PROTO-SAMPLE-001","task_file":"docs/tasks/contracts/PROTO-SAMPLE-001.md","branch":"codex/qs-proto-sample-001","worktree":"%s","session":"qs-proto-sample-001","derived_ready":false,"refer_fingerprint_version":"content-v2","refer_fingerprint":"%s"}\n' "$wt" "$fingerprint" > "$wt/.omx/context/proto-sample-001-launch.json"
}

refresh_evidence() {
  wt=$1
  mkdir -p "$wt/.omx/context"
  head=$(git -C "$wt" rev-parse HEAD)
  printf '# final evidence\n\n- Final HEAD: `%s`\n- Verification: PASS\n' "$head" > "$wt/.omx/context/proto-sample-001-final-evidence.md"
}

make_fixture() {
  name=$1
  conflict=${2:-0}
  allow_refer=${3:-0}
  repo="$tmp_root/$name"
  wt_root="${repo}-task-worktrees"
  wt="$wt_root/proto-sample-001"
  mkdir -p "$repo"
  git -C "$repo" init -b main -q
  git -C "$repo" config user.name 'Finisher Test'
  git -C "$repo" config user.email finisher-test@example.invalid
  mkdir -p "$repo/docs/tasks/contracts" "$repo/scripts"
  cp "$source_finisher" "$repo/scripts/finish-omx-task"
  chmod +x "$repo/scripts/finish-omx-task"
  write_task "$repo/docs/tasks/contracts/PROTO-SAMPLE-001.md" ready "$allow_refer"
  printf 'base\n' > "$repo/README.md"
  printf 'refer/\n' > "$repo/.gitignore"
  mkdir -p "$repo/refer"
  printf 'read-only reference\n' > "$repo/refer/reference.txt"
  printf '.omx/\n' >> "$repo/.git/info/exclude"
  git -C "$repo" add .
  git -C "$repo" commit -qm 'fixture base'

  mkdir -p "$wt_root"
  git -C "$repo" worktree add -q -b codex/qs-proto-sample-001 "$wt" main
  git -C "$wt" branch fixture-worker
  git -C "$wt" switch -q fixture-worker
  mkdir -p "$wt/docs/contracts/sample"
  printf 'append-only sample contract\n' > "$wt/docs/contracts/sample/README.md"
  git -C "$wt" add docs/contracts/sample/README.md
  git -C "$wt" commit -qm 'worker sample contract'
  git -C "$wt" switch -q codex/qs-proto-sample-001
  git -C "$wt" commit --allow-empty -qm 'leader checkpoint'
  git -C "$wt" merge --no-ff -qm 'merge worker checkpoint' fixture-worker
  write_task "$wt/docs/tasks/contracts/PROTO-SAMPLE-001.md" done "$allow_refer"
  git -C "$wt" add docs/tasks/contracts/PROTO-SAMPLE-001.md
  git -C "$wt" commit -qm 'mark sample task done'

  if [ "$conflict" -eq 1 ]; then
    mkdir -p "$repo/docs/contracts/sample"
    printf 'main conflicting contract\n' > "$repo/docs/contracts/sample/README.md"
    git -C "$repo" add docs/contracts/sample/README.md
  else
    printf 'main advanced\n' >> "$repo/README.md"
    git -C "$repo" add README.md
  fi
  git -C "$repo" commit -qm 'advance main after task launch'

  mkdir -p "$wt/.omx/state/team/random-team-7f3a" "$tmp_root/tmux-$name"
  printf '{"name":"random-team-7f3a","leader_cwd":"%s","leader_pane_id":"%%42","tmux_session":"qs-proto-sample-001:0"}\n' "$wt" > "$wt/.omx/state/team/random-team-7f3a/config.json"
  : > "$tmp_root/tmux-$name/session-qs-proto-sample-001"
  : > "$tmp_root/tmux-$name/pane-%42"
  : > "$tmp_root/tmux-$name/session-qs-foreign-001"
  mkdir -p "$repo/.omx/state/team/foreign-team"
  printf '{"name":"foreign-team"}\n' > "$repo/.omx/state/team/foreign-team/config.json"
  write_launch_state "$wt" "$repo"
  refresh_evidence "$wt"
  printf '%s\n' "$repo"
}

run_finisher() {
  repo=$1
  shift
  name=$(basename "$repo")
  task_worktree=$(cd "${repo}-task-worktrees/proto-sample-001" && pwd -P)
  : > "$tmp_root/omx-$name.log"
  : > "$tmp_root/tmux-$name.log"
  (
    cd "$repo"
    FAKE_OMX_LOG="$tmp_root/omx-$name.log" \
      FAKE_TMUX_LOG="$tmp_root/tmux-$name.log" \
      FAKE_TMUX_STATE="$tmp_root/tmux-$name" \
      FAKE_TASK_WORKTREE="$task_worktree" \
      FAKE_OMX_MODE="${FAKE_OMX_MODE:-complete}" \
      FAKE_TMUX_MODE="${FAKE_TMUX_MODE:-ok}" \
      FAKE_MAIN_REPO="$repo" \
      FAKE_VERIFY_COUNTER="$tmp_root/verify-$name.count" \
      FAKE_VERIFY_DIRTY_ON_RUN="${FAKE_VERIFY_DIRTY_ON_RUN:-0}" \
      OMX_BIN="$tmp_root/fake-bin/omx" \
      TMUX_BIN="$tmp_root/fake-bin/tmux" \
      OMX_TASK_WORKTREE_ROOT="${repo}-task-worktrees" \
      ./scripts/finish-omx-task "$@"
  )
}

make_fake_bins "$tmp_root/fake-bin"

repo=$(make_fixture success)
old_main=$(git -C "$repo" rev-parse HEAD)
output=$(run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=finished'
assert_contains "$output" 'team_name=random-team-7f3a'
assert_contains "$output" 'rebase_mode=--rebase-merges'
assert_contains "$output" 'verification_runs=3'
test "$(git -C "$repo" rev-parse HEAD)" != "$old_main" || fail 'success did not advance main'
test -f "$repo/docs/contracts/sample/README.md" || fail 'success did not merge contract'
rg -n '^- Status: `done`$' "$repo/docs/tasks/contracts/PROTO-SAMPLE-001.md" >/dev/null || fail 'success did not merge Task status'
test ! -e "${repo}-task-worktrees/proto-sample-001" || fail 'success left worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/qs-proto-sample-001 && fail 'success left branch'
test ! -f "$tmp_root/tmux-success/session-qs-proto-sample-001" || fail 'success left tmux session'
test -f "$tmp_root/tmux-success/session-qs-foreign-001" || fail 'success touched foreign tmux session'
test -f "$repo/.omx/state/team/foreign-team/config.json" || fail 'success touched foreign Team state'
git -C "$repo" log --merges --format='%s' | rg -F 'merge worker checkpoint' >/dev/null || fail 'success lost merge topology'
test -z "$(git -C "$repo" status --porcelain)" || fail 'success left main dirty'

repo=$(make_fixture stable-refer-metadata)
mkdir -p "$repo/refer/nested"
write_launch_state "${repo}-task-worktrees/proto-sample-001" "$repo"
touch -t 202001010000 "$repo/refer/reference.txt"
mkdir -p "$repo/refer/nested/.git" "$repo/refer/nested/.omx/state"
printf 'volatile git metadata\n' > "$repo/refer/nested/.git/index"
printf 'volatile omx state\n' > "$repo/refer/nested/.omx/state/runtime.json"
printf 'finder metadata\n' > "$repo/refer/.DS_Store"
output=$(run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=finished'

repo=$(make_fixture leader-with-hud)
output=$(FAKE_TMUX_MODE=leader-with-hud run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=finished'

repo=$(make_fixture replaced-pane)
output=$(FAKE_TMUX_MODE=replaced-pane run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'leader_pane_recovered=old:%42,new:%77'
assert_contains "$output" 'mode=finished'

repo=$(make_fixture reused-pane)
output=$(FAKE_TMUX_MODE=reused-pane run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'leader_pane_recovered=old:%42,new:%77'
assert_contains "$output" 'mode=finished'

repo=$(make_fixture missing-pane)
if output=$(FAKE_TMUX_MODE=missing-pane run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'missing replacement pane unexpectedly finished'; fi
assert_contains "$output" 'no live exact-cwd leader pane in qs-proto-sample-001'
assert_not_contains "$(<"$tmp_root/omx-missing-pane.log")" 'shutdown'

repo=$(make_fixture multiple-panes)
if output=$(FAKE_TMUX_MODE=multiple-panes run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'ambiguous replacement pane unexpectedly finished'; fi
assert_contains "$output" 'multiple live exact-cwd leader panes in qs-proto-sample-001'
assert_not_contains "$(<"$tmp_root/omx-multiple-panes.log")" 'shutdown'

repo=$(make_fixture multiple-teams)
mkdir -p "${repo}-task-worktrees/proto-sample-001/.omx/state/team/second-team"
printf '{}\n' > "${repo}-task-worktrees/proto-sample-001/.omx/state/team/second-team/config.json"
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'multiple teams unexpectedly finished'; fi
assert_contains "$output" 'expected one OMX team config, found 2'
assert_contains "$output" 'recovery_worktree='
assert_not_contains "$(<"$tmp_root/omx-multiple-teams.log")" 'shutdown'

repo=$(make_fixture no-team)
rm -rf "${repo}-task-worktrees/proto-sample-001/.omx/state/team/random-team-7f3a"
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'missing team unexpectedly finished'; fi
assert_contains "$output" 'expected one OMX team config, found 0'
assert_not_contains "$(<"$tmp_root/omx-no-team.log")" 'shutdown'

repo=$(make_fixture active-team)
if output=$(FAKE_OMX_MODE=active run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'active team unexpectedly finished'; fi
assert_contains "$output" 'team is not complete'
assert_not_contains "$(<"$tmp_root/omx-active-team.log")" 'shutdown'

repo=$(make_fixture missing-evidence)
rm -f "${repo}-task-worktrees/proto-sample-001/.omx/context/"*final-evidence*.md
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'missing evidence unexpectedly finished'; fi
assert_contains "$output" 'expected one final evidence file, found 0'
assert_not_contains "$(<"$tmp_root/omx-missing-evidence.log")" 'shutdown'

repo=$(make_fixture leader-head-evidence)
wt="${repo}-task-worktrees/proto-sample-001"
leader_head=$(git -C "$wt" rev-parse HEAD)
printf '# final evidence\n\n- Final leader HEAD: `%s`\n- Verification: PASS\n' "$leader_head" > "$wt/.omx/context/proto-sample-001-final-evidence.md"
output=$(run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=finished'

repo=$(make_fixture checked-acceptance)
wt="${repo}-task-worktrees/proto-sample-001"
sed -i.bak 's/^- \[ \] Contract remains append-only\.$/- [x] Contract remains append-only./' "$wt/docs/tasks/contracts/PROTO-SAMPLE-001.md"
rm -f "$wt/docs/tasks/contracts/PROTO-SAMPLE-001.md.bak"
git -C "$wt" add docs/tasks/contracts/PROTO-SAMPLE-001.md
git -C "$wt" commit -qm 'record verified acceptance'
refresh_evidence "$wt"
output=$(run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=finished'

repo=$(make_fixture changed-acceptance-text)
wt="${repo}-task-worktrees/proto-sample-001"
sed -i.bak 's/^- \[ \] Contract remains append-only\.$/- [x] Contract may be rewritten./' "$wt/docs/tasks/contracts/PROTO-SAMPLE-001.md"
rm -f "$wt/docs/tasks/contracts/PROTO-SAMPLE-001.md.bak"
git -C "$wt" add docs/tasks/contracts/PROTO-SAMPLE-001.md
git -C "$wt" commit -qm 'rewrite acceptance semantics'
refresh_evidence "$wt"
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'changed acceptance text unexpectedly finished'; fi
assert_contains "$output" 'Task file changed beyond controlled Status and Acceptance transitions'
assert_not_contains "$(<"$tmp_root/omx-changed-acceptance-text.log")" 'shutdown'

repo=$(make_fixture stale-evidence)
wt="${repo}-task-worktrees/proto-sample-001"
stale_head=$(git -C "$repo" rev-parse HEAD)
printf '# final evidence\n\n- Final HEAD: `%s`\n' "$stale_head" > "$wt/.omx/context/proto-sample-001-final-evidence.md"
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'stale evidence unexpectedly finished'; fi
assert_contains "$output" 'final evidence HEAD is not an ancestor of Task HEAD'
assert_not_contains "$(<"$tmp_root/omx-stale-evidence.log")" 'shutdown'

repo=$(make_fixture dirty-worktree)
printf 'dirty\n' > "${repo}-task-worktrees/proto-sample-001/untracked.txt"
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'dirty worktree unexpectedly finished'; fi
assert_contains "$output" 'Task worktree is not clean'
assert_not_contains "$(<"$tmp_root/omx-dirty-worktree.log")" 'shutdown'

repo=$(make_fixture scope-violation)
wt="${repo}-task-worktrees/proto-sample-001"
mkdir -p "$wt/refer"
printf 'forbidden\n' > "$wt/refer/change.txt"
git -C "$wt" add -f refer/change.txt
git -C "$wt" commit -qm 'violate protected scope'
refresh_evidence "$wt"
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'scope violation unexpectedly finished'; fi
assert_contains "$output" 'branch changed protected refer/: refer/change.txt'
assert_not_contains "$(<"$tmp_root/omx-scope-violation.log")" 'shutdown'

repo=$(make_fixture protected-allowed 0 1)
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'refer Allowed Files pattern unexpectedly finished'; fi
assert_contains "$output" 'Allowed Files may not include protected refer/'
assert_not_contains "$(<"$tmp_root/omx-protected-allowed.log")" 'shutdown'

repo=$(make_fixture refer-mutated)
printf 'mutated\n' >> "$repo/refer/reference.txt"
output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1)
assert_contains "$output" 'WARNING: external refer/ drift detected'
assert_contains "$output" 'mode=finished'

repo=$(make_fixture verification-failure)
wt="${repo}-task-worktrees/proto-sample-001"
printf 'wrong contract\n' > "$wt/docs/contracts/sample/README.md"
git -C "$wt" add docs/contracts/sample/README.md
git -C "$wt" commit -qm 'break task verification'
refresh_evidence "$wt"
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'verification failure unexpectedly finished'; fi
assert_contains "$output" 'verification failed at pre-shutdown'
assert_not_contains "$(<"$tmp_root/omx-verification-failure.log")" 'shutdown'

repo=$(make_fixture shutdown-failure)
if output=$(FAKE_OMX_MODE=shutdown-fail run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'shutdown failure unexpectedly finished'; fi
assert_contains "$output" 'team shutdown failed'
test -f "$tmp_root/tmux-shutdown-failure/session-qs-proto-sample-001" || fail 'shutdown failure removed recovery session'

repo=$(make_fixture shutdown-content-change)
if output=$(FAKE_OMX_MODE=shutdown-content-change run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'shutdown content change unexpectedly finished'; fi
assert_contains "$output" 'shutdown changed repository content'
test -f "$tmp_root/tmux-shutdown-content-change/session-qs-proto-sample-001" || fail 'content change removed recovery session'

repo=$(make_fixture tmux-stuck)
if output=$(FAKE_TMUX_MODE=kill-stuck run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'stuck tmux unexpectedly finished'; fi
assert_contains "$output" 'tmux session remains after cleanup'
test -d "${repo}-task-worktrees/proto-sample-001" || fail 'stuck tmux removed recovery worktree'
output=$(FAKE_TMUX_MODE=ok run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=finished'
assert_contains "$output" 'resumed=true'

repo=$(make_fixture rebase-conflict 1)
main_before=$(git -C "$repo" rev-parse HEAD)
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'rebase conflict unexpectedly finished'; fi
assert_contains "$output" 'rebase with merge topology failed'
test "$(git -C "$repo" rev-parse HEAD)" = "$main_before" || fail 'rebase conflict moved main'
test -d "${repo}-task-worktrees/proto-sample-001" || fail 'rebase conflict removed recovery worktree'
git -C "$repo" rm -q docs/contracts/sample/README.md
git -C "$repo" commit -qm 'remove conflicting main contract for retry'
output=$(run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=finished'
assert_contains "$output" 'resumed=true'

repo=$(make_fixture dirty-post-rebase)
if output=$(FAKE_VERIFY_DIRTY_ON_RUN=2 run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'dirty post-rebase verification unexpectedly finished'; fi
assert_contains "$output" 'verification failed at post-rebase'
test -d "${repo}-task-worktrees/proto-sample-001" || fail 'dirty post-rebase removed recovery worktree'
test -n "$(git -C "${repo}-task-worktrees/proto-sample-001" status --porcelain)" || fail 'dirty post-rebase fixture did not dirty worktree'
rm -f "${repo}-task-worktrees/proto-sample-001/verification-dirty.txt"
output=$(FAKE_VERIFY_DIRTY_ON_RUN=0 run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=finished'
assert_contains "$output" 'resumed=true'

repo=$(make_fixture dirty-post-merge)
if output=$(FAKE_VERIFY_DIRTY_ON_RUN=3 run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'dirty post-merge verification unexpectedly finished'; fi
assert_contains "$output" 'verification failed at post-merge'
test -d "${repo}-task-worktrees/proto-sample-001" || fail 'dirty post-merge removed recovery worktree'
git -C "$repo" show-ref --verify --quiet refs/heads/codex/qs-proto-sample-001 || fail 'dirty post-merge removed recovery branch'
rm -f "$repo/verification-dirty.txt"
output=$(FAKE_VERIFY_DIRTY_ON_RUN=0 run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=finished'
assert_contains "$output" 'resumed=true'

repo=$(make_fixture main-drift)
if output=$(FAKE_OMX_MODE=main-drift run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'main drift unexpectedly finished'; fi
assert_contains "$output" 'main advanced during finish'
test -d "${repo}-task-worktrees/proto-sample-001" || fail 'main drift removed recovery worktree'
output=$(FAKE_OMX_MODE=complete run_finisher "$repo" PROTO-SAMPLE-001)
assert_contains "$output" 'mode=finished'
assert_contains "$output" 'resumed=true'

repo=$(make_fixture locked)
mkdir "$repo/.git/finish-omx-task.lock"
if output=$(run_finisher "$repo" PROTO-SAMPLE-001 2>&1); then fail 'locked finisher unexpectedly ran'; fi
assert_contains "$output" 'another finish-omx-task is active or stale'
assert_not_contains "$(<"$tmp_root/omx-locked.log")" 'shutdown'

printf 'PASS finish-omx-task discovery gates pane recovery verification shutdown rebase merge cleanup recovery\n'
