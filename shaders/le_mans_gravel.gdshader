// shaders/le_mans_gravel.gdshader
// Le Mans sand/gravel traps and paved run-off aprons (le_mans_visual_realism_plan
// WS-A), drawn as ribbon meshes by LeMansDressing.
//
// Mesh contract (LeMansDressing._ribbon_mesh):
//   UV       = world XZ in metres (so pebble/normal sampling is world-locked and
//              the generated tangents line up with it);
//   COLOR.a  = 1 inside the trap, 0 on the ragged fringe row.
// At COLOR.a = 0 the albedo is EXACTLY the grass the plain computes (shared
// include), so the trap dissolves into the field with no hard rectangle edge.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://shaders/le_mans_ground_inc.gdshaderinc"

uniform sampler2D pebble_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 sand_light : source_color = vec3(0.74, 0.66, 0.50);
uniform vec3 sand_dark : source_color = vec3(0.50, 0.43, 0.32);
uniform vec3 apron_color : source_color = vec3(0.17, 0.17, 0.17);
uniform float pebble_scale = 1.6;
// 0 = loose sand/gravel trap, 1 = paved asphalt run-off apron.
uniform float paved = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float micro;
	vec3 grass = lm_grass(v_world.xz, micro);
	float peb = texture(lm_noise, UV * pebble_scale).r;
	float peb2 = texture(lm_noise, UV * pebble_scale * 3.7 + vec2(0.2, 0.6)).r;
	vec3 sand = mix(sand_dark, sand_light, smoothstep(0.25, 0.75, peb * 0.6 + peb2 * 0.4));
	// Raked/driven-through streaks at the trap scale.
	sand *= mix(0.88, 1.06, micro);
	vec3 apron = apron_color * mix(0.85, 1.12, peb2) * mix(0.92, 1.05, micro);
	vec3 surf = mix(sand, apron, paved);
	// Torn edge: noise pushes the grass/sand threshold around the fringe.
	float a = clamp(COLOR.a, 0.0, 1.0);
	float e = smoothstep(0.05, 0.95, a + (peb - 0.5) * 0.9 * (1.0 - a));
	ALBEDO = mix(grass, surf, e);
	ROUGHNESS = mix(0.96, mix(0.93, 0.82, paved), e);
	SPECULAR = mix(0.25, 0.4, e);
	NORMAL_MAP = texture(pebble_normal, UV * pebble_scale).xyz;
	NORMAL_MAP_DEPTH = mix(0.0, mix(1.1, 0.35, paved), e);
}
