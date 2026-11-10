shader_type spatial;
// Glowing outline: bright where the surface turns away from the camera.
// Used as an overlay on tiered zombies and for the commander's shield bubble.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float power = 2.2;
uniform float strength = 1.2;
uniform float base = 0.0; // flat glow added everywhere
uniform float bands = 0.0; // 1 = moving energy bands (shield)

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), power);
	float band = 0.5 + 0.5 * sin(UV.y * 46.0 - TIME * 4.0);
	ALBEDO = color.rgb * (f * strength + base) * mix(1.0, 0.55 + 0.9 * band, bands);
}
