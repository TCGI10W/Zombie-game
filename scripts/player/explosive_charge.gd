extends "res://scripts/player/frag_grenade.gd"
# Supply Depot explosives, built on the frag grenade's blast:
#  - "c4":   tossed a few metres, sticks where it lands, a red light blinks;
#            goes off when its owner holds [T].
#  - "mine": dropped at your feet, arms after 1 s, then any zombie within
#            2.2 m sets it off.

var mode: String = "c4"
var _armed_t: float = 1.0
var _stuck: bool = false
var _lamp_t: float = 0.0
var _blink: OmniLight3D


func _ready() -> void:
	super._ready()
	for c in get_children():
		if c is OmniLight3D:
			_blink = c
	_fuse = 1.0e9 # never on a timer
	if mode == "c4":
		radius = 7.5
		damage = 900.0
	else:
		radius = 5.0
		damage = 650.0
		freeze = true
	add_to_group("placed_charges")
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(func(_b: Node):
		if mode == "c4" and not _stuck:
			_stuck = true
			set_deferred("freeze", true)
	)
	# Visual: a brick with a blinking light (C4) or a flat disc (mine)
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = false
	var body := MeshInstance3D.new()
	if mode == "c4":
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 0.08, 0.12)
		body.mesh = bm
		body.material_override = MaterialLib.get_pbr("burlap", 2.0, Color(0.55, 0.5, 0.36), 0.0, 0.9, false)
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.14
		cm.bottom_radius = 0.16
		cm.height = 0.06
		body.mesh = cm
		body.material_override = MaterialLib.get_pbr("rusted_metal", 2.0, Color(0.3, 0.33, 0.28), 0.6, 0.6, false)
	add_child(body)


func _physics_process(delta: float) -> void:
	_lamp_t += delta
	if _blink:
		_blink.light_energy = 1.4 if fmod(_lamp_t, 0.8) < 0.12 else 0.0
	if mode != "mine":
		return
	_armed_t -= delta
	if _armed_t > 0.0:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var z := node as ZombieEnemy
		if z and not z.is_dead and z.global_position.distance_to(global_position) < 2.2:
			_explode()
			return


func detonate() -> void:
	if is_inside_tree():
		_explode()
