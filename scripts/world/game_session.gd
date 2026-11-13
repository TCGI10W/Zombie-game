extends Node3D

const PvpMapArenaScript := preload("res://scripts/world/pvp_map_arena.gd")

var arena: BunkerArena
var player: PlayerController
var wave_mgr: WaveManager
var hud: GameHUD
var enemies_container: Node3D
var post_fx: ShaderMaterial
var _fx_damage: float = 0.0
var _fx_downed: float = 0.0
var _fx_stress: float = 0.0


func _ready() -> void:
	GameState.reset_run()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var is_pvp: bool = GameState.is_pvp()
	if is_pvp:
		if not GameState.PVP_MAPS.has(GameState.active_pvp_map):
			GameState.resolve_pvp_map()
		if GameState.active_pvp_map != "nacht":
			arena = PvpMapArenaScript.new(GameState.active_pvp_map)
		else:
			arena = BunkerArena.new()
	else:
		arena = BunkerArena.new()
	arena.name = "BunkerArena"
	add_child(arena)

	enemies_container = Node3D.new()
	enemies_container.name = "EnemiesContainer"
	add_child(enemies_container)

	player = PlayerController.new()
	player.name = "Player"
	player.position = arena.player_spawn
	add_child(player)

	if not is_pvp:
		wave_mgr = WaveManager.new()
		wave_mgr.name = "WaveManager"
		add_child(wave_mgr)

	hud = GameHUD.new()
	hud.name = "GameHUD"
	add_child(hud)

	var weather_node: Weather = null
	if not is_pvp:
		var weather := Weather.new()
		weather.name = "Weather"
		add_child(weather)
		weather.setup(arena.world_env)
		wave_mgr.weather = weather
		weather_node = weather
		var atmo: Node3D = (load("res://scripts/world/atmosphere.gd") as GDScript).new()
		atmo.name = "Atmosphere"
		add_child(atmo)
		atmo.setup(arena, weather)

	hud.setup(player, wave_mgr)
	if not is_pvp:
		if GameState.is_overdrive():
			var od_dir: Node = (load("res://scripts/world/overdrive_director.gd") as GDScript).new()
			od_dir.name = "Overdrive"
			add_child(od_dir)
		var challenge: Node = (load("res://scripts/world/round_challenge.gd") as GDScript).new()
		challenge.name = "RoundChallenge"
		add_child(challenge)
		challenge.setup(player, wave_mgr)
		if GameState.pending_resume and not Net.is_online():
			player.import_state(GameState.load_player_state(GameState.run_id))
		wave_mgr.setup(arena, player, enemies_container)

	GameState.apply_graphics()
	if GameState.is_horror_mode():
		var horror: Node = (load("res://scripts/world/horror_director.gd") as GDScript).new()
		horror.name = "Horror"
		add_child(horror)
		horror.setup(arena, player, hud, wave_mgr)
		var crow_mgr: Node3D = (load("res://scripts/world/crow_flock_manager.gd") as GDScript).new()
		crow_mgr.name = "CrowFlockManager"
		add_child(crow_mgr)
		crow_mgr.setup(arena, player, wave_mgr, weather_node)

	var ng: NetGame = null
	if Net.is_online():
		ng = NetGame.new()
		ng.name = "NetGame"
		add_child(ng)
		ng.setup(player, wave_mgr, arena, enemies_container)

	if is_pvp:
		var pvp_dir: PvpDirector = (load("res://scripts/world/pvp_director.gd") as GDScript).new()
		pvp_dir.name = "PvpDirector"
		add_child(pvp_dir)
		pvp_dir.setup(player, arena, enemies_container, ng)
		var pvp_hud: CanvasLayer = (load("res://scripts/ui/pvp_hud.gd") as GDScript).new()
		pvp_hud.name = "PvpHUD"
		add_child(pvp_hud)
		pvp_hud.setup(player, pvp_dir)


	# First match after launching: draw everything once so the graphics card
	# prepares its shaders now instead of stuttering mid-fight
	if not Engine.has_meta("shaders_warmed"):
		var warm: Node = (load("res://scripts/world/shader_warmup.gd") as GDScript).new()
		add_child(warm)
		warm.start(self)

	# Camera finishing pass (grain, vignette, grade) under the HUD
	if true:
		var layer := CanvasLayer.new()
		layer.name = "PostFX"
		layer.layer = -1
		layer.visible = GameState.post_fx_enabled
		add_child(layer)
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		post_fx = ShaderMaterial.new()
		post_fx.shader = load("res://assets/shaders/post_fx.gdshader")
		if GameState.is_overdrive() or is_pvp:
			post_fx.set_shader_parameter("grain", 0.0)
			post_fx.set_shader_parameter("vignette", 0.10)
			post_fx.set_shader_parameter("aberration", 0.0004)
			post_fx.set_shader_parameter("saturation", 1.22)
			post_fx.set_shader_parameter("contrast", 1.04)
			post_fx.set_shader_parameter("shadow_tint", Vector3(0.0, 0.002, 0.005))
			post_fx.set_shader_parameter("highlight_tint", Vector3(1.03, 1.0, 0.95))
		elif not GameState.is_horror_mode():
			# Classic CASUAL / INFINITE: crisp moonlit night grading (no dark horror crush)
			post_fx.set_shader_parameter("grain", 0.008)
			post_fx.set_shader_parameter("vignette", 0.16)
			post_fx.set_shader_parameter("aberration", 0.0005)
			post_fx.set_shader_parameter("saturation", 1.06)
			post_fx.set_shader_parameter("contrast", 1.04)
			post_fx.set_shader_parameter("shadow_tint", Vector3(0.002, 0.004, 0.010))
			post_fx.set_shader_parameter("highlight_tint", Vector3(0.99, 1.0, 1.02))
		rect.material = post_fx
		layer.add_child(rect)


func _process(delta: float) -> void:
	if post_fx == null or not is_instance_valid(player):
		return
	var ratio := clampf(player.hp / maxf(1.0, player.max_hp), 0.0, 1.0)
	var want_damage := clampf((0.45 - ratio) / 0.45, 0.0, 1.0)
	_fx_damage = lerpf(_fx_damage, want_damage, clampf(4.0 * delta, 0.0, 1.0))
	_fx_downed = move_toward(_fx_downed, 1.0 if player.is_downed else 0.0, delta * 2.5)
	_fx_stress = lerpf(_fx_stress, float(player.get("stress")) if player.get("stress") != null else 0.0, clampf(5.0 * delta, 0.0, 1.0)) if GameState.is_horror_mode() else 0.0
	post_fx.set_shader_parameter("stress", _fx_stress)
	post_fx.set_shader_parameter("damage", _fx_damage)
	post_fx.set_shader_parameter("downed", _fx_downed)
