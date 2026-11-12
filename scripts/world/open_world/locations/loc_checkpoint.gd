extends OWLocation
# ARMY CHECKPOINT on the depot - Hollow Creek road: where the evacuation was
# meant to be held. Jersey barriers and sandbags funnel the road, a tent
# camp beside it, floodlights, abandoned police cars, crates of supplies.
#   pad x 92..128, z 74..110; the road runs through it diagonally (NE).

const O := Vector2(110, 92)


func _init() -> void:
	id = "checkpoint"
	title = "ARMY CHECKPOINT"
	center = O
	pad = Rect2(92, 74, 36, 36)
	views = [[Vector3(96, 4, 76), Vector3(116, 1, 98)], [Vector3(126, 3, 82), Vector3(108, 1, 96)]]


func build() -> void:
	# the funnel across the road (road dir ~ (0.75, 0.66))
	for p in [Vector2(-6, 6), Vector2(-2, 9), Vector2(6, -6), Vector2(2, -9)]:
		w._prop("prop_jersey_barrier", Vector3(O.x + p.x, 0, O.y + p.y), -48.0, Vector3(2.0, 1.0, 0.6), Vector3(0, 0.5, 0))
	w._add_sandbags(Vector3(O.x - 8, 0, O.y + 2), -48.0)
	w._add_sandbags(Vector3(O.x + 8, 0, O.y - 2), -48.0)
	k("ext_barricade", O.x + 1, O.y + 1, -48.0)
	# tent camp on the north-west side of the road
	for i in range(3):
		k("ext_tent", O.x - 12 + i * 4.5, O.y - 10 + i * 1.0, 40.0)
	k("ext_campfire", O.x - 8, O.y - 4)
	k("int_table", O.x - 4, O.y - 12, 40.0)
	w._spawn_station("ammo_box", "", "ARMY AMMO", 450, 0, Color(1.0, 0.78, 0.2), Vector3(O.x - 4, 1.0, O.y - 12), 40.0)
	k("int_boxes", O.x - 1, O.y - 14, 10.0)
	w._add_crate_stack(Vector3(O.x - 14, 0, O.y - 2), 2)
	# vehicles left behind
	k("ext_police_car", O.x + 12, O.y + 6, 130.0)
	wreck(O.x + 10, O.y + 14, 40.0)
	k("ext_bus_wreck", O.x - 6, O.y + 16, 100.0)
	for p in [Vector2(-14, -12), Vector2(14, 10)]:
		light(O.x + p.x, O.y + p.y, Color(0.9, 0.95, 1.0), 2.4)
	for p in [Vector2(-16, 14), Vector2(16, -14)]:
		k("ext_pine", O.x + p.x, O.y + p.y)
