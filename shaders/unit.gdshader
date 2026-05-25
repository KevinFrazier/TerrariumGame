shader_type spatial;
// Unit body material: team-tinted, with a shader-driven white hit flash.
// `flash` is pulsed to 1.0 on damage and tweened back to 0.
render_mode cull_back, diffuse_burley;

uniform vec3 albedo : source_color = vec3(1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float f = clamp(flash, 0.0, 1.0);
	ALBEDO = mix(albedo, vec3(1.0), f);
	EMISSION = vec3(1.0) * f * 2.0;
}
