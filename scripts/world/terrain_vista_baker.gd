# scripts/world/terrain_vista_baker.gd
class_name TerrainVistaBaker
extends RefCounted

## Pure math for the static far-terrain vista (TerrainVista): a 3x3 grid of
## 1024 px Terrain3D regions at 8 m per vertex, covering x/z [-8192, 16384).
## Every vista vertex samples the SAME canonical field the live ring bakes at
## 1 m (TerrainBaker: per-256 m-cell seeded fBm, biome table, domes, spawn pad,
## road carve, clamp) at the point the ring's texel maps to (vertex + 0.5 m),
## then sits BIAS below it, so wherever the ring is loaded the ring wins the
## depth test and the vista only shows past the ring's edge.
##
## The position-only terms (biome weight sums and domes) come from a 32 m
## lattice built per band; the biome base is acc / total of the interpolated
## sums. A 64 m lattice was measured too coarse at the dome feet (~1.3 m
## interpolation error, more than BIAS).
##
## An 8-aligned ring vertex X is a convex blend of the ring's 4 m coarse
## samples at X +- RING_COARSE_HALF (both axes); the vista samples X + 0.5,
## their bilinear centre. Two places need the exact samples instead: on a
## live-cell boundary the ring clamps its coarse grid (first texel = this
## cell's +2 m sample, last texels = the previous cell's -2 m sample, each
## with its own seed, so the ring has a seam there), and where every biome
## weight fades out the ring's base drops in one step (to
## BIOME_FALLBACK_BASE; 260 m -> 1 m east of the highland plateau). Those
## vertices take the minimum over the ring's samples (_support_min), and the
## biome-edge ones (0 < total < EDGE_TOTAL) are lowered to their 3x3 minimum
## in the second pass so no 8 m chord spans the step.
##
## Road corridors are carved with the ring's formulas (nearest segment, lower
## road wins near-ties, flat core, smoothstep blend to BLEND_END_DISTANCE).
## Between 8 m vertices the vista mesh is a straight chord, which can rise above
## the ring's curved cut/fill profile, so texels in a road's blend sink by an
## extra ROAD_SAG_BIAS per metre of cut or fill depth.
##
## Work is split into bands of BAND_ROWS rows (one 256 m cell row), each
## computed independently with its own noise objects, so bands run in parallel
## on WorkerThreadPool. The control pass needs the neighbouring rows for its
## slope, so it runs after every height band of a region is done.

const REGION_PX := 1024
const STEP := 8.0
const REGION_WORLD := 8192.0
const BIAS := -1.0
const ROAD_SAG_BIAS := 0.05
const SAMPLE_OFFSET := 0.5
const LOC_MIN := -1
const LOC_MAX := 1
const BAND_ROWS := 32
const BAND_COUNT := 32
const LAT_STEP := 32.0
const LAT_COLS := 258
const ROAD_BAND := 12.0
const ROAD_TOO_HIGH := 9.0
const ROAD_GAP := 0.5
const SAG_TAPER_START := 40.0
const SAG_TAPER_END := 56.0
const CONTROL_BLOCK := 2
const EDGE_TOTAL := 0.0006
const RING_COARSE_HALF := 2.0

## The nine region locations, always the same, in no particular order.
static func all_region_locs() -> Array[Vector2i]:
	var locs: Array[Vector2i] = []
	for ly in range(LOC_MIN, LOC_MAX + 1):
		for lx in range(LOC_MIN, LOC_MAX + 1):
			locs.append(Vector2i(lx, ly))
	return locs

## World XZ of a region's first vertex.
static func region_origin(loc: Vector2i) -> Vector2:
	return Vector2(float(loc.x) * REGION_WORLD, float(loc.y) * REGION_WORLD)

## World centre of a region, for Terrain3DData.add_region_blankp().
static func region_center(loc: Vector2i) -> Vector3:
	var o := region_origin(loc)
	return Vector3(o.x + REGION_WORLD * 0.5, 0.0, o.y + REGION_WORLD * 0.5)

