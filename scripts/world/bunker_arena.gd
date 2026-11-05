class_name BunkerArena
extends Node3D
# Outpost Nacht-7: four zones joined by buyable doors.
#
#            +-----------------------+
#            |     COMMAND BUNKER    |  (roofed, mystery crate)
#  +---------+-----------[D]---------+-----------+
#  | MED LAB [D]      COURTYARD     [D] MOTOR    |
#  | (forge) |  (start, furnace)     |   POOL    |
#  +---------+-----------------------+-----------+
#
# Zombies spawn outside and break in through boarded windows in the outer
# walls. Only windows in zones the player has opened are used.

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

var zones_open: Dictionary = {"courtyard": true, "bunker": false, "motorpool": false, "lab": false}
var zone_names: Dictionary = {"courtyard": "COURTYARD", "bunker": "COMMAND BUNKER", "motorpool": "MOTOR POOL", "lab": "MED LAB"}
var windows: Array[Node3D] = []
var boss_points: Dictionary = {
	"courtyard": [Vector3(-6.0, 0.1, -4.8), Vector3(6.0, 0.1, -4.8), Vector3(0.0, 0.1, 11.0)],
	"bunker": [Vector3(0.0, 0.1, -14.0)],
	"motorpool": [Vector3(16.0, 0.1, -3.5), Vector3(25.0, 0.1, 10.0)],
	"lab": [Vector3(-18.5, 0.1, -3.5)],
}
var player_spawn: Vector3 = Vector3(0.0, 0.2, 9.0)
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
var m_wood: Material


func _ready() -> void:
	add_to_group("arena")
	m_conc = MaterialLib.get_world("concrete", 0.5, Color(0.78, 0.8, 0.84), 0.0, 1.0, 0.0, 0.55)
	m_dark_conc = MaterialLib.get_world("concrete", 0.5, Color(0.5, 0.51, 0.55), 0.0, 1.0, 0.0, 0.4)
	m_metal = MaterialLib.get_world("rusted_metal", 0.5, Color(0.85, 0.82, 0.8), 0.35, 0.9, 0.0, 0.25)
	m_wood = MaterialLib.get_world("wood_planks", 0.5, Color(0.9, 0.85, 0.78), 0.0, 1.0, 0.0, 0.3)

	_build_environment()
	_build_ground()
	_build_walls_and_windows()
	_build_roofs_and_lights()
	_build_courtyard()
	_build_bunker()
	_build_motor_pool()
	_build_lab()
	_dress_map()
	_build_doors()
	_bake_navigation()
	_scatter_blood.call_deferred()


func _process(delta: float) -> void:
	_flicker_time += delta * 7.5
	for i in range(fire_lights.size()):
		var fl := fire_lights[i]
		fl.light_energy = 2.6 + sin(_flicker_time + float(i) * 1.9) * 0.45 + cos(_flicker_time * 2.3 + float(i)) * 0.25
	if power_on:
		for i in range(flicker_lamps.size()):
			var lamp := flicker_lamps[i]
			var n := sin(_flicker_time * 3.1 + float(i) * 7.0) + sin(_flicker_time * 7.7 + float(i))
			lamp.light_energy = 0.15 if n > 1.6 else 1.9
	else:
		var pulse := 0.45 + sin(_flicker_time * 0.35) * 0.2
		for d in powered_lamps:
			(d["light"] as OmniLight3D).light_energy = pulse


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


# Which zone a point lies in ("" outside the walls).
func zone_at(p: Vector3) -> String:
	if p.z > -8.0 and p.z < 14.0:
		if p.x > -12.0 and p.x < 12.0:
			return "courtyard"
		if p.x > -28.0 and p.x <= -12.0:
			return "lab"
		if p.x >= 12.0 and p.x < 30.0:
			return "motorpool"
	elif p.z > -22.0 and p.z <= -8.0 and p.x > -12.0 and p.x < 12.0:
		return "bunker"
	return ""


# Boss spawns in an open zone, as far from the player as possible.
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


