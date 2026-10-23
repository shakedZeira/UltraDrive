# scripts/ui/map_terrain.gd
class_name MapTerrain
extends RefCounted

## Shared relief for the 2D maps (pause map + HUD minimap): ONE height texture
## baked once per world rect on a worker thread, shaded per pixel by
## shaders/ui/map_terrain.gdshader. Replaces the old 64x64 block grid, so the map
## backdrop is smooth at any zoom and costs the CPU nothing per frame.
##
## Heights come from the deterministic TerrainBaker natural field (the same field
## the pause map always used), never from the streamed ring, so the whole island
## is visible the moment the map opens. A map without a terrain source never
## requests a bake and keeps its flat backdrop.
##
## State is static on purpose: the HUD minimap and the pause map want the same
## image, and the bake (~0.3 s) must run once, off the main thread. poll() is the
## one main-thread step (it turns the finished Image into a texture); callers
## invoke it every frame until is_ready().

const SHADER_PATH := "res://shaders/ui/map_terrain.gdshader"
## Texels per side of the baked square (about 50 m per texel over a 20 km rect).
const DEFAULT_PX := 384
## The baked square is this multiple of the road span, centred on the roads, so a
## wide pause-map panel never runs out of terrain past the letterboxed content.
const RECT_SPAN_FACTOR := 2.3
const MIN_SPAN_M := 512.0

static var _rect := Rect2()
static var _px := 0
static var _image: Image = null
static var _texture: ImageTexture = null
static var _task_id := -1
static var _result: Image = null
static var _shader: Shader = null

## The square world rect (x, z metres) to bake for a road network: centred on the
## roads' AABB, RECT_SPAN_FACTOR times its longest side. Empty roads -> empty Rect2.
static func world_rect_for_roads(chains: Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for chain in chains:
		for p in chain:
			var w: Vector3 = p
			lo.x = minf(lo.x, w.x)
			lo.y = minf(lo.y, w.z)
			hi.x = maxf(hi.x, w.x)
			hi.y = maxf(hi.y, w.z)
	if not is_finite(lo.x) or not is_finite(hi.x):
		return Rect2()
	var span := maxf(maxf(hi.x - lo.x, hi.y - lo.y), MIN_SPAN_M) * RECT_SPAN_FACTOR
	var centre := (lo + hi) * 0.5
	# Snap to 256 m so a one-vertex change in a road does not invalidate the bake.
	span = ceilf(span / 256.0) * 256.0
	var origin := Vector2(floorf((centre.x - span * 0.5) / 256.0), floorf((centre.y - span * 0.5) / 256.0)) * 256.0
	return Rect2(origin, Vector2(span, span))

## Pure bake: an FORMAT_RF height image of `rect` at px x px from a provider
## Callable(Vector2 xz) -> float. Texel centres, row 0 = rect.position.y (north).
static func bake_image(provider: Callable, rect: Rect2, px: int) -> Image:
	var n := maxi(px, 2)
	var buf := PackedFloat32Array()
	buf.resize(n * n)
	var step := rect.size / float(n)
	for iy in n:
		var wz := rect.position.y + (float(iy) + 0.5) * step.y
		var row := iy * n
		for ix in n:
			var h := float(provider.call(Vector2(rect.position.x + (float(ix) + 0.5) * step.x, wz)))
			buf[row + ix] = h if is_finite(h) else 0.0
	return Image.create_from_data(n, n, false, Image.FORMAT_RF, buf.to_byte_array())

## Make sure `rect` is baked (or being baked). A different rect or size restarts.
## With an explicit `provider` (tests, injected readers) the bake is synchronous
## and the texture exists on return; otherwise the TerrainBaker natural field is
## baked on a worker thread and poll() picks the result up.
static func request(rect: Rect2, px: int = DEFAULT_PX, provider: Callable = Callable()) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if rect == _rect and px == _px and (_texture != null or _task_id >= 0):
		return
	reset()
	_rect = rect
	_px = px
	if provider.is_valid():
		_install(bake_image(provider, rect, px))
		return
	var bake_rect := rect
	var bake_px := px
	_task_id = WorkerThreadPool.add_task(func() -> void:
		var baker := TerrainBaker.new()
		_result = baker.bake_full_height_image(bake_rect.position, bake_rect.end, bake_px, bake_px)
	)

## Main-thread step: finishes a completed worker bake. Returns is_ready().
static func poll() -> bool:
	if _texture != null:
		return true
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		if _result != null:
			_install(_result)
			_result = null
	return _texture != null

static func _install(image: Image) -> void:
	_image = image
	# Half-float: R32F textures are not linearly filterable on every GPU (the map
	# showed stair-stepped nearest-neighbour relief), RH always is. Heights are
	# well inside half-float range and a 0.5 m step at 1 km is invisible.
	var filterable := image.duplicate() as Image
	filterable.convert(Image.FORMAT_RH)
	_texture = ImageTexture.create_from_image(filterable)

static func is_ready() -> bool:
	return _texture != null

static func is_pending() -> bool:
	return _task_id >= 0

static func rect() -> Rect2:
	return _rect

static func texture() -> Texture2D:
	return _texture

## The baked height under `xz` (bilinear, edge-clamped); `fallback` when unbaked.
static func height_at(xz: Vector2, fallback: float = 0.0) -> float:
	if _image == null:
		return fallback
	var texel := _rect.size / float(_image.get_width())
	return MapRoads.sample_height_image(_image, _rect.position, texel, xz)

## Drop the cache (and join any in-flight bake). Tests call this for isolation.
static func reset() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	_result = null
	_image = null
	_texture = null
	_rect = Rect2()
	_px = 0

static func make_material() -> ShaderMaterial:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	return mat

## Point a material at the baked texture and a view. `view_world_min` is the
## world xz under the control's top-left pixel, `view_scale` px per metre.
## `mask_radius` > 0 clips to a disc of that radius (the minimap).
static func apply_view(mat: ShaderMaterial, rect_px: Vector2, view_world_min: Vector2,
		view_scale: float, mask_radius: float = 0.0, dim: float = 1.0,
		saturation: float = 1.0, hill_strength: float = 1.0) -> void:
	if mat == null or _texture == null:
		return
	mat.set_shader_parameter("height_tex", _texture)
	mat.set_shader_parameter("tex_world_min", _rect.position)
	mat.set_shader_parameter("tex_world_size", _rect.size)
	mat.set_shader_parameter("rect_px", rect_px)
	mat.set_shader_parameter("view_world_min", view_world_min)
	mat.set_shader_parameter("view_scale", view_scale)
	mat.set_shader_parameter("mask_radius", mask_radius)
	mat.set_shader_parameter("dim", dim)
	mat.set_shader_parameter("saturation", saturation)
	mat.set_shader_parameter("hill_strength", hill_strength)
