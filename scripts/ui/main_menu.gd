extends Node3D
# Nacht-7 command terminal: a living 3D diorama (operator showcase on a lit
# podium, horde looming in the fog, fire barrel, drifting fog, lightning)
# behind a navigation rail and one content panel. Full keyboard navigation,
# a persistent ambience toggle and rotating field-manual tips.

const ZombieRigScript := preload("res://scripts/enemies/zombie_rig.gd")

const ACCENT := Color(0.95, 0.30, 0.20)
const CYAN := Color(0.42, 0.85, 1.0)
const GREEN := Color(0.45, 1.0, 0.55)
const AMBER := Color(1.0, 0.74, 0.28)
const TEXT := Color(0.88, 0.90, 0.94)
const DIM := Color(0.55, 0.58, 0.64)
const MODES := {
	"casual": {"name": "CASUAL", "desc": "Survive 20 rounds, then kill THE PROGENITOR to contain the outbreak. Escape by chopper from round 8."},
	"infinite": {"name": "INFINITE", "desc": "Endless rounds that keep getting harder. No final boss — just how long you last."},
}
const PAGE_ORDER := ["play", "coop", "career", "intel", "options"]
const TIPS := [
	"Commanders hide behind bodyguards — kill the guards to break their damage shield.",
	"Jump over seismic slams, step out of toxin pools, and leave arc charges before they burst.",
	"Every 4th round challenge you finish grants a free stat level. Check the top-left objective.",
	"Fire Sale slashes the mystery crate price — stock up on weapons while it lasts.",
	"Extract by chopper from round 8 to bank the run and keep your career XP.",
	"Zombies that taste your blood rank up into stalkers and commanders. Don't let them live.",
	"Shoot an Overlord in the head to interrupt its psychic scream.",
	"Relics drop from commanders — unleash their skills with [X] and [Z].",
	"Casual ends at round 20 with THE PROGENITOR. Infinite never ends.",
	"Hold [TAB] for the scoreboard, press [M] for the full map.",
]

# 3D diorama
var menu_cam: Camera3D
var cam_pivot: Node3D
var operator: Node3D
var operator_rig: RefCounted
var zombie_rigs: Array[RefCounted] = []
var accent_light: OmniLight3D
var rim_light: SpotLight3D
var fire_light: OmniLight3D
var lamp_light: SpotLight3D
var beacon_light: OmniLight3D
var beacon_mat: StandardMaterial3D
var podium_ring_mat: StandardMaterial3D
var lightning: DirectionalLight3D
var fog_cards: Array[MeshInstance3D] = []
var fog_speeds: Array[float] = []
var _orbit_time: float = 0.0
var _t: float = 0.0
var _parallax := Vector2.ZERO
var _lightning_t: float = 7.0
var _amb_event_t: float = 5.0
var _rng := RandomNumberGenerator.new()

# UI
var _pages: Dictionary
var _nav: Dictionary
var _nav_order: Array[String] = []
var _nav_index: int = 0
var _current_page: String = ""
var _stack: VBoxContainer
var _content_title: Label
var _page_index: Label
var _title_box: VBoxContainer
var _panel: PanelContainer
var _tip_label: Label
var _tip_index: int = 0
var _tip_t: float = 0.0
var _tip_tween: Tween
var _nemesis_plate: Label
var _sound_btn: Button
var _deploying: bool = false
var _deploy_overlay: ColorRect
var _deploy_label: Label

# Play page
var _char_cards: Dictionary
var _mode_cards: Dictionary
var _diff_buttons: Array[Button] = []
var _diff_info: Label
var _deploy_btn: Button
var _deploy_summary: Label
var _detail_name: Label
var _detail_code: Label
var _detail_summary: Label
var _detail_stats: Label
var _detail_skills: Label
var _vitality_bar: ProgressBar
var _speed_bar: ProgressBar
var _coop_settings: Label

# Co-op page
var coop_status: Label
var coop_roster: Label
var coop_ip: LineEdit
var coop_start: Button
var coop_resume: Button
var coop_invite: Button
var coop_host_steam: Button

# Audio
var _amb: Array[AudioStreamPlayer] = []
var _amb_vol: Array[float] = []
var _muted: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_rng.randomize()
	_muted = not GameState.menu_sound
	_build_diorama()
	_build_ui()
	_build_ambience()
	_apply_menu_audio()
	_select_character(GameState.selected_character)
	_show_page("coop" if Net.is_online() or Net.status_text != "" else "play")
	Nav_sync_index()
	Net.lobby_changed.connect(_refresh_coop)
	Net.lobby_changed.connect(_refresh_play)
	Net.status_changed.connect(_on_net_status)
	_entrance_animation()


func _exit_tree() -> void:
	if Net.lobby_changed.is_connected(_refresh_coop):
		Net.lobby_changed.disconnect(_refresh_coop)
	if Net.lobby_changed.is_connected(_refresh_play):
		Net.lobby_changed.disconnect(_refresh_play)
	if Net.status_changed.is_connected(_on_net_status):
		Net.status_changed.disconnect(_on_net_status)


func _on_net_status(_text: String) -> void:
	_refresh_coop()


func Nav_sync_index() -> void:
	var idx := _nav_order.find(_current_page)
	if idx >= 0:
		_nav_index = idx
	_update_nav_styles()


# ---------------------------------------------------------------------------
# FRAME UPDATES
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	_orbit_time += delta * 0.22
	if is_instance_valid(cam_pivot):
		cam_pivot.rotation.y = sin(_orbit_time) * 0.13
	var vp := get_viewport().get_visible_rect().size
	var m := get_viewport().get_mouse_position()
	if vp.x > 0.0 and vp.y > 0.0:
		var target := Vector2(clampf((m.x / vp.x - 0.5) * 2.0, -1.0, 1.0), clampf((m.y / vp.y - 0.5) * 2.0, -1.0, 1.0))
		_parallax = _parallax.lerp(target, minf(delta * 3.0, 1.0))
	if is_instance_valid(menu_cam):
		menu_cam.look_at(Vector3(0.9 + _parallax.x * 0.7, 1.15 - _parallax.y * 0.4, 0.0), Vector3.UP)
	if is_instance_valid(operator):
		operator.rotation.y = PI + sin(_t * 0.4) * 0.045
	# Fire flicker
	if is_instance_valid(fire_light):
		fire_light.light_energy = 2.3 + sin(_t * 11.0) * 0.35 + sin(_t * 23.7) * 0.22 + _rng.randf_range(-0.12, 0.12)
	# Lamp flicker with a periodic brownout
	if is_instance_valid(lamp_light):
		var brown := fmod(_t, 9.0) > 8.55
		lamp_light.light_energy = 0.0 if brown else 1.15 + sin(_t * 13.0) * 0.14 + _rng.randf_range(-0.08, 0.08)
	# Radio tower beacon
	if is_instance_valid(beacon_light):
		var on := sin(_t * 2.2) > 0.55
		beacon_light.light_energy = 2.6 if on else 0.0
		if beacon_mat:
			beacon_mat.emission_energy_multiplier = 3.2 if on else 0.15
	# Drifting fog cards
	for i in range(fog_cards.size()):
		var c := fog_cards[i]
		if is_instance_valid(c):
			c.position.x += fog_speeds[i] * delta
			if c.position.x > 16.0:
				c.position.x = -16.0
	# Lightning
	_lightning_t -= delta
	if _lightning_t <= 0.0:
		_lightning_t = _rng.randf_range(9.0, 18.0)
		_flash_lightning()
	# Distant ambience one-shots
	_amb_event_t -= delta
	if _amb_event_t <= 0.0:
		_amb_event_t = _rng.randf_range(7.0, 15.0)
		var picks := ["crow", "bell_far", "scream_far", "train_horn", "creak", "whisper_eerie", "metal_scrape"]
		_sfx(picks[_rng.randi_range(0, picks.size() - 1)], _rng.randf_range(-19.0, -14.0), _rng.randf_range(0.9, 1.1))
	# Nemesis plate pulse
	if is_instance_valid(_nemesis_plate):
		_nemesis_plate.modulate.a = 0.72 + 0.28 * sin(_t * 3.0)
	# Rotating tips
	_tip_t += delta
	if _tip_t >= 9.0:
		_tip_t = 0.0
		_rotate_tip()


