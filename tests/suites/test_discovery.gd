# tests/suites/test_discovery.gd
extends GdUnitTestSuite

## P5 fog-of-war: WorldDiscovery visited-bit model, XZ segment math, snap
## projection, and the SaveManager persistence bridge (slot 0 is snapshotted
## before each run and restored afterwards so external saves stay untouched).

func _defs() -> Array[RoadDef]:
	# Open chain: 3 points -> 2 segments ((0,0,0)->(100,0,0)->(100,0,100)).
	# Closed chain: 4 points -> 4 segments; segment 3 wraps p3 -> p0.
	return [
		RoadDef.make(RoadDef.Tier.ARTERIAL, [
			Vector3(0.0, 0.0, 0.0),
			Vector3(100.0, 0.0, 0.0),
			Vector3(100.0, 0.0, 100.0),
		], "open", false),
		RoadDef.make(RoadDef.Tier.HIGHWAY, [
			Vector3(0.0, 0.0, 0.0),
			Vector3(10.0, 2.0, 0.0),
			Vector3(20.0, 2.0, 0.0),
			Vector3(30.0, 2.0, 0.0),
		], "ring", true),
	]

func test_fresh_state_and_mask_sizes() -> void:
	var defs := _defs()
	var discovery := WorldDiscovery.new()
	discovery.configure(defs)
	assert_that(discovery.visited_indices(0).is_empty()).is_true()
	# Open chain N=3 -> 2 segments; closed chain N=4 -> 4 segments.
	assert_that(discovery.segment_visited_mask(0).size()).is_equal(2)
	assert_that(discovery.segment_visited_mask(1).size()).is_equal(4)
	# Unknown road ids return an empty mask so the map draws all-visited.
	assert_that(discovery.segment_visited_mask(999).is_empty()).is_true()
	discovery.free()

func test_reveal_marks_only_segments_within_radius() -> void:
	var defs := _defs()
	var discovery := WorldDiscovery.new()
	discovery.configure(defs)
	discovery.reveal_at_radius(Vector3(50.0, 0.0, 0.0), 1.0)
	# Only the open chain's seg0 passes through (50,0,0); everything else is
	# 20+ metres away.
	assert_that(discovery.visited_indices(0)).is_equal([0])
	assert_that(discovery.visited_indices(1).is_empty()).is_true()
	discovery.free()

func test_closed_chain_wrap_segment_and_monotonic_reveal() -> void:
	var defs := _defs()
	var discovery := WorldDiscovery.new()
	discovery.configure(defs)
	# A radius-30 disc at the ring's centre covers all four segments,
	# including the wrapping seg3 (p3 -> p0).
	discovery.reveal_at_radius(Vector3(15.0, 0.0, 0.0), 30.0)
	assert_that(discovery.visited_indices(1)).is_equal([0, 1, 2, 3])
	# Reveal is monotonic: repeats and far-away reveals never clear bits.
	discovery.reveal_at_radius(Vector3(15.0, 0.0, 0.0), 30.0)
	discovery.reveal_at_radius(Vector3(200.0, 0.0, 300.0), 1.0)
	assert_that(discovery.visited_indices(1)).is_equal([0, 1, 2, 3])
	discovery.free()

func test_is_revealed_respects_distance_threshold() -> void:
	var defs := _defs()
	var discovery := WorldDiscovery.new()
	discovery.configure(defs)
	discovery.reveal_at_radius(Vector3(0.0, 0.0, 0.0), 1.0)
	# Origin sits exactly on the visited open-chain seg0.
	assert_that(discovery.is_revealed(Vector3(0.0, 0.0, 0.0))).is_true()
	# (50,0,0) sits ON visited seg0 too: revealed even at a hairline threshold.
	assert_that(discovery.is_revealed(Vector3(50.0, 0.0, 0.0), 0.5)).is_true()
	# (150,0,0) is 50m past visited seg0's end: inside the wide threshold but
	# beyond the tight one.
	assert_that(discovery.is_revealed(Vector3(150.0, 0.0, 0.0), 100.0)).is_true()
	assert_that(discovery.is_revealed(Vector3(150.0, 0.0, 0.0), 10.0)).is_false()
	# (100,0,50) sits ON the open-chain seg1 (unvisited): never revealed.
	assert_that(discovery.is_revealed(Vector3(100.0, 0.0, 50.0), 100.0)).is_false()
	discovery.free()

