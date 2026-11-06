class_name WaveManager
extends Node

signal round_started(round_num: int, boss_cfg: Dictionary)
signal wave_status_changed(status_text: String)
signal boss_spawned(boss: ZombieEnemy)
signal boss_updated(boss: ZombieEnemy)
signal boss_defeated(boss_name: String)
signal powerup_collected(kind: String)
signal exfil_won()
signal run_won()

const PowerUpScript := preload("res://scripts/world/power_up.gd")
const RelicScript := preload("res://scripts/world/boss_relic.gd")
const BOSS_RELIC_CHANCE := 0.25
const HeliScript := preload("res://scripts/world/extraction_heli.gd")
const MAX_DROPS_PER_ROUND := 4
const MAX_ALIVE := 20

var arena: BunkerArena
var player: PlayerController
var enemies_container: Node3D

var zombies_to_spawn: int = 0
var alive_enemies: int = 0
var boss_pending: bool = false
var boss_intro_triggered: bool = false
var active_boss: ZombieEnemy = null

var spawn_timer: float = 0.0
var boss_intro_timer: float = 0.0
var intermission_timer: float = 0.0
var in_intermission: bool = false

var weather: Weather

# Extraction: 0 idle, 1 hold out, 2 boarding, 3 over
const EXFIL_HOLD := 90.0
const EXFIL_BOARD := 40.0
const LZ_RADIUS := 3.0
var exfil_state: int = 0
var exfil_timer: float = 0.0
var board_progress: float = 0.0
var lz_pos: Vector3 = Vector3(0.0, 0.0, 8.5)
var heli: Node3D
var lz_marker: Node3D
var hound_round: bool = false
var hounds_to_spawn: int = 0
var hound_timer: float = 0.0

var kills_until_drop: int = 0
var drops_this_round: int = 0
var _nuking: bool = false


func setup(p_arena: BunkerArena, p_player: PlayerController, p_container: Node3D) -> void:
	arena = p_arena
	if "lz_pos" in p_arena:
		lz_pos = p_arena.lz_pos
	player = p_player
	enemies_container = p_container
	kills_until_drop = randi_range(7, 12)
	arena.zone_opened.connect(func(zid: String):
		player.status_banner_requested.emit("%s OPENED — NEW WINDOWS ARE NOW ACTIVE" % arena.zone_names[zid], Color(1.0, 0.85, 0.4))
	)
	if not Net.is_online():
		if GameState.pending_resume:
			resume_saved_world()
		else:
			start_round(1) # online: NetGame starts round 1 once everyone has loaded


func start_round(round_num: int) -> void:
	if Net.is_online():
		_c_round.rpc(round_num)
	_present_round(round_num)
	_commander_due = round_num >= 8 and randf() < 0.3 + 0.04 * float(GameState.difficulty)
	var n := Net.player_count()
	var crowd := 1.0 + 0.55 * float(n - 1)
	in_intermission = false
	drops_this_round = 0
	zombies_to_spawn = int(round(float(6 + round_num * 3) * crowd * GameState.diff("crowd")))
	hounds_to_spawn = 0
	if hound_round:
		zombies_to_spawn = 0
		hounds_to_spawn = mini(int(round(float(6 + round_num) * crowd)), 26 + 6 * (n - 1))
		hound_timer = 4.0
	boss_pending = true
	boss_intro_triggered = false
	boss_intro_timer = 0.0
	spawn_timer = 1.5
	_emit_wave_status()


@rpc("authority", "call_remote", "reliable")
func _c_round(round_num: int) -> void:
	in_intermission = false
	_present_round(round_num)


# What every player sees and gets when a round begins.
func _present_round(round_num: int) -> void:
	GameState.current_round = round_num
	GameState.round_changed.emit(round_num)
	hound_round = false # hound raids removed
	if hound_round:
		GameState.play_sfx("hound_round_sting", 0.0, 1.0)
		GameState.play_sfx("hound_howl", -5.0, randf_range(0.95, 1.05))
	else:
		GameState.play_sfx("round_sting", 0.0, 1.0)
	GameState.rebuild_points_round = 0
	if round_num > 1:
		GameState.record_run()
		player.add_grenades(2)
	if weather:
		weather.set_storm(hound_round)
	var boss_cfg := GameState.get_boss_config(round_num)
	round_started.emit(round_num, boss_cfg)
	if round_num == GameState.FINAL_ROUND and GameState.game_mode == "casual":
		player.status_banner_requested.emit("FINAL ROUND! KILL THE PROGENITOR TO END THE OUTBREAK", Color(1.0, 0.82, 0.25))
	var ng := _ng()
	if ng:
		ng.on_round_start(round_num)
	# Autosave at the top of every round
	if is_instance_valid(player) and not player.is_dead:
		GameState.save_player_state(player.export_state())
	if Net.is_host():
		GameState.save_world(world_state())


func _ng() -> Node:
	return get_tree().get_first_node_in_group("net_game")


func _banner(text: String, col: Color) -> void:
	player.status_banner_requested.emit(text, col)
	if Net.is_online() and Net.is_host():
		_c_banner.rpc(text, col)


@rpc("authority", "call_remote", "reliable")
func _c_banner(text: String, col: Color) -> void:
	player.status_banner_requested.emit(text, col)


