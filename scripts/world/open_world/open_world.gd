class_name OpenWorld
extends BunkerArena
# THE COUNTY - open-world map (1 km x 1 km). Rolling hills walled in by
# mountains, roads linking five locations. The land between them ("wilds")
# is always open; inside each location the classic loop still runs: buy the
# doors into buildings, turn the power on at the plant, board the windows.
#   DEPOT (start)  gas station, diner, bus garage          (0, 0)
#   FARM           farmhouse, barn, silo, fields           (-280, 160)
#   VILLAGE        houses and a schoolhouse                (260, 220)
#   TOWN           main street of shops, police station    (300, -240)
#   POWER PLANT    turbine hall with the generator          (-260, -260)
# Every location pad and road sits at y = 0, so all the old gameplay pieces
# (doors, barricades, wall buys, stations) work unchanged on flat ground.
# Built from the Blender world kit (art/blender/build_world_kit.py).

const KIT := "res://art/models/%s.glb"
const NAV_TILE := 96.0
const NAV_CELL := 0.25

var terrain: OpenTerrain
var map_min := Vector2(-512, -512)
var map_max := Vector2(512, 512)
var locations: Dictionary = {}  # id -> {"name", "center": Vector3}
var _road_mats: Dictionary = {}
var _scenes: Dictionary = {}
var _nav_source: NavigationMeshSourceGeometryData3D
var _nav_tiles: Dictionary = {}  # Vector2i -> NavigationRegion3D
var _nav_busy := false
var _nav_dirty := false
var _player: Node3D


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	add_to_group("arena")
	zones_open = {"wilds": true, "diner": true}
	zone_names = {"wilds": "THE COUNTY", "diner": "DINER"}
	boss_points = {}
	zone_polys = {}
	player_spawn = Vector3(14.0, 0.3, -15.0)  # inside the depot diner
	lz_pos = Vector3(-232.0, 0.0, -226.0)
	m_conc = MaterialLib.get_world("concrete", 0.5, Color(0.8, 0.8, 0.82), 0.0, 1.0, 0.0, 0.5)
	m_dark_conc = MaterialLib.get_world("concrete", 0.5, Color(0.5, 0.51, 0.55), 0.0, 1.0, 0.0, 0.4)
	m_wood = MaterialLib.get_world("wood_planks", 0.5, Color(0.9, 0.85, 0.78), 0.0, 1.0, 0.0, 0.3)
	m_stone = MaterialLib.get_world("stone_block", 0.4, Color(0.9, 0.88, 0.85), 0.0, 1.0, 0.0, 0.6)
	m_brick = MaterialLib.get_world("brick", 0.6, Color(0.95, 0.92, 0.9), 0.0, 1.0, 0.0, 0.5)
	m_metal = MaterialLib.get_world("rusted_metal", 0.5, Color(0.85, 0.82, 0.8), 0.35, 0.9, 0.0, 0.25)
	m_fence = m_metal
	_build_environment()
	world_env.volumetric_fog_density = 0.009
	_make_locations()
	_layout_land()
	terrain.build()
	_build_roads()
	for loc in _locs:
		loc.build()
		_register(loc.id, loc.title, Vector3(loc.center.x, 0, loc.center.y))
	_build_wilds()
	_psx_subdivide(self)
	print("OpenWorld built in %d ms" % (Time.get_ticks_msec() - t0))
	_setup_navigation.call_deferred()


