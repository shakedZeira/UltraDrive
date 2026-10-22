class_name LeMansTerrain
extends RefCounted

## Real-elevation ground for the Le Mans No-Chicane scene (replaces the flat v1
## PlaneMesh). One height field, three consumers -- the visual tiles, the
## HeightMapShape3D collider and `height_at()` (what the dressing, verge, skirt,
## foliage and traps stand on) -- so nothing can float or sink relative to
## another: `height_at()` interpolates on EXACTLY the triangles the tiles draw.
##
## Height = lerp(far field, road ground, w(d)):
##   * far field: the 100 m SRTM grid (`LeMansElevationData.GRID_M`, 3x3
##     smoothed to take SRTM canopy/roof bumps off), bilinear, minus the layout's
##     S/F datum, plus PLAIN_Y -- the real surrounding landscape;
##   * road ground: `LeMansLayout.ground_y_at_arc` of the nearest centerline
##     point (0.40 m under the road edge, the v1 relation, carried along the
##     real road profile);
##   * w = 1 inside CORRIDOR_FLAT_M of the centerline (verge, aprons, traps,
##     barriers stand on a cross-level shelf), smoothstep to 0 at
##     CORRIDOR_BLEND_M -- the road sits in a shallow cutting/embankment that
##     fades into the real terrain.
## Built once per process and cached (deterministic inputs, ~1-2 s of
## GDScript); every scene instance and test shares the arrays and meshes.

## Fine grid cell (m) of the visual mesh + collider.
const CELL_M := 16.0
## Tile edge in cells (culling granularity: 32 x 16 m = 512 m tiles).
const TILE_CELLS := 32
## Corridor shelf / blend-out half-widths from the centerline (m).
const CORRIDOR_FLAT_M := 30.0
const CORRIDOR_BLEND_M := 120.0
## Centerline subsampling for the corridor splat (every Nth point, ~5.7 m).
const SPLAT_STRIDE := 2

static var _ready := false
static var _origin := Vector2.ZERO
static var _nx := 0
static var _nz := 0
static var _h := PackedFloat32Array()
static var _tiles: Array[Dictionary] = []
static var _bake_ms := 0


## Bake (once) over a plane of `size` centred at `center` (world XZ).
static func ensure(center: Vector2, size: Vector2, road_points: Array[Vector3]) -> void:
	if _ready:
		return
	var t0 := Time.get_ticks_msec()
	_origin = center - size * 0.5
	_nx = int(roundf(size.x / CELL_M)) + 1
	_nz = int(roundf(size.y / CELL_M)) + 1
	var n := _nx * _nz
	_h = PackedFloat32Array()
	_h.resize(n)
	var datum := LeMansLayout.elevation_datum_asl()
	var far := _smoothed_dem()
	for iz in _nz:
		var z := _origin.y + float(iz) * CELL_M
		for ix in _nx:
			var x := _origin.x + float(ix) * CELL_M
			_h[iz * _nx + ix] = _dem_bilinear(far, x, z) - datum + LeMansLayout.PLAIN_Y
	_splat_corridor(road_points)
	_build_tiles()
	_ready = true
	_bake_ms = Time.get_ticks_msec() - t0


static func is_ready() -> bool:
	return _ready


static func bake_ms() -> int:
	return _bake_ms


static func grid_size() -> Vector2i:
	return Vector2i(_nx, _nz)


static func grid_origin() -> Vector2:
	return _origin


## Raw grid heights (row-major Z then X) for the HeightMapShape3D.
static func heights() -> PackedFloat32Array:
	return _h


## Visual tiles: Array of {"mesh": ArrayMesh, "aabb_center": Vector3}.
static func tiles() -> Array[Dictionary]:
	return _tiles


## Ground height at world XZ on the SAME triangles the tiles draw (each cell
## split along its (0,0)-(1,1) diagonal). Clamps to the grid edge.
static func height_at(x: float, z: float) -> float:
	var fx := clampf((x - _origin.x) / CELL_M, 0.0, float(_nx - 1) - 0.0001)
	var fz := clampf((z - _origin.y) / CELL_M, 0.0, float(_nz - 1) - 0.0001)
	var ix := int(fx)
	var iz := int(fz)
	var u := fx - float(ix)
	var v := fz - float(iz)
	var h00 := _h[iz * _nx + ix]
	var h10 := _h[iz * _nx + ix + 1]
	var h01 := _h[(iz + 1) * _nx + ix]
	var h11 := _h[(iz + 1) * _nx + ix + 1]
	if u >= v:
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h11 - h01) * u + (h01 - h00) * v


## 3x3 box-smoothed copy of the SRTM grid.
static func _smoothed_dem() -> PackedFloat32Array:
	var nx := LeMansElevationData.GRID_NX
	var nz := LeMansElevationData.GRID_NZ
	var src: Array[float] = LeMansElevationData.GRID_M
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var sum := 0.0
			var cnt := 0.0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var jx := clampi(ix + dx, 0, nx - 1)
					var jz := clampi(iz + dz, 0, nz - 1)
					sum += src[jz * nx + jx]
					cnt += 1.0
			out[iz * nx + ix] = sum / cnt
	return out


