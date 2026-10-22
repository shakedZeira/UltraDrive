# tests/suites/test_car_reverse_lights.gd
extends GdUnitTestSuite

## Rear-lights gate (GTR R35 lights/glass plan): (1) the taillight collector is
## PLURAL — the R35 rear cluster is two mesh nodes (Taillight_L + Taillight_R),
## each cloning the shared GLB material, so a single-match cache only ever ramps
## half of the four lamps; (2) the reverse cue rides those EXISTING taillight
## materials: while reverse is engaged they glow bright white and the GLB-authored
## base emissive colour is restored when it is released (an earlier pass built a
## separate white lamp mesh and a playtest read it as an extra light — that path is
## gone); (3) the player controller caches every taillight clone and drives the
## reverse cue off `gear < 0`. Fully hand-built nodes + the real controller script
## — no scene/GLB instantiation (the GLB-specific gates live in test_gtr_r35.gd).
## Headless-safe, no frames, leak-free.

const PlayerCarScript: GDScript = preload("res://scripts/player/player_car_controller.gd")

## R35 GLB-space taillight origins (x, y, z), mirrored across the centreline.
const R35_TAIL_X := 0.32
const R35_TAIL_Y := 0.788
const R35_TAIL_Z := -2.238

## Name the deleted geometry builder used for its holder; the reverse cue must
## never add one of these again.
const DEFUNCT_LAMP_HOLDER := "ReverseLamps"

var _managed_nodes: Array = []

func before_test() -> void:
	_managed_nodes.clear()

func after_test() -> void:
	for node in _managed_nodes:
		if is_instance_valid(node):
			node.free()
	_managed_nodes.clear()

func _new_root() -> Node3D:
	var root := Node3D.new()
	_managed_nodes.append(root)
	return root

func _new_mesh_instance(material: StandardMaterial3D, material_name: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	material.resource_name = material_name
	mesh.surface_set_material(0, material)
	mesh_instance.mesh = mesh
	_managed_nodes.append(mesh_instance)
	return mesh_instance

## Hand-built GLB-like visual: two taillight nodes at the measured R35
## origins, each with its own "Taillight" material (apply_paint then clones
## them per-surface, exactly like the real GLB's two nodes).
func _new_two_tail_root() -> Node3D:
	var root := _new_root()
	var left := _new_mesh_instance(StandardMaterial3D.new(), "Taillight")
	left.name = "Taillight_L"
	left.position = Vector3(R35_TAIL_X, R35_TAIL_Y, R35_TAIL_Z)
	root.add_child(left)
	var right := _new_mesh_instance(StandardMaterial3D.new(), "Taillight")
	right.name = "Taillight_R"
	right.position = Vector3(-R35_TAIL_X, R35_TAIL_Y, R35_TAIL_Z)
	root.add_child(right)
	return root

## Untyped on purpose: the controller script has no class_name, so the
## instance has to stay dynamically typed for the suite to drive it.
func _new_controller():
	var controller = PlayerCarScript.new()
	_managed_nodes.append(controller)
	return controller

# --- FIX 1: the collector is plural ---

func test_find_named_materials_collects_every_taillight_clone() -> void:
	var root := _new_two_tail_root()
	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)

	var all := CarVisuals.find_named_materials(root, "taillight")
	assert_that(all.size()).is_equal(2)
	if all.size() < 2:
		return
	# The two nodes each got their OWN clone of the shared GLB material —
	# glowing one must never be glowing the other by aliasing.
	assert_that(all[0].get_instance_id()).is_not_equal(all[1].get_instance_id())

	# The singular convenience wrapper still resolves the first match.
	var first := CarVisuals.find_named_material(root, "taillight")
	assert_that(first).is_not_null()
	assert_that(first.resource_name).is_equal("Taillight")

	# The direct R35 "4 lamps" fix: ramping the ARRAY lights BOTH clones.
	CarVisuals.apply_brake_glow_all(all, 1.0)
	for material: Variant in all:
		var tail := material as StandardMaterial3D
		assert_that(tail.emission_enabled).is_true()
		assert_that(tail.emission_energy_multiplier).is_equal_approx(CarVisuals.BRAKE_GLOW_MAX, 0.001)

func test_find_named_materials_is_empty_on_null_and_absent() -> void:
	assert_that(CarVisuals.find_named_materials(null, "taillight").is_empty()).is_true()
	var root := _new_root()
	root.add_child(_new_mesh_instance(StandardMaterial3D.new(), "Paint"))
	assert_that(CarVisuals.find_named_materials(root, "taillight").is_empty()).is_true()

func test_find_named_materials_dedups_shared_material() -> void:
	# One material instance reachable through TWO nodes (a mesh reused under two
	# parents) counts once, so the array size stays a meaningful "number of lit
	# lamp materials".
	var root := _new_root()
	var shared := StandardMaterial3D.new()
	shared.resource_name = "Taillight"
	for node_name: String in ["Taillight_L", "Taillight_R"]:
		var mesh_instance := _new_mesh_instance(shared, "Taillight")
		mesh_instance.name = node_name
		root.add_child(mesh_instance)
	assert_that(CarVisuals.find_named_materials(root, "taillight").size()).is_equal(1)

# --- FIX 2: the reverse cue whitens the EXISTING rear lamps ---

