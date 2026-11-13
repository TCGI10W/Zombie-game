class_name JunctionMap
extends BunkerArena
# KESSLER JUNCTION - a closed, classic-rules map (buy doors, board windows,
# turn the power on), built from the Blender kits. A walled truck-stop motel
# on a dead highway. Separate from Nacht (bunker_arena.gd) and The County.
#
#              x -34      -16          16        34
#       z -26   +--------+------------+
#               | OFFICE | MOTEL      |
#       z -12   +--------+-----D------+---------+
#               | GARAGE D COURTYARD  D DINER   |
#               |        | (start)    |         |
#       z  12   +---D----+-windows----+----D----+
#               | YARD   |            |WAREHOUSE|
#       z  34   +--------+            +---------+
#
# Zombies come from outside through boarded windows on the outer walls;
# only windows of zones you have opened are used. Power is in the warehouse.

const H := 4.2

var map_min := Vector2(-48, -40)
var map_max := Vector2(48, 48)
var map_title := "KESSLER JUNCTION  —  TACTICAL MAP"
var outdoor_zones := ["courtyard", "yard"]
var fire_spots := [[Vector3(-6, 0.5, 6), 0.5], [Vector3(-26, 0.6, 28), 0.7], [Vector3(40, 0.6, 40), 0.8]]

var m_plaster: Material
var m_siding: Material
var m_tiles: Material
var m_wood_floor: Material


func _ready() -> void:
	add_to_group("arena")
	zones_open = {"courtyard": true, "motel": false, "diner": false, "garage": false, "office": false, "warehouse": false, "yard": false}
	zone_names = {"courtyard": "MOTEL COURTYARD", "motel": "MOTEL ROOMS", "diner": "ROADSIDE DINER", "garage": "MECHANIC'S GARAGE",
		"office": "MANAGER'S OFFICE", "warehouse": "FREIGHT WAREHOUSE", "yard": "BACK YARD"}
	var R := func(x0: float, z0: float, x1: float, z1: float) -> Array:
		return [PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])]
	zone_polys = {"courtyard": R.call(-16, -12, 16, 12), "motel": R.call(-16, -26, 16, -12), "diner": R.call(16, -12, 34, 12),
		"garage": R.call(-34, -12, -16, 12), "office": R.call(-34, -26, -16, -12), "warehouse": R.call(16, 12, 34, 34),
		"yard": R.call(-34, 12, -16, 34)}
	boss_points = {"courtyard": [Vector3(0, 0.1, -4), Vector3(8, 0.1, 6)], "motel": [Vector3(0, 0.1, -19)], "diner": [Vector3(25, 0.1, 0)],
		"garage": [Vector3(-25, 0.1, 0)], "office": [Vector3(-25, 0.1, -19)], "warehouse": [Vector3(25, 0.1, 23)], "yard": [Vector3(-25, 0.1, 23)]}
	player_spawn = Vector3(0, 0.2, 5)
	lz_pos = Vector3(-4, 0, 2)

	m_conc = MaterialLib.get_world("concrete", 0.5, Color(0.8, 0.8, 0.82), 0.0, 1.0, 0.0, 0.5)
	m_dark_conc = MaterialLib.get_world("concrete", 0.5, Color(0.5, 0.51, 0.55), 0.0, 1.0, 0.0, 0.4)
	m_brick = MaterialLib.get_world("brick", 0.6, Color(0.95, 0.92, 0.9), 0.0, 1.0, 0.0, 0.5)
	m_plaster = MaterialLib.get_world("plaster", 0.5, Color(0.95, 0.92, 0.88), 0.0, 1.0, 0.0, 0.4)
	m_siding = MaterialLib.get_world("siding_white", 0.45, Color(0.92, 0.92, 0.9), 0.0, 1.0, 0.0, 0.4)
	m_metal = MaterialLib.get_world("rusted_metal", 0.5, Color(0.85, 0.82, 0.8), 0.35, 0.9, 0.0, 0.25)
	m_fence = MaterialLib.get_world("rusted_metal", 0.5, Color(0.6, 0.56, 0.52), 0.4, 0.9, 0.0, 0.2)
	m_wood = MaterialLib.get_world("wood_planks", 0.5, Color(0.9, 0.85, 0.78), 0.0, 1.0, 0.0, 0.3)
	m_stone = m_conc
	m_tiles = MaterialLib.get_world("tiles", 0.5, Color(0.9, 0.92, 0.9), 0.0, 1.0, 0.0, 0.0, true)
	m_wood_floor = MaterialLib.get_world("wood_planks", 0.5, Color(0.85, 0.8, 0.75), 0.0, 1.0, 0.0, 0.0, true)

	_build_environment()
	_ground()
	_walls()
	_courtyard()
	_motel()
	_diner()
	_garage()
	_office()
	_warehouse()
	_yard()
	_outside()
	_window_lights()
	# soft always-on fill so rooms read before the power is on (Nacht does the same)
	_fill_lights([Vector3(0, 3.2, -14.5), Vector3(-8, 3.0, -21.5), Vector3(8, 3.0, -21.5), Vector3(25, 3.2, -4),
		Vector3(25, 3.2, 6), Vector3(-25, 3.2, -4), Vector3(-25, 3.2, 6), Vector3(-25, 3.0, -19), Vector3(25, 3.2, 23)],
		Color(0.75, 0.8, 0.95), 0.55, 11.0)
	_psx_subdivide(self)
	_bake_navigation()