## The nine locations sorted nearest-first to a world XZ (distance to each
## region's rectangle, so the region holding the point is always first).
static func order_locs(world_xz: Vector2) -> Array[Vector2i]:
	var locs := all_region_locs()
	locs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := _rect_distance(a, world_xz)
		var db := _rect_distance(b, world_xz)
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return locs

static func _rect_distance(loc: Vector2i, p: Vector2) -> float:
	var o := region_origin(loc)
	var dx := maxf(maxf(o.x - p.x, 0.0), p.x - (o.x + REGION_WORLD))
	var dz := maxf(maxf(o.y - p.y, 0.0), p.y - (o.y + REGION_WORLD))
	return sqrt(dx * dx + dz * dz)

## Road centrelines (the Array of Array[Vector3] the seeder carves with) as
## the ring's raw chains, clipped to a region plus the carve reach, so each
## band only scans the segments that can touch it.
static func region_chains(roads: Array, loc: Vector2i) -> Array[PackedVector3Array]:
	var tb := TerrainBaker.new()
	var chains := tb._raw_road_chains(roads)
	var o := region_origin(loc)
	var reach := SAG_TAPER_END + STEP
	return _clip_to_rect(tb, chains, o.x - reach, o.y - reach, o.x + REGION_WORLD + reach, o.y + REGION_WORLD + reach)

static func _clip_to_rect(tb: TerrainBaker, chains: Array[PackedVector3Array], min_x: float, min_z: float, max_x: float, max_z: float) -> Array[PackedVector3Array]:
	var clipped: Array[PackedVector3Array] = []
	for pts in chains:
		var n := pts.size()
		var closed := tb._chain_is_closed(pts)
		var run := PackedVector3Array()
		for s in (n if closed else n - 1):
			var a := pts[s]
			var b := pts[(s + 1) % n] if closed else pts[s + 1]
			if not tb._seg_in_rect(a, b, min_x, min_z, max_x, max_z):
				if run.size() >= 2:
					clipped.append(run)
				run = PackedVector3Array()
				continue
			if run.is_empty() or run[run.size() - 1] != a:
				run.append(a)
			if run[run.size() - 1] != b:
				run.append(b)
		if run.size() >= 2:
			clipped.append(run)
	return clipped

