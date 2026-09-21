# tests/suites/test_settings_presets.gd
extends GdUnitTestSuite

## Quality-settings ladder (Task 3): preset tables, unknown-index fallback,
## and the static apply_quality_preset helper against a fresh Environment +
## Viewport. Tests the settings_menu script directly — no scene instantiated.

const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

const REQUIRED_KEYS: Array = [
	"ssao_enabled",
	"glow_enabled",
	"volumetric_fog_enabled",
	"ssr_enabled",
	"sdfgi_enabled",
	"msaa_3d",
	"tonemap_mode",
	"probe_enabled",
	"scaling_3d_mode",
	"scaling_3d_scale",
]

const ACES: int = Environment.TONE_MAPPER_ACES

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for obj in _managed:
		if obj is Node and is_instance_valid(obj):
			obj.free()
	_managed.clear()

func test_every_preset_has_all_required_keys() -> void:
	for index in SettingsMenuScript.QUALITY_PRESETS:
		var preset: Dictionary = SettingsMenuScript.preset_for(index)
		for key in REQUIRED_KEYS:
			assert_that(preset.has(key)).is_true()

func test_low_preset_spot_check() -> void:
	var preset: Dictionary = SettingsMenuScript.preset_for(0)
	assert_that(preset["ssao_enabled"]).is_false()
	assert_that(preset["glow_enabled"]).is_false()
	assert_that(preset["volumetric_fog_enabled"]).is_false()
	assert_that(preset["ssr_enabled"]).is_false()
	assert_that(preset["sdfgi_enabled"]).is_false()
	assert_that(preset["tonemap_mode"]).is_equal(ACES)
	# Plan item 8: Low gained MSAA (2 = MSAA_4X) to stop aliasing; the old
	# msaa_3d==0 passthrough assertion was updated deliberately to match.
	assert_that(preset["msaa_3d"]).is_greater_equal(2)
	assert_that(preset["probe_enabled"]).is_false()
	assert_that(preset["scaling_3d_mode"]).is_equal(0)
	assert_that(preset["scaling_3d_scale"]).is_equal_approx(1.0, 0.001)

func test_medium_preset_spot_check() -> void:
	var preset: Dictionary = SettingsMenuScript.preset_for(1)
	assert_that(preset["ssao_enabled"]).is_true()
	assert_that(preset["glow_enabled"]).is_true()
	assert_that(preset["volumetric_fog_enabled"]).is_false()
	assert_that(preset["ssr_enabled"]).is_false()
	assert_that(preset["sdfgi_enabled"]).is_true()
	assert_that(preset["tonemap_mode"]).is_equal(ACES)
	assert_that(preset["msaa_3d"]).is_equal(2)
	assert_that(preset["probe_enabled"]).is_false()
	assert_that(preset["scaling_3d_mode"]).is_equal(0)
	assert_that(preset["scaling_3d_scale"]).is_equal_approx(1.0, 0.001)

func test_high_preset_spot_check() -> void:
	var preset: Dictionary = SettingsMenuScript.preset_for(2)
	assert_that(preset["ssao_enabled"]).is_true()
	assert_that(preset["glow_enabled"]).is_true()
	assert_that(preset["volumetric_fog_enabled"]).is_true()
	assert_that(preset["ssr_enabled"]).is_true()
	assert_that(preset["sdfgi_enabled"]).is_true()
	assert_that(preset["tonemap_mode"]).is_equal(ACES)
	assert_that(preset["msaa_3d"]).is_equal(0)
	assert_that(preset["probe_enabled"]).is_true()
	assert_that(preset["scaling_3d_mode"]).is_equal(1)
	assert_that(preset["scaling_3d_scale"]).is_equal_approx(0.9, 0.001)

func test_preset_for_one_matches_medium_defaults() -> void:
	var preset: Dictionary = SettingsMenuScript.preset_for(1)
	assert_that(preset["ssao_enabled"]).is_true()
	assert_that(preset["glow_enabled"]).is_true()
	assert_that(preset["sdfgi_enabled"]).is_true()
	assert_that(preset["volumetric_fog_enabled"]).is_false()
	assert_that(preset["tonemap_mode"]).is_equal(ACES)

func test_preset_for_unknown_index_falls_back_to_medium() -> void:
	var preset: Dictionary = SettingsMenuScript.preset_for(99)
	var medium: Dictionary = SettingsMenuScript.preset_for(1)
	assert_that(preset).is_equal(medium)

