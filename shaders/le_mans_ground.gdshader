// shaders/le_mans_ground.gdshader
// Le Mans plain / skirt / verge-wear ground (le_mans_visual_realism_plan.md
// WS-B). The scene is a flat PlaneMesh, not Terrain3D, so "macro variation +
// more than one texture set" is done here in world space (see the include).
//
// `vertex_wear` = 1 only on the verge ribbon (`le_mans.gd::_build_verge_mesh`),
// whose vertex COLOR.r carries the worn-earth weight: high at the road edge and
// in braking zones, exactly 0 on the ribbon's outer row so it dissolves into the
// identical grass the plain computes underneath. The plain has no vertex colour
// and keeps vertex_wear = 0, so COLOR never matters there.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://shaders/le_mans_ground_inc.gdshaderinc"

uniform float vertex_wear = 0.0;
uniform float tint = 1.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float micro;
	vec3 col = lm_grass(v_world.xz, micro);
	float w = clamp(COLOR.r * vertex_wear, 0.0, 1.0);
	// Ragged, patchy wear: the metre-scale noise pushes the threshold around so
	// the band edge is torn, not a ruled line ("kill the perfect edge").
	float wn = smoothstep(0.12, 0.85, w + (micro - 0.5) * 0.8 * w);
	col = mix(col, lm_earth * mix(0.8, 1.15, micro), wn * 0.9);
	ALBEDO = col * tint;
	ROUGHNESS = 0.96;
	SPECULAR = 0.25;
}
