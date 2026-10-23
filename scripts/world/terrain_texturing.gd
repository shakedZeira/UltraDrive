# scripts/world/terrain_texturing.gd
class_name TerrainTexturing
extends RefCounted

## Open-world ground look for Terrain3D: the texture set, the control-map bit
## layout TerrainBaker.bake_region_control() writes, and the material settings
## that keep the layers from reading as a repeating tile.
##
## Textures: 8 CC0 ambientCG layers (sources in assets/terrain/SOURCES.md),
## packed by tools/pack_terrain_textures.py into Terrain3D's two-array layout
## (albedo RGB + height A, OpenGL normal RGB + roughness A), 1024 px, VRAM
## compressed with mipmaps. LAYERS order IS the Terrain3D texture id, and the
## packer's LAYERS table must list the same names in the same order.
##
## Tiling is hidden inside Terrain3D's own shaders (no custom shader to
## maintain): the material's macro variation (two low-frequency world-space
## noise tints), height-based blending between the 2 layers each control texel
## holds, world-space biome patches in the control map, and in the FULL tier
## per-layer detiling (random per-cell rotation + shift) plus projected UVs on
## steep faces (enable_projection, Terrain3D's triplanar equivalent). See
## QUALITY_LITE / QUALITY_FULL for the measured cost of each tier. The ground is
## one heightfield mesh, so there is no second surface to z-fight with.
##
## Encoding helpers are static and pure (no engine singletons), so the bake
## worker thread can call them; tests pin them against Terrain3DUtil.

const TEXTURE_DIR := "res://assets/terrain/textures/"
const ALBEDO_SUFFIX := "_alb_ht.png"
const NORMAL_SUFFIX := "_nrm_rgh.png"

const ID_GRASS := 0
const ID_MEADOW := 1
const ID_DIRT := 2
const ID_ROCK := 3
const ID_SAND := 4
const ID_SNOW := 5
const ID_GRAVEL := 6
const ID_FOREST := 7
const LAYER_COUNT := 8

## Per-layer Terrain3DTextureAsset settings, indexed by texture id.
## uv_scale: texture repeats per metre in Terrain3D's generated (FULL) shader,
## 0.24 = one repeat every ~4.2 m; the LITE shader halves it (~8.3 m), which
## also stretches the repeat at distance. detiling_*: 0..1 strength of the per-cell random
## rotation / shift. roughness: added to the packed roughness (-1..1).
## roughness is pushed up on the vegetation/soil layers: natural ground is
## near-fully rough, and the scans' own roughness let grazing-angle Fresnel
## mirror the sky as white blotches across distant fields (seen in captures).
const LAYERS := [
	{"name": "grass", "uv_scale": 0.24, "detiling_rotation": 0.35, "detiling_shift": 0.35, "normal_depth": 1.0, "ao_strength": 0.5, "roughness": 0.35},
	{"name": "meadow", "uv_scale": 0.12, "detiling_rotation": 0.35, "detiling_shift": 0.35, "normal_depth": 1.0, "ao_strength": 0.5, "roughness": 0.35, "tint": Color(0.86, 0.92, 0.78)},
	{"name": "dirt", "uv_scale": 0.2, "detiling_rotation": 0.3, "detiling_shift": 0.3, "normal_depth": 1.0, "ao_strength": 0.5, "roughness": 0.25},
	{"name": "rock", "uv_scale": 0.08, "detiling_rotation": 0.2, "detiling_shift": 0.3, "normal_depth": 1.2, "ao_strength": 0.7, "roughness": 0.15, "tint": Color(1.25, 1.22, 1.18)},
	{"name": "sand", "uv_scale": 0.16, "detiling_rotation": 0.3, "detiling_shift": 0.3, "normal_depth": 0.8, "ao_strength": 0.3, "roughness": 0.25},
	{"name": "snow", "uv_scale": 0.12, "detiling_rotation": 0.3, "detiling_shift": 0.3, "normal_depth": 0.7, "ao_strength": 0.3, "roughness": 0.1},
	{"name": "gravel", "uv_scale": 0.3, "detiling_rotation": 0.4, "detiling_shift": 0.4, "normal_depth": 1.0, "ao_strength": 0.6, "roughness": 0.2},
	{"name": "forest", "uv_scale": 0.24, "detiling_rotation": 0.35, "detiling_shift": 0.35, "normal_depth": 1.0, "ao_strength": 0.5, "roughness": 0.35},
]

