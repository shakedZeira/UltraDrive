# tests/suites/test_road_graph.gd
extends GdUnitTestSuite

## P0 open-world road-plan gate: RoadDef data tables, RoadGraph topology and
## hop routing, RoadNetwork integration, the real 3-road bootstrap
## connectivity contract and TrackBuilder tier/material/banking rendering.

const OPEN_WORLD_SCENE := "res://scenes/world/open_world_root.tscn"
const LINK_THRESHOLD := 15.0

var _managed: Array[Node] = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()

func _track(node: Node) -> void:
	_managed.append(node)

func _square_points() -> Array[Vector3]:
	return [
		Vector3(0, 0, 0),
		Vector3(100, 0, 0),
		Vector3(100, 0, 100),
		Vector3(0, 0, 100),
	]

func _first_surface_vertices(builder: TrackBuilder) -> PackedVector3Array:
	var mesh_instance := builder.get_child(0) as MeshInstance3D
	if mesh_instance == null:
		return PackedVector3Array()
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return PackedVector3Array()
	var arrays := mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]

func _surface_material(builder: TrackBuilder) -> StandardMaterial3D:
	var mesh_instance := builder.get_child(0) as MeshInstance3D
	if mesh_instance == null:
		return null
	return mesh_instance.material_override as StandardMaterial3D

func _edge_materials(builder: TrackBuilder) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for i in [1, 2]:
		var instance := builder.get_child(i) as MeshInstance3D
		if instance == null:
			continue
		out.append(instance.material_override as StandardMaterial3D)
	return out

func test_road_def_tier_defaults_and_names() -> void:
	var tiers: Array[int] = [RoadDef.Tier.HIGHWAY, RoadDef.Tier.ARTERIAL, RoadDef.Tier.TOUGE, RoadDef.Tier.COASTAL, RoadDef.Tier.DIRT]
	var widths: Array[float] = [16.0, 10.0, 9.0, 9.0, 7.0]
	var names: Array[String] = ["Highway", "Arterial", "Touge", "Coastal", "Dirt"]
	for i in tiers.size():
		var tier := tiers[i]
		assert_float(RoadDef.default_width(tier)).is_equal_approx(widths[i], 0.001)
		assert_that(RoadDef.tier_name(tier)).is_equal(names[i])
		if tier == RoadDef.Tier.DIRT:
			assert_that(RoadDef.default_surface(tier)).is_equal(RoadDef.Surface.GRAVEL)
		else:
			assert_that(RoadDef.default_surface(tier)).is_equal(RoadDef.Surface.ASPHALT)
	assert_float(RoadDef.default_width(99)).is_equal_approx(10.0, 0.001)
	assert_that(RoadDef.tier_name(99)).is_equal("Arterial")

func test_road_def_surface_names() -> void:
	var surfaces: Array[int] = [RoadDef.Surface.ASPHALT, RoadDef.Surface.CONCRETE, RoadDef.Surface.GRAVEL, RoadDef.Surface.SNOW]
	var names: Array[String] = ["Asphalt", "Concrete", "Gravel", "Snow"]
	for i in surfaces.size():
		assert_that(RoadDef.surface_name(surfaces[i])).is_equal(names[i])
	assert_that(RoadDef.surface_name(99)).is_equal("Asphalt")

func test_road_def_make_applies_tier_defaults_and_overrides() -> void:
	var pts: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(200, 0, 0)]
	var dirt := RoadDef.make(RoadDef.Tier.DIRT, pts)
	assert_that(dirt.tier).is_equal(RoadDef.Tier.DIRT)
	assert_float(dirt.width).is_equal_approx(7.0, 0.001)
	assert_that(dirt.surface).is_equal(RoadDef.Surface.GRAVEL)
	assert_that(dirt.closed).is_true()
	assert_that(dirt.id).is_equal("")

	var highway := RoadDef.make(RoadDef.Tier.HIGHWAY, pts, "hw-1", false, 22.5, RoadDef.Surface.SNOW)
	assert_that(highway.id).is_equal("hw-1")
	assert_that(highway.closed).is_false()
	assert_float(highway.width).is_equal_approx(22.5, 0.001)
	assert_that(highway.surface).is_equal(RoadDef.Surface.SNOW)

	# Non-positive width override falls back to the tier default.
	var arterial := RoadDef.make(RoadDef.Tier.ARTERIAL, pts, "", true, 0.0, -1)
	assert_float(arterial.width).is_equal_approx(10.0, 0.001)
	assert_that(arterial.surface).is_equal(RoadDef.Surface.ASPHALT)

