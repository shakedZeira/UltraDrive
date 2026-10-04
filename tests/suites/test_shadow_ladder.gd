# tests/suites/test_shadow_ladder.gd
extends GdUnitTestSuite

## DirectionalLight3D shadow-cascade ladder — fh5_optimization_plan.md item 3
## (P0-3). Before this the three presets carried NO shadow keys at all, so Low,
## Medium and High all rendered identical shadows.
##
## THE PLAN'S API IS WRONG FOR THIS ENGINE, and this suite pins the real one.
## The plan (and the task brief) name `shadow_cascade_count`, `shadow_max_distance`
## and `shadow_resolution`. Verified against ClassDB on 4.7.2:
##   * `shadow_cascade_count` does NOT exist. The cascade count is expressed as
##     `directional_shadow_mode` (int): SHADOW_ORTHOGONAL = 1 cascade,
##     SHADOW_PARALLEL_2_SPLITS = 2, SHADOW_PARALLEL_4_SPLITS = 4.
##   * `shadow_max_distance` does NOT exist. It is `directional_shadow_max_distance`.
##   * `shadow_resolution` does NOT exist on DirectionalLight3D AT ALL (not even
##     inherited from Light3D). Directional shadow resolution is the project
##     setting `rendering/lights_and_shadows/directional_shadow/size` (2048 here),
##     read by the rendering server at startup — there is no per-light handle and
##     project.godot is out of scope for this item. The ladder therefore DECLARES
##     shadow_resolution (1024/2048/2048) and applies it through a guarded no-op.
##   * `shadow_fade_start` is `directional_shadow_fade_start`, and it is a 0..1
##     FRACTION of max_distance, not metres.
##   * `shadow_opacity` does exist, on the Light3D base class.
##
## Lights are built in code (no scene dependency) and freed in after_test so the
## suite stays orphan-free, mirroring test_weather_sun.gd / test_settings_presets.gd.

const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

## The four shadow keys every preset must declare. shadow_fade_start /
## shadow_opacity are the extra far-plane softening from the same item.
const SHADOW_KEYS: Array = [
	"shadow_cascade_count",
	"shadow_max_distance",
	"shadow_resolution",
	"shadow_fade_start",
	"shadow_opacity",
]

## The plan's table, verbatim: [cascade_count, max_distance, resolution].
const EXPECTED_TABLE: Dictionary = {
	0: [1, 20.0, 1024],
	1: [2, 50.0, 2048],
	2: [4, 100.0, 2048],
}

## Engine default max distance, used to prove a preset actually overwrote it.
const ENGINE_DEFAULT_MAX_DISTANCE := 100.0

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for obj in _managed:
		if obj is Node and is_instance_valid(obj):
			obj.free()
	_managed.clear()

## Builds a scene root with one real, rendering directional light under it so
## find_scene_directional_light has something to find. Only the root is
## managed: freeing it frees the sun too, so managing both would double-free.
func _root_with_sun() -> Array:
	var root := Node.new()
	var holder := Node3D.new()
	root.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	holder.add_child(sun)
	_managed.append(root)
	return [root, sun]

func _bare_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	_managed.append(sun)
	return sun

# --- (a) the ladder declares the shadow keys ---------------------------------

## (a) Every preset declares every shadow key — the whole point of the item,
## since before it none of them did.
func test_every_preset_declares_the_shadow_keys() -> void:
	for index in [0, 1, 2]:
		var preset: Dictionary = SettingsMenuScript.preset_for(index)
		for key in SHADOW_KEYS:
			assert_that(preset.has(key)).override_failure_message(
				"preset %d is missing shadow key %s" % [index, key]).is_true()

## (b) Values match the plan's table exactly.
func test_preset_shadow_values_match_the_plan_table() -> void:
	for index in [0, 1, 2]:
		var preset: Dictionary = SettingsMenuScript.preset_for(index)
		var row: Array = EXPECTED_TABLE[index]
		assert_that(preset["shadow_cascade_count"]).override_failure_message(
			"preset %d cascade count" % index).is_equal(row[0])
		assert_that(float(preset["shadow_max_distance"])).override_failure_message(
			"preset %d max distance" % index).is_equal_approx(row[1], 0.001)
		assert_that(preset["shadow_resolution"]).override_failure_message(
			"preset %d resolution" % index).is_equal(row[2])

