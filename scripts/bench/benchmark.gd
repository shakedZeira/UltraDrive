# scripts/bench/benchmark.gd
class_name PerfBench
extends Node

## AAA-2 reference-scene perf harness (docs/plans/aaa_roadmap_plan.md §AAA-2).
##
## WHAT THIS MEASURES (be honest):
##   This harness runs the reference scene under a FIXED timestep and measures
##   the CPU/process budget the reference scene needs to keep the game running,
##   averaged over a fixed wall-clock window per preset. In headless mode there
##   is no renderer, so no GPU knob (SDFGI/SSR/volumetrics/MSAA/FSR) is
##   exercised here — the GPU-side locked-60 claim is the GTX 970 reference
##   machine's job, measured there with tools/perf_probe.tscn (windowed) at
##   1080p. On any machine the gate this harness feeds asserts the honest CPU
##   fixed-timestep budget: process + physics must fit inside one 60 Hz frame
##   (CONTRACT_FRAME_BUDGET_MS = 16.7 ms) or the game cannot keep a locked 60
##   no matter what the GPU does. The two signals stay orthogonal and both are
##   documented at the top of tests/suites/test_perf_gate.gd.
##
## DETERMINISM:
##   - Fixed scene (REFERENCE_SCENE), fixed preset order [Low, Medium, High],
##     fixed warmup/measure windows, no RNG, no player input override (the car
##     sits still so streaming settles instead of churning regions while we
##     sample).
##   - Rows are sampled once per physics tick; the averaged metrics are
##     deterministic up to machine noise because the scene, windows and preset
##     ladder are fixed.
##
## LEAK-FREE:
##   The bench instantiates the reference scene under itself and stops the
##   TerrainSeeder worker before freeing it (_exit_tree tears down both), so a
##   caller can simply add_child(bench) ... then bench.free().

## Same reference scene the 7ffb524 preset probes and tools/perf_probe.gd use.
const REFERENCE_SCENE := "res://scenes/world/open_world_root.tscn"
const WARMUP_SECONDS := 3.0
const MEASURE_SECONDS := 3.0
## GTX-970-calibrated fixed-timestep budget: 1000 ms / 60 Hz = 16.7 ms per
## frame. This is the contract threshold the gate asserts against (never
## loosened for a slow machine).
const CONTRACT_FRAME_BUDGET_MS := 16.7
const PRESET_IDS: Array[int] = [0, 1, 2]
const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

## Rows measured by the last run_bench(), one per preset:
## [ {"preset_id": int, "preset_name": String, "avg_ms": float,
##    "avg_process_ms": float, "avg_physics_ms": float, "samples": int}, ... ]
var rows: Array = []

## The reference scene under test, owned by this bench.
var _reference_scene: Node = null
var _sample_timer := 0.0
var _measure_elapsed := 0.0
var _phase := "idle"
var _current_preset := 0
var _samples: Array = []

func _exit_tree() -> void:
	_teardown_scene()

## Helper used by the CLI tool (tools/bench_probe) and by the gate suite to
## measure a single preset. Runs the full reference-scene bench for one preset
## id and returns its row. Headless-safe.
func measure_preset(preset_id: int) -> Dictionary:
	var all: Array = await run_bench([preset_id])
	for row: Dictionary in all:
		if int(row["preset_id"]) == preset_id:
			return row
	return {}

## Instantiates the reference scene once and measures each requested preset in
## order (default: Low, Medium, High). Each preset gets its own warmup +
## measure window. Returns one row per preset with the averaged fixed-timestep
## budget in ms ("avg_ms") plus the process/physics breakdown. Deterministic,
## headless-safe, leak-free (worker stopped + scene freed on return).
func run_bench(preset_ids: Array = PRESET_IDS) -> Array:
	rows.clear()
	if _reference_scene == null or not is_instance_valid(_reference_scene):
		_spawn_scene()
		if _reference_scene == null:
			push_warning("[bench] reference scene failed to instantiate")
			return rows
	# Let the scene's _ready bootstrap settle before the first measurement.
	await _physics_seconds(0.5)
	for preset_id in preset_ids:
		var index := clampi(int(preset_id), 0, 2)
		_apply_preset(index)
		var row := await _measure_preset(index)
		rows.append(row)
	_teardown_scene()
	return rows

