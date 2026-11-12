extends OWLocation
# GREYMILL. The county seat: a proper main street of brick and concrete blocks.
# North side: hardware store, pharmacy, police station, county office, bank
# and a boarded-up block; south side: apartments, the Rusty Nail bar, the
# general store, a motel. Crossroads with traffic lights where the village
# road comes in, a parking lot, alleys with dumpsters, a police roadblock and
# the wrecks of the evacuation.
#   pad x 236..372, z -290..-190. Main Street: z = -240 (sidewalks at
#   z -248..-244 and -236..-232). The village road crosses the south row at
#   x ~296..310, so that lot is the crossroads.

const Z0 := -240.0


func _init() -> void:
	id = "town"
	title = "GREYMILL"
	center = Vector2(300, Z0)
	pad = Rect2(236, -290, 136, 100)
	views = [[Vector3(240, 3, -240), Vector3(370, 1, -240)], [Vector3(252, 1.7, -258), Vector3(252, 1.4, -264)],
		[Vector3(306, 1.7, -258), Vector3(306, 1.4, -264)], [Vector3(303, 10, -205), Vector3(303, 0, -240)],
		[Vector3(272, 1.7, -224), Vector3(270, 1.4, -216)]]


func build() -> void:
	w._slab(Rect2(236, Z0 - 12, 136, 4))
	w._slab(Rect2(236, Z0 + 8, 136, 4))
	# --- north side (doors south onto Main Street)
	var north := [
		[244.0, "brick", "hardware", "HARDWARE", "store_tools"],
		[262.0, "plaster", "pharmacy", "PHARMACY", "store"],
		[280.0, "brick", "", "", ""],
		[298.0, "concrete", "police", "POLICE", "police"],
		[316.0, "concrete", "office", "COUNTY OFFICE", "office"],
		[334.0, "brick", "bank", "BANK", "office"],
		[352.0, "plaster", "", "", ""],
	]
	for b in north:
		var r := Rect2(b[0], Z0 - 28, 16, 16)
		_block(r, "s", b[1], b[2], b[3], b[4])
	# --- south side (doors north)
	var south := [
		[244.0, "plaster", "apartments", "APARTMENTS", "house"],
		[262.0, "brick", "bar", "RUSTY NAIL", "bar"],
		[314.0, "brick", "store", "GENERAL STORE", "store"],
		[332.0, "plaster", "motel", "MOTEL", "house"],
		[350.0, "concrete", "", "", ""],
	]
	for b in south:
		var r := Rect2(b[0], Z0 + 12, 16, 16)
		_block(r, "n", b[1], b[2], b[3], b[4])
	# --- the buys and stations
	var hardware := Rect2(244, Z0 - 28, 16, 16)
	buy(hardware, "n", 1, "ammo_box", "", "AMMO CACHE", 450, 0)
	var police := Rect2(298, Z0 - 28, 16, 16)
	buy(police, "n", 2, "weapon", "lmg", "RAZORBACK LMG", 3000, 1500)
	buy(police, "w", 2, "ammo_box", "", "AMMO CACHE", 450, 0)
	var bar := Rect2(262, Z0 + 12, 16, 16)
	buy(bar, "e", 1, "forge", "", "WEAPON FORGE", 5000, 0)
	w._place(w.SecondWindScript, Vector3(bar.position.x + 1.2, 0, bar.get_center().y + 3.0), 90.0)
	var gstore := Rect2(314, Z0 + 12, 16, 16)
	buy(gstore, "e", 1, "weapon", "rifle", "COMMANDO M14A", 1200, 600)
	w._place(load("res://scripts/world/supply_depot.gd") as GDScript, Vector3(290, 0, Z0 + 4), 180.0)
	# --- crossroads with lights, the parking lot behind the north row
	k("ext_traffic_light", 296.5, Z0 - 7.0, 90.0)
	k("ext_traffic_light", 309.5, Z0 + 7.0, -90.0)
	k("ext_stop_sign", 296, Z0 + 9, 0.0)
	w._slab(Rect2(262, Z0 - 50, 72, 20))
	for i in range(6):
		wreck(268 + i * 11.0, Z0 - 40.0, 180.0 + (i % 3) * 8.0)
	k("prop_water_tower", 342, Z0 - 44)
	k("prop_billboard", 248, Z0 + 42, 180.0)
	# --- alleys: dumpsters, bins, boxes
	for x in [261.0, 297.0, 333.0, 351.0]:
		w._prop("prop_dumpster", Vector3(x, 0, Z0 - 21), 90.0, Vector3(1.2, 1.4, 2.0), Vector3(0, 0.7, 0))
	for x in [279.0, 331.0, 348.0]:
		k("ext_trash_can", x, Z0 + 20)
		k("int_boxes", x + 0.2, Z0 + 23, 15.0)
	# --- main street: the evacuation that went wrong
	for c in [[258.0, Z0 - 2.0, 95.0], [276.0, Z0 + 3.0, 260.0], [322.0, Z0 - 1.0, 88.0], [344.0, Z0 + 2.5, 280.0]]:
		wreck(c[0], c[1], c[2])
	k("ext_bus_wreck", 286, Z0 + 1.0, 96.0)
	k("ext_police_car", 362, Z0 - 3, 120.0)
	k("ext_police_car", 358, Z0 + 4, 60.0)
	for z in [-6.0, 0.0, 6.0]:
		k("ext_barricade", 368, Z0 + z, 90.0)
	w._add_sandbags(Vector3(312, 0, Z0 - 6), 0.0)
	for x in [250.0, 270.0, 290.0, 320.0, 340.0, 360.0]:
		if int(x) % 40 == 10:
			k("ext_hydrant", x + 3, Z0 - 9.0)
		light(x, Z0 - 8.5)
		light(x + 9.0, Z0 + 8.5)
	for x in [256.0, 300.0, 344.0]:
		k("ext_trash_can", x, Z0 + 9.0)
	w._add_vehicle("truck", "SS-07 TRUCK", Vector3(352, 0.4, Z0 + 3), -90.0)


# One 16 x 16 town block: a shop/office with a sign and interior, or a
# boarded-up shell (kind "") that keeps its glass and stays shut.
func _block(r: Rect2, door: String, style: String, zone: String, label: String, kind: String) -> void:
	if zone == "":
		house(r, style, "", [], [], "flat")
		return
	w.zone_names[zone] = label
	var wins := [["e", 1], ["w", 1]]
	house(r, style, zone, [door, 1, 0], wins, "flat", "wood" if kind == "bar" else "tiles")
	shop_sign(r, door, 2, label)
	awning(r, door, 2)
	match kind:
		"store":
			furnish_store(r, door)
		"store_tools":
			furnish_store(r, door)
			kin("int_workbench", r, 3.0, 0.6 if door == "s" else r.size.y - 0.6, 180.0 if door == "s" else 0.0)
		"police":
			furnish_police(r, door)
		"office":
			furnish_office(r)
		"bar":
			furnish_bar(r, door)
		"house":
			furnish_house(Rect2(r.position, Vector2(8, 16)), door)
			furnish_house(Rect2(r.position + Vector2(8, 0), Vector2(8, 16)), door)
