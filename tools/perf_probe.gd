extends Node

## TEMPORARY perf probe - measure CURRENT DEFAULTS (after fixes applied).

const WORLD := "res://scenes/world/open_world_root.tscn"
const WARMUP_SECONDS := 8.0
const MEASURE_SECONDS := 20.0
const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

## CPU ablations: PERF_DISABLE names mapped to world-relative node paths. These
## are stopped with set_process + set_physics_process so the diff attributes CPU
## cost specifically (a MultiMesh is NOT hidden, so render cost is untouched).
## Motivation: every preset measures frame_ms ~= process_ms, and
## PHYSICS_3D_ACTIVE_OBJECTS avg=2, so Jolt is solving almost nothing and the
## cost must be in per-frame callbacks rather than rigid-body solving.
const CPU_ABLATION := {
	# Terrain3D region streaming (drains up to 2 baked regions per frame).
	"chunk_streamer": ["ChunkStreamer"],
	# Runtime terrain seeding/baking - the sync player-region bake plus the
	# worker-thread ring. Heaviest _process candidate.
	"terrain_stream": ["TerrainSeeder"],
	# 8 AI cars, each ticking vehicle_physics + ai_controller + engine_audio +
	# car_audio in physics ticks. Top suspect: they tick callbacks but are not
	# active Jolt bodies, which is consistent with phys_bodies staying at 2.
	"traffic": ["TrafficSpawner"],
	"living": ["LivingWorld"],
	"collectibles": ["CollectibleField"],
	"events": ["EventSession"],
	# Per-frame runtime prop/foliage scatter work (MultiMesh built once, but the
	# scatterers keep processing).
	"dressing": [
		"Foliage", "PropsFestival", "PropsLowlands",
		"PropsCoast", "PropsHighlands", "PropsAlpine",
	],
}

var _world: Node = null
var _car: Node = null
var _t := 0.0
var _phase := "warmup"
var _samples: Array = []
## Frame-stage breakdown. Godot's TIME_PROCESS / TIME_PHYSICS_PROCESS monitors
## are NOT additive with frame time (process_ms has repeatedly exceeded
## frame_ms), so they cannot be differenced to find where a frame blocks. This
## measures the frame directly instead:
##   _period  = start of one process_frame -> start of the next
##   _to_draw = start of process_frame -> RenderingServer.frame_post_draw
##   _wait    = _period - _to_draw  (engine tail + present + compositor/OS)
## High _wait with low GPU utilization means the frame is BLOCKED, not busy.
var _prev_frame_usec := 0
var _frame_start_usec := 0
var _sum_period := 0.0
var _sum_to_draw := 0.0
var _stage_frames := 0
var _max_to_draw := 0.0
var _max_period := 0.0
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
	_apply_render_scale_override()
	_apply_hide_from_env()
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	print("[perfprobe] world instanced, warming up ", WARMUP_SECONDS, "s")

## PERF_RSCALE=<float> forces `Viewport.scaling_3d_scale` AFTER the quality preset
## has been applied. 3D render scale is the cleanest available probe for whether
## `stage_todraw` is fill-bound or geometry/draw-call-bound: it multiplies
## fragment cost only and leaves vertex/primitive work untouched. Both the
## property and the mode enum were verified against ClassDB first (see
## reports/verify_scaling.gd) after `OS.get_ticks_usec` burned a run.
func _apply_render_scale_override() -> void:
	var raw := OS.get_environment("PERF_RSCALE").strip_edges()
	if raw.is_empty():
		return
	var s := raw.to_float()
	if s <= 0.0:
		print("[perfprobe] ignoring PERF_RSCALE=", raw, " (must be > 0)")
		return
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = s
	print("[perfprobe] PERF_RSCALE override -> scaling_3d_scale=", get_viewport().scaling_3d_scale)

## Runs once per rendered frame, before the scene tree's own _process pass.
func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_frame_start_usec = now
	if _prev_frame_usec != 0 and _phase == "measure":
		var period := float(now - _prev_frame_usec) / 1000.0
		_sum_period += period
		_max_period = maxf(_max_period, period)
	_prev_frame_usec = now

func _on_frame_post_draw() -> void:
	if _phase != "measure" or _frame_start_usec == 0:
		return
	var to_draw := float(Time.get_ticks_usec() - _frame_start_usec) / 1000.0
	_sum_to_draw += to_draw
	_max_to_draw = maxf(_max_to_draw, to_draw)
	_stage_frames += 1

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
		_report_primitive_breakdown()
	elif _phase == "measure":
		_samples.append(_snapshot())
		if _t >= WARMUP_SECONDS + MEASURE_SECONDS:
			_report()
			get_tree().quit()