# ---------------------------------------------------------------- shell
func _ground() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)
	_add_static_box(Vector3(0, -0.25, 4), Vector3(140, 0.5, 130),
		MaterialLib.get_world("asphalt", 0.33, Color(0.88, 0.9, 0.96), 0.05, 1.0, 1.0, 0.0, true))
	var conc := MaterialLib.get_world("concrete_floor", 0.5, Color(0.6, 0.6, 0.62), 0.0, 1.0, 0.0, 0.0, true)
	_add_floor_tile(Vector3(0, 0, 0), Vector2(32, 24), conc)
	_add_floor_tile(Vector3(0, 0, -19), Vector2(32, 14), m_wood_floor)
	_add_floor_tile(Vector3(25, 0, 0), Vector2(18, 24), m_tiles)
	_add_floor_tile(Vector3(-25, 0, 0), Vector2(18, 24), conc)
	_add_floor_tile(Vector3(-25, 0, -19), Vector2(18, 14), m_wood_floor)
	_add_floor_tile(Vector3(25, 0, 23), Vector2(18, 22), conc)
	_add_floor_tile(Vector3(-25, 0, 23), Vector2(18, 22), MaterialLib.get_world("gravel", 0.5, Color(0.8, 0.8, 0.8), 0.0, 1.0, 0.0, 0.0, true))


