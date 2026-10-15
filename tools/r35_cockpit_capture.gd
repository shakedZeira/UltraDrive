extends SceneTree

## Automated R35 cockpit capture. Runs a real (windowed) render so the viewport
## has pixels, boots test_track, swaps the PlayerCar to the GT-R R35 config,
## re-applies visual + interior, cycles the C-camera to COCKPIT, lets the car
## settle, then saves 3 PNG captures to .vision/captures/ and quits itself.
##
## RUN (windowed, NOT --headless — dummy driver renders black):
##   call godot_path.bat & !GODOT_EXE_CONSOLE! --path . -s res://tools/r35_cockpit_capture.gd
##
## Set APPDATA to a project-absolute dir before running.

const TRACK := "res://scenes/test/test_track.tscn"
const R35 := "res://resources/cars/nissan_gt_r35_2017.tres"
const OUT_DIR := "res://.vision/captures"

var _frames := 0
var _car: Node3D = null
var _rig: Node = null
var _orbit: Node3D = null
var _cockpit: Node3D = null
var _saved := 0
var _pending := ""
var _look_frames := 0

func _initialize() -> void:
	# root IS the root Window in a SceneTree script; size it directly.
	root.size = Vector2i(1280, 720)
	root.title = "UltraDrive capture"

	var track := load(TRACK) as PackedScene
	var scene := track.instantiate()
	root.add_child(scene)

	_car = scene.get_node_or_null("%PlayerCar")
	_rig = scene.get_node_or_null("%PlayerCar/CockpitRig")
	_orbit = scene.get_node_or_null("OrbitCamera")
	_cockpit = scene.get_node_or_null("CockpitCamera")

	# Hide 2D overlays so the shot is pure cockpit interior. A top-level
	# CanvasLayer hide does NOT reach nested CanvasLayers (CockpitDash is a
	# layer-2 child of the HUD layer), so sweep every CanvasLayer in the tree.
	var layers: Array[Node] = []
	_layers(scene, layers)
	for layer: Node in layers:
		if layer is CanvasLayer:
			layer.visible = false
	print("CAPTURE hidden canvas layers=", layers.size())

	if _car == null:
		print("CAPTURE ERROR: no PlayerCar")
		quit(1)
		return

	var cfg := load(R35) as CarConfig
	_car.set("config", cfg)
	var controller := _car.get_node_or_null("PlayerCarController")
	if controller != null and controller.has_method("_apply_visual"):
		controller._apply_visual()
	if _rig != null and _rig.has_method("rebuild_interior"):
		_rig.rebuild_interior()

	print("CAPTURE ready: car=", _car.name, " rig=", _rig != null, " orbit=", _orbit != null, " cockpit=", _cockpit != null)

func _process(delta: float) -> bool:
	_frames += 1

	if _frames == 10:
		if _orbit != null and _orbit.has_method("cycle_mode_for_test"):
			_orbit.cycle_mode_for_test()  # -> ORBIT
			_orbit.cycle_mode_for_test()  # -> HOOD
			_orbit.cycle_mode_for_test()  # -> COCKPIT
		print("CAPTURE frame 10: cockpit view engaged")

	if _pending == "" and _frames == 140:
		if _car is RigidBody3D:
			(_car as RigidBody3D).freeze = true
		_capture("r35_cockpit_forward.png")

	# Hold the look sweep toward the driver-side stack (positive X) across
	# several frames so the yaw actually accumulates past the return-to-center
	# damp before the angled capture.
	if _pending == "" and _frames >= 180 and _frames < 250:
		if _cockpit != null:
			_cockpit.apply_look(-0.9, 0.18, delta)
	if _pending == "" and _frames == 250:
		_capture("r35_cockpit_binnacle_stack.png")

	if _pending == "" and _frames == 280 and _saved >= 2:
		_capture("r35_cockpit_console.png")

	if _saved >= 3:
		print("CAPTURE DONE")
		quit(0)

	return false

## Saves the current presented frame. Awaits RenderingServer.frame_post_draw so
## the texture we snapshot has actually been rendered (reading it earlier in the
## frame yields the clearing colour).
func _capture(name: String) -> void:
	_pending = name
	await _snapshot(name)

func _snapshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var ok := img.save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + name))
	_saved += 1
	_pending = ""
	print("CAPTURE ", name, " saved ok=", ok, " saved_count=", _saved)

## Flattens every descendant (incl. all CanvasLayer nodes) into `out`. Used to
## hide nested canvas layers whose visibility is NOT tied to their parent layer.
func _layers(node: Node, out: Array[Node]) -> void:
	out.append(node)
	for child in node.get_children():
		_layers(child, out)