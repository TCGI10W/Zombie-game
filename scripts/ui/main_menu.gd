extends Node3D
# DEAD PROTOCOL // NACHT OUTBREAK — Professional AAA Command Menu
# Mode-reactive 3D Diorama (Horror Outpost <-> Golden-Hour Overdrive Showcase),
# armed operator centerpiece, top command bar, left callout HUD, and frosted
# right-hand Command Deck using HudIcons vector iconography.

const ZombieRigScript := preload("res://scripts/enemies/zombie_rig.gd")
const HI := preload("res://scripts/ui/hud_icons.gd")
const MPG := preload("res://scripts/ui/menu_preview_gen.gd")

const ACCENT := Color(0.95, 0.28, 0.20)
const CYAN := Color(0.38, 0.86, 1.0)
const GREEN := Color(0.42, 0.94, 0.56)
const AMBER := Color(1.0, 0.74, 0.28)
const GOLD := Color(1.0, 0.84, 0.24)
const TEXT := Color(0.92, 0.93, 0.96)
const DIM := Color(0.56, 0.60, 0.68)

const GUNSMITH_ORIGIN := Vector3(18.0, 6.0, 0.0)
const MAP_HOLO_ORIGIN := Vector3(-18.0, 6.0, 0.0)

const OPERATOR_WEAPONS := {
	"ravager": {"id": "shotgun", "icon": "shotgun", "label": "TRENCH-12 SHOTGUN", "model": "res://assets/models/vm_shotgun.glb"},
	"alchemist": {"id": "smg", "icon": "smg", "label": "KURZ-9 TAC SMG", "model": "res://assets/models/vm_smg.glb"},
	"warden": {"id": "lmg", "icon": "lmg", "label": "RAZORBACK LMG", "model": "res://assets/models/vm_lmg.glb"},
}

const MODES := {
	"casual": {
		"name": "CASUAL",
		"tag": "LIT NIGHT • 20-RD",
		"icon": "chopper",
		"desc": "Lit night outpost. Hold out to Round 20 & slay THE PROGENITOR, or evac from Round 8.",
	},
	"infinite": {
		"name": "INFINITE",
		"tag": "LIT NIGHT • ENDLESS",
		"icon": "hourglass",
		"desc": "Lit night siege. No final boss, no ceiling — escalating waves until the bunker falls.",
	},
	"horror": {
		"name": "HORROR",
		"tag": "BLACKOUT • CROWS",
		"icon": "eye",
		"desc": "Pitch-dark blackout. Sight & footstep AI, carrion crows, 6s mutations & Blood Murder.",
	},
	"overdrive": {
		"name": "OVERDRIVE",
		"tag": "ARCADE",
		"icon": "star",
		"desc": "Zero-horror solar arena: kill-chain ranks, Blitz Pods, mutators & Boss Drafts.",
	},
}

const PAGE_ORDER := ["play", "loadouts", "multiplayer", "coop", "career", "intel", "options"]
const PAGE_META := {
	"play": {"label": "PLAY", "title": "TACTICAL DEPLOYMENT", "icon": "play"},
	"loadouts": {"label": "ARMORY", "title": "ARMORY  //  40 WEAPONS & CUSTOM SETS", "icon": "rifle"},
	"multiplayer": {"label": "MULTIPLAYER", "title": "PVP MULTIPLAYER  //  UP TO 32P", "icon": "target"},
	"coop": {"label": "CO-OP", "title": "CO-OP SQUAD", "icon": "user"},
	"career": {"label": "CAREER", "title": "CAREER RECORD", "icon": "crown"},
	"intel": {"label": "INTEL", "title": "FIELD MANUAL", "icon": "compass"},
	"options": {"label": "SETTINGS", "title": "SYSTEM OPTIONS", "icon": "gauge"},
}

const TIPS := [
	"MULTIPLAYER: Fight across 4 distinct arenas — Outpost Nacht-7, Ironclad Dockyard, Sub-Zero Black Site & Sunscorch Refinery (or Random Rotation).",
	"MULTIPLAYER: Play TDM, Gun Game, Search & Destroy, or Domination with up to 32 players across 2, 4, or 6 teams.",
	"GUN GAME: Advance through 9 weapons with every kill — score a final melee kill on Tier 9 to win, or knife foes to demote them!",
	"SEARCH & DESTROY: No respawns! Hold [E] to plant or defuse at Site A or B, or eliminate all rival squads.",
	"Commanders hide behind bodyguards — kill the guards to break their damage shield.",
	"Jump over seismic slams, step out of toxin pools, and leave arc charges before they burst.",
	"Every 4th round challenge you finish grants a free stat level. Check the top-left objective.",
	"Fire Sale slashes the mystery crate price — stock up on weapons while it lasts.",
	"Extract by chopper from round 8 in CASUAL to bank the run and keep your career XP.",
	"Zombies that taste your blood rank up into stalkers and commanders. Don't let them live.",
	"Shoot an Overlord in the head to interrupt its psychic scream.",
	"Relics drop from commanders — unleash their skills with [X] and [Z].",
	"OVERDRIVE: Chain kills to unleash ★ OVERDRIVE ★ for bottomless ammo & arc-lightning bullets.",
	"OVERDRIVE: Enter golden Blitz Pods mid-round for +750 pts, +50 Shield & a free weapon mod.",
	"Shoot red fuel drums to detonate explosive blasts that stun nearby elites. Drums restock after 2 rounds.",
	"Finished shopping early? Press [N] during intermission to start the next round for +100 bonus points.",
	"HORROR: Zombies hunt by sight & sound — crouch to stay quiet, cut your flashlight to hide, and mind the darkness.",
	"HORROR: Crows devour corpses before they mutate at 6s! Kill 3 crows to trigger BLOOD MURDER — survive 20s for 4x POINTS!",
	"MOVEMENT: Double-tap [SHIFT] (or enable Auto Tac-Sprint in Settings) for Tactical Sprint, press [SPACE] near ledges to Mantle.",
	"ARMORY: Press [I] in combat to inspect your weapon finish and attachments — fire or aim at any moment to cancel instantly.",
]

# 3D Diorama nodes
var menu_cam: Camera3D
var cam_pivot: Node3D
var operator: Node3D
var operator_rig: RefCounted
var _showcase_weapon: Node3D
var _diorama_zombies: Array[Node3D] = []
var _showcase_muzzle_glow: OmniLight3D
var zombie_rigs: Array[RefCounted] = []
var diorama_env: Environment
var diorama_sky: ProceduralSkyMaterial
var accent_light: OmniLight3D
var key_light: SpotLight3D
var rim_light: SpotLight3D
var fill_light: OmniLight3D
var horde_glow: OmniLight3D
var fire_light: OmniLight3D
var lamp_light: SpotLight3D
var beacon_light: OmniLight3D
var beacon_mat: StandardMaterial3D
var podium_ring_mat: StandardMaterial3D
var podium_inner_mat: StandardMaterial3D
var lightning: DirectionalLight3D
var _embers_node: CPUParticles3D
var fog_cards: Array[MeshInstance3D] = []
var fog_speeds: Array[float] = []
var _orbit_time: float = 0.0
var _t: float = 0.0
var _parallax := Vector2.ZERO
var _lightning_t: float = 7.0
var _amb_event_t: float = 5.0
var _rng := RandomNumberGenerator.new()

# Interactive 3D Stage State (Command Bunker / Gunsmith 360° / 3D Tactical Map)
var _stage_mode: String = "command" # "command", "gunsmith", "map"
var _gunsmith_stage: Node3D
var _gunsmith_pivot: Node3D
var _gun_key_light: SpotLight3D
var _gun_rim_light: SpotLight3D
var _gun_fill_light: OmniLight3D
var _gun_yaw: float = 1.38
var _gun_pitch: float = 0.14
var _gun_zoom: float = 1.0
var _gun_auto_spin: bool = true
var _map_holo_stage: Node3D
var _map_holo_pivot: Node3D
var _map_key_light: SpotLight3D
var _map_fill_light: OmniLight3D
var _map_yaw: float = 0.42
var _map_pitch: float = -0.68
var _map_zoom: float = 1.0
var _map_auto_spin: bool = true
var _mp_stage_show_operator: bool = false
var _cmd_op_yaw: float = 0.0
var _stage_dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _cam_pos_cur: Vector3 = Vector3(0.45, 1.92, 6.8)
var _cam_target_cur: Vector3 = Vector3(1.15, 1.15, 0.0)
var _cam_fov_cur: float = 50.0
var _cam_preset: int = 0 # 0=WIDE, 1=CLOSE-UP, 2=CINEMATIC
var _cam_preset_btns: Array[Button] = []
var _directives_card: PanelContainer
var _directives_box: VBoxContainer
var _gunsmith_last_sig: String = ""
var _map_holo_last_sig: String = ""

# UI state
var _root: Control
var _pages: Dictionary = {}
var _nav: Dictionary = {}
var _nav_order: Array[String] = []
var _nav_index: int = 0
var _current_page: String = ""
var _stack: VBoxContainer
var _play_scroll: ScrollContainer
var _content_title: Label
var _page_index: Label
var _panel: PanelContainer
var _header_bar: PanelContainer
var _header_stripe: ColorRect
var _header_icon: TextureRect
var _net_pill_dot: ColorRect
var _net_pill_lbl: Label
var _sound_btn: Button
var _tip_icon: TextureRect
var _tip_label: Label
var _tip_index: int = 0
var _tip_t: float = 0.0
var _tip_tween: Tween
var _deploying: bool = false
var _deploy_overlay: ColorRect
var _deploy_label: Label

# Left Showcase floating callouts & context-sensitive 3D stage HUD
var _left_hud: VBoxContainer
var _stage_drag_zone: Control
var _gunsmith_overlay: Control
var _op_plate: PanelContainer
var _op_plate_stripe: ColorRect
var _op_plate_role: Label
var _op_plate_name: Label
var _op_plate_weapon_icon: TextureRect
var _op_plate_weapon_lbl: Label
var _continue_card: PanelContainer
var _nemesis_card: PanelContainer
var _nemesis_plate: Label
var _stage_top_card: PanelContainer
var _stage_top_kicker: Label
var _stage_top_title: Label
var _stage_top_sub: Label
var _stage_bar_card: PanelContainer
var _stage_btn_a: Button
var _stage_btn_b: Button
var _stage_spin_btn: Button
var _stage_hint_lbl: Label

# Play Page controls
var _char_cards: Dictionary = {}
var _mode_cards: Dictionary = {}
var _diff_buttons: Array[Button] = []
var _diff_grid: GridContainer
var _diff_grid_mode: String = ""
var _score_mult_pill: Label
var _diff_chips_box: HBoxContainer
var _diff_info: Label
var _play_footer: VBoxContainer
var _deploy_btn: Button
var _deploy_summary: Label
var _detail_name: Label
var _detail_code: Label
var _detail_summary: Label
var _detail_stats_hp: Label
var _detail_stats_spd: Label
var _skill_rows_box: VBoxContainer
var _vitality_bar: ProgressBar
var _speed_bar: ProgressBar
var _coop_settings: Label
var _play_custom_chk: Button
var _play_set_btns: Array[Button] = []
var _play_armory_lbl: Label

# Armory / Custom Loadouts page
var _armory_set_btns: Array[Button] = []
var _armory_name_edit: LineEdit
var _armory_slot: String = "primary"
var _armory_subtab: String = "weapons" # "weapons", "gunsmith", "equipment"
var _armory_subtab_btns: Dictionary = {}
var _armory_subtab_panels: Dictionary = {}
var _armory_cat_filter: String = "all"
var _armory_pri_card: PanelContainer
var _armory_pri_lbl: Label
var _armory_pri_sub: Label
var _armory_pri_sil: TextureRect
var _armory_sec_card: PanelContainer
var _armory_sec_lbl: Label
var _armory_sec_sub: Label
var _armory_sec_sil: TextureRect
var _armory_att_head: Label
var _armory_att_btns: Dictionary = {}
var _armory_att_hover: String = ""
var _armory_camo_btns: Dictionary = {}
var _armory_let_btns: Dictionary = {}
var _armory_tac_btns: Dictionary = {}
var _armory_perk_btns: Dictionary = {}
var _armory_cat_row: HBoxContainer
var _armory_cat_btns: Dictionary = {}
var _armory_grid: GridContainer
var _armory_desc_lbl: Label
var _armory_stat_bars: Dictionary = {}
var _armory_stat_vals: Dictionary = {}
var _armory_preview_lbl: Label
var _armory_fire_mode_lbl: Label

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
	var idx: int = _nav_order.find(_current_page)
	if idx >= 0:
		_nav_index = idx
	_update_nav_styles()


# ---------------------------------------------------------------------------
# FRAME UPDATES
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	_orbit_time += delta * 0.22
	var is_od: bool = GameState.is_overdrive()

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var m: Vector2 = get_viewport().get_mouse_position()
	if vp.x > 0.0 and vp.y > 0.0:
		var target := Vector2.ZERO if m.length_squared() < 2.0 else Vector2(clampf((m.x / vp.x - 0.5) * 2.0, -1.0, 1.0), clampf((m.y / vp.y - 0.5) * 2.0, -1.0, 1.0))
		_parallax = _parallax.lerp(target, minf(delta * 3.0, 1.0))

	var goal_pos: Vector3
	var goal_target: Vector3
	var goal_fov: float = 50.0
	if _stage_mode == "gunsmith":
		if is_instance_valid(cam_pivot):
			cam_pivot.rotation.y = lerpf(cam_pivot.rotation.y, 0.0, minf(delta * 7.0, 1.0))
		if _gun_auto_spin and not _stage_dragging:
			_gun_yaw += delta * 0.34
		if is_instance_valid(_gunsmith_pivot):
			_gunsmith_pivot.rotation.x = lerpf(_gunsmith_pivot.rotation.x, _gun_pitch, minf(delta * 10.0, 1.0))
			_gunsmith_pivot.rotation.y = lerpf(_gunsmith_pivot.rotation.y, _gun_yaw, minf(delta * 10.0, 1.0))
		goal_target = GUNSMITH_ORIGIN + Vector3(0.32 + _parallax.x * 0.02, 0.01 - _parallax.y * 0.015, 0.0)
		goal_pos = GUNSMITH_ORIGIN + Vector3(0.32, 0.14, 1.94 * _gun_zoom)
		goal_fov = 38.0
		if is_instance_valid(_gunsmith_overlay):
			_gunsmith_overlay.queue_redraw()
	elif _stage_mode == "map":
		if is_instance_valid(cam_pivot):
			cam_pivot.rotation.y = lerpf(cam_pivot.rotation.y, 0.0, minf(delta * 7.0, 1.0))
		if _map_auto_spin and not _stage_dragging:
			_map_yaw += delta * 0.20
		if is_instance_valid(_map_holo_pivot):
			_map_holo_pivot.rotation.x = lerpf(_map_holo_pivot.rotation.x, _map_pitch, minf(delta * 10.0, 1.0))
			_map_holo_pivot.rotation.y = lerpf(_map_holo_pivot.rotation.y, _map_yaw, minf(delta * 10.0, 1.0))
		goal_target = MAP_HOLO_ORIGIN + Vector3(0.68 + _parallax.x * 0.04, 0.06 - _parallax.y * 0.03, 0.0)
		goal_pos = MAP_HOLO_ORIGIN + Vector3(0.68, 3.00 * _map_zoom, 4.35 * _map_zoom)
		goal_fov = 42.0
	else:
		if is_instance_valid(cam_pivot):
			cam_pivot.rotation.y = lerpf(cam_pivot.rotation.y, sin(_orbit_time) * (0.14 if _cam_preset == 2 else 0.08), minf(delta * 5.0, 1.0))
		if _cam_preset == 1:
			goal_pos = Vector3(0.28, 1.62, 2.75)
			goal_target = Vector3(0.25 + _parallax.x * 0.14, 1.38 - _parallax.y * 0.10, 0.25)
			goal_fov = 44.0
		elif _cam_preset == 2:
			var ca: float = sin(_orbit_time * 0.85) * 0.38
			goal_pos = Vector3(-0.32 + sin(ca) * 3.8, 1.28, 0.30 + cos(ca) * 4.4)
			goal_target = Vector3(0.75 + _parallax.x * 0.22, 1.18 - _parallax.y * 0.14, 0.20)
			goal_fov = 47.0
		else:
			goal_pos = Vector3(0.45, 1.96, 7.1)
			goal_target = Vector3(1.15 + _parallax.x * 0.45, 1.15 - _parallax.y * 0.28, 0.0)
			goal_fov = 51.0

	var cam_lerp: float = minf(delta * 7.5, 1.0)
	_cam_pos_cur = _cam_pos_cur.lerp(goal_pos, cam_lerp)
	_cam_target_cur = _cam_target_cur.lerp(goal_target, cam_lerp)
	_cam_fov_cur = lerpf(_cam_fov_cur, goal_fov, cam_lerp)
	if is_instance_valid(menu_cam):
		menu_cam.position = _cam_pos_cur
		menu_cam.fov = _cam_fov_cur
		menu_cam.look_at(_cam_target_cur, Vector3.UP)

	if is_instance_valid(operator):
		operator.rotation.y = PI - 0.14 + _cmd_op_yaw + sin(_t * 0.45) * 0.04

	if is_instance_valid(fire_light):
		fire_light.light_energy = (1.1 if is_od else 2.4) + sin(_t * 11.0) * 0.25 + sin(_t * 23.7) * 0.18
	if is_instance_valid(lamp_light):
		if is_od:
			lamp_light.light_energy = 1.6
		else:
			var brown: bool = fmod(_t, 9.0) > 8.55
			lamp_light.light_energy = 0.0 if brown else 1.25 + sin(_t * 13.0) * 0.14 + _rng.randf_range(-0.08, 0.08)
	if is_instance_valid(beacon_light):
		var on: bool = true if is_od else (sin(_t * 2.2) > 0.55)
		beacon_light.light_energy = 1.4 if is_od else (2.6 if on else 0.0)
		if beacon_mat:
			beacon_mat.emission_energy_multiplier = 2.0 if is_od else (3.2 if on else 0.15)

	for i in range(fog_cards.size()):
		var c: MeshInstance3D = fog_cards[i]
		if is_instance_valid(c):
			c.visible = not is_od
			if not is_od:
				c.position.x += fog_speeds[i] * delta
				if c.position.x > 16.0:
					c.position.x = -16.0

	if not is_od:
		_lightning_t -= delta
		if _lightning_t <= 0.0:
			_lightning_t = _rng.randf_range(9.0, 18.0)
			_flash_lightning()
		_amb_event_t -= delta
		if _amb_event_t <= 0.0:
			_amb_event_t = _rng.randf_range(7.0, 15.0)
			var picks := ["crow", "bell_far", "scream_far", "train_horn", "creak", "whisper_eerie", "metal_scrape"]
			_sfx(picks[_rng.randi_range(0, picks.size() - 1)], _rng.randf_range(-19.0, -14.0), _rng.randf_range(0.9, 1.1))

	if is_instance_valid(_nemesis_card) and _nemesis_card.visible:
		_nemesis_card.modulate.a = 0.80 + 0.20 * sin(_t * 3.0)

	_tip_t += delta
	if _tip_t >= 9.0:
		_tip_t = 0.0
		_rotate_tip()


func _physics_process(delta: float) -> void:
	if operator_rig:
		var look_tgt := Vector3(-_parallax.x * 0.65, 1.58 - _parallax.y * 0.18, -3.5)
		operator_rig.update(delta, "idle", 0.0, {"look_local": look_tgt})
		_pose_operator_arms()
	for r in zombie_rigs:
		r.update(delta, "idle", 0.0)


func _pose_operator_arms() -> void:
	if operator_rig == null:
		return
	var n: Dictionary = operator_rig.nodes
	for j in ["UpperArmR", "ForearmR", "HandR", "UpperArmL", "ForearmL", "HandL"]:
		if n.has(j):
			(n[j] as Node3D).rotation = Vector3.ZERO