# ---------------------------------------------------------------------------
# ENVIRONMENT
# ---------------------------------------------------------------------------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	world_env = env

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.03, 0.045, 0.08)
	sky_mat.sky_horizon_color = Color(0.08, 0.10, 0.15)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sky_mat.ground_horizon_color = Color(0.06, 0.07, 0.10)
	# Stars, Milky Way, moonlit clouds and the moon itself
	if ResourceLoader.exists("res://assets/textures/sky_night.png"):
		sky_mat.sky_cover = load("res://assets/textures/sky_night.png")
		sky_mat.sky_cover_modulate = Color(1.45, 1.45, 1.55, 1.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.14, 0.17, 0.24)
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.3
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.18
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.14, 0.17, 0.23)
	env.volumetric_fog_emission = Color(0.02, 0.025, 0.04)
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.58, 0.68, 0.90)
	moon.light_energy = 1.15
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	add_child(moon)


func _build_ground() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)
	_add_static_box(Vector3(1.0, -0.25, -2.0), Vector3(84.0, 0.5, 68.0),
		MaterialLib.get_world("asphalt", 0.33, Color(0.88, 0.90, 0.96), 0.05, 1.0, 1.0, 0.0, true))
	# Indoor floors (visual only)
	_add_floor_tile(Vector3(0, 0, -15), Vector2(24, 14), MaterialLib.get_world("concrete_floor", 0.5, Color(0.56, 0.57, 0.6), 0.0, 1.0, 0.0, 0.0, true))
	_add_floor_tile(Vector3(-20, 0, 3), Vector2(16, 22), MaterialLib.get_world("concrete_floor", 0.5, Color(0.62, 0.68, 0.66), 0.0, 0.9, 0.0, 0.0, true))


# ---------------------------------------------------------------------------
# WALLS, WINDOWS & ROOFS
# ---------------------------------------------------------------------------
func _build_walls_and_windows() -> void:
	# South outer wall (courtyard, lab, motor pool)
	_wall_x(14.0, -28.3, 30.3, [[-20.0, WINDOW_W, WINDOW_H], [-7.0, WINDOW_W, WINDOW_H], [0.0, WINDOW_W, WINDOW_H], [7.0, WINDOW_W, WINDOW_H], [21.0, WINDOW_W, WINDOW_H]], m_conc)
	_add_window(Vector3(-20, 0, 14), Vector3.BACK, "lab")
	_add_window(Vector3(-7, 0, 14), Vector3.BACK, "courtyard")
	_add_window(Vector3(0, 0, 14), Vector3.BACK, "courtyard")
	_add_window(Vector3(7, 0, 14), Vector3.BACK, "courtyard")
	_add_window(Vector3(21, 0, 14), Vector3.BACK, "motorpool")

	# Middle wall: lab/motor pool north walls + bunker/courtyard divider
	_wall_x(-8.0, -28.3, 30.3, [[-20.0, WINDOW_W, WINDOW_H], [0.0, DOOR_W, DOOR_H], [21.0, WINDOW_W, WINDOW_H]], m_conc)
	_add_window(Vector3(-20, 0, -8), Vector3.FORWARD, "lab")
	_add_window(Vector3(21, 0, -8), Vector3.FORWARD, "motorpool")

	# Bunker north wall
	_wall_x(-22.0, -12.3, 12.3, [[-6.0, WINDOW_W, WINDOW_H], [6.0, WINDOW_W, WINDOW_H]], m_conc)
	_add_window(Vector3(-6, 0, -22), Vector3.FORWARD, "bunker")
	_add_window(Vector3(6, 0, -22), Vector3.FORWARD, "bunker")

	# Lab west wall / motor pool east wall
	_wall_z(-28.0, -8.3, 14.3, [[-1.0, WINDOW_W, WINDOW_H], [8.0, WINDOW_W, WINDOW_H]], m_conc)
	_add_window(Vector3(-28, 0, -1), Vector3.LEFT, "lab")
	_add_window(Vector3(-28, 0, 8), Vector3.LEFT, "lab")
	_wall_z(30.0, -8.3, 14.3, [[-1.0, WINDOW_W, WINDOW_H], [8.0, WINDOW_W, WINDOW_H]], m_conc)
	_add_window(Vector3(30, 0, -1), Vector3.RIGHT, "motorpool")
	_add_window(Vector3(30, 0, 8), Vector3.RIGHT, "motorpool")

	# Courtyard side walls (also bunker side walls): doors to lab & motor pool
	_wall_z(-12.0, -22.3, 14.3, [[-15.0, WINDOW_W, WINDOW_H], [3.0, DOOR_W, DOOR_H]], m_conc)
	_add_window(Vector3(-12, 0, -15), Vector3.LEFT, "bunker")
	_wall_z(12.0, -22.3, 14.3, [[-15.0, WINDOW_W, WINDOW_H], [3.0, DOOR_W, DOOR_H]], m_conc)
	_add_window(Vector3(12, 0, -15), Vector3.RIGHT, "bunker")

	# Buttress pillars along the outer walls
	for x in [-24.0, -16.0, -10.0, 10.0, 16.0, 26.0]:
		_add_static_box(Vector3(x, WALL_H * 0.5, 14.45), Vector3(0.9, WALL_H + 0.3, 0.5), m_dark_conc)
	for x in [-10.0, -3.0, 3.0, 10.0]:
		_add_static_box(Vector3(x, WALL_H * 0.5, -22.45), Vector3(0.9, WALL_H + 0.3, 0.5), m_dark_conc)


