class_name OutbreakWaveManager
extends WaveManager
# Wave manager for the open-world OUTBREAK mode (The County). Rounds, bosses,
# hounds, power-ups and exfil all run exactly as in the classic mode (it is
# the same WaveManager underneath); on top of that sits the DIRECTOR:
#   * round zombies are OutbreakZombies that come in out of sight and hunt
#   * an ambient population roams the land around every player in packs,
#     not counted toward the round: they wake up when they see or hear you
#   * gunfire and running engines are noise: zombies in earshot come looking
#   * zombies left far behind are recycled to a fresh spot near a player,
#     so a 1 km map never empties out or fills up with stragglers
# The closed map never loads this file.

const AMBIENT_BASE := 14
const AMBIENT_PER_PLAYER := 5
const AMBIENT_MAX := 34
const RECYCLE_RANGE := 150.0
const GUN_NOISE := 42.0
const ENGINE_NOISE := 22.0

var _ambient: Array[OutbreakZombie] = []
var _dir_t := 0.0
var _recycle_t := 0.0
var _noise_t := 0.0
var _wired: Dictionary = {}  # player -> last mag count


func _new_zombie() -> ZombieEnemy:
	return OutbreakZombie.new()


# Hounds strike down near the player, on open ground with a path to them.
func _hound_spawn_point() -> Vector3:
	return (arena as OpenWorld).open_spawn_point(_focus_pos(), 9.0, 16.0)


func _process(delta: float) -> void:
	super._process(delta)
	if Net.is_online() and not Net.is_host():
		return
	if not (arena is OpenWorld) or not is_instance_valid(player):
		return
	_dir_t -= delta
	_recycle_t -= delta
	_noise_t -= delta
	if _dir_t <= 0.0:
		_dir_t = 0.8
		_top_up_ambient()
	if _recycle_t <= 0.0:
		_recycle_t = 2.0
		_recycle()
	if _noise_t <= 0.0:
		_noise_t = 0.5
		_listen()


# ---------------------------------------------------------------- ambient
func _ambient_target() -> int:
	var n := AMBIENT_BASE + AMBIENT_PER_PLAYER * (Net.player_count() - 1) + mini(GameState.current_round, 12)
	if boss_pending and alive_enemies <= 0:
		n = n / 2  # quieter while a boss walks in
	return mini(n, AMBIENT_MAX)


func _top_up_ambient() -> void:
	_ambient.assign(_ambient.filter(func(z): return is_instance_valid(z) and not z.is_dead))
	if _ambient.size() >= _ambient_target():
		return
	var players := _all_players()
	if players.is_empty():
		return
	var focus: Node3D = players[randi() % players.size()]
	var world := arena as OpenWorld
	var pos := world.open_spawn_point(focus.global_position, 45.0, 110.0)
	# a small pack: 1-3 zombies sharing a home point
	var pack := 1 + (randi() % 3)
	for i in range(pack):
		if _ambient.size() >= _ambient_target():
			break
		var p := pos + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
		p.y = world.terrain.height_at(p.x, p.z) + 0.15
		var z := _spawn_regular_zombie(GameState.current_round, p, "walker" if randf() < 0.7 else "")
		if z == null:
			continue
		# not part of the round: undo the round bookkeeping, keep the rewards
		alive_enemies = maxi(0, alive_enemies - 1)
		z.died.disconnect(_on_enemy_died)
		z.died.connect(_on_ambient_died)
		var oz := z as OutbreakZombie
		oz.ambient = true
		oz.start_wandering(p)
		_ambient.append(oz)
	_emit_wave_status()


func _on_ambient_died(enemy: ZombieEnemy, headshot: bool) -> void:
	# full kill pipeline (points, drops, challenges) without touching the round count
	alive_enemies += 1
	_on_enemy_died(enemy, headshot)


# ---------------------------------------------------------------- recycling
func _recycle() -> void:
	var players := _all_players()
	if players.is_empty():
		return
	var world := arena as OpenWorld
	for n in get_tree().get_nodes_in_group("enemies"):
		var z := n as OutbreakZombie
		if z == null or z.is_dead or z.is_boss:
			continue
		var far := true
		for p in players:
			if (p as Node3D).global_position.distance_to(z.global_position) < RECYCLE_RANGE:
				far = false
				break
		if not far:
			continue
		var focus: Node3D = players[randi() % players.size()]
		if z.ambient:
			var spot := world.open_spawn_point(focus.global_position, 50.0, 110.0)
			z.global_position = spot
			z.start_wandering(spot)
		else:
			z.global_position = world.open_spawn_point(focus.global_position, 28.0, 44.0)
			z.target_player = focus
		z.velocity = Vector3.ZERO


# ---------------------------------------------------------------- noise
func _listen() -> void:
	for p in _all_players():
		var pl := p as Node3D
		if pl == null:
			continue
		# gunfire: watch the magazine count drop (works for every weapon)
		if pl is PlayerController and not _wired.has(pl):
			_wired[pl] = true
			(pl as PlayerController).ammo_changed.connect(func(_n: String, mag: int, _r: int, reloading: bool, _pap: bool):
				var last: int = pl.get_meta("ob_last_mag", mag)
				pl.set_meta("ob_last_mag", mag)
				if mag < last and not reloading:
					_noise(pl, pl.global_position, GUN_NOISE))
	for v in get_tree().get_nodes_in_group("vehicles"):
		var car := v as DriveVehicle
		if car and is_instance_valid(car.driver) and car.linear_velocity.length() > 2.0:
			_noise(car.driver, car.global_position, ENGINE_NOISE)


func _noise(who: Node3D, at: Vector3, radius: float) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		var z := n as OutbreakZombie
		if z and z.wandering and z.global_position.distance_to(at) < radius:
			z.alert(who, false)
