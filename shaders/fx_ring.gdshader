shader_type spatial;
// Flat ground ring that expands outward as `t` runs 0->1 (level-up / buff / tier
// flourish). The ring radius and fade are computed per-fragment, so the mesh is
// just a static flat quad scaled to the maximum diameter.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0);
uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform float thickness = 0.08;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;  // 0 at center .. 1 at edge
	float ring = smoothstep(thickness, 0.0, abs(d - t));
	ALBEDO = color;
	ALPHA = ring * clamp(1.0 - t, 0.0, 1.0);
}
