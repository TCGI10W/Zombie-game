shader_type spatial;
// Open-world ground: three Blender-kit textures (grass, dirt, rock) blended by vertex colour
// (r = rock / steep, g = dirt patches), world-space UVs, nearest texels, and the same global
// PSX vertex snap + affine warp as ps1_core so the land wobbles like every other surface.
// Terrain triangles are 4 m, small enough that the snap never slides a whole hillside.
render_mode cull_back;

global uniform vec2 ps1_snap;
global uniform float ps1_warp;

uniform sampler2D grass_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform float uv_scale = 0.25;  // repeats per metre
uniform vec4 tint : source_color = vec4(1.0);

varying vec3 affine_uvw;
varying float near_vertex;
varying vec3 blend;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	UV = wp.xz * uv_scale;
	blend = COLOR.rgb;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (ps1_snap.x > 0.0 && PROJECTION_MATRIX[3][3] == 0.0 && clip.w > 0.0) {
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * ps1_snap + 0.5) / ps1_snap;
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
	affine_uvw = vec3(UV * clip.w, clip.w);
	near_vertex = clip.w < 1.5 ? 1.0 : 0.0;
}

void fragment() {
	vec2 affine = affine_uvw.xy / affine_uvw.z;
	vec2 uv = mix(UV, affine, near_vertex > 0.0001 ? 0.0 : ps1_warp * 0.5);
	vec3 g = texture(grass_tex, uv).rgb;
	vec3 d = texture(dirt_tex, uv * 1.3).rgb;
	vec3 r = texture(rock_tex, uv * 0.7).rgb;
	// hard-ish PSX style blend: quantize the weights so patches have crisp edges
	float wd = smoothstep(0.35, 0.65, blend.g);
	float wr = smoothstep(0.35, 0.6, blend.r);
	vec3 c = mix(mix(g, d, wd), r, wr);
	ALBEDO = c * tint.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