func _build_roofs_and_lights() -> void:
	# Bunker & lab are roofed
	_add_static_box(Vector3(0, WALL_H + 0.2, -15.0), Vector3(24.6, 0.4, 14.6), m_dark_conc)
	_add_static_box(Vector3(-20, WALL_H + 0.2, 3.0), Vector3(16.6, 0.4, 22.6), m_dark_conc)
	# Roof beams
	for x in [-8.0, 0.0, 8.0]:
		_add_static_box(Vector3(x, WALL_H - 0.25, -15.0), Vector3(0.4, 0.5, 14.0), m_metal)
	for z in [-3.0, 3.0, 9.0]:
		_add_static_box(Vector3(-20, WALL_H - 0.25, z), Vector3(16.0, 0.5, 0.4), m_metal)

	# Ceiling lamps
	var warm := Color(1.0, 0.82, 0.55)
	for p in [Vector3(-6, 3.85, -11.5), Vector3(6, 3.85, -11.5), Vector3(-6, 3.85, -18.5), Vector3(6, 3.85, -18.5)]:
		_add_lamp(p, warm, 2.2, p.x > 0.0 and p.z < -15.0)
	var lab_col := Color(0.75, 1.0, 0.85)
	for p in [Vector3(-20, 3.85, -3.5), Vector3(-20, 3.85, 3.0), Vector3(-20, 3.85, 9.5)]:
		_add_lamp(p, lab_col, 2.0, p.z > 9.0)

	# Red danger lights outside every window so you can see what's coming
	for w in windows:
		var l := OmniLight3D.new()
		l.light_color = Color(0.95, 0.2, 0.12)
		l.light_energy = 1.8
		l.omni_range = 6.0
		l.position = w.position + w.basis.z * 3.0 + Vector3(0, 2.6, 0)
		add_child(l)


func _add_lamp(pos: Vector3, col: Color, energy: float, flicker: bool) -> void:
	var fixture := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 0.12, 0.3)
	fixture.mesh = bm
	fixture.material_override = MaterialLib.get_emissive(col, 3.0)
	fixture.position = pos + Vector3(0, 0.2, 0)
	add_child(fixture)
	var l := OmniLight3D.new()
	l.light_color = EMERGENCY_RED
	l.light_energy = 0.45
	l.omni_range = 10.0
	l.position = pos
	add_child(l)
	fixture.material_override = MaterialLib.get_emissive(EMERGENCY_RED, 1.2)
	powered_lamps.append({"light": l, "fixture": fixture, "color": col, "energy": energy})
	if flicker:
		flicker_lamps.append(l)


func set_power(on: bool) -> void:
	power_on = on
	for d in powered_lamps:
		var l: OmniLight3D = d["light"]
		l.light_color = d["color"]
		l.light_energy = d["energy"]
		(d["fixture"] as MeshInstance3D).material_override = MaterialLib.get_emissive(d["color"], 3.0)


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


