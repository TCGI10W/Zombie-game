extends Node

var _cache: Dictionary = {}


func get_pbr(prefix: String, uv_scale: float = 0.35, tint: Color = Color.WHITE, metallic: float = 0.0, rough_mult: float = 1.0, triplanar: bool = true) -> StandardMaterial3D:
	var key := "%s_%.2f_%s_%.2f_%.2f_%s" % [prefix, uv_scale, tint.to_html(), metallic, rough_mult, str(triplanar)]
	if _cache.has(key):
		return _cache[key]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.metallic = metallic
	mat.roughness = rough_mult

	var a_path := "res://assets/textures/%s_albedo.png" % prefix
	var n_path := "res://assets/textures/%s_normal.png" % prefix
	var r_path := "res://assets/textures/%s_rough.png" % prefix

	if ResourceLoader.exists(a_path):
		mat.albedo_texture = load(a_path)
	if ResourceLoader.exists(n_path):
		mat.normal_enabled = true
		mat.normal_scale = 1.25
		mat.normal_texture = load(n_path)
	if ResourceLoader.exists(r_path):
		mat.roughness_texture = load(r_path)

	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if triplanar:
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	else:
		mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)

	_cache[key] = mat
	return mat


const WorldShader := preload("res://assets/shaders/world_surface.gdshader")
const RimShader := preload("res://assets/shaders/rim_glow.gdshader")
const WarnShader := preload("res://assets/shaders/warn_zone.gdshader")


# Map surfaces (walls, floors, ground): world-space triplanar textures with
# repeats broken up, large-scale variation, grime at the base of walls and
# optional rain puddles. `rotate_tiles` also turns the texture copies in 90
# degree steps - only for surfaces without a direction (ground, floors).
func get_world(prefix: String, uv_scale: float = 0.3, tint: Color = Color.WHITE, metallic: float = 0.0, rough_mult: float = 1.0, wetness: float = 0.0, grime: float = 0.45, rotate_tiles: bool = false) -> ShaderMaterial:
	var key := "world_%s_%.2f_%s_%.2f_%.2f_%.2f_%.2f_%s" % [prefix, uv_scale, tint.to_html(), metallic, rough_mult, wetness, grime, str(rotate_tiles)]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = WorldShader
	mat.set_shader_parameter("variation_rotate", rotate_tiles)
	for pair in [["albedo_tex", "albedo"], ["normal_tex", "normal"], ["rough_tex", "rough"], ["height_tex", "height"]]:
		var path := "res://assets/textures/%s_%s.png" % [prefix, pair[1]]
		if ResourceLoader.exists(path):
			mat.set_shader_parameter(pair[0], load(path))
	if ResourceLoader.exists("res://assets/textures/macro_noise.png"):
		mat.set_shader_parameter("macro_tex", load("res://assets/textures/macro_noise.png"))
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("metallic_value", metallic)
	mat.set_shader_parameter("rough_mult", rough_mult)
	mat.set_shader_parameter("wetness", wetness)
	mat.set_shader_parameter("grime_strength", grime)
	_cache[key] = mat
	return mat


# One plank out of a strip atlas (`strips` planks stacked top to bottom),
# stretched over the two big faces of a BoxMesh. BoxMesh lays its faces out
# in a 3x2 UV grid, so scaling by (3, 2/strips) gives each face one strip.
func get_box_strip(prefix: String, strip: int, strips: int, tint: Color = Color.WHITE, rough_mult: float = 1.0) -> StandardMaterial3D:
	var key := "strip_%s_%d_%d_%s_%.2f" % [prefix, strip, strips, tint.to_html(), rough_mult]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = rough_mult
	var a_path := "res://assets/textures/%s_albedo.png" % prefix
	var n_path := "res://assets/textures/%s_normal.png" % prefix
	var r_path := "res://assets/textures/%s_rough.png" % prefix
	if ResourceLoader.exists(a_path):
		mat.albedo_texture = load(a_path)
	if ResourceLoader.exists(n_path):
		mat.normal_enabled = true
		mat.normal_texture = load(n_path)
	if ResourceLoader.exists(r_path):
		mat.roughness_texture = load(r_path)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.uv1_scale = Vector3(3.0, 2.0 / float(strips), 1.0)
	mat.uv1_offset = Vector3(0.0, float(strip) / float(strips), 0.0)
	_cache[key] = mat
	return mat


func get_emissive(color: Color, energy: float = 3.5, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "em_%s_%.2f_%.2f" % [color.to_html(), energy, alpha]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.2
	if alpha < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = mat
	return mat


# Glowing outline overlay (tiered zombies) / energy bubble (bands = 1).
func get_rim(color: Color, strength: float = 1.2, power: float = 2.2, base: float = 0.0, bands: float = 0.0) -> ShaderMaterial:
	var key := "rim_%s_%.2f_%.2f_%.2f_%.1f" % [color.to_html(), strength, power, base, bands]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = RimShader
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("power", power)
	mat.set_shader_parameter("base", base)
	mat.set_shader_parameter("bands", bands)
	_cache[key] = mat
	return mat


# Danger circle for a flat PlaneMesh. Not cached: every circle animates its
# own "fill" (0..1) while the attack charges.
func new_warn_zone(color: Color, rim: float = 0.05, pulse: float = 1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WarnShader
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("rim", rim)
	mat.set_shader_parameter("pulse", pulse)
	mat.set_shader_parameter("fill", 0.0)
	return mat
