# scripts/capture/menu_clip_recorder.gd
class_name MenuClipRecorder
extends Node3D

## Capture harness for the main-menu background clips (plan
## docs/plans/main_menu_video_bg_plan.md §3B). This node is the ROOT of a
## dedicated capture scene that instances open_world_root.tscn as a child --
## the real world scene and world_driver.gd are never touched (D9).
##
## It runs the engine headlessly-enough through Godot's Movie Writer
## (--write-movie, launched by tools/record_menu_clips.py): a small phase
## machine (boot -> hold -> settle -> capture) waits out the world bootstrap
## and the first terrain bake, arms a deterministic scripted shot, then prints
## frame markers and quits. The Python harness trims everything outside the
## markers and strips the always-present Vorbis track in post.
##
## Determinism rules honoured here:
##   - quality forced to High on the LIVE tree, and re-applied at the end of
##     boot: GameState._ready defers one frame and then re-applies the SAVED
##     preset (Low on the reference GTX 970), which would clobber a one-shot
##     apply done in _ready. Plain field assignments only -- never
##     set_quality_preset/set_probe_enabled, which would write the save.
##   - DayNightDriver disabled, clock fixed to `hour`, weather forced CLEAR.
##   - ambient traffic/living world switched off; the shot car is driven only
##     through TrafficDriver (input_override) with the player-proximity probe
##     pinned at FAR_AWAY so its STOP_GAP latch can never fire.
##
## Marker protocol (parsed by tools/record_menu_clips.py):
##   CAPTURE_READY frame=<n>   first frame of the wanted content
##   CAPTURE_END   frame=<n>   last frame; the engine quits right after
##   CAPTURE_ERROR <message>   shot failed; the engine exits with code 1

## settings_menu.gd has no class_name; preload it exactly like perf_probe.gd
## and game_state.gd do.
const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

## Boot phase: physics ticks to wait out WorldDriver's 8-step bootstrap
## (8 awaited frames + a ~3.3 s synchronous terrain bake) before giving up.
const BOOT_TICK_CAP: int = 3600
## Hold phase: ticks to keep re-planting the car at the shot origin waiting
## for real terrain/road collision under it (~30 s at 60 Hz).
const HOLD_TICK_CAP: int = 1800
## Settle ticks between "ground proven" and the CAPTURE_READY marker: lets
## the suspension land and the chase camera converge after the teleport.
const SETTLE_TICKS: int = 45
## Ground-ready ray: from this far above the car origin, this far down.
const GROUND_RAY_UP: float = 3.0
const GROUND_RAY_DOWN: float = 25.0
## Pan shot: pivot height above the parked car, and the world-far point the
## TrafficDriver player-proximity probe is pinned at (its STOP_GAP is 5 m).
const PAN_PIVOT_HEIGHT: float = 1.2
const FAR_AWAY: Vector3 = Vector3(1e9, 0.0, 1e9)
## Pan sweep: PanPivot yaw at the first and last captured frame. The scene's
## PanAnimation clip sweeps -0.42 -> +0.42 rad over 16 s, but the sweep here is
## driven by FRAME COUNT in _process, NOT by that AnimationPlayer: on this
## scene a wall-clock-driven clip finishes in the first handful of frames (the
## pass/pan shots render at ~0.2-2 s per frame) and the rest of the clip is a
## static frame. Tied to drawn frames, the sweep is exactly duration_sec long.
const PAN_YAW_START: float = -0.42
const PAN_YAW_END: float = 0.42
## Movie Writer output rate ([editor] movie_writer/fps=30 and --fixed-fps 30).
## The capture window is measured in DRAWN FRAMES at this rate, NOT in summed
## physics delta -- see _tick_capture for why that distinction is load-bearing.
const MOVIE_FPS: float = 30.0

## Chase shot: the gameplay ChaseCamera sits 2.5 m above the car origin and
## LAGS behind it (follow_speed 5), with NO collision/spring arm -- so on the
## hub route it drifts off the road centreline and passes through roadside tree
## foliage, blacking out ~0.3-0.7 s twice (frames 212-218 and 353-371 of
## menu_drive_hub.ogv: dark-green frames, mean luma ~6). The capture pulls the
## rig lower and tighter (the car clears the same canopy at road level) so the
## camera follows the car's own clear path instead of the foliage. Capture-time
## property writes only -- chase_camera.gd and gameplay are untouched.
const CHASE_CAM_HEIGHT: float = 1.2
const CHASE_CAM_DISTANCE: float = 4.5
const CHASE_CAM_FOLLOW_SPEED: float = 12.0

