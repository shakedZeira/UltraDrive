class_name WindshieldFX
extends RefCounted

## Weather VFX (S12): windshield droplet/streak overlay. Gated to chase-cam
## mode (fist-person/hood views) so the world view stays clean. Pure builders
## and a strict active() rule -- headless-safe, no scene required.

const OVERLAY_ALPHA := 0.18

## Canvas-item droplet streak shader drawn on a full-rect ColorRect. Multiple
## downward lanes with per-lane speed/phase so the feel is rain on glass.
const SHADER_CODE := """
shader_type canvas_item;
uniform float amount : hint_range(2.0, 40.0) = 14.0;
uniform float drip_speed : hint_range(0.1, 2.0) = 0.6;
uniform vec3 tint : source_color = vec3(0.72, 0.82, 0.92);

float rand2(vec2 c) {
	return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float streak = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float lane = fract(rand2(vec2(fi, 1.0)) * 7.13);
		float streak_seed = rand2(vec2(fi, 2.0));
		float speed = drip_speed * (0.6 + streak_seed * 0.9);
		float phase = fi * 0.37;
		float y = fract(uv.y * 1.0 + TIME * speed + phase);
		float width = 0.008 + streak_seed * 0.02;
		float dx = abs(uv.x - lane);
		float lane_mask = 1.0 - smoothstep(0.0, width, dx);
		float drip_mask = smoothstep(0.0, 0.12, y) * (1.0 - smoothstep(0.55, 1.0, y));
		streak += lane_mask * drip_mask;
	}
	float a = min(streak, 1.0);
	COLOR = vec4(tint, a);
}
"""

## Heat-type running rain + streaking motion capture. Gate: rain MUST be
## falling AND the active view must be a chase cam (not orbit / world map).
static func active(raining: bool, chase_mode: bool) -> bool:
	return raining and chase_mode

static func build_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER_CODE
	material.shader = shader
	return material

## Full-rect droplets overlay. Hidden until active() fires; the material does
## the drawing, modulate just caps total alpha.
static func build_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.name = "WindshieldOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.material = build_material()
	overlay.modulate = Color(1.0, 1.0, 1.0, OVERLAY_ALPHA)
	overlay.visible = false
	return overlay

## Applies the (raining, chase_mode) state to an overlay built by
## build_overlay(). Visibility is exactly active().
static func apply(overlay: ColorRect, raining: bool, chase_mode: bool) -> void:
	overlay.visible = active(raining, chase_mode)