class_name PvpObjectiveZone
extends Node3D

# 3D objective zone for PvP Search & Destroy bomb sites and Domination flags.

const HI := preload("res://scripts/ui/hud_icons.gd")
const PLANT_TIME := 3.5
const DEFUSE_TIME := 4.5
const DOM_RADIUS := 4.5

var zone_id: String = "A"
var zone_label: String = "SITE A"
var zone_kind: String = "bomb_site" # "bomb_site" or "dom_flag"
var interact_radius: float = 3.2

# Bomb site state
var is_planted: bool = false
var is_defused: bool = false
var planted_team: int = -1
var bomb_timer: float = 0.0
var local_hold: float = 0.0
var _hold_decay_t: float = 0.0
var _beep_t: float = 0.0

# Domination flag state
var owner_team: int = -1
var capturing_team: int = -1
var capture_progress: float = 0.0
var contested: bool = false

var _ring_mesh: MeshInstance3D
var _beam_mesh: MeshInstance3D
var _bomb_crate: Node3D
var _flag_banner: MeshInstance3D
var _label_3d: Label3D
var _pulse_t: float = 0.0


func setup(p_id: String, p_label: String, p_kind: String, p_pos: Vector3) -> void:
	zone_id = p_id
	zone_label = p_label
	zone_kind = p_kind
	position = p_pos


func _ready() -> void:
	add_to_group("pvp_objectives")
	if zone_kind == "bomb_site":
		add_to_group("wall_stations")
	_build_visuals()
	_refresh_colors()


func _build_visuals() -> void:
	var rad: float = 2.4 if zone_kind == "bomb_site" else DOM_RADIUS

	# Ground ring
	_ring_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = rad - 0.14
	torus.outer_radius = rad
	torus.rings = 32
	torus.ring_segments = 12
	_ring_mesh.mesh = torus
	_ring_mesh.position.y = 0.08
	add_child(_ring_mesh)

	# Translucent sky marker beam
	_beam_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.22
	cyl.height = 14.0
	_beam_mesh.mesh = cyl
	_beam_mesh.position.y = 7.0
	add_child(_beam_mesh)

	# Floating 3D tag
	_label_3d = Label3D.new()
	_label_3d.text = zone_id
	_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_3d.no_depth_test = true
	_label_3d.font_size = 56
	_label_3d.outline_size = 10
	_label_3d.position = Vector3(0.0, 2.9, 0.0)
	add_child(_label_3d)

	if zone_kind == "bomb_site":
		# Tactical target crate + armed C4 satchel visual
		var pad := MeshInstance3D.new()
		var pbm := BoxMesh.new()
		pbm.size = Vector3(1.15, 0.72, 0.85)
		pad.mesh = pbm
		pad.position = Vector3(0.0, 0.36, 0.0)
		pad.material_override = MaterialLib.get_pbr("concrete", 1.5, Color(0.24, 0.26, 0.30), 0.75, 0.2, false)
		add_child(pad)

		_bomb_crate = Node3D.new()
		_bomb_crate.position = Vector3(0.0, 0.76, 0.0)
		var pack := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.38, 0.16, 0.26)
		pack.mesh = bm
		pack.material_override = MaterialLib.get_emissive(Color(1.0, 0.28, 0.12), 2.2)
		_bomb_crate.add_child(pack)
		_bomb_crate.visible = false
		add_child(_bomb_crate)
	else:
		# Domination flagpole + team banner
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.045
		pm.bottom_radius = 0.055
		pm.height = 3.2
		pole.mesh = pm
		pole.position = Vector3(0.0, 1.6, 0.0)
		pole.material_override = MaterialLib.get_pbr("gunmetal", 2.0, Color(0.65, 0.68, 0.72), 0.3, 0.8, false)
		add_child(pole)

		_flag_banner = MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.95, 0.52, 0.04)
		_flag_banner.mesh = fm
		_flag_banner.position = Vector3(0.48, 2.75, 0.0)
		add_child(_flag_banner)


func _process(delta: float) -> void:
	_pulse_t += delta
	if _hold_decay_t > 0.0:
		_hold_decay_t -= delta
		if _hold_decay_t <= 0.0:
			local_hold = 0.0

	if zone_kind == "bomb_site" and is_planted and not is_defused:
		_beep_t -= delta
		if _beep_t <= 0.0:
			var interval: float = 0.22 if bomb_timer < 8.0 else (0.45 if bomb_timer < 18.0 else 0.9)
			_beep_t = interval
			GameState.play_sfx("radio_beep", -6.0, 1.45 if bomb_timer < 8.0 else 1.1)
		if _bomb_crate:
			_bomb_crate.visible = true
			_bomb_crate.scale = Vector3.ONE * (1.0 + 0.12 * sin(_pulse_t * 14.0))
	elif _bomb_crate:
		_bomb_crate.visible = is_planted and not is_defused

	if _flag_banner:
		var target_y: float = 1.6 + 1.15 * (1.0 if owner_team >= 0 else capture_progress)
		_flag_banner.position.y = lerpf(_flag_banner.position.y, target_y, clampf(delta * 8.0, 0.0, 1.0))

	_refresh_colors()


