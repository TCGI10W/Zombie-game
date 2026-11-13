class_name NetGame
extends Node
# Co-op gameplay sync, living at /root/Game/NetGame on every machine.
#
# Built for long-distance, lossy links:
#  - Your own movement, aim and hit detection run locally (instant feel).
#    Hits on zombies are predicted and forwarded to the host, which trusts
#    the shooter, so nothing you hit "un-dies" on a laggy link.
#  - The host runs zombies/rounds and sends compact snapshots (12 bytes per
#    zombie, 15 Hz) on an unreliable channel: a lost packet is skipped, never
#    resent late. Clients draw everything slightly in the past and blend
#    between snapshots, with an adaptive delay that grows with jitter.
#  - Events that must not be lost (spawns, deaths, purchases, doors, revives,
#    rounds) go on the reliable channel.

const STATE_INTERVAL := 0.05
const SNAP_INTERVAL := 1.0 / 15.0
const FIRE_INTERVAL := 0.05
const READY_TIMEOUT := 45.0
const RemotePlayerScript := preload("res://scripts/net/remote_player.gd")

static var render_delay: float = 0.12

var player: PlayerController
var wave_mgr: WaveManager
var arena: BunkerArena
var container: Node3D
var avatars: Dictionary = {} # peer id -> RemotePlayer
var zombies: Dictionary = {} # net id -> ZombieEnemy
var world_nodes: Array = []
var weapon_keys: Array = []
var started: bool = false
var game_over: bool = false

var _next_zid: int = 1
var _state_t: float = 0.0
var _snap_t: float = 0.0
var _fire_t: float = 0.0
var _check_t: float = 0.0
var _wait_t: float = 0.0
var _hello_t: float = 0.0
var _loaded_ack: bool = false
var _jitter: float = 0.02
var _ready_peers: Dictionary = {}
var _hits := StreamPeerBuffer.new()
var _hit_count: int = 0
var _fire_pts := PackedVector3Array()
var _fire_weapon: String = ""

# Being revived (this machine's player)
var revive_by: String = ""
var revive_in: float = 0.0
var _revive_show_t: float = 0.0

# HUD
var _hud: CanvasLayer
var _roster_box: VBoxContainer
var _center_lbl: Label
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _roster_t: float = 0.0


func setup(p_player: PlayerController, p_wave: WaveManager, p_arena: BunkerArena, p_container: Node3D) -> void:
	player = p_player
	wave_mgr = p_wave
	arena = p_arena
	container = p_container
	weapon_keys = GameState.WEAPONS.keys()
	weapon_keys.append("knife")
	add_to_group("net_game")
	_index_world()
	_place_local_player()
	for id in Net.players.keys():
		if int(id) != Net.my_id():
			_add_avatar(int(id))
	Net.lobby_changed.connect(_on_roster_changed)
	_build_hud()
	if Net.is_host():
		_ready_peers[1] = true
	render_delay = 0.12
	# Coming back to a run (resume or rejoin): restore this player's loadout
	if (GameState.pending_resume or GameState.late_join) and not GameState.is_pvp():
		player.import_state(GameState.load_player_state(GameState.run_id))


# Interactables, numbered in tree order (identical on every machine)
func _index_world() -> void:
	world_nodes.clear()
	for n in arena.find_children("*", "", true, false):
		if n.has_method("net_apply"):
			n.set_meta("net_idx", world_nodes.size())
			world_nodes.append(n)


func _spawn_point(idx: int) -> Vector3:
	if idx <= 0:
		return arena.player_spawn
	var ang := float(idx) / 8.0 * TAU
	return arena.player_spawn + Vector3(cos(ang), 0.0, sin(ang)) * 1.7


func _my_index() -> int:
	var ids := Net.players.keys()
	ids.sort()
	return maxi(0, ids.find(Net.my_id()))


func _place_local_player() -> void:
	if GameState.is_pvp() and is_instance_valid(player):
		player.team_id = Net.my_team
	player.global_position = _spawn_point(_my_index())


func _add_avatar(id: int) -> void:
	if avatars.has(id):
		return
	var av: RemotePlayer = RemotePlayerScript.new()
	var tid: int = Net.player_team(id)
	av.setup(id, Net.player_name(id), Net.player_color(id), tid)
	get_parent().add_child(av)
	av.global_position = arena.player_spawn
	avatars[id] = av