func test_apply_high_preset_sets_env_and_viewport() -> void:
	var env := Environment.new()
	var viewport: SubViewport = SubViewport.new()
	_managed.append(env)
	_managed.append(viewport)
	SettingsMenuScript.apply_quality_preset(env, viewport, SettingsMenuScript.preset_for(2))
	assert_that(env.volumetric_fog_enabled).is_true()
	assert_that(env.ssr_enabled).is_true()
	assert_that(env.sdfgi_enabled).is_true()
	assert_that(env.ssao_enabled).is_true()
	assert_that(env.glow_enabled).is_true()
	assert_that(env.tonemap_mode).is_equal(ACES)
	assert_that(viewport.msaa_3d).is_equal(Viewport.MSAA_DISABLED)
	assert_that(viewport.scaling_3d_mode).is_equal(Viewport.SCALING_3D_MODE_FSR2)
	assert_that(viewport.scaling_3d_scale).is_equal_approx(0.9, 0.001)

func test_fresh_environment_defaults_differ_from_high() -> void:
	var env := Environment.new()
	_managed.append(env)
	assert_that(env.volumetric_fog_enabled).is_false()
	assert_that(env.ssr_enabled).is_false()
	assert_that(env.sdfgi_enabled).is_false()
	assert_that(env.ssao_enabled).is_false()
	assert_that(env.tonemap_mode).is_equal(Environment.TONE_MAPPER_LINEAR)

func test_apply_low_preset_flips_values() -> void:
	var env := Environment.new()
	var viewport: SubViewport = SubViewport.new()
	_managed.append(env)
	_managed.append(viewport)
	SettingsMenuScript.apply_quality_preset(env, viewport, SettingsMenuScript.preset_for(0))
	assert_that(env.ssao_enabled).is_false()
	assert_that(env.glow_enabled).is_false()
	assert_that(env.volumetric_fog_enabled).is_false()
	assert_that(env.ssr_enabled).is_false()
	assert_that(env.sdfgi_enabled).is_false()
	assert_that(env.tonemap_mode).is_equal(ACES)
	# Plan item 8: Low applies MSAA_4X (was MSAA_DISABLED) to kill aliasing.
	assert_that(viewport.msaa_3d).is_equal(Viewport.MSAA_4X)
	assert_that(viewport.scaling_3d_mode).is_equal(Viewport.SCALING_3D_MODE_BILINEAR)
	assert_that(viewport.scaling_3d_scale).is_equal_approx(1.0, 0.001)

func test_apply_medium_maps_msaa_to_4x_and_no_scaling() -> void:
	var env := Environment.new()
	var viewport: SubViewport = SubViewport.new()
	_managed.append(env)
	_managed.append(viewport)
	SettingsMenuScript.apply_quality_preset(env, viewport, SettingsMenuScript.preset_for(1))
	assert_that(viewport.msaa_3d).is_equal(Viewport.MSAA_4X)
	assert_that(viewport.scaling_3d_mode).is_equal(Viewport.SCALING_3D_MODE_BILINEAR)
	assert_that(viewport.scaling_3d_scale).is_equal_approx(1.0, 0.001)

func test_apply_quality_preset_tolerates_null_env_and_viewport() -> void:
	SettingsMenuScript.apply_quality_preset(null, null, SettingsMenuScript.preset_for(1))
	assert_that(true).is_true()

func test_default_quality_preset_is_within_ladder_bounds() -> void:
	var index: int = SettingsMenuScript.default_quality_preset()
	assert_that(index).is_greater_equal(0)
	assert_that(index).is_less_equal(2)

func test_find_scene_environment_locates_world_environment() -> void:
	var root := Node.new()
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	root.add_child(we)
	_managed.append(root)
	_managed.append(we.environment)
	var env: Environment = SettingsMenuScript.find_scene_environment(root)
	assert_that(env).is_not_null()
	assert_that(SettingsMenuScript.find_scene_environment(null)).is_null()

func test_apply_to_scene_tree_pushes_preset_onto_scene_env() -> void:
	var root := Node.new()
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	root.add_child(we)
	var viewport: SubViewport = SubViewport.new()
	_managed.append(root)
	_managed.append(we.environment)
	_managed.append(viewport)
	SettingsMenuScript.apply_to_scene_tree(2, root, viewport)
	assert_that(we.environment.ssao_enabled).is_true()
	assert_that(we.environment.glow_enabled).is_true()
	assert_that(we.environment.volumetric_fog_enabled).is_true()
	assert_that(we.environment.ssr_enabled).is_true()
	assert_that(we.environment.sdfgi_enabled).is_true()
	assert_that(viewport.msaa_3d).is_equal(Viewport.MSAA_DISABLED)
	SettingsMenuScript.apply_to_scene_tree(0, root, viewport)
	assert_that(we.environment.ssao_enabled).is_false()
	assert_that(we.environment.glow_enabled).is_false()
	assert_that(we.environment.volumetric_fog_enabled).is_false()
	assert_that(we.environment.ssr_enabled).is_false()
	assert_that(we.environment.sdfgi_enabled).is_false()