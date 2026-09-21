# tests/suites/test_environment_lighting.gd
extends GdUnitTestSuite

## Graphics-gap lighting gate (plan items 1-3): every playable world scene
## bakes a shadow-casting DirectionalLight3D, a procedural sun sky, and a
## fogged sky-background Environment, and the settings ladder applies exposure
## + HDR glow fill + cool ambient on top of its presets. The .tscn files are
## parsed as text so the gate runs headless with no renderer.

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
		assert_that(sun_count).is_greater_equal(1)

func test_every_playable_world_scene_uses_procedural_sky() -> void:
	for path in PLAYABLE_WORLD_SCENES:
		var parsed := _parse_tscn(path)
		var has_mat := false
		var has_sky := false
		for id: Variant in parsed["resources"]:
			var res: Dictionary = parsed["resources"][id]
			if res["type"] == "ProceduralSkyMaterial":
				has_mat = true
				assert_that(res["props"].has("sky_top_color")).is_true()
				assert_that(res["props"].has("sun_angle_max")).is_true()
				assert_that(res["props"].has("energy_multiplier")).is_true()
			elif res["type"] == "Sky":
				has_sky = true
		assert_that(has_mat).is_true()
		assert_that(has_sky).is_true()

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
		assert_that(String(props.get("fog_density", ""))).is_not_empty()
		assert_that(String(props.get("fog_sky_affect", ""))).is_not_empty()

func test_apply_medium_preset_sets_exposure_and_hdr_glow() -> void:
	var env := Environment.new()
	_managed.append(env)
	SettingsMenuScript.apply_quality_preset(env, null, SettingsMenuScript.preset_for(1))
	assert_that(env.tonemap_exposure).is_equal_approx(0.9, 0.001)
	assert_that(env.glow_enabled).is_true()
	assert_that(env.glow_intensity).is_equal_approx(0.4, 0.001)
	assert_that(env.glow_strength).is_equal_approx(0.8, 0.001)
	assert_that(env.glow_bloom).is_equal_approx(0.6, 0.001)
	assert_that(env.ambient_light_color).is_equal(Color(0.6, 0.62, 0.7))

func test_apply_low_preset_keeps_glow_off_with_restrained_bloom() -> void:
	var env := Environment.new()
	_managed.append(env)
	SettingsMenuScript.apply_quality_preset(env, null, SettingsMenuScript.preset_for(0))
	assert_that(env.tonemap_exposure).is_equal_approx(0.9, 0.001)
	assert_that(env.glow_enabled).is_false()
	assert_that(env.glow_bloom).is_equal_approx(0.1, 0.001)
	assert_that(env.ambient_light_energy).is_equal_approx(1.0, 0.001)

func test_apply_high_preset_keeps_hdr_glow_and_acces() -> void:
	var env := Environment.new()
	_managed.append(env)
	SettingsMenuScript.apply_quality_preset(env, null, SettingsMenuScript.preset_for(2))
	assert_that(env.tonemap_mode).is_equal(Environment.TONE_MAPPER_ACES)
	assert_that(env.tonemap_exposure).is_equal_approx(0.9, 0.001)
	assert_that(env.glow_enabled).is_true()
	assert_that(env.glow_bloom).is_equal_approx(0.6, 0.001)

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