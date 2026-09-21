# tests/suites/test_quality_ladder.gd
extends GdUnitTestSuite

## Graphics-gap ladder gate (docs/plans/graphics_gap_plan.md items 4 + 8):
## the SSAO/SDFGI tuning applied per preset for a GT7-style contact-shading
## look, plus the Low AA/scaling change so the default preset stops aliasing.
## Complements test_settings_presets (preset tables + mixed application) with
## AO/GI-value bands and the GPU-name default seam.

const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for obj in _managed:
		if obj is Node and is_instance_valid(obj):
			obj.free()
	_managed.clear()

## (a) Low: cheap preset keeps AO/GI/glow off but MSAA on so it stops
## aliasing; scaling stays bilinear 1.0 (unchanged from the old ladder).
func test_low_has_msaa_on_and_feature_effects_off() -> void:
	var preset: Dictionary = SettingsMenuScript.preset_for(0)
	assert_that(preset["msaa_3d"]).is_greater_equal(2)
	assert_that(preset["ssao_enabled"]).is_false()
	assert_that(preset["sdfgi_enabled"]).is_false()
	assert_that(preset["ssr_enabled"]).is_false()
	assert_that(preset["glow_enabled"]).is_false()
	assert_that(preset["scaling_3d_mode"]).is_equal(0)
	assert_that(preset["scaling_3d_scale"]).is_equal_approx(1.0, 0.001)

## (b) Medium: SSAO carries the GT7 contact-shading knobs (tight radius AO on
## the car-to-ground gap), SDFGI stays on with its defaults.
func test_medium_has_tuned_ssao_and_sdfgi_on() -> void:
	var preset: Dictionary = SettingsMenuScript.preset_for(1)
	assert_that(preset["ssao_enabled"]).is_true()
	assert_that(preset["ssao_intensity"]).is_between(1.5, 2.5)
	assert_that(preset["ssao_radius"]).is_between(0.03, 0.08)
	assert_that(preset["ssao_ao_channel_affect"]).is_between(0.05, 0.2)
	assert_that(preset["sdfgi_enabled"]).is_true()
	assert_that(preset.has("sdfgi_energy")).is_false()

## (c) High: full stack — SSAO knobs, SDFGI energy 0.8, SSR + glow on, and
## FSR 2.2 scaling (mode 1, 0.9) instead of MSAA.
func test_high_has_full_stack_with_sdfgi_energy_and_fsr() -> void:
	var preset: Dictionary = SettingsMenuScript.preset_for(2)
	assert_that(preset["ssao_enabled"]).is_true()
	assert_that(preset["ssao_intensity"]).is_between(1.5, 2.5)
	assert_that(preset["ssao_radius"]).is_between(0.03, 0.08)
	assert_that(preset["ssao_ao_channel_affect"]).is_between(0.05, 0.2)
	assert_that(preset["sdfgi_enabled"]).is_true()
	assert_that(preset["sdfgi_energy"]).is_between(0.7, 0.9)
	assert_that(preset["ssr_enabled"]).is_true()
	assert_that(preset["glow_enabled"]).is_true()
	assert_that(preset["msaa_3d"]).is_equal(0)
	assert_that(preset["scaling_3d_mode"]).is_equal(1)
	assert_that(preset["scaling_3d_scale"]).is_equal_approx(0.9, 0.001)

## (d) Default preset decision: the /graphics-gap rig's "GeForce GTX 970"
## resolves to Low via _legacy_geforce (expected — documented in
## settings_menu.gd), modern discrete cards resolve to Medium.
func test_default_preset_for_legacy_geforce_is_low() -> void:
	assert_that(SettingsMenuScript._legacy_geforce("geforce gtx 970")).is_true()
	assert_that(SettingsMenuScript.preset_for_adapter_name("GeForce GTX 970")).is_equal(0)
	assert_that(SettingsMenuScript.preset_for_adapter_name("NVIDIA GeForce RTX 3060")).is_equal(1)
	assert_that(SettingsMenuScript.preset_for_adapter_name("AMD Radeon RX 5700 XT")).is_equal(1)
	assert_that(SettingsMenuScript.preset_for_adapter_name("Intel UHD Graphics 630")).is_equal(0)

## (e) Applying the Medium preset lands the tuned AO knobs and keeps SDFGI on
## (default energy untouched) without error on a fresh Environment.
func test_apply_medium_lands_ao_knobs() -> void:
	var env := Environment.new()
	_managed.append(env)
	SettingsMenuScript.apply_quality_preset(env, null, SettingsMenuScript.preset_for(1))
	assert_that(env.ssao_enabled).is_true()
	assert_that(env.ssao_intensity).is_between(1.5, 2.5)
	assert_that(env.ssao_radius).is_between(0.03, 0.08)
	assert_that(env.ssao_ao_channel_affect).is_between(0.05, 0.2)
	assert_that(env.sdfgi_enabled).is_true()

## (e2) Applying the High preset lands SDFGI energy + cascade distance, SSR and
## glow, and the FSR viewport mapping.
func test_apply_high_lands_gi_energy_and_fsr() -> void:
	var env := Environment.new()
	var viewport: SubViewport = SubViewport.new()
	_managed.append(env)
	_managed.append(viewport)
	SettingsMenuScript.apply_quality_preset(env, viewport, SettingsMenuScript.preset_for(2))
	assert_that(env.ssao_enabled).is_true()
	assert_that(env.sdfgi_enabled).is_true()
	assert_that(env.sdfgi_energy).is_between(0.7, 0.9)
	assert_that(env.sdfgi_cascade0_distance).is_greater_equal(14.0)
	assert_that(env.ssr_enabled).is_true()
	assert_that(env.glow_enabled).is_true()
	assert_that(viewport.msaa_3d).is_equal(Viewport.MSAA_DISABLED)
	assert_that(viewport.scaling_3d_mode).is_equal(Viewport.SCALING_3D_MODE_FSR2)
	assert_that(viewport.scaling_3d_scale).is_equal_approx(0.9, 0.001)

## (e3) Applying the Low preset on a fresh Environment runs the AO/GI path
## without error (both branches disabled) and the viewport gets MSAA.
func test_apply_low_runs_clean_with_msaa() -> void:
	var env := Environment.new()
	var viewport: SubViewport = SubViewport.new()
	_managed.append(env)
	_managed.append(viewport)
	SettingsMenuScript.apply_quality_preset(env, viewport, SettingsMenuScript.preset_for(0))
	assert_that(env.ssao_enabled).is_false()
	assert_that(env.sdfgi_enabled).is_false()
	assert_that(viewport.msaa_3d).is_equal(Viewport.MSAA_4X)