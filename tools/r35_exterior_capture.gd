extends SceneTree

## In-game exterior shots of the R35 (front 3/4, side, rear 3/4, chase-height rear)
## into .vision/captures/r35_ext_*.png. Windowed run only.

const TRACK := "res://scenes/test/test_track.tscn"
const R35 := "res://resources/cars/nissan_gt_r35_2017.tres"
var _frames := 0
var _car: Node3D
var _cam: Camera3D
var _shots := [
	["r35_ext_front34.png", Vector3(3.6, 1.3, -4.6)],
	["r35_ext_side.png", Vector3(7.5, 0.9, 0.0)],
	["r35_ext_rear34.png", Vector3(3.4, 1.6, 4.8)],
	["r35_ext_chase.png", Vector3(0.0, 1.9, 6.2)],
]
var _idx := 0
var _busy := false

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	var scene := (load(TRACK) as PackedScene).instantiate()
	root.add_child(scene)
	var layers: Array[Node] = scene.find_children("*", "CanvasLayer", true, false)
	for l in layers:
		(l as CanvasLayer).visible = false
	_car = scene.get_node_or_null("%PlayerCar")
	_cam = Camera3D.new()
	_cam.fov = 45.0
	scene.add_child(_cam)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3 and _car != null:
		_car.set("config", load(R35) as CarConfig)
		var c := _car.get_node_or_null("PlayerCarController")
		if c != null:
			c.set("_car_id", "nissan_gt_r35_2017")
			c.call("_apply_visual")
	if _frames > 60 and not _busy and _idx < _shots.size() and _frames % 30 == 0:
		var s: Array = _shots[_idx]
		var b := _car.global_transform.basis
		var off: Vector3 = s[1]
		var pos := _car.global_position + b.x * off.x + Vector3.UP * off.y + b.z * off.z
		_cam.global_position = pos
		_cam.look_at(_car.global_position + Vector3.UP * 0.55, Vector3.UP)
		_cam.make_current()
		_busy = true
		_snap(String(s[0]))
	if _idx >= _shots.size():
		quit(0)
	return false

func _snap(name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://.vision/captures/" + name)
	print("EXT ", name, " ", img.save_png(path))
	_idx += 1
	_busy = false
