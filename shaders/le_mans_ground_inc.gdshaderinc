// shaders/le_mans_ground_inc.gdshaderinc
// Shared Le Mans grass colour model (docs/plans/le_mans_visual_realism_plan.md
// WS-B). Included by le_mans_ground.gdshader (plain, skirt, verge wear band)
// and le_mans_gravel.gdshader (sand traps, paved aprons) so every surface that
// meets the grass computes the SAME grass colour at the same world XZ. That is
// what lets a trap or verge fade into the grass with no visible seam: at blend
// weight 0 both shaders return byte-identical albedo.
//
// Pure world-space sampling of ONE seamless noise texture at four scales
// (macro ~770 m, meso ~110 m, micro ~9 m, fine ~1.4 m). No UVs are needed, so
// the flat 6 x 7 km PlaneMesh, the UV-less skirt ribbon and the trap ribbons
// all share it. Works on Forward+, Mobile and Compatibility (no Forward+-only
// built-ins).

uniform sampler2D lm_noise : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec3 lm_lush : source_color = vec3(0.20, 0.28, 0.12);
uniform vec3 lm_dry : source_color = vec3(0.38, 0.37, 0.20);
uniform vec3 lm_dark : source_color = vec3(0.11, 0.18, 0.07);
uniform vec3 lm_earth : source_color = vec3(0.31, 0.26, 0.18);
uniform float lm_macro_scale = 0.0013;
uniform float lm_meso_scale = 0.009;
uniform float lm_micro_scale = 0.11;
uniform float lm_fine_scale = 0.7;

// Grass albedo at world XZ `p`. `micro` returns the metre-scale noise so a
// caller can break up its own blend edge with the same pattern.
vec3 lm_grass(vec2 p, out float micro) {
	float macro = texture(lm_noise, p * lm_macro_scale).r;
	float meso = texture(lm_noise, p * lm_meso_scale + vec2(0.31, 0.77)).r;
	micro = texture(lm_noise, p * lm_micro_scale + vec2(0.53, 0.19)).r;
	float fine = texture(lm_noise, p * lm_fine_scale + vec2(0.11, 0.41)).r;
	// Dry/straw fields vs lush meadow at the field scale.
	float dry = smoothstep(0.42, 0.78, macro * 0.65 + meso * 0.35);
	vec3 col = mix(lm_lush, lm_dry, dry * 0.75);
	// Damp, denser patches at the 100 m scale.
	float damp = smoothstep(0.50, 0.22, meso);
	col = mix(col, lm_dark, damp * 0.5);
	// Metre-scale clumping so the near ground is never a flat sheet.
	col *= mix(0.82, 1.14, micro * 0.7 + fine * 0.3);
	return col;
}