func _flash_lightning() -> void:
	if not is_instance_valid(lightning) or GameState.is_overdrive():
		return
	lightning.light_energy = 2.6
	var tw := lightning.create_tween()
	tw.tween_property(lightning, "light_energy", 0.0, 0.14)
	tw.tween_callback(func():
		if is_instance_valid(lightning) and not GameState.is_overdrive():
			lightning.light_energy = 1.5).set_delay(0.16)
	tw.tween_property(lightning, "light_energy", 0.0, 0.4)
	get_tree().create_timer(1.15).timeout.connect(func():
		if is_instance_valid(self) and not GameState.is_overdrive():
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
		else:
			focused.release_focus()
		return
	if focused != null:
		return
	match kc:
		KEY_R:
			_reset_stage_view()
			_sfx("hit_tick", -14.0, 1.2)
		KEY_Q, KEY_LEFT:
			_nav_move(-1)
		KEY_E, KEY_RIGHT:
			_nav_move(1)
		KEY_ENTER, KEY_KP_ENTER:
			if (_current_page == "play" or _current_page == "multiplayer") and not _deploying:
				_deploy()
			else:
				_activate_nav()
		_:
			if kc >= KEY_1 and kc <= KEY_7:
				var idx: int = kc - KEY_1
				if idx < _nav_order.size():
					_nav_index = idx
					_update_nav_styles()
					_activate_nav()


func _reset_stage_view() -> void:
	if _stage_mode == "gunsmith":
		_gun_yaw = 1.42
		_gun_pitch = 0.12
		_gun_zoom = 1.0
	elif _stage_mode == "map":
		_map_yaw = 0.42
		_map_pitch = 0.0
		_map_zoom = 1.0
	else:
		_cmd_op_yaw = 0.0


func _on_stage_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_stage_dragging = mb.pressed
			_drag_last = mb.position
			if mb.double_click:
				_reset_stage_view()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _stage_mode == "gunsmith":
				_gun_zoom = clampf(_gun_zoom - 0.09, 0.62, 1.65)
			elif _stage_mode == "map":
				_map_zoom = clampf(_map_zoom - 0.08, 0.68, 1.45)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _stage_mode == "gunsmith":
				_gun_zoom = clampf(_gun_zoom + 0.09, 0.62, 1.65)
			elif _stage_mode == "map":
				_map_zoom = clampf(_map_zoom + 0.08, 0.68, 1.45)
	elif event is InputEventMouseMotion and _stage_dragging:
		var mm := event as InputEventMouseMotion
		var d: Vector2 = mm.position - _drag_last
		_drag_last = mm.position
		if _stage_mode == "gunsmith":
			_gun_yaw += d.x * 0.011
			_gun_pitch = clampf(_gun_pitch + d.y * 0.0085, -0.78, 0.78)
		elif _stage_mode == "map":
			_map_yaw += d.x * 0.010
			_map_pitch = clampf(_map_pitch + d.y * 0.007, -0.38, 0.44)
		else:
			_cmd_op_yaw += d.x * 0.010


func _draw_gunsmith_callouts() -> void:
	if _stage_mode != "gunsmith" or not is_instance_valid(_gunsmith_overlay):
		return
	if not is_instance_valid(menu_cam) or not is_instance_valid(_gunsmith_pivot):
		return
	if _gunsmith_pivot.get_child_count() == 0:
		return
	var weapon_root: Node = _gunsmith_pivot.get_child(0)
	var decor: Node = weapon_root.find_child("CustomDecor", true, false)
	if decor == null:
		return
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var slot_accent: Color = CYAN if _armory_slot == "primary" else AMBER
	var max_x: float = _gunsmith_overlay.size.x - 16.0
	var used_ys: Array[float] = []
	for child in decor.get_children():
		if not (child is Node3D) or not String(child.name).begins_with("Socket_"):
			continue
		var s3 := child as Node3D
		if not s3.visible or not s3.has_meta("label"):
			continue
		var lbl_txt := String(s3.get_meta("label", "")).to_upper()
		if lbl_txt == "":
			continue
		var wp: Vector3 = s3.global_position
		if menu_cam.is_position_behind(wp):
			continue
		var sp: Vector2 = menu_cam.unproject_position(wp)
		if sp.x < 16.0 or sp.x > max_x - 30.0 or sp.y < 76.0 or sp.y > _gunsmith_overlay.size.y - 100.0:
			continue
		var is_upper: bool = sp.y < _gunsmith_overlay.size.y * 0.45
		var ly: float = sp.y + (-58.0 if is_upper else 58.0)
		for py in used_ys:
			if absf(ly - py) < 26.0:
				ly += (-28.0 if is_upper else 28.0)
		ly = clampf(ly, 128.0, _gunsmith_overlay.size.y - 140.0)
		used_ys.append(ly)
		var tw: float = font.get_string_size(lbl_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var pill_w: float = tw + 14.0
		var go_left: bool = sp.x > _gunsmith_overlay.size.x * 0.60
		var lx: float = clampf(sp.x + (-pill_w - 22.0 if go_left else 22.0), 18.0, max_x - pill_w - 8.0)
		var connect_x: float = lx + pill_w if go_left else lx
		var elbow := Vector2(connect_x + (10.0 if go_left else -10.0), ly + 10.0)
		_gunsmith_overlay.draw_circle(sp, 3.5, slot_accent)
		_gunsmith_overlay.draw_circle(sp, 5.5, Color(slot_accent.r, slot_accent.g, slot_accent.b, 0.35))
		_gunsmith_overlay.draw_polyline(PackedVector2Array([sp, elbow, Vector2(connect_x, ly + 10.0)]), Color(slot_accent.r, slot_accent.g, slot_accent.b, 0.85), 1.4, true)
		var pill := Rect2(lx, ly, pill_w, 20.0)
		_gunsmith_overlay.draw_rect(pill, Color(0.025, 0.032, 0.048, 0.90), true)
		_gunsmith_overlay.draw_rect(pill, Color(slot_accent.r, slot_accent.g, slot_accent.b, 0.78), false, 1.2)
		_gunsmith_overlay.draw_string(font, Vector2(lx + 7.0, ly + 14.0), lbl_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.97, 1.0))


func _nav_move(dir: int) -> void:
	if _nav_order.is_empty():
		return
	_nav_index = wrapi(_nav_index + dir, 0, _nav_order.size())
	_update_nav_styles()
	_activate_nav()
	_sfx("hit_tick", -16.0, 1.2)


func _activate_nav() -> void:
	if _nav_order.is_empty():
		return
	var k: String = _nav_order[_nav_index]
	_show_page(k)


func _update_nav_styles() -> void:
	var mode_col: Color = GOLD if GameState.is_overdrive() else ACCENT
	for i in range(_nav_order.size()):
		var k: String = _nav_order[i]
		var b: Button = _nav[k]
		if not is_instance_valid(b):
			continue
		var selected: bool = k == _current_page
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(mode_col.r, mode_col.g, mode_col.b, 0.14) if selected else Color(1, 1, 1, 0.02)
		sb.border_color = mode_col if selected else Color(1, 1, 1, 0.08)
		sb.border_width_bottom = 3 if selected else 1
		sb.border_width_top = 0
		sb.border_width_left = 0
		sb.border_width_right = 0
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", Color.WHITE if selected else DIM)


# ---------------------------------------------------------------------------
# 3D DIORAMA
# ---------------------------------------------------------------------------
func _build_diorama() -> void:
	var world_env := WorldEnvironment.new()
	diorama_env = Environment.new()
	diorama_sky = ProceduralSkyMaterial.new()
	diorama_sky.sky_top_color = Color(0.01, 0.014, 0.022)
	diorama_sky.sky_horizon_color = Color(0.025, 0.032, 0.044)
	diorama_sky.ground_bottom_color = Color(0.004, 0.005, 0.008)
	diorama_sky.ground_horizon_color = Color(0.018, 0.022, 0.030)
	var sky := Sky.new()
	sky.sky_material = diorama_sky
	diorama_env.background_mode = Environment.BG_SKY
	diorama_env.sky = sky
	diorama_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	diorama_env.ambient_light_color = Color(0.06, 0.07, 0.09)
	diorama_env.ambient_light_energy = 0.14
	diorama_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	diorama_env.tonemap_exposure = 1.0
	diorama_env.fog_enabled = true
	diorama_env.fog_density = 0.038
	diorama_env.fog_light_color = Color(0.02, 0.026, 0.036)
	diorama_env.fog_light_energy = 0.35
	diorama_env.glow_enabled = true
	diorama_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	diorama_env.glow_intensity = 0.48
	diorama_env.glow_bloom = 0.08
	if GameState.graphics_quality >= 1:
		diorama_env.volumetric_fog_enabled = true
		diorama_env.volumetric_fog_density = 0.030
		diorama_env.volumetric_fog_length = 38.0
	world_env.environment = diorama_env
	add_child(world_env)

	# Wet asphalt clearing
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(96, 96)
	ground.mesh = plane
	ground.material_override = MaterialLib.get_world("asphalt", 0.22, Color(0.52, 0.56, 0.64), 0.0, 0.88, 0.55, 0.5, true)
	add_child(ground)

	# Sleek Two-Tier Octagonal Metallic Podium + Dual Glow Rings
	var podium := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.46
	cyl.bottom_radius = 1.72
	cyl.height = 0.20
	cyl.radial_segments = 8
	podium.mesh = cyl
	podium.position = Vector3(-0.32, 0.10, 0.30)
	podium.material_override = MaterialLib.get_world("gunmetal", 0.34, Color(0.18, 0.20, 0.24), 0.72, 0.85, 0.15, 0.35)
	add_child(podium)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.46
	torus.outer_radius = 1.60
	torus.rings = 48
	torus.ring_segments = 12
	ring.mesh = torus
	ring.position = Vector3(-0.32, 0.205, 0.30)
	podium_ring_mat = StandardMaterial3D.new()
	podium_ring_mat.albedo_color = Color(0.08, 0.08, 0.09)
	podium_ring_mat.roughness = 0.35
	podium_ring_mat.metallic = 0.65
	podium_ring_mat.emission_enabled = true
	podium_ring_mat.emission = ACCENT
	podium_ring_mat.emission_energy_multiplier = 0.9
	ring.material_override = podium_ring_mat
	add_child(ring)

	var ring2 := MeshInstance3D.new()
	var torus2 := TorusMesh.new()
	torus2.inner_radius = 1.24
	torus2.outer_radius = 1.30
	torus2.rings = 48
	torus2.ring_segments = 8
	ring2.mesh = torus2
	ring2.position = Vector3(-0.32, 0.21, 0.30)
	podium_inner_mat = StandardMaterial3D.new()
	podium_inner_mat.albedo_color = Color(0.12, 0.12, 0.14)
	podium_inner_mat.emission_enabled = true
	podium_inner_mat.emission = CYAN
	podium_inner_mat.emission_energy_multiplier = 0.4
	ring2.material_override = podium_inner_mat
	add_child(ring2)

	# Fortified Command Bunker Backdrop Walls + Steel Buttresses (closes bare horizon)
	var wall_mat := MaterialLib.get_world("concrete", 0.72, Color(0.24, 0.26, 0.30), 0.12, 0.9, 0.18, 0.45)
	var steel_mat := MaterialLib.get_world("panzer_steel", 0.38, Color(0.20, 0.23, 0.28), 0.75, 0.8, 0.2, 0.4)
	for bspec in [
		[Vector3(-6.2, 1.9, -9.8), Vector3(7.4, 3.8, 0.9), 0.18, wall_mat],
		[Vector3(1.6, 2.2, -10.8), Vector3(8.6, 4.4, 0.9), -0.06, wall_mat],
		[Vector3(-9.8, 1.7, -5.8), Vector3(0.9, 3.4, 7.6), 0.12, wall_mat],
		[Vector3(-4.0, 2.1, -9.2), Vector3(0.55, 4.2, 0.95), 0.14, steel_mat],
		[Vector3(0.2, 2.2, -10.2), Vector3(0.55, 4.4, 0.95), -0.04, steel_mat],
		[Vector3(4.5, 2.1, -9.9), Vector3(0.55, 4.2, 0.95), -0.14, steel_mat],
	]:
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bspec[1]
		wall.mesh = bm
		wall.position = bspec[0]
		wall.rotation.y = bspec[2]
		wall.material_override = bspec[3]
		add_child(wall)

	# Operator Hero Showcase
	operator = (load("res://assets/models/player_survivor.glb") as PackedScene).instantiate() as Node3D
	operator.position = Vector3(-0.32, 0.18, 0.30)
	operator.rotation.y = PI - 0.14
	add_child(operator)
	operator_rig = ZombieRigScript.new()
	var proxies := SkinRigAdapter.attach(operator)
	if operator_rig.bind(proxies if proxies else operator):
		operator_rig.limp = 0.0
		operator_rig.hunch = 0.0
		operator_rig.arm_style = 2
		operator_rig.sway = 0.25
	accent_light = OmniLight3D.new()
	accent_light.light_color = ACCENT
	accent_light.light_energy = 0.55
	accent_light.omni_range = 4.5
	accent_light.position = Vector3(0.0, 1.35, 0.55)
	operator.add_child(accent_light)

	# Looming Horde Silhouette Backdrop (including custom Boss + V2 Infected)
	var zdata := [
		["zombie_soldier_v2", Vector3(-2.7, 0.0, -3.5), 2.85, 0.15, 0.25, 0, 0.7, 1.0],
		["zombie_bloater", Vector3(1.5, 0.0, -4.6), 3.35, 0.25, 0.30, 1, 0.8, 1.0],
		["zombie_runner_v2", Vector3(-0.7, 0.0, -5.8), 3.05, 0.0, 0.15, 0, 0.55, 1.0],
		["boss_gorilla", Vector3(-3.6, 0.0, -8.2), 2.95, 0.1, 0.2, 2, 0.45, 1.15],
	]
	for zd in zdata:
		var mpath := "res://assets/models/%s.glb" % String(zd[0])
		if not ResourceLoader.exists(mpath):
			continue
		var z := (load(mpath) as PackedScene).instantiate() as Node3D
		z.position = zd[1]
		z.rotation.y = zd[2]
		z.scale = Vector3.ONE * float(zd[7])
		add_child(z)
		_diorama_zombies.append(z)
		var zr := ZombieRigScript.new()
		var zp := SkinRigAdapter.attach(z)
		if zr.bind(zp if zp else z):
			zr.limp = zd[3]
			zr.hunch = zd[4]
			zr.arm_style = zd[5]
			zr.sway = zd[6]
			zr.twitch_amt = 0.55
			zombie_rigs.append(zr)
			var head_node: Node3D = (zr.nodes.get("Head") as Node3D) if zr.nodes.has("Head") else z.find_child("Head", true, false) as Node3D
			if head_node:
				var eye_mat := MaterialLib.get_emissive(Color(0.95, 0.72, 0.26), 1.1)
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

	# Outpost set dressing (tight grounded perimeter)
	_prop("barrel", Vector3(-2.9, 0, 2.0), 0.3)
	_prop("barrel", Vector3(3.1, 0, -1.3), 1.1)
	_prop("mystery_crate", Vector3(2.2, 0, 1.0), 0.42, 0.95)
	_prop("sandbags", Vector3(-2.1, 0, -1.6), 0.3)
	_prop("sandbags", Vector3(1.6, 0, -2.3), -0.5)
	_prop("tire_stack", Vector3(-3.8, 0, -0.6), 0.8)
	_prop("car_wreck", Vector3(4.6, 0, -3.8), 0.7)
	_prop("rubble", Vector3(0.7, 0, -2.9), 0.2)
	_prop("barbed_wire", Vector3(0.2, 0, -7.2), 0.15, 1.3)
	_prop("lamp_post", Vector3(3.4, 0, -2.6), 0.0)
	_prop("radio_tower", Vector3(1.8, 0, -12.6), 0.0, 1.6)

	# Fire barrel glow + embers
	var coal := MeshInstance3D.new()
	var coal_mesh := SphereMesh.new()
	coal_mesh.radius = 0.18
	coal_mesh.height = 0.2
	coal.mesh = coal_mesh
	coal.position = Vector3(-2.9, 0.95, 2.0)
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
	fire_light.light_energy = 2.4
	fire_light.omni_range = 6.5
	fire_light.position = Vector3(-2.9, 1.15, 2.0)
	add_child(fire_light)
	_embers_node = _embers(Vector3(-2.9, 1.0, 2.0), 22)
	_dust()

	# Showcase Lights
	key_light = SpotLight3D.new()
	key_light.light_color = Color(0.94, 0.88, 0.78)
	key_light.light_energy = 4.8
	key_light.spot_range = 18.0
	key_light.spot_angle = 32.0
	key_light.shadow_enabled = GameState.graphics_quality >= 1
	key_light.look_at_from_position(Vector3(1.6, 5.4, 3.8), Vector3(-0.3, 1.1, 0.3), Vector3.UP)
	add_child(key_light)

	rim_light = SpotLight3D.new()
	rim_light.light_color = Color(0.95, 0.25, 0.18)
	rim_light.light_energy = 1.65
	rim_light.spot_range = 14.0
	rim_light.spot_angle = 50.0
	rim_light.look_at_from_position(Vector3(-2.8, 3.4, -3.4), Vector3(-0.3, 1.2, 0.3), Vector3.UP)
	add_child(rim_light)

	fill_light = OmniLight3D.new()
	fill_light.light_color = Color(0.42, 0.72, 1.0)
	fill_light.light_energy = 0.28
	fill_light.omni_range = 12.0
	fill_light.position = Vector3(2.2, 1.8, 4.5)
	add_child(fill_light)

	horde_glow = OmniLight3D.new()
	horde_glow.light_color = Color(0.92, 0.16, 0.10)
	horde_glow.light_energy = 0.55
	horde_glow.omni_range = 9.0
	horde_glow.position = Vector3(-1.2, 2.0, -7.2)
	add_child(horde_glow)

	lamp_light = SpotLight3D.new()
	lamp_light.light_color = Color(0.7, 0.85, 1.0)
	lamp_light.light_energy = 1.2
	lamp_light.spot_range = 10.0
	lamp_light.spot_angle = 40.0
	lamp_light.look_at_from_position(Vector3(3.4, 4.2, -2.6), Vector3(2.6, 0, -1.8), Vector3.UP)
	add_child(lamp_light)

	# Radio tower beacon
	var beacon := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.12
	bs.height = 0.24
	beacon.mesh = bs
	beacon.position = Vector3(1.8, 8.4, -13.0)
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
	beacon_light.position = Vector3(1.8, 8.4, -13.0)
	add_child(beacon_light)

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

	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	menu_cam = Camera3D.new()
	_cam_pos_cur = Vector3(0.45, 1.96, 7.1)
	_cam_target_cur = Vector3(1.15, 1.15, 0.0)
	_cam_fov_cur = 51.0
	menu_cam.position = _cam_pos_cur
	menu_cam.fov = _cam_fov_cur
	menu_cam.current = true
	cam_pivot.add_child(menu_cam)
	menu_cam.look_at(_cam_target_cur, Vector3.UP)

	_build_gunsmith_stage()
	_build_map_holo_stage()


func _build_gunsmith_stage() -> void:
	_gunsmith_stage = Node3D.new()
	_gunsmith_stage.position = GUNSMITH_ORIGIN
	_gunsmith_stage.visible = false
	add_child(_gunsmith_stage)

	# Matte studio cyclorama backplate so weapon silhouettes & camos pop cleanly
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(5.6, 3.2, 0.12)
	back.mesh = bm
	back.position = Vector3(0.2, 0.0, -1.25)
	var matte_back := StandardMaterial3D.new()
	matte_back.albedo_color = Color(0.028, 0.036, 0.052)
	matte_back.roughness = 0.94
	matte_back.metallic = 0.05
	back.material_override = matte_back
	_gunsmith_stage.add_child(back)

	# Studio calibration grid ring beneath weapon
	var floor_disc := MeshInstance3D.new()
	var fcm := CylinderMesh.new()
	fcm.top_radius = 0.78
	fcm.bottom_radius = 0.84
	fcm.height = 0.04
	fcm.radial_segments = 32
	floor_disc.mesh = fcm
	floor_disc.position = Vector3(-0.22, -0.36, 0.0)
	floor_disc.material_override = MaterialLib.get_world("gunmetal", 0.40, Color(0.10, 0.12, 0.16), 0.75, 0.85, 0.1, 0.25)
	_gunsmith_stage.add_child(floor_disc)

	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.72
	tor.outer_radius = 0.755
	tor.rings = 48
	tor.ring_segments = 8
	ring.mesh = tor
	ring.position = Vector3(-0.22, -0.338, 0.0)
	ring.material_override = MaterialLib.get_emissive(CYAN, 1.35)
	_gunsmith_stage.add_child(ring)

	_gunsmith_pivot = Node3D.new()
	_gunsmith_pivot.position = Vector3(-0.22, 0.02, 0.0)
	_gunsmith_stage.add_child(_gunsmith_pivot)

	_gun_key_light = SpotLight3D.new()
	_gun_key_light.light_color = Color(0.98, 0.97, 1.0)
	_gun_key_light.light_energy = 6.2
	_gun_key_light.spot_range = 6.0
	_gun_key_light.spot_angle = 48.0
	_gun_key_light.look_at_from_position(Vector3(0.45, 1.15, 1.45), Vector3(-0.22, 0.0, 0.0), Vector3.UP)
	_gunsmith_stage.add_child(_gun_key_light)

	_gun_rim_light = SpotLight3D.new()
	_gun_rim_light.light_color = Color(0.38, 0.86, 1.0)
	_gun_rim_light.light_energy = 4.2
	_gun_rim_light.spot_range = 5.0
	_gun_rim_light.spot_angle = 52.0
	_gun_rim_light.look_at_from_position(Vector3(-0.95, 0.85, -0.95), Vector3(-0.22, 0.0, 0.0), Vector3.UP)
	_gunsmith_stage.add_child(_gun_rim_light)

	_gun_fill_light = OmniLight3D.new()
	_gun_fill_light.light_color = Color(0.95, 0.76, 0.56)
	_gun_fill_light.light_energy = 1.45
	_gun_fill_light.omni_range = 4.5
	_gun_fill_light.position = Vector3(-0.95, -0.25, 1.10)
	_gunsmith_stage.add_child(_gun_fill_light)


func _build_map_holo_stage() -> void:
	_map_holo_stage = Node3D.new()
	_map_holo_stage.position = MAP_HOLO_ORIGIN
	_map_holo_stage.visible = false
	add_child(_map_holo_stage)

	var war_floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12.0, 10.0)
	war_floor.mesh = pm
	war_floor.position = Vector3(0.0, -0.22, 0.0)
	war_floor.material_override = MaterialLib.get_world("asphalt", 0.58, Color(0.10, 0.13, 0.18), 0.15, 0.9, 0.2, 0.4)
	_map_holo_stage.add_child(war_floor)

	_map_holo_pivot = Node3D.new()
	_map_holo_pivot.position = Vector3(-0.92, 0.0, 0.0)
	_map_holo_stage.add_child(_map_holo_pivot)

	_map_key_light = SpotLight3D.new()
	_map_key_light.light_color = Color(0.95, 0.98, 1.0)
	_map_key_light.light_energy = 7.5
	_map_key_light.spot_range = 10.0
	_map_key_light.spot_angle = 55.0
	_map_key_light.look_at_from_position(Vector3(0.55, 4.10, 2.20), Vector3(-0.92, 0.0, 0.0), Vector3.UP)
	_map_holo_stage.add_child(_map_key_light)

	_map_fill_light = OmniLight3D.new()
	_map_fill_light.light_color = Color(0.42, 0.80, 1.0)
	_map_fill_light.light_energy = 1.65
	_map_fill_light.omni_range = 7.5
	_map_fill_light.position = Vector3(-1.85, 2.20, 1.90)
	_map_holo_stage.add_child(_map_fill_light)


func _rebuild_gunsmith_weapon(w_id: String, atts: Array, camo_id: String) -> void:
	if not is_instance_valid(_gunsmith_pivot):
		return
	var sig := "%s|%s|%s" % [w_id, camo_id, ",".join(atts)]
	if sig == _gunsmith_last_sig and _gunsmith_pivot.get_child_count() > 0:
		return
	_gunsmith_last_sig = sig
	for c in _gunsmith_pivot.get_children():
		_gunsmith_pivot.remove_child(c)
		c.queue_free()
	var gun_node := WeaponRigBuilder.build_gunsmith_weapon(w_id, atts, camo_id)
	if gun_node == null:
		return
	var span: float = maxf(0.28, float(gun_node.get_meta("span", 0.72)))
	var target_span: float = 0.70 if span >= 0.45 else 0.48
	gun_node.scale = Vector3.ONE * clampf(target_span / span, 0.55, 1.95)
	_gunsmith_pivot.add_child(gun_node)


