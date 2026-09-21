class_name RainSystem
extends Node3D

## Weather VFX (S12): rain GPU particle system. Headless culls the emitter in
## _ready (mirrors VehicleFX) so the suite stays renderer-free; the state
## machine (weather -> raining) still runs so behaviour is assertable without a
## renderer. The emitter box follows the active camera so rain surrounds the
## viewport, not the (distant) world origin.

const RAIN_BOX_HALF := 12.0
const RAIN_BOX_TALL := 1.5
const RAIN_AMOUNT := 900
const STORM_AMOUNT := 1600
const FOLLOW_HEIGHT := 5.0

var _emitter: GPUParticles3D = null
var _raining := false
var _weather: int = WeatherManager.Weather.CLEAR

## Rain/storm are the wet, particle-drawing states; everything else is dry.
static func rain_active(weather: int) -> bool:
	return weather == WeatherManager.Weather.RAIN or weather == WeatherManager.Weather.STORM

func _ready() -> void:
	# Signal wiring + state init run ALWAYS (the headless suite asserts the
	# weather -> raining state machine); only the emitter build is culled.
	if not WeatherManager.weather_changed.is_connected(_on_weather_changed):
		WeatherManager.weather_changed.connect(_on_weather_changed)
	set_weather(WeatherManager.current_weather)
	if DisplayServer.get_name() == "headless":
		return
	_build_emitter()

func _exit_tree() -> void:
	if WeatherManager.weather_changed.is_connected(_on_weather_changed):
		WeatherManager.weather_changed.disconnect(_on_weather_changed)

func _process(_delta: float) -> void:
	if _emitter == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		global_position = Vector3(cam.global_position.x, cam.global_position.y + FOLLOW_HEIGHT, cam.global_position.z)

func set_weather(weather: int) -> void:
	_weather = weather
	_raining = rain_active(weather)
	if _emitter == null:
		return
	_emitter.emitting = _raining
	_emitter.visible = _raining
	if _raining:
		_emitter.amount = STORM_AMOUNT if weather == WeatherManager.Weather.STORM else RAIN_AMOUNT

func get_weather() -> int:
	return _weather

## State-machine truth; runs headless even when the emitter was culled.
func is_raining() -> bool:
	return _raining

## Emitter count: 1 when not headless, 0 when the headless cull left nothing.
func particle_count() -> int:
	return 1 if _emitter != null else 0

func _on_weather_changed(weather: int) -> void:
	set_weather(weather)

func _build_emitter() -> void:
	var emitter := GPUParticles3D.new()
	emitter.name = "RainDrops"
	emitter.amount = RAIN_AMOUNT
	emitter.lifetime = 1.4
	emitter.one_shot = false
	emitter.emitting = false
	emitter.visible = false
	emitter.local_coords = false
	emitter.draw_pass_1 = QuadMesh.new()

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(RAIN_BOX_HALF, RAIN_BOX_TALL, RAIN_BOX_HALF)
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 8.0
	material.gravity = Vector3(0.0, -14.0, 0.0)
	material.initial_velocity_min = 7.0
	material.initial_velocity_max = 9.0
	material.damping_min = 0.0
	material.damping_max = 0.1
	material.scale_min = 0.06
	material.scale_max = 0.14
	material.color = Color(0.62, 0.68, 0.76, 0.55)
	material.angular_velocity_min = 0.0
	material.angular_velocity_max = 0.0
	emitter.process_material = material
	add_child(emitter)
	_emitter = emitter