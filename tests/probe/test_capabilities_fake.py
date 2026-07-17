from loop_engineer.contracts.enums import ExitCode
from loop_engineer.probe.capabilities import probe_capabilities


def _fake_runner(table):
    def runner(argv):
        return table[tuple(argv)]
    return runner


def test_probe_records_detected_versions():
    table = {
        ("git", "--version"): ("git version 2.43.0\n", 0),
        ("tmux", "-V"): ("tmux 3.4\n", 0),
        ("codex", "--version"): ("codex 0.9.0\n", 0),
        ("claude", "--version"): ("claude 1.0.0\n", 0),
    }
    rec = probe_capabilities(run=_fake_runner(table))
    assert rec.git_version == "2.43.0"
    assert rec.tmux_version == "3.4"
    assert rec.codex_version == "0.9.0"
    assert rec.claude_version == "1.0.0"
    assert rec.exit_code == ExitCode.OK


def test_probe_missing_optional_provider_records_none_not_failure():
    def runner(argv):
        if argv[0] == "claude":
            return ("", 127)
        return {
            ("git", "--version"): ("git version 2.43.0\n", 0),
            ("tmux", "-V"): ("tmux 3.4\n", 0),
            ("codex", "--version"): ("codex 0.9.0\n", 0),
        }[tuple(argv)]
    rec = probe_capabilities(run=runner)
    assert rec.claude_version is None
    assert rec.exit_code == ExitCode.OK


def test_probe_missing_required_tool_returns_exit_2():
    def runner(argv):
        if argv[0] == "git":
            return ("", 127)
        return {
            ("tmux", "-V"): ("tmux 3.4\n", 0),
            ("codex", "--version"): ("codex 0.9.0\n", 0),
            ("claude", "--version"): ("claude 1.0.0\n", 0),
        }[tuple(argv)]
    rec = probe_capabilities(run=runner)
    assert rec.exit_code == ExitCode.INVALID_INPUT
    assert rec.git_version is None


def test_probe_never_launches_team():
    seen = []

    def runner(argv):
        seen.append(tuple(argv))
        return ("tool version 1.0.0\n", 0)

    probe_capabilities(run=runner)
    for argv in seen:
        assert argv[-1] in ("--version", "-V"), f"probe issued non-version command: {argv}"
