class_name WeaponRigBuilder
extends RefCounted

# Procedural weapon appearance customization, PBR texture skins/camos,
# multi-part 3D attachments, and Gunsmith 360° centerpiece builder across
# all 40 weapons:
# 1) 1st-person viewmodels + 3D menu Gunsmith (decorate_viewmodel / build_gunsmith_weapon)
# 2) 3rd-person world guns on PvP bots & remote players (build_world_gun)

static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


static func _is_arm_or_hand(n: Node) -> bool:
	var cur: Node = n
	while cur != null:
		var s := cur.name
		if s.begins_with("Arm") or s.begins_with("Hand"):
			return true
		if cur is Node3D and cur.get_parent() == null:
			break
		cur = cur.get_parent()
		if cur != null and (cur.name == "GunRig" or cur.name == "ShowcaseWeapon" or cur.name == "GunsmithWeapon" or cur.name.begins_with("vm_")):
			break
	return false


static func _hide_arms_recursive(n: Node) -> void:
	if n.name.begins_with("Arm") or n.name.begins_with("Hand"):
		if n is Node3D:
			(n as Node3D).visible = false
		return
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 1
	for c in n.get_children():
		_hide_arms_recursive(c)


static func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path] as Texture2D
	if ResourceLoader.exists(path):
		var t := load(path) as Texture2D
		_tex_cache[path] = t
		return t
	_tex_cache[path] = null
	return null


