class_name PvpMapArena
extends BunkerArena
# Dedicated competitive PvP battlegrounds sharing BunkerArena's public API and
# world helpers: "dockyard" (Ironclad Dockyard), "black_site" (Sub-Zero Black
# Site), and "quarry" (Sunscorch Refinery).
# Built with strict NavMesh clearance, flush 20° beveled deck ramps, vaultable
# <= 1.0m low cover, obstacle-free 4x4 spawn courtyards per sector (96 slots),
# solid perimeter boundaries, and zero visual rail collisions.

var map_id: String = "dockyard"
var _bounds: Rect2 = Rect2(Vector2(-42.0, -36.0), Vector2(84.0, 72.0))
var _spawn_centers: Dictionary = {}
var _spawn_y: Dictionary = {}
var _hotspots: Array[Vector3] = []
var _objectives_snd: Array = []
var _objectives_dom: Array = []


func _init(p_map_id: String = "dockyard") -> void:
	map_id = p_map_id if p_map_id in ["dockyard", "black_site", "quarry"] else "dockyard"


func _ready() -> void:
	add_to_group("arena")
	_init_base_materials()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)

	match map_id:
		"dockyard":
			_build_dockyard()
		"black_site":
			_build_black_site()
		"quarry":
			_build_quarry()

	for zk in zone_polys.keys():
		zones_open[zk] = true
	set_power(true)
	_bake_navigation()


# ---------------------------------------------------------------------------
# POLYMORPHIC MAP CONTRACT
# ---------------------------------------------------------------------------
func get_map_id() -> String:
	return map_id


func get_map_title() -> String:
	match map_id:
		"dockyard": return "IRONCLAD DOCKYARD"
		"black_site": return "SUB-ZERO BLACK SITE"
		"quarry": return "SUNSCORCH REFINERY"
	return "OUTPOST NACHT-7"


func get_map_bounds() -> Rect2:
	return _bounds


func get_pvp_sector_zones() -> Dictionary:
	match map_id:
		"dockyard":
			return {
				0: "pier_west",
				1: "pier_east",
				2: "helipad",
				3: "drydock",
				4: "customs_nw",
				5: "rigging_se",
			}
		"black_site":
			return {
				0: "cryo_west",
				1: "armory_east",
				2: "radar_north",
				3: "reactor_south",
				4: "barracks_nw",
				5: "motor_se",
			}
		"quarry":
			return {
				0: "convoy_west",
				1: "crusher_east",
				2: "derrick_north",
				3: "depot_south",
				4: "boneyard_nw",
				5: "spur_se",
			}
	return super.get_pvp_sector_zones()


func get_pvp_spawn_points() -> Dictionary:
	var out: Dictionary = {}
	for tid in range(6):
		var c: Vector2 = _spawn_centers.get(tid, Vector2.ZERO)
		var sy: float = float(_spawn_y.get(tid, 0.0))
		out[tid] = _grid_spawns_4x4(c, 2.75, 2.75, sy)
	return out


func get_pvp_objectives(mode_id: String) -> Array:
	if mode_id == "snd":
		return _objectives_snd
	if mode_id == "dom":
		return _objectives_dom
	return []


func get_pvp_hotspots() -> Array[Vector3]:
	return _hotspots


# ---------------------------------------------------------------------------
# SHARED GEOMETRY & ENVIRONMENT HELPERS
# ---------------------------------------------------------------------------
func _setup_grid_zones(xs: Array[float], zs: Array[float], defs: Array) -> void:
	zone_polys.clear()
	zone_names.clear()
	zones_open.clear()
	for d in defs:
		var zid: String = String(d["id"])
		var zname: String = String(d["name"])
		var col: int = int(d["col"])
		var row: int = int(d["row"])
		var x0: float = xs[col]
		var x1: float = xs[col + 1]
		var z0: float = zs[row]
		var z1: float = zs[row + 1]
		zone_names[zid] = zname
		zones_open[zid] = true
		zone_polys[zid] = [PackedVector2Array([
			Vector2(x0, z0),
			Vector2(x1, z0),
			Vector2(x1, z1),
			Vector2(x0, z1),
		])]


func _grid_spawns_4x4(center: Vector2, step_x: float = 2.75, step_z: float = 2.75, y: float = 0.0) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for gz in range(4):
		for gx in range(4):
			var ox: float = (float(gx) - 1.5) * step_x
			var oz: float = (float(gz) - 1.5) * step_z
			pts.append(Vector3(center.x + ox, y, center.y + oz))
	return pts


func _build_map_environment(sky_top: Color, sky_hor: Color, g_bot: Color, g_hor: Color,
		amb_col: Color, amb_e: float, sun_col: Color, sun_e: float, sun_rot: Vector3,
		exposure: float = 1.06) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	world_env = env

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = sky_hor
	sky_mat.ground_bottom_color = g_bot
	sky_mat.ground_horizon_color = g_hor
	sky_mat.sun_angle_max = 16.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = amb_col
	env.ambient_light_energy = amb_e
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = exposure
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.14
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.volumetric_fog_density = 0.0
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = sun_col
	sun.light_energy = sun_e
	sun.shadow_enabled = true
	sun.rotation_degrees = sun_rot
	add_child(sun)


func _add_vista_perimeter(r: Rect2, wall_h: float, wall_mat: Material, cap_mat: Material) -> void:
	var x0: float = r.position.x
	var x1: float = r.position.x + r.size.x
	var z0: float = r.position.y
	var z1: float = r.position.y + r.size.y
	var cx: float = (x0 + x1) * 0.5
	var cz: float = (z0 + z1) * 0.5
	var w: float = r.size.x
	var d: float = r.size.y
	var t: float = 0.8

	# Visible parapet seawall / retaining wall (lets players see ocean/peaks/mesas beyond)
	_add_static_box(Vector3(cx, wall_h * 0.5, z0 - t * 0.5), Vector3(w + t * 2.0, wall_h, t), wall_mat)
	_add_static_box(Vector3(cx, wall_h * 0.5, z1 + t * 0.5), Vector3(w + t * 2.0, wall_h, t), wall_mat)
	_add_static_box(Vector3(x0 - t * 0.5, wall_h * 0.5, cz), Vector3(t, wall_h, d), wall_mat)
	_add_static_box(Vector3(x1 + t * 0.5, wall_h * 0.5, cz), Vector3(t, wall_h, d), wall_mat)

	# Contrasting cap rail trim
	_add_visual_box(Vector3(cx, wall_h + 0.06, z0 - t * 0.5), Vector3(w + t * 2.1, 0.12, t + 0.14), cap_mat)
	_add_visual_box(Vector3(cx, wall_h + 0.06, z1 + t * 0.5), Vector3(w + t * 2.1, 0.12, t + 0.14), cap_mat)
	_add_visual_box(Vector3(x0 - t * 0.5, wall_h + 0.06, cz), Vector3(t + 0.14, 0.12, d), cap_mat)
	_add_visual_box(Vector3(x1 + t * 0.5, wall_h + 0.06, cz), Vector3(t + 0.14, 0.12, d), cap_mat)

	# Full-height invisible clip above parapet so players/bots/grenades stay in-bounds
	var inv_h: float = 4.6
	_add_invisible_collider(Vector3(cx, inv_h * 0.5, z0 - t * 0.5), Vector3(w + t * 2.0, inv_h, t), 0.0)
	_add_invisible_collider(Vector3(cx, inv_h * 0.5, z1 + t * 0.5), Vector3(w + t * 2.0, inv_h, t), 0.0)
	_add_invisible_collider(Vector3(x0 - t * 0.5, inv_h * 0.5, cz), Vector3(t, inv_h, d), 0.0)
	_add_invisible_collider(Vector3(x1 + t * 0.5, inv_h * 0.5, cz), Vector3(t, inv_h, d), 0.0)