func test_build_topology_shared_endpoint_joins_two_chains() -> void:
	var chain_a: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(100, 0, 100)]
	var chain_b: Array[Vector3] = [Vector3(100, 0, 100), Vector3(100, 0, 200)]
	var defs: Array[RoadDef] = [
		RoadDef.make(RoadDef.Tier.ARTERIAL, chain_a),
		RoadDef.make(RoadDef.Tier.ARTERIAL, chain_b),
	]
	var top := RoadGraph.build_topology(defs, LINK_THRESHOLD)
	var adj: Dictionary = top["adjacency"]
	assert_that(adj.size()).is_equal(2)
	assert_that(adj[0]).is_equal(PackedInt32Array([1]))
	assert_that(adj[1]).is_equal(PackedInt32Array([0]))
	var junctions: Array = top["junctions"]
	assert_that(junctions.size()).is_equal(1)
	var j: Dictionary = junctions[0]
	assert_that(j["road_a"]).is_equal(0)
	assert_that(j["road_b"]).is_equal(1)
	assert_float(j["dist"]).is_equal_approx(0.0, 0.001)
	assert_that(j["point"]).is_equal_approx(Vector3(100, 0, 100), Vector3(0.001, 0.001, 0.001))

func test_build_topology_skips_pair_beyond_threshold() -> void:
	var chain_a: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0)]
	var chain_b: Array[Vector3] = [Vector3(100, 0, 15.5), Vector3(200, 0, 15.5)]
	var defs: Array[RoadDef] = [
		RoadDef.make(RoadDef.Tier.ARTERIAL, chain_a),
		RoadDef.make(RoadDef.Tier.ARTERIAL, chain_b),
	]
	var top := RoadGraph.build_topology(defs, LINK_THRESHOLD)
	var adj: Dictionary = top["adjacency"]
	assert_that(adj[0].size()).is_equal(0)
	assert_that(adj[1].size()).is_equal(0)
	assert_that(top["junctions"]).is_empty()

func test_build_topology_single_closed_chain_has_no_self_link() -> void:
	var defs: Array[RoadDef] = [RoadDef.make(RoadDef.Tier.COASTAL, _square_points())]
	var top := RoadGraph.build_topology(defs, LINK_THRESHOLD)
	var adj: Dictionary = top["adjacency"]
	assert_that(adj.size()).is_equal(1)
	assert_that(adj[0]).is_empty()
	assert_that(top["junctions"]).is_empty()

func test_build_topology_deterministic_across_runs() -> void:
	var chain_a: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0)]
	var chain_b: Array[Vector3] = [Vector3(100, 0, 0), Vector3(180, 0, 0)]
	var chain_c: Array[Vector3] = [Vector3(500, 0, 0), Vector3(600, 0, 0)]
	var defs: Array[RoadDef] = [
		RoadDef.make(RoadDef.Tier.ARTERIAL, chain_a),
		RoadDef.make(RoadDef.Tier.DIRT, chain_b),
		RoadDef.make(RoadDef.Tier.COASTAL, chain_c),
	]
	var first := RoadGraph.build_topology(defs, LINK_THRESHOLD)
	var second := RoadGraph.build_topology(defs, LINK_THRESHOLD)
	assert_that(first).is_equal(second)
	assert_that(first["adjacency"]).is_equal({
		0: PackedInt32Array([1]),
		1: PackedInt32Array([0]),
		2: PackedInt32Array(),
	})

