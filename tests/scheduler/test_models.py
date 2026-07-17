from loop_engineer.contracts.provider import Provider
from loop_engineer.scheduler.models import (
    CapacityConfig,
    Conflict,
    ConflictDimension,
    Launch,
    LaunchPlan,
    PlannerConfig,
    TaskExecutionMeta,
)


def test_capacity_defaults_match_operator_spec():
    c = CapacityConfig()
    assert (c.omx_max, c.omc_max, c.global_max, c.finish_max, c.burst_max) == (3, 3, 3, 1, 4)


def test_planner_config_default_protected_refer():
    assert PlannerConfig().protected_paths == ["refer/"]


def test_task_execution_meta_defaults():
    m = TaskExecutionMeta(task_id="T1")
    assert m.migration_dir is None and m.ports == [] and m.engine_hint is None


def test_conflict_and_launch_models():
    c = Conflict(
        candidate="T2", other="T1", dimension=ConflictDimension.ALLOWED_FILES, reason="x"
    )
    launch = Launch(task_id="T2", provider=Provider.OMC)
    lp = LaunchPlan(
        launch=[launch],
        skipped=[c],
        blocked=[],
        active_omx=1,
        active_omc=0,
        remaining_global=2,
        burst=False,
    )
    assert lp.launch[0].provider == Provider.OMC