func _add_beveled_deck(center: Vector2, size: Vector2, h: float, deck_mat: Material, trim_mat: Material) -> void:
	_add_static_box(Vector3(center.x, h * 0.5, center.y), Vector3(size.x, h, size.y), deck_mat)
	var rw: float = 0.72
	var pitch: float = deg_to_rad(20.0)
	var hx: float = size.x * 0.5
	var hz: float = size.y * 0.5
	var ramp_y: float = h * 0.42
	# Flush 20° ramps on all 4 sides so bots and players glide cleanly up/down
	_add_static_box(Vector3(center.x, ramp_y, center.y - hz - rw * 0.34), Vector3(size.x, 0.10, rw), trim_mat, Vector3(pitch, 0.0, 0.0))
	_add_static_box(Vector3(center.x, ramp_y, center.y + hz + rw * 0.34), Vector3(size.x, 0.10, rw), trim_mat, Vector3(-pitch, 0.0, 0.0))
	_add_static_box(Vector3(center.x - hx - rw * 0.34, ramp_y, center.y), Vector3(rw, 0.10, size.y), trim_mat, Vector3(0.0, 0.0, -pitch))
	_add_static_box(Vector3(center.x + hx + rw * 0.34, ramp_y, center.y), Vector3(rw, 0.10, size.y), trim_mat, Vector3(0.0, 0.0, pitch))


func _make_painted_metal(col: Color, rough: float = 0.48, metallic: float = 0.42) -> Material:
	return MaterialLib.get_world("panzer_steel", 0.5, col.lightened(0.18), metallic, rough, 0.0, 0.12)


func _add_container_closed(pos: Vector3, rot_deg: float, col: Color, length: float = 6.2, width: float = 2.5, height: float = 2.65) -> void:
	var mat := _make_painted_metal(col, 0.46, 0.44)
	_add_static_box(pos + Vector3(0.0, height * 0.5, 0.0), Vector3(length, height, width), mat, Vector3(0.0, deg_to_rad(rot_deg), 0.0))
	# Visual frame trim strips along top and bottom for crisp silhouette
	var trim := _make_painted_metal(col.darkened(0.45), 0.5, 0.55)
	_add_visual_box(pos + Vector3(0.0, height - 0.08, 0.0), Vector3(length + 0.08, 0.16, width + 0.08), trim, Vector3(0.0, deg_to_rad(rot_deg), 0.0))


func _add_container_open(pos: Vector3, rot_deg: float, col: Color, length: float = 6.2, inner_w: float = 2.7) -> void:
	# Walkthrough container: side walls + high roof (>= 2.85m clearance so NavMesh bakes cleanly inside!)
	var mat := _make_painted_metal(col, 0.48, 0.42)
	var trim := _make_painted_metal(col.darkened(0.42), 0.5, 0.55)
	var yaw: float = deg_to_rad(rot_deg)
	var basis := Basis(Vector3.UP, yaw)
	var wall_h: float = 2.95
	var wt: float = 0.22
	var off_z: float = (inner_w + wt) * 0.5
	for side in [-1.0, 1.0]:
		var wp: Vector3 = pos + basis * Vector3(0.0, wall_h * 0.5, side * off_z)
		_add_static_box(wp, Vector3(length, wall_h, wt), mat, Vector3(0.0, yaw, 0.0))
	var roof_p: Vector3 = pos + basis * Vector3(0.0, wall_h + 0.12, 0.0)
	_add_static_box(roof_p, Vector3(length, 0.24, inner_w + wt * 2.0), trim, Vector3(0.0, yaw, 0.0))


func _add_waist_cover(pos: Vector3, length: float, rot_deg: float, mat: Material, h: float = 0.96, depth: float = 0.55) -> void:
	_add_static_box(pos + Vector3(0.0, h * 0.5, 0.0), Vector3(length, h, depth), mat, Vector3(0.0, deg_to_rad(rot_deg), 0.0))


func _add_canopy_bay(center: Vector2, size: Vector2, roof_y: float, pillar_mat: Material, roof_mat: Material) -> void:
	var hx: float = size.x * 0.5 - 0.35
	var hz: float = size.y * 0.5 - 0.35
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_static_box(Vector3(center.x + sx * hx, roof_y * 0.5, center.y + sz * hz), Vector3(0.55, roof_y, 0.55), pillar_mat)
	_add_static_box(Vector3(center.x, roof_y + 0.18, center.y), Vector3(size.x, 0.36, size.y), roof_mat)