# Every player zombies can go after (this machine's player + teammates)
func _all_players() -> Array:
	return get_tree().get_nodes_in_group("net_players")


func _any_player_alive() -> bool:
	for p in _all_players():
		if not p.is_dead and not p.extracted:
			return true
	return false


# Near a random living player: where the action is
func _focus_pos() -> Vector3:
	var alive := []
	for p in _all_players():
		if not p.is_dead and not p.extracted:
			alive.append(p)
	if alive.is_empty():
		return player.global_position
	return (alive[randi() % alive.size()] as Node3D).global_position


func _nearest_player(pos: Vector3) -> Node3D:
	var best: Node3D = player
	var best_d := INF
	for p in _all_players():
		if p.is_dead or p.is_downed or p.extracted:
			continue
		var d := pos.distance_squared_to((p as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _max_alive() -> int:
	return mini(MAX_ALIVE + 3 * (Net.player_count() - 1), 36)


func _net_register(z: ZombieEnemy, data: Dictionary) -> void:
	var ng := _ng()
	if ng:
		ng.register_zombie(z, data)


# Clients only mirror: the HUD's extraction countdown and boarding meter.
func _client_process(delta: float) -> void:
	if exfil_state == 1 or exfil_state == 2:
		exfil_timer = maxf(0.0, exfil_timer - delta)
	if exfil_state == 2 and is_instance_valid(player):
		var bp: Vector3 = heli.board_point() if is_instance_valid(heli) else lz_pos
		var d := Vector2(player.global_position.x - bp.x, player.global_position.z - bp.z).length()
		if d < LZ_RADIUS and not player.is_downed and not player.is_dead:
			board_progress = minf(1.0, board_progress + delta / 2.5)
		else:
			board_progress = maxf(0.0, board_progress - delta * 0.8)


func _process(delta: float) -> void:
	if Net.is_client():
		_client_process(delta)
		return
	_watch_downs()
	_process_feast(delta)
	if not _any_player_alive():
		return

	if exfil_state != 0:
		_process_exfil(delta)
		return

	if in_intermission:
		intermission_timer -= delta
		if intermission_timer <= 0.0:
			start_round(GameState.current_round + 1)
		return

	# Phase 1: zombies break in through the windows
	if zombies_to_spawn > 0 and alive_enemies < _max_alive():
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			spawn_timer = maxf(0.55, 1.9 - float(GameState.current_round) * 0.12)
			zombies_to_spawn -= 1
			_spawn_regular_zombie(GameState.current_round)

	# Hound raid: dogs arrive in lightning strikes around the player
	if hounds_to_spawn > 0 and alive_enemies < 6 + GameState.current_round / 5 + 2 * (Net.player_count() - 1):
		hound_timer -= delta
		if hound_timer <= 0.0:
			hound_timer = randf_range(0.9, 1.7)
			hounds_to_spawn -= 1
			_spawn_hound(GameState.current_round)

	# Phase 2: the round boss arrives once the horde is dead
	if zombies_to_spawn <= 0 and hounds_to_spawn <= 0 and alive_enemies <= 0 and boss_pending:
		if not boss_intro_triggered:
			boss_intro_triggered = true
			boss_intro_timer = 2.5
			GameState.play_sfx("boss_roar", 2.0, 0.92)
			var cfg := GameState.get_boss_config(GameState.current_round)
			_banner(
				"ALL ZOMBIES ELIMINATED! ROUND %d BOSS INCOMING: %s!" % [GameState.current_round, cfg["name"]],
				cfg["color"]
			)
			_emit_wave_status()
		else:
			boss_intro_timer -= delta
			if boss_intro_timer <= 0.0:
				boss_pending = false
				boss_intro_triggered = false
				_spawn_round_boss(GameState.current_round)
		return

	# Phase 3: round over once the boss and its minions are dead
	if zombies_to_spawn <= 0 and hounds_to_spawn <= 0 and not boss_pending and alive_enemies <= 0:
		in_intermission = true
		if weather and weather.storm:
			weather.set_storm(false)
		intermission_timer = 8.0
		_emit_wave_status()
		_banner(
			"ROUND %s CLEARED! NEXT ROUND IN 8s — REBUILD WINDOWS & VISIT THE FURNACE!" % GameState.to_roman(GameState.current_round),
			Color(0.95, 0.82, 0.32)
		)


# Picks an open window, favouring ones near the player.
func _pick_window() -> Node3D:
	var options := arena.get_open_windows()
	if options.is_empty():
		return null
	var weights: Array[float] = []
	var total := 0.0
	var focus := _focus_pos()
	for w in options:
		var d := w.global_position.distance_to(focus)
		var wt := 1.0 / (1.0 + d / 9.0)
		weights.append(wt)
		total += wt
	var roll := randf() * total
	for i in range(options.size()):
		roll -= weights[i]
		if roll <= 0.0:
			return options[i]
	return options.back()


func _spawn_regular_zombie(round_num: int, forced_pos: Vector3 = Vector3.INF, forced_variant: String = "") -> void:
	var z := ZombieEnemy.new()
	z.add_to_group("enemies")

	var variant := forced_variant
	if variant == "":
		var roll := randf()
		var sp := GameState.diff("special")
		if round_num >= 10 and randf() < 0.1 * sp and _count_alive("spitter") < int(3 * sp):
			variant = "spitter"
		elif round_num >= 10 and randf() < 0.12 * sp and _count_alive("shielded") < int(4 * sp):
			variant = "shielded"
		elif round_num >= 6 and randf() < 0.07 * sp and _count_alive("bloater") < int(2 * sp):
			variant = "bloater"
		elif round_num >= 3 and roll < 0.22:
			variant = "armored"
		elif round_num >= 2 and roll < 0.52:
			variant = "sprinter"
		else:
			variant = "walker"

	var window: Node3D = null
	var sp := forced_pos
	if sp == Vector3.INF:
		window = _pick_window()
		if window:
			var side := window.global_basis.x * randf_range(-1.5, 1.5)
			sp = window.spawn_pos() + side
			sp.y = 0.1
		else:
			sp = arena.get_boss_spawn(_focus_pos())

	enemies_container.add_child(z)
	z.global_position = sp
	z.setup_regular(round_num, variant)
	z.max_hp *= (1.0 + 0.12 * float(Net.player_count() - 1)) * GameState.diff_hp_mult()
	z.hp = z.max_hp
	z.base_damage *= GameState.diff_dmg_mult()
	z.base_speed *= GameState.diff("speed")
	z.target_player = _nearest_player(sp)
	if window:
		z.set_entry_window(window)
	z.died.connect(_on_enemy_died)
	# Tiers: most are tier 1, some tier 2 (more on harder difficulties).
	# From round 8 a commander can turn up on its own.
	if _commander_due and _count_commanders() == 0 and variant != "spitter":
		_commander_due = false
		z.apply_tier(3)
	elif randf() < clampf(0.25 + 0.05 * float(GameState.difficulty - 1) + 0.01 * float(round_num), 0.15, 0.6):
		z.apply_tier(2)
	_net_register(z, {"k": "z", "v": variant, "r": round_num, "w": arena.windows.find(window) if window else -1, "t": z.tier, "cn": z.commander_name})

	alive_enemies += 1
	_emit_wave_status()

	if randf() < 0.45:
		z._play_3d_roar("zombie_roar_1", randf_range(0.88, 1.12))


func _spawn_hound(round_num: int) -> void:
	var pos := _hound_spawn_point()
	if weather:
		weather.strike(pos)
	var h := HoundEnemy.new()
	h.add_to_group("enemies")
	enemies_container.add_child(h)
	h.global_position = pos + Vector3(0, 0.1, 0)
	h.setup_hound(round_num)
	h.max_hp *= 1.0 + 0.12 * float(Net.player_count() - 1)
	h.hp = h.max_hp
	h.target_player = _nearest_player(pos)
	h.died.connect(_on_enemy_died)
	_net_register(h, {"k": "h", "r": round_num})
	alive_enemies += 1
	_emit_wave_status()


# A point on the navmesh 7-13 m from the player, inside an open zone.
func _hound_spawn_point() -> Vector3:
	var map := player.get_world_3d().navigation_map
	var focus := _focus_pos()
	for i in range(18):
		var ang := randf() * TAU
		var d := randf_range(7.0, 13.0)
		var cand := focus + Vector3(cos(ang) * d, 0.0, sin(ang) * d)
		var snapped := NavigationServer3D.map_get_closest_point(map, cand)
		if snapped.distance_to(focus) < 6.0 or absf(snapped.y) > 0.6:
			continue
		var zone := arena.zone_at(snapped)
		if zone == "" or not arena.is_zone_open(zone):
			continue
		return snapped
	var w := _pick_window()
	if w:
		return w.inside_pos()
	return arena.get_boss_spawn(focus)


func _count_alive(kind: String) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var z := node as ZombieEnemy
		if z and not z.is_dead and ((kind == "bloater" and z.is_bloater) or (kind == "hound" and z.is_in_group("hounds")) or (kind == "spitter" and z.is_spitter) or (kind == "shielded" and z.is_shielded)):
			n += 1
	return n


func _spawn_round_boss(round_num: int) -> void:
	var cfg := GameState.get_boss_config(round_num)
	var boss := ZombieEnemy.new()
	boss.add_to_group("enemies")
	enemies_container.add_child(boss)
	boss.global_position = arena.get_boss_spawn(_focus_pos())
	boss.setup_boss(cfg)
	# Bosses are tougher: +70% health, +30% damage, faster, more armor
	boss.max_hp *= 1.7 * (1.0 + 0.65 * float(Net.player_count() - 1)) * GameState.diff_hp_mult() * GameState.diff("boss")
	boss.hp = boss.max_hp
	boss.base_damage *= 1.3 * GameState.diff_dmg_mult()
	boss.base_speed *= 1.12 * minf(GameState.diff("speed"), 1.15)
	boss.endurance = minf(0.6, boss.endurance + 0.08)
	boss.set_meta("final", bool(cfg.get("final", false)))
	boss.target_player = _nearest_player(boss.global_position)
	if is_instance_valid(boss.target_player):
		var tp := boss.target_player.global_position
		boss.look_at(Vector3(tp.x, boss.global_position.y, tp.z), Vector3.UP)
	boss._play_3d_roar("boss_roar", 0.95)
	boss.died.connect(_on_enemy_died)
	boss.boss_damaged.connect(func(b: ZombieEnemy): boss_updated.emit(b))
	boss.spawn_minion_requested.connect(func(pos: Vector3):
		var safe := NavigationServer3D.map_get_closest_point(boss.get_world_3d().navigation_map, pos)
		_spawn_regular_zombie(round_num, safe + Vector3(0, 0.1, 0), "crawler")
	)

	active_boss = boss
	alive_enemies += 1
	_emit_wave_status()
	boss_spawned.emit(boss)
	_net_register(boss, {"k": "b", "r": round_num})


func _on_enemy_died(enemy: ZombieEnemy, _was_headshot: bool) -> void:
	alive_enemies = maxi(0, alive_enemies - 1)
	_emit_wave_status()
	if enemy.tier >= 3 and not enemy.is_boss:
		_commander_slain(enemy)

	if enemy.is_boss:
		active_boss = null
		if enemy.get_meta("final", false):
			if Net.is_online():
				_c_victory.rpc()
			_victory()
			return
		_boss_relics(enemy.global_position)
		if Net.is_online():
			_c_boss_down.rpc(enemy.display_name)
		_boss_down(enemy.display_name)


var _next_powerup_id: int = 1
var _powerups_taken: Dictionary = {}
var _powerup_kinds: Dictionary = {}


# Host decides drops; every machine shows them; whoever touches one first
# (as the host sees it) triggers it for the whole squad.
func _spawn_powerup(kind: String, pos: Vector3, owner: int = 0) -> void:
	var id := _next_powerup_id
	_next_powerup_id += 1
	_powerup_kinds[id] = kind
	if Net.is_online():
		_c_powerup.rpc(id, kind, pos, owner)
	_make_powerup(id, kind, pos, owner)


@rpc("authority", "call_remote", "reliable")
func _c_powerup(id: int, kind: String, pos: Vector3, owner: int) -> void:
	_make_powerup(id, kind, pos, owner)


var _relic_misses: Dictionary = {} # peer id -> bosses in a row without a relic


# Every player rolls their own relic (25%); the third boss without one
# always pays out.
func _boss_relics(pos: Vector3) -> void:
	var ids: Array = Net.players.keys() if Net.is_online() else [1]
	ids.sort()
	for i in range(ids.size()):
		var pid := int(ids[i])
		var miss := int(_relic_misses.get(pid, 0))
		if randf() < BOSS_RELIC_CHANCE or miss >= 2:
			_relic_misses[pid] = 0
			var ang := float(i) / float(ids.size()) * TAU
			_spawn_powerup(_roll_relic(), pos + Vector3(cos(ang), 0.0, sin(ang)) * (1.2 if ids.size() > 1 else 0.0), pid if Net.is_online() else 0)
		else:
			_relic_misses[pid] = miss + 1


func _make_powerup(id: int, kind: String, pos: Vector3, owner: int = 0) -> void:
	var pu: Area3D = RelicScript.new() if kind.begins_with("relic:") else PowerUpScript.new()
	pu.kind = kind
	if kind.begins_with("relic:"):
		pu.owner_peer = owner
	pu.set_meta("pu_id", id)
	pu.add_to_group("net_powerups")
	get_parent().add_child(pu)
	pu.global_position = Vector3(pos.x, 0.0, pos.z)
	pu.collected.connect(func(_k: String): _request_powerup(id))
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = GameState.get_sfx_stream("powerup_spawn")
	sfx.bus = &"SFX"
	sfx.unit_size = 6.0
	pu.add_child(sfx)
	sfx.position.y = 1.0
	sfx.play()


func _request_powerup(id: int) -> void:
	if Net.is_host():
		_grant_powerup(id, Net.my_id())
	else:
		_s_powerup.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _s_powerup(id: int) -> void:
	if Net.is_host():
		_grant_powerup(id, multiplayer.get_remote_sender_id())


func _grant_powerup(id: int, collector: int) -> void:
	if _powerups_taken.has(id) or not _powerup_kinds.has(id):
		return
	_powerups_taken[id] = true
	var kind: String = _powerup_kinds[id]
	if Net.is_online():
		_c_powerup_taken.rpc(id, kind, collector)
	_powerup_taken(id, kind, collector)


@rpc("authority", "call_remote", "reliable")
func _c_powerup_taken(id: int, kind: String, collector: int) -> void:
	_powerup_taken(id, kind, collector)


func _powerup_taken(id: int, kind: String, collector: int) -> void:
	for pu in get_tree().get_nodes_in_group("net_powerups"):
		if int(pu.get_meta("pu_id", -1)) == id:
			pu.queue_free()
	if kind.begins_with("relic:"):
		if collector == Net.my_id():
			_apply_relic(kind)
		else:
			var r := RelicScript.rarity_of(kind)
			player.status_banner_requested.emit("%s FOUND A %s RELIC: %s" % [Net.player_name(collector), RelicScript.RARITY_NAMES[r], RelicScript.describe(kind)], RelicScript.RARITY_COLORS[r])
		return
	_on_powerup_collected(kind)


# Host: rarity 55% common, 28% rare, 13% epic, 4% legendary. Epic and
# legendary relics can hold another operator's skill instead of stat levels.
func _roll_relic(bonus: bool = false) -> String:
	var roll := randf() * 100.0
	if bonus:
		roll = 35.0 + randf() * 65.0 # bought caches skip most commons
	var rarity := 0 if roll < 55.0 else (1 if roll < 83.0 else (2 if roll < 96.0 else 3))
	if rarity >= 2 and randf() < 0.4:
		var skills: Array = PlayerController.BORROWED_SKILLS.keys()
		return "relic:%d:skill:%s:%d" % [rarity, skills[randi() % skills.size()], 60 if rarity == 3 else 100]
	var stat: String = GameState.STATS[randi() % GameState.STATS.size()]["id"]
	return "relic:%d:stat:%s:%d" % [rarity, stat, [1, 2, 3, 5][rarity]]


# This machine's player picked up a relic.
func _apply_relic(kind: String) -> void:
	var p := kind.split(":")
	var r := RelicScript.rarity_of(kind)
	var col: Color = RelicScript.RARITY_COLORS[r]
	var levels: int = [1, 2, 3, 5][r]
	if p[2] == "stat" and r < 3 and GameState.has_unlock("relic_luck") and randf() < 0.25:
		r += 1 # career unlock: a lucky upgrade
		col = RelicScript.RARITY_COLORS[r]
		p[4] = str([1, 2, 3, 5][r])
	GameState.play_sfx("level_up", 0.0, 1.0 + 0.08 * float(r))
	GameState.play_sfx("buy_ching", -2.0, 1.3)
	if p[2] == "skill" and player.can_borrow(p[3]):
		player.grant_borrowed_skill(p[3], float(p[4]) / 100.0)
		return
	# A stat relic (or a skill you already have): levels into a stat that isn't maxed
	var stat_id: String = p[3] if p[2] == "stat" else ""
	if p[2] == "stat":
		levels = int(p[4])
	var open_stats: Array = []
	for s in GameState.STATS:
		if player.stat_level(s["id"]) < GameState.STAT_MAX_LEVEL:
			open_stats.append(s["id"])
	if stat_id == "" or not stat_id in open_stats:
		if open_stats.is_empty():
			GameState.add_points(1000 * (r + 1))
			player.status_banner_requested.emit("%s RELIC! ALL STATS MAXED — +%d POINTS" % [RelicScript.RARITY_NAMES[r], 1000 * (r + 1)], col)
			return
		stat_id = open_stats[randi() % open_stats.size()]
	var gained: int = player.grant_stat_levels(stat_id, levels)
	var stat_name := stat_id.to_upper()
	for s in GameState.STATS:
		if s["id"] == stat_id:
			stat_name = s["name"]
	player.status_banner_requested.emit("%s RELIC! +%d %s" % [RelicScript.RARITY_NAMES[r], gained, stat_name], col)


@rpc("authority", "call_remote", "reliable")
func _c_boss_down(boss_name: String) -> void:
	_boss_down(boss_name)


func _boss_down(boss_name: String) -> void:
	GameState.bosses_slain += 1
	boss_defeated.emit(boss_name)
	if is_instance_valid(player) and not player.is_dead:
		player.refill_all_ammo()
		player.hp = minf(player.max_hp, player.hp + 45.0)
		player.hp_changed.emit(player.hp, player.max_hp, player.overshield)


func _on_powerup_collected(kind: String) -> void:
	if not is_instance_valid(player):
		return
	GameState.play_sfx("buy_ching", 2.0, 0.75)
	GameState.play_sfx("round_sting", -4.0, 1.6)
	match kind:
		"max_ammo":
			if not player.is_dead:
				player.refill_all_ammo()
		"insta_kill":
			GameState.activate_powerup("insta_kill")
			player.status_banner_requested.emit("INSTA-KILL! EVERY HIT KILLS FOR 20s", Color(0.92, 0.94, 1.0))
		"double_points":
			GameState.activate_powerup("double_points")
			player.status_banner_requested.emit("DOUBLE POINTS! 2x POINTS FOR 20s", Color(0.30, 1.0, 0.42))
		"nuke":
			_detonate_nuke()
		"carpenter":
			for w in arena.windows:
				if w.has_method("repair_all"):
					w.repair_all()
			GameState.add_points(200)
			GameState.play_sfx("carpenter", 0.0, 1.0)
			player.status_banner_requested.emit("CARPENTER! EVERY WINDOW REBUILT  +200", Color(0.95, 0.72, 0.4))
		"fire_sale":
			GameState.activate_powerup("fire_sale", 30.0)
			GameState.play_sfx("fire_sale", -1.0, 1.0)
			player.status_banner_requested.emit("FIRE SALE! MYSTERY CRATE COSTS 10 POINTS FOR 30s", Color(1.0, 0.35, 0.25))
	powerup_collected.emit(kind)


func _detonate_nuke() -> void:
	_nuking = true
	var killed := 0
	for node in (get_tree().get_nodes_in_group("enemies") if Net.is_host() else []):
		var z := node as ZombieEnemy
		if z and not z.is_dead and not z.is_boss:
			var res: Dictionary = z.take_damage(1.0e9, Vector3.ZERO, true, "explosive")
			if res["killed"]:
				killed += 1
	_nuking = false
	GameState.total_kills += killed
	GameState.add_points(400)
	GameState.play_sfx("grenade_explode", 3.0, 0.6)
	player.add_camera_shake(0.6)
	player.status_banner_requested.emit(("NUKE! %d ZOMBIES VAPORIZED  +400" % killed) if killed > 0 else "NUKE! THE HORDE IS VAPORIZED  +400", Color(1.0, 0.45, 0.18))


func _emit_wave_status() -> void:
	var txt := ""
	if exfil_state != 0:
		txt = "☢ EXTRACTION — %d HOSTILES" % alive_enemies
	elif in_intermission:
		txt = "INTERMISSION"
	elif boss_pending:
		if boss_intro_triggered:
			txt = "⚠ BOSS INCOMING!"
		else:
			var z_left := alive_enemies + zombies_to_spawn + hounds_to_spawn
			txt = ("HOUNDS: %d  (THEN BOSS)" if hound_round else "ZOMBIES: %d  (THEN BOSS)") % z_left
	else:
		txt = "☠ ROUND BOSS FIGHT"
	wave_status_changed.emit(txt)
	if Net.is_online() and Net.is_host():
		_c_status.rpc(txt, in_intermission)


@rpc("authority", "call_remote", "reliable")
func _c_status(txt: String, intermission: bool) -> void:
	in_intermission = intermission
	wave_status_changed.emit(txt)


# ---------------------------------------------------------------------------
# EXTRACTION
# ---------------------------------------------------------------------------
func start_exfil() -> void:
	if not Net.is_host():
		return
	in_intermission = false
	boss_pending = false
	zombies_to_spawn = 0
	hounds_to_spawn = 0
	spawn_timer = 1.5
	hound_timer = 12.0
	_boarded.clear()
	_board_progress.clear()
	_exfil_event("start")


var _boarded: Dictionary = {} # peer id -> true once on the chopper
var _board_progress: Dictionary = {} # peer id -> 0..1


# Extraction beats happen on every machine at the same moment.
func _exfil_event(ev: String) -> void:
	if Net.is_online() and Net.is_host():
		_c_exfil_event.rpc(ev)
	_present_exfil(ev)


@rpc("authority", "call_remote", "reliable")
func _c_exfil_event(ev: String) -> void:
	_present_exfil(ev)


func _present_exfil(ev: String) -> void:
	match ev:
		"start":
			exfil_state = 1
			exfil_timer = EXFIL_HOLD
			board_progress = 0.0
			in_intermission = false
			GameState.play_sfx("radio_call", 0.0, 1.0)
			GameState.play_sfx("exfil_siren", -4.0, 1.0)
			if weather:
				weather.set_storm(true)
			lz_marker = _make_lz_marker(lz_pos)
			player.status_banner_requested.emit("EXTRACTION INBOUND! HOLD OUT FOR 90 SECONDS, THEN GET TO THE FLARE IN THE COURTYARD", Color(1.0, 0.4, 0.2))
			wave_status_changed.emit("☢ EXTRACTION")
		"heli":
			exfil_timer = minf(exfil_timer, 26.0)
			heli = HeliScript.new()
			get_parent().add_child(heli)
			heli.fly_in(lz_pos, 24.0, 90.0)
			player.status_banner_requested.emit("CHOPPER INBOUND — HOLD ON!", Color(1.0, 0.75, 0.3))
		"ladder":
			exfil_state = 2
			exfil_timer = EXFIL_BOARD
			if heli:
				heli.lower_ladder()
			GameState.play_sfx("radio_beep", 0.0, 1.0)
			player.status_banner_requested.emit("THE CHOPPER IS HERE — GET TO THE LADDER!", Color(0.4, 1.0, 0.5))
		"depart":
			exfil_state = 3
			if is_instance_valid(lz_marker):
				lz_marker.queue_free()
			if is_instance_valid(player) and not player.extracted and not player.is_dead:
				player.status_banner_requested.emit("THE CHOPPER LEFT WITHOUT YOU...", Color(1.0, 0.25, 0.2))
				get_tree().create_timer(2.5).timeout.connect(func():
					if is_instance_valid(player) and not player.is_dead:
						player.revives = 0
						player.die()
				)
			get_tree().create_timer(2.2).timeout.connect(func():
				if is_instance_valid(heli):
					heli.depart()
			)


func _process_exfil(delta: float) -> void:
	if exfil_state == 3:
		return
	# Everything that's left comes for you
	spawn_timer -= delta
	if spawn_timer <= 0.0 and alive_enemies < _max_alive() + 4:
		spawn_timer = maxf(0.35, 0.95 - float(GameState.current_round) * 0.03) / sqrt(float(Net.player_count()))
		_spawn_regular_zombie(GameState.current_round + 1)
	if GameState.current_round >= 5:
		pass # no hounds any more

	exfil_timer -= delta
	if exfil_state == 1:
		if exfil_timer <= 26.0 and heli == null:
			_exfil_event("heli")
		if exfil_timer <= 0.0:
			_exfil_event("ladder")
	elif exfil_state == 2:
		var bp: Vector3 = heli.board_point() if heli else lz_pos
		var waiting := 0
		for p in _all_players():
			var pid: int = Net.my_id() if p == player else int(p.peer_id)
			if p.is_dead or _boarded.has(pid):
				continue
			waiting += 1
			var pos: Vector3 = (p as Node3D).global_position
			var d := Vector2(pos.x - bp.x, pos.z - bp.z).length()
			var prog: float = _board_progress.get(pid, 0.0)
			if d < LZ_RADIUS and not p.is_downed:
				prog += delta / 2.5
			else:
				prog = maxf(0.0, prog - delta * 0.8)
			_board_progress[pid] = prog
			if p == player:
				board_progress = prog
			if prog >= 1.0:
				_boarded[pid] = true
				waiting -= 1
				if pid == Net.my_id():
					_extract_local()
				else:
					_c_extract.rpc_id(pid)
		if (waiting <= 0 and not _boarded.is_empty()) or exfil_timer <= 0.0:
			_exfil_event("depart")


@rpc("authority", "call_remote", "reliable")
func _c_extract() -> void:
	_extract_local()


# This machine's player climbs aboard: they made it.
func _extract_local() -> void:
	if not is_instance_valid(player) or player.extracted:
		return
	player.extract_to(heli)
	GameState.play_sfx("exfil_success", 0.0, 1.0)
	GameState.record_exfil()
	exfil_won.emit()


# Burning red flare, smoke and a painted ring marking the landing zone.
func _make_lz_marker(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	get_parent().add_child(root)
	root.global_position = pos
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = LZ_RADIUS - 0.15
	tm.outer_radius = LZ_RADIUS
	tm.rings = 48
	ring.mesh = tm
	ring.scale = Vector3(1.0, 0.05, 1.0)
	ring.position.y = 0.03
	ring.material_override = MaterialLib.get_emissive(Color(1.0, 0.3, 0.12), 2.5, 0.8)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.035
	cm.height = 0.3
	stick.mesh = cm
	stick.material_override = MaterialLib.get_emissive(Color(1.0, 0.15, 0.08), 6.0)
	stick.position = Vector3(0, 0.08, 0)
	stick.rotation.z = 1.3
	root.add_child(stick)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.18, 0.08)
	light.light_energy = 3.5
	light.omni_range = 11.0
	light.position.y = 0.6
	root.add_child(light)
	light.set_meta("flicker", true)
	var smoke := CPUParticles3D.new()
	smoke.amount = 60
	smoke.lifetime = 5.0
	smoke.direction = Vector3(0.15, 1, 0.05)
	smoke.spread = 12.0
	smoke.gravity = Vector3(0.35, 0.6, 0.1)
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.2
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 2.8))
	smoke.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.25, 0.15, 0.65))
	grad.set_color(1, Color(0.5, 0.18, 0.15, 0.0))
	smoke.color_ramp = grad
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	if ResourceLoader.exists("res://assets/textures/soft_particle.png"):
		sm.albedo_texture = load("res://assets/textures/soft_particle.png")
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = sm
	smoke.mesh = q
	smoke.position.y = 0.15
	root.add_child(smoke)
	var snd := AudioStreamPlayer3D.new()
	var st := GameState.get_sfx_stream("flare_burn")
	if st is AudioStreamWAV:
		var wav: AudioStreamWAV = (st as AudioStreamWAV).duplicate()
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))  # in frames, whatever the import format
		snd.stream = wav
	snd.bus = &"SFX"
	snd.unit_size = 4.0
	root.add_child(snd)
	snd.play()
	GameState.play_sfx("flare_ignite", -2.0, 1.0)
	var tw := root.create_tween().set_loops()
	tw.tween_property(light, "light_energy", 2.4, 0.09)
	tw.tween_property(light, "light_energy", 3.8, 0.13)
	return root