## Biome weight sums and dome height at a world point, with the same
## arithmetic as TerrainBaker._fill_coarse_natural(). Returns (acc, total, dome).
static func position_terms(wx: float, wz: float) -> Vector3:
	var total := 0.0
	var acc := 0.0
	var centers := [TerrainBaker.BIOME_SPAWN_CENTER, TerrainBaker.BIOME_ROLLING_CENTER, TerrainBaker.BIOME_HIGHLAND_CENTER, TerrainBaker.BIOME_FARMLAND_CENTER, TerrainBaker.BIOME_COAST_CENTER, TerrainBaker.BIOME_LOWLAND_CENTER, TerrainBaker.BIOME_HIGHLAND_PLATEAU_CENTER, TerrainBaker.BIOME_SEA_CENTER]
	var radii := [TerrainBaker.BIOME_SPAWN_RADIUS, TerrainBaker.BIOME_ROLLING_RADIUS, TerrainBaker.BIOME_HIGHLAND_RADIUS, TerrainBaker.BIOME_FARMLAND_RADIUS, TerrainBaker.BIOME_COAST_RADIUS, TerrainBaker.BIOME_LOWLAND_RADIUS, TerrainBaker.BIOME_HIGHLAND_PLATEAU_RADIUS, TerrainBaker.BIOME_SEA_RADIUS]
	var bases := [TerrainBaker.BIOME_SPAWN_BASE, TerrainBaker.BIOME_ROLLING_BASE, TerrainBaker.BIOME_HIGHLAND_BASE, TerrainBaker.BIOME_FARMLAND_BASE, TerrainBaker.BIOME_COAST_BASE, TerrainBaker.BIOME_LOWLAND_BASE, TerrainBaker.BIOME_HIGHLAND_PLATEAU_BASE, TerrainBaker.BIOME_SEA_BASE]
	for k in 8:
		var c: Vector2 = centers[k]
		var r: float = radii[k]
		var dx := wx - c.x
		var dz := wz - c.y
		var dist := sqrt(dx * dx + dz * dz)
		if dist < r:
			var t := 1.0 - dist / r
			total += t * t
			acc += t * t * float(bases[k])
	var dome := 0.0
	var ldx := wx - TerrainBaker.LEGACY_DOME_CENTER.x
	var ldz := wz - TerrainBaker.LEGACY_DOME_CENTER.y
	dome += TerrainBaker.LEGACY_DOME_AMP * (1.0 - smoothstep(TerrainBaker.LEGACY_DOME_RADIUS * TerrainBaker.LEGACY_DOME_EDGE, TerrainBaker.LEGACY_DOME_RADIUS, sqrt(ldx * ldx + ldz * ldz)))
	for di in TerrainBaker.DOME_FAMILY.size():
		var dc: Vector2 = TerrainBaker.DOME_FAMILY[di]["center"]
		var dr: float = TerrainBaker.DOME_FAMILY[di]["radius"]
		var de: float = TerrainBaker.DOME_FAMILY[di]["edge"]
		var da: float = TerrainBaker.DOME_FAMILY[di]["amp"]
		var ddx := wx - dc.x
		var ddz := wz - dc.y
		dome += da * (1.0 - smoothstep(dr * de, dr, sqrt(ddx * ddx + ddz * ddz)))
	return Vector3(acc, total, dome)

