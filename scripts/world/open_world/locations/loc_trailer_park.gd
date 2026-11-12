extends OWLocation
# PINE VIEW TRAILER PARK, off the farm road: a loop of mobile homes under the
# pines, picnic tables and a fire pit in the middle, a laundry shed, old
# cars up on blocks. One trailer still has the owner's guns on the wall.
#   pad x -178..-122, z 40..80.

const O := Vector2(-150, 60)


func _init() -> void:
	id = "trailers"
	title = "PINE VIEW TRAILERS"
	center = O
	pad = Rect2(-178, 40, 56, 40)
	views = [[Vector3(-176, 4, 60), Vector3(-140, 1, 60)], [Vector3(-162, 6, 86), Vector3(-150, 1, 58)]]


func build() -> void:
	w._slab(Rect2(O.x - 26, O.y - 4, 52, 8), "gravel")  # the loop drive
	# five trailers around the drive
	var spots := [[-14.0, -12.0, 0.0], [6.0, -12.0, 0.0], [-11.0, 12.0, 180.0], [7.0, 12.0, 180.0], [22.0, 0.0, 90.0]]
	for s in spots:
		k("ext_trailer", O.x + s[0], O.y + s[1], s[2])
	# the shed: the owner's guns
	var shed := Rect2(O.x - 26, O.y + 12, 8, 8)
	w.zone_names["trailer_shed"] = "LAUNDRY SHED"
	house(shed, "metal", "trailer_shed", ["e", 0, 0], [], "flat", "concrete")
	buy(shed, "w", 1, "weapon", "shotgun", "TRENCH-12 PUMP", 1500, 750)
	kin("int_boxes", shed, 1.2, 1.2, 0.0)
	kin("int_workbench", shed, 4.0, 7.4, 0.0)
	# middle: tables, fire pit, junk
	for p in [Vector2(-4, 0), Vector2(4, 2)]:
		k("ext_picnic_table", O.x + p.x, O.y + p.y - 6, p.x * 10.0)
	k("ext_campfire", O.x, O.y - 1)
	wreck(O.x + 16, O.y - 18, 20.0)
	wreck(O.x - 22, O.y - 16, 70.0)
	k("prop_tire_stack", O.x + 12, O.y + 18)
	k("ext_trash_can", O.x - 2, O.y + 8)
	k("prop_mailbox", O.x - 24, O.y - 4)
	for t in [Vector2(-28, -18), Vector2(-10, -20), Vector2(14, -22), Vector2(28, -14), Vector2(28, 16), Vector2(0, 20), Vector2(-28, 20)]:
		k("ext_pine", O.x + t.x, O.y + t.y, t.y * 7.0)
	light(O.x, O.y + 4, Color(1.0, 0.8, 0.5), 1.8)
