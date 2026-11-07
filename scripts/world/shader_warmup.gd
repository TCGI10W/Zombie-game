extends Node
# Shader warm-up: the first time a material or effect is drawn, the graphics
# driver has to prepare ("compile") it, which can cause hitches and lower FPS
# early in the first run after launching or updating the game. Behind a short
# "preparing" screen we draw every zombie type, boss, tier glow and combat
# effect once in front of the camera, so it is all ready before play starts.
# Runs once per launch.

const VARIANTS := ["walker", "sprinter", "armored", "crawler", "bloater", "spitter", "shielded"]
const HOLD := 1.6

var _session: Node
var _things: Array[Node] = []
var _layer: CanvasLayer
var _t: float = 0.0


func start(session: Node) -> void:
	_session = session
	Engine.set_meta("shaders_warmed", true)
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)
	var lbl := Label.new()
	lbl.text = "PREPARING THE OUTBREAK..."
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.35, 0.25))
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = -300
	lbl.offset_right = 300
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer.add_child(lbl)
	_spawn_all.call_deferred()


func _spawn_all() -> void:
	var player: Node3D = _session.get_node_or_null("Player")
	var cam := get_viewport().get_camera_3d()
	if player == null or cam == null:
		queue_free()
		return
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var base := cam.global_position + fwd * 8.0
	base.y = 0.1
	var i := 0
	var scene := _session
	for v in VARIANTS:
		var z := ZombieEnemy.new()
		scene.add_child(z)
		z.global_position = base + right * (-6.0 + 2.0 * float(i % 7)) + fwd * float(i / 7) * 2.0
		z.setup_regular(1, v)
		z.process_mode = Node.PROCESS_MODE_DISABLED
		if i % 2 == 1:
			z.tier = 2 + (i % 4)
			z._tier_visuals() # tier glow materials
		_things.append(z)
		i += 1
	for r in range(1, 6):
		var b := ZombieEnemy.new()
		scene.add_child(b)
		b.global_position = base + fwd * 5.0 + right * (-6.0 + 3.0 * float(r - 1))
		b.setup_boss(GameState.get_boss_config(r))
		b.process_mode = Node.PROCESS_MODE_DISABLED
		_things.append(b)
	# Combat effects
	var p := base + Vector3(0, 1.2, 0)
	FX.blood_spray(p, Vector3.UP, 12)
	FX.gore_burst(p, 4, 2.0)
	FX.impact(p, -fwd)
	FX.blood_decal(base + Vector3(0, 0.02, 0), Vector3.UP, 1.2)
	FX.casing(p, right, Vector3.UP, false)
	FX.casing(p, right, Vector3.UP, true)
	if _things.size() > 0:
		FX.damage_number(_things[0] as Node3D, p, 42.0, true, true)
	var frag: Node3D = (load("res://scripts/player/frag_grenade.gd") as GDScript).new()
	frag.set("freeze", true)
	scene.add_child(frag)
	frag.global_position = base + right * 3.0
	frag.set_physics_process(false)
	frag._spawn_fx(frag.global_position)
	_things.append(frag)


func _process(delta: float) -> void:
	_t += delta
	if _t < HOLD:
		return
	for n in _things:
		if is_instance_valid(n):
			n.queue_free()
	_things.clear()
	queue_free()