# ---------------------------------------------------------------------------
# ZONES
# ---------------------------------------------------------------------------
func _build_courtyard() -> void:
	# Ruined monument in the middle — good for running trains
	_add_static_box(Vector3(0, 0.55, -0.5), Vector3(3.6, 1.1, 3.6), m_conc)
	_add_static_box(Vector3(0, 1.95, -0.5), Vector3(1.3, 1.8, 1.3), m_metal)
	for x in [-8.0, 8.0]:
		_add_static_box(Vector3(x, 1.1, 4.5), Vector3(1.4, 2.2, 1.4), m_dark_conc)
	# Caged wall lamps along the courtyard side walls
	for p in [Vector3(-11.55, 3.5, -3.0), Vector3(11.55, 3.5, -3.0), Vector3(-11.55, 3.5, 9.0), Vector3(11.55, 3.5, 9.0)]:
		var out := -signf(p.x)
		var bracket := MeshInstance3D.new()
		var brm := BoxMesh.new()
		brm.size = Vector3(0.3, 0.12, 0.25)
		bracket.mesh = brm
		bracket.material_override = m_metal
		bracket.position = p + Vector3(out * 0.1, 0.12, 0)
		add_child(bracket)
		var bulb := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.08
		bm.height = 0.16
		bulb.mesh = bm
		bulb.material_override = MaterialLib.get_emissive(Color(1.0, 0.85, 0.6), 3.0)
		bulb.position = p + Vector3(out * 0.18, 0, 0)
		add_child(bulb)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.65)
		l.light_energy = 1.5
		l.omni_range = 12.0
		l.position = p + Vector3(out * 0.4, 0, 0)
		add_child(l)

	_add_sandbags(Vector3(-5.0, 0, 5.2), 20.0)
	_add_sandbags(Vector3(5.0, 0, 5.2), -20.0)
	_add_sandbags(Vector3(-6.5, 0, -4.0), -10.0)
	_add_sandbags(Vector3(6.5, 0, -4.0), 10.0)
	for p in [Vector3(-10.3, 0, -6.3), Vector3(10.3, 0, -6.3), Vector3(10.3, 0, 12.6)]:
		_add_fire_barrel(p)

	_spawn_station("weapon", "smg", "KURZ-9 SMG", 1000, 500, Color(0.25, 0.88, 1.0), Vector3(-6.0, 1.55, -7.68), 0.0)
	_spawn_station("weapon", "rifle", "COMMANDO M14A", 1200, 600, Color(0.25, 0.88, 1.0), Vector3(6.0, 1.55, -7.68), 0.0)

	var furnace: Node3D = FurnaceScript.new()
	furnace.position = Vector3(-10.6, 0.0, 9.5)
	furnace.rotation_degrees.y = -90.0
	add_child(furnace)

	# Second Wind medical cabinet against the east wall
	var depot: Node3D = (load("res://scripts/world/supply_depot.gd") as GDScript).new()
	depot.position = Vector3(-11.0, 0.0, -3.5)
	depot.rotation_degrees.y = -90.0
	add_child(depot)
	var med: Node3D = SecondWindScript.new()
	med.position = Vector3(11.6, 0.0, 11.0)
	med.rotation_degrees.y = 90.0
	add_child(med)


func _build_bunker() -> void:
	for x in [-5.0, 5.0]:
		_add_static_box(Vector3(x, WALL_H * 0.5, -15.0), Vector3(0.8, WALL_H, 0.8), m_dark_conc)
	_add_crate_stack(Vector3(-10.5, 0, -20.5), 2)
	_add_crate_stack(Vector3(10.5, 0, -10.0), 1)
	_add_sandbags(Vector3(-2.5, 0, -12.0), 0.0)

	var crate: Node3D = CrateScript.new()
	crate.position = Vector3(0.0, 0.0, -20.9)
	crate.rotation_degrees.y = 180.0
	add_child(crate)

	_spawn_station("weapon", "shotgun", "TRENCH-12 PUMP", 1500, 750, Color(0.25, 0.88, 1.0), Vector3(-7.0, 1.55, -8.32), 180.0)

	# Field radio for calling the extraction chopper
	var radio: Node3D = RadioScript.new()
	radio.position = Vector3(-3.2, 0.0, -21.2)
	radio.rotation_degrees.y = 180.0
	add_child(radio)