## Heights (BIAS applied) and the RGBA8 colour map of one band of rows of a
## region. Pure and thread-safe: every call makes its own noise objects.
## chains: region_chains() for this region. Returns {"height":
## PackedFloat32Array (BAND_ROWS x REGION_PX), "color": PackedByteArray}.
func bake_band(loc: Vector2i, band: int, chains: Array[PackedVector3Array]) -> Dictionary:
	var tb := TerrainBaker.new()
	tb._configure_control_noise()
	var o := region_origin(loc)
	var row0 := band * BAND_ROWS
	var rows := BAND_ROWS
	var n := rows * REGION_PX
	var z_first := o.y + float(row0) * STEP + SAMPLE_OFFSET
	var lat_z0 := floorf((z_first - o.y) / LAT_STEP) * LAT_STEP + o.y
	var lat_rows := int(ceilf((float(rows) * STEP) / LAT_STEP)) + 2
	var lat_acc := PackedFloat32Array()
	var lat_tot := PackedFloat32Array()
	var lat_dome := PackedFloat32Array()
	lat_acc.resize(lat_rows * LAT_COLS)
	lat_tot.resize(lat_rows * LAT_COLS)
	lat_dome.resize(lat_rows * LAT_COLS)
	for r in lat_rows:
		var lz := lat_z0 + float(r) * LAT_STEP
		for c in LAT_COLS:
			var t := position_terms(o.x + float(c) * LAT_STEP, lz)
			var li := r * LAT_COLS + c
			lat_acc[li] = t.x
			lat_tot[li] = t.y
			lat_dome[li] = t.z
	var col_idx := PackedInt32Array()
	col_idx.resize(REGION_PX)
	var col_t := PackedFloat32Array()
	col_t.resize(REGION_PX)
	for ix in REGION_PX:
		var g := (float(ix) * STEP + SAMPLE_OFFSET) / LAT_STEP
		var gi := int(floorf(g))
		col_idx[ix] = gi
		col_t[ix] = g - float(gi)
	var natural := PackedFloat32Array()
	natural.resize(n)
	var edge := PackedByteArray()
	edge.resize(n)
	var row_acc := PackedFloat32Array()
	var row_tot := PackedFloat32Array()
	var row_dome := PackedFloat32Array()
	row_acc.resize(rows * LAT_COLS)
	row_tot.resize(rows * LAT_COLS)
	row_dome.resize(rows * LAT_COLS)
	for j in rows:
		var sz := o.y + float(row0 + j) * STEP + SAMPLE_OFFSET
		var gz := (sz - lat_z0) / LAT_STEP
		var r0 := int(floorf(gz))
		var tz := gz - float(r0)
		var a0 := r0 * LAT_COLS
		var a1 := a0 + LAT_COLS
		var dst := j * LAT_COLS
		for c in LAT_COLS:
			row_acc[dst + c] = lerpf(lat_acc[a0 + c], lat_acc[a1 + c], tz)
			row_tot[dst + c] = lerpf(lat_tot[a0 + c], lat_tot[a1 + c], tz)
			row_dome[dst + c] = lerpf(lat_dome[a0 + c], lat_dome[a1 + c], tz)
	var cell_z := floori((o.y + float(row0) * STEP) / TerrainBaker.REGION_SIZE)
	var cells_x := int(REGION_WORLD / TerrainBaker.REGION_SIZE)
	var px_per_cell := int(TerrainBaker.REGION_SIZE / STEP)
	var cell_x0 := floori(o.x / TerrainBaker.REGION_SIZE)
	var prev_x := TerrainBaker.new()
	var prev_z := TerrainBaker.new()
	var prev_xz := TerrainBaker.new()
	for cx in cells_x:
		tb._configure_noise(Vector2i(cell_x0 + cx, cell_z))
		prev_x._configure_noise(Vector2i(cell_x0 + cx - 1, cell_z))
		prev_z._configure_noise(Vector2i(cell_x0 + cx, cell_z - 1))
		prev_xz._configure_noise(Vector2i(cell_x0 + cx - 1, cell_z - 1))
		var noises: Array[FastNoiseLite] = [tb._noise, prev_x._noise, prev_z._noise, prev_xz._noise]
		var noise := tb._noise
		for j in rows:
			var sz := o.y + float(row0 + j) * STEP + SAMPLE_OFFSET
			var rb := j * LAT_COLS
			var out_row := j * REGION_PX
			for k in px_per_cell:
				var ix := cx * px_per_cell + k
				var ci := rb + col_idx[ix]
				var tx := col_t[ix]
				var tot := lerpf(row_tot[ci], row_tot[ci + 1], tx)
				var sx := o.x + float(ix) * STEP + SAMPLE_OFFSET
				var near_edge := tot > 0.0 and tot < EDGE_TOTAL
				var acc := lerpf(row_acc[ci], row_acc[ci + 1], tx)
				var base := TerrainBaker.BIOME_FALLBACK_BASE if tot <= 0.0001 else acc / tot
				var scale := 1.8 + 0.14 * base
				var dome := lerpf(row_dome[ci], row_dome[ci + 1], tx)
				var near_top := base + dome + scale > TerrainBaker.HEIGHT_MAX
				if near_edge or near_top or k == 0 or j == 0:
					natural[out_row + ix] = _support_min(noises, sx - SAMPLE_OFFSET, sz - SAMPLE_OFFSET, k == 0, j == 0, near_edge or near_top)
					if near_edge:
						edge[out_row + ix] = 1
					continue
				var h := base + noise.get_noise_2d(sx, sz) * scale + dome
				natural[out_row + ix] = clampf(h, TerrainBaker.HEIGHT_MIN, TerrainBaker.HEIGHT_MAX)
	_spawn_guard(natural, o, row0, rows)
	var heights := natural.duplicate()
	var sag := PackedFloat32Array()
	if not chains.is_empty():
		sag = _carve_roads(heights, natural, chains, o, row0, rows)
	var color := PackedByteArray()
	color.resize(n * 4)
	var patch := tb._ctrl_patch
	for j in rows:
		var sz := o.y + float(row0 + j) * STEP + SAMPLE_OFFSET
		var out_row := j * REGION_PX
		for ix in REGION_PX:
			var i := out_row + ix
			var h := clampf(heights[i], TerrainBaker.HEIGHT_MIN, TerrainBaker.HEIGHT_MAX)
			var sx := o.x + float(ix) * STEP + SAMPLE_OFFSET
			var brightness := 0.92 + 0.16 * patch.get_noise_2d(sx * 2.3 + 911.0, sz * 2.3 - 377.0)
			var col: Color = TerrainBaker.BAND_COLORS[TerrainBaker.elevation_band(h)] * brightness
			var b := i * 4
			color[b] = clampi(int(col.r * 255.0), 0, 255)
			color[b + 1] = clampi(int(col.g * 255.0), 0, 255)
			color[b + 2] = clampi(int(col.b * 255.0), 0, 255)
			color[b + 3] = clampi(int(col.a * 255.0), 0, 255)
			var extra := sag[i] if not sag.is_empty() else 0.0
			heights[i] = h + BIAS - extra
	return {"height": heights, "color": color, "edge": edge}

