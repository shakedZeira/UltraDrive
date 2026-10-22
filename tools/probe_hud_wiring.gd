# tools/probe_hud_wiring.gd — throwaway diagnostic (delete after use).
# Boots the real PlayerCar + real HUD in one tree, simulates frames, and prints
# the LIVE values of every readout the user reported dead (speed, rpm, gear,
# hp, nm, coords). Proves or disproves "the HUD wiring is broken" end-to-end
# with the production car scene, not a test stub.
extends SceneTree

func _init() -> void:
	var hud: PackedScene = load("res://scenes/ui/hud.tscn")
	var car: PackedScene = load("res://scenes/vehicle/player_car.tscn")
	var root := Node3D.new()
	root.name = "ProbeRoot"
	root.add_child(car.instantiate())
	var hud_inst: Node = hud.instantiate()
	root.add_child(hud_inst)
	root.add_child(Camera3D.new())
	get_root().add_child(root)
	# Let @onready + _ready + a few _process ticks run.
	for i in range(12):
		await process_frame
	await physics_frame
	await physics_frame
	var vm: Node = root.get_node_or_null("/root/VehicleManager")
	var player: VehiclePhysics = vm.get_player_car() if vm != null else null
	print("PROBE VehicleManager present: ", vm != null, "  registered: ", player != null)
	var ui: CanvasLayer = hud_inst
	if player != null:
		var info: Dictionary = player.get_drive_info()
		print("PROBE drive_info: ", info)
	else:
		print("PROBE drive_info: <no car>")
	# Read the labels directly off the HUD.
	_dump(ui, "Cluster")
	_dump(ui, "PowerValue")
	_dump(ui, "TorqueValue")
	_dump(ui, "CoordsLabel")
	_dump(ui, "LapLabel")
	_dump(ui, "PositionLabel")
	print("PROBE race_over=", ui.get("_race_over"), " post_race_state=", ui.get("_post_race_state"))
	quit(0)

func _dump(ui: CanvasLayer, node_name: String) -> void:
	var node: Node = ui.find_child(node_name, true, false)
	if node == null:
		print("PROBE ", node_name, ": <MISSING>")
		return
	if node is Label:
		print("PROBE ", node_name, ".text=", (node as Label).text)
		return
	if node.has_method("set_speed_kmh"):
		print("PROBE ", node_name, ": <cluster>")
		return
	print("PROBE ", node_name, ": <", node.get_class(), ">")