## (c) The far-plane softening: High must not fade inside its own 100 m range
## (fade_start 1.0) and Low must fade early (well under half the distance), so
## cutting max_distance to 20 m does not pop.
func test_fade_start_is_a_fraction_that_rises_with_the_preset() -> void:
	var low: Dictionary = SettingsMenuScript.preset_for(0)
	var medium: Dictionary = SettingsMenuScript.preset_for(1)
	var high: Dictionary = SettingsMenuScript.preset_for(2)
	assert_that(float(high["shadow_fade_start"])).is_equal_approx(1.0, 0.001)
	assert_that(float(medium["shadow_fade_start"])).is_between(0.3, 0.8)
	assert_that(float(low["shadow_fade_start"])).is_less(0.5)
	# Monotone: more distance covered, later the fade starts.
	assert_that(float(low["shadow_fade_start"])).is_less(float(medium["shadow_fade_start"]))
	assert_that(float(medium["shadow_fade_start"])).is_less(float(high["shadow_fade_start"]))
	# Opacity softens the same cut, and High stays fully solid.
	assert_that(float(high["shadow_opacity"])).is_equal_approx(1.0, 0.001)
	assert_that(float(low["shadow_opacity"])).is_less(1.0)
	assert_that(float(low["shadow_opacity"])).is_greater(0.0)

# --- (d) unknown index still resolves -----------------------------------------

## (d) An unknown preset index still falls back to Medium, shadow keys included —
## the fallback is the whole preset dict, not a stripped copy.
func test_unknown_index_falls_back_to_medium_with_shadow_keys() -> void:
	var fallback: Dictionary = SettingsMenuScript.preset_for(99)
	var medium: Dictionary = SettingsMenuScript.preset_for(1)
	assert_that(fallback).is_equal(medium)
	for key in SHADOW_KEYS:
		assert_that(fallback.has(key)).is_true()
	assert_that(fallback["shadow_cascade_count"]).is_equal(2)
	assert_that(float(fallback["shadow_max_distance"])).is_equal_approx(50.0, 0.001)

# --- (e) applying to a real DirectionalLight3D --------------------------------

