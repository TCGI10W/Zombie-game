extends OWLocation
# POWER PLANT. The county's power station: the turbine hall (two turbines,
# control desk, pipework, the generator that turns the power back on), the
# admin block, a fenced substation full of transformers, a cooling stack,
# cable spools and fuel, and the pylon line marching off toward Greymill.
#   pad x -312..-208, z -312..-208. Road in from the east at z ~ -262;
#   the dirt road leaves north-west (x ~ -266..-259 at z -250).

const O := Vector2(-260, -260)


func _init() -> void:
	id = "plant"
	title = "POWER PLANT"
	center = O
	pad = Rect2(-312, -312, 104, 104)
	views = [[Vector3(-230, 6, -262), Vector3(-262, 2, -282)], [Vector3(-262, 1.7, -279), Vector3(-262, 1.4, -284)],
		[Vector3(-300, 6, -240), Vector3(-280, 1, -252)], [Vector3(-291, 1.7, -295), Vector3(-298, 1.2, -297)]]


func build() -> void:
	w._slab(Rect2(O.x - 50, O.y - 50, 100, 100))
	# --- turbine hall (generator inside)
	var hall := Rect2(O.x - 12, O.y - 28, 24, 12)
	w.zone_names["plant"] = "TURBINE HALL"
	house(hall, "metal", "plant", ["s", 2, 0], [["w", 1], ["e", 1], ["n", 1], ["n", 4]], "tin", "concrete")
	k("int_turbine", hall.position.x + 6.5, hall.position.y + 7.0, 0.0)
	k("int_turbine", hall.position.x + 17.5, hall.position.y + 7.0, 0.0)
	kin("int_control_panel", hall, 20.0, 1.0, 180.0)
	for i in [0, 1]:
		kin("int_pipes", hall, 2.0 + i * 4.0, 0.4, 180.0)
	w._place(w.GeneratorScript, Vector3(O.x, 0, O.y - 25.5), 0.0)
	buy(hall, "w", 2, "ammo_box", "", "AMMO CACHE", 450, 0)
	w._skull(Vector3(hall.end.x - 1.0, 2.4, hall.position.y + 3.0), -90.0)
	shop_sign(hall, "s", 4, "TURBINE HALL")
	# --- admin block
	var admin := Rect2(O.x - 40, O.y - 40, 12, 8)
	w.zone_names["plant_admin"] = "PLANT OFFICE"
	house(admin, "concrete", "plant_admin", ["e", 1, 0], [["n", 1], ["w", 0]], "flat", "tiles")
	furnish_office(admin)
	shop_sign(admin, "e", 0, "OFFICE")
	# --- substation yard
	for r in range(2):
		for i in range(4):
			k("prop_transformer", O.x - 30 + i * 6, O.y + 10 + r * 7)
	w._fence_line(O + Vector2(-36, 4), O + Vector2(-36, 26), "prop_fence_metal")
	w._fence_line(O + Vector2(-36, 26), O + Vector2(-6, 26), "prop_fence_metal")
	w._fence_line(O + Vector2(-6, 4), O + Vector2(-6, 26), "prop_fence_metal")
	k("prop_power_pylon", O.x - 20, O.y + 32, 90.0)
	# --- cooling stack, fuel, cable spools, pipes
	k("prop_silo", O.x + 30, O.y - 30, 0.0, 1.5)
	k("prop_fuel_tank", O.x + 26, O.y - 6)
	k("prop_fuel_tank", O.x + 26, O.y + 4)
	w._prop("prop_pipe_stack", Vector3(O.x + 36, 0, O.y + 18), 90.0, Vector3(3.0, 1.1, 1.8), Vector3(0, 0.55, 0))
	for p in [Vector2(10, 14), Vector2(13, 16)]:
		k("prop_tire_stack", O.x + p.x, O.y + p.y)
	k("ext_police_car", O.x + 16, O.y + 30, 200.0)
	k("ext_barricade", O.x + 44, O.y - 2, 90.0)
	# --- the exfil radio by the gate
	w._place(w.RadioScript, Vector3(O.x + 20, 0, O.y + 18), 135.0)
	for p in [Vector2(-20, 0), Vector2(20, 0), Vector2(0, 30), Vector2(-34, -20)]:
		light(O.x + p.x, O.y + p.y, Color(0.75, 0.9, 1.0), 2.0)
	# --- the pylon line toward town
	for i in range(1, 9):
		var t := float(i) / 9.0
		var p := O.lerp(Vector2(300, -240), t) + Vector2(0, -26)
		ky("prop_power_pylon", Vector3(p.x, w.terrain.height_at(p.x, p.y) - 0.2, p.y), 90.0)
	w._add_vehicle("truck", "SS-07 TRUCK", Vector3(O.x + 22, 0.4, O.y + 20), 180.0)
