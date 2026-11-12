extends OWLocation
# OLD FARM. A working farm caught mid-harvest: the farmhouse with its porch,
# the big red barn (stalls, hay loft floor, tools), a machine shed, the silo
# and water tower, a fenced corn field to the south with a dirt track through
# it, hay everywhere and the tractor left in the yard.
#   pad x -330..-230, z 112..208. Dirt roads: south track runs north up
#   x ~ -287 into the yard; the east road leaves the yard at z ~ 153-160.

const O := Vector2(-280, 160)


func _init() -> void:
	id = "farm"
	title = "OLD FARM"
	center = O
	pad = Rect2(-330, 112, 100, 96)
	views = [[Vector3(-300, 6, 158), Vector3(-280, 1, 130)], [Vector3(-304, 1.7, 130), Vector3(-300, 1.4, 126)],
		[Vector3(-270, 1.7, 145), Vector3(-270, 1.4, 132)], [Vector3(-320, 8, 214), Vector3(-284, 0, 186)]]


func build() -> void:
	# --- farmhouse: porch on the yard side, furnished
	var hs := Rect2(O.x - 30, O.y - 36, 12, 8)
	w.zone_names["farmhouse"] = "FARMHOUSE"
	house(hs, "siding_white", "farmhouse", ["s", 1, 0], [["n", 1], ["w", 0], ["e", 1]], "gable", "wood")
	porch(hs, "s", 1)
	furnish_house(hs, "s")
	buy(hs, "n", 0, "weapon", "revolver", ".44 HAND CANNON", 1750, 875)
	w._skull(Vector3(hs.position.x + 1.2, 2.3, hs.position.y + 6.5), 90.0)
	k("prop_mailbox", hs.position.x - 3, hs.end.y + 4)
	k("ext_picnic_table", hs.position.x + 3, hs.end.y + 6, 10.0)
	# --- the barn: big doors west, stalls, hay, tools
	var barn := Rect2(O.x + 4, O.y - 32, 12, 20)
	w.zone_names["barn"] = "BARN"
	house(barn, "siding_red", "barn", ["w", 2, 0], [["e", 1], ["e", 3], ["n", 1], ["s", 1]], "tin", "wood")
	furnish_barn(barn)
	buy(barn, "e", 2, "weapon", "shotgun", "TRENCH-12 PUMP", 1500, 750)
	w._place(w.SecondWindScript, Vector3(barn.position.x + 6, 0, barn.end.y - 1.2), 180.0)
	# --- machine shed (open front) with the farm's tools
	var shed := Rect2(O.x + 24, O.y - 44, 12, 8)
	house(shed, "metal", "", ["s", 1, 0], [], "tin", "concrete")
	kin("int_workbench", shed, 3.0, 0.6, 180.0)
	kin("int_tool_cabinet", shed, 9.5, 0.5, 180.0)
	k("prop_barrel", shed.position.x + 1.0, shed.position.y + 6.8)
	k("prop_barrel", shed.position.x + 1.8, shed.position.y + 7.0)
	# --- silo, water tower, tractor, hay
	k("prop_silo", O.x + 28, O.y - 22)
	k("prop_water_tower", O.x - 42, O.y + 2)
	k("prop_tractor", O.x - 4, O.y - 10, 35.0)
	for p in [Vector2(-10, 4), Vector2(-7, 6), Vector2(20, -6), Vector2(22, -3), Vector2(-14, -18), Vector2(34, 6)]:
		k("prop_hay_bale", O.x + p.x, O.y + p.y, p.x * 13.0)
	k("prop_hay_stack", O.x + 30, O.y - 6, 10.0)
	k("prop_hay_stack", O.x - 18, O.y - 4, -20.0)
	# --- yard fences + gate posts, scarecrow-ish wreck
	w._fence_line(O + Vector2(-46, -46), O + Vector2(10, -46))
	w._fence_line(O + Vector2(-46, -46), O + Vector2(-46, 10))
	wreck(O.x - 24, O.y - 6, 140.0)
	# --- the corn field south of the yard, a dirt track through the middle
	w._fence_line(O + Vector2(-44, 12), O + Vector2(36, 12))
	w._fence_line(O + Vector2(-44, 12), O + Vector2(-44, 44))
	w._fence_line(O + Vector2(36, 12), O + Vector2(36, 44))
	w._fence_line(O + Vector2(-44, 44), O + Vector2(36, 44))
	for row in range(7):
		for c in range(9):
			var x := O.x - 40 + c * 8.6
			if absf(x - (O.x - 4)) < 5.0:
				continue  # the track
			k("ext_corn", x + 4.0, O.y + 16 + row * 4.0, 0.0)
	for t in [Vector2(-50, -30), Vector2(-52, -10), Vector2(40, -40), Vector2(44, 20)]:
		k("ext_pine", O.x + t.x, O.y + t.y, t.x * 3.0)
	for b in [Vector2(-34, -20), Vector2(-20, -42), Vector2(12, -40)]:
		k("ext_bush", O.x + b.x, O.y + b.y)
	light(O.x - 10, O.y - 24, Color(1.0, 0.8, 0.5), 1.8)
	light(O.x + 18, O.y - 10, Color(1.0, 0.8, 0.5), 1.8)
	w._add_vehicle("truck", "SS-07 TRUCK", Vector3(O.x + 6, 0.4, O.y - 4), 90.0)
