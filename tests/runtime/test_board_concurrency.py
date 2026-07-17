"""Parallel-claim requirement (spec P2a §2, §8): two real OS processes claiming
non-overlapping Tasks both succeed under the shared file lock — one OMX, one OMC."""

import multiprocessing as mp
from pathlib import Path

from loop_engineer.contracts.lease import Lease
from loop_engineer.contracts.plan import Plan, TaskNode
from loop_engineer.contracts.provider import Provider
from loop_engineer.contracts.task import Task, VerificationSpec
from loop_engineer.runtime.board import BoardStore

_LEASE = Lease(
    generation=0, expires_at="2099-01-01T00:00:00Z", last_heartbeat_at="2099-01-01T00:00:00Z",
)


def _plan() -> Plan:
    nodes = [
        TaskNode(task=Task(
            id=tid, owner_domain="omx", allowed_files=[f"src/{tid}.py"],
            acceptance_criteria=["x"],
            verification=VerificationSpec(commands=["t"], working_dir="."),
            required_evidence=["c"],
        ))
        for tid in ("T1", "T2")
    ]
    return Plan(goal_id="G", nodes=nodes, edges=[])


def _claim_worker(board_dir: str, task_id: str, provider: str, q) -> None:
    try:
        store = BoardStore.open(Path(board_dir))
        store.claim(task_id, Provider(provider), _LEASE)
        q.put(("ok", task_id, provider))
    except Exception as e:  # noqa: BLE001 - surface any failure to the parent
        q.put(("err", task_id, f"{type(e).__name__}: {e}"))


def test_two_processes_claim_disjoint_tasks_concurrently(tmp_path):
    plan = _plan()
    store = BoardStore.from_plan(plan, tmp_path)  # initialize the board
    board_dir = store.dir

    ctx = mp.get_context("fork")
    q = ctx.Queue()
    p1 = ctx.Process(target=_claim_worker, args=(str(board_dir), "T1", "omx", q))
    p2 = ctx.Process(target=_claim_worker, args=(str(board_dir), "T2", "omc", q))
    p1.start()
    p2.start()
    p1.join(timeout=20)
    p2.join(timeout=20)
    assert p1.exitcode == 0, f"p1 exited {p1.exitcode}"
    assert p2.exitcode == 0, f"p2 exited {p2.exitcode}"

    results = [q.get(timeout=5), q.get(timeout=5)]
    assert all(r[0] == "ok" for r in results), results
    providers = {r[1]: r[2] for r in results}
    assert providers == {"T1": "omx", "T2": "omc"}

    # board reflects both claims, by the right providers
    final = BoardStore.open(board_dir).load_state()
    assert final.tasks["T1"].status.value == "claimed"
    assert final.tasks["T2"].status.value == "claimed"
    assert final.tasks["T1"].provider.value == "omx"
    assert final.tasks["T2"].provider.value == "omc"
