shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Mixed asphalt / loose-dirt road surface for TrackBuilder roads that carry a
// per-point surface profile (RoadDef.point_surfaces, e.g. Barcelona RX).
//
// Mesh contract (TrackBuilder._build_mesh with a profile):
//   COLOR.r = loose weight of that centerline row: 1 on a GRAVEL/dirt section,
//             0 on asphalt, with TrackBuilder's feather + downstream dirt spill
//             ramps in between (the physics surface switches at the hard
//             boundary; this only decides the look).
//   UV.x    = lateral position, -1 = left edge .. +1 = right edge.
//   UV.y    = arc length along the road (m).
// Everything else is world-space procedural noise, so there are no textures to
// load and the pattern is continuous across the closed-loop seam.

uniform vec3 asphalt_color : source_color = vec3(0.16, 0.17, 0.19);
uniform vec3 dirt_color : source_color = vec3(0.34, 0.24, 0.15);
uniform vec3 gravel_color : source_color = vec3(0.52, 0.45, 0.35);
uniform vec3 line_color : source_color = vec3(0.86, 0.86, 0.84);
uniform float asphalt_roughness = 0.88;
uniform float dirt_roughness = 1.0;
uniform float half_width = 6.0;
// Painted edge line on the asphalt: centre this far in from the edge (m).
uniform float edge_line_inset = 0.45;
uniform float edge_line_width = 0.16;
// Lateral offset (m) of the two compacted tyre tracks from the centreline.
uniform float track_offset = 1.7;
uniform float bump_strength = 0.9;

varying vec3 world_pos;
varying float loose_w;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 4-octave fbm, normalised to ~[0, 1].
float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return sum / 0.9375;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	loose_w = COLOR.r;
}

void fragment() {
	vec2 xz = world_pos.xz;
	float lat_m = UV.x * half_width;
	float dist_px = length(VERTEX);
	// Fade the high-frequency detail with distance so it never shimmers.
	float near = 1.0 - smoothstep(25.0, 90.0, dist_px);

	// Two compacted tyre tracks either side of the centreline, wandering a little.
	float wander = (vnoise(vec2(UV.y * 0.03, 3.7)) - 0.5) * 1.2;
	float track = exp(-pow((abs(lat_m - wander) - track_offset) / 0.75, 2.0));

	// --- surface change: a ragged, patchy boundary rather than a straight cut.
	// Spill (0 < w < 1) is carried in the tyre tracks first, like dirt dragged
	// onto the tarmac at a section exit.
	float w = clamp(loose_w, 0.0, 1.0);
	float spill = clamp(w + (track - 0.35) * w * (1.0 - w) * 1.6, 0.0, 1.0);
	float edge_n = 0.12 + 0.76 * fbm(xz * 0.23);
	float mask = smoothstep(edge_n - 0.10, edge_n + 0.10, spill);
	// Thin dust film where the spill has not taken over yet.
	float film = clamp(spill * 1.4, 0.0, 1.0) * (1.0 - mask);

	// --- asphalt
	float macro_a = fbm(xz * 0.045);
	vec3 asphalt = asphalt_color * (0.88 + 0.24 * macro_a);
	float stones = step(0.94, hash12(floor(xz * 38.0))) * near;
	asphalt += vec3(0.05) * stones;
	asphalt *= 1.0 - 0.10 * track;  // rubbered-in line
	float line_c = half_width - edge_line_inset;
	float line_m = 1.0 - smoothstep(edge_line_width * 0.5 - 0.02, edge_line_width * 0.5 + 0.02,
		abs(abs(lat_m) - line_c));
	asphalt = mix(asphalt, line_color * (0.9 + 0.1 * macro_a), line_m * (1.0 - film));
	asphalt = mix(asphalt, dirt_color * 0.95, film * 0.55);
	float rough_a = asphalt_roughness - 0.07 * track - 0.25 * line_m * 0.3;

	// --- loose dirt / gravel
	float mottle = 0.62 + 0.38 * fbm(xz * 0.35);
	float patches = fbm(xz * 0.06 + vec2(41.0, 7.0));
	vec3 dirt = dirt_color * mottle;
	// Drier, lighter loose gravel toward the edges and between the tracks.
	float loose = smoothstep(0.55, 0.98, abs(UV.x)) * 0.8 + (1.0 - track) * 0.25;
	dirt = mix(dirt, gravel_color * (0.85 + 0.3 * patches), clamp(loose * 0.55 + patches * 0.25, 0.0, 0.8));
	// Pebbles: sparse lighter and darker grains.
	float g = hash12(floor(xz * 16.0));
	dirt = mix(dirt, gravel_color * 1.15, step(0.86, g) * 0.6 * near);
	dirt = mix(dirt, dirt_color * 0.55, step(g, 0.06) * 0.5 * near);
	// Compacted, darker and smoother tracks.
	dirt *= 1.0 - 0.20 * track;
	float rough_d = dirt_roughness - 0.08 * track;

	ALBEDO = mix(asphalt, dirt, mask);
	ROUGHNESS = mix(rough_a, rough_d, mask);
	SPECULAR = mix(0.5, 0.3, mask);

	// Screen-space derivative bump (no tangents on the road mesh): coarse ruts
	// and grain on the dirt, almost nothing on the asphalt.
	float h = (fbm(xz * 1.6) * 0.6 + g * 0.4 * near - track * 0.5) * mask * near;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump_strength * 0.05);
}
