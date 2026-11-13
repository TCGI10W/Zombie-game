extends Node
# Co-op session manager (autoload "Net").
#
# Transport: Steam lobbies + SteamMultiplayerPeer (GodotSteam). Steam routes
# the traffic through Valve's relay network (Steam Datagram Relay): no port
# forwarding, NAT-proof, IPs stay hidden, and long-distance links ride Valve's
# backbone instead of the public internet. A direct-IP (ENet) mode exists for
# LAN play and local testing.
#
# The host runs the simulation (zombies, rounds, drops); each player owns
# their own movement and hit detection so their game feels instant even on
# a bad connection. Gameplay sync lives in scripts/net/net_game.gd.

signal lobby_changed()
signal status_changed(text: String)
signal session_ended(reason: String)

enum Mode {OFFLINE, HOST, CLIENT}

const MAX_PLAYERS := 8
const MAX_PVP_PLAYERS := 32
const PORT := 24680
const STEAM_APP_ID := 480 # Valve's public test app ("Spacewar"); replace with your own App ID
const NET_VERSION := "dp-coop-8"
const COLORS := [Color(0.35, 0.8, 1.0), Color(1.0, 0.75, 0.25), Color(0.55, 1.0, 0.45), Color(1.0, 0.45, 0.75),
	Color(0.75, 0.55, 1.0), Color(1.0, 0.45, 0.3), Color(0.3, 1.0, 0.85), Color(0.95, 0.95, 0.95)]

var mode: int = Mode.OFFLINE
var transport: String = ""
var steam: Object = null
var steam_ok: bool = false
var steam_id: int = 0
var my_name: String = "SURVIVOR"
var lobby_id: int = 0
var players: Dictionary = {} # peer_id -> {"name", "char", "color", "team"}
var my_team: int = 0
var in_game: bool = false
var status_text: String = ""
var _pending_lobby: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var user := OS.get_environment("USERNAME")
	if user == "":
		user = OS.get_environment("USER")
	if user != "":
		my_name = user.to_upper().substr(0, 20)
	_init_steam()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func(): _fail("COULD NOT CONNECT TO THE HOST"))
	multiplayer.server_disconnected.connect(func(): _end("THE HOST LEFT THE GAME"))
	_parse_command_line()


func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		return
	steam = Engine.get_singleton("Steam")
	var r: Dictionary = steam.steamInitEx(STEAM_APP_ID, true)
	steam_ok = int(r.get("status", 1)) == 0
	if not steam_ok:
		print("Steam unavailable: ", r.get("verbal", ""))
		return
	steam_id = steam.getSteamID()
	my_name = String(steam.getPersonaName()).to_upper()
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.join_requested.connect(func(lid: int, _friend: int): join_steam_lobby(lid))


func _parse_command_line() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in range(args.size()):
		var a: String = args[i]
		if a == "+connect_lobby" and i + 1 < args.size():
			_pending_lobby = int(args[i + 1])
		elif a.begins_with("--net-name="):
			my_name = a.get_slice("=", 1).to_upper()
	if steam_ok and _pending_lobby == 0:
		var launch: String = steam.getLaunchCommandLine()
		var idx := launch.find("+connect_lobby")
		if idx >= 0:
			_pending_lobby = int(launch.substr(idx + 15).strip_edges().get_slice(" ", 0))
	if _pending_lobby != 0:
		join_steam_lobby.call_deferred(_pending_lobby)


# ---------------------------------------------------------------------------
# QUERIES
# ---------------------------------------------------------------------------
func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode != Mode.CLIENT # offline games are their own authority


func is_client() -> bool:
	return mode == Mode.CLIENT


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func player_count() -> int:
	return maxi(1, players.size()) if is_online() else 1


func player_name(peer_id: int) -> String:
	return String(players.get(peer_id, {}).get("name", "PLAYER %d" % peer_id))


func player_color(peer_id: int) -> Color:
	if GameState.is_pvp() and players.has(peer_id):
		return GameState.pvp_team_color(int((players[peer_id] as Dictionary).get("team", 0)))
	return COLORS[int(players.get(peer_id, {}).get("color", 0)) % COLORS.size()]


func active_max_players() -> int:
	return MAX_PVP_PLAYERS if GameState.is_pvp() else MAX_PLAYERS


func player_team(peer_id: int) -> int:
	return int((players.get(peer_id, {}) as Dictionary).get("team", GameState.pvp_selected_team))


func count_on_team(team_id: int) -> int:
	var n := 0
	for p in players.values():
		if int((p as Dictionary).get("team", 0)) == team_id:
			n += 1
	return n


func pick_open_team(preferred: int = 0) -> int:
	var t_count: int = GameState.pvp_team_count()
	var cap: int = GameState.pvp_max_per_team()
	var pref: int = clampi(preferred, 0, t_count - 1)
	if count_on_team(pref) < cap:
		return pref
	var best_t := pref
	var best_n := 9999
	for t in range(t_count):
		var c := count_on_team(t)
		if c < cap and c < best_n:
			best_n = c
			best_t = t
	return best_t


# Estimated host clock (seconds), kept by NetGame from snapshot timestamps
var clock_offset: float = 0.0
var clock_synced: bool = false


func local_time() -> float:
	return Time.get_ticks_msec() / 1000.0


func host_time() -> float:
	return local_time() + clock_offset


# ---------------------------------------------------------------------------
# HOSTING / JOINING
# ---------------------------------------------------------------------------
func host_steam() -> void:
	if not steam_ok:
		_fail("STEAM IS NOT RUNNING — START STEAM AND RESTART THE GAME")
		return
	leave()
	_set_status("CREATING STEAM LOBBY...")
	steam.createLobby(ClassDB.class_get_integer_constant("Steam", "LOBBY_TYPE_FRIENDS_ONLY"), MAX_PVP_PLAYERS)


func join_steam_lobby(lid: int) -> void:
	if not steam_ok or lid == 0:
		return
	if in_game:
		return
	leave()
	_set_status("JOINING STEAM LOBBY...")
	steam.joinLobby(lid)


func invite_friends() -> void:
	if steam_ok and lobby_id != 0:
		steam.activateGameOverlayInviteDialog(lobby_id)


func host_direct(port: int = PORT) -> void:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PVP_PLAYERS - 1)
	if err != OK:
		_fail("COULD NOT OPEN PORT %d (ERROR %d)" % [port, err])
		return
	_start_peer(peer, Mode.HOST, "enet")
	_set_status("HOSTING ON PORT %d — FRIENDS JOIN WITH YOUR IP" % port)


func join_direct(address: String, port: int = PORT) -> void:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		_fail("BAD ADDRESS")
		return
	_start_peer(peer, Mode.CLIENT, "enet")
	_set_status("CONNECTING TO %s..." % address)


func _on_lobby_created(result: int, lid: int) -> void:
	if result != 1:
		_fail("STEAM COULD NOT CREATE A LOBBY (CODE %d)" % result)
		return
	lobby_id = lid
	steam.setLobbyJoinable(lid, true)
	steam.setLobbyData(lid, "name", "%s'S SQUAD" % my_name)
	steam.setLobbyData(lid, "version", NET_VERSION)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer.has_method("set_server_relay"):
		peer.call("set_server_relay", true) # host forwards teammate-to-teammate traffic
	var err: int = peer.call("host_with_lobby", lid)
	if err != OK:
		_fail("STEAM NETWORKING ERROR %d" % err)
		return
	_start_peer(peer, Mode.HOST, "steam")
	steam.setRichPresence("steam_display", "#Status")
	steam.setRichPresence("connect", "+connect_lobby %d" % lid)
	_set_status("LOBBY READY — INVITE FRIENDS THROUGH STEAM")


func _on_lobby_joined(lid: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		_fail("COULD NOT JOIN THAT LOBBY (FULL, CLOSED OR GONE)")
		return
	lobby_id = lid
	if steam.getLobbyOwner(lid) == steam_id:
		return # our own lobby
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer.has_method("set_server_relay"):
		peer.call("set_server_relay", true) # host forwards teammate-to-teammate traffic
	var err: int = peer.call("connect_to_lobby", lid)
	if err != OK:
		_fail("STEAM NETWORKING ERROR %d" % err)
		return
	_start_peer(peer, Mode.CLIENT, "steam")
	_set_status("CONNECTING THROUGH STEAM RELAY...")


func _start_peer(peer: MultiplayerPeer, new_mode: int, kind: String) -> void:
	multiplayer.multiplayer_peer = peer
	mode = new_mode
	transport = kind
	players.clear()
	my_team = clampi(GameState.pvp_selected_team, 0, GameState.pvp_team_count() - 1)
	if mode == Mode.HOST:
		players[1] = {"name": my_name, "char": GameState.selected_character, "color": 0, "team": my_team}
	lobby_changed.emit()


func leave() -> void:
	if mode == Mode.OFFLINE and lobby_id == 0:
		return
	if steam_ok and lobby_id != 0:
		steam.leaveLobby(lobby_id)
		steam.setRichPresence("connect", "")
	lobby_id = 0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	transport = ""
	players.clear()
	in_game = false
	clock_offset = 0.0
	clock_synced = false
	lobby_changed.emit()


func _fail(text: String) -> void:
	leave()
	_set_status(text)


# Back to the menu with a reason (host left, kicked, ...)
func _end(reason: String) -> void:
	var was_in_game := in_game
	leave()
	_set_status(reason)
	session_ended.emit(reason)
	if was_in_game:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _set_status(text: String) -> void:
	status_text = text
	status_changed.emit(text)


# ---------------------------------------------------------------------------
# LOBBY PROTOCOL
# ---------------------------------------------------------------------------
func _on_peer_connected(_id: int) -> void:
	pass # wait for the newcomer's hello


func _on_connected_to_server() -> void:
	_set_status("CONNECTED — WAITING FOR THE HOST")
	_s_hello.rpc_id(1, my_name, GameState.selected_character, NET_VERSION)


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	if players.erase(id):
		_c_players.rpc(players)
		lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _s_hello(pname: String, char_id: String, version: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != NET_VERSION:
		_c_kick.rpc_id(id, "VERSION MISMATCH — EVERYONE NEEDS THE SAME BUILD")
		return
	if players.size() >= active_max_players():
		_c_kick.rpc_id(id, "LOBBY IS FULL")
		return
	var used := []
	for p in players.values():
		used.append(int(p["color"]))
	var col := 0
	while col in used:
		col += 1
	var clean := pname.strip_edges().substr(0, 20)
	if clean == "":
		clean = "SURVIVOR"
	var team_id: int = pick_open_team(-1)
	players[id] = {"name": clean, "char": char_id, "color": col, "team": team_id}
	_c_players.rpc(players)
	_c_match_config.rpc_id(id, _build_match_config())
	lobby_changed.emit()
	if in_game:
		# Join in progress: load straight into the running game
		_c_start_game.rpc_id(id, GameState.active_diff_index(), GameState.run_id, false, true, GameState.game_mode, _build_match_config())


@rpc("authority", "call_remote", "reliable")
func _c_players(list: Dictionary) -> void:
	players = list
	var me: int = my_id()
	if players.has(me) and players[me] is Dictionary:
		my_team = int((players[me] as Dictionary).get("team", my_team))
	lobby_changed.emit()
	_set_status("IN LOBBY — WAITING FOR THE HOST TO START")


@rpc("authority", "call_remote", "reliable")
func _c_kick(reason: String) -> void:
	_end(reason)


# Operator changes in the lobby
func set_character(char_id: String) -> void:
	if not is_online():
		return
	if is_host():
		_s_set_char(char_id)
	else:
		_s_set_char.rpc_id(1, char_id)


@rpc("any_peer", "call_remote", "reliable")
func _s_set_char(char_id: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if players.has(id):
		players[id]["char"] = char_id
		_c_players.rpc(players)
		lobby_changed.emit()


func set_team(tid: int) -> void:
	var clamped: int = clampi(tid, 0, maxi(0, GameState.pvp_team_count() - 1))
	my_team = clamped
	GameState.pvp_selected_team = clamped
	if not is_online():
		return
	if is_host():
		_s_set_team(clamped)
	else:
		_s_set_team.rpc_id(1, clamped)


@rpc("any_peer", "call_remote", "reliable")
func _s_set_team(tid: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if not players.has(id):
		return
	var target: int = clampi(tid, 0, maxi(0, GameState.pvp_team_count() - 1))
	var current: int = int((players[id] as Dictionary).get("team", 0))
	if target != current and count_on_team(target) >= GameState.pvp_max_per_team():
		target = pick_open_team(target)
	players[id]["team"] = target
	if id == 1:
		my_team = target
		GameState.pvp_selected_team = target
	_c_players.rpc(players)
	lobby_changed.emit()


func _build_match_config() -> Dictionary:
	return {
		"game_mode": GameState.game_mode,
		"pvp_mode": GameState.pvp_mode,
		"pvp_map": GameState.pvp_map,
		"active_pvp_map": GameState.active_pvp_map,
		"team_preset": GameState.team_preset,
		"pvp_player_cap": GameState.pvp_player_cap,
	}


func _apply_match_config(cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	var gm: String = String(cfg.get("game_mode", GameState.game_mode))
	if gm in ["casual", "infinite", "horror", "overdrive", "pvp"]:
		GameState.game_mode = gm
	var pm: String = String(cfg.get("pvp_mode", GameState.pvp_mode))
	if GameState.PVP_MODES.has(pm):
		GameState.pvp_mode = pm
	var pmap: String = String(cfg.get("pvp_map", GameState.pvp_map))
	if pmap == "random" or GameState.PVP_MAPS.has(pmap):
		GameState.pvp_map = pmap
	var amap: String = String(cfg.get("active_pvp_map", GameState.active_pvp_map))
	if GameState.PVP_MAPS.has(amap):
		GameState.active_pvp_map = amap
	var tp: int = int(cfg.get("team_preset", GameState.team_preset))
	if GameState.PVP_TEAM_PRESETS.has(tp):
		GameState.team_preset = tp
	var cap: int = int(cfg.get("pvp_player_cap", GameState.pvp_player_cap))
	if cap in [0, 16, 24, 32]:
		GameState.pvp_player_cap = cap


func sync_match_config() -> void:
	if not is_host():
		return
	var changed: bool = false
	var t_count: int = GameState.pvp_team_count()
	var t_max: int = GameState.pvp_max_per_team()
	var counts: Array[int] = []
	counts.resize(t_count)
	for pid_v in players.keys():
		var pid: int = int(pid_v)
		var entry: Dictionary = players[pid]
		var t: int = clampi(int(entry.get("team", 0)), 0, maxi(0, t_count - 1))
		if counts[t] >= t_max:
			t = pick_open_team(-1)
		if int(entry.get("team", -1)) != t:
			entry["team"] = t
			if pid == 1:
				my_team = t
				GameState.pvp_selected_team = t
			changed = true
		counts[t] += 1
	if changed:
		_c_players.rpc(players)
	_c_match_config.rpc(_build_match_config())
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _c_match_config(cfg: Dictionary) -> void:
	_apply_match_config(cfg)
	lobby_changed.emit()


func start_game(resume: bool = false) -> void:
	if mode != Mode.HOST:
		return
	var is_pvp_mode: bool = GameState.is_pvp()
	if is_pvp_mode:
		resume = false
		GameState.resolve_pvp_map()
	var rid := int(GameState.load_world().get("run_id", 0)) if resume else GameState.new_run_id()
	if resume:
		var w := GameState.load_world()
		var wm := String(w.get("mode", GameState.game_mode))
		GameState.game_mode = wm if wm in ["casual", "infinite", "horror", "overdrive", "pvp"] else "casual"
		var wd := int(w.get("difficulty", GameState.active_diff_index()))
		if GameState.is_overdrive():
			GameState.overdrive_difficulty = clampi(wd, 0, GameState.OVERDRIVE_DIFFICULTIES.size() - 1)
		else:
			GameState.difficulty = clampi(wd, 0, GameState.DIFFICULTIES.size() - 1)
	_c_start_game.rpc(GameState.active_diff_index(), rid, resume, false, GameState.game_mode, _build_match_config())


@rpc("authority", "call_local", "reliable")
func _c_start_game(diff: int, rid: int = 0, resume: bool = false, late: bool = false, mode: String = "casual", pvp_cfg: Dictionary = {}) -> void:
	GameState.game_mode = mode if mode in ["casual", "infinite", "horror", "overdrive", "pvp"] else "casual"
	if GameState.is_pvp():
		_apply_match_config(pvp_cfg)
		var me: int = my_id()
		if players.has(me) and players[me] is Dictionary:
			my_team = int((players[me] as Dictionary).get("team", my_team))
		GameState.pvp_selected_team = clampi(my_team, 0, maxi(0, GameState.pvp_team_count() - 1))
	if GameState.is_overdrive():
		GameState.overdrive_difficulty = clampi(diff, 0, GameState.OVERDRIVE_DIFFICULTIES.size() - 1)
	else:
		GameState.difficulty = clampi(diff, 0, GameState.DIFFICULTIES.size() - 1)
	in_game = true
	GameState.reset_run()
	GameState.run_id = rid
	GameState.pending_resume = resume and not GameState.is_pvp()
	GameState.late_join = late
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# Host: the run ended, everyone goes back to the lobby screen together
func return_to_lobby() -> void:
	if mode == Mode.HOST:
		_c_return_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _c_return_to_lobby() -> void:
	in_game = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# Shared world change (door, power, window board, crate...). Offline it just
# happens; online it goes through the host so every machine applies it in
# the same order. Stations implement net_apply(action, args).
func world(node: Node, action: String, args: Array = []) -> void:
	var ng: Node = get_tree().get_first_node_in_group("net_game") if is_online() else null
	if ng:
		ng.world_event(node, action, args)
	else:
		node.net_apply(action, args)