func _rebuild_map_diorama() -> void:
	if not is_instance_valid(_map_holo_pivot):
		return
	var sig := "%s|%s|%d" % [GameState.pvp_map, GameState.pvp_mode, GameState.team_preset]
	if sig == _map_holo_last_sig and _map_holo_pivot.get_child_count() > 0:
		return
	_map_holo_last_sig = sig
	MPG.build_map_diorama(_map_holo_pivot, GameState.pvp_map, GameState.pvp_mode, GameState.team_preset)


func _update_stage_mode() -> void:
	var new_mode := "command"
	if _current_page == "loadouts":
		new_mode = "gunsmith"
	elif _current_page == "multiplayer" and not _mp_stage_show_operator:
		new_mode = "map"
	_stage_mode = new_mode
	if is_instance_valid(_gunsmith_stage):
		_gunsmith_stage.visible = (_stage_mode == "gunsmith")
	if is_instance_valid(_map_holo_stage):
		_map_holo_stage.visible = (_stage_mode == "map")
	if is_instance_valid(_gunsmith_overlay):
		_gunsmith_overlay.visible = (_stage_mode == "gunsmith")
		_gunsmith_overlay.queue_redraw()
	if _stage_mode == "map":
		_rebuild_map_diorama()


func _attach_showcase_weapon(cid: String) -> void:
	if _current_page == "loadouts":
		return
	if _current_page == "multiplayer":
		var ls: Dictionary = GameState.get_active_loadout()
		_attach_showcase_weapon_id(String(ls.get("primary", "m4_carbine")), ls.get("attachments", []), String(ls.get("pri_camo", "factory")))
		return
	var winfo: Dictionary = OPERATOR_WEAPONS.get(cid, OPERATOR_WEAPONS["ravager"])
	_attach_showcase_weapon_path(String(winfo.get("model", "")), String(winfo.get("id", "shotgun")), [], "factory")


func _attach_showcase_weapon_id(w_id: String, atts: Array = [], camo_id: String = "factory") -> void:
	var wcfg: Dictionary = GameState.WEAPONS.get(w_id, GameState.WEAPONS.get("rifle", {}))
	_attach_showcase_weapon_path(String(wcfg.get("model", "")), w_id, atts, camo_id)


func _attach_showcase_weapon_path(mpath: String, w_id: String, atts: Array, camo_id: String = "factory") -> void:
	if is_instance_valid(_showcase_weapon):
		_showcase_weapon.queue_free()
		_showcase_weapon = null
	if not is_instance_valid(operator):
		return
	if mpath == "" or not ResourceLoader.exists(mpath):
		return
	var packed := load(mpath) as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return
	if w_id != "":
		var dcfg: Dictionary = GameState.WEAPONS.get(w_id, {}).duplicate(true)
		dcfg["attachments"] = atts
		dcfg["camo"] = camo_id
		WeaponRigBuilder.decorate_viewmodel(inst, w_id, dcfg)
	_prepare_showcase_weapon_node(inst)
	var holder := Node3D.new()
	holder.position = Vector3(0.02, 1.22, -0.22)
	holder.rotation_degrees = Vector3(0.0, -82.0, 28.0)
	holder.scale = Vector3.ONE * 1.02
	holder.add_child(inst)
	operator.add_child(holder)
	_showcase_weapon = holder


func _prepare_showcase_weapon_node(n: Node) -> void:
	if n.name.begins_with("Arm") or n.name.begins_with("Hand"):
		if n is Node3D:
			(n as Node3D).visible = false
		return
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 1
	for c in n.get_children():
		_prepare_showcase_weapon_node(c)


func _apply_diorama_mode(is_od: bool) -> void:
	var is_pvp: bool = _current_page in ["multiplayer", "loadouts"] or GameState.is_pvp()
	for dz in _diorama_zombies:
		if is_instance_valid(dz):
			dz.visible = not is_pvp
	var pvp_accent: Color = GameState.pvp_team_color(GameState.pvp_selected_team)
	var is_horror: bool = GameState.is_horror_mode() and not is_od and not is_pvp
	var bright: bool = is_od or is_pvp
	if diorama_env != null and diorama_sky != null:
		if bright:
			var top_c: Color = Color(0.14, 0.34, 0.64)
			var hor_c: Color = Color(0.82, 0.64, 0.38)
			var gbot_c: Color = Color(0.16, 0.14, 0.12)
			var ghor_c: Color = Color(0.62, 0.50, 0.34)
			var amb_c: Color = Color(0.55, 0.56, 0.64)
			if is_pvp:
				gbot_c = Color(0.14, 0.16, 0.20)
				ghor_c = Color(0.45, 0.50, 0.58)
				amb_c = Color(0.58, 0.64, 0.74)
				match GameState.pvp_map:
					"dockyard":
						top_c = Color(0.08, 0.30, 0.58)
						hor_c = pvp_accent.lerp(Color(0.52, 0.78, 0.94), 0.72)
					"black_site":
						top_c = Color(0.12, 0.36, 0.68)
						hor_c = pvp_accent.lerp(Color(0.76, 0.88, 0.98), 0.76)
						amb_c = Color(0.62, 0.72, 0.84)
					"quarry":
						top_c = Color(0.16, 0.38, 0.72)
						hor_c = pvp_accent.lerp(Color(0.92, 0.70, 0.44), 0.72)
						gbot_c = Color(0.24, 0.16, 0.10)
						ghor_c = Color(0.70, 0.54, 0.38)
					_:
						top_c = Color(0.10, 0.24, 0.46)
						hor_c = pvp_accent.lerp(Color(0.65, 0.72, 0.85), 0.65)
			diorama_sky.sky_top_color = top_c
			diorama_sky.sky_horizon_color = hor_c
			diorama_sky.ground_bottom_color = gbot_c
			diorama_sky.ground_horizon_color = ghor_c
			diorama_env.ambient_light_color = amb_c
			diorama_env.ambient_light_energy = 0.68 if is_pvp else 0.62
			diorama_env.fog_density = 0.004 if is_pvp else 0.006
			diorama_env.fog_light_color = hor_c if is_pvp else Color(0.88, 0.72, 0.45)
			diorama_env.volumetric_fog_enabled = false
		elif is_horror:
			diorama_sky.sky_top_color = Color(0.008, 0.010, 0.016)
			diorama_sky.sky_horizon_color = Color(0.022, 0.018, 0.026)
			diorama_sky.ground_bottom_color = Color(0.004, 0.004, 0.006)
			diorama_sky.ground_horizon_color = Color(0.014, 0.014, 0.020)
			diorama_env.ambient_light_color = Color(0.05, 0.055, 0.075)
			diorama_env.ambient_light_energy = 0.11
			diorama_env.fog_density = 0.042
			diorama_env.fog_light_color = Color(0.02, 0.022, 0.032)
			diorama_env.volumetric_fog_enabled = GameState.graphics_quality >= 1
		else:
			# Readable moonlit night for CASUAL & INFINITE
			diorama_sky.sky_top_color = Color(0.03, 0.05, 0.11)
			diorama_sky.sky_horizon_color = Color(0.10, 0.13, 0.22)
			diorama_sky.ground_bottom_color = Color(0.02, 0.025, 0.04)
			diorama_sky.ground_horizon_color = Color(0.07, 0.09, 0.15)
			diorama_env.ambient_light_color = Color(0.28, 0.34, 0.48)
			diorama_env.ambient_light_energy = 0.44
			diorama_env.fog_density = 0.012
			diorama_env.fog_light_color = Color(0.16, 0.20, 0.30)
			diorama_env.volumetric_fog_enabled = GameState.graphics_quality >= 1
	if is_instance_valid(key_light):
		key_light.light_color = Color(0.95, 0.97, 1.0) if is_pvp else (Color(1.0, 0.90, 0.72) if is_od else (Color(0.88, 0.78, 0.76) if is_horror else Color(0.84, 0.90, 1.0)))
		key_light.light_energy = 5.4 if bright else (4.2 if is_horror else 5.0)
	if is_instance_valid(fill_light):
		fill_light.light_energy = 0.82 if is_pvp else (0.75 if is_od else (0.20 if is_horror else 0.62))
	if is_instance_valid(horde_glow):
		horde_glow.light_color = pvp_accent if is_pvp else (GOLD if is_od else (Color(0.98, 0.12, 0.12) if is_horror else Color(0.92, 0.26, 0.16)))
		horde_glow.light_energy = 0.95 if bright else (0.75 if is_horror else 0.55)
	if podium_ring_mat != null:
		podium_ring_mat.emission_enabled = true
		podium_ring_mat.emission = pvp_accent if is_pvp else (GOLD if is_od else (Color(0.96, 0.20, 0.24) if is_horror else ACCENT))
		podium_ring_mat.emission_energy_multiplier = 1.8 if bright else 0.95


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


func _embers(pos: Vector3, count: int) -> CPUParticles3D:
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
	return p


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
	var loops := [["wind_loop", -15.0], ["fire_loop", -16.0]]
	for l in loops:
		var st := GameState.get_sfx_stream(String(l[0]))
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
		p.volume_db = float(l[1])
		add_child(p)
		p.play()
		_amb.append(p)
		_amb_vol.append(float(l[1]))


func _apply_menu_audio() -> void:
	for i in range(_amb.size()):
		if is_instance_valid(_amb[i]):
			_amb[i].volume_db = -80.0 if _muted else _amb_vol[i]
	if is_instance_valid(_sound_btn):
		_sound_btn.text = "MUTE" if _muted else "AUDIO"
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
func _style_btn(btn: Button, active: bool, accent: Color, idle_bg: Color = Color(0.06, 0.075, 0.10, 0.92), pad_h: int = 8, pad_v: int = 4) -> void:
	var bg := accent.darkened(0.72) if active else idle_bg
	var border := accent if active else Color(1, 1, 1, 0.12)
	var bw := 2 if active else 1
	btn.add_theme_stylebox_override("normal", _box(bg, border, bw, 0, 4, pad_h, pad_v))
	btn.add_theme_stylebox_override("hover", _box(accent.darkened(0.56), accent.lightened(0.20), bw, 0, 4, pad_h, pad_v))
	btn.add_theme_stylebox_override("pressed", _box(accent.darkened(0.80), accent, bw, 0, 4, pad_h, pad_v))
	btn.add_theme_color_override("font_color", Color.WHITE if active else TEXT)


func _box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, left_bar: int = 0, corner: int = 4, pad_h: int = 12, pad_v: int = 7) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = maxi(bw, left_bar)
	sb.border_width_right = bw
	sb.border_width_top = bw
	sb.border_width_bottom = bw
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.set_stylebox("normal", "Button", _box(Color(0.06, 0.075, 0.10, 0.92), Color(1, 1, 1, 0.10), 1))
	th.set_stylebox("hover", "Button", _box(Color(0.13, 0.12, 0.14, 0.96), ACCENT, 1))
	th.set_stylebox("pressed", "Button", _box(Color(0.20, 0.10, 0.10, 0.98), ACCENT, 1))
	th.set_stylebox("disabled", "Button", _box(Color(0.05, 0.055, 0.07, 0.72), Color(1, 1, 1, 0.05), 1))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.52))
	th.set_font_size("font_size", "Button", 14)
	th.set_font_size("font_size", "Label", 14)
	th.set_color("font_color", "Label", TEXT)
	th.set_stylebox("normal", "LineEdit", _box(Color(0.04, 0.05, 0.07, 0.96), Color(1, 1, 1, 0.16), 1))
	th.set_stylebox("focus", "LineEdit", _box(Color(0.05, 0.07, 0.11, 0.98), CYAN, 1))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("caret_color", "LineEdit", CYAN)

	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color(1, 1, 1, 0.04)
	scroll_bg.set_corner_radius_all(3)
	scroll_bg.content_margin_left = 3
	scroll_bg.content_margin_right = 3
	th.set_stylebox("scroll", "VScrollBar", scroll_bg)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.95, 0.30, 0.20, 0.55)
	grab.set_corner_radius_all(3)
	th.set_stylebox("grabber", "VScrollBar", grab)
	var grab_hl := grab.duplicate() as StyleBoxFlat
	grab_hl.bg_color = Color(0.95, 0.30, 0.20, 0.85)
	th.set_stylebox("grabber_highlight", "VScrollBar", grab_hl)
	th.set_stylebox("grabber_pressed", "VScrollBar", grab_hl)

	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(1, 1, 1, 0.08)
	pbg.set_corner_radius_all(3)
	th.set_stylebox("background", "ProgressBar", pbg)
	var pfill := StyleBoxFlat.new()
	pfill.bg_color = CYAN
	pfill.set_corner_radius_all(3)
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


func _section_header(parent: Control, text: String, right_node: Control = null) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tick := ColorRect.new()
	tick.color = GOLD if GameState.is_overdrive() else ACCENT
	tick.custom_minimum_size = Vector2(3, 13)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tick)
	var lbl := _label(text, 11, DIM)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	if right_node != null:
		row.add_child(right_node)
	parent.add_child(row)


func _stat_bar(parent: Control, caption: String, frac: float, col: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cap := _label(caption, 10, DIM)
	cap.custom_minimum_size = Vector2(54, 0)
	row.add_child(cap)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(frac, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 7)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var val_lbl := _label("", 11, col)
	val_lbl.custom_minimum_size = Vector2(52, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)
	parent.add_child(row)
	return [bar, val_lbl]


func _stat_tile(parent: Control, value: String, caption: String, col: Color) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 1, 0, 5, 10, 8))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var val := _label(value, 20, col)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(val)
	var cap := _label(caption, 9, DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	parent.add_child(p)


# ---------------------------------------------------------------------------
# UI CONSTRUCTION
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = _make_theme()
	layer.add_child(_root)

	# Subtle bottom-left vignette for callout legibility without covering showcase
	var vgrad := Gradient.new()
	vgrad.set_color(0, Color(0.01, 0.014, 0.022, 0.72))
	vgrad.set_color(1, Color(0.01, 0.014, 0.022, 0.0))
	var vgt := GradientTexture2D.new()
	vgt.gradient = vgrad
	vgt.fill_from = Vector2(0, 1)
	vgt.fill_to = Vector2(0, 0)
	var bfade := TextureRect.new()
	bfade.texture = vgt
	bfade.anchor_top = 1.0
	bfade.anchor_bottom = 1.0
	bfade.anchor_right = 1.0
	bfade.offset_top = -220
	bfade.stretch_mode = TextureRect.STRETCH_SCALE
	bfade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bfade)

	# Interactive 3D Stage Drag & Scroll Layer + 2D Attachment Callout Overlay (Left Viewport)
	_stage_drag_zone = Control.new()
	_stage_drag_zone.anchor_right = 1.0
	_stage_drag_zone.anchor_bottom = 1.0
	_stage_drag_zone.offset_top = 62
	_stage_drag_zone.offset_bottom = -38
	_stage_drag_zone.offset_right = -752
	_stage_drag_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_drag_zone.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_stage_drag_zone.gui_input.connect(_on_stage_drag_input)
	_root.add_child(_stage_drag_zone)

	_gunsmith_overlay = Control.new()
	_gunsmith_overlay.anchor_right = 1.0
	_gunsmith_overlay.anchor_bottom = 1.0
	_gunsmith_overlay.offset_top = 62
	_gunsmith_overlay.offset_bottom = -38
	_gunsmith_overlay.offset_right = -752
	_gunsmith_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gunsmith_overlay.visible = false
	_gunsmith_overlay.draw.connect(_draw_gunsmith_callouts)
	_root.add_child(_gunsmith_overlay)

	_build_top_bar()
	_build_left_showcase_hud()
	_build_command_deck()
	_build_bottom_ticker()
	_build_deploy_overlay()


func _build_top_bar() -> void:
	_header_bar = PanelContainer.new()
	_header_bar.anchor_right = 1.0
	_header_bar.offset_bottom = 60
	_header_bar.add_theme_stylebox_override("panel", _box(Color(0.024, 0.028, 0.040, 0.92), Color(1, 1, 1, 0.09), 0, 0, 0, 22, 8))
	var bar_sb: StyleBoxFlat = _header_bar.get_theme_stylebox("panel") as StyleBoxFlat
	bar_sb.border_width_bottom = 1
	_root.add_child(_header_bar)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	_header_bar.add_child(h)

	# Brand Identity
	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 10)
	h.add_child(brand_row)
	_header_stripe = ColorRect.new()
	_header_stripe.color = ACCENT
	_header_stripe.custom_minimum_size = Vector2(4, 34)
	_header_stripe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand_row.add_child(_header_stripe)
	_header_icon = HI.icon("skull", 24, ACCENT)
	_header_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand_row.add_child(_header_icon)
	var brand_col := VBoxContainer.new()
	brand_col.add_theme_constant_override("separation", 0)
	brand_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand_row.add_child(brand_col)
	var title_lbl := _label("DEAD PROTOCOL", 20, Color.WHITE)
	brand_col.add_child(title_lbl)
	brand_col.add_child(_label("OUTPOST NACHT-7  //  COMMAND", 10, DIM))

	# Horizontal Nav Tabs
	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 6)
	nav_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_row.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(nav_row)

	for key in PAGE_ORDER:
		var meta: Dictionary = PAGE_META[key]
		var btn := Button.new()
		btn.text = String(meta["label"])
		btn.icon = HI.tex(String(meta["icon"]))
		btn.expand_icon = true
		btn.custom_minimum_size = Vector2(84, 38)
		btn.add_theme_font_size_override("font_size", 11)
		btn.focus_mode = Control.FOCUS_NONE
		var k_id: String = key
		btn.pressed.connect(func():
			_sfx("buy_ching", -14.0, 1.35)
			_show_page(k_id))
		nav_row.add_child(btn)
		_nav[key] = btn
		_nav_order.append(key)

	# Right Career + Network + Controls cluster
	var right_row := HBoxContainer.new()
	right_row.add_theme_constant_override("separation", 10)
	right_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(right_row)

	var lvl: int = GameState.career_level()
	var lo: int = GameState.xp_for_level(lvl)
	var hi: int = GameState.xp_for_level(lvl + 1)
	var rank_pill := PanelContainer.new()
	rank_pill.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.10), 1, 0, 5, 10, 4))
	right_row.add_child(rank_pill)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 8)
	rank_pill.add_child(rh)
	rh.add_child(HI.icon("crown", 14, AMBER))
	rh.add_child(_label("LV %d" % lvl, 12, CYAN))
	var xp_bar := ProgressBar.new()
	xp_bar.min_value = lo
	xp_bar.max_value = hi
	xp_bar.value = GameState.career_xp
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(68, 6)
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(xp_bar)

	var net_pill := PanelContainer.new()
	net_pill.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.10), 1, 0, 5, 10, 4))
	right_row.add_child(net_pill)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 6)
	net_pill.add_child(nh)
	_net_pill_dot = ColorRect.new()
	_net_pill_dot.custom_minimum_size = Vector2(8, 8)
	_net_pill_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_net_pill_dot.color = GREEN if Net.steam_ok else AMBER
	nh.add_child(_net_pill_dot)
	_net_pill_lbl = _label(Net.my_name.to_upper() if Net.steam_ok else "SOLO / LAN", 11, TEXT)
	nh.add_child(_net_pill_lbl)

	_sound_btn = Button.new()
	_sound_btn.text = "AUDIO"
	_sound_btn.custom_minimum_size = Vector2(74, 34)
	_sound_btn.add_theme_font_size_override("font_size", 11)
	_sound_btn.focus_mode = Control.FOCUS_NONE
	_sound_btn.pressed.connect(_toggle_sound)
	right_row.add_child(_sound_btn)

	var quit_btn := Button.new()
	quit_btn.text = "QUIT"
	quit_btn.icon = HI.tex("cross")
	quit_btn.expand_icon = true
	quit_btn.custom_minimum_size = Vector2(78, 34)
	quit_btn.add_theme_font_size_override("font_size", 11)
	quit_btn.focus_mode = Control.FOCUS_NONE
	quit_btn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.52))
	quit_btn.pressed.connect(func(): get_tree().quit())
	right_row.add_child(quit_btn)


