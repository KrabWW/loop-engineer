"""Safe capability probe (spec §12 P1, §14 D7).

Detects installed tool versions using ONLY read-only `--version` / `-V` commands.
Never launches a Team, never writes outside a state dir, never shells out to a
mutating command. Supported OMX/OMC version ranges are runtime data recorded
here, not hardcoded contracts.
"""

import re
import shutil
import subprocess
from collections.abc import Callable, Sequence

from pydantic import BaseModel

from loop_engineer.contracts.enums import ExitCode

# A runner maps an argv tuple to (stdout, returncode). Default shells out.
Runner = Callable[[Sequence[str]], tuple[str, int]]


class CapabilityRecord(BaseModel):
    git_version: str | None
    tmux_version: str | None
    codex_version: str | None   # OMX/Codex leader
    claude_version: str | None  # OMC/Claude workers
    exit_code: ExitCode


_VERSION_RE = re.compile(r"(\d+\.\d+(?:\.\d+)?)")


def _extract(stdout: str) -> str | None:
    m = _VERSION_RE.search(stdout)
    return m.group(1) if m else None


def _default_run(argv: Sequence[str]) -> tuple[str, int]:
    if shutil.which(argv[0]) is None:
        return "", 127
    proc = subprocess.run(list(argv), capture_output=True, text=True, check=False)
    return proc.stdout, proc.returncode


def probe_capabilities(run: Runner | None = None) -> CapabilityRecord:
    runner = run or _default_run
    git = _extract(runner(("git", "--version"))[0])
    tmux = _extract(runner(("tmux", "-V"))[0])
    codex = _extract(runner(("codex", "--version"))[0])
    claude = _extract(runner(("claude", "--version"))[0])
    exit_code = ExitCode.OK if git and tmux else ExitCode.INVALID_INPUT
    return CapabilityRecord(
        git_version=git,
        tmux_version=tmux,
        codex_version=codex,
        claude_version=claude,
        exit_code=exit_code,
    )
