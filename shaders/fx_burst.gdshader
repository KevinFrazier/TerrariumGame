shader_type spatial;
// Self-contained impact/explosion pop. A unit sphere whose vertices expand
// outward along their normals as `t` runs 0->1, fading out as it grows.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0);
uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform float radius = 1.0;

void vertex() {
	VERTEX += NORMAL * t * radius;
}

void fragment() {
	ALBEDO = color;
	// Bright core early, fading to transparent as it expands.
	ALPHA = clamp(1.0 - t, 0.0, 1.0) * 0.9;
}
