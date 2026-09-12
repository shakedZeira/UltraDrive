// shaders/grass_wind.gdshader
// Cheap wind sway + solid grass-green albedo for MultiMesh grass tufts.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform float wind_strength = 0.05;
uniform vec3 u_color : source_color = vec3(0.32, 0.52, 0.28);

varying vec3 world_pos;

void vertex() {
	// Bend tops more than bases. Flat ground quads sit at y ~ 0 so they barely
	// move; anything standing up (raised tufts, later billboards) sways.
	float wave_x = sin(TIME * 1.4 + (VERTEX.x + VERTEX.z) * 0.7);
	float wave_z = cos(TIME * 1.1 + VERTEX.y * 0.5);
	float sway = max(VERTEX.y, 0.0) * wind_strength;
	VERTEX.x += wave_x * sway;
	VERTEX.z += wave_z * sway;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Subtle world-position hash keeps the field from reading as one flat tint.
	float dither = fract(sin(dot(world_pos.xz, vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = u_color * mix(0.92, 1.08, dither);
}