## Which clip this scene records: "hub", "pass" or "pan" (log/message label).
@export var shot: String = "hub"
## Length of the WANTED capture window, in seconds (the trimmed clip length).
@export var duration_sec: float = 18.0
## RoadDef.id of the road the shot runs on ("hub-ring", "pass-loop").
@export var road_name: String = "hub-ring"
## "chase" = TrafficDriver cruise along the road; "pan" = parked car, camera
## sweep around it driven from the capture frame count (see PAN_YAW_START).
@export var mode: String = "chase"
## Fixed time of day for the shot (WeatherManager hours).
@export var hour: float = 10.0
## Cruise speed for the chase shot (km/h).
@export var cruise_kmh: float = 90.0

var _world: Node3D
var _car: VehiclePhysics
var _driver: TrafficDriver
var _fallback: StaticBody3D
var _pan_camera: Camera3D
var _pan_pivot: Node3D
var _phase: String = "boot"
var _boot_ticks: int = 0
var _hold_ticks: int = 0
var _settle_ticks: int = 0
## Engine.get_frames_drawn() at the CAPTURE_READY marker, and how many drawn
## frames the capture window should hold: the window is counted in DRAWN FRAMES
## from here, not in accumulated physics delta (see _process).
var _capture_start_frame: int = 0
var _capture_target_frames: int = 0
var _hold_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	_world = get_node_or_null("OpenWorldRoot") as Node3D
	if _world == null:
		_fail("capture scene has no OpenWorldRoot child")
		return
	_car = _world.get_node_or_null("PlayerCar") as VehiclePhysics
	if _car == null:
		_fail("world has no PlayerCar (VehiclePhysics)")
		return
	_fallback = _world.get_node_or_null("FallbackGround") as StaticBody3D
	_apply_reference_look()
	_force_deterministic_world()
	_quiet_ambient_life()
	# Children tick before parents in Godot, so as the scene ROOT this
	# recorder's per-tick input_override write lands before the car reads it.
	set_physics_process(true)
	# The capture window ends on DRAWN FRAMES, checked once per rendered frame
	# in _process -- a physics-only check can drift when a slow frame swallows
	# the physics ticks (see _process).
	set_process(true)

func _physics_process(delta: float) -> void:
	# Failed shots park in "failed": quit(1) is queued but this callback can
	# still fire for the rest of the frame, and a re-entry here would touch
	# null state (a script error would hang the engine instead of exiting).
	if _car == null or _phase == "failed":
		return
	match _phase:
		"boot":
			_tick_boot()
		"hold":
			_tick_hold(delta)
		"settle":
			_tick_settle(delta)
		"capture":
			_tick_capture(delta)

# --- Boot: wait out WorldDriver's bootstrap chain, then arm the shot. ---

func _tick_boot() -> void:
	_boot_ticks += 1
	if _boot_ticks > BOOT_TICK_CAP:
		_fail("world bootstrap never finished (loading screen still visible)")
		return
	if not _loading_hidden():
		return
	_arm_shot()

func _loading_hidden() -> bool:
	var screen := LoadingScreenManager.get_node_or_null("LoadingScreen") as Control
	return screen == null or not screen.visible

# --- Hold: keep the car planted at the shot origin until real ground exists.
# FallbackGround's collision box tops out at y=0 under the whole world, so a
# bare short ray would "prove ground" over an unbaked void; the ray excludes
# both the car body and that fallback so a hit can only be terrain/road.

func _tick_hold(delta: float) -> void:
	_hold_ticks += 1
	_car.respawn_at(_hold_pos)
	_drive_tick(delta)
	if _ground_ready():
		_phase = "settle"
		_settle_ticks = 0
		return
	if _hold_ticks > HOLD_TICK_CAP:
		push_warning("MenuClipRecorder[%s]: no ground under road '%s' after %d ticks; capturing anyway" % [shot, road_name, HOLD_TICK_CAP])
		_phase = "settle"
		_settle_ticks = 0

