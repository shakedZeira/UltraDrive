// shaders/le_mans_asphalt.gdshader
// Le Mans carriageway surface (le_mans_visual_realism_plan.md WS-B "uniform
// asphalt" tell + WS-F "rubbered-in racing line"). Applied by le_mans.gd to a
// UV'd copy of the road's visual mesh (`_build_road_visual_mesh`); the road's
// COLLISION is TrackBuilder's own and is untouched.
//
// Mesh contract:
//   UV.x  = 0 left edge .. 1 right edge;   UV.y = arc length (m)
//   UV2.x = racing-line lateral position (-1 left edge .. +1 right edge)
//   UV2.y = rubber intensity 0..1 (higher through corner complexes)
// Everything is analytic or one shared noise texture, so it renders on every
// renderer and costs a handful of texture taps per pixel.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D lm_noise : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 asphalt : source_color = vec3(0.128, 0.132, 0.142);
uniform vec3 rubber : source_color = vec3(0.05, 0.05, 0.055);
uniform vec3 dust : source_color = vec3(0.30, 0.285, 0.26);
uniform vec3 paint : source_color = vec3(0.86, 0.86, 0.83);
uniform float road_half_m = 6.0;
uniform float line_half_width = 0.24;
uniform float edge_line_inner_m = 0.30;
uniform float edge_line_outer_m = 0.12;
uniform float section_m = 83.0;

varying vec3 v_world;

float lm_hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float lat = UV.x * 2.0 - 1.0;
	float s = UV.y;
	vec2 road_uv = vec2(UV.x * road_half_m * 2.0, s);
	float macro = texture(lm_noise, v_world.xz * 0.004 + vec2(0.7, 0.2)).r;
	float micro = texture(lm_noise, road_uv * 0.35).r;
	float fine = texture(lm_noise, road_uv * 3.1 + vec2(0.3, 0.1)).r;

	// Resurfacing sections: whole-width tone steps with straight transverse
	// seams (real circuits are patchworks of differently aged asphalt).
	float tone = mix(0.9, 1.1, lm_hash(floor(s / section_m)));
	vec3 col = asphalt * tone * mix(0.86, 1.14, macro) * mix(0.9, 1.1, micro * 0.6 + fine * 0.4);

	// Rubbered-in racing line: darker, slightly smoother, broken up by noise.
	float d = abs(lat - UV2.x);
	float line = smoothstep(line_half_width, line_half_width * 0.3, d) * UV2.y;
	line *= mix(0.55, 1.0, micro);
	col = mix(col, rubber, line * 0.7);

	// Dusty, lighter off-line edges (marbles / blown-in dirt).
	float edge_dust = smoothstep(0.74, 0.96, abs(lat));
	col = mix(col, dust, edge_dust * 0.32 * mix(0.5, 1.0, fine));

	// Tar-snake crack sealant: thin dark iso-lines of a low-frequency noise,
	// antialiased with fwidth so they never shimmer into a moire.
	float c = texture(lm_noise, road_uv * 0.045 + vec2(0.5, 0.5)).r;
	float fw = max(fwidth(c) * 1.5, 0.002);
	float crack = 1.0 - smoothstep(0.0, fw, abs(c - 0.5));
	// Sparse: only where a second, very low-frequency mask says this stretch
	// was crack-sealed, so the lap is not one continuous contour map.
	crack *= smoothstep(0.58, 0.72, texture(lm_noise, road_uv * 0.006 + vec2(0.9, 0.3)).r);
	col = mix(col, rubber * 0.85, crack * 0.4);

	// White edge lines (inset from the edge, antialiased in metres).
	float edge_m = (1.0 - abs(lat)) * road_half_m;
	float fwm = max(fwidth(edge_m), 0.001);
	float paint_mask = smoothstep(edge_line_outer_m - fwm, edge_line_outer_m + fwm, edge_m)
		* (1.0 - smoothstep(edge_line_inner_m - fwm, edge_line_inner_m + fwm, edge_m));
	paint_mask *= mix(0.7, 1.0, fine);
	col = mix(col, paint * mix(0.85, 1.0, fine), paint_mask);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.88, 0.74, line), 0.62, paint_mask);
	SPECULAR = 0.45;
	NORMAL_MAP = texture(grain_normal, road_uv * 1.3).xyz;
	NORMAL_MAP_DEPTH = mix(0.6, 0.2, paint_mask);
}
