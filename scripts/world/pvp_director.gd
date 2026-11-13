class_name PvpDirector
extends Node

# Authoritative PvP Match Director for up to 32 players & 6 teams.
# Supports Team Deathmatch, Gun Game, Search & Destroy, and Domination,
# offline (with bots) or online (Host authoritative, clients synced via NetGame).

const PvpBotScript := preload("res://scripts/enemies/pvp_bot.gd")
const PvpObjScript := preload("res://scripts/world/pvp_objective_zone.gd")
const FragGrenadeScript := preload("res://scripts/player/frag_grenade.gd")

const BOT_CALLSIGNS: Array[String] = [
	"VANGUARD", "SPECTRE", "TALON", "WARDEN", "CIPHER", "NOMAD", "APEX", "VIPER",
	"STRIKER", "PHOENIX", "REAPER", "SENTINEL", "VECTOR", "BLADE", "COBRA", "FROST",
	"FALCON", "GHOST", "TITAN", "HUNTER", "RAZOR", "SHADOW", "ONYX", "BOLT",
	"DRIFT", "ECHO", "HAVOC", "KRAKEN", "LYNX", "ORION", "PULSE", "STORM",
]

# Obstacle-free 16-slot spawn points mapped to BunkerArena's 6 sectors:
# 0 ALPHA (rail), 1 BRAVO (church), 2 CHARLIE (warehouse), 3 DELTA (hospital), 4 ECHO (plaza), 5 FOXTROT (cemetery)
const SECTOR_ZONES := {
	0: "rail",
	1: "church",
	2: "warehouse",
	3: "hospital",
	4: "plaza",
	5: "cemetery",
}

const SECTOR_SPAWN_POINTS := {
	0: [
		Vector3(-33.0, 0.0, 19.6), Vector3(-30.0, 0.0, 19.6), Vector3(-27.0, 0.0, 19.6), Vector3(-24.0, 0.0, 19.6),
		Vector3(-21.0, 0.0, 19.6), Vector3(-18.0, 0.0, 19.6), Vector3(-15.0, 0.0, 19.6), Vector3(-12.5, 0.0, 19.6),
		Vector3(-22.0, 0.0, 28.4), Vector3(-19.0, 0.0, 28.4), Vector3(-16.0, 0.0, 28.4), Vector3(-13.0, 0.0, 28.4),
		Vector3(-10.0, 0.0, 28.4), Vector3(-7.0, 0.0, 28.4), Vector3(-21.0, 0.0, 31.2), Vector3(-18.0, 0.0, 31.2),
	],
	1: [
		Vector3(-17.5, 0.0, -31.0), Vector3(-14.5, 0.0, -31.0), Vector3(-11.5, 0.0, -31.0), Vector3(-8.5, 0.0, -31.0),
		Vector3(-17.5, 0.0, -35.0), Vector3(-14.5, 0.0, -35.0), Vector3(-11.5, 0.0, -35.0), Vector3(-8.5, 0.0, -35.0),
		Vector3(10.5, 0.0, -31.0), Vector3(13.2, 0.0, -31.0), Vector3(15.9, 0.0, -31.0), Vector3(18.6, 0.0, -31.0),
		Vector3(11.2, 0.0, -35.5), Vector3(13.8, 0.0, -35.5), Vector3(16.4, 0.0, -35.5), Vector3(19.0, 0.0, -35.5),
	],
	2: [
		Vector3(34.0, 0.0, -9.2), Vector3(36.8, 0.0, -9.2), Vector3(39.6, 0.0, -9.2), Vector3(42.2, 0.0, -9.2),
		Vector3(24.0, 0.0, -2.8), Vector3(27.0, 0.0, -2.8), Vector3(30.0, 0.0, -2.8), Vector3(33.0, 0.0, -2.8),
		Vector3(36.0, 0.0, -2.8), Vector3(39.0, 0.0, -2.8), Vector3(42.0, 0.0, -2.8), Vector3(35.0, 0.0, 10.0),
		Vector3(38.0, 0.0, 10.0), Vector3(41.0, 0.0, 10.0), Vector3(43.8, 0.0, 10.0), Vector3(46.2, 0.0, 10.0),
	],
	3: [
		Vector3(-29.5, 0.0, -9.5), Vector3(-29.5, 0.0, -3.5), Vector3(-29.5, 0.0, 0.0), Vector3(-29.5, 0.0, 3.2),
		Vector3(-26.0, 0.0, -9.5), Vector3(-26.0, 0.0, -6.0), Vector3(-26.0, 0.0, -2.5), Vector3(-26.0, 0.0, 0.8),
		Vector3(-23.0, 0.0, -6.0), Vector3(-23.0, 0.0, -2.5), Vector3(-23.0, 0.0, 0.8), Vector3(-23.0, 0.0, 3.5),
		Vector3(-41.2, 0.0, -22.5), Vector3(-38.0, 0.0, -22.5), Vector3(-41.2, 0.0, -18.5), Vector3(-35.5, 0.0, -18.5),
	],
	4: [
		Vector3(-10.5, 0.0, 9.5), Vector3(-8.0, 0.0, 9.5), Vector3(-3.0, 0.0, 9.8), Vector3(0.0, 0.0, 10.8),
		Vector3(3.2, 0.0, 9.8), Vector3(6.5, 0.0, 9.5), Vector3(9.5, 0.0, 9.5), Vector3(12.5, 0.0, 9.5),
		Vector3(-7.0, 0.0, -12.2), Vector3(-3.5, 0.0, -12.2), Vector3(0.0, 0.0, -12.2), Vector3(3.5, 0.0, -12.2),
		Vector3(7.0, 0.0, -12.2), Vector3(-6.5, 0.0, -8.5), Vector3(5.5, 0.0, -8.5), Vector3(8.5, 0.0, -6.5),
	],
	5: [
		Vector3(26.5, 0.0, -39.0), Vector3(29.5, 0.0, -43.2), Vector3(32.5, 0.0, -43.2), Vector3(35.5, 0.0, -43.2),
		Vector3(38.2, 0.0, -43.2), Vector3(27.5, 0.0, -46.2), Vector3(33.0, 0.0, -46.2), Vector3(36.0, 0.0, -46.2),
		Vector3(30.5, 0.0, -49.2), Vector3(33.5, 0.0, -49.2), Vector3(28.5, 0.0, -28.0), Vector3(32.0, 0.0, -28.0),
		Vector3(36.0, 0.0, -28.0), Vector3(40.0, 0.0, -28.0), Vector3(48.5, 0.0, -36.0), Vector3(49.5, 0.0, -40.0),
	],
}

