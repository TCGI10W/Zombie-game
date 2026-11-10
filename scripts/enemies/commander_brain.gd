extends Node
# COMMANDER BRAIN (tier 3+): a zombie that ate enough brain to think and talk.
#
#   TIER 3  COMMANDER  leads from behind, gives orders and uses one skill it
#                      stole from an operator's brain (slam / toxin / arc)
#   TIER 4  WARLORD    + RALLY, RAISE DEAD, DEVOUR (eats a minion to heal)
#   TIER 5  OVERLORD   + SUMMON, PSYCHIC SCREAM (a headshot interrupts it)
#
# Orders: TRAP, FLANK, GUARD (bodyguards = damage shield), RUSH (when you
# reload or bleed), BOMBER (sends a bloater), VOLLEY (spitters fire together).
# Zombies near a commander fight harder (aura). When its horde is dead it
# stops hiding and charges. Logic runs on the host; speech and effects go to
# every player.

const FIRST := ["GRUL", "VESK", "MORRAK", "SKARN", "HOLLOW", "OSSIAN", "DREG", "KHAR", "MAWL", "VORN", "SILAS", "ROTFANG", "ULGRIM", "NOX", "CARRION", "BRAKK"]
const TITLE := ["THE GNAWER", "BRAINEATER", "THE HUNGRY", "THE CLEVER", "SKULLSPLITTER", "THE WHISPERER", "THE FIRST", "OF THE PIT", "THE PATIENT", "MARROWDRINKER"]
const SKILLS := {
	"slam": {"name": "SEISMIC SLAM", "from": "RAVAGER", "tip": "JUMP TO DODGE THE SHOCKWAVE"},
	"toxin": {"name": "TOXIN FLASK", "from": "ALCHEMIST", "tip": "GET OUT OF THE GREEN POOL"},
	"arc": {"name": "ARC CHARGE", "from": "WARDEN", "tip": "LEAVE THE BLUE CIRCLE BEFORE IT BURSTS"},
}
const OPERATOR_SKILL := {"ravager": "slam", "alchemist": "toxin", "warden": "arc"}
const AURA_R := 10.0
const LINES := {
	"rise": ["I... I CAN THINK. YOUR THOUGHTS TASTE LIKE FEAR.", "SO MANY MEMORIES IN ONE BRAIN. I KNOW HOW YOU FIGHT NOW.", "THE HUNGER IS QUIET. NOW I CAN PLAN.", "I REMEMBER WORDS. I REMEMBER... WAR."],
	"nemesis": ["WE MEET AGAIN, MEAT.", "I STILL TASTE YOUR BRAIN. I WANT THE REST.", "YOU DIED ONCE BY MY HAND. DIE AGAIN.", "DID YOU THINK I WOULD FORGET YOU?"],
	"taunt": ["YOU CAN'T RUN FOREVER, MEAT.", "I SMELL YOUR HEART BEATING FASTER.", "EVERY BULLET YOU WASTE MAKES ME STRONGER.", "COME CLOSER. I WANT ANOTHER TASTE.", "YOUR FRIENDS ARE ALREADY OURS.", "I COUNT YOUR BULLETS. DO YOU?", "THERE IS NO RESCUE. THERE IS ONLY US.", "TIRED YET? WE NEVER TIRE."],
	"trap": ["BUILD THE TRAP! THERE, IN THEIR PATH!", "BONES AND IRON. MAKE THEM BLEED.", "SET THE SPIKES! LET THEM WALK INTO IT."],
	"flank": ["SURROUND THEM! LEFT AND RIGHT!", "GO WIDE. CUT OFF THE ESCAPE.", "FROM THE SIDES, YOU FOOLS!"],
	"guard": ["PROTECT ME!", "STAND BEFORE ME. TAKE THE BULLETS.", "SHIELD YOUR MASTER!"],
	"rally": ["RISE! FEAST! FIGHT!", "FEEL MY HUNGER. TEAR THEM APART!", "STRONGER! FASTER! NOW!"],
	"summon": ["MORE! I CALL THE HORDE!", "COME TO ME, MY CHILDREN!"],
	"raise": ["RISE AGAIN! I AM NOT DONE WITH YOU!", "THE DEAD DO NOT REST WHILE I SPEAK.", "UP! CRAWL IF YOU MUST!"],
	"rush_reload": ["EMPTY GUN! NOW! NOW!", "RELOADING! TEAR THEM APART!", "THE WEAPON IS SILENT. GO!"],
	"rush_blood": ["BLOOD! FINISH IT!", "ALMOST DEAD. DO NOT LET THEM BREATHE!", "I SMELL THE END. CHARGE!"],
	"bomber": ["SEND THE BLOATED ONE!", "YOU, FAT ONE. GO AND BURST."],
	"volley": ["SPITTERS! FIRE!", "DROWN THEM IN ACID!"],
	"devour": ["YOUR FLESH SERVES ME.", "I NEED YOUR STRENGTH MORE THAN YOU DO.", "HOLD STILL. THIS IS AN HONOUR."],
	"scream": ["HEAR ME!", "YOUR MIND IS MINE!", "KNEEL!"],
	"interrupt": ["MY HEAD! YOU WILL SUFFER FOR THAT!", "AARGH! CLEVER MEAT..."],
	"slam": ["YOUR OWN TRICK, BEAST!", "I REMEMBER THIS ONE. DOWN!"],
	"toxin": ["A GIFT FROM YOUR DOCTOR'S MEMORIES.", "BREATHE DEEP."],
	"arc": ["LIGHTNING. I LEARNED IT FROM YOUR SERGEANT.", "FEEL YOUR OWN WEAPON."],
	"enrage": ["USELESS! I'LL DO IT MYSELF.", "WEAK FLESH. YOU FAILED ME. NOW WATCH.", "NO MORE HIDING. COME HERE!"],
	"hurt": ["YOU WILL PAY FOR THAT.", "PAIN... I REMEMBER PAIN.", "IS THAT ALL YOU HAVE?"],
	"fail": ["CLUMSY FOOLS! BUILD IT AGAIN!", "MUST I DO EVERYTHING MYSELF?"],
	"down": ["YOUR BRAIN WILL BE MINE.", "STAY DOWN. I'M HUNGRY.", "ANOTHER MEAL!"],
	"death": ["THIS... ISN'T... OVER...", "I'LL... REMEMBER... YOU...", "THE HORDE... WILL... AVENGE..."],
}