## Terrain3D material shader parameters (names from Terrain3DMaterial's
## generated shader in addon 1.0.x). Macro variation tints are multiplied in
## where the world-space noise is low, so they must stay close to white.
const SHADER_PARAMS := {
	# Height-blend sharpness: 0.8 gave stair-stepped 1 m texel edges along
	# diagonal road shoulders; ~0.5 keeps a natural height-blend, softer edge.
	"blend_sharpness": 0.5,
	"enable_projection": true,
	"projection_threshold": 0.8,
	"enable_macro_variation": true,
	"macro_variation1": Color(0.86, 0.92, 0.8),
	"macro_variation2": Color(0.95, 0.9, 0.84),
	"macro_variation_slope": 0.333,
	"noise1_scale": 0.04,
	"noise2_scale": 0.076,
}

# -- Control map bit layout (Terrain3D 1.0, see addons/terrain_3d/extras/shaders) --
const CONTROL_BASE_SHIFT := 27
const CONTROL_OVERLAY_SHIFT := 22
const CONTROL_BLEND_SHIFT := 14
const CONTROL_ID_MASK := 0x1F
const CONTROL_BLEND_MASK := 0xFF
const CONTROL_AUTO_BIT := 0x1

## Packs one control texel: base texture id, overlay texture id, overlay blend
## (0 = all base, 1 = all overlay) and the autoshader flag. Returns the raw
## uint32 bit pattern (Terrain3D stores it reinterpreted as a 32-bit float).
static func encode_control(base: int, overlay: int, blend: float, auto: bool = false) -> int:
	var b := clampi(int(roundf(clampf(blend, 0.0, 1.0) * 255.0)), 0, CONTROL_BLEND_MASK)
	var bits := ((base & CONTROL_ID_MASK) << CONTROL_BASE_SHIFT) \
		| ((overlay & CONTROL_ID_MASK) << CONTROL_OVERLAY_SHIFT) \
		| (b << CONTROL_BLEND_SHIFT)
	if auto:
		bits |= CONTROL_AUTO_BIT
	return bits

static func decode_base(bits: int) -> int:
	return (bits >> CONTROL_BASE_SHIFT) & CONTROL_ID_MASK

static func decode_overlay(bits: int) -> int:
	return (bits >> CONTROL_OVERLAY_SHIFT) & CONTROL_ID_MASK

static func decode_blend(bits: int) -> float:
	return float((bits >> CONTROL_BLEND_SHIFT) & CONTROL_BLEND_MASK) / 255.0

## Reads the raw control bits of texel (x, y) from a FORMAT_RF control image.
static func control_at(image: Image, x: int, y: int) -> int:
	var data := image.get_data()
	return data.decode_u32((y * image.get_width() + x) * 4)

static func albedo_path(id: int) -> String:
	return TEXTURE_DIR + String(LAYERS[id]["name"]) + ALBEDO_SUFFIX

static func normal_path(id: int) -> String:
	return TEXTURE_DIR + String(LAYERS[id]["name"]) + NORMAL_SUFFIX