func _physics_process(delta: float) -> void:
	if operator_rig:
		operator_rig.update(delta, "idle", 0.0)
	for r in zombie_rigs:
		r.update(delta, "idle", 0.0)


func _flash_lightning() -> void:
	if not is_instance_valid(lightning):
		return
	lightning.light_energy = 2.6
	var tw := lightning.create_tween()
	tw.tween_property(lightning, "light_energy", 0.0, 0.14)
	tw.tween_callback(func(): lightning.light_energy = 1.5).set_delay(0.16)
	tw.tween_property(lightning, "light_energy", 0.0, 0.4)
	get_tree().create_timer(1.15).timeout.connect(func():
		if is_instance_valid(self):
			_sfx("thunder_far", -11.0, _rng.randf_range(0.9, 1.1)))


# ---------------------------------------------------------------------------
# KEYBOARD NAVIGATION
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if _deploying or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var focused := get_viewport().gui_get_focus_owner()
	var kc: int = event.keycode
	if kc == KEY_ESCAPE:
		if focused == null:
			_show_page("play")
		return
	if focused != null:
		return
	match kc:
		KEY_UP, KEY_W:
			_nav_move(-1)
		KEY_DOWN, KEY_S:
			_nav_move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate_nav()
		_:
			if kc >= KEY_1 and kc <= KEY_7:
				var idx := kc - KEY_1
				if idx < _nav_order.size():
					_nav_index = idx
					_update_nav_styles()
					_activate_nav()


func _nav_move(dir: int) -> void:
	if _nav_order.is_empty():
		return
	_nav_index = wrapi(_nav_index + dir, 0, _nav_order.size())
	_update_nav_styles()
	_sfx("hit_tick", -16.0, 1.2)


func _activate_nav() -> void:
	if _nav_order.is_empty():
		return
	var b: Button = _nav[_nav_order[_nav_index]]
	if is_instance_valid(b) and not b.disabled:
		b.pressed.emit()


func _update_nav_styles() -> void:
	for i in range(_nav_order.size()):
		var k := _nav_order[i]
		var b: Button = _nav[k]
		if not is_instance_valid(b):
			continue
		var selected := k == _current_page
		var cursor := i == _nav_index
		var bg := Color(1, 1, 1, 0.08) if selected else (Color(1, 1, 1, 0.045) if cursor else Color(0, 0, 0, 0))
		var bar := ACCENT if selected else (Color(1, 1, 1, 0.25) if cursor else Color(0, 0, 0, 0))
		b.add_theme_stylebox_override("normal", _box(bg, bar, 0, 4 if selected else (2 if cursor else 0)))