func _ground_ready() -> bool:
	var space := _car.get_world_3d().direct_space_state
	if space == null:
		return false
	var exclude: Array[RID] = [_car.get_rid()]
	if _fallback != null and is_instance_valid(_fallback):
		exclude.append(_fallback.get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		_car.global_position + Vector3.UP * GROUND_RAY_UP,
		_car.global_position + Vector3.DOWN * GROUND_RAY_DOWN,
		0xFFFFFFFF,
		exclude
	)
	return not space.intersect_ray(query).is_empty()

# --- Settle: ground proven; let suspension and chase camera land, then open
# the capture window with the marker frame.

func _tick_settle(delta: float) -> void:
	_settle_ticks += 1
	_drive_tick(delta)
	if _settle_ticks < SETTLE_TICKS:
		return
	_capture_start_frame = Engine.get_frames_drawn()
	_capture_target_frames = int(duration_sec * MOVIE_FPS)
	print("CAPTURE_READY frame=", _capture_start_frame)
	_phase = "capture"

func _tick_capture(delta: float) -> void:
	_drive_tick(delta)

## Capture ends here, once per RENDERED frame, not in _physics_process.
##
## The Movie Writer writes one frame per main-loop iteration, but on a heavy
## scene (the pass/pan shots spam Terrain3D out-of-bounds errors and render at
## 1-2 s per frame) the delta of that single iteration balloons to match real
## time. The old "sum the delta until duration_sec" countdown therefore fired
## after only a handful of frames (pass: 74 frames, pan: 5) instead of
## duration_sec * MOVIE_FPS. Engine.get_frames_drawn() counts the frames the
## Movie Writer actually captured, so this window cannot run short; checking it
## in _process (per frame) rather than _physics_process (which a slow frame can
## starve) keeps the end marker frame-accurate.
func _process(_delta: float) -> void:
	if _phase != "capture":
		return
	var drawn := Engine.get_frames_drawn() - _capture_start_frame
	if mode == "pan" and _pan_pivot != null:
		# Frame-driven sweep (see PAN_YAW_START): one 16 s sweep per capture
		# window regardless of how slow the scene renders. Avoids the wall-clock
		# AnimationPlayer, which would finish the sweep in the first few frames.
		var t := clampf(float(drawn) / float(_capture_target_frames), 0.0, 1.0)
		_pan_pivot.rotation.y = lerpf(PAN_YAW_START, PAN_YAW_END, t)
	if drawn < _capture_target_frames:
		return
	print("CAPTURE_END frame=", Engine.get_frames_drawn())
	get_tree().quit()

func _drive_tick(delta: float) -> void:
	if _driver != null:
		# FAR_AWAY keeps the TrafficDriver player-proximity latch inert.
		_driver.update(FAR_AWAY, delta)

# --- Arming (end of boot): re-assert the look GameState may have clobbered,
# snap the sun, hide chrome, position and aim the car, wire the driver. ---

func _arm_shot() -> void:
	_apply_reference_look()
	_snap_suns()
	_hide_node("HUD")
	_hide_node("PauseMenu")
	_hide_node("WeatherFXLayer")
	var def := _find_road(road_name)
	if def == null:
		_fail("no RoadDef with id '%s'" % road_name)
		return
	if def.points.size() < 2:
		_fail("road '%s' has fewer than 2 points" % road_name)
		return
	var idx: int = def.points.size() / 2 if mode == "pan" else 0
	var start: Vector3 = def.points[idx]
	var next: Vector3 = def.points[(idx + 1) % def.points.size()]
	var dir := Vector3(next.x - start.x, 0.0, next.z - start.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, 0.0, -1.0)
	dir = dir.normalized()
	_hold_pos = start
	_car.set_scripted_driver(true)
	# Forward is local -Z, so yaw = atan2(-dir.x, -dir.z). Set the basis
	# BEFORE respawn_at: the teleport keeps the body's current yaw.
	_car.global_basis = Basis(Vector3.UP, atan2(-dir.x, -dir.z))
	_car.respawn_at(_hold_pos)
	_driver = TrafficDriver.new()
	_driver.configure(_car, def.points, def.closed, cruise_kmh)
	if mode == "pan":
		_setup_pan()
	else:
		_tune_chase_camera()
	_phase = "hold"
	_hold_ticks = 0

