# tests/test_dressing_road_clearance.gd
extends GdUnitTestSuite

## Locks in the shared road-clearance contract for every dressing spawner
## (PropScatterer static helpers + Foliage): segment-aware half-width + margin
## rejection, world-space placement for offset scatterers, preserved instance
## counts, and bit-identical placement for a given seed. Headless-safe: no scene
## processing, no physics, synchronous MultiMesh generation.

const MARGIN := 3.0

func test_world_offset_scatterer_keeps_props_off_road() -> void:
	var roads := auto_free(_straight_road(12.0)) as RoadNetwork
	var scatterer := auto_free(PropScatterer.new()) as PropScatterer
	scatterer.road_network = roads
	scatterer.configure({
		"radius": 200.0,
		"inner_clear_radius": 0.0,
		"seed": 90210,
		"road_threshold": 6.0,
		"placement_attempts": 64,
		"props": {
			"rock": {"count": 30, "min_spacing": 8.0},
		},
	})
	scatterer.position = Vector3(128.0, 0.0, 128.0)
	add_child(scatterer)
	scatterer.generate()
	var placed := scatterer.get_instance_transforms("rock")
	assert_that(placed.size()).is_greater(0)
	assert_that(placed.size()).is_less_equal(30)
	for p in placed:
		var world: Vector3 = scatterer.to_global(p)
		assert_that(PropScatterer.is_clear_of_road(world, roads, 6.0)).is_true()

func test_road_clearance_is_segment_aware_and_width_aware() -> void:
	var roads := auto_free(_straight_road(20.0)) as RoadNetwork
	assert_that(roads.is_on_road(Vector3(0.0, 0.0, 0.0), 6.0)).is_false()
	assert_that(PropScatterer.is_clear_of_road(Vector3(0.0, 0.0, 0.0), roads)).is_false()
	assert_that(PropScatterer.is_clear_of_road(Vector3(0.0, 0.0, 11.0), roads)).is_false()
	assert_that(PropScatterer.is_clear_of_road(Vector3(0.0, 0.0, 13.0), roads)).is_true()
	assert_that(PropScatterer.is_clear_of_road(Vector3(0.0, 0.0, 20.0), roads, 25.0)).is_false()
	assert_that(PropScatterer.is_clear_of_road(Vector3(0.0, 0.0, 14.0), roads, 25.0)).is_false()
	assert_that(PropScatterer.is_clear_of_road(Vector3(200.0, 0.0, 14.0), roads)).is_true()
	assert_that(PropScatterer.is_clear_of_road(Vector3(200.0, 0.0, 12.0), roads)).is_false()
	assert_that(PropScatterer.is_clear_of_road(Vector3(310.0, 0.0, 12.0), roads)).is_true()
	assert_that(PropScatterer.is_clear_of_road(Vector3.ZERO, null)).is_true()

func test_foliage_keeps_trees_off_road_and_preserves_counts() -> void:
	var roads := auto_free(_straight_road(12.0)) as RoadNetwork
	var foliage := auto_free(Foliage.new()) as Foliage
	foliage.seed = 777
	foliage.road_network = roads
	add_child(foliage)
	foliage.generate()
	assert_that(foliage.get_instance_count()).is_equal(700 + 40)
	var margin := 6.0 + MARGIN
	for p: Vector3 in foliage.get_batch_positions("TreesMMI"):
		assert_that(absf(p.z)).is_greater_equal(margin - 0.001)
	for p: Vector3 in foliage.get_batch_positions("GrassMMI"):
		assert_that(absf(p.z)).is_greater_equal(6.0 - 0.001)

## P1 gate: the tree batches must draw the imported CC0 GLB meshes (merged,
## thousands of vertices), never the old fused primitives, and every tree
## variant must exist with the full 40-instance budget up front.
func test_foliage_uses_imported_tree_meshes() -> void:
	var foliage := auto_free(Foliage.new()) as Foliage
	foliage.seed = 100
	add_child(foliage)
	foliage.generate()
	assert_that(Foliage.TREE_MODELS.size()).is_equal(3)
	var tree_positions := foliage.get_batch_positions("TreesMMI")
	assert_that(tree_positions.size()).is_equal(40)
	assert_that(foliage.get_tree_mesh()).is_not_null()
	var arrays := foliage.get_tree_mesh().surface_get_arrays(0)
	var tree_verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_that(tree_verts).is_greater(200)
	assert_that(foliage.get_node_or_null("TreesMMI_B")).is_not_null()
	assert_that(foliage.get_node_or_null("TreesMMI_C")).is_not_null()

func test_foliage_road_placement_is_deterministic() -> void:
	var roads := auto_free(_straight_road(12.0)) as RoadNetwork
	var a := auto_free(Foliage.new()) as Foliage
	a.seed = 42
	a.road_network = roads
	add_child(a)
	a.generate()
	var b := auto_free(Foliage.new()) as Foliage
	b.seed = 42
	b.road_network = roads
	add_child(b)
	b.generate()
	assert_that(a.get_instance_positions() == b.get_instance_positions()).is_true()
	var free := auto_free(Foliage.new()) as Foliage
	free.seed = 42
	add_child(free)
	free.generate()
	var occupied_in_band := false
	for p in free.get_instance_positions():
		if absf(p.z) < 6.0 + MARGIN:
			occupied_in_band = true
			break
	assert_that(occupied_in_band).is_true()

func _straight_road(width: float) -> RoadNetwork:
	var roads := RoadNetwork.new()
	roads.add_road([Vector3(-300.0, 0.0, 0.0), Vector3(300.0, 0.0, 0.0)], width, false)
	return roads