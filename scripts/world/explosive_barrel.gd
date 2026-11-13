class_name ExplosiveBarrel
extends StaticBody3D
# Interactive hazard drum. Detonates when shot or caught in explosions,
# dealing AoE damage + stun to nearby zombies and chain-detonating nearby drums.

const BLAST_RADIUS := 6.8
const BASE_DAMAGE := 520.0
const RESPAWN_ROUNDS := 2

static var _drum_mesh: CylinderMesh
static var _band_mesh: CylinderMesh
static var _rib_mesh: CylinderMesh
static var _bung_mesh: CylinderMesh
static var _wreck_mesh: CylinderMesh
static var _ball_mesh: SphereMesh
static var _red_mat: StandardMaterial3D
static var _band_mat: StandardMaterial3D
static var _steel_mat: StandardMaterial3D
static var _char_mat: StandardMaterial3D

var _col: CollisionShape3D
var _visual: Node3D
var _wreck: MeshInstance3D
var _exploded: bool = false
var _chain_queued: bool = false
var _spent_round: int = -99


func _ready() -> void:
	collision_layer = 1 | HitboxRig.BALLISTIC_WORLD_LAYER
	collision_mask = 0
	set_meta("surface", "metal")
	add_to_group("hazard_barrels")
	_ensure_assets()

	_col = CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.36
	cs.height = 0.98
	_col.shape = cs
	_col.position = Vector3(0.0, 0.49, 0.0)
	add_child(_col)

	_visual = Node3D.new()
	add_child(_visual)

	var body := MeshInstance3D.new()
	body.mesh = _drum_mesh
	body.material_override = _red_mat
	body.position = Vector3(0.0, 0.47, 0.0)
	_visual.add_child(body)

	var band := MeshInstance3D.new()
	band.mesh = _band_mesh
	band.material_override = _band_mat
	band.position = Vector3(0.0, 0.50, 0.0)
	_visual.add_child(band)

	for ry in [0.06, 0.33, 0.65, 0.92]:
		var rib := MeshInstance3D.new()
		rib.mesh = _rib_mesh
		rib.material_override = _steel_mat
		rib.position = Vector3(0.0, ry, 0.0)
		_visual.add_child(rib)

	var bung := MeshInstance3D.new()
	bung.mesh = _bung_mesh
	bung.material_override = _steel_mat
	bung.position = Vector3(0.14, 0.95, 0.0)
	_visual.add_child(bung)

	_wreck = MeshInstance3D.new()
	_wreck.mesh = _wreck_mesh
	_wreck.material_override = _char_mat
	_wreck.position = Vector3(0.0, 0.05, 0.0)
	_wreck.visible = false
	add_child(_wreck)


static func _ensure_assets() -> void:
	if _drum_mesh != null:
		return
	_drum_mesh = CylinderMesh.new()
	_drum_mesh.top_radius = 0.34
	_drum_mesh.bottom_radius = 0.34
	_drum_mesh.height = 0.94
	_drum_mesh.radial_segments = 16

	_band_mesh = CylinderMesh.new()
	_band_mesh.top_radius = 0.346
	_band_mesh.bottom_radius = 0.346
	_band_mesh.height = 0.16
	_band_mesh.radial_segments = 16

	_rib_mesh = CylinderMesh.new()
	_rib_mesh.top_radius = 0.355
	_rib_mesh.bottom_radius = 0.355
	_rib_mesh.height = 0.045
	_rib_mesh.radial_segments = 16

	_bung_mesh = CylinderMesh.new()
	_bung_mesh.top_radius = 0.035
	_bung_mesh.bottom_radius = 0.035
	_bung_mesh.height = 0.04
	_bung_mesh.radial_segments = 10

	_wreck_mesh = CylinderMesh.new()
	_wreck_mesh.top_radius = 0.31
	_wreck_mesh.bottom_radius = 0.35
	_wreck_mesh.height = 0.10
	_wreck_mesh.radial_segments = 14

	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = 1.0
	_ball_mesh.height = 2.0

	_red_mat = StandardMaterial3D.new()
	_red_mat.albedo_color = Color(0.66, 0.11, 0.09)
	_red_mat.roughness = 0.58
	_red_mat.metallic = 0.35

	_band_mat = StandardMaterial3D.new()
	_band_mat.albedo_color = Color(0.92, 0.68, 0.12)
	_band_mat.roughness = 0.45
	_band_mat.metallic = 0.2
	_band_mat.emission_enabled = true
	_band_mat.emission = Color(0.85, 0.55, 0.08)
	_band_mat.emission_energy_multiplier = 0.18

	_steel_mat = StandardMaterial3D.new()
	_steel_mat.albedo_color = Color(0.20, 0.21, 0.23)
	_steel_mat.roughness = 0.42
	_steel_mat.metallic = 0.72

	_char_mat = StandardMaterial3D.new()
	_char_mat.albedo_color = Color(0.11, 0.10, 0.10)
	_char_mat.roughness = 0.92
	_char_mat.metallic = 0.15


func is_intact() -> bool:
	return not _exploded


func on_shot(attacker: Node = null) -> void:
	if _exploded:
		return
	detonate(attacker)


func trigger_chain(attacker: Node = null, delay: float = 0.14) -> void:
	if _exploded or _chain_queued:
		return
	_chain_queued = true
	get_tree().create_timer(delay).timeout.connect(func():
		if is_instance_valid(self) and not _exploded:
			detonate(attacker))


