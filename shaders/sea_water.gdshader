// shaders/sea_water.gdshader
// FH6-look pass (2026-10-23): open-world sea at y = 0 off the coast biome.
// Opaque (no refraction / depth read, so it costs about one textured plane),
// sky reflections via low roughness + Fresnel, two scrolling normal octaves
// for small waves, a teal tint toward grazing angles.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.18);
uniform vec3 near_color : source_color = vec3(0.06, 0.28, 0.32);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world.xz * 0.018;
	vec3 n1 = texture(wave_normal, uv + TIME * vec2(0.012, 0.008)).xyz;
	vec3 n2 = texture(wave_normal, uv * 3.1 - TIME * vec2(0.02, 0.015)).xyz;
	NORMAL_MAP = normalize(mix(n1, n2, 0.45));
	NORMAL_MAP_DEPTH = 0.6;
	float facing = clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0);
	ALBEDO = mix(near_color, deep_color, facing);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