func _apply_hide_from_env() -> void:
	# PERF_HIDE=<substring[,substring...]> hides every node whose path contains
	# a keyword, subtree included. This is a RENDER-side ablation, unlike
	# PERF_DISABLE which only stops _process/_physics_process callbacks - so it
	# is the only clean way to ask "what does drawing X cost?". Needed because
	# Terrain3D tiles are not MeshInstance3D children and so are invisible to the
	# primitive breakdown.
	var raw := OS.get_environment("PERF_HIDE").strip_edges().to_lower()
	if raw.is_empty():
		return
	for key in raw.split(",", false):
		var k := key.strip_edges()
		if k.is_empty():
			continue
		var hidden := 0
		for node in _find_all(_world):
			if node is Node3D and k in str(node.get_path()).to_lower():
				(node as Node3D).visible = false
				hidden += 1
		print("[perfprobe] PERF_HIDE '", k, "' -> hid ", hidden, " nodes")


func _report_primitive_breakdown() -> void:
	# Where the 476 draw calls / 650k primitives per frame actually come from.
	# 9.10 established the frame is GEOMETRY-bound, so this is the only
	# attribution that can point at a lever.
	#
	# Primitive counts are cached per mesh RID: `surface_get_arrays` allocates,
	# and there are only a few dozen UNIQUE meshes behind hundreds of
	# MultiMesh instances, so paying it once per mesh is cheap. Do NOT switch
	# this to `surface_get_array_len` - it does not exist in Godot 4.
	var prims_by_mesh := {}
	var by_cat := {}   # category -> [prims, instances, draws]
	var root_path := str(_world.get_path())

	for node in _find_all(_world):
		var mesh: Mesh = null
		var instances := 1
		if node is MultiMeshInstance3D:
			var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			mesh = mm.mesh
			instances = mm.visible_instance_count
			if instances <= 0:
				continue
		elif node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		else:
			continue
		if mesh == null or not (node as VisualInstance3D).is_visible_in_tree():
			continue

		var key := mesh.get_instance_id()
		if not prims_by_mesh.has(key):
			prims_by_mesh[key] = _mesh_primitive_count(mesh)
		var prims: int = prims_by_mesh[key]
		var cat := _categorize(str(node.get_path()).replace(root_path, ""))
		var row: Array = by_cat.get(cat, [0, 0, 0])
		row[0] = int(row[0]) + prims * instances
		row[1] = int(row[1]) + instances
		row[2] = int(row[2]) + 1
		by_cat[cat] = row

	var ranked := by_cat.keys()
	ranked.sort_custom(func(a, b): return int(by_cat[a][0]) > int(by_cat[b][0]))
	print("[perfprobe] --- primitive breakdown (mesh prims x visible instances) ---")
	var total := 0
	for cat in ranked:
		var row: Array = by_cat[cat]
		total += int(row[0])
		print("[perfprobe]   %-12s prims=%-9d instances=%-6d draws=%d" % [cat, int(row[0]), int(row[1]), int(row[2])])
	print("[perfprobe]   TOTAL prims=", total, " across ", prims_by_mesh.size(), " unique meshes")


func _find_all(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _mesh_primitive_count(mesh: Mesh) -> int:
	var total := 0
	for i in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.size() > 0:
			total += int(idx.size() / 3)
		else:
			total += int(verts.size() / 3)
	return total


func _categorize(rel_path: String) -> String:
	var p := rel_path.to_lower()
	if "terrain" in p or "ground" in p:
		return "terrain"
	if "foliage" in p or "grass" in p or "tree" in p or "rock" in p:
		return "foliage"
	if "prop" in p or "scatter" in p or "dresser" in p:
		return "props"
	if "road" in p or "track" in p or "rail" in p:
		return "roads"
	if "car" in p or "vehicle" in p or "wheel" in p:
		return "vehicles"
	return "other"


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
	_apply_cpu_ablation()

## Stops the named subsystems' per-frame callbacks. Deliberately does NOT hide
## anything, so a win here is CPU time and not render time.
func _apply_cpu_ablation() -> void:
	for name: String in CPU_ABLATION.keys():
		if not _disable.has(name):
			continue
		var stopped: Array[String] = []
		for path: String in CPU_ABLATION[name]:
			var node: Node = _world.get_node_or_null(NodePath(path))
			if node == null:
				continue
			node.set_process(false)
			node.set_physics_process(false)
			stopped.append(path)
		print("[perfprobe] CPU ablation OFF: ", name, " -> ", stopped)

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
	# Self-consistent frame breakdown (see _prev_frame_usec docs). _wait is the
	# engine tail + present + compositor; if that dominates while GPU util is low,
	# the frame is blocked rather than busy.
	if _stage_frames > 0:
		var s := float(_stage_frames)
		var period := _sum_period / s
		var to_draw := _sum_to_draw / s
		print("[perfprobe] -- frame stages over ", _stage_frames, " frames --")
		print("[perfprobe] stage_period avg=", snappedf(period, 0.1), " max=", snappedf(_max_period, 0.1))
		print("[perfprobe] stage_todraw  avg=", snappedf(to_draw, 0.1), " max=", snappedf(_max_to_draw, 0.1))
		print("[perfprobe] stage_wait    avg=", snappedf(period - to_draw, 0.1), "  (engine tail + present + compositor)")
		print("[perfprobe] ==========================================================")