func test_snap_projects_onto_revealed_segment_and_lerps_y() -> void:
	var defs: Array[RoadDef] = [
		RoadDef.make(RoadDef.Tier.ARTERIAL, [
			Vector3(0.0, 10.0, 0.0),
			Vector3(100.0, 20.0, 0.0),
			Vector3(100.0, 30.0, 100.0),
		], "slope", false),
	]
	var discovery := WorldDiscovery.new()
	discovery.configure(defs)
	discovery.reveal_at_radius(Vector3(50.0, 0.0, 0.0), 1.0)
	# Projection lands on seg0 with Y lerped: t=0.1 -> Y = 10 + 0.1*10 = 11.
	var snapped := discovery.try_snap_to_revealed(Vector3(10.0, 0.0, 0.0))
	assert_that(snapped).is_equal_approx(Vector3(10.0, 11.0, 0.0), Vector3(0.01, 0.01, 0.01))
	# No revealed segment within the threshold: sentinel.
	var snapped_far := discovery.try_snap_to_revealed_distance(Vector3(0.0, 0.0, 500.0), 50.0)
	assert_that(snapped_far == Vector3.INF).is_true()
	discovery.free()

func test_segment_math_is_xz_plane_only() -> void:
	# Y is ignored for distance but a point beyond the segment end clamps.
	assert_float(WorldDiscovery.point_segment_distance_xz(
		Vector3(0.0, 999.0, 0.0), Vector3(0, 0, 0), Vector3(100, 0, 0))).is_equal_approx(0.0, 0.0001)
	var clamped := WorldDiscovery.closest_point_on_segment(
		Vector3(200.0, 0.0, 0.0), Vector3(0, 0, 0), Vector3(100, 0, 0))
	assert_that(clamped).is_equal_approx(Vector3(100.0, 0.0, 0.0), Vector3(0.001, 0.001, 0.001))

func test_store_restore_round_trip_and_sanitization() -> void:
	var defs := _defs()
	var discovery := WorldDiscovery.new()
	discovery.configure(defs)
	discovery.reveal_at_radius(Vector3(0.0, 0.0, 0.0), 1.0)
	var saved := discovery.store()
	assert_that(saved.has(WorldDiscovery.SAVE_KEY)).is_true()

	var restored := WorldDiscovery.new()
	restored.configure(defs)
	restored.restore(saved)
	# Open-chain seg0 (0,0,0)->(100,0,0) plus the ring's seg0 (0->10) and the
	# wrapping seg3 (30->0) all touch the origin, so all three serialize and
	# merge back in.
	assert_that(restored.visited_indices(0)).is_equal([0])
	assert_that(restored.visited_indices(1)).is_equal([0, 3])
	restored.free()

	# Sanitization: unknown roads and out-of-range indices are dropped.
	var junk := {WorldDiscovery.SAVE_KEY: {"999": [0], "0": [1, 999, -2], "1": [3]}}
	var mercy := WorldDiscovery.new()
	mercy.configure(defs)
	mercy.restore(junk)
	assert_that(mercy.visited_indices(0)).is_equal([1])
	assert_that(mercy.visited_indices(1)).is_equal([3])
	mercy.free()
	discovery.free()

func test_revealed_points_for_returns_visited_anchors() -> void:
	var defs := _defs()
	var discovery := WorldDiscovery.new()
	discovery.configure(defs)
	discovery.reveal_at_radius(Vector3(0.0, 0.0, 0.0), 1.0)
	# Open chain: only seg0 visited -> the two endpoints of that segment.
	var open_pts := discovery.revealed_points_for(defs[0])
	assert_that(open_pts.size()).is_equal(2)
	assert_that(open_pts[0]).is_equal(Vector3(0.0, 0.0, 0.0))
	assert_that(open_pts[1]).is_equal(Vector3(100.0, 0.0, 0.0))
	# A RoadDef not registered with this instance -> empty.
	var ghost := RoadDef.make(RoadDef.Tier.DIRT, [Vector3(0, 0, 0)], "ghost", false)
	assert_that(discovery.revealed_points_for(ghost).is_empty()).is_true()
	discovery.free()

func test_save_slot_round_trip_is_hermetic() -> void:
	var slot := 0
	var snapshot: Dictionary = SaveManager.load_game(slot)

	var defs := _defs()
	var discovery := WorldDiscovery.new()
	discovery.configure(defs)
	discovery.reveal_at_radius(Vector3(0.0, 0.0, 0.0), 1.0)
	assert_that(discovery.save_to_slot(slot)).is_true()

	var after: Dictionary = SaveManager.load_game(slot)
	assert_that(after.has(WorldDiscovery.SAVE_KEY)).is_true()

	var reloaded := WorldDiscovery.new()
	reloaded.configure(_defs())
	assert_that(reloaded.load_from_slot(slot)).is_true()
	assert_that(reloaded.visited_indices(0)).is_equal([0])
	assert_that(reloaded.visited_indices(1)).is_equal([0, 3])
	reloaded.free()
	discovery.free()

	# Restore the slot exactly as it was.
	var path = SaveManager.SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
	if snapshot.is_empty() and not SaveManager.has_save(slot):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		SaveManager.save_game(slot, snapshot)