var z: Node # ZombieEnemy
var casting: String = "" # "slam" / "arc" / "scream" while winding up
var enraged: bool = false
var horde: int = 0 # lesser zombies alive around the commander
var _cast_t: float = 0.0
var _cast_pos: Vector3 = Vector3.ZERO
var _skill_cd: float = 6.0
var _skill_said: bool = false
var _order_cd: float = 5.0
var _taunt_cd: float = 9.0
var _react_cd: float = 6.0
var _devour_cd: float = 0.0
var _scream_cd: float = 10.0
var _summons_left: int = 3
var _prey: Node = null # minion called over to be eaten
var _raises_left: int = 3
var _tick: float = 0.0
var _alone_t: float = 0.0
var _had_horde: bool = false
var _hurt_said: bool = false
var _intro_done: bool = false
var _guards: Array = []
var _builders: Array = []
var _build_pos: Vector3
var _build_t: float = 0.0
var _bubble: Label3D
var _bubble_t: float = 0.0


static func random_name() -> String:
	return "%s %s" % [FIRST[randi() % FIRST.size()], TITLE[randi() % TITLE.size()]]


static func random_skill() -> String:
	var keys: Array = SKILLS.keys()
	return String(keys[randi() % keys.size()])


func setup(owner_zombie: Node) -> void:
	z = owner_zombie
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


