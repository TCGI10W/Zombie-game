extends Node3D
# A locked steel shutter between zones. Buying it opens a new area
# (and the windows in it start spawning zombies).
# Origin on the floor at the middle of the doorway; the door spans local X.

signal opened(zone_id: String)

var zone_id: String = ""
var title: String = "AREA"
var cost: int = 750
var width: float = 3.0
var height: float = 3.2
var interact_radius: float = 3.0
var _body: StaticBody3D
var _visual: Node3D


func _ready() -> void:
	add_to_group("wall_stations")
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.3)
	cs.shape = bs
	cs.position.y = height * 0.5
	_body.add_child(cs)
	add_child(_body)

	_visual = Node3D.new()
	add_child(_visual)
	var steel := MaterialLib.get_pbr("rusted_metal", 0.5, Color(0.55, 0.52, 0.5), 0.7, 0.7)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, height, 0.24)
	slab.mesh = bm
	slab.material_override = steel
	slab.position.y = height * 0.5
	_visual.add_child(slab)
	# Shutter ribs
	for i in range(7):
		var rib := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(width, 0.06, 0.3)
		rib.mesh = rm
		rib.material_override = steel
		rib.position.y = 0.3 + float(i) * 0.42
		_visual.add_child(rib)
	# Hazard stripes along the bottom
	var yellow := MaterialLib.get_emissive(Color(1.0, 0.75, 0.1), 1.2)
	for i in range(int(width / 0.5)):
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.22, 0.3, 0.32)
		stripe.mesh = sm
		stripe.material_override = yellow
		stripe.position = Vector3(-width * 0.5 + 0.25 + float(i) * 0.5, 0.2, 0)
		stripe.rotation.z = deg_to_rad(35)
		_visual.add_child(stripe)

	for side in [1.0, -1.0]:
		var lbl := Label3D.new()
		lbl.text = "%s\n%d PTS" % [title, cost]
		lbl.font_size = 40
		lbl.outline_size = 10
		lbl.pixel_size = 0.005
		lbl.modulate = Color(1.0, 0.85, 0.4)
		lbl.position = Vector3(0, height * 0.62, 0.2 * side)
		if side < 0.0:
			lbl.rotation.y = PI
		_visual.add_child(lbl)

	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.55, 0.15)
	lamp.light_energy = 1.2
	lamp.omni_range = 4.0
	lamp.position = Vector3(0, height + 0.3, 0)
	_visual.add_child(lamp)


func get_prompt(_player: Node3D) -> String:
	return "[E] OPEN %s  —  %d PTS" % [title, cost]


var _opened: bool = false


func try_purchase(player: Node3D) -> void:
	if not _opened and GameState.try_pay(player, cost):
		Net.world(self, "open")


func net_apply(action: String, _args: Array) -> void:
	if action == "open":
		open()


func open() -> void:
	if _opened:
		return
	_opened = true
	remove_from_group("wall_stations")
	_body.queue_free()
	GameState.play_sfx("door_open", 0.0, 1.0)
	var tw := create_tween()
	tw.tween_property(_visual, "position:y", height + 0.4, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_visual.queue_free)
	opened.emit(zone_id)