## (e1) The headline: applying a preset to a real DirectionalLight3D writes the
## cascade count (as directional_shadow_mode), the max distance and the fade.
func test_apply_writes_cascades_max_distance_and_fade_onto_a_real_light() -> void:
	var sun := _bare_sun()
	# Start from values no preset produces so every assertion is a real write.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = ENGINE_DEFAULT_MAX_DISTANCE

	SettingsMenuScript.apply_quality_preset(null, null, SettingsMenuScript.preset_for(0), sun)
	assert_that(sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_that(sun.directional_shadow_max_distance).is_equal_approx(20.0, 0.001)
	assert_that(sun.directional_shadow_fade_start).is_equal_approx(0.25, 0.001)
	assert_that(sun.shadow_opacity).is_equal_approx(0.75, 0.001)

	SettingsMenuScript.apply_quality_preset(null, null, SettingsMenuScript.preset_for(1), sun)
	assert_that(sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	assert_that(sun.directional_shadow_max_distance).is_equal_approx(50.0, 0.001)

	SettingsMenuScript.apply_quality_preset(null, null, SettingsMenuScript.preset_for(2), sun)
	assert_that(sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_that(sun.directional_shadow_max_distance).is_equal_approx(100.0, 0.001)
	assert_that(sun.directional_shadow_fade_start).is_equal_approx(1.0, 0.001)
	assert_that(sun.shadow_opacity).is_equal_approx(1.0, 0.001)

## (e2) The cascade-count -> ShadowMode mapping is the whole contract, asserted
## directly so a rename cannot silently turn every preset into 4 cascades.
func test_shadow_mode_for_maps_counts_onto_the_engine_enum() -> void:
	assert_that(SettingsMenuScript._shadow_mode_for(1)).is_equal(DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_that(SettingsMenuScript._shadow_mode_for(2)).is_equal(DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	assert_that(SettingsMenuScript._shadow_mode_for(4)).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	# Out-of-range counts degrade to the 4-split mode rather than erroring.
	assert_that(SettingsMenuScript._shadow_mode_for(0)).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_that(SettingsMenuScript._shadow_mode_for(99)).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)

## (e3) RESOLUTION IS NOT REACHABLE PER-LIGHT on 4.7.2 — this pins that finding
## instead of pretending the ladder value was applied. DirectionalLight3D has no
## `shadow_resolution` property at all (verified via ClassDB); the size comes
## from `rendering/lights_and_shadows/directional_shadow/size`. So the declared
## ladder value is documented-only and the guarded writer must be a silent
## no-op rather than an error.
func test_shadow_resolution_is_a_project_setting_not_a_per_light_property() -> void:
	var sun := _bare_sun()
	var has_property := false
	for entry: Dictionary in sun.get_property_list():
		if String(entry["name"]) == "shadow_resolution":
			has_property = true
	assert_that(has_property).is_false()
	var project_size: int = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")
	assert_that(project_size).is_equal(2048)
	# The guarded writer must run clean and leave the light untouched.
	SettingsMenuScript._set_shadow_resolution_if_supported(sun, 1024)
	assert_that(sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_that(true).is_true()

## (e4) A legacy/hand-edited preset dict missing the shadow keys must not crash
## the boot path — apply_quality_preset reads the new keys with .get(default).
func test_legacy_preset_without_shadow_keys_falls_back_to_defaults() -> void:
	var sun := _bare_sun()
	var legacy: Dictionary = SettingsMenuScript.preset_for(1).duplicate()
	for key in SHADOW_KEYS:
		legacy.erase(key)
	SettingsMenuScript.apply_quality_preset(null, null, legacy, sun)
	assert_that(sun.directional_shadow_max_distance).is_equal_approx(ENGINE_DEFAULT_MAX_DISTANCE, 0.001)
	assert_that(sun.directional_shadow_fade_start).is_equal_approx(0.8, 0.001)
	assert_that(sun.shadow_opacity).is_equal_approx(1.0, 0.001)

# --- (f) scene walk + the clock invariant --------------------------------------

## (f1) find_scene_directional_light mirrors find_scene_environment's shape and
## tolerates a scene with no sun at all.
func test_find_scene_directional_light_locates_the_sun() -> void:
	var built := _root_with_sun()
	var root: Node = built[0]
	var sun: DirectionalLight3D = built[1]
	assert_that(SettingsMenuScript.find_scene_directional_light(root)).is_same(sun)
	assert_that(SettingsMenuScript.find_scene_directional_light(null)).is_null()
	var empty := Node.new()
	_managed.append(empty)
	assert_that(SettingsMenuScript.find_scene_directional_light(empty)).is_null()

## (f2) apply_to_scene_tree reaches the light through the boot path, and only
## the sun (not some unrelated node) is written.
func test_apply_to_scene_tree_pushes_the_shadow_ladder_onto_the_scene_sun() -> void:
	var built := _root_with_sun()
	var root: Node = built[0]
	var sun: DirectionalLight3D = built[1]
	var viewport: SubViewport = SubViewport.new()
	_managed.append(viewport)

	SettingsMenuScript.apply_to_scene_tree(0, root, viewport)
	assert_that(sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_that(sun.directional_shadow_max_distance).is_equal_approx(20.0, 0.001)
	assert_that(sun.shadow_opacity).is_equal_approx(0.75, 0.001)

	SettingsMenuScript.apply_to_scene_tree(2, root, viewport)
	assert_that(sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_that(sun.directional_shadow_max_distance).is_equal_approx(100.0, 0.001)

	# An unknown index must still land Medium on the light, not throw.
	SettingsMenuScript.apply_to_scene_tree(77, root, viewport)
	assert_that(sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	assert_that(sun.directional_shadow_max_distance).is_equal_approx(50.0, 0.001)

## (f3) THE TIME-OF-DAY INVARIANT (design point 3). The clock path reaches the
## sun through WorldDriver.apply_sun_transform (driven by sun_driver.gd /
## autoload/day_night_driver.gd -> WeatherManager). It writes exactly two
## fields — `transform` and `shadow_enabled` — so a preset must survive it
## untouched. This drives the real static rather than simulating it, so a future
## edit that starts resetting the cascades fails here.
##
## The preset is AUTHORITATIVE (not re-applied after the clock): the ladder is
## the only writer of these knobs, which is why the re-apply fallback is not
## needed and why no autoload had to be touched.
func test_shadow_ladder_survives_a_time_of_day_update() -> void:
	var built := _root_with_sun()
	var sun: DirectionalLight3D = built[1]
	SettingsMenuScript.apply_shadow_preset(sun, SettingsMenuScript.preset_for(0))
	var mode := sun.directional_shadow_mode
	var max_distance := sun.directional_shadow_max_distance
	var fade := sun.directional_shadow_fade_start
	var opacity := sun.shadow_opacity

	# Real clock path: sun_driver.gd::_on_time_of_day_changed -> this static.
	WorldDriver.apply_sun_transform(sun, 6.5, false)
	WorldDriver.apply_sun_transform(sun, 19.25, true)

	assert_that(sun.directional_shadow_mode).is_equal(mode)
	assert_that(sun.directional_shadow_max_distance).is_equal_approx(max_distance, 0.001)
	assert_that(sun.directional_shadow_fade_start).is_equal_approx(fade, 0.001)
	assert_that(sun.shadow_opacity).is_equal_approx(opacity, 0.001)
	# The clock's own contract still holds alongside the ladder.
	assert_that(sun.shadow_enabled).is_true()
	assert_that(sun.directional_shadow_max_distance).is_equal_approx(20.0, 0.001)

## (f4) The ladder never fights the clock over shadow_enabled: the clock
## re-asserts it every tick (world_driver.gd:365), so it is deliberately NOT a
## ladder key — asserting that keeps a future "Low disables shadows" idea from
## silently no-op'ing every frame.
func test_shadow_enabled_is_not_a_ladder_key() -> void:
	for index in [0, 1, 2]:
		assert_that(SettingsMenuScript.preset_for(index).has("shadow_enabled")).is_false()

# --- (g) the weak-GPU default is unaffected -------------------------------------

## (g) Adding the shadow keys must not disturb the hardware-recommended default:
## discrete cards still start on Medium, and only weak adapters drop to Low.
func test_default_preset_detection_still_skips_low_on_discrete_gpus() -> void:
	assert_that(SettingsMenuScript.preset_for_adapter_name("NVIDIA GeForce RTX 3060")).is_equal(1)
	assert_that(SettingsMenuScript.preset_for_adapter_name("AMD Radeon RX 5700 XT")).is_equal(1)
	assert_that(SettingsMenuScript.preset_for_adapter_name("NVIDIA GeForce RTX 4090")).is_equal(1)
	# Documented reference-rig behaviour: the GTX 970 is a legacy GeForce, so it
	# resolves to Low. Unchanged by this item.
	assert_that(SettingsMenuScript.preset_for_adapter_name("GeForce GTX 970")).is_equal(0)
	assert_that(SettingsMenuScript.preset_for_adapter_name("Intel UHD Graphics 630")).is_equal(0)
	assert_that(SettingsMenuScript.preset_for_adapter_name("")).is_equal(1)

## (g2) default_quality_preset() stays inside the ladder AND its result now
## carries the shadow keys — whatever box this runs on, the boot preset must be
## fully specified.
func test_default_quality_preset_is_bounded_and_fully_specified() -> void:
	var index: int = SettingsMenuScript.default_quality_preset()
	assert_that(index).is_greater_equal(0)
	assert_that(index).is_less_equal(2)
	var preset: Dictionary = SettingsMenuScript.preset_for(index)
	for key in SHADOW_KEYS:
		assert_that(preset.has(key)).is_true()

## (g3) Backwards compatibility: the pre-ladder 3-arg call signature must keep
## working (test_settings_presets.gd / test_quality_ladder.gd still call it).
func test_apply_quality_preset_still_accepts_three_args_with_no_light() -> void:
	var env := Environment.new()
	var viewport: SubViewport = SubViewport.new()
	_managed.append(env)
	_managed.append(viewport)
	SettingsMenuScript.apply_quality_preset(env, viewport, SettingsMenuScript.preset_for(2))
	assert_that(env.ssr_enabled).is_true()
	assert_that(viewport.scaling_3d_mode).is_equal(Viewport.SCALING_3D_MODE_FSR2)