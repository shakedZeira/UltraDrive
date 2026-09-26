# tests/suites/test_speed_trap_visuals.gd
extends GdUnitTestSuite

## Visible speed-trap dressing gate. SpeedTrapVisuals builds one gantry per
## UNCLAIMED `speedtrap_*` collectible out of the SAME published placement data
## the trigger uses, aligned to the host road's tangent and width, and swaps it
## to a claimed look (dimmed posts, green glint, fading flash light) on
## CollectibleField.collectible_claimed.
##
## Layers of gate, all headless-safe (no Terrain3D, no tree walk; the deferred
## first build is driven through the same rebuild() the node calls itself):
##  * PURE: frame_for() / post_offset_for() resolve the heading and the post
##    offsets off the published POI + road defs, including the unknown-road
##    fallback, so the alignment is asserted without building a single mesh.
##  * SCENE: a real CollectibleField + SpeedTrapVisuals pair proves the wiring --
##    one gate per unclaimed trap and none for bonus boards / photo spots, the
##    claim path (flash spawned, faded, freed), and the rebuild-on-ready path
##    with a pre-claimed save.
##
## The slot this suite writes is snapshotted in before_test and restored in
## after_test (a claim moves the shipped wallet and XP), so it never clobbers a
## real playthrough save. Dressing nodes are freed sync rather than queue_free'd,
## so a gate never survives into the next test.

const SLOT := 0
const WALLET_BEFORE := 4_321
## Vector/angle tolerance: the frames are exact maths, this is only float slack.
const EPS := 0.001

var _slot_backup: Dictionary = {}
var _slot_existed := false
var _fields: Array[CollectibleField] = []
var _visuals: Array[SpeedTrapVisuals] = []
var _pair_index := 0

# ---------------------------------------------------------------------------
# Fixtures.
# ---------------------------------------------------------------------------

func before_test() -> void:
	_slot_existed = SaveManager.has_save(SLOT)
	_slot_backup = SaveManager.load_game(SLOT)
	SaveManager.save_career_money(SLOT, {
		"credits": WALLET_BEFORE,
		"total_credited": WALLET_BEFORE,
		"total_spent": 0,
	})
	# Empty claim set, so gate counts never depend on the player's history.
	SaveManager.save_collectibles(SLOT, {})
	_pair_index = 0

func after_test() -> void:
	for visuals in _visuals:
		if is_instance_valid(visuals) and visuals.get_parent() != null:
			visuals.free()
	for field in _fields:
		if is_instance_valid(field) and field.get_parent() != null:
			field.free()
	_visuals.clear()
	_fields.clear()
	if _slot_existed:
		SaveManager.save_game(SLOT, _slot_backup)
		return
	DirAccess.remove_absolute("user://saves/slot_%d.json" % (SLOT + 1))

func _defs() -> Array[RoadDef]:
	return CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})

## The shipped pairing, as open_world_root.tscn builds it: the field first (so
## its _ready has already read the save and published the registry set), then the
## dressing node beside it. Names are suffixed so a test that wants two worlds
## gets two real nodes instead of a silent "@CollectibleField@2" rename.
func _make_pair() -> SpeedTrapVisuals:
	_pair_index += 1
	var field := CollectibleField.new()
	field.name = "CollectibleField%d" % _pair_index
	field.save_on_pause = false
	add_child(field)
	field.set_physics_process(false)
	_fields.append(field)
	var visuals := SpeedTrapVisuals.new()
	visuals.name = "SpeedTrapVisuals%d" % _pair_index
	visuals.field_path = NodePath("../" + field.name)
	add_child(visuals)
	_visuals.append(visuals)
	return visuals

## Boots the deferred first build synchronously -- the same rebuild() _process
## makes on the first frame after _ready.
func _booted(visuals: SpeedTrapVisuals) -> SpeedTrapVisuals:
	visuals.rebuild()
	return visuals

func _field_of(visuals: SpeedTrapVisuals) -> CollectibleField:
	for field in _fields:
		if visuals.get_node_or_null(visuals.field_path) == field:
			return field
	return _fields[0]

func _trap_ids(placed: Dictionary) -> Array[String]:
	return Collectibles.ids_of_kind(placed, Collectibles.KIND_SPEED_TRAP)

