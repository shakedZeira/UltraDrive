shader_type spatial;
// Exhaust backfire flame: additive, unshaded teardrop jet built on a 3-plane
// cross mesh (UV.x across the jet, UV.y 0 at the pipe mouth -> 1 at the far end).
// Per-flame state arrives through instance uniforms so ONE shared material
// serves the whole pool. Cheap: a few hash-noise taps, no textures, no lights.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

instance uniform float life : hint_range(0.0, 1.0) = 1.0;   // 0 = just fired, 1 = gone
instance uniform float energy : hint_range(0.0, 6.0) = 1.0;
instance uniform float seed : hint_range(0.0, 64.0) = 0.0;

uniform vec3 core_color : source_color = vec3(1.0, 0.93, 0.72);
uniform vec3 mid_color : source_color = vec3(1.0, 0.45, 0.06);
uniform vec3 tip_color : source_color = vec3(0.75, 0.12, 0.02);
uniform vec3 base_color : source_color = vec3(0.30, 0.45, 1.0);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);
	float across = abs(UV.x - 0.5) * 2.0;
	float n = vnoise(vec2(UV.x * 3.0 + seed, along * 4.0 - life * 16.0 + seed * 1.7));
	float n2 = vnoise(vec2(UV.x * 7.0 - seed, along * 9.0 - life * 30.0));
	// Teardrop: starts narrow at the pipe, swells, then tapers to a ragged tip.
	float prof = mix(0.35, 1.0, smoothstep(0.0, 0.22, along)) * (1.0 - pow(along, 1.5));
	float d = across / max(prof, 0.001) + (n - 0.5) * 0.7 * along;
	float shape = 1.0 - smoothstep(0.45, 1.0, d);
	float tip_fade = 1.0 - smoothstep(0.55, 1.0, along + (n2 - 0.5) * 0.35);
	float heat = clamp((1.0 - d) * (1.0 - along * 0.85), 0.0, 1.0);
	vec3 col = mix(tip_color, mid_color, smoothstep(0.0, 0.45, heat));
	col = mix(col, core_color, smoothstep(0.45, 0.95, heat));
	// Cool, blue-ish tint right at the pipe mouth.
	col = mix(col, base_color, (1.0 - smoothstep(0.0, 0.16, along)) * 0.65);
	float flick = 0.7 + 0.3 * n2;
	float fade = pow(clamp(1.0 - life, 0.0, 1.0), 1.3);
	ALBEDO = col * shape * tip_fade * fade * flick * energy;
	ALPHA = 1.0;
}