@rpc("authority", "call_remote", "reliable")
func _c_victory() -> void:
	_victory()


# The final boss is dead: the run is won for everyone still in it.
func _victory() -> void:
	set_process(false)
	for z in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(z) and not z.is_dead and not z.net_puppet:
			z.take_damage(1.0e9, Vector3.ZERO, true, "explosive")
	GameState.play_sfx("exfil_success", 0.0, 1.0)
	if is_instance_valid(player):
		player.revive_invuln = 9999.0
	run_won.emit()


# ---------------------------------------------------------------------------
# RUN SAVE / RESUME / LATE JOIN
# ---------------------------------------------------------------------------
func world_state() -> Dictionary:
	var doors: Array = []
	var power := false
	for n in arena.find_children("*", "", true, false):
		if "_opened" in n and "zone_id" in n and n._opened:
			doors.append(String(n.zone_id))
		if "_running" in n and n._running:
			power = true
	return {"run_id": GameState.run_id, "round": GameState.current_round, "difficulty": GameState.difficulty, "mode": GameState.game_mode,
		"doors": doors, "power": power, "players": Net.player_count()}


# Host/solo: open the saved doors, restore power, start at the saved round.
func resume_saved_world() -> void:
	var w := GameState.load_world()
	var start := maxi(1, int(w.get("round", 1)))
	for n in arena.find_children("*", "", true, false):
		if "_opened" in n and "zone_id" in n and String(n.zone_id) in w.get("doors", []):
			Net.world(n, "open")
		if "_running" in n and bool(w.get("power", false)) and not n._running:
			Net.world(n, "start")
	start_round(start)
	_banner("RUN RESUMED — ROUND %d" % start, Color(0.55, 0.9, 1.0))