# ===========================================================================
# MAP 2: IRONCLAD DOCKYARD (84m x 72m Coastal Shipping Port)
# ===========================================================================
func _build_dockyard() -> void:
	_bounds = Rect2(Vector2(-42.0, -36.0), Vector2(84.0, 72.0))
	var xs: Array[float] = [-42.0, -14.0, 14.0, 42.0]
	var zs: Array[float] = [-36.0, -12.0, 12.0, 36.0]
	_setup_grid_zones(xs, zs, [
		{"id": "pier_west", "name": "WEST PIER", "col": 0, "row": 1},
		{"id": "cargo_hub", "name": "CARGO HUB", "col": 1, "row": 1},
		{"id": "pier_east", "name": "EAST PIER", "col": 2, "row": 1},
		{"id": "helipad", "name": "NORTH HELIPAD", "col": 1, "row": 0},
		{"id": "drydock", "name": "SOUTH DRYDOCK", "col": 1, "row": 2},
		{"id": "customs_nw", "name": "CUSTOMS SHED", "col": 0, "row": 0},
		{"id": "gantry_ne", "name": "CHOPPER APRON", "col": 2, "row": 0},
		{"id": "fuel_sw", "name": "FUEL QUAY", "col": 0, "row": 2},
		{"id": "rigging_se", "name": "RIGGING YARD", "col": 2, "row": 2},
	])

	player_spawn = Vector3(-34.0, 0.1, 0.0)
	_spawn_centers = {
		0: Vector2(-34.0, 0.0),
		1: Vector2(34.0, 0.0),
		2: Vector2(0.0, -30.5),
		3: Vector2(0.0, 30.5),
		4: Vector2(-33.5, -28.0),
		5: Vector2(33.5, 28.0),
	}
	_spawn_y = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0}
	_objectives_snd = [
		{"id": "A", "label": "HELIPAD A", "kind": "bomb_site", "pos": Vector3(0.0, 0.20, -19.0)},
		{"id": "B", "label": "DRYDOCK B", "kind": "bomb_site", "pos": Vector3(0.0, 0.0, 19.5)},
	]
	_objectives_dom = [
		{"id": "A", "label": "WEST PIER A", "kind": "dom_flag", "pos": Vector3(-21.5, 0.0, 0.0)},
		{"id": "B", "label": "CARGO B", "kind": "dom_flag", "pos": Vector3(0.0, 0.20, 0.0)},
		{"id": "C", "label": "EAST PIER C", "kind": "dom_flag", "pos": Vector3(21.5, 0.0, 0.0)},
	]
	_hotspots = [
		Vector3(0.0, 0.20, 0.0),
		Vector3(-21.5, 0.0, 0.0),
		Vector3(21.5, 0.0, 0.0),
		Vector3(0.0, 0.20, -19.0),
		Vector3(0.0, 0.0, 19.5),
		Vector3(22.0, 0.0, -19.0),
		Vector3(-22.0, 0.0, 19.0),
		Vector3(-21.0, 0.0, -18.0),
		Vector3(21.0, 0.0, 18.0),
	]

	_build_map_environment(
		Color(0.11, 0.36, 0.70), Color(0.66, 0.84, 0.96),
		Color(0.08, 0.20, 0.30), Color(0.46, 0.66, 0.80),
		Color(0.58, 0.68, 0.78), 0.84,
		Color(1.0, 0.95, 0.86), 2.15, Vector3(-44.0, -35.0, 0.0)
	)

	# Pier foundation + surrounding ocean water plane
	var dock_asphalt := MaterialLib.get_world("asphalt", 0.35, Color(0.68, 0.72, 0.76), 0.02, 0.85, 0.55, 0.2, true)
	_add_static_box(Vector3(0.0, -0.30, 0.0), Vector3(88.0, 0.60, 76.0), dock_asphalt)

	var ocean := MeshInstance3D.new()
	var om := PlaneMesh.new()
	om.size = Vector2(280.0, 260.0)
	ocean.mesh = om
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.05, 0.22, 0.34)
	water_mat.roughness = 0.08
	water_mat.metallic = 0.30
	water_mat.metallic_specular = 0.9
	ocean.material_override = water_mat
	ocean.position = Vector3(0.0, -1.15, 0.0)
	add_child(ocean)

	# Floor apron tiles & yellow hazard perimeter paint
	var dock_conc := MaterialLib.get_world("concrete_floor", 0.5, Color(0.64, 0.68, 0.72), 0.0, 0.9, 0.0, 0.1, true)
	_add_floor_tile(Vector3(0.0, 0.0, 0.0), Vector2(28.0, 24.0), dock_conc)
	_add_floor_tile(Vector3(0.0, 0.0, -24.0), Vector2(24.0, 22.0), dock_conc)
	_add_floor_tile(Vector3(0.0, 0.0, 24.0), Vector2(24.0, 22.0), dock_conc)

	var yellow_trim := _make_painted_metal(Color(0.95, 0.72, 0.16), 0.45, 0.3)
	_add_vista_perimeter(_bounds, 1.25, m_conc, yellow_trim)

	# Central Cargo Hub: 0.20m beveled deck + gantry crane arch + 2 walkthrough containers
	_add_beveled_deck(Vector2(0.0, 0.0), Vector2(9.2, 9.2), 0.20, dock_conc, yellow_trim)
	var crane_orange := _make_painted_metal(Color(0.92, 0.42, 0.12), 0.42, 0.48)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_static_box(Vector3(sx * 11.8, 3.2, sz * 9.8), Vector3(0.85, 6.4, 0.85), crane_orange)
	# Overhead crane beams at y = 6.5m (clear above NavMesh)
	_add_visual_box(Vector3(0.0, 6.55, -9.8), Vector3(24.8, 0.75, 0.95), crane_orange)
	_add_visual_box(Vector3(0.0, 6.55, 9.8), Vector3(24.8, 0.75, 0.95), crane_orange)
	_add_visual_box(Vector3(-4.0, 6.55, 0.0), Vector3(1.1, 0.65, 20.6), crane_orange)
	_add_visual_box(Vector3(4.0, 6.55, 0.0), Vector3(1.1, 0.65, 20.6), crane_orange)

	_add_container_open(Vector3(-8.5, 0.0, -6.5), 0.0, Color(0.16, 0.44, 0.66))
	_add_container_open(Vector3(8.5, 0.0, 6.5), 0.0, Color(0.72, 0.26, 0.18))
	_add_waist_cover(Vector3(-7.0, 0.0, 5.2), 2.8, 90.0, m_dark_conc)
	_add_waist_cover(Vector3(7.0, 0.0, -5.2), 2.8, 90.0, m_dark_conc)
	for bp in [Vector3(-10.2, 0.0, 9.8), Vector3(10.2, 0.0, -9.8), Vector3(-5.8, 0.0, -10.8), Vector3(5.8, 0.0, 10.8)]:
		_barrel(bp)

	# Symmetric West & East Piers (16v16 mirror lanes; ±34,0 courtyards strictly clear)
	for side in [-1.0, 1.0]:
		_add_container_closed(Vector3(side * 22.0, 0.0, -7.8), 0.0, Color(0.18, 0.42, 0.68) if side < 0.0 else Color(0.68, 0.26, 0.20))
		_add_container_closed(Vector3(side * 22.0, 0.0, 7.8), 0.0, Color(0.24, 0.52, 0.42))
		_add_waist_cover(Vector3(side * 16.5, 0.0, 0.0), 3.4, 90.0, m_dark_conc)
		_add_sandbags(Vector3(side * 26.8, 0.0, -10.2), 25.0 if side < 0.0 else -25.0)
		_add_sandbags(Vector3(side * 26.8, 0.0, 10.2), -25.0 if side < 0.0 else 25.0)
		_barrel(Vector3(side * 17.5, 0.0, -10.5))
		_barrel(Vector3(side * 17.5, 0.0, 10.5))
		_post_light(Vector3(side * 26.5, 0.0, -11.0), Color(0.75, 0.90, 1.0), 1.8, 12.0, 90.0 if side < 0.0 else -90.0)

	# North Helipad (Team 2 spawn courtyard centered at (0, -30.5) stays open)
	_add_beveled_deck(Vector2(0.0, -19.0), Vector2(10.5, 8.5), 0.20, m_dark_conc, yellow_trim)
	_add_visual_box(Vector3(-1.4, 0.206, -19.0), Vector3(0.38, 0.012, 3.6), yellow_trim)
	_add_visual_box(Vector3(1.4, 0.206, -19.0), Vector3(0.38, 0.012, 3.6), yellow_trim)
	_add_visual_box(Vector3(0.0, 0.206, -19.0), Vector3(2.8, 0.012, 0.38), yellow_trim)
	_add_waist_cover(Vector3(-8.2, 0.0, -19.0), 2.8, 90.0, yellow_trim)
	_add_waist_cover(Vector3(8.2, 0.0, -19.0), 2.8, 90.0, yellow_trim)
	_barrel(Vector3(-11.0, 0.0, -23.0))

	# South Drydock (Team 3 spawn courtyard centered at (0, 30.5) stays open)
	_add_canopy_bay(Vector2(0.0, 19.5), Vector2(11.6, 8.2), 4.4, m_metal, m_dark_conc)
	_add_waist_cover(Vector3(-9.5, 0.0, 19.5), 2.8, 90.0, yellow_trim)
	_add_waist_cover(Vector3(9.5, 0.0, 19.5), 2.8, 90.0, yellow_trim)
	_barrel(Vector3(11.2, 0.0, 22.8))

	# NE Chopper Apron
	_prop("vehicle_helicopter", Vector3(28.5, 0.0, -24.5), 215.0, Vector3(4.0, 2.5, 8.6), Vector3(0.0, 1.25, 0.0))
	_add_sandbags(Vector3(21.5, 0.0, -17.5), -35.0)
	_barrel(Vector3(24.0, 0.0, -28.0))
	_add_waist_cover(Vector3(18.0, 0.0, -24.5), 3.0, 90.0, m_dark_conc)

	# SW Fuel Quay
	_prop("prop_fuel_tank", Vector3(-30.0, 0.0, 21.5), 0.0, Vector3(2.2, 2.8, 4.6), Vector3(0.0, 1.4, 0.0))
	_prop("prop_fuel_tank", Vector3(-30.0, 0.0, 28.5), 0.0, Vector3(2.2, 2.8, 4.6), Vector3(0.0, 1.4, 0.0))
	_add_container_open(Vector3(-20.0, 0.0, 18.5), 90.0, Color(0.22, 0.36, 0.52))
	_barrel(Vector3(-24.5, 0.0, 24.5))

	# NW Customs Shed (Team 4 spawn at (-33.5, -28.0) strictly clear)
	_add_canopy_bay(Vector2(-20.5, -26.5), Vector2(8.5, 8.5), 4.2, m_conc, m_dark_conc)
	_add_container_open(Vector3(-20.5, 0.0, -17.5), 0.0, Color(0.55, 0.38, 0.20))
	_add_sandbags(Vector3(-25.8, 0.0, -16.5), 35.0)
	_barrel(Vector3(-17.5, 0.0, -32.5))

	# SE Rigging Yard (Team 5 spawn at (33.5, 28.0) strictly clear)
	_add_container_closed(Vector3(21.0, 0.0, 17.5), 0.0, Color(0.20, 0.44, 0.56))
	_add_container_open(Vector3(21.0, 0.0, 25.5), 90.0, Color(0.76, 0.50, 0.16))
	_add_waist_cover(Vector3(25.5, 0.0, 16.5), 3.0, 35.0, yellow_trim)
	_barrel(Vector3(17.5, 0.0, 32.0))

	# Offshore Cargo Ships (out-of-bounds vista)
	_add_offshore_ship(Vector3(0.0, -1.0, -58.0), 0.0)
	_add_offshore_ship(Vector3(64.0, -1.0, 0.0), 90.0)


