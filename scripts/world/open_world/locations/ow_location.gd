class_name OWLocation
extends RefCounted
# One place on The County map. Every location is its own script so it can be
# laid out, dressed and checked on its own (tools/location_shots.gd renders
# each one from its `views`). A location only describes itself: its id and
# name, its flat pad, the camera views used for review, and build(), which
# places kit pieces through the OpenWorld helpers below.
#
# Coordinates: world metres, the pad sits at y = 0. A furniture piece's front
# faces -Z at rot 0, so:  against the south wall facing in -> 0,
# north wall -> 180, west wall -> -90, east wall -> 90.

var w: OpenWorld
var id := ""
var title := ""
var center := Vector2.ZERO
var pad := Rect2()
var views: Array = []  # [[Vector3 eye, Vector3 look_at], ...]


func build() -> void:
	pass


# ------------------------------------------------------------- shortcuts
func k(piece: String, x: float, z: float, rot: float = 0.0, s: float = 1.0) -> Node3D:
	return w._kit(piece, Vector3(x, 0, z), rot, s)


func ky(piece: String, p: Vector3, rot: float = 0.0, s: float = 1.0) -> Node3D:
	return w._kit(piece, p, rot, s)


func at(r: Rect2, u: float, v: float) -> Vector3:
	return Vector3(r.position.x + u, 0, r.position.y + v)


func kin(piece: String, r: Rect2, u: float, v: float, rot: float = 0.0) -> Node3D:
	return w._kit(piece, at(r, u, v), rot)


func house(r: Rect2, style: String, zone: String, door: Array, wins: Array, roof: String, floor_kind: String = "wood") -> void:
	if zone != "":
		w.zone_names[zone] = w.zone_names.get(zone, zone.to_upper())
	w._building(r, style, zone, [door] if not door.is_empty() else [], wins, roof, floor_kind)


func buy(r: Rect2, side: String, slot: int, stype: String, wid: String, wtitle: String, cost: int, acost: int) -> void:
	w._buy(r, side, slot, stype, wid, wtitle, cost, acost)


func light(x: float, z: float, col: Color = Color(1.0, 0.82, 0.55), energy: float = 2.0) -> void:
	w._post_light(Vector3(x, 0, z), col, energy, 14.0)


func wreck(x: float, z: float, rot: float, kind: String = "prop_car_wreck") -> void:
	var sz := Vector3(1.9, 1.3, 4.3)
	w._prop(kind, Vector3(x, 0, z), rot, sz if kind == "prop_car_wreck" else Vector3.ZERO, Vector3(0, 0.65, 0))


func prop(name: String, x: float, z: float, rot: float = 0.0, col: Vector3 = Vector3.ZERO, s: float = 1.0) -> void:
	w._prop(name, Vector3(x, 0, z), rot, col, Vector3(0, col.y * 0.5, 0), s)


# Shop sign with the name lettered on it, on a wall slot facing out.
func shop_sign(r: Rect2, side: String, slot: int, text: String, col: Color = Color(0.12, 0.1, 0.09)) -> void:
	var out: Vector3 = OpenWorld.SIDE_OUT[side]
	var p: Vector3 = w._slot_pos(r, side, slot) + out * 0.25 + Vector3(0, 3.45, 0)
	var rot: float = OpenWorld.SIDE_ROT[side]
	w._kit("ext_sign_board", p, rot)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 56
	lbl.pixel_size = 0.0075
	lbl.modulate = col
	lbl.outline_size = 0
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	lbl.double_sided = false
	lbl.position = p + out * 0.08
	lbl.rotation_degrees.y = rot + 180.0
	w.add_child(lbl)


func awning(r: Rect2, side: String, slot: int) -> void:
	var out: Vector3 = OpenWorld.SIDE_OUT[side]
	w._kit("ext_awning", w._slot_pos(r, side, slot) + out * 0.15, OpenWorld.SIDE_ROT[side])