func _refresh_colors() -> void:
	var col := Color(0.9, 0.75, 0.25)
	if zone_kind == "bomb_site":
		if is_defused:
			col = Color(0.3, 0.9, 1.0)
		elif is_planted:
			var blink: float = 0.5 + 0.5 * sin(_pulse_t * 12.0)
			col = Color(1.0, 0.22, 0.15).lerp(Color(1.0, 0.78, 0.2), blink)
		else:
			col = Color(1.0, 0.58, 0.2) if zone_id == "A" else Color(0.35, 0.78, 1.0)
		_label_3d.text = ("PLANTED %s  %ds" % [zone_id, ceili(bomb_timer)]) if is_planted else ("SITE %s" % zone_id)
	else:
		if owner_team >= 0:
			col = GameState.pvp_team_color(owner_team)
		elif capturing_team >= 0:
			col = GameState.pvp_team_color(capturing_team).lerp(Color.WHITE, 0.35)
		else:
			col = Color(0.85, 0.88, 0.92)
		if contested:
			col = Color(1.0, 0.72, 0.2)
		_label_3d.text = "%s  %s" % [zone_id, "CONTESTED" if contested else (GameState.pvp_team_code(owner_team) if owner_team >= 0 else "OPEN")]

	_label_3d.modulate = col
	if _ring_mesh:
		_ring_mesh.material_override = MaterialLib.get_emissive(col, 1.6)
	if _beam_mesh:
		_beam_mesh.material_override = MaterialLib.get_emissive(col, 0.45, 0.22)
	if _flag_banner:
		_flag_banner.material_override = MaterialLib.get_emissive(col, 1.2)


# ---------------------------------------------------------------------------
# PLAYER INTERACTION (S&D Plant / Defuse via [HOLD E])
# ---------------------------------------------------------------------------
func get_prompt(p: Node3D) -> String:
	if zone_kind != "bomb_site" or p == null or p.is_dead:
		return ""
	var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
	if pvp_dir == null:
		return ""
	var tid: int = int(p.team_id) if "team_id" in p else 0
	if pvp_dir.can_team_defuse(zone_id, tid):
		return "[HOLD E] DEFUSE BOMB AT SITE %s  (%.1fs)" % [zone_id, DEFUSE_TIME * (1.0 - local_hold)]
	if pvp_dir.can_team_plant(zone_id, tid):
		return "[HOLD E] PLANT BOMB AT SITE %s  (%.1fs)" % [zone_id, PLANT_TIME * (1.0 - local_hold)]
	return ""


func try_purchase(_p: Node3D) -> void:
	pass


func interact_hold(p: Node3D, delta: float) -> void:
	if zone_kind != "bomb_site" or p == null or p.is_dead:
		return
	var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
	if pvp_dir == null:
		return
	var tid: int = int(p.team_id) if "team_id" in p else 0
	var action: String = ""
	var req_time: float = PLANT_TIME
	if pvp_dir.can_team_defuse(zone_id, tid):
		action = "defuse"
		req_time = DEFUSE_TIME
	elif pvp_dir.can_team_plant(zone_id, tid):
		action = "plant"
		req_time = PLANT_TIME
	else:
		return
	_hold_decay_t = 0.2
	local_hold = clampf(local_hold + delta / req_time, 0.0, 1.0)
	pvp_dir.set_local_hold_hint(
		("DEFUSING SITE %s..." if action == "defuse" else "PLANTING AT SITE %s...") % zone_id,
		local_hold
	)
	if local_hold >= 1.0:
		local_hold = 0.0
		_hold_decay_t = 0.0
		pvp_dir.set_local_hold_hint("", 0.0)
		var ng := get_tree().get_first_node_in_group("net_game")
		if ng and Net.is_online():
			ng.request_pvp_interact(zone_id, action)
		else:
			pvp_dir.handle_interact("peer_%d" % Net.my_id(), zone_id, action)


func reset_site() -> void:
	is_planted = false
	is_defused = false
	planted_team = -1
	bomb_timer = 0.0
	local_hold = 0.0
	_hold_decay_t = 0.0
	_beep_t = 0.0
	owner_team = -1
	capturing_team = -1
	capture_progress = 0.0
	contested = false