## Pan shot: park the car, retire the gameplay camera rigs, and hand the
## viewport to the capture scene's own pivot + camera. The sweep itself is
## driven from the frame count in _process; the .tscn's PanAnimation is left
## unplayed (a wall-clock clip would finish far too early on this scene).
func _setup_pan() -> void:
	_driver.set_parked(true)
	_pan_pivot = get_node_or_null("PanPivot") as Node3D
	_pan_camera = get_node_or_null("PanCamera") as Camera3D
	if _pan_pivot != null:
		_pan_pivot.global_position = _car.global_position + Vector3.UP * PAN_PIVOT_HEIGHT
		# Start yaw before aiming, so the camera's aim-at-pivot is baked at the
		# sweep's first-frame orientation.
		_pan_pivot.rotation.y = PAN_YAW_START
	if _pan_camera != null and _pan_pivot != null:
		_pan_camera.look_at(_pan_pivot.global_position)
	for rig_name in ["ChaseCamera", "OrbitCamera", "HoodCamera", "CockpitCamera"]:
		var rig := _world.get_node_or_null(rig_name) as Node3D
		if rig == null:
			continue
		rig.set_process(false)
		rig.set_physics_process(false)
		for cam in rig.find_children("*", "Camera3D", false, false):
			if cam is Camera3D:
				(cam as Camera3D).current = false
	if _pan_camera != null:
		_pan_camera.current = true

## Chase shot: pull the gameplay ChaseCamera lower and tighter than its
## shipped rig (see CHASE_CAM_HEIGHT) so the capture cannot drift into the
## roadside foliage that blacked out two stretches of the hub route. Plain
## property writes on the capture-time tree; nothing else reads them.
func _tune_chase_camera() -> void:
	var rig := _world.get_node_or_null("ChaseCamera")
	if rig == null:
		return
	rig.set("camera_height", CHASE_CAM_HEIGHT)
	rig.set("camera_distance", CHASE_CAM_DISTANCE)
	rig.set("follow_speed", CHASE_CAM_FOLLOW_SPEED)

# --- Determinism + look helpers. ---

## Pushes the High preset onto the LIVE tree and neutralises FSR2 for crisp
## 720p. Called once in _ready and again at the end of boot: GameState._ready
## defers one frame and then re-applies the SAVED preset (Low on the
## reference rig), which would otherwise clobber the first call.
func _apply_reference_look() -> void:
	GameState.quality_preset = 2
	GameState.probe_enabled = SettingsMenuScript.probe_enabled_for(2)
	GameState.camera_settings = SettingsMenuScript.camera_settings_for_quality_preset(2)
	var scene := get_tree().current_scene
	if scene != null:
		SettingsMenuScript.apply_to_scene_tree(2, scene, get_viewport())
		SettingsMenuScript.apply_camera_settings(GameState.camera_settings, scene)
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_mode = 0
		vp.scaling_3d_scale = 1.0

func _force_deterministic_world() -> void:
	DayNightDriver.set_enabled(false)
	WeatherManager.set_time_of_day(hour)
	WeatherManager.set_weather(WeatherManager.Weather.CLEAR)

## TrafficSpawner/LivingWorld: disable both -- LivingWorld owns the physics
## tick that spawns traffic, the spawner owns the vehicles. Duck-typed call:
## the scripts carry no class_name.
func _quiet_ambient_life() -> void:
	var traffic := _world.get_node_or_null("TrafficSpawner")
	if traffic != null and traffic.has_method("set_enabled"):
		traffic.call("set_enabled", false)
	var living := _world.get_node_or_null("LivingWorld")
	if living != null and living.has_method("set_enabled"):
		living.call("set_enabled", false)

## Snap every "sun"-group light to the shot hour (WeatherManager's signal may
## have fired before WorldDriver connected to it during its bootstrap).
func _snap_suns() -> void:
	for sun in get_tree().get_nodes_in_group("sun"):
		if sun is DirectionalLight3D:
			WorldDriver.apply_sun_transform(sun as DirectionalLight3D, hour, true)

func _find_road(id: String) -> RoadDef:
	var network := _world.get_node_or_null("RoadNetwork") as RoadNetwork
	if network == null:
		return null
	for def in network.get_road_defs():
		if def.id == id:
			return def
	return null

func _hide_node(node_name: String) -> void:
	var node := _world.get_node_or_null(node_name)
	if node != null:
		node.set("visible", false)

func _fail(message: String) -> void:
	printerr("MenuClipRecorder[%s]: %s" % [shot, message])
	print("CAPTURE_ERROR %s" % message)
	_phase = "failed"
	get_tree().quit(1)
