# tests/test_prop_scatterer.gd
extends GdUnitTestSuite

## Unit tests for the generic PropScatterer: road exclusion, flat-ground
## fallback without a height provider, and deterministic bounded placement.
## Headless-safe: meshes are built synchronously from primitives with no
## scene tree, no input, and no physics step required.

const ROAD_START := Vector3(-200.0, 0.0, -200.0)
const ROAD_END := Vector3(200.0, 0.0, 200.0)
const ROAD_THRESHOLD := 6.0

func test_road_exclusion_keeps_all_instances_off_road() -> void:
	var roads := auto_free(RoadNetwork.new()) as RoadNetwork
	roads.add_road(_synthetic_road(9), 12.0)
	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
	scatterer.road_network = roads
	scatterer.configure({
		"radius": 200.0,
		"inner_clear_radius": 0.0,
		"seed": 90210,
		"road_threshold": ROAD_THRESHOLD,
		"placement_attempts": 64,
		"props": {
			"rock": {"count": 30, "min_spacing": 8.0, "scale": Vector2(0.7, 1.8)},
		},
	})
	scatterer.generate()
	var placed := scatterer.get_instance_transforms("rock")
	assert_that(placed.size()).is_greater(0)
	assert_that(placed.size()).is_less_equal(30)
	assert_that(scatterer.get_instance_count()).is_less_equal(30)
	for i in placed.size():
		assert_that(roads.is_on_road(placed[i], ROAD_THRESHOLD)).is_false()

func test_props_fall_back_to_flat_ground_without_provider() -> void:
	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
	scatterer.configure({
		"radius": 100.0,
		"inner_clear_radius": 0.0,
		"seed": 7,
		"props": {"tent": {"count": 10, "min_spacing": 12.0}},
	})
	scatterer.generate()
	var placed := scatterer.get_instance_transforms("tent")
	assert_that(placed.size()).is_greater(0)
	assert_that(placed.size()).is_less_equal(10)
	for i in placed.size():
		assert_that(placed[i].y).is_greater(-0.001)
		assert_that(placed[i].y).is_less(0.001)
	assert_that(scatterer.get_child_count()).is_greater(0)

func test_same_seed_duplicates_identical_placement() -> void:
	var preset := {
		"radius": 80.0,
		"inner_clear_radius": 10.0,
		"seed": 4242,
		"props": {
			"rock": {"count": 12, "min_spacing": 9.0},
			"power_pole": {"count": 3, "min_spacing": 30.0},
		},
	}
	var first := auto_free(PropScatterer.new()) as PropScatterer
	first.configure(preset)
	first.generate()
	var second := auto_free(PropScatterer.new()) as PropScatterer
	second.configure(preset)
	second.generate()
	assert_that(second.get_instance_count()).is_less_equal(15)
	assert_that(first.get_instance_count()).is_equal(second.get_instance_count())
	var a := first.get_instance_transforms("rock")
	var b := second.get_instance_transforms("rock")
	assert_that(a.size()).is_equal(b.size())
	for i in a.size():
		assert_that(a[i].distance_to(b[i])).is_less(0.001)

func _synthetic_road(point_count: int) -> Array[Vector3]:
	var road: Array[Vector3] = []
	var count := maxi(point_count, 2)
	for i in count:
		var t := float(i) / float(count - 1)
		road.append(ROAD_START.lerp(ROAD_END, t))
	return road