# scripts/ui/photo_mode.gd
class_name PhotoMode
extends Node

## AAA-3 Photo Mode: a freeze-frame, hide-UI, free-orbit high-level state over
## the shipped orbit camera rig, with FOV/aperture (DoF-lite → data-only) and
## filter sliders plus a headless-guarded screenshot export.
##
## enter() samples the rig before freezing: it remembers whether the tree was
## paused, remembers the HUD layer's visibility, remembers the orbit camera's
## active CameraMode, then pauses the tree, hides the HUD and forces the orbit
## camera into ORBIT so the photographer owns the viewport. exit() restores all
## three exactly. While active (the tree is paused, so the orbit camera's
## _physics_process is frozen) the caller drives free orbit via orbit_delta(),
## which reuses orbit_camera's own _apply_orbit() look/position math and re-pins
## the photo FOV on top (the orbit camera's speed-FOV is disabled by zeroing its
## fov_strength export, restored on exit).
##
## Screenshots: Viewport.get_texture().get_image().save_png() under user://
## whenever the engine has a renderer. Headless mode (DisplayServer "headless")
## returns a {"written": false, "reason": "headless"} result WITHOUT touching any
## render path, so the gdUnit gate stays deterministic. Aperture is stored for a
## future DoF pass and exposed through get_photo_params() exactly like the F5
## settings knobs; filters paint a thin ColorRect on a topmost CanvasLayer.

const ORBIT_SCRIPT_PATH := "res://scripts/camera/orbit_camera.gd"
const HUD_SCRIPT_PATH := "res://scripts/race/race_ui.gd"
const ORBIT_MODE := 1  # orbit_camera.gd CameraMode.ORBIT
const FOV_MIN := 55.0
const FOV_MAX := 100.0
const APERTURE_MIN := 1.0
const APERTURE_MAX := 16.0
const FILTER_LAYER := 50
const DEFAULT_FILTER := "none"

## Photo filters by name: a translucent full-screen tint (true grading would be
## a shader; the ColorRect overlay is full-res and cheap on the GTX 970).
const FILTERS: Dictionary = {
	"none": Color(1.0, 1.0, 1.0, 0.0),
	"warm": Color(1.0, 0.82, 0.55, 0.22),
	"cool": Color(0.55, 0.78, 1.0, 0.22),
	"mono": Color(0.0, 0.0, 0.0, 0.35),
}

var _active := false
var _was_paused := false
var _was_hud_visible := true
var _prev_mode := -1
var _prev_fov_strength := 1.0
var _fov_strength := 1.0
var _aperture := 4.0
var _filter := DEFAULT_FILTER
var _orbit: Node3D = null
var _hud: CanvasLayer = null
var _overlay_layer: CanvasLayer = null
var _overlay: ColorRect = null

func _ready() -> void:
	# Photo mode must keep answering while the game is frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS

## Enters photo mode over the resolved orbit camera. Gracefully returns false
## (no state touched) when there is no orbit camera or when already active.
func enter() -> bool:
	if _active:
		return false
	var orbit := _resolve_orbit_camera()
	if orbit == null:
		return false
	_orbit = orbit
	_hud = _find_hud_layer()
	_was_paused = get_tree().paused
	get_tree().paused = true
	if _hud != null:
		_was_hud_visible = _hud.visible
		_hud.visible = false
	_prev_mode = int(_orbit.get("_mode"))
	_prev_fov_strength = float(_orbit.get("fov_strength"))
	_orbit.set("fov_strength", 0.0)  # the photo knob, not the speed-FOV, owns FOV
	_orbit.set("_mode", ORBIT_MODE)
	_orbit.call("_apply_mode")
	_apply_photo_fov()
	_active = true
	return true

## Leaves photo mode, restoring the orbit camera's prior mode, the HUD
## visibility and the tree pause state sampled at enter(). Returns false when
## not active.
func exit() -> bool:
	if not _active:
		return false
	if _orbit != null:
		if _prev_mode >= 0:
			_orbit.set("_mode", _prev_mode)
			_orbit.call("_apply_mode")
		_orbit.set("fov_strength", _prev_fov_strength)
		var cam := _orbit.get("_camera") as Camera3D
		if cam != null:
			cam.fov = float(_orbit.get("fov_min"))  # snap back like sync_camera_settings
	if _hud != null:
		_hud.visible = _was_hud_visible
	get_tree().paused = _was_paused
	_free_overlay()
	_active = false
	return true

func is_active() -> bool:
	return _active

## Hide/show toggle for the game HUD while in photo mode. Returns the new
## visibility (true when there is no HUD to toggle, so callers stay safe).
func toggle_ui() -> bool:
	if _hud == null:
		return true
	_hud.visible = not _hud.visible
	return _hud.visible

## Photo FOV knob (0..1): maps linearly across [FOV_MIN, FOV_MAX] on the orbit
## camera and is re-asserted after every orbit tick. Clamped into range.
func set_fov_strength(value: float) -> void:
	_fov_strength = clampf(value, 0.0, 1.0)
	_apply_photo_fov()

## Aperture slider (DoF-lite): stored data-only today, exposed through
## get_photo_params() so a future depth pass and a SaveManager round-trip both
## read it back identically. Clamped into range.
func set_aperture(value: float) -> void:
	_aperture = clampf(value, APERTURE_MIN, APERTURE_MAX)