## Count of collision / area nodes anywhere under `node` -- the check that the
## dressing never touches the physics world.
func _physics_nodes_in(node: Node) -> int:
	var found := 0
	if node is CollisionObject3D or node is Area3D:
		found += 1
	for child: Node in node.get_children():
		found += _physics_nodes_in(child)
	return found

## Claims one collectible through the field's own shipped rule path.
func _claim(field: CollectibleField, collectible_id: String) -> void:
	var poi: Dictionary = field.placed()[collectible_id]
	var speed := 999.0 if Collectibles.kind_of_id(collectible_id) == Collectibles.KIND_SPEED_TRAP else 0.0
	field.claim_at(poi["position"] as Vector3, speed)

## Pre-banks `count` traps straight into the slot, the way a previous session
## would have, so the rebuild-on-ready path sees them as claimed.
func _seed_claimed_traps(count: int) -> Array[String]:
	var placed: Dictionary = Collectibles.place_data(_defs())
	var claimed := _trap_ids(placed).slice(0, count)
	var ledger := Collectibles.new()
	for collectible_id: String in claimed:
		ledger.claim(placed, collectible_id)
	ledger.save_to_slot(SLOT)
	return claimed

# ---------------------------------------------------------------------------
# PURE: the road frame a gate is aligned to.
# ---------------------------------------------------------------------------

## A trap's gate faces along its host road's centreline tangent and straddles
## that road at half its own width plus the clearance, so the player drives
## BETWEEN the posts instead of through one.
func test_frame_follows_the_host_road_tangent_and_width() -> void:
	var defs := _defs()
	var placed: Dictionary = Collectibles.place_data(defs)
	var by_road: Dictionary = {}
	for def: RoadDef in defs:
		by_road[def.id] = def
	var traps := _trap_ids(placed)
	for collectible_id: String in traps:
		var poi: Dictionary = placed[collectible_id]
		var host: RoadDef = by_road.get(str(poi["road_id"]), null)
		assert_object(host).is_not_null()
		if host == null:
			continue
		var frame := SpeedTrapVisuals.frame_for(poi, defs)
		assert_bool(bool(frame["known"])).is_true()
		# A unit, horizontal heading -- the gate never rolls with the road grade.
		var forward: Vector3 = frame["forward"]
		assert_float(forward.length()).is_equal_approx(1.0, EPS)
		assert_float(absf(forward.y)).is_less(EPS)
		# And posts that can never stand inside the carriageway.
		var offset := SpeedTrapVisuals.post_offset_for(float(frame["width"]))
		assert_float(offset).is_greater_equal(host.width * 0.5)
		assert_float(offset).is_greater_equal(SpeedTrapVisuals.MIN_POST_OFFSET)
	assert_int(traps.size()).is_equal(int(Collectibles.FAMILY_COUNT[Collectibles.KIND_SPEED_TRAP]))

## Post offsets are the road's half width plus the clearance, floored so a 7 m
## dirt track still clears, with the plain 7 m stand-in when the width is
## unknown (a placement with no resolvable host road).
func test_post_offset_scales_with_road_width_and_falls_back() -> void:
	assert_float(SpeedTrapVisuals.post_offset_for(24.0)).is_equal(13.5)
	assert_float(SpeedTrapVisuals.post_offset_for(10.0)).is_equal(6.5)
	assert_float(SpeedTrapVisuals.post_offset_for(7.0)).is_equal(SpeedTrapVisuals.MIN_POST_OFFSET)
	assert_float(SpeedTrapVisuals.post_offset_for(0.0)).is_equal(SpeedTrapVisuals.DEFAULT_POST_OFFSET)
	assert_float(SpeedTrapVisuals.post_offset_for(-1.0)).is_equal(SpeedTrapVisuals.DEFAULT_POST_OFFSET)

## No resolvable host road: straight ahead (local -Z) and the 7 m stand-in, so a
## gate is still built rather than dropped from the world.
func test_frame_falls_back_to_straight_ahead_without_a_road() -> void:
	var poi: Dictionary = {
		"id": "speedtrap_0",
		"kind": Collectibles.KIND_SPEED_TRAP,
		"road_id": "not-a-road",
		"position": Vector3(10.0, 2.0, 20.0),
		"extra": {"point_index": 0, "def_index": 0},
	}
	var frame := SpeedTrapVisuals.frame_for(poi, _defs())
	assert_bool(bool(frame["known"])).is_false()
	assert_that(frame["forward"] as Vector3).is_equal(SpeedTrapVisuals.FALLBACK_FORWARD)
	assert_float(SpeedTrapVisuals.post_offset_for(float(frame["width"]))).is_equal(7.0)
	assert_object(SpeedTrapVisuals.find_def(_defs(), "not-a-road")).is_null()

