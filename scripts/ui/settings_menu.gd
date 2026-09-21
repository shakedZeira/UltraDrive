# scripts/ui/settings_menu.gd
extends Control

## Settings menu: video quality, audio, controls.

@onready var quality_option: OptionButton = %QualityOption
@onready var volume_slider: HSlider = %VolumeSlider
@onready var transmission_option: OptionButton = %TransmissionOption

## Quality ladder shared by the settings menu and the test suite. Each preset
## is applied to the current scene Environment + root Viewport.
##
## AO/GI pass (docs/plans/graphics_gap_plan.md items 4 + 8): Medium and High
## carry the GT7-style contact-shading knobs — tight SSAO radius so the
## car-to-ground gap darkens without broad flat AO; High additionally tunes
## SDFGI energy down to 0.8 so bounce light reads against the GG-Env
## tonemap_exposure 0.9. Low keeps AO/GI off for perf but gains MSAA (2 in
## project-settings units → Viewport.MSAA_4X) so it stops aliasing, keeping
## scaling bilinear 1.0.
const QUALITY_PRESETS: Dictionary = {
	0: {
		"ssao_enabled": false,
		"glow_enabled": false,
		"volumetric_fog_enabled": false,
		"ssr_enabled": false,
		"sdfgi_enabled": false,
		"msaa_3d": 2,
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"probe_enabled": false,
		"scaling_3d_mode": 0,
		"scaling_3d_scale": 1.0,
	},
	1: {
		"ssao_enabled": true,
		"glow_enabled": true,
		"volumetric_fog_enabled": false,
		"ssr_enabled": false,
		"sdfgi_enabled": true,
		"msaa_3d": 2,
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"probe_enabled": false,
		"scaling_3d_mode": 0,
		"scaling_3d_scale": 1.0,
		"ssao_intensity": 2.0,
		"ssao_radius": 0.05,
		"ssao_ao_channel_affect": 0.1,
	},
	2: {
		"ssao_enabled": true,
		"glow_enabled": true,
		"volumetric_fog_enabled": true,
		"ssr_enabled": true,
		"sdfgi_enabled": true,
		"msaa_3d": 0,
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"probe_enabled": true,
		"scaling_3d_mode": 1,
		"scaling_3d_scale": 0.9,
		"ssao_intensity": 2.0,
		"ssao_radius": 0.05,
		"ssao_ao_channel_affect": 0.1,
		"sdfgi_energy": 0.8,
		# 4.7.2 has no sdfgi_cascaded_distance; the closest property is
		# sdfgi_cascade0_distance (default 12.8) — stretch it a touch so the
		# first cascade covers the car + immediate roadside.
		"sdfgi_cascade0_distance": 16.0,
	},
}

static func preset_for(index: int) -> Dictionary:
	if QUALITY_PRESETS.has(index):
		return QUALITY_PRESETS[index]
	return QUALITY_PRESETS[1]

## The probe_enabled flag carried by the preset ladder (High=true,
## Low/Medium=false), unknown indices falling back to the medium preset.
## Drives the per-car ReflectionProbe through GameState.set_probe_enabled().
static func probe_enabled_for(index: int) -> bool:
	var preset: Dictionary = preset_for(index)
	return bool(preset["probe_enabled"])

## First-boot preset for the current GPU: integral/weak adapters (Vega-less
## AMD iGPU, Intel UHD/HD, VGA/llvmpipe fallbacks) start on Low so the game is
## playable out of the box; discrete cards get Medium. The user can always
## raise/lower it in Settings — this is only the no-save default.
static func default_quality_preset() -> int:
	return preset_for_adapter_name(RenderingServer.get_video_adapter_name())

## Test-friendly seam for the GPU-name → preset decision (no server reads).
## The /graphics-gap captures were recorded on this rig by a "GeForce GTX 970":
## _legacy_geforce() matches below, so default is Low there. That is the
## expected hardware-recommended default, not a bug — it just means the
## reference look (SSAO/SDFGI/SSR ao High) is only reached by raising to
## Medium/High, not by the first-boot preset.
static func preset_for_adapter_name(adapter: String) -> int:
	var name: String = adapter.to_lower()
	if name.is_empty():
		return 1
	var weak_gpu := (
		("radeon" in name and "rx" not in name)
		or "uhd graphics" in name
		or "intel hd" in name
		or "iris" in name
		or "vga" in name
		or "llvmpipe" in name
		or "swrast" in name
		or _legacy_geforce(name)
	)
	return 0 if weak_gpu else 1

static func _legacy_geforce(name: String) -> bool:
	var gtx := name.find("gtx")
	if gtx < 0:
		return false
	gtx += 3
	while gtx < name.length() and not _is_digit_char(name[gtx]):
		gtx += 1
	if gtx >= name.length():
		return true
	return name[gtx] != "1"

static func _is_digit_char(ch: String) -> bool:
	return ch >= "0" and ch <= "9"

