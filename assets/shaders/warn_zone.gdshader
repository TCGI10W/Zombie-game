shader_type spatial;
// Danger circle on the ground: a bright rim, plus a fill that grows from the
// centre to the rim while the attack charges (fill 0..1).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform float fill = 0.0;
uniform float rim = 0.05; // rim width as a share of the radius
uniform float pulse = 1.0;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0; // 0 centre .. 1 edge
	float edge = smoothstep(1.0 - rim - 0.02, 1.0 - rim, d) * (1.0 - smoothstep(0.985, 1.0, d));
	float inner = (1.0 - smoothstep(fill - 0.02, fill, d)) * 0.22;
	float front = smoothstep(fill - 0.1, fill, d) * (1.0 - smoothstep(fill, fill + 0.012, d)) * 0.55 * step(0.001, fill);
	float a = max(edge, max(inner, front));
	a *= 1.0 - step(1.0, d);
	float blink = mix(1.0, 0.75 + 0.25 * sin(TIME * 14.0), pulse);
	ALBEDO = color.rgb * (1.0 + edge * 1.5) * blink;
	ALPHA = a * color.a;
}
