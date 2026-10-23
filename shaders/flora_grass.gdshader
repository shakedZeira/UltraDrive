// shaders/flora_grass.gdshader
// Standing grass clumps and wild flowers (FloraMeshes "grass", "dune_grass",
// "flowers"). Double-sided blades with up-facing normals so a clump is lit
// like the ground under it; per-instance tint in INSTANCE_CUSTOM.rgb for the
// tintable parts (COLOR.a = 1). Clumps shrink into the ground between
// fade_start and fade_end metres from the camera, so the patch edge never
// shows as a line and far clumps cost no fragments.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform float wind_strength = 0.12;
uniform float fade_start = 55.0;
uniform float fade_end = 95.0;

varying vec3 v_tint;

void vertex() {
	// Instance origin (the MultiMesh node sits at its patch centre).
	vec3 inst = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(inst, CAMERA_POSITION_WORLD);
	float k = 1.0 - smoothstep(fade_start, fade_end, d);
	v_tint = mix(vec3(1.0), INSTANCE_CUSTOM.rgb, COLOR.a);
	float ph = dot(inst.xz, vec2(0.31, 0.23));
	float h = max(VERTEX.y, 0.0);
	VERTEX.x += sin(TIME * 2.1 + ph + VERTEX.z * 2.0) * h * wind_strength;
	VERTEX.z += cos(TIME * 1.7 + ph) * h * wind_strength * 0.6;
	VERTEX *= k;
}

void fragment() {
	ALBEDO = COLOR.rgb * v_tint;
	ROUGHNESS = 0.95;
}