static func _pbr_mat(prefix: String, uv_scale: float, tint: Color, rough: float, met: float) -> StandardMaterial3D:
	var key := "%s_%.2f_%s_%.2f_%.2f" % [prefix, uv_scale, tint.to_html(true), rough, met]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = clampf(rough, 0.05, 1.0)
	mat.metallic = clampf(met, 0.0, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var a := _load_tex("res://assets/textures/%s_albedo.png" % prefix)
	var n := _load_tex("res://assets/textures/%s_normal.png" % prefix)
	var r := _load_tex("res://assets/textures/%s_rough.png" % prefix)
	if a != null:
		mat.albedo_texture = a
	if n != null:
		mat.normal_enabled = true
		mat.normal_scale = 1.15
		mat.normal_texture = n
	if r != null:
		mat.roughness_texture = r
	# Object-local triplanar so camos and metal grain stay locked while rotating in 3D Gunsmith
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	_mat_cache[key] = mat
	return mat


static func _emissive_mat(col: Color, energy: float = 2.8, alpha: float = 1.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := "em_%s_%.2f_%.2f_%s" % [col.to_html(true), energy, alpha, str(unshaded)]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.20
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = m
	return m


static func _glass_mat(col: Color) -> StandardMaterial3D:
	var key := "glass_%s" % col.to_html(true)
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.06
	m.metallic = 0.12
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m


static func _resolve_camo_mats(w_id: String, cfg: Dictionary) -> Dictionary:
	var style: Dictionary = cfg.get("style", {})
	var weapon_tint: Color = style.get("tint", Color(0.24, 0.25, 0.28))
	var weapon_accent: Color = style.get("accent", Color(0.18, 0.19, 0.22))
	var camo_id := String(cfg.get("camo", "factory"))
	if not WeaponCatalog.WEAPON_CAMOS.has(camo_id):
		camo_id = "factory"
	var cd: Dictionary = WeaponCatalog.WEAPON_CAMOS[camo_id]
	var tex_name := String(cd.get("tex", "gunmetal"))
	var uv_s := float(cd.get("uv", 3.0))
	var rough := float(cd.get("rough", 0.42))
	var met := float(cd.get("met", 0.68))

	var body_tint: Color = cd.get("tint", Color.WHITE)
	if bool(cd.get("use_weapon_tint", false)):
		# Lift dark default tints so gunmetal normal/roughness detail catches studio lights clearly
		body_tint = Color(
			clampf(weapon_tint.r * 1.38 + 0.10, 0.18, 0.95),
			clampf(weapon_tint.g * 1.38 + 0.10, 0.18, 0.95),
			clampf(weapon_tint.b * 1.38 + 0.10, 0.18, 0.95)
		)

	var primary_mat := _pbr_mat(tex_name, uv_s, body_tint, rough, met)
	var barrel_mat := _pbr_mat("panzer_steel", 3.4, Color(0.30, 0.33, 0.38), 0.30, 0.86)
	var steel_dark := _pbr_mat("gunmetal", 4.0, Color(0.20, 0.22, 0.25), 0.36, 0.78)
	var grip_mat := _pbr_mat("leather", 5.2, weapon_accent.lerp(Color(0.24, 0.24, 0.26), 0.45), 0.70, 0.10)
	var wrap_mat := _pbr_mat("fabric", 5.6, Color(0.24, 0.26, 0.24), 0.85, 0.05)

	var accent_mat: StandardMaterial3D
	if bool(style.get("wood_stock", false)) and camo_id in ["factory", "survivor", "woodland"]:
		accent_mat = _pbr_mat("wood_grain", 4.2, weapon_accent.lerp(Color(0.68, 0.40, 0.22), 0.55), 0.62, 0.06)
	elif camo_id == "gilded":
		accent_mat = _pbr_mat("gunmetal", 3.8, Color(0.14, 0.14, 0.17), 0.32, 0.84)
	elif camo_id == "crimson":
		accent_mat = _pbr_mat("gunmetal", 3.8, Color(0.18, 0.15, 0.17), 0.38, 0.72)
	elif camo_id == "panzer":
		accent_mat = _pbr_mat("gunmetal", 3.8, Color(0.22, 0.25, 0.29), 0.34, 0.76)
	else:
		var acc_tint := weapon_accent.lightened(0.18) if camo_id == "factory" else body_tint.darkened(0.32)
		accent_mat = _pbr_mat("gunmetal", 3.6, acc_tint, 0.48, 0.52)

	var wood_mat := _pbr_mat("wood_grain", 4.2, Color(0.66, 0.38, 0.20), 0.60, 0.06)
	var brass_mat := _pbr_mat("panzer_steel", 4.0, Color(0.92, 0.72, 0.26), 0.28, 0.90)
	var crimson_mat := _pbr_mat("panzer_steel", 4.0, Color(0.86, 0.20, 0.18), 0.32, 0.78)
	if w_id == "volt":
		accent_mat = _emissive_mat(Color(0.28, 0.86, 1.0), 2.1)

	return {
		"primary": primary_mat,
		"accent": accent_mat,
		"barrel": barrel_mat,
		"dark": steel_dark,
		"grip": grip_mat,
		"wrap": wrap_mat,
		"wood": wood_mat,
		"brass": brass_mat,
		"crimson": crimson_mat,
	}


static func _add_mesh(parent: Node3D, name_id: String, mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_id
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _add_socket(parent: Node3D, sock_name: String, pos: Vector3, label_txt: String, slot_kind: String, att_id: String = "") -> Node3D:
	var n := Node3D.new()
	n.name = sock_name
	n.position = pos
	n.set_meta("label", label_txt)
	n.set_meta("slot_kind", slot_kind)
	n.set_meta("att_id", att_id)
	parent.add_child(n)
	return n


static func decorate_viewmodel(gun_model: Node, w_id: String, cfg: Dictionary) -> void:
	if not is_instance_valid(gun_model):
		return
	var old_dec := gun_model.get_node_or_null("CustomDecor")
	if is_instance_valid(old_dec):
		old_dec.queue_free()

	var style: Dictionary = cfg.get("style", {})
	var cls := String(cfg.get("class", "rifle"))
	var atts: Array = cfg.get("attachments", [])
	var muzzle_v: Vector2 = cfg.get("muzzle", Vector2(0.04, 0.65))
	var muzzle_y := muzzle_v.x
	var muzzle_z := -muzzle_v.y
	var mats := _resolve_camo_mats(w_id, cfg)
	var primary_mat: Material = mats["primary"]
	var accent_mat: Material = mats["accent"]
	var barrel_mat: Material = mats["barrel"]
	var dark_mat: Material = mats["dark"]
	var grip_mat: Material = mats["grip"]
	var wrap_mat: Material = mats["wrap"]
	var wood_mat: Material = mats["wood"]
	var brass_mat: Material = mats["brass"]
	var crimson_mat: Material = mats["crimson"]

	var model_path := String(cfg.get("model", ""))
	var is_lmg_glb := model_path.ends_with("vm_lmg.glb")
	var is_shotgun_glb := model_path.ends_with("vm_shotgun.glb")
	var is_pistol_glb := model_path.ends_with("vm_pistol.glb")
	var is_revolver_glb := model_path.ends_with("vm_revolver.glb")
	var is_smg_glb := model_path.ends_with("vm_smg.glb")
	var is_sniper_glb := model_path.ends_with("vm_sniper.glb")
	var is_volt_glb := model_path.ends_with("vm_volt.glb")
	var is_scoped := bool(cfg.get("scoped", false)) or is_sniper_glb
	var is_preview := bool(cfg.get("gunsmith_preview", false))

	var optic_kind := String(style.get("optic", ""))
	if "red_dot" in atts and not is_scoped:
		if optic_kind == "":
			optic_kind = "red_dot"
	if is_scoped:
		optic_kind = "sniper_scope"
	elif is_volt_glb and optic_kind == "":
		optic_kind = "volt_holo"

	if gun_model is Node3D:
		var sc: Vector3 = style.get("scale", Vector3.ONE)
		(gun_model as Node3D).scale = sc

	# Apply real PBR materials across all weapon GLB parts (never touching Arm* / Hand* sleeves or gloves)
	var hide_base := bool(style.get("rpg_tube", false)) or bool(style.get("gl_barrel", false))
	var hide_irons := (optic_kind != "" and not is_scoped)
	var idx := 0
	for child in gun_model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or _is_arm_or_hand(mi):
			continue
		if hide_base:
			mi.visible = false
			continue
		var nm := mi.name
		if hide_irons and nm in ["FrontPost", "FrontSight", "RearSight", "RearSight.001", "RearEar", "RearEar.001", "Bead"]:
			mi.visible = false
			continue
		else:
			mi.visible = true
		if is_lmg_glb and nm in ["CarryHandle", "HandlePost", "HandlePost.001"]:
			# Fold M249 carry handle flush against right side of receiver so sightlines stay clear
			var fold_b := Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(-68.0)))
			mi.basis = fold_b
			mi.position = Vector3(0.022, 0.084, 0.0) - fold_b * Vector3(0.0, 0.088, 0.0)
		if nm in ["Barrel", "OpRod", "Cylinder", "BoltKnob", "Bolt"]:
			mi.material_override = barrel_mat
		elif nm in ["Stock", "PistolGrip", "Pump", "Grip"]:
			mi.material_override = accent_mat
		elif nm in ["Mag", "Magazine"]:
			mi.material_override = dark_mat
		elif nm in ["FrontPost", "RearEar", "RearEar.001", "FrontSight", "RearSight", "RearSight.001"]:
			mi.material_override = dark_mat
		else:
			mi.material_override = primary_mat if idx % 3 != 2 else accent_mat
		idx += 1

	var decor := Node3D.new()
	decor.name = "CustomDecor"
	gun_model.add_child(decor)

	var rail_top_y := 0.067
	if is_lmg_glb:
		rail_top_y = 0.088
	elif is_pistol_glb or is_revolver_glb:
		rail_top_y = 0.062
	elif is_smg_glb:
		rail_top_y = 0.066
	elif is_shotgun_glb:
		rail_top_y = 0.064
	elif is_volt_glb:
		rail_top_y = 0.108
	elif is_sniper_glb:
		rail_top_y = 0.075

	var iron_y := 0.0748
	var iron_z := -0.18
	if is_pistol_glb:
		iron_y = 0.0715
		iron_z = -0.09
	elif is_revolver_glb:
		iron_y = 0.0705
		iron_z = -0.10
	elif is_smg_glb:
		iron_y = 0.0725
		iron_z = -0.16
	elif is_shotgun_glb:
		iron_y = 0.0730
		iron_z = -0.22
	elif is_lmg_glb:
		iron_y = 0.1090
		iron_z = -0.22
	elif is_sniper_glb:
		iron_y = 0.1150
		iron_z = -0.20
	elif is_volt_glb:
		iron_y = 0.1250
		iron_z = -0.18

	# Structural chassis enhancements to eliminate floating sights and keep rails clear of sightlines
	if not hide_base:
		_add_structural_chassis(decor, w_id, cls, style, muzzle_y, muzzle_z, rail_top_y, atts, mats)

	var has_supp := bool(style.get("suppressor", false)) or ("suppressor" in atts)
	var has_hvy := bool(style.get("long_barrel", false)) or ("heavy_barrel" in atts)
	var tip_z := muzzle_z

	# 1. Extended / Heavy Match Barrel + Dual-Chamber Muzzle Brake
	if has_hvy and not hide_base:
		var ext_len := 0.14
		var br := CylinderMesh.new()
		br.top_radius = 0.0110
		br.bottom_radius = 0.0120
		br.height = ext_len
		_add_mesh(decor, "HeavyBarrel", br, Vector3(0.0, muzzle_y, muzzle_z - ext_len * 0.42), Vector3(PI * 0.5, 0.0, 0.0), barrel_mat)
		if not has_supp:
			var brake := BoxMesh.new()
			brake.size = Vector3(0.022, 0.020, 0.042)
			_add_mesh(decor, "MuzzleBrake", brake, Vector3(0.0, muzzle_y, muzzle_z - ext_len * 0.88), Vector3.ZERO, dark_mat)
			_add_socket(decor, "Socket_Barrel", Vector3(0.0, muzzle_y, muzzle_z - ext_len * 0.55), "HEAVY BARREL", "barrel", "heavy_barrel")
		tip_z = muzzle_z - ext_len * 0.85

	# 2. Monolithic Tactical Suppressor (slimmer pistol profile so iron sights stay unobstructed)
	if has_supp and not hide_base:
		var s_len := 0.155 if cls == "pistol" else 0.175
		var s_z := tip_z - s_len * 0.44
		var r_supp := 0.0150 if cls == "pistol" else 0.0185
		var collar := CylinderMesh.new()
		collar.top_radius = r_supp * 0.78
		collar.bottom_radius = r_supp * 0.78
		collar.height = 0.022
		_add_mesh(decor, "SuppCollar", collar, Vector3(0.0, muzzle_y, tip_z - 0.008), Vector3(PI * 0.5, 0.0, 0.0), barrel_mat)
		var cy := CylinderMesh.new()
		cy.top_radius = r_supp
		cy.bottom_radius = r_supp
		cy.height = s_len
		_add_mesh(decor, "Suppressor", cy, Vector3(0.0, muzzle_y, s_z), Vector3(PI * 0.5, 0.0, 0.0), dark_mat)
		var sleeve := CylinderMesh.new()
		sleeve.top_radius = r_supp + 0.0012
		sleeve.bottom_radius = r_supp + 0.0012
		sleeve.height = s_len * 0.66
		_add_mesh(decor, "SuppWrap", sleeve, Vector3(0.0, muzzle_y, s_z + 0.005), Vector3(PI * 0.5, 0.0, 0.0), wrap_mat)
		var ring_f := CylinderMesh.new()
		ring_f.top_radius = r_supp + 0.0010
		ring_f.bottom_radius = r_supp + 0.0010
		ring_f.height = 0.012
		_add_mesh(decor, "SuppCap", ring_f, Vector3(0.0, muzzle_y, s_z - s_len * 0.46), Vector3(PI * 0.5, 0.0, 0.0), barrel_mat)
		_add_socket(decor, "Socket_Muzzle", Vector3(0.0, muzzle_y, s_z), "SUPPRESSOR", "muzzle", "suppressor")

	# 3. Optics (Reflex Red Dot / Holo / Hollow 3D ACOG / Volt Arch / Open Iron Bead)
	var sight_anchor_pos := Vector3(0.0, iron_y, iron_z)
	var glass_alpha := 0.22 if is_preview else 0.05
	var opt_z := clampf(muzzle_z * 0.28, -0.24, -0.05)
	if is_shotgun_glb and optic_kind == "" and not hide_base:
		# Clean ghost-ring rear ears + glowing green fiber-optic front bead for shotguns without optics
		for sx in [-1.0, 1.0]:
			var ear := BoxMesh.new()
			ear.size = Vector3(0.0032, 0.012, 0.014)
			_add_mesh(decor, "ShotgunRearEar_%d" % int(sx), ear, Vector3(sx * 0.0085, iron_y - 0.001, -0.14), Vector3.ZERO, dark_mat)
		var rear_bar := BoxMesh.new()
		rear_bar.size = Vector3(0.018, 0.003, 0.014)
		_add_mesh(decor, "ShotgunRearBase", rear_bar, Vector3(0.0, rail_top_y + 0.002, -0.14), Vector3.ZERO, dark_mat)
		var f_base := BoxMesh.new()
		f_base.size = Vector3(0.006, 0.007, 0.014)
		_add_mesh(decor, "ShotgunFrontBase", f_base, Vector3(0.0, iron_y - 0.005, muzzle_z + 0.06), Vector3.ZERO, dark_mat)
		var bead := SphereMesh.new()
		bead.radius = 0.0022
		bead.height = 0.0044
		var b_mi := _add_mesh(decor, "ShotgunFiberBead", bead, Vector3(0.0, iron_y, muzzle_z + 0.06), Vector3.ZERO, _emissive_mat(Color(0.28, 1.0, 0.42), 2.4, 1.0, true))
		b_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sight_anchor_pos = Vector3(0.0, iron_y, -0.14)
	elif optic_kind != "" and optic_kind != "sniper_scope" and not hide_base:
		var ret_y := rail_top_y + 0.018
		if optic_kind == "acog":
			ret_y = rail_top_y + 0.024
			# Hollow octagonal 3D ACOG tube (zero solid bore obstruction)
			var tube_r := 0.0175
			var tube_len := 0.115
			var seg_w := 0.0152
			for si in range(8):
				var ang := float(si) * (TAU / 8.0) + (PI / 8.0)
				var wall := BoxMesh.new()
				wall.size = Vector3(seg_w, 0.0032, tube_len)
				var wx := sin(ang) * tube_r
				var wy := cos(ang) * tube_r
				_add_mesh(decor, "AcogShell_%d" % si, wall, Vector3(wx, ret_y + wy, opt_z), Vector3(0.0, 0.0, -ang), dark_mat)
			# Objective front bezel ring + mounting clamps
			for rz in [opt_z - 0.026, opt_z + 0.026]:
				var mount_b := BoxMesh.new()
				mount_b.size = Vector3(0.022, 0.010, 0.016)
				_add_mesh(decor, "AcogMount", mount_b, Vector3(0.0, rail_top_y + 0.004, rz), Vector3.ZERO, barrel_mat)
			var f_lens := CylinderMesh.new()
			f_lens.top_radius = 0.0155
			f_lens.bottom_radius = 0.0155
			f_lens.height = 0.0025
			var fl_mi := _add_mesh(decor, "AcogFrontLens", f_lens, Vector3(0.0, ret_y, opt_z - tube_len * 0.46), Vector3(PI * 0.5, 0.0, 0.0), _glass_mat(Color(0.18, 0.86, 1.0, glass_alpha)))
			fl_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Glowing unshaded red chevron + 3 BDC holdover ticks
			var chev_mat := _emissive_mat(Color(1.0, 0.20, 0.14), 3.2, 1.0, true)
			for side in [-1.0, 1.0]:
				var leg := BoxMesh.new()
				leg.size = Vector3(0.0008, 0.0040, 0.0008)
				var lm := _add_mesh(decor, "AcogChev_%d" % int(side), leg, Vector3(side * 0.0012, ret_y - 0.0012, opt_z - 0.004), Vector3(0.0, 0.0, -side * 0.62), chev_mat)
				lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var apex := SphereMesh.new()
			apex.radius = 0.0008
			apex.height = 0.0016
			var am := _add_mesh(decor, "AcogChevApex", apex, Vector3(0.0, ret_y, opt_z - 0.004), Vector3.ZERO, chev_mat)
			am.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for bi in range(3):
				var tick := BoxMesh.new()
				tick.size = Vector3(0.0024 - float(bi) * 0.0004, 0.0006, 0.0006)
				var tm := _add_mesh(decor, "AcogBdc_%d" % bi, tick, Vector3(0.0, ret_y - 0.0032 - float(bi) * 0.0024, opt_z - 0.004), Vector3.ZERO, chev_mat)
				tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sight_anchor_pos = Vector3(0.0, ret_y, opt_z - 0.004)
			_add_socket(decor, "Socket_Optic", Vector3(0.0, ret_y + 0.012, opt_z), "ACOG 4x OPTIC", "optic", "red_dot")
		elif optic_kind == "volt_holo":
			ret_y = 0.125
			var base := BoxMesh.new()
			base.size = Vector3(0.024, 0.006, 0.044)
			_add_mesh(decor, "VoltOpticBase", base, Vector3(0.0, rail_top_y + 0.002, opt_z), Vector3.ZERO, dark_mat)
			for sx in [-1.0, 1.0]:
				var post := BoxMesh.new()
				post.size = Vector3(0.0036, 0.026, 0.036)
				_add_mesh(decor, "VoltOpticPost_%d" % int(sx), post, Vector3(sx * 0.014, ret_y - 0.001, opt_z), Vector3(0.0, 0.0, -sx * 0.12), accent_mat)
			var arch := BoxMesh.new()
			arch.size = Vector3(0.028, 0.0036, 0.036)
			_add_mesh(decor, "VoltOpticArch", arch, Vector3(0.0, ret_y + 0.014, opt_z), Vector3.ZERO, dark_mat)
			var vpane := BoxMesh.new()
			vpane.size = Vector3(0.022, 0.020, 0.002)
			var vp_mi := _add_mesh(decor, "OpticGlass", vpane, Vector3(0.0, ret_y, opt_z - 0.012), Vector3.ZERO, _glass_mat(Color(0.24, 0.90, 1.0, glass_alpha)))
			vp_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var cmat := _emissive_mat(Color(0.24, 0.92, 1.0), 3.4, 1.0, true)
			var vdot := SphereMesh.new()
			vdot.radius = 0.0015
			vdot.height = 0.0030
			var vd_mi := _add_mesh(decor, "OpticReticle", vdot, Vector3(0.0, ret_y, opt_z), Vector3.ZERO, cmat)
			vd_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for sx in [-1.0, 1.0]:
				var wing := BoxMesh.new()
				wing.size = Vector3(0.0045, 0.0008, 0.0008)
				var wm := _add_mesh(decor, "VoltRetWing_%d" % int(sx), wing, Vector3(sx * 0.0055, ret_y, opt_z), Vector3.ZERO, cmat)
				wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sight_anchor_pos = Vector3(0.0, ret_y, opt_z)
			_add_socket(decor, "Socket_Optic", Vector3(0.0, ret_y + 0.014, opt_z), "VOLT HOLO OPTIC", "optic", "red_dot")
		elif optic_kind == "holo":
			ret_y = rail_top_y + 0.020
			var riser := BoxMesh.new()
			riser.size = Vector3(0.030, 0.008, 0.054)
			_add_mesh(decor, "OpticRiser", riser, Vector3(0.0, rail_top_y + 0.003, opt_z), Vector3.ZERO, dark_mat)
			for sx in [-1.0, 1.0]:
				var wall := BoxMesh.new()
				wall.size = Vector3(0.0042, 0.028, 0.048)
				_add_mesh(decor, "OpticWall_%d" % int(sx), wall, Vector3(sx * 0.0155, ret_y, opt_z), Vector3.ZERO, dark_mat)
			var hood := BoxMesh.new()
			hood.size = Vector3(0.035, 0.0042, 0.048)
			_add_mesh(decor, "OpticHood", hood, Vector3(0.0, ret_y + 0.0155, opt_z), Vector3.ZERO, barrel_mat)
			var pane := BoxMesh.new()
			pane.size = Vector3(0.026, 0.022, 0.002)
			var p_mi := _add_mesh(decor, "OpticGlass", pane, Vector3(0.0, ret_y, opt_z - 0.015), Vector3.ZERO, _glass_mat(Color(0.24, 0.85, 0.98, glass_alpha)))
			p_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var hmat := _emissive_mat(Color(1.0, 0.24, 0.16), 3.4, 1.0, true)
			var dot := SphereMesh.new()
			dot.radius = 0.0013
			dot.height = 0.0026
			var d_mi := _add_mesh(decor, "OpticReticle", dot, Vector3(0.0, ret_y, opt_z - 0.002), Vector3.ZERO, hmat)
			d_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for tpos in [Vector2(0.0, 0.0068), Vector2(0.0, -0.0068), Vector2(0.0068, 0.0), Vector2(-0.0068, 0.0)]:
				var tick := BoxMesh.new()
				tick.size = Vector3(0.0012 if absf(tpos.x) < 0.001 else 0.0036, 0.0036 if absf(tpos.x) < 0.001 else 0.0012, 0.0008)
				var tm := _add_mesh(decor, "HoloTick", tick, Vector3(tpos.x, ret_y + tpos.y, opt_z - 0.002), Vector3.ZERO, hmat)
				tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sight_anchor_pos = Vector3(0.0, ret_y, opt_z - 0.002)
			_add_socket(decor, "Socket_Optic", Vector3(0.0, ret_y + 0.014, opt_z), "EOTECH HOLO", "optic", "red_dot")
		else:
			# Machined Reflex Red Dot with open frame & unshaded floating reticle
			ret_y = rail_top_y + 0.018
			var riser := BoxMesh.new()
			riser.size = Vector3(0.025, 0.007, 0.048)
			_add_mesh(decor, "OpticRiser", riser, Vector3(0.0, rail_top_y + 0.002, opt_z), Vector3.ZERO, dark_mat)
			for sx in [-1.0, 1.0]:
				var wall := BoxMesh.new()
				wall.size = Vector3(0.0034, 0.024, 0.040)
				_add_mesh(decor, "OpticWall_%d" % int(sx), wall, Vector3(sx * 0.0128, ret_y, opt_z), Vector3.ZERO, barrel_mat)
			var hood := BoxMesh.new()
			hood.size = Vector3(0.029, 0.0036, 0.040)
			_add_mesh(decor, "OpticHood", hood, Vector3(0.0, ret_y + 0.0135, opt_z), Vector3.ZERO, dark_mat)
			var pane := BoxMesh.new()
			pane.size = Vector3(0.021, 0.020, 0.002)
			var p_mi := _add_mesh(decor, "OpticGlass", pane, Vector3(0.0, ret_y, opt_z - 0.013), Vector3.ZERO, _glass_mat(Color(0.24, 0.85, 0.98, glass_alpha)))
			p_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var dot := SphereMesh.new()
			dot.radius = 0.0015
			dot.height = 0.0030
			var d_mi := _add_mesh(decor, "OpticReticle", dot, Vector3(0.0, ret_y, opt_z - 0.002), Vector3.ZERO, _emissive_mat(Color(1.0, 0.22, 0.16), 3.6, 1.0, true))
			d_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sight_anchor_pos = Vector3(0.0, ret_y, opt_z - 0.002)
			_add_socket(decor, "Socket_Optic", Vector3(0.0, ret_y + 0.013, opt_z), "REFLEX RED DOT", "optic", "red_dot")

	# 4. Extended / Drum Magazine, Angled Quickdraw Foregrip, AN/PEQ-15 Laser & Ammo Tech
	var mag_z := clampf(muzzle_z * 0.34, -0.24, -0.06)
	if bool(style.get("ext_mag", false)) or ("ext_mag" in atts):
		var mag := BoxMesh.new()
		mag.size = Vector3(0.024, 0.125, 0.044)
		_add_mesh(decor, "ExtMag", mag, Vector3(0.0, muzzle_y - 0.102, mag_z), Vector3(-0.22, 0.0, 0.0), dark_mat)
		var base := BoxMesh.new()
		base.size = Vector3(0.028, 0.016, 0.050)
		_add_mesh(decor, "ExtMagBase", base, Vector3(0.0, muzzle_y - 0.162, mag_z - 0.014), Vector3(-0.22, 0.0, 0.0), primary_mat)
		_add_socket(decor, "Socket_Mag", Vector3(0.0, muzzle_y - 0.135, mag_z - 0.008), "EXTENDED MAG", "mag", "ext_mag")

	if bool(style.get("drum_mag", false)):
		var drum := CylinderMesh.new()
		drum.top_radius = 0.056
		drum.bottom_radius = 0.056
		drum.height = 0.046
		_add_mesh(decor, "DrumMag", drum, Vector3(0.0, muzzle_y - 0.075, mag_z - 0.02), Vector3(PI * 0.5, 0.0, 0.0), dark_mat)
		var cap := CylinderMesh.new()
		cap.top_radius = 0.030
		cap.bottom_radius = 0.030
		cap.height = 0.050
		_add_mesh(decor, "DrumCenter", cap, Vector3(0.0, muzzle_y - 0.075, mag_z - 0.02), Vector3(PI * 0.5, 0.0, 0.0), barrel_mat)

	if bool(style.get("foregrip", false)) or ("quickdraw" in atts):
		var fg_z := clampf(muzzle_z * 0.60, -0.44, -0.14)
		var clamp_b := BoxMesh.new()
		clamp_b.size = Vector3(0.024, 0.014, 0.040)
		_add_mesh(decor, "ForegripBase", clamp_b, Vector3(0.0, muzzle_y - 0.028, fg_z), Vector3.ZERO, dark_mat)
		var fg := CylinderMesh.new()
		fg.top_radius = 0.013
		fg.bottom_radius = 0.011
		fg.height = 0.078
		_add_mesh(decor, "Foregrip", fg, Vector3(0.0, muzzle_y - 0.064, fg_z - 0.006), Vector3(-0.24 if "quickdraw" in atts else 0.0, 0.0, 0.0), grip_mat)
		if "quickdraw" in atts:
			_add_socket(decor, "Socket_Underbarrel", Vector3(0.0, muzzle_y - 0.068, fg_z - 0.006), "QUICKDRAW GRIP", "underbarrel", "quickdraw")

	if "tac_laser" in atts:
		var lz_z := clampf(muzzle_z * 0.68, -0.50, -0.15)
		var lbox := BoxMesh.new()
		lbox.size = Vector3(0.022, 0.018, 0.058)
		_add_mesh(decor, "LaserPod", lbox, Vector3(0.024, minf(muzzle_y - 0.004, rail_top_y - 0.014), lz_z), Vector3.ZERO, barrel_mat)
		var emitter := CylinderMesh.new()
		emitter.top_radius = 0.0052
		emitter.bottom_radius = 0.0052
		emitter.height = 0.010
		_add_mesh(decor, "LaserLens", emitter, Vector3(0.028, minf(muzzle_y - 0.002, rail_top_y - 0.012), lz_z - 0.030), Vector3(PI * 0.5, 0.0, 0.0), _emissive_mat(Color(0.28, 1.0, 0.42), 3.0, 1.0, true))
		if is_preview:
			var beam := CylinderMesh.new()
			beam.top_radius = 0.0018
			beam.bottom_radius = 0.0018
			beam.height = 0.36
			_add_mesh(decor, "GunsmithLaserBeam", beam, Vector3(0.028, minf(muzzle_y - 0.002, rail_top_y - 0.012), lz_z - 0.215), Vector3(PI * 0.5, 0.0, 0.0), _emissive_mat(Color(0.28, 1.0, 0.42), 2.2, 0.36, true))
		_add_socket(decor, "Socket_Laser", Vector3(0.028, minf(muzzle_y - 0.002, rail_top_y - 0.012), lz_z), "TAC-LASER", "laser", "tac_laser")

	if "fmj" in atts and not hide_base:
		var fmj_z := clampf(muzzle_z * 0.48, -0.36, -0.10)
		var band := BoxMesh.new()
		band.size = Vector3(0.032, 0.016, 0.024)
		_add_mesh(decor, "FmjBand", band, Vector3(0.0, muzzle_y - 0.012, fmj_z), Vector3.ZERO, brass_mat)
		_add_socket(decor, "Socket_Ammo_FMJ", Vector3(0.0, muzzle_y - 0.012, fmj_z), "FMJ AP AMMO", "ammo", "fmj")

	if "overpressured" in atts and not hide_base:
		var collar_p := CylinderMesh.new()
		collar_p.top_radius = 0.0145
		collar_p.bottom_radius = 0.0145
		collar_p.height = 0.024
		_add_mesh(decor, "OverpressuredCollar", collar_p, Vector3(0.0, muzzle_y, clampf(muzzle_z * 0.78, -0.62, -0.16)), Vector3(PI * 0.5, 0.0, 0.0), crimson_mat)
		_add_socket(decor, "Socket_Ammo_PlusP", Vector3(0.0, muzzle_y, clampf(muzzle_z * 0.78, -0.62, -0.16)), "+P ROUNDS", "ammo", "overpressured")

	# 5. Radical Special Silhouettes (RPG-7V2, M79/M32 GL, Crossbow, M134 Rotary) + Launcher Sights
	if bool(style.get("rpg_tube", false)):
		var tube_mat: Material = primary_mat
		var shield_mat: Material = wood_mat if String(cfg.get("camo", "factory")) in ["factory", "woodland", "survivor"] else accent_mat
		var warhead_mat := _pbr_mat("camo", 3.2, Color(0.32, 0.40, 0.24), 0.50, 0.28)
		var cone_mat := barrel_mat
		var tube := CylinderMesh.new()
		tube.top_radius = 0.029
		tube.bottom_radius = 0.029
		tube.height = 0.94
		_add_mesh(decor, "RpgTube", tube, Vector3(0.0, muzzle_y, -0.27), Vector3(PI * 0.5, 0.0, 0.0), tube_mat)
		var venturi := CylinderMesh.new()
		venturi.top_radius = 0.027
		venturi.bottom_radius = 0.046
		venturi.height = 0.10
		_add_mesh(decor, "RpgVenturi", venturi, Vector3(0.0, muzzle_y, 0.23), Vector3(-PI * 0.5, 0.0, 0.0), barrel_mat)
		var sleeve := CylinderMesh.new()
		sleeve.top_radius = 0.0355
		sleeve.bottom_radius = 0.0355
		sleeve.height = 0.26
		_add_mesh(decor, "RpgHeatShield", sleeve, Vector3(0.0, muzzle_y, -0.30), Vector3(PI * 0.5, 0.0, 0.0), shield_mat)
		for rz in [-0.43, -0.17]:
			var clamp_r := CylinderMesh.new()
			clamp_r.top_radius = 0.0368
			clamp_r.bottom_radius = 0.0368
			clamp_r.height = 0.016
			_add_mesh(decor, "RpgClamp", clamp_r, Vector3(0.0, muzzle_y, rz), Vector3(PI * 0.5, 0.0, 0.0), dark_mat)
		var grip := BoxMesh.new()
		grip.size = Vector3(0.025, 0.084, 0.036)
		_add_mesh(decor, "RpgGrip", grip, Vector3(0.0, muzzle_y - 0.056, -0.02), Vector3(0.2, 0.0, 0.0), grip_mat)
		var fgrip := BoxMesh.new()
		fgrip.size = Vector3(0.025, 0.078, 0.034)
		_add_mesh(decor, "RpgForeGrip", fgrip, Vector3(0.0, muzzle_y - 0.056, -0.35), Vector3(0.16, 0.0, 0.0), grip_mat)
		if optic_kind == "red_dot":
			var r_y := muzzle_y + 0.054
			var r_riser := BoxMesh.new()
			r_riser.size = Vector3(0.024, 0.010, 0.048)
			_add_mesh(decor, "OpticRiser", r_riser, Vector3(0.0, muzzle_y + 0.038, -0.20), Vector3.ZERO, dark_mat)
			for sx in [-1.0, 1.0]:
				var w := BoxMesh.new()
				w.size = Vector3(0.0034, 0.024, 0.040)
				_add_mesh(decor, "OpticWall_%d" % int(sx), w, Vector3(sx * 0.0128, r_y, -0.20), Vector3.ZERO, barrel_mat)
			var hd := BoxMesh.new()
			hd.size = Vector3(0.029, 0.0036, 0.040)
			_add_mesh(decor, "OpticHood", hd, Vector3(0.0, r_y + 0.0135, -0.20), Vector3.ZERO, dark_mat)
			var dot_r := SphereMesh.new()
			dot_r.radius = 0.0016
			dot_r.height = 0.0032
			var dm_r := _add_mesh(decor, "OpticReticle", dot_r, Vector3(0.0, r_y, -0.202), Vector3.ZERO, _emissive_mat(Color(1.0, 0.22, 0.16), 3.6, 1.0, true))
			dm_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sight_anchor_pos = Vector3(0.0, r_y, -0.202)
		else:
			# Open rear notch + hooded front post clear of warhead cone (top at muzzle_y + 0.046)
			var r_y := muzzle_y + 0.058
			for sx in [-1.0, 1.0]:
				var rear_e := BoxMesh.new()
				rear_e.size = Vector3(0.004, 0.018, 0.010)
				_add_mesh(decor, "RpgRearNotch_%d" % int(sx), rear_e, Vector3(sx * 0.0065, r_y - 0.005, -0.18), Vector3.ZERO, dark_mat)
			var r_base := BoxMesh.new()
			r_base.size = Vector3(0.018, 0.014, 0.010)
			_add_mesh(decor, "RpgRearBase", r_base, Vector3(0.0, muzzle_y + 0.042, -0.18), Vector3.ZERO, dark_mat)
			var f_base := BoxMesh.new()
			f_base.size = Vector3(0.004, 0.022, 0.012)
			_add_mesh(decor, "RpgFrontPost", f_base, Vector3(0.0, muzzle_y + 0.046, -0.58), Vector3.ZERO, dark_mat)
			var f_pip := SphereMesh.new()
			f_pip.radius = 0.0018
			f_pip.height = 0.0036
			var fp_mi := _add_mesh(decor, "RpgFrontTritium", f_pip, Vector3(0.0, r_y, -0.58), Vector3.ZERO, _emissive_mat(Color(0.32, 1.0, 0.45), 2.8, 1.0, true))
			fp_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sight_anchor_pos = Vector3(0.0, r_y, -0.18)
		var warhead := Node3D.new()
		warhead.name = "RocketWarhead"
		warhead.position = Vector3(0.0, muzzle_y, -0.78)
		decor.add_child(warhead)
		var stem := CylinderMesh.new()
		stem.top_radius = 0.018
		stem.bottom_radius = 0.020
		stem.height = 0.14
		_add_mesh(warhead, "WarheadStem", stem, Vector3(0.0, 0.0, 0.03), Vector3(PI * 0.5, 0.0, 0.0), warhead_mat)
		var bulb := CylinderMesh.new()
		bulb.top_radius = 0.010
		bulb.bottom_radius = 0.046
		bulb.height = 0.115
		_add_mesh(warhead, "WarheadCone", bulb, Vector3(0.0, 0.0, -0.092), Vector3(-PI * 0.5, 0.0, 0.0), cone_mat)
		var tail := CylinderMesh.new()
		tail.top_radius = 0.018
		tail.bottom_radius = 0.046
		tail.height = 0.08
		_add_mesh(warhead, "WarheadTail", tail, Vector3(0.0, 0.0, 0.005), Vector3(PI * 0.5, 0.0, 0.0), warhead_mat)
		_add_socket(decor, "Socket_Muzzle", Vector3(0.0, muzzle_y, -0.84), "PG-7V WARHEAD", "muzzle", "warhead")

	elif bool(style.get("gl_barrel", false)):
		var gbarrel := CylinderMesh.new()
		gbarrel.top_radius = 0.027
		gbarrel.bottom_radius = 0.029
		gbarrel.height = 0.36
		_add_mesh(decor, "GLBarrel", gbarrel, Vector3(0.0, muzzle_y, -0.44), Vector3(PI * 0.5, 0.0, 0.0), barrel_mat)
		var shroud := BoxMesh.new()
		shroud.size = Vector3(0.044, 0.022, 0.24)
		_add_mesh(decor, "GLShroud", shroud, Vector3(0.0, muzzle_y - 0.022, -0.40), Vector3.ZERO, accent_mat)
		var receiver := BoxMesh.new()
		receiver.size = Vector3(0.048, 0.070, 0.25)
		_add_mesh(decor, "GLReceiver", receiver, Vector3(0.0, muzzle_y - 0.015, -0.22), Vector3.ZERO, primary_mat)
		var gl_stock := BoxMesh.new()
		gl_stock.size = Vector3(0.034, 0.056, 0.18)
		_add_mesh(decor, "GLStock", gl_stock, Vector3(0.0, muzzle_y - 0.020, -0.01), Vector3(-0.08, 0.0, 0.0), accent_mat)
		var grip := BoxMesh.new()
		grip.size = Vector3(0.026, 0.086, 0.038)
		_add_mesh(decor, "GLGrip", grip, Vector3(0.0, muzzle_y - 0.076, -0.15), Vector3(0.25, 0.0, 0.0), grip_mat)
		if bool(style.get("drum_mag", false)):
			var rot_drum := CylinderMesh.new()
			rot_drum.top_radius = 0.058
			rot_drum.bottom_radius = 0.058
			rot_drum.height = 0.115
			_add_mesh(decor, "GLDrum", rot_drum, Vector3(0.0, muzzle_y - 0.008, -0.25), Vector3(PI * 0.5, 0.0, 0.0), dark_mat)
			_add_socket(decor, "Socket_Mag", Vector3(0.0, muzzle_y - 0.008, -0.25), "6-RD 40MM DRUM", "mag", "drum")
		var gl_top := muzzle_y + (0.054 if bool(style.get("drum_mag", false)) else 0.029)
		if optic_kind == "red_dot":
			var g_y := gl_top + 0.018
			var griser := BoxMesh.new()
			griser.size = Vector3(0.024, 0.008, 0.048)
			_add_mesh(decor, "OpticRiser", griser, Vector3(0.0, gl_top + 0.003, -0.20), Vector3.ZERO, dark_mat)
			for sx in [-1.0, 1.0]:
				var gw := BoxMesh.new()
				gw.size = Vector3(0.0034, 0.024, 0.040)
				_add_mesh(decor, "OpticWall_%d" % int(sx), gw, Vector3(sx * 0.0128, g_y, -0.20), Vector3.ZERO, barrel_mat)
			var ghd := BoxMesh.new()
			ghd.size = Vector3(0.029, 0.0036, 0.040)
			_add_mesh(decor, "OpticHood", ghd, Vector3(0.0, g_y + 0.0135, -0.20), Vector3.ZERO, dark_mat)
			var gdot := SphereMesh.new()
			gdot.radius = 0.0016
			gdot.height = 0.0032
			var gdm := _add_mesh(decor, "OpticReticle", gdot, Vector3(0.0, g_y, -0.202), Vector3.ZERO, _emissive_mat(Color(1.0, 0.22, 0.16), 3.6, 1.0, true))
			gdm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sight_anchor_pos = Vector3(0.0, g_y, -0.202)
		else:
			# Quadrant flip-up ladder sight + glowing front leaf post
			var l_y := gl_top + 0.016
			for sx in [-1.0, 1.0]:
				var post := BoxMesh.new()
				post.size = Vector3(0.0032, 0.024, 0.006)
				_add_mesh(decor, "GLLadderPost_%d" % int(sx), post, Vector3(sx * 0.009, l_y - 0.004, -0.18), Vector3.ZERO, dark_mat)
			var rung := BoxMesh.new()
			rung.size = Vector3(0.020, 0.0022, 0.004)
			_add_mesh(decor, "GLLadderRung", rung, Vector3(0.0, l_y + 0.006, -0.18), Vector3.ZERO, dark_mat)
			var fpip := SphereMesh.new()
			fpip.radius = 0.0016
			fpip.height = 0.0032
			var fpm := _add_mesh(decor, "GLFrontBead", fpip, Vector3(0.0, l_y, -0.52), Vector3.ZERO, _emissive_mat(Color(1.0, 0.56, 0.16), 2.8, 1.0, true))
			fpm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sight_anchor_pos = Vector3(0.0, l_y, -0.18)

	if bool(style.get("xbow_limbs", false)):
		var prod := BoxMesh.new()
		prod.size = Vector3(0.44, 0.014, 0.030)
		_add_mesh(decor, "BowLimb", prod, Vector3(0.0, muzzle_y + 0.004, muzzle_z + 0.08), Vector3.ZERO, dark_mat)
		for sx in [-1.0, 1.0]:
			var cam := CylinderMesh.new()
			cam.top_radius = 0.022
			cam.bottom_radius = 0.022
			cam.height = 0.016
			_add_mesh(decor, "BowCam_%d" % int(sx), cam, Vector3(sx * 0.215, muzzle_y + 0.004, muzzle_z + 0.08), Vector3.ZERO, brass_mat)
		var bolt_tip := CylinderMesh.new()
		bolt_tip.top_radius = 0.001
		bolt_tip.bottom_radius = 0.008
		bolt_tip.height = 0.19
		_add_mesh(decor, "ExplosiveBolt", bolt_tip, Vector3(0.0, muzzle_y + 0.006, muzzle_z - 0.03), Vector3(-PI * 0.5, 0.0, 0.0), crimson_mat)

	if bool(style.get("rotary_barrels", false)):
		var cluster := Node3D.new()
		cluster.name = "RotaryCluster"
		cluster.position = Vector3(0.0, muzzle_y - 0.008, muzzle_z + 0.05)
		decor.add_child(cluster)
		for bi in range(6):
			var ang := float(bi) * TAU / 6.0
			var bx := cos(ang) * 0.024
			var by := sin(ang) * 0.024
			var br := CylinderMesh.new()
			br.top_radius = 0.0068
			br.bottom_radius = 0.0068
			br.height = 0.30
			_add_mesh(cluster, "Bar_%d" % bi, br, Vector3(bx, by, -0.06), Vector3(PI * 0.5, 0.0, 0.0), barrel_mat)
		for cz in [-0.06, -0.17]:
			var clamp_m := CylinderMesh.new()
			clamp_m.top_radius = 0.034
			clamp_m.bottom_radius = 0.034
			clamp_m.height = 0.024
			_add_mesh(cluster, "ClampRing", clamp_m, Vector3(0.0, 0.0, cz), Vector3(PI * 0.5, 0.0, 0.0), accent_mat)

	var sight_anchor := Node3D.new()
	sight_anchor.name = "SightAnchor"
	sight_anchor.position = sight_anchor_pos
	decor.add_child(sight_anchor)
	gun_model.set_meta("optic_kind", optic_kind)
	gun_model.set_meta("sight_anchor_local", sight_anchor_pos)


static func _add_structural_chassis(decor: Node3D, w_id: String, cls: String, _style: Dictionary, muzzle_y: float, muzzle_z: float, rail_top_y: float, atts: Array, mats: Dictionary) -> void:
	var primary_mat: Material = mats["primary"]
	var barrel_mat: Material = mats["barrel"]
	var dark_mat: Material = mats["dark"]
	var has_supp := ("suppressor" in atts)
	var has_hvy := ("heavy_barrel" in atts)
	var max_rail_center := rail_top_y - 0.007

	# Bridge internal barrel + handguard shroud + gas block kept cleanly below sightlines
	if cls in ["rifle", "br", "lmg", "sniper"]:
		var span_z := clampf(-muzzle_z - 0.12, 0.22, 0.72)
		var spine := CylinderMesh.new()
		spine.top_radius = 0.0090
		spine.bottom_radius = 0.0100
		spine.height = span_z
		_add_mesh(decor, "BarrelSpine", spine, Vector3(0.0, minf(muzzle_y - 0.002, rail_top_y - 0.014), -0.12 - span_z * 0.5), Vector3(PI * 0.5, 0.0, 0.0), barrel_mat)

		var hg_len := clampf(span_z * 0.62, 0.16, 0.38)
		var handguard := BoxMesh.new()
		handguard.size = Vector3(0.034, 0.030, hg_len)
		_add_mesh(decor, "ChassisHandguard", handguard, Vector3(0.0, minf(muzzle_y - 0.012, rail_top_y - 0.022), -0.14 - hg_len * 0.5), Vector3.ZERO, primary_mat)

		var rail := BoxMesh.new()
		rail.size = Vector3(0.018, 0.005, hg_len * 1.15)
		_add_mesh(decor, "TopPicatinny", rail, Vector3(0.0, minf(muzzle_y + 0.012, max_rail_center), -0.10 - hg_len * 0.52), Vector3.ZERO, dark_mat)

		var gas_blk := BoxMesh.new()
		gas_blk.size = Vector3(0.020, 0.024, 0.026)
		_add_mesh(decor, "GasBlockCollar", gas_blk, Vector3(0.0, minf(muzzle_y - 0.004, rail_top_y - 0.016), muzzle_z * 0.78), Vector3.ZERO, dark_mat)

		if not has_supp and not has_hvy:
			var flash_hider := CylinderMesh.new()
			flash_hider.top_radius = 0.0115
			flash_hider.bottom_radius = 0.0125
			flash_hider.height = 0.040
			_add_mesh(decor, "MuzzleComp", flash_hider, Vector3(0.0, muzzle_y, muzzle_z + 0.005), Vector3(PI * 0.5, 0.0, 0.0), barrel_mat)
	elif cls == "smg":
		var shroud := BoxMesh.new()
		shroud.size = Vector3(0.032, 0.028, 0.18)
		_add_mesh(decor, "SmgShroud", shroud, Vector3(0.0, minf(muzzle_y - 0.010, rail_top_y - 0.020), -0.22), Vector3.ZERO, primary_mat)
		var rail := BoxMesh.new()
		rail.size = Vector3(0.018, 0.005, 0.20)
		_add_mesh(decor, "SmgRail", rail, Vector3(0.0, minf(muzzle_y + 0.012, max_rail_center), -0.20), Vector3.ZERO, dark_mat)
	elif cls == "shotgun":
		var tube := CylinderMesh.new()
		tube.top_radius = 0.0105
		tube.bottom_radius = 0.0105
		tube.height = clampf(-muzzle_z * 0.65, 0.24, 0.45)
		_add_mesh(decor, "UnderTube", tube, Vector3(0.0, muzzle_y - 0.024, muzzle_z * 0.55), Vector3(PI * 0.5, 0.0, 0.0), barrel_mat)
	elif cls == "pistol" and w_id != "revolver":
		var u_rail := BoxMesh.new()
		u_rail.size = Vector3(0.020, 0.010, 0.09)
		_add_mesh(decor, "PistolRail", u_rail, Vector3(0.0, muzzle_y - 0.018, muzzle_z * 0.68), Vector3.ZERO, dark_mat)


static func _compute_local_aabb(root: Node3D) -> AABB:
	var has_any := false
	var combined := AABB()
	var stack: Array = [[root, root.transform]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var n: Node = pair[0]
		var xf: Transform3D = pair[1]
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.visible and not _is_arm_or_hand(mi) and mi.mesh != null:
				var ma := mi.get_aabb()
				for ci in range(8):
					var corner := ma.get_endpoint(ci)
					var wp := xf * corner
					if not has_any:
						combined = AABB(wp, Vector3.ZERO)
						has_any = true
					else:
						combined = combined.expand(wp)
		for child in n.get_children():
			if child is Node3D and (child as Node3D).visible:
				stack.append([child, xf * (child as Node3D).transform])
			elif not (child is Node3D):
				stack.append([child, xf])
	return combined if has_any else AABB(Vector3(-0.3, -0.1, -0.3), Vector3(0.6, 0.2, 0.6))


static func build_gunsmith_weapon(w_id: String, atts: Array, camo_id: String = "factory") -> Node3D:
	var wcfg: Dictionary = GameState.WEAPONS.get(w_id, GameState.WEAPONS.get("rifle", {})).duplicate(true)
	var mpath := String(wcfg.get("model", "res://assets/models/vm_rifle.glb"))
	var pivot := Node3D.new()
	pivot.name = "GunsmithWeapon"
	if mpath == "" or not ResourceLoader.exists(mpath):
		pivot.set_meta("span", 0.7)
		return pivot
	var packed := load(mpath) as PackedScene
	if packed == null:
		pivot.set_meta("span", 0.7)
		return pivot
	var inst := packed.instantiate() as Node3D
	if inst == null:
		pivot.set_meta("span", 0.7)
		return pivot
	wcfg["attachments"] = atts
	wcfg["camo"] = camo_id
	wcfg["gunsmith_preview"] = true
	decorate_viewmodel(inst, w_id, wcfg)
	_hide_arms_recursive(inst)

	var aabb := _compute_local_aabb(inst)
	inst.position = -aabb.get_center()
	pivot.add_child(inst)
	var max_dim := maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)
	pivot.set_meta("span", clampf(max_dim, 0.34, 1.35))
	return pivot


static func build_world_gun(gun_root: Node3D, w_id: String, camo_id: String = "factory", atts: Array = []) -> Vector3:
	for c in gun_root.get_children():
		gun_root.remove_child(c)
		c.queue_free()

	var cfg: Dictionary = GameState.WEAPONS.get(w_id, GameState.WEAPONS.get("rifle", {})).duplicate(true)
	cfg["camo"] = camo_id
	cfg["attachments"] = atts
	var cls := String(cfg.get("class", "rifle"))
	var style: Dictionary = cfg.get("style", {})
	var mats := _resolve_camo_mats(w_id, cfg)
	var body_mat: Material = mats["primary"]
	var dark_mat: Material = mats["dark"]
	var barrel_mat: Material = mats["barrel"]
	var acc_mat: Material = mats["accent"]

	var body_len := 0.52
	var body_h := 0.085
	var barrel_len := 0.28
	var barrel_r := 0.015

	match cls:
		"pistol":
			body_len = 0.24; body_h = 0.055; barrel_len = 0.12; barrel_r = 0.013
		"smg":
			body_len = 0.38; body_h = 0.075; barrel_len = 0.18; barrel_r = 0.014
		"shotgun":
			body_len = 0.56; body_h = 0.072; barrel_len = 0.34; barrel_r = 0.020
		"lmg":
			body_len = 0.64; body_h = 0.11; barrel_len = 0.36; barrel_r = 0.018
		"sniper", "br":
			body_len = 0.60 if cls == "br" else 0.72
			body_h = 0.08
			barrel_len = 0.34 if cls == "br" else 0.46
			barrel_r = 0.015
		"launcher":
			body_len = 0.76 if w_id == "rpg7" else 0.44
			body_h = 0.085 if w_id == "rpg7" else 0.11
			barrel_len = 0.34
			barrel_r = 0.032 if w_id == "rpg7" else 0.028
		"special":
			body_len = 0.54; body_h = 0.065; barrel_len = 0.20; barrel_r = 0.012
		"wonder":
			body_len = 0.56; body_h = 0.12; barrel_len = 0.26; barrel_r = 0.022

	var body_m := BoxMesh.new()
	body_m.size = Vector3(0.058, body_h, body_len)
	_add_mesh(gun_root, "Body", body_m, Vector3(0.0, 0.0, -body_len * 0.45), Vector3.ZERO, body_mat)

	var barrel_m := CylinderMesh.new()
	barrel_m.top_radius = barrel_r
	barrel_m.bottom_radius = barrel_r
	barrel_m.height = barrel_len
	_add_mesh(gun_root, "Barrel", barrel_m, Vector3(0.0, 0.014, -body_len * 0.85 - barrel_len * 0.4), Vector3(PI * 0.5, 0.0, 0.0), barrel_mat)

	var grip_m := BoxMesh.new()
	grip_m.size = Vector3(0.04, 0.11, 0.045)
	_add_mesh(gun_root, "Grip", grip_m, Vector3(0.0, -0.068, -0.10), Vector3(0.24, 0.0, 0.0), acc_mat)

	if bool(style.get("suppressor", false)) or ("suppressor" in atts):
		var sm := CylinderMesh.new()
		sm.top_radius = 0.020; sm.bottom_radius = 0.020; sm.height = 0.18
		_add_mesh(gun_root, "Suppressor", sm, Vector3(0.0, 0.014, -body_len * 0.85 - barrel_len * 0.85), Vector3(PI * 0.5, 0.0, 0.0), dark_mat)
	if bool(style.get("drum_mag", false)) or cls == "lmg":
		var dm := BoxMesh.new()
		dm.size = Vector3(0.11, 0.11, 0.10)
		_add_mesh(gun_root, "AmmoBox", dm, Vector3(0.0, -0.075, -0.26), Vector3.ZERO, acc_mat)
	if w_id == "rpg7":
		var cone := CylinderMesh.new()
		cone.top_radius = 0.010; cone.bottom_radius = 0.050; cone.height = 0.15
		_add_mesh(gun_root, "RpgWarhead", cone, Vector3(0.0, 0.014, -0.96), Vector3(-PI * 0.5, 0.0, 0.0), acc_mat)
	if bool(style.get("xbow_limbs", false)):
		var limb := BoxMesh.new()
		limb.size = Vector3(0.56, 0.018, 0.04)
		_add_mesh(gun_root, "BowLimb", limb, Vector3(0.0, 0.016, -0.58), Vector3.ZERO, dark_mat)
	if cls == "sniper" or String(style.get("optic", "")) != "" or ("red_dot" in atts):
		var scope := CylinderMesh.new()
		scope.top_radius = 0.019; scope.bottom_radius = 0.019; scope.height = 0.18
		_add_mesh(gun_root, "Scope", scope, Vector3(0.0, body_h * 0.68, -body_len * 0.45), Vector3(PI * 0.5, 0.0, 0.0), dark_mat)

	var muzzle_z := -body_len * 0.85 - barrel_len * 0.90
	return Vector3(0.0, 0.014, muzzle_z)