func porch(r: Rect2, side: String, slot: int) -> void:
	var out: Vector3 = OpenWorld.SIDE_OUT[side]
	w._kit("ext_porch", w._slot_pos(r, side, slot) + out * 0.15, OpenWorld.SIDE_ROT[side])


# ------------------------------------------------------------- furnishing
# Room sets. `door` is the side the doorway is on, so nothing blocks it.
func furnish_house(r: Rect2, door: String) -> void:
	var W := r.size.x
	var D := r.size.y
	var far := "n" if door == "s" else "s"
	var back_v := 0.8 if far == "n" else D - 0.8
	var back_rot := 180.0 if far == "n" else 0.0
	kin("int_kitchen", r, 2.0, back_v - (0.1 if far == "n" else -0.1), back_rot)
	kin("int_bed", r, W - 1.0, D * 0.5, -90.0 if true else 0.0)
	kin("int_sofa", r, 1.0, D * 0.5, -90.0)
	kin("int_table", r, W * 0.5, D * 0.5 + (1.6 if far == "s" else -1.6), 0.0)
	kin("int_chair", r, W * 0.5 - 0.5, D * 0.5 + (2.3 if far == "s" else -2.3), 180.0 if far == "s" else 0.0)
	kin("int_chair", r, W * 0.5 + 0.5, D * 0.5 + (1.0 if far == "s" else -1.0), 0.0 if far == "s" else 180.0)
	kin("int_bookshelf", r, W - 0.5, back_v, back_rot if far == "n" else 0.0)
	kin("int_boxes", r, 1.1, D * 0.5 + (2.8 if far == "n" else -2.8), 20.0)


func furnish_diner(r: Rect2) -> void:
	# booths along the north wall, a counter + stools mid-room, kitchen behind
	for i in range(3):
		kin("int_booth", r, 2.2 + i * 2.2, 0.55, 0.0)
	kin("int_counter", r, r.size.x * 0.5, r.size.y - 2.6, 180.0)
	for i in range(5):
		kin("int_stool", r, r.size.x * 0.5 - 1.6 + i * 0.8, r.size.y - 3.5)
	kin("int_kitchen", r, r.size.x * 0.5, r.size.y - 0.7, 0.0)
	kin("int_fridge_row", r, r.size.x - 0.6, r.size.y * 0.5, 90.0)


func furnish_store(r: Rect2, door: String) -> void:
	var cols := int((r.size.x - 4.0) / 3.2)
	for i in range(cols):
		for j in range(2):
			kin("int_store_shelf", r, 2.6 + i * 3.2, 4.0 + j * 4.4 if door == "s" else r.size.y - 4.0 - j * 4.4, 90.0)
	kin("int_fridge_row", r, 1.6, 0.6 if door == "s" else r.size.y - 0.6, 180.0 if door == "s" else 0.0)
	kin("int_counter", r, r.size.x - 2.6, r.size.y - 2.6 if door == "s" else 2.6, 90.0)
	kin("int_boxes", r, r.size.x - 1.0, 1.0 if door == "s" else r.size.y - 1.0, 35.0)


func furnish_police(r: Rect2, door: String) -> void:
	var back := 0.7 if door == "s" else r.size.y - 0.7
	kin("int_cell_bars", r, 4.0, 3.2 if door == "s" else r.size.y - 3.2, 0.0)
	kin("int_bed", r, 1.0, 1.4 if door == "s" else r.size.y - 1.4, 0.0)
	for i in range(3):
		kin("prop_desk", r, 2.0 + i * 3.0, r.size.y * 0.5 + (2.0 if door == "s" else -2.0), 0.0 if door == "s" else 180.0)
	for i in range(4):
		kin("int_filing_cabinet", r, r.size.x - 0.5, 2.0 + i * 0.6, 90.0)
	kin("prop_lockers", r, r.size.x - 3.0, back, 180.0 if door == "s" else 0.0)