func detonate(attacker: Node = null) -> void:
	if _exploded:
		return
	_exploded = true
	_chain_queued = false
	_spent_round = GameState.current_round
	collision_layer = 0
	if is_instance_valid(_col):
		_col.set_deferred("disabled", true)
	if is_instance_valid(_visual):
		_visual.visible = false
	if is_instance_valid(_wreck):
		_wreck.visible = true

	var center := global_position + Vector3(0.0, 0.5, 0.0)
	GameState.play_sfx("grenade_explode", 2.5, randf_range(0.86, 0.98))
	var round_scale := 1.0 + 0.14 * float(maxi(0, GameState.current_round - 1))

	var any_hit := false
	var any_kill := false
	for node in get_tree().get_nodes_in_group("enemies"):
		var z := node as ZombieEnemy
		if z == null or z.is_dead:
			continue
		var d := z.global_position.distance_to(global_position)
		if d > BLAST_RADIUS:
			continue
		var falloff := 1.0 - 0.55 * (d / BLAST_RADIUS)
		var res: Dictionary = z.take_damage(BASE_DAMAGE * round_scale * falloff, z.global_position + Vector3(0.0, 1.0, 0.0), false, "explosive")
		if float(res.get("dealt", 0.0)) > 0.0:
			any_hit = true
			if not z.is_dead:
				z.apply_stun(1.2 if z.is_boss else 2.0)
			if bool(res.get("killed", false)):
				any_kill = true
				FX.gore_burst(z.global_position + Vector3(0.0, 0.9, 0.0), 5, 5.5)
				if is_instance_valid(attacker) and attacker.has_method("_on_enemy_killed_by_player"):
					attacker._on_enemy_killed_by_player(z, false)

	if any_hit and is_instance_valid(attacker) and attacker.has_signal("hitmarker_triggered"):
		attacker.hitmarker_triggered.emit(false, any_kill, true)

	for p_node in get_tree().get_nodes_in_group("player"):
		var p3 := p_node as Node3D
		if p3 == null or not is_instance_valid(p3):
			continue
		var pd := p3.global_position.distance_to(global_position)
		if pd < 16.0 and p3.has_method("add_camera_shake"):
			p3.add_camera_shake(clampf(0.65 - pd * 0.038, 0.12, 0.65))
		if not GameState.is_pvp() and pd < 3.8 and p3.has_method("take_damage"):
			p3.take_damage(24.0 * (1.0 - pd / 3.8), global_position)

	if GameState.is_pvp():
		var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
		if pvp_dir:
			var atk_key: String = pvp_dir.node_to_key(attacker) if is_instance_valid(attacker) else ""
			for c in get_tree().get_nodes_in_group("pvp_combatants"):
				var c3 := c as Node3D
				if c3 == null or not is_instance_valid(c3):
					continue
				if "is_dead" in c3 and c3.is_dead:
					continue
				var cd: float = c3.global_position.distance_to(global_position)
				if cd > BLAST_RADIUS:
					continue
				var tkey: String = pvp_dir.node_to_key(c3)
				if tkey == "":
					continue
				var bdmg: float = 95.0 * (1.0 - 0.55 * (cd / BLAST_RADIUS))
				pvp_dir.apply_pvp_hit(atk_key if atk_key != "" else tkey, tkey, bdmg, false, "grenade", global_position)

	for hb in get_tree().get_nodes_in_group("hazard_barrels"):
		if hb == self or not is_instance_valid(hb):
			continue
		if (hb as Node3D).global_position.distance_to(global_position) < 7.2 and hb.has_method("trigger_chain"):
			hb.trigger_chain(attacker, 0.13)

	for tr in get_tree().get_nodes_in_group("zombie_traps"):
		if is_instance_valid(tr) and tr.has_method("blast"):
			tr.blast(global_position, BLAST_RADIUS)

	_spawn_fx(center)


func _spawn_fx(center: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	FX.scorch(Vector3(global_position.x, 0.02, global_position.z), 3.8)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.58, 0.22)
	flash.light_energy = 9.0
	flash.omni_range = 11.0
	scene.add_child(flash)
	flash.global_position = center + Vector3(0.0, 0.5, 0.0)
	var ftw := flash.create_tween()
	ftw.tween_property(flash, "light_energy", 0.0, 0.38)
	ftw.tween_callback(flash.queue_free)

	var ball := MeshInstance3D.new()
	ball.mesh = _ball_mesh
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := MaterialLib.get_emissive(Color(1.0, 0.52, 0.14), 6.0, 0.82).duplicate() as StandardMaterial3D
	ball.material_override = mat
	scene.add_child(ball)
	ball.global_position = center
	ball.scale = Vector3.ONE * 0.35
	var btw := ball.create_tween()
	btw.set_parallel(true)
	btw.tween_property(ball, "scale", Vector3.ONE * 4.6, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	btw.tween_property(mat, "albedo_color:a", 0.0, 0.32)
	btw.chain().tween_callback(ball.queue_free)


func try_respawn(round_num: int) -> void:
	if not _exploded or round_num < _spent_round + RESPAWN_ROUNDS:
		return
	_exploded = false
	_chain_queued = false
	collision_layer = 1 | HitboxRig.BALLISTIC_WORLD_LAYER
	if is_instance_valid(_col):
		_col.set_deferred("disabled", false)
	if is_instance_valid(_wreck):
		_wreck.visible = false
	if is_instance_valid(_visual):
		_visual.visible = true
		_visual.scale = Vector3(0.85, 0.2, 0.85)
		var tw := _visual.create_tween()
		tw.tween_property(_visual, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