func test_route_chain_forward_and_reverse() -> void:
	var adj := {
		0: PackedInt32Array([1]),
		1: PackedInt32Array([0, 2]),
		2: PackedInt32Array([1]),
	}
	assert_that(RoadGraph.route(adj, 0, 2)).is_equal(PackedInt32Array([0, 1, 2]))
	assert_that(RoadGraph.route(adj, 2, 0)).is_equal(PackedInt32Array([2, 1, 0]))

func test_route_same_node_returns_singleton() -> void:
	var adj := {0: PackedInt32Array([1]), 1: PackedInt32Array([0])}
	assert_that(RoadGraph.route(adj, 1, 1)).is_equal(PackedInt32Array([1]))
	assert_that(RoadGraph.route(adj, 0, 0).size()).is_equal(1)

func test_route_disconnected_pair_is_empty() -> void:
	var adj := {
		0: PackedInt32Array([1]),
		1: PackedInt32Array([0]),
		2: PackedInt32Array(),
	}
	assert_that(RoadGraph.route(adj, 0, 2)).is_empty()
	assert_that(RoadGraph.route(adj, 2, 0)).is_empty()

func test_route_unknown_id_is_empty() -> void:
	var adj := {0: PackedInt32Array([1]), 1: PackedInt32Array([0])}
	assert_that(RoadGraph.route(adj, 0, 7)).is_empty()
	assert_that(RoadGraph.route(adj, 7, 0)).is_empty()
	assert_that(RoadGraph.route(adj, 7, 8)).is_empty()

func test_route_prefers_fewest_hops() -> void:
	var adj := {
		0: PackedInt32Array([1]),
		1: PackedInt32Array([0, 2, 3]),
		2: PackedInt32Array([1, 3]),
		3: PackedInt32Array([1, 2]),
	}
	assert_that(RoadGraph.route(adj, 0, 3)).is_equal(PackedInt32Array([0, 1, 3]))

func test_chain_distance_matches_segment_distance() -> void:
	var a: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0)]
	var b: Array[Vector3] = [Vector3(100, 0, 0), Vector3(200, 0, 0)]
	assert_float(RoadGraph.chain_distance(a, b)).is_equal_approx(0.0, 0.001)
	var gap: Array[Vector3] = [Vector3(100, 0, 12.0), Vector3(300, 0, 12.0)]
	assert_float(RoadGraph.chain_distance(a, gap)).is_equal_approx(12.0, 0.001)
	var empty: Array[Vector3] = []
	assert_that(RoadGraph.chain_distance(a, empty)).is_equal(INF)

func test_network_add_road_returns_incrementing_indices() -> void:
	var network := RoadNetwork.new()
	add_child(network)
	_track(network)
	var first: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0)]
	var second: Array[Vector3] = [Vector3(100, 0, 0), Vector3(200, 0, 0)]
	var third: Array[Vector3] = [Vector3(500, 0, 0), Vector3(600, 0, 0)]
	assert_that(network.add_road(first)).is_equal(0)
	assert_that(network.add_road(second, 8.0, false)).is_equal(1)
	assert_that(network.add_road(third)).is_equal(2)
	assert_that(network.get_roads().size()).is_equal(3)

func test_network_add_road_before_in_tree_still_works() -> void:
	var network := RoadNetwork.new()
	var first: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0)]
	var second: Array[Vector3] = [Vector3(100, 0, 0), Vector3(200, 0, 0)]
	network.add_road(first)
	network.add_road(second, 8.0, false)
	assert_that(network.get_roads().size()).is_equal(2)
	add_child(network)
	_track(network)
	var adj := network.get_adjacency()
	assert_that(adj[0]).is_equal(PackedInt32Array([1]))
	assert_that(adj[1]).is_equal(PackedInt32Array([0]))

