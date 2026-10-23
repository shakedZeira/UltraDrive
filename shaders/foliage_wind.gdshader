// shaders/foliage_wind.gdshader
// Low-poly tree: wind sway in vertex, bark/leaf split picked from baked
// height UVs in fragment (trunk is the bottom 25% of the tree).
// FH6-look pass (2026-10-23): back faces get their normal flipped (the merged
// conifer meshes are drawn double-sided; with the front normal a back face is
// lit from the wrong side and whole trees read black), wrap diffuse, a darker
// low canopy / lighter tips gradient and a per-tree hue/value variation from the
// instance origin so a stand of the same mesh does not read as clones.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform float wind_strength = 0.05;
uniform vec3 bark_color : source_color = vec3(0.36, 0.25, 0.16);
uniform vec3 leaf_color : source_color = vec3(0.17, 0.36, 0.17);

varying float v_var;

void vertex() {
	// Sway scales with local vertex height so tops bend more than bases.
	float wave_x = sin(TIME * 1.4 + (VERTEX.x + VERTEX.z) * 0.7);
	float wave_z = cos(TIME * 1.1 + VERTEX.y * 0.5);
	float sway = max(VERTEX.y, 0.0) * wind_strength;
	VERTEX.x += wave_x * sway;
	VERTEX.z += wave_z * sway;
	vec2 o = MODEL_MATRIX[3].xz;
	v_var = fract(sin(dot(o, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float canopy = step(0.25, UV.y); // 0 = trunk, 1 = canopy
	vec3 leaf = leaf_color * mix(0.82, 1.15, v_var);
	leaf *= vec3(mix(0.92, 1.08, v_var), 1.0, mix(1.08, 0.9, v_var));
	leaf *= mix(0.72, 1.18, smoothstep(0.25, 1.0, UV.y));
	ALBEDO = mix(bark_color, leaf, canopy);
	ROUGHNESS = 0.9;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
