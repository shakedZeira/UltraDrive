class_name LeMansSurfaces
extends RefCounted

## Shared surface materials for the Le Mans No-Chicane scene
## (docs/plans/le_mans_visual_realism_plan.md WS-A / WS-B / WS-F).
##
## One place builds the noise textures and ShaderMaterials that the plain, the
## skirt, the verge wear band, the asphalt, the sand traps and the paved aprons
## all use, so every surface that meets another one samples the SAME seamless
## world-space noise (the "no visible seam" contract in
## `shaders/le_mans_ground_inc.gdshaderinc`).
##
## Everything here is deterministic: fixed seeds, fixed sizes, no RNG, no clock.
## The textures are cached in static vars so the scene, the test probes and any
## rebuild share one GPU copy (and one generation pass) per process.
##
## Renderer support: the four shaders use only core spatial built-ins
## (ALBEDO/ROUGHNESS/SPECULAR/NORMAL_MAP/UV/UV2/COLOR, fwidth), so they render on
## Forward+, Mobile and Compatibility alike. Nothing here needs a per-preset gate.

const GROUND_SHADER := "res://shaders/le_mans_ground.gdshader"
const GRAVEL_SHADER := "res://shaders/le_mans_gravel.gdshader"
const ASPHALT_SHADER := "res://shaders/le_mans_asphalt.gdshader"

## The one seamless value-noise tile every surface samples at several scales.
const NOISE_SIZE := 512
const NOISE_SEED := 20261021
const NOISE_FREQUENCY := 0.012
const NOISE_OCTAVES := 5
## Fine grain normal map (asphalt aggregate / gravel pebbles).
const GRAIN_SIZE := 256
const GRAIN_SEED := 20261022
const GRAIN_FREQUENCY := 0.09
const GRAIN_BUMP := 6.0

static var _noise_tex: NoiseTexture2D = null
static var _leaf_tex: NoiseTexture2D = null
static var _grain_tex: NoiseTexture2D = null


## Seamless 0..1 FBM tile (R channel), mipmapped.
static func noise_texture() -> NoiseTexture2D:
	if _noise_tex == null:
		var noise := FastNoiseLite.new()
		noise.seed = NOISE_SEED
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = NOISE_FREQUENCY
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = NOISE_OCTAVES
		var tex := NoiseTexture2D.new()
		tex.width = NOISE_SIZE
		tex.height = NOISE_SIZE
		tex.seamless = true
		tex.normalize = true
		tex.generate_mipmaps = true
		tex.noise = noise
		_noise_tex = tex
	return _noise_tex


## Low-contrast leafy clumping (0.6..1.0 grey) for canopy albedo: multiplied
## with each instance's green, it breaks flat low-poly lobes into foliage
## clusters without the near-black spots a full-range noise would paint.
static func leaf_texture() -> NoiseTexture2D:
	if _leaf_tex == null:
		var noise := FastNoiseLite.new()
		noise.seed = NOISE_SEED + 7
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.03
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.58, 0.58, 0.58))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.normalize = true
		tex.generate_mipmaps = true
		tex.color_ramp = ramp
		tex.noise = noise
		_leaf_tex = tex
	return _leaf_tex


## Seamless tangent-space normal map of a high-frequency cellular-ish noise.
static func grain_normal_texture() -> NoiseTexture2D:
	if _grain_tex == null:
		var noise := FastNoiseLite.new()
		noise.seed = GRAIN_SEED
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = GRAIN_FREQUENCY
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		var tex := NoiseTexture2D.new()
		tex.width = GRAIN_SIZE
		tex.height = GRAIN_SIZE
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = GRAIN_BUMP
		tex.generate_mipmaps = true
		tex.noise = noise
		_grain_tex = tex
	return _grain_tex


## Plain / skirt / verge. `vertex_wear` 1 enables the COLOR.r worn-earth blend
## (verge ribbon only); `tint` < 1 darkens (the vertical skirt face).
static func ground_material(vertex_wear: float = 0.0, tint: float = 1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(GROUND_SHADER) as Shader
	mat.set_shader_parameter("lm_noise", noise_texture())
	mat.set_shader_parameter("vertex_wear", vertex_wear)
	mat.set_shader_parameter("tint", tint)
	return mat


## Sand/gravel trap (`paved` 0) or paved asphalt run-off apron (`paved` 1).
static func gravel_material(paved: float = 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(GRAVEL_SHADER) as Shader
	mat.set_shader_parameter("lm_noise", noise_texture())
	mat.set_shader_parameter("pebble_normal", grain_normal_texture())
	mat.set_shader_parameter("paved", paved)
	return mat


## Carriageway: macro/micro asphalt variation, resurfacing sections, rubbered
## racing line (mesh UV2), dusty edges, crack sealant, painted edge lines.
static func asphalt_material(road_half_m: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(ASPHALT_SHADER) as Shader
	mat.set_shader_parameter("lm_noise", noise_texture())
	mat.set_shader_parameter("grain_normal", grain_normal_texture())
	mat.set_shader_parameter("road_half_m", road_half_m)
	return mat


## Appends one quad (a, b, c, d = two triangles a-b-c, c-b-d) to `indices`,
## flipping each triangle so its FRONT face points up (+Y). Godot's front faces
## are clockwise seen from the camera, i.e. their right-hand normal points AWAY
## from the viewer -- so a face seen from above must have a -Y geometric normal.
## Doing this numerically (instead of trusting a hand-derived winding per side)
## is what keeps a cull_disabled surface from rendering its back face, whose
## normal Godot flips DOWN and which then reads near-black under the sun.
static func append_quad_up(indices: PackedInt32Array, verts: PackedVector3Array,
		a: int, b: int, c: int, d: int) -> void:
	append_quad_facing(indices, verts, a, b, c, d, Vector3.UP)


## `append_quad_up` for an arbitrary intended front-face direction `facing`.
static func append_quad_facing(indices: PackedInt32Array, verts: PackedVector3Array,
		a: int, b: int, c: int, d: int, facing: Vector3) -> void:
	_append_tri_facing(indices, verts, a, b, c, facing)
	_append_tri_facing(indices, verts, c, b, d, facing)


static func _append_tri_facing(indices: PackedInt32Array, verts: PackedVector3Array,
		a: int, b: int, c: int, facing: Vector3) -> void:
	var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if n.dot(facing) > 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])
