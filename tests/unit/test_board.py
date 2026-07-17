import pytest

from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.runtime.board import (
    BoardStore,
    PriorStateError,
    ScopeOverlapError,
    WrongTokenError,
)


def _plan(task_files: dict[str, list[str]], deps: dict[str, list[str]] | None = None) -> Plan:
    deps = deps or {}
    nodes = []
    for tid, files in task_files.items():
        nodes.append(TaskNode(task=Task(
            id=tid, owner_domain="omx", dependencies=deps.get(tid, []),
            allowed_files=files, acceptance_criteria=["x"],
            verification=VerificationSpec(commands=["t"], working_dir="."),
            required_evidence=["c"],
        )))
    return Plan(goal_id="G1", nodes=nodes, edges=[
        DependencyEdge(from_id=d, to_id=tid) for tid, ds in deps.items() for d in ds
    ])


def test_from_plan_initializes_all_pending(tmp_path):
    plan = _plan({"T1": ["src/a.py"], "T2": ["src/b.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    state = store.load_state()
    assert set(state.tasks) == {"T1", "T2"}
    assert all(e.status.value == "pending" for e in state.tasks.values())


def test_open_existing_board_roundtrips(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    s1 = BoardStore.from_plan(plan, tmp_path)
    s2 = BoardStore.open(s1.dir)
    assert set(s2.load_state().tasks) == {"T1"}


def test_open_missing_board_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        BoardStore.open(tmp_path / "nope")


_LEASE = Lease(
    generation=0, expires_at="2099-01-01T00:00:00Z", last_heartbeat_at="2099-01-01T00:00:00Z",
)


def test_claim_returns_token_and_marks_claimed(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    token = store.claim("T1", Provider.OMX, _LEASE)
    assert isinstance(token, str) and len(token) >= 16
    e = store.load_state().tasks["T1"]
    assert e.status.value == "claimed"
    assert e.provider == Provider.OMX
    assert e.claim is not None and e.claim.token_digest.startswith("sha256:")
    assert e.lease == _LEASE


def test_claim_wrong_prior_state_raises(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    store.claim("T1", Provider.OMX, _LEASE)
    with pytest.raises(PriorStateError):
        store.claim("T1", Provider.OMC, _LEASE)


def test_claim_overlapping_disjoint_tasks_both_ok(tmp_path):
    plan = _plan({"T1": ["src/a.py"], "T2": ["src/b.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    store.claim("T1", Provider.OMX, _LEASE)
    store.claim("T2", Provider.OMC, _LEASE)  # disjoint files -> ok in parallel
    s = store.load_state()
    assert s.tasks["T1"].provider == Provider.OMX
    assert s.tasks["T2"].provider == Provider.OMC


def test_claim_overlapping_files_rejected(tmp_path):
    plan = _plan({"T1": ["src/a.py"], "T2": ["src/a.py"]})  # same file, no dep
    store = BoardStore.from_plan(plan, tmp_path)
    store.claim("T1", Provider.OMX, _LEASE)
    with pytest.raises(ScopeOverlapError):
        store.claim("T2", Provider.OMC, _LEASE)


def test_claim_overlap_allowed_when_dependency_ordered(tmp_path):
    # T2 depends on T1; both touch src/a.py. T1 claimed first; T2 overlap is
    # legal because T2 is a descendant of T1 (independent Tasks may overlap when ordered).
    plan = _plan({"T1": ["src/a.py"], "T2": ["src/a.py"]}, deps={"T2": ["T1"]})
    store = BoardStore.from_plan(plan, tmp_path)
    store.claim("T1", Provider.OMX, _LEASE)
    token = store.claim("T2", Provider.OMC, _LEASE)
    assert isinstance(token, str)


def test_complete_with_correct_token(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    token = store.claim("T1", Provider.OMX, _LEASE)
    store.complete("T1", token)
    assert store.load_state().tasks["T1"].status.value == "done"


def test_complete_wrong_token_rejected(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    store.claim("T1", Provider.OMX, _LEASE)
    with pytest.raises(WrongTokenError):
        store.complete("T1", "not-the-token")


def test_release_returns_to_released(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    token = store.claim("T1", Provider.OMX, _LEASE)
    store.release("T1", token)
    e = store.load_state().tasks["T1"]
    assert e.status.value == "released" and e.claim is None


def test_reset_to_pending_makes_reclaimable(tmp_path):
    plan = _plan({"T1": ["src/a.py"]})
    store = BoardStore.from_plan(plan, tmp_path)
    token = store.claim("T1", Provider.OMX, _LEASE)
    store.release("T1", token)
    store.reset_to_pending("T1")  # coordinator op; no token (claim cleared at release)
    store.claim("T1", Provider.OMC, _LEASE)  # reclaimable post-reset
    e = store.load_state().tasks["T1"]
    assert e.provider == Provider.OMC
    assert e.attempt_id == 2