func _build_motor_pool() -> void:
	if ResourceLoader.exists("res://assets/models/prop_truck.glb"):
		var truck: Node3D = (load("res://assets/models/prop_truck.glb") as PackedScene).instantiate()
		truck.position = Vector3(21.0, 0, 4.0)
		truck.rotation_degrees.y = 90.0
		add_child(truck)
	_add_invisible_collider(Vector3(20.6, 1.4, 4.0), Vector3(7.4, 2.8, 2.4), 0.0)

	_add_crate_stack(Vector3(27.5, 0, 12.0), 2)
	_add_crate_stack(Vector3(27.5, 0, -5.8), 1)
	_add_sandbags(Vector3(17.0, 0, 10.0), 15.0)
	_add_fire_barrel(Vector3(14.0, 0, 12.5))

	# Floodlights on poles
	for pair in [[Vector3(28.8, 0, -6.8), Vector3(21, 0, 3)], [Vector3(13.2, 0, 12.8), Vector3(21, 0, 3)]]:
		var base: Vector3 = pair[0]
		_add_static_box(base + Vector3(0, 3.0, 0), Vector3(0.25, 6.0, 0.25), m_metal)
		var head := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.7, 0.4, 0.4)
		head.mesh = hm
		head.material_override = MaterialLib.get_emissive(Color(1.0, 0.95, 0.8), 4.0)
		head.position = base + Vector3(0, 6.1, 0)
		add_child(head)
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.92, 0.75)
		spot.light_energy = 6.0
		spot.spot_range = 22.0
		spot.spot_angle = 42.0
		add_child(spot)
		spot.look_at_from_position(base + Vector3(0, 6.0, 0), pair[1], Vector3.UP)

	_spawn_station("ammo_box", "", "AMMO CACHE", 450, 0, Color(1.0, 0.78, 0.20), Vector3(25.5, 1.55, -7.68), 0.0)
	_spawn_station("weapon", "lmg", "RAZORBACK LMG", 3000, 1500, Color(0.25, 0.88, 1.0), Vector3(29.68, 1.55, 3.5), -90.0)


func _build_lab() -> void:
	var m_bench := MaterialLib.get_pbr("rusted_metal", 0.6, Color(0.6, 0.62, 0.65), 0.6, 0.6)
	for p in [Vector3(-22.0, 0.45, -5.6), Vector3(-15.5, 0.45, -5.6), Vector3(-22.0, 0.45, 11.6), Vector3(-15.5, 0.45, 11.6)]:
		_add_static_box(p, Vector3(2.6, 0.9, 0.9), m_bench)
	var vat_glass := MaterialLib.get_emissive(Color(0.3, 1.0, 0.45), 2.2, 0.55)
	for p in [Vector3(-26.6, 0, -6.6), Vector3(-26.6, 0, 12.6), Vector3(-13.4, 0, 12.6)]:
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
		_add_static_box(p + Vector3(0, 2.3, 0), Vector3(1.2, 0.2, 1.2), m_metal)
		_add_invisible_collider(p + Vector3(0, 1.2, 0), Vector3(1.1, 2.4, 1.1), 0.0)
		var gl := OmniLight3D.new()
		gl.light_color = Color(0.3, 1.0, 0.45)
		gl.light_energy = 1.2
		gl.omni_range = 4.0
		gl.position = p + Vector3(0, 1.4, 0)
		add_child(gl)

	_spawn_station("forge", "", "WEAPON FORGE", 5000, 0, Color(0.72, 0.30, 1.0), Vector3(-25.2, 0.0, 3.0), -90.0)
	_spawn_station("weapon", "revolver", ".44 HAND CANNON", 1750, 875, Color(0.25, 0.88, 1.0), Vector3(-15.0, 1.55, 13.68), 180.0)