signal state_updated
signal kill_feed_added(entry: Dictionary)

var player: PlayerController
var arena: BunkerArena
var bots_container: Node3D
var net_game: Node

var team_count: int = 2
var max_per_team: int = 16
var team_scores: Array[int] = []
var score_limit: int = 75

# Combatant records keyed by "peer_<id>" or "bot_<idx>"
var roster: Dictionary = {}
var nodes_by_key: Dictionary = {} # key -> PlayerController / RemotePlayer / PvpBot
var bots_by_key: Dictionary = {}
var kill_feed: Array[Dictionary] = []

var match_time_left: float = 600.0
var match_ended: bool = false
var winning_team: int = -1
var win_reason: String = ""
var _started: bool = false

# S&D state
var snd_round: int = 1
var snd_win_target: int = 4
var snd_round_time: float = 105.0
var snd_attacker_team: int = 0 # Used in 2-team S&D; in 4T/6T any squad can plant
var snd_planted_site: String = ""
var snd_planted_team: int = -1
var snd_bomb_timer: float = 40.0
var snd_freeze_t: float = 0.0
var _bot_site_holds: Dictionary = {} # key -> progress

# Domination tick
var _dom_tick_t: float = 0.0

# Assist tracking & gun-fire alerts
var _recent_hits: Dictionary = {} # victim_key -> { attacker_key: time_sec }
var _minimap_pings: Array[Dictionary] = [] # { pos, time }

# Local objective hold UI hint
var local_hold_text: String = ""
var local_hold_prog: float = 0.0
var _local_hold_decay: float = 0.0
var _sync_t: float = 0.0
var _spawn_slots: Dictionary = {} # team_id -> Array[Vector3]


func setup(p_player: PlayerController, p_arena: BunkerArena, p_bots_parent: Node3D, p_net_game: Node) -> void:
	player = p_player
	arena = p_arena
	bots_container = p_bots_parent
	net_game = p_net_game
	add_to_group("pvp_director")

	team_count = GameState.pvp_team_count()
	max_per_team = GameState.pvp_max_per_team()
	team_scores.resize(team_count)
	for i in range(team_count):
		team_scores[i] = 0

	match GameState.pvp_mode:
		"tdm":
			score_limit = 75 if team_count == 2 else 50
			match_time_left = 600.0
		"gungame":
			score_limit = GameState.GUN_GAME_LADDER.size()
			match_time_left = 600.0
		"snd":
			snd_win_target = 4
			snd_round = 1
			snd_round_time = 105.0
			match_time_left = 105.0
		"dom":
			score_limit = 150
			match_time_left = 600.0

	_build_spawn_slots()
	_spawn_objectives()
	_build_initial_roster()
	_apply_local_loadout()

	# Offline matches start immediately; online matches start once NetGame fires on_net_started() or timeout
	if not Net.is_online():
		_started = true
		_spawn_all_combatants()


func on_net_started() -> void:
	if _started:
		return
	_started = true
	_spawn_all_combatants()
	state_updated.emit()
	if Net.is_online() and net_game:
		net_game.broadcast_pvp_event({"type": "tick", "scores": team_scores, "time": match_time_left, "snd_t": snd_round_time, "bomb_t": snd_bomb_timer})


func match_active() -> bool:
	return _started and not match_ended and snd_freeze_t <= 0.0


func _build_spawn_slots() -> void:
	var nav_map: RID = arena.get_world_3d().navigation_map if arena and arena.get_world_3d() else RID()
	var has_nav: bool = nav_map.is_valid() and not NavigationServer3D.map_get_regions(nav_map).is_empty()
	var spawn_dict: Dictionary = arena.get_pvp_spawn_points() if arena and arena.has_method("get_pvp_spawn_points") else SECTOR_SPAWN_POINTS
	for tid in range(GameState.PVP_TEAMS.size()):
		var raw_pts: Array = spawn_dict.get(tid, [Vector3.ZERO])
		var pts: Array[Vector3] = []
		for rp in raw_pts:
			var p: Vector3 = rp as Vector3
			if has_nav:
				var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, p)
				if snapped.distance_to(p) < 3.0 and absf(snapped.y) <= 0.35:
					p = Vector3(snapped.x, snapped.y, snapped.z)
			pts.append(p)
		_spawn_slots[tid] = pts
	_verify_spawn_slots_after_physics()


func _verify_spawn_slots_after_physics() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(arena):
		return
	var sec_zones: Dictionary = arena.get_pvp_sector_zones() if arena and arena.has_method("get_pvp_sector_zones") else SECTOR_ZONES
	for tid in _spawn_slots.keys():
		var zid: String = String(sec_zones.get(tid, ""))
		var arr: Array[Vector3] = _spawn_slots[tid]
		for i in range(arr.size()):
			arr[i] = arena.find_clear_ground_point(arr[i], zid, 0.42)


func _spawn_objectives() -> void:
	if arena and arena.has_method("get_pvp_objectives"):
		for obj in arena.get_pvp_objectives(GameState.pvp_mode):
			_add_objective(String(obj["id"]), String(obj["label"]), String(obj["kind"]), obj["pos"] as Vector3)
	elif GameState.pvp_mode == "snd":
		_add_objective("A", "PLAZA A", "bomb_site", Vector3(0.0, 0.0, 8.2))
		_add_objective("B", "CHURCH B", "bomb_site", Vector3(1.0, 0.0, -33.0))
	elif GameState.pvp_mode == "dom":
		_add_objective("A", "RAIL A", "dom_flag", Vector3(-24.5, 0.22, 25.2))
		_add_objective("B", "PLAZA B", "dom_flag", Vector3(0.0, 0.0, 8.2))
		_add_objective("C", "CHURCH C", "dom_flag", Vector3(1.0, 0.0, -33.0))


func _add_objective(oid: String, olabel: String, okind: String, pos: Vector3) -> void:
	var oz: PvpObjectiveZone = PvpObjScript.new()
	oz.setup(oid, olabel, okind, pos)
	arena.add_child(oz)


