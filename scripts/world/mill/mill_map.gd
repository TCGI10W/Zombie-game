class_name MillMap
extends BunkerArena
# HALLOWAY MILL - closed classic-rules map (docs/maps/halloway_mill.md).
# GREYBOX: flat walls, slabs and blockers only, to test flow, doors and
# spawns. Buildings get replaced by the Blender kit (art/models/mill/).
#
#        x -30   -12 -6  -8       24 28        44
#  z -36  +HOUSE--+walk+--KILN-----+
#  z -20  |       |    +--MILL-----+
#  z  -8  +-walk2-+    |           |   river ->
#  z  -2  |STORE  |    +----D2-----+---+-------+
#  z   6  +-------+  YARD          | D7| POWER |
#  z  14         +OFFICE+          |   | + LZ  |
#  z  26         +------+          |   |       |
#  z  30                +----------+   +-------+

const H := 4.2

var map_min := Vector2(-44, -48)
var map_max := Vector2(56, 44)
var map_title := "HALLOWAY MILL  —  TACTICAL MAP"
var outdoor_zones := ["yard", "power"]
var fire_spots := [[Vector3(2, 0.5, 8), 0.5], [Vector3(20, 0.6, 26), 0.6], [Vector3(36, 0.6, 30), 0.7]]

var roofs: Array[Node3D] = []
var m_plaster: Material
var m_siding: Material
var m_wood_floor: Material
var m_lumber: Material
var m_bark: Material
var m_corr: Material


func _ready() -> void:
	add_to_group("arena")
	zones_open = {"office": true, "yard": false, "mill": false, "store": false, "kiln": false, "house": false, "power": false}
	zone_names = {"office": "FOREMAN'S OFFICE", "yard": "MILL YARD", "mill": "SAWMILL FLOOR", "store": "COMPANY STORE",
		"kiln": "KILN SHEDS", "house": "BOARDING HOUSE", "power": "POWER HOUSE & LANDING"}
	var R := func(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	zone_polys = {
		"office": [R.call(-8, 14, 8, 26)],
		"yard": [PackedVector2Array([Vector2(-12, -2), Vector2(28, -2), Vector2(28, 30), Vector2(8, 30), Vector2(8, 14), Vector2(-12, 14)])],
		"mill": [R.call(-8, -20, 24, -2)],
		"store": [R.call(-28, -8, -12, 6)],
		"kiln": [R.call(-6, -36, 24, -20)],
		"house": [R.call(-30, -36, -12, -22), R.call(-12, -30, -6, -26), R.call(-24, -22, -20, -8)],
		"power": [R.call(28, -2, 44, 34)],
	}
	boss_points = {"office": [Vector3(0, 0.1, 20)], "yard": [Vector3(12, 0.1, 8), Vector3(20, 0.1, 22)], "mill": [Vector3(8, 0.1, -6)],
		"store": [Vector3(-20, 0.1, -1)], "kiln": [Vector3(9, 0.1, -28)], "house": [Vector3(-21, 0.1, -29)], "power": [Vector3(37, 0.1, 24)]}
	player_spawn = Vector3(0, 0.2, 22)
	lz_pos = Vector3(37, 0, 24)

	# Brutalist/metal set (art/blender/build_brut_textures.py): 128 px = 2 m -> uv 0.5
	var W := func(n: String, metal: float = 0.0) -> Material:
		return MaterialLib.get_world("brut_" + n, 0.5, Color.WHITE, metal, 1.0, 0.0, 0.3)
	m_conc = W.call("conc_floor")
	m_dark_conc = W.call("roof")
	m_brick = W.call("panel_conc")
	m_plaster = W.call("block")
	m_siding = W.call("cast_conc")
	m_metal = W.call("steel_panel", 0.4)
	m_fence = W.call("rust", 0.2)
	m_wood = W.call("cladding", 0.3)
	m_stone = m_conc
	m_wood_floor = W.call("conc_floor")
	m_lumber = W.call("primer", 0.2)
	m_bark = W.call("rust", 0.2)
	m_corr = W.call("cladding", 0.3)

	_build_environment()
	_ground()
	_walls()
	_office()
	_yard()
	_mill()
	_store()
	_kiln()
	_house()
	_power()
	_labels()
	_window_lights()
	_fill_lights([Vector3(0, 3.2, 20), Vector3(0, 3.4, -11), Vector3(16, 3.4, -11), Vector3(-20, 3.2, -1),
		Vector3(2, 3.4, -28), Vector3(16, 3.4, -28), Vector3(-21, 3.2, -29), Vector3(37, 3.2, 6)],
		Color(0.75, 0.8, 0.95), 0.55, 12.0)
	_psx_subdivide(self)
	_bake_navigation()


# ---------------------------------------------------------------- shell
func _ground() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)
	_add_static_box(Vector3(6, -0.25, -2), Vector3(130, 0.5, 110),
		MaterialLib.get_world("brut_ground", 0.5, Color.WHITE, 0.0, 1.0, 0.0, 0.3))
	var conc := m_conc
	_add_floor_tile(Vector3(0, 0, 20), Vector2(16, 12), m_wood_floor)
	_add_floor_tile(Vector3(8, 0, -11), Vector2(32, 18), conc)
	_add_floor_tile(Vector3(-20, 0, -1), Vector2(16, 14), m_wood_floor)
	_add_floor_tile(Vector3(9, 0, -28), Vector2(30, 16), conc)
	_add_floor_tile(Vector3(-21, 0, -29), Vector2(18, 14), m_wood_floor)
	_add_floor_tile(Vector3(37, 0, 6), Vector2(10, 12), conc)
	# river beyond the landing (visual band; zombies come up the bank)
	_add_floor_tile(Vector3(54, 0.02, -2), Vector2(12, 110), MaterialLib.get_world("brut_water", 0.25, Color.WHITE, 0.0, 0.4, 0.0, 0.0))


func _walls() -> void:
	# OFFICE (start): two windows so round 1 is fair; D1 north to the yard
	_edge("office", Vector2(-8, 14), Vector2(-8, 26), [6.0], [], m_siding, H)
	_edge("office", Vector2(-8, 26), Vector2(8, 26), [8.0], [], m_siding, H)
	_edge("office", Vector2(-8, 14), Vector2(8, 14), [], [8.0, "yard", 750], m_siding, H)
	_seg(Vector2(8, 14), Vector2(8, 26), [], m_siding, H)
	_r(Vector3(0, H + 0.2, 20), Vector2(16.6, 12.6))
	# YARD fence (3 m): west, south and the fence stubs
	_edge("yard", Vector2(-12, 6), Vector2(-12, 14), [4.0], [], m_fence, 3.0)
	_seg(Vector2(-12, 14), Vector2(-8, 14), [], m_fence, 3.0)
	_seg(Vector2(8, 26), Vector2(8, 30), [], m_fence, 3.0)
	_edge("yard", Vector2(8, 30), Vector2(28, 30), [10.0], [], m_fence, 3.0)
	_seg(Vector2(-12, -2), Vector2(-8, -2), [], m_fence, 3.0)
	_seg(Vector2(24, -2), Vector2(28, -2), [], m_fence, 3.0)
	_edge("yard", Vector2(28, -2), Vector2(28, 30), [], [22.0, "power", 3000], m_fence, 3.0)
	# MILL: D2 from the yard, D4 north to the kiln
	_edge("yard", Vector2(-8, -2), Vector2(24, -2), [], [16.0, "mill", 1000], m_wood, H)
	_edge("mill", Vector2(24, -20), Vector2(24, -2), [9.0], [], m_wood, H)
	_edge("mill", Vector2(-8, -20), Vector2(-8, -2), [6.0, 14.0], [], m_wood, H)
	_seg(Vector2(-8, -20), Vector2(-6, -20), [], m_wood, H)
	_edge("mill", Vector2(-6, -20), Vector2(24, -20), [], [15.0, "kiln", 1500], m_brick, H)
	_r(Vector3(8, H + 0.2, -11), Vector2(32.6, 18.6))
	# KILN
	_edge("kiln", Vector2(-6, -36), Vector2(24, -36), [8.0, 22.0], [], m_brick, H)
	_edge("kiln", Vector2(24, -36), Vector2(24, -20), [8.0], [], m_brick, H)
	_edge("kiln", Vector2(-6, -36), Vector2(-6, -20), [], [8.0, "house", 2000], m_brick, H)
	_r(Vector3(9, H + 0.2, -28), Vector2(30.6, 16.6))
	# covered walk kiln -> house
	_seg(Vector2(-12, -30), Vector2(-6, -30), [], m_wood, 3.2)
	_seg(Vector2(-12, -26), Vector2(-6, -26), [], m_wood, 3.2)
	_r(Vector3(-9, 3.4, -28), Vector2(6.6, 4.6))
	# BOARDING HOUSE
	_seg(Vector2(-30, -36), Vector2(-12, -36), [], m_siding, H)
	_edge("house", Vector2(-30, -36), Vector2(-30, -22), [7.0], [], m_siding, H)
	_seg(Vector2(-12, -36), Vector2(-12, -22), [[8.0, 4.0, 3.2]], m_siding, H)
	_seg(Vector2(-30, -22), Vector2(-12, -22), [[8.0, 4.0, 3.2], [14.0, WINDOW_W, WINDOW_H]], m_siding, H)
	_add_window(Vector3(-16, 0, -22), Vector3(0, 0, 1), "house")
	_r(Vector3(-21, H + 0.2, -29), Vector2(18.6, 14.6))
	# walk2 house -> store
	_seg(Vector2(-24, -22), Vector2(-24, -8), [], m_wood, 3.2)
	_seg(Vector2(-20, -22), Vector2(-20, -8), [], m_wood, 3.2)
	_r(Vector3(-22, 3.4, -15), Vector2(4.6, 14.6))
	# STORE: D3 from the yard, D6 north into walk2
	_edge("store", Vector2(-28, -8), Vector2(-28, 6), [7.0], [], m_siding, H)
	_edge("store", Vector2(-28, 6), Vector2(-12, 6), [8.0], [], m_siding, H)
	_edge("store", Vector2(-28, -8), Vector2(-12, -8), [], [6.0, "house", 1750], m_plaster, H)
	_edge("store", Vector2(-12, -8), Vector2(-12, -2), [3.0], [], m_plaster, H)
	_edge("yard", Vector2(-12, -2), Vector2(-12, 6), [], [4.0, "store", 1250], m_plaster, H)
	_r(Vector3(-20, H + 0.2, -1), Vector2(16.6, 14.6))
	# POWER + LANDING fence
	_edge("power", Vector2(28, -2), Vector2(44, -2), [8.0], [], m_corr, 3.0)
	_edge("power", Vector2(44, -2), Vector2(44, 34), [10.0, 26.0], [], m_corr, 3.0)
	_seg(Vector2(28, 34), Vector2(44, 34), [], m_fence, 3.0)
	_seg(Vector2(28, 30), Vector2(28, 34), [], m_fence, 3.0)
	# power house building inside the fence, open doorway on the west
	_seg(Vector2(32, 0), Vector2(42, 0), [], m_brick, H)
	_seg(Vector2(42, 0), Vector2(42, 12), [], m_brick, H)
	_seg(Vector2(32, 12), Vector2(42, 12), [], m_brick, H)
	_seg(Vector2(32, 0), Vector2(32, 12), [[6.0, DOOR_W, DOOR_H]], m_brick, H)
	_r(Vector3(37, H + 0.2, 6), Vector2(10.6, 12.6))


func _r(c: Vector3, s: Vector2) -> void:
	roofs.append(_add_static_box(c, Vector3(s.x, 0.4, s.y), m_dark_conc))


func _block(x: float, z: float, sx: float, sy: float, sz: float, mat: Material = null) -> void:
	_add_static_box(Vector3(x, sy * 0.5, z), Vector3(sx, sy, sz), mat if mat else m_lumber)


func _lamps(points: Array, col: Color = Color(1.0, 0.9, 0.75)) -> void:
	for p in points:
		_add_lamp(Vector3(p.x, H - 0.35, p.y), col, 2.2, false)


# ---------------------------------------------------------------- zones
func _office() -> void:
	_wall_buy("office", Vector2(-8, 26), Vector2(8, 26), 3.0, "weapon", "smg", "KURZ-9 SMG", 1000, 500)
	_wall_buy("office", Vector2(-8, 14), Vector2(-8, 26), 10.0, "ammo_box", "", "AMMO CACHE", 450, 0)
	_place(RadioScript, Vector3(5.5, 0, 23.5), -135.0)
	_block(4.5, 23.5, 2.4, 0.8, 1.2)       # foreman's desk
	_block(-5, 16, 3.0, 1.0, 1.4, m_metal) # truck scale dial housing
	_skull(Vector3(-7.4, 2.0, 18.0), 90.0) # on the filing cabinet
	_block(-7.3, 18, 0.9, 1.8, 1.4, m_metal)
	_lamps([Vector2(0, 20)])


func _yard() -> void:
	# two log decks = the training loop anchors
	_block(4, 5, 10, 1.4, 3, m_bark)
	_block(18, 12, 3, 1.4, 10, m_bark)
	_block(12, 22, 4, 2.6, 2.4, m_metal)  # log loader
	_wall_buy("yard", Vector2(8, 14), Vector2(8, 26), 6.0, "weapon", "rifle", "COMMANDO M14A", 1200, 600)
	_wall_buy("yard", Vector2(28, -2), Vector2(28, 30), 6.0, "ammo_box", "", "AMMO CACHE", 450, 0)
	_place(load("res://scripts/world/supply_depot.gd") as GDScript, Vector3(24, 0, 26), -90.0)
	_add_fire_barrel(Vector3(2, 0, 8))
	_add_fire_barrel(Vector3(20, 0, 26))
	for p in [Vector3(-2, 0, 0), Vector3(24, 0, 2), Vector3(12, 0, 28)]:
		_post_light(p, Color(1.0, 0.75, 0.45), 2.0, 14.0)


func _mill() -> void:
	_block(8, -12, 20, 1.0, 2.0, m_metal)  # head-saw carriage track
	_block(14, -12, 1.0, 3.2, 3.2, m_metal) # head saw
	_block(-4, -16, 3, 1.2, 6, m_bark)              # log infeed
	_spawn_station("weapon", "shotgun", "TRENCH-12 PUMP", 1500, 750, Color(0.25, 0.88, 1.0), Vector3(23.68, 1.55, -6.0), -90.0)
	_place(CrateScript, Vector3(0, 0, -6), 0.0)
	_skull(Vector3(14, 3.9, -12), 0.0)
	_lamps([Vector2(0, -11), Vector2(16, -11)], Color(0.9, 0.95, 1.0))


func _store() -> void:
	_block(-20, -5, 8, 1.1, 1.0)         # counter
	_block(-26.5, 2, 1.2, 1.2, 4)        # shelves
	_wall_buy("store", Vector2(-28, -8), Vector2(-12, -8), 12.0, "weapon", "revolver", ".44 HAND CANNON", 1750, 875)
	_wall_buy("store", Vector2(-28, -8), Vector2(-28, 6), 12.0, "ammo_box", "", "AMMO CACHE", 450, 0)
	_place(SecondWindScript, Vector3(-14, 0, 4.5), 180.0)
	_lamps([Vector2(-20, -1)])


func _kiln() -> void:
	for x in [0.0, 6.0]:
		_block(x, -30, 3, 2.2, 3, m_metal)  # Batch 7 vats
	_block(16, -33, 8, 0.8, 3)             # drying racks
	_block(16, -25, 8, 0.8, 3)
	_place(FurnaceScript, Vector3(22.8, 0, -28), -90.0)
	_wall_buy("kiln", Vector2(-6, -20), Vector2(24, -20), 4.0, "weapon", "lmg", "RAZORBACK LMG", 3000, 1500)
	_wall_buy("kiln", Vector2(-6, -36), Vector2(24, -36), 15.0, "ammo_box", "", "AMMO CACHE", 450, 0)
	_lamps([Vector2(3, -28), Vector2(16, -28)], Color(1.0, 0.3, 0.2))


func _house() -> void:
	_seg(Vector2(-30, -29), Vector2(-21, -29), [[4.5, 1.6, 2.4]], m_plaster, H)  # room partition
	_block(-27, -34, 2, 0.6, 1)  # bunks
	_block(-27, -24, 2, 0.6, 1)
	_block(-14, -34, 2, 1.0, 3)  # stair block (2nd storey in the real build)
	_spawn_station("weapon", "sniper", "LONGSHOT .50", 3500, 1750, Color(0.25, 0.88, 1.0), Vector3(-21, 1.55, -35.68), 0.0)
	_skull(Vector3(-27, 0.7, -34), 0.0)
	_lamps([Vector2(-25, -32), Vector2(-17, -26)])


func _power() -> void:
	_place(GeneratorScript, Vector3(39, 0, 6), -90.0)
	_spawn_station("forge", "", "WEAPON FORGE", 5000, 0, Color(0.72, 0.30, 1.0), Vector3(37, 1.55, 11.68), 180.0)
	_block(41, 20, 2, 1.2, 8, m_metal)  # penstock pipe
	_lamps([Vector2(37, 6)], Color(0.9, 0.95, 1.0))
	for p in [Vector3(31, 0, 32), Vector3(43, 0, 16)]:
		_post_light(p, Color(1.0, 0.75, 0.45), 1.8, 14.0)


# Greybox zone labels (removed once the buildings are modelled)
func _labels() -> void:
	for z in zone_polys:
		var poly: PackedVector2Array = zone_polys[z][0]
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= poly.size()
		var l := Label3D.new()
		l.text = zone_names[z]
		l.font_size = 160
		l.pixel_size = 0.02
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = Color(1, 0.85, 0.3)
		l.position = Vector3(c.x, 6.0, c.y)
		l.add_to_group("greybox_label")
		add_child(l)


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
	nav_mesh.filter_baking_aabb = AABB(Vector3(-48, -1.0, -50), Vector3(100, 3.2, 98))
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, self)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	nav_region.navigation_mesh = nav_mesh