# ---------------------------------------------------------------------------
# 3D DIORAMA
# ---------------------------------------------------------------------------
func _build_diorama() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.003, 0.004, 0.006)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_energy = 0.10
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.94
	env.fog_enabled = true
	env.fog_density = 0.048
	env.fog_light_color = Color(0.015, 0.02, 0.028)
	env.fog_light_energy = 0.32
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = 0.45
	env.glow_bloom = 0.05
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 0.82
	if GameState.graphics_quality >= 1:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.036
		env.volumetric_fog_length = 40.0
	world_env.environment = env
	add_child(world_env)

	# Wet asphalt clearing
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	ground.mesh = plane
	ground.material_override = MaterialLib.get_world("asphalt", 0.22, Color(0.5, 0.55, 0.62), 0.0, 0.9, 0.55, 0.5, true)
	add_child(ground)

	# Operator podium + emissive ring
	var podium := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.55
	cyl.bottom_radius = 1.7
	cyl.height = 0.18
	cyl.radial_segments = 48
	podium.mesh = cyl
	podium.position = Vector3(0, 0.09, 0)
	podium.material_override = MaterialLib.get_world("concrete", 0.5, Color(0.5, 0.51, 0.55), 0.0, 1.0, 0.0, 0.4)
	add_child(podium)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.58
	torus.outer_radius = 1.72
	torus.rings = 48
	torus.ring_segments = 12
	ring.mesh = torus
	ring.position = Vector3(0, 0.19, 0)
	podium_ring_mat = StandardMaterial3D.new()
	podium_ring_mat.albedo_color = Color(0.08, 0.07, 0.07)
	podium_ring_mat.roughness = 0.92
	podium_ring_mat.metallic = 0.35
	podium_ring_mat.emission_enabled = false
	ring.material_override = podium_ring_mat
	add_child(ring)

	# Operator showcase
	operator = (load("res://assets/models/player_survivor.glb") as PackedScene).instantiate() as Node3D
	operator.position = Vector3(0, 0.18, 0)
	operator.rotation.y = PI
	add_child(operator)
	operator_rig = ZombieRigScript.new()
	var proxies := SkinRigAdapter.attach(operator)
	if operator_rig.bind(proxies if proxies else operator):
		operator_rig.limp = 0.0
		operator_rig.hunch = 0.0
		operator_rig.arm_style = 2
		operator_rig.sway = 0.3
	accent_light = OmniLight3D.new()
	accent_light.light_color = ACCENT
	accent_light.light_energy = 0.22
	accent_light.omni_range = 4.0
	accent_light.position = Vector3(0, 1.3, 0.5)
	operator.add_child(accent_light)

	# Horde looming in the fog behind the operator
	var zdata := [
		["zombie_soldier_v2", Vector3(-2.4, 0, -3.8), 2.85, 0.15, 0.25, 0, 0.8],
		["zombie_walker_v2", Vector3(2.0, 0, -4.9), 3.4, 0.3, 0.35, 1, 1.0],
		["zombie_runner_v2", Vector3(-0.3, 0, -6.6), 3.05, 0.0, 0.15, 0, 0.6],
	]
	for zd in zdata:
		var z := (load("res://assets/models/%s.glb" % zd[0]) as PackedScene).instantiate() as Node3D
		z.position = zd[1]
		z.rotation.y = zd[2]
		add_child(z)
		var zr := ZombieRigScript.new()
		var zp := SkinRigAdapter.attach(z)
		if zr.bind(zp if zp else z):
			zr.limp = zd[3]
			zr.hunch = zd[4]
			zr.arm_style = zd[5]
			zr.sway = zd[6]
			zr.twitch_amt = 0.65
			zombie_rigs.append(zr)
			var head_node: Node3D = (zr.nodes.get("Head") as Node3D) if zr.nodes.has("Head") else z.find_child("Head", true, false) as Node3D
			if head_node:
				var eye_mat := MaterialLib.get_emissive(Color(0.88, 0.70, 0.28), 0.9)
				var eye_sm := SphereMesh.new()
				eye_sm.radius = 0.013
				eye_sm.height = 0.026
				for sx in [-1.0, 1.0]:
					var eye := MeshInstance3D.new()
					eye.mesh = eye_sm
					eye.material_override = eye_mat
					eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					eye.position = Vector3(0.044 * sx, 0.11, -0.105)
					head_node.add_child(eye)

	# Set dressing
	_prop("barrel", Vector3(-2.7, 0, 1.9), 0.3)
	_prop("barrel", Vector3(3.4, 0, -1.2), 1.1)
	_prop("crate", Vector3(2.6, 0, 0.8), 0.4)
	_prop("crate", Vector3(2.95, 0, 1.6), -0.2, 0.8)
	_prop("sandbags", Vector3(-1.8, 0, -1.6), 0.3)
	_prop("sandbags", Vector3(1.9, 0, -2.2), -0.5)
	_prop("tire_stack", Vector3(-3.6, 0, -0.6), 0.8)
	_prop("dead_tree", Vector3(-5.2, 0, -4.5), 0.4, 1.2)
	_prop("car_wreck", Vector3(4.6, 0, -3.4), 0.7)
	_prop("truck", Vector3(-6.5, 0, -8.5), 0.4, 1.1)
	_prop("rubble", Vector3(0.9, 0, -2.8), 0.2)
	_prop("rubble", Vector3(-3.2, 0, -5.8), 1.4)
	_prop("barbed_wire", Vector3(0.4, 0, -8.2), 0.15, 1.3)
	_prop("lamp_post", Vector3(3.6, 0, -2.6), 0.0)
	_prop("radio_tower", Vector3(2.0, 0, -13.0), 0.0, 1.7)

	# Fire barrel glow + embers
	var coal := MeshInstance3D.new()
	var coal_mesh := SphereMesh.new()
	coal_mesh.radius = 0.18
	coal_mesh.height = 0.2
	coal.mesh = coal_mesh
	coal.position = Vector3(-2.7, 0.95, 1.9)
	var coal_mat := StandardMaterial3D.new()
	coal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	coal_mat.albedo_color = Color(1.0, 0.5, 0.15)
	coal_mat.emission_enabled = true
	coal_mat.emission = Color(1.0, 0.45, 0.1)
	coal_mat.emission_energy_multiplier = 2.5
	coal.material_override = coal_mat
	add_child(coal)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.55, 0.2)
	fire_light.light_energy = 2.3
	fire_light.omni_range = 6.0
	fire_light.position = Vector3(-2.7, 1.15, 1.9)
	add_child(fire_light)
	_embers(Vector3(-2.7, 1.0, 1.9), 22)
	_dust()

	# Key / rim / fill lighting
	var key := SpotLight3D.new()
	key.light_color = Color(0.92, 0.84, 0.72)
	key.light_energy = 4.6
	key.spot_range = 16.0
	key.spot_angle = 28.0
	key.shadow_enabled = GameState.graphics_quality >= 1
	key.look_at_from_position(Vector3(1.9, 5.6, 3.4), Vector3(0, 1.1, 0), Vector3.UP)
	add_child(key)
	rim_light = SpotLight3D.new()
	rim_light.light_color = Color(0.95, 0.25, 0.18)
	rim_light.light_energy = 1.3
	rim_light.spot_range = 12.0
	rim_light.spot_angle = 50.0
	rim_light.look_at_from_position(Vector3(-2.6, 3.4, -3.6), Vector3(0, 1.2, 0), Vector3.UP)
	add_child(rim_light)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.4, 0.7, 1.0)
	fill.light_energy = 0.18
	fill.omni_range = 10.0
	fill.position = Vector3(2.5, 1.6, 4.5)
	add_child(fill)
	var horde_glow := OmniLight3D.new()
	horde_glow.light_color = Color(0.9, 0.15, 0.1)
	horde_glow.light_energy = 0.45
	horde_glow.omni_range = 7.0
	horde_glow.position = Vector3(0, 1.8, -8.0)
	add_child(horde_glow)

	# Flickering lamp
	lamp_light = SpotLight3D.new()
	lamp_light.light_color = Color(0.7, 0.85, 1.0)
	lamp_light.light_energy = 1.15
	lamp_light.spot_range = 9.0
	lamp_light.spot_angle = 38.0
	lamp_light.look_at_from_position(Vector3(3.6, 4.2, -2.6), Vector3(2.8, 0, -1.8), Vector3.UP)
	add_child(lamp_light)

	# Radio tower beacon
	var beacon := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.12
	bs.height = 0.24
	beacon.mesh = bs
	beacon.position = Vector3(2.0, 8.4, -13.0)
	beacon_mat = StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.albedo_color = Color(1.0, 0.15, 0.1)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.1, 0.08)
	beacon_mat.emission_energy_multiplier = 3.2
	beacon.material_override = beacon_mat
	add_child(beacon)
	beacon_light = OmniLight3D.new()
	beacon_light.light_color = Color(1.0, 0.12, 0.08)
	beacon_light.light_energy = 2.6
	beacon_light.omni_range = 6.0
	beacon_light.position = Vector3(2.0, 8.4, -13.0)
	add_child(beacon_light)

	# Lightning (flashes in _process)
	lightning = DirectionalLight3D.new()
	lightning.light_color = Color(0.75, 0.82, 1.0)
	lightning.light_energy = 0.0
	lightning.rotation_degrees = Vector3(-52, -28, 0)
	add_child(lightning)

	# Drifting fog cards
	var disc := _soft_disc()
	var card_count := 7 if GameState.graphics_quality >= 1 else 4
	for i in range(card_count):
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		var s := _rng.randf_range(8.0, 14.0)
		q.size = Vector2(s, s * 0.5)
		mi.mesh = q
		mi.position = Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(0.6, 2.2), _rng.randf_range(-10.0, 2.0))
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		fm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		fm.albedo_texture = disc
		fm.albedo_color = Color(0.6, 0.7, 0.8, _rng.randf_range(0.05, 0.1))
		mi.material_override = fm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		fog_cards.append(mi)
		fog_speeds.append(_rng.randf_range(0.12, 0.3))

	# Camera
	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	menu_cam = Camera3D.new()
	menu_cam.position = Vector3(0.55, 2.05, 7.5)
	menu_cam.fov = 55.0
	menu_cam.current = true
	cam_pivot.add_child(menu_cam)
	menu_cam.look_at(Vector3(0.9, 1.15, 0), Vector3.UP)


func _prop(nm: String, pos: Vector3, rot_y: float = 0.0, sc: float = 1.0) -> Node3D:
	var path := "res://assets/models/prop_%s.glb" % nm
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * sc
	add_child(n)
	return n


func _soft_disc() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 128
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 1.0)
	return gt


func _particle_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = tex
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _embers(pos: Vector3, count: int) -> void:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = 1.8
	p.preprocess = 1.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.22
	p.direction = Vector3.UP
	p.spread = 20.0
	p.gravity = Vector3(0, 0.5, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.2
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.randomness = 0.5
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 0.62, 0.2, 1), Color(0.9, 0.25, 0.06, 0.7), Color(0.3, 0.05, 0.02, 0)])
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	p.mesh = q
	p.material_override = _particle_mat(_soft_disc())
	p.position = pos
	p.emitting = true
	add_child(p)


func _dust() -> void:
	var p := CPUParticles3D.new()
	p.amount = 50 if GameState.graphics_quality >= 1 else 25
	p.lifetime = 9.0
	p.preprocess = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(9, 2.5, 7)
	p.direction = Vector3(0.3, 0.05, 0.1)
	p.spread = 60.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.08
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	g.colors = PackedColorArray([Color(0.7, 0.75, 0.85, 0), Color(0.7, 0.75, 0.85, 0.4), Color(0.7, 0.75, 0.85, 0.4), Color(0.7, 0.75, 0.85, 0)])
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	p.mesh = q
	p.material_override = _particle_mat(_soft_disc())
	p.position = Vector3(0, 2.5, -2)
	p.emitting = true
	add_child(p)