## Pure, deterministic preset picker: returns the highest-quality preset id
## whose measured avg frame-time rows are inside the CONTRACT_FRAME_BUDGET_MS
## window (Low = 0 when none fit). Any id returned is always in the ladder.
## The gate asserts both determinism and ladder validity. The runtime first-boot
## auto-pick stays SettingsMenuScript.default_quality_preset() — this picker is
## only the harness's own recommendation surface.
static func pick_preset(measured_rows: Array) -> int:
	var best := 0
	for row: Dictionary in measured_rows:
		var preset_id := clampi(int(row.get("preset_id", 0)), 0, 2)
		var avg_ms := float(row.get("avg_ms", INF))
		if avg_ms <= CONTRACT_FRAME_BUDGET_MS:
			best = maxi(best, preset_id)
	return clampi(best, 0, 2)

func _spawn_scene() -> void:
	_reference_scene = (load(REFERENCE_SCENE) as PackedScene).instantiate()
	add_child(_reference_scene)

func _apply_preset(preset_id: int) -> void:
	SettingsMenuScript.apply_to_scene_tree(preset_id, _reference_scene, get_viewport())
	_current_preset = preset_id

func _measure_preset(preset_id: int) -> Dictionary:
	_sample_timer = 0.0
	_measure_elapsed = 0.0
	_samples.clear()
	_phase = "warmup"
	# Warm the preset: let env re-apply + streaming settle so the measure window
	# captures steady state, never cache-cold startup.
	await _physics_seconds(WARMUP_SECONDS)
	_phase = "measure"
	_samples.clear()
	await _physics_seconds(MEASURE_SECONDS)
	_phase = "idle"
	return _average_row(preset_id)

## Idle-process sampler: every physics tick during the measure phase we record
## the engine's real frame-time as 1000 / fps plus the process/physics monitor
## values. Averaging the per-tick frame-time over the window is the honest
## headless CPU budget signal.
func _physics_process(delta: float) -> void:
	if _phase != "measure":
		return
	_sample_timer += delta
	_measure_elapsed += delta
	_samples.append({
		"fps": Engine.get_frames_per_second(),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	})

func _average_row(preset_id: int) -> Dictionary:
	if _samples.is_empty():
		return {
			"preset_id": preset_id,
			"preset_name": _preset_name(preset_id),
			"avg_ms": INF,
			"avg_process_ms": INF,
			"avg_physics_ms": INF,
			"samples": 0,
		}
	var n := float(_samples.size())
	var sum_fps := 0.0
	var sum_process := 0.0
	var sum_physics := 0.0
	for s: Dictionary in _samples:
		sum_fps += float(s["fps"])
		sum_process += float(s["process_ms"])
		sum_physics += float(s["physics_ms"])
	var avg_fps := sum_fps / n
	var avg_ms := 1000.0 / maxf(avg_fps, 0.01)
	return {
		"preset_id": preset_id,
		"preset_name": _preset_name(preset_id),
		"avg_ms": avg_ms,
		"avg_process_ms": sum_process / n,
		"avg_physics_ms": sum_physics / n,
		"samples": _samples.size(),
	}

static func _preset_name(preset_id: int) -> String:
	match clampi(preset_id, 0, 2):
		0:
			return "low"
		1:
			return "medium"
		_:
			return "high"

## Awaits N seconds of real physics time by ticking one physics frame at a
## time, so the coastal timer advances deterministically with the fixed
## timestep instead of a wall-clock timer.
func _physics_seconds(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		await get_tree().physics_frame
		remaining -= 1.0 / float(Engine.physics_ticks_per_second)

## Frees the reference scene and stops the TerrainSeeder worker (joins the
## thread) so the bench teardown is leak-free. Safe to call twice.
func _teardown_scene() -> void:
	if _reference_scene == null or not is_instance_valid(_reference_scene):
		_reference_scene = null
		return
	var seeder := _reference_scene.get_node_or_null("TerrainSeeder")
	if seeder != null and seeder.has_method("_stop_worker"):
		seeder.call("_stop_worker")
	_reference_scene.free()
	_reference_scene = null