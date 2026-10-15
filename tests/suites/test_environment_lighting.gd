# tests/suites/test_environment_lighting.gd
extends GdUnitTestSuite

## Graphics-gap lighting gate (plan items 1-3): every playable world scene
## bakes a shadow-casting DirectionalLight3D, a PhysicalSkyMaterial sun sky
## that feeds ambient + IBL, and a fogged sky-background Environment, and the
## settings ladder applies exposure + HDR glow fill + cool ambient on top of
## its presets. The .tscn files are parsed as text so the gate runs headless
## with no renderer.

const PLAYABLE_WORLD_SCENES: Array[String] = [
	"res://scenes/world/open_world_root.tscn",
	"res://scenes/track/mountain_pass.tscn",
	"res://scenes/test/test_track.tscn",
	"res://scenes/main.tscn",
]

const SettingsMenuScript: GDScript = preload("res://scripts/ui/settings_menu.gd")

var _managed: Array = []
var _attr_re: RegEx
var _sub_re: RegEx

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	_managed.clear()

func test_every_playable_world_scene_has_sun_with_shadows() -> void:
	for path in PLAYABLE_WORLD_SCENES:
		var parsed := _parse_tscn(path)
		var sun_count := 0
		for node in parsed["nodes"]:
			if node["type"] == "DirectionalLight3D":
				sun_count += 1
				assert_that(node["props"].has("shadow_enabled")).is_true()
				assert_that(node["props"]["shadow_enabled"]).is_equal("true")
				assert_that(node["props"].has("shadow_filter")).is_true()
				# Light-leak guard: bias stays at the engine default (0.1, with
				# normal bias 2.0) or tighter. An inflated shadow_bias pulls the
				# projection away from the caster — peter-panning, which reads as
				# light leaking under the car — while too little bias causes
				# shadow acne. Both defaults were verified against 4.7.2.
				var bias := String(node["props"].get("shadow_bias", "0.1")).to_float()
				var normal_bias := String(node["props"].get("shadow_normal_bias", "2.0")).to_float()
				assert_that(bias).is_between(0.001, 0.15)
				assert_that(normal_bias).is_between(0.5, 2.0)
		# Exactly one: PhysicalSkyMaterial only supports one sun and reads the
		# first DirectionalLight3D in the tree, so a second light anywhere in a
		# playable scene would silently change what the sky reflects.
		assert_that(sun_count).is_equal(1)

## Engine-level parse gate: the text parser above tolerates anything a human
## would call a stray indent, so it cannot see a syntax error Godot itself
## rejects. Load each playable through ResourceLoader and read the scene STATE
## (no instantiate(), so no scene _ready side effects — terrain bake, autoload
## chatter — inside a unit test) and re-count the sun from the engine's own
## view of the file.
func test_every_playable_world_scene_parses_in_engine() -> void:
	for path in PLAYABLE_WORLD_SCENES:
		var packed := load(path) as PackedScene
		assert_that(packed).is_not_null()
		if packed == null:
			continue
		var state := packed.get_state()
		var suns := 0
		for i in state.get_node_count():
			if state.get_node_type(i) == "DirectionalLight3D":
				suns += 1
		assert_that(suns).is_equal(1)

## PhysicalSkyMaterial replaced ProceduralSkyMaterial in all four playables.
## The sun's disk, color and direction are taken automatically from the scene's
## FIRST DirectionalLight3D in the tree (4.7 class docs, and every playable
## scene declares exactly one — asserted below), so sky and light cannot
## disagree and there is nothing time-dependent to test: sun_driver.gd / the
## WorldDriver move that one light, and the sky follows it. The bands below
## pin the deliberate tuning: a clear-ish sky (turbidity 4), a mild Mie
## aureole so the sun reads as a bright highlight in reflections, and 1.5x sky
## energy over the stock physical default.
func test_every_playable_world_scene_uses_physical_sky() -> void:
	for path in PLAYABLE_WORLD_SCENES:
		var parsed := _parse_tscn(path)
		var has_mat := false
		var has_sky := false
		for id: Variant in parsed["resources"]:
			var res: Dictionary = parsed["resources"][id]
			if res["type"] == "PhysicalSkyMaterial":
				has_mat = true
				assert_that(res["props"].has("ground_color")).is_true()
				assert_that(res["props"].has("energy_multiplier")).is_true()
				assert_that(String(res["props"].get("turbidity", "")).to_float()).is_between(3.0, 6.0)
				assert_that(String(res["props"].get("rayleigh_coefficient", "")).to_float()).is_between(1.5, 3.0)
				assert_that(String(res["props"].get("mie_coefficient", "")).to_float()).is_between(0.004, 0.02)
				assert_that(String(res["props"].get("energy_multiplier", "")).to_float()).is_between(1.0, 2.0)
				# Procedural-only knobs must be gone, not merely unused.
				assert_that(res["props"].has("sun_angle_max")).is_false()
				assert_that(res["props"].has("sky_top_color")).is_false()
			elif res["type"] == "Sky":
				has_sky = true
		assert_that(has_mat).is_true()
		assert_that(has_sky).is_true()

