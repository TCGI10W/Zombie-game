class_name TruckModel
extends Node3D
## SS-07, the crew's truck (METRO 9 M9), as a model: the body, four doors, four wheels, the steering
## wheel, the tailgate and the START button from TruckKit, the headlights and tail lights. A double cab
## with the driver on the left (round 2, the user's Land Cruiser picture: docs/design/place_metro9.md).
## The driving truck (Truck, step 3) carries one of these: each wheel is a pivot (its suspension height
## and steer) holding a spin node (its roll) holding the wheel piece. Its frame: the nose at -Z, the
## origin on the ground under the middle of the wheelbase. `collide` adds the hull's boxes (truck.json)
## as a static body, so a crew member can stand on the bed of a parked model.

const WHEELS: Array[String] = ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]
## The doors, hinged on their front edges (each piece's origin is its hinge line's foot).
const DOORS: Array[String] = ["door_fl", "door_fr", "door_rl", "door_rr"]
## The column's tilt: the steering wheel's axis runs down and forward into the dash.
const STEER_TILT: float = -0.62

@export var lights_on: bool = false:
	set(value):
		lights_on = value
		if is_inside_tree():
			_apply_lights()
@export var collide: bool = false

var body: Node3D
## Each wheel's pivot (position, steer) and its spin node (roll about the axle).
var wheels: Array[Node3D] = []
var spins: Array[Node3D] = []
var doors: Dictionary = {}  # "door_fl" ... -> Node3D
var steer: Node3D
var tailgate: Node3D
var button: Node3D
var _lights: Array[Light3D] = []


func _ready() -> void:
	body = TruckKit.piece("body")
	TruckKit.sun_shadow(body, "body", true)
	add_child(body)
	for w: String in WHEELS:
		var pivot := Node3D.new()
		pivot.name = w.capitalize().replace(" ", "")
		pivot.position = TruckKit.point("body", w)
		add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin"
		pivot.add_child(spin)
		var wheel := TruckKit.piece("wheel")
		TruckKit.sun_shadow(wheel, "wheel", false)  # (under the hull's shadow)
		if w.ends_with("l"):
			wheel.rotation.y = PI  # the rim's dish faces out on both sides
		spin.add_child(wheel)
		wheels.append(pivot)
		spins.append(spin)
	for d: String in DOORS:
		var door := TruckKit.piece(d)
		TruckKit.sun_shadow(door, d, true)
		door.name = d.capitalize().replace(" ", "")
		door.position = TruckKit.point("body", d)
		add_child(door)
		doors[d] = door
	steer = TruckKit.piece("steer")
	TruckKit.sun_shadow(steer, "steer", false)
	for n: Node in steer.find_children("*", "MeshInstance3D", true, false):  # (its steel: dark worn metal)
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and m.resource_name == "trk_steel":
				mi.set_surface_override_material(i, TruckKit.material("steer_steel"))
	steer.position = TruckKit.point("body", "steer")
	steer.rotation.x = STEER_TILT
	add_child(steer)
	tailgate = TruckKit.piece("tailgate")
	TruckKit.sun_shadow(tailgate, "tailgate", true)
	tailgate.position = TruckKit.point("body", "tailgate")
	add_child(tailgate)
	# the steps under the tailgate's end and the chains holding it flat: shown while it's down (show_steps)
	var steps := TruckKit.piece("steps")
	TruckKit.sun_shadow(steps, "steps", false)
	steps.name = "Steps"
	steps.position = TruckKit.point("body", "steps")
	steps.visible = false
	add_child(steps)
	button = TruckKit.piece("button")
	TruckKit.sun_shadow(button, "button", false)
	button.position = TruckKit.point("body", "button")
	add_child(button)
	_build_lights()
	if collide:
		_build_hull()
	_apply_lights()


func _build_lights() -> void:
	for side: String in ["headlight_l", "headlight_r"]:
		var spot := SpotLight3D.new()
		spot.name = side.capitalize().replace(" ", "")
		spot.position = TruckKit.point("body", side) + Vector3(0.0, 0.0, -0.05)
		spot.rotation.x = deg_to_rad(-5.0)
		spot.light_color = Color(1.0, 0.86, 0.62)
		spot.light_energy = 4.0
		spot.spot_range = 30.0
		spot.spot_angle = 32.0
		spot.spot_attenuation = 0.8
		spot.shadow_enabled = false
		add_child(spot)
		_lights.append(spot)
	for side: String in ["tail_l", "tail_r"]:
		var omni := OmniLight3D.new()
		omni.name = side.capitalize().replace(" ", "")
		omni.position = TruckKit.point("body", side) + Vector3(0.0, 0.0, 0.15)
		omni.light_color = Color(1.0, 0.12, 0.06)
		omni.light_energy = 0.6 if side == "tail_r" else 0.0  # the left lamp is the cracked, dead one
		omni.omni_range = 1.4
		omni.shadow_enabled = false
		add_child(omni)
		_lights.append(omni)
	# (no light for the map screen: its own glow is enough, and a lamp there flared on the windscreen)


## The fold-down steps under the tailgate's end: shown while it's down (the driving Truck calls it).
func show_steps(on: bool) -> void:
	var steps := get_node_or_null("Steps") as Node3D
	if steps:
		steps.visible = on


## Swings a door open by `angle` radians (0 shut); its free edge goes outward on either side.
func set_door(door: String, angle: float) -> void:
	var n := doors.get(door) as Node3D
	if n:
		n.rotation.y = angle if door.ends_with("r") else -angle


## The map screen shows `tex` (a TruckMap's texture): unshaded and point-filtered like every CRT.
func set_screen(tex: Texture2D) -> void:
	for n: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and m.resource_name == "trk_crt":
				var screen := StandardMaterial3D.new()
				screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				screen.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				screen.albedo_texture = tex
				mi.set_surface_override_material(i, screen)


func _apply_lights() -> void:
	for l: Light3D in _lights:
		l.visible = lights_on
	TruckKit.set_lit(body, lights_on, PackedStringArray(["lens_head", "lens_tail"]))


## The hull's boxes from the manifest as one static body (the look round; the driving truck builds
## its own rigid hull and deck from the same boxes).
func _build_hull() -> void:
	var sb := StaticBody3D.new()
	sb.name = "Hull"
	add_child(sb)
	for b: Array in TruckKit.info("body").get("boxes", []):
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(b[3]), float(b[4]), float(b[5]))
		shape.shape = box
		shape.position = Vector3(float(b[0]), float(b[1]), float(b[2]))
		sb.add_child(shape)
