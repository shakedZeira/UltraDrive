# scripts/race/cockpit_dash.gd
class_name CockpitDash
extends CanvasLayer

## F4 dash-as-HUD: in-cockpit speed / gear / rpm readouts plus the auto
## "subtract cluster" HUD dim, both gated on the CockpitCamera owning the
## viewport. The dash mirrors the SAME drive feed race_ui.gd already drives the
## %Cluster on — car.get_drive_info() (speed_kmh / gear / rpm), read-only, so
## there is no second source of truth. When the cockpit camera is the current
## view the dash readouts appear (dark panel + light text, readable at night
## against the F2a rig's mild self-emission) and the screen %Cluster is dimmed
## to cluster_dim_opacity (~15-25%, GT7 Display-Setting style) so the player
## reads the car, not the screen; every other camera mode restores the cluster.
##
## Optionality (ACC dash-removal demand): dash_hud_enabled gates the readout
## panel independently of the cluster dim, so a player can strip the dash
## without touching the F2a cockpit geometry rig.
##
## Headless-safe, like CockpitRig: no render signals, no MainLoop dependency;
## the cockpit-camera probe polls is_current_view() (found via the
## cockpit_camera_path export or an ancestor walk for a node named
## "CockpitCamera"). Polled every _process so it follows the C-cycle live.

@export var dash_hud_enabled: bool = true
## Opacity the %Cluster moderates to in cockpit mode (GT7 "subtract cluster"
## range; 1.0 = unchanged, 0.2 = dimmed to ~20%).
@export_range(0.05, 1.0, 0.05) var cluster_dim_opacity: float = 0.2
## The HUD-dim gate: when false the cluster stays full even in cockpit mode.
@export var hud_dim_enabled: bool = true
## Explicit pin to the cockpit camera (same contract as CockpitRig). Empty =
## ancestor walk for a node named "CockpitCamera".
@export var cockpit_camera_path: NodePath
## NodePath to the %Cluster canvas to dim. Default matches hud.tscn layout
## (CockpitDash is a child of the HUD CanvasLayer; Cluster lives under Root).
@export var cluster_path: NodePath = NodePath("../Root/Cluster")

@onready var panel: Control = $DashPanel
@onready var gear_label: Label = $DashPanel/GearLabel
@onready var rpm_label: Label = $DashPanel/RpmLabel
@onready var speed_label: Label = $DashPanel/SpeedLabel

var _cluster: CanvasItem = null
var _cockpit_current := false

func _ready() -> void:
	_cluster = _resolve_cluster()
	panel.visible = false
	sync_cockpit_mode()

func _process(_delta: float) -> void:
	var cockpit := sync_cockpit_mode()
	_update_cluster_dim()
	panel.visible = cockpit and dash_hud_enabled and _has_player_car()
	if panel.visible:
		refresh_readouts()

## Polls cockpit-camera ownership and mirrors it internally. Returns the
## current state so tests can assert the gate directly.
func sync_cockpit_mode() -> bool:
	var cam := _find_cockpit_camera()
	var active := false
	if cam != null and cam.has_method("is_current_view"):
		active = bool(cam.call("is_current_view"))
	_cockpit_current = active
	return active

## Mirrors race_ui.gd's feed: car.get_drive_info() -> speed_kmh / gear / rpm.
## Read-only and NaN-safe (a non-finite drive value renders as 0, never "nan").
func refresh_readouts() -> void:
	var car := VehicleManager.get_player_car()
	if car == null or not car.has_method("get_drive_info"):
		return
	var info: Dictionary = car.get_drive_info()
	var speed_kmh := _safe_float(info.get("speed_kmh", 0.0))
	var rpm := _safe_float(info.get("rpm", 0.0))
	var gear := int(info.get("gear", 1))
	speed_label.text = "%d" % roundi(speed_kmh)
	rpm_label.text = "%d" % roundi(rpm)
	gear_label.text = _gear_text(gear)

## The dash-HUD optionality toggle (ACC dash-removal seam). The readout panel
## respects it independently of the cluster dim.
func set_dash_hud_enabled(enabled: bool) -> void:
	dash_hud_enabled = enabled
	panel.visible = enabled and _cockpit_current and _has_player_car()

func get_dash_hud_enabled() -> bool:
	return dash_hud_enabled

## The HUD-dim toggle. When disabled, the cluster stays at full opacity even in
## cockpit mode (the "keep the screen cluster" choice).
func set_hud_dim_enabled(enabled: bool) -> void:
	hud_dim_enabled = enabled
	_update_cluster_dim()

func get_hud_dim_enabled() -> bool:
	return hud_dim_enabled

func set_cluster_dim_opacity(opacity: float) -> void:
	cluster_dim_opacity = clampf(opacity, 0.05, 1.0)
	_update_cluster_dim()

func get_cluster_dim_opacity() -> float:
	return cluster_dim_opacity

func _update_cluster_dim() -> void:
	if _cluster == null:
		return
	var alpha := 1.0
	if _cockpit_current and hud_dim_enabled:
		alpha = cluster_dim_opacity
	var color := _cluster.modulate
	_cluster.modulate = Color(color.r, color.g, color.b, alpha)

func _has_player_car() -> bool:
	var car := VehicleManager.get_player_car()
	return car != null and car.has_method("get_drive_info")

func _resolve_cluster() -> CanvasItem:
	if cluster_path.is_empty():
		return null
	var node := get_node_or_null(cluster_path)
	return node as CanvasItem

## Same probe CockpitRig.gd uses: explicit path first, then an ancestor walk
## for a node named "CockpitCamera" (the wired player scenes all name it that).
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

static func _safe_float(value: Variant) -> float:
	var f := float(value)
	return f if is_finite(f) else 0.0

static func _gear_text(gear: int) -> String:
	return "R" if gear == -1 else str(gear)