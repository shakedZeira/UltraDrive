extends Node

## TEMPORARY perf probe - measure CURRENT DEFAULTS (after fixes applied).

const WORLD := "res://scenes/world/open_world_root.tscn"
const WARMUP_SECONDS := 8.0
const MEASURE_SECONDS := 20.0

var _world: Node = null
var _car: Node = null
var _t := 0.0
var _phase := "warmup"
var _samples: Array = []

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var win := DisplayServer.window_get_size()
	print("[perfprobe] window=", win, " adapter=", RenderingServer.get_video_adapter_name())
	print("[perfprobe] Engine.physics_ticks_per_second=", Engine.physics_ticks_per_second)
	print("[perfprobe] Viewport.msaa_3d=", get_viewport().msaa_3d)
	_world = load(WORLD).instantiate()
	add_child(_world)
	print("[perfprobe] world instanced, warming up ", WARMUP_SECONDS, "s")

func _physics_process(delta: float) -> void:
	_t += delta
	if _car == null:
		_car = _world.get_node_or_null("%PlayerCar")
	if _car != null and _car.has_method("set_input_override"):
		_car.call("set_input_override", Vector2(sin(_t * 1.2) * 0.25, 1.0))
	if _phase == "warmup" and _t >= WARMUP_SECONDS:
		_phase = "measure"
		print("[perfprobe] measuring ", MEASURE_SECONDS, "s")
	elif _phase == "measure":
		_samples.append(_snapshot())
		if _t >= WARMUP_SECONDS + MEASURE_SECONDS:
			_report()
			get_tree().quit()

func _snapshot() -> Dictionary:
	return {
		"fps": Engine.get_frames_per_second(),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"bodies": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"vram_mb": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576,
	}

func _report() -> void:
	if _samples.is_empty():
		print("[perfprobe] NO SAMPLES")
		return
	var n := float(_samples.size())
	var sum_fps := 0.0; var sum_proc := 0.0; var sum_phys := 0.0; var sum_prims := 0.0; var sum_draw := 0.0; var sum_vram := 0.0
	var min_fps := 999999; var max_fps := 0
	for s: Dictionary in _samples:
		sum_fps += float(s["fps"])
		sum_proc += float(s["process_ms"])
		sum_phys += float(s["physics_ms"])
		sum_prims += float(s["prims"])
		sum_draw += float(s["draw_calls"])
		sum_vram += float(s["vram_mb"])
		min_fps = mini(min_fps, int(s["fps"]))
		max_fps = maxi(max_fps, int(s["fps"]))
	var avg_fps := sum_fps / n
	var fps_safe := maxf(avg_fps, 0.01)
	var ticks_per_frame := float(Engine.physics_ticks_per_second) / fps_safe
	var physics_ms_per_tick := (sum_phys / n) * fps_safe / float(Engine.physics_ticks_per_second)
	print("[perfprobe] ================= CURRENT DEFAULTS RESULT =================")
	print("[perfprobe] fps         avg=", snappedf(avg_fps, 0.1), " min=", min_fps, " max=", max_fps)
	print("[perfprobe] frame_ms    avg=", snappedf(1000.0/fps_safe, 0.1))
	print("[perfprobe] process_ms  avg=", snappedf(sum_proc/n, 0.1))
	print("[perfprobe] physics_ms  avg=", snappedf(sum_phys/n, 0.1))
	print("[perfprobe] physics_ms/tick  avg=", snappedf(physics_ms_per_tick, 0.1))
	print("[perfprobe] ticks_per_frame  avg=", snappedf(ticks_per_frame, 0.1))
	print("[perfprobe] draw_calls  avg=", int(sum_draw/n))
	print("[perfprobe] primitives  avg=", int(sum_prims/n))
	print("[perfprobe] vram_mb     avg=", int(sum_vram/n))
	print("[perfprobe] ==========================================================")