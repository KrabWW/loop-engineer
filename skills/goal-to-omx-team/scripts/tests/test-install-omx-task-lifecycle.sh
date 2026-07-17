#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd "$(dirname "$0")" && pwd -P)
skill_root=$(cd "$test_dir/../.." && pwd -P)
installer="$skill_root/scripts/install-omx-task-lifecycle"
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/install-omx-lifecycle.XXXXXX")
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

repo="$tmp_root/repo"
mkdir -p "$repo"
git -C "$repo" init -b main -q
git -C "$repo" config user.name Installer
git -C "$repo" config user.email installer@example.invalid
printf 'base\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm base

output=$("$installer" "$repo")
assert_contains "$output" 'mode=installed'
assert_contains "$output" './scripts/start-omx-task <TASK_ID>'
assert_contains "$output" './scripts/finish-omx-task <TASK_ID>'
assert_contains "$output" './scripts/run-omx-task-batch --mode custom scripts/examples/omx-task-batch-plan.txt'
for path in \
  scripts/start-omx-task \
  scripts/finish-omx-task \
  scripts/run-omx-task-batch \
  scripts/tests/test-start-omx-task.sh \
  scripts/tests/test-finish-omx-task.sh \
  scripts/tests/test-run-omx-task-batch.sh; do
  test -x "$repo/$path" || fail "not installed executable: $path"
done
test -f "$repo/scripts/examples/omx-task-batch-plan.txt" || fail 'plan example not installed'
cmp -s "$skill_root/scripts/start-omx-task" "$repo/scripts/start-omx-task" || fail 'launcher content mismatch'
cmp -s "$skill_root/scripts/finish-omx-task" "$repo/scripts/finish-omx-task" || fail 'finisher content mismatch'
cmp -s "$skill_root/scripts/run-omx-task-batch" "$repo/scripts/run-omx-task-batch" || fail 'batch content mismatch'

"$installer" "$repo" >/dev/null
printf 'local change\n' >> "$repo/scripts/start-omx-task"
if output=$("$installer" "$repo" 2>&1); then fail 'installer overwrote a changed target without --force'; fi
assert_contains "$output" 'target differs; rerun with --force'
"$installer" --force "$repo" >/dev/null
cmp -s "$skill_root/scripts/start-omx-task" "$repo/scripts/start-omx-task" || fail '--force did not restore launcher'

printf 'PASS install-omx-task-lifecycle one-command idempotent guarded force\n'