func _build_left_showcase_hud() -> void:
	_left_hud = VBoxContainer.new()
	_left_hud.anchor_top = 1.0
	_left_hud.anchor_bottom = 1.0
	_left_hud.offset_left = 34
	_left_hud.offset_right = 490
	_left_hud.offset_bottom = -52
	_left_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_left_hud.add_theme_constant_override("separation", 8)
	_root.add_child(_left_hud)

	# Nemesis warning card
	_nemesis_card = PanelContainer.new()
	_nemesis_card.visible = not GameState.nemesis.is_empty()
	_left_hud.add_child(_nemesis_card)
	if not GameState.nemesis.is_empty():
		var nm: Dictionary = GameState.nemesis
		var nt: int = clampi(int(nm.get("tier", 3)), 3, 5)
		var ncol: Color = ZombieEnemy.TIER_COLORS[nt]
		_nemesis_card.add_theme_stylebox_override("panel", _box(Color(0.08, 0.025, 0.025, 0.90), ncol, 1, 4, 5, 12, 8))
		var n_row := HBoxContainer.new()
		n_row.add_theme_constant_override("separation", 8)
		_nemesis_card.add_child(n_row)
		n_row.add_child(HI.icon("skull", 18, ncol))
		_nemesis_plate = _label("NEMESIS HUNTING YOU: %s  %s" % [String(nm.get("name", "")), "★".repeat(nt)], 12, ncol)
		n_row.add_child(_nemesis_plate)

	# Continue Saved Run quick-resume card
	var saved: Dictionary = GameState.load_world()
	if not saved.is_empty() and int(saved.get("players", 1)) <= 1:
		_continue_card = PanelContainer.new()
		_continue_card.add_theme_stylebox_override("panel", _box(Color(0.03, 0.08, 0.055, 0.92), GREEN, 1, 4, 5, 12, 8))
		_left_hud.add_child(_continue_card)
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 10)
		_continue_card.add_child(ch)
		var cv := VBoxContainer.new()
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_theme_constant_override("separation", 1)
		ch.add_child(cv)
		var saved_mode: String = String(saved.get("mode", "casual"))
		var mode_name: String = String(MODES.get(saved_mode, MODES["casual"])["name"])
		var d_name: String = GameState.diff_name_for(saved_mode, int(saved.get("difficulty", 1)))
		cv.add_child(_label("SAVED OPERATION AVAILABLE", 11, GREEN))
		cv.add_child(_label("%s  •  ROUND %d  •  %s" % [mode_name, int(saved.get("round", 1)), d_name], 13, TEXT))
		var cbtn := Button.new()
		cbtn.text = "CONTINUE"
		cbtn.icon = HI.tex("play")
		cbtn.expand_icon = true
		cbtn.custom_minimum_size = Vector2(118, 34)
		cbtn.focus_mode = Control.FOCUS_NONE
		cbtn.add_theme_stylebox_override("normal", _box(Color(0.14, 0.48, 0.24), GREEN, 1))
		cbtn.pressed.connect(func(): _continue_run(saved))
		ch.add_child(cbtn)

	# Operator Callsign Nameplate
	_op_plate = PanelContainer.new()
	_op_plate.add_theme_stylebox_override("panel", _box(Color(0.025, 0.03, 0.045, 0.88), Color(1, 1, 1, 0.12), 1, 0, 5, 14, 10))
	_left_hud.add_child(_op_plate)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 12)
	_op_plate.add_child(ph)
	_op_plate_stripe = ColorRect.new()
	_op_plate_stripe.custom_minimum_size = Vector2(4, 46)
	_op_plate_stripe.color = ACCENT
	ph.add_child(_op_plate_stripe)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pv)
	_op_plate_role = _label("", 11, ACCENT)
	pv.add_child(_op_plate_role)
	_op_plate_name = _label("", 22, Color.WHITE)
	pv.add_child(_op_plate_name)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 6)
	pv.add_child(wrow)
	_op_plate_weapon_icon = HI.icon("shotgun", 15, CYAN)
	wrow.add_child(_op_plate_weapon_icon)
	_op_plate_weapon_lbl = _label("", 12, CYAN)
	_op_plate_weapon_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrow.add_child(_op_plate_weapon_lbl)

	# Showcase Camera Framing Preset Pills (WIDE / CLOSE-UP / CINEMATIC)
	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 4)
	pv.add_child(cam_row)
	cam_row.add_child(_label("CAM:", 9, DIM))
	_cam_preset_btns.clear()
	for ci in range(3):
		var clabels: Array = ["WIDE", "CLOSE-UP", "CINEMATIC"]
		var cb := Button.new()
		cb.text = String(clabels[ci])
		cb.custom_minimum_size = Vector2(68, 22)
		cb.add_theme_font_size_override("font_size", 9)
		cb.focus_mode = Control.FOCUS_NONE
		var c_cap: int = ci
		cb.pressed.connect(func():
			set_camera_preset(c_cap)
			_sfx("hit_tick", -14.0, 1.25))
		cam_row.add_child(cb)
		_cam_preset_btns.append(cb)
	_update_cam_preset_btns()

	# Top-Left Floating Active Field Directives Card (visible on PLAY & CO-OP)
	_directives_card = PanelContainer.new()
	_directives_card.anchor_left = 0.0
	_directives_card.anchor_top = 0.0
	_directives_card.offset_left = 34
	_directives_card.offset_top = 74
	_directives_card.offset_right = 432
	_directives_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_directives_card.add_theme_stylebox_override("panel", _box(Color(0.02, 0.028, 0.044, 0.88), AMBER, 1, 4, 5, 12, 8))
	_root.add_child(_directives_card)
	_directives_box = VBoxContainer.new()
	_directives_box.add_theme_constant_override("separation", 5)
	_directives_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_directives_card.add_child(_directives_box)
	_refresh_directives()

	# Top-Left Floating Stage Identity Header (Gunsmith / 3D Tactical Map)
	_stage_top_card = PanelContainer.new()
	_stage_top_card.anchor_left = 0.0
	_stage_top_card.anchor_top = 0.0
	_stage_top_card.offset_left = 30
	_stage_top_card.offset_top = 74
	_stage_top_card.offset_right = 470
	_stage_top_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_top_card.visible = false
	_stage_top_card.add_theme_stylebox_override("panel", _box(Color(0.02, 0.028, 0.044, 0.86), CYAN, 1, 4, 5, 14, 9))
	_root.add_child(_stage_top_card)
	var stv := VBoxContainer.new()
	stv.add_theme_constant_override("separation", 2)
	stv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_top_card.add_child(stv)
	_stage_top_kicker = _label("3D GUNSMITH STAGE", 10, CYAN)
	stv.add_child(_stage_top_kicker)
	_stage_top_title = _label("M4A1 SOPMOD", 21, Color.WHITE)
	stv.add_child(_stage_top_title)
	_stage_top_sub = _label("", 11, Color(0.76, 0.82, 0.90))
	stv.add_child(_stage_top_sub)

	# Bottom-Left Interactive 3D Stage Controls (Orbit / Spin / Slot / Map Toggle)
	_stage_bar_card = PanelContainer.new()
	_stage_bar_card.visible = false
	_stage_bar_card.add_theme_stylebox_override("panel", _box(Color(0.022, 0.028, 0.044, 0.90), Color(1, 1, 1, 0.14), 1, 0, 5, 12, 8))
	_left_hud.add_child(_stage_bar_card)
	var sbv := VBoxContainer.new()
	sbv.add_theme_constant_override("separation", 6)
	_stage_bar_card.add_child(sbv)
	var sbh := HBoxContainer.new()
	sbh.add_theme_constant_override("separation", 6)
	sbv.add_child(sbh)

	_stage_btn_a = Button.new()
	_stage_btn_a.custom_minimum_size = Vector2(96, 28)
	_stage_btn_a.add_theme_font_size_override("font_size", 10)
	_stage_btn_a.focus_mode = Control.FOCUS_NONE
	_stage_btn_a.pressed.connect(func():
		if _current_page == "loadouts":
			_armory_slot = "primary"
			_armory_cat_filter = "all"
			_sfx("hit_tick", -12.0, 1.15)
			_refresh_loadouts()
		elif _current_page == "multiplayer":
			_mp_stage_show_operator = false
			_sfx("hit_tick", -12.0, 1.15)
			_update_stage_mode()
			_update_left_hud_for_page())
	sbh.add_child(_stage_btn_a)

	_stage_btn_b = Button.new()
	_stage_btn_b.custom_minimum_size = Vector2(96, 28)
	_stage_btn_b.add_theme_font_size_override("font_size", 10)
	_stage_btn_b.focus_mode = Control.FOCUS_NONE
	_stage_btn_b.pressed.connect(func():
		if _current_page == "loadouts":
			_armory_slot = "secondary"
			_armory_cat_filter = "all"
			_sfx("hit_tick", -12.0, 1.1)
			_refresh_loadouts()
		elif _current_page == "multiplayer":
			_mp_stage_show_operator = true
			_sfx("hit_tick", -12.0, 1.1)
			_update_stage_mode()
			_update_left_hud_for_page())
	sbh.add_child(_stage_btn_b)

	_stage_spin_btn = Button.new()
	_stage_spin_btn.text = "SPIN: ON"
	_stage_spin_btn.custom_minimum_size = Vector2(82, 28)
	_stage_spin_btn.add_theme_font_size_override("font_size", 10)
	_stage_spin_btn.focus_mode = Control.FOCUS_NONE
	_stage_spin_btn.pressed.connect(func():
		if _stage_mode == "gunsmith":
			_gun_auto_spin = not _gun_auto_spin
		elif _stage_mode == "map":
			_map_auto_spin = not _map_auto_spin
		_sfx("hit_tick", -14.0, 1.2)
		_update_left_hud_for_page())
	sbh.add_child(_stage_spin_btn)

	var rst_view := Button.new()
	rst_view.text = "RESET [R]"
	rst_view.custom_minimum_size = Vector2(78, 28)
	rst_view.add_theme_font_size_override("font_size", 10)
	rst_view.focus_mode = Control.FOCUS_NONE
	_style_btn(rst_view, false, CYAN, Color(0.06, 0.08, 0.12, 0.92), 8, 3)
	rst_view.pressed.connect(func():
		_reset_stage_view()
		_sfx("hit_tick", -14.0, 1.1))
	sbh.add_child(rst_view)

	_stage_hint_lbl = _label("DRAG TO ROTATE 360°  ·  SCROLL ZOOM  ·  DOUBLE-CLICK RESET", 9, DIM)
	sbv.add_child(_stage_hint_lbl)


func _build_command_deck() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -742
	_panel.offset_right = -24
	_panel.offset_top = 72
	_panel.offset_bottom = -46
	var pst := _box(Color(0.022, 0.028, 0.040, 0.93), ACCENT, 1, 0, 6, 20, 14)
	pst.border_width_top = 3
	_panel.add_theme_stylebox_override("panel", pst)
	_root.add_child(_panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	_panel.add_child(pv)

	var title_row := HBoxContainer.new()
	_content_title = _label("", 22, Color.WHITE)
	_content_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_content_title)
	_page_index = _label("", 12, DIM)
	_page_index.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_page_index)
	pv.add_child(title_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	_play_scroll = scroll
	_stack = VBoxContainer.new()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stack)

	_play_footer = VBoxContainer.new()
	_play_footer.add_theme_constant_override("separation", 4)
	pv.add_child(_play_footer)
	var deploy := Button.new()
	deploy.text = "DEPLOY — NACHT OUTBREAK"
	deploy.icon = HI.tex("play")
	deploy.expand_icon = true
	deploy.custom_minimum_size = Vector2(0, 50)
	deploy.add_theme_font_size_override("font_size", 19)
	deploy.focus_mode = Control.FOCUS_NONE
	_deploy_btn = deploy
	deploy.pressed.connect(_deploy)
	_play_footer.add_child(deploy)
	_deploy_summary = _label("", 11, DIM)
	_deploy_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_play_footer.add_child(_deploy_summary)

	_pages["play"] = _build_play_page()
	_pages["loadouts"] = _build_loadouts_page()
	_pages["multiplayer"] = _build_multiplayer_page()
	_pages["coop"] = _build_coop_page()
	_pages["career"] = _build_career_page()
	_pages["intel"] = _build_intel_page()
	var opts := OptionsPanel.new()
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages["options"] = opts
	for k in _pages:
		_stack.add_child(_pages[k])


func _build_bottom_ticker() -> void:
	var bar := PanelContainer.new()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 1.0
	bar.offset_top = -36
	bar.add_theme_stylebox_override("panel", _box(Color(0.018, 0.022, 0.032, 0.94), Color(1, 1, 1, 0.08), 0, 0, 0, 22, 6))
	var sb: StyleBoxFlat = bar.get_theme_stylebox("panel") as StyleBoxFlat
	sb.border_width_top = 1
	_root.add_child(bar)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	bar.add_child(h)
	_tip_icon = HI.icon("warning", 15, AMBER)
	_tip_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_tip_icon)
	_tip_label = _label(GameState.keyify(TIPS[0]), 12, Color(0.76, 0.80, 0.86))
	_tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tip_label.clip_text = true
	h.add_child(_tip_label)
	var controls := _label("[1-7] TABS   [Q/E] SWITCH   [ENTER] DEPLOY   [ESC] BACK", 11, DIM)
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(controls)


func _build_deploy_overlay() -> void:
	_deploy_overlay = ColorRect.new()
	_deploy_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deploy_overlay.color = Color(0.005, 0.008, 0.012, 1)
	_deploy_overlay.modulate.a = 0.0
	_deploy_overlay.visible = false
	_deploy_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_deploy_overlay)
	var dv := VBoxContainer.new()
	dv.set_anchors_preset(Control.PRESET_CENTER)
	dv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dv.grow_vertical = Control.GROW_DIRECTION_BOTH
	dv.add_theme_constant_override("separation", 8)
	_deploy_overlay.add_child(dv)
	_deploy_label = _label("DEPLOYING TO NACHT-7 …", 26, Color.WHITE)
	_deploy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(_deploy_label)
	var sub := _label("ESTABLISHING SECURE UPLINK", 12, DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(sub)


func _entrance_animation() -> void:
	_left_hud.modulate.a = 0.0
	var lt := _left_hud.create_tween()
	lt.tween_property(_left_hud, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_panel.modulate.a = 0.0
	var pt := _panel.create_tween()
	pt.tween_property(_panel, "modulate:a", 1.0, 0.42).set_delay(0.08).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _show_page(key: String) -> void:
	if not _pages.has(key) or key == _current_page:
		return
	if key == "multiplayer":
		if GameState.game_mode != "pvp":
			GameState.last_pve_mode = GameState.game_mode
		GameState.game_mode = "pvp"
	elif key == "play" and GameState.game_mode == "pvp":
		GameState.game_mode = GameState.last_pve_mode
	_current_page = key
	var meta: Dictionary = PAGE_META.get(key, {})
	_content_title.text = String(meta.get("title", key.to_upper()))
	var pi: int = PAGE_ORDER.find(key)
	_page_index.text = "%02d / %02d" % [pi + 1, PAGE_ORDER.size()] if pi >= 0 else ""
	if key == "career":
		var old: Control = _pages["career"]
		old.visible = false
		old.queue_free()
		_pages["career"] = _build_career_page()
		_stack.add_child(_pages["career"])
	for k in _pages:
		_pages[k].visible = k == key
	if is_instance_valid(_play_footer):
		_play_footer.visible = (key == "play" or key == "multiplayer")
	var idx: int = _nav_order.find(key)
	if idx >= 0:
		_nav_index = idx
	_update_nav_styles()
	var page: Control = _pages[key]
	page.modulate.a = 0.0
	var tw := page.create_tween()
	tw.tween_property(page, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if key == "multiplayer":
		_refresh_multiplayer()
	elif key == "loadouts":
		_refresh_loadouts()
	elif key == "play":
		_refresh_play()
	elif key == "coop":
		_refresh_coop()
	_update_stage_mode()
	_update_left_hud_for_page()


func _update_left_hud_for_page() -> void:
	var on_play := (_current_page == "play" or _current_page == "coop" or _current_page == "")
	var on_armory := (_current_page == "loadouts")
	var on_mp := (_current_page == "multiplayer")
	if is_instance_valid(_continue_card):
		_continue_card.visible = on_play
	if is_instance_valid(_nemesis_card):
		_nemesis_card.visible = on_play and not GameState.nemesis.is_empty()
	if is_instance_valid(_op_plate):
		_op_plate.visible = on_play or (on_mp and _mp_stage_show_operator)
	if is_instance_valid(_directives_card):
		_directives_card.visible = on_play
	if is_instance_valid(_stage_top_card):
		_stage_top_card.visible = on_armory or on_mp
	if is_instance_valid(_stage_bar_card):
		_stage_bar_card.visible = on_armory or on_mp

	if on_armory:
		var ls := GameState.get_active_loadout()
		var on_pri := _armory_slot == "primary"
		var w_id := String(ls.get("primary" if on_pri else "secondary", "m4_carbine"))
		var wc: Dictionary = GameState.WEAPONS.get(w_id, {})
		var camo_id := String(ls.get("pri_camo" if on_pri else "sec_camo", "factory"))
		var camo_name := String(WeaponCatalog.WEAPON_CAMOS.get(camo_id, {}).get("name", "FACTORY"))
		var atts: Array = ls.get("attachments" if on_pri else "sec_attachments", [])
		var slot_col := CYAN if on_pri else AMBER
		_stage_top_card.add_theme_stylebox_override("panel", _box(Color(0.02, 0.028, 0.044, 0.88), slot_col, 1, 4, 5, 14, 9))
		_stage_top_kicker.text = "%s  //  %s" % ["PRIMARY SLOT" if on_pri else "SECONDARY SLOT", String(WeaponCatalog.CLASS_LABELS.get(String(wc.get("class", "")), "WEAPON"))]
		_stage_top_kicker.add_theme_color_override("font_color", slot_col)
		_stage_top_title.text = String(wc.get("name", w_id.to_upper()))
		var tag_s := GameState.format_attachment_tags(atts)
		_stage_top_sub.text = "FINISH: %s  ·  %d/%d MODS%s" % [camo_name.to_upper(), atts.size(), 3 if on_pri else 2, ("  " + tag_s) if tag_s != "" else ""]
		_stage_btn_a.text = "PRIMARY"
		_stage_btn_b.text = "SECONDARY"
		_style_btn(_stage_btn_a, on_pri, CYAN, Color(0.06, 0.08, 0.12, 0.92), 8, 3)
		_style_btn(_stage_btn_b, not on_pri, AMBER, Color(0.06, 0.08, 0.12, 0.92), 8, 3)
		_stage_spin_btn.text = "SPIN: ON" if _gun_auto_spin else "SPIN: OFF"
		_stage_spin_btn.visible = true
		_style_btn(_stage_spin_btn, _gun_auto_spin, CYAN, Color(0.06, 0.08, 0.12, 0.92), 8, 3)
		_stage_hint_lbl.text = "DRAG TO ROTATE 360°  ·  SCROLL ZOOM  ·  DOUBLE-CLICK RESET [R]"
	elif on_mp:
		var pvp_col: Color = GameState.pvp_team_color(GameState.pvp_selected_team)
		var is_rand := GameState.pvp_map == "random"
		var mp: Dictionary = GameState.PVP_MAPS.get("dockyard" if is_rand else GameState.pvp_map, GameState.PVP_MAPS["nacht"])
		var m_col: Color = GOLD if is_rand else mp.get("accent", pvp_col)
		_stage_top_card.add_theme_stylebox_override("panel", _box(Color(0.02, 0.028, 0.044, 0.88), m_col, 1, 4, 5, 14, 9))
		_stage_top_kicker.text = "TACTICAL RECON  //  %s" % String(GameState.PVP_MODES[GameState.pvp_mode]["name"])
		_stage_top_kicker.add_theme_color_override("font_color", m_col)
		_stage_top_title.text = "RANDOM MAP ROTATION" if is_rand else String(mp["name"])
		_stage_top_sub.text = "%s  ·  %s" % [String(GameState.PVP_TEAM_PRESETS[GameState.team_preset]["label"]), String(mp["tag"])]
		_stage_btn_a.text = "3D MAP"
		_stage_btn_b.text = "OPERATOR"
		_style_btn(_stage_btn_a, not _mp_stage_show_operator, m_col, Color(0.06, 0.08, 0.12, 0.92), 8, 3)
		_style_btn(_stage_btn_b, _mp_stage_show_operator, pvp_col, Color(0.06, 0.08, 0.12, 0.92), 8, 3)
		_stage_spin_btn.visible = not _mp_stage_show_operator
		_stage_spin_btn.text = "ORBIT: ON" if _map_auto_spin else "ORBIT: OFF"
		_style_btn(_stage_spin_btn, _map_auto_spin, m_col, Color(0.06, 0.08, 0.12, 0.92), 8, 3)
		_stage_hint_lbl.text = "DRAG TO ORBIT ARENA  ·  SCROLL ZOOM  ·  [R] RESET VIEW" if not _mp_stage_show_operator else "DRAG TO ROTATE OPERATOR  ·  SWITCH TO 3D MAP FOR TACTICAL OVERVIEW"


func _rotate_tip() -> void:
	if not is_instance_valid(_tip_label):
		return
	_tip_index = (_tip_index + 1) % TIPS.size()
	if _tip_tween and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_tween = _tip_label.create_tween()
	_tip_tween.tween_property(_tip_label, "modulate:a", 0.0, 0.22)
	_tip_tween.tween_callback(func(): _tip_label.text = GameState.keyify(TIPS[_tip_index]))
	_tip_tween.tween_property(_tip_label, "modulate:a", 1.0, 0.22)


# ---------------------------------------------------------------------------
# PLAY PAGE (Precision Budget for Zero Scroll Overflow)
# ---------------------------------------------------------------------------
func _build_play_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 01 // SELECT OPERATOR
	_section_header(v, "01 // SELECT OPERATOR")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)

	const OP_ICONS := {"ravager": "beast", "alchemist": "syringe", "warden": "bolt"}
	for cid in ["ravager", "alchemist", "warden"]:
		var cd: Dictionary = GameState.CHARACTERS[cid]
		var full := String(cd["name"])
		var short := full.get_slice("'", 1) if full.contains("'") else full.get_slice(" ", full.get_slice_count(" ") - 1)
		var role := String(cd["codename"]).get_slice("//", 1).strip_edges()
		var card := _build_selectable_card(48, String(OP_ICONS[cid]), short, role, "", Color(cd["accent"]))
		var btn: Button = card.get_node("Hit") as Button
		var c_id: String = cid
		btn.pressed.connect(func():
			_select_character(c_id)
			if c_id == "ravager":
				_sfx("monster_roar", -15.0, 1.0)
			elif c_id == "alchemist":
				_sfx("pain_drug", -13.0, 1.0)
			else:
				_sfx("trap_zap", -14.0, 1.0)
		)
		row.add_child(card)
		_char_cards[cid] = card

	# Operator Dossier Card
	var dossier := PanelContainer.new()
	dossier.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.08), 1, 0, 5, 12, 6))
	v.add_child(dossier)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 3)
	dossier.add_child(dv)

	var op_head := HBoxContainer.new()
	op_head.add_theme_constant_override("separation", 8)
	dv.add_child(op_head)
	_detail_name = _label("", 15, Color.WHITE)
	_detail_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_head.add_child(_detail_name)
	_detail_code = _label("", 11, ACCENT)
	op_head.add_child(_detail_code)

	_detail_summary = _label("", 11, Color(0.76, 0.80, 0.86), true)
	dv.add_child(_detail_summary)

	var bars_row := HBoxContainer.new()
	bars_row.add_theme_constant_override("separation", 14)
	dv.add_child(bars_row)
	var vit_pair: Array = _stat_bar(bars_row, "HEALTH", 0.7, ACCENT)
	_vitality_bar = vit_pair[0] as ProgressBar
	_detail_stats_hp = vit_pair[1] as Label
	var spd_pair: Array = _stat_bar(bars_row, "SPEED", 0.7, CYAN)
	_speed_bar = spd_pair[0] as ProgressBar
	_detail_stats_spd = spd_pair[1] as Label

	_skill_rows_box = VBoxContainer.new()
	_skill_rows_box.add_theme_constant_override("separation", 3)
	dv.add_child(_skill_rows_box)

	# 02 // OPERATION MODE
	_section_header(v, "02 // OPERATION MODE")
	var mgrid := GridContainer.new()
	mgrid.columns = 2
	mgrid.add_theme_constant_override("h_separation", 8)
	mgrid.add_theme_constant_override("v_separation", 5)
	v.add_child(mgrid)
	const HORROR_ACCENT := Color(0.96, 0.20, 0.24)
	for mid in ["casual", "infinite", "horror", "overdrive"]:
		var md: Dictionary = MODES[mid]
		var best_r: int = _best_round_for(mid)
		var badge_txt: String = ("BEST RD %d" % best_r) if best_r > 0 else String(md["tag"])
		var m_col: Color = GOLD if mid == "overdrive" else (HORROR_ACCENT if mid == "horror" else (CYAN if mid == "infinite" else ACCENT))
		var mcard := _build_mode_card(String(md["icon"]), String(md["name"]), badge_txt, String(md["desc"]), m_col, MPG.mode_banner(mid))
		mcard.custom_minimum_size = Vector2(0, 62)
		var mbtn: Button = mcard.get_node("Hit") as Button
		var m_id: String = mid
		mbtn.pressed.connect(func():
			GameState.game_mode = m_id
			GameState.write_save()
			_sfx("hit_tick", -10.0, 1.15 if m_id == "overdrive" else (0.78 if m_id == "horror" else 1.0))
			_refresh_play())
		mgrid.add_child(mcard)
		_mode_cards[mid] = mcard

	# 03 // THREAT TIER
	_score_mult_pill = _label("SCORE x1.0", 11, GOLD)
	_section_header(v, "03 // THREAT TIER", _score_mult_pill)
	_diff_grid = GridContainer.new()
	_diff_grid.columns = 4
	_diff_grid.add_theme_constant_override("h_separation", 6)
	_diff_grid.add_theme_constant_override("v_separation", 5)
	v.add_child(_diff_grid)

	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.07), 1, 0, 5, 10, 6))
	v.add_child(strip)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	strip.add_child(sv)
	_diff_chips_box = HBoxContainer.new()
	_diff_chips_box.add_theme_constant_override("separation", 6)
	sv.add_child(_diff_chips_box)
	_diff_info = _label("", 11, Color(0.76, 0.80, 0.86), true)
	sv.add_child(_diff_info)

	var kit_row := HBoxContainer.new()
	kit_row.add_theme_constant_override("separation", 5)
	v.add_child(kit_row)
	_play_custom_chk = Button.new()
	_play_custom_chk.custom_minimum_size = Vector2(148, 26)
	_play_custom_chk.add_theme_font_size_override("font_size", 10)
	_play_custom_chk.focus_mode = Control.FOCUS_NONE
	_play_custom_chk.pressed.connect(func():
		GameState.pve_use_custom_loadout = not GameState.pve_use_custom_loadout
		GameState.write_save()
		_sfx("hit_tick", -10.0, 1.1)
		_refresh_play())
	kit_row.add_child(_play_custom_chk)
	_play_set_btns.clear()
	for i in range(WeaponCatalog.DEFAULT_LOADOUTS.size()):
		var sb := Button.new()
		sb.text = "S%d" % (i + 1)
		sb.custom_minimum_size = Vector2(36, 26)
		sb.add_theme_font_size_override("font_size", 10)
		sb.focus_mode = Control.FOCUS_NONE
		var s_idx: int = i
		sb.pressed.connect(func():
			GameState.pve_use_custom_loadout = true
			GameState.set_active_loadout(s_idx)
			_sfx("weapon_swap", -10.0, 1.1)
			_refresh_play())
		kit_row.add_child(sb)
		_play_set_btns.append(sb)
	_play_armory_lbl = _label("", 10, CYAN)
	_play_armory_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_armory_lbl.clip_text = true
	kit_row.add_child(_play_armory_lbl)
	var ed_btn := Button.new()
	ed_btn.text = "ARMORY"
	ed_btn.custom_minimum_size = Vector2(72, 26)
	ed_btn.add_theme_font_size_override("font_size", 10)
	ed_btn.focus_mode = Control.FOCUS_NONE
	ed_btn.add_theme_stylebox_override("normal", _box(Color(0.08, 0.14, 0.22, 0.92), CYAN, 1, 0, 3, 6, 2))
	ed_btn.pressed.connect(func(): _show_page("loadouts"))
	kit_row.add_child(ed_btn)

	_rebuild_diff_buttons()
	v.visible = false
	return v