func _on_roster_changed() -> void:
	for id in Net.players.keys():
		var pid: int = int(id)
		if pid != Net.my_id() and not avatars.has(pid):
			_add_avatar(pid)
			var msg: String = "%s JOINED THE MATCH" if GameState.is_pvp() else "%s JOINED THE SQUAD"
			player.status_banner_requested.emit(msg % Net.player_name(pid), Color(0.55, 0.9, 1.0))
		elif pid != Net.my_id() and avatars.has(pid):
			var av_upd: RemotePlayer = avatars[pid] as RemotePlayer
			if is_instance_valid(av_upd):
				av_upd.set_team_id(Net.player_team(pid))
	for id in avatars.keys():
		if not Net.players.has(id):
			var av: Node = avatars[id]
			if is_instance_valid(av):
				player.status_banner_requested.emit("%s LEFT THE GAME" % av.display_name, Color(1.0, 0.6, 0.3))
				av.queue_free()
			avatars.erase(id)


func _process(delta: float) -> void:
	if not Net.is_online() or not is_instance_valid(player):
		return
	_state_t += delta
	if _state_t >= STATE_INTERVAL:
		_state_t = 0.0
		_send_state()
	_fire_t += delta
	if _fire_t >= FIRE_INTERVAL and _fire_pts.size() > 0:
		_fire_t = 0.0
		_r_fire.rpc(maxi(0, weapon_keys.find(_fire_weapon)), _fire_pts)
		_fire_pts = PackedVector3Array()
	if Net.is_host():
		if not started:
			_wait_t += delta
			var all_in := true
			for id in Net.players.keys():
				if not _ready_peers.has(int(id)):
					all_in = false
			if all_in or _wait_t > READY_TIMEOUT:
				started = true
				if GameState.is_pvp() or wave_mgr == null:
					var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
					if pvp_dir and pvp_dir.has_method("on_net_started"):
						pvp_dir.on_net_started()
				elif GameState.pending_resume:
					wave_mgr.resume_saved_world()
				else:
					wave_mgr.start_round(1)
		if not GameState.is_pvp() and wave_mgr != null:
			_snap_t += delta
			if _snap_t >= SNAP_INTERVAL:
				_snap_t = 0.0
				_send_snapshot()
			if _hit_count > 0:
				_c_hits.rpc(_hits.data_array)
				_hits = StreamPeerBuffer.new()
				_hit_count = 0
			_check_t += delta
			if _check_t >= 0.5:
				_check_t = 0.0
				_check_game_over()
	elif not _loaded_ack:
		_hello_t -= delta
		if _hello_t <= 0.0:
			_hello_t = 1.0
			_s_loaded.rpc_id(1)
	if not GameState.is_pvp():
		if _revive_show_t > 0.0:
			_revive_show_t -= delta
			if _revive_show_t <= 0.0:
				revive_in = 0.0
		_update_spectate()
		_update_hud(delta)


# ---------------------------------------------------------------------------
# LOADING HANDSHAKE
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func _s_loaded() -> void:
	var id := multiplayer.get_remote_sender_id()
	var was_ready := _ready_peers.has(id)
	_ready_peers[id] = true
	_c_loaded_ack.rpc_id(id)
	if started and not was_ready:
		_send_late_state(id)


# Host: bring a player who joined mid-run up to date.
func _send_late_state(peer: int) -> void:
	if GameState.is_pvp() or wave_mgr == null:
		var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
		var st_pvp: Dictionary = pvp_dir.export_net_state() if pvp_dir and pvp_dir.has_method("export_net_state") else {}
		_c_late_state.rpc_id(peer, {"pvp": true, "pvp_state": st_pvp})
		return
	var boards := {}
	var doors: Array = []
	var power := false
	for i in range(world_nodes.size()):
		var n: Node = world_nodes[i]
		if "boards" in n:
			boards[i] = int(n.boards)
		if "_opened" in n and n._opened:
			doors.append(i)
		if "_running" in n and n._running:
			power = true
	_c_late_state.rpc_id(peer, {"round": GameState.current_round, "event": GameState.round_event, "boards": boards, "doors": doors, "power": power,
		"intermission": wave_mgr.in_intermission})
	for z in zombies.values():
		if is_instance_valid(z) and not z.is_dead and z.has_meta("spawn"):
			var d: Dictionary = (z.get_meta("spawn") as Dictionary).duplicate()
			d["p"] = z.global_position
			d["y"] = z.rotation.y
			d["t"] = z.tier # ranks can change after the spawn
			d["cn"] = z.commander_name
			d["sk"] = z.stolen_skill
			_c_spawn.rpc_id(peer, d)