func _add_offshore_ship(pos: Vector3, rot_deg: float) -> void:
	var hull_mat := _make_painted_metal(Color(0.14, 0.17, 0.22), 0.65, 0.3)
	var deck_mat := _make_painted_metal(Color(0.32, 0.16, 0.14), 0.7, 0.25)
	var white_mat := _make_painted_metal(Color(0.84, 0.87, 0.90), 0.5, 0.2)
	var yaw: float = deg_to_rad(rot_deg)
	var b := Basis(Vector3.UP, yaw)
	_add_visual_box(pos + b * Vector3(0.0, 2.2, 0.0), Vector3(54.0, 4.8, 12.0), hull_mat, Vector3(0.0, yaw, 0.0))
	_add_visual_box(pos + b * Vector3(0.0, 4.7, 0.0), Vector3(52.0, 0.4, 11.4), deck_mat, Vector3(0.0, yaw, 0.0))
	_add_visual_box(pos + b * Vector3(19.0, 8.8, 0.0), Vector3(8.5, 8.0, 9.6), white_mat, Vector3(0.0, yaw, 0.0))
	var cols := [Color(0.18, 0.44, 0.72), Color(0.74, 0.24, 0.18), Color(0.82, 0.56, 0.16), Color(0.18, 0.52, 0.40)]
	for i in range(4):
		var cmat := _make_painted_metal(cols[i], 0.55, 0.35)
		_add_visual_box(pos + b * Vector3(-14.0 + float(i) * 8.2, 6.8, -2.2), Vector3(7.2, 3.6, 3.8), cmat, Vector3(0.0, yaw, 0.0))
		_add_visual_box(pos + b * Vector3(-14.0 + float(i) * 8.2, 6.8, 2.2), Vector3(7.2, 3.6, 3.8), cmat, Vector3(0.0, yaw, 0.0))