# ---------------------------------------------------------------------------
# AUDIO
# ---------------------------------------------------------------------------
func _build_ambience() -> void:
	var loops := [["drone_loop", -13.0], ["wind_loop", -15.0], ["fire_loop", -16.0]]
	for l in loops:
		var st := GameState.get_sfx_stream(l[0])
		if st is AudioStreamWAV:
			var w := st as AudioStreamWAV
			if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				w.loop_end = int(w.get_length() * float(w.mix_rate))
		if st == null:
			continue
		var p := AudioStreamPlayer.new()
		p.stream = st
		p.bus = &"SFX"
		p.volume_db = l[1]
		add_child(p)
		p.play()
		_amb.append(p)
		_amb_vol.append(l[1])


func _apply_menu_audio() -> void:
	for i in range(_amb.size()):
		if is_instance_valid(_amb[i]):
			_amb[i].volume_db = -80.0 if _muted else _amb_vol[i]
	if is_instance_valid(_sound_btn):
		_sound_btn.text = "SOUND  OFF" if _muted else "SOUND  ON"
		_sound_btn.add_theme_color_override("font_color", DIM if _muted else CYAN)


func _toggle_sound() -> void:
	_muted = not _muted
	GameState.menu_sound = not _muted
	GameState.write_save()
	_apply_menu_audio()
	if not _muted:
		_sfx("hit_tick", -10.0, 1.0)


func _sfx(sfx_name: String, vol: float = -12.0, pitch: float = 1.0) -> void:
	if _muted:
		return
	GameState.play_sfx(sfx_name, vol, pitch)


# ---------------------------------------------------------------------------
# STYLE HELPERS
# ---------------------------------------------------------------------------
func _box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, left_bar: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = maxi(bw, left_bar)
	sb.border_width_right = bw
	sb.border_width_top = bw
	sb.border_width_bottom = bw
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.set_stylebox("normal", "Button", _box(Color(0.07, 0.08, 0.1, 0.92), Color(1, 1, 1, 0.08), 1))
	th.set_stylebox("hover", "Button", _box(Color(0.14, 0.12, 0.13, 0.96), ACCENT, 1))
	th.set_stylebox("pressed", "Button", _box(Color(0.22, 0.1, 0.09, 0.98), ACCENT, 1))
	th.set_stylebox("disabled", "Button", _box(Color(0.06, 0.06, 0.07, 0.7), Color(1, 1, 1, 0.04), 1))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color(1, 1, 1))
	th.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.5))
	th.set_font_size("font_size", "Button", 16)
	th.set_font_size("font_size", "Label", 15)
	th.set_color("font_color", "Label", TEXT)
	th.set_stylebox("normal", "LineEdit", _box(Color(0.04, 0.05, 0.07, 0.95), Color(1, 1, 1, 0.15), 1))
	th.set_stylebox("focus", "LineEdit", _box(Color(0.05, 0.07, 0.1, 0.98), CYAN, 1))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("caret_color", "LineEdit", CYAN)
	# Scrollbars in the terminal's own language
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color(1, 1, 1, 0.04)
	scroll_bg.corner_radius_top_left = 3
	scroll_bg.corner_radius_top_right = 3
	scroll_bg.corner_radius_bottom_left = 3
	scroll_bg.corner_radius_bottom_right = 3
	scroll_bg.content_margin_left = 3
	scroll_bg.content_margin_right = 3
	th.set_stylebox("scroll", "VScrollBar", scroll_bg)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.95, 0.30, 0.20, 0.55)
	grab.corner_radius_top_left = 3
	grab.corner_radius_top_right = 3
	grab.corner_radius_bottom_left = 3
	grab.corner_radius_bottom_right = 3
	th.set_stylebox("grabber", "VScrollBar", grab)
	var grab_hl := grab.duplicate() as StyleBoxFlat
	grab_hl.bg_color = Color(0.95, 0.30, 0.20, 0.85)
	th.set_stylebox("grabber_highlight", "VScrollBar", grab_hl)
	var grab_pr := grab.duplicate() as StyleBoxFlat
	grab_pr.bg_color = ACCENT
	th.set_stylebox("grabber_pressed", "VScrollBar", grab_pr)
	# Sliders (options panel)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(1, 1, 1, 0.1)
	slider.corner_radius_top_left = 2
	slider.corner_radius_top_right = 2
	slider.corner_radius_bottom_left = 2
	slider.corner_radius_bottom_right = 2
	th.set_stylebox("slider", "HSlider", slider)
	var garea := StyleBoxFlat.new()
	garea.bg_color = Color(0.42, 0.85, 1.0, 0.35)
	garea.corner_radius_top_left = 2
	garea.corner_radius_top_right = 2
	garea.corner_radius_bottom_left = 2
	garea.corner_radius_bottom_right = 2
	th.set_stylebox("grabber_area", "HSlider", garea)
	var garea_hl := garea.duplicate() as StyleBoxFlat
	garea_hl.bg_color = Color(0.42, 0.85, 1.0, 0.6)
	th.set_stylebox("grabber_area_highlight", "HSlider", garea_hl)
	# Progress bars
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(1, 1, 1, 0.08)
	pbg.corner_radius_top_left = 2
	pbg.corner_radius_top_right = 2
	pbg.corner_radius_bottom_left = 2
	pbg.corner_radius_bottom_right = 2
	th.set_stylebox("background", "ProgressBar", pbg)
	var pfill := StyleBoxFlat.new()
	pfill.bg_color = CYAN
	pfill.corner_radius_top_left = 2
	pfill.corner_radius_top_right = 2
	pfill.corner_radius_bottom_left = 2
	pfill.corner_radius_bottom_right = 2
	th.set_stylebox("fill", "ProgressBar", pfill)
	return th


