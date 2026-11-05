extends Node3D
# Electric trap: a wall switch (this node) that electrifies a doorway between
# two coil pylons. Needs power. Kills zombies in the doorway, and hurts you too.

const COST := 1000
const ACTIVE_TIME := 20.0
const COOLDOWN := 40.0

var interact_radius: float = 2.6
var zone_center: Vector3 = Vector3.ZERO # world position of the doorway
var zone_yaw: float = 0.0 # doorway spans local X after this yaw
var zone_width: float = 3.0

var _active: float = 0.0
var _cooldown: float = 0.0
var _arcs: Array[MeshInstance3D] = []
var _arc_t: float = 0.0
var _zap_sfx_t: float = 0.0
var _player_hurt_t: float = 0.0
var _zone_light: OmniLight3D
var _lamp: MeshInstance3D
var _pylon_tops: Array[Vector3] = []


func _ready() -> void:
	add_to_group("wall_stations")
	# Switch box on the wall
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.7, 0.18)
	box.mesh = bm
	box.material_override = MaterialLib.get_pbr("rusted_metal", 0.6, Color(0.5, 0.5, 0.45), 0.7, 0.6)
	add_child(box)
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.52, 0.08, 0.19)
	stripe.mesh = sm
	stripe.material_override = MaterialLib.get_emissive(Color(1.0, 0.75, 0.1), 1.5)
	stripe.position.y = 0.3
	add_child(stripe)
	_lamp = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.05
	lm.height = 0.1
	_lamp.mesh = lm
	_lamp.position = Vector3(0, 0.12, 0.1)
	add_child(_lamp)
	var lbl := Label3D.new()
	lbl.text = "ELECTRIC TRAP\n%d PTS" % COST
	lbl.font_size = 30
	lbl.outline_size = 8
	lbl.pixel_size = 0.004
	lbl.modulate = Color(0.5, 0.85, 1.0)
	lbl.position = Vector3(0, 0.62, 0.1)
	add_child(lbl)

	# Pylons on either side of the doorway
	var zb := Basis(Vector3.UP, zone_yaw)
	for side in [-1.0, 1.0]:
		var p := zone_center + zb * Vector3(side * (zone_width * 0.5 + 0.35), 0, 0.55)
		if ResourceLoader.exists("res://assets/models/prop_trap_pylon.glb"):
			var py: Node3D = (load("res://assets/models/prop_trap_pylon.glb") as PackedScene).instantiate()
			py.top_level = true
			add_child(py)
			py.global_position = p
		_pylon_tops.append(p + Vector3(0, 2.0, 0))
		_pylon_tops.append(p + Vector3(0, 1.1, 0))

	for i in range(4):
		var arc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 1.0
		cm.radial_segments = 4
		arc.mesh = cm
		arc.material_override = MaterialLib.get_emissive(Color(0.55, 0.85, 1.0), 9.0, 0.9)
		arc.top_level = true
		arc.visible = false
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arc)
		_arcs.append(arc)

	_zone_light = OmniLight3D.new()
	_zone_light.light_color = Color(0.5, 0.8, 1.0)
	_zone_light.light_energy = 0.0
	_zone_light.omni_range = 7.0
	_zone_light.top_level = true
	add_child(_zone_light)
	_zone_light.global_position = zone_center + Vector3(0, 1.8, 0)
	_update_lamp()


func _powered() -> bool:
	var arena := get_tree().get_first_node_in_group("arena")
	return arena != null and arena.power_on


func _update_lamp() -> void:
	var col := Color(1.0, 0.15, 0.1)
	if _active > 0.0:
		col = Color(0.4, 0.8, 1.0)
	elif _cooldown <= 0.0 and _powered():
		col = Color(0.2, 1.0, 0.3)
	_lamp.material_override = MaterialLib.get_emissive(col, 4.0)


func get_prompt(_player: Node3D) -> String:
	if not _powered():
		return "ELECTRIC TRAP — REQUIRES POWER (GENERATOR IN MOTOR POOL)"
	if _active > 0.0:
		return "ELECTRIC TRAP ACTIVE (%ds)" % ceili(_active)
	if _cooldown > 0.0:
		return "ELECTRIC TRAP COOLING DOWN (%ds)" % ceili(_cooldown)
	return "[E] ACTIVATE ELECTRIC TRAP  —  %d PTS" % COST


func try_purchase(player: Node3D) -> void:
	if not _powered() or _active > 0.0 or _cooldown > 0.0:
		return
	if GameState.try_pay(player, COST):
		Net.world(self, "zap")


func net_apply(action: String, _args: Array) -> void:
	if action == "zap" and _active <= 0.0:
		_active = ACTIVE_TIME
		GameState.play_sfx("power_on", -6.0, 1.6)
		_update_lamp()


func _physics_process(delta: float) -> void:
	if _active <= 0.0:
		if _cooldown > 0.0:
			_cooldown -= delta
		_update_lamp()
		return
	_active -= delta
	if _active <= 0.0:
		_cooldown = COOLDOWN
		for a in _arcs:
			a.visible = false
		_zone_light.light_energy = 0.0
		_update_lamp()
		return

	_arc_t -= delta
	if _arc_t <= 0.0:
		_arc_t = 0.06
		_zone_light.light_energy = randf_range(2.0, 5.0)
		for i in range(_arcs.size()):
			var a: Vector3 = _pylon_tops[(i % 2)]
			var b: Vector3 = _pylon_tops[2 + ((i + 1) % 2)]
			var mid := (a + b) * 0.5 + Vector3(randf_range(-0.3, 0.3), randf_range(-0.6, 0.4), randf_range(-0.3, 0.3))
			var from: Vector3 = a if i < 2 else mid
			var to: Vector3 = mid if i < 2 else b
			_place_arc(_arcs[i], from, to)
	_zap_sfx_t -= delta
	if _zap_sfx_t <= 0.0:
		_zap_sfx_t = 0.95
		GameState.play_sfx("trap_zap", -6.0, randf_range(0.95, 1.05))

	var inv := Basis(Vector3.UP, zone_yaw).inverse()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for node in (get_tree().get_nodes_in_group("enemies") if Net.is_host() else []):
		var z := node as ZombieEnemy
		if z == null or z.is_dead:
			continue
		if _in_zone(z.global_position, inv):
			var dmg := 1.0e6 if not z.is_boss else 450.0 * delta
			var res := z.take_damage(dmg, z.global_position + Vector3(0, 1.0, 0), true, "electric")
			if res["killed"]:
				GameState.play_sfx("electrocute", -4.0, randf_range(0.9, 1.1))
				if player and player.has_method("_on_enemy_killed_by_player"):
					player._on_enemy_killed_by_player(z, false)
	if player and _in_zone(player.global_position, inv):
		_player_hurt_t -= delta
		if _player_hurt_t <= 0.0:
			_player_hurt_t = 0.5
			player.take_damage(25.0, zone_center)


func _in_zone(p: Vector3, inv: Basis) -> bool:
	var l := inv * (p - zone_center)
	return absf(l.x) < zone_width * 0.5 + 0.3 and absf(l.z) < 1.1


func _place_arc(arc: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := a.distance_to(b)
	arc.visible = true
	arc.scale = Vector3(1, d, 1)
	arc.global_position = (a + b) * 0.5
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	arc.look_at(b, up)
	arc.rotate_object_local(Vector3.RIGHT, PI * 0.5)
