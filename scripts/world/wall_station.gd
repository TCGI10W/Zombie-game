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
	var plaque := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.55, 0.92, 0.06)
	plaque.mesh = bm
	plaque.material_override = MaterialLib.get_pbr("concrete", 0.5, Color(0.22, 0.24, 0.28))
	add_child(plaque)

	var border := MeshInstance3D.new()
	var b_rim := BoxMesh.new()
	b_rim.size = Vector3(1.62, 0.98, 0.04)
	border.mesh = b_rim
	border.position.z = -0.02
	border.material_override = MaterialLib.get_emissive(glow_color, 3.8, 0.9)
	add_child(border)

	var light := OmniLight3D.new()
	light.light_color = glow_color
	light.light_energy = 1.4
	light.omni_range = 4.2
	light.position = Vector3(0, 0.1, 0.55)
	add_child(light)

	if station_type == "weapon" and GameState.WEAPONS.has(weapon_id):
		var model_path: String = GameState.WEAPONS[weapon_id]["model"]
		if ResourceLoader.exists(model_path):
			var packed: PackedScene = load(model_path)
			var inst := packed.instantiate()
			inst.position = Vector3(0, -0.05, 0.16)
			inst.rotation = Vector3(0, deg_to_rad(90.0), 0)
			inst.scale = Vector3.ONE * 1.25
			add_child(inst)
	else:
		var cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.20
		cm.bottom_radius = 0.22
		cm.height = 0.58
		cyl.mesh = cm
		cyl.position = Vector3(0, -0.04, 0.18)
		cyl.material_override = MaterialLib.get_emissive(glow_color, 4.2, 0.95)
		add_child(cyl)

	label_3d = Label3D.new()
	label_3d.text = "%s\n[%d PTS]" % [title, cost]
	label_3d.font_size = 34
	label_3d.outline_size = 10
	label_3d.pixel_size = 0.0045
	label_3d.modulate = glow_color.lightened(0.35)
	label_3d.position = Vector3(0, 0.72, 0.12)
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
	light.light_color = glow_color
	light.light_energy = 2.4
	light.omni_range = 6.0
	light.position = Vector3(0, 1.6, -0.9)
	add_child(light)

	label_3d = Label3D.new()
	label_3d.text = "%s\n[%d PTS]" % [title, cost]
	label_3d.font_size = 36
	label_3d.outline_size = 10
	label_3d.pixel_size = 0.005
	label_3d.modulate = glow_color.lightened(0.35)
	label_3d.position = Vector3(0, 3.2, -0.3)
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
