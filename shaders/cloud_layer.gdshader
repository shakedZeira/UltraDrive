// shaders/cloud_layer.gdshader
// FH6-look pass (2026-10-23): a cheap cumulus layer on an inverted sphere that
// follows the camera (WorldAtmosphere). The sky itself stays the scene's
// PhysicalSkyMaterial (it feeds the IBL); the clouds are only drawn, never
// baked into the radiance map. Planar projection of the view ray onto a cloud
// deck, two noise octaves, sun-side brightening, faded out toward the horizon.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float coverage = 0.5;      // 0 clear .. 1 overcast
uniform float softness = 0.22;
uniform float scale = 0.22;
uniform vec2 drift = vec2(0.0012, 0.0005);
uniform vec3 lit_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 shade_color : source_color = vec3(0.62, 0.67, 0.76);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float opacity = 0.92;
uniform int octaves = 2;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 dir = normalize(v_world - CAMERA_POSITION_WORLD);
	if (dir.y < 0.015) {
		discard;
	}
	vec2 uv = dir.xz / (dir.y + 0.08) * scale + TIME * drift;
	float n = texture(cloud_noise, uv).r;
	if (octaves > 1) {
		n = n * 0.68 + texture(cloud_noise, uv * 2.7 + vec2(0.37, 0.71)).r * 0.32;
	}
	float thr = mix(0.78, 0.32, coverage);
	float density = smoothstep(thr, thr + softness, n);
	float horizon = smoothstep(0.015, 0.2, dir.y);
	float a = density * horizon * opacity;
	if (a < 0.01) {
		discard;
	}
	// Thicker parts are darker underneath; the side facing the sun glows.
	float thick = smoothstep(thr, thr + softness * 2.5, n);
	float sun = pow(max(dot(dir, normalize(sun_dir)), 0.0), 6.0);
	vec3 col = mix(lit_color, shade_color, thick * 0.65);
	col += lit_color * sun * 0.35;
	ALBEDO = col;
	ALPHA = a;
}
