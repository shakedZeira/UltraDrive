extends SceneTree

## In-game captures of the R35 exhaust backfire (rear close, chase, day + dusk)
## into .vision/captures/backfire_*.png. Windowed run only.
## godot --path . -s res://tools/backfire_capture.gd

const TRACK := "res://scenes/test/test_track.tscn"
const R35 := "res://resources/cars/nissan_gt_r35_2017.tres"
var _frames := 0
var _car: Node3D
var _cam: Camera3D
var _bf: Node
var _scene: Node
# [file, cam offset (car-local), look-at offset, dusk?, loudness]
var _shots := [
	["backfire_rear_day.png", Vector3(1.6, 0.9, 4.4), Vector3(0.0, 0.35, 2.4), false, 1.0],
	["backfire_chase_day.png", Vector3(0.0, 1.9, 6.2), Vector3(0.0, 0.5, 0.0), false, 1.0],
	["backfire_rear_dusk.png", Vector3(1.6, 0.9, 4.4), Vector3(0.0, 0.35, 2.4), true, 1.0],
	["backfire_chase_dusk.png", Vector3(0.0, 1.9, 6.2), Vector3(0.0, 0.5, 0.0), true, 1.0],
]
var _idx := 0
var _busy := false

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	_scene = (load(TRACK) as PackedScene).instantiate()
	root.add_child(_scene)
	for l in _scene.find_children("*", "CanvasLayer", true, false):
		(l as CanvasLayer).visible = false
	_car = _scene.get_node_or_null("%PlayerCar")
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_scene.add_child(_cam)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3 and _car != null:
		_car.set("config", load(R35) as CarConfig)
		var c := _car.get_node_or_null("PlayerCarController")
		if c != null:
			c.set("_car_id", "nissan_gt_r35_2017")
			c.call("_apply_visual")
		_bf = _car.get_node_or_null("ExhaustBackfire")
		print("BF ", _bf, " tips=", _bf.call("tip_positions") if _bf != null else "none")
	if _frames > 60 and not _busy and _idx < _shots.size() and _frames % 30 == 0:
		var s: Array = _shots[_idx]
		if bool(s[3]):
			_dusk()
		var b := _car.global_transform.basis
		var off: Vector3 = s[1]
		var look: Vector3 = s[2]
		_cam.global_position = _car.global_position + b * off
		_cam.look_at(_car.global_position + b * look, Vector3.UP)
		_cam.make_current()
		_busy = true
		_snap(s)
	if _idx >= _shots.size():
		quit(0)
	return false

func _dusk() -> void:
	for l in _scene.find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).light_energy = 0.04
	for e in _scene.find_children("*", "WorldEnvironment", true, false):
		var env := (e as WorldEnvironment).environment
		if env != null:
			env.ambient_light_energy = 0.05
			env.background_energy_multiplier = 0.08

func _snap(s: Array) -> void:
	_bf.set("engine_state_override", 1)
	_bf.set_process(true)
	_bf.call("_process", 1.0)
	_bf.call("trigger_pop", float(s[4]))
	_bf.call("_process", 0.022)
	_bf.set_process(false)
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://.vision/captures/" + String(s[0]))
	print("BF_SHOT ", s[0], " ", img.save_png(path), " flames=", _bf.call("active_flame_count"))
	_idx += 1
	_busy = false