# ---------------------------------------------------------------------------
# ZOMBIE TIERS: the brain feast and commanders
# ---------------------------------------------------------------------------
const MAX_COMMANDERS := 2
const TrapScript := preload("res://scripts/world/zombie_trap.gd")
var _commander_due: bool = false
var _was_down: Dictionary = {}
var _feast_pos: Vector3 = Vector3.INF
var _feasters: Array = []
var _feast_t: float = 0.0
var _feast_fight: float = -1.0


func _count_commanders() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_dead and not e.is_boss and e.tier >= 3:
			n += 1
	return n


# A player just went down: the nearest zombies run for the body and fight
# over the brain. The winner ranks up one tier.
func _watch_downs() -> void:
	for p in get_tree().get_nodes_in_group("net_players"):
		var down: bool = bool(p.get("is_downed")) or bool(p.get("is_dead"))
		var key := p.get_instance_id()
		if down and not _was_down.get(key, false):
			_start_feast(p.global_position)
		_was_down[key] = down


func _start_feast(pos: Vector3) -> void:
	if _feast_pos != Vector3.INF:
		return
	var list: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_dead or e.is_boss or e.entry_stage < 3 or e.rise_timer > 0.0:
			continue
		var d: float = e.global_position.distance_to(pos)
		if d < 30.0:
			list.append([d, e])
		if e.commander:
			e.commander.on_player_down()
	if list.size() < 2:
		return
	list.sort_custom(func(a, b): return a[0] < b[0])
	_feasters.clear()
	for i in range(mini(4, list.size())):
		var e: ZombieEnemy = list[i][1]
		e.give_order("feast", pos + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8)), 12.0)
		_feasters.append(e)
	_feast_pos = pos
	_feast_t = 12.0
	_feast_fight = -1.0
	_banner_all("THEY'RE FIGHTING OVER YOUR BRAIN...", Color(1.0, 0.45, 0.35))