## Applies a named filter from FILTERS (unknown names fall back to "none").
func set_filter(filter_name: String) -> void:
	_filter = filter_name if FILTERS.has(filter_name) else DEFAULT_FILTER
	_apply_filter_overlay()

## Drives the free orbit while photo mode is active: yaw/pitch deltas are
## accumulated on the orbit camera (pitch clamped to its pitch_min/max) and its
## own _apply_orbit() repositions + re-looks, then the photo FOV is re-pinned so
## the frozen car's speed never drifts it. No-op when not active.
func orbit_delta(yaw_delta: float, pitch_delta: float, delta: float) -> void:
	if _orbit == null or not _active:
		return
	var pitch_min := float(_orbit.get("pitch_min"))
	var pitch_max := float(_orbit.get("pitch_max"))
	_orbit.set("yaw", float(_orbit.get("yaw")) + yaw_delta)
	_orbit.set("pitch", clampf(float(_orbit.get("pitch")) + pitch_delta, pitch_min, pitch_max))
	_orbit.call("_apply_orbit", delta)
	_apply_photo_fov()

## Current photo state, shaped like the F5 camera-settings knobs so the settings
## menu / save layer can persist them with the exact same merge machinery.
func get_photo_params() -> Dictionary:
	return {
		"active": _active,
		"fov_strength": _fov_strength,
		"aperture": _aperture,
		"filter": _filter,
	}

func get_orbit_camera() -> Node3D:
	return _orbit

func get_filter_overlay() -> ColorRect:
	return _overlay

## True when the filter overlay layer is shown (i.e. a non-"none" filter is
## applied). Test hook + UI state readback.
func is_filter_overlay_visible() -> bool:
	return _overlay_layer != null and _overlay_layer.visible

## True when the engine has no renderer (gdUnit CLI / CI). The screenshot path
## must never touch the viewport in this mode.
static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

## Canonical screenshot path: user://screenshots/ultradrive_NNN.png.
static func build_screenshot_path(index: int) -> String:
	return "user://screenshots/ultradrive_%03d.png" % maxi(index, 0)

## Writes a full-frame PNG of the current viewport. Headless runs and missing
## viewports resolve to a {"written": false, ...} result WITHOUT touching any
## render path (the whole method bails before get_image()). Returns
## {"written": bool, "path": String, "reason": String} — path is empty whenever
## nothing was written.
func capture_screenshot(index: int = 0) -> Dictionary:
	if is_headless():
		return {"written": false, "path": "", "reason": "headless"}
	var viewport := get_viewport()
	if viewport == null:
		return {"written": false, "path": "", "reason": "no_viewport"}
	var path := build_screenshot_path(index)
	var image := viewport.get_texture().get_image()
	if image == null:
		return {"written": false, "path": "", "reason": "no_image"}
	var err := image.save_png(path)
	if err == OK:
		return {"written": true, "path": path, "reason": ""}
	return {"written": false, "path": "", "reason": "save_failed_%d" % err}

## Explicit orbit-camera injection (scene wiring / tests). Falls back to a
## tree-wide search for the orbit_camera.gd script when left empty.
func set_orbit_camera(camera: Node3D) -> void:
	_orbit = camera

func _resolve_orbit_camera() -> Node3D:
	if _orbit != null and is_instance_valid(_orbit):
		return _orbit
	if get_tree() == null:
		return null
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		var script: Script = node.get_script()
		if script != null and str(script.resource_path) == ORBIT_SCRIPT_PATH:
			return node as Node3D
	return null

## Locates the game HUD layer by name ("HUD") or by its race_ui.gd script, so
## photo mode hides exactly the driving UI.
func _find_hud_layer() -> CanvasLayer:
	if get_tree() == null:
		return null
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer == null:
			continue
		if layer.name == "HUD" or _hud_script_matches(layer):
			return layer
	return null

func _hud_script_matches(layer: CanvasLayer) -> bool:
	var script: Script = layer.get_script()
	return script != null and str(script.resource_path) == HUD_SCRIPT_PATH

## Pins the photo FOV on the orbit camera and keeps the speed-FOV from fighting
## it. Safe to call before enter() (no camera → pure param store).
func _apply_photo_fov() -> void:
	if _orbit == null:
		return
	_orbit.set("fov_strength", 0.0)
	var cam := _orbit.get("_camera") as Camera3D
	if cam != null:
		cam.fov = lerpf(FOV_MIN, FOV_MAX, _fov_strength)

## Materializes the overlay only when a filter is requested; "none" hides it.
func _apply_filter_overlay() -> void:
	if _filter == DEFAULT_FILTER:
		if _overlay_layer != null:
			_overlay_layer.visible = false
		return
	var rect := _ensure_overlay()
	rect.color = FILTERS[_filter]
	_overlay_layer.visible = true

func _ensure_overlay() -> ColorRect:
	if _overlay != null:
		return _overlay
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = FILTER_LAYER
	add_child(_overlay_layer)
	_overlay = ColorRect.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := _overlay_layer.get_viewport()
	var overlay_size := Vector2(1920.0, 1080.0)
	if viewport != null and viewport.get_visible_rect().size.x > 0.0 and viewport.get_visible_rect().size.y > 0.0:
		overlay_size = viewport.get_visible_rect().size
	_overlay.size = overlay_size
	_overlay_layer.add_child(_overlay)
	return _overlay

func _free_overlay() -> void:
	if _overlay != null:
		_overlay.free()
		_overlay = null
	if _overlay_layer != null:
		_overlay_layer.free()
		_overlay_layer = null