static func _dem_bilinear(dem: PackedFloat32Array, x: float, z: float) -> float:
	var nx := LeMansElevationData.GRID_NX
	var nz := LeMansElevationData.GRID_NZ
	var o := LeMansElevationData.GRID_ORIGIN
	var step := LeMansElevationData.GRID_STEP_M
	var fx := clampf((x - o.x) / step, 0.0, float(nx - 1) - 0.0001)
	var fz := clampf((z - o.y) / step, 0.0, float(nz - 1) - 0.0001)
	var ix := int(fx)
	var iz := int(fz)
	var u := fx - float(ix)
	var v := fz - float(iz)
	var a := lerpf(dem[iz * nx + ix], dem[iz * nx + ix + 1], u)
	var b := lerpf(dem[(iz + 1) * nx + ix], dem[(iz + 1) * nx + ix + 1], u)
	return lerpf(a, b, v)


## Pull every grid vertex near the road onto the road-ground profile: splat
## each (subsampled) centerline point into the vertices within
## CORRIDOR_BLEND_M, keep the nearest point's ground height, then blend.
static func _splat_corridor(road_points: Array[Vector3]) -> void:
	var n := _nx * _nz
	var best_d2 := PackedFloat32Array()
	best_d2.resize(n)
	best_d2.fill(INF)
	var best_g := PackedFloat32Array()
	best_g.resize(n)
	var reach := int(ceil(CORRIDOR_BLEND_M / CELL_M))
	var r2 := CORRIDOR_BLEND_M * CORRIDOR_BLEND_M
	var spacing := LeMansLayout.spacing()
	for i in range(0, road_points.size(), SPLAT_STRIDE):
		var p := road_points[i]
		var g := LeMansLayout.ground_y_at_arc(float(i) * spacing)
		var cx := int(roundf((p.x - _origin.x) / CELL_M))
		var cz := int(roundf((p.z - _origin.y) / CELL_M))
		for iz in range(maxi(cz - reach, 0), mini(cz + reach, _nz - 1) + 1):
			var dz := _origin.y + float(iz) * CELL_M - p.z
			var row := iz * _nx
			for ix in range(maxi(cx - reach, 0), mini(cx + reach, _nx - 1) + 1):
				var dx := _origin.x + float(ix) * CELL_M - p.x
				var d2 := dx * dx + dz * dz
				if d2 < r2 and d2 < best_d2[row + ix]:
					best_d2[row + ix] = d2
					best_g[row + ix] = g
	for k in n:
		if best_d2[k] == INF:
			continue
		var d := sqrt(best_d2[k])
		var w := 1.0 - smoothstep(CORRIDOR_FLAT_M, CORRIDOR_BLEND_M, d)
		_h[k] = lerpf(_h[k], best_g[k], w)


## One ArrayMesh per TILE_CELLS x TILE_CELLS block (shared edge vertices with
## the neighbours, so there are no cracks), normals from central differences,
## front faces up, the same diagonal `height_at()` uses.
static func _build_tiles() -> void:
	_tiles = []
	var tz := 0
	while tz < _nz - 1:
		var tx := 0
		var tz1 := mini(tz + TILE_CELLS, _nz - 1)
		while tx < _nx - 1:
			var tx1 := mini(tx + TILE_CELLS, _nx - 1)
			_tiles.append(_build_tile(tx, tz, tx1, tz1))
			tx = tx1
		tz = tz1


static func _build_tile(x0: int, z0: int, x1: int, z1: int) -> Dictionary:
	var w := x1 - x0 + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			verts.append(Vector3(_origin.x + float(ix) * CELL_M, _h[iz * _nx + ix],
				_origin.y + float(iz) * CELL_M))
			var hl := _h[iz * _nx + maxi(ix - 1, 0)]
			var hr := _h[iz * _nx + mini(ix + 1, _nx - 1)]
			var hd := _h[maxi(iz - 1, 0) * _nx + ix]
			var hu := _h[mini(iz + 1, _nz - 1) * _nx + ix]
			normals.append(Vector3(hl - hr, 2.0 * CELL_M, hd - hu).normalized())
	for iz in z1 - z0:
		for ix in x1 - x0:
			var a := iz * w + ix          # (ix, iz)
			var b := a + 1                # (ix+1, iz)
			var c := a + w                # (ix, iz+1)
			var d := c + 1                # (ix+1, iz+1)
			# Diagonal a-d, matching height_at(): triangles (a, b, d) and (a, d, c).
			# Both have a -Y right-hand normal, i.e. they are CLOCKWISE seen from
			# above -- Godot's front face, pointing up.
			indices.append_array([a, b, d, a, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "x0": x0, "z0": z0, "x1": x1, "z1": z1}