# ---------------------------------------------------------------------------
# SCENE: one gate per unclaimed speed trap, and nothing else.
# ---------------------------------------------------------------------------

## One visible gate per unclaimed speedtrap_* POI -- each a fused-primitive
## gantry (Structure + Glint) standing on the published road vertex -- and
## nothing for the 12 bonus boards / 8 photo spots sharing the same data.
func test_one_gate_per_unclaimed_speed_trap_and_nothing_else() -> void:
	var visuals := _booted(_make_pair())
	var placed: Dictionary = _field_of(visuals).placed()
	var traps := _trap_ids(placed)
	assert_int(visuals.gate_count()).is_equal(traps.size())
	assert_array(visuals.gate_ids()).contains_exactly(traps)
	for collectible_id: String in traps:
		var gate := visuals.gate_node(collectible_id)
		assert_object(gate).is_not_null()
		if gate == null:
			continue
		assert_that(str(gate.name)).is_equal("Gate_%s" % collectible_id)
		assert_object(gate.get_node_or_null(SpeedTrapVisuals.STRUCTURE_NAME)).is_not_null()
		assert_object(gate.get_node_or_null(SpeedTrapVisuals.GLINT_NAME)).is_not_null()
		# Dressed, not simulated: a gate owns no collision or area node anywhere
		# below it, so nothing about it can enter the physics world.
		assert_int(_physics_nodes_in(gate)).is_equal(0)
		assert_that(visuals.gate_look(collectible_id)).is_equal("active")
		# A handful of boxes, not a model: the whole gate is 6 boxes = 72 tris.
		assert_int(visuals.gate_triangle_count(collectible_id)).is_equal(72)
	assert_int(visuals.gate_count()).is_less(placed.size())

## The gate stands exactly on the published anchor -- the same road vertex the
## trigger measures its claim radius from -- and points along that road, so a
## mesh and a trigger can never disagree by a metre.
func test_gates_stand_on_the_published_road_vertices() -> void:
	var visuals := _booted(_make_pair())
	var placed: Dictionary = _field_of(visuals).placed()
	var defs := _defs()
	for collectible_id: String in _trap_ids(placed):
		var poi: Dictionary = placed[collectible_id]
		var gate := visuals.gate_node(collectible_id)
		if gate == null:
			continue
		var expected := poi["position"] as Vector3
		assert_that(gate.global_position).is_equal(expected)
		var frame := SpeedTrapVisuals.frame_for(poi, defs)
		var forward: Vector3 = frame["forward"]
		assert_float(visuals.gate_forward(collectible_id).dot(forward)).is_equal_approx(1.0, EPS)
		# The posts really are as far out as the frame asked for.
		assert_float(visuals.gate_post_offset(collectible_id)).is_equal_approx(
			SpeedTrapVisuals.post_offset_for(float(frame["width"])), EPS)

## A wired ground-height provider re-seats the gate on the real surface (the
## prop_scatterer / foliage contract); with none, the road vertex Y stands.
func test_ground_height_provider_takes_precedence_over_the_poi_y() -> void:
	var visuals := _make_pair()
	visuals.ground_height_provider = func(_xz: Vector2) -> float: return 12.5
	visuals.rebuild()
	var trap_id := visuals.gate_ids()[0]
	var anchor := (_field_of(visuals).placed()[trap_id] as Dictionary)["position"] as Vector3
	var seated := visuals.gate_node(trap_id).global_position
	assert_float(seated.y).is_equal(12.5)
	assert_float(seated.x).is_equal(anchor.x)
	assert_float(seated.z).is_equal(anchor.z)

	var flat := _booted(_make_pair())
	assert_float(flat.gate_node(trap_id).global_position.y).is_equal(anchor.y)

# ---------------------------------------------------------------------------
# SCENE: the claim path.
# ---------------------------------------------------------------------------

