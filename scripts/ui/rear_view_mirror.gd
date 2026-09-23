# scripts/ui/rear_view_mirror.gd
class_name RearViewMirror
extends Control

## F4 virtual rear-view mirror (deferred-paid, iRacing VirtualMirrors model):
## a low-res SubViewport (256x144) plus a dedicated rear Camera3D whose view of
## "what's behind" is blitted onto a corner HUD panel through a ViewportTexture.
## Disabled by default (mirror_enabled = false) — a plain scene export that F5
## can drive through its persisted settings without touching this script. When
## enabled the SubViewport is built ONCE on entering the tree, uses
## render_target_update_mode = UPDATE_WHEN_PARENT_VISIBLE (a cost gate: the
## pass only re-renders while the mirror panel is actually visible, i.e. in
## cockpit mode), and the whole tree is freed with the node so nothing leaks.
##
## Frame-budget note for settings (F4 plan §4): this is a 256x144 pass, aim
## < 1 ms on the low-preset machines — roughly the cost of one extra shadow
## cascade. F5's "Camera and Feel" section can apply that note; it is not
## exposed here.
##
## Visibility gate mirrors CockpitRig: the mirror panel draws ONLY while the
## CockpitCamera owns the viewport (cockpit_camera_path export or an ancestor
## walk for a node named "CockpitCamera"). Headless-safe: no render signals,
## no MainLoop dependency; tests drive _ensure_mirror / _sync_mirror_camera /
## sync_visibility directly.

@export var mirror_enabled: bool = false
## Explicit pin to the rear-view camera target; empty = VehicleManager player
## car, then an ancestor-walk VehiclePhysics fallback.
@export var target: Node3D
@export var cockpit_camera_path: NodePath
@export_range(96, 512, 16) var viewport_width: int = 256
@export_range(54, 288, 9) var viewport_height: int = 144
## How far behind the car's rear (local +Z) the mirror camera sits.
@export var mirror_distance_behind: float = 1.6
## Height of the point the mirror camera looks along (backend rear view).
@export var mirror_look_height: float = 1.0
## Distance in front of the mirror camera it looks toward ("infinity" for the
## rearward road; anything far behind the bumper flattens to a proper mirror).
@export var mirror_look_ahead: float = 24.0

@onready var frame: Panel = $Frame
@onready var display: TextureRect = $Frame/Display

var _viewport: SubViewport = null
var _mirror_camera: Camera3D = null

func _ready() -> void:
	visible = false
	if mirror_enabled:
		_ensure_mirror()
		_refresh_display_texture()
	sync_visibility()

func _process(_delta: float) -> void:
	sync_visibility()
	_sync_mirror_camera()

func _physics_process(_delta: float) -> void:
	_sync_mirror_camera()

## Builds the SubViewport + rear camera exactly once. Safe to call many times:
## the second call is a no-op returning the existing viewport (the "creates its
## texture once" contract). Returns true when it actually constructed.
func _ensure_mirror() -> bool:
	if _viewport != null:
		return false
	_viewport = SubViewport.new()
	_viewport.name = "MirrorViewport"
	_viewport.size = Vector2i(viewport_width, viewport_height)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	# Inherit the world + environment from the active scene instead of a second
	# baked world — one light list, one environment, cheap.
	_viewport.own_world_3d = false
	add_child(_viewport)

	_mirror_camera = Camera3D.new()
	_mirror_camera.name = "MirrorCamera"
	_mirror_camera.fov = 55.0
	_mirror_camera.near = 0.1
	_mirror_camera.far = 300.0
	_viewport.add_child(_mirror_camera)
	return true

## Returns the mirror viewport (null until mirror_enabled builds it) — test
## seam for the "no leak / built once" gate.
func get_mirror_viewport() -> SubViewport:
	return _viewport

func get_mirror_camera() -> Camera3D:
	return _mirror_camera

func is_mirror_built() -> bool:
	return _viewport != null

## Mirror-optionality seam (ACC VirtualMirrors gate): flip before entering the
## tree for the zero-cost default; toggling live rebuilds/tears down the
## SubViewport so an F5 setting can add it at runtime.
func set_mirror_enabled(enabled: bool) -> void:
	if mirror_enabled == enabled:
		return
	mirror_enabled = enabled
	if enabled:
		if not _ensure_mirror():
			_refresh_display_texture()
	else:
		if _viewport != null:
			_viewport.queue_free()
			_viewport = null
			_mirror_camera = null
	sync_visibility()

func get_mirror_enabled() -> bool:
	return mirror_enabled

func _refresh_display_texture() -> void:
	if _viewport != null and display != null:
		display.texture = _viewport.get_texture()

## Polls cockpit-camera ownership (same probe as CockpitRig / CockpitDash) and
## mirrors it onto this node's visibility. Returns the resulting state.
func sync_visibility() -> bool:
	var cam := _find_cockpit_camera()
	var active := false
	if cam != null and cam.has_method("is_current_view"):
		active = bool(cam.call("is_current_view"))
	if not mirror_enabled:
		visible = false
	else:
		visible = active
	return visible

## Re-aims the mirror camera at the rearward road each frame: camera sits
## mirror_distance_behind behind the car tail and looks along the car's back
## heading, so the panel shows what is genuinely behind the car.
func _sync_mirror_camera() -> void:
	if _mirror_camera == null:
		return
	var car := _resolve_target()
	if car == null:
		return
	var heading := car.global_basis.z.normalized()
	var cam_pos := car.global_position + heading * mirror_distance_behind
	cam_pos.y += 0.15
	_mirror_camera.global_position = cam_pos
	var look_at := cam_pos + heading * mirror_look_ahead
	look_at.y = car.global_position.y + mirror_look_height
	_mirror_camera.look_at(look_at, Vector3.UP)

func _resolve_target() -> Node3D:
	if target != null:
		return target
	var player := VehicleManager.get_player_car()
	if player != null:
		return player
	var node := get_parent()
	while node != null:
		if node is VehiclePhysics:
			return node as Node3D
		node = node.get_parent()
	return null

func _find_cockpit_camera() -> Node:
	if not cockpit_camera_path.is_empty():
		var via_path := get_node_or_null(cockpit_camera_path)
		if via_path != null:
			return via_path
	var node := get_parent()
	while node != null:
		var cam := node.get_node_or_null("CockpitCamera")
		if cam != null:
			return cam
		node = node.get_parent()
	return null