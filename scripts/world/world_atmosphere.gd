# scripts/world/world_atmosphere.gd
class_name WorldAtmosphere
extends Node3D

## FH6-look atmosphere for the open world (2026-10-23). Created at runtime by
## WorldDriver._bootstrap_world_look(); the scene keeps its authored
## Environment / PhysicalSkyMaterial as the fallback that other scenes and the
## environment-lighting gate read.
##
## What it does:
##  - colour grade: Environment adjustments (a little contrast, warmer and more
##    saturated) — part of the tonemap pass, effectively free;
##  - haze: lighter aerial-perspective fog (FOG_DENSITY) so the 24 km vista keeps
##    its relief instead of turning into flat blue silhouettes past ~2 km, a bit
##    denser by the coast and thinner in the alpine area (haze_for);
##  - sky: clearer PhysicalSky (lower turbidity / Mie), brighter ground bounce;
##  - sun: warm low sun, neutral-warm noon, dim blue moonlight at night
##    (sun_grade), re-applied only when the hour moved by > 0.05 h so the sky
##    radiance is not re-baked every frame;
##  - sea: an opaque water plane at y = 0 over the sea biome (there was none:
##    the sea floor rendered as a sand desert);
##  - clouds: a cumulus layer on a camera-following inverted sphere (Medium and
##    High; off on Low) — shaders/cloud_layer.gdshader.
## Quality hook: set_world_detail(level) (group "world_detail", called by
## SettingsMenu.apply_quality_preset).

const GROUP := "world_detail"
const FOG_DENSITY := 0.00026
const FOG_COLOR := Color(0.70, 0.80, 0.92)
const ADJ_CONTRAST := 1.07
const ADJ_SATURATION := 1.16
const ADJ_BRIGHTNESS := 1.02
const SKY_TURBIDITY := 3.2
const SKY_RAYLEIGH := 2.3
const SKY_MIE := 0.005
const SKY_GROUND := Color(0.23, 0.25, 0.18)
const SUN_DAY_ENERGY := 1.3
const SUN_NIGHT_ENERGY := 0.12
const SEA_CENTER := Vector2(9100.0, -4700.0)
const SEA_SIZE := Vector2(9800.0, 8600.0)
const CLOUD_RADIUS := 20000.0
const HOUR_EPSILON := 0.05

var environment: Environment
var sun: DirectionalLight3D
var player: Node3D
var detail := 1
var _cloud: MeshInstance3D
var _cloud_mat: ShaderMaterial
var _sea: MeshInstance3D
var _last_hour := -100.0
var _last_haze := -1.0

func _ready() -> void:
	add_to_group(GROUP)
	apply_static()
	_build_sea()
	_build_clouds()
	_update(true)

## Pure: sun colour and energy for an hour of the day (0..24). Warm and dim at
## low sun, neutral-warm at noon, faint blue at night.
static func sun_grade(hour: float) -> Dictionary:
	var angle := deg_to_rad(fposmod(hour, 24.0) / 24.0 * 360.0 - 90.0)
	var elev := Vector3(cos(angle), sin(angle), 0.3).normalized().y
	if elev <= 0.0:
		return {"color": Color(0.55, 0.65, 0.9), "energy": SUN_NIGHT_ENERGY, "elevation": elev}
	var t := smoothstep(0.02, 0.55, elev)
	var warm := Color(1.0, 0.6, 0.36)
	var noon := Color(1.0, 0.95, 0.86)
	return {"color": warm.lerp(noon, t), "energy": lerpf(0.55, SUN_DAY_ENERGY, smoothstep(0.0, 0.35, elev)), "elevation": elev}

## Pure: fog density at a world position. Coast humid, alpine clear.
static func haze_for(pos: Vector3) -> float:
	var coast := TerrainBaker.coast_weight(pos.x, pos.z)
	var alpine := smoothstep(400.0, 1200.0, pos.y)
	return FOG_DENSITY * (1.0 + 0.6 * coast) * (1.0 - 0.45 * alpine)

func apply_static() -> void:
	if environment == null:
		return
	environment.adjustment_enabled = true
	environment.adjustment_contrast = ADJ_CONTRAST
	environment.adjustment_saturation = ADJ_SATURATION
	environment.adjustment_brightness = ADJ_BRIGHTNESS
	environment.fog_density = FOG_DENSITY
	environment.fog_light_color = FOG_COLOR
	var sky_mat := environment.sky.sky_material as PhysicalSkyMaterial if environment.sky != null else null
	if sky_mat != null:
		sky_mat.turbidity = SKY_TURBIDITY
		sky_mat.rayleigh_coefficient = SKY_RAYLEIGH
		sky_mat.mie_coefficient = SKY_MIE
		sky_mat.ground_color = SKY_GROUND

func set_world_detail(level: int) -> void:
	detail = clampi(level, 0, 2)
	if _cloud != null:
		_cloud.visible = detail >= 1
		if _cloud_mat != null:
			_cloud_mat.set_shader_parameter("octaves", 2 if detail >= 1 else 1)

func _process(_delta: float) -> void:
	_update(false)
	if _cloud != null and _cloud.visible:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_cloud.global_position = cam.global_position

func _update(force: bool) -> void:
	var hour: float = WeatherManager.get_time_of_day() if WeatherManager.has_method("get_time_of_day") else 12.0
	if force or absf(hour - _last_hour) > HOUR_EPSILON:
		_last_hour = hour
		var g := sun_grade(hour)
		if sun != null:
			sun.light_color = g["color"]
			sun.light_energy = g["energy"]
		if _cloud_mat != null:
			var c: Color = g["color"]
			var day := clampf(float(g["elevation"]) * 4.0, 0.15, 1.0)
			_cloud_mat.set_shader_parameter("lit_color", Color(c.r * day, c.g * day, c.b * day))
			_cloud_mat.set_shader_parameter("shade_color", Color(0.62 * day, 0.67 * day, 0.76 * day))
			_cloud_mat.set_shader_parameter("sun_dir", WorldDriver.sun_direction(hour))
	if environment != null and player != null:
		var haze := haze_for(player.global_position)
		if absf(haze - _last_haze) > FOG_DENSITY * 0.05:
			_last_haze = haze
			environment.fog_density = haze

func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = SEA_SIZE
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sea_water.gdshader") as Shader
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	n.fractal_octaves = 3
	nt.noise = n
	mat.set_shader_parameter("wave_normal", nt)
	_sea = MeshInstance3D.new()
	_sea.name = "Sea"
	_sea.mesh = plane
	_sea.material_override = mat
	_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sea)
	_sea.global_position = Vector3(SEA_CENTER.x, 0.0, SEA_CENTER.y)

func _build_clouds() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = CLOUD_RADIUS
	sphere.height = CLOUD_RADIUS * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	sphere.is_hemisphere = true
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = load("res://shaders/cloud_layer.gdshader") as Shader
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.008
	n.fractal_octaves = 5
	n.seed = 2026
	nt.noise = n
	_cloud_mat.set_shader_parameter("cloud_noise", nt)
	_cloud = MeshInstance3D.new()
	_cloud.name = "CloudLayer"
	_cloud.mesh = sphere
	_cloud.material_override = _cloud_mat
	_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cloud.top_level = true
	# The sphere follows the camera; never frustum-cull it away.
	_cloud.extra_cull_margin = CLOUD_RADIUS
	add_child(_cloud)
	set_world_detail(detail)