@rpc("authority", "call_remote", "reliable")
func _c_late_state(st: Dictionary) -> void:
	started = true
	if bool(st.get("pvp", false)) or GameState.is_pvp() or wave_mgr == null:
		var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
		if pvp_dir and pvp_dir.has_method("import_net_state"):
			pvp_dir.import_net_state(st.get("pvp_state", {}))
		return
	for i in st.get("doors", []):
		if int(i) < world_nodes.size():
			world_nodes[int(i)].net_apply("open", [])
	if bool(st.get("power", false)):
		for n in world_nodes:
			if "_running" in n and not n._running:
				n.net_apply("start", [])
	var boards: Dictionary = st.get("boards", {})
	for k in boards.keys():
		if int(k) < world_nodes.size():
			world_nodes[int(k)].net_apply("set", [int(boards[k])])
	wave_mgr.in_intermission = bool(st.get("intermission", false))
	wave_mgr._present_round(int(st.get("round", 1)), String(st.get("event", "")))
	player.status_banner_requested.emit("JOINED THE SQUAD ON ROUND %d" % int(st.get("round", 1)), Color(0.55, 0.9, 1.0))


@rpc("authority", "call_remote", "reliable")
func _c_loaded_ack() -> void:
	_loaded_ack = true


func on_round_start(_round_num: int) -> void:
	started = true
	if player.is_dead and not game_over and Net.is_online():
		player.net_respawn(_spawn_point(_my_index()))


# ---------------------------------------------------------------------------
# PLAYER STATE (every machine -> everyone, unreliable 20 Hz)
# ---------------------------------------------------------------------------
func _send_state() -> void:
	var b := StreamPeerBuffer.new()
	b.put_double(Net.host_time())
	var p := player.global_position
	b.put_float(p.x)
	b.put_float(p.y)
	b.put_float(p.z)
	b.put_float(player.rotation.y)
	b.put_float(player.head_pivot.rotation.x)
	var f := 0
	if player.is_downed:
		f |= 1
	if player.is_dead:
		f |= 2
	if player.extracted:
		f |= 4
	if player.is_crouching or player.is_sliding:
		f |= 8
	if player.is_downed and player.self_reviving:
		f |= 16
	if player.flashlight_lit():
		f |= 32
	b.put_u8(f)
	b.put_u8(int(clampf(player.hp / maxf(1.0, player.max_hp), 0.0, 1.0) * 255.0))
	b.put_u8(maxi(0, weapon_keys.find(player.get_current_weapon_id())))
	b.put_u32(maxi(0, GameState.points))
	b.put_u8(int(clampf(player.bleedout_timer, 0.0, 255.0)))
	b.put_u16(clampi(GameState.total_kills, 0, 65535))
	b.put_u8(clampi(GameState.downs, 0, 255))
	_r_state.rpc(b.data_array)


@rpc("any_peer", "call_remote", "unreliable")
func _r_state(data: PackedByteArray) -> void:
	var av: RemotePlayer = avatars.get(multiplayer.get_remote_sender_id())
	if av == null or data.size() < 36:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var t := b.get_double()
	var pos := Vector3(b.get_float(), b.get_float(), b.get_float())
	var yaw := b.get_float()
	var pitch := b.get_float()
	var f := b.get_u8()
	var hp := float(b.get_u8()) / 255.0
	var widx := b.get_u8()
	var pts := b.get_u32()
	var bleed := float(b.get_u8())
	if data.size() >= 39:
		av.kills = b.get_u16()
		av.downs = b.get_u8()
	av.apply_state(t, pos, yaw, {"pitch": pitch, "downed": (f & 1) != 0, "dead": (f & 2) != 0,
		"extracted": (f & 4) != 0, "crouch": (f & 8) != 0, "self_revive": (f & 16) != 0, "light": (f & 32) != 0, "hp": hp,
		"weapon": weapon_keys[widx] if widx < weapon_keys.size() else "pistol", "points": pts, "bleed": bleed})


# Shots: muzzle flash, sound and tracers on everyone else's screen
func local_shot(w_id: String, end_pt: Vector3) -> void:
	if not Net.is_online():
		return
	_fire_weapon = w_id
	if _fire_pts.size() < 8:
		_fire_pts.append(end_pt)


@rpc("any_peer", "call_remote", "unreliable")
func _r_fire(widx: int, pts: PackedVector3Array) -> void:
	var av: RemotePlayer = avatars.get(multiplayer.get_remote_sender_id())
	if av and widx < weapon_keys.size():
		av.play_fire(weapon_keys[widx], Array(pts))


