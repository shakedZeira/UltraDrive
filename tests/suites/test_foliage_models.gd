extends GdUnitTestSuite

func test_all_tree_variants_load_as_real_10m_meshes() -> void:
	var foliage := auto_free(Foliage.new()) as Foliage
	assert_that(foliage).is_not_null()
	assert_that(Foliage.TREE_MODELS.size()).is_greater_equal(2)
	assert_that(Foliage.TREE_MODELS.size()).is_less_equal(4)
	var vertex_counts: Array[int] = []
	for index in Foliage.TREE_MODELS.size():
		var path := String(Foliage.TREE_MODELS[index])
		assert_that(FileAccess.file_exists(path)).is_true()
		var packed := load(path) as PackedScene
		assert_that(packed).is_not_null()
		var mesh := foliage._build_tree_mesh(path)
		assert_that(mesh).is_not_null()
		if mesh == null:
			continue
		assert_that(mesh.get_surface_count()).is_greater(0)
		var arrays := mesh.surface_get_arrays(0)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
		assert_that(vertices.size()).is_greater(100)
		assert_that(uvs.size()).is_equal(vertices.size())
		vertex_counts.append(vertices.size())
		var bounds: AABB = mesh.get_aabb()
		assert_that(bounds.size.y).is_equal_approx(10.0, 0.1)
		assert_that(bounds.position.y).is_equal_approx(0.0, 0.1)
		var min_height := 1.0
		var max_height := 0.0
		for uv: Vector2 in uvs:
			min_height = minf(min_height, uv.y)
			max_height = maxf(max_height, uv.y)
		assert_that(min_height).is_less_equal(0.05)
		assert_that(max_height).is_greater_equal(0.95)
	assert_that(vertex_counts.size()).is_equal(Foliage.TREE_MODELS.size())
