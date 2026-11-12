extends Node3D
# Pay to open the crate: weapons spin above it, then it offers one random
# weapon you can take. Origin on the floor; the crate front faces local -Z.

const COST := 950
const ROLL_TIME := 3.6
const OFFER_TIME := 9.0

enum State { IDLE, ROLLING, OFFER }

var interact_radius: float = 2.8
var state: State = State.IDLE
var offered_id: String = ""
var owner_peer: int = 0 # who paid for the current roll
var _timer: float = 0.0
var _cycle_t: float = 0.0
var _lid: Node3D
var _display: Node3D
var _display_model: Node3D
var _glow: OmniLight3D
var _t: float = 0.0
var _price_lbl: Label3D


func current_cost() -> int:
	return 10 if GameState.is_powerup_active("fire_sale") else COST


func _ready() -> void:
	add_to_group("wall_stations")
	if ResourceLoader.exists("res://assets/models/prop_mystery_crate.glb"):
		var m: Node3D = (load("res://assets/models/prop_mystery_crate.glb") as PackedScene).instantiate()
		add_child(m)
		_lid = m.find_child("LidPivot", true, false)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.65, 0.75, 0.78)
	cs.shape = bs
	cs.position.y = 0.375
	body.add_child(cs)
	add_child(body)

	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.4, 0.75, 1.0)
	_glow.light_energy = 1.4
	_glow.omni_range = 5.0
	_glow.position = Vector3(0, 1.4, -0.3)
	add_child(_glow)

	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.45
	cm.height = 6.0
	beam.mesh = cm
	beam.material_override = MaterialLib.get_emissive(Color(0.4, 0.75, 1.0), 0.5, 0.05)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 3.6
	add_child(beam)

	var lbl := Label3D.new()
	lbl.text = "MYSTERY CRATE\n%d PTS" % COST
	lbl.font_size = 34
	lbl.outline_size = 10
	lbl.pixel_size = 0.005
	lbl.modulate = Color(0.6, 0.85, 1.0)
	lbl.position = Vector3(0, 0.95, -0.5)
	lbl.rotation.y = PI
	add_child(lbl)
	_price_lbl = lbl

	_display = Node3D.new()
	_display.position = Vector3(0, 0.55, 0)
	add_child(_display)


func _process(delta: float) -> void:
	_t += delta
	_glow.light_energy = 1.4 + sin(_t * 3.0) * 0.3
	if _price_lbl:
		var fs := GameState.is_powerup_active("fire_sale")
		_price_lbl.text = "MYSTERY CRATE\n%s" % ("FIRE SALE — 10 PTS" if fs else "%d PTS" % COST)
		_price_lbl.modulate = Color(1.0, 0.4, 0.3) if fs else Color(0.6, 0.85, 1.0)
	match state:
		State.ROLLING:
			_timer -= delta
			var p := 1.0 - _timer / ROLL_TIME
			_display.position.y = lerpf(0.55, 1.25, p)
			_cycle_t -= delta
			if _cycle_t <= 0.0:
				_cycle_t = 0.07 + p * p * 0.35
				_show_weapon(_random_weapon(""))
			if _timer <= 0.0:
				state = State.OFFER
				_timer = OFFER_TIME
				_show_weapon(offered_id)
				GameState.play_sfx("crate_reveal", 0.0, 1.0)
		State.OFFER:
			_timer -= delta
			_display.position.y = 1.25 + sin(_t * 2.5) * 0.05
			_display.rotation.y = sin(_t * 1.5) * 0.25
			if _timer <= 0.0:
				_close()


func get_prompt(player: Node3D) -> String:
	match state:
		State.IDLE:
			return "[E] MYSTERY CRATE — RANDOM WEAPON  —  %d PTS" % current_cost()
		State.OFFER:
			var w_name: String = GameState.WEAPONS[offered_id]["name"]
			if owner_peer != Net.my_id():
				return "%s'S CRATE — %s" % [Net.player_name(owner_peer), w_name]
			if player.weapons_owned.size() >= 2 and not player.weapons_owned.has(offered_id):
				return "[E] TAKE %s  (REPLACES %s)" % [w_name, player.get_weapon_cfg(player.get_current_weapon_id())["name"]]
			return "[E] TAKE %s" % w_name
	return ""


func try_purchase(player: Node3D) -> void:
	match state:
		State.IDLE:
			if player.is_monster_form:
				return
			if GameState.try_pay(player, current_cost()):
				Net.world(self, "open", [_random_weapon("", player.weapons_owned), Net.my_id()])
		State.OFFER:
			if player.is_monster_form or owner_peer != Net.my_id():
				return
			player.grant_or_refill_weapon(offered_id)
			GameState.play_sfx("weapon_swap", 0.0, 0.9)
			Net.world(self, "close")


func net_apply(action: String, args: Array) -> void:
	match action:
		"open":
			if state == State.IDLE:
				_open_with(String(args[0]), int(args[1]))
		"close":
			if state != State.IDLE:
				_close()


func _open_with(w_id: String, owner: int) -> void:
	state = State.ROLLING
	_timer = ROLL_TIME
	_cycle_t = 0.0
	offered_id = w_id
	owner_peer = owner
	GameState.play_sfx("crate_open", -1.0, 1.0)
	if _lid:
		_lid.create_tween().tween_property(_lid, "rotation:x", deg_to_rad(105.0), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close() -> void:
	state = State.IDLE
	offered_id = ""
	if is_instance_valid(_display_model):
		_display_model.queue_free()
		_display_model = null
	_display.position.y = 0.55
	if _lid:
		_lid.create_tween().tween_property(_lid, "rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _random_weapon(_unused: String, exclude: Array = []) -> String:
	var total := 0
	for w_id in GameState.WEAPONS:
		if not exclude.has(w_id):
			total += int(GameState.WEAPONS[w_id].get("box_weight", 0))
	if total <= 0:
		return "smg"
	var roll := randi() % total
	for w_id in GameState.WEAPONS:
		if exclude.has(w_id):
			continue
		roll -= int(GameState.WEAPONS[w_id].get("box_weight", 0))
		if roll < 0:
			return w_id
	return "smg"


func _show_weapon(w_id: String) -> void:
	if is_instance_valid(_display_model):
		_display_model.queue_free()
	var path: String = GameState.WEAPONS[w_id]["model"]
	if not ResourceLoader.exists(path):
		return
	_display_model = (load(path) as PackedScene).instantiate()
	_display_model.scale = Vector3.ONE * 1.7
	_display_model.rotation.y = deg_to_rad(90.0)
	_display.add_child(_display_model)
