extends Node

## Controls the player's car. Attach as child of VehiclePhysics.

const CAR_ORIENT := Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
const DEFAULT_VISUAL := "res://assets/cars/sports_coupe.glb"

@onready var car: VehiclePhysics = get_parent()

var _car_id: String = ""
var _spin_angle: float = 0.0
var _visual_wheels: Dictionary = {}
var _taillight_material: StandardMaterial3D = null
var _visual_ready: bool = false
var _probe: ReflectionProbe = null
var _probe_synced_enabled: bool = true
var _night_lamps: Node3D = null
var _headlight_intensity: float = 0.0
## AUTO = follow the DayNightDriver clock; OFF / ON are the X / Cross overrides.
var _lamp_mode: CarVisuals.LampMode = CarVisuals.LampMode.AUTO

func _ready() -> void:
	VehicleManager.register_player_car(car)
	var garage := Garage.new_from_save()
	var active := garage.get_active_car()
	_car_id = active
	if active != "":
		var car_path := "res://resources/cars/%s.tres" % active
		if ResourceLoader.exists(car_path):
			var base := load(car_path) as CarConfig
			var tuned := garage.get_car_overrides(active)
			car.config = base.with_overrides(tuned) if not tuned.is_empty() else base
	_apply_visual()

## The car is freed on scene swaps but VehicleManager keeps stale refs (its
## remove_car() had no callers), so all_cars/player_car could point at a freed
## body that a later start_race() then calls release_ground_lock() on. Unregister
## when this controller leaves the tree (children exit before parents, so the
## car body is still valid here).
func _exit_tree() -> void:
	if is_instance_valid(car):
		VehicleManager.remove_car(car)

func _process(delta: float) -> void:
	if not _visual_ready:
		return
	var info := car.get_drive_info()
	var speed_kmh: float = info["speed_kmh"]
	var steer: float = info["steer"]
	var brake: float = info["brake"]
	# Wheel visuals now translate REAL tire spin: the integrated
	# wheel_angular_velocity (rad/s, signed like the spin angle). When no wheel
	# is spinning (parked, or the moderate cruise where spin matches rolling),
	# fall back to the speed-derived rolling rate so idle visuals stay exact.
	if _has_real_wheelspin():
		_spin_angle = _spin_angle + _visual_wheel_angular_velocity() * delta
	else:
		_spin_angle = _spin_angle + CarVisuals.wheel_spin_rate(speed_kmh, CarVisuals.WHEEL_RADIUS) * delta
	CarVisuals.apply_wheel_visuals(_visual_wheels, steer, _spin_angle)
	CarVisuals.apply_brake_glow(_taillight_material, brake)
	_sync_probe()
	_poll_headlight_toggle()
	_sync_night_lamps()

## Fully-driven visual spin: |omega| must exceed the rolling match by 25% so a
## wheelspin is unmistakable since every cog spins that much faster than the
## road under traction loss. Returns the SIGNED angular rate (rad/s, positive =
## forward roll) of the FASTEST wheel, so a smoke-limiter or ABS lock blow-through
## is visible whether it's a drive wheelspin or a brake lockup.
func _visual_wheel_angular_velocity() -> float:
	var best: float = 0.0
	for w in [car.wheel_fl, car.wheel_fr, car.wheel_rl, car.wheel_rr]:
		if absf(w.wheel_angular_velocity) > absf(best):
			best = w.wheel_angular_velocity
	return best

## True when any wheel is actually spinning off its rolling match (either
## direction, only while it bears weight so resting wheels never shake).
func _has_real_wheelspin() -> bool:
	var speed := car.linear_velocity.length()
	if speed < 0.5:
		return false
	for w in [car.wheel_fl, car.wheel_fr, car.wheel_rl, car.wheel_rr]:
		if not w.is_in_contact:
			continue  # wheel on the ground only
		var rolling := speed / WheelPhysics.WHEEL_RADIUS
		if absf(w.wheel_angular_velocity) > rolling * 1.25:
			return true
	return false

## Rebuilds the per-car ReflectionProbe under the visual body after its
## children were cleared in _apply_visual. Centered on the body (so it follows
## the car), sized to the mesh, real-time when GameState.probe_enabled.
func _ensure_car_probe(body: Node3D) -> void:
	var probe := ReflectionProbe.new()
	probe.name = "CarProbe"
	probe.size = CarVisuals.CAR_PROBE_SIZE
	probe.origin_offset = CarVisuals.CAR_PROBE_ORIGIN_OFFSET
	probe.box_projection = true
	body.add_child(probe)
	_probe = probe
	_probe_synced_enabled = GameState.probe_enabled
	CarVisuals.refresh_probe(probe, _probe_synced_enabled)

## Mirrors GameState.probe_enabled onto the live probe whenever it changes at
## runtime (e.g. quality preset switched mid-drive). Polled per frame; the
## single bool compare is negligible vs. the probe's own update cost.
func _sync_probe() -> void:
	if _probe == null:
		return
	var enabled := GameState.probe_enabled
	if enabled == _probe_synced_enabled:
		return
	_probe_synced_enabled = enabled
	CarVisuals.refresh_probe(_probe, enabled)

