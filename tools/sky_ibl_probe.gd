extends SceneTree

## One-off headless probe for the graphics-gap IBL step. Prints the 4.7.2
## engine defaults that tests/suites/test_environment_lighting.gd documents
## (Light3D shadow bias) and the SSAO knobs Environment actually exposes in
## 4.x — ssao_bias and ssao_half_size are Godot 3 names and no longer exist.
## Resources are RefCounted, so they are dropped by quit() rather than freed.
## Run: godot --headless -s res://tools/sky_ibl_probe.gd --path .

func _init() -> void:
	var light := DirectionalLight3D.new()
	print("[probe] shadow_bias=", light.shadow_bias, " shadow_normal_bias=", light.shadow_normal_bias)
	light.free()
	var env := Environment.new()
	var keys: Array[String] = []
	for prop: Dictionary in env.get_property_list():
		var prop_name := String(prop["name"])
		if prop_name.begins_with("ssao"):
			keys.append(prop_name)
	print("[probe] env ssao props=", keys)
	var sky := Sky.new()
	print("[probe] sky radiance_size=", sky.radiance_size, " process_mode=", sky.process_mode)
	print("[probe] ambient_source_sky=", Environment.AMBIENT_SOURCE_SKY,
		" reflected_source_sky=", Environment.REFLECTION_SOURCE_SKY)
	quit()
