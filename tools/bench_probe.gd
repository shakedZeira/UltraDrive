# tools/bench_probe.gd
extends Node

## Headless CLI driver for the AAA-2 reference-scene bench harness
## (scripts/bench/benchmark.gd). Prints one row per preset: the honest CPU
## fixed-timestep budget (avg_ms) against the CONTRACT_FRAME_BUDGET_MS window
## and the process/physics breakdown, then quits. GPU-side 60 fps is the GTX
## 970 reference machine's job — use tools/perf_probe.tscn there (windowed).

const PerfBenchScript: GDScript = preload("res://scripts/bench/benchmark.gd")

var _bench: Node = null
var _started := false

func _ready() -> void:
	_bench = PerfBench.new()
	add_child(_bench)
	_run()

func _run() -> void:
	print("[bench] reference=", PerfBenchScript.REFERENCE_SCENE)
	print("[bench] contract_budget_ms=", PerfBenchScript.CONTRACT_FRAME_BUDGET_MS)
	print("[bench] warmup=", PerfBenchScript.WARMUP_SECONDS, "s measure=", PerfBenchScript.MEASURE_SECONDS, "s")
	var rows: Array = await _bench.run_bench()
	print("[bench] ================ RESULT ================")
	for row: Dictionary in rows:
		var preset_id := int(row["preset_id"])
		var avg_ms := float(row["avg_ms"])
		var process_ms := float(row["avg_process_ms"])
		var physics_ms := float(row["avg_physics_ms"])
		var samples := int(row["samples"])
		var within: String = "PASS" if avg_ms <= PerfBenchScript.CONTRACT_FRAME_BUDGET_MS else "OVER"
		print("[bench] preset=", row["preset_name"], " (", preset_id, ") avg_ms=",
				snappedf(avg_ms, 0.01), " process_ms=", snappedf(process_ms, 0.01),
				" physics_ms=", snappedf(physics_ms, 0.01), " samples=", samples,
				" budget_16.7=", within)
	var picked: int = PerfBenchScript.pick_preset(rows)
	print("[bench] pick_preset=", picked, " (", PerfBenchScript._preset_name(picked), ")")
	print("[bench] ================================")
	get_tree().quit()