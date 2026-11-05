extends Area3D
# A floating power-up dropped by a zombie. The wave manager applies its effect
# when the player walks through it.

signal collected(kind: String)

const LIFETIME := 26.0
const BLINK_TIME := 7.0

const KINDS := {
	"max_ammo": {"label": "MAX AMMO", "color": Color(1.0, 0.80, 0.22)},
	"insta_kill": {"label": "INSTA-KILL", "color": Color(0.92, 0.94, 1.0)},
	"double_points": {"label": "DOUBLE POINTS", "color": Color(0.30, 1.0, 0.42)},
	"nuke": {"label": "NUKE", "color": Color(1.0, 0.36, 0.14)},
	"carpenter": {"label": "CARPENTER", "color": Color(0.95, 0.72, 0.4)},
	"fire_sale": {"label": "FIRE SALE", "color": Color(1.0, 0.28, 0.22)},
}

var kind: String = "max_ammo"
var _life: float = LIFETIME
var _t: float = 0.0
var _visual: Node3D
var _taken: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # Player
	monitoring = true

	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.15
	cs.shape = sphere
	cs.position.y = 0.9
	add_child(cs)

	var info: Dictionary = KINDS.get(kind, KINDS["max_ammo"])
	var col: Color = info["color"]

	_visual = Node3D.new()
	_visual.position.y = 1.0
	add_child(_visual)
	_build_icon(col)

	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.4
	light.omni_range = 4.5
	light.position.y = 1.0
	add_child(light)

	var lbl := Label3D.new()
	lbl.text = info["label"]
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 30
	lbl.outline_size = 12
	lbl.modulate = col.lightened(0.25)
	lbl.position.y = 1.7
	lbl.pixel_size = 0.0038
	add_child(lbl)

	body_entered.connect(_on_body_entered)


func _build_icon(col: Color) -> void:
	var mat := MaterialLib.get_emissive(col, 4.5, 0.95)
	match kind:
		"max_ammo":
			# Stack of three rounds
			for i in range(3):
				var shell := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.07
				cm.bottom_radius = 0.09
				cm.height = 0.5
				shell.mesh = cm
				shell.material_override = mat
				shell.position.x = (float(i) - 1.0) * 0.22
				_visual.add_child(shell)
		"insta_kill":
			# Skull-ish: sphere head with dark eye sockets
			var head := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.3
			sm.height = 0.56
			head.mesh = sm
			head.material_override = mat
			_visual.add_child(head)
			for side in [-1.0, 1.0]:
				var eye := MeshInstance3D.new()
				var em := SphereMesh.new()
				em.radius = 0.08
				em.height = 0.16
				eye.mesh = em
				eye.material_override = MaterialLib.get_emissive(Color(0.05, 0.0, 0.0), 0.2)
				eye.position = Vector3(side * 0.11, 0.04, 0.24)
				_visual.add_child(eye)
		"double_points":
			# Two overlapping coins
			for i in range(2):
				var coin := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.26
				cm.bottom_radius = 0.26
				cm.height = 0.07
				coin.mesh = cm
				coin.material_override = mat
				coin.rotation.x = deg_to_rad(90.0)
				coin.position = Vector3((float(i) - 0.5) * 0.24, (float(i) - 0.5) * 0.12, float(i) * 0.05)
				_visual.add_child(coin)
		"carpenter":
			# Claw hammer
			var handle := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = 0.045
			hm.bottom_radius = 0.05
			hm.height = 0.62
			handle.mesh = hm
			handle.material_override = mat
			handle.position.y = -0.08
			_visual.add_child(handle)
			var head := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.36, 0.11, 0.12)
			head.mesh = bm
			head.material_override = mat
			head.position.y = 0.24
			_visual.add_child(head)
		"fire_sale":
			# Price tag with a flame on top
			var tag := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.38, 0.5, 0.06)
			tag.mesh = tm
			tag.material_override = mat
			_visual.add_child(tag)
			var flame := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.13
			cm.height = 0.3
			flame.mesh = cm
			flame.material_override = MaterialLib.get_emissive(Color(1.0, 0.55, 0.1), 5.0, 0.9)
			flame.position.y = 0.4
			_visual.add_child(flame)
		_:
			# Nuke: bomb body + fin ring
			var body := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.17
			cap.height = 0.62
			body.mesh = cap
			body.material_override = mat
			body.rotation.z = deg_to_rad(90.0)
			_visual.add_child(body)
			var fin := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.12
			tm.outer_radius = 0.2
			fin.mesh = tm
			fin.material_override = mat
			fin.rotation.z = deg_to_rad(90.0)
			fin.position.x = -0.32
			_visual.add_child(fin)


func _process(delta: float) -> void:
	_t += delta
	_life -= delta
	_visual.rotation.y += delta * 2.4
	_visual.position.y = 1.0 + sin(_t * 3.2) * 0.13
	if _life < BLINK_TIME:
		# Blink faster as it is about to vanish
		var rate := lerpf(3.0, 9.0, 1.0 - _life / BLINK_TIME)
		visible = sin(_t * rate * TAU) > -0.3
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	collected.emit(kind)
	queue_free()