## Exact natural height minimised over the ring's own samples for vertex
## (x, z): on a live-cell boundary (cell_x / cell_z) the ring's first texel
## uses this cell's coarse sample at +RING_COARSE_HALF and the previous cell's
## last texels hold its sample at -RING_COARSE_HALF (with that cell's seed);
## with corners (biome edge, height clamp) both +- samples of this cell; else
## the texel centre. Because the ring holds its first 2 m flat at the +2 m
## sample and only then follows the slope, a seam vertex also drops by 2 m
## times the slope there, so the 8 m chord into the cell stays under the ring.
## noises: this cell, previous x, previous z, previous x and z.
func _support_min(noises: Array[FastNoiseLite], x: float, z: float, cell_x: bool, cell_z: bool, corners: bool) -> float:
	var xs: Array = [[x + RING_COARSE_HALF, 0], [x - RING_COARSE_HALF, 1]] if cell_x else ([[x - RING_COARSE_HALF, 0], [x + RING_COARSE_HALF, 0]] if corners else [[x + SAMPLE_OFFSET, 0]])
	var zs: Array = [[z + RING_COARSE_HALF, 0], [z - RING_COARSE_HALF, 2]] if cell_z else ([[z - RING_COARSE_HALF, 0], [z + RING_COARSE_HALF, 0]] if corners else [[z + SAMPLE_OFFSET, 0]])
	var m := INF
	for zp: Array in zs:
		for xp: Array in xs:
			m = minf(m, _exact(noises[int(xp[1]) + int(zp[1])], xp[0], zp[0]))
	var this_cell := noises[0]
	if cell_x:
		var zq: float = zs[0][0]
		var a := _exact(this_cell, x + RING_COARSE_HALF, zq)
		var b := _exact(this_cell, x + 3.0 * RING_COARSE_HALF, zq)
		m -= RING_COARSE_HALF * absf(b - a) / (2.0 * RING_COARSE_HALF)
	if cell_z:
		var xq: float = xs[0][0]
		var a := _exact(this_cell, xq, z + RING_COARSE_HALF)
		var b := _exact(this_cell, xq, z + 3.0 * RING_COARSE_HALF)
		m -= RING_COARSE_HALF * absf(b - a) / (2.0 * RING_COARSE_HALF)
	return m

## TerrainBaker's natural height at a world point, with the given cell noise.
static func _exact(noise: FastNoiseLite, px: float, pz: float) -> float:
	var t := position_terms(px, pz)
	var base := TerrainBaker.BIOME_FALLBACK_BASE if t.y <= 0.0001 else t.x / t.y
	var h := base + noise.get_noise_2d(px, pz) * (1.8 + 0.14 * base) + t.z
	return clampf(h, TerrainBaker.HEIGHT_MIN, TerrainBaker.HEIGHT_MAX)

