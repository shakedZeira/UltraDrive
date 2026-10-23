extends SceneTree

## Automated R35 exterior capture (front-end review). Windowed run, NOT --headless.
## Boots test_track, swaps the PlayerCar to the R35 at frame 3 (after
## PlayerCarController._ready), freezes it, then flies a dedicated Camera3D around the
## nose and saves PNGs to .vision/captures/ (prefix from env R35_CAP_TAG, default "r35_ext").
##
## RUN: set APPDATA=<project>\reports\godot_userdata, then
##   godot --path . -s res://tools/r35_front_capture.gd

const TRACK := "res://scenes/test/test_track.tscn"
const R35 := "res://resources/cars/nissan_gt_r35_2017.tres"
const OUT_DIR := "res://.vision/captures"

# name, forward (m, along nose), side (m, +left), up (m), look forward, look side, look up
const SHOTS := [
	["front34", 4.3, 2.9, 1.25, 1.3, 0.1, 0.55],
	["front_low", 3.4, 1.1, 0.5, 1.6, 0.2, 0.5],
	["front", 5.5, 0.0, 0.85, 1.6, 0.0, 0.55],
	["side34_high", 3.2, 3.6, 1.7, 0.6, 0.0, 0.6],
]

var _frames := 0
var _car: Node3D = null
var _cam: Camera3D = null
var _shot := 0
var _tag := "r35_ext"

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.title = "UltraDrive exterior capture"
	var env_tag := OS.get_environment("R35_CAP_TAG")
	if env_tag != "":
		_tag = env_tag
	var scene := (load(TRACK) as PackedScene).instantiate()
	root.add_child(scene)
	_car = scene.get_node_or_null("%PlayerCar")
	var layers: Array[Node] = []
	_collect(scene, layers)
	for n: Node in layers:
		if n is CanvasLayer:
			n.visible = false
	if _car == null:
		print("CAPTURE ERROR: no PlayerCar")
		quit(1)

func _swap_to_r35() -> void:
	var cfg := load(R35) as CarConfig
	_car.set("config", cfg)
	var controller := _car.get_node_or_null("PlayerCarController")
	if controller != null and controller.has_method("_apply_visual"):
		controller.set("_car_id", "nissan_gt_r35_2017")
		controller._apply_visual()
	print("CAPTURE swapped to R35")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_swap_to_r35()
	if _frames == 60 and _car is RigidBody3D:
		(_car as RigidBody3D).freeze = true
	if _frames == 62:
		_cam = Camera3D.new()
		_cam.far = 400.0
		_cam.fov = 50.0
		root.add_child(_cam)
		_cam.make_current()
	if _frames > 62 and _shot < SHOTS.size():
		var phase := (_frames - 63) % 8
		if phase == 0:
			_place(SHOTS[_shot])
		elif phase == 6:
			_snap(String(SHOTS[_shot][0]))
			_shot += 1
	if _shot >= SHOTS.size() and _frames > 63 + SHOTS.size() * 8 + 4:
		print("CAPTURE DONE")
		quit(0)
	return false

func _place(s: Array) -> void:
	var fwd := -_car.global_transform.basis.z
	var left := -_car.global_transform.basis.x
	# the R35 GLB is mounted nose-forward in body space; verify at runtime via the mesh bounds
	var origin := _car.global_transform.origin
	var pos := origin + fwd * float(s[1]) + left * float(s[2]) + Vector3.UP * float(s[3])
	var tgt := origin + fwd * float(s[4]) + left * float(s[5]) + Vector3.UP * float(s[6])
	_cam.global_transform = Transform3D(Basis(), pos).looking_at(tgt, Vector3.UP)

func _snap(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ok := img.save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + _tag + "_" + shot + ".png"))
	print("CAPTURE ", shot, " ok=", ok)

func _collect(node: Node, out: Array[Node]) -> void:
	out.append(node)
	for c in node.get_children():
		_collect(c, out)