## Builds the Terrain3DAssets texture list from LAYERS. Returns null when any
## texture fails to load (the caller then leaves the terrain untouched rather
## than shipping a half-filled texture array).
static func build_assets() -> Terrain3DAssets:
	var assets := Terrain3DAssets.new()
	var list: Array = []
	for id in LAYERS.size():
		var layer: Dictionary = LAYERS[id]
		var albedo := load(albedo_path(id)) as Texture2D
		var normal := load(normal_path(id)) as Texture2D
		if albedo == null or normal == null:
			push_warning("TerrainTexturing: missing texture for layer '%s'" % layer["name"])
			return null
		var tex := Terrain3DTextureAsset.new()
		tex.name = String(layer["name"])
		tex.id = id
		tex.albedo_texture = albedo
		tex.normal_texture = normal
		tex.uv_scale = float(layer["uv_scale"])
		tex.detiling_rotation = float(layer["detiling_rotation"])
		tex.detiling_shift = float(layer["detiling_shift"])
		tex.normal_depth = float(layer["normal_depth"])
		tex.ao_strength = float(layer["ao_strength"])
		tex.roughness = float(layer["roughness"])
		tex.albedo_color = layer.get("tint", Color.WHITE)
		list.append(tex)
	assets.texture_list = list
	return assets

## Ground shader tiers. Measured 2026-10-22 on the GTX 970 / 1080p / Medium,
## fixed camera poses around the hub, vs the old untextured checkerboard:
##   QUALITY_LITE (addon extras/shaders/lightweight.gdshader override):
##     +0.5..+1.2 ms. Base/overlay/blend, height blending, autoshader, colour
##     map, macro variation; no per-cell detiling, no projected cliffs.
##   QUALITY_FULL (Terrain3D's generated shader, dual scaling off):
##     +1.5..+6.7 ms. Adds detiling, projected UVs on steep faces, per-pixel
##     normals and 4-texel bilinear id blending near the camera. Dual scaling
##     cost another 1.5..4 ms, so it stays off.
## LITE is the default (the plan's ground budget is ~+1 ms GPU at Medium).
const QUALITY_LITE := 0
const QUALITY_FULL := 1
const LITE_SHADER_PATH := "res://addons/terrain_3d/extras/shaders/lightweight.gdshader"

## Gives a Terrain3D node the ground texture set and material settings.
## Background (outside any region) and blank regions use the autoshader, set
## to plain grass, so a not-yet-baked region already reads as ground.
## Returns false when the terrain or the textures are missing. shared_assets:
## an already built set to reuse (the far vista shares the live terrain's).
static func apply(terrain: Terrain3D, quality: int = QUALITY_LITE, shared_assets: Terrain3DAssets = null) -> bool:
	if terrain == null:
		return false
	var assets := shared_assets if shared_assets != null else build_assets()
	if assets == null:
		return false
	terrain.assets = assets
	# The node mirrors its debug views into the material; both must be off.
	terrain.show_checkered = false
	terrain.show_colormap = false
	var mat: Terrain3DMaterial = terrain.material
	if mat == null:
		mat = Terrain3DMaterial.new()
		terrain.material = mat
	mat.show_checkered = false
	mat.show_colormap = false
	mat.auto_shader = true
	mat.dual_scaling = false
	var lite := quality == QUALITY_LITE
	var lite_shader: Shader = load(LITE_SHADER_PATH) as Shader if lite else null
	mat.shader_override = lite_shader
	mat.shader_override_enabled = lite_shader != null
	# Feature toggles rebuild the generated shader, and a rebuild drops any
	# parameter set before it (they read back null), so rebuild first, then set.
	mat.update()
	apply_shader_params(mat)
	return true

## Writes SHADER_PARAMS plus the autoshader / dual-scale texture choices into
## a Terrain3D material. Safe to call again after any later shader rebuild.
static func apply_shader_params(mat: Terrain3DMaterial) -> void:
	if mat == null:
		return
	# The autoshader only shades the flat world background past the live ring
	# and blank regions awaiting their bake (baked regions carry real ids). Its
	# slope term reads bogus normals outside regions, so a rock base showed as
	# pale blotches across the far background: both slots are grass.
	mat.set_shader_param("auto_base_texture", ID_GRASS)
	mat.set_shader_param("auto_overlay_texture", ID_GRASS)
	for key: String in SHADER_PARAMS:
		mat.set_shader_param(key, SHADER_PARAMS[key])
