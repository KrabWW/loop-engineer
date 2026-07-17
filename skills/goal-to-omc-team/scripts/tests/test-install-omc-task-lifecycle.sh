#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd "$(dirname "$0")" && pwd -P)
skill_root=$(cd "$test_dir/../.." && pwd -P)
installer="$skill_root/scripts/install-omc-task-lifecycle"
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/install-omc-task-lifecycle.XXXXXX")
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

test -x "$installer" || fail "missing executable installer"

make_repo() {
  name=$1
  repo="$tmp_root/$name"
  mkdir -p "$repo"
  git -C "$repo" init -b main -q
  git -C "$repo" config user.name 'Installer Test'
  git -C "$repo" config user.email install@example.invalid
  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add .
  git -C "$repo" commit -qm base
  repo=$(cd "$repo" && pwd -P)
  printf '%s\n' "$repo"
}

sources=(
  scripts/start-omc-task
  scripts/omc-runtime-bin/tmux
  scripts/status-omc-task
  scripts/finish-omc-task
  scripts/run-omc-task-batch
  scripts/tests/test-start-omc-task.sh
  scripts/tests/test-status-omc-task.sh
  scripts/tests/test-finish-omc-task.sh
  scripts/tests/test-run-omc-task-batch.sh
  scripts/examples/omc-task-batch-plan.txt
)

# fresh install
repo=$(make_repo fresh)
output=$("$installer" "$repo")
assert_contains "$output" 'mode=installed'
assert_contains "$output" "repository=$repo"
assert_contains "$output" 'start=./scripts/start-omc-task <TASK_ID>'
assert_contains "$output" 'status=./scripts/status-omc-task <TASK_ID>'
assert_contains "$output" 'finish=./scripts/finish-omc-task <TASK_ID>'
assert_contains "$output" 'batch=./scripts/run-omc-task-batch'
for path in "${sources[@]}"; do
  test -e "$repo/$path" || fail "fresh install missing $path"
  case "$path" in
    *.txt) ;;
    *) test -x "$repo/$path" || fail "fresh install $path not executable" ;;
  esac
done

# idempotent re-install (identical content succeeds without --force)
repo=$(make_repo idempotent)
"$installer" "$repo" >/dev/null
output=$("$installer" "$repo")
assert_contains "$output" 'mode=installed'

# differing target without --force fails
repo=$(make_repo differing)
"$installer" "$repo" >/dev/null
printf 'tampered\n' >> "$repo/scripts/start-omc-task"
if output=$("$installer" "$repo" 2>&1); then fail 'differing target unexpectedly overwrote without --force'; fi
assert_contains "$output" 'target differs'
# --force overwrites
output=$("$installer" --force "$repo")
assert_contains "$output" 'mode=installed'
cmp -s "$skill_root/scripts/start-omc-task" "$repo/scripts/start-omc-task" || fail '--force did not restore identical content'

# missing skill bundle source fails
repo=$(make_repo missing-source)
mv "$skill_root/scripts/examples/omc-task-batch-plan.txt" "$tmp_root/stashed-example"
if output=$("$installer" "$repo" 2>&1); then fail 'missing bundle source unexpectedly installed'; fi
assert_contains "$output" 'skill bundle is incomplete'
mv "$tmp_root/stashed-example" "$skill_root/scripts/examples/omc-task-batch-plan.txt"

# non-git target fails
nongit="$tmp_root/nongit"
mkdir -p "$nongit"
if output=$("$installer" "$nongit" 2>&1); then fail 'non-git target unexpectedly installed'; fi
assert_contains "$output" 'not a Git repository root'

printf 'PASS install-omc-task-lifecycle fresh idempotent force missing-source non-git\n'
