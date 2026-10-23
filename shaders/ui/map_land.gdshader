shader_type canvas_item;

// Stylised satellite land for the race-menu world map. The CC0 world SVG is flat
// grey land on transparency; its alpha is the land mask. This shader paints land
// by latitude band (polar white, boreal green, temperate green, desert tan,
// tropical green) with grain, adds a pale coast rim, and puts a soft teal
// continental shelf in the ocean around every coast.

uniform sampler2D land_tex : filter_linear, repeat_disable;
uniform vec4 src_uv = vec4(0.0, 0.0, 1.0, 1.0);   // crop of the raster (uv)
uniform vec2 px_uv = vec2(0.0005);                // raster uv per screen px
uniform float lat_top = 90.0;
uniform float lat_bottom = -90.0;
uniform float lon_left = -180.0;
uniform float lon_right = 180.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float land_a(vec2 uv) {
	return texture(land_tex, clamp(uv, vec2(0.0), vec2(1.0))).a;
}

// Rough aridity: the big deserts as soft boxes in lon/lat.
float arid(float lon, float lat) {
	float sahara = smoothstep(-18.0, -8.0, lon) * (1.0 - smoothstep(40.0, 52.0, lon))
		* smoothstep(14.0, 20.0, lat) * (1.0 - smoothstep(30.0, 35.0, lat));
	float arabia = smoothstep(36.0, 42.0, lon) * (1.0 - smoothstep(58.0, 64.0, lon))
		* smoothstep(14.0, 20.0, lat) * (1.0 - smoothstep(29.0, 34.0, lat));
	float australia = smoothstep(114.0, 124.0, lon) * (1.0 - smoothstep(142.0, 150.0, lon))
		* smoothstep(-34.0, -28.0, lat) * (1.0 - smoothstep(-20.0, -14.0, lat));
	float southwest = smoothstep(-122.0, -114.0, lon) * (1.0 - smoothstep(-100.0, -92.0, lon))
		* smoothstep(26.0, 31.0, lat) * (1.0 - smoothstep(38.0, 43.0, lat));
	float central = smoothstep(50.0, 62.0, lon) * (1.0 - smoothstep(98.0, 112.0, lon))
		* smoothstep(36.0, 40.0, lat) * (1.0 - smoothstep(44.0, 48.0, lat));
	float namib = smoothstep(10.0, 14.0, lon) * (1.0 - smoothstep(20.0, 24.0, lon))
		* smoothstep(-30.0, -24.0, lat) * (1.0 - smoothstep(-16.0, -10.0, lat));
	return clamp(sahara + arabia + australia + southwest * 0.8 + central * 0.7 + namib * 0.8, 0.0, 1.0);
}

vec3 biome(float lon, float lat, float n) {
	float al = abs(lat);
	vec3 tropic = vec3(0.20, 0.44, 0.21);
	vec3 temperate = vec3(0.36, 0.52, 0.28);
	vec3 boreal = vec3(0.24, 0.36, 0.29);
	vec3 desert = vec3(0.79, 0.68, 0.46);
	vec3 snow = vec3(0.93, 0.95, 0.98);
	vec3 c = mix(tropic, temperate, smoothstep(10.0, 30.0, al));
	c = mix(c, boreal, smoothstep(48.0, 60.0, al));
	c = mix(c, snow, smoothstep(69.0, 75.0, al));
	// Warp the lon/lat before the desert boxes so their edges wander like real ones.
	vec2 w = vec2(lon, lat) + (vec2(vnoise(vec2(lon, lat) * 0.30), vnoise(vec2(lat, lon) * 0.30 + 7.0)) - 0.5) * 14.0;
	c = mix(c, desert, arid(w.x, w.y) * (0.70 + 0.25 * n));
	return c;
}

void fragment() {
	vec2 uv = src_uv.xy + UV * src_uv.zw;
	float lat = mix(lat_top, lat_bottom, UV.y);
	float lon = mix(lon_left, lon_right, UV.x);
	float a = land_a(uv);

	// Blurred alpha at two radii (px): inner for the coast rim, outer for the shelf.
	float b_in = a;
	float b_out = a;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.785398;
		vec2 d = vec2(cos(ang), sin(ang));
		b_in += land_a(uv + d * px_uv * 3.0);
		b_out += land_a(uv + d * px_uv * 9.0) * 0.5 + land_a(uv + d * px_uv * 16.0) * 0.5;
	}
	b_in /= 9.0;
	b_out /= 9.0;

	float n = vnoise(vec2(lon, lat) * 1.6) * 0.6 + vnoise(vec2(lon, lat) * 6.0) * 0.4;
	vec3 land = biome(lon, lat, n) * (0.92 + 0.16 * n);
	// Coast rim: lighter where the blurred land fades out.
	land = mix(land, vec3(0.90, 0.92, 0.80), (1.0 - smoothstep(0.55, 1.0, b_in)) * 0.40);

	vec3 shelf = vec3(0.19, 0.55, 0.64);
	float shelf_a = smoothstep(0.0, 0.55, b_out) * 0.50;

	float land_mask = smoothstep(0.30, 0.70, a);
	vec3 col = mix(shelf, land, land_mask);
	float alpha = mix(shelf_a, 1.0, land_mask);
	COLOR = vec4(col, alpha);
}