# ---------------------------------------------------------------------------
# ZOMBIES (host authority)
# ---------------------------------------------------------------------------
func register_zombie(z: ZombieEnemy, data: Dictionary) -> void:
	if not Net.is_online():
		return
	var id := _next_zid
	_next_zid = _next_zid + 1 if _next_zid < 60000 else 1
	z.net_id = id
	zombies[id] = z
	z.tree_exiting.connect(func(): zombies.erase(id))
	data["id"] = id
	data["m"] = z.max_hp
	z.set_meta("spawn", data)
	data["p"] = z.global_position
	data["y"] = z.rotation.y
	_c_spawn.rpc(data)


@rpc("authority", "call_remote", "reliable")
func _c_spawn(data: Dictionary) -> void:
	var kind: String = data["k"]
	var z: ZombieEnemy = HoundEnemy.new() if kind == "h" else ZombieEnemy.new()
	z.net_puppet = true
	z.net_id = int(data["id"])
	z.name = "Z%d" % z.net_id
	z.add_to_group("enemies")
	container.add_child(z)
	z.global_position = data["p"]
	z.rotation.y = data["y"]
	match kind:
		"h":
			(z as HoundEnemy).setup_hound(int(data["r"]))
			if wave_mgr.weather:
				wave_mgr.weather.strike(data["p"])
		"b":
			z.setup_boss(GameState.get_boss_config(int(data["r"])))
			wave_mgr.active_boss = z
			z.boss_damaged.connect(func(b: ZombieEnemy): wave_mgr.boss_updated.emit(b))
			wave_mgr.boss_spawned.emit(z)
			z._play_3d_roar("boss_roar", 0.95)
		_:
			z.setup_regular(int(data["r"]), String(data.get("v", "walker")))
			if randf() < 0.45:
				z._play_3d_roar("zombie_roar_1", randf_range(0.88, 1.12))
	z.max_hp = float(data["m"])
	z.hp = z.max_hp
	if int(data.get("t", 1)) > 1:
		z.commander_name = String(data.get("cn", ""))
		z.stolen_skill = String(data.get("sk", ""))
		z.is_nemesis = bool(data.get("nm", false))
		z.apply_tier(int(data["t"]), false)
	z.rise_timer = 0.0
	var id := z.net_id
	zombies[id] = z
	z.tree_exiting.connect(func(): zombies.erase(id))


func _send_snapshot() -> void:
	var list: Array = []
	for z in zombies.values():
		if is_instance_valid(z) and not z.is_dead:
			list.append(z)
	var b := StreamPeerBuffer.new()
	b.put_double(Net.local_time())
	b.put_u16(list.size())
	for z in list:
		var p: Vector3 = z.global_position
		b.put_u16(z.net_id)
		b.put_16(clampi(int(round(p.x * 100.0)), -32767, 32767))
		b.put_16(clampi(int(round(p.y * 100.0)), -32767, 32767))
		b.put_16(clampi(int(round(p.z * 100.0)), -32767, 32767))
		b.put_u8(int(fposmod(z.rotation.y, TAU) / TAU * 256.0) & 255)
		b.put_u8(clampi(int(Vector2(z.velocity.x, z.velocity.z).length() * 16.0), 0, 255))
		b.put_u8(z.net_anim_byte() & 255)
		b.put_u8(clampi(int(ceil(z.hp / maxf(1.0, z.max_hp) * 255.0)), 1, 255))
	_c_snap.rpc(b.data_array)


