// shaders/foliage_wind.gdshader
// Low-poly tree: wind sway in vertex, bark/leaf split picked from baked
// height UVs in fragment (trunk is the bottom 25% of the tree).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform float wind_strength = 0.05;
uniform vec3 bark_color : source_color = vec3(0.42, 0.27, 0.15);
uniform vec3 leaf_color : source_color = vec3(0.20, 0.44, 0.19);

void vertex() {
	// Sway scales with local vertex height so tops bend more than bases.
	float wave_x = sin(TIME * 1.4 + (VERTEX.x + VERTEX.z) * 0.7);
	float wave_z = cos(TIME * 1.1 + VERTEX.y * 0.5);
	float sway = max(VERTEX.y, 0.0) * wind_strength;
	VERTEX.x += wave_x * sway;
	VERTEX.z += wave_z * sway;
}

void fragment() {
	float canopy = step(0.25, UV.y); // 0 = trunk, 1 = canopy
	ALBEDO = mix(bark_color, leaf_color, canopy);
}
