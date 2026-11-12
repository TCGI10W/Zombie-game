extends Node3D
# A boarded-up window in an outside wall. Zombies spawn outside, tear the
# boards off one by one, then climb in. Hold [E] from inside to rebuild.
# Local +Z points OUTSIDE. Origin sits on the floor in the middle of the gap.

const MAX_BOARDS := 6
const GAP_WIDTH := 2.0
const REPAIR_TIME := 0.55

var zone_id: String = "courtyard"
var boards: int = MAX_BOARDS
var interact_radius: float = 2.7
var _board_nodes: Array[MeshInstance3D] = []
var _board_rest: Array[Transform3D] = []
var _board_tweens: Dictionary = {}
var _repair_t: float = 0.0


func _ready() -> void:
	add_to_group("barricades")
	add_to_group("wall_stations")

	# Invisible wall that only stops the player (layer 5 / value 16)
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 16
	blocker.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(GAP_WIDTH, 2.6, 0.7)
	cs.shape = bs
	cs.position.y = 1.3
	blocker.add_child(cs)
	add_child(blocker)

	for i in range(MAX_BOARDS):
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(GAP_WIDTH + 0.35, 0.2, 0.06)
		b.mesh = bm
		# Each board is one real plank (four to pick from in the scan atlas)
		b.material_override = MaterialLib.get_box_strip("wood_board", randi() % 4, 4, Color(0.78, 0.66, 0.52))
		var y := 0.45 + float(i) * 0.3
		var tilt := deg_to_rad(randf_range(-9.0, 9.0))
		var xf := Transform3D(Basis(Vector3.FORWARD, tilt), Vector3(randf_range(-0.05, 0.05), y, 0.36 + float(i % 2) * 0.03))
		b.transform = xf
		add_child(b)
		_board_nodes.append(b)
		_board_rest.append(xf)


func spawn_pos() -> Vector3:
	return global_position + global_basis.z * 5.5


func attack_pos() -> Vector3:
	return global_position + global_basis.z * 0.95


func inside_pos() -> Vector3:
	return global_position - global_basis.z * 1.5


func tear_board() -> void:
	if boards > 0:
		Net.world(self, "tear")


func net_apply(action: String, _args: Array) -> void:
	match action:
		"tear":
			_do_tear()
		"repair":
			_do_repair()
		"set":
			var want := clampi(int(_args[0]), 0, MAX_BOARDS)
			while boards > want:
				_do_tear()
			while boards < want:
				_do_repair()


func _kill_board_tween(i: int) -> void:
	var tw: Tween = _board_tweens.get(i)
	if tw and tw.is_valid():
		tw.kill()
	_board_tweens.erase(i)


func _do_tear() -> void:
	if boards <= 0:
		return
	boards -= 1
	var b := _board_nodes[boards]
	_kill_board_tween(boards)
	var out_dir := global_basis.z
	var tw := b.create_tween()
	_board_tweens[boards] = tw
	tw.set_parallel(true)
	tw.tween_property(b, "global_position", b.global_position + out_dir * 1.4 + Vector3(randf_range(-0.6, 0.6), -b.position.y + 0.05, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "rotation", Vector3(randf_range(-1.2, 1.2), randf_range(-1.0, 1.0), randf_range(-1.5, 1.5)), 0.35)
	tw.chain().tween_interval(0.5)
	tw.chain().tween_callback(func(): b.visible = false)
	_play_local("board_tear", -2.0)


func interact_hold(player: Node3D, delta: float) -> void:
	if boards >= MAX_BOARDS or not _player_inside(player):
		return
	_repair_t += delta * float(player.dex_mult())
	if _repair_t < REPAIR_TIME:
		return
	_repair_t = 0.0
	GameState.play_sfx("board_repair", -2.0, randf_range(0.92, 1.08))
	if GameState.rebuild_points_round < GameState.REBUILD_POINTS_CAP:
		GameState.rebuild_points_round += 10
		GameState.add_points(10)
	Net.world(self, "repair")


func _do_repair() -> void:
	if boards >= MAX_BOARDS:
		return
	var b := _board_nodes[boards]
	_kill_board_tween(boards)
	b.transform = _board_rest[boards]
	b.visible = true
	b.scale = Vector3(1.2, 1.2, 1.2)
	_board_tweens[boards] = b.create_tween().tween_property(b, "scale", Vector3.ONE, 0.12)
	boards += 1


# Carpenter power-up: every board snaps back into place at once.
func repair_all() -> void:
	while boards < MAX_BOARDS:
		var b := _board_nodes[boards]
		_kill_board_tween(boards)
		b.transform = _board_rest[boards]
		b.visible = true
		b.scale = Vector3(1.15, 1.15, 1.15)
		_board_tweens[boards] = b.create_tween().tween_property(b, "scale", Vector3.ONE, 0.2)
		boards += 1


func try_purchase(_player: Node3D) -> void:
	pass # Rebuilding is done by holding [E]


func get_prompt(player: Node3D) -> String:
	if boards >= MAX_BOARDS or not _player_inside(player):
		return ""
	return "HOLD [E] TO REBUILD BARRIER  (%d / %d)" % [boards, MAX_BOARDS]


func _player_inside(player: Node3D) -> bool:
	return (player.global_position - global_position).dot(global_basis.z) < 0.0


func _play_local(sfx: String, vol: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var d := p.global_position.distance_to(global_position)
	if d < 30.0:
		GameState.play_sfx(sfx, vol - d * 0.6, randf_range(0.9, 1.1))
