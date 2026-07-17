#!/usr/bin/env python3

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "SKILL.md"
CONTRACT = ROOT / "references" / "deliverable-contract.md"
QUEUE = ROOT / "scripts" / "run-omx-task-queue"
QUEUE_TEST = ROOT / "scripts" / "tests" / "test-run-omx-task-queue.sh"
STARTER = ROOT / "scripts" / "start-omx-task"
STARTER_TEST = ROOT / "scripts" / "tests" / "test-start-omx-task.sh"
FINISHER = ROOT / "scripts" / "finish-omx-task"
FINISHER_TEST = ROOT / "scripts" / "tests" / "test-finish-omx-task.sh"
BATCH = ROOT / "scripts" / "run-omx-task-batch"
BATCH_TEST = ROOT / "scripts" / "tests" / "test-run-omx-task-batch.sh"
INSTALLER = ROOT / "scripts" / "install-omx-task-lifecycle"
INSTALLER_TEST = ROOT / "scripts" / "tests" / "test-install-omx-task-lifecycle.sh"
QUEUE_EXAMPLE = ROOT / "examples" / "omx-task-queue.txt"
BATCH_EXAMPLE = ROOT / "examples" / "omx-task-batch-plan.txt"


def require(text: str, fragments: list[str], source: Path) -> None:
    missing = [fragment for fragment in fragments if fragment not in text]
    assert not missing, f"{source}: missing {missing}"


assert SKILL.is_file(), f"missing {SKILL}"
assert CONTRACT.is_file(), f"missing {CONTRACT}"
assert QUEUE.is_file(), f"missing {QUEUE}"
assert QUEUE_TEST.is_file(), f"missing {QUEUE_TEST}"
assert STARTER.is_file(), f"missing {STARTER}"
assert STARTER_TEST.is_file(), f"missing {STARTER_TEST}"
assert FINISHER.is_file(), f"missing {FINISHER}"
assert FINISHER_TEST.is_file(), f"missing {FINISHER_TEST}"
assert BATCH.is_file(), f"missing {BATCH}"
assert BATCH_TEST.is_file(), f"missing {BATCH_TEST}"
assert INSTALLER.is_file(), f"missing {INSTALLER}"
assert INSTALLER_TEST.is_file(), f"missing {INSTALLER_TEST}"
assert QUEUE_EXAMPLE.is_file(), f"missing {QUEUE_EXAMPLE}"
assert BATCH_EXAMPLE.is_file(), f"missing {BATCH_EXAMPLE}"

skill = SKILL.read_text()
contract = CONTRACT.read_text()
queue = QUEUE.read_text()
starter = STARTER.read_text()
finisher = FINISHER.read_text()
batch = BATCH.read_text()
installer = INSTALLER.read_text()

frontmatter = re.match(r"\A---\n(.*?)\n---\n", skill, re.S)
assert frontmatter, "missing YAML frontmatter"
keys = re.findall(r"^([a-z-]+):", frontmatter.group(1), re.M)
assert keys == ["name", "description"], keys
assert "name: goal-to-omx-team" in frontmatter.group(1)
assert re.search(r"^description: Use when ", frontmatter.group(1), re.M)

require(
    skill,
    [
        "Use define-goal",
        "Use team",
        "G is a milestone",
        "one Task -> one integration branch -> one integration worktree -> one persistent Codex leader -> one OMX team",
        "persistent Codex leader",
        "temporary shell helpers",
        "atomic sentence",
        "OMX_ROOT",
        "leader pane",
        "OMX worker worktrees",
        "refer/",
        "acyclic",
        "references/deliverable-contract.md",
        "Do not launch a real team",
        "scripts/run-omx-task-queue",
        "scripts/finish-omx-task",
        "install-omx-task-lifecycle",
        "Batch waves",
        "stale pane",
    ],
    SKILL,
)

