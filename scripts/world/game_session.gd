extends Node3D

var arena: BunkerArena
var player: PlayerController
var wave_mgr: WaveManager
var hud: GameHUD
var enemies_container: Node3D
var post_fx: ShaderMaterial
var _fx_damage: float = 0.0
var _fx_downed: float = 0.0


func _ready() -> void:
	GameState.reset_run()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

	wave_mgr = WaveManager.new()
	wave_mgr.name = "WaveManager"
	add_child(wave_mgr)

	hud = GameHUD.new()
	hud.name = "GameHUD"
	add_child(hud)

	var weather := Weather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(arena.world_env)
	wave_mgr.weather = weather
	var atmo: Node3D = (load("res://scripts/world/atmosphere.gd") as GDScript).new()
	atmo.name = "Atmosphere"
	add_child(atmo)
	atmo.setup(arena, weather)

	hud.setup(player, wave_mgr)
	var challenge: Node = (load("res://scripts/world/round_challenge.gd") as GDScript).new()
	challenge.name = "RoundChallenge"
	add_child(challenge)
	challenge.setup(player, wave_mgr)
	if GameState.pending_resume and not Net.is_online():
		player.import_state(GameState.load_player_state(GameState.run_id))
	wave_mgr.setup(arena, player, enemies_container)

	GameState.apply_graphics()
	var horror: Node = (load("res://scripts/world/horror_director.gd") as GDScript).new()
	horror.name = "Horror"
	add_child(horror)
	horror.setup(arena, player, hud, wave_mgr)

	if Net.is_online():
		var ng := NetGame.new()
		ng.name = "NetGame"
		add_child(ng)
		ng.setup(player, wave_mgr, arena, enemies_container)


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
		rect.material = post_fx
		layer.add_child(rect)


func _process(delta: float) -> void:
	if post_fx == null or not is_instance_valid(player):
		return
	var ratio := clampf(player.hp / maxf(1.0, player.max_hp), 0.0, 1.0)
	var want_damage := clampf((0.45 - ratio) / 0.45, 0.0, 1.0)
	_fx_damage = lerpf(_fx_damage, want_damage, clampf(4.0 * delta, 0.0, 1.0))
	_fx_downed = move_toward(_fx_downed, 1.0 if player.is_downed else 0.0, delta * 2.5)
	post_fx.set_shader_parameter("damage", _fx_damage)
	post_fx.set_shader_parameter("downed", _fx_downed)