func _build_selectable_card(height_px: int, icon_name: String, title: String, sub: String, right_badge: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(0, height_px)
	p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.10), 1, 0, 5, 10, 6))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)

	var ic := HI.icon(icon_name, 20, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var t_lbl := _label(title, 13, Color.WHITE)
	t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(t_lbl)
	if right_badge != "":
		var b_lbl := _label(right_badge, 10, col)
		b_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(b_lbl)

	var s_lbl := _label(sub, 10, DIM)
	s_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s_lbl.clip_text = true
	v.add_child(s_lbl)

	var hit := Button.new()
	hit.name = "Hit"
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.mouse_entered.connect(func():
		p.modulate = Color(1.12, 1.12, 1.14, 1.0)
		_sfx("hit_tick", -22.0, 1.35))
	hit.mouse_exited.connect(func():
		p.modulate = Color.WHITE)
	p.add_child(hit)
	return p


func _build_mode_card(icon_name: String, title: String, badge_txt: String, desc: String, col: Color, banner_tex: Texture2D = null) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(0, 62 if banner_tex != null else 56)
	p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.10), 1, 0, 5, 8, 4))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)

	if banner_tex != null:
		var art := TextureRect.new()
		art.texture = banner_tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.custom_minimum_size = Vector2(0, 18)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(art)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	top.add_child(HI.icon(icon_name, 16, col))
	var t_lbl := _label(title, 13, Color.WHITE)
	t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(t_lbl)
	var b_lbl := _label(badge_txt, 10, col)
	b_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(b_lbl)

	var d_lbl := _label(desc, 10, Color(0.72, 0.76, 0.82), true)
	d_lbl.max_lines_visible = 2
	d_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d_lbl)

	var hit := Button.new()
	hit.name = "Hit"
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.mouse_entered.connect(func():
		p.modulate = Color(1.12, 1.12, 1.14, 1.0)
		_sfx("hit_tick", -22.0, 1.28))
	hit.mouse_exited.connect(func():
		p.modulate = Color.WHITE)
	p.add_child(hit)
	return p


func set_camera_preset(idx: int) -> void:
	_cam_preset = clampi(idx, 0, 2)
	_update_cam_preset_btns()


func _update_cam_preset_btns() -> void:
	for i in range(_cam_preset_btns.size()):
		var active: bool = i == _cam_preset
		_style_btn(_cam_preset_btns[i], active, CYAN, Color(0.06, 0.08, 0.12, 0.92), 9, 2)


func _refresh_directives() -> void:
	if not is_instance_valid(_directives_box):
		return
	for c in _directives_box.get_children():
		c.queue_free()
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 6)
	_directives_box.add_child(head_row)
	head_row.add_child(HI.icon("target", 14, AMBER))
	head_row.add_child(_label("ACTIVE FIELD DIRECTIVES", 10, AMBER))

	var best_rd: int = maxi(maxi(GameState.best_round, GameState.best_round_infinite), maxi(GameState.best_round_horror, GameState.best_round_overdrive))
	var defs: Array = [
		["skull", "EXTERMINATION PROTOCOL", GameState.life_kills, [50, 250, 1000, 5000], ACCENT],
		["crown", "APEX BOSS HUNTER", GameState.life_bosses, [3, 15, 50, 150], GOLD],
		["shield", "SIEGE ENDURANCE", best_rd, [5, 10, 20, 35], CYAN],
	]
	for d in defs:
		var val: int = int(d[2])
		var tiers: Array = d[3]
		var goal: int = int(tiers[tiers.size() - 1])
		var tier_lbl: String = "MASTER"
		for ti in range(tiers.size()):
			if val < int(tiers[ti]):
				goal = int(tiers[ti])
				tier_lbl = "TIER %s" % GameState.to_roman(ti + 1)
				break
		var col: Color = d[4] as Color
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_directives_box.add_child(row)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		row.add_child(top)
		top.add_child(HI.icon(String(d[0]), 12, col))
		var nm := _label("%s · %s" % [String(d[1]), tier_lbl], 10, TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		top.add_child(_label("%d / %d" % [val, goal], 10, col))
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = float(maxi(1, goal))
		bar.value = float(mini(val, goal))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 5)
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		fill.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)


func _best_round_for(mid: String) -> int:
	if mid == "overdrive":
		return GameState.best_round_overdrive
	if mid == "horror":
		return GameState.best_round_horror
	if mid == "infinite":
		return GameState.best_round_infinite
	return GameState.best_round


func _rebuild_diff_buttons() -> void:
	if not is_instance_valid(_diff_grid):
		return
	var target_kind: String = "overdrive" if GameState.is_overdrive() else "horror"
	if _diff_grid_mode == target_kind and not _diff_buttons.is_empty():
		return
	_diff_grid_mode = target_kind
	for c in _diff_grid.get_children():
		c.queue_free()
	_diff_buttons.clear()
	if target_kind == "overdrive":
		_diff_grid.columns = 5
		for i in range(GameState.OVERDRIVE_DIFFICULTIES.size()):
			var b := Button.new()
			var d: Dictionary = GameState.OVERDRIVE_DIFFICULTIES[i]
			b.text = "%s\nx%s" % [GameState.OVERDRIVE_DIFFICULTY_NAMES[i], str(snappedf(float(d["score"]), 0.01))]
			b.custom_minimum_size = Vector2(0, 40)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 11)
			b.focus_mode = Control.FOCUS_NONE
			var t := float(i) / maxf(1.0, float(GameState.OVERDRIVE_DIFFICULTIES.size() - 1))
			b.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0).lerp(GOLD, t))
			var idx: int = i
			b.pressed.connect(func():
				GameState.overdrive_difficulty = idx
				GameState.write_save()
				_sfx("hit_tick", -10.0, 1.1)
				_refresh_play())
			_diff_grid.add_child(b)
			_diff_buttons.append(b)
	else:
		_diff_grid.columns = 4
		for i in range(GameState.DIFFICULTIES.size()):
			var b := Button.new()
			b.text = "%s\nx%s" % [GameState.DIFFICULTY_NAMES[i], str(snappedf(float(GameState.DIFFICULTIES[i]["score"]), 0.01))]
			b.custom_minimum_size = Vector2(0, 38)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 11)
			b.focus_mode = Control.FOCUS_NONE
			if i >= 3:
				b.add_theme_color_override("font_color", Color(1.0, 0.58, 0.42).lerp(Color(1.0, 0.24, 0.22), float(i - 3) / 3.0))
			var idx: int = i
			b.pressed.connect(func():
				GameState.difficulty = idx
				GameState.write_save()
				_sfx("hit_tick", -10.0, 1.0)
				_refresh_play())
			_diff_grid.add_child(b)
			_diff_buttons.append(b)


func _refresh_play() -> void:
	if not is_instance_valid(_deploy_btn):
		return
	if _current_page == "multiplayer" or GameState.is_pvp():
		_refresh_multiplayer()
		return
	var od: bool = GameState.is_overdrive()
	_refresh_directives()
	var hr: bool = GameState.is_horror_mode()
	var horror_col := Color(0.96, 0.20, 0.24)
	var mode_col: Color = GOLD if od else (horror_col if hr else (CYAN if GameState.game_mode == "infinite" else ACCENT))
	_rebuild_diff_buttons()
	_apply_diorama_mode(od)
	_update_nav_styles()

	# Header / Deck mode-reactive accent trim
	if is_instance_valid(_header_stripe):
		_header_stripe.color = mode_col
	if is_instance_valid(_header_icon):
		_header_icon.modulate = mode_col
	if is_instance_valid(_tip_icon):
		_tip_icon.texture = HI.tex("star" if od else ("eye" if hr else "warning"))
		_tip_icon.modulate = GOLD if od else (horror_col if hr else AMBER)
	if is_instance_valid(_panel):
		var pst := _box(Color(0.022, 0.028, 0.040, 0.93), mode_col, 1, 0, 6, 20, 14)
		pst.border_width_top = 3
		_panel.add_theme_stylebox_override("panel", pst)

	for mid in _mode_cards:
		var on: bool = mid == GameState.game_mode
		var hi_col: Color = GOLD if mid == "overdrive" else (horror_col if mid == "horror" else (CYAN if mid == "infinite" else ACCENT))
		var bg_col: Color = (Color(0.22, 0.16, 0.04, 0.96) if mid == "overdrive" else (Color(0.22, 0.04, 0.06, 0.96) if mid == "horror" else (Color(0.05, 0.16, 0.24, 0.95) if mid == "infinite" else Color(0.20, 0.07, 0.07, 0.95)))) if on else Color(1, 1, 1, 0.04)
		(_mode_cards[mid] as PanelContainer).add_theme_stylebox_override("panel", _box(bg_col, hi_col if on else Color(1, 1, 1, 0.10), 2 if on else 1, 0, 5, 8, 4))

	var cur_diff: int = GameState.active_diff_index()
	for i in range(_diff_buttons.size()):
		var on: bool = i == cur_diff
		var bg_col: Color = (Color(0.22, 0.16, 0.04, 0.96) if od else (Color(0.05, 0.16, 0.24, 0.95) if GameState.game_mode == "infinite" else Color(0.20, 0.07, 0.07, 0.95))) if on else Color(0.06, 0.075, 0.10, 0.92)
		_diff_buttons[i].add_theme_stylebox_override("normal", _box(bg_col, mode_col if on else Color(1, 1, 1, 0.10), 2 if on else 1, 0, 4, 8, 4))

	if Net.is_online() and Net.is_host():
		_deploy_btn.text = "LAUNCH CO-OP MATCH  (%d PLAYERS)" % Net.players.size()
		_deploy_btn.disabled = false
	elif Net.is_online():
		_deploy_btn.text = "WAITING FOR SQUAD HOST..."
		_deploy_btn.disabled = true
	else:
		_deploy_btn.text = "LAUNCH OVERDRIVE ARENA" if od else ("DEPLOY — BLACKOUT HORROR" if hr else "DEPLOY — NACHT OUTBREAK")
		_deploy_btn.disabled = false

	if od:
		_deploy_btn.add_theme_stylebox_override("normal", _box(Color(0.56, 0.39, 0.04), GOLD, 2))
		_deploy_btn.add_theme_stylebox_override("hover", _box(Color(0.74, 0.54, 0.08), Color(1.0, 0.92, 0.48), 2))
		_deploy_btn.add_theme_stylebox_override("pressed", _box(Color(0.45, 0.32, 0.04), GOLD, 2))
	else:
		_deploy_btn.add_theme_stylebox_override("normal", _box(Color(0.68, 0.11, 0.10), Color(1.0, 0.42, 0.32), 2))
		_deploy_btn.add_theme_stylebox_override("hover", _box(Color(0.84, 0.17, 0.14), Color(1.0, 0.62, 0.44), 2))
		_deploy_btn.add_theme_stylebox_override("pressed", _box(Color(0.54, 0.09, 0.08), Color(1.0, 0.42, 0.32), 2))

	# Telemetry Chips + Score Pill
	var d_tbl: Dictionary = GameState.OVERDRIVE_DIFFICULTIES[cur_diff] if od else GameState.DIFFICULTIES[cur_diff]
	if is_instance_valid(_score_mult_pill):
		_score_mult_pill.text = "SCORE x%s" % str(snappedf(float(d_tbl.get("score", 1.0)), 0.01))
		_score_mult_pill.add_theme_color_override("font_color", GOLD if od else AMBER)

	if is_instance_valid(_diff_chips_box):
		for c in _diff_chips_box.get_children():
			c.queue_free()
		var chips: Array = [
			["HP x%.2f" % float(d_tbl.get("hp", 1.0)), ACCENT],
			["SPD x%.2f" % float(d_tbl.get("speed", 1.0)), CYAN],
			["HORDE x%.2f" % float(d_tbl.get("crowd", 1.0)), AMBER],
		]
		if od:
			chips.append(["%d MUTATOR%s" % [int(d_tbl.get("mutators", 1)), "S" if int(d_tbl.get("mutators", 1)) > 1 else ""], GOLD])
			var tw: int = int(d_tbl.get("twin_every", 0))
			if tw > 0:
				chips.append(["TWIN BOSS /%d" % tw, Color(1.0, 0.45, 0.32)])
		elif hr:
			chips.append(["HORROR %d%%" % roundi(float(d_tbl.get("horror", 0.78)) * 100.0), Color(0.96, 0.28, 0.32)])
			chips.append(["CROWS + SIGHT/SOUND", Color(0.85, 0.45, 0.42)])
		else:
			chips.append(["LIT NIGHT", CYAN])
		for ch in chips:
			var cp := PanelContainer.new()
			cp.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), (ch[1] as Color).darkened(0.25), 1, 0, 3, 7, 2))
			cp.add_child(_label(String(ch[0]), 10, ch[1]))
			_diff_chips_box.add_child(cp)

	if is_instance_valid(_play_custom_chk):
		var on_k: bool = GameState.pve_use_custom_loadout
		_play_custom_chk.text = "CUSTOM KIT: ON" if on_k else "CUSTOM KIT: OFF"
		_play_custom_chk.add_theme_stylebox_override("normal", _box(Color(0.08, 0.22, 0.16, 0.92) if on_k else Color(0.06, 0.075, 0.10, 0.92), GREEN if on_k else Color(1, 1, 1, 0.12), 1, 0, 3, 6, 2))
		for i in range(_play_set_btns.size()):
			var act := on_k and i == GameState.active_loadout_index
			_play_set_btns[i].add_theme_stylebox_override("normal", _box(CYAN.darkened(0.72) if act else Color(0.06, 0.075, 0.10, 0.92), CYAN if act else Color(1, 1, 1, 0.10), 2 if act else 1, 0, 3, 4, 2))
		var ls: Dictionary = GameState.get_active_loadout()
		var p_name := String(GameState.WEAPONS.get(String(ls.get("primary", "")), {}).get("name", ""))
		var s_name := String(GameState.WEAPONS.get(String(ls.get("secondary", "")), {}).get("name", ""))
		if on_k:
			_play_armory_lbl.text = "DEPLOY KIT: %s + %s" % [p_name, s_name]
		else:
			_play_armory_lbl.text = "CLASSIC MODE: Start with M1911 & buy weapons on map"

	var lines: Array[String] = GameState.overdrive_diff_lines(cur_diff) if od else GameState.diff_lines(cur_diff)
	var d_name: String = GameState.active_diff_name()
	_diff_info.text = "%s:  %s" % [d_name, "  •  ".join(lines.slice(0, mini(lines.size(), 4)))]
	_deploy_summary.text = "%s  •  %s  •  %s  •  %s" % [
		MODES.get(GameState.game_mode, MODES["casual"])["name"],
		d_name,
		String(GameState.CHARACTERS[GameState.selected_character]["name"]).to_upper(),
		"CO-OP" if Net.is_online() else "SOLO"
	]
	if is_instance_valid(_coop_settings):
		_coop_settings.text = "MATCH CONFIG (HOST): %s • %s • OPERATOR: %s" % [MODES.get(GameState.game_mode, MODES["casual"])["name"], d_name, GameState.CHARACTERS[GameState.selected_character]["name"]]


func _select_character(cid: String) -> void:
	GameState.selected_character = cid
	Net.set_character(cid)
	var cd: Dictionary = GameState.CHARACTERS[cid]
	var accent: Color = cd["accent"]

	for k in _char_cards:
		var on: bool = k == cid
		var col: Color = GameState.CHARACTERS[k]["accent"]
		(_char_cards[k] as PanelContainer).add_theme_stylebox_override("panel", _box(Color(col.r, col.g, col.b, 0.16) if on else Color(1, 1, 1, 0.04), col if on else Color(1, 1, 1, 0.10), 2 if on else 1, 0, 5, 10, 6))

	_detail_code.text = String(cd["codename"])
	_detail_code.add_theme_color_override("font_color", accent)
	_detail_name.text = String(cd["name"])
	_detail_summary.text = String(cd["summary"])
	_vitality_bar.value = clampf(float(cd["max_hp"]) / 140.0, 0.0, 1.0)
	_speed_bar.value = clampf(float(cd["move_speed"]) / 7.0, 0.0, 1.0)
	_detail_stats_hp.text = "%.0f HP" % float(cd["max_hp"])
	_detail_stats_spd.text = "%.1f M/S" % float(cd["move_speed"])

	# Populate compact [Q] and [F] keycap skill rows
	if is_instance_valid(_skill_rows_box):
		for c in _skill_rows_box.get_children():
			c.queue_free()
		const SHORT_SKILLS := {
			"ravager": [["F", "MONSTER FORM — Morphs 18s; LMB Savage Rend (480 dmg), Q/RMB Seismic Slam stun."]],
			"alchemist": [["Q", "NOCICEPT-X DART — Cripples Boss dmg (-55%), speed (-45%) & armor."], ["F", "PAINKILLER OVERDOSE — Full heal +50 Shield, +35% fire/reload rate (10s)."]],
			"warden": [["Q", "TESLA CHARGE — 150 AoE shock damage + 2.5s stun (briefly stuns Bosses)."], ["F", "ARC OVERCHARGE — 12s bottomless clip & 2.2x plasma weapon damage."]],
		}
		var rows: Array = SHORT_SKILLS.get(cid, [])
		for sr in rows:
			var rh := HBoxContainer.new()
			rh.add_theme_constant_override("separation", 6)
			rh.add_child(HI.keycap(String(sr[0]), 10))
			var sl := _label(String(sr[1]), 11, TEXT, true)
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rh.add_child(sl)
			_skill_rows_box.add_child(rh)

	# Update Left Showcase Nameplate & 3D Held Weapon
	if is_instance_valid(_op_plate_stripe):
		_op_plate_stripe.color = accent
	if is_instance_valid(_op_plate_role):
		_op_plate_role.text = String(cd["codename"])
		_op_plate_role.add_theme_color_override("font_color", accent)
	if is_instance_valid(_op_plate_name):
		_op_plate_name.text = String(cd["name"])
	var winfo: Dictionary = OPERATOR_WEAPONS.get(cid, OPERATOR_WEAPONS["ravager"])
	if is_instance_valid(_op_plate_weapon_icon):
		_op_plate_weapon_icon.texture = HI.tex(String(winfo.get("icon", "rifle")))
		_op_plate_weapon_icon.modulate = CYAN
	if is_instance_valid(_op_plate_weapon_lbl):
		_op_plate_weapon_lbl.text = "SIGNATURE ARMAMENT: %s" % String(winfo.get("label", "RIFLE"))

	_attach_showcase_weapon(cid)
	if is_instance_valid(accent_light):
		accent_light.light_color = accent
	if podium_ring_mat:
		podium_ring_mat.albedo_color = accent.darkened(0.65)
	if podium_inner_mat:
		podium_inner_mat.emission = accent
	if is_instance_valid(rim_light):
		rim_light.light_color = accent.lerp(Color(0.95, 0.2, 0.15), 0.35)
	_refresh_play()