func test_network_add_road_def_auto_ids_and_roundtrip() -> void:
	var network := RoadNetwork.new()
	add_child(network)
	_track(network)
	var dirt_pts: Array[Vector3] = [Vector3(0, 0, 0), Vector3(200, 0, 0)]
	var dirt := RoadDef.make(RoadDef.Tier.DIRT, dirt_pts)
	assert_that(network.add_road_def(dirt)).is_equal(0)
	assert_that(dirt.id).is_equal("road_0")
	var named_pts: Array[Vector3] = [Vector3(0, 0, 0), Vector3(80, 0, 0)]
	var named := RoadDef.make(RoadDef.Tier.HIGHWAY, named_pts, "pass-road")
	assert_that(network.add_road_def(named)).is_equal(1)
	assert_that(named.id).is_equal("pass-road")
	var defs := network.get_road_defs()
	assert_that(defs.size()).is_equal(2)
	assert_that(defs[0].tier).is_equal(RoadDef.Tier.DIRT)
	assert_float(defs[0].width).is_equal_approx(7.0, 0.001)
	assert_that(defs[0].surface).is_equal(RoadDef.Surface.GRAVEL)
	assert_that(defs[1].tier).is_equal(RoadDef.Tier.HIGHWAY)
	assert_float(defs[1].width).is_equal_approx(16.0, 0.001)

func test_network_nearest_road_id_and_tiebreak() -> void:
	var network := RoadNetwork.new()
	add_child(network)
	_track(network)
	var first: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0)]
	var second: Array[Vector3] = [Vector3(0, 0, 0), Vector3(0, 0, 100)]
	network.add_road(first)
	network.add_road(second)
	# Distance tie at the shared origin resolves to the lowest road index.
	assert_that(network.nearest_road_id(Vector3(0, 0, 0))).is_equal(0)
	assert_that(network.nearest_road_id(Vector3(60, 0, 0))).is_equal(0)
	assert_that(network.nearest_road_id(Vector3(0, 0, 60))).is_equal(1)
	var empty := RoadNetwork.new()
	add_child(empty)
	_track(empty)
	assert_that(empty.nearest_road_id(Vector3(5, 0, 5))).is_equal(-1)

func test_network_topology_matches_hand_built_example() -> void:
	var network := RoadNetwork.new()
	add_child(network)
	_track(network)
	var first: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0)]
	var second: Array[Vector3] = [Vector3(100, 0, 0), Vector3(200, 0, 0)]
	var third: Array[Vector3] = [Vector3(400, 0, 0), Vector3(500, 0, 0)]
	network.add_road(first)
	network.add_road(second)
	network.add_road(third)
	var adj := network.get_adjacency()
	assert_that(adj.size()).is_equal(3)
	assert_that(adj[0]).is_equal(PackedInt32Array([1]))
	assert_that(adj[1]).is_equal(PackedInt32Array([0]))
	assert_that(adj[2]).is_empty()
	assert_that(network.neighbor_roads(0)).is_equal(PackedInt32Array([1]))
	assert_that(network.neighbor_roads(2)).is_empty()
	assert_that(network.neighbor_roads(42)).is_empty()
	assert_that(network.route(0, 1)).is_equal(PackedInt32Array([0, 1]))
	assert_that(network.route(0, 2)).is_empty()
	var junctions := network.get_junctions()
	assert_that(junctions.size()).is_equal(1)
	var j: Dictionary = junctions[0]
	assert_that(j["road_a"]).is_equal(0)
	assert_that(j["road_b"]).is_equal(1)
	assert_float(j["dist"]).is_equal_approx(0.0, 0.001)
	assert_that(j["point"]).is_equal_approx(Vector3(100, 0, 0), Vector3(0.001, 0.001, 0.001))