func _build_initial_roster() -> void:
	roster.clear()
	nodes_by_key.clear()
	bots_by_key.clear()

	var counts: Array[int] = []
	counts.resize(team_count)

	# 1. Human players first
	if Net.is_online():
		var ids: Array = Net.players.keys()
		ids.sort()
		for id_v in ids:
			var pid: int = int(id_v)
			var tid: int = clampi(Net.player_team(pid), 0, team_count - 1)
			if counts[tid] >= max_per_team:
				tid = _least_filled_team(counts)
			counts[tid] += 1
			var pkey: String = "peer_%d" % pid
			var pname: String = Net.player_name(pid)
			var node_ref: Node3D = player if pid == Net.my_id() else (net_game.avatars.get(pid) as Node3D if net_game else null)
			_register_combatant(pkey, pname, tid, false, pid, node_ref)
	else:
		var tid: int = clampi(GameState.pvp_selected_team, 0, team_count - 1)
		counts[tid] += 1
		var pkey: String = "peer_%d" % Net.my_id()
		_register_combatant(pkey, Net.my_name if Net.my_name != "" else "OPERATOR", tid, false, Net.my_id(), player)

	if is_instance_valid(player):
		var my_entry: Dictionary = roster.get("peer_%d" % Net.my_id(), {})
		player.team_id = int(my_entry.get("team", 0))

	# 2. Fill remaining slots with AI bots up to pvp_player_cap (capped at 32)
	var target_total: int = mini(GameState.MAX_PVP_PLAYERS, maxi(roster.size(), GameState.pvp_player_cap))
	if GameState.pvp_player_cap <= 0:
		target_total = roster.size()
	var bot_idx: int = 0
	var safety: int = 0
	while roster.size() < target_total and safety < 64:
		safety += 1
		var pick_t: int = _least_filled_team(counts)
		if pick_t < 0 or counts[pick_t] >= max_per_team:
			break
		counts[pick_t] += 1
		var bkey: String = "bot_%d" % bot_idx
		var bname: String = BOT_CALLSIGNS[bot_idx % BOT_CALLSIGNS.size()]
		if bot_idx >= BOT_CALLSIGNS.size():
			bname += "-%d" % (1 + bot_idx / BOT_CALLSIGNS.size())
		var wep: String = _bot_initial_weapon(bot_idx)
		var bot: PvpBot = PvpBotScript.new()
		bot.setup(bkey, bot_idx, bname, pick_t, wep)
		if GameState.pvp_mode != "gungame":
			var kit := _bot_loadout_kit(bot_idx)
			bot.set_loadout_kit(wep, String(kit["secondary"]), String(kit["lethal"]), String(kit["tactical"]), String(kit["perk"]))
		bots_container.add_child(bot)
		bots_by_key[bkey] = bot
		_register_combatant(bkey, bname, pick_t, true, -1, bot)
		bot_idx += 1


func _register_combatant(key: String, pname: String, tid: int, is_bot: bool, pid: int, node_ref: Node3D) -> void:
	roster[key] = {
		"key": key,
		"name": pname,
		"team": tid,
		"is_bot": is_bot,
		"peer_id": pid,
		"hp": 100.0,
		"max_hp": 100.0,
		"dead": false,
		"kills": 0,
		"deaths": 0,
		"assists": 0,
		"score": 0,
		"gg_tier": 0,
		"respawn_t": 0.0,
	}
	if node_ref:
		nodes_by_key[key] = node_ref
		if "team_id" in node_ref:
			node_ref.team_id = tid


func _least_filled_team(counts: Array[int]) -> int:
	var best_t: int = -1
	var best_c: int = 999
	for i in range(team_count):
		if counts[i] < max_per_team and counts[i] < best_c:
			best_c = counts[i]
			best_t = i
	return best_t


func _bot_initial_weapon(idx: int) -> String:
	if GameState.pvp_mode == "gungame":
		return GameState.GUN_GAME_LADDER[0]
	var pool: Array[String] = [
		"m4_carbine", "ak47", "scar_h", "famas_burst", "aug_a3", "honey_badger",
		"mk14_ebr", "fal_osw", "vss_vintorez", "mp5_sd", "vector_45", "p90_pdw",
		"ump45", "mp7_pdw", "benelli_m4", "aa12_auto", "spas12", "m249_saw",
		"pkm_heavy", "awm_magnum", "barrett_amr", "kar98k_marksman",
		"rifle", "smg", "shotgun", "lmg", "sniper", "volt",
	]
	return pool[idx % pool.size()]


func _bot_loadout_kit(idx: int) -> Dictionary:
	var secs := ["pistol", "glock18_auto", "deagle_50", "usp_tactical", "rpg7", "m79_thumper", "crossbow_fury"]
	var lets := ["frag", "semtex", "impact", "thermite"]
	var tacs := ["flashbang", "smoke", "concussion"]
	var prks := ["fast_hands", "flak_jacket", "tactical_mask"]
	return {
		"secondary": secs[idx % secs.size()],
		"lethal": lets[(idx / 2) % lets.size()],
		"tactical": tacs[(idx / 3) % tacs.size()],
		"perk": prks[idx % prks.size()],
	}


func _apply_local_loadout() -> void:
	if not is_instance_valid(player):
		return
	if GameState.pvp_mode == "gungame":
		var my_entry: Dictionary = roster.get("peer_%d" % Net.my_id(), {})
		var tier: int = clampi(int(my_entry.get("gg_tier", 0)), 0, GameState.GUN_GAME_LADDER.size() - 1)
		player.set_gungame_weapon(GameState.GUN_GAME_LADDER[tier])
	else:
		player.set_pvp_loadout("")


func _spawn_all_combatants() -> void:
	# Rebind avatars if any connected late
	if net_game:
		for pid_v in net_game.avatars.keys():
			var pid: int = int(pid_v)
			var k: String = "peer_%d" % pid
			if roster.has(k) and not nodes_by_key.has(k):
				nodes_by_key[k] = net_game.avatars[pid]

	var team_slot_cursor: Array[int] = []
	team_slot_cursor.resize(team_count)

	for key in roster.keys():
		var e: Dictionary = roster[key]
		e["dead"] = false
		e["hp"] = 100.0
		e["respawn_t"] = 0.0
		var tid: int = clampi(int(e["team"]), 0, team_count - 1)
		var slot: int = team_slot_cursor[tid]
		team_slot_cursor[tid] += 1
		var pt: Vector3 = _pick_slot_pos(tid, slot)
		var yaw: float = atan2(-pt.x, -pt.z) # Face inward toward central plaza
		_place_combatant(key, pt, yaw)
	state_updated.emit()


func _pick_slot_pos(tid: int, slot_idx: int) -> Vector3:
	var arr: Array = _spawn_slots.get(tid, [Vector3.ZERO])
	if arr.is_empty():
		return Vector3.ZERO
	return arr[slot_idx % arr.size()]