func _process_feast(delta: float) -> void:
	if _feast_pos == Vector3.INF:
		return
	_feasters = _feasters.filter(func(e): return is_instance_valid(e) and not e.is_dead)
	_feast_t -= delta
	if _feasters.is_empty() or _feast_t <= 0.0:
		_feast_pos = Vector3.INF
		return
	var arrived: Array = _feasters.filter(func(e): return e.at_order_spot(2.2))
	if _feast_fight < 0.0 and arrived.size() >= 1:
		_feast_fight = 3.5 # they claw at each other over the head
	if _feast_fight >= 0.0:
		_feast_fight -= delta
		for e in arrived:
			e.order_t = maxf(e.order_t, 1.0)
		if _feast_fight <= 0.0:
			_finish_feast(arrived if not arrived.is_empty() else _feasters)


func _finish_feast(contenders: Array) -> void:
	# Higher tiers win more often
	var total := 0.0
	for e in contenders:
		total += float(e.tier + 1)
	var r := randf() * total
	var winner: ZombieEnemy = contenders[0]
	for e in contenders:
		r -= float(e.tier + 1)
		if r <= 0.0:
			winner = e
			break
	for e in _feasters:
		e.order_t = 0.0
		e.order_kind = ""
	_feast_pos = Vector3.INF
	var new_tier := mini(5, winner.tier + 1)
	if new_tier >= 3 and winner.tier < 3 and _count_commanders() >= MAX_COMMANDERS:
		new_tier = winner.tier # the horde has enough leaders already
	if new_tier == winner.tier:
		winner.hp = winner.max_hp
		_banner_all("A ZOMBIE ATE YOUR BRAIN", Color(1.0, 0.6, 0.4))
		return
	winner.apply_tier(new_tier)
	winner.hp = winner.max_hp
	if new_tier >= 3:
		_banner_all("%s ATE YOUR BRAIN — TIER %d COMMANDER" % [winner.commander_name, new_tier], ZombieEnemy.TIER_COLORS[new_tier])
	else:
		_banner_all("A ZOMBIE ATE YOUR BRAIN — NOW TIER %d" % new_tier, ZombieEnemy.TIER_COLORS[new_tier])


func _commander_slain(z: ZombieEnemy) -> void:
	if z.commander:
		z.commander.on_death()
	_boss_relics(z.global_position)
	_banner_all("COMMANDER %s SLAIN! RELIC DROPPED" % z.commander_name, Color(0.5, 1.0, 0.6))


func spawn_zombie_trap(pos: Vector3, t: int) -> void:
	_place_trap(pos, t)
	var ng := _ng()
	if ng:
		ng.zombie_trap(pos, t)


func _place_trap(pos: Vector3, t: int) -> void:
	var trap: Node3D = TrapScript.new()
	trap.tier = t
	get_tree().current_scene.add_child(trap)
	trap.global_position = pos


func _banner_all(text: String, col: Color) -> void:
	if is_instance_valid(player):
		player.status_banner_requested.emit(text, col)
	if Net.is_online():
		_c_banner.rpc(text, col)

