// Camera-like finishing pass over the 3D view: subtle lens aberration at the
// edges, a cool-shadow / warm-highlight grade, vignette and animated film
// grain. `damage` (0..1) drains colour when the player is hurt or downed.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.03;
uniform float vignette = 0.32;
uniform float aberration = 0.0012;
uniform float saturation = 0.92;
uniform float contrast = 1.05;
uniform vec3 shadow_tint = vec3(0.010, 0.014, 0.026);
uniform vec3 highlight_tint = vec3(1.03, 1.0, 0.96);
uniform float damage = 0.0;
uniform float downed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	float ab = aberration * (1.0 + downed * 3.0);
	vec2 off = c * r2 * ab * 12.0;
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;

	// Downed: smeared double vision
	if (downed > 0.0) {
		vec3 ghost = texture(screen_tex, uv + vec2(sin(TIME * 1.7) * 0.006, cos(TIME * 1.3) * 0.004) * downed).rgb;
		col = mix(col, ghost, 0.35 * downed);
	}

	col = (col - 0.5) * contrast + 0.5;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	float sat = saturation * (1.0 - damage * 0.75);
	col = mix(vec3(l), col, sat);
	col = col * highlight_tint + shadow_tint * (1.0 - clamp(l * 2.0, 0.0, 1.0));
	col = mix(col, col * vec3(1.0, 0.55, 0.5), downed * 0.35);

	float v = vignette + downed * 0.35 + damage * 0.15;
	col *= 1.0 - v * smoothstep(0.08, 0.6, r2 * 2.0);

	float g = hash(uv * vec2(1931.0, 1087.0) + fract(TIME * 7.13) * 91.7) - 0.5;
	col += g * grain * (1.0 - l * 0.5);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