## The sky has to feed the LIGHTING, not just the background:
## ambient_light_source SKY (3) makes the IBL radiance bake sample the sky
## panorama — at the old COLOR (2) the ambient_light_sky_contribution 0.7
## was inert and every surface got the flat cool fill only — and
## reflected_light_source SKY (2) makes glossy reflections come from that same
## panorama (reflected_source 0 = "background" also happens to be the sky
## here, but 2 states the intent and survives a background_mode change).
## radiance_size 3 = RADIANCE_SIZE_256, the Sky's 256px radiance mip chain
## (the engine default, and the ceiling the 4.7 docs call safe outside
## high-end hardware — 512+ is explicitly flagged as such), the number the
## reflections actually filter over.
func test_every_playable_world_scene_sky_feeds_ibl() -> void:
	for path in PLAYABLE_WORLD_SCENES:
		var parsed := _parse_tscn(path)
		var env_props := {}
		for node in parsed["nodes"]:
			if node["type"] == "WorldEnvironment":
				var env_ref := _sub_resource_id(String(node["props"].get("environment", "")))
				var env_res: Dictionary = parsed["resources"].get(env_ref, {})
				env_props = env_res.get("props", {})
				break
		assert_that(String(env_props.get("ambient_light_source", ""))).is_equal("3")
		assert_that(String(env_props.get("reflected_light_source", ""))).is_equal("2")
		var sky_ref := _sub_resource_id(String(env_props.get("sky", "")))
		var sky_res: Dictionary = parsed["resources"].get(sky_ref, {})
		assert_that(String(sky_res.get("type", ""))).is_equal("Sky")
		assert_that(String((sky_res.get("props", {}) as Dictionary).get("radiance_size", ""))).is_equal("3")

func test_every_playable_world_scene_has_fogged_sky_background() -> void:
	for path in PLAYABLE_WORLD_SCENES:
		var parsed := _parse_tscn(path)
		var env_res: Dictionary = {}
		for node in parsed["nodes"]:
			if node["type"] == "WorldEnvironment":
				var env_ref := _sub_resource_id(String(node["props"].get("environment", "")))
				env_res = parsed["resources"].get(env_ref, {})
				break
		assert_that(env_res.has("type")).is_true()
		assert_that(env_res["type"]).is_equal("Environment")
		var props: Dictionary = env_res.get("props", {})
		assert_that(String(props.get("background_mode", ""))).is_equal("2")
		assert_that(String(props.get("fog_enabled", ""))).is_equal("true")
		# Horizon retune (graphics-gap): density raised out of the near-invisible
		# 0.0008-0.001 band and sky_affect from 0.2 to 0.5 so distant geometry
		# fades into a hazed sky instead of ending on a hard line.
		assert_that(String(props.get("fog_density", "")).to_float()).is_between(0.001, 0.002)
		assert_that(String(props.get("fog_sky_affect", "")).to_float()).is_between(0.4, 0.6)

func test_apply_medium_preset_sets_exposure_and_hdr_glow() -> void:
	var env := Environment.new()
	_managed.append(env)
	SettingsMenuScript.apply_quality_preset(env, null, SettingsMenuScript.preset_for(1))
	assert_that(env.tonemap_exposure).is_equal_approx(0.9, 0.001)
	assert_that(env.tonemap_white).is_equal_approx(6.0, 0.001)
	assert_that(env.glow_enabled).is_true()
	assert_that(env.glow_intensity).is_equal_approx(0.4, 0.001)
	assert_that(env.glow_strength).is_equal_approx(0.8, 0.001)
	assert_that(env.glow_bloom).is_equal_approx(0.6, 0.001)
	assert_that(env.ambient_light_color).is_equal(Color(0.6, 0.62, 0.7))
	# The cool fill only lands when sky_contribution < 1.0 (see apply comment).
	assert_that(env.ambient_light_sky_contribution).is_equal_approx(0.7, 0.001)