func test_open_world_bootstrap_connects_all_three_roads() -> void:
	var runner := scene_runner(OPEN_WORLD_SCENE)
	await runner.simulate_frames(1)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var network := scene.get_node_or_null("RoadNetwork") as RoadNetwork
	assert_that(network).is_not_null()
	if network == null:
		return
	var roads := network.get_roads()
	# The P2 classified network (CorridorPlanner.plan) emits 12 road defs; the
	# bootstrap core invariant is that defs 0..2 are hub ring / hub->pass
	# connector / pass loop, so the growth must never break that prefix.
	assert_that(roads.size()).is_greater_equal(3)
	var hub: Array[Vector3] = roads[0]
	# Hub ring point 0 doubles as the connector's first point.
	assert_that(hub[0]).is_equal_approx(Vector3(238.0, 2.2, 128.0), Vector3(0.001, 0.001, 0.001))
	var adj := network.get_adjacency()
	# Hub ring now also spawns the coast arterial, highway on-ramp and dirt
	# cut-throughs; the connector link (-1) must still be present.
	assert_that(adj[0].has(1)).is_true()
	assert_that(adj[1]).is_equal(PackedInt32Array([0, 2]))
	assert_that(adj[2]).is_equal(PackedInt32Array([1]))
	var junctions := network.get_junctions()
	var ring_junction: Dictionary = {}
	var pass_junction: Dictionary = {}
	for j in junctions:
		if int(j["road_a"]) == 0 and int(j["road_b"]) == 1:
			ring_junction = j
		elif int(j["road_a"]) == 1 and int(j["road_b"]) == 2:
			pass_junction = j
	assert_that(ring_junction.is_empty()).is_false()
	assert_that(pass_junction.is_empty()).is_false()
	assert_float(ring_junction["dist"]).is_equal_approx(0.0, 0.001)
	assert_float(pass_junction["dist"]).is_equal_approx(0.0, 0.001)
	assert_that(ring_junction["point"]).is_equal_approx(hub[0], Vector3(0.001, 0.001, 0.001))
	var pass_first: Vector3 = roads[2][0]
	assert_that(pass_junction["point"]).is_equal_approx(pass_first, Vector3(0.001, 0.001, 0.001))
	assert_that(network.route(0, 2)).is_equal(PackedInt32Array([0, 1, 2]))
	assert_that(network.route(2, 0)).is_equal(PackedInt32Array([2, 1, 0]))
	assert_that(network.neighbor_roads(1)).is_equal(PackedInt32Array([0, 2]))

func test_track_builder_default_asphalt_arterial_flat() -> void:
	var builder := TrackBuilder.new()
	add_child(builder)
	_track(builder)
	builder.build_track(_square_points())
	assert_that(builder.get_child_count()).is_equal(4)
	if builder.get_child_count() < 4:
		return
	var mesh_instances := 0
	var static_bodies := 0
	for child in builder.get_children():
		if child is MeshInstance3D:
			mesh_instances += 1
		elif child is StaticBody3D:
			static_bodies += 1
	assert_that(mesh_instances).is_equal(3)
	assert_that(static_bodies).is_equal(1)
	var body := builder.get_child(3) as StaticBody3D
	assert_that(body).is_not_null()
	if body == null:
		return
	assert_that(body.get_child_count()).is_equal(1)
	assert_that(body.get_child(0) is CollisionShape3D).is_true()
	var mat := _surface_material(builder)
	assert_that(mat).is_not_null()
	if mat == null:
		return
	assert_float(mat.albedo_color.r).is_equal_approx(0.16, 0.001)
	assert_float(mat.albedo_color.g).is_equal_approx(0.17, 0.001)
	assert_float(mat.albedo_color.b).is_equal_approx(0.19, 0.001)
	assert_float(mat.roughness).is_equal_approx(0.92, 0.001)
	var edges := _edge_materials(builder)
	assert_that(edges.size() >= 2).is_true()
	if edges.size() < 2:
		return
	assert_float(edges[0].albedo_color.r).is_equal_approx(0.82, 0.001)
	assert_float(edges[0].albedo_color.g).is_equal_approx(0.13, 0.001)
	assert_float(edges[0].albedo_color.b).is_equal_approx(0.13, 0.001)
	assert_float(edges[1].albedo_color.r).is_equal_approx(0.85, 0.001)
	assert_float(edges[1].albedo_color.g).is_equal_approx(0.85, 0.001)
	assert_float(edges[1].albedo_color.b).is_equal_approx(0.82, 0.001)
	# Default width is the builder's road_width (12.0): apex vertex pair spans it.
	var vertices: PackedVector3Array = _first_surface_vertices(builder)
	assert_that(vertices.size() >= 2).is_true()
	if vertices.size() < 2:
		return
	assert_float(vertices[0].distance_to(vertices[1])).is_equal_approx(12.0, 0.001)

