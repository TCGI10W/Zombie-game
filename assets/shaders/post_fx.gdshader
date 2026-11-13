// Grounded bleak horror finishing pass over the 3D view:
// subtle edge chromatic dispersion, bleach-bypass cold shadow crush,
// smooth low-health desaturation & vignette, and subtle dark shadow grain.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.032;
uniform float vignette = 0.34;
uniform float aberration = 0.0010;
uniform float saturation = 0.78;
uniform float contrast = 1.12;
uniform vec3 shadow_tint = vec3(0.004, 0.009, 0.013);
uniform vec3 highlight_tint = vec3(0.98, 0.97, 0.92);
uniform float stress = 0.0;
uniform float damage = 0.0;
uniform float downed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float cr2 = dot(c, c);

	// Subtle optical edge dispersion (no screen warp or jiggle)
	float ab = aberration * (1.0 + downed * 1.6);
	vec2 off = c * cr2 * ab * 10.0;
	vec3 col;
	col.r = texture(screen_tex, clamp(uv + off, vec2(0.001), vec2(0.999))).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, clamp(uv - off, vec2(0.001), vec2(0.999))).b;

	// Bleach-bypass micro-contrast & cold low-health desaturation
	float con = contrast + stress * 0.04 + damage * 0.05;
	col = (col - 0.5) * con + 0.5;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	float sat = max(0.16, saturation * (1.0 - damage * 0.62 - stress * 0.16 - downed * 0.35));
	col = mix(vec3(l), col, sat);
	col = col * highlight_tint + shadow_tint * (1.0 - clamp(l * 2.0, 0.0, 1.0));

	col = mix(col, col * vec3(1.0, 0.55, 0.50), downed * 0.35);

	// Natural tunnel-vision vignette
	float v = vignette + stress * 0.16 + downed * 0.28 + damage * 0.16;
	col *= 1.0 - v * smoothstep(0.10, 0.66, cr2 * 2.0);

	// Subtle organic film grain weighted toward dark shadows
	float shadow_weight = 1.10 - clamp(l * 1.4, 0.0, 0.85);
	float g = hash(uv * vec2(1931.0, 1087.0) + fract(TIME * 7.13) * 91.7) - 0.5;
	col += g * grain * shadow_weight;

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