func _process(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble.visible = false
	if z == null or z.is_dead or z.net_puppet:
		return
	if z.rise_timer > 0.0 or z.entry_stage < 3:
		return
	if not _intro_done:
		_intro_done = true
		say("nemesis" if z.is_nemesis else "rise")
	_guards = _guards.filter(func(g): return is_instance_valid(g) and not g.is_dead)
	_builders = _builders.filter(func(b): return is_instance_valid(b) and not b.is_dead)
	_update_build(delta)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_slow_tick()
	if z.stun_timer > 0.0:
		if casting != "":
			_cancel_cast()
		return
	if casting != "":
		_cast_t -= delta
		if _cast_t <= 0.0:
			_finish_cast()
		return
	if not is_instance_valid(z.target_player):
		return
	var dist := _dist()

	# The skill it stole from an operator's brain
	_skill_cd -= delta
	if _skill_cd <= 0.0 and dist < 26.0:
		_skill_cd = 1.0 # could not use it yet: look again soon
		if _try_skill(dist):
			_skill_cd = [0.0, 0.0, 0.0, 10.0, 8.5, 7.0][z.tier]
			return

	if z.tier >= 5:
		_scream_cd -= delta
		if _scream_cd <= 0.0 and dist < 13.0:
			_scream_cd = 18.0
			_begin_cast("scream", 1.5, z.global_position, 12.0)
			say("scream")
			return

	if z.tier >= 4:
		if is_instance_valid(_prey) and not _prey.is_dead:
			if _prey.global_position.distance_to(z.global_position) < 2.8:
				_eat(_prey)
			elif _prey.order_kind != "serve":
				_prey = null # it never made it
		else:
			_devour_cd -= delta
			if _devour_cd <= 0.0 and z.hp < z.max_hp * 0.55:
				_devour_cd = 18.0 if _call_prey() else 3.0

	_react_cd -= delta
	if _react_cd <= 0.0 and dist < 26.0:
		_react_cd = 14.0 if _react() else 0.7

	_taunt_cd -= delta
	if _taunt_cd <= 0.0:
		_taunt_cd = randf_range(14.0, 24.0)
		if dist < 30.0 and _bubble_t <= 0.0:
			say("taunt")

	_order_cd -= delta
	if _order_cd <= 0.0 and dist < 30.0:
		_order_cd = [12.0, 12.0, 12.0, 11.0, 9.0, 7.5][z.tier]
		_give_order()


# Twice a second: count the horde, spread the aura, decide whether to charge
func _slow_tick() -> void:
	var n := 0
	var aura := 1.0 + 0.06 * float(z.tier)
	for e in z.get_tree().get_nodes_in_group("enemies"):
		if e == z or e.is_dead or e.is_boss or e.tier >= 3:
			continue
		var d: float = e.global_position.distance_to(z.global_position)
		if d < 30.0:
			n += 1
		if d < AURA_R:
			e.aura_mult = aura if e.aura_t <= 0.0 else maxf(aura, e.aura_mult)
			e.aura_t = 0.9
	horde = n
	z.shield_on = guard_count() >= 2
	if n >= 3:
		_had_horde = true
	_alone_t = _alone_t + 0.5 if n <= 1 else 0.0
	if not enraged and ((_had_horde and n <= 1) or _alone_t >= 6.0 or z.hp < z.max_hp * 0.3):
		_enrage()
	if not _hurt_said and z.hp < z.max_hp * 0.5:
		_hurt_said = true
		say("hurt")


# Lead from behind while there is a horde to hide behind
func wants_distance() -> bool:
	return not enraged and horde >= 2


func _enrage() -> void:
	enraged = true
	z.base_speed *= 1.35
	z.base_damage *= 1.2
	z.commander_fx("cenrage", z.global_position, 0.0)
	say("enrage")


func guard_count() -> int:
	var n := 0
	for g in _guards:
		if is_instance_valid(g) and not g.is_dead and g.order_kind == "guard" and g.global_position.distance_to(z.global_position) < 6.5:
			n += 1
	return n


func _dist() -> float:
	var off: Vector3 = z.target_player.global_position - z.global_position
	off.y = 0.0
	return off.length()


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


func _specials(flag: String, radius: float) -> Array:
	var out: Array = []
	for n in z.get_tree().get_nodes_in_group("enemies"):
		if n == z or n.is_dead or n.is_boss or n.entry_stage < 3 or not bool(n.get(flag)):
			continue
		if n.global_position.distance_to(z.global_position) < radius:
			out.append(n)
	return out


# ---------------------------------------------------------------------------
# STOLEN SKILLS
# ---------------------------------------------------------------------------
func _try_skill(dist: float) -> bool:
	var p: Node3D = z.target_player
	match String(z.stolen_skill):
		"slam":
			if dist < 6.5:
				_begin_cast("slam", 0.9, z.global_position, 5.0)
				_say_skill()
				return true
		"arc":
			if dist > 3.0 and dist < 22.0:
				var lead := Vector3.ZERO
				if "velocity" in p:
					lead = Vector3(p.velocity.x, 0.0, p.velocity.z) * 0.45
				_begin_cast("arc", 1.15, p.global_position + lead, 3.6)
				_say_skill()
				return true
		"toxin":
			if dist > 3.0 and dist < 22.0:
				z.commander_fx("ctoxin", p.global_position, z.base_damage * 0.22)
				_say_skill()
				return true
	return false


func _say_skill() -> void:
	if not _skill_said or randf() < 0.3:
		_skill_said = true
		say(String(z.stolen_skill))


func _begin_cast(kind: String, time: float, pos: Vector3, radius: float) -> void:
	casting = kind
	_cast_t = time
	_cast_pos = pos
	z.commander_fx("cwarn_" + kind, pos, radius)


func _finish_cast() -> void:
	var kind := casting
	casting = ""
	match kind:
		"slam":
			z.commander_fx("cslam", _cast_pos, z.base_damage * 0.9)
		"arc":
			z.commander_fx("carc", _cast_pos, z.base_damage * 0.75)
		"scream":
			z.commander_fx("cscream", z.global_position, z.base_damage * 0.5)
			for e in z.get_tree().get_nodes_in_group("enemies"):
				if e != z and not e.is_dead and not e.is_boss and e.global_position.distance_to(z.global_position) < 14.0:
					e.buff_t = maxf(e.buff_t, 5.0)


func _cancel_cast() -> void:
	casting = ""
	z.commander_fx("ccancel", Vector3.ZERO, 0.0)


# A headshot while it screams breaks its concentration
func on_headshot() -> void:
	if casting == "scream":
		_cancel_cast()
		_scream_cd = 14.0
		z.apply_stun(1.6)
		say("interrupt")


# Warlords eat one of their own to heal: the nearest minion is called over
# (kill it on the way and the meal is off)
func _call_prey() -> bool:
	var m := _minions(25.0, 1)
	if m.is_empty():
		return false
	_prey = m[0]
	_prey.give_order("serve", Vector3.ZERO, 8.0, z)
	say("devour")
	return true


func _eat(prey: Node) -> void:
	_prey = null
	z.commander_fx("cdevour", prey.global_position + Vector3(0, 1.0, 0), 0.0)
	prey.take_damage(1.0e7, prey.global_position + Vector3(0, 1.0, 0), true, "explosive")
	z.hp = minf(z.max_hp, z.hp + z.max_hp * 0.3)


# The player is reloading or badly hurt: send everyone in, right now
func _react() -> bool:
	var p: Node3D = z.target_player
	var reloading: bool = p.get("is_reloading") == true
	var hp_low := false
	if p.get("max_hp") != null:
		hp_low = float(p.get("hp")) < float(p.get("max_hp")) * 0.35
	elif p.get("hp_ratio") != null:
		hp_low = float(p.get("hp_ratio")) < 0.35
	if not reloading and not hp_low:
		return false
	var n := 0
	for e in z.get_tree().get_nodes_in_group("enemies"):
		if e == z or e.is_dead or e.is_boss or e.tier >= 3:
			continue
		if e.global_position.distance_to(p.global_position) < 20.0:
			e.buff_t = maxf(e.buff_t, 3.5)
			n += 1
	if n < 2:
		return false
	say("rush_blood" if hp_low else "rush_reload")
	return true


# ---------------------------------------------------------------------------
# ORDERS
# ---------------------------------------------------------------------------
func _give_order() -> void:
	var options := ["flank"]
	if _builders.is_empty() and z.get_tree().get_nodes_in_group("zombie_traps").size() < 4:
		options.append("trap")
	if guard_count() < 2:
		options.append("guard")
		if z.hp < z.max_hp * 0.6:
			options.append("guard") # hurt commanders want bodyguards
	if z.tier >= 4:
		options.append("rally")
		if _raises_left > 0:
			options.append("raise")
	if z.tier >= 5 and _summons_left > 0:
		options.append("summon")
	if not _specials("is_bloater", 35.0).is_empty():
		options.append("bomber")
	if not _specials("is_spitter", 35.0).is_empty():
		options.append("volley")
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
		"raise":
			_order_raise()
		"summon":
			_order_summon()
		"bomber":
			_order_bomber()
		"volley":
			_order_volley()


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
	var m := _minions(30.0, z.tier)
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
		var rid: int = m[i].get_instance_id()
		var zid: int = z.get_instance_id()
		z.get_tree().create_timer(4.0).timeout.connect(func():
			var runner: Object = instance_from_id(rid)
			var boss: Object = instance_from_id(zid)
			if is_instance_valid(runner) and is_instance_valid(boss) and not runner.is_dead:
				runner.give_order("flank_run", Vector3.ZERO, 5.0, boss))
	say("flank")


func _order_guard() -> void:
	var m := _minions(18.0, 3 + (z.tier - 3))
	if m.size() < 2:
		return
	_guards = m
	for i in range(m.size()):
		var a := TAU * float(i) / float(m.size())
		m[i].give_order("guard", Vector3(cos(a), 0, sin(a)) * 2.2, 14.0, z)
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
		z.commander_fx("crally", z.global_position, 13.0)
		say("rally")


func _order_raise() -> void:
	var wm := z.get_tree().current_scene.get_node_or_null("WaveManager")
	if wm == null or wm.alive_enemies > wm._max_alive() - 3:
		return
	_raises_left -= 1
	var map: RID = z.get_world_3d().navigation_map
	for i in range(2 if z.tier == 4 else 3):
		var pos: Vector3 = z.global_position + Vector3(randf_range(-3.5, 3.5), 0, randf_range(-3.5, 3.5))
		pos = NavigationServer3D.map_get_closest_point(map, pos)
		z.commander_fx("craise", pos, 0.0)
		wm._spawn_regular_zombie(GameState.current_round, pos + Vector3(0, 0.1, 0), "crawler")
	say("raise")


func _order_summon() -> void:
	var wm := z.get_tree().current_scene.get_node_or_null("WaveManager")
	if wm == null or wm.alive_enemies > wm._max_alive() - 3:
		return
	_summons_left -= 1
	for i in range(3):
		wm._spawn_regular_zombie(GameState.current_round)
	say("summon")


func _order_bomber() -> void:
	var list := _specials("is_bloater", 35.0)
	if list.is_empty():
		return
	for b in list:
		b.give_order("flank_run", Vector3.ZERO, 8.0, z)
		b.buff_t = maxf(b.buff_t, 8.0)
	say("bomber")


func _order_volley() -> void:
	var list := _specials("is_spitter", 35.0)
	if list.is_empty():
		return
	for s in list:
		s.attack_cooldown = randf_range(0.1, 0.6)
	say("volley")


func on_player_down() -> void:
	if not z.is_dead and is_instance_valid(z.target_player) and _dist() < 40.0:
		say("down")


func on_death() -> void:
	if casting != "":
		_cancel_cast()
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
	z.speak()
