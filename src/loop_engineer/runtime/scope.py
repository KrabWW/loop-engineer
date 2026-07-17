"""Allowed-files normalization + overlap detection (spec P2a §5.3).

Normalization is lexical (no filesystem access): paths are relative POSIX,
absolute paths and any '..' that escapes the repo root are rejected. Two file
sets overlap on exact file match or directory containment (either direction).
"""

from collections.abc import Iterable


class ScopeError(ValueError):
    """An allowed-files entry is not a legal relative in-repo path."""


def normalize(path: str) -> str:
    posix = path.replace("\\", "/")
    if posix.startswith("/"):
        raise ScopeError(f"absolute paths are not allowed: {path!r}")
    out: list[str] = []
    parts = posix.split("/")
    for part in parts:
        if part in ("", "."):
            continue
        if part == "..":
            if not out:
                raise ScopeError(f"path escapes repo root: {path!r}")
            out.pop()
            continue
        out.append(part)
    if not out:
        raise ScopeError(f"empty path after normalization: {path!r}")
    return "/".join(out)


def _norm_set(files: Iterable[str]) -> set[str]:
    return {normalize(f) for f in files}


def overlaps(a: Iterable[str], b: Iterable[str]) -> bool:
    na = _norm_set(a)
    nb = _norm_set(b)
    for x in na:
        for y in nb:
            if x == y or x.startswith(y + "/") or y.startswith(x + "/"):
                return True
    return False