## Finds the first WorldEnvironment under a loaded scene and returns its
## Environment resource (or null when the scene has none).
static func find_scene_environment(root: Node) -> Environment:
	if root == null:
		return null
	for we_node: Node in root.find_children("*", "WorldEnvironment", true, false):
		var we := we_node as WorldEnvironment
		if we and we.environment:
			return we.environment
	return null

## Auto-apply entry point: pushes the ladder preset onto a loaded scene's
## environment + the given viewport. Used by GameState on boot and on every
## scene transition so scenes honor the saved choice instead of their baked
## max-quality environment. Mirrors the live settings-menu path.
static func apply_to_scene_tree(preset_index: int, scene_root: Node, viewport: Viewport) -> void:
	var env := find_scene_environment(scene_root)
	apply_quality_preset(env, viewport, preset_for(preset_index))

static func apply_quality_preset(env: Environment, viewport: Viewport, preset: Dictionary) -> void:
	if env:
		env.ssao_enabled = preset["ssao_enabled"]
		env.glow_enabled = preset["glow_enabled"]
		env.volumetric_fog_enabled = preset["volumetric_fog_enabled"]
		env.ssr_enabled = preset["ssr_enabled"]
		env.sdfgi_enabled = preset["sdfgi_enabled"]
		env.tonemap_mode = preset["tonemap_mode"]
		env.tonemap_exposure = 0.9
		env.glow_intensity = 0.4
		env.glow_strength = 0.8
		env.glow_bloom = 0.6 if preset["glow_enabled"] else 0.1
		env.ambient_light_color = Color(0.6, 0.62, 0.7)
		env.ambient_light_energy = 1.0
		# GT7-style contact shading (plan item 4): tight-radius AO darkens the
		# car-to-ground gap instead of broad flat AO. Only presets that enable
		# SSAO carry the knobs (Low keeps them off).
		if preset["ssao_enabled"]:
			env.ssao_intensity = float(preset.get("ssao_intensity", 2.0))
			env.ssao_radius = float(preset.get("ssao_radius", 0.05))
			env.ssao_ao_channel_affect = float(preset.get("ssao_ao_channel_affect", 0.1))
		# Bounced sky light into under-car + foliage (plan item 4, tuned on High
		# only; Medium keeps SDFGI defaults). 4.7.2 ships sdfgi_cascade0_distance
		# / sdfgi_max_distance instead of a single sdfgi_cascaded_distance.
		if preset["sdfgi_enabled"]:
			if preset.has("sdfgi_energy"):
				env.sdfgi_energy = float(preset["sdfgi_energy"])
			if preset.has("sdfgi_cascade0_distance"):
				env.sdfgi_cascade0_distance = float(preset["sdfgi_cascade0_distance"])
	if viewport:
		viewport.msaa_3d = _msaa_enum_for(preset["msaa_3d"])
		viewport.scaling_3d_mode = _scaling_mode_for(preset["scaling_3d_mode"])
		var scale: float = preset["scaling_3d_scale"]
		viewport.scaling_3d_scale = clampf(scale, 0.5, 2.0)

## Maps the project-settings msaa_3d units (0=off/1=2x/2=4x/3=8x) to the
## Viewport.MSAA enum. The old dead "msaa" caps at 4x; anything out of range
## falls back to disabled.
static func _msaa_enum_for(level: int) -> Viewport.MSAA:
	match level:
		3:
			return Viewport.MSAA_8X
		2:
			return Viewport.MSAA_4X
		1:
			return Viewport.MSAA_2X
		_:
			return Viewport.MSAA_DISABLED

## Preset scaling mode: 0 = bilinear (scale 1.0 = effectively off),
## 1 = FSR 2.2. Note SCALING_3D_MODE_FSR2 is enum value 2, not 1.
static func _scaling_mode_for(mode: int) -> Viewport.Scaling3DMode:
	if mode == 1:
		return Viewport.SCALING_3D_MODE_FSR2
	return Viewport.SCALING_3D_MODE_BILINEAR

func _ready() -> void:
	quality_option.add_item("Low", 0)
	quality_option.add_item("Medium", 1)
	quality_option.add_item("High", 2)
	quality_option.select(GameState.quality_preset)
	quality_option.item_selected.connect(_on_quality_selected)
	volume_slider.value_changed.connect(_on_volume_changed)
	transmission_option.add_item("Automatic")
	transmission_option.add_item("Manual")
	transmission_option.select(GameState.transmission_mode)
	transmission_option.item_selected.connect(_on_transmission_selected)

func _on_quality_selected(index: int) -> void:
	var preset: Dictionary = preset_for(index)
	var viewport: Viewport = get_viewport()
	var env: Environment = null
	var world_env: WorldEnvironment = viewport.world_environment
	if world_env:
		env = world_env.environment
	apply_quality_preset(env, viewport, preset)
	GameState.set_quality_preset(index)
	GameState.set_probe_enabled(probe_enabled_for(index))

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))

func _on_transmission_selected(index: int) -> void:
	if index == 1:
		GameState.set_transmission_mode(GameState.TransmissionMode.MANUAL)
	else:
		GameState.set_transmission_mode(GameState.TransmissionMode.AUTO)

func _on_back_pressed() -> void:
	SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")