func test_track_builder_dirt_surface_and_edge_colors() -> void:
	var builder := TrackBuilder.new()
	add_child(builder)
	_track(builder)
	var def := RoadDef.make(RoadDef.Tier.DIRT, _square_points())
	builder.build_track(_square_points(), true, def)
	assert_that(builder.get_child_count()).is_equal(4)
	if builder.get_child_count() < 4:
		return
	var mat := _surface_material(builder)
	assert_that(mat).is_not_null()
	if mat == null:
		return
	assert_float(mat.albedo_color.r).is_equal_approx(0.55, 0.001)
	assert_float(mat.albedo_color.g).is_equal_approx(0.48, 0.001)
	assert_float(mat.albedo_color.b).is_equal_approx(0.38, 0.001)
	assert_float(mat.roughness).is_equal_approx(0.95, 0.001)
	var edges := _edge_materials(builder)
	assert_that(edges.size() >= 2).is_true()
	if edges.size() < 2:
		return
	assert_float(edges[0].albedo_color.r).is_equal_approx(0.55, 0.001)
	assert_float(edges[0].albedo_color.g).is_equal_approx(0.40, 0.001)
	assert_float(edges[0].albedo_color.b).is_equal_approx(0.28, 0.001)
	assert_float(edges[1].albedo_color.r).is_equal_approx(0.60, 0.001)
	assert_float(edges[1].albedo_color.g).is_equal_approx(0.55, 0.001)
	assert_float(edges[1].albedo_color.b).is_equal_approx(0.48, 0.001)
	# DIRT width (7.0) overrides the builder road_width default (12.0).
	var vertices: PackedVector3Array = _first_surface_vertices(builder)
	assert_that(vertices.size() >= 2).is_true()
	if vertices.size() < 2:
		return
	assert_float(vertices[0].distance_to(vertices[1])).is_equal_approx(7.0, 0.001)

func test_track_builder_banking_lowers_right_edge_on_right_turn() -> void:
	var right_turn: Array[Vector3] = [
		Vector3(0, 0, 0),
		Vector3(100, 0, 0),
		Vector3(100, 0, 100),
	]
	var def := RoadDef.make(RoadDef.Tier.ARTERIAL, right_turn, "", false)
	def.banking = 0.4
	var banked := TrackBuilder.new()
	add_child(banked)
	_track(banked)
	banked.build_track(right_turn, false, def)
	assert_that(banked.get_child_count()).is_equal(4)
	if banked.get_child_count() < 4:
		return
	var apex_center := right_turn[1]
	var vertices: PackedVector3Array = _first_surface_vertices(banked)
	assert_that(vertices.size() >= 4).is_true()
	if vertices.size() < 4:
		return
	# Apex vertex pair for path point 1 lives at indices 2 and 3.
	var v_left: Vector3 = vertices[2]
	var v_right: Vector3 = vertices[3]
	var forward := (right_turn[2] - right_turn[0]).normalized()
	var right := forward.cross(Vector3.UP)
	assert_that((v_right - apex_center).dot(right)).is_greater(0.0)
	assert_that((v_left - apex_center).dot(right)).is_less(0.0)
	# Inside (right) edge of the right turn sits lower than the outside edge.
	assert_float(v_right.y).is_less(v_left.y)
	assert_float(v_right.y).is_equal_approx(-v_left.y, 0.001)
	assert_float(v_left.y).is_greater(0.01)

	var flat_def := RoadDef.make(RoadDef.Tier.ARTERIAL, right_turn, "", false)
	flat_def.banking = 0.0
	var flat := TrackBuilder.new()
	add_child(flat)
	_track(flat)
	flat.build_track(right_turn, false, flat_def)
	var flat_vertices: PackedVector3Array = _first_surface_vertices(flat)
	assert_float(flat_vertices[2].y).is_equal_approx(flat_vertices[3].y, 0.0001)