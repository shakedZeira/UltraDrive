extends Node

## TEMPORARY perf probe - measure CURRENT DEFAULTS (after fixes applied).

const WORLD := "res://scenes/world/open_world_root.tscn"
const WARMUP_SECONDS := 8.0
const MEASURE_SECONDS := 20.0
const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

var _world: Node = null
var _car: Node = null
var _t := 0.0
var _phase := "warmup"
var _samples: Array = []
var _preset_override := -1
var _preset_label := "default"

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var win := DisplayServer.window_get_size()
	print("[perfprobe] window=", win, " adapter=", RenderingServer.get_video_adapter_name())
	print("[perfprobe] Engine.physics_ticks_per_second=", Engine.physics_ticks_per_second)
	print("[perfprobe] Viewport.msaa_3d=", get_viewport().msaa_3d)
	_world = load(WORLD).instantiate()
	add_child(_world)
	_apply_preset_from_env()
	print("[perfprobe] world instanced, warming up ", WARMUP_SECONDS, "s")

func _physics_process(delta: float) -> void:
	_t += delta
	if _preset_override >= 0 and _t < 1.0:
		_apply_override()
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

func _apply_preset_from_env() -> void:
	var raw := OS.get_environment("PERF_QUALITY").strip_edges()
	if raw.is_empty():
		return
	var index := 1
	match raw.to_lower():
		"low":
			index = 0
		"high":
			index = 2
		"medium":
			index = 1
		_:
			print("[perfprobe] unknown PERF_QUALITY=", raw, " (expected low|medium|high), using medium")
	_preset_override = index
	_preset_label = raw.to_lower()
	_apply_override()
	print("[perfprobe] preset applied: ", _preset_label, " (index ", index, ")")
	_describe_quality()

func _apply_override() -> void:
	SettingsMenuScript.apply_to_scene_tree(_preset_override, _world, get_viewport())

func _describe_quality() -> void:
	var env: Environment = SettingsMenuScript.find_scene_environment(_world)
	var vp := get_viewport()
	if env:
		print("[perfprobe] env: sdfgi=", env.sdfgi_enabled, " ssao=", env.ssao_enabled, " glow=", env.glow_enabled, " volfog=", env.volumetric_fog_enabled, " ssr=", env.ssr_enabled, " tonemap=", env.tonemap_mode, " sdfgi_energy=", env.sdfgi_energy)
	print("[perfprobe] viewport: msaa=", vp.msaa_3d, " scaling_mode=", vp.scaling_3d_mode, " scale=", vp.scaling_3d_scale)

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
	_describe_quality()
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
	print("[perfprobe] ================= RESULT [", _preset_label, "] =================")
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