func _find_safe_spawn(tid: int) -> Vector3:
	var arr: Array = _spawn_slots.get(tid, [Vector3.ZERO])
	var best_pt: Vector3 = arr[0]
	var best_min_enemy_d: float = -1.0
	for pt in arr:
		var min_d: float = 9999.0
		for other_k in roster.keys():
			var oe: Dictionary = roster[other_k]
			if bool(oe["dead"]) or int(oe["team"]) == tid:
				continue
			var n: Node3D = nodes_by_key.get(other_k) as Node3D
			if is_instance_valid(n):
				var d: float = pt.distance_to(n.global_position)
				if d < min_d:
					min_d = d
		if min_d > best_min_enemy_d:
			best_min_enemy_d = min_d
			best_pt = pt
	return best_pt


func _place_combatant(key: String, pos: Vector3, yaw: float) -> void:
	var e: Dictionary = roster.get(key, {})
	if e.is_empty():
		return
	e["dead"] = false
	e["hp"] = float(e.get("max_hp", 100.0))
	e["respawn_t"] = 0.0
	var n: Node3D = nodes_by_key.get(key) as Node3D
	if n == player and is_instance_valid(player):
		player.pvp_respawn(pos, yaw)
		_apply_local_loadout()
	elif n is PvpBot:
		var bot := n as PvpBot
		if GameState.pvp_mode == "gungame":
			var tier: int = clampi(int(e.get("gg_tier", 0)), 0, GameState.GUN_GAME_LADDER.size() - 1)
			bot.set_weapon(GameState.GUN_GAME_LADDER[tier])
		bot.spawn_at(pos, yaw)


func _process(delta: float) -> void:
	if _local_hold_decay > 0.0:
		_local_hold_decay -= delta
		if _local_hold_decay <= 0.0:
			local_hold_text = ""
			local_hold_prog = 0.0

	# Expire old minimap fire pings
	var now: float = Time.get_ticks_msec() / 1000.0
	for i in range(_minimap_pings.size() - 1, -1, -1):
		if now - float(_minimap_pings[i]["time"]) > 1.8:
			_minimap_pings.remove_at(i)

	if not _started or match_ended:
		return
	if Net.is_online() and not Net.is_host():
		return

	if snd_freeze_t > 0.0:
		snd_freeze_t -= delta
		if snd_freeze_t <= 0.0:
			_start_next_snd_round()
		return

	# Match / round clock
	if GameState.pvp_mode == "snd":
		_process_snd(delta)
	else:
		match_time_left = maxf(0.0, match_time_left - delta)
		if match_time_left <= 0.0:
			var lead_t: int = _leading_team()
			_finish_match(lead_t, "TIME EXPIRED")
			return
		# Respawns
		for key in roster.keys():
			var e: Dictionary = roster[key]
			if bool(e["dead"]) and float(e["respawn_t"]) > 0.0:
				e["respawn_t"] = float(e["respawn_t"]) - delta
				if float(e["respawn_t"]) <= 0.0:
					var sp: Vector3 = _find_safe_spawn(int(e["team"]))
					var sy: float = atan2(-sp.x, -sp.z)
					_place_combatant(key, sp, sy)
					if Net.is_online() and net_game:
						net_game.broadcast_pvp_event({"type": "respawn", "key": key, "pos": sp, "yaw": sy})

	if GameState.pvp_mode == "dom":
		_process_domination(delta)

	_sync_t += delta
	if _sync_t >= 0.25:
		_sync_t = 0.0
		state_updated.emit()
		if Net.is_online() and net_game:
			net_game.broadcast_pvp_event({"type": "tick", "scores": team_scores, "time": match_time_left, "snd_t": snd_round_time, "bomb_t": snd_bomb_timer})


func _process_snd(delta: float) -> void:
	if snd_planted_site != "":
		snd_bomb_timer = maxf(0.0, snd_bomb_timer - delta)
		match_time_left = snd_bomb_timer
		for z in get_tree().get_nodes_in_group("pvp_objectives"):
			var oz := z as PvpObjectiveZone
			if oz and oz.zone_id == snd_planted_site:
				oz.bomb_timer = snd_bomb_timer
		if snd_bomb_timer <= 0.0:
			GameState.play_sfx("grenade_explode", 2.0, 0.72)
			_end_snd_round(snd_planted_team, "BOMB DETONATED AT SITE %s" % snd_planted_site)
			return
	else:
		snd_round_time = maxf(0.0, snd_round_time - delta)
		match_time_left = snd_round_time
		if snd_round_time <= 0.0:
			var win_t: int = (1 - snd_attacker_team) if team_count == 2 else _most_alive_team()
			_end_snd_round(win_t, "DEFENDERS HELD — TIME EXPIRED")
			return


func _process_domination(delta: float) -> void:
	var zones: Array = get_tree().get_nodes_in_group("pvp_objectives")
	for z in zones:
		var oz := z as PvpObjectiveZone
		if oz == null or oz.zone_kind != "dom_flag":
			continue
		var counts: Array[int] = []
		counts.resize(team_count)
		for key in roster.keys():
			var e: Dictionary = roster[key]
			if bool(e["dead"]):
				continue
			var n: Node3D = nodes_by_key.get(key) as Node3D
			if is_instance_valid(n) and n.global_position.distance_to(oz.global_position) <= PvpObjectiveZone.DOM_RADIUS:
				counts[int(e["team"])] += 1
		var teams_present: int = 0
		var top_t: int = -1
		var top_c: int = 0
		for t in range(team_count):
			if counts[t] > 0:
				teams_present += 1
				if counts[t] > top_c:
					top_c = counts[t]
					top_t = t
		oz.contested = teams_present > 1
		if teams_present == 1 and top_t >= 0 and oz.owner_team != top_t:
			if oz.capturing_team != top_t:
				oz.capturing_team = top_t
				oz.capture_progress = 0.0
			oz.capture_progress += delta * (0.28 + 0.08 * float(mini(3, top_c - 1)))
			if oz.capture_progress >= 1.0:
				oz.owner_team = top_t
				oz.capturing_team = -1
				oz.capture_progress = 1.0
				GameState.play_sfx("radio_beep", -2.0, 1.25)
				_announce_banner("%s CAPTURED FLAG %s" % [GameState.pvp_team_name(top_t), oz.zone_id], GameState.pvp_team_color(top_t))

	_dom_tick_t += delta
	if _dom_tick_t >= 2.0:
		_dom_tick_t -= 2.0
		for z in zones:
			var oz := z as PvpObjectiveZone
			if oz and oz.zone_kind == "dom_flag" and oz.owner_team >= 0 and oz.owner_team < team_count:
				team_scores[oz.owner_team] += 1
				if team_scores[oz.owner_team] >= score_limit:
					_finish_match(oz.owner_team, "DOMINATION SCORE LIMIT")
					return