# Props, the generator, the trap, the secret skulls and outside scenery.
func _dress_map() -> void:
	# --- Courtyard ---
	_prop("prop_car_wreck", Vector3(-8.6, 0, -0.8), 4.0, Vector3(1.9, 1.3, 4.3), Vector3(0, 0.65, 0))
	_prop("prop_rubble", Vector3(10.4, 0, 8.4), 30.0, Vector3(2.0, 0.6, 1.6), Vector3(0, 0.3, 0))
	_skull(Vector3(8.0, 2.2, 4.5), 200.0)

	# --- Bunker ---
	_prop("prop_desk", Vector3(-9.3, 0, -11.6), 90.0, Vector3(1.6, 1.0, 0.8), Vector3(0, 0.5, 0))
	_prop("prop_desk", Vector3(8.6, 0, -18.6), -90.0, Vector3(1.6, 1.0, 0.8), Vector3(0, 0.5, 0))
	_prop("prop_lockers", Vector3(11.4, 0, -19.6), -90.0, Vector3(2.0, 2.0, 0.55), Vector3(0, 1.0, 0))
	_prop("prop_lockers", Vector3(-11.4, 0, -11.0), 90.0, Vector3(2.0, 2.0, 0.55), Vector3(0, 1.0, 0))
	for z in [-21.2, -8.9]:
		var pipe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.09
		cm.height = 23.0
		pipe.mesh = cm
		pipe.material_override = m_metal
		pipe.rotation.z = PI * 0.5
		pipe.position = Vector3(0, 3.7, z)
		add_child(pipe)
	_skull(Vector3(-10.5, 2.27, -20.5), 150.0)

	# --- Med Lab ---
	for g in [[Vector3(-23.0, 0, -2.5), 90.0], [Vector3(-17.0, 0, -2.5), 90.0], [Vector3(-17.0, 0, 8.5), 90.0]]:
		_prop("prop_gurney", g[0], g[1], Vector3(0.8, 1.1, 2.0), Vector3(0, 0.55, 0))
	_prop("prop_lockers", Vector3(-14.5, 0, -7.4), 0.0, Vector3(2.0, 2.0, 0.55), Vector3(0, 1.0, 0))
	_skull(Vector3(-14.5, 2.0, -7.35), 0.0)
	# A specimen floating in a vat
	if ResourceLoader.exists("res://assets/models/zombie_walker_v2.glb"):
		var spec: Node3D = (load("res://assets/models/zombie_walker_v2.glb") as PackedScene).instantiate()
		spec.position = Vector3(-26.6, 0.35, -6.6)
		spec.scale = Vector3.ONE * 0.85
		spec.rotation_degrees.y = 45.0
		add_child(spec)
		var arm := spec.find_child("UpperArmL", true, false) as Node3D
		if arm:
			arm.rotation.x = 0.6
		var head := spec.find_child("Head", true, false) as Node3D
		if head:
			head.rotation.x = -0.5

	# --- Motor Pool ---
	var gen: Node3D = GeneratorScript.new()
	gen.position = Vector3(17.0, 0, -5.4)
	gen.rotation_degrees.y = 180.0
	add_child(gen)
	_prop("prop_fuel_tank", Vector3(24.5, 0, 10.6), 90.0, Vector3(3.6, 2.1, 1.8), Vector3(0, 1.05, 0))
	_prop("prop_tire_stack", Vector3(28.6, 0, -3.6), 0.0, Vector3(0.9, 1.0, 0.9), Vector3(0, 0.5, 0))
	_prop("prop_tire_stack", Vector3(13.4, 0, -1.2), 0.0, Vector3(0.9, 1.0, 0.9), Vector3(0, 0.5, 0))


	# --- Outside: dead trees, radio tower, wire, wrecks, rubble, lamp posts ---
	var trees := [Vector3(-36, 0, 24), Vector3(-25, 0, 26), Vector3(12, 0, 27), Vector3(33, 0, 24), Vector3(38, 0, -12),
		Vector3(32, 0, -26), Vector3(-15, 0, -30), Vector3(17, 0, -30), Vector3(-38, 0, -20), Vector3(-36, 0, 12),
		Vector3(28, 0, 21), Vector3(-4, 0, 28), Vector3(40, 0, 6), Vector3(-40, 0, -4)]
	for i in range(trees.size()):
		_prop("prop_dead_tree", trees[i], float(i) * 47.0, Vector3.ZERO, Vector3.ZERO, randf_range(0.8, 1.3))
	_prop("prop_radio_tower", Vector3(-33, 0, -27), 20.0, Vector3.ZERO, Vector3.ZERO)
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.1, 0.05)
	beacon.light_energy = 3.0
	beacon.omni_range = 8.0
	beacon.position = Vector3(-33, 22.4, -27)
	add_child(beacon)
	fire_lights.append(beacon)
	for w in [[Vector3(-13.5, 0, 17.2), 0.0], [Vector3(14.0, 0, 17.2), 0.0], [Vector3(0, 0, -25.5), 0.0],
			[Vector3(33.0, 0, 3.5), 90.0], [Vector3(-31.0, 0, 3.5), 90.0]]:
		_prop("prop_barbed_wire", w[0], w[1], Vector3.ZERO, Vector3.ZERO)
	_prop("prop_car_wreck", Vector3(-25, 0, 21), 30.0, Vector3.ZERO, Vector3.ZERO)
	_prop("prop_car_wreck", Vector3(35, 0, -18), -60.0, Vector3.ZERO, Vector3.ZERO)
	_prop("prop_rubble", Vector3(-30, 0, -13), 0.0, Vector3.ZERO, Vector3.ZERO, 1.4)
	_prop("prop_rubble", Vector3(37, 0, 15), 70.0, Vector3.ZERO, Vector3.ZERO, 1.3)
	for lp in [Vector3(-3.5, 0, 17.6), Vector3(10.5, 0, 17.6)]:
		_prop("prop_lamp_post", lp, 180.0, Vector3.ZERO, Vector3.ZERO)
		var ll := OmniLight3D.new()
		ll.light_color = Color(1.0, 0.82, 0.55)
		ll.light_energy = 2.2
		ll.omni_range = 11.0
		ll.position = lp + Vector3(0, 4.2, -0.75)
		add_child(ll)


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
func _scatter_blood() -> void:
	if not is_inside_tree():
		return
	var spots := [Vector3(-3, 0, 6), Vector3(4.5, 0, -2), Vector3(-6, 0, 11), Vector3(2, 0, -6.5),
		Vector3(-4, 0, -14), Vector3(6, 0, -19), Vector3(-20, 0, 6), Vector3(-24, 0, -4), Vector3(20, 0, -2), Vector3(26, 0, 7)]
	for sp in spots:
		FX.blood_decal(sp + Vector3(0, 0.02, 0), Vector3.UP, randf_range(1.0, 2.2))