func _label(text: String, size: int, col: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _header(parent: Control, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tick := ColorRect.new()
	tick.color = ACCENT
	tick.custom_minimum_size = Vector2(3, 14)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tick)
	row.add_child(_label(text, 13, ACCENT))
	parent.add_child(row)


func _stat_bar(parent: Control, caption: String, frac: float, col: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cap := _label(caption, 11, DIM)
	cap.custom_minimum_size = Vector2(70, 0)
	row.add_child(cap)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(frac, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	parent.add_child(row)
	return bar


func _stat_tile(parent: Control, value: String, caption: String, col: Color) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.07), 1))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var val := _label(value, 21, col)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(val)
	var cap := _label(caption, 9, DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	parent.add_child(p)


# ---------------------------------------------------------------------------
# LAYOUT
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = _make_theme()
	layer.add_child(root)

	# Left + top fades so the UI reads over the diorama
	var fade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.01, 0.012, 0.02, 0.94))
	grad.set_color(1, Color(0.01, 0.012, 0.02, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	fade.texture = gt
	fade.anchor_bottom = 1.0
	fade.offset_right = 860
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	var tfade := TextureRect.new()
	var tg := Gradient.new()
	tg.set_color(0, Color(0.01, 0.012, 0.02, 0.85))
	tg.set_color(1, Color(0.01, 0.012, 0.02, 0.0))
	var tgt := GradientTexture2D.new()
	tgt.gradient = tg
	tgt.fill_from = Vector2(0, 0)
	tgt.fill_to = Vector2(0, 1)
	tfade.texture = tgt
	tfade.anchor_right = 1.0
	tfade.offset_bottom = 150
	tfade.stretch_mode = TextureRect.STRETCH_SCALE
	tfade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tfade)

	# Title block
	_title_box = VBoxContainer.new()
	_title_box.position = Vector2(48, 34)
	_title_box.add_theme_constant_override("separation", 4)
	root.add_child(_title_box)
	_title_box.add_child(_label("OUTPOST NACHT-7  //  CLASSIFIED", 12, ACCENT))
	var t1 := _label("DEAD PROTOCOL", 56, Color(0.96, 0.96, 0.98))
	t1.add_theme_constant_override("outline_size", 6)
	t1.add_theme_color_override("font_outline_color", Color.BLACK)
	_title_box.add_child(t1)
	var rule := ColorRect.new()
	rule.color = ACCENT
	rule.custom_minimum_size = Vector2(248, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_title_box.add_child(rule)
	_title_box.add_child(_label("N A C H T   O U T B R E A K", 17, Color(0.72, 0.75, 0.8)))
	var lvl := GameState.career_level()
	var lo := GameState.xp_for_level(lvl)
	var hi := GameState.xp_for_level(lvl + 1)
	var career_row := HBoxContainer.new()
	career_row.add_theme_constant_override("separation", 10)
	var lv_lbl := _label("LV %d" % lvl, 14, CYAN)
	lv_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	career_row.add_child(lv_lbl)
	var xp_bar := ProgressBar.new()
	xp_bar.min_value = lo
	xp_bar.max_value = hi
	xp_bar.value = GameState.career_xp
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(150, 8)
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	career_row.add_child(xp_bar)
	var xp_lbl := _label("%d / %d XP" % [GameState.career_xp, hi], 11, DIM)
	xp_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	career_row.add_child(xp_lbl)
	_title_box.add_child(career_row)
	if not GameState.nemesis.is_empty():
		var nm: Dictionary = GameState.nemesis
		var nt := clampi(int(nm.get("tier", 3)), 3, 5)
		_nemesis_plate = _label("NEMESIS ACTIVE  —  %s  %s" % [String(nm.get("name", "")), "★".repeat(nt)], 13, ZombieEnemy.TIER_COLORS[nt])
		_title_box.add_child(_nemesis_plate)

	# Sound toggle (top-right)
	_sound_btn = Button.new()
	_sound_btn.text = "SOUND  ON"
	_sound_btn.custom_minimum_size = Vector2(118, 34)
	_sound_btn.anchor_left = 1.0
	_sound_btn.anchor_right = 1.0
	_sound_btn.offset_left = -166
	_sound_btn.offset_right = -48
	_sound_btn.offset_top = 34
	_sound_btn.add_theme_font_size_override("font_size", 13)
	_sound_btn.focus_mode = Control.FOCUS_NONE
	_sound_btn.pressed.connect(_toggle_sound)
	root.add_child(_sound_btn)

	# Navigation rail
	var rail := VBoxContainer.new()
	rail.position = Vector2(48, 292)
	rail.custom_minimum_size = Vector2(300, 0)
	rail.add_theme_constant_override("separation", 6)
	root.add_child(rail)
	var saved := GameState.load_world()
	if not saved.is_empty() and int(saved.get("players", 1)) <= 1:
		var mode_name: String = MODES.get(String(saved.get("mode", "casual")), MODES["casual"])["name"]
		_nav_button(rail, "continue", "CONTINUE", "%s • ROUND %d • %s" % [mode_name, int(saved.get("round", 1)), GameState.DIFFICULTY_NAMES[int(saved.get("difficulty", 1))]], func(): _continue_run(saved))
	_nav_button(rail, "play", "PLAY", "SOLO RUN", func(): _show_page("play"))
	_nav_button(rail, "coop", "CO-OP", "UP TO 8 PLAYERS", func(): _show_page("coop"))
	_nav_button(rail, "career", "CAREER", "LEVEL, UNLOCKS & RECORDS", func(): _show_page("career"))
	_nav_button(rail, "intel", "INTEL", "RANKS, EVENTS & FIELD MANUAL", func(): _show_page("intel"))
	_nav_button(rail, "options", "OPTIONS", "AUDIO, CONTROLS, VIDEO", func(): _show_page("options"))
	_nav_button(rail, "quit", "QUIT", "", func(): get_tree().quit())

	# Footer: rotating tip + controls + status
	_tip_label = _label(GameState.keyify(TIPS[0]), 12, Color(0.62, 0.66, 0.72))
	_tip_label.anchor_top = 1.0
	_tip_label.anchor_bottom = 1.0
	_tip_label.offset_left = 48
	_tip_label.offset_top = -58
	_tip_label.offset_right = 820
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_tip_label)
	var foot := _label(GameState.keyify("[WASD] MOVE   [SHIFT] SPRINT   [R] RELOAD   [V] KNIFE   [G] GRENADE   [Q]/[F] SKILLS   [E] USE   [ESC] PAUSE"), 11, Color(0.5, 0.53, 0.58))
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 48
	foot.offset_top = -34
	root.add_child(foot)
	var status := _label(("STEAM: %s" % Net.my_name) if Net.steam_ok else "OFFLINE — DIRECT IP AVAILABLE", 11, CYAN if Net.steam_ok else DIM)
	status.anchor_left = 1.0
	status.anchor_right = 1.0
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.offset_right = -48
	status.offset_top = -58
	status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(status)
	var nav_hint := _label("[↑↓] NAVIGATE   [ENTER] SELECT   [1-7] QUICK", 11, Color(0.5, 0.53, 0.58))
	nav_hint.anchor_left = 1.0
	nav_hint.anchor_right = 1.0
	nav_hint.anchor_top = 1.0
	nav_hint.anchor_bottom = 1.0
	nav_hint.offset_right = -48
	nav_hint.offset_top = -34
	nav_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	nav_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(nav_hint)

	# Content panel
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -690
	_panel.offset_right = -40
	_panel.offset_top = 84
	_panel.offset_bottom = -76
	var pst := _box(Color(0.022, 0.028, 0.04, 0.92), ACCENT, 1)
	pst.border_width_top = 3
	pst.content_margin_left = 24
	pst.content_margin_right = 24
	pst.content_margin_top = 16
	pst.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", pst)
	root.add_child(_panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 12)
	_panel.add_child(pv)
	var title_row := HBoxContainer.new()
	_content_title = _label("", 28, Color(0.97, 0.97, 0.99))
	_content_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_content_title)
	_page_index = _label("", 13, DIM)
	_page_index.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_page_index)
	pv.add_child(title_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	_stack = VBoxContainer.new()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stack)

	_pages["play"] = _build_play_page()
	_pages["coop"] = _build_coop_page()
	_pages["career"] = _build_career_page()
	_pages["intel"] = _build_intel_page()
	var opts := OptionsPanel.new()
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages["options"] = opts
	for k in _pages:
		_stack.add_child(_pages[k])

	# Deploy fade overlay
	_deploy_overlay = ColorRect.new()
	_deploy_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deploy_overlay.color = Color(0.005, 0.008, 0.012, 1)
	_deploy_overlay.modulate.a = 0.0
	_deploy_overlay.visible = false
	_deploy_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_deploy_overlay)
	var dv := VBoxContainer.new()
	dv.set_anchors_preset(Control.PRESET_CENTER)
	dv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dv.grow_vertical = Control.GROW_DIRECTION_BOTH
	dv.add_theme_constant_override("separation", 8)
	_deploy_overlay.add_child(dv)
	_deploy_label = _label("DEPLOYING TO NACHT-7 …", 26, Color(0.96, 0.96, 0.98))
	_deploy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(_deploy_label)
	var sub := _label("STAND BY", 12, DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(sub)


func _nav_button(parent: Control, key: String, title: String, sub: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = "%s\n%s" % [title, sub] if sub != "" else title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(300, 56 if sub != "" else 46)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.06), ACCENT, 0, 4))
	b.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.1), ACCENT, 0, 4))
	b.pressed.connect(func():
		_sfx("buy_ching", -12.0, 1.4)
		on_press.call()
	)
	var idx := _nav_order.size()
	b.mouse_entered.connect(func():
		if _nav_index != idx:
			_nav_index = idx
			_update_nav_styles()
			_sfx("hit_tick", -18.0, 1.3)
	)
	parent.add_child(b)
	_nav[key] = b
	_nav_order.append(key)