@rpc("authority", "call_remote", "unreliable")
func _c_snap(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var t := b.get_double()
	# Host clock = local clock + offset. Track the fastest-arriving packets
	# (smallest delay) and treat the rest as jitter.
	var sample := t - Net.local_time()
	if not Net.clock_synced:
		Net.clock_offset = sample
		Net.clock_synced = true
	elif sample > Net.clock_offset:
		Net.clock_offset = lerpf(Net.clock_offset, sample, 0.5)
	else:
		Net.clock_offset = lerpf(Net.clock_offset, sample, 0.01)
	_jitter = lerpf(_jitter, Net.clock_offset - sample, 0.05)
	render_delay = clampf(SNAP_INTERVAL + 2.5 * _jitter + 0.02, 0.09, 0.4)
	var n := b.get_u16()
	for i in range(n):
		var id := b.get_u16()
		var pos := Vector3(float(b.get_16()), float(b.get_16()), float(b.get_16())) / 100.0
		var yaw := float(b.get_u8()) / 256.0 * TAU
		var spd := float(b.get_u8()) / 16.0
		var anim := b.get_u8()
		var hpf := float(b.get_u8()) / 255.0
		var z: ZombieEnemy = zombies.get(id)
		if z and is_instance_valid(z) and not z.is_dead:
			z.net_push(t, pos, yaw, spd, anim, hpf)


func zombie_hit(z: ZombieEnemy, pos: Vector3, dmg: float, origin: int) -> void:
	if _hit_count >= 60:
		return
	_hits.put_u16(z.net_id)
	_hits.put_16(clampi(int(round(pos.x * 100.0)), -32767, 32767))
	_hits.put_16(clampi(int(round(pos.y * 100.0)), -32767, 32767))
	_hits.put_16(clampi(int(round(pos.z * 100.0)), -32767, 32767))
	_hits.put_u8(clampi(int(dmg / 4.0), 0, 255))
	_hits.put_u32(origin)
	_hit_count += 1


@rpc("authority", "call_remote", "unreliable")
func _c_hits(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var me := Net.my_id()
	while b.get_position() + 13 <= data.size():
		var id := b.get_u16()
		var pos := Vector3(float(b.get_16()), float(b.get_16()), float(b.get_16())) / 100.0
		var dmg := float(b.get_u8()) * 4.0
		var origin := b.get_u32()
		if origin == me:
			continue # we already showed our own hit
		var z: ZombieEnemy = zombies.get(id)
		if z and is_instance_valid(z):
			z.net_remote_hit(pos, dmg)


func zombie_died(z: ZombieEnemy, was_headshot: bool) -> void:
	_c_died.rpc(z.net_id, was_headshot, z.last_hit_point, z.last_hit_from, z.last_damage_amount, z.last_damage_kind)
	zombies.erase(z.net_id)
	# Assists: everyone else who did real damage gets paid too
	var killer := z._net_attacker
	for pid in z.dmg_by.keys():
		if int(pid) == killer or float(z.dmg_by[pid]) < z.max_hp * 0.15:
			continue
		var amount := int(z.point_reward * 0.4) if z.is_boss else 30
		var why := "BOSS ASSIST" if z.is_boss else "ASSIST"
		if int(pid) == Net.my_id():
			_award(amount, why)
		else:
			_c_award.rpc_id(int(pid), amount, why)


@rpc("authority", "call_remote", "reliable")
func _c_award(amount: int, why: String) -> void:
	_award(amount, why)


func _award(amount: int, why: String) -> void:
	GameState.add_points(amount)
	if why == "BOSS ASSIST":
		player.status_banner_requested.emit("BOSS ASSIST  +%d" % amount, Color(0.95, 0.85, 0.35))


func send_points(peer: int, amount: int) -> void:
	_r_points.rpc_id(peer, amount)


@rpc("any_peer", "call_remote", "reliable")
func _r_points(amount: int) -> void:
	var got := maxi(0, amount)
	GameState.points += got
	GameState.points_changed.emit(GameState.points, got)
	GameState.play_sfx("buy_ching", -2.0, 1.2)
	player.status_banner_requested.emit("%s SENT YOU %d POINTS" % [Net.player_name(multiplayer.get_remote_sender_id()), got], Color(0.95, 0.85, 0.35))


@rpc("authority", "call_remote", "reliable")
func _c_died(id: int, headshot: bool, point: Vector3, from_dir: Vector3, dmg: float, kind: String) -> void:
	var z: ZombieEnemy = zombies.get(id)
	zombies.erase(id)
	if z and is_instance_valid(z):
		z.net_remote_die(headshot, point, from_dir, dmg, kind)
		if z.is_boss and wave_mgr.active_boss == z:
			wave_mgr.active_boss = null


func boss_fx(z: ZombieEnemy, kind: String, on: bool, pos: Vector3, amount: float) -> void:
	_c_boss_fx.rpc(z.net_id, kind, on, pos, amount)


@rpc("authority", "call_remote", "reliable")
func _c_boss_fx(id: int, kind: String, on: bool, pos: Vector3, amount: float) -> void:
	var z: ZombieEnemy = zombies.get(id)
	if z and is_instance_valid(z) and not z.is_dead:
		z.net_boss_fx(kind, on, pos, amount)


# Explosions (grenades, C4, mines) show up on everyone's screen.
func broadcast_explosion(pos: Vector3) -> void:
	_r_explosion.rpc(pos)


@rpc("any_peer", "call_remote", "unreliable")
func _r_explosion(pos: Vector3) -> void:
	var fx: Node3D = (load("res://scripts/player/frag_grenade.gd") as GDScript).new()
	fx.set_physics_process(false)
	get_parent().add_child(fx)
	fx.global_position = pos
	fx.visible = false
	GameState.play_sfx("grenade_explode", 0.0, randf_range(0.92, 1.05))
	fx._spawn_fx(pos)
	fx.queue_free()


# Client -> host: our predicted hit. The host trusts the shooter.
func forward_damage(z: ZombieEnemy, raw: float, pos: Vector3, ignore_armor: bool, kind: String, killed: bool, headshot: bool) -> void:
	_s_damage.rpc_id(1, z.net_id, raw, pos, ignore_armor, kind, killed, headshot)


@rpc("any_peer", "call_remote", "reliable")
func _s_damage(id: int, raw: float, pos: Vector3, ignore_armor: bool, kind: String, killed: bool, headshot: bool) -> void:
	var z: ZombieEnemy = zombies.get(id)
	if z == null or not is_instance_valid(z) or z.is_dead:
		return
	z._net_attacker = multiplayer.get_remote_sender_id()
	z.take_damage(raw, pos, ignore_armor, kind)
	if killed and not z.is_dead:
		z.hp = 0.0
		z._die(headshot)
	z._net_attacker = 1


func forward_status(z: ZombieEnemy, kind: String, duration: float) -> void:
	_s_status.rpc_id(1, z.net_id, kind, duration)


@rpc("any_peer", "call_remote", "reliable")
func _s_status(id: int, kind: String, duration: float) -> void:
	var z: ZombieEnemy = zombies.get(id)
	if z == null or not is_instance_valid(z):
		return
	if kind == "stun":
		z.apply_stun(duration)
	elif kind == "boss_stun":
		z.apply_stun(duration, true)
	else:
		z.apply_pain_drug(duration)


# Host: a zombie hit a teammate -> their own machine takes the damage
func hurt_peer(peer: int, amount: float, from_pos: Vector3) -> void:
	_c_hurt.rpc_id(peer, amount, from_pos)


@rpc("authority", "call_remote", "reliable")
func _c_hurt(amount: float, from_pos: Vector3) -> void:
	player.take_damage(amount, from_pos)


# ---------------------------------------------------------------------------
# SHARED WORLD (doors, power, windows, crate, trap, radio)
# ---------------------------------------------------------------------------
func world_event(node: Node, action: String, args: Array) -> void:
	var idx: int = node.get_meta("net_idx", -1)
	if idx < 0:
		node.net_apply(action, args)
	elif Net.is_host():
		_c_world.rpc(idx, action, args)
		node.net_apply(action, args)
	else:
		_s_world.rpc_id(1, idx, action, args)


@rpc("any_peer", "call_remote", "reliable")
func _s_world(idx: int, action: String, args: Array) -> void:
	if Net.is_host() and idx >= 0 and idx < world_nodes.size():
		_c_world.rpc(idx, action, args)
		world_nodes[idx].net_apply(action, args)


@rpc("authority", "call_remote", "reliable")
func _c_world(idx: int, action: String, args: Array) -> void:
	if idx >= 0 and idx < world_nodes.size() and is_instance_valid(world_nodes[idx]):
		world_nodes[idx].net_apply(action, args)


# ---------------------------------------------------------------------------
# REVIVES, DEATH, GAME OVER
# ---------------------------------------------------------------------------
func send_revive_progress(peer: int, progress: float) -> void:
	_r_revive_progress.rpc_id(peer, progress)


func send_revive(peer: int) -> void:
	_r_revive.rpc_id(peer)


@rpc("any_peer", "call_remote", "unreliable")
func _r_revive_progress(progress: float) -> void:
	revive_in = progress
	revive_by = Net.player_name(multiplayer.get_remote_sender_id())
	_revive_show_t = 0.3


@rpc("any_peer", "call_remote", "reliable")
func _r_revive() -> void:
	if player.is_downed and not player.is_dead:
		player.revive_by_teammate(Net.player_name(multiplayer.get_remote_sender_id()))
		revive_in = 0.0


func any_teammate_standing() -> bool:
	for av in avatars.values():
		if is_instance_valid(av) and not av.is_dead and not av.extracted and (not av.is_downed or av.self_reviving):
			return true
	return false


func _check_game_over() -> void:
	if GameState.is_pvp() or game_over or not started:
		return
	var standing := 0
	var extracted := 0
	for p in get_tree().get_nodes_in_group("net_players"):
		if p.extracted:
			extracted += 1
			continue
		if p.is_dead:
			continue
		if p.is_downed and not p.self_reviving:
			continue
		standing += 1
	if standing == 0:
		_c_game_over.rpc(extracted > 0)
		_game_over(extracted > 0)


@rpc("authority", "call_remote", "reliable")
func _c_game_over(any_extracted: bool) -> void:
	_game_over(any_extracted)


func _game_over(_any_extracted: bool) -> void:
	if game_over:
		return
	game_over = true
	if wave_mgr:
		wave_mgr.set_process(false)
	if player.extracted:
		return # their win screen is already up
	if not player.is_dead:
		player.revives = 0
		player.die()
	else:
		var hud := get_parent().get_node_or_null("GameHUD")
		if hud:
			hud._on_player_died()


# While dead: watch a teammate over the shoulder until the next round.
var _dead_t: float = 0.0


var _spec_idx: int = 0
var _spec_target: RemotePlayer = null


# While dead: see the game through a living teammate's eyes until the next
# round. Your own gun, HUD and body are hidden; click to switch teammate.
func _update_spectate() -> void:
	if GameState.is_pvp():
		return
	var hud := get_parent().get_node_or_null("GameHUD") as CanvasLayer
	var spectating := player.is_dead and not game_over and not player.extracted
	if not spectating:
		_dead_t = 0.0
		_set_spec_target(null)
		if hud and not hud.visible:
			hud.visible = true
		return
	_dead_t += get_process_delta_time()
	player.gun_rig.visible = false
	if _dead_t < 1.6:
		return # let the death camera play out
	var alive: Array = []
	for av in avatars.values():
		if is_instance_valid(av) and not av.is_dead and not av.extracted:
			alive.append(av)
	if alive.is_empty():
		_set_spec_target(null)
		return
	if Input.is_action_just_pressed("fire"):
		_spec_idx += 1
	var target: RemotePlayer = alive[_spec_idx % alive.size()]
	_set_spec_target(target)
	if hud:
		hud.visible = false
	# First person from the teammate's head
	player.camera.rotation = Vector3.ZERO
	player.camera.position = Vector3.ZERO
	player.head_pivot.position.y = player._head_rest_y - (0.25 if target.crouching else 0.0)
	player.global_position = target.global_position
	player.rotation.y = target.rotation.y
	player.head_pivot.rotation.x = target.pitch
	_center_lbl.text = "SPECTATING %s   •   CLICK TO SWITCH
YOU RESPAWN NEXT ROUND IF THE SQUAD HOLDS" % target.display_name


func _set_spec_target(t: RemotePlayer) -> void:
	if _spec_target == t:
		return
	if is_instance_valid(_spec_target):
		_spec_target.spectated = false
	_spec_target = t
	if is_instance_valid(t):
		t.spectated = true


# ---------------------------------------------------------------------------
# SQUAD HUD
# ---------------------------------------------------------------------------
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 6
	_hud.visible = not GameState.is_pvp()
	add_child(_hud)
	_roster_box = VBoxContainer.new()
	_roster_box.anchor_left = 1.0
	_roster_box.anchor_right = 1.0
	_roster_box.offset_left = -270
	_roster_box.offset_right = -18
	_roster_box.offset_top = 92
	_roster_box.add_theme_constant_override("separation", 4)
	_roster_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_roster_box)

	_center_lbl = Label.new()
	_center_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_center_lbl.offset_top = -210
	_center_lbl.offset_bottom = -150
	_center_lbl.offset_left = -360
	_center_lbl.offset_right = 360
	_center_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_lbl.add_theme_font_size_override("font_size", 18)
	_center_lbl.add_theme_constant_override("outline_size", 6)
	_center_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_child(_center_lbl)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0, 0, 0, 0.6)
	_bar_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar_bg.offset_left = -150
	_bar_bg.offset_right = 150
	_bar_bg.offset_top = -146
	_bar_bg.offset_bottom = -136
	_hud.add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.4, 1.0, 0.55)
	_bar_fill.size = Vector2(0, 10)
	_bar_bg.add_child(_bar_fill)


