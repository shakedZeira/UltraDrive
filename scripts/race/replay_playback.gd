# scripts/race/replay_playback.gd
class_name ReplayPlayback
extends Node3D

## AAA-5 playback entity: a plain Node3D (NO physics, no VehiclePhysics) that
## re-drives a recorded ReplayRecorder stream by interpolating the stored sample
## transforms on its own timeline. Point any existing camera rig at it (chase /
## orbit / hood / cockpit all follow a Node3D target) and the 4-mode cycle works
## unchanged during playback. Visuals are culled under the headless display
## server (ReplayRecorder.is_headless) so tests only ever see the transform
## stream, never a rendered ghost.

var recording: ReplayRecorder = null

var _samples: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _clock: float = 0.0
var _playing := false
var _loop := true
var _visual: MeshInstance3D = null

func _ready() -> void:
	_ensure_visual()

func set_source(source: ReplayRecorder) -> void:
	recording = source
	if source == null:
		_samples = []
		_events = []
	else:
		_samples = source.get_samples()
		_events = source.get_events()
	_clock = _stream_start()
	_playing = false

func get_events() -> Array[Dictionary]:
	return _events.duplicate()

func set_loop(value: bool) -> void:
	_loop = value

func is_looping() -> bool:
	return _loop

func is_playing() -> bool:
	return _playing

func get_time() -> float:
	return _clock

func start_playback() -> void:
	if _samples.is_empty():
		_playing = false
		return
	_clock = _stream_start()
	_playing = true
	_apply_stream()

func stop_playback() -> void:
	_playing = false

func seek(time: float) -> void:
	_clock = time
	_apply_stream()

## Advances the playback timeline by delta seconds and re-applies the recorded
## stream. Pure arithmetic over stored samples — no physics, no wall clock.
## Looping wraps the clock back to the first sample; a non-looping stream stops
## on its final pose.
func advance(delta: float) -> void:
	if not _playing or _samples.is_empty():
		return
	_clock += delta
	var span := _stream_end() - _stream_start()
	if _clock >= _stream_end() and span > 0.0:
		if _loop:
			_clock = fposmod(_clock - _stream_start(), span) + _stream_start()
		else:
			_clock = _stream_end()
			_playing = false
	_apply_stream()

## Current recorded speed (for HUD / camera FOV consumers). Duck-typed so a rig
## targeting this node can read it without casting to VehiclePhysics.
func get_speed_kmh() -> float:
	if _samples.is_empty():
		return 0.0
	return float(_samples[_find_index(_clock)]["speed_kmh"])

func get_drive_info() -> Dictionary:
	if _samples.is_empty():
		return {"speed_kmh": 0.0, "gear": 0, "rpm": 0.0}
	var sample := _samples[_find_index(_clock)]
	return {
		"speed_kmh": float(sample["speed_kmh"]),
		"gear": int(sample["gear"]),
		"rpm": float(sample["rpm"]),
	}

## Builds the ghost visual (a translucent box). Pure factory — no tree access
## — so headless tests can still build and free one to assert the shape exists
## while the node itself stays visually culled. The node only adds this child
## when the display server can actually render it.
static func build_ghost() -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.8, 0.6, 3.6)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.5)
	var ghost := MeshInstance3D.new()
	ghost.name = "ReplayGhost"
	ghost.mesh = mesh
	ghost.material_override = mat
	return ghost

## Headless-culled playback visuals: the ghost is only attached when the display
## server is real. Under headless (the test/CI path) _visual stays null and the
## node carries no children — playback is the transform stream alone.
func _ensure_visual() -> void:
	if _visual != null or ReplayRecorder.is_headless():
		return
	_visual = ReplayPlayback.build_ghost()
	add_child(_visual)

func _process(delta: float) -> void:
	advance(delta)

func _apply_stream() -> void:
	if _samples.is_empty():
		return
	var index := mini(_find_index(_clock), _samples.size() - 1)
	if index >= _samples.size() - 1:
		global_transform = _sample_transform(_samples[index])
		return
	var a := _samples[index]
	var b := _samples[index + 1]
	var ta := float(a["t"])
	var tb := float(b["t"])
	var span := tb - ta
	var weight := 0.0
	if span > 0.000001:
		weight = clampf((_clock - ta) / span, 0.0, 1.0)
	global_transform = _sample_transform(a).interpolate_with(_sample_transform(b), weight)

func _sample_transform(sample: Dictionary) -> Transform3D:
	var stored: Transform3D = sample["transform"]
	return stored

func _find_index(time: float) -> int:
	if _samples.is_empty():
		return 0
	var lo := 0
	var hi := _samples.size() - 1
	var result := 0
	while lo <= hi:
		var mid := (lo + hi) >> 1
		if float(_samples[mid]["t"]) <= time:
			result = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return result

func _stream_start() -> float:
	if _samples.is_empty():
		return 0.0
	return float(_samples[0]["t"])

func _stream_end() -> float:
	if _samples.is_empty():
		return 0.0
	return float(_samples[_samples.size() - 1]["t"])