# ===========================================================================
# MAP 3: SUB-ZERO BLACK SITE (90m x 90m Polar Cryo-Lab & Missile Silo)
# ===========================================================================
func _build_black_site() -> void:
	_bounds = Rect2(Vector2(-45.0, -45.0), Vector2(90.0, 90.0))
	var xs: Array[float] = [-45.0, -15.0, 15.0, 45.0]
	var zs: Array[float] = [-45.0, -15.0, 15.0, 45.0]
	_setup_grid_zones(xs, zs, [
		{"id": "cryo_west", "name": "CRYO LAB", "col": 0, "row": 1},
		{"id": "silo_core", "name": "SILO ROTUNDA", "col": 1, "row": 1},
		{"id": "armory_east", "name": "ORDNANCE BAY", "col": 2, "row": 1},
		{"id": "radar_north", "name": "RADAR ARRAY", "col": 1, "row": 0},
		{"id": "reactor_south", "name": "REACTOR HALL", "col": 1, "row": 2},
		{"id": "barracks_nw", "name": "CRYO BARRACKS", "col": 0, "row": 0},
		{"id": "comms_ne", "name": "COMMS BUNKER", "col": 2, "row": 0},
		{"id": "helipad_sw", "name": "ICEFIELD PAD", "col": 0, "row": 2},
		{"id": "motor_se", "name": "SNOWCAT DEPOT", "col": 2, "row": 2},
	])

	player_spawn = Vector3(-37.0, 0.1, 0.0)
	_spawn_centers = {
		0: Vector2(-37.0, 0.0),
		1: Vector2(37.0, 0.0),
		2: Vector2(0.0, -37.0),
		3: Vector2(0.0, 37.0),
		4: Vector2(-36.5, -36.5),
		5: Vector2(36.5, 36.5),
	}
	_spawn_y = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0}
	_objectives_snd = [
		{"id": "A", "label": "RADAR A", "kind": "bomb_site", "pos": Vector3(0.0, 0.0, -22.5)},
		{"id": "B", "label": "REACTOR B", "kind": "bomb_site", "pos": Vector3(0.0, 0.0, 22.5)},
	]
	_objectives_dom = [
		{"id": "A", "label": "CRYO A", "kind": "dom_flag", "pos": Vector3(-22.5, 0.0, 0.0)},
		{"id": "B", "label": "SILO B", "kind": "dom_flag", "pos": Vector3(5.8, 0.22, 0.0)},
		{"id": "C", "label": "ORDNANCE C", "kind": "dom_flag", "pos": Vector3(22.5, 0.0, 0.0)},
	]
	_hotspots = [
		Vector3(5.8, 0.22, 0.0),
		Vector3(-5.8, 0.22, 0.0),
		Vector3(-22.5, 0.0, 0.0),
		Vector3(22.5, 0.0, 0.0),
		Vector3(0.0, 0.0, -22.5),
		Vector3(0.0, 0.0, 22.5),
		Vector3(23.0, 0.0, -23.0),
		Vector3(-23.0, 0.0, 23.0),
		Vector3(-23.0, 0.0, -23.0),
	]

	_build_map_environment(
		Color(0.16, 0.44, 0.78), Color(0.80, 0.90, 0.98),
		Color(0.45, 0.56, 0.68), Color(0.86, 0.93, 0.99),
		Color(0.68, 0.78, 0.92), 0.90,
		Color(0.92, 0.97, 1.0), 2.10, Vector3(-38.0, -42.0, 0.0),
		1.04
	)

	var snow_mat := MaterialLib.get_world("concrete", 0.3, Color(0.88, 0.94, 0.99), 0.0, 0.94, 0.0, 0.15, true)
	var panzer := MaterialLib.get_world("panzer_steel", 0.45, Color(0.44, 0.50, 0.58), 0.45, 0.42, 0.0, 0.15, true)
	var slate_floor := MaterialLib.get_world("concrete_floor", 0.5, Color(0.36, 0.42, 0.48), 0.12, 0.72, 0.0, 0.1, true)
	var cyan_trim := MaterialLib.get_emissive(Color(0.22, 0.88, 1.0), 2.2)

	# Outer snowfield & compound foundation
	_add_static_box(Vector3(0.0, -0.30, 0.0), Vector3(94.0, 0.60, 94.0), snow_mat)
	var vista_snow := MeshInstance3D.new()
	var vsm := PlaneMesh.new()
	vsm.size = Vector2(300.0, 300.0)
	vista_snow.mesh = vsm
	vista_snow.material_override = snow_mat
	vista_snow.position = Vector3(0.0, -0.65, 0.0)
	add_child(vista_snow)

	_add_floor_tile(Vector3(0.0, 0.0, 0.0), Vector2(30.0, 30.0), slate_floor)
	_add_floor_tile(Vector3(-25.0, 0.0, 0.0), Vector2(20.0, 22.0), slate_floor)
	_add_floor_tile(Vector3(25.0, 0.0, 0.0), Vector2(20.0, 22.0), slate_floor)
	_add_floor_tile(Vector3(0.0, 0.0, -22.5), Vector2(22.0, 14.0), slate_floor)
	_add_floor_tile(Vector3(0.0, 0.0, 22.5), Vector2(22.0, 14.0), slate_floor)

	_add_vista_perimeter(_bounds, 1.30, panzer, MaterialLib.get_world("gunmetal", 0.5, Color(0.55, 0.62, 0.70), 0.6, 0.45))

	# Central Silo Rotunda: 0.22m beveled blast deck + central sealed ICBM silo hatch + angled blast walls
	_add_beveled_deck(Vector2(0.0, 0.0), Vector2(15.6, 15.6), 0.22, slate_floor, panzer)
	var silo_cap := MeshInstance3D.new()
	var scm := CylinderMesh.new()
	scm.top_radius = 2.4
	scm.bottom_radius = 2.6
	scm.height = 1.9
	scm.radial_segments = 24
	silo_cap.mesh = scm
	silo_cap.material_override = panzer
	silo_cap.position = Vector3(0.0, 1.15, 0.0)
	add_child(silo_cap)
	HitboxRig.attach_ballistic_trimesh(silo_cap, "metal")
	_add_invisible_collider(Vector3(0.0, 1.25, 0.0), Vector3(4.3, 2.3, 4.3), 0.0)

	var silo_ring := MeshInstance3D.new()
	var srm := CylinderMesh.new()
	srm.top_radius = 2.66
	srm.bottom_radius = 2.66
	srm.height = 0.14
	srm.radial_segments = 24
	silo_ring.mesh = srm
	silo_ring.material_override = cyan_trim
	silo_ring.position = Vector3(0.0, 0.30, 0.0)
	add_child(silo_ring)

	# 4 angled blast bunker walls on the Silo perimeter leaving wide 6m cardinal & diagonal breach lanes
	for signs in [[-1.0, -1.0, 45.0], [1.0, -1.0, -45.0], [-1.0, 1.0, -45.0], [1.0, 1.0, 45.0]]:
		var sx: float = float(signs[0])
		var sz: float = float(signs[1])
		var ang: float = float(signs[2])
		_add_static_box(Vector3(sx * 10.6, 1.8, sz * 10.6), Vector3(5.2, 3.6, 0.75), panzer, Vector3(0.0, deg_to_rad(ang), 0.0))
	_add_waist_cover(Vector3(-6.2, 0.22, -4.6), 2.6, 90.0, panzer)
	_add_waist_cover(Vector3(6.2, 0.22, 4.6), 2.6, 90.0, panzer)
	for bp in [Vector3(-12.2, 0.0, -5.5), Vector3(12.2, 0.0, 5.5), Vector3(-5.5, 0.0, 12.2), Vector3(5.5, 0.0, -12.2)]:
		_barrel(bp)

	# West Cryo Lab (T0 spawn at (-37, 0) strictly clear)
	for cz in [-7.5, 7.5]:
		_add_cryo_vat(Vector3(-22.8, 0.0, cz), panzer, cyan_trim)
	for cz in [-10.5, 10.5]:
		_add_cryo_vat(Vector3(-29.2, 0.0, cz), panzer, cyan_trim)
	_add_waist_cover(Vector3(-17.5, 0.0, 0.0), 3.4, 90.0, panzer)
	_prop("prop_med_station", Vector3(-25.0, 0.0, -13.0), 0.0, Vector3(1.6, 2.0, 0.9), Vector3(0.0, 1.0, 0.0))

	# East Ordnance Bay (T1 spawn at (37, 0) strictly clear)
	_add_crate_stack(Vector3(23.0, 0.0, -7.5), 2)
	_add_crate_stack(Vector3(23.0, 0.0, 7.5), 2)
	_prop("prop_lockers", Vector3(29.2, 0.0, -10.5), 0.0, Vector3(2.2, 2.1, 0.9), Vector3(0.0, 1.05, 0.0))
	_prop("prop_lockers", Vector3(29.2, 0.0, 10.5), 180.0, Vector3(2.2, 2.1, 0.9), Vector3(0.0, 1.05, 0.0))
	_add_waist_cover(Vector3(17.5, 0.0, 0.0), 3.4, 90.0, panzer)
	_barrel(Vector3(19.0, 0.0, -10.5))

	# North Radar Array (T2 spawn at (0, -37) strictly clear; Site A at (0, 0, -22.5))
	_prop("prop_radio_tower", Vector3(-8.8, 0.0, -22.5), 0.0, Vector3(1.8, 4.2, 1.8), Vector3(0.0, 2.1, 0.0))
	_prop("prop_radio_console", Vector3(8.8, 0.0, -22.5), -90.0, Vector3(1.8, 1.6, 1.2), Vector3(0.0, 0.8, 0.0))
	_add_waist_cover(Vector3(0.0, 0.0, -27.2), 4.0, 0.0, panzer)

	# South Reactor Hall (T3 spawn at (0, 37) strictly clear; Site B at (0, 0, 22.5))
	_add_canopy_bay(Vector2(0.0, 22.5), Vector2(12.2, 8.2), 4.6, panzer, m_dark_conc)
	_prop("prop_generator", Vector3(-8.8, 0.0, 22.5), 0.0, Vector3(2.2, 1.8, 1.6), Vector3(0.0, 0.9, 0.0))
	_prop("prop_trap_pylon", Vector3(8.8, 0.0, 22.5), 0.0, Vector3(1.0, 2.4, 1.0), Vector3(0.0, 1.2, 0.0))
	_add_waist_cover(Vector3(0.0, 0.0, 27.2), 4.0, 0.0, panzer)

	# NW Barracks / NE Comms / SW Icefield / SE Snowcat Depot
	_add_canopy_bay(Vector2(-22.5, -22.5), Vector2(8.0, 8.0), 4.2, panzer, m_dark_conc)
	_add_fire_barrel(Vector3(-28.0, 0.0, -24.5))
	_add_waist_cover(Vector3(-22.5, 0.0, -29.0), 3.4, 0.0, panzer)

	_add_crate_stack(Vector3(23.0, 0.0, -22.5), 2)
	_add_sandbags(Vector3(26.5, 0.0, -18.5), -35.0)
	_barrel(Vector3(19.5, 0.0, -26.5))

	_add_beveled_deck(Vector2(-23.0, 23.0), Vector2(9.0, 9.0), 0.20, slate_floor, panzer)
	_add_sandbags(Vector3(-19.5, 0.0, 17.5), 40.0)
	_barrel(Vector3(-28.5, 0.0, 19.0))

	_prop("prop_truck", Vector3(22.5, 0.0, 23.5), 35.0, Vector3(2.8, 2.5, 6.2), Vector3(0.0, 1.25, 0.0))
	_add_fire_barrel(Vector3(27.0, 0.0, 18.0))
	_add_waist_cover(Vector3(18.5, 0.0, 27.5), 3.2, 45.0, panzer)

	# Glacial Mountain Peaks surrounding perimeter
	var mtn_mat := MaterialLib.get_world("concrete", 0.25, Color(0.76, 0.85, 0.95), 0.0, 0.88)
	for mp in [
		[Vector3(-74, 14, -68), Vector3(44, 34, 38), 22.0],
		[Vector3(10, 18, -80), Vector3(62, 42, 42), -12.0],
		[Vector3(76, 15, -58), Vector3(46, 36, 40), 35.0],
		[Vector3(78, 14, 52), Vector3(48, 32, 42), -28.0],
		[Vector3(-72, 16, 62), Vector3(54, 38, 44), 18.0],
	]:
		var m_mesh := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = mp[1]
		m_mesh.mesh = pm
		m_mesh.material_override = mtn_mat
		m_mesh.position = mp[0]
		m_mesh.rotation_degrees.y = float(mp[2])
		add_child(m_mesh)


