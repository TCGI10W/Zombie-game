class_name BunkerArena
extends Node3D
# Town of Nacht: an open map of six very different areas joined by buyable
# doors and gates. The town plaza is the start; the old church (with the
# cemetery behind it), the warehouse, the hospital and the rail station
# open up around it. Walls can run at any angle, so areas follow their
# own shapes. Zombies come from outside through boarded windows on the
# outer walls; only windows of opened areas are used.

signal zone_opened(zone_id: String)

const BarricadeScript := preload("res://scripts/world/barricade.gd")
const ZoneDoorScript := preload("res://scripts/world/zone_door.gd")
const CrateScript := preload("res://scripts/world/mystery_crate.gd")
const FurnaceScript := preload("res://scripts/world/augment_furnace.gd")
const GeneratorScript := preload("res://scripts/world/power_generator.gd")
const SkullScript := preload("res://scripts/world/secret_skull.gd")
const SecondWindScript := preload("res://scripts/world/second_wind_station.gd")
const RadioScript := preload("res://scripts/world/exfil_radio.gd")
const EMERGENCY_RED := Color(1.0, 0.16, 0.1)

const WALL_H := 4.2
const WALL_T := 0.6
const WINDOW_W := 2.0
const WINDOW_H := 2.4
const DOOR_W := 3.0
const DOOR_H := 3.2

var zones_open: Dictionary = {"plaza": true, "church": false, "warehouse": false, "hospital": false, "rail": false, "cemetery": false}
var zone_names: Dictionary = {"plaza": "TOWN PLAZA", "church": "OLD CHURCH", "warehouse": "WAREHOUSE", "hospital": "HOSPITAL", "rail": "RAIL STATION", "cemetery": "CEMETERY"}
var zone_polys: Dictionary = {}
var windows: Array[Node3D] = []
var boss_points: Dictionary = {
	"plaza": [Vector3(0.0, 0.1, -12.0), Vector3(13.0, 0.1, 8.0), Vector3(-14.0, 0.1, -2.0)],
	"church": [Vector3(1.0, 0.1, -36.0)],
	"warehouse": [Vector3(42.0, 0.1, -6.0), Vector3(42.0, 0.1, 22.0)],
	"hospital": [Vector3(-38.0, 0.1, -20.0)],
	"rail": [Vector3(-36.0, 0.1, 31.5), Vector3(-10.0, 0.1, 31.5)],
	"cemetery": [Vector3(36.0, 0.1, -40.0)],
}
var player_spawn: Vector3 = Vector3(0.0, 0.2, 9.0)
var lz_pos: Vector3 = Vector3(-7.0, 0.0, 4.0)
var nav_region: NavigationRegion3D
var world_env: Environment

var fire_lights: Array[OmniLight3D] = []
var flicker_lamps: Array[OmniLight3D] = []

# Power: indoor lamps run on dim red emergency light until the generator is on
var power_on: bool = false
var powered_lamps: Array[Dictionary] = []
var skulls_found: int = 0
var _song_player: AudioStreamPlayer
var _flicker_time: float = 0.0

var m_conc: Material
var m_dark_conc: Material
var m_metal: Material
var m_stone: Material
var m_brick: Material
var m_fence: Material
var m_wood: Material


func _ready() -> void:
	add_to_group("arena")
	_make_polys()
	m_conc = MaterialLib.get_world("concrete", 0.5, Color(0.78, 0.8, 0.84), 0.0, 1.0, 0.0, 0.55)
	m_dark_conc = MaterialLib.get_world("concrete", 0.5, Color(0.5, 0.51, 0.55), 0.0, 1.0, 0.0, 0.4)
	m_metal = MaterialLib.get_world("rusted_metal", 0.5, Color(0.85, 0.82, 0.8), 0.35, 0.9, 0.0, 0.25)
	m_wood = MaterialLib.get_world("wood_planks", 0.5, Color(0.9, 0.85, 0.78), 0.0, 1.0, 0.0, 0.3)
	m_stone = MaterialLib.get_world("concrete", 0.4, Color(0.66, 0.62, 0.58), 0.0, 1.0, 0.0, 0.6)
	m_brick = MaterialLib.get_world("concrete", 0.6, Color(0.62, 0.42, 0.36), 0.0, 1.0, 0.0, 0.5)
	m_fence = MaterialLib.get_world("rusted_metal", 0.5, Color(0.55, 0.52, 0.5), 0.4, 0.9, 0.0, 0.2)

	_build_environment()
	_build_ground()
	_build_plaza()
	_build_church()
	_build_warehouse()
	_build_hospital()
	_build_rail()
	_build_cemetery()
	_build_outside()
	_window_lights()
	_bake_navigation()
	_scatter_blood.call_deferred()


# ---------------------------------------------------------------------------
# PUBLIC API (wave manager)
# ---------------------------------------------------------------------------
func is_zone_open(zone_id: String) -> bool:
	return zones_open.get(zone_id, false)


func get_open_windows() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for w in windows:
		if is_zone_open(w.zone_id):
			out.append(w)
	return out


func zone_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	for zid in zone_polys:
		if _in_zone(zid, q):
			return zid
	return ""


func _in_zone(zid: String, q: Vector2) -> bool:
	for poly in zone_polys.get(zid, []):
		if Geometry2D.is_point_in_polygon(q, poly):
			return true
	return false


# ---------------------------------------------------------------------------
# SHAPE HELPERS: walls at any angle, windows and doors placed along them
# ---------------------------------------------------------------------------
# Straight wall from a to b (x, z on the ground). gaps: [[distance from a, width, height]]
func _seg(a: Vector2, b: Vector2, gaps: Array, mat: Material, h: float = WALL_H) -> void:
	var d := (b - a).normalized()
	var a2 := a - d * WALL_T * 0.5 # overlap the corners
	var total := a.distance_to(b) + WALL_T
	var ang := atan2(-d.y, d.x)
	var gs := gaps.duplicate()
	gs.sort_custom(func(x, y): return x[0] < y[0])
	var cursor := 0.0
	for g in gs:
		var g0: float = float(g[0]) + WALL_T * 0.5 - float(g[1]) * 0.5
		var g1: float = g0 + float(g[1])
		_seg_box(a2, d, cursor, g0, 0.0, h, mat, ang)
		_seg_box(a2, d, g0, g1, float(g[2]), h, mat, ang)
		cursor = g1
	_seg_box(a2, d, cursor, total, 0.0, h, mat, ang)


func _seg_box(a: Vector2, d: Vector2, t0: float, t1: float, y0: float, y1: float, mat: Material, ang: float) -> void:
	if t1 - t0 < 0.02 or y1 - y0 < 0.02:
		return
	var mid := a + d * ((t0 + t1) * 0.5)
	_add_static_box(Vector3(mid.x, (y0 + y1) * 0.5, mid.y), Vector3(t1 - t0, y1 - y0, WALL_T), mat, Vector3(0, ang, 0))


# A wall on the edge of `zone`: barricaded windows at the given distances,
# and optionally a buyable door [distance, zone it opens, cost].
func _edge(zone: String, a: Vector2, b: Vector2, wins: Array, door: Array = [], mat: Material = null, h: float = WALL_H) -> void:
	var gaps := []
	for w in wins:
		gaps.append([w, WINDOW_W, WINDOW_H])
	if not door.is_empty():
		gaps.append([door[0], DOOR_W, DOOR_H])
	_seg(a, b, gaps, mat if mat else m_conc, h)
	var d := (b - a).normalized()
	var out := _outward(zone, a, b)
	for w in wins:
		var p: Vector2 = a + d * float(w)
		_add_window(Vector3(p.x, 0, p.y), Vector3(out.x, 0, out.y), zone)
	if not door.is_empty():
		var p2: Vector2 = a + d * float(door[0])
		_add_door(Vector3(p2.x, 0, p2.y), rad_to_deg(atan2(-d.y, d.x)), door[1], door[2])


func _outward(zone: String, a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	return -n if _in_zone(zone, (a + b) * 0.5 + n) else n


# Wall station on the inside face of a wall of `zone`.
func _wall_buy(zone: String, a: Vector2, b: Vector2, dist: float, stype: String, wid: String, title: String, cost: int, acost: int, y: float = 1.55, inset: float = 0.32) -> void:
	var d := (b - a).normalized()
	var inn := -_outward(zone, a, b)
	var p: Vector2 = a + d * dist + inn * inset
	var col := Color(0.84, 0.78, 0.64)
	if stype == "ammo_box":
		col = Color(0.76, 0.62, 0.30)
	elif stype == "forge":
		col = Color(0.68, 0.16, 0.14)
	_spawn_station(stype, wid, title, cost, acost, col, Vector3(p.x, y, p.y), rad_to_deg(atan2(inn.x, inn.y)))


func _roof(center: Vector3, size: Vector2) -> void:
	_add_static_box(center, Vector3(size.x, 0.4, size.y), m_dark_conc)


func _post_light(pos: Vector3, col: Color, energy: float, rng: float, rot: float = 0.0) -> void:
	_prop("prop_lamp_post", pos, rot, Vector3(0.3, 4.0, 0.3), Vector3(0, 2.0, 0))
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy * 0.48
	l.omni_range = rng * 0.85
	l.position = pos + Vector3(0, 4.3, 0)
	add_child(l)


# Soft fill lights: dead until power is restored in the Warehouse Motor Pool
func _fill_lights(points: Array, col: Color, energy: float, rng: float) -> void:
	for p in points:
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 0.0
		l.omni_range = rng * 0.85
		l.position = p
		add_child(l)
		powered_lamps.append({"light": l, "fixture": null, "color": col, "energy": energy * 0.52})


func _place(script: GDScript, pos: Vector3, rot: float) -> Node3D:
	var n: Node3D = script.new()
	n.position = pos
	n.rotation_degrees.y = rot
	add_child(n)
	return n


# ---------------------------------------------------------------------------
# GROUND
# ---------------------------------------------------------------------------
func _build_ground() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)
	_add_static_box(Vector3(2.5, -0.25, -7.5), Vector3(150.0, 0.5, 140.0),
		MaterialLib.get_world("asphalt", 0.33, Color(0.88, 0.90, 0.96), 0.05, 1.0, 1.0, 0.0, true))
	var tile := MaterialLib.get_world("concrete_floor", 0.5, Color(0.56, 0.57, 0.6), 0.0, 1.0, 0.0, 0.0, true)
	_add_floor_tile(Vector3(1, 0, -31), Vector2(18, 30), tile)
	_add_floor_tile(Vector3(1, 0, -33), Vector2(42, 10), tile)
	_add_floor_tile(Vector3(35, 0, 0), Vector2(30, 24), tile)
	_add_floor_tile(Vector3(42, 0, 22), Vector2(16, 20), tile)
	var htile := MaterialLib.get_world("concrete_floor", 0.5, Color(0.62, 0.68, 0.66), 0.0, 0.9, 0.0, 0.0, true)
	_add_floor_tile(Vector3(-32, 0, -3), Vector2(24, 18), htile)
	_add_floor_tile(Vector3(-38, 0, -21), Vector2(12, 18), htile)


# ---------------------------------------------------------------------------
# TOWN PLAZA (start): a wide, eight-sided square around an old fountain
# ---------------------------------------------------------------------------
func _build_plaza() -> void:
	var P := zone_polys["plaza"][0] as PackedVector2Array
	_edge("plaza", P[0], P[1], [8.0], [], m_brick)
	_edge("church", P[1], P[2], [], [9.0, "church", 1000], m_stone, 8.0)
	_edge("plaza", P[2], P[3], [8.0], [], m_brick)
	_edge("warehouse", Vector2(20, -12), Vector2(20, 12), [], [14.0, "warehouse", 1250], m_dark_conc, 7.0)
	_edge("plaza", P[4], P[5], [5.0, 11.5], [], m_brick)
	_edge("rail", P[5], P[6], [], [9.0, "rail", 1500], m_fence, 3.4)
	_edge("plaza", P[6], P[7], [6.0], [], m_brick)
	_edge("hospital", Vector2(-20, -12), Vector2(-20, 6), [], [9.0, "hospital", 1250], m_conc)

	# Fountain in the middle: run trains around it
	_add_static_box(Vector3(0, 0.35, -2.0), Vector3(6.0, 0.7, 6.0), m_stone)
	_add_static_box(Vector3(0, 0.35, -2.0), Vector3(8.4, 0.7, 2.4), m_stone, Vector3(0, PI / 4.0, 0))
	_add_static_box(Vector3(0, 1.6, -2.0), Vector3(1.2, 1.8, 1.2), m_stone)
	var water := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(5.4, 0.04, 5.4)
	water.mesh = wm
	water.material_override = MaterialLib.get_emissive(Color(0.15, 0.35, 0.45), 0.6, 0.85)
	water.position = Vector3(0, 0.72, -2.0)
	add_child(water)
	var fl := OmniLight3D.new()
	fl.light_color = Color(0.32, 0.44, 0.56)
	fl.light_energy = 0.32
	fl.omni_range = 6.5
	fl.position = Vector3(0, 2.8, -2.0)
	add_child(fl)
	# Cover and scenery
	_prop("prop_car_wreck", Vector3(-12.0, 0, -4.0), 20.0, Vector3(1.9, 1.3, 4.3), Vector3(0, 0.65, 0))
	_prop("prop_rubble", Vector3(11.5, 0, -9.0), 30.0, Vector3(2.0, 0.6, 1.6), Vector3(0, 0.3, 0))
	_add_sandbags(Vector3(-6.0, 0, 6.5), 20.0)
	_add_sandbags(Vector3(7.5, 0, 2.0), -30.0)
	_add_crate_stack(Vector3(16.5, 0, 9.5), 2)
	for p in [Vector3(-16.0, 0, 8.0), Vector3(14.0, 0, -11.0), Vector3(4.0, 0, 13.0)]:
		_add_fire_barrel(p)
	for lp in [Vector3(-15.0, 0, -6.0), Vector3(15.0, 0, 3.0), Vector3(-6.0, 0, 12.5)]:
		_post_light(lp, Color(1.0, 0.82, 0.55), 2.2, 13.0)
	# Stations
	_wall_buy("plaza", P[0], P[1], 3.0, "weapon", "smg", "KURZ-9 SMG", 1000, 500)
	_wall_buy("plaza", P[2], P[3], 3.0, "weapon", "rifle", "COMMANDO M14A", 1200, 600)
	_place(FurnaceScript, Vector3(-15.5, 0.0, 3.0), 90.0)
	_place(load("res://scripts/world/supply_depot.gd") as GDScript, Vector3(17.0, 0.0, 5.0), -90.0)
	_place(SecondWindScript, Vector3(-4.5, 0.0, -13.5), 0.0)
	_skull(Vector3(0.0, 2.6, -2.0), 30.0)


# ---------------------------------------------------------------------------
# OLD CHURCH: cross-shaped, tall stone walls, rounded altar end
# ---------------------------------------------------------------------------
func _build_church() -> void:
	var H := 8.0
	_edge("church", Vector2(-8, -16), Vector2(-8, -28), [7.5], [], m_stone, H)
	_edge("church", Vector2(-8, -28), Vector2(-20, -28), [6.0], [], m_stone, H)
	_edge("church", Vector2(-20, -28), Vector2(-20, -38), [5.0], [], m_stone, H)
	_edge("church", Vector2(-20, -38), Vector2(-8, -38), [6.0], [], m_stone, H)
	_edge("church", Vector2(-8, -38), Vector2(-8, -46), [], [], m_stone, H)
	var apse := _apse_points()
	for i in range(apse.size() - 1):
		_edge("church", apse[i], apse[i + 1], [2.3] if i == 1 or i == 4 else [], [], m_stone, H)
	_edge("church", Vector2(10, -46), Vector2(10, -38), [], [], m_stone, H)
	_edge("church", Vector2(10, -38), Vector2(22, -38), [6.0], [], m_stone, H)
	_edge("cemetery", Vector2(22, -38), Vector2(22, -28), [], [5.0, "cemetery", 2000], m_stone, H)
	_edge("church", Vector2(22, -28), Vector2(10, -28), [6.0], [], m_stone, H)
	_edge("church", Vector2(10, -28), Vector2(10, -16), [4.5], [], m_stone, H)
	_roof(Vector3(1, H + 0.2, -31.0), Vector2(18.6, 30.6))
	_roof(Vector3(1, H + 0.2, -33.0), Vector2(42.6, 10.6))
	_roof(Vector3(1, H + 0.2, -50.5), Vector2(18.6, 9.6))
	# Pillars down the nave and pews between them
	for z in [-20.0, -25.0, -40.0, -44.0]:
		for x in [-4.5, 6.5]:
			_add_static_box(Vector3(x, H * 0.5, z), Vector3(0.9, H, 0.9), m_stone)
	for z in [-19.0, -21.5, -24.0, -26.5]:
		for x in [-2.5, 4.5]:
			_add_static_box(Vector3(x, 0.45, z), Vector3(3.2, 0.9, 0.6), m_wood)
	# Altar
	_add_static_box(Vector3(1, 0.6, -49.0), Vector3(4.0, 1.2, 1.6), m_stone)
	var candle_col := Color(1.0, 0.6, 0.3)
	for p in [Vector3(-2.0, 1.4, -49.0), Vector3(4.0, 1.4, -49.0)]:
		var c := OmniLight3D.new()
		c.light_color = candle_col
		c.light_energy = 1.6
		c.omni_range = 7.0
		c.position = p
		add_child(c)
		fire_lights.append(c)
	for p in [Vector3(1, 7.6, -22.0), Vector3(1, 7.6, -33.0), Vector3(-14, 7.6, -33.0), Vector3(16, 7.6, -33.0)]:
		_add_lamp(p, Color(1.0, 0.8, 0.55), 2.4, p.x > 10.0)
		(powered_lamps[-1]["light"] as OmniLight3D).omni_range = 17.0
	_fill_lights([Vector3(1, 5.0, -22.0), Vector3(1, 5.0, -40.0), Vector3(-14, 5.0, -33.0), Vector3(16, 5.0, -33.0)], Color(0.9, 0.7, 0.5), 0.9, 15.0)
	# Stations
	_place(CrateScript, Vector3(1.0, 0.0, -52.6), 180.0)
	_place(RadioScript, Vector3(-4.0, 0.0, -47.0), 135.0)
	_wall_buy("church", Vector2(-8, -16), Vector2(-8, -28), 3.0, "weapon", "shotgun", "TRENCH-12 PUMP", 1500, 750)
	_skull(Vector3(-4.5, H - 0.4, -44.0), 90.0)


func _apse_points() -> Array:
	var pts := []
	for i in range(7):
		var a := deg_to_rad(-30.0 * float(i))
		pts.append(Vector2(1.0 + 9.0 * cos(a), -46.0 + 9.0 * sin(a)))
	return pts


# ---------------------------------------------------------------------------
# WAREHOUSE: one huge L-shaped hall with racks and a truck
# ---------------------------------------------------------------------------
func _build_warehouse() -> void:
	var H := 7.0
	_edge("warehouse", Vector2(20, -12), Vector2(50, -12), [8.0, 22.0], [], m_dark_conc, H)
	_edge("warehouse", Vector2(50, -12), Vector2(50, 32), [8.0, 20.0, 36.0], [], m_dark_conc, H)
	_edge("warehouse", Vector2(50, 32), Vector2(34, 32), [8.0], [], m_dark_conc, H)
	_edge("warehouse", Vector2(34, 32), Vector2(34, 12), [6.0, 14.0], [], m_dark_conc, H)
	_edge("warehouse", Vector2(34, 12), Vector2(20, 12), [7.0], [], m_dark_conc, H)
	_roof(Vector3(35, H + 0.2, 0.0), Vector2(30.6, 24.6))
	_roof(Vector3(42, H + 0.2, 22.0), Vector2(16.6, 20.6))
	for x in [27.0, 35.0, 43.0]:
		_add_static_box(Vector3(x, H - 0.4, 0.0), Vector3(0.4, 0.6, 24.0), m_metal)
	# Racks (leave lanes free)
	for r in [[Vector3(28.0, 1.6, -6.5), Vector3(8.0, 3.2, 1.2)], [Vector3(28.0, 1.6, 7.0), Vector3(8.0, 3.2, 1.2)],
			[Vector3(45.0, 1.6, -7.0), Vector3(1.2, 3.2, 7.0)], [Vector3(38.0, 1.6, 26.0), Vector3(1.2, 3.2, 8.0)],
			[Vector3(46.0, 1.6, 18.0), Vector3(1.2, 3.2, 6.0)]]:
		_add_static_box(r[0], r[1], m_metal)
	if ResourceLoader.exists("res://assets/models/prop_truck.glb"):
		var truck: Node3D = (load("res://assets/models/prop_truck.glb") as PackedScene).instantiate()
		truck.position = Vector3(38.0, 0, 2.0)
		truck.rotation_degrees.y = 90.0
		add_child(truck)
	_add_invisible_collider(Vector3(37.6, 1.4, 2.0), Vector3(7.4, 2.8, 2.4), 0.0)
	_prop("prop_fuel_tank", Vector3(46.5, 0, 28.5), 0.0, Vector3(3.6, 2.1, 1.8), Vector3(0, 1.05, 0))
	_prop("prop_tire_stack", Vector3(48.4, 0, 9.5), 0.0, Vector3(0.9, 1.0, 0.9), Vector3(0, 0.5, 0))
	_add_crate_stack(Vector3(23.0, 0, 9.5), 2)
	_add_crate_stack(Vector3(36.5, 0, 14.5), 1)
	for p in [Vector3(27, 6.6, -3), Vector3(41, 6.6, -3), Vector3(34, 6.6, 8), Vector3(42, 6.6, 22)]:
		_add_lamp(p, Color(1.0, 0.9, 0.7), 2.6, p.x > 40.0 and p.z > 10.0)
		(powered_lamps[-1]["light"] as OmniLight3D).omni_range = 16.0
	_fill_lights([Vector3(27, 4.5, -3), Vector3(41, 4.5, -3), Vector3(30, 4.5, 8), Vector3(42, 4.5, 24)], Color(0.75, 0.8, 0.9), 0.8, 14.0)
	_place(GeneratorScript, Vector3(24.0, 0, -8.5), 0.0)
	_wall_buy("warehouse", Vector2(50, -12), Vector2(50, 32), 14.0, "weapon", "lmg", "RAZORBACK LMG", 3000, 1500)
	_wall_buy("warehouse", Vector2(20, -12), Vector2(50, -12), 15.0, "ammo_box", "", "AMMO CACHE", 450, 0)


# ---------------------------------------------------------------------------
# HOSPITAL: T-shaped, a corridor along the plaza and wards behind it
# ---------------------------------------------------------------------------
func _build_hospital() -> void:
	_edge("hospital", Vector2(-20, 6), Vector2(-44, 6), [6.0, 18.0])
	_edge("hospital", Vector2(-44, 6), Vector2(-44, -30), [8.0, 20.0, 30.0])
	_edge("hospital", Vector2(-44, -30), Vector2(-32, -30), [6.0])
	_edge("hospital", Vector2(-32, -30), Vector2(-32, -12), [9.0])
	_edge("hospital", Vector2(-32, -12), Vector2(-20, -12), [6.0])
	# Inside walls with open doorways
	_seg(Vector2(-32, -12), Vector2(-32, 6), [[4.0, 3.0, 3.2], [14.0, 3.0, 3.2]], m_conc)
	_seg(Vector2(-44, -3), Vector2(-32, -3), [[6.0, 3.0, 3.2]], m_conc)
	_seg(Vector2(-44, -12), Vector2(-32, -12), [[6.0, 3.0, 3.2]], m_conc)
	_roof(Vector3(-32, WALL_H + 0.2, -3.0), Vector2(24.6, 18.6))
	_roof(Vector3(-38, WALL_H + 0.2, -21.0), Vector2(12.6, 18.6))
	var lab_col := Color(0.75, 1.0, 0.85)
	for p in [Vector3(-26, 3.85, -3.0), Vector3(-38, 3.85, 1.5), Vector3(-38, 3.85, -7.5), Vector3(-38, 3.85, -21.0)]:
		_add_lamp(p, lab_col, 2.0, p.z < -15.0)
	for g in [[Vector3(-41.5, 0, 2.5), 90.0], [Vector3(-35.0, 0, 2.5), 90.0], [Vector3(-41.5, 0, -8.0), 90.0], [Vector3(-38.0, 0, -26.0), 0.0]]:
		_prop("prop_gurney", g[0], g[1], Vector3(0.8, 1.1, 2.0), Vector3(0, 0.55, 0))
	_prop("prop_lockers", Vector3(-21.0, 0, -9.0), -90.0, Vector3(2.0, 2.0, 0.55), Vector3(0, 1.0, 0))
	_prop("prop_desk", Vector3(-26.0, 0, 3.5), 0.0, Vector3(1.6, 1.0, 0.8), Vector3(0, 0.5, 0))
	var vat_glass := MaterialLib.get_emissive(Color(0.22, 0.65, 0.32), 0.9, 0.55)
	for p in [Vector3(-42.6, 0, -28.0), Vector3(-33.4, 0, -28.0), Vector3(-33.4, 0, -14.0)]:
		var vat := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.5
		cm.height = 2.0
		vat.mesh = cm
		vat.material_override = vat_glass
		vat.position = p + Vector3(0, 1.2, 0)
		add_child(vat)
		_add_static_box(p + Vector3(0, 0.1, 0), Vector3(1.3, 0.2, 1.3), m_metal)
		_add_invisible_collider(p + Vector3(0, 1.2, 0), Vector3(1.1, 2.4, 1.1), 0.0)
	_wall_buy("hospital", Vector2(-44, 6), Vector2(-44, -30), 13.0, "forge", "", "WEAPON FORGE", 5000, 0, 0.0, 2.8)
	_wall_buy("hospital", Vector2(-32, -12), Vector2(-20, -12), 3.0, "ammo_box", "", "AMMO CACHE", 450, 0)
	_place(SecondWindScript, Vector3(-43.4, 0.0, -18.0), 90.0)
	_skull(Vector3(-21.0, 2.05, -9.0), -90.0)


# ---------------------------------------------------------------------------
# RAIL STATION: a long open platform area with tracks and wagons
# ---------------------------------------------------------------------------
func _build_rail() -> void:
	var R := zone_polys["rail"][0] as PackedVector2Array
	_edge("rail", R[1], R[2], [9.0], [], m_fence, 3.4)
	_edge("rail", R[2], R[3], [8.0, 24.0, 40.0], [], m_fence, 3.4)
	_edge("rail", R[3], R[4], [8.0], [], m_fence, 3.4)
	_edge("rail", R[4], R[5], [8.0, 18.0], [], m_fence, 3.4)
	_edge("rail", R[5], R[0], [4.0], [], m_fence, 3.4)
	for tz in [21.0, 29.5]:
		for side in [-0.72, 0.72]:
			_add_static_box(Vector3(-20.0, 0.06, tz + side), Vector3(50.0, 0.12, 0.12), m_metal)
		for i in range(25):
			_add_static_box(Vector3(-44.0 + 2.0 * i, 0.03, tz), Vector3(0.3, 0.06, 2.0), m_wood)
	# Low platform between the tracks (low enough to walk onto)
	_add_static_box(Vector3(-20.0, 0.12, 25.2), Vector3(40.0, 0.24, 3.4), m_stone)
	# Wagons
	_add_static_box(Vector3(-30.0, 1.7, 29.5), Vector3(12.0, 3.0, 2.8), m_metal)
	_add_static_box(Vector3(-5.0, 1.5, 21.0), Vector3(9.0, 2.6, 2.8), m_brick)
	_prop("prop_car_wreck", Vector3(-38.0, 0, 21.5), 80.0, Vector3(1.9, 1.3, 4.3), Vector3(0, 0.65, 0))
	_add_crate_stack(Vector3(-42.5, 0, 31.5), 2)
	_add_crate_stack(Vector3(-12.0, 0, 32.0), 1)
	_add_sandbags(Vector3(-20.0, 0, 18.0), 0.0)
	for p in [Vector3(-26.0, 0, 32.5), Vector3(2.0, 0, 30.0)]:
		_add_fire_barrel(p)
	for lp in [Vector3(-36.0, 0, 25.2), Vector3(-20.0, 0, 25.2), Vector3(-4.0, 0, 25.2)]:
		_post_light(lp, Color(1.0, 0.82, 0.55), 2.0, 12.0)
	_wall_buy("rail", R[2], R[3], 16.0, "weapon", "revolver", ".44 HAND CANNON", 1750, 875)
	_wall_buy("rail", R[2], R[3], 32.0, "ammo_box", "", "AMMO CACHE", 450, 0)
	_skull(Vector3(-27.0, 3.4, 29.5), 0.0)


# ---------------------------------------------------------------------------
# CEMETERY: an uneven fenced field behind the church, graves and a crypt
# ---------------------------------------------------------------------------
func _build_cemetery() -> void:
	var C := zone_polys["cemetery"][0] as PackedVector2Array
	_edge("cemetery", C[1], C[2], [4.5], [], m_fence, 3.4)
	_edge("cemetery", C[2], C[3], [5.0, 11.0], [], m_fence, 3.4)
	_edge("cemetery", C[3], C[4], [8.0], [], m_fence, 3.4)
	_edge("cemetery", C[4], C[5], [8.0], [], m_fence, 3.4)
	_edge("cemetery", C[5], C[6], [6.0, 12.0], [], m_fence, 3.4)
	_edge("cemetery", C[6], C[0], [7.5], [], m_fence, 3.4)
	# Graves in loose rows
	for row in range(4):
		for i in range(6):
			var gp := Vector3(27.0 + 2.6 * float(i) + (1.3 if row % 2 == 1 else 0.0), 0.35, -30.0 - 3.6 * float(row))
			if gp.x > 44.0:
				continue
			_add_static_box(gp, Vector3(0.8, 0.7, 0.18), m_stone, Vector3(0, randf_range(-0.12, 0.12), 0))
	# Crypt
	_add_static_box(Vector3(44.0, 2.0, -44.0), Vector3(6.0, 4.0, 7.0), m_stone)
	_add_static_box(Vector3(44.0, 4.3, -44.0), Vector3(6.8, 0.6, 7.8), m_dark_conc)
	_spawn_station("weapon", "sniper", "LONGSHOT .50", 3500, 1750, Color(0.84, 0.78, 0.64), Vector3(40.68, 1.55, -44.0), -90.0)
	_spawn_station("ammo_box", "", "AMMO CACHE", 450, 0, Color(0.76, 0.62, 0.30), Vector3(44.0, 1.55, -40.18), 0.0)
	for t in [Vector3(30.0, 0, -46.0), Vector3(48.0, 0, -30.0), Vector3(36.0, 0, -50.0)]:
		_prop("prop_dead_tree", t, t.x * 7.0, Vector3(0.6, 3.0, 0.6), Vector3(0, 1.5, 0), 1.1)
	for lp in [Vector3(34.0, 0, -36.0), Vector3(46.0, 0, -36.0)]:
		_post_light(lp, Color(0.6, 0.75, 1.0), 1.8, 12.0)


# ---------------------------------------------------------------------------
# OUTSIDE: scenery around the town
# ---------------------------------------------------------------------------
func _build_outside() -> void:
	var trees := [Vector3(-55, 0, -40), Vector3(-58, 0, 10), Vector3(-30, 0, 45), Vector3(20, 0, 45), Vector3(62, 0, 10),
		Vector3(62, 0, -30), Vector3(10, 0, -62), Vector3(-25, 0, -55), Vector3(64, 0, -58), Vector3(-60, 0, 40),
		Vector3(-52, 0, -10), Vector3(40, 0, 44), Vector3(-10, 0, -60), Vector3(24, 0, -16), Vector3(-30, 0, -40)]
	for i in range(trees.size()):
		_prop("prop_dead_tree", trees[i], float(i) * 47.0, Vector3.ZERO, Vector3.ZERO, randf_range(0.9, 1.4))
	_prop("prop_radio_tower", Vector3(-52, 0, -50), 20.0, Vector3.ZERO, Vector3.ZERO)
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.1, 0.05)
	beacon.light_energy = 3.0
	beacon.omni_range = 8.0
	beacon.position = Vector3(-52, 22.4, -50)
	add_child(beacon)
	fire_lights.append(beacon)
	_prop("prop_car_wreck", Vector3(-30, 0, 9), 30.0, Vector3.ZERO, Vector3.ZERO)
	_prop("prop_car_wreck", Vector3(58, 0, -12), -60.0, Vector3.ZERO, Vector3.ZERO)
	_prop("prop_rubble", Vector3(-50, 0, 24), 0.0, Vector3.ZERO, Vector3.ZERO, 1.4)
	_prop("prop_rubble", Vector3(56, 0, 20), 70.0, Vector3.ZERO, Vector3.ZERO, 1.3)
	# Ruined buildings on the horizon
	for b in [[Vector3(-62, 6, -66), Vector3(14, 12, 10)], [Vector3(40, 9, -68), Vector3(18, 18, 8)], [Vector3(68, 5, 40), Vector3(8, 10, 16)],
			[Vector3(-66, 7, 48), Vector3(10, 14, 12)], [Vector3(12, 4, 54), Vector3(20, 8, 6)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[1]
		mi.mesh = bm
		mi.material_override = m_dark_conc
		mi.position = b[0]
		add_child(mi)


# Old blood stains on the floors (decals need the scene to be ready)
func _scatter_blood() -> void:
	if not is_inside_tree():
		return
	var spots := [Vector3(-3, 0, 6), Vector3(5, 0, -8), Vector3(-10, 0, 9), Vector3(1, 0, -24), Vector3(-12, 0, -33),
		Vector3(30, 0, 4), Vector3(42, 0, 20), Vector3(-28, 0, 0), Vector3(-38, 0, -18), Vector3(-25, 0, 27), Vector3(36, 0, -38),
		Vector3(-21, 0, -3), Vector3(-35, 0, 2), Vector3(-40, 0, -8), Vector3(1, 0, -45), Vector3(24, 0, -5), Vector3(0, 0, 4), Vector3(-8, 0, -12)]
	for sp in spots:
		FX.blood_decal(sp + Vector3(0, 0.02, 0), Vector3.UP, randf_range(1.1, 2.5))


func _make_polys() -> void:
	zone_polys["plaza"] = [PackedVector2Array([Vector2(-20, -10), Vector2(-8, -16), Vector2(10, -16), Vector2(20, -8),
		Vector2(20, 12), Vector2(4, 16), Vector2(-14, 14), Vector2(-20, 4)])]
	var church := PackedVector2Array([Vector2(-8, -16), Vector2(10, -16), Vector2(10, -28), Vector2(22, -28), Vector2(22, -38),
		Vector2(10, -38), Vector2(10, -46)])
	var apse := _apse_points()
	for i in range(1, apse.size() - 1):
		church.append(apse[i])
	church.append_array(PackedVector2Array([Vector2(-8, -46), Vector2(-8, -38), Vector2(-20, -38), Vector2(-20, -28), Vector2(-8, -28)]))
	zone_polys["church"] = [church]
	zone_polys["warehouse"] = [PackedVector2Array([Vector2(20, -12), Vector2(50, -12), Vector2(50, 32), Vector2(34, 32), Vector2(34, 12), Vector2(20, 12)])]
	zone_polys["hospital"] = [PackedVector2Array([Vector2(-20, -12), Vector2(-20, 6), Vector2(-44, 6), Vector2(-44, -30), Vector2(-32, -30), Vector2(-32, -12)])]
	zone_polys["rail"] = [PackedVector2Array([Vector2(-14, 14), Vector2(4, 16), Vector2(6, 34), Vector2(-46, 34), Vector2(-46, 18), Vector2(-22, 16)])]
	zone_polys["cemetery"] = [PackedVector2Array([Vector2(22, -38), Vector2(22, -28), Vector2(30, -24), Vector2(46, -26), Vector2(54, -40), Vector2(46, -54), Vector2(28, -52)])]


# Dim crimson bleed outside every boarded window so zombies silhouette in the dark
func _window_lights() -> void:
	for w in windows:
		var l := OmniLight3D.new()
		l.light_color = Color(0.75, 0.09, 0.06)
		l.light_energy = 0.36
		l.omni_range = 4.2
		l.position = w.position + w.basis.z * 2.6 + Vector3(0, 2.4, 0)
		add_child(l)


# ---------------------------------------------------------------------------
# BUILDING HELPERS AND SHARED PARTS
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_flicker_time += delta * 7.5
	for i in range(fire_lights.size()):
		var fl := fire_lights[i]
		fl.light_energy = 2.0 + sin(_flicker_time + float(i) * 1.9) * 0.42 + cos(_flicker_time * 2.3 + float(i)) * 0.22
	if power_on:
		for i in range(flicker_lamps.size()):
			var lamp := flicker_lamps[i]
			var n := sin(_flicker_time * 3.1 + float(i) * 7.0) + sin(_flicker_time * 7.7 + float(i))
			lamp.light_energy = 0.08 if n > 1.45 else 1.45
	else:
		var pulse := 0.20 + sin(_flicker_time * 0.35) * 0.10
		for d in powered_lamps:
			var l: OmniLight3D = d["light"]
			if d["fixture"] == null:
				l.light_energy = 0.0
			else:
				l.light_energy = pulse


func get_boss_spawn(player_pos: Vector3) -> Vector3:
	var best := Vector3(0, 0.1, -4.8)
	var best_d := -1.0
	for zid in boss_points:
		if not is_zone_open(zid):
			continue
		for p in boss_points[zid]:
			var d: float = (p as Vector3).distance_to(player_pos)
			if d > best_d:
				best_d = d
				best = p
	return best


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	world_env = env

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.005, 0.008, 0.014)
	sky_mat.sky_horizon_color = Color(0.016, 0.020, 0.028)
	sky_mat.ground_bottom_color = Color(0.004, 0.004, 0.006)
	sky_mat.ground_horizon_color = Color(0.012, 0.015, 0.020)
	# Stars, Milky Way, moonlit clouds and the moon itself
	if ResourceLoader.exists("res://assets/textures/sky_night.png"):
		sky_mat.sky_cover = load("res://assets/textures/sky_night.png")
		sky_mat.sky_cover_modulate = Color(0.28, 0.32, 0.40, 1.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.055, 0.070, 0.090)
	env.ambient_light_energy = 0.16
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.98
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.036
	env.volumetric_fog_albedo = Color(0.08, 0.095, 0.115)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.42, 0.50, 0.66)
	moon.light_energy = 0.24
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	add_child(moon)


func _add_lamp(pos: Vector3, col: Color, energy: float, flicker: bool) -> void:
	var fixture := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 0.12, 0.3)
	fixture.mesh = bm
	fixture.position = pos + Vector3(0, 0.2, 0)
	add_child(fixture)
	var l := OmniLight3D.new()
	l.light_color = EMERGENCY_RED
	l.light_energy = 0.20
	l.omni_range = 6.5
	l.position = pos
	add_child(l)
	fixture.material_override = MaterialLib.get_emissive(EMERGENCY_RED, 0.85)
	powered_lamps.append({"light": l, "fixture": fixture, "color": col, "energy": energy * 0.72})
	if flicker:
		flicker_lamps.append(l)


func set_power(on: bool) -> void:
	power_on = on
	for d in powered_lamps:
		var l: OmniLight3D = d["light"]
		l.light_color = d["color"]
		l.light_energy = d["energy"]
		if d["fixture"] != null:
			(d["fixture"] as MeshInstance3D).material_override = MaterialLib.get_emissive(d["color"], 2.4)


func skull_found() -> void:
	skulls_found += 1
	var player := get_tree().get_first_node_in_group("player")
	if skulls_found < 3:
		if player:
			player.status_banner_requested.emit("SOMETHING STIRS... (%d / 3)" % skulls_found, Color(0.4, 1.0, 0.55))
		return
	GameState.play_sfx("level_up", 0.0, 0.8)
	GameState.add_points(2500)
	if player:
		player.refill_all_ammo()
		player.status_banner_requested.emit("SECRET UNLOCKED! +2500 POINTS & MAX AMMO", Color(0.4, 1.0, 0.55))


func _prop(model: String, pos: Vector3, rot_deg: float, col_size: Vector3, col_off: Vector3, scale_f: float = 1.0) -> void:
	var path := "res://assets/models/%s.glb" % model
	if ResourceLoader.exists(path):
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		inst.position = pos
		inst.rotation_degrees.y = rot_deg
		inst.scale = Vector3.ONE * scale_f
		add_child(inst)
	if col_size != Vector3.ZERO:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.position = pos
		sb.rotation_degrees.y = rot_deg
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = col_size
		cs.shape = bs
		cs.position = col_off
		sb.add_child(cs)
		add_child(sb)


func _skull(pos: Vector3, rot_deg: float) -> void:
	var sk: StaticBody3D = SkullScript.new()
	sk.position = pos
	sk.rotation_degrees.y = rot_deg
	add_child(sk)


# Old blood stains on the floors (decals need the scene to be ready)


func _add_door(pos: Vector3, rot_y: float, zone_id: String, cost: int) -> void:
	var door: Node3D = ZoneDoorScript.new()
	door.zone_id = zone_id
	door.title = zone_names[zone_id]
	door.cost = cost
	door.width = DOOR_W
	door.height = DOOR_H
	door.position = pos
	door.rotation_degrees.y = rot_y
	add_child(door)
	door.opened.connect(_on_door_opened)


func _on_door_opened(zone_id: String) -> void:
	zones_open[zone_id] = true
	zone_opened.emit(zone_id)
	# The door's collider is freed at the end of this frame; rebake after that.
	await get_tree().process_frame
	_bake_navigation()


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
	nav_mesh.filter_baking_aabb = AABB(Vector3(-52.0, -1.0, -60.0), Vector3(112.0, 3.2, 100.0))
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, self)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	nav_region.navigation_mesh = nav_mesh


func _add_window(pos: Vector3, outward: Vector3, zone_id: String) -> void:
	var w: Node3D = BarricadeScript.new()
	w.zone_id = zone_id
	w.position = pos
	w.rotation.y = atan2(outward.x, outward.z)
	add_child(w)
	windows.append(w)
	# Window frame trim
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, WINDOW_H, WALL_T + 0.1)
		post.mesh = bm
		post.material_override = m_wood
		post.position = Vector3(side * (WINDOW_W * 0.5 + 0.02), WINDOW_H * 0.5, 0)
		w.add_child(post)


func _add_sandbags(pos: Vector3, rot_deg: float) -> void:
	if ResourceLoader.exists("res://assets/models/prop_sandbags.glb"):
		var inst := (load("res://assets/models/prop_sandbags.glb") as PackedScene).instantiate() as Node3D
		inst.position = pos
		inst.rotation_degrees.y = rot_deg
		inst.scale = Vector3.ONE * 1.35
		add_child(inst)
	_add_invisible_collider(pos + Vector3(0, 0.55, 0), Vector3(2.1, 1.1, 0.7), rot_deg)


func _add_crate_stack(pos: Vector3, height: int) -> void:
	for i in range(height):
		var s := 1.2 - float(i) * 0.15
		_add_static_box(pos + Vector3(randf_range(-0.1, 0.1), s * 0.5 + float(i) * 1.2, randf_range(-0.1, 0.1)), Vector3(s, s, s), m_wood, Vector3(0, randf_range(-0.3, 0.3), 0))


func _add_fire_barrel(bpos: Vector3) -> void:
	if ResourceLoader.exists("res://assets/models/prop_barrel.glb"):
		var b := (load("res://assets/models/prop_barrel.glb") as PackedScene).instantiate() as Node3D
		b.position = bpos
		b.scale = Vector3.ONE * 1.15
		add_child(b)
	_add_invisible_collider(bpos + Vector3(0, 0.55, 0), Vector3(0.8, 1.1, 0.8), 0.0)

	var flame_orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.55
	flame_orb.mesh = sm
	flame_orb.position = bpos + Vector3(0, 1.15, 0)
	flame_orb.material_override = MaterialLib.get_emissive(Color(1.0, 0.48, 0.10), 5.5, 0.85)
	add_child(flame_orb)

	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.56, 0.18)
	fl.light_energy = 2.8
	fl.omni_range = 11.0
	fl.position = bpos + Vector3(0, 1.65, 0)
	add_child(fl)
	fire_lights.append(fl)

	var sparks := CPUParticles3D.new()
	sparks.position = bpos + Vector3(0, 1.15, 0)
	sparks.amount = 18
	sparks.lifetime = 1.4
	sparks.direction = Vector3.UP
	sparks.spread = 22.0
	sparks.gravity = Vector3(0, 1.8, 0)
	sparks.initial_velocity_min = 0.8
	sparks.initial_velocity_max = 2.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.albedo_color = Color(1.0, 0.62, 0.16)
	if ResourceLoader.exists("res://assets/textures/soft_particle.png"):
		qmat.albedo_texture = load("res://assets/textures/soft_particle.png")
		qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = qmat
	sparks.mesh = quad
	add_child(sparks)


func _spawn_station(stype: String, wid: String, stitle: String, scost: int, sacost: int, col: Color, pos: Vector3, rot_y: float) -> void:
	var ws := WallStation.new()
	ws.station_type = stype
	ws.weapon_id = wid
	ws.title = stitle
	ws.cost = scost
	ws.ammo_cost = sacost
	ws.glow_color = col
	ws.position = pos
	ws.rotation_degrees.y = rot_y
	add_child(ws)


func _add_floor_tile(center: Vector3, size: Vector2, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.02, size.y)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center + Vector3(0, 0.011, 0)
	add_child(mi)


func _add_static_box(pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.position = pos
	sb.rotation = rot

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)

	add_child(sb)
	return sb


func _add_invisible_collider(pos: Vector3, size: Vector3, rot_y_deg: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.position = pos
	sb.rotation_degrees.y = rot_y_deg
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
