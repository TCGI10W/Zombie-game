extends OWLocation
# HOLLOW CREEK. A one-street village: a row of family houses with porches and
# mailboxes along both sides of Main Street, the schoolhouse and its yard, a
# corner shop, a picnic green, parked and crashed cars, and the pines behind.
#   pad x 214..310, z 172..272. Village street: z = 220, x 214..310.
#   Roads in from the north-west (depot, x ~222..240 at the north row)
#   and out to the north-east (town, x ~262..274 at the north row), so the
#   north row leaves gaps there.

const O := Vector2(260, 220)


func _init() -> void:
	id = "village"
	title = "HOLLOW CREEK"
	center = O
	pad = Rect2(214, 172, 96, 100)
	views = [[Vector3(222, 3, 222), Vector3(300, 1, 214)], [Vector3(237, 1.7, 246), Vector3(234, 1.2, 240)],
		[Vector3(300, 4, 236), Vector3(304, 1, 214)], [Vector3(250, 10, 270), Vector3(260, 0, 220)]]


func build() -> void:
	var styles := ["siding_white", "siding_blue", "siding_red", "plaster", "siding_white", "siding_blue"]
	# south row: six houses, doors north onto Main Street
	var south := [218.0, 232.0, 246.0, 260.0, 274.0, 288.0]
	for i in range(south.size()):
		var r := Rect2(south[i], 236, 8, 12)
		var zone := ""
		if i == 1:
			zone = "house_a"
			w.zone_names[zone] = "GREEN HOUSE"
		elif i == 4:
			zone = "house_b"
			w.zone_names[zone] = "CORNER HOUSE"
		house(r, styles[i], zone, ["n", 0, 0], [["w", 1], ["e", 1]], "gable", "wood")
		porch(r, "n", 0)
		furnish_house(r, "n")
		k("prop_mailbox", r.position.x + 6.0, r.position.y - 4.5)
		w._fence_line(Vector2(r.position.x - 1, r.end.y + 6), Vector2(r.end.x + 5, r.end.y + 6))
		if i == 1:
			buy(r, "w", 2, "ammo_box", "", "AMMO CACHE", 450, 0)
		if i == 4:
			w._skull(Vector3(r.get_center().x, 0.9, r.get_center().y), 45.0)
	# north row: houses + the corner shop, gaps for the two roads
	var shop := Rect2(244, 188, 12, 12)
	w.zone_names["corner_shop"] = "CORNER SHOP"
	house(shop, "brick", "corner_shop", ["s", 1, 0], [["e", 1]], "flat", "tiles")
	furnish_store(shop, "s")
	shop_sign(shop, "s", 2, "GROCERY")
	awning(shop, "s", 1)
	for i in range(2):
		var r := Rect2(278 + i * 14, 188, 8, 12)
		house(r, styles[i + 2], "", ["s", 1, 0], [["w", 1]], "gable", "wood")
		porch(r, "s", 1)
		furnish_house(r, "s")
	# the schoolhouse at the east end
	var school := Rect2(302, 204, 8, 16)
	w.zone_names["school"] = "SCHOOLHOUSE"
	house(school, "siding_red", "school", ["w", 1, 0], [["e", 1], ["e", 2], ["n", 1]], "gable", "wood")
	furnish_school(school)
	buy(school, "e", 3, "weapon", "sniper", "LONGSHOT .50", 3500, 1750)
	shop_sign(school, "w", 2, "SCHOOL")
	# the green: picnic tables, a bench, the bus stop
	for p in [Vector2(-6, -10), Vector2(2, -12), Vector2(-14, -12)]:
		k("ext_picnic_table", O.x + p.x + 30, O.y + p.y - 8, p.x * 9.0)
	w._prop("prop_bench", Vector3(O.x + 22, 0, O.y - 6), 0.0, Vector3.ZERO, Vector3.ZERO)
	k("prop_bus_stop", O.x + 6, O.y - 6, 0.0)
	# street life
	for c in [[226.0, 224.0, 85.0], [254.0, 216.0, 270.0], [284.0, 225.0, 100.0]]:
		wreck(c[0], c[1], c[2])
	k("ext_hydrant", 240, 230)
	k("ext_hydrant", 282, 230)
	k("ext_stop_sign", 300, 226, 90.0)
	for x in [222.0, 250.0, 280.0, 306.0]:
		light(x, 230)
	for t in [Vector2(216, 262), Vector2(232, 268), Vector2(262, 266), Vector2(296, 268), Vector2(312, 250), Vector2(214, 196)]:
		k("ext_pine", t.x, t.y, t.x)
	for b in [Vector2(230, 234), Vector2(258, 234), Vector2(286, 234), Vector2(276, 202)]:
		k("ext_bush", b.x, b.y)
	k("ext_trash_can", 257, 202)