## Claiming a trap through the field's own rule path marks the gate claimed,
## swaps it to the dimmed/green look and spawns the flash light; ticking the fade
## out frees the light and settles the glint. The gate itself stays standing.
func test_claiming_a_trap_flashes_then_settles_on_the_claimed_look() -> void:
	var visuals := _booted(_make_pair())
	var field := _field_of(visuals)
	var trap_id := _trap_ids(field.placed())[0]
	var gate := visuals.gate_node(trap_id)
	assert_object(gate).is_not_null()
	if gate == null:
		return
	assert_that(visuals.gate_look(trap_id)).is_equal("active")
	assert_bool(visuals.is_processing()).is_false()

	_claim(field, trap_id)
	assert_bool(visuals.is_claimed(trap_id)).is_true()
	assert_bool(visuals.has_gate(trap_id)).is_true()
	assert_that(visuals.gate_look(trap_id)).is_equal("flash")
	# Flash in flight, and the node is processing again only because of it.
	var light := visuals.flash_light(trap_id)
	assert_object(light).is_not_null()
	assert_int(visuals.flash_count()).is_equal(1)
	assert_bool(visuals.is_processing()).is_true()
	if light != null:
		assert_float(light.light_energy).is_equal(SpeedTrapVisuals.FLASH_ENERGY)
		assert_bool(visuals.tick(SpeedTrapVisuals.FLASH_SECONDS * 0.5)).is_true()
		assert_float(light.light_energy).is_less(SpeedTrapVisuals.FLASH_ENERGY)
		assert_float(light.light_energy).is_greater(0.0)

	# Burnt out: the light is gone and the glint settled on the steady claimed
	# green, with the node idle again.
	assert_bool(visuals.tick(SpeedTrapVisuals.FLASH_SECONDS * 0.5 + 0.01)).is_false()
	assert_object(visuals.flash_light(trap_id)).is_null()
	assert_int(visuals.flash_count()).is_equal(0)
	assert_object(gate.get_node_or_null(SpeedTrapVisuals.FLASH_LIGHT_NAME)).is_null()
	assert_float(visuals.flash_time_left()).is_equal(0.0)
	assert_that(visuals.gate_look(trap_id)).is_equal("claimed")
	assert_bool(visuals.is_processing()).is_false()
	# A second entry is a no-op: the trap pays once, so it never re-flashes.
	visuals.mark_claimed(trap_id)
	assert_int(visuals.flash_count()).is_equal(0)

## A trap crossed UNDER the speed target pays nothing, so its gate never enters
## the claimed look and never flashes.
func test_under_speed_claim_leaves_the_gate_live() -> void:
	var visuals := _booted(_make_pair())
	var field := _field_of(visuals)
	var trap_id := _trap_ids(field.placed())[0]
	var anchor := (field.placed()[trap_id] as Dictionary)["position"] as Vector3
	field.claim_at(anchor, 0.0)
	assert_bool(field.is_claimed(trap_id)).is_false()
	assert_bool(visuals.is_claimed(trap_id)).is_false()
	assert_bool(visuals.has_gate(trap_id)).is_true()
	assert_that(visuals.gate_look(trap_id)).is_equal("active")
	assert_int(visuals.flash_count()).is_equal(0)
	assert_bool(visuals.is_processing()).is_false()

## Bonus boards and photo spots pay through the very same signal but have no
## gate: they must not dim or flash anything.
func test_bonus_and_photo_claims_never_touch_the_trap_gates() -> void:
	var visuals := _booted(_make_pair())
	var field := _field_of(visuals)
	var placed := field.placed()
	var before := visuals.gate_transforms()
	_claim(field, Collectibles.ids_of_kind(placed, Collectibles.KIND_BONUS)[0])
	_claim(field, Collectibles.ids_of_kind(placed, Collectibles.KIND_PHOTO)[0])
	assert_int(visuals.flash_count()).is_equal(0)
	assert_bool(visuals.is_processing()).is_false()
	assert_that(visuals.gate_transforms()).is_equal(before)
	assert_int(visuals.gate_count()).is_equal(_trap_ids(placed).size())
	for collectible_id: String in visuals.gate_ids():
		assert_bool(visuals.is_claimed(collectible_id)).is_false()

# ---------------------------------------------------------------------------
# SCENE: rebuild / load path.
# ---------------------------------------------------------------------------

