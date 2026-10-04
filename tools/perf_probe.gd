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
## Comma-separated effect names forced OFF after the preset is applied, read from
## PERF_DISABLE. Leave-one-out attribution of the GPU cost: run the full preset,
## then disable exactly one effect and diff. Names: sdfgi, ssr, volfog, glow,
## ssao, shadows. Empty = no ablation.
var _disable: Dictionary = {}
## SDFGI tuning overrides, applied after the preset. SDFGI is the dominant GPU
## cost at High, so this is how we test whether a CHEAPER SDFGI can hold the
## look without the full-fat cascade march.
var _sdfgi_cascades := 0
var _sdfgi_max_dist := 0.0
var _sdfgi_cascade0 := 0.0

func _parse_tuning() -> void:
	_sdfgi_cascades = int(OS.get_environment("PERF_SDFGI_CASCADES"))
	_sdfgi_max_dist = float(OS.get_environment("PERF_SDFGI_MAXDIST"))
	_sdfgi_cascade0 = float(OS.get_environment("PERF_SDFGI_CASCADE0"))
	if _sdfgi_cascades > 0 or _sdfgi_max_dist > 0.0 or _sdfgi_cascade0 > 0.0:
		print("[perfprobe] sdfgi tuning: cascades=", _sdfgi_cascades,
				" max_dist=", _sdfgi_max_dist, " cascade0=", _sdfgi_cascade0)

func _parse_disable() -> void:
	_disable.clear()
	var raw := OS.get_environment("PERF_DISABLE").strip_edges().to_lower()
	if raw.is_empty():
		return
	for token in raw.split(",", false):
		var name := token.strip_edges()
		if not name.is_empty():
			_disable[name] = true
	print("[perfprobe] ablation DISABLING: ", _disable.keys())

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var win := DisplayServer.window_get_size()
	print("[perfprobe] window=", win, " adapter=", RenderingServer.get_video_adapter_name())
	print("[perfprobe] Engine.physics_ticks_per_second=", Engine.physics_ticks_per_second)
	print("[perfprobe] Viewport.msaa_3d=", get_viewport().msaa_3d)
	_world = load(WORLD).instantiate()
	add_child(_world)
	_parse_disable()
	_parse_tuning()
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
	_apply_ablation()

## Forces the PERF_DISABLE effects off AFTER the ladder wrote them, so the
## ablation always wins over the preset regardless of apply order.
func _apply_ablation() -> void:
	if _disable.is_empty():
		return
	var env: Environment = SettingsMenuScript.find_scene_environment(_world)
	if env:
		if _disable.has("sdfgi"):
			env.sdfgi_enabled = false
		if _disable.has("ssr"):
			env.ssr_enabled = false
		if _disable.has("volfog"):
			env.volumetric_fog_enabled = false
		if _disable.has("glow"):
			env.glow_enabled = false
		if _disable.has("ssao"):
			env.ssao_enabled = false
	if _disable.has("shadows"):
		var light: DirectionalLight3D = SettingsMenuScript.find_scene_directional_light(_world)
		if light:
			light.shadow_enabled = false
	if env and _sdfgi_cascades > 0:
		env.sdfgi_cascades = _sdfgi_cascades
	if env and _sdfgi_max_dist > 0.0:
		env.sdfgi_max_distance = _sdfgi_max_dist
	if env and _sdfgi_cascade0 > 0.0:
		env.sdfgi_cascade0_distance = _sdfgi_cascade0

func _describe_quality() -> void:
	var env: Environment = SettingsMenuScript.find_scene_environment(_world)
	var vp := get_viewport()
	if env:
		print("[perfprobe] env: sdfgi=", env.sdfgi_enabled, " ssao=", env.ssao_enabled, " glow=", env.glow_enabled, " volfog=", env.volumetric_fog_enabled, " ssr=", env.ssr_enabled, " tonemap=", env.tonemap_mode, " sdfgi_energy=", env.sdfgi_energy)
		print("[perfprobe] sdfgi: cascades=", env.sdfgi_cascades, " cascade0=", env.sdfgi_cascade0_distance, " max_dist=", env.sdfgi_max_distance)
	print("[perfprobe] viewport: msaa=", vp.msaa_3d, " scaling_mode=", vp.scaling_3d_mode, " scale=", vp.scaling_3d_scale)
	var light: DirectionalLight3D = SettingsMenuScript.find_scene_directional_light(_world)
	if light:
		print("[perfprobe] sun: shadows=", light.shadow_enabled, " mode=", light.directional_shadow_mode, " max_dist=", light.directional_shadow_max_distance, " fade=", light.directional_shadow_fade_start)

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
	var sum_bodies := 0.0
	var min_fps := 999999; var max_fps := 0
	for s: Dictionary in _samples:
		sum_fps += float(s["fps"])
		sum_proc += float(s["process_ms"])
		sum_phys += float(s["physics_ms"])
		sum_prims += float(s["prims"])
		sum_draw += float(s["draw_calls"])
		sum_vram += float(s["vram_mb"])
		sum_bodies += float(s["bodies"])
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
	# CPU attribution: every preset now measures frame_ms ~= process_ms, so the
	# frame is CPU-bound. Physics share + active body count says whether Jolt is
	# the cost and whether body count is the lever.
	print("[perfprobe] phys_bodies avg=", int(sum_bodies/n))
	print("[perfprobe] phys_share  avg=", snappedf((sum_phys/n) / maxf(sum_proc/n, 0.01) * 100.0, 0.1), "% of process")
	print("[perfprobe] ==========================================================")