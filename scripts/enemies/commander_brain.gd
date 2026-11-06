extends Node
# COMMANDER: a zombie that reached tier 3 by eating a player's brain. It can
# think and talk, and it gives orders to the zombies around it:
#   TRAP   - two zombies build a bone-spike trap in the player's path
#   FLANK  - zombies split up and come at the player from the sides
#   GUARD  - bodyguards circle the commander (it takes half damage)
#   RALLY  - (tier 4+) nearby zombies heal and get faster and stronger
#   SUMMON - (tier 5) calls extra zombies in
# Logic runs on the host; speech goes to everyone.

const FIRST := ["GRUL", "VESK", "MORRAK", "SKARN", "HOLLOW", "OSSIAN", "DREG", "KHAR", "MAWL", "VORN", "SILAS", "ROTFANG"]
const TITLE := ["THE GNAWER", "BRAINEATER", "THE HUNGRY", "THE CLEVER", "SKULLSPLITTER", "THE WHISPERER", "THE FIRST", "OF THE PIT"]
const LINES := {
	"rise": ["I... I CAN THINK. YOUR THOUGHTS TASTE LIKE FEAR.", "YOUR BRAIN... SO MANY MEMORIES. I KNOW HOW YOU FIGHT NOW.", "I REMEMBER YOUR NAME. I WILL REMEMBER YOUR SCREAMS."],
	"taunt": ["YOU CAN'T RUN FOREVER, MEAT.", "I SMELL YOUR HEART BEATING FASTER.", "EVERY BULLET YOU WASTE MAKES ME STRONGER.", "COME CLOSER. I WANT ANOTHER TASTE.", "YOUR FRIENDS ARE ALREADY OURS."],
	"trap": ["BUILD THE TRAP! THERE, IN HIS PATH!", "BONES AND IRON. MAKE HIM BLEED.", "SET THE SPIKES! LET HIM WALK INTO THEM."],
	"flank": ["SURROUND HIM! LEFT AND RIGHT!", "GO WIDE. CUT OFF HIS ESCAPE.", "FROM THE SIDES, YOU FOOLS!"],
	"guard": ["PROTECT ME!", "STAND BEFORE ME. TAKE HIS BULLETS.", "SHIELD YOUR MASTER!"],
	"rally": ["RISE! FEAST! FIGHT!", "FEEL MY HUNGER. TEAR HIM APART!", "STRONGER! FASTER! NOW!"],
	"summon": ["MORE! I CALL THE HORDE!", "COME TO ME, MY CHILDREN!"],
	"hurt": ["YOU WILL PAY FOR THAT.", "PAIN... I REMEMBER PAIN.", "IS THAT ALL YOU HAVE?"],
	"fail": ["USELESS! I'LL DO IT MYSELF.", "WEAK FLESH. YOU FAILED ME."],
	"down": ["YOUR BRAIN WILL BE MINE.", "STAY DOWN. I'M HUNGRY.", "ANOTHER MEAL!"],
	"death": ["THIS... ISN'T... OVER...", "I'LL... REMEMBER... YOU...", "THE HORDE... WILL... AVENGE..."],
}

var z: Node # ZombieEnemy
var _order_cd: float = 6.0
var _taunt_cd: float = 9.0
var _hurt_said: bool = false
var _guards: Array = []
var _builders: Array = []
var _build_pos: Vector3
var _build_t: float = 0.0
var _bubble: Label3D
var _bubble_t: float = 0.0


func setup(owner_zombie: Node) -> void:
	z = owner_zombie
	if z.commander_name == "":
		z.commander_name = "%s %s" % [FIRST[randi() % FIRST.size()], TITLE[randi() % TITLE.size()]]
	z.base_speed *= 0.92 # walks with purpose, lets the horde go first
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 30
	_bubble.outline_size = 9
	_bubble.pixel_size = 0.0035
	_bubble.width = 900.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.modulate = Color(1.0, 0.92, 0.75)
	_bubble.position = Vector3(0, 3.2 * z.model_scale, 0)
	_bubble.visible = false
	z.add_child(_bubble)
	z._tier_visuals()
	if not z.net_puppet:
		say("rise")


func _process(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble.visible = false
	if z == null or z.is_dead or z.net_puppet:
		return
	_guards = _guards.filter(func(g): return is_instance_valid(g) and not g.is_dead)
	_builders = _builders.filter(func(b): return is_instance_valid(b) and not b.is_dead)
	_update_build(delta)
	if not _hurt_said and z.hp < z.max_hp * 0.5:
		_hurt_said = true
		say("hurt")
	_taunt_cd -= delta
	if _taunt_cd <= 0.0:
		_taunt_cd = randf_range(14.0, 24.0)
		if _near_player(30.0):
			say("taunt")
	_order_cd -= delta
	if _order_cd <= 0.0 and z.rise_timer <= 0.0 and z.entry_stage >= 3 and _near_player(28.0):
		_order_cd = [12.0, 12.0, 12.0, 12.0, 10.0, 8.0][z.tier]
		_give_order()


func guard_count() -> int:
	var n := 0
	for g in _guards:
		if is_instance_valid(g) and not g.is_dead and g.global_position.distance_to(z.global_position) < 6.0:
			n += 1
	return n


func _near_player(r: float) -> bool:
	return is_instance_valid(z.target_player) and z.global_position.distance_to(z.target_player.global_position) < r


func _minions(radius: float, count: int, exclude: Array = []) -> Array:
	var list: Array = []
	for n in z.get_tree().get_nodes_in_group("enemies"):
		if n == z or n.is_dead or n.is_boss or n.tier >= 3 or n in exclude or n.order_t > 0.0 or n.entry_stage < 3:
			continue
		var d: float = n.global_position.distance_to(z.global_position)
		if d < radius:
			list.append([d, n])
	list.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in range(mini(count, list.size())):
		out.append(list[i][1])
	return out


func _give_order() -> void:
	var options := ["trap", "flank", "guard"]
	if z.tier >= 4:
		options.append("rally")
	if z.tier >= 5:
		options.append("summon")
	if not _builders.is_empty():
		options.erase("trap")
	if guard_count() >= 2:
		options.erase("guard")
	if z.hp < z.max_hp * 0.5 and "guard" in options:
		options.append("guard") # hurt commanders want bodyguards
	var pick: String = options[randi() % options.size()]
	match pick:
		"trap":
			_order_trap()
		"flank":
			_order_flank()
		"guard":
			_order_guard()
		"rally":
			_order_rally()
		"summon":
			_order_summon()


func _order_trap() -> void:
	var b := _minions(25.0, 2)
	if b.is_empty():
		return
	var p: Node3D = z.target_player
	var ahead := Vector3(p.velocity.x, 0, p.velocity.z) if "velocity" in p else Vector3.ZERO
	var spot: Vector3 = p.global_position + (ahead.normalized() * 6.0 if ahead.length() > 1.0 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 5.0)
	var map: RID = z.get_world_3d().navigation_map
	spot = NavigationServer3D.map_get_closest_point(map, spot)
	_build_pos = spot
	_build_t = 0.0
	_builders = b
	for m in b:
		m.give_order("build", spot + Vector3(randf_range(-0.7, 0.7), 0, randf_range(-0.7, 0.7)), 10.0, z)
	say("trap")


func _update_build(delta: float) -> void:
	if _builders.is_empty():
		if _build_t > 0.0:
			_build_t = 0.0
			say("fail")
		return
	var working := 0
	for b in _builders:
		if b.order_kind == "build" and b.at_order_spot(2.0):
			working += 1
	if working > 0:
		_build_t += delta * float(working)
	if _build_t >= 4.0:
		var wm := z.get_tree().current_scene.get_node_or_null("WaveManager")
		if wm and wm.has_method("spawn_zombie_trap"):
			wm.spawn_zombie_trap(_build_pos, z.tier)
		for b in _builders:
			b.order_t = 0.0
			b.order_kind = ""
		_builders.clear()
		_build_t = 0.0
	elif _builders.all(func(b): return b.order_t <= 0.0):
		_builders.clear()
		_build_t = 0.0
		say("fail")


func _order_flank() -> void:
	var m := _minions(30.0, 2 + z.tier - 2)
	if m.is_empty():
		return
	var p: Node3D = z.target_player
	var to_p: Vector3 = p.global_position - z.global_position
	to_p.y = 0.0
	var side := to_p.normalized().cross(Vector3.UP)
	for i in range(m.size()):
		var sgn := 1.0 if i % 2 == 0 else -1.0
		var spot: Vector3 = p.global_position + side * sgn * 7.0 - to_p.normalized() * 2.0
		m[i].give_order("flank", spot, 4.0, z)
		m[i].buff_t = maxf(m[i].buff_t, 6.0)
		# After reaching the side, they run in hard
		m[i].get_tree().create_timer(4.0).timeout.connect(func():
			if is_instance_valid(m[i]) and not m[i].is_dead:
				m[i].give_order("flank_run", Vector3.ZERO, 5.0, z))
	say("flank")


func _order_guard() -> void:
	var m := _minions(18.0, 3 + (z.tier - 3))
	if m.is_empty():
		return
	_guards = m
	for i in range(m.size()):
		var a := TAU * float(i) / float(m.size())
		m[i].give_order("guard", Vector3(cos(a), 0, sin(a)) * 2.2, 9.0, z)
	say("guard")


func _order_rally() -> void:
	var n := 0
	for e in z.get_tree().get_nodes_in_group("enemies"):
		if e == z or e.is_dead or e.is_boss:
			continue
		if e.global_position.distance_to(z.global_position) < 13.0:
			e.hp = minf(e.max_hp, e.hp + e.max_hp * 0.3)
			e.buff_t = maxf(e.buff_t, 8.0)
			n += 1
	if n > 0:
		say("rally")


func _order_summon() -> void:
	var wm := z.get_tree().current_scene.get_node_or_null("WaveManager")
	if wm == null:
		return
	for i in range(3):
		wm._spawn_regular_zombie(GameState.current_round)
	say("summon")


func on_player_down() -> void:
	if not z.is_dead and _near_player(40.0):
		say("down")


func on_death() -> void:
	say("death")


# Speech: bubble over the head and a subtitle for players nearby (all clients)
func say(kind: String) -> void:
	var opts: Array = LINES.get(kind, [])
	if opts.is_empty():
		return
	var line: String = opts[randi() % opts.size()]
	show_line(line)
	if Net.is_online() and not z.net_puppet and z.net_id > 0:
		var ng: Node = z._net_game()
		if ng:
			ng.zombie_say(z, line)


func show_line(line: String) -> void:
	_bubble.text = line
	_bubble.visible = true
	_bubble_t = 4.5
	var cam := z.get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(z.global_position) < 45.0:
		GameState.subtitle.emit("%s: \"%s\"" % [z.commander_name, line], z.TIER_COLORS[z.tier])
	GameState.play_sfx("zombie_groan", -6.0, 0.6)