func _entrance_animation() -> void:
	_title_box.modulate.a = 0.0
	_title_box.position.x = 24.0
	var tt := _title_box.create_tween()
	tt.set_parallel(true)
	tt.tween_property(_title_box, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tt.tween_property(_title_box, "position:x", 48.0, 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_panel.modulate.a = 0.0
	var pt := _panel.create_tween()
	pt.tween_property(_panel, "modulate:a", 1.0, 0.45).set_delay(0.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	for i in range(_nav_order.size()):
		var b: Button = _nav[_nav_order[i]]
		b.modulate.a = 0.0
		var bt := b.create_tween()
		bt.tween_property(b, "modulate:a", 1.0, 0.35).set_delay(0.12 + i * 0.05)


func _show_page(key: String) -> void:
	if not _pages.has(key) or key == _current_page:
		return
	_current_page = key
	var titles := {"play": "PLAY", "coop": "CO-OP SQUAD", "career": "CAREER", "intel": "INTEL", "options": "OPTIONS"}
	_content_title.text = titles.get(key, "")
	var pi := PAGE_ORDER.find(key)
	_page_index.text = "%02d / %02d" % [pi + 1, PAGE_ORDER.size()] if pi >= 0 else ""
	if key == "career":
		var old: Control = _pages["career"]
		old.visible = false
		old.queue_free()
		_pages["career"] = _build_career_page()
		_stack.add_child(_pages["career"])
	for k in _pages:
		_pages[k].visible = k == key
	var idx := _nav_order.find(key)
	if idx >= 0:
		_nav_index = idx
	_update_nav_styles()
	var page: Control = _pages[key]
	page.modulate.a = 0.0
	if page.size.x > 0.0:
		page.pivot_offset = page.size * 0.5
		page.scale = Vector2(0.985, 0.985)
	var tw := page.create_tween()
	tw.set_parallel(true)
	tw.tween_property(page, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(page, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if key == "coop":
		_refresh_coop()


func _rotate_tip() -> void:
	if not is_instance_valid(_tip_label):
		return
	_tip_index = (_tip_index + 1) % TIPS.size()
	if _tip_tween and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_tween = _tip_label.create_tween()
	_tip_tween.tween_property(_tip_label, "modulate:a", 0.0, 0.25)
	_tip_tween.tween_callback(func(): _tip_label.text = GameState.keyify(TIPS[_tip_index]))
	_tip_tween.tween_property(_tip_label, "modulate:a", 1.0, 0.25)


# ---------------------------------------------------------------------------
# PLAY
# ---------------------------------------------------------------------------
func _build_play_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header(v, "OPERATOR")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	for cid in ["ravager", "alchemist", "warden"]:
		var cd: Dictionary = GameState.CHARACTERS[cid]
		var b := Button.new()
		var full := String(cd["name"])
		var short := full.get_slice("'", 1) if full.contains("'") else full.get_slice(" ", full.get_slice_count(" ") - 1)
		b.text = "%s\n%s" % [short, String(cd["codename"]).get_slice("//", 1).strip_edges()]
		b.custom_minimum_size = Vector2(0, 62)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			_select_character(cid)
			match cid:
				"ravager": _sfx("monster_roar", -15.0, 1.0)
				"alchemist": _sfx("pain_drug", -13.0, 1.0)
				"warden": _sfx("trap_zap", -14.0, 1.0)
		)
		row.add_child(b)
		_char_cards[cid] = b
	_detail_code = _label("", 13, ACCENT)
	v.add_child(_detail_code)
	_detail_name = _label("", 21, Color(0.97, 0.97, 0.99))
	v.add_child(_detail_name)
	_detail_summary = _label("", 14, Color(0.78, 0.8, 0.85), true)
	v.add_child(_detail_summary)
	_vitality_bar = _stat_bar(v, "VITALITY", 0.7, ACCENT)
	_speed_bar = _stat_bar(v, "SPEED", 0.7, CYAN)
	_detail_stats = _label("", 12, AMBER)
	v.add_child(_detail_stats)
	_detail_skills = _label("", 12, TEXT, true)
	v.add_child(_detail_skills)

	_header(v, "MODE")
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	v.add_child(mrow)
	for mid in ["casual", "infinite"]:
		var b := Button.new()
		b.text = "%s\n%s" % [MODES[mid]["name"], MODES[mid]["desc"]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 88)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			GameState.game_mode = mid
			GameState.write_save()
			_sfx("hit_tick", -10.0, 1.0)
			_refresh_play())
		mrow.add_child(b)
		_mode_cards[mid] = b

	_header(v, "DIFFICULTY")
	var drow := GridContainer.new()
	drow.columns = 4
	drow.add_theme_constant_override("h_separation", 8)
	drow.add_theme_constant_override("v_separation", 8)
	v.add_child(drow)
	for i in range(GameState.DIFFICULTIES.size()):
		var b := Button.new()
		b.text = "%s\nSCORE x%s" % [GameState.DIFFICULTY_NAMES[i], str(snappedf(float(GameState.DIFFICULTIES[i]["score"]), 0.01))]
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.focus_mode = Control.FOCUS_NONE
		if i >= 3:
			b.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4).lerp(Color(1.0, 0.2, 0.2), float(i - 3) / 3.0))
		var idx := i
		b.pressed.connect(func():
			GameState.difficulty = idx
			GameState.write_save()
			_sfx("hit_tick", -10.0, 1.0)
			_refresh_play())
		drow.add_child(b)
		_diff_buttons.append(b)
	_diff_info = _label("", 13, Color(0.82, 0.85, 0.9), true)
	v.add_child(_diff_info)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	v.add_child(gap)
	var deploy := Button.new()
	deploy.text = "DEPLOY"
	deploy.custom_minimum_size = Vector2(0, 56)
	deploy.add_theme_font_size_override("font_size", 24)
	deploy.focus_mode = Control.FOCUS_NONE
	deploy.add_theme_stylebox_override("normal", _box(Color(0.72, 0.12, 0.1), Color(1.0, 0.4, 0.3), 1))
	deploy.add_theme_stylebox_override("hover", _box(Color(0.88, 0.18, 0.14), Color(1.0, 0.6, 0.4), 1))
	deploy.add_theme_stylebox_override("pressed", _box(Color(0.6, 0.1, 0.08), Color(1.0, 0.4, 0.3), 1))
	_deploy_btn = deploy
	deploy.pressed.connect(_deploy)
	v.add_child(deploy)
	_deploy_summary = _label("", 11, DIM)
	_deploy_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_deploy_summary)
	v.visible = false
	return v


func _refresh_play() -> void:
	if not is_instance_valid(_deploy_btn):
		return
	for mid in _mode_cards:
		var on: bool = mid == GameState.game_mode
		(_mode_cards[mid] as Button).add_theme_stylebox_override("normal", _box(Color(0.2, 0.08, 0.07, 0.95) if on else Color(0.07, 0.08, 0.1, 0.92), ACCENT if on else Color(1, 1, 1, 0.08), 2 if on else 1))
	for i in range(_diff_buttons.size()):
		var on: bool = i == GameState.difficulty
		_diff_buttons[i].add_theme_stylebox_override("normal", _box(Color(0.2, 0.08, 0.07, 0.95) if on else Color(0.07, 0.08, 0.1, 0.92), ACCENT if on else Color(1, 1, 1, 0.08), 2 if on else 1))
	if Net.is_online() and Net.is_host():
		_deploy_btn.text = "START CO-OP GAME  (%d PLAYERS)" % Net.players.size()
		_deploy_btn.disabled = false
	elif Net.is_online():
		_deploy_btn.text = "WAITING FOR THE HOST TO START..."
		_deploy_btn.disabled = true
	else:
		_deploy_btn.text = "DEPLOY"
		_deploy_btn.disabled = false
	_diff_info.text = "%s:   %s" % [GameState.DIFFICULTY_NAMES[GameState.difficulty], "   •   ".join(GameState.diff_lines(GameState.difficulty))]
	_deploy_summary.text = "%s  •  %s  •  %s" % [MODES[GameState.game_mode]["name"], GameState.DIFFICULTY_NAMES[GameState.difficulty], String(GameState.CHARACTERS[GameState.selected_character]["name"]).to_upper()]
	if is_instance_valid(_coop_settings):
		_coop_settings.text = "SQUAD SETTINGS (HOST'S CHOICE, SET ON THE PLAY PAGE): %s • %s • YOUR OPERATOR: %s" % [MODES[GameState.game_mode]["name"], GameState.DIFFICULTY_NAMES[GameState.difficulty], GameState.CHARACTERS[GameState.selected_character]["name"]]


func _select_character(cid: String) -> void:
	GameState.selected_character = cid
	Net.set_character(cid)
	var cd: Dictionary = GameState.CHARACTERS[cid]
	var accent: Color = cd["accent"]
	for k in _char_cards:
		var on: bool = k == cid
		var col: Color = GameState.CHARACTERS[k]["accent"]
		(_char_cards[k] as Button).add_theme_stylebox_override("normal", _box(Color(0.16, 0.1, 0.1, 0.95) if on else Color(0.07, 0.08, 0.1, 0.92), col if on else Color(1, 1, 1, 0.08), 2 if on else 1))
	_detail_code.text = cd["codename"]
	_detail_code.add_theme_color_override("font_color", accent)
	_detail_name.text = cd["name"]
	_detail_summary.text = cd["summary"]
	_detail_stats.text = "VITALITY %.0f HP   •   SPEED %.1f m/s   •   SIDEARM M1911" % [cd["max_hp"], cd["move_speed"]]
	_detail_skills.text = "\n".join(cd["skills"])
	_vitality_bar.value = clampf(float(cd["max_hp"]) / 140.0, 0.0, 1.0)
	_speed_bar.value = clampf(float(cd["move_speed"]) / 7.0, 0.0, 1.0)
	# Recolor the diorama to the operator
	if is_instance_valid(accent_light):
		accent_light.light_color = accent
	if podium_ring_mat:
		podium_ring_mat.albedo_color = accent.darkened(0.75)
	if is_instance_valid(rim_light):
		rim_light.light_color = accent.lerp(Color(0.95, 0.2, 0.15), 0.35)
	_refresh_play()


func _deploy() -> void:
	if _deploying:
		return
	_sfx("round_sting", -2.0, 1.0)
	if Net.is_online():
		if Net.is_host():
			Net.start_game(false)
		return
	GameState.reset_run()
	GameState.run_id = GameState.new_run_id()
	GameState.pending_resume = false
	GameState.late_join = false
	_fade_to_game("DEPLOYING TO NACHT-7 …")


func _continue_run(saved: Dictionary) -> void:
	if _deploying:
		return
	_sfx("round_sting", -2.0, 1.0)
	GameState.reset_run()
	GameState.run_id = int(saved.get("run_id", 0))
	GameState.difficulty = int(saved.get("difficulty", 1))
	GameState.game_mode = String(saved.get("mode", "casual"))
	GameState.pending_resume = true
	GameState.late_join = false
	_fade_to_game("RETURNING TO NACHT-7 …")


func _fade_to_game(text: String) -> void:
	_deploying = true
	_deploy_label.text = text
	_deploy_overlay.visible = true
	var tw := _deploy_overlay.create_tween()
	tw.tween_property(_deploy_overlay, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/game.tscn"))


# ---------------------------------------------------------------------------
# CAREER
# ---------------------------------------------------------------------------
func _build_career_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lvl := GameState.career_level()
	var lo := GameState.xp_for_level(lvl)
	var hi := GameState.xp_for_level(lvl + 1)
	v.add_child(_label("CAREER LEVEL %d" % lvl, 24, Color(0.97, 0.97, 0.99)))
	var bar := ProgressBar.new()
	bar.min_value = lo
	bar.max_value = hi
	bar.value = GameState.career_xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	v.add_child(bar)
	v.add_child(_label("%d / %d XP  —  every run's score turns into XP (1 per 10 points)" % [GameState.career_xp, hi], 13, Color(0.7, 0.73, 0.78)))
	_header(v, "UNLOCKS")
	for u in GameState.META_UNLOCKS:
		var got: bool = lvl >= int(u["level"])
		v.add_child(_label("%s  LEVEL %d  —  %s" % ["■" if got else "□", u["level"], u["text"]], 14, GREEN if got else Color(0.55, 0.57, 0.62)))
	_header(v, "NEMESIS")
	if GameState.nemesis.is_empty():
		v.add_child(_label("None. Die while a commander is still standing and it will remember you.", 14, Color(0.7, 0.73, 0.78), true))
	else:
		var nm: Dictionary = GameState.nemesis
		var nt := clampi(int(nm.get("tier", 3)), 3, 5)
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), ZombieEnemy.TIER_COLORS[nt], 1))
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 4)
		plate.add_child(pv)
		pv.add_child(_label("%s  %s %s" % [String(nm.get("name", "")), "★".repeat(nt), ZombieEnemy.TIER_NAMES[nt]], 18, ZombieEnemy.TIER_COLORS[nt]))
		pv.add_child(_label("Killed you %d time(s). It hunts you from round 4 of your next runs. Kill it for +2500 points and a relic." % int(nm.get("kills", 1)), 13, Color(0.7, 0.73, 0.78), true))
		v.add_child(plate)
	_header(v, "LIFETIME")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	_stat_tile(grid, str(GameState.life_runs), "RUNS", TEXT)
	_stat_tile(grid, str(GameState.life_kills), "ZOMBIES KILLED", ACCENT)
	_stat_tile(grid, str(GameState.life_bosses), "BOSSES SLAIN", AMBER)
	_stat_tile(grid, str(GameState.life_commanders), "COMMANDERS SLAIN", CYAN)
	_stat_tile(grid, str(GameState.life_nemesis_slain), "NEMESES SLAIN", GREEN)
	_stat_tile(grid, str(GameState.exfils), "EXTRACTIONS", TEXT)
	_header(v, "RECORDS")
	var rgrid := GridContainer.new()
	rgrid.columns = 3
	rgrid.add_theme_constant_override("h_separation", 8)
	rgrid.add_theme_constant_override("v_separation", 8)
	v.add_child(rgrid)
	_stat_tile(rgrid, str(GameState.best_round), "BEST ROUND · CASUAL", CYAN)
	_stat_tile(rgrid, str(GameState.best_round_infinite), "BEST ROUND · INFINITE", CYAN)
	_stat_tile(rgrid, str(GameState.best_kills), "MOST KILLS IN A RUN", ACCENT)
	v.visible = false
	return v