func test_apply_low_preset_keeps_glow_off_with_restrained_bloom() -> void:
	var env := Environment.new()
	_managed.append(env)
	SettingsMenuScript.apply_quality_preset(env, null, SettingsMenuScript.preset_for(0))
	assert_that(env.tonemap_exposure).is_equal_approx(0.9, 0.001)
	assert_that(env.tonemap_white).is_equal_approx(6.0, 0.001)
	assert_that(env.glow_enabled).is_false()
	assert_that(env.glow_bloom).is_equal_approx(0.1, 0.001)
	assert_that(env.ambient_light_energy).is_equal_approx(1.0, 0.001)

func test_apply_high_preset_keeps_hdr_glow_and_acces() -> void:
	var env := Environment.new()
	_managed.append(env)
	SettingsMenuScript.apply_quality_preset(env, null, SettingsMenuScript.preset_for(2))
	assert_that(env.tonemap_mode).is_equal(Environment.TONE_MAPPER_ACES)
	assert_that(env.tonemap_exposure).is_equal_approx(0.9, 0.001)
	assert_that(env.tonemap_white).is_equal_approx(6.0, 0.001)
	assert_that(env.glow_enabled).is_true()
	assert_that(env.glow_bloom).is_equal_approx(0.6, 0.001)

## The scenes must carry the ladder's de-bleach calibration themselves (pre-
## apply default), not rely solely on GameState applying the preset: ACES with
## the stock tonemap_white 1.0 clips highlights at scene HDR ~2, and the cool
## ambient color is inert at the stock sky_contribution 1.0.
func test_every_playable_world_scene_calibrates_tonemap_and_ambient() -> void:
	for path in PLAYABLE_WORLD_SCENES:
		var parsed := _parse_tscn(path)
		for node in parsed["nodes"]:
			if node["type"] != "WorldEnvironment":
				continue
			var env_ref := _sub_resource_id(String(node["props"].get("environment", "")))
			var env_res: Dictionary = parsed["resources"].get(env_ref, {})
			var props: Dictionary = env_res.get("props", {})
			assert_that(String(props.get("tonemap_white", "")).to_float()).is_equal_approx(6.0, 0.001)
			assert_that(String(props.get("ambient_light_sky_contribution", "")).to_float()).is_equal_approx(0.7, 0.001)

func _parse_tscn(path: String) -> Dictionary:
	var result := {"resources": {}, "nodes": []}
	var file := FileAccess.open(path, FileAccess.READ)
	assert_that(file).is_not_null()
	if file == null:
		return result
	var block: Dictionary = {}
	for line: String in file.get_as_text().split("\n", false):
		var trimmed := line.strip_edges()
		if trimmed.is_empty():
			continue
		if trimmed.begins_with("["):
			_commit_block(result, block)
			var kind := "skip"
			if trimmed.begins_with("[sub_resource"):
				kind = "resource"
			elif trimmed.begins_with("[node"):
				kind = "node"
			block = {"kind": kind, "header": trimmed, "props": {}}
		elif block.get("kind", "skip") != "skip":
			var eq := trimmed.find("=")
			if eq > 0:
				block["props"][trimmed.substr(0, eq).strip_edges()] = trimmed.substr(eq + 1).strip_edges()
	_commit_block(result, block)
	return result

func _commit_block(result: Dictionary, block: Dictionary) -> void:
	var kind: String = block.get("kind", "skip")
	if kind == "skip" or block.is_empty():
		return
	var attrs := _header_attrs(String(block["header"]))
	if kind == "resource":
		var id: String = attrs.get("id", "")
		if not id.is_empty():
			result["resources"][id] = {"type": attrs.get("type", ""), "props": block["props"]}
	else:
		(result["nodes"] as Array).append({"type": attrs.get("type", ""), "props": block["props"]})

func _header_attrs(header: String) -> Dictionary:
	if _attr_re == null:
		_attr_re = RegEx.new()
		_attr_re.compile("([a-z_]+)=((?:\"[^\"]*\")|(?:\\[[^\\]]*\\])|(?:\\S+))")
	var attrs := {}
	for m: RegExMatch in _attr_re.search_all(header):
		attrs[m.get_string(1)] = m.get_string(2).trim_prefix("\"").trim_suffix("\"")
	return attrs

func _sub_resource_id(value: String) -> String:
	if _sub_re == null:
		_sub_re = RegEx.new()
		_sub_re.compile("SubResource\\(\"([^\"]+)\"\\)")
	var m := _sub_re.search(value)
	return m.get_string(1) if m else ""