func _walls() -> void:
	# --- outer walls, with the boarded windows zombies break in through
	_edge("office", Vector2(-34, -26), Vector2(-16, -26), [9.0], [], m_siding, H)
	_edge("motel", Vector2(-16, -26), Vector2(16, -26), [12.0, 20.0], [], m_siding, H)
	_edge("motel", Vector2(16, -26), Vector2(16, -12), [7.0], [], m_siding, H)
	_edge("office", Vector2(-34, -26), Vector2(-34, -12), [7.0], [], m_siding, H)
	_edge("garage", Vector2(-34, -12), Vector2(-34, 12), [7.0, 17.0], [], m_metal, H)
	_edge("diner", Vector2(16, -12), Vector2(34, -12), [9.0], [], m_plaster, H)
	_edge("diner", Vector2(34, -12), Vector2(34, 12), [7.0, 17.0], [], m_plaster, H)
	_edge("courtyard", Vector2(-16, 12), Vector2(16, 12), [7.0, 25.0], [], m_brick, 3.0)
	_edge("yard", Vector2(-34, 12), Vector2(-34, 34), [11.0], [], m_fence, 3.0)
	_edge("yard", Vector2(-34, 34), Vector2(-16, 34), [9.0], [], m_fence, 3.0)
	_edge("yard", Vector2(-16, 12), Vector2(-16, 34), [11.0], [], m_fence, 3.0)
	_edge("warehouse", Vector2(16, 12), Vector2(16, 34), [11.0], [], m_metal, H)
	_edge("warehouse", Vector2(16, 34), Vector2(34, 34), [4.0], [], m_metal, H)
	_edge("warehouse", Vector2(34, 12), Vector2(34, 34), [11.0], [], m_metal, H)
	# --- inner walls with the buyable doors
	_edge("courtyard", Vector2(-16, -12), Vector2(16, -12), [], [16.0, "motel", 750], m_siding, H)
	_edge("courtyard", Vector2(16, -12), Vector2(16, 12), [], [12.0, "diner", 1000], m_plaster, H)
	_edge("courtyard", Vector2(-16, -12), Vector2(-16, 12), [], [12.0, "garage", 1000], m_metal, H)
	_edge("motel", Vector2(-16, -26), Vector2(-16, -12), [], [7.0, "office", 1500], m_siding, H)
	_edge("diner", Vector2(16, 12), Vector2(34, 12), [], [9.0, "warehouse", 1250], m_plaster, H)
	_edge("garage", Vector2(-34, 12), Vector2(-16, 12), [], [9.0, "yard", 1250], m_metal, H)
	_seg(Vector2(-34, -12), Vector2(-16, -12), [], m_siding, H)  # office | garage
	# --- roofs over the buildings (courtyard and yard are open to the sky)
	_roof(Vector3(0, H + 0.2, -19), Vector2(32.6, 14.6))
	_roof(Vector3(-25, H + 0.2, -19), Vector2(18.6, 14.6))
	_roof(Vector3(25, H + 0.2, 0), Vector2(18.6, 24.6))
	_roof(Vector3(-25, H + 0.2, 0), Vector2(18.6, 24.6))
	_roof(Vector3(25, H + 0.2, 23), Vector2(18.6, 22.6))


func _k(name: String, x: float, z: float, rot: float = 0.0, col: Vector3 = Vector3.ZERO, s: float = 1.0) -> void:
	_prop(name, Vector3(x, 0, z), rot, col, Vector3(0, col.y * 0.5, 0), s)


func _ceiling_lamps(points: Array, col: Color = Color(1.0, 0.9, 0.75)) -> void:
	for p in points:
		_add_lamp(Vector3(p.x, H - 0.35, p.y), col, 2.2, false)


# ---------------------------------------------------------------- zones
# COURTYARD (start): the motel's parking court. Cars, the vending corner,
# the sign pole, the pool long drained and boarded over.
func _courtyard() -> void:
	_wall_buy("courtyard", Vector2(-16, 12), Vector2(16, 12), 16.0, "weapon", "smg", "KURZ-9 SMG", 1000, 500)
	_wall_buy("courtyard", Vector2(-16, 12), Vector2(16, 12), 3.0, "ammo_box", "", "AMMO CACHE", 450, 0)
	_place(SecondWindScript, Vector3(13.5, 0, 9.5), -90.0)
	_place(load("res://scripts/world/supply_depot.gd") as GDScript, Vector3(-13.5, 0, -8.5), 90.0)
	_k("prop_car_wreck", -8, -3, 15.0, Vector3(1.9, 1.3, 4.3))
	_k("prop_car_wreck", 9, -4, -10.0, Vector3(1.9, 1.3, 4.3))
	_k("ext_police_car", 5, 6, 80.0)
	_add_sandbags(Vector3(-3, 0, -8), 0.0)
	_add_sandbags(Vector3(3, 0, -8), 0.0)
	_k("ext_picnic_table", -10, 6, 20.0)
	_k("ext_trash_can", -14.6, 10.6)
	_k("ext_trash_can", 14.5, -10.5)
	_k("int_fridge_row", 13.5, 3, 90.0)  # vending row under the diner wall
	_k("ext_bush", -14.5, 3.5)
	_add_fire_barrel(Vector3(-6, 0, 6))
	_skull(Vector3(-15.4, 0.95, 6.0), -90.0)
	for p in [Vector3(-12, 0, -9), Vector3(12, 0, 9)]:
		_post_light(p, Color(1.0, 0.82, 0.55), 2.2, 13.0)


# MOTEL: a corridor with four rooms off it (beds, TVs, the lot).
func _motel() -> void:
	# corridor along the courtyard side; room partitions north of it
	for x in [-8.0, 0.0, 8.0]:
		_seg(Vector2(x, -26), Vector2(x, -17), [], m_plaster, H)
	_seg(Vector2(-16, -17), Vector2(16, -17), [[4.0, 1.6, 2.4], [12.0, 1.6, 2.4], [20.0, 1.6, 2.4], [28.0, 1.6, 2.4]], m_plaster, H)
	for x in [-12.0, -4.0, 4.0, 12.0]:
		_k("int_bed", x - 3.0, -23.6, 0.0)
		_k("int_filing_cabinet", x + 2.6, -25.3, 180.0)
		_k("int_chair", x + 2.2, -19.5, 200.0)
	_k("int_sofa", -6, -12.9, 180.0)
	_k("int_table", 6, -13.4, 0.0)
	_k("int_boxes", 14, -15.5, 20.0)
	_spawn_station("weapon", "shotgun", "TRENCH-12 PUMP", 1500, 750, Color(0.25, 0.88, 1.0), Vector3(14.6, 1.55, -16.68), 0.0)
	_skull(Vector3(11.0, 0.75, -24.0), 0.0)
	_ceiling_lamps([Vector2(-8, -14.5), Vector2(8, -14.5), Vector2(-12, -21.5), Vector2(-4, -21.5), Vector2(4, -21.5), Vector2(12, -21.5)])


# DINER: booths along the windows, counter and kitchen at the back.
func _diner() -> void:
	for x in [18.6, 21.0, 29.2, 31.6]:
		_k("int_booth", x, -11.35, 0.0)
	_k("int_counter", 22, 4, 90.0)
	for z in [2.4, 3.2, 4.0, 4.8, 5.6]:
		_k("int_stool", 23.2, z)
	_k("int_kitchen", 19, 10.9, 0.0)
	_k("int_fridge_row", 28, 11.2, 0.0)
	_k("int_table", 26, -6, 0.0)
	_wall_buy("diner", Vector2(16, -12), Vector2(34, -12), 4.0, "weapon", "rifle", "COMMANDO M14A", 1200, 600)
	_wall_buy("diner", Vector2(34, -12), Vector2(34, 12), 12.0, "ammo_box", "", "AMMO CACHE", 450, 0)
	_ceiling_lamps([Vector2(25, -6), Vector2(25, 6)])


# GARAGE: bays, a wrecked pickup on the lift, tools; the mystery crate.
func _garage() -> void:
	_k("prop_car_wreck", -26, -4, 0.0, Vector3(1.9, 1.3, 4.3))
	_k("int_workbench", -33.2, 0, -90.0)
	_k("int_tool_cabinet", -33.3, 9, -90.0)
	_k("int_tool_cabinet", -33.3, -9, -90.0)
	_k("prop_tire_stack", -18, -10.5)
	_k("prop_tire_stack", -19.2, -10.4)
	_k("prop_barrel", -21, 10.5)
	_k("int_boxes", -30, -10.8, 0.0)
	_place(CrateScript, Vector3(-31, 0, 10.6), 180.0)
	_wall_buy("garage", Vector2(-34, -12), Vector2(-16, -12), 6.0, "weapon", "revolver", ".44 HAND CANNON", 1750, 875)
	_place(FurnaceScript, Vector3(-17.2, 0, -6), -90.0)
	_ceiling_lamps([Vector2(-25, -5), Vector2(-25, 5)])


# OFFICE: the manager's office and the radio room (exfil).
func _office() -> void:
	_k("prop_desk", -28, -22, 180.0)
	_k("int_filing_cabinet", -33.3, -24, -90.0)
	_k("int_filing_cabinet", -33.3, -23.3, -90.0)
	_k("int_bookshelf", -20, -25.5, 180.0)
	_k("int_chair", -27.4, -21, 0.0)
	_place(RadioScript, Vector3(-30, 0, -15), 45.0)
	_wall_buy("office", Vector2(-34, -26), Vector2(-16, -26), 15.0, "ammo_box", "", "AMMO CACHE", 450, 0)
	_ceiling_lamps([Vector2(-25, -19)])


# WAREHOUSE: freight racks, the generator, the heavy gear.
func _warehouse() -> void:
	_place(GeneratorScript, Vector3(26, 0, 32.4), 0.0)
	for z in [17.0, 22.0]:
		_k("int_store_shelf", 21, z, 0.0)
		_k("int_store_shelf", 29, z, 0.0)
	_add_crate_stack(Vector3(18.6, 0, 14.6), 2)
	_k("int_boxes", 18.4, 28.5, 90.0)
	_k("prop_fuel_tank", 30, 28, 90.0)
	_k("int_pipes", 31.5, 33.6, 0.0)
	_wall_buy("warehouse", Vector2(16, 12), Vector2(16, 34), 18.0, "weapon", "lmg", "RAZORBACK LMG", 3000, 1500)
	_wall_buy("warehouse", Vector2(34, 12), Vector2(34, 34), 4.0, "forge", "", "WEAPON FORGE", 5000, 0, 0.0, 2.8)
	_ceiling_lamps([Vector2(21, 23), Vector2(29, 23)], Color(0.9, 0.95, 1.0))


# YARD: fenced dump behind the garage - scrap, a trailer, the sniper.
func _yard() -> void:
	_k("ext_trailer", -25, 29, 0.0)
	_k("prop_rubble", -30, 17, 30.0, Vector3(2.0, 0.6, 1.6))
	_k("prop_tire_stack", -19, 18)
	_k("ext_barricade", -24, 19, 10.0)
	_add_fire_barrel(Vector3(-26, 0, 22))
	_spawn_station("weapon", "sniper", "LONGSHOT .50", 3500, 1750, Color(0.25, 0.88, 1.0), Vector3(-16.35, 1.55, 30.0), -90.0)
	_skull(Vector3(-31.0, 0.6, 32.0), 135.0)
	_post_light(Vector3(-20, 0, 30), Color(1.0, 0.8, 0.5), 1.8, 13.0)


# OUTSIDE the walls: the dead highway and its wrecks (zombies come from here).
func _outside() -> void:
	_add_floor_tile(Vector3(0, 0.01, 44), Vector2(120, 10), MaterialLib.get_world("asphalt", 0.33, Color(0.8, 0.82, 0.86), 0.05, 1.0, 1.0, 0.0, true))
	for c in [[-36.0, 44.0, 95.0], [-12.0, 43.0, 80.0], [10.0, 45.0, 260.0], [40.0, 43.0, 100.0]]:
		_k("prop_car_wreck", c[0], c[1], c[2])
	_k("ext_bus_wreck", 52, 20, 8.0)
	_k("prop_billboard", -46, -30, 30.0)
	_k("prop_gas_canopy", 42, -36, 0.0)
	for x in [36.0, 48.0]:
		_k("prop_gas_pump", x, -36)
	_k("prop_water_tower", -48, 0)
	for t in [Vector2(-46, -40), Vector2(-50, 24), Vector2(46, -12), Vector2(24, -42), Vector2(-20, -44), Vector2(52, 40)]:
		_k("ext_pine", t.x, t.y, t.x)
	for p in [Vector2(-40, 46), Vector2(0, 46), Vector2(40, 46)]:
		_post_light(Vector3(p.x, 0, p.y), Color(1.0, 0.7, 0.45), 1.6, 14.0)


# The navmesh covers the compound and the ground outside it (spawns).
func _bake_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_max_climb = 0.25
	nav_mesh.agent_max_slope = 40.0
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = 1
	nav_mesh.filter_baking_aabb = AABB(Vector3(-58, -1.0, -50), Vector3(116, 3.2, 104))
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, self)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	nav_region.navigation_mesh = nav_mesh