## Spawn plateau guard, before the road carve like the ring.
func _spawn_guard(buf: PackedFloat32Array, o: Vector2, row0: int, rows: int) -> void:
	var c := TerrainBaker.SPAWN_PLATEAU_CENTER
	var r := TerrainBaker.SPAWN_PLATEAU_RADIUS
	var r2 := r * r
	for j in rows:
		var sz := o.y + float(row0 + j) * STEP + SAMPLE_OFFSET
		var dz := sz - c.y
		if absf(dz) > r:
			continue
		var lo := maxi(0, int(floorf((c.x - r - SAMPLE_OFFSET - o.x) / STEP)))
		var hi := mini(REGION_PX - 1, int(ceilf((c.x + r - SAMPLE_OFFSET - o.x) / STEP)))
		for ix in range(lo, hi + 1):
			var dx := o.x + float(ix) * STEP + SAMPLE_OFFSET - c.x
			if dx * dx + dz * dz <= r2:
				buf[j * REGION_PX + ix] = TerrainBaker.SPAWN_HEIGHT

## Ring road carve on the band's vertices (TerrainBaker._conform_roads rules,
## ROAD_BAND being the ring's 12 * step^2 at its 1 m step). Writes the carved
## heights into buf and returns the per-texel sag allowance.
func _carve_roads(buf: PackedFloat32Array, natural: PackedFloat32Array, chains: Array[PackedVector3Array], o: Vector2, row0: int, rows: int) -> PackedFloat32Array:
	var n := rows * REGION_PX
	var sag := PackedFloat32Array()
	var reach := SAG_TAPER_END
	var reach2 := reach * reach
	var z_lo := o.y + float(row0) * STEP + SAMPLE_OFFSET
	var z_hi := z_lo + float(rows - 1) * STEP
	var x_lo := o.x + SAMPLE_OFFSET
	var x_hi := x_lo + float(REGION_PX - 1) * STEP
	var d2_map := PackedFloat32Array()
	var elev_map := PackedFloat32Array()
	var owner := PackedInt32Array()
	var any := false
	var ri := 0
	for pts in chains:
		ri += 1
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			if maxf(a.x, b.x) < x_lo - reach or minf(a.x, b.x) > x_hi + reach:
				continue
			if maxf(a.z, b.z) < z_lo - reach or minf(a.z, b.z) > z_hi + reach:
				continue
			var abx := b.x - a.x
			var abz := b.z - a.z
			var len2 := abx * abx + abz * abz
			if len2 <= 0.0001:
				continue
			if not any:
				any = true
				d2_map.resize(n)
				d2_map.fill(INF)
				elev_map.resize(n)
				owner.resize(n)
				owner.fill(-1)
			var dy := b.y - a.y
			var lo_ix := maxi(0, int(floorf((minf(a.x, b.x) - reach - x_lo) / STEP)))
			var hi_ix := mini(REGION_PX - 1, int(ceilf((maxf(a.x, b.x) + reach - x_lo) / STEP)))
			var lo_j := maxi(0, int(floorf((minf(a.z, b.z) - reach - z_lo) / STEP)))
			var hi_j := mini(rows - 1, int(ceilf((maxf(a.z, b.z) + reach - z_lo) / STEP)))
			for j in range(lo_j, hi_j + 1):
				var dz := z_lo + float(j) * STEP - a.z
				var row := j * REGION_PX
				for ix in range(lo_ix, hi_ix + 1):
					var wx := x_lo + float(ix) * STEP
					var t := clampf(((wx - a.x) * abx + dz * abz) / len2, 0.0, 1.0)
					var ex := wx - (a.x + abx * t)
					var ez := dz - abz * t
					var d2 := ex * ex + ez * ez
					if d2 >= reach2:
						continue
					var i := row + ix
					var elev := a.y + dy * t
					var cur := d2_map[i]
					var owned := cur < reach2
					var too_high := owned and elev - elev_map[i] > ROAD_TOO_HIGH
					if (d2 < cur - ROAD_BAND and not too_high) or (owned and d2 <= cur + ROAD_BAND and elev_map[i] - elev > ROAD_GAP and owner[i] != ri):
						d2_map[i] = d2
						elev_map[i] = elev
						owner[i] = ri
	if not any:
		return sag
	sag.resize(n)
	var core := TerrainBaker.ROAD_WIDTH * 0.5 + 0.3
	var blend_end := TerrainBaker.BLEND_END_DISTANCE
	for i in n:
		var d2 := d2_map[i]
		if d2 >= reach2:
			continue
		var dist := sqrt(d2)
		var target := elev_map[i] - TerrainBaker.ROAD_TOPPING
		var nat := natural[i]
		if dist < blend_end:
			if dist <= core:
				buf[i] = target
			else:
				buf[i] = lerpf(target, nat, smoothstep(core, blend_end, dist))
		sag[i] = ROAD_SAG_BIAS * absf(nat - target) * (1.0 - smoothstep(SAG_TAPER_START, SAG_TAPER_END, dist))
	return sag