# ---------------------------------------------------------------- land + roads
# Roads stop at each place's edge (or join its own street) so no road ever
# runs through a building. [points, width, texture]
const ROADS := [
	[[Vector2(-44, 30), Vector2(44, 30)], 10.0, "asphalt"],                                   # depot street
	[[Vector2(44, 30), Vector2(120, 100), Vector2(236, 214)], 10.0, "asphalt"],              # -> checkpoint -> village
	[[Vector2(214, 220), Vector2(310, 220)], 8.0, "asphalt"],                                 # village street
	[[Vector2(270, 216), Vector2(275, 180), Vector2(330, 0), Vector2(303, -190), Vector2(303, -232)], 10.0, "asphalt"],
	[[Vector2(230, -240), Vector2(372, -240)], 12.0, "asphalt"],                              # Greymill main street
	[[Vector2(236, -244), Vector2(0, -280), Vector2(-208, -262)], 10.0, "asphalt"],           # town -> plant
	[[Vector2(-270, -208), Vector2(-330, -40), Vector2(-287, 112), Vector2(-284, 150)], 7.0, "dirt_road"],
	[[Vector2(-230, 153), Vector2(-150, 100), Vector2(-120, 90), Vector2(-44, 30)], 7.0, "dirt_road"],
	[[Vector2(0, -34), Vector2(0, -280)], 8.0, "dirt_road"],
	[[Vector2(0, -112), Vector2(104, -112)], 6.0, "dirt_road"],                               # campground spur
]
const LOCATION_SCRIPTS := [
	"res://scripts/world/open_world/locations/loc_depot.gd",
	"res://scripts/world/open_world/locations/loc_farm.gd",
	"res://scripts/world/open_world/locations/loc_village.gd",
	"res://scripts/world/open_world/locations/loc_town.gd",
	"res://scripts/world/open_world/locations/loc_plant.gd",
	"res://scripts/world/open_world/locations/loc_checkpoint.gd",
	"res://scripts/world/open_world/locations/loc_trailer_park.gd",
	"res://scripts/world/open_world/locations/loc_campground.gd",
]
var _locs: Array = []
var pads: Array[Rect2] = []


func _make_locations() -> void:
	for path in LOCATION_SCRIPTS:
		var loc: OWLocation = (load(path) as GDScript).new()
		loc.w = self
		_locs.append(loc)
		pads.append(loc.pad)


func get_location(lid: String) -> OWLocation:
	for loc in _locs:
		if loc.id == lid:
			return loc
	return null


func _layout_land() -> void:
	terrain = OpenTerrain.new()
	terrain.name = "Terrain"
	for r in pads:
		terrain.add_flat(r)
	for rd in ROADS:
		terrain.add_road(PackedVector2Array(rd[0]), rd[1])
	add_child(terrain)


func _road_mat(tex: String) -> Material:
	if _road_mats.has(tex):
		return _road_mats[tex]
	var m := ShaderMaterial.new()
	m.shader = MaterialLib.PS1Shader
	m.set_shader_parameter("albedo_texture", load("res://art/textures/%s_albedo.png" % tex))
	m.set_shader_parameter("albedo_color", Color(0.9, 0.9, 0.92))
	m.set_shader_parameter("surface_roughness", 0.9)
	_road_mats[tex] = m
	return m


# Flat strips of 4 m quads along each road polyline (UV v runs along the road).
func _build_roads() -> void:
	for rd in ROADS:
		var pts: Array = rd[0]
		var w: float = rd[1]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var v_acc := 0.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x) * w * 0.5
			var steps := int(ceil(a.distance_to(b) / 4.0))
			for s in range(steps):
				var p0 := a.lerp(b, float(s) / steps)
				var p1 := a.lerp(b, float(s + 1) / steps)
				var v0 := v_acc / w
				v_acc += p0.distance_to(p1)
				var v1 := v_acc / w
				var y := 0.03 + float(i) * 0.0005
				var q := [Vector3(p0.x - n.x, y, p0.y - n.y), Vector3(p0.x + n.x, y, p0.y + n.y),
					Vector3(p1.x + n.x, y, p1.y + n.y), Vector3(p1.x - n.x, y, p1.y - n.y)]
				var uv := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
				for k in [0, 2, 1, 0, 3, 2]:
					st.set_normal(Vector3.UP)
					st.set_uv(uv[k])
					st.add_vertex(q[k])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _road_mat(rd[2])
		add_child(mi)


# ---------------------------------------------------------------- kit placing
func _kit(name: String, pos: Vector3, rot_deg: float = 0.0, scale_f: float = 1.0) -> Node3D:
	var path := KIT % name
	if not _scenes.has(path):
		if not ResourceLoader.exists(path):
			push_warning("world kit piece missing: " + name)
			return null
		_scenes[path] = load(path)
	var inst: Node3D = (_scenes[path] as PackedScene).instantiate()
	inst.position = pos
	inst.rotation_degrees.y = rot_deg
	if scale_f != 1.0:
		inst.scale = Vector3.ONE * scale_f
	add_child(inst)
	# small dressing fades out with distance (the fog hides it anyway), so a
	# dense map costs nothing for the places you are not standing in
	var vis := _vis_range(name)
	if vis > 0.0:
		for g in inst.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).visibility_range_end = vis
			(g as GeometryInstance3D).visibility_range_end_margin = 6.0
	return inst


func _vis_range(name: String) -> float:
	if name.begins_with("int_"):
		return 55.0
	if name in ["ext_bush", "ext_corn", "prop_mailbox", "ext_trash_can", "ext_hydrant", "ext_campfire", "ext_picnic_table",
			"prop_hay_bale", "ext_stop_sign", "prop_barrel", "prop_tire_stack", "ext_sign_board", "ext_awning"]:
		return 110.0
	if name in ["ext_pine", "prop_dead_tree", "prop_rubble", "prop_utility_pole", "prop_fence_wood", "prop_fence_metal"]:
		return 240.0
	return 0.0


const SIDE_ROT := {"n": 0.0, "s": 180.0, "w": 90.0, "e": -90.0}
const SIDE_OUT := {"n": Vector3(0, 0, -1), "s": Vector3(0, 0, 1), "w": Vector3(-1, 0, 0), "e": Vector3(1, 0, 0)}


func _slot_pos(r: Rect2, side: String, slot: int) -> Vector3:
	match side:
		"n": return Vector3(r.position.x + 2.0 + slot * 4.0, 0, r.position.y)
		"s": return Vector3(r.position.x + 2.0 + slot * 4.0, 0, r.end.y)
		"w": return Vector3(r.position.x, 0, r.position.y + 2.0 + slot * 4.0)
	return Vector3(r.end.x, 0, r.position.y + 2.0 + slot * 4.0)


# A building from kit pieces on a 4 m grid.
#  zone: buyable zone id ("" = part of the wilds / sealed facade)
#  doors: [[side, slot, cost]] cost 0 = open doorway, -1 = the zone's buy door
#  wins:  [[side, slot]] boarded windows zombies break through
#  roof: "flat" | "gable" | "tin"
func _building(r: Rect2, style: String, zone: String, doors: Array, wins: Array, roof: String,
		floor_kind: String = "concrete", zone_cost: int = 0) -> void:
	var cols := int(r.size.x / 4.0)
	var rows := int(r.size.y / 4.0)
	var special := {}
	for d in doors:
		special["%s%d" % [d[0], d[1]]] = ["door", d[2]]
	for w in wins:
		special["%s%d" % [w[0], w[1]]] = ["window", 0]
	for side in ["n", "s", "w", "e"]:
		var count := cols if side in ["n", "s"] else rows
		for slot in range(count):
			var p := _slot_pos(r, side, slot)
			var key := "%s%d" % [side, slot]
			var rot: float = SIDE_ROT[side]
			if special.has(key):
				# Outbreak rules (Cold War's open maps): no buy doors, no
				# barricades. Doorways are just open, windows are glazed.
				var kind: String = special[key][0]
				_kit("wall_%s_%s" % [style, "door" if kind == "door" else "glass"], p, rot)
			else:
				_kit("wall_%s_glass" % style if slot % 2 == 1 else "wall_%s" % style, p, rot)
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		_kit("corner_" + style, Vector3(c.x, 0, c.y))
	for j in range(rows):
		for i in range(cols):
			_kit("floor_" + floor_kind, Vector3(r.position.x + 2 + i * 4, 0, r.position.y + 2 + j * 4))
	if roof == "flat":
		for j in range(rows):
			for i in range(cols):
				_kit("roof_flat", Vector3(r.position.x + 2 + i * 4, 0, r.position.y + 2 + j * 4))
		for side in ["n", "s", "w", "e"]:
			var count := cols if side in ["n", "s"] else rows
			for slot in range(count):
				_kit("parapet_" + style, _slot_pos(r, side, slot), SIDE_ROT[side])
	else:
		var along_x := r.size.x >= r.size.y
		var span := int(r.size.y if along_x else r.size.x)
		var piece := ("roof_gable_%d" if roof == "gable" else "roof_tin_%d") % span
		var c := r.get_center()
		var n := cols if along_x else rows
		for k in range(n):
			if along_x:
				_kit(piece, Vector3(r.position.x + 2 + k * 4, 0, c.y), 0.0)
			else:
				_kit(piece, Vector3(c.x, 0, r.position.y + 2 + k * 4), 90.0)
		if along_x:
			_kit("gable_%s_%d" % [style, span], Vector3(r.position.x, 0, c.y), 90.0)
			_kit("gable_%s_%d" % [style, span], Vector3(r.end.x, 0, c.y), -90.0)
		else:
			_kit("gable_%s_%d" % [style, span], Vector3(c.x, 0, r.position.y), 0.0)
			_kit("gable_%s_%d" % [style, span], Vector3(c.x, 0, r.end.y), 180.0)
	if zone != "":
		zone_polys[zone] = [PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])]
		boss_points[zone] = [Vector3(r.get_center().x, 0.1, r.get_center().y)]
		if not zones_open.has(zone):
			zones_open[zone] = true
	# ceiling lamps run on emergency red until the power is on
	var lc := r.get_center()
	_add_lamp(Vector3(lc.x, 3.85, lc.y), Color(1.0, 0.9, 0.75), 2.2, false)


const STATION_COL := {"weapon": Color(0.25, 0.88, 1.0), "ammo_box": Color(1.0, 0.78, 0.2), "forge": Color(0.72, 0.3, 1.0)}


# Wall buy on the inside face of a building wall slot.
func _buy(r: Rect2, side: String, slot: int, stype: String, wid: String, title: String, cost: int, acost: int) -> void:
	var p := _slot_pos(r, side, slot)
	var inn: Vector3 = -SIDE_OUT[side]
	var y := 0.0 if stype == "forge" else 1.55
	var inset := 2.8 if stype == "forge" else 0.32
	p += inn * inset + Vector3(0, y, 0)
	_spawn_station(stype, wid, title, cost, acost, STATION_COL.get(stype, Color.WHITE), p, rad_to_deg(atan2(inn.x, inn.z)))


func _slab(rect: Rect2, tex: String = "concrete_floor") -> void:
	var c := rect.get_center()
	_add_floor_tile(Vector3(c.x, 0.02, c.y), rect.size, MaterialLib.get_world(tex, 0.5, Color(0.8, 0.8, 0.8), 0.0, 1.0, 0.0, 0.0, true))


func _fence_line(a: Vector2, b: Vector2, piece: String = "prop_fence_wood") -> void:
	var d := b - a
	var n := int(round(d.length() / 4.0))
	var rot := rad_to_deg(atan2(-d.y, d.x))
	for i in range(n):
		var p := a.lerp(b, (i + 0.5) / n)
		_kit(piece, Vector3(p.x, 0, p.y), rot)


func _register(id: String, title: String, center: Vector3) -> void:
	locations[id] = {"name": title, "center": center}


# ---------------------------------------------------------------- locations
# Trees, rocks, wrecks and poles out in the county, on the terrain surface.
func _build_wilds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# woods: pines grow in clumps where a forest noise is high; between them
	# dead trees, brush and rock piles thin out across open fields
	var woods := FastNoiseLite.new()
	woods.seed = 31
	woods.frequency = 0.012
	var placed := 0
	var tries := 0
	while placed < 720 and tries < 9000:
		tries += 1
		var p := Vector2(rng.randf_range(-470, 470), rng.randf_range(-470, 470))
		if _near_flat(p, 8.0):
			continue
		var h := terrain.height_at(p.x, p.y)
		if h > 34.0:
			continue
		var forest := woods.get_noise_2d(p.x, p.y)
		var roll := rng.randf()
		var kind := ""
		if forest > 0.15:
			kind = "ext_pine" if roll < 0.7 else ("ext_bush" if roll < 0.92 else "prop_dead_tree")
		elif roll < 0.18:
			kind = "prop_dead_tree"
		elif roll < 0.3:
			kind = "ext_bush"
		elif roll < 0.34:
			kind = "prop_rubble"
		else:
			continue
		var s := rng.randf_range(0.85, 1.45)
		_kit(kind, Vector3(p.x, h - 0.15, p.y), rng.randf() * 360.0, s)
		if kind == "prop_dead_tree":
			_add_invisible_collider(Vector3(p.x, h + 1.5, p.y), Vector3(0.6 * s, 3.0, 0.6 * s), 0.0)
		placed += 1
	# utility poles + the odd wreck along each road
	for rd in ROADS:
		var pts: Array = rd[0]
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var d := (b - a).normalized()
			var side := Vector2(-d.y, d.x) * (float(rd[1]) * 0.5 + 2.0)
			var n := int(a.distance_to(b) / 36.0)
			for k in range(1, n):
				var p: Vector2 = a.lerp(b, float(k) / n) + side
				if _near_flat_pads(p, 4.0):
					continue
				_kit("prop_utility_pole", Vector3(p.x, 0, p.y), rad_to_deg(atan2(-d.y, d.x)))
				if rng.randf() < 0.12:
					var w := a.lerp(b, float(k) / n) - side * 0.4
					_prop("prop_car_wreck", Vector3(w.x, 0, w.y), rad_to_deg(atan2(d.x, d.y)) + rng.randf_range(-25, 25),
						Vector3(1.9, 1.3, 4.3), Vector3(0, 0.65, 0))


func _near_flat(p: Vector2, margin: float) -> bool:
	if _near_flat_pads(p, margin):
		return true
	for rd in ROADS:
		var pts: Array = rd[0]
		for i in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			if p.distance_to(q) < float(rd[1]) * 0.5 + margin:
				return true
	return false


func _near_flat_pads(p: Vector2, margin: float) -> bool:
	for r in pads:
		if r.grow(margin).has_point(p):
			return true
	return false


func _add_vehicle(model: String, title: String, pos: Vector3, rot: float) -> void:
	var v := DriveVehicle.new()
	v.model = model
	v.title = title
	v.position = pos
	v.rotation_degrees.y = rot
	add_child(v)


# ---------------------------------------------------------------- zones + spawns
func zone_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	for zid in zone_polys:
		if _in_zone(zid, q):
			return zid
	return "wilds"


func location_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	for loc in _locs:
		if (loc.pad as Rect2).grow(12.0).has_point(q):
			return loc.id
	return ""


# A walkable point 26-44 m from the focus (zombies jog in from the dark).
func open_spawn_point(focus: Vector3, near: float = 26.0, far: float = 44.0) -> Vector3:
	var map := get_world_3d().navigation_map
	# Outbreak style: out of sight (behind the camera when we can), on the
	# ground navmesh, and with a real path to the player (no roofs, no
	# sealed shop interiors, no islands).
	var cam := get_viewport().get_camera_3d()
	var view := -cam.global_basis.z if cam else Vector3.ZERO
	view.y = 0.0
	var goal := NavigationServer3D.map_get_closest_point(map, focus)
	for i in range(24):
		var ang := randf() * TAU
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		if i < 16 and view.length() > 0.1 and dir.dot(view.normalized()) > 0.35:
			continue
		var d := randf_range(near, far)
		var c := focus + dir * d
		c.y = terrain.height_at(c.x, c.z)
		var s := NavigationServer3D.map_get_closest_point(map, c)
		if s == Vector3.ZERO or s.distance_to(c) > 3.0 or s.distance_to(focus) < near * 0.8:
			continue
		if absf(s.y - c.y) > 1.5:
			continue  # a roof or a ledge, not the ground
		var path := NavigationServer3D.map_get_path(map, s, goal, true)
		if path.is_empty() or path[path.size() - 1].distance_to(goal) > 2.5:
			continue
		return s + Vector3(0, 0.1, 0)
	var c2 := focus + Vector3(near, 0, 0)
	return Vector3(c2.x, terrain.height_at(c2.x, c2.z) + 0.5, c2.z)


func get_boss_spawn(player_pos: Vector3) -> Vector3:
	return open_spawn_point(player_pos, 30.0, 50.0)


func _on_door_opened(zone_id: String) -> void:
	zones_open[zone_id] = true
	zone_opened.emit(zone_id)
	await get_tree().process_frame
	_nav_dirty = true


func _bake_navigation() -> void:
	pass  # streamed tiles instead (see below)


# ---------------------------------------------------------------- navigation
# The county is too big for one navmesh, so it is baked in 96 m tiles around
# the players on a worker thread, from geometry parsed once (and again after
# a door opens). Tiles share edges, so paths run seamlessly across them.
func _setup_navigation() -> void:
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, NAV_CELL)
	NavigationServer3D.map_set_cell_height(map, 0.25)
	NavigationServer3D.map_set_edge_connection_margin(map, 0.6)
	var t1 := Time.get_ticks_msec()
	_parse_nav()
	print("nav parse %d ms" % (Time.get_ticks_msec() - t1))
	_player = get_tree().get_first_node_in_group("player")
	# the spawn tiles are baked right away so round 1 has a navmesh
	var t := _tile_of(player_spawn)
	for dj in range(-1, 2):
		for di in range(-1, 2):
			_bake_tile(t + Vector2i(di, dj), false)
	print("nav spawn tiles %d ms" % (Time.get_ticks_msec() - t1))


func _nav_template() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = NAV_CELL
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 42.0
	nm.border_size = 1.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	return nm


func _parse_nav() -> void:
	_nav_source = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_nav_template(), _nav_source, self)


func _tile_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / NAV_TILE), floori(p.z / NAV_TILE))


func _bake_tile(t: Vector2i, async: bool) -> void:
	var region: NavigationRegion3D = _nav_tiles.get(t)
	if region == null:
		region = NavigationRegion3D.new()
		region.name = "NavTile_%d_%d" % [t.x, t.y]
		add_child(region)
		_nav_tiles[t] = region
	var nm := _nav_template()
	var x0 := t.x * NAV_TILE
	var z0 := t.y * NAV_TILE
	nm.filter_baking_aabb = AABB(Vector3(x0, -20.0, z0), Vector3(NAV_TILE, 140.0, NAV_TILE))
	if async:
		_nav_busy = true
		NavigationServer3D.bake_from_source_geometry_data_async(nm, _nav_source, func():
			region.navigation_mesh = nm
			_nav_busy = false)
	else:
		NavigationServer3D.bake_from_source_geometry_data(nm, _nav_source)
		region.navigation_mesh = nm


var _rescue_t := 0.0


# Anything that slips under the land (a shove off a ledge, a bad spawn) is
# put back on the surface instead of falling forever.
func _rescue_fallen(delta: float) -> void:
	_rescue_t -= delta
	if _rescue_t > 0.0:
		return
	_rescue_t = 1.0
	for n in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("vehicles") + get_tree().get_nodes_in_group("player"):
		var b := n as Node3D
		if b == null:
			continue
		var g := terrain.height_at(b.global_position.x, b.global_position.z)
		if b.global_position.y < g - 3.0:
			b.global_position = Vector3(b.global_position.x, g + 1.0, b.global_position.z)
			if b is CharacterBody3D:
				(b as CharacterBody3D).velocity = Vector3.ZERO
			elif b is RigidBody3D:
				(b as RigidBody3D).linear_velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if terrain:
		_rescue_fallen(delta)
	if _nav_source == null or _nav_busy:
		return
	if _nav_dirty:
		_nav_dirty = false
		_parse_nav()
		for t in _nav_tiles.keys():
			_nav_tiles[t].set_meta("stale", true)
	# bake the nearest missing (or stale) tile around any player
	var best := Vector2i(9999, 9999)
	var best_d := 1e9
	for pl in get_tree().get_nodes_in_group("player"):
		var ct := _tile_of((pl as Node3D).global_position)
		for dj in range(-1, 2):
			for di in range(-1, 2):
				var t := ct + Vector2i(di, dj)
				if absi(t.x) > 6 or absi(t.y) > 6:
					continue
				var have: NavigationRegion3D = _nav_tiles.get(t)
				if have and not have.get_meta("stale", false):
					continue
				var d := float(di * di + dj * dj)
				if d < best_d:
					best_d = d
					best = t
	if best.x != 9999:
		if _nav_tiles.has(best):
			_nav_tiles[best].set_meta("stale", false)
		_bake_tile(best, true)