# ---------------------------------------------------------------------------
# COMBAT, TRACERS & DAMAGE AUTHORITY
# ---------------------------------------------------------------------------
func node_to_key(n: Node) -> String:
	for k in nodes_by_key.keys():
		if nodes_by_key[k] == n:
			return String(k)
	if n is PvpBot:
		return (n as PvpBot).bot_key
	if n == player:
		return "peer_%d" % Net.my_id()
	if n is RemotePlayer:
		return "peer_%d" % (n as RemotePlayer).peer_id
	return ""


func report_gunfire_ping(pos: Vector3, suppressed: bool = false) -> void:
	if suppressed:
		return
	_minimap_pings.append({"pos": pos, "time": Time.get_ticks_msec() / 1000.0})


func get_minimap_pings() -> Array[Dictionary]:
	return _minimap_pings


func bot_attempt_fire(bot: PvpBot, target: Node3D, eye: Vector3, aim_dir: Vector3, wid: String) -> void:
	if not is_instance_valid(bot) or bot.is_dead:
		return
	var wcfg: Dictionary = GameState.WEAPONS.get(wid, {})
	var cam := get_viewport().get_camera_3d()
	var cam_pos: Vector3 = cam.global_position if cam else eye
	bot.trigger_muzzle_fx(wid, cam_pos)
	report_gunfire_ping(bot.global_position, bool(wcfg.get("suppressed", false)))

	if wid == "knife":
		if is_instance_valid(target) and eye.distance_to(target.global_position + Vector3(0, 1.3, 0)) <= 2.35:
			var tkey: String = node_to_key(target)
			if tkey != "":
				apply_pvp_hit(bot.bot_key, tkey, GameState.pvp_weapon_damage("knife"), false, "knife", bot.global_position)
		return

	var proj_kind := String(wcfg.get("projectile", ""))
	if proj_kind != "":
		var proj := LaunchedProjectile.new()
		var p_speed := float(wcfg.get("proj_speed", 42.0))
		var launch_dir := aim_dir
		if proj_kind == "gl_he":
			var h_dist := eye.distance_to(eye + aim_dir * 20.0)
			if is_instance_valid(target):
				h_dist = eye.distance_to(target.global_position + Vector3(0, 1.0, 0))
			launch_dir = (aim_dir + Vector3.UP * clampf(h_dist * 0.012, 0.04, 0.34)).normalized()
		proj.setup(
			proj_kind,
			eye + aim_dir * 0.85,
			launch_dir,
			p_speed,
			float(wcfg.get("damage", 160.0)),
			GameState.pvp_weapon_damage(wid),
			float(wcfg.get("blast_radius", 5.0)),
			bot,
			wid,
			bot.team_id
		)
		get_tree().current_scene.add_child(proj)
		return

	var pellets: int = mini(8, int(wcfg.get("pellets", 1)))
	var wcls := String(wcfg.get("class", "rifle"))
	var base_spread: float = 0.085 if wcls == "shotgun" else (0.042 if wcls == "smg" else (0.018 if wcls in ["sniper", "br"] else 0.028))
	var spread: float = base_spread * bot.get_accuracy_spread_mult()
	var max_rng: float = minf(90.0, float(wcfg.get("range", 65.0)))
	var space: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	var excl: Array[RID] = [bot.get_rid()]
	if "_hurtboxes" in bot:
		for hb_area in bot._hurtboxes:
			if is_instance_valid(hb_area):
				excl.append((hb_area as Area3D).get_rid())
	for c in get_tree().get_nodes_in_group("pvp_combatants"):
		if c != bot and is_instance_valid(c) and "team_id" in c and int(c.team_id) == bot.team_id:
			if c is CollisionObject3D:
				excl.append((c as CollisionObject3D).get_rid())
			if "_hurtboxes" in c:
				for hb_area in c._hurtboxes:
					if is_instance_valid(hb_area):
						excl.append((hb_area as Area3D).get_rid())
	var hit_end: Vector3 = eye + aim_dir * 55.0

	for p_i in range(pellets):
		var dir: Vector3 = (aim_dir + Vector3(randf_range(-spread, spread), randf_range(-spread * 0.7, spread * 0.7), randf_range(-spread, spread))).normalized()
		var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * max_rng, HitboxRig.BULLET_MASK, excl)
		q.collide_with_areas = true
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue
		hit_end = hit["position"]
		var hit_nrm: Vector3 = hit.get("normal", Vector3.UP)
		var col: Object = hit["collider"]
		if col is ExplosiveBarrel:
			(col as ExplosiveBarrel).on_shot(bot)
			continue
		var hb_info: Dictionary = HitboxRig.resolve_hit(col)
		var zone := String(hb_info.get("zone", ""))
		var owner_obj: Object = hb_info.get("owner", col)
		if zone != "" and owner_obj is Node3D:
			var hit_node := owner_obj as Node3D
			var tkey: String = node_to_key(hit_node)
			if tkey != "" and roster.has(tkey):
				var te: Dictionary = roster[tkey]
				if int(te["team"]) != bot.team_id and not bool(te["dead"]):
					var is_hs: bool = (zone == "head")
					var dmg_mult: float = 1.55 if is_hs else clampf(float(hb_info.get("dmg_mult", 1.0)), 0.55, 1.25)
					var dmg: float = GameState.pvp_weapon_damage(wid) * dmg_mult
					apply_pvp_hit(bot.bot_key, tkey, dmg, is_hs, wid, bot.global_position)
		elif hit_end.distance_to(cam_pos) <= 38.0:
			FX.surface_impact(get_parent(), hit_end, hit_nrm, String(hb_info.get("surface", "concrete")))

	if bot.global_position.distance_to(cam_pos) <= 48.0:
		_spawn_tracer(bot.muzzle_world_pos(), hit_end, bot.color.lerp(Color(1.0, 0.9, 0.65), 0.7))


func bot_throw_ordnance(bot: PvpBot, target_pos: Vector3, is_tactical: bool) -> void:
	if not is_instance_valid(bot) or bot.is_dead:
		return
	var origin: Vector3 = bot.global_position + Vector3(0.0, 1.48, 0.0)
	var flat: Vector3 = target_pos - origin
	var dist: float = maxf(2.0, Vector2(flat.x, flat.z).length())
	var dir_h: Vector3 = Vector3(flat.x, 0.0, flat.z).normalized() if dist > 0.1 else -bot.global_basis.z
	var vel: Vector3 = dir_h * clampf(dist * 0.72, 9.0, 17.5) + Vector3.UP * clampf(2.4 + dist * 0.14, 2.5, 6.0)
	if is_tactical:
		var tg := TacticalGrenade.new()
		tg.setup(bot.tactical_id, bot, bot.team_id)
		get_tree().current_scene.add_child(tg)
		tg.global_position = origin + dir_h * 0.55
		tg.linear_velocity = vel
	else:
		var fg: RigidBody3D = FragGrenadeScript.new()
		if fg.has_method("setup"):
			fg.setup(bot.lethal_id, bot)
		else:
			fg.thrower = bot
		get_tree().current_scene.add_child(fg)
		fg.global_position = origin + dir_h * 0.55
		fg.linear_velocity = vel
	GameState.play_sfx("grenade_pin", -8.0, randf_range(0.95, 1.08))


func _spawn_tracer(a: Vector3, b: Vector3, col: Color) -> void:
	var diff: Vector3 = b - a
	var length: float = diff.length()
	if length < 0.2:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = length
	mi.mesh = cm
	mi.material_override = MaterialLib.get_emissive(col, 2.2)
	get_tree().current_scene.add_child(mi)
	var dir: Vector3 = diff / length
	var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


func apply_pvp_hit(attacker_key: String, target_key: String, raw_dmg: float, is_hs: bool, weapon_id: String, attacker_pos: Vector3) -> void:
	if not _started or match_ended or snd_freeze_t > 0.0:
		return
	if Net.is_online() and not Net.is_host():
		return
	if not roster.has(target_key):
		return
	var target: Dictionary = roster[target_key]
	if bool(target["dead"]):
		return
	var attacker: Dictionary = roster.get(attacker_key, {})
	if not attacker.is_empty() and int(attacker["team"]) == int(target["team"]) and attacker_key != target_key:
		return # Friendly fire OFF

	var use_raw := raw_dmg > 0.0 and weapon_id in ["frag", "semtex", "thermite", "impact", "rpg7", "m79_thumper", "m32_rotary", "crossbow_fury", "skill", "knife"]
	var dmg: float = raw_dmg if use_raw else GameState.pvp_weapon_damage(weapon_id) * (1.6 if is_hs else 1.0)
	var is_explosive_w := weapon_id in ["frag", "semtex", "thermite", "impact", "rpg7", "m79_thumper", "m32_rotary", "crossbow_fury", "barrett_amr"]
	var my_key: String = "peer_%d" % Net.my_id()
	var t_node: Node3D = nodes_by_key.get(target_key) as Node3D
	if is_explosive_w:
		if target_key == my_key and is_instance_valid(player) and player.has_method("has_flak_jacket") and player.has_flak_jacket():
			dmg *= 0.55
		elif t_node is PvpBot and (t_node as PvpBot).bot_perk == "flak_jacket":
			dmg *= 0.55
	var new_hp: float = maxf(0.0, float(target["hp"]) - dmg)
	target["hp"] = new_hp
	if t_node is PvpBot and new_hp > 0.0:
		(t_node as PvpBot).notify_damaged_from(attacker_pos)

	# Assist ledger
	if attacker_key != "" and attacker_key != target_key:
		if not _recent_hits.has(target_key):
			_recent_hits[target_key] = {}
		(_recent_hits[target_key] as Dictionary)[attacker_key] = Time.get_ticks_msec() / 1000.0

	# Mirror damage onto local player or target peer
	if target_key == my_key and is_instance_valid(player):
		player.apply_pvp_damage(dmg, attacker_pos, new_hp <= 0.0)
	elif Net.is_online() and net_game and not bool(target["is_bot"]):
		net_game.broadcast_pvp_event({"type": "dmg", "target": target_key, "dmg": dmg, "hp": new_hp, "from": attacker_pos, "fatal": new_hp <= 0.0})

	if new_hp <= 0.0:
		_on_kill(attacker_key, target_key, weapon_id, is_hs)


func _on_kill(attacker_key: String, victim_key: String, weapon_id: String, is_hs: bool) -> void:
	var victim: Dictionary = roster[victim_key]
	victim["dead"] = true
	victim["hp"] = 0.0
	victim["deaths"] = int(victim["deaths"]) + 1
	victim["respawn_t"] = -1.0 if GameState.pvp_mode == "snd" else 3.0

	var v_node: Node3D = nodes_by_key.get(victim_key) as Node3D
	if v_node is PvpBot:
		(v_node as PvpBot).mark_dead()

	var killer: Dictionary = roster.get(attacker_key, {})
	var killer_name: String = String(killer.get("name", "WORLD"))
	var killer_team: int = int(killer.get("team", -1))
	var victim_name: String = String(victim["name"])
	var victim_team: int = int(victim["team"])
	var humiliated: bool = false

	if not killer.is_empty() and attacker_key != victim_key:
		killer["kills"] = int(killer["kills"]) + 1
		killer["score"] = int(killer["score"]) + (125 if is_hs else 100)
		if attacker_key == "peer_%d" % Net.my_id():
			GameState.pvp_kills_life += 1
			GameState.play_sfx("kill_confirm", -2.0, 1.05)

		# Assists (other teammates who hit victim within 6s)
		var now: float = Time.get_ticks_msec() / 1000.0
		var hit_map: Dictionary = _recent_hits.get(victim_key, {})
		for ak in hit_map.keys():
			if ak != attacker_key and float(hit_map[ak]) >= now - 6.0 and roster.has(ak):
				var ae: Dictionary = roster[ak]
				if int(ae["team"]) == killer_team:
					ae["assists"] = int(ae["assists"]) + 1
					ae["score"] = int(ae["score"]) + 50
		_recent_hits.erase(victim_key)

		# Mode scoring
		match GameState.pvp_mode:
			"tdm":
				if killer_team >= 0 and killer_team < team_count:
					team_scores[killer_team] += 1
					if team_scores[killer_team] >= score_limit:
						_push_kill_feed(killer_name, killer_team, victim_name, victim_team, weapon_id, is_hs, false)
						_finish_match(killer_team, "SCORE LIMIT REACHED")
						return
			"gungame":
				var cur_tier: int = int(killer["gg_tier"])
				var final_tier: int = GameState.GUN_GAME_LADDER.size() - 1
				if cur_tier >= final_tier and weapon_id == "knife":
					_push_kill_feed(killer_name, killer_team, victim_name, victim_team, weapon_id, is_hs, false)
					_finish_match(killer_team, "GUN GAME VICTORY — %s" % killer_name)
					return
				if cur_tier < final_tier:
					var next_t: int = cur_tier + 1
					killer["gg_tier"] = next_t
					if killer_team >= 0 and killer_team < team_count:
						team_scores[killer_team] = maxi(team_scores[killer_team], next_t + 1)
					var next_wep: String = GameState.GUN_GAME_LADDER[next_t]
					var kn: Node3D = nodes_by_key.get(attacker_key) as Node3D
					if kn == player and is_instance_valid(player):
						player.set_gungame_weapon(next_wep)
						GameState.play_sfx("level_up", -2.0, 1.15)
					elif kn is PvpBot:
						(kn as PvpBot).set_weapon(next_wep)
				if weapon_id == "knife" and int(victim["gg_tier"]) > 0:
					var vt: int = int(victim["gg_tier"]) - 1
					victim["gg_tier"] = vt
					humiliated = true
					var v_wep: String = GameState.GUN_GAME_LADDER[vt]
					if v_node == player and is_instance_valid(player):
						player.set_gungame_weapon(v_wep)
					elif v_node is PvpBot:
						(v_node as PvpBot).set_weapon(v_wep)
			"snd":
				_check_snd_elimination()

		var killer_node: Node3D = nodes_by_key.get(attacker_key) as Node3D
		if killer_node == player and is_instance_valid(player) and player.has_method("on_scavenger_resupply"):
			player.on_scavenger_resupply()

	var kf := _push_kill_feed(killer_name, killer_team, victim_name, victim_team, weapon_id, is_hs, humiliated)
	if Net.is_online() and net_game:
		net_game.broadcast_pvp_event({"type": "kill", "feed": kf, "scores": team_scores, "victim": victim_key, "killer": attacker_key, "k_tier": int(killer.get("gg_tier", 0)), "v_tier": int(victim.get("gg_tier", 0))})
	state_updated.emit()


func _push_kill_feed(k_name: String, k_team: int, v_name: String, v_team: int, wep: String, hs: bool, humil: bool) -> Dictionary:
	var entry := {
		"killer": k_name,
		"k_team": k_team,
		"victim": v_name,
		"v_team": v_team,
		"weapon": wep.to_upper(),
		"hs": hs,
		"humil": humil,
		"time": Time.get_ticks_msec() / 1000.0,
	}
	kill_feed.push_front(entry)
	if kill_feed.size() > 6:
		kill_feed.resize(6)
	kill_feed_added.emit(entry)
	return entry


# ---------------------------------------------------------------------------
# SEARCH & DESTROY LOGIC
# ---------------------------------------------------------------------------
func can_team_plant(site_id: String, tid: int) -> bool:
	if GameState.pvp_mode != "snd" or not _started or match_ended or snd_freeze_t > 0.0:
		return false
	if snd_planted_site != "":
		return false
	if team_count == 2:
		return tid == snd_attacker_team
	return true # 4T/6T Multi-Squad Sabotage: any squad can plant


func can_team_defuse(site_id: String, tid: int) -> bool:
	if GameState.pvp_mode != "snd" or not _started or match_ended or snd_freeze_t > 0.0:
		return false
	if snd_planted_site != site_id:
		return false
	return tid != snd_planted_team


func set_local_hold_hint(txt: String, prog: float) -> void:
	local_hold_text = txt
	local_hold_prog = prog
	_local_hold_decay = 0.25


func advance_bot_site_hold(site_id: String, bot_key: String, bot_team: int, action: String, delta: float) -> void:
	var req: float = PvpObjectiveZone.DEFUSE_TIME if action == "defuse" else PvpObjectiveZone.PLANT_TIME
	var cur: float = float(_bot_site_holds.get(bot_key, 0.0)) + delta / req
	_bot_site_holds[bot_key] = cur
	if cur >= 1.0:
		_bot_site_holds.erase(bot_key)
		handle_interact(bot_key, site_id, action)


func handle_interact(actor_key: String, site_id: String, action: String) -> void:
	if GameState.pvp_mode != "snd" or not _started or match_ended or snd_freeze_t > 0.0:
		return
	var e: Dictionary = roster.get(actor_key, {})
	if e.is_empty() or bool(e["dead"]):
		return
	var tid: int = int(e["team"])
	if action == "plant" and can_team_plant(site_id, tid):
		snd_planted_site = site_id
		snd_planted_team = tid
		snd_bomb_timer = 40.0
		match_time_left = 40.0
		e["score"] = int(e["score"]) + 150
		for z in get_tree().get_nodes_in_group("pvp_objectives"):
			var oz := z as PvpObjectiveZone
			if oz and oz.zone_id == site_id:
				oz.is_planted = true
				oz.planted_team = tid
				oz.bomb_timer = 40.0
		GameState.play_sfx("exfil_siren", -4.0, 1.1)
		_announce_banner("BOMB PLANTED AT SITE %s BY %s!" % [site_id, GameState.pvp_team_name(tid)], GameState.pvp_team_color(tid))
		_check_snd_elimination()
	elif action == "defuse" and can_team_defuse(site_id, tid):
		e["score"] = int(e["score"]) + 200
		for z in get_tree().get_nodes_in_group("pvp_objectives"):
			var oz := z as PvpObjectiveZone
			if oz and oz.zone_id == site_id:
				oz.is_defused = true
				oz.is_planted = false
		GameState.play_sfx("power_on", -2.0, 1.1)
		_end_snd_round(tid, "BOMB DEFUSED BY %s!" % GameState.pvp_team_name(tid))


func _check_snd_elimination() -> void:
	var alive_per_team: Array[int] = []
	alive_per_team.resize(team_count)
	for key in roster.keys():
		var e: Dictionary = roster[key]
		if not bool(e["dead"]):
			alive_per_team[int(e["team"])] += 1

	var alive_teams: Array[int] = []
	for t in range(team_count):
		if alive_per_team[t] > 0:
			alive_teams.append(t)

	if snd_planted_site != "":
		# If every team EXCEPT the planting team is dead -> planters win round!
		var rival_alive: bool = false
		for t in alive_teams:
			if t != snd_planted_team:
				rival_alive = true
		if not rival_alive:
			_end_snd_round(snd_planted_team, "DEFENDERS ELIMINATED — BOMB SECURED")
	else:
		if alive_teams.size() == 1:
			_end_snd_round(alive_teams[0], "ENEMY SQUADS ELIMINATED")
		elif alive_teams.is_empty():
			_end_snd_round(0, "ROUND DRAW")


func _end_snd_round(win_team: int, reason: String) -> void:
	if snd_freeze_t > 0.0 or match_ended:
		return
	if win_team >= 0 and win_team < team_count:
		team_scores[win_team] += 1
		if team_scores[win_team] >= snd_win_target:
			_finish_match(win_team, reason)
			return
	_announce_banner("ROUND %d: %s WON — %s" % [snd_round, GameState.pvp_team_name(win_team), reason], GameState.pvp_team_color(win_team))
	snd_freeze_t = 3.5
	state_updated.emit()


func _start_next_snd_round() -> void:
	snd_round += 1
	snd_planted_site = ""
	snd_planted_team = -1
	snd_bomb_timer = 40.0
	snd_round_time = 105.0
	match_time_left = 105.0
	_bot_site_holds.clear()
	if team_count == 2:
		snd_attacker_team = 0 if ((snd_round - 1) / 2) % 2 == 0 else 1
	for z in get_tree().get_nodes_in_group("pvp_objectives"):
		if z.has_method("reset_site"):
			z.reset_site()
	for hb in get_tree().get_nodes_in_group("hazard_barrels"):
		if is_instance_valid(hb) and hb.has_method("try_respawn"):
			hb.try_respawn(999)
	_spawn_all_combatants()
	var role_note: String = ("ATTACKERS: %s" % GameState.pvp_team_name(snd_attacker_team)) if team_count == 2 else "MULTI-SQUAD SABOTAGE"
	_announce_banner("ROUND %d  ·  %s" % [snd_round, role_note], Color(0.95, 0.85, 0.35))


func _most_alive_team() -> int:
	var alive: Array[int] = []
	alive.resize(team_count)
	for key in roster.keys():
		var e: Dictionary = roster[key]
		if not bool(e["dead"]):
			alive[int(e["team"])] += 1
	var best_t: int = 0
	var best_c: int = -1
	for t in range(team_count):
		if alive[t] > best_c:
			best_c = alive[t]
			best_t = t
	return best_t


func _leading_team() -> int:
	var best_t: int = 0
	var best_s: int = -1
	for t in range(team_count):
		if team_scores[t] > best_s:
			best_s = team_scores[t]
			best_t = t
	return best_t


func _announce_banner(txt: String, col: Color) -> void:
	if is_instance_valid(player):
		player.status_banner_requested.emit(txt, col)


func _finish_match(w_team: int, reason: String) -> void:
	if match_ended:
		return
	match_ended = true
	winning_team = w_team
	win_reason = reason
	state_updated.emit()

	var my_key: String = "peer_%d" % Net.my_id()
	var my_e: Dictionary = roster.get(my_key, {})
	var my_team: int = int(my_e.get("team", Net.my_team))
	var won: bool = (my_team == winning_team)
	var xp_gain: int = 120 + (180 if won else 0) + int(my_e.get("kills", 0)) * 25 + int(int(my_e.get("score", 0)) * 0.2)
	GameState.career_xp += xp_gain
	if won:
		GameState.pvp_wins += 1
	GameState.write_save()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Net.is_online() and Net.is_host() and net_game:
		net_game.broadcast_pvp_event({"type": "match_end", "win_team": winning_team, "reason": reason, "scores": team_scores})
	var hud := get_tree().current_scene.get_node_or_null("GameHUD")
	if hud and hud.has_method("show_pvp_match_end"):
		hud.show_pvp_match_end(winning_team, reason, xp_gain, roster, team_scores)


# ---------------------------------------------------------------------------
# NETWORK STATE SYNC (clients receive host snapshots & events)
# ---------------------------------------------------------------------------
func export_net_state() -> Dictionary:
	return {"scores": team_scores, "time": match_time_left, "snd_round": snd_round, "planted_site": snd_planted_site, "planted_team": snd_planted_team, "bomb_t": snd_bomb_timer}


func import_net_state(st: Dictionary) -> void:
	var sc: Array = st.get("scores", [])
	for i in range(mini(sc.size(), team_scores.size())):
		team_scores[i] = int(sc[i])
	match_time_left = float(st.get("time", match_time_left))
	snd_round = int(st.get("snd_round", snd_round))
	snd_planted_site = String(st.get("planted_site", ""))
	snd_planted_team = int(st.get("planted_team", -1))
	snd_bomb_timer = float(st.get("bomb_t", 40.0))
	state_updated.emit()


func handle_net_event(ev: Dictionary) -> void:
	var t: String = String(ev.get("type", ""))
	match t:
		"tick":
			var sc: Array = ev.get("scores", [])
			for i in range(mini(sc.size(), team_scores.size())):
				team_scores[i] = int(sc[i])
			match_time_left = float(ev.get("time", match_time_left))
			snd_round_time = float(ev.get("snd_t", snd_round_time))
			snd_bomb_timer = float(ev.get("bomb_t", snd_bomb_timer))
			state_updated.emit()
		"dmg":
			var target_k: String = String(ev.get("target", ""))
			if target_k == "peer_%d" % Net.my_id() and is_instance_valid(player):
				player.apply_pvp_damage(float(ev.get("dmg", 15.0)), Vector3(ev.get("from", Vector3.ZERO)), bool(ev.get("fatal", false)))
		"respawn":
			if String(ev.get("key", "")) == "peer_%d" % Net.my_id():
				_place_local_player_from_net(Vector3(ev.get("pos", Vector3.ZERO)), float(ev.get("yaw", 0.0)))
		"kill":
			var sc2: Array = ev.get("scores", [])
			for i in range(mini(sc2.size(), team_scores.size())):
				team_scores[i] = int(sc2[i])
			var kf: Dictionary = ev.get("feed", {})
			if not kf.is_empty():
				kill_feed.push_front(kf)
				if kill_feed.size() > 6:
					kill_feed.resize(6)
				kill_feed_added.emit(kf)
			var my_k: String = "peer_%d" % Net.my_id()
			if GameState.pvp_mode == "gungame":
				if String(ev.get("killer", "")) == my_k and is_instance_valid(player):
					var kt: int = clampi(int(ev.get("k_tier", 0)), 0, GameState.GUN_GAME_LADDER.size() - 1)
					player.set_gungame_weapon(GameState.GUN_GAME_LADDER[kt])
				elif String(ev.get("victim", "")) == my_k and is_instance_valid(player):
					var vt: int = clampi(int(ev.get("v_tier", 0)), 0, GameState.GUN_GAME_LADDER.size() - 1)
					player.set_gungame_weapon(GameState.GUN_GAME_LADDER[vt])
			state_updated.emit()
		"match_end":
			var sc3: Array = ev.get("scores", [])
			for i in range(mini(sc3.size(), team_scores.size())):
				team_scores[i] = int(sc3[i])
			_finish_match(int(ev.get("win_team", 0)), String(ev.get("reason", "")))


func _place_local_player_from_net(pos: Vector3, yaw: float) -> void:
	if is_instance_valid(player):
		player.pvp_respawn(pos, yaw)
		_apply_local_loadout()
