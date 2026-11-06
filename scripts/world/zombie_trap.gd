extends Node3D
# Bone-spike trap built by zombies on a commander's order. Players standing in
# it bleed and are slowed. It rots away after a while; explosions destroy it.

const RADIUS := 1.6
var tier: int = 3
var life: float = 45.0
var _tick: float = 0.0


func _ready() -> void:
	add_to_group("zombie_traps")
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.78, 0.72, 0.6)
	bone.roughness = 0.8
	var blood := MaterialLib.get_emissive(Color(0.45, 0.02, 0.02), 0.2, 0.9)
	for i in range(14):
		var a := TAU * float(i) / 14.0 + randf_range(-0.2, 0.2)
		var r := randf_range(0.2, RADIUS - 0.2)
		var spike := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = randf_range(0.04, 0.08)
		cm.height = randf_range(0.35, 0.75)
		cm.radial_segments = 5
		cm.rings = 1
		spike.mesh = cm
		spike.material_override = bone if i % 3 != 0 else blood
		spike.position = Vector3(cos(a) * r, cm.height * 0.45, sin(a) * r)
		spike.rotation = Vector3(randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35))
		add_child(spike)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RADIUS - 0.08
	tm.outer_radius = RADIUS
	ring.mesh = tm
	ring.material_override = MaterialLib.get_emissive(Color(0.8, 0.1, 0.05), 1.2, 0.6)
	ring.position.y = 0.03
	add_child(ring)
	FX.blood_decal(global_position + Vector3(0, 0.02, 0), Vector3.UP, RADIUS * 2.0)
	GameState.play_sfx("gore_splat", -4.0, 0.7)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_tick -= delta
	# Each client hurts its own player
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or p.get("is_dead") or p.get("is_downed"):
		return
	var off := p.global_position - global_position
	off.y = 0.0
	if off.length() < RADIUS:
		p.set("trap_slow_t", 0.6)
		if _tick <= 0.0:
			_tick = 0.5
			p.take_damage((6.0 + 2.0 * float(tier)) * GameState.diff_dmg_mult(), global_position)


func blast(pos: Vector3, radius: float) -> void:
	if pos.distance_to(global_position) < radius + RADIUS:
		queue_free()