require(
    contract,
    [
        "Operator",
        "Depends on",
        "Allowed Files",
        "Non-goals",
        "Acceptance Criteria",
        "Verification Commands",
        "./scripts/start-omx-task <TASK_ID>",
        "./scripts/start-omx-task --dry-run <TASK_ID>",
        "omx exec --dangerously-bypass-approvals-and-sandbox",
        "fake OMX/tmux",
        "OMX_AUTO_UPDATE=0",
        "OMX_ROOT",
        "pane_dead=0",
        "one atomic sentence",
        "cwd-bound",
        "persistent Codex leader",
        "rich controls belong in the leader prompt",
        "leader mailbox",
        "omx team status <team> --json",
        "omx team await <team> --timeout-ms 30000 --json",
        "omx team shutdown <team>",
        "phase=complete",
        "failed` or `cancelled",
        "exact `leader_pane`",
        "signals",
        "live tmux session after cleanup",
        "worker-backed session",
        "adapter-neutral",
        "unique",
        "acyclic",
        "--allow-derived-ready",
        "--finish-current",
        "ff-only",
        "./scripts/finish-omx-task <TASK_ID>",
        "--rebase-merges",
        "three verification runs",
        "Integrated batch runner",
        "One-command lifecycle installer",
        "same finish command",
        "refer/` fingerprint",
        "unique live exact-cwd pane",
        "refer_fingerprint_version",
        "content-v2",
        "12-hour",
    ],
    CONTRACT,
)
assert "omx --direct --ask-for-approval" not in contract, (
    "contract must use the verified non-interactive OMX exec entrypoint"
)

combined = skill + contract
placeholder_pattern = r"\b(?:TO" + r"DO|TB" + r"D)\b|" + "待" + "定"
assert not re.search(placeholder_pattern, combined)
require(
    queue,
    [
        "--allow-derived-ready",
        "OMX_AUTO_UPDATE=0",
        "OMX_ROOT",
        "team status",
        "team await",
        "active_leader_pane",
        "pane_dead",
        "phase",
        "print_recovery",
        "OMX_TASK_FINISHER",
        "finish-omx-task",
        "finish_output",
        "main_after",
        "queue_status=deadline",
    ],
    QUEUE,
)
assert "team shutdown" not in queue, "queue must delegate shutdown to finisher"
assert "merge --ff-only" not in queue, "queue must delegate merge to finisher"
require(
    starter,
    [
        "--allow-derived-ready",
        '"$omx_bin" exec',
        "refer_fingerprint",
        "refer_fingerprint_version",
        "content-v2",
        "finish-omx-task",
    ],
    STARTER,
)
require(
    finisher,
    [
        "expected one OMX team config",
        "validate_terminal_status",
        "final evidence",
        "Allowed Files",
        "run_verification pre-shutdown",
        "run_verification post-rebase",
        "run_verification post-merge",
        "team shutdown",
        "rebase --rebase-merges main",
        "merge --ff-only",
        "recovery_worktree",
        "resolve_leader_pane",
        "list-panes",
        "content-v2",
        "mode=finished",
    ],
    FINISHER,
)
require(
    batch,
    [
        "--mode serial|parallel|custom",
        "--max-parallel",
        "--allow-derived-ready",
        "team status",
        "resolve_leader_pane",
        "list-panes",
        "tmux_session",
        "finish-omx-task",
        "recovery_command",
    ],
    BATCH,
)
assert "team shutdown" not in batch, "batch must delegate shutdown to finisher"
assert "merge --ff-only" not in batch, "batch must delegate merge to finisher"
require(
    installer,
    [
        "install-omx-task-lifecycle [--force] <REPOSITORY>",
        "scripts/start-omx-task",
        "scripts/finish-omx-task",
        "scripts/run-omx-task-batch",
        "mode=installed",
    ],
    INSTALLER,
)
assert len(skill.split()) < 500, f"SKILL.md too large: {len(skill.split())} words"
assert QUEUE.stat().st_mode & 0o111, "queue runner must be executable"
assert QUEUE_TEST.stat().st_mode & 0o111, "queue test must be executable"
assert STARTER.stat().st_mode & 0o111, "starter must be executable"
assert STARTER_TEST.stat().st_mode & 0o111, "starter test must be executable"
assert FINISHER.stat().st_mode & 0o111, "finisher must be executable"
assert FINISHER_TEST.stat().st_mode & 0o111, "finisher test must be executable"
assert BATCH.stat().st_mode & 0o111, "batch runner must be executable"
assert BATCH_TEST.stat().st_mode & 0o111, "batch test must be executable"
assert INSTALLER.stat().st_mode & 0o111, "installer must be executable"
assert INSTALLER_TEST.stat().st_mode & 0o111, "installer test must be executable"
assert not (ROOT / ".omx").exists(), "skill package must not contain runtime state"

print("PASS goal-to-omx-team skill contract")