func test_apply_reverse_glow_whitens_existing_taillights() -> void:
	var root := _new_two_tail_root()
	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)
	var tails := CarVisuals.find_named_materials(root, "taillight")
	assert_that(tails.size()).is_equal(2)
	if tails.size() < 2:
		return

	CarVisuals.apply_reverse_glow(tails, true)
	for material: StandardMaterial3D in tails:
		assert_that(material.emission_enabled).is_true()
		assert_that(material.emission).is_equal(CarVisuals.REVERSE_LIGHT_COLOR)
		assert_that(material.emission_energy_multiplier).is_equal_approx(CarVisuals.REVERSE_LIGHT_ENERGY, 0.001)

func test_apply_reverse_glow_restores_base_emission_when_released() -> void:
	var root := _new_two_tail_root()
	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)
	var tails := CarVisuals.find_named_materials(root, "taillight")
	assert_that(tails.size()).is_equal(2)
	if tails.size() < 2:
		return

	# The base emissive colour the reverse cue must save and restore — on a real
	# GLB that is the RED the brake ramp modulates. apply_brake_glow() only ever
	# touches ENERGY, never the colour, so if the reverse white were left in
	# place the tail lights would stay white forever.
	var bases: Array[Color] = []
	for material: StandardMaterial3D in tails:
		bases.append(material.emission)

	CarVisuals.apply_reverse_glow(tails, true)
	for material: StandardMaterial3D in tails:
		assert_that(material.emission).is_equal(CarVisuals.REVERSE_LIGHT_COLOR)

	CarVisuals.apply_reverse_glow(tails, false)
	for index: int in range(tails.size()):
		assert_that(tails[index].emission).is_equal(bases[index])

	# Restored red survives a brake ramp: the ramp only moves ENERGY, and the
	# reverse white must not have leaked into the base colour.
	CarVisuals.apply_brake_glow_all(tails, 1.0)
	for index: int in range(tails.size()):
		assert_that(tails[index].emission).is_equal(bases[index])
		assert_that(tails[index].emission_energy_multiplier).is_equal_approx(CarVisuals.BRAKE_GLOW_MAX, 0.001)

	# Idempotent: repeating the release never errors or drifts.
	CarVisuals.apply_reverse_glow(tails, false)
	for index: int in range(tails.size()):
		assert_that(tails[index].emission).is_equal(bases[index])

func test_apply_reverse_glow_is_a_safe_no_op_on_empty_and_null_entries() -> void:
	var empty: Array[StandardMaterial3D] = []
	CarVisuals.apply_reverse_glow(empty, true)
	CarVisuals.apply_reverse_glow(empty, false)
	assert_that(empty.is_empty()).is_true()

	# A null element in the array is skipped, not dereferenced. resize() is the
	# safe way to get a null slot into a typed Object array (it leaves one there
	# without going through element validation).
	var with_null: Array[StandardMaterial3D] = []
	with_null.resize(1)
	assert_that(with_null[0] == null).is_true()
	CarVisuals.apply_reverse_glow(with_null, true)
	CarVisuals.apply_reverse_glow(with_null, false)

func test_reverse_glow_leaves_no_built_lamp_geometry_after_paint() -> void:
	# The old builder parented a "ReverseLamps" holder under the visual. The new
	# cue adds NO geometry at all — assert the painted visual carries no such node
	# (grep-free structural check; the name is the deleted holder's).
	var root := _new_two_tail_root()
	CarVisuals.apply_paint(root, CarVisuals.DEFAULT_PAINT)
	assert_that(CarVisuals.find_named_materials(root, "taillight").size()).is_equal(2)
	assert_that(root.find_child(DEFUNCT_LAMP_HOLDER, true, false)).is_null()

# --- player controller seam ---

func test_player_controller_whitens_on_reverse_and_restores_in_gear() -> void:
	var controller = _new_controller()
	var instance := _new_two_tail_root()
	CarVisuals.apply_paint(instance, CarVisuals.DEFAULT_PAINT)
	controller.call("_cache_visuals", instance)

	# The cache is the ARRAY, not a single material (the old single-match cache
	# is exactly what left Taillight_R dark on the R35). Read it through the
	# typed accessor so the seam the controller actually drives is the one under
	# test (a bare get("_taillight_materials") would stay an untyped Variant).
	var cached: Array[StandardMaterial3D] = controller.taillight_materials()
	assert_that(cached.size()).is_equal(2)
	if cached.size() < 2:
		return
	var bases: Array[Color] = []
	for material: StandardMaterial3D in cached:
		bases.append(material.emission)

	# Drive the seam exactly as _process does: brake ramps BOTH clones, then the
	# reverse cue keyed on gear == -1 (whitens the cached array).
	CarVisuals.apply_brake_glow_all(cached, 1.0)
	CarVisuals.apply_reverse_glow(cached, true)
	for material: StandardMaterial3D in cached:
		assert_that(material.emission).is_equal(CarVisuals.REVERSE_LIGHT_COLOR)
		assert_that(material.emission_energy_multiplier).is_equal_approx(CarVisuals.REVERSE_LIGHT_ENERGY, 0.001)

	# gear >= 0: the white is released and each clone returns to its red base.
	CarVisuals.apply_reverse_glow(cached, false)
	for index: int in range(cached.size()):
		assert_that(cached[index].emission).is_equal(bases[index])
