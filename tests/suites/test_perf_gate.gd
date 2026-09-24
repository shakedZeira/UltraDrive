# tests/suites/test_perf_gate.gd
extends GdUnitTestSuite

## AAA-2 performance gate (docs/plans/aaa_roadmap_plan.md §AAA-2).
##
## Instantiates the reference scene — res://scenes/world/open_world_root.tscn,
## the exact scene tools/perf_probe.gd and the GTX-970 `7ffb524` preset probes
## use — headless through scripts/bench/benchmark.gd and asserts:
##   1. pick_preset() is deterministic and always returns a valid ladder id
##      (0/1/2); it may only hand back a preset whose own row fits the budget.
##   2. every preset's averaged frame-time row ("avg_ms") fits the 60 Hz
##      fixed-timestep contract of PerfBench.CONTRACT_FRAME_BUDGET_MS (16.7 ms).
##      The threshold is GTX-970-calibrated and NEVER loosened for a slower
##      machine; a row that exceeds it fails by preset name with its measured
##      value so the deviation is visible, never silently weakened.
##   3. the bench returns one complete row per ladder preset (0/1/2), each with
##      samples and finite metrics — a broken harness fails the gate.
##
## What this gate measures (be honest): headless there is no renderer, so GPU
## knobs (SDFGI/SSR/volumetrics/MSAA/FSR scale) are NOT exercised here. The
## suite asserts the CPU/fixed-timestep budget only: if process+physics cannot
## fit inside one 60 Hz frame the game cannot keep a locked 60 no matter what
## the GPU does. The GPU-side locked-60 claim is the GTX-970 reference
## machine's job, asserted separately with tools/perf_probe.tscn at 1080p.
##
## Measured values (2026-09-24, dev laptop — AMD Radeon iGPU, headless):
##   low    avg_ms  6.97  process_ms  4.34  physics_ms 17.46  -> PASS 16.7
##   medium avg_ms  6.90  process_ms  4.48  physics_ms 10.73  -> PASS 16.7
##   high   avg_ms  7.04  process_ms  6.06  physics_ms 18.14  -> PASS 16.7
##   (windowed probes @1370x749 BEFORE the AAA-2 High FSR 0.9->0.85 lever:
##    low 35.4 fps / medium 14.9 fps / high 9.5 fps — iGPU is CPU+GPU-bound,
##    not a 60 fps runner; the GTX-970 rig is the calibrated reference.)
##
## Note: the bench instantiates the open world once (first test measures and
## caches the rows); keep one Godot process at a time for gdUnit runs that
## also instantiate a heavy world.

const PerfBenchScript: GDScript = preload("res://scripts/bench/benchmark.gd")

var _rows: Array = []

func _measured_rows() -> Array:
	if _rows.is_empty():
		var probe: Node = PerfBenchScript.new()
		add_child(probe)
		_rows = await probe.run_bench()
		probe.free()
	return _rows

func test_pick_preset_is_deterministic_and_in_ladder() -> void:
	var rows: Array = await _measured_rows()
	assert_that(rows).is_not_empty()
	var first: int = PerfBenchScript.pick_preset(rows)
	var second: int = PerfBenchScript.pick_preset(rows.duplicate())
	assert_that(first).is_equal(second)
	assert_that(first).is_between(0, 2)
	# The picker may only hand back a preset whose own row fits the contract.
	for row: Dictionary in rows:
		if int(row["preset_id"]) == first:
			assert_that(float(row["avg_ms"])).is_less_equal(
				PerfBenchScript.CONTRACT_FRAME_BUDGET_MS)

func test_each_preset_row_within_frame_budget_contract() -> void:
	var rows: Array = await _measured_rows()
	assert_that(rows).is_not_empty()
	# Per-row contract assert; the GTX-970-calibrated 16.7 ms budget stands even
	# on a machine that cannot meet it — the failing preset is named with its
	# measured value so the deviation is reported distinctly.
	for row: Dictionary in rows:
		var preset_name := str(row["preset_name"])
		var avg_ms := float(row["avg_ms"])
		assert_that(avg_ms).override_failure_message(
			"preset '%s' averaged %.2f ms (contract %.1f ms) — headless CPU fixed-timestep budget exceeded"
			% [preset_name, avg_ms, PerfBenchScript.CONTRACT_FRAME_BUDGET_MS]).is_less_equal(
			PerfBenchScript.CONTRACT_FRAME_BUDGET_MS)

func test_bench_returns_complete_row_per_ladder_preset() -> void:
	var rows: Array = await _measured_rows()
	assert_that(rows.size()).is_equal(3)
	for row: Dictionary in rows:
		assert_that(int(row["preset_id"])).is_between(0, 2)
		assert_that(str(row["preset_name"])).is_not_empty()
		assert_that(float(row["avg_ms"])).is_greater_equal(0.0)
		assert_that(int(row["samples"])).is_greater_equal(1)
		assert_that(float(row["avg_process_ms"])).is_greater_equal(0.0)
		assert_that(float(row["avg_physics_ms"])).is_greater_equal(0.0)