# ---------------------------------------------------------------------------
# INTEL
# ---------------------------------------------------------------------------
func _build_intel_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := Color(0.8, 0.82, 0.87)
	var add := func(text: String, col: Color = body, size: int = 13) -> void:
		v.add_child(_label(text, size, col, true))
	_header(v, "ZOMBIE RANKS")
	var ranks := [
		[1, "Mindless. Walks straight at you."],
		[2, "Yellow outline. Sidesteps when shot, leaps the last few metres and runs from grenades."],
		[3, "Talks. Leads from behind, gives orders (traps, flanks, bodyguards, rushes when you reload) and uses a skill stolen from an operator's brain. Zombies inside its ring fight harder."],
		[4, "Also rallies the horde, raises crawlers from the ground and eats its own zombies to heal."],
		[5, "Also summons more zombies and lets out a psychic scream. Shoot its head to interrupt the scream."],
	]
	for r in ranks:
		var t := int(r[0])
		add.call("%s %s" % ["★".repeat(t), ZombieEnemy.TIER_NAMES[t]], ZombieEnemy.TIER_COLORS[t] if t > 1 else Color(0.9, 0.9, 0.9), 15)
		add.call(String(r[1]))
	_header(v, "HOW THEY RANK UP")
	add.call("• BRAIN FEAST: when a player goes down, the nearest zombies fight over the brain. The winner goes up one rank and learns that operator's skill. Kill them before one eats it.")
	add.call("• TASTE OF BLOOD: a zombie that hits you 3 times becomes a Stalker; a Stalker that hits 6 more times becomes a Commander.")
	add.call("• From round 6 commanders also arrive on their own, later even Warlords and Overlords.")
	_header(v, "FIGHTING A COMMANDER")
	add.call("• BODYGUARDS: a glowing bubble means its guards are close and it takes far less damage. Kill the guards first.")
	add.call("• SEISMIC SLAM (orange circle): jump to dodge.   TOXIN FLASK (green pool): step out.   ARC CHARGE (blue circle): leave before it bursts.")
	add.call("• When its horde is dead it stops hiding and charges.")
	add.call("• Killing it stuns every zombie around it and can drop a relic.")
	_header(v, "NEMESIS")
	add.call("If you die while a commander is still standing, it remembers you and returns in later runs (from round 4). Kill it for +2500 points and a guaranteed relic. If it kills you again it gains a rank.")
	_header(v, "SPECIAL ROUNDS (FROM ROUND 4)")
	for k in GameState.ROUND_EVENTS:
		var ev: Dictionary = GameState.ROUND_EVENTS[k]
		add.call("%s — %s" % [ev["name"], String(ev["desc"]).to_lower().capitalize()], ev["color"])
	_header(v, "CHALLENGES, MAP AND SCOREBOARD")
	add.call("• Every round gives you one optional challenge (top-left). Finishing it pays points; every 4th one in a run gives a free stat level.")
	add.call(GameState.keyify("• The minimap shows zones, stations, your squad, relics, bosses and commanders, but not regular zombies. Press [M] for the full map, hold [TAB] for the scoreboard."))
	v.visible = false
	return v


# ---------------------------------------------------------------------------
# CO-OP LOBBY
# ---------------------------------------------------------------------------
func _coop_button(text: String, on_press: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		_sfx("buy_ching", -8.0, 1.2)
		on_press.call()
	)
	parent.add_child(b)
	return b


func _build_coop_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_label("Online play runs through Steam's relay network: no port forwarding, IPs stay private, and long-distance links take Valve's fast routes. Up to 8 survivors; zombie numbers and boss health scale with the squad. Friends can join a game already in progress.", 13, Color(0.7, 0.75, 0.82), true))
	coop_status = _label("", 15, AMBER, true)
	v.add_child(coop_status)
	_coop_settings = _label("", 12, CYAN, true)
	v.add_child(_coop_settings)
	_header(v, "STEAM")
	var steam_row := HBoxContainer.new()
	steam_row.add_theme_constant_override("separation", 8)
	v.add_child(steam_row)
	coop_host_steam = _coop_button("HOST STEAM SQUAD", func(): Net.host_steam(), steam_row)
	coop_invite = _coop_button("INVITE FRIENDS", func(): Net.invite_friends(), steam_row)
	_header(v, "DIRECT CONNECTION  (LAN / UDP PORT %d)" % Net.PORT)
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	v.add_child(ip_row)
	coop_ip = LineEdit.new()
	coop_ip.placeholder_text = "HOST IP ADDRESS"
	coop_ip.custom_minimum_size = Vector2(200, 42)
	ip_row.add_child(coop_ip)
	_coop_button("HOST", func(): Net.host_direct(), ip_row)
	_coop_button("JOIN", func(): Net.join_direct(coop_ip.text if coop_ip.text.strip_edges() != "" else "127.0.0.1"), ip_row)
	_header(v, "SQUAD")
	var roster_panel := PanelContainer.new()
	roster_panel.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06), 1))
	v.add_child(roster_panel)
	coop_roster = _label("", 15)
	coop_roster.custom_minimum_size = Vector2(0, 110)
	roster_panel.add_child(coop_roster)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	v.add_child(bottom)
	coop_start = _coop_button("START GAME", func(): Net.start_game(false), bottom)
	coop_resume = _coop_button("RESUME SAVED RUN", func(): Net.start_game(true), bottom)
	_coop_button("LEAVE", func():
		Net.leave()
		Net.status_text = ""
		_refresh_coop()
	, bottom)
	v.visible = false
	return v


func _refresh_coop() -> void:
	if coop_status == null or not is_instance_valid(coop_status):
		return
	if Net.status_text != "":
		coop_status.text = Net.status_text
	elif Net.steam_ok:
		coop_status.text = "STEAM: SIGNED IN AS %s — HOST A SQUAD, OR ACCEPT A FRIEND'S INVITE IN STEAM" % Net.my_name
	else:
		coop_status.text = "STEAM IS NOT RUNNING — START STEAM AND RESTART THE GAME FOR ONLINE PLAY (DIRECT IP STILL WORKS)"
	coop_host_steam.disabled = not Net.steam_ok
	coop_invite.disabled = not (Net.steam_ok and Net.lobby_id != 0)
	var lines: Array[String] = []
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var pinfo: Dictionary = Net.players[id]
		var cname: String = GameState.CHARACTERS.get(String(pinfo.get("char", "")), {}).get("name", "?")
		lines.append("■ %s  —  %s%s" % [pinfo.get("name", "?"), cname, "   (HOST)" if int(id) == 1 else ""])
	coop_roster.text = "\n".join(lines) if not lines.is_empty() else "NOBODY YET — HOST A SQUAD OR JOIN ONE"
	coop_start.visible = Net.mode == Net.Mode.HOST
	var sw := GameState.load_world()
	coop_resume.visible = Net.mode == Net.Mode.HOST and not sw.is_empty()
	if coop_resume.visible:
		coop_resume.text = "RESUME ROUND %d" % int(sw.get("round", 1))
	_refresh_play()