func _update_hud(delta: float) -> void:
	_roster_t -= delta
	if _roster_t <= 0.0:
		_roster_t = 0.25
		for c in _roster_box.get_children():
			c.queue_free()
		for av in avatars.values():
			if not is_instance_valid(av):
				continue
			var row := Label.new()
			var state := "%d PTS" % av.points
			if av.extracted:
				state = "EXTRACTED"
			elif av.is_dead:
				state = "DEAD"
			elif av.is_downed:
				state = "DOWN — %ds" % int(ceil(av.bleed_left)) if not av.self_reviving else "DOWN — GETTING UP"
			var hp_bar := "▮".repeat(int(ceil(av.hp_ratio * 10.0))) + "▯".repeat(10 - int(ceil(av.hp_ratio * 10.0)))
			row.text = "■ %s  %s\n   %s" % [av.display_name, state, hp_bar if not av.is_dead and not av.is_downed else ""]
			row.add_theme_font_size_override("font_size", 14)
			row.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if av.is_downed or av.is_dead else av.color)
			row.add_theme_constant_override("outline_size", 5)
			row.add_theme_color_override("font_outline_color", Color.BLACK)
			_roster_box.add_child(row)

	# Revive bars: us reviving someone, or someone reviving us
	var prog := 0.0
	var text := ""
	if player.is_downed and revive_in > 0.0:
		prog = revive_in
		text = "%s IS REVIVING YOU..." % revive_by
	else:
		for av in avatars.values():
			if is_instance_valid(av) and av.revive_progress > 0.0:
				prog = av.revive_progress
				text = "REVIVING %s..." % av.display_name
		if prog <= 0.0:
			for av in avatars.values():
				if is_instance_valid(av) and av.gift_progress > 0.0:
					prog = av.gift_progress
					text = "SENDING ALL POINTS TO %s..." % av.display_name
	_bar_bg.visible = prog > 0.0
	_bar_fill.size = Vector2(300.0 * clampf(prog, 0.0, 1.0), 10)
	if text != "":
		_center_lbl.text = text
	elif not player.is_dead or game_over:
		_center_lbl.text = ""



