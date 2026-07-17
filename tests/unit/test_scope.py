import pytest

from loop_engineer.runtime.scope import ScopeError, normalize, overlaps


def test_normalize_strips_dot_and_collapses():
    assert normalize("src/./a/../a.py") == "src/a.py"


def test_normalize_rejects_absolute():
    with pytest.raises(ScopeError):
        normalize("/etc/passwd")


def test_normalize_rejects_escape():
    with pytest.raises(ScopeError):
        normalize("../escape.py")
    with pytest.raises(ScopeError):
        normalize("src/../../escape.py")


def test_normalize_rejects_empty():
    with pytest.raises(ScopeError):
        normalize("./")


def test_overlaps_exact_file():
    assert overlaps({"src/a.py"}, {"src/a.py", "src/b.py"})


def test_overlaps_directory_contains_file():
    assert overlaps({"src"}, {"src/a.py"})


def test_no_overlap_disjoint():
    assert not overlaps({"src/a.py"}, {"tests/test_a.py"})


def test_overlaps_normalized_first():
    # trailing "." and dup slashes do not defeat detection
    assert overlaps({"src/./a.py"}, {"src//a.py"})
