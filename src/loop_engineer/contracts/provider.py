"""Provider enum: which execution lane claimed a Task (spec P2a §4)."""

from enum import StrEnum


class Provider(StrEnum):
    OMX = "omx"
    OMC = "omc"