## Night lamp layer (roadmap #5). The car GLB only PAINTS its headlight /
## taillight materials, so the actual Light3D nodes live on the car body:
## two spots aimed along CAR_ORIENT's nose plus a rear red omni. Rebuilt with
## the visual at the same seam as _ensure_car_probe, because _apply_visual()
## clears every CarBody child before re-instancing the GLB.
func _ensure_night_lamps(body: Node3D) -> void:
	_night_lamps = CarVisuals.build_night_lamps()
	body.add_child(_night_lamps)
	_apply_lamp_intensity(_headlight_intensity)

## Mirrors _sync_probe for the lamps: reads the DayNightDriver-owned clock
## (WeatherManager's 0..24h time_of_day, the value DayNightDriver.advance_time
## wraps with fposmod), resolves it through the current lamp MODE and only
## touches the lights when that intensity actually moved -- a float compare per
## frame.
func _sync_night_lamps() -> void:
	if _night_lamps == null:
		return
	var intensity := _resolved_lamp_intensity()
	if absf(intensity - _headlight_intensity) < CarVisuals.HEADLIGHT_INTENSITY_EPSILON:
		return
	_apply_lamp_intensity(intensity)

## X / Cross (the `headlight` action) cycles OFF -> ON -> AUTO. Polled once per
## frame from _process, right before the clock sync so the mode change lands in
## the same frame's apply; the manual states pin the intensity, so the epsilon
## compare in _sync_night_lamps still swallows the rest.
func _poll_headlight_toggle() -> void:
	if not InputManager.is_headlight_just_pressed():
		return
	cycle_headlight_mode()

## Lamp intensity the current mode asks for at the current clock hour.
func _resolved_lamp_intensity() -> float:
	return CarVisuals.resolve_lamp_intensity(_lamp_mode, WeatherManager.get_time_of_day())

func _apply_lamp_intensity(intensity: float) -> void:
	_headlight_intensity = intensity
	CarVisuals.apply_lamp_intensity(_night_lamps, intensity)

## Pure visual-path resolver: a config with no visual_path (the starter
## Striker .tres ships none) MUST fall back to DEFAULT_VISUAL, never to an
## empty path -- an empty path loads nothing and renders an invisible car on
## first launch. Locked by tests/suites/test_night_headlights.gd.
static func resolve_visual_path(config: CarConfig) -> String:
	if config != null and not config.visual_path.is_empty():
		return config.visual_path
	return DEFAULT_VISUAL

## Accessor for the DEFAULT_VISUAL constant (the script has no class_name, so
## tests reach the constant through here rather than poking a bare literal).
static func default_visual_path() -> String:
	return DEFAULT_VISUAL

# --- Night lamps: public seam (tests drive these directly) ---

## Builds the night lamp layer under body and applies the current intensity.
func ensure_night_lamps(body: Node3D) -> void:
	_ensure_night_lamps(body)

## Maps a raw clock hour to a headlight intensity and switches the lamps,
## exactly as the per-frame clock poll does (mode-aware: a manual OFF stays
## dark at midnight, a manual ON stays lit at noon).
func set_headlight_time(time_of_day: float) -> void:
	_apply_lamp_intensity(CarVisuals.resolve_lamp_intensity(_lamp_mode, time_of_day))

## Last applied headlight intensity (0.0 day .. 1.0 night).
func headlight_intensity() -> float:
	return _headlight_intensity

## Current lamp mode (CarVisuals.LampMode). AUTO until the driver presses X.
func lamp_mode() -> CarVisuals.LampMode:
	return _lamp_mode

## Drops straight into a mode (tests + a settings row would drive this) and
## re-applies immediately so the lamps never wait a frame.
func set_lamp_mode(mode: CarVisuals.LampMode) -> void:
	_lamp_mode = mode
	_apply_lamp_intensity(_resolved_lamp_intensity())

## One X / Cross press: AUTO -> OFF -> ON -> AUTO.
func cycle_headlight_mode() -> void:
	set_lamp_mode(CarVisuals.next_lamp_mode(_lamp_mode))

## Light-node count of the built layer (2 spots + 1 rear omni), 0 before the
## first visual swap.
func night_lamp_count() -> int:
	return CarVisuals.night_lamp_count(_night_lamps)

## True while any lamp is lit.
func night_lamps_active() -> bool:
	return CarVisuals.night_lamps_active(_night_lamps)

## The built night lamp holder, for lookups by node name in tests.
func get_night_lamps() -> Node3D:
	return _night_lamps

func _apply_visual() -> void:
	var config := car.config as CarConfig
	var visual_path := resolve_visual_path(config)
	var body := car.get_node_or_null("CarBody") as Node3D
	if body == null:
		return
	for child in body.get_children():
		if child is BodyRig:
			continue
		body.remove_child(child)
		child.queue_free()
	var visual := load(visual_path) as PackedScene
	if visual == null:
		return
	var instance: Node3D = visual.instantiate()
	instance.transform = CAR_ORIENT
	body.add_child(instance)
	CarVisuals.apply_paint(instance, CarVisuals.paint_profile_for(_car_id))
	_cache_visuals(instance)
	_ensure_car_probe(body)
	_ensure_night_lamps(body)

func _cache_visuals(instance: Node3D) -> void:
	_visual_wheels = CarVisuals.resolve_wheel_nodes(instance, _car_id)
	_taillight_material = CarVisuals.find_named_material(instance, "taillight")
	_spin_angle = 0.0
	_visual_ready = true