# --- Zombie tiers: rank-ups, commander speech and traps for every client
func zombie_tier(z: ZombieEnemy, t: int, cname: String, skill: String = "") -> void:
	_c_zombie_tier.rpc(z.net_id, t, cname, skill)


@rpc("authority", "call_remote", "reliable")
func _c_zombie_tier(id: int, t: int, cname: String, skill: String) -> void:
	var z: ZombieEnemy = zombies.get(id)
	if z and is_instance_valid(z) and not z.is_dead:
		var up := t > z.tier
		z.commander_name = cname
		z.stolen_skill = skill
		z.apply_tier(t, false)
		if up:
			z.tier_up_fx()


func zombie_say(z: ZombieEnemy, line: String) -> void:
	_c_zombie_say.rpc(z.net_id, line)


@rpc("authority", "call_remote", "reliable")
func _c_zombie_say(id: int, line: String) -> void:
	var z: ZombieEnemy = zombies.get(id)
	if z and is_instance_valid(z) and z.commander:
		z.commander.show_line(line)


func zombie_trap(pos: Vector3, t: int) -> void:
	_c_zombie_trap.rpc(pos, t)


@rpc("authority", "call_remote", "reliable")
func _c_zombie_trap(pos: Vector3, t: int) -> void:
	var wm := get_tree().current_scene.get_node_or_null("WaveManager")
	if wm:
		wm._place_trap(pos, t)


