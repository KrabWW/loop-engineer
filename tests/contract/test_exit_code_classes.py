"""Exit codes are a public, stable contract (spec §4)."""

import pytest

from loop_engineer.contracts.enums import ExitCode


@pytest.mark.parametrize("code", list(ExitCode))
def test_every_exit_code_is_documented_class(code):
    # 1 is intentionally unused; the spec defines 0,2,3,4,5,6,7.
    assert int(code) in {0, 2, 3, 4, 5, 6, 7}


def test_exit_class_count_is_stable():
    # Changing this number is a breaking contract change.
    assert len(list(ExitCode)) == 7
