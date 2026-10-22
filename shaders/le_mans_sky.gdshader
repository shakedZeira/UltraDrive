// shaders/le_mans_sky.gdshader
// Custom sky for the Le Mans No-Chicane scene (le_mans_visual_realism_plan.md
// WS-F: "HDRI or custom sky replacing the procedural PhysicalSkyMaterial").
// The repo ships no HDRI, so this is the custom-sky route: an analytic
// horizon-to-zenith gradient with a warm sun glow and disk, plus a fair-weather
// cumulus layer projected onto a virtual cloud plane from one seamless noise
// tile. Static (no TIME), so the radiance map is only re-baked when the sun
// moves, and the cubemap pass skips the sun disk so reflections/ambient are not
// spiked by it. Core sky built-ins only: renders on every renderer.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.23, 0.40, 0.70);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.74, 0.84);
uniform vec3 ground_color : source_color = vec3(0.32, 0.33, 0.30);
uniform float sky_energy = 1.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable, hint_default_black;
uniform float cloud_coverage = 0.42;
uniform float cloud_softness = 0.22;
uniform float cloud_scale = 0.55;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.99, 0.97);
uniform vec3 cloud_shade : source_color = vec3(0.58, 0.63, 0.71);
uniform float sun_disk_cos = 0.99989;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), 0.5));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	}
	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	vec3 sun = LIGHT0_COLOR * LIGHT0_ENERGY;
	// Mie-ish forward glow + broad warm halo near the horizon.
	col += sun * (pow(sd, 6.0) * 0.10 + pow(sd, 48.0) * 0.22);
	if (h > 0.004) {
		vec2 uv = d.xz / (h + 0.06) * cloud_scale;
		float n = texture(cloud_noise, uv * 0.08).r * 0.62
			+ texture(cloud_noise, uv * 0.31 + vec2(0.37, 0.21)).r * 0.28
			+ texture(cloud_noise, uv * 1.10 + vec2(0.71, 0.53)).r * 0.10;
		float c = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + cloud_softness, n);
		// Thin out toward the horizon (perspective-compressed, hazed).
		c *= smoothstep(0.004, 0.18, h);
		float thick = smoothstep(0.55, 0.95, n);
		vec3 cc = mix(cloud_lit, cloud_shade, thick * 0.8);
		cc *= 0.85 + 0.35 * clamp(LIGHT0_DIRECTION.y + 0.2, 0.0, 1.0);
		cc += sun * pow(sd, 10.0) * 0.25 * (1.0 - thick);
		col = mix(col, cc, c * 0.92);
	}
	if (!AT_CUBEMAP_PASS && h > -0.01) {
		col += sun * smoothstep(sun_disk_cos, sun_disk_cos + 0.00005, sd) * 18.0;
	}
	COLOR = col * sky_energy;
}