## The rebuild-on-ready path: a save that already banked three traps shows no
## gate standing for them, and every trap still live is untouched.
func test_rebuild_omits_gates_claimed_in_the_save() -> void:
	var claimed := _seed_claimed_traps(3)
	var visuals := _booted(_make_pair())
	var all_traps := _trap_ids(Collectibles.place_data(_defs()))
	assert_int(visuals.gate_count()).is_equal(all_traps.size() - claimed.size())
	for collectible_id: String in claimed:
		assert_bool(visuals.is_claimed(collectible_id)).is_true()
		assert_bool(visuals.has_gate(collectible_id)).is_false()
		assert_that(visuals.gate_look(collectible_id)).is_equal("")
	for collectible_id: String in all_traps.slice(3, 6):
		assert_bool(visuals.is_claimed(collectible_id)).is_false()
		assert_bool(visuals.has_gate(collectible_id)).is_true()
		assert_that(visuals.gate_look(collectible_id)).is_equal("active")

## keep_claimed_gates: the same pre-claimed save instead shows the banked traps
## standing in their dimmed claimed look -- identical geometry, different look,
## and no flash (the claim happened in an earlier session).
func test_keep_claimed_gates_builds_them_in_the_claimed_look() -> void:
	var claimed := _seed_claimed_traps(2)
	var visuals := _make_pair()
	visuals.keep_claimed_gates = true
	visuals.rebuild()
	var all_traps := _trap_ids(Collectibles.place_data(_defs()))
	assert_int(visuals.gate_count()).is_equal(all_traps.size())
	assert_int(visuals.flash_count()).is_equal(0)
	var live_id := all_traps[all_traps.size() - 1]
	for collectible_id: String in claimed:
		assert_bool(visuals.is_claimed(collectible_id)).is_true()
		assert_bool(visuals.has_gate(collectible_id)).is_true()
		assert_that(visuals.gate_look(collectible_id)).is_equal("claimed")
		# Same built geometry as a live gate of the same road, only a new look.
		assert_int(visuals.gate_triangle_count(collectible_id)).is_equal(
			visuals.gate_triangle_count(live_id))
	assert_that(visuals.gate_look(live_id)).is_equal("active")

## Rebuild is idempotent: re-running it never stacks duplicate gates, and a claim
## survives the resync (the banked trap leaves the world for good).
func test_rebuild_is_idempotent_and_preserves_the_claimed_look() -> void:
	var visuals := _booted(_make_pair())
	var field := _field_of(visuals)
	var trap_id := _trap_ids(field.placed())[0]
	var first := visuals.gate_transforms()
	visuals.rebuild()
	assert_that(visuals.gate_transforms()).is_equal(first)
	assert_int(visuals.get_child_count()).is_equal(visuals.gate_count())
	assert_int(visuals.get_child_count()).is_equal(8)

	_claim(field, trap_id)
	visuals.tick(SpeedTrapVisuals.FLASH_SECONDS + 0.01)
	visuals.rebuild()
	assert_bool(visuals.is_claimed(trap_id)).is_true()
	assert_bool(visuals.has_gate(trap_id)).is_false()
	assert_int(visuals.get_child_count()).is_equal(visuals.gate_count())
	assert_int(visuals.gate_count()).is_equal(7)
	# The surviving gates did not move.
	assert_array(visuals.gate_ids()).contains_exactly(_trap_ids(field.placed()).slice(1, 8))

## Determinism: two builds from the same published data produce the same gate
## count, ids and transforms.
func test_two_builds_from_the_same_data_are_identical() -> void:
	var first := _booted(_make_pair())
	var first_transforms := first.gate_transforms()
	var second := _booted(_make_pair())
	assert_int(second.gate_count()).is_equal(first.gate_count())
	assert_array(second.gate_ids()).contains_exactly(first.gate_ids())
	assert_that(second.gate_transforms()).is_equal(first_transforms)

## Cost discipline: the node builds once and then idles -- processing off with no
## flash, no physics body anywhere, and the only tick a plain idle node ever
## costs is a single early-out.
func test_node_is_idle_and_physics_free() -> void:
	var visuals := _make_pair()
	# _ready defers the build to the next frame; until then it is armed.
	assert_bool(visuals.is_processing()).is_true()
	assert_bool(visuals.is_booted()).is_false()
	visuals.rebuild()
	assert_bool(visuals.is_booted()).is_true()
	assert_bool(visuals.is_processing()).is_false()
	assert_bool(visuals.tick(1.0)).is_false()
	assert_int(visuals.flash_count()).is_equal(0)
	assert_int(_physics_nodes_in(visuals)).is_equal(0)
	assert_bool(visuals.is_physics_processing()).is_false()
