"""Plan + atomic Task DAG (spec §6.1).

The compiler emits atomic Task documents and proves the dependency graph is
acyclic. Construction itself rejects cycles, unknown edges, and duplicate ids.
"""

from collections import deque

from pydantic import BaseModel, Field, model_validator

from loop_engineer.contracts.task import Task


class TaskNode(BaseModel):
    task: Task


class DependencyEdge(BaseModel):
    from_id: str
    to_id: str


class Wave(BaseModel):
    """A set of Tasks with all dependencies satisfied; legal overlap unit (spec §8)."""

    task_ids: list[str] = Field(min_length=1)


class Plan(BaseModel):
    goal_id: str = Field(min_length=1)
    nodes: list[TaskNode] = Field(min_length=1)
    edges: list[DependencyEdge] = Field(default_factory=list)

    @model_validator(mode="after")
    def _validate_graph(self) -> "Plan":
        ids = [n.task.id for n in self.nodes]
        if len(ids) != len(set(ids)):
            raise ValueError("duplicate task ids in plan")
        id_set = set(ids)
        for e in self.edges:
            if e.from_id not in id_set or e.to_id not in id_set:
                raise ValueError(f"edge references unknown task: {e.from_id}->{e.to_id}")
        declared = {(e.from_id, e.to_id) for e in self.edges}
        for n in self.nodes:
            for dep in n.task.dependencies:
                if (dep, n.task.id) not in declared:
                    raise ValueError(
                        f"task {n.task.id} declares dependency on {dep} with no matching edge"
                    )
        if not self.is_acyclic():
            raise ValueError("plan dependency graph has a cycle")
        return self

    def _adjacency(self) -> dict[str, list[str]]:
        adj: dict[str, list[str]] = {n.task.id: [] for n in self.nodes}
        for e in self.edges:
            adj[e.from_id].append(e.to_id)
        return adj

    def is_acyclic(self) -> bool:
        """Kahn's algorithm; True iff a topological order covers every node."""
        adj = self._adjacency()
        indeg = {nid: 0 for nid in adj}
        for _src, dsts in adj.items():
            for d in dsts:
                indeg[d] += 1
        q = deque(sorted(nid for nid, deg in indeg.items() if deg == 0))
        seen = 0
        while q:
            n = q.popleft()
            seen += 1
            for d in sorted(adj[n]):
                indeg[d] -= 1
                if indeg[d] == 0:
                    q.append(d)
        return seen == len(indeg)

    def topological_order(self) -> list[str]:
        """Return a deterministic topological ordering; raises if cyclic."""
        if not self.is_acyclic():
            raise ValueError("cannot order a cyclic plan")
        adj = self._adjacency()
        indeg = {nid: 0 for nid in adj}
        for _src, dsts in adj.items():
            for d in dsts:
                indeg[d] += 1
        q = deque(sorted(nid for nid, deg in indeg.items() if deg == 0))
        order: list[str] = []
        while q:
            n = q.popleft()
            order.append(n)
            for d in sorted(adj[n]):
                indeg[d] -= 1
                if indeg[d] == 0:
                    q.append(d)
        return order
