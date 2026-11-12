class_name WallStation
extends Node3D
# Wall-buy weapon, ammo cache, or the Weapon Forge (upgrades your gun).
# Wall plaques face local +Z. The forge sits on the floor facing local -Z.

@export var station_type: String = "weapon" # "weapon", "ammo_box", "forge"
@export var weapon_id: String = "rifle"
@export var title: String = "COMMANDO M14A"
@export var cost: int = 750
@export var ammo_cost: int = 350
@export var glow_color: Color = Color(0.28, 0.86, 1.0)

var label_3d: Label3D
var interact_radius: float = 3.0


func _ready() -> void:
	add_to_group("wall_stations")
	if station_type == "forge":
		_build_forge()
	else:
		_build_plaque()


func _build_plaque() -> void:
	# Weathered CoD 5/7 Nacht/Kino wooden/iron backboard with faint chalk & dried-blood trim
	var plaque := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.48, 0.84, 0.024)
	plaque.mesh = bm
	plaque.material_override = MaterialLib.get_pbr("wood_planks", 0.78, Color(0.14, 0.11, 0.09))
	add_child(plaque)

	var chalk_col := Color(0.84, 0.79, 0.66) if station_type == "weapon" else Color(0.76, 0.58, 0.28)
	var chalk_mat := MaterialLib.get_emissive(chalk_col, 0.42, 0.85)
	for bar in [
		[Vector3(0, 0.42, 0.012), Vector3(1.46, 0.028, 0.01)],
		[Vector3(0, -0.42, 0.012), Vector3(1.46, 0.028, 0.01)],
		[Vector3(-0.73, 0, 0.012), Vector3(0.028, 0.86, 0.01)],
		[Vector3(0.73, 0, 0.012), Vector3(0.028, 0.86, 0.01)],
	]:
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = bar[1]
		strip.mesh = sm
		strip.position = bar[0]
		strip.material_override = chalk_mat
		add_child(strip)

	# Dried blood smear corner accent
	var smear := MeshInstance3D.new()
	var sm_box := BoxMesh.new()
	sm_box.size = Vector3(0.45, 0.24, 0.008)
	smear.mesh = sm_box
	smear.position = Vector3(-0.42, -0.24, 0.014)
	smear.material_override = MaterialLib.get_pbr("concrete", 0.35, Color(0.22, 0.02, 0.02))
	add_child(smear)

	# Dim moody tungsten/amber glint so the chalk wall-buy is spotted without flooding the hall
	var light := OmniLight3D.new()
	light.light_color = Color(0.95, 0.72, 0.44)
	light.light_energy = 0.42
	light.omni_range = 2.6
	light.position = Vector3(0, 0.12, 0.42)
	add_child(light)

	if station_type == "weapon" and GameState.WEAPONS.has(weapon_id):
		var model_path: String = GameState.WEAPONS[weapon_id]["model"]
		if ResourceLoader.exists(model_path):
			var packed: PackedScene = load(model_path)
			var inst := packed.instantiate()
			inst.position = Vector3(0, -0.04, 0.14)
			inst.rotation = Vector3(0, deg_to_rad(90.0), 0)
			inst.scale = Vector3.ONE * 1.22
			add_child(inst)
	else:
		# Gritty olive-drab military munitions crate + brass shells (replaces neon cylinder)
		var crate_mat: Material = MaterialLib.get_pbr("rusted_metal", 0.65, Color(0.24, 0.27, 0.18), 0.25, 1.0)
		var latch_mat: Material = MaterialLib.get_pbr("rusted_metal", 0.9, Color(0.18, 0.17, 0.15), 0.72, 0.75)
		var brass_mat: Material = MaterialLib.get_pbr("rusted_metal", 0.9, Color(0.74, 0.56, 0.22), 0.85, 0.55)
		var base_box := MeshInstance3D.new()
		var bm1 := BoxMesh.new()
		bm1.size = Vector3(0.56, 0.24, 0.30)
		base_box.mesh = bm1
		base_box.position = Vector3(-0.04, -0.14, 0.17)
		base_box.rotation = Vector3(0, 0.08, 0)
		base_box.material_override = crate_mat
		add_child(base_box)
		var top_box := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.42, 0.19, 0.25)
		top_box.mesh = bm2
		top_box.position = Vector3(0.05, 0.08, 0.16)
		top_box.rotation = Vector3(0, -0.14, 0)
		top_box.material_override = crate_mat
		add_child(top_box)
		var latch := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.10, 0.12, 0.27)
		latch.mesh = lm
		latch.position = Vector3(0.05, 0.08, 0.16)
		latch.material_override = latch_mat
		add_child(latch)
		for bi in range(3):
			var shell := MeshInstance3D.new()
			var scm := CylinderMesh.new()
			scm.top_radius = 0.018
			scm.bottom_radius = 0.020
			scm.height = 0.09
			shell.mesh = scm
			shell.position = Vector3(-0.22 + 0.05 * bi, 0.02, 0.22)
			shell.rotation = Vector3(0.15, 0, -0.1 + 0.08 * bi)
			shell.material_override = brass_mat
			add_child(shell)

	label_3d = Label3D.new()
	label_3d.text = "%s\n[%d PTS]" % [title, cost]
	label_3d.font_size = 30
	label_3d.outline_size = 8
	label_3d.pixel_size = 0.0042
	label_3d.modulate = Color(0.88, 0.84, 0.72)
	label_3d.position = Vector3(0, 0.64, 0.12)
	add_child(label_3d)