func _build_doors() -> void:
	_add_door(Vector3(0, 0, -8), 0.0, "bunker", 750)
	_add_door(Vector3(12, 0, 3), 90.0, "motorpool", 1000)
	_add_door(Vector3(-12, 0, 3), 90.0, "lab", 1250)


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


# ---------------------------------------------------------------------------
# NAVIGATION
# ---------------------------------------------------------------------------
# Bakes the navmesh from the arena's colliders so zombies path around walls,
# props and closed doors.
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
	nav_mesh.filter_baking_aabb = AABB(Vector3(-40.0, -1.0, -34.0), Vector3(82.0, 3.2, 64.0))
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, self)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	nav_region.navigation_mesh = nav_mesh


# ---------------------------------------------------------------------------
# BUILDING HELPERS
# ---------------------------------------------------------------------------
# Wall along X at `z`, from x0 to x1, with gaps [center, width, gap_height].
func _wall_x(z: float, x0: float, x1: float, gaps: Array, mat: Material) -> void:
	gaps.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := x0
	for g in gaps:
		var a: float = g[0] - g[1] * 0.5
		var b: float = g[0] + g[1] * 0.5
		if a > cursor:
			_add_static_box(Vector3((cursor + a) * 0.5, WALL_H * 0.5, z), Vector3(a - cursor, WALL_H, WALL_T), mat)
		var lintel_h: float = WALL_H - g[2]
		_add_static_box(Vector3(g[0], g[2] + lintel_h * 0.5, z), Vector3(g[1], lintel_h, WALL_T), m_metal if g[2] > 3.0 else mat)
		cursor = b
	if cursor < x1:
		_add_static_box(Vector3((cursor + x1) * 0.5, WALL_H * 0.5, z), Vector3(x1 - cursor, WALL_H, WALL_T), mat)


# Wall along Z at `x`, from z0 to z1, with gaps [center, width, gap_height].
func _wall_z(x: float, z0: float, z1: float, gaps: Array, mat: Material) -> void:
	gaps.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := z0
	for g in gaps:
		var a: float = g[0] - g[1] * 0.5
		var b: float = g[0] + g[1] * 0.5
		if a > cursor:
			_add_static_box(Vector3(x, WALL_H * 0.5, (cursor + a) * 0.5), Vector3(WALL_T, WALL_H, a - cursor), mat)
		var lintel_h: float = WALL_H - g[2]
		_add_static_box(Vector3(x, g[2] + lintel_h * 0.5, g[0]), Vector3(WALL_T, lintel_h, g[1]), m_metal if g[2] > 3.0 else mat)
		cursor = b
	if cursor < z1:
		_add_static_box(Vector3(x, WALL_H * 0.5, (cursor + z1) * 0.5), Vector3(WALL_T, WALL_H, z1 - cursor), mat)


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