func _add_cryo_vat(pos: Vector3, frame_mat: Material, glow_mat: Material) -> void:
	_add_static_box(pos + Vector3(0.0, 1.45, 0.0), Vector3(1.5, 2.9, 1.5), frame_mat)
	var tube := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.62
	cm.bottom_radius = 0.62
	cm.height = 2.0
	cm.radial_segments = 16
	tube.mesh = cm
	tube.material_override = glow_mat
	tube.position = pos + Vector3(0.0, 1.45, 0.0)
	add_child(tube)


# ===========================================================================
# MAP 4: SUNSCORCH REFINERY (96m x 84m Desert Canyon & Oil Refinery)
# ===========================================================================
func _build_quarry() -> void:
	_bounds = Rect2(Vector2(-48.0, -42.0), Vector2(96.0, 84.0))
	var xs: Array[float] = [-48.0, -16.0, 16.0, 48.0]
	var zs: Array[float] = [-42.0, -14.0, 14.0, 42.0]
	_setup_grid_zones(xs, zs, [
		{"id": "convoy_west", "name": "CONVOY ROAD", "col": 0, "row": 1},
		{"id": "refinery_pit", "name": "REFINERY CORE", "col": 1, "row": 1},
		{"id": "crusher_east", "name": "CRUSHER MILL", "col": 2, "row": 1},
		{"id": "derrick_north", "name": "DERRICK RIDGE", "col": 1, "row": 0},
		{"id": "depot_south", "name": "FUEL DEPOT", "col": 1, "row": 2},
		{"id": "boneyard_nw", "name": "SCRAP BONEYARD", "col": 0, "row": 0},
		{"id": "mesa_ne", "name": "MESA PASS", "col": 2, "row": 0},
		{"id": "gulch_sw", "name": "PIPELINE GULCH", "col": 0, "row": 2},
		{"id": "spur_se", "name": "CANYON RAIL", "col": 2, "row": 2},
	])

	player_spawn = Vector3(-40.0, 0.1, 0.0)
	_spawn_centers = {
		0: Vector2(-40.0, 0.0),
		1: Vector2(40.0, 0.0),
		2: Vector2(0.0, -35.5),
		3: Vector2(0.0, 35.5),
		4: Vector2(-39.5, -33.5),
		5: Vector2(39.5, 33.5),
	}
	_spawn_y = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0}
	_objectives_snd = [
		{"id": "A", "label": "DERRICK A", "kind": "bomb_site", "pos": Vector3(0.0, 0.22, -21.0)},
		{"id": "B", "label": "DEPOT B", "kind": "bomb_site", "pos": Vector3(0.0, 0.0, 21.0)},
	]
	_objectives_dom = [
		{"id": "A", "label": "CONVOY A", "kind": "dom_flag", "pos": Vector3(-23.5, 0.0, 0.0)},
		{"id": "B", "label": "REFINERY B", "kind": "dom_flag", "pos": Vector3(0.0, 0.22, 0.0)},
		{"id": "C", "label": "CRUSHER C", "kind": "dom_flag", "pos": Vector3(23.5, 0.0, 0.0)},
	]
	_hotspots = [
		Vector3(0.0, 0.22, 0.0),
		Vector3(-23.5, 0.0, 0.0),
		Vector3(23.5, 0.0, 0.0),
		Vector3(0.0, 0.22, -21.0),
		Vector3(0.0, 0.0, 21.0),
		Vector3(24.0, 0.0, -22.0),
		Vector3(-24.0, 0.0, 22.0),
		Vector3(-24.0, 0.0, -22.0),
		Vector3(24.0, 0.0, 22.0),
	]

	_build_map_environment(
		Color(0.20, 0.48, 0.86), Color(0.96, 0.76, 0.50),
		Color(0.32, 0.20, 0.12), Color(0.84, 0.64, 0.44),
		Color(0.76, 0.66, 0.54), 0.82,
		Color(1.0, 0.88, 0.66), 2.28, Vector3(-36.0, -24.0, 0.0),
		1.06
	)

	var desert_sand := MaterialLib.get_world("concrete", 0.35, Color(0.86, 0.68, 0.48), 0.0, 0.92, 0.0, 0.2, true)
	var sandstone := MaterialLib.get_world("concrete", 0.45, Color(0.76, 0.54, 0.36), 0.0, 0.90, 0.0, 0.3, true)
	var rust_steel := MaterialLib.get_world("rusted_metal", 0.45, Color(0.72, 0.46, 0.34), 0.38, 0.78, 0.0, 0.2)
	var road_mat := MaterialLib.get_world("asphalt", 0.35, Color(0.56, 0.52, 0.48), 0.02, 0.88, 0.15, 0.1, true)
	var conc_pad := MaterialLib.get_world("concrete_floor", 0.5, Color(0.68, 0.62, 0.54), 0.0, 0.85, 0.0, 0.1, true)

	_add_static_box(Vector3(0.0, -0.30, 0.0), Vector3(100.0, 0.60, 88.0), desert_sand)
	var outer_sand := MeshInstance3D.new()
	var osm := PlaneMesh.new()
	osm.size = Vector2(320.0, 320.0)
	outer_sand.mesh = osm
	outer_sand.material_override = desert_sand
	outer_sand.position = Vector3(0.0, -0.65, 0.0)
	add_child(outer_sand)

	# Asphalt highway & refinery pads
	_add_floor_tile(Vector3(-24.0, 0.0, 0.0), Vector2(38.0, 9.0), road_mat)
	_add_floor_tile(Vector3(0.0, 0.0, 0.0), Vector2(28.0, 24.0), conc_pad)
	_add_vista_perimeter(_bounds, 1.35, sandstone, rust_steel)

	# Central Refinery Pit: 0.22m drill pad + twin Fuel Cracking Towers + overhead pipeline bridge
	_add_beveled_deck(Vector2(0.0, 0.0), Vector2(10.0, 10.0), 0.22, conc_pad, sandstone)
	_prop("prop_fuel_tank", Vector3(-9.5, 0.0, -7.5), 45.0, Vector3(2.4, 3.0, 4.8), Vector3(0.0, 1.5, 0.0))
	_prop("prop_fuel_tank", Vector3(9.5, 0.0, 7.5), 45.0, Vector3(2.4, 3.0, 4.8), Vector3(0.0, 1.5, 0.0))
	# Overhead pipeline truss at y = 4.35m supported by vertical cracking-tower stanchions
	_add_visual_box(Vector3(0.0, 4.35, 0.0), Vector3(25.0, 0.55, 0.65), rust_steel, Vector3(0.0, deg_to_rad(-38.0), 0.0))
	_add_visual_box(Vector3(-9.5, 2.35, -7.5), Vector3(0.75, 4.7, 0.75), rust_steel)
	_add_visual_box(Vector3(9.5, 2.35, 7.5), Vector3(0.75, 4.7, 0.75), rust_steel)
	_add_static_box(Vector3(-7.2, 2.20, -5.63), Vector3(0.55, 4.4, 0.55), rust_steel)
	_add_static_box(Vector3(7.2, 2.20, 5.63), Vector3(0.55, 4.4, 0.55), rust_steel)
	_add_waist_cover(Vector3(-6.8, 0.0, 5.2), 3.6, -25.0, sandstone)
	_add_waist_cover(Vector3(6.8, 0.0, -5.2), 3.6, -25.0, sandstone)
	_add_sandbags(Vector3(-12.5, 0.0, -2.5), 90.0)
	_add_sandbags(Vector3(12.5, 0.0, 2.5), 90.0)
	for bp in [Vector3(-6.2, 0.0, -10.5), Vector3(6.2, 0.0, 10.5), Vector3(-11.2, 0.0, 7.5), Vector3(11.2, 0.0, -7.5)]:
		_barrel(bp)

	# West Convoy Road (T0 spawn at (-40, 0) strictly clear)
	_prop("prop_car_wreck", Vector3(-25.5, 0.0, -8.2), 18.0, Vector3(2.2, 1.4, 4.4), Vector3(0.0, 0.7, 0.0))
	_prop("prop_truck", Vector3(-25.5, 0.0, 8.2), -14.0, Vector3(2.8, 2.5, 6.2), Vector3(0.0, 1.25, 0.0))
	_add_sandbags(Vector3(-19.0, 0.0, -4.5), 75.0)
	_add_sandbags(Vector3(-19.0, 0.0, 4.5), -75.0)
	_barrel(Vector3(-29.0, 0.0, -11.0))

	# East Crusher Mill (T1 spawn at (40, 0) strictly clear)
	_add_canopy_bay(Vector2(24.5, 0.0), Vector2(11.0, 11.0), 4.8, rust_steel, m_dark_conc)
	_add_waist_cover(Vector3(18.5, 0.0, -4.8), 3.0, 90.0, sandstone)
	_add_waist_cover(Vector3(18.5, 0.0, 4.8), 3.0, 90.0, sandstone)
	_add_crate_stack(Vector3(29.5, 0.0, -9.5), 2)
	_add_crate_stack(Vector3(29.5, 0.0, 9.5), 2)
	_barrel(Vector3(19.5, 0.0, 9.5))

	# North Derrick Ridge (T2 spawn at (0, -35.5) strictly clear)
	_add_beveled_deck(Vector2(0.0, -21.0), Vector2(11.0, 8.2), 0.22, sandstone, rust_steel)
	_prop("prop_radio_tower", Vector3(9.8, 0.0, -21.0), 0.0, Vector3(1.8, 4.2, 1.8), Vector3(0.0, 2.1, 0.0))
	_add_waist_cover(Vector3(-8.8, 0.0, -21.0), 3.4, 90.0, sandstone)
	_barrel(Vector3(-11.5, 0.0, -24.5))

	# South Fuel Depot (T3 spawn at (0, 35.5) strictly clear)
	_add_canopy_bay(Vector2(0.0, 21.0), Vector2(11.4, 8.2), 4.5, rust_steel, conc_pad)
	_prop("prop_fuel_tank", Vector3(-9.8, 0.0, 21.0), 90.0, Vector3(2.2, 2.8, 4.6), Vector3(0.0, 1.4, 0.0))
	_prop("prop_fuel_tank", Vector3(9.8, 0.0, 21.0), 90.0, Vector3(2.2, 2.8, 4.6), Vector3(0.0, 1.4, 0.0))
	_barrel(Vector3(12.2, 0.0, 25.0))

	# NW Boneyard / NE Mesa Pass / SW Pipeline Gulch / SE Canyon Rail
	_prop("prop_car_wreck", Vector3(-22.5, 0.0, -22.5), -35.0, Vector3(2.2, 1.4, 4.4), Vector3(0.0, 0.7, 0.0))
	_add_waist_cover(Vector3(-28.0, 0.0, -19.5), 3.2, 35.0, sandstone)
	_barrel(Vector3(-19.5, 0.0, -26.5))

	_add_waist_cover(Vector3(23.0, 0.0, -23.0), 4.2, -35.0, sandstone)
	_add_sandbags(Vector3(28.0, 0.0, -19.0), 25.0)
	_barrel(Vector3(19.5, 0.0, -26.5))

	_add_waist_cover(Vector3(-23.0, 0.0, 23.0), 4.2, 35.0, sandstone)
	_add_visual_box(Vector3(-23.0, 4.15, 23.0), Vector3(14.0, 0.55, 0.55), rust_steel, Vector3(0.0, deg_to_rad(35.0), 0.0))
	_add_static_box(Vector3(-29.0, 2.05, 18.8), Vector3(0.7, 4.1, 0.7), rust_steel)
	_add_static_box(Vector3(-17.0, 2.05, 27.2), Vector3(0.7, 4.1, 0.7), rust_steel)
	_barrel(Vector3(-19.0, 0.0, 18.5))

	# Visual-only mining rail tracks in SE Canyon Rail (zero collision boxes -> never snags bots/players!)
	var sleeper_mat := m_wood
	for rail_z in [19.4, 21.0]:
		_add_visual_box(Vector3(31.0, 0.018, rail_z), Vector3(26.0, 0.025, 0.12), rust_steel)
	for sx in range(19, 44, 2):
		_add_visual_box(Vector3(float(sx), 0.010, 20.2), Vector3(0.24, 0.02, 2.2), sleeper_mat)
	_add_crate_stack(Vector3(22.5, 0.0, 16.5), 2)
	_add_waist_cover(Vector3(26.0, 0.0, 25.5), 3.4, -20.0, sandstone)
	_barrel(Vector3(19.5, 0.0, 25.0))

	# Distant Red-Rock Canyon Mesas surrounding quarry
	var mesa_mat := MaterialLib.get_world("concrete", 0.4, Color(0.68, 0.40, 0.26), 0.0, 0.92)
	for mp in [
		[Vector3(-76.0, 9.0, -56.0), Vector3(36.0, 20.0, 34.0), 14.0],
		[Vector3(4.0, 11.0, -74.0), Vector3(68.0, 24.0, 30.0), -6.0],
		[Vector3(78.0, 10.0, -48.0), Vector3(34.0, 22.0, 38.0), 28.0],
		[Vector3(76.0, 9.5, 50.0), Vector3(38.0, 20.0, 36.0), -22.0],
		[Vector3(-74.0, 10.5, 58.0), Vector3(44.0, 22.0, 34.0), 19.0],
	]:
		_add_visual_box(mp[0], mp[1], mesa_mat, Vector3(0.0, deg_to_rad(float(mp[2])), 0.0))