func _build_forge() -> void:
	if ResourceLoader.exists("res://assets/models/prop_weapon_forge.glb"):
		add_child((load("res://assets/models/prop_weapon_forge.glb") as PackedScene).instantiate())
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.9, 2.4, 1.1)
	cs.shape = bs
	cs.position.y = 1.2
	body.add_child(cs)
	add_child(body)

	var light := OmniLight3D.new()
	light.light_color = Color(0.75, 0.18, 0.14)
	light.light_energy = 1.05
	light.omni_range = 4.6
	light.position = Vector3(0, 1.6, -0.9)
	add_child(light)

	label_3d = Label3D.new()
	label_3d.text = "%s\n[%d PTS]" % [title, cost]
	label_3d.font_size = 32
	label_3d.outline_size = 9
	label_3d.pixel_size = 0.0046
	label_3d.modulate = Color(0.86, 0.78, 0.68)
	label_3d.position = Vector3(0, 3.1, -0.3)
	label_3d.rotation.y = PI
	add_child(label_3d)


func get_prompt(player: PlayerController) -> String:
	match station_type:
		"weapon":
			if player.weapons_owned.has(weapon_id):
				return "[E] REFILL %s AMMO  —  %d PTS" % [title, ammo_cost]
			return "[E] BUY %s  —  %d PTS" % [title, cost]
		"ammo_box":
			return "[E] RESUPPLY ALL WEAPONS & GRENADES  —  %d PTS" % cost
		"forge":
			if not _powered():
				return "WEAPON FORGE — REQUIRES POWER (GENERATOR IN MOTOR POOL)"
			if player.is_monster_form:
				return "WEAPON FORGE: RETURN TO HUMAN FORM FIRST"
			var w_name: String = player.get_weapon_cfg(player.get_current_weapon_id())["name"]
			if not player.can_upgrade_weapon():
				return "%s IS ALREADY FORGED" % w_name
			return "[E] FORGE %s (2.1x DMG, BIGGER MAG)  —  %d PTS" % [w_name, cost]
	return ""


func try_purchase(player: PlayerController) -> void:
	if player.is_monster_form:
		return
	match station_type:
		"weapon":
			var actual_cost := ammo_cost if player.weapons_owned.has(weapon_id) else cost
			if GameState.try_pay(player, actual_cost):
				player.grant_or_refill_weapon(weapon_id)
		"ammo_box":
			if GameState.try_pay(player, cost):
				player.refill_all_ammo()
		"forge":
			if _powered() and player.can_upgrade_weapon() and GameState.try_pay(player, cost):
				player.upgrade_current_weapon()


func _powered() -> bool:
	var arena := get_tree().get_first_node_in_group("arena")
	return arena == null or arena.power_on
