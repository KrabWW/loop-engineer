"""Goal compiler: GoalDefinition -> Plan (spec P2a §3).

Constructs TaskNode per task and a DependencyEdge per declared dependency; the
P1 Plan model validates acyclicity, unknown edges, duplicate ids, and
declared-dependency-without-edge at construction time.
"""

from loop_engineer.compiler.definition import GoalDefinition
from loop_engineer.contracts.plan import DependencyEdge, Plan, TaskNode


def compile_goal(definition: GoalDefinition) -> Plan:
    nodes = [TaskNode(task=t) for t in definition.tasks]
    edges: list[DependencyEdge] = []
    for t in definition.tasks:
        for dep in t.dependencies:
            edges.append(DependencyEdge(from_id=dep, to_id=t.id))
    return Plan(goal_id=definition.goal.id, nodes=nodes, edges=edges)
