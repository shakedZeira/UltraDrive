shader_type canvas_item;

// Stylised satellite terrain for the 2D maps (pause map + HUD minimap).
// Reads ONE shared height texture (R = metres, world-space rect) and shades it
// per pixel: shallow/deep water with a coast foam line, beach, lowland meadow,
// olive midland, ochre highland, rock, snow, plus a NW hillshade and a faint
// value-noise grain so large flat areas still read as ground, not as a fill.
// The caller maps screen px -> world metres with view_world_min/view_scale, so
// zoom/pan/rotation-free views of any size share this one shader.

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec2 tex_world_min = vec2(0.0);
uniform vec2 tex_world_size = vec2(1024.0);
uniform vec2 rect_px = vec2(512.0);
uniform vec2 view_world_min = vec2(0.0);   // world xz at the control's top-left
uniform float view_scale = 0.1;            // screen px per metre
uniform float mask_radius = 0.0;           // > 0: clip to a disc (minimap), px
uniform float dim = 1.0;                   // brightness multiplier
uniform float saturation = 1.0;
uniform float hill_strength = 1.0;

const vec3 C_ABYSS    = vec3(0.020, 0.075, 0.170);
const vec3 C_DEEP     = vec3(0.045, 0.200, 0.330);
const vec3 C_SHALLOW  = vec3(0.150, 0.470, 0.560);
const vec3 C_SHOAL    = vec3(0.330, 0.690, 0.690);
const vec3 C_PLAINS   = vec3(0.500, 0.550, 0.330);
const float COAST_H   = -3.0;              // the far field hovers around 0 m: that is dry plain, not sea
const vec3 C_LOWLAND  = vec3(0.330, 0.500, 0.230);
const vec3 C_MEADOW   = vec3(0.440, 0.580, 0.270);
const vec3 C_MIDLAND  = vec3(0.470, 0.500, 0.250);
const vec3 C_HIGHLAND = vec3(0.600, 0.440, 0.280);
const vec3 C_ROCK     = vec3(0.560, 0.520, 0.480);
const vec3 C_SNOW     = vec3(0.930, 0.950, 0.975);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float height_at(vec2 world) {
	vec2 uv = (world - tex_world_min) / tex_world_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return -40.0;
	}
	return texture(height_tex, uv).r;
}

vec3 land_color(float h, float grain) {
	vec3 c = mix(C_PLAINS, C_LOWLAND, smoothstep(3.0, 16.0, h));
	c = mix(c, C_MEADOW, smoothstep(10.0, 28.0, h) * (0.35 + 0.65 * grain));
	c = mix(c, C_MIDLAND, smoothstep(40.0, 110.0, h));
	c = mix(c, C_HIGHLAND, smoothstep(110.0, 300.0, h));
	c = mix(c, C_ROCK, smoothstep(280.0, 560.0, h));
	c = mix(c, C_SNOW, smoothstep(600.0, 820.0, h));
	return c;
}

vec3 water_color(float h) {
	float d = clamp(COAST_H - h, 0.0, 60.0);
	vec3 c = mix(C_SHOAL, C_SHALLOW, smoothstep(0.0, 4.0, d));
	c = mix(c, C_DEEP, smoothstep(3.0, 18.0, d));
	c = mix(c, C_ABYSS, smoothstep(16.0, 50.0, d));
	return c;
}

void fragment() {
	vec2 px = UV * rect_px;
	vec2 world = view_world_min + px / view_scale;
	float h = height_at(world);

	// Hillshade from central differences, one tex-world texel apart.
	vec2 texel = tex_world_size / vec2(textureSize(height_tex, 0));
	float hx = height_at(world + vec2(texel.x, 0.0)) - height_at(world - vec2(texel.x, 0.0));
	float hz = height_at(world + vec2(0.0, texel.y)) - height_at(world - vec2(0.0, texel.y));
	vec3 n = normalize(vec3(-hx / (2.0 * texel.x) * 2.2, 1.0, -hz / (2.0 * texel.y) * 2.2));
	float lit = dot(n, normalize(vec3(-0.55, 0.78, -0.55)));
	float shade = 1.0 + (lit - 0.78) * 0.95 * hill_strength;

	float grain = vnoise(world / 90.0) * 0.6 + vnoise(world / 23.0) * 0.4;
	vec3 col;
	if (h >= COAST_H) {
		col = land_color(h, grain);
		col *= clamp(shade, 0.55, 1.45);
		col *= 0.94 + 0.12 * grain;
		// Pale shore on the land side of the water line.
		col = mix(col, vec3(0.86, 0.84, 0.66), (1.0 - smoothstep(0.0, 1.5, h - COAST_H)) * 0.45);
	} else {
		col = water_color(h);
		col *= 0.97 + 0.06 * vnoise(world / 140.0);
		// Foam rim on the water side.
		col = mix(col, vec3(0.88, 0.96, 0.96), (1.0 - smoothstep(0.0, 1.6, COAST_H - h)) * 0.40);
	}

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation) * dim;

	float alpha = 1.0;
	if (mask_radius > 0.0) {
		float r = length(px - rect_px * 0.5);
		alpha = 1.0 - smoothstep(mask_radius - 1.5, mask_radius, r);
		// Darken toward the rim so the disc has depth.
		col *= 1.0 - 0.38 * smoothstep(0.55, 1.0, r / mask_radius);
	}
	COLOR = vec4(col, alpha);
}
