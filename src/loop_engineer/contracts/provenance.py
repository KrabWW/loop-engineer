"""Provenance manifest (spec §10).

Original code has no entry and is redistributable. Any imported/adapted file
requires an entry with source origin, source license, transformation policy,
and explicit approval before redistribution.
"""

from pathlib import PurePosixPath

from pydantic import BaseModel, Field, model_validator


class ProvenanceEntry(BaseModel):
    path: str = Field(min_length=1)
    source_origin: str = Field(min_length=1)
    source_license: str = Field(min_length=1)
    transformation: str = Field(min_length=1)  # verbatim | adapted | generated-from
    approved: bool = False
    imported_at: str | None = None


class ProvenanceManifest(BaseModel):
    entries: list[ProvenanceEntry] = Field(default_factory=list)

    @model_validator(mode="after")
    def _unique_paths(self) -> "ProvenanceManifest":
        paths = [e.path for e in self.entries]
        if len(paths) != len(set(paths)):
            raise ValueError("provenance paths must be unique")
        return self

    def _normalized(self, path: str) -> str:
        return PurePosixPath(path).as_posix()

    def redistribution_allowed(self, path: str) -> bool:
        """True iff the file is original (no entry) or has an approved entry."""
        target = self._normalized(path)
        for e in self.entries:
            if self._normalized(e.path) == target:
                return e.approved
        return True  # original code: no entry required
