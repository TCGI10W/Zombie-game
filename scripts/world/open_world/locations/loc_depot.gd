extends OWLocation
# BUS DEPOT (start). The county bus line's yard at the crossroads: a gas
# station with its kiosk, the diner where survivors held out (start room), the
# bus garage, a yard of dead buses, and abandoned cars along the street.
#   pad x -44..44, z -34..36; the street runs east-west along z = 30.


func _init() -> void:
	id = "depot"
	title = "BUS DEPOT"
	center = Vector2(0, 0)
	pad = Rect2(-44, -34, 88, 70)
	views = [[Vector3(-8, 6, 30), Vector3(10, 1, -10)], [Vector3(10, 1.7, -12), Vector3(14, 1.4, -20)],
		[Vector3(-30, 5, -30), Vector3(-20, 1, -10)], [Vector3(36, 6, 30), Vector3(30, 1, 0)]]


func build() -> void:
	w._slab(Rect2(-44, -34, 88, 58))  # the lot (the street strip is a road)
	# --- diner: the start room
	var diner := Rect2(6, -22, 16, 12)
	w.zone_names["diner"] = "DINER"
	house(diner, "plaster", "diner", ["n", 1, 0], [["s", 1], ["s", 2], ["e", 1], ["w", 1]], "flat", "tiles")
	furnish_diner(diner)
	shop_sign(diner, "n", 2, "DINER")
	awning(diner, "n", 2)
	buy(diner, "w", 2, "weapon", "smg", "KURZ-9 SMG", 1000, 500)
	buy(diner, "e", 2, "ammo_box", "", "AMMO CACHE", 450, 0)
	k("ext_trash_can", 23.0, -9.0)
	prop("prop_dumpster", 24.5, -20.0, 90.0, Vector3(1.2, 1.4, 2.0))
	# --- gas station: canopy, pumps, kiosk shop
	k("prop_gas_canopy", -22, -14)
	for x in [-25.0, -19.0]:
		k("prop_gas_pump", x, -14)
	var kiosk := Rect2(-40, -26, 8, 8)
	w.zone_names["kiosk"] = "GAS KIOSK"
	house(kiosk, "concrete", "kiosk", ["e", 1, 0], [["n", 0]], "flat", "tiles")
	kin("int_store_shelf", kiosk, 3.0, 4.0, 0.0)
	kin("int_fridge_row", kiosk, 4.0, 0.6, 180.0)
	kin("int_counter", kiosk, 4.0, 6.6, 0.0)
	shop_sign(kiosk, "e", 0, "GAS")
	k("prop_billboard", -36, 20, 20.0)
	k("ext_stop_sign", -6, 24.5, 180.0)
	# --- bus garage (mystery crate, rifle)
	var garage := Rect2(-16, 2, 20, 12)
	w.zone_names["garage"] = "BUS GARAGE"
	house(garage, "metal", "garage", ["s", 2, 0], [["n", 1], ["n", 3], ["w", 1]], "tin", "concrete")
	furnish_garage(garage)
	w._place(w.CrateScript, Vector3(-12.5, 0, 12.6), 0.0)
	buy(garage, "e", 1, "weapon", "rifle", "COMMANDO M14A", 1200, 600)
	shop_sign(garage, "s", 2, "COUNTY TRANSIT")
	# --- bus yard: dead buses behind a fence
	for i in range(3):
		k("ext_bus_wreck", 30.0 + i * 4.5, -4.0 + (i % 2) * 2.0, 4.0 - i * 3.0)
	w._fence_line(Vector2(26, -18), Vector2(44, -18), "prop_fence_metal")
	w._fence_line(Vector2(44, -18), Vector2(44, 14), "prop_fence_metal")
	# --- the furnace stands in the lot under a lamp, by the survivors' barricade
	w._place(w.FurnaceScript, Vector3(-4, 0, -6), 0.0)
	k("ext_barricade", -6, 18, 10.0)
	k("ext_barricade", 8, 19, -8.0)
	w._add_sandbags(Vector3(1, 0, 17), 0.0)
	k("prop_bus_stop", 14, 24.5, 180.0)
	for p in [Vector2(-30, 4), Vector2(26, 20), Vector2(0, -26), Vector2(-12, -2)]:
		light(p.x, p.y)
	# --- abandoned cars along the street + a police cruiser
	for c in [[-34.0, 26.0, 88.0], [-20.0, 26.5, 95.0], [24.0, 26.0, 270.0], [38.0, 25.0, 80.0]]:
		wreck(c[0], c[1], c[2])
	k("ext_police_car", 30, 16, 200.0)
	prop("prop_traffic_cone", 27, 19)
	prop("prop_traffic_cone", 28.5, 20.5)
	for b in [[-42.0, -32.0], [42.0, -32.0], [-42.0, 0.0]]:
		k("ext_bush", b[0], b[1])
	w._add_crate_stack(Vector3(-30, 0, -2), 2)
	k("int_boxes", -27.5, -3.0, 20.0)
	w._add_vehicle("truck", "SS-07 TRUCK", Vector3(-24, 0.4, 10), 0.0)
