extends Node
# HORROR DIRECTOR: how frightening the game is depends on the difficulty
# (GameState.horror(): 0 on Easy = a normal zombie shooter, 1 on Extinction).
#   - darkness: weaker moon and ambient light, so lamps and fires are islands
#   - lights that fail: every lamp flickers and dies for a few seconds
#   - sound scares: steps, whispers and knocks behind you
#   - heartbeat when zombies are close but out of sight
#   - less HUD: no minimap and no zombie count on the scariest settings
# Everything here is local to each player; nothing needs syncing in co-op.

var arena: Node
var player: Node3D
var hud: Node
var h: float = 0.0
var blackout: bool = false
var _lamps: Array = []
var _blackout_t: float = 60.0
var _scare_t: float = 20.0
var _beat_t: float = 0.0
var _busy: bool = false


func setup(p_arena: Node, p_player: Node3D, p_hud: Node, wave_mgr: Node) -> void:
	arena = p_arena
	player = p_player
	hud = p_hud
	h = GameState.horror()
	if h <= 0.0:
		set_process(false)
		return
	_apply_darkness()
	for l in arena.find_children("*", "OmniLight3D", true, false):
		if not (l in arena.fire_lights):
			_lamps.append(l)
	_blackout_t = randf_range(50.0, 90.0)
	_scare_t = randf_range(15.0, 30.0)
	if h >= 0.92:
		wave_mgr.wave_status_changed.connect(_hide_count)


# Subtle refinement over BunkerArena's dark horror baseline
func _apply_darkness() -> void:
	var env: Environment = arena.world_env
	if env == null:
		return
	env.ambient_light_energy *= lerpf(1.0, 0.72, h)
	env.tonemap_exposure = lerpf(env.tonemap_exposure, 0.94, h)
	env.volumetric_fog_density *= 1.0 + 0.30 * h
	for d in arena.find_children("*", "DirectionalLight3D", true, false):
		(d as DirectionalLight3D).light_energy *= lerpf(1.0, 0.70, h)
	var sky := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
	if sky:
		sky.sky_cover_modulate = sky.sky_cover_modulate * lerpf(1.0, 0.75, h)


func _hide_count(_txt: String) -> void:
	var lbl: Label = hud.hostiles_lbl
	if lbl and lbl.text.begins_with("ZOMBIES"):
		lbl.text = "ZOMBIES: ??  (THEN BOSS)"


func _process(delta: float) -> void:
	if not is_instance_valid(player) or player.get("is_dead") == true:
		return
	if h >= 0.35 and not _busy:
		_blackout_t -= delta
		if _blackout_t <= 0.0:
			_blackout_t = randf_range(70.0, 150.0) / (0.5 + h)
			_run_blackout()
	_scare_t -= delta
	if _scare_t <= 0.0:
		_scare_t = randf_range(16.0, 34.0) / (0.4 + h)
		_sound_scare()


func trigger_boss_blackout(duration: float = 2.6) -> void:
	if _busy or not is_inside_tree():
		return
	_busy = true
	GameState.play_sfx("boss_blackout", 1.0, 1.0)
	for i in range(4):
		if not is_inside_tree():
			_busy = false
			return
		_set_lamps(i % 2 == 1)
		await get_tree().create_timer(randf_range(0.05, 0.13)).timeout
	if not is_inside_tree():
		_busy = false
		return
	_set_lamps(false)
	blackout = true
	await get_tree().create_timer(duration).timeout
	if not is_inside_tree():
		_busy = false
		return
	for i in range(3):
		if not is_inside_tree():
			_busy = false
			return
		_set_lamps(i % 2 == 0)
		await get_tree().create_timer(randf_range(0.05, 0.14)).timeout
	if not is_inside_tree():
		_busy = false
		return
	_set_lamps(true)
	blackout = false
	_busy = false


# Lamps stutter, die for a few seconds, then come back
func _run_blackout() -> void:
	if not is_inside_tree():
		return
	_busy = true
	GameState.play_sfx("trap_zap", -10.0, 0.7)
	for i in range(4):
		if not is_inside_tree():
			_busy = false
			return
		_set_lamps(i % 2 == 1)
		await get_tree().create_timer(randf_range(0.06, 0.18)).timeout
	if not is_inside_tree():
		_busy = false
		return
	_set_lamps(false)
	blackout = true
	GameState.play_sfx("power_on", -8.0, 0.45)
	await get_tree().create_timer(2.5 + 4.0 * h).timeout
	if not is_inside_tree():
		_busy = false
		return
	for i in range(3):
		if not is_inside_tree():
			_busy = false
			return
		_set_lamps(i % 2 == 0)
		await get_tree().create_timer(randf_range(0.05, 0.14)).timeout
	if not is_inside_tree():
		_busy = false
		return
	_set_lamps(true)
	blackout = false
	_busy = false


func _set_lamps(on: bool) -> void:
	for l in _lamps:
		if is_instance_valid(l):
			(l as Node3D).visible = on


# Something moves or breathes just behind you. Nothing is really there.
func _sound_scare() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var back := cam.global_basis.z
	back.y = 0.0
	back = back.normalized().rotated(Vector3.UP, randf_range(-0.9, 0.9))
	var pos := cam.global_position + back * randf_range(2.5, 6.0)
	match randi() % 9:
		0:
			_play_at("zombie_step_1", pos, 2.0, 0.8)
			get_tree().create_timer(0.45).timeout.connect(func(): _play_at("zombie_step_2", pos + back * -0.6, 3.0, 0.8))
		1:
			_play_at("whisper_eerie", pos, -2.0, randf_range(0.92, 1.08))
		2:
			_play_at("board_tear", pos + back * 6.0, -4.0, 0.6)
		3:
			_play_at("scream_far", pos + back * 25.0, -2.0, randf_range(0.8, 1.1))
		4:
			_play_at("creak", pos, 0.0, 0.7)
		5:
			_play_at("zombie_roar_2", pos, -14.0, 0.45) # low breath
		6:
			_play_at("metal_scrape", pos + back * 4.0, -3.0, randf_range(0.88, 1.12))
		7:
			_play_at("fluorescent_buzz", pos, -5.0, randf_range(0.92, 1.08))
		8:
			_play_at("zombie_groan", pos, -7.0, 1.65)


func _play_at(clip: String, pos: Vector3, db: float, pitch: float) -> void:
	var st := GameState.get_sfx_stream(clip)
	if st == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = &"SFX"
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = 5.0
	p.max_distance = 60.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