# ---------------------------------------------------------------------------
# PVP AUTHORITY & EVENT SYNC
# ---------------------------------------------------------------------------
func request_pvp_hit(target_key: String, damage: float, is_hs: bool, weapon_id: String, attacker_pos: Vector3) -> void:
	var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
	if pvp_dir == null:
		return
	if Net.is_host() or not Net.is_online():
		var my_key: String = "peer_%d" % Net.my_id()
		pvp_dir.apply_pvp_hit(my_key, target_key, damage, is_hs, weapon_id, attacker_pos)
	else:
		_s_pvp_hit.rpc_id(1, target_key, damage, is_hs, weapon_id, attacker_pos)


@rpc("any_peer", "call_remote", "reliable")
func _s_pvp_hit(target_key: String, damage: float, is_hs: bool, weapon_id: String, attacker_pos: Vector3) -> void:
	if not Net.is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
	if pvp_dir:
		pvp_dir.apply_pvp_hit("peer_%d" % sender, target_key, damage, is_hs, weapon_id, attacker_pos)


func broadcast_pvp_event(ev: Dictionary) -> void:
	if Net.is_host() and Net.is_online():
		_c_pvp_event.rpc(ev)


@rpc("authority", "call_remote", "reliable")
func _c_pvp_event(ev: Dictionary) -> void:
	var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
	if pvp_dir and pvp_dir.has_method("handle_net_event"):
		pvp_dir.handle_net_event(ev)


func request_pvp_interact(zone_id: String, action: String) -> void:
	var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
	if pvp_dir == null:
		return
	if Net.is_host() or not Net.is_online():
		pvp_dir.handle_interact("peer_%d" % Net.my_id(), zone_id, action)
	else:
		_s_pvp_interact.rpc_id(1, zone_id, action)


@rpc("any_peer", "call_remote", "reliable")
func _s_pvp_interact(zone_id: String, action: String) -> void:
	if not Net.is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
	if pvp_dir:
		pvp_dir.handle_interact("peer_%d" % sender, zone_id, action)