func furnish_bar(r: Rect2, door: String) -> void:
	var back := 1.2 if door == "s" else r.size.y - 1.2
	kin("int_counter", r, r.size.x * 0.5, back + (1.2 if door == "s" else -1.2), 180.0 if door == "s" else 0.0)
	for i in range(5):
		kin("int_stool", r, r.size.x * 0.5 - 1.6 + i * 0.8, back + (2.2 if door == "s" else -2.2))
	for i in range(4):
		kin("int_keg", r, 1.0 + i * 0.6, back - (0.5 if door == "s" else -0.5))
	for p in [Vector2(3.0, 0.62), Vector2(8.0, 0.62), Vector2(5.5, 0.4)]:
		var v: float = r.size.y * p.y
		kin("int_table", r, p.x + 2.0, v, 20.0)
		kin("int_chair", r, p.x + 1.2, v, -90.0)
		kin("int_chair", r, p.x + 2.8, v, 90.0)


func furnish_barn(r: Rect2) -> void:
	for i in range(3):
		k("prop_hay_bale", r.position.x + 1.6, r.position.y + 2.5 + i * 2.2, 0.0)
	k("prop_hay_stack", r.end.x - 2.0, r.position.y + 3.0, 90.0)
	kin("int_workbench", r, r.size.x - 0.8, r.size.y * 0.5 + 3.0, 90.0)
	kin("int_tool_cabinet", r, r.size.x - 0.6, r.size.y * 0.5 + 5.0, 90.0)
	for i in range(3):
		k("prop_fence_wood", r.position.x + 4.0, r.position.y + 8.0 + i * 4.0, 90.0)  # stalls
	kin("int_boxes", r, 1.2, r.size.y - 1.2, 0.0)


func furnish_garage(r: Rect2) -> void:
	k("ext_bus_wreck", r.get_center().x - 2.0, r.get_center().y, 90.0)
	kin("int_workbench", r, 2.0, 0.6, 180.0)
	kin("int_workbench", r, 4.5, 0.6, 180.0)
	kin("int_tool_cabinet", r, 6.8, 0.5, 180.0)
	prop("prop_tire_stack", r.end.x - 1.0, r.end.y - 1.0)
	prop("prop_tire_stack", r.end.x - 2.1, r.end.y - 0.9)
	kin("prop_barrel", r, r.size.x - 1.0, 1.0)
	kin("int_boxes", r, 1.2, r.size.y - 1.0, 10.0)


func furnish_school(r: Rect2) -> void:
	kin("int_chalkboard", r, r.size.x * 0.5, 0.25, 180.0)
	kin("prop_desk", r, r.size.x * 0.5, 2.0, 180.0)
	for row in range(4):
		for c in range(2):
			kin("int_school_desk", r, 2.2 + c * 3.6, 4.0 + row * 2.4, 180.0)
	kin("int_bookshelf", r, r.size.x - 0.4, r.size.y - 1.5, 90.0)


func furnish_office(r: Rect2) -> void:
	for i in range(int(r.size.x / 3.0)):
		kin("prop_desk", r, 1.6 + i * 3.0, r.size.y * 0.5, 0.0)
	for i in range(3):
		kin("int_filing_cabinet", r, 0.5, 1.5 + i * 0.6, -90.0)
	kin("int_bookshelf", r, r.size.x - 0.4, 2.0, 90.0)


func furnish_plant_hall(r: Rect2) -> void:
	k("int_turbine", r.get_center().x - 5.0, r.get_center().y + 1.0, 0.0)
	k("int_turbine", r.get_center().x + 5.0, r.get_center().y + 1.0, 0.0)
	kin("int_control_panel", r, 4.0, r.size.y - 1.0, 0.0)
	for i in range(int(r.size.x / 4.0)):
		kin("int_pipes", r, 2.0 + i * 4.0, 0.4, 180.0)
	kin("int_boxes", r, r.size.x - 1.2, r.size.y - 1.2, 0.0)
