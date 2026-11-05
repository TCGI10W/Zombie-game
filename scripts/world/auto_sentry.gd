extends Node3D
# AUTO-SENTRY from the Supply Depot: a tripod gun that shoots the nearest
# zombie it can see for a while, then powers down. Kills pay its owner.

const LIFETIME := 60.0
const RANGE := 22.0
const FIRE_GAP := 0.12

var owner_player: Node = null
var _life: float = LIFETIME
var _cd: float = 0.5
var _head: Node3D
var _light: OmniLight3D


func _ready() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.24, 0.26)
	metal.metallic = 0.7
	metal.roughness = 0.45
	for i in range(3):
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.025
		lm.bottom_radius = 0.035
		lm.height = 0.75
		leg.mesh = lm
		leg.material_override = metal
		var a := TAU * float(i) / 3.0
		leg.position = Vector3(cos(a) * 0.2, 0.33, sin(a) * 0.2)
		leg.rotation = Vector3(sin(a) * 0.35, 0.0, -cos(a) * 0.35)
		add_child(leg)
	_head = Node3D.new()
	_head.position.y = 0.75
	add_child(_head)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.22, 0.42)
	body.mesh = bm
	body.material_override = metal
	_head.add_child(body)
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.035
	cm.height = 0.5
	barrel.mesh = cm
	barrel.material_override = metal
	barrel.rotation.x = PI / 2.0
	barrel.position = Vector3(0, 0.02, -0.4)
	_head.add_child(barrel)
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.035
	em.height = 0.07
	eye.mesh = em
	eye.material_override = MaterialLib.get_emissive(Color(0.3, 1.0, 0.5), 4.0)
	eye.position = Vector3(0, 0.13, -0.12)
	_head.add_child(eye)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.35)
	_light.light_energy = 0.0
	_light.omni_range = 4.0
	_light.position = Vector3(0, 0.02, -0.7)
	_head.add_child(_light)
	var lbl := Label3D.new()
	lbl.name = "Timer"
	lbl.font_size = 26
	lbl.outline_size = 8
	lbl.pixel_size = 0.004
	lbl.modulate = Color(0.4, 1.0, 0.55)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = 1.2
	add_child(lbl)


func _physics_process(delta: float) -> void:
	_life -= delta
	(get_node("Timer") as Label3D).text = "SENTRY %ds" % ceili(maxf(0.0, _life))
	_light.light_energy = maxf(0.0, _light.light_energy - delta * 40.0)
	if _life <= 0.0:
		queue_free()
		return
	var target := _pick_target()
	if target == null:
		return
	var aim := target.global_position + Vector3(0, 1.1, 0)
	var flat := Vector3(aim.x, _head.global_position.y, aim.z)
	if flat.distance_to(_head.global_position) > 0.05:
		_head.look_at(flat, Vector3.UP)
	_cd -= delta
	if _cd > 0.0:
		return
	_cd = FIRE_GAP
	var mult := 1.0
	if is_instance_valid(owner_player) and owner_player.has_method("dmg_mult"):
		mult = owner_player.dmg_mult()
	var res: Dictionary = target.take_damage(55.0 * mult, aim, false, "bullet")
	if res.get("killed", false) and is_instance_valid(owner_player):
		owner_player._on_enemy_killed_by_player(target, false)
	_light.light_energy = 3.0
	_tracer(_head.global_position + (-_head.global_basis.z) * 0.6, aim)
	GameState.play_sfx("gun_smg", -13.0, randf_range(1.15, 1.3))


func _pick_target() -> ZombieEnemy:
	var best: ZombieEnemy = null
	var best_d := RANGE
	var space := get_world_3d().direct_space_state
	var from := _head.global_position
	for n in get_tree().get_nodes_in_group("enemies"):
		var z := n as ZombieEnemy
		if z == null or z.is_dead:
			continue
		var d := z.global_position.distance_to(global_position)
		if d >= best_d:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, z.global_position + Vector3(0, 1.1, 0), 1)
		if not space.intersect_ray(q).is_empty():
			continue
		best = z
		best_d = d
	return best


func _tracer(a: Vector3, b: Vector3) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var len := a.distance_to(b)
	bm.size = Vector3(0.015, 0.015, len)
	m.mesh = bm
	m.material_override = MaterialLib.get_emissive(Color(1.0, 0.8, 0.4), 5.0, 0.8)
	get_tree().current_scene.add_child(m)
	m.global_position = (a + b) * 0.5
	if len > 0.05:
		m.look_at(b, Vector3.UP)
	var tw := m.create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(m.queue_free)