## Second pass over one band, from the region's assembled biased heights and
## biome-edge mask (all REGION_PX rows; only the band's rows +-1 are read).
## Returns {"control": Terrain3D control bits (FORMAT_RF bytes), "height": the
## band's final rows (erode_rows)}. Control is classified on the input heights.
func bake_control_band(loc: Vector2i, band: int, heights: PackedFloat32Array, edge: PackedByteArray = PackedByteArray()) -> Dictionary:
	return {"control": _control_rows(loc, band, heights), "height": erode_rows(heights, edge, band * BAND_ROWS, BAND_ROWS)}

## Every vertex flagged in edge (near the biome-union step) takes the minimum
## of its 3x3 neighbourhood, so the quads on both sides of the step sit below
## the ring's ramp. Only ever lowers the field; other vertices are untouched.
static func erode_rows(heights: PackedFloat32Array, edge: PackedByteArray, row0: int, rows: int) -> PackedFloat32Array:
	var w := REGION_PX
	var last := w - 1
	var out := heights.slice(row0 * w, (row0 + rows) * w)
	if edge.is_empty():
		return out
	for j in rows:
		var r := row0 + j
		var rb := r * w
		for c in w:
			if edge[rb + c] == 0:
				continue
			var m := INF
			for rr in [maxi(r - 1, 0), r, mini(r + 1, last)]:
				var b: int = rr * w
				m = minf(m, minf(heights[b + maxi(c - 1, 0)], minf(heights[b + c], heights[b + mini(c + 1, last)])))
			out[j * w + c] = m
	return out

## Control bits for one band, classified per CONTROL_BLOCK x CONTROL_BLOCK
## block with TerrainBaker.classify_ground(); roads are left out (sub-texel at
## 8 m, and the road meshes cover them).
func _control_rows(loc: Vector2i, band: int, heights: PackedFloat32Array) -> PackedByteArray:
	var tb := TerrainBaker.new()
	tb._configure_control_noise()
	var o := region_origin(loc)
	var row0 := band * BAND_ROWS
	var rows := BAND_ROWS
	var out := PackedByteArray()
	out.resize(rows * REGION_PX * 4)
	var coast_near := _near_coast(o)
	var last := REGION_PX - 1
	var inv := 1.0 / (2.0 * STEP)
	for bj in range(0, rows, CONTROL_BLOCK):
		var iz := row0 + bj
		var zm := maxi(iz - 1, 0)
		var zp := mini(iz + 1, last)
		var sz := o.y + float(iz) * STEP + SAMPLE_OFFSET
		for bx in range(0, REGION_PX, CONTROL_BLOCK):
			var xm := maxi(bx - 1, 0)
			var xp := mini(bx + 1, last)
			var row := iz * REGION_PX
			var gx := (heights[row + xp] - heights[row + xm]) * inv
			var gz := (heights[zp * REGION_PX + bx] - heights[zm * REGION_PX + bx]) * inv
			var sx := o.x + float(bx) * STEP + SAMPLE_OFFSET
			var coast := TerrainBaker.coast_weight(sx, sz) if coast_near else 0.0
			var bits := TerrainBaker.classify_ground(heights[row + bx] - BIAS, sqrt(gx * gx + gz * gz), tb._ctrl_patch.get_noise_2d(sx, sz), tb._ctrl_detail.get_noise_2d(sx, sz), coast, INF)
			for dj in CONTROL_BLOCK:
				var ob := (bj + dj) * REGION_PX
				for di in CONTROL_BLOCK:
					out.encode_u32((ob + bx + di) * 4, bits)
	return out