func _deploy() -> void:
	if _deploying:
		return
	_sfx("bolt_cycle", -2.0, 0.95)
	if Net.is_online():
		if Net.is_host():
			Net.start_game(false)
		return
	GameState.reset_run()
	GameState.run_id = GameState.new_run_id()
	GameState.pending_resume = false
	GameState.late_join = false
	var fade_txt: String = "DEPLOYING TO NACHT-7 …"
	if GameState.is_pvp():
		var m_id: String = GameState.resolve_pvp_map()
		GameState.write_save()
		fade_txt = "DEPLOYING TO %s …" % String(GameState.pvp_map_info(m_id)["name"])
	elif GameState.is_overdrive():
		fade_txt = "LAUNCHING OVERDRIVE ARENA …"
	_fade_to_game(fade_txt)


func _continue_run(saved: Dictionary) -> void:
	if _deploying:
		return
	_sfx("bolt_cycle", -2.0, 0.95)
	GameState.reset_run()
	GameState.run_id = int(saved.get("run_id", 0))
	GameState.game_mode = String(saved.get("mode", "casual"))
	if GameState.is_overdrive():
		GameState.overdrive_difficulty = clampi(int(saved.get("difficulty", 1)), 0, GameState.OVERDRIVE_DIFFICULTIES.size() - 1)
	else:
		GameState.difficulty = clampi(int(saved.get("difficulty", 1)), 0, GameState.DIFFICULTIES.size() - 1)
	GameState.pending_resume = true
	GameState.late_join = false
	_fade_to_game("RETURNING TO NACHT-7 …")


func _fade_to_game(text: String) -> void:
	_deploying = true
	_deploy_label.text = text
	_deploy_overlay.visible = true
	var tw := _deploy_overlay.create_tween()
	tw.tween_property(_deploy_overlay, "modulate:a", 1.0, 0.50).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/game.tscn"))


# ---------------------------------------------------------------------------
# CAREER
# ---------------------------------------------------------------------------
func _build_career_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lvl: int = GameState.career_level()
	var lo: int = GameState.xp_for_level(lvl)
	var hi: int = GameState.xp_for_level(lvl + 1)

	var top_card := PanelContainer.new()
	top_card.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), CYAN.darkened(0.2), 1, 4, 5, 14, 10))
	v.add_child(top_card)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	top_card.add_child(tv)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 8)
	tv.add_child(tr)
	tr.add_child(HI.icon("crown", 20, AMBER))
	var lv_lbl := _label("CAREER LEVEL %d" % lvl, 18, Color.WHITE)
	lv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(lv_lbl)
	tr.add_child(_label("%d / %d XP" % [GameState.career_xp, hi], 12, CYAN))
	var bar := ProgressBar.new()
	bar.min_value = lo
	bar.max_value = hi
	bar.value = GameState.career_xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	tv.add_child(bar)
	tv.add_child(_label("Every run's score converts directly to Career XP (1 XP per 10 points).", 11, DIM))

	_section_header(v, "META UNLOCKS")
	for u in GameState.META_UNLOCKS:
		var got: bool = lvl >= int(u["level"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(HI.icon("star" if got else "flag", 14, GREEN if got else DIM))
		row.add_child(_label("LV %d  —  %s" % [int(u["level"]), String(u["text"])], 13, GREEN if got else Color(0.56, 0.60, 0.66)))
		v.add_child(row)

	_section_header(v, "NEMESIS DOSSIER")
	if GameState.nemesis.is_empty():
		v.add_child(_label("None active. Fall while a commander is still standing and it will hunt future runs.", 13, DIM, true))
	else:
		var nm: Dictionary = GameState.nemesis
		var nt: int = clampi(int(nm.get("tier", 3)), 3, 5)
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), ZombieEnemy.TIER_COLORS[nt], 1, 4, 5, 12, 8))
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 3)
		plate.add_child(pv)
		pv.add_child(_label("%s  %s %s" % [String(nm.get("name", "")), "★".repeat(nt), ZombieEnemy.TIER_NAMES[nt]], 16, ZombieEnemy.TIER_COLORS[nt]))
		pv.add_child(_label("Killed you %d time(s). Stalks from Round 4. Slay for +2500 pts & a relic." % int(nm.get("kills", 1)), 12, Color(0.75, 0.78, 0.84), true))
		v.add_child(plate)

	_section_header(v, "LIFETIME COMBAT RECORD")
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

	_section_header(v, "PERSONAL BESTS")
	var rgrid := GridContainer.new()
	rgrid.columns = 5
	rgrid.add_theme_constant_override("h_separation", 8)
	rgrid.add_theme_constant_override("v_separation", 8)
	v.add_child(rgrid)
	_stat_tile(rgrid, str(GameState.best_round), "CASUAL ROUND", CYAN)
	_stat_tile(rgrid, str(GameState.best_round_infinite), "INFINITE ROUND", CYAN)
	_stat_tile(rgrid, str(GameState.best_round_horror), "HORROR ROUND", Color(0.96, 0.20, 0.24))
	_stat_tile(rgrid, str(GameState.best_round_overdrive), "OVERDRIVE ROUND", GOLD)
	_stat_tile(rgrid, str(GameState.best_kills), "BEST KILLS", ACCENT)
	v.visible = false
	return v


# ---------------------------------------------------------------------------
# MULTIPLAYER PVP PAGE (Up to 32 Players · 2 / 4 / 6 Teams · 4 Maps · Zero Overflow)
# ---------------------------------------------------------------------------
var _mp_mode_cards: Dictionary = {}
var _mp_map_cards: Dictionary = {}
var _mp_rand_map_btn: Button
var _mp_preset_btns: Dictionary = {}
var _mp_team_grid: GridContainer
var _mp_cap_btns: Dictionary = {}
var _mp_wep_btns: Dictionary = {}
var _mp_wep_note: Label
var _mp_net_lbl: Label
var _mp_ip_edit: LineEdit


func _build_multiplayer_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_section_header(v, "PVP MODE")
	var m_grid := GridContainer.new()
	m_grid.columns = 2
	m_grid.add_theme_constant_override("h_separation", 8)
	m_grid.add_theme_constant_override("v_separation", 4)
	v.add_child(m_grid)
	for pm_id in ["tdm", "gungame", "snd", "dom"]:
		var pm: Dictionary = GameState.PVP_MODES[pm_id]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 46)
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		var pid_cap: String = pm_id
		btn.pressed.connect(func():
			GameState.pvp_mode = pid_cap
			GameState.write_save()
			_sfx("buy_ching", -10.0, 1.3)
			if Net.is_host():
				Net.sync_match_config()
			_refresh_multiplayer())
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(vb)
		vb.add_child(_label(String(pm["name"]), 12, Color.WHITE))
		var dlbl := _label(String(pm["desc"]), 9, DIM, true)
		vb.add_child(dlbl)
		card.add_child(btn)
		m_grid.add_child(card)
		_mp_mode_cards[pm_id] = card

	_mp_rand_map_btn = Button.new()
	_mp_rand_map_btn.text = "RANDOM MAP"
	_mp_rand_map_btn.icon = HI.tex("swap")
	_mp_rand_map_btn.expand_icon = true
	_mp_rand_map_btn.custom_minimum_size = Vector2(118, 22)
	_mp_rand_map_btn.add_theme_font_size_override("font_size", 10)
	_mp_rand_map_btn.focus_mode = Control.FOCUS_NONE
	_mp_rand_map_btn.pressed.connect(func():
		GameState.pvp_map = "random"
		GameState.write_save()
		_sfx("buy_ching", -10.0, 1.35)
		if Net.is_host():
			Net.sync_match_config()
		_refresh_multiplayer())
	_section_header(v, "BATTLEGROUND MAP", _mp_rand_map_btn)

	var map_grid := GridContainer.new()
	map_grid.columns = 2
	map_grid.add_theme_constant_override("h_separation", 8)
	map_grid.add_theme_constant_override("v_separation", 6)
	v.add_child(map_grid)
	for mid in GameState.PVP_MAP_ORDER:
		var mp: Dictionary = GameState.PVP_MAPS[mid]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 64)
		var root_ov := Control.new()
		root_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		root_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(root_ov)

		var banner := TextureRect.new()
		banner.texture = MPG.map_banner(mid)
		banner.set_anchors_preset(Control.PRESET_FULL_RECT)
		banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root_ov.add_child(banner)

		var scrim := ColorRect.new()
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		scrim.color = Color(0.018, 0.024, 0.038, 0.56)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root_ov.add_child(scrim)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		vb.alignment = BoxContainer.ALIGNMENT_END
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(vb)
		var top_r := HBoxContainer.new()
		top_r.add_theme_constant_override("separation", 5)
		top_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(top_r)
		top_r.add_child(HI.icon(String(mp["icon"]), 14, mp["accent"]))
		var m_name := _label(String(mp["name"]), 12, Color.WHITE)
		m_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_r.add_child(m_name)
		top_r.add_child(_label(String(mp["tag"]), 9, mp["accent"]))
		var m_desc := _label(String(mp["desc"]), 9, Color(0.80, 0.85, 0.92))
		m_desc.clip_text = true
		vb.add_child(m_desc)

		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var mid_cap: String = mid
		btn.pressed.connect(func():
			GameState.pvp_map = mid_cap
			GameState.active_pvp_map = mid_cap
			GameState.write_save()
			_sfx("buy_ching", -10.0, 1.25)
			if Net.is_host():
				Net.sync_match_config()
			_refresh_multiplayer())
		card.add_child(btn)
		map_grid.add_child(card)
		_mp_map_cards[mid] = card

	_section_header(v, "TEAM STRUCTURE (MAX 32 PLAYERS)")
	var p_row := HBoxContainer.new()
	p_row.add_theme_constant_override("separation", 8)
	v.add_child(p_row)
	for tp_id in [2, 4, 6]:
		var tp: Dictionary = GameState.PVP_TEAM_PRESETS[tp_id]
		var b := Button.new()
		b.text = String(tp["label"])
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.focus_mode = Control.FOCUS_NONE
		var tid_cap: int = int(tp_id)
		b.pressed.connect(func():
			GameState.team_preset = tid_cap
			if GameState.pvp_selected_team >= GameState.pvp_team_count():
				GameState.pvp_selected_team = 0
				Net.set_team(0)
			_sfx("buy_ching", -10.0, 1.2)
			if Net.is_host():
				Net.sync_match_config()
			_refresh_multiplayer())
		p_row.add_child(b)
		_mp_preset_btns[tp_id] = b

	_section_header(v, "SELECT FACTION / SQUAD")
	_mp_team_grid = GridContainer.new()
	_mp_team_grid.columns = 3
	_mp_team_grid.add_theme_constant_override("h_separation", 8)
	_mp_team_grid.add_theme_constant_override("v_separation", 4)
	v.add_child(_mp_team_grid)

	_section_header(v, "PLAYER FILL & PRIMARY WEAPON")
	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 6)
	v.add_child(cap_row)
	for cap_item in [[32, "32P FULL"], [24, "24 PLAYERS"], [16, "16 PLAYERS"], [0, "HUMANS ONLY"]]:
		var cap_val: int = int(cap_item[0])
		var cb := Button.new()
		cb.text = String(cap_item[1])
		cb.custom_minimum_size = Vector2(0, 26)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.add_theme_font_size_override("font_size", 11)
		cb.focus_mode = Control.FOCUS_NONE
		cb.pressed.connect(func():
			GameState.pvp_player_cap = cap_val
			_sfx("hit_tick", -12.0, 1.2)
			if Net.is_host():
				Net.sync_match_config()
			_refresh_multiplayer())
		cap_row.add_child(cb)
		_mp_cap_btns[cap_val] = cb

	var wep_row := HBoxContainer.new()
	wep_row.add_theme_constant_override("separation", 5)
	v.add_child(wep_row)
	for i in range(WeaponCatalog.DEFAULT_LOADOUTS.size()):
		var wb := Button.new()
		wb.text = "SET %d" % (i + 1)
		wb.custom_minimum_size = Vector2(0, 26)
		wb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wb.add_theme_font_size_override("font_size", 11)
		wb.focus_mode = Control.FOCUS_NONE
		var s_cap: int = i
		wb.pressed.connect(func():
			GameState.set_active_loadout(s_cap)
			_sfx("weapon_swap", -8.0, 1.1)
			_refresh_multiplayer())
		wep_row.add_child(wb)
		_mp_wep_btns[str(i)] = wb
	var armory_btn := Button.new()
	armory_btn.text = "EDIT ARMORY ->"
	armory_btn.icon = HI.tex("rifle")
	armory_btn.expand_icon = true
	armory_btn.custom_minimum_size = Vector2(138, 26)
	armory_btn.add_theme_font_size_override("font_size", 10)
	armory_btn.focus_mode = Control.FOCUS_NONE
	armory_btn.add_theme_stylebox_override("normal", _box(Color(0.08, 0.16, 0.24, 0.94), CYAN, 1, 0, 3, 6, 3))
	armory_btn.pressed.connect(func():
		_sfx("buy_ching", -12.0, 1.3)
		_show_page("loadouts"))
	wep_row.add_child(armory_btn)
	_mp_wep_note = _label("", 10, AMBER)
	v.add_child(_mp_wep_note)

	_section_header(v, "ONLINE / LAN LOBBY (UP TO 32P)")
	var net_card := PanelContainer.new()
	net_card.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.10), 1, 0, 4, 8, 5))
	v.add_child(net_card)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 3)
	net_card.add_child(nv)

	_mp_net_lbl = _label("", 11, CYAN)
	nv.add_child(_mp_net_lbl)

	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 6)
	nv.add_child(nh)
	var host_lan := Button.new()
	host_lan.text = "HOST 32P LAN"
	host_lan.custom_minimum_size = Vector2(126, 28)
	host_lan.add_theme_font_size_override("font_size", 11)
	host_lan.focus_mode = Control.FOCUS_NONE
	host_lan.pressed.connect(func():
		Net.host_direct()
		Net.sync_match_config()
		_refresh_multiplayer())
	nh.add_child(host_lan)

	var host_st := Button.new()
	host_st.text = "HOST STEAM"
	host_st.custom_minimum_size = Vector2(114, 28)
	host_st.add_theme_font_size_override("font_size", 11)
	host_st.focus_mode = Control.FOCUS_NONE
	host_st.pressed.connect(func():
		Net.host_steam()
		_refresh_multiplayer())
	nh.add_child(host_st)

	_mp_ip_edit = LineEdit.new()
	_mp_ip_edit.text = "127.0.0.1"
	_mp_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mp_ip_edit.custom_minimum_size = Vector2(0, 28)
	nh.add_child(_mp_ip_edit)

	var join_btn := Button.new()
	join_btn.text = "JOIN IP"
	join_btn.custom_minimum_size = Vector2(82, 28)
	join_btn.add_theme_font_size_override("font_size", 11)
	join_btn.focus_mode = Control.FOCUS_NONE
	join_btn.pressed.connect(func():
		Net.join_direct(_mp_ip_edit.text)
		_refresh_multiplayer())
	nh.add_child(join_btn)

	v.visible = false
	return v


func _refresh_multiplayer() -> void:
	if not is_instance_valid(_mp_team_grid):
		return
	var sel_team: int = clampi(Net.my_team if Net.is_online() else GameState.pvp_selected_team, 0, GameState.pvp_team_count() - 1)
	GameState.pvp_selected_team = sel_team
	var pvp_col: Color = GameState.pvp_team_color(sel_team)
	_apply_diorama_mode(false)
	_update_nav_styles()

	if is_instance_valid(_header_stripe):
		_header_stripe.color = pvp_col
	if is_instance_valid(_header_icon):
		_header_icon.modulate = pvp_col
	if is_instance_valid(_panel):
		var pst := _box(Color(0.022, 0.028, 0.040, 0.93), pvp_col, 1, 0, 6, 20, 14)
		pst.border_width_top = 3
		_panel.add_theme_stylebox_override("panel", pst)

	for pm_id in _mp_mode_cards.keys():
		var on: bool = String(pm_id) == GameState.pvp_mode
		var card := _mp_mode_cards[pm_id] as PanelContainer
		card.add_theme_stylebox_override("panel", _box(pvp_col.darkened(0.75) if on else Color(1, 1, 1, 0.04), pvp_col if on else Color(1, 1, 1, 0.10), 2 if on else 1, 0, 4, 8, 4))

	var is_rand_map: bool = GameState.pvp_map == "random"
	if is_instance_valid(_mp_rand_map_btn):
		_mp_rand_map_btn.add_theme_stylebox_override("normal", _box(Color(0.24, 0.18, 0.04, 0.96) if is_rand_map else Color(0.06, 0.075, 0.10, 0.92), GOLD if is_rand_map else Color(1, 1, 1, 0.14), 2 if is_rand_map else 1, 0, 4, 8, 2))
		_mp_rand_map_btn.add_theme_color_override("font_color", GOLD if is_rand_map else TEXT)
	for mid in _mp_map_cards.keys():
		var mp: Dictionary = GameState.PVP_MAPS[mid]
		var m_col: Color = mp["accent"]
		var on: bool = (not is_rand_map) and String(mid) == GameState.pvp_map
		var mcard := _mp_map_cards[mid] as PanelContainer
		mcard.add_theme_stylebox_override("panel", _box(m_col.darkened(0.82) if on else Color(0.03, 0.04, 0.06, 0.92), m_col if on else Color(1, 1, 1, 0.14), 2 if on else 1, 0, 5, 7, 5))
	_rebuild_map_diorama()
	_update_left_hud_for_page()

	for tp_id in _mp_preset_btns.keys():
		var on: bool = int(tp_id) == GameState.team_preset
		var b := _mp_preset_btns[tp_id] as Button
		b.add_theme_stylebox_override("normal", _box(pvp_col.darkened(0.72) if on else Color(0.06, 0.075, 0.10, 0.92), pvp_col if on else Color(1, 1, 1, 0.10), 2 if on else 1, 0, 4, 8, 4))

	# Rebuild team faction buttons for 2, 4, or 6 teams
	for c in _mp_team_grid.get_children():
		c.queue_free()
	var t_count: int = GameState.pvp_team_count()
	var t_max: int = GameState.pvp_max_per_team()
	_mp_team_grid.columns = 2 if t_count <= 4 else 3
	for tid in range(t_count):
		var tc: Color = GameState.pvp_team_color(tid)
		var is_sel: bool = (tid == sel_team)
		var cnt: int = Net.count_on_team(tid) if Net.is_online() else (1 if is_sel else 0)
		var tb := Button.new()
		tb.text = "%s (%d/%d)%s" % [GameState.pvp_team_name(tid), cnt, t_max, " ★" if is_sel else ""]
		tb.custom_minimum_size = Vector2(0, 27)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.add_theme_font_size_override("font_size", 11)
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_stylebox_override("normal", _box(tc.darkened(0.68) if is_sel else Color(0.06, 0.075, 0.10, 0.92), tc if is_sel else tc.darkened(0.45), 2 if is_sel else 1, 0, 4, 6, 3))
		var t_cap: int = tid
		tb.pressed.connect(func():
			Net.set_team(t_cap)
			_sfx("hit_tick", -10.0, 1.3)
			_refresh_multiplayer())
		_mp_team_grid.add_child(tb)

	for cap_val in _mp_cap_btns.keys():
		var on: bool = int(cap_val) == GameState.pvp_player_cap
		var cb := _mp_cap_btns[cap_val] as Button
		cb.add_theme_stylebox_override("normal", _box(pvp_col.darkened(0.75) if on else Color(0.06, 0.075, 0.10, 0.92), pvp_col if on else Color(1, 1, 1, 0.10), 2 if on else 1, 0, 3, 6, 3))

	var is_gg: bool = GameState.pvp_mode == "gungame"
	for k in _mp_wep_btns.keys():
		var wb := _mp_wep_btns[k] as Button
		var idx := int(String(k))
		var ls_btn: Dictionary = GameState.get_loadout(idx)
		var p_short := String(GameState.WEAPONS.get(String(ls_btn.get("primary", "")), {}).get("name", "")).split(" ")[0]
		wb.text = "S%d · %s" % [idx + 1, p_short]
		wb.disabled = is_gg
		var on: bool = (not is_gg) and idx == GameState.active_loadout_index
		wb.add_theme_stylebox_override("normal", _box(pvp_col.darkened(0.75) if on else Color(0.06, 0.075, 0.10, 0.92), pvp_col if on else Color(1, 1, 1, 0.10), 2 if on else 1, 0, 3, 6, 3))
	var active_ls := GameState.get_active_loadout()
	if is_gg:
		_mp_wep_note.text = "GUN GAME OVERRIDE: All players climb the 12-weapon ladder ending with RPG-7V2 & Knife."
	else:
		var p_n := String(GameState.WEAPONS.get(String(active_ls.get("primary", "")), {}).get("name", ""))
		var s_n := String(GameState.WEAPONS.get(String(active_ls.get("secondary", "")), {}).get("name", ""))
		var let_s := String(GameState.LETHALS.get(String(active_ls.get("lethal", "frag")), {}).get("short", "FRAG"))
		var tac_s := String(GameState.TACTICALS.get(String(active_ls.get("tactical", "flashbang")), {}).get("short", "FLASH"))
		var prk_s := String(GameState.FIELD_PERKS.get(String(active_ls.get("perk", "fast_hands")), {}).get("short", "PERK"))
		var att_s := GameState.format_attachment_tags(active_ls.get("attachments", []))
		_mp_wep_note.text = "SET %d: %s %s  +  %s  |  %s + %s  ·  %s" % [GameState.active_loadout_index + 1, p_n, att_s, s_n, let_s, tac_s, prk_s]
	_attach_showcase_weapon(GameState.selected_character)

	var humans: int = Net.players.size() if Net.is_online() else 1
	var target_total: int = mini(32, maxi(humans, GameState.pvp_player_cap)) if GameState.pvp_player_cap > 0 else humans
	var bots: int = maxi(0, target_total - humans)
	_mp_net_lbl.text = "%s   |   %d/%d HUMANS · +%d AI BOTS (%d TOTAL)" % [Net.status_text if Net.is_online() else "OFFLINE / READY FOR LAN OR STEAM", humans, Net.MAX_PVP_PLAYERS, bots, target_total]

	var map_short: String = "RANDOM MAP" if is_rand_map else String(GameState.PVP_MAPS.get(GameState.pvp_map, GameState.PVP_MAPS["nacht"])["short"])
	if is_instance_valid(_deploy_btn):
		if Net.is_online() and Net.is_host():
			_deploy_btn.text = "LAUNCH %dP PVP MATCH (%d ONLINE)" % [target_total, humans]
			_deploy_btn.disabled = false
		elif Net.is_online():
			_deploy_btn.text = "WAITING FOR HOST TO LAUNCH PVP..."
			_deploy_btn.disabled = true
		else:
			_deploy_btn.text = "DEPLOY — %s (%s)" % [String(GameState.PVP_MODES[GameState.pvp_mode]["short"]), map_short]
			_deploy_btn.disabled = false
		_deploy_btn.add_theme_stylebox_override("normal", _box(pvp_col.darkened(0.55), pvp_col, 2))
		_deploy_btn.add_theme_stylebox_override("hover", _box(pvp_col.darkened(0.35), pvp_col.lightened(0.3), 2))
		_deploy_btn.add_theme_stylebox_override("pressed", _box(pvp_col.darkened(0.68), pvp_col, 2))
	if is_instance_valid(_deploy_summary):
		_deploy_summary.text = "%s  ·  %s  ·  %s  ·  %s  ·  %d COMBATANTS" % [
			map_short,
			String(GameState.PVP_MODES[GameState.pvp_mode]["name"]),
			String(GameState.PVP_TEAM_PRESETS[GameState.team_preset]["label"]),
			GameState.pvp_team_name(sel_team),
			target_total
		]


