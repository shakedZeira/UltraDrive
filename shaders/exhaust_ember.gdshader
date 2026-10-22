shader_type spatial;
// Backfire ember / spark: tiny additive billboard disc. Billboarding is done
// in the vertex stage (no per-frame camera lookups in script), so it is correct
// from the cockpit, chase and any other camera.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

instance uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform vec3 hot_color : source_color = vec3(1.0, 0.72, 0.28);

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy,
			INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float disc = 1.0 - smoothstep(0.35, 1.0, r);
	ALBEDO = hot_color * disc * fade * 3.0;
	ALPHA = 1.0;
}
