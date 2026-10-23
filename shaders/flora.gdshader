// shaders/flora.gdshader
// Procedural low-poly trees, bushes, rocks and roadside props (FloraMeshes).
// Vertex COLOR.rgb = albedo with baked shading; COLOR.a = 1 marks tintable
// parts, multiplied by the per-instance tint in INSTANCE_CUSTOM.rgb.
// UV.y = height / 10 m drives the wind bend (0 for props and rocks).
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_disabled;

uniform float wind_strength = 0.0; // metres of sway at 10 m height
uniform bool use_instance_tint = true;

varying vec3 v_tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 tint = use_instance_tint ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	v_tint = mix(vec3(1.0), tint, COLOR.a);
	if (wind_strength > 0.0) {
		float ph = dot(origin.xz, vec2(0.13, 0.17));
		float h = UV.y * UV.y * wind_strength;
		VERTEX.x += sin(TIME * 1.3 + ph) * h;
		VERTEX.z += cos(TIME * 1.05 + ph * 1.3) * h * 0.7;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * v_tint;
	ROUGHNESS = 0.92;
}
