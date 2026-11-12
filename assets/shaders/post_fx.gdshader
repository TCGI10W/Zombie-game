// Bodycam v0.9 + CoD 5/7 finishing pass over the 3D view:
// wide-angle fisheye barrel distortion, radial chromatic dispersion, bleach-bypass
// cold shadow crush, dynamic CMOS auto-exposure flash dip, stress tunnel vision,
// low-light ISO sensor noise, and broken-feed static on death.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.042;
uniform float vignette = 0.36;
uniform float aberration = 0.0014;
uniform float saturation = 0.76;
uniform float contrast = 1.13;
uniform vec3 shadow_tint = vec3(0.004, 0.009, 0.013);
uniform vec3 highlight_tint = vec3(0.98, 0.97, 0.92);
uniform float bodycam = 1.0;
uniform float stress = 0.0;
uniform float flash_blind = 0.0;
uniform float damage = 0.0;
uniform float downed = 0.0;
uniform float dead_cam = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 raw_uv = SCREEN_UV;
	vec2 p = raw_uv * 2.0 - 1.0;
	float r2 = dot(p, p);

	// Bodycam wide-angle barrel lens warp (zoom-compensated at center)
	vec2 uv = raw_uv;
	float corner_mask = 1.0;
	if (bodycam > 0.001) {
		float k1 = 0.145 * bodycam;
		float k2 = 0.045 * bodycam;
		vec2 pw = p * (1.0 + k1 * r2 + k2 * r2 * r2) / (1.0 + k1 * 0.70 + k2 * 0.42);
		uv = clamp(pw * 0.5 + 0.5, vec2(0.001), vec2(0.999));
		corner_mask = 1.0 - smoothstep(1.48, 1.94, r2) * 0.84 * bodycam;
	}

	// Impact / dead-feed horizontal scanline glitch tear
	float glitch = max(damage * 0.55, dead_cam);
	if (glitch > 0.02) {
		float band = floor(uv.y * 44.0);
		float n_band = hash(vec2(band, floor(TIME * 19.0)));
		if (n_band > 1.0 - glitch * 0.28) {
			uv.x = clamp(uv.x + (n_band - 0.5) * 0.045 * glitch, 0.001, 0.999);
		}
	}

	vec2 c = uv - 0.5;
	float cr2 = dot(c, c);
	float ab = aberration * (1.0 + bodycam * 1.35 + stress * 1.65 + downed * 3.0 + dead_cam * 2.5);
	vec2 off = c * cr2 * ab * 12.0;
	vec3 col;
	col.r = texture(screen_tex, clamp(uv + off, vec2(0.001), vec2(0.999))).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, clamp(uv - off, vec2(0.001), vec2(0.999))).b;

	// Downed or extreme panic: subtle double-vision pulse
	float ghost_amt = max(downed, max(0.0, stress - 0.68) * 1.4);
	if (ghost_amt > 0.005) {
		vec2 goff = vec2(sin(TIME * 2.1) * 0.006, cos(TIME * 1.5) * 0.004) * ghost_amt;
		vec3 ghost = texture(screen_tex, clamp(uv + goff, vec2(0.001), vec2(0.999))).rgb;
		col = mix(col, ghost, 0.34 * clamp(ghost_amt, 0.0, 1.0));
	}

	// Bleach-bypass micro-contrast & desaturation
	float con = contrast + stress * 0.06 + damage * 0.08;
	col = (col - 0.5) * con + 0.5;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	float sat = max(0.12, saturation * (1.0 - damage * 0.68 - stress * 0.22 - dead_cam * 0.55));
	col = mix(vec3(l), col, sat);
	col = col * highlight_tint + shadow_tint * (1.0 - clamp(l * 2.0, 0.0, 1.0));

	// Dynamic CMOS auto-exposure flash dip (darkens shadows after gunshots/lightning in pitch black)
	if (flash_blind > 0.001) {
		col *= 1.0 - 0.26 * flash_blind;
		col = max(col - vec3(0.03 * flash_blind), vec3(0.0));
	}

	col = mix(col, col * vec3(1.0, 0.52, 0.48), downed * 0.38);

	// Tunnel-vision panic vignette + lens housing bevel
	float v = vignette + bodycam * 0.14 + stress * 0.28 + downed * 0.32 + damage * 0.16;
	col *= 1.0 - v * smoothstep(0.08, 0.62, cr2 * 2.0);
	col *= corner_mask;

	// Low-light CMOS ISO sensor grain (stronger in shadows) + subtle sensor scanlines + death static
	float shadow_weight = 1.15 - clamp(l * 1.4, 0.0, 0.85);
	float g = hash(uv * vec2(1931.0, 1087.0) + fract(TIME * 7.13) * 91.7) - 0.5;
	col += g * (grain + dead_cam * 0.24) * shadow_weight;
	if (bodycam > 0.001) {
		col *= 1.0 - (sin(raw_uv.y * 860.0) * 0.5 + 0.5) * (0.018 + dead_cam * 0.06) * bodycam;
	}
	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