static func _near_coast(o: Vector2) -> bool:
	var reach := maxf(TerrainBaker.BIOME_COAST_RADIUS, TerrainBaker.BIOME_SEA_RADIUS)
	for c: Vector2 in [TerrainBaker.BIOME_COAST_CENTER, TerrainBaker.BIOME_SEA_CENTER]:
		var dx := maxf(maxf(o.x - c.x, 0.0), c.x - (o.x + REGION_WORLD))
		var dz := maxf(maxf(o.y - c.y, 0.0), c.y - (o.y + REGION_WORLD))
		if dx * dx + dz * dz < reach * reach:
			return true
	return false

## Whole region on the calling thread (tests, tools). TerrainVista runs the
## same bands on WorkerThreadPool instead. Returns {"height", "color",
## "control": Image, "height_min", "height_max": float}.
func bake_region(loc: Vector2i, roads: Array) -> Dictionary:
	var chains := region_chains(roads, loc)
	var bands: Array = []
	for b in BAND_COUNT:
		bands.append(bake_band(loc, b, chains))
	return assemble(loc, bands, self)

## Joins height/colour bands, runs the second pass (serially on `baker`) and
## builds the Terrain3D images. Used by bake_region(); TerrainVista runs the
## second pass on the pool and calls make_images() itself.
static func assemble(loc: Vector2i, bands: Array, baker: TerrainVistaBaker) -> Dictionary:
	var heights := join_heights(bands)
	var edge := join_edges(bands)
	var second: Array = []
	for b in BAND_COUNT:
		second.append(baker.bake_control_band(loc, b, heights, edge))
	return make_images(second, join_colors(bands))

static func join_heights(bands: Array) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	for b: Dictionary in bands:
		heights.append_array(b["height"])
	return heights

static func join_edges(bands: Array) -> PackedByteArray:
	var edge := PackedByteArray()
	for b: Dictionary in bands:
		edge.append_array(b["edge"])
	return edge

static func join_colors(bands: Array) -> PackedByteArray:
	var color := PackedByteArray()
	for b: Dictionary in bands:
		color.append_array(b["color"])
	return color

## second: the bake_control_band() results of every band, in band order. The
## colour map carries its mipmaps: Terrain3D's shader samples it at a
## distance-based mip, and a vista texel (8 m) reaches mip 1 at ~5 km, where
## the missing levels rendered black.
static func make_images(second: Array, color: PackedByteArray) -> Dictionary:
	var control := PackedByteArray()
	var heights := PackedFloat32Array()
	for s: Dictionary in second:
		control.append_array(s["control"])
		heights.append_array(s["height"])
	var lo := INF
	var hi := -INF
	for h in heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var color_img := Image.create_from_data(REGION_PX, REGION_PX, false, Image.FORMAT_RGBA8, color)
	color_img.generate_mipmaps()
	return {
		"height": Image.create_from_data(REGION_PX, REGION_PX, false, Image.FORMAT_RF, heights.to_byte_array()),
		"color": color_img,
		"control": Image.create_from_data(REGION_PX, REGION_PX, false, Image.FORMAT_RF, control),
		"height_min": lo,
		"height_max": hi,
	}
