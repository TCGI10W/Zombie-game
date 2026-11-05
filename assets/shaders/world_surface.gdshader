// World-space triplanar PBR for the map's walls, floors, beams and ground.
// On top of the (photo-scanned) tiling textures it:
//  - breaks up visible repeats: every lookup blends two differently offset
//    (and, on floors, rotated) copies of the texture along a low-frequency
//    noise (after Inigo Quilez's "texture repetition", technique 3),
//  - adds large-scale tone variation,
//  - lets grime creep up the base of walls,
//  - and pools rain in the low spots of up-facing ground (reflects lights
//    with SSR).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.3;
uniform float metallic_value = 0.0;
uniform float rough_mult = 1.0;
uniform float normal_strength = 1.0;
uniform float blend_sharpness = 8.0;
uniform float variation = 1.0;
uniform bool variation_rotate = false;
uniform float variation_scale = 0.08;
uniform float macro_scale = 0.045;
uniform float macro_strength = 0.3;
uniform float grime_height = 1.1;
uniform float grime_strength = 0.45;
uniform float wetness = 0.0;
uniform float puddle_scale = 0.05;
uniform float puddle_threshold = 0.6;
uniform float puddle_height_bias = 0.22;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack_normal(vec4 s) {
	vec2 xy = (s.rg * 2.0 - 1.0) * normal_strength;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

vec2 rot90(vec2 v, int r) {
	if (r == 1) {
		return vec2(-v.y, v.x);
	} else if (r == 2) {
		return -v;
	} else if (r == 3) {
		return vec2(v.y, -v.x);
	}
	return v;
}

// One copy of the texture set, shifted and turned by variant `i`.
// The tangent normal comes back in the projection's (u, -v) frame.
void tex_variant(vec2 uv, vec2 dx, vec2 dy, float i, bool want_h, out vec3 alb, out float rough, out vec3 nrm, out float h) {
	int r = variation_rotate ? int(mod(i, 4.0)) : 0;
	vec2 suv = rot90(uv, r) + sin(vec2(3.0, 7.0) * i);
	vec2 sdx = rot90(dx, r);
	vec2 sdy = rot90(dy, r);
	alb = textureGrad(albedo_tex, suv, sdx, sdy).rgb;
	rough = textureGrad(rough_tex, suv, sdx, sdy).r;
	vec3 tn = unpack_normal(textureGrad(normal_tex, suv, sdx, sdy));
	// Because v points down the image, turning the uvs turns the normal the same way
	nrm = vec3(rot90(tn.xy, r), tn.z);
	h = want_h ? textureGrad(height_tex, suv, sdx, sdy).r : 0.5;
}

void tex_set(vec2 uv, vec2 dx, vec2 dy, bool want_h, out vec3 alb, out float rough, out vec3 nrm, out float h) {
	if (variation <= 0.0) {
		tex_variant(uv, dx, dy, 0.0, want_h, alb, rough, nrm, h);
		return;
	}
	float k = textureLod(macro_tex, uv * variation_scale + vec2(0.31, 0.67), 0.0).b;
	float l = k * 8.0;
	float ia = floor(l);
	float f = fract(l);
	vec3 alb_a; float rough_a; vec3 nrm_a; float h_a;
	vec3 alb_b; float rough_b; vec3 nrm_b; float h_b;
	tex_variant(uv, dx, dy, ia, want_h, alb_a, rough_a, nrm_a, h_a);
	tex_variant(uv, dx, dy, ia + 1.0, want_h, alb_b, rough_b, nrm_b, h_b);
	// The seam between the two copies follows the texture's own detail
	float w = smoothstep(0.2, 0.8, f - 0.1 * dot(alb_a - alb_b, vec3(1.0)));
	w *= variation;
	alb = mix(alb_a, alb_b, w);
	rough = mix(rough_a, rough_b, w);
	nrm = normalize(mix(nrm_a, nrm_b, w));
	h = mix(h_a, h_b, w);
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 bw = pow(abs(n), vec3(blend_sharpness));
	bw /= max(bw.x + bw.y + bw.z, 1e-5);
	// Skip projections that barely contribute (walls and floors use just one)
	bw = step(vec3(0.02), bw) * bw;
	bw /= max(bw.x + bw.y + bw.z, 1e-5);
	vec3 p = w_pos * uv_scale;
	vec2 uv_x = vec2(p.z, -p.y);
	vec2 uv_y = vec2(p.x, p.z);
	vec2 uv_z = vec2(p.x, -p.y);
	// Screen-space derivatives up front (they're undefined inside branches)
	vec2 dx_x = dFdx(uv_x), dy_x = dFdy(uv_x);
	vec2 dx_y = dFdx(uv_y), dy_y = dFdy(uv_y);
	vec2 dx_z = dFdx(uv_z), dy_z = dFdy(uv_z);
	bool want_h = wetness > 0.0;

	vec3 alb = vec3(0.0);
	float rough = 0.0;
	vec3 wn = vec3(0.0);
	float h_up = 0.5;
	vec3 a; float r; vec3 t; float h;
	if (bw.x > 0.0) {
		tex_set(uv_x, dx_x, dy_x, false, a, r, t, h);
		alb += a * bw.x;
		rough += r * bw.x;
		wn += vec3(sign(n.x) * t.z, t.y, t.x) * bw.x;
	}
	if (bw.y > 0.0) {
		tex_set(uv_y, dx_y, dy_y, want_h, a, r, t, h);
		alb += a * bw.y;
		rough += r * bw.y;
		wn += vec3(t.x, sign(n.y) * t.z, -t.y) * bw.y;
		h_up = h;
	}
	if (bw.z > 0.0) {
		tex_set(uv_z, dx_z, dy_z, false, a, r, t, h);
		alb += a * bw.z;
		rough += r * bw.z;
		wn += vec3(t.x, t.y, sign(n.z) * t.z) * bw.z;
	}
	wn = normalize(wn);

	// Large-scale variation hides texture repeats
	vec2 muv = (w_pos.xz + vec2(w_pos.y * 0.7, -w_pos.y * 0.4)) * macro_scale;
	vec3 macro = texture(macro_tex, muv).rgb;
	alb *= mix(1.0 - macro_strength, 1.0 + macro_strength * 0.6, macro.r);
	alb *= tint.rgb;

	// Dirt and damp climb up the base of walls
	float wall = 1.0 - abs(n.y);
	float g = (1.0 - smoothstep(0.0, grime_height * (0.6 + 0.8 * macro.b), w_pos.y)) * wall * grime_strength;
	alb = mix(alb, alb * vec3(0.52, 0.48, 0.4), g);
	rough = clamp(rough * rough_mult + g * 0.08, 0.03, 1.0);

	// Rain puddles on low, flat ground; water settles in cracks and dips first
	float up = smoothstep(0.75, 0.95, n.y);
	float low = 1.0 - smoothstep(0.08, 0.35, w_pos.y);
	float pm = texture(macro_tex, w_pos.xz * puddle_scale + vec2(0.37, 0.11)).g + (0.5 - h_up) * puddle_height_bias;
	float puddle = smoothstep(puddle_threshold, puddle_threshold + 0.05, pm) * up * low * wetness;
	float damp = smoothstep(puddle_threshold - 0.14, puddle_threshold, pm) * up * low * wetness;
	alb *= mix(1.0, 0.6, max(damp * 0.55, puddle));
	rough = mix(rough, rough * 0.5, damp);
	rough = mix(rough, 0.03, puddle);
	wn = normalize(mix(wn, n, puddle));

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metallic_value;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