# ---------------------------------------------------------------------------
# INTEL
# ---------------------------------------------------------------------------
func _build_intel_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := Color(0.80, 0.83, 0.88)
	var add := func(text: String, col: Color = body, size: int = 12) -> void:
		v.add_child(_label(text, size, col, true))

	_section_header(v, "MULTIPLAYER PVP MODES & ARENAS (UP TO 32P · 6 TEAMS)")
	add.call("• 4 ARENAS + RANDOM ROTATION: Outpost Nacht-7 (Town), Ironclad Dockyard (Coastal Port), Sub-Zero Black Site (Arctic Silo), and Sunscorch Refinery (Desert Canyon).", CYAN)
	add.call("• TEAM STRUCTURES: 2 Teams (16v16 = 32), 4 Teams (4×8 = 32), or 6 Teams (up to 6/team, capped at 32) across all arena sectors with optional AI bot fill.", CYAN)
	add.call("• TEAM DEATHMATCH & DOMINATION: Race to 75/50 kills (TDM) or hold Flags A/B/C to 150 points (Domination). Unsuppressed gunfire pings radar.", CYAN)
	add.call("• GUN GAME: 9-weapon ladder (Pistol → Knife). Gun kills advance +1 tier; melee kills advance & demote victims (-1). Knife kill at Tier 9 wins!", GOLD)
	add.call("• SEARCH & DESTROY: No respawns! Hold [E] to plant/defuse Bomb Sites A or B. First to 4 rounds wins.", AMBER)

	_section_header(v, "OVERDRIVE v2 (SOLAR ARCADE MODE)")
	add.call("• SOLAR ARENA: Zero horror effects, pre-powered compound, golden skylight, radar & crosshair.", GOLD)
	add.call("• KILL-CHAIN RANKS (C → B → A → S → ★ OVERDRIVE ★): Chain kills rapidly to boost point multipliers, fire/reload rate, and kinetic slide impact. Reaching ★ OVERDRIVE ★ grants bottomless ammo & arc bullets.")
	add.call("• BLITZ DROP PODS: Once mid-wave, a golden supply pod lands with a sky beacon. Hold inside the ring (+20% charge per kill) for +750 pts, +50 Shield, 6s ★ OVERDRIVE ★ & a free weapon mod/forge!")
	add.call("• BOSS DRAFTS & REROLL PYLON: Defeating a boss raises 3 Town Plaza Draft Pedestals (1 free pick; Draft 3+ offers pre-forged MK-II guns) plus a Reroll Pylon to roll fresh offers.")
	add.call("• 10 STACKABLE MUTATIONS & DEFENSE GRID: Build explosive rounds, Volt Slides, Phoenix Core, or Grid Overclock while upgrading the 4 Town Plaza Auto-Turrets & Shock Coils to MK-III.")

	_section_header(v, "ZOMBIE RANKS & UPGRADING")
	var ranks := [
		[1, "Mindless. Walks straight at you."],
		[2, "Yellow outline. Sidesteps when shot, leaps the last few metres and runs from grenades."],
		[3, "Talks. Leads from behind, issues orders (traps, flanks, bodyguards) and casts stolen operator skills."],
		[4, "Rallies the horde, raises crawlers from the ground, and devours weak zombies to heal."],
		[5, "Summons reinforcements and unleashes psychic screams. Shoot its head to interrupt."],
	]
	for r in ranks:
		var t: int = int(r[0])
		add.call("%s %s — %s" % ["★".repeat(t), ZombieEnemy.TIER_NAMES[t], String(r[1])], ZombieEnemy.TIER_COLORS[t] if t > 1 else body)

	_section_header(v, "COMMANDER & NEMESIS TACTICS")
	add.call("• BODYGUARDS: A glowing shield bubble means guards are nearby — eliminate them first.")
	add.call("• HAZARDS: Jump over orange Seismic Slams, exit green Toxin pools, and dodge blue Arc bursts.")
	add.call("• BRAIN FEAST & TASTE OF BLOOD: Infected striking you or feasting near downed players rank up.")
	add.call("• NEMESIS: Commanders standing when you fall remember you and stalk from Round 4 (+2500 pts + relic on kill).")

	_section_header(v, "HAZARD DRUMS, SPECIAL ROUNDS & INTERMISSION")
	add.call("• EXPLOSIVE BARRELS: Shoot red fuel drums for chain explosions & elite stuns. Respawns after 2 rounds.")
	add.call(GameState.keyify("• EARLY READY [N]: Press [N] during intermission to launch the next wave early for +100 pts."))
	add.call(GameState.keyify("• Press [M] for full tactical map, hold [TAB] for scoreboard, [X]/[Z] for relic skills."))
	for k in GameState.ROUND_EVENTS:
		var ev: Dictionary = GameState.ROUND_EVENTS[k]
		add.call("%s — %s" % [String(ev["name"]), String(ev["desc"]).to_lower().capitalize()], ev["color"])
	v.visible = false
	return v


# ---------------------------------------------------------------------------
# CO-OP LOBBY
# ---------------------------------------------------------------------------
func _coop_button(text: String, on_press: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		_sfx("buy_ching", -8.0, 1.2)
		on_press.call())
	parent.add_child(b)
	return b


func _build_coop_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_label("Online squads run via Steam Relay (private IPs, zero port forwarding, up to 8 players) or Direct LAN/UDP. Teammates can join matches in progress.", 12, Color(0.74, 0.78, 0.85), true))
	coop_status = _label("", 14, AMBER, true)
	v.add_child(coop_status)
	_coop_settings = _label("", 12, CYAN, true)
	v.add_child(_coop_settings)

	_section_header(v, "STEAM RELAY")
	var steam_row := HBoxContainer.new()
	steam_row.add_theme_constant_override("separation", 8)
	v.add_child(steam_row)
	coop_host_steam = _coop_button("HOST STEAM SQUAD", func(): Net.host_steam(), steam_row)
	coop_invite = _coop_button("INVITE FRIENDS", func(): Net.invite_friends(), steam_row)

	_section_header(v, "DIRECT CONNECTION  (UDP PORT %d)" % Net.PORT)
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	v.add_child(ip_row)
	coop_ip = LineEdit.new()
	coop_ip.placeholder_text = "HOST IP ADDRESS"
	coop_ip.custom_minimum_size = Vector2(210, 40)
	ip_row.add_child(coop_ip)
	_coop_button("HOST", func(): Net.host_direct(), ip_row)
	_coop_button("JOIN", func(): Net.join_direct(coop_ip.text if coop_ip.text.strip_edges() != "" else "127.0.0.1"), ip_row)

	_section_header(v, "SQUAD ROSTER")
	var roster_panel := PanelContainer.new()
	roster_panel.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.08), 1, 0, 5, 12, 10))
	v.add_child(roster_panel)
	coop_roster = _label("", 14)
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
		_refresh_coop(), bottom)
	v.visible = false
	return v


func _refresh_coop() -> void:
	if coop_status == null or not is_instance_valid(coop_status):
		return
	if Net.status_text != "":
		coop_status.text = Net.status_text
	elif Net.steam_ok:
		coop_status.text = "STEAM ONLINE AS %s — HOST A SQUAD OR ACCEPT AN INVITE" % Net.my_name
	else:
		coop_status.text = "STEAM OFFLINE — START STEAM FOR RELAY PLAY OR USE DIRECT IP BELOW"
	coop_host_steam.disabled = not Net.steam_ok
	coop_invite.disabled = not (Net.steam_ok and Net.lobby_id != 0)
	var lines: Array[String] = []
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var pinfo: Dictionary = Net.players[id]
		var cname: String = GameState.CHARACTERS.get(String(pinfo.get("char", "")), {}).get("name", "?")
		lines.append("■ %s  —  %s%s" % [pinfo.get("name", "?"), cname, "   (HOST)" if int(id) == 1 else ""])
	coop_roster.text = "\n".join(lines) if not lines.is_empty() else "NO SQUAD CONNECTED — HOST A LOBBY OR JOIN VIA IP"
	coop_start.visible = Net.mode == Net.Mode.HOST
	var sw: Dictionary = GameState.load_world()
	coop_resume.visible = Net.mode == Net.Mode.HOST and not sw.is_empty()
	if coop_resume.visible:
		coop_resume.text = "RESUME ROUND %d" % int(sw.get("round", 1))
	_refresh_play()


# ---------------------------------------------------------------------------
# ARMORY / 3D GUNSMITH PAGE (5 Custom Sets · 40 Weapons · 8 PBR Camos · Mods)
# ---------------------------------------------------------------------------
func _build_loadouts_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 1) Custom Set Selector + Rename + Reset
	var set_row := HBoxContainer.new()
	set_row.add_theme_constant_override("separation", 5)
	v.add_child(set_row)
	_armory_set_btns.clear()
	for i in range(WeaponCatalog.DEFAULT_LOADOUTS.size()):
		var sb := Button.new()
		sb.text = "SET %d" % (i + 1)
		sb.custom_minimum_size = Vector2(58, 30)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.add_theme_font_size_override("font_size", 11)
		sb.focus_mode = Control.FOCUS_NONE
		var idx: int = i
		sb.pressed.connect(func():
			GameState.set_active_loadout(idx)
			_sfx("buy_ching", -12.0, 1.25)
			_refresh_loadouts())
		set_row.add_child(sb)
		_armory_set_btns.append(sb)

	_armory_name_edit = LineEdit.new()
	_armory_name_edit.placeholder_text = "CLASS NAME"
	_armory_name_edit.max_length = 22
	_armory_name_edit.custom_minimum_size = Vector2(146, 30)
	_armory_name_edit.add_theme_font_size_override("font_size", 11)
	_armory_name_edit.text_submitted.connect(func(txt: String):
		_commit_loadout_name(txt)
		_armory_name_edit.release_focus())
	_armory_name_edit.focus_exited.connect(func():
		_commit_loadout_name(_armory_name_edit.text))
	set_row.add_child(_armory_name_edit)

	var rst_btn := Button.new()
	rst_btn.text = "RESET"
	rst_btn.custom_minimum_size = Vector2(60, 30)
	rst_btn.add_theme_font_size_override("font_size", 10)
	rst_btn.focus_mode = Control.FOCUS_NONE
	rst_btn.add_theme_stylebox_override("normal", _box(Color(0.22, 0.08, 0.08, 0.92), ACCENT, 1, 0, 3, 6, 3))
	rst_btn.pressed.connect(func():
		GameState.reset_loadout_slot(GameState.active_loadout_index)
		_sfx("weapon_swap", -8.0, 0.95)
		_refresh_loadouts())
	set_row.add_child(rst_btn)

	# 2) Active Primary & Secondary Slot Cards (with weapon silhouettes)
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	v.add_child(slot_row)

	var pri_built := _build_armory_slot_card("SLOT 1 // PRIMARY", true)
	_armory_pri_card = pri_built[0]
	_armory_pri_lbl = pri_built[1]
	_armory_pri_sub = pri_built[2]
	_armory_pri_sil = pri_built[3]
	slot_row.add_child(_armory_pri_card)

	var sec_built := _build_armory_slot_card("SLOT 2 // SECONDARY & LAUNCHER", false)
	_armory_sec_card = sec_built[0]
	_armory_sec_lbl = sec_built[1]
	_armory_sec_sub = sec_built[2]
	_armory_sec_sil = sec_built[3]
	slot_row.add_child(_armory_sec_card)

	# 3) Clean 3-Subtab Bar (Arsenal / Mods & Camo / Ordnance & Perks)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	v.add_child(tab_row)
	_armory_subtab_btns.clear()
	_armory_subtab_panels.clear()
	for tdef in [
		["weapons", "01 // WEAPON ARSENAL"],
		["gunsmith", "02 // ATTACHMENTS & CAMO"],
		["equipment", "03 // ORDNANCE & PERKS"],
	]:
		var tid := String(tdef[0])
		var tb := Button.new()
		tb.text = String(tdef[1])
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size = Vector2(0, 30)
		tb.add_theme_font_size_override("font_size", 11)
		tb.focus_mode = Control.FOCUS_NONE
		tb.pressed.connect(func(): _set_armory_subtab(tid))
		tab_row.add_child(tb)
		_armory_subtab_btns[tid] = tb

	# --- SUBTAB A: WEAPON ARSENAL (Category Filter + 2-Col Silhouette Grid) ---
	var pan_weapons := VBoxContainer.new()
	pan_weapons.add_theme_constant_override("separation", 5)
	pan_weapons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(pan_weapons)
	_armory_subtab_panels["weapons"] = pan_weapons

	_armory_cat_row = HBoxContainer.new()
	_armory_cat_row.add_theme_constant_override("separation", 3)
	pan_weapons.add_child(_armory_cat_row)
	_armory_cat_btns.clear()
	var cat_list := ["all", "rifle", "br", "smg", "shotgun", "lmg", "sniper", "pistol", "launcher", "special", "wonder"]
	for cid in cat_list:
		var cb := Button.new()
		cb.text = "ALL" if cid == "all" else String(WeaponCatalog.CLASS_LABELS.get(cid, cid.to_upper())).get_slice(" ", 0)
		cb.custom_minimum_size = Vector2(0, 23)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.add_theme_font_size_override("font_size", 9)
		cb.focus_mode = Control.FOCUS_NONE
		var c_cap: String = cid
		cb.pressed.connect(func():
			_armory_cat_filter = c_cap
			_sfx("hit_tick", -14.0, 1.2)
			_refresh_loadouts())
		_armory_cat_row.add_child(cb)
		_armory_cat_btns[cid] = cb

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 250)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.theme = HI.theme()
	pan_weapons.add_child(scroll)
	_armory_grid = GridContainer.new()
	_armory_grid.columns = 2
	_armory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_armory_grid.add_theme_constant_override("h_separation", 6)
	_armory_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_armory_grid)

	# --- SUBTAB B: ATTACHMENTS & PBR CAMO ---
	var pan_gun := VBoxContainer.new()
	pan_gun.add_theme_constant_override("separation", 6)
	pan_gun.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pan_gun.visible = false
	v.add_child(pan_gun)
	_armory_subtab_panels["gunsmith"] = pan_gun

	_armory_att_head = _label("ATTACHMENTS (SELECT UP TO 3)", 11, CYAN)
	_section_header(pan_gun, "RAIL & MUZZLE MODIFICATIONS", _armory_att_head)
	var att_grid := GridContainer.new()
	att_grid.columns = 4
	att_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	att_grid.add_theme_constant_override("h_separation", 6)
	att_grid.add_theme_constant_override("v_separation", 6)
	pan_gun.add_child(att_grid)
	_armory_att_btns.clear()
	for aid in ["red_dot", "suppressor", "tac_laser", "ext_mag", "fmj", "heavy_barrel", "quickdraw", "overpressured"]:
		var info: Dictionary = GameState.WEAPON_ATTACHMENTS[aid]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 56)
		var av := VBoxContainer.new()
		av.add_theme_constant_override("separation", 1)
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(av)
		var top_a := HBoxContainer.new()
		top_a.add_theme_constant_override("separation", 4)
		top_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av.add_child(top_a)
		var tag_l := _label(String(info["tag"]), 11, Color.WHITE)
		tag_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_a.add_child(tag_l)
		var slot_l := _label(String(info.get("slot", "MOD")).to_upper(), 9, DIM)
		top_a.add_child(slot_l)
		var nm_l := _label(String(info.get("name", aid)), 9, Color(0.76, 0.82, 0.88))
		nm_l.clip_text = true
		av.add_child(nm_l)
		var bn_l := _label(String(info.get("desc", "")), 8, CYAN)
		bn_l.clip_text = true
		av.add_child(bn_l)

		var ab := Button.new()
		ab.flat = true
		ab.focus_mode = Control.FOCUS_NONE
		ab.set_anchors_preset(Control.PRESET_FULL_RECT)
		ab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var a_cap: String = aid
		ab.pressed.connect(func(): _toggle_loadout_attachment(a_cap))
		ab.mouse_entered.connect(func():
			_armory_att_hover = a_cap
			var ls_h := GameState.get_active_loadout()
			var on_p := _armory_slot == "primary"
			_update_armory_telemetry(String(ls_h.get("primary" if on_p else "secondary", "m4_carbine")), ls_h.get("attachments" if on_p else "sec_attachments", [])))
		ab.mouse_exited.connect(func():
			if _armory_att_hover == a_cap:
				_armory_att_hover = ""
				var ls_h := GameState.get_active_loadout()
				var on_p := _armory_slot == "primary"
				_update_armory_telemetry(String(ls_h.get("primary" if on_p else "secondary", "m4_carbine")), ls_h.get("attachments" if on_p else "sec_attachments", [])))
		card.add_child(ab)
		att_grid.add_child(card)
		_armory_att_btns[aid] = {"card": card, "btn": ab, "tag": tag_l, "bn": bn_l}

	_section_header(pan_gun, "PBR WEAPON FINISH / CAMO (APPLIES IN 3D MENU & GAMEPLAY)")
	var camo_grid := GridContainer.new()
	camo_grid.columns = 4
	camo_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camo_grid.add_theme_constant_override("h_separation", 6)
	camo_grid.add_theme_constant_override("v_separation", 6)
	pan_gun.add_child(camo_grid)
	_armory_camo_btns.clear()
	for cid in GameState.WEAPON_CAMO_ORDER:
		var cinfo: Dictionary = GameState.WEAPON_CAMOS[cid]
		var ccard := PanelContainer.new()
		ccard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ccard.custom_minimum_size = Vector2(0, 56)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 3)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ccard.add_child(cv)
		var sw := TextureRect.new()
		sw.texture = MPG.camo_swatch(cid)
		sw.custom_minimum_size = Vector2(0, 26)
		sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sw.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(sw)
		var clbl := _label(String(cinfo.get("name", cid.to_upper())).to_upper(), 9, Color.WHITE)
		clbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		clbl.clip_text = true
		cv.add_child(clbl)

		var cbtn := Button.new()
		cbtn.flat = true
		cbtn.focus_mode = Control.FOCUS_NONE
		cbtn.set_anchors_preset(Control.PRESET_FULL_RECT)
		cbtn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var c_cap: String = cid
		cbtn.pressed.connect(func(): _select_armory_camo(c_cap))
		ccard.add_child(cbtn)
		camo_grid.add_child(ccard)
		_armory_camo_btns[cid] = {"card": ccard, "label": clbl}

	# --- SUBTAB C: ORDNANCE & FIELD PERKS ---
	var pan_eq := VBoxContainer.new()
	pan_eq.add_theme_constant_override("separation", 7)
	pan_eq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pan_eq.visible = false
	v.add_child(pan_eq)
	_armory_subtab_panels["equipment"] = pan_eq

	_section_header(pan_eq, "[G] LETHAL ORDNANCE")
	var let_row := HBoxContainer.new()
	let_row.add_theme_constant_override("separation", 6)
	pan_eq.add_child(let_row)
	_armory_let_btns.clear()
	for lid in ["frag", "semtex", "thermite", "impact"]:
		var lc: Dictionary = GameState.LETHALS[lid]
		var lb := Button.new()
		lb.text = "%s\n%s" % [String(lc["short"]), String(lc.get("desc", "")).substr(0, 26)]
		lb.custom_minimum_size = Vector2(0, 48)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.add_theme_font_size_override("font_size", 10)
		lb.focus_mode = Control.FOCUS_NONE
		var l_cap: String = lid
		lb.pressed.connect(func():
			var d := GameState.get_active_loadout().duplicate(true)
			d["lethal"] = l_cap
			GameState.update_loadout(GameState.active_loadout_index, d)
			_sfx("hit_tick", -10.0, 1.15)
			_refresh_loadouts())
		let_row.add_child(lb)
		_armory_let_btns[lid] = lb

	_section_header(pan_eq, "[4] TACTICAL GEAR")
	var tac_row := HBoxContainer.new()
	tac_row.add_theme_constant_override("separation", 6)
	pan_eq.add_child(tac_row)
	_armory_tac_btns.clear()
	for tid in ["flashbang", "smoke", "concussion", "stim"]:
		var tc: Dictionary = GameState.TACTICALS[tid]
		var tb := Button.new()
		tb.text = "%s\n%s" % [String(tc["short"]), String(tc.get("desc", "")).substr(0, 26)]
		tb.custom_minimum_size = Vector2(0, 48)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.add_theme_font_size_override("font_size", 10)
		tb.focus_mode = Control.FOCUS_NONE
		var t_cap: String = tid
		tb.pressed.connect(func():
			var d := GameState.get_active_loadout().duplicate(true)
			d["tactical"] = t_cap
			GameState.update_loadout(GameState.active_loadout_index, d)
			_sfx("hit_tick", -10.0, 1.25)
			_refresh_loadouts())
		tac_row.add_child(tb)
		_armory_tac_btns[tid] = tb

	_section_header(pan_eq, "FIELD PERK & DEPLOY")
	var prk_row := GridContainer.new()
	prk_row.columns = 2
	prk_row.add_theme_constant_override("h_separation", 6)
	prk_row.add_theme_constant_override("v_separation", 6)
	pan_eq.add_child(prk_row)
	_armory_perk_btns.clear()
	for pid in ["fast_hands", "flak_jacket", "scavenger", "tactical_mask"]:
		var pc: Dictionary = GameState.FIELD_PERKS[pid]
		var pb := Button.new()
		pb.text = "%s — %s" % [String(pc["short"]), String(pc.get("desc", ""))]
		pb.custom_minimum_size = Vector2(0, 42)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.add_theme_font_size_override("font_size", 10)
		pb.focus_mode = Control.FOCUS_NONE
		var p_cap: String = pid
		pb.pressed.connect(func():
			var d := GameState.get_active_loadout().duplicate(true)
			d["perk"] = p_cap
			GameState.update_loadout(GameState.active_loadout_index, d)
			_sfx("hit_tick", -10.0, 1.3)
			_refresh_loadouts())
		prk_row.add_child(pb)
		_armory_perk_btns[pid] = pb

	var go_mp := Button.new()
	go_mp.text = "TAKE THIS CLASS TO PVP MULTIPLAYER ->"
	go_mp.custom_minimum_size = Vector2(0, 34)
	go_mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go_mp.add_theme_font_size_override("font_size", 11)
	go_mp.focus_mode = Control.FOCUS_NONE
	go_mp.add_theme_stylebox_override("normal", _box(Color(0.56, 0.12, 0.12), Color(1.0, 0.45, 0.35), 1, 0, 4, 8, 4))
	go_mp.pressed.connect(func(): _show_page("multiplayer"))
	pan_eq.add_child(go_mp)

	# 4) Persistent Weapon Telemetry Card (2-column wide stat bars — never crushed)
	var tel := PanelContainer.new()
	tel.add_theme_stylebox_override("panel", _box(Color(0.03, 0.04, 0.06, 0.90), Color(1, 1, 1, 0.11), 1, 0, 5, 10, 8))
	v.add_child(tel)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	tel.add_child(tv)

	var thead := HBoxContainer.new()
	thead.add_theme_constant_override("separation", 8)
	tv.add_child(thead)
	_armory_preview_lbl = _label("", 13, CYAN)
	_armory_preview_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thead.add_child(_armory_preview_lbl)
	_armory_fire_mode_lbl = _label("", 10, GOLD)
	thead.add_child(_armory_fire_mode_lbl)

	_armory_desc_lbl = _label("", 10, Color(0.75, 0.80, 0.86))
	_armory_desc_lbl.clip_text = true
	_armory_desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(_armory_desc_lbl)

	var sgrid := GridContainer.new()
	sgrid.columns = 2
	sgrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sgrid.add_theme_constant_override("h_separation", 14)
	sgrid.add_theme_constant_override("v_separation", 5)
	tv.add_child(sgrid)
	_armory_stat_bars.clear()
	_armory_stat_vals.clear()
	for skey in [
		["dmg", "DMG", ACCENT],
		["rof", "ROF", GOLD],
		["rng", "RNG", CYAN],
		["ctrl", "CTRL", GREEN],
		["mob", "MOB", Color(0.68, 0.45, 0.96)],
		["rel", "RELOAD", AMBER],
	]:
		var p_pair: Array = _stat_bar(sgrid, String(skey[1]), 0.5, skey[2])
		(p_pair[0] as ProgressBar).custom_minimum_size = Vector2(120, 8)
		(p_pair[1] as Label).custom_minimum_size = Vector2(64, 0)
		_armory_stat_bars[String(skey[0])] = p_pair[0]
		_armory_stat_vals[String(skey[0])] = p_pair[1]

	v.visible = false
	return v


func _build_armory_slot_card(tag_txt: String, is_primary: bool) -> Array:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(0, 62)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var t_lbl := _label(tag_txt, 9, DIM)
	t_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t_lbl)
	var name_lbl := _label("", 13, Color.WHITE)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_lbl)
	var sub_lbl := _label("", 10, CYAN)
	sub_lbl.clip_text = true
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sub_lbl)

	var sil := TextureRect.new()
	sil.custom_minimum_size = Vector2(92, 34)
	sil.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sil)

	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.pressed.connect(func():
		_armory_slot = "primary" if is_primary else "secondary"
		_armory_cat_filter = "all"
		_sfx("hit_tick", -12.0, 1.1)
		_refresh_loadouts())
	p.add_child(hit)
	return [p, name_lbl, sub_lbl, sil]


func _set_armory_subtab(tid: String) -> void:
	_armory_subtab = tid
	_armory_att_hover = ""
	_sfx("hit_tick", -14.0, 1.25)
	_refresh_loadouts()


func _select_armory_camo(cid: String) -> void:
	var d := GameState.get_active_loadout().duplicate(true)
	if _armory_slot == "primary":
		d["pri_camo"] = cid
	else:
		d["sec_camo"] = cid
	GameState.update_loadout(GameState.active_loadout_index, d)
	_sfx("buy_ching", -12.0, 1.35)
	_refresh_loadouts()


func _commit_loadout_name(txt: String) -> void:
	var clean := txt.strip_edges().to_upper()
	if clean == "":
		return
	var d := GameState.get_active_loadout().duplicate(true)
	if String(d.get("name", "")) != clean:
		d["name"] = clean
		GameState.update_loadout(GameState.active_loadout_index, d)
		_refresh_loadouts()


func _toggle_loadout_attachment(aid: String) -> void:
	var d := GameState.get_active_loadout().duplicate(true)
	var on_pri := _armory_slot == "primary"
	var w_id := String(d.get("primary" if on_pri else "secondary", "m4_carbine"))
	if not GameState.is_attachment_allowed(w_id, aid):
		return
	var key := "attachments" if on_pri else "sec_attachments"
	var max_mods := 3 if on_pri else 2
	var atts: Array = d.get(key, []).duplicate()
	var idx := atts.find(aid)
	if idx >= 0:
		atts.remove_at(idx)
	else:
		if atts.size() >= max_mods:
			atts.remove_at(0)
		atts.append(aid)
	d[key] = atts
	GameState.update_loadout(GameState.active_loadout_index, d)
	_sfx("hit_tick", -10.0, 1.25)
	_refresh_loadouts()


func _weapon_fire_mode(wc: Dictionary) -> String:
	if String(wc.get("projectile", "")) == "rocket":
		return "ROCKET"
	if int(wc.get("burst_count", 1)) > 1:
		return "%d-BURST" % int(wc.get("burst_count", 1))
	if bool(wc.get("auto", false)):
		return "AUTO"
	var wcls := String(wc.get("class", ""))
	if wcls == "shotgun":
		return "PUMP"
	if wcls == "sniper":
		return "BOLT"
	return "SEMI"


func _refresh_loadouts() -> void:
	if _armory_grid == null or not is_instance_valid(_armory_grid):
		return
	var on_pri := _armory_slot == "primary"
	var slot_accent := CYAN if on_pri else AMBER
	_apply_diorama_mode(false)
	_update_nav_styles()
	if is_instance_valid(_header_stripe):
		_header_stripe.color = slot_accent
	if is_instance_valid(_header_icon):
		_header_icon.modulate = slot_accent
	if is_instance_valid(_panel):
		var pst := _box(Color(0.022, 0.028, 0.040, 0.93), slot_accent, 1, 0, 6, 20, 14)
		pst.border_width_top = 3
		_panel.add_theme_stylebox_override("panel", pst)

	var ls: Dictionary = GameState.get_active_loadout()
	for i in range(_armory_set_btns.size()):
		var on := i == GameState.active_loadout_index
		var l_i := GameState.get_loadout(i)
		var short_w := String(GameState.WEAPONS.get(String(l_i.get("primary", "")), {}).get("name", "")).split(" ")[0]
		_armory_set_btns[i].text = "SET %d · %s" % [i + 1, short_w]
		_style_btn(_armory_set_btns[i], on, CYAN, Color(0.06, 0.075, 0.10, 0.92), 6, 2)
	if is_instance_valid(_armory_name_edit) and not _armory_name_edit.has_focus():
		_armory_name_edit.text = String(ls.get("name", "CUSTOM CLASS"))

	var pri_id := String(ls.get("primary", "m4_carbine"))
	var sec_id := String(ls.get("secondary", "rpg7"))
	var pri_cfg: Dictionary = GameState.WEAPONS.get(pri_id, {})
	var sec_cfg: Dictionary = GameState.WEAPONS.get(sec_id, {})
	var pri_atts: Array = ls.get("attachments", [])
	var sec_atts: Array = ls.get("sec_attachments", [])
	var pri_camo := String(ls.get("pri_camo", "factory"))
	var sec_camo := String(ls.get("sec_camo", "factory"))

	_armory_pri_lbl.text = String(pri_cfg.get("name", pri_id.to_upper()))
	var pri_tags := GameState.format_attachment_tags(pri_atts)
	var pri_cname := String(WeaponCatalog.WEAPON_CAMOS.get(pri_camo, {}).get("name", "Factory"))
	_armory_pri_sub.text = "%s · %s%s" % [String(WeaponCatalog.CLASS_LABELS.get(String(pri_cfg.get("class", "")), "RIFLE")), pri_cname.to_upper(), (" " + pri_tags) if pri_tags != "" else ""]
	_armory_pri_sil.texture = MPG.weapon_silhouette(pri_id, pri_cfg, CYAN if on_pri else DIM)

	_armory_sec_lbl.text = String(sec_cfg.get("name", sec_id.to_upper()))
	var sec_tags := GameState.format_attachment_tags(sec_atts)
	var sec_cname := String(WeaponCatalog.WEAPON_CAMOS.get(sec_camo, {}).get("name", "Factory"))
	_armory_sec_sub.text = "%s · %s%s" % [String(WeaponCatalog.CLASS_LABELS.get(String(sec_cfg.get("class", "")), "PISTOL")), sec_cname.to_upper(), (" " + sec_tags) if sec_tags != "" else ""]
	_armory_sec_sil.texture = MPG.weapon_silhouette(sec_id, sec_cfg, AMBER if not on_pri else DIM)

	_armory_pri_card.add_theme_stylebox_override("panel", _box(CYAN.darkened(0.76) if on_pri else Color(1, 1, 1, 0.04), CYAN if on_pri else Color(1, 1, 1, 0.10), 2 if on_pri else 1, 0, 4, 8, 5))
	_armory_sec_card.add_theme_stylebox_override("panel", _box(AMBER.darkened(0.76) if not on_pri else Color(1, 1, 1, 0.04), AMBER if not on_pri else Color(1, 1, 1, 0.10), 2 if not on_pri else 1, 0, 4, 8, 5))

	for tid in _armory_subtab_btns.keys():
		var active_t := String(tid) == _armory_subtab
		_style_btn(_armory_subtab_btns[tid] as Button, active_t, slot_accent, Color(0.06, 0.075, 0.10, 0.92), 8, 3)
		if _armory_subtab_panels.has(tid):
			(_armory_subtab_panels[tid] as Control).visible = active_t

	var show_id := pri_id if on_pri else sec_id
	var show_atts := pri_atts if on_pri else sec_atts
	var show_camo := pri_camo if on_pri else sec_camo
	var max_mods := 3 if on_pri else 2

	if is_instance_valid(_armory_att_head):
		_armory_att_head.text = "%s MODS (%d / %d)" % ["PRIMARY" if on_pri else "SECONDARY", show_atts.size(), max_mods]
		_armory_att_head.add_theme_color_override("font_color", slot_accent)

	for aid in _armory_att_btns.keys():
		var entry: Dictionary = _armory_att_btns[aid]
		var acard := entry["card"] as PanelContainer
		var abtn := entry["btn"] as Button
		var atag := entry["tag"] as Label
		var abn := entry["bn"] as Label
		var active: bool = (String(aid) in show_atts)
		var allowed: bool = GameState.is_attachment_allowed(show_id, String(aid))
		abtn.disabled = not allowed
		acard.modulate.a = 1.0 if allowed else 0.42
		acard.add_theme_stylebox_override("panel", _box(slot_accent.darkened(0.72) if active else Color(0.055, 0.070, 0.095, 0.92), slot_accent if active else Color(1, 1, 1, 0.10), 2 if active else 1, 0, 4, 8, 5))
		atag.add_theme_color_override("font_color", Color.WHITE if active else slot_accent)
		abn.add_theme_color_override("font_color", GOLD if active else Color(0.68, 0.76, 0.84))

	for cid in _armory_camo_btns.keys():
		var centry: Dictionary = _armory_camo_btns[cid]
		var ccard := centry["card"] as PanelContainer
		var clbl := centry["label"] as Label
		var c_on := String(cid) == show_camo
		ccard.add_theme_stylebox_override("panel", _box(slot_accent.darkened(0.74) if c_on else Color(0.055, 0.070, 0.095, 0.92), slot_accent if c_on else Color(1, 1, 1, 0.12), 2 if c_on else 1, 0, 4, 6, 5))
		clbl.add_theme_color_override("font_color", slot_accent if c_on else Color(0.84, 0.88, 0.92))

	for lid in _armory_let_btns.keys():
		var lb := _armory_let_btns[lid] as Button
		var on := String(lid) == String(ls.get("lethal", "frag"))
		_style_btn(lb, on, AMBER, Color(0.06, 0.075, 0.10, 0.92), 6, 4)
	for tid in _armory_tac_btns.keys():
		var tb := _armory_tac_btns[tid] as Button
		var on := String(tid) == String(ls.get("tactical", "flashbang"))
		_style_btn(tb, on, CYAN, Color(0.06, 0.075, 0.10, 0.92), 6, 4)
	for pid in _armory_perk_btns.keys():
		var pb := _armory_perk_btns[pid] as Button
		var on := String(pid) == String(ls.get("perk", "fast_hands"))
		_style_btn(pb, on, GOLD, Color(0.06, 0.075, 0.10, 0.92), 6, 4)

	for cid in _armory_cat_btns.keys():
		var cb := _armory_cat_btns[cid] as Button
		var c_str := String(cid)
		var slot_has := c_str == "all"
		if not slot_has:
			for wid in GameState.WEAPONS:
				var valid := GameState.is_valid_primary(wid) if on_pri else GameState.is_valid_secondary(wid)
				if valid and String(GameState.WEAPONS[wid].get("class", "")) == c_str:
					slot_has = true
					break
		cb.visible = slot_has
		var c_on := c_str == _armory_cat_filter
		_style_btn(cb, c_on, slot_accent, Color(0.06, 0.075, 0.10, 0.92), 4, 2)

	_rebuild_armory_grid(pri_id, sec_id, on_pri)
	_update_armory_telemetry(show_id, show_atts)
	_rebuild_gunsmith_weapon(show_id, show_atts, show_camo)
	_update_stage_mode()
	_update_left_hud_for_page()


func _rebuild_armory_grid(pri_id: String, sec_id: String, on_pri: bool) -> void:
	for c in _armory_grid.get_children():
		c.queue_free()
	var equipped_id := pri_id if on_pri else sec_id
	var order: Array[String] = []
	for cls in WeaponCatalog.CLASS_ORDER:
		for wid in GameState.WEAPONS:
			var valid := GameState.is_valid_primary(wid) if on_pri else GameState.is_valid_secondary(wid)
			if not valid:
				continue
			var wcls := String(GameState.WEAPONS[wid].get("class", ""))
			if wcls != cls:
				continue
			if _armory_cat_filter != "all" and wcls != _armory_cat_filter:
				continue
			order.append(wid)

	var slot_accent := CYAN if on_pri else AMBER
	for wid in order:
		var wc: Dictionary = GameState.WEAPONS[wid]
		var wcls := String(wc.get("class", "rifle"))
		var is_eq := wid == equipped_id
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 62)
		card.add_theme_stylebox_override("panel", _box(slot_accent.darkened(0.76) if is_eq else Color(0.055, 0.070, 0.095, 0.92), slot_accent if is_eq else Color(1, 1, 1, 0.10), 2 if is_eq else 1, 0, 4, 8, 5))

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hb)

		var sil := TextureRect.new()
		sil.texture = MPG.weapon_silhouette(wid, wc, slot_accent if is_eq else Color(0.65, 0.72, 0.80))
		sil.custom_minimum_size = Vector2(96, 36)
		sil.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(sil)

		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vb.add_theme_constant_override("separation", 1)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(vb)

		var nl := _label(String(wc["name"]), 11, Color.WHITE if is_eq else Color(0.88, 0.92, 0.96))
		nl.clip_text = true
		vb.add_child(nl)
		var rpm := int(roundf(60.0 / maxf(0.04, float(wc.get("fire_rate", 0.2)))))
		var mag := int(wc.get("mag_size", 30))
		var sl := _label("%s · %s · %d MAG · %d RPM" % [String(WeaponCatalog.CLASS_LABELS.get(wcls, wcls.to_upper())), _weapon_fire_mode(wc), mag, rpm], 9, slot_accent if is_eq else DIM)
		sl.clip_text = true
		vb.add_child(sl)

		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.set_anchors_preset(Control.PRESET_FULL_RECT)
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var w_cap: String = wid
		hit.pressed.connect(func():
			var d := GameState.get_active_loadout().duplicate(true)
			if on_pri:
				d["primary"] = w_cap
			else:
				d["secondary"] = w_cap
			GameState.update_loadout(GameState.active_loadout_index, d)
			_sfx("weapon_swap", -8.0, 1.05)
			_refresh_loadouts())
		card.add_child(hit)
		_armory_grid.add_child(card)


func _calc_armory_stats(wc: Dictionary, w_id: String, atts: Array) -> Dictionary:
	var pvp_d: float = float(GameState.PVP_WEAPON_DAMAGE.get(w_id, 30.0)) * maxf(1.0, float(wc.get("pellets", 1)) * 0.45)
	var dmg_k := 1.0
	var spr_k := 1.0
	var rec_k := 1.0
	var rng_k := 1.0
	var rel_k := 1.0
	var ads_k := 1.0
	for a in atts:
		var ai: Dictionary = GameState.WEAPON_ATTACHMENTS.get(String(a), {})
		dmg_k *= float(ai.get("dmg", 1.0))
		spr_k *= float(ai.get("spread", 1.0))
		rec_k *= float(ai.get("recoil", 1.0))
		rng_k *= float(ai.get("range", 1.0))
		rel_k *= float(ai.get("reload", 1.0))
		ads_k *= float(ai.get("ads_speed", 1.0))
	var dmg_n := clampf(pow((pvp_d * dmg_k) / 115.0, 0.62), 0.14, 1.0)
	var rof_n := clampf(0.11 / maxf(0.045, float(wc.get("fire_rate", 0.15))), 0.08, 1.0)
	var rng_n := clampf((float(wc.get("range", 70.0)) * rng_k) / 150.0, 0.12, 1.0)
	var ctrl_n := clampf(1.0 - ((float(wc.get("recoil_pitch", 1.5)) * rec_k + float(wc.get("spread_deg", 2.0)) * spr_k * 0.35) / 8.5), 0.10, 1.0)
	var mob_n := clampf(((float(wc.get("move_mult", 0.96)) * clampf(ads_k, 0.80, 1.25)) - 0.68) / 0.56, 0.12, 1.0)
	var rel_t := maxf(0.55, float(wc.get("reload_time", 2.0)) * rel_k)
	var rel_n := clampf(1.0 - ((rel_t - 0.85) / 3.4), 0.10, 1.0)
	return {"dmg": dmg_n, "rof": rof_n, "rng": rng_n, "ctrl": ctrl_n, "mob": mob_n, "rel": rel_n}


func _update_armory_telemetry(w_id: String, atts: Array) -> void:
	var wc: Dictionary = GameState.WEAPONS.get(w_id, {})
	if wc.is_empty():
		return
	var base_vals := _calc_armory_stats(wc, w_id, [])
	var preview_atts := atts.duplicate()
	if _armory_att_hover != "" and GameState.is_attachment_allowed(w_id, _armory_att_hover):
		if _armory_att_hover in preview_atts:
			preview_atts.erase(_armory_att_hover)
		else:
			preview_atts.append(_armory_att_hover)
	var cur_vals := _calc_armory_stats(wc, w_id, preview_atts)

	for k in cur_vals.keys():
		var v_now := float(cur_vals[k])
		var v_base := float(base_vals[k])
		var pts_now := roundi(v_now * 100.0)
		var pts_delta := pts_now - roundi(v_base * 100.0)
		if _armory_stat_bars.has(k):
			(_armory_stat_bars[k] as ProgressBar).value = v_now
		if _armory_stat_vals.has(k):
			var lbl := _armory_stat_vals[k] as Label
			if pts_delta != 0:
				lbl.text = "%d (%+d)" % [pts_now, pts_delta]
				lbl.add_theme_color_override("font_color", GREEN if pts_delta > 0 else ACCENT)
			else:
				lbl.text = "%d" % pts_now
				lbl.add_theme_color_override("font_color", Color(0.86, 0.90, 0.95))

	var mag_mult := 1.4 if ("ext_mag" in preview_atts) else 1.0
	var mag_sz := maxi(1, roundi(float(wc.get("mag_size", 30)) * mag_mult))
	var res_sz := roundi(float(wc.get("reserve_max", 120)) * mag_mult)
	var rpm := int(roundf(60.0 / maxf(0.04, float(wc.get("fire_rate", 0.2)))))
	_armory_preview_lbl.text = "%s  ·  %d / %d AMMO" % [String(wc.get("name", w_id)), mag_sz, res_sz]
	if is_instance_valid(_armory_fire_mode_lbl):
		_armory_fire_mode_lbl.text = "%s · %d RPM" % [_weapon_fire_mode(wc), rpm]
	_armory_desc_lbl.text = String(wc.get("desc", ""))
