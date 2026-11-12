class_name GameHUD
extends CanvasLayer
# In-match HUD. Icon-first tactical kit: every readout is a glyph + number rather
# than a sentence. All gameplay logic (signals, pause, scoreboard, commander /
# boss tracking, exfil, downed, borrowed skills) is unchanged from the original;
# only the presentation layer was rebuilt around HudIcons.

const HI := preload("res://scripts/ui/hud_icons.gd")
const TallyMarksScript := preload("res://scripts/ui/tally_marks.gd")
const AugmentMenuScript := preload("res://scripts/ui/augment_menu.gd")

var player: PlayerController
var wave_mgr: WaveManager

# Overlays
var blood_overlay: TextureRect
var monster_overlay: TextureRect

# Top boss & wave UI
var boss_panel: PanelContainer
var boss_title_lbl: Label
var boss_sub_lbl: Label
var boss_hp_bar: ProgressBar
var boss_status_box: HBoxContainer
var boss_hp_lbl: Label
var hostiles_panel: PanelContainer
var hostiles_icon: TextureRect
var hostiles_lbl: Label
var hostiles_boss: TextureRect
var banner_lbl: Label
var banner_timer: float = 0.0

# Center crosshair & prompts
var crosshair_root: Control
var hit_canvas: Control
var streak_icon: TextureRect
var streak_lbl: Label
var sub_lbl: Label
var _tick_cd: float = 0.0
var hitmarker_timer: float = 0.0
var hitmarker_color: Color = Color.WHITE
var hitmarker_big: bool = false
var interact_box: HBoxContainer
var interact_key: PanelContainer
var interact_icon: TextureRect
var interact_lbl: Label
var ammo_hint_box: HBoxContainer
var ammo_hint_icon: TextureRect
var ammo_hint_key: PanelContainer
var ammo_hint_lbl: Label

# Damage direction arcs
var dmg_canvas: Control
var dmg_indicators: Array = []

# Power-ups (top-right under hostiles)
var powerups_box: VBoxContainer
var _power_sig: String = ""

# Bottom-left round / points / vitals
var tally_marks: Control
var round_sub_lbl: Label
var points_lbl: Label
var points_popup_lbl: Label
var points_popup_timer: float = 0.0
var hp_bar: ProgressBar
var hp_lbl: Label
var shield_bar: ProgressBar
var shield_row: HBoxContainer
var stamina_bar: ProgressBar
var perks_box: HBoxContainer
var _perk_sig: String = ""
var revive_row: HBoxContainer
var revive_lbl: Label

# Bottom-right weapon & skills
var weapon_icon: TextureRect
var weapon_name_lbl: Label
var reload_icon: TextureRect
var ammo_lbl: Label
var reserve_lbl: Label
var grenade_lbl: Label
var loadout_box: HBoxContainer
var _loadout_sig: String = ""
var tile_q: Dictionary
var tile_f: Dictionary
var tile_x: Dictionary
var tile_z: Dictionary
var tile_t: Dictionary
var tile_b: Dictionary

# Pause & game over modal
var modal_overlay: ColorRect
var modal_icon: TextureRect
var modal_title: Label
var modal_tiles: HBoxContainer
var modal_stats: Label
var resume_btn: Button
var settings_box: Control
var is_paused: bool = false

var augment_menu: Control
var cross_ticks: Array[ColorRect] = []
var scope_canvas: Control
var minimap: Control

# Extraction / last stand
var exfil_box: HBoxContainer
var exfil_lbl: Label
var downed_box: VBoxContainer
var downed_sub: Label
var downed_bar: ProgressBar

var fps_lbl: Label
var score_panel: PanelContainer
var score_title: Label
var score_grid: GridContainer
var score_summary: Label
var _score_t: float = 0.0

# Objectives
var event_box: HBoxContainer
var event_lbl: Label
var challenge_box: HBoxContainer
var challenge_lbl: Label
var _challenge: Node

# Commander bar
var cmd_panel: PanelContainer
var cmd_pips: HBoxContainer
var cmd_title: Label
var cmd_bar: ProgressBar
var cmd_icon: TextureRect
var cmd_status: Label
var _cmd_fill: StyleBoxFlat
var _cmd_border: StyleBoxFlat
var _cmd_t: float = 0.0


func setup(p_player: PlayerController, p_wave: WaveManager) -> void:
	player = p_player
	wave_mgr = p_wave
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	_build_fps()
	_build_ui()
	_build_commander_bar()
	_build_objectives()
	_build_scoreboard()
	flash_lbl = Label.new()
	flash_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	flash_lbl.offset_left = -200
	flash_lbl.offset_right = 200
	flash_lbl.offset_top = -34
	flash_lbl.offset_bottom = -10
	flash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash_lbl.add_theme_font_size_override("font_size", 14)
	flash_lbl.add_theme_constant_override("outline_size", 6)
	flash_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	flash_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_lbl)
	move_child(flash_lbl, 1)
	minimap = (load("res://scripts/ui/minimap.gd") as GDScript).new()
	minimap.name = "Minimap"
	add_child(minimap)
	minimap.setup(player, get_tree().get_first_node_in_group("arena"), wave_mgr)
	_build_downed_overlay()
	_build_exfil_label()
	_connect_signals()
	_refresh_all()


func _build_fps() -> void:
	var box := HBoxContainer.new()
	box.position = Vector2(12, 8)
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.add_child(HI.icon("gauge", 14, HI.GREEN))
	fps_lbl = HI.label("", 13, HI.GREEN)
	box.add_child(fps_lbl)


# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------
func _panel(bg: Color, border: Color, corner: int = 5, bw: int = 1, margin: int = 10) -> StyleBoxFlat:
	return HI.panel(bg, border, corner, bw, margin)


func _bar(col: Color, corner: int = 3) -> StyleBoxFlat:
	return HI.bar(col, corner)


func _chip(parent: Node, icon_name: String, col: Color, px: float = 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(HI.icon(icon_name, px, col))
	parent.add_child(h)
	return h


# ---------------------------------------------------------------------------
# Downed / exfil
# ---------------------------------------------------------------------------
func _build_downed_overlay() -> void:
	downed_box = VBoxContainer.new()
	downed_box.anchor_left = 0.5
	downed_box.anchor_right = 0.5
	downed_box.anchor_top = 0.5
	downed_box.anchor_bottom = 0.5
	downed_box.offset_left = -260
	downed_box.offset_right = 260
	downed_box.offset_top = 70
	downed_box.offset_bottom = 190
	downed_box.alignment = BoxContainer.ALIGNMENT_CENTER
	downed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	downed_box.visible = false
	add_child(downed_box)
	var hr := HBoxContainer.new()
	hr.alignment = BoxContainer.ALIGNMENT_CENTER
	hr.add_theme_constant_override("separation", 10)
	downed_box.add_child(hr)
	hr.add_child(HI.icon("cross", 34, HI.RED))
	var title := HI.label("DOWNED", 42, HI.RED)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0, 0))
	hr.add_child(title)
	downed_sub = HI.label("", 16, HI.TEXT)
	downed_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	downed_box.add_child(downed_sub)
	downed_bar = ProgressBar.new()
	downed_bar.custom_minimum_size = Vector2(0, 8)
	downed_bar.max_value = 1.0
	downed_bar.show_percentage = false
	downed_bar.add_theme_stylebox_override("background", _bar(Color(0.15, 0.05, 0.05)))
	downed_bar.add_theme_stylebox_override("fill", _bar(HI.GREEN))
	downed_box.add_child(downed_bar)


func _build_exfil_label() -> void:
	exfil_box = HBoxContainer.new()
	exfil_box.anchor_left = 0.5
	exfil_box.anchor_right = 0.5
	exfil_box.offset_left = -360
	exfil_box.offset_right = 360
	exfil_box.offset_top = 196
	exfil_box.offset_bottom = 240
	exfil_box.alignment = BoxContainer.ALIGNMENT_CENTER
	exfil_box.add_theme_constant_override("separation", 10)
	exfil_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	exfil_box.visible = false
	add_child(exfil_box)
	exfil_box.add_child(HI.icon("chopper", 26, HI.GREEN))
	exfil_lbl = HI.label("", 24, HI.AMBER)
	exfil_lbl.add_theme_constant_override("outline_size", 6)
	exfil_lbl.add_theme_color_override("font_outline_color", Color(0.05, 0, 0))
	exfil_box.add_child(exfil_lbl)


func _update_exfil_label() -> void:
	var st: int = wave_mgr.exfil_state
	exfil_box.visible = st == 1 or st == 2
	if st == 1:
		var tl := maxf(0.0, wave_mgr.exfil_timer)
		exfil_lbl.text = "EXTRACTION INBOUND  %d:%02d" % [int(tl) / 60, int(tl) % 60]
		exfil_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.25))
	elif st == 2:
		var tl2 := maxf(0.0, wave_mgr.exfil_timer)
		var pct := int(wave_mgr.board_progress * 100.0)
		var tail := ("   BOARDING %d%%" % pct) if pct > 0 else ""
		exfil_lbl.text = "GET TO THE LADDER!  %d:%02d%s" % [int(tl2) / 60, int(tl2) % 60, tail]
		exfil_lbl.add_theme_color_override("font_color", HI.GREEN if pct > 0 else Color(1.0, 0.85, 0.3))


func _on_exfil_won() -> void:
	if augment_menu:
		augment_menu.close()
	scope_canvas.visible = false
	_set_interact("")
	ammo_hint_box.visible = false
	downed_box.visible = false
	await get_tree().create_timer(3.6).timeout
	_show_modal("chopper", "EXFIL SUCCESSFUL", HI.GREEN,
		[GameState.current_round, GameState.total_kills, GameState.headshots, GameState.bosses_slain],
		"ESCAPED NACHT-7  •  EXTRACTIONS %d\n\n%s" % [GameState.exfils, GameState.finish_run("exfil")])


func _on_run_won() -> void:
	if augment_menu:
		augment_menu.close()
	scope_canvas.visible = false
	_set_interact("")
	downed_box.visible = false
	await get_tree().create_timer(2.5).timeout
	_show_modal("star", "OUTBREAK CONTAINED", HI.AMBER,
		[GameState.current_round, GameState.total_kills, GameState.headshots, GameState.bosses_slain],
		"THE PROGENITOR IS DEAD. NACHT-7 IS SILENT.\n\n%s" % GameState.finish_run("victory"))


func _on_downed_changed(downed: bool) -> void:
	downed_box.visible = downed
	scope_canvas.visible = false
	_refresh_stats_line()


# ---------------------------------------------------------------------------
# Main HUD build
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	blood_overlay = TextureRect.new()
	blood_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	blood_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blood_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/textures/blood_vignette.png"):
		blood_overlay.texture = load("res://assets/textures/blood_vignette.png")
	blood_overlay.modulate.a = 0.0
	root.add_child(blood_overlay)

	monster_overlay = TextureRect.new()
	monster_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	monster_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	monster_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/textures/monster_vignette.png"):
		monster_overlay.texture = load("res://assets/textures/monster_vignette.png")
	monster_overlay.modulate.a = 0.0
	root.add_child(monster_overlay)

	_build_top_right(root)
	_build_boss_bar(root)
	_build_center(root)
	_build_bottom_left(root)
	_build_bottom_right(root)
	_build_modal()


func _build_top_right(root: Control) -> void:
	hostiles_panel = PanelContainer.new()
	hostiles_panel.anchor_left = 1.0
	hostiles_panel.anchor_right = 1.0
	hostiles_panel.offset_left = -150
	hostiles_panel.offset_right = -20
	hostiles_panel.offset_top = 18
	hostiles_panel.offset_bottom = 60
	hostiles_panel.add_theme_stylebox_override("panel", _panel(HI.BG, HI.RED.darkened(0.2), 5, 1, 10))
	root.add_child(hostiles_panel)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	hostiles_panel.add_child(h)
	hostiles_icon = HI.icon("skull", 20, HI.RED)
	h.add_child(hostiles_icon)
	hostiles_lbl = HI.label("0", 20, HI.TEXT)
	h.add_child(hostiles_lbl)
	hostiles_boss = HI.icon("crown", 18, HI.AMBER)
	hostiles_boss.visible = false
	h.add_child(hostiles_boss)

	powerups_box = VBoxContainer.new()
	powerups_box.anchor_left = 1.0
	powerups_box.anchor_right = 1.0
	powerups_box.offset_left = -190
	powerups_box.offset_right = -20
	powerups_box.offset_top = 68
	powerups_box.offset_bottom = 200
	powerups_box.add_theme_constant_override("separation", 6)
	powerups_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(powerups_box)


func _build_boss_bar(root: Control) -> void:
	boss_panel = PanelContainer.new()
	boss_panel.anchor_left = 0.5
	boss_panel.anchor_right = 0.5
	boss_panel.offset_left = -340
	boss_panel.offset_right = 340
	boss_panel.offset_top = 16
	boss_panel.offset_bottom = 122
	boss_panel.visible = false
	boss_panel.add_theme_stylebox_override("panel", _panel(Color(0.06, 0.05, 0.07, 0.9), HI.RED, 6, 1, 12))
	root.add_child(boss_panel)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 4)
	boss_panel.add_child(bv)
	var tr := HBoxContainer.new()
	tr.alignment = BoxContainer.ALIGNMENT_CENTER
	tr.add_theme_constant_override("separation", 8)
	bv.add_child(tr)
	tr.add_child(HI.icon("crown", 22, HI.RED))
	boss_title_lbl = HI.label("", 19, Color(1.0, 0.34, 0.24))
	tr.add_child(boss_title_lbl)
	boss_sub_lbl = HI.label("", 11, HI.DIM)
	boss_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(boss_sub_lbl)
	boss_hp_bar = ProgressBar.new()
	boss_hp_bar.custom_minimum_size = Vector2(0, 14)
	boss_hp_bar.show_percentage = false
	boss_hp_bar.add_theme_stylebox_override("background", _bar(Color(0.16, 0.06, 0.06)))
	boss_hp_bar.add_theme_stylebox_override("fill", _bar(Color(0.88, 0.16, 0.14)))
	bv.add_child(boss_hp_bar)
	var sr := HBoxContainer.new()
	sr.alignment = BoxContainer.ALIGNMENT_CENTER
	sr.add_theme_constant_override("separation", 10)
	bv.add_child(sr)
	boss_status_box = HBoxContainer.new()
	boss_status_box.add_theme_constant_override("separation", 10)
	sr.add_child(boss_status_box)
	boss_hp_lbl = HI.label("", 12, HI.DIM)
	sr.add_child(boss_hp_lbl)

	banner_lbl = HI.label("", 18, HI.TEXT)
	banner_lbl.anchor_left = 0.5
	banner_lbl.anchor_right = 0.5
	banner_lbl.offset_left = -460
	banner_lbl.offset_right = 460
	banner_lbl.offset_top = 132
	banner_lbl.offset_bottom = 172
	banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_lbl.add_theme_constant_override("outline_size", 6)
	banner_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	banner_lbl.visible = false
	root.add_child(banner_lbl)


func _build_center(root: Control) -> void:
	crosshair_root = Control.new()
	crosshair_root.anchor_left = 0.5
	crosshair_root.anchor_right = 0.5
	crosshair_root.anchor_top = 0.5
	crosshair_root.anchor_bottom = 0.5
	crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair_root)
	for rect_cfg in [Vector4(-13, -1, 8, 2), Vector4(5, -1, 8, 2), Vector4(-1, -13, 2, 8), Vector4(-1, 5, 2, 8)]:
		var tick := ColorRect.new()
		tick.position = Vector2(rect_cfg.x, rect_cfg.y)
		tick.size = Vector2(rect_cfg.z, rect_cfg.w)
		tick.color = Color(0.95, 0.95, 0.95, 0.85)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair_root.add_child(tick)
		cross_ticks.append(tick)

	scope_canvas = Control.new()
	scope_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_canvas.visible = false
	scope_canvas.draw.connect(_draw_scope)
	root.add_child(scope_canvas)
	root.move_child(scope_canvas, 0)

	hit_canvas = Control.new()
	hit_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_canvas.draw.connect(_draw_hitmarker)
	crosshair_root.add_child(hit_canvas)

	var streak_row := HBoxContainer.new()
	streak_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	streak_row.set_anchors_preset(Control.PRESET_CENTER)
	streak_row.offset_left = -300
	streak_row.offset_right = 300
	streak_row.offset_top = 46
	streak_row.offset_bottom = 96
	streak_row.alignment = BoxContainer.ALIGNMENT_CENTER
	streak_row.add_theme_constant_override("separation", 10)
	streak_row.modulate.a = 0.0
	root.add_child(streak_row)
	streak_icon = HI.icon("skull", 26, HI.AMBER)
	streak_row.add_child(streak_icon)
	streak_lbl = HI.label("", 24, HI.AMBER)
	streak_lbl.add_theme_constant_override("outline_size", 8)
	streak_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	streak_row.add_child(streak_lbl)
	streak_lbl.pivot_offset = Vector2(150, 25)

	sub_lbl = Label.new()
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub_lbl.offset_left = -560
	sub_lbl.offset_right = 560
	sub_lbl.offset_top = -210
	sub_lbl.offset_bottom = -150
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.add_theme_font_size_override("font_size", 20)
	sub_lbl.add_theme_constant_override("outline_size", 7)
	sub_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub_lbl.modulate.a = 0.0
	root.add_child(sub_lbl)
	GameState.subtitle.connect(func(text: String, col: Color):
		sub_lbl.text = text
		sub_lbl.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.35))
		sub_lbl.modulate.a = 1.0
		var tw := sub_lbl.create_tween()
		tw.tween_interval(3.8)
		tw.tween_property(sub_lbl, "modulate:a", 0.0, 0.6))

	dmg_canvas = Control.new()
	dmg_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	dmg_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dmg_canvas.draw.connect(_draw_damage_indicators)
	root.add_child(dmg_canvas)

	ammo_hint_box = HBoxContainer.new()
	ammo_hint_box.anchor_left = 0.5
	ammo_hint_box.anchor_right = 0.5
	ammo_hint_box.anchor_top = 0.5
	ammo_hint_box.anchor_bottom = 0.5
	ammo_hint_box.offset_left = -220
	ammo_hint_box.offset_right = 220
	ammo_hint_box.offset_top = 88
	ammo_hint_box.offset_bottom = 120
	ammo_hint_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ammo_hint_box.add_theme_constant_override("separation", 8)
	ammo_hint_box.visible = false
	root.add_child(ammo_hint_box)
	ammo_hint_icon = HI.icon("reload", 18, HI.AMBER)
	ammo_hint_box.add_child(ammo_hint_icon)
	ammo_hint_key = HI.keycap("R", 12)
	ammo_hint_box.add_child(ammo_hint_key)
	ammo_hint_lbl = HI.label("", 16, HI.AMBER)
	ammo_hint_lbl.add_theme_constant_override("outline_size", 5)
	ammo_hint_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	ammo_hint_box.add_child(ammo_hint_lbl)

	interact_box = HBoxContainer.new()
	interact_box.anchor_left = 0.5
	interact_box.anchor_right = 0.5
	interact_box.anchor_top = 0.5
	interact_box.anchor_bottom = 0.5
	interact_box.offset_left = -300
	interact_box.offset_right = 300
	interact_box.offset_top = 46
	interact_box.offset_bottom = 84
	interact_box.alignment = BoxContainer.ALIGNMENT_CENTER
	interact_box.add_theme_constant_override("separation", 8)
	interact_box.visible = false
	root.add_child(interact_box)
	interact_key = HI.keycap("E", 13)
	interact_box.add_child(interact_key)
	interact_icon = HI.icon("hand", 18, HI.AMBER)
	interact_box.add_child(interact_icon)
	interact_lbl = HI.label("", 17, Color(1.0, 0.92, 0.48))
	interact_lbl.add_theme_constant_override("outline_size", 5)
	interact_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	interact_box.add_child(interact_lbl)


func _build_bottom_left(root: Control) -> void:
	var bl_box := VBoxContainer.new()
	bl_box.anchor_top = 1.0
	bl_box.anchor_bottom = 1.0
	bl_box.offset_left = 24
	bl_box.offset_right = 400
	bl_box.offset_top = -252
	bl_box.offset_bottom = -20
	bl_box.add_theme_constant_override("separation", 6)
	root.add_child(bl_box)

	var round_row := HBoxContainer.new()
	round_row.add_theme_constant_override("separation", 10)
	bl_box.add_child(round_row)
	tally_marks = TallyMarksScript.new()
	round_row.add_child(tally_marks)
	var rv := VBoxContainer.new()
	rv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	round_row.add_child(rv)
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 6)
	rv.add_child(fr)
	fr.add_child(HI.icon("flag", 15, HI.DIM))
	round_sub_lbl = HI.label("ROUND 1", 14, HI.DIM)
	fr.add_child(round_sub_lbl)

	var pts_row := HBoxContainer.new()
	pts_row.add_theme_constant_override("separation", 8)
	bl_box.add_child(pts_row)
	pts_row.add_child(HI.icon("coin", 22, HI.AMBER))
	points_lbl = HI.label("500", 26, HI.AMBER)
	points_lbl.add_theme_constant_override("outline_size", 5)
	points_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	pts_row.add_child(points_lbl)
	points_popup_lbl = HI.label("", 19, Color(1.0, 0.94, 0.45))
	pts_row.add_child(points_popup_lbl)

	var hp_panel := PanelContainer.new()
	hp_panel.add_theme_stylebox_override("panel", _panel(HI.BG, HI.EDGE, 5, 1, 10))
	bl_box.add_child(hp_panel)
	var hp_v := VBoxContainer.new()
	hp_v.add_theme_constant_override("separation", 4)
	hp_panel.add_child(hp_v)
	var hp_head := HBoxContainer.new()
	hp_head.add_theme_constant_override("separation", 7)
	hp_v.add_child(hp_head)
	hp_head.add_child(HI.icon("heart", 18, HI.RED))
	hp_lbl = HI.label("", 15, HI.TEXT)
	hp_head.add_child(hp_lbl)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 12)
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("background", _bar(Color(0.15, 0.15, 0.18)))
	hp_bar.add_theme_stylebox_override("fill", _bar(Color(0.84, 0.18, 0.18)))
	hp_v.add_child(hp_bar)
	shield_row = HBoxContainer.new()
	shield_row.add_theme_constant_override("separation", 7)
	shield_row.visible = false
	hp_v.add_child(shield_row)
	shield_row.add_child(HI.icon("shield", 14, HI.CYAN))
	shield_bar = ProgressBar.new()
	shield_bar.custom_minimum_size = Vector2(0, 6)
	shield_bar.show_percentage = false
	shield_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shield_bar.add_theme_stylebox_override("background", _bar(Color(0.10, 0.14, 0.18), 2))
	shield_bar.add_theme_stylebox_override("fill", _bar(HI.CYAN, 2))
	shield_row.add_child(shield_bar)
	var st_row := HBoxContainer.new()
	st_row.add_theme_constant_override("separation", 7)
	hp_v.add_child(st_row)
	st_row.add_child(HI.icon("bolt", 13, HI.AMBER))
	stamina_bar = ProgressBar.new()
	stamina_bar.custom_minimum_size = Vector2(0, 5)
	stamina_bar.show_percentage = false
	stamina_bar.max_value = 1.0
	stamina_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stamina_bar.add_theme_stylebox_override("background", _bar(Color(0.15, 0.15, 0.18), 2))
	stamina_bar.add_theme_stylebox_override("fill", _bar(Color(0.95, 0.85, 0.35), 2))
	st_row.add_child(stamina_bar)
	perks_box = HBoxContainer.new()
	perks_box.add_theme_constant_override("separation", 8)
	hp_v.add_child(perks_box)
	revive_row = HBoxContainer.new()
	revive_row.add_theme_constant_override("separation", 6)
	revive_row.visible = false
	hp_v.add_child(revive_row)
	revive_row.add_child(HI.icon("cross", 14, HI.GREEN))
	revive_lbl = HI.label("SECOND WIND", 12, HI.GREEN)
	revive_row.add_child(revive_lbl)


func _make_tile(key: String, icon_name: String, accent: Color) -> Dictionary:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(60, 60)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _panel(Color(0.05, 0.07, 0.10, 0.9), accent.darkened(0.35), 6, 1, 0)
	panel.add_theme_stylebox_override("panel", sb)
	var ic := HI.icon(icon_name, 28, accent)
	ic.position = Vector2(16, 15)
	panel.add_child(ic)
	var kc := HI.keycap(key, 10)
	kc.position = Vector2(3, 3)
	panel.add_child(kc)
	var cd := ColorRect.new()
	cd.color = Color(0, 0, 0, 0.66)
	cd.position = Vector2(1, 61)
	cd.size = Vector2(58, 0)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(cd)
	var cd_lbl := HI.label("", 15, Color.WHITE)
	cd_lbl.position = Vector2(1, 20)
	cd_lbl.size = Vector2(58, 20)
	cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(cd_lbl)
	var count := HI.label("", 12, HI.TEXT)
	count.position = Vector2(1, 42)
	count.size = Vector2(58, 16)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(count)
	var pips := HBoxContainer.new()
	pips.position = Vector2(6, 52)
	pips.add_theme_constant_override("separation", 3)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(pips)
	return {"panel": panel, "sb": sb, "icon": ic, "cd": cd, "cd_lbl": cd_lbl, "count": count, "pips": pips, "accent": accent}


func _set_tile(t: Dictionary, icon_name: String, ratio: float, secs: String, count_txt: String, pip_filled: int, pip_total: int, ready: bool) -> void:
	(t["icon"] as TextureRect).texture = HI.tex(icon_name)
	var h := clampf(ratio, 0.0, 1.0) * 58.0
	(t["cd"] as ColorRect).size = Vector2(58, h)
	(t["cd"] as ColorRect).position = Vector2(1, 60 - h)
	(t["cd_lbl"] as Label).text = secs
	(t["count"] as Label).text = count_txt
	var pips := t["pips"] as HBoxContainer
	if pips.get_child_count() != pip_total:
		for c in pips.get_children():
			c.queue_free()
		for i in range(pip_total):
			var pr := ColorRect.new()
			pr.custom_minimum_size = Vector2(7, 4)
			pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pips.add_child(pr)
	for i in range(pips.get_child_count()):
		(pips.get_child(i) as ColorRect).color = (t["accent"] as Color) if i < pip_filled else Color(0.2, 0.24, 0.3)
	(t["sb"] as StyleBoxFlat).border_color = (t["accent"] as Color) if ready else (t["accent"] as Color).darkened(0.55)


func _build_bottom_right(root: Control) -> void:
	var br_box := VBoxContainer.new()
	br_box.anchor_left = 1.0
	br_box.anchor_right = 1.0
	br_box.anchor_top = 1.0
	br_box.anchor_bottom = 1.0
	br_box.offset_left = -420
	br_box.offset_right = -24
	br_box.offset_top = -220
	br_box.offset_bottom = -20
	br_box.add_theme_constant_override("separation", 8)
	root.add_child(br_box)

	var skills_row := HBoxContainer.new()
	skills_row.alignment = BoxContainer.ALIGNMENT_END
	skills_row.add_theme_constant_override("separation", 8)
	br_box.add_child(skills_row)
	tile_q = _make_tile("Q", "claw", HI.CYAN)
	skills_row.add_child(tile_q["panel"])
	tile_f = _make_tile("F", "beast", HI.RED)
	skills_row.add_child(tile_f["panel"])
	tile_x = _make_tile("X", "star", HI.PURPLE)
	tile_x["panel"].visible = false
	skills_row.add_child(tile_x["panel"])
	tile_z = _make_tile("Z", "star", HI.PURPLE)
	tile_z["panel"].visible = false
	skills_row.add_child(tile_z["panel"])
	tile_t = _make_tile("T", "box", HI.AMBER)
	tile_t["panel"].visible = false
	skills_row.add_child(tile_t["panel"])
	tile_b = _make_tile("B", "mine", HI.AMBER)
	tile_b["panel"].visible = false
	skills_row.add_child(tile_b["panel"])

	var wep_panel := PanelContainer.new()
	wep_panel.add_theme_stylebox_override("panel", _panel(HI.BG, HI.EDGE, 5, 1, 12))
	br_box.add_child(wep_panel)
	var wvv := VBoxContainer.new()
	wvv.add_theme_constant_override("separation", 4)
	wep_panel.add_child(wvv)
	var wv := HBoxContainer.new()
	wv.add_theme_constant_override("separation", 10)
	wvv.add_child(wv)
	weapon_icon = HI.icon("pistol", 30, HI.TEXT)
	wv.add_child(weapon_icon)
	weapon_name_lbl = HI.label("", 16, HI.TEXT)
	weapon_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wv.add_child(weapon_name_lbl)
	reload_icon = HI.icon("reload", 18, HI.AMBER)
	reload_icon.visible = false
	wv.add_child(reload_icon)
	var ammo_row := HBoxContainer.new()
	ammo_row.add_theme_constant_override("separation", 8)
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	wvv.add_child(ammo_row)
	ammo_row.add_child(HI.icon("bullet", 18, HI.AMBER))
	ammo_lbl = HI.label("8", 30, Color(1.0, 0.96, 0.88))
	ammo_row.add_child(ammo_lbl)
	reserve_lbl = HI.label("/ 80", 16, HI.DIM)
	reserve_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ammo_row.add_child(reserve_lbl)
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 10)
	gr.alignment = BoxContainer.ALIGNMENT_END
	wvv.add_child(gr)
	var gch := HBoxContainer.new()
	gch.add_theme_constant_override("separation", 5)
	gr.add_child(gch)
	gch.add_child(HI.icon("grenade", 15, HI.GREEN))
	grenade_lbl = HI.label("3", 14, HI.GREEN)
	gch.add_child(grenade_lbl)
	loadout_box = HBoxContainer.new()
	loadout_box.add_theme_constant_override("separation", 8)
	loadout_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gr.add_child(loadout_box)


# ---------------------------------------------------------------------------
# Modal (pause / game over)
# ---------------------------------------------------------------------------
func _build_modal() -> void:
	modal_overlay = ColorRect.new()
	modal_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_overlay.color = Color(0.02, 0.02, 0.03, 0.85)
	modal_overlay.visible = false
	add_child(modal_overlay)
	var m_card := PanelContainer.new()
	m_card.anchor_left = 0.5
	m_card.anchor_right = 0.5
	m_card.anchor_top = 0.5
	m_card.anchor_bottom = 0.5
	m_card.offset_left = -300
	m_card.offset_right = 300
	m_card.offset_top = -250
	m_card.offset_bottom = 250
	m_card.add_theme_stylebox_override("panel", _panel(HI.BG_SOLID, HI.RED, 8, 1, 22))
	modal_overlay.add_child(m_card)
	var mv := VBoxContainer.new()
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", 14)
	m_card.add_child(mv)
	var hr := HBoxContainer.new()
	hr.alignment = BoxContainer.ALIGNMENT_CENTER
	hr.add_theme_constant_override("separation", 12)
	mv.add_child(hr)
	modal_icon = HI.icon("pause", 34, HI.RED)
	hr.add_child(modal_icon)
	modal_title = HI.label("PAUSED", 30, HI.RED)
	hr.add_child(modal_title)
	modal_tiles = HBoxContainer.new()
	modal_tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	modal_tiles.add_theme_constant_override("separation", 18)
	mv.add_child(modal_tiles)
	modal_stats = HI.label("", 15, HI.TEXT)
	modal_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mv.add_child(modal_stats)
	var opt_scroll := ScrollContainer.new()
	opt_scroll.custom_minimum_size = Vector2(560, 260)
	opt_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	opt_scroll.theme = HI.theme()
	mv.add_child(opt_scroll)
	settings_box = opt_scroll
	var opts := OptionsPanel.new()
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_scroll.add_child(opts)
	resume_btn = _icon_button("play", "RESUME COMBAT")
	resume_btn.pressed.connect(_toggle_pause)
	mv.add_child(resume_btn)
	var restart_btn := _icon_button("restart", "BACK TO LOBBY (WHOLE SQUAD)" if Net.is_online() else "RESTART OUTBREAK")
	restart_btn.visible = not Net.is_client()
	restart_btn.pressed.connect(func():
		if Net.is_online():
			Net.return_to_lobby()
			return
		get_tree().paused = false
		GameState.reset_run()
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	mv.add_child(restart_btn)
	var menu_btn := _icon_button("home", "LEAVE SQUAD" if Net.is_online() else "MAIN MENU")
	menu_btn.pressed.connect(func():
		Net.leave()
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	mv.add_child(menu_btn)


func _icon_button(icon_name: String, text: String) -> Button:
	var b := Button.new()
	b.text = "  " + text
	b.icon = HI.tex(icon_name)
	b.add_theme_constant_override("icon_max_width", 20)
	b.custom_minimum_size = Vector2(0, 42)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _modal_tile(icon_name: String, value: String, col: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	var ic := HI.icon(icon_name, 26, col)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := HI.label(value, 20, HI.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


func _show_modal(icon_name: String, title: String, col: Color, stats: Array, summary: String) -> void:
	modal_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_btn.visible = false
	settings_box.visible = false
	modal_icon.texture = HI.tex(icon_name)
	modal_icon.modulate = col
	modal_title.text = title
	modal_title.add_theme_color_override("font_color", col)
	for c in modal_tiles.get_children():
		c.queue_free()
	modal_tiles.add_child(_modal_tile("flag", str(stats[0]), HI.TEXT))
	modal_tiles.add_child(_modal_tile("skull", str(stats[1]), HI.RED))
	modal_tiles.add_child(_modal_tile("target", str(stats[2]), HI.AMBER))
	modal_tiles.add_child(_modal_tile("crown", str(stats[3]), HI.PURPLE))
	modal_stats.text = summary


# ---------------------------------------------------------------------------
# Scoreboard
# ---------------------------------------------------------------------------
var flash_lbl: Label


func _update_flash_label() -> void:
	if flash_lbl == null:
		return
	var cells := int(ceil(player.flash_battery * 10.0))
	flash_lbl.text = "FLASHLIGHT %s  %s%s  %s" % [GameState.key_label("flashlight"), "▮".repeat(cells), "▯".repeat(10 - cells), "ON" if player.flashlight_on else "OFF"]
	var col := Color(1.0, 0.95, 0.8) if player.flashlight_on else Color(0.6, 0.62, 0.68)
	if player.flash_battery < 0.2:
		col = Color(1.0, 0.4, 0.3)
	flash_lbl.add_theme_color_override("font_color", col)
	flash_lbl.visible = not player.is_dead and not modal_overlay.visible


func _build_scoreboard() -> void:
	score_panel = PanelContainer.new()
	score_panel.anchor_left = 0.5
	score_panel.anchor_right = 0.5
	score_panel.anchor_top = 0.5
	score_panel.anchor_bottom = 0.5
	score_panel.offset_left = -430
	score_panel.offset_right = 430
	score_panel.offset_top = -230
	score_panel.offset_bottom = -230
	score_panel.grow_vertical = Control.GROW_DIRECTION_END
	score_panel.visible = false
	score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _panel(Color(0.03, 0.04, 0.055, 0.94), HI.RED, 6, 1, 20)
	score_panel.add_theme_stylebox_override("panel", sb)
	add_child(score_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	score_panel.add_child(v)
	score_title = HI.label("", 18, HI.TEXT)
	v.add_child(score_title)
	score_grid = GridContainer.new()
	score_grid.columns = 6
	score_grid.add_theme_constant_override("h_separation", 26)
	score_grid.add_theme_constant_override("v_separation", 6)
	v.add_child(score_grid)
	score_summary = HI.label("", 13, HI.DIM)
	score_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	score_summary.custom_minimum_size = Vector2(810, 0)
	v.add_child(score_summary)


func _score_cell(text: String, col: Color, wide: bool = false) -> void:
	var l := HI.label(text, 15, col)
	if wide:
		l.custom_minimum_size = Vector2(200, 0)
	score_grid.add_child(l)


func _score_icon_cell(icon_name: String, col: Color) -> void:
	var ic := HI.icon(icon_name, 16, col)
	score_grid.add_child(ic)


func _update_scoreboard(delta: float) -> void:
	if score_panel == null:
		return
	var want := Input.is_action_pressed("scoreboard") and not modal_overlay.visible
	if want != score_panel.visible:
		score_panel.visible = want
		_score_t = 0.0
	if not want:
		return
	_score_t -= delta
	if _score_t > 0.0:
		return
	_score_t = 0.3
	var secs := int(GameState.run_time)
	score_title.text = "ROUND %d   •   %s   •   %s   •   %02d:%02d" % [GameState.current_round, GameState.DIFFICULTY_NAMES[GameState.difficulty],
		"CASUAL" if GameState.game_mode == "casual" else "INFINITE", secs / 60, secs % 60]
	for c in score_grid.get_children():
		c.queue_free()
	var head := Color(0.6, 0.63, 0.7)
	_score_icon_cell("user", head)
	_score_icon_cell("beast", head)
	_score_icon_cell("skull", head)
	_score_icon_cell("coin", head)
	_score_icon_cell("down", head)
	_score_icon_cell("heart", head)
	var me_col := Color(1.0, 0.9, 0.5)
	var my_name: String = Net.player_name(Net.my_id()) if Net.is_online() else "YOU"
	var state := "dead" if player.is_dead else ("down" if player.is_downed else "alive")
	_score_cell(my_name, me_col, true)
	_score_cell(player.char_id.to_upper(), me_col)
	_score_cell(str(GameState.total_kills), me_col)
	_score_cell(str(GameState.points), me_col)
	_score_cell(str(GameState.downs), me_col)
	_score_status_cell(state)
	var ng := get_tree().get_first_node_in_group("net_game")
	if Net.is_online() and ng:
		for av in ng.avatars.values():
			if not is_instance_valid(av):
				continue
			var st := "exfil" if av.extracted else ("dead" if av.is_dead else ("down" if av.is_downed else "alive"))
			var op := String((Net.players.get(av.peer_id, {}) as Dictionary).get("char", "")).to_upper()
			_score_cell(av.display_name, av.color, true)
			_score_cell(op, av.color)
			_score_cell(str(av.kills), av.color)
			_score_cell(str(av.points), av.color)
			_score_cell(str(av.downs), av.color)
			_score_status_cell(st)
	var hs_pct := int(round(100.0 * float(GameState.headshots) / float(maxi(1, GameState.total_kills))))
	var lines := "YOUR RUN:  %d KILLS  •  %d HEADSHOTS (%d%%)  •  %d BOSSES  •  %d COMMANDERS  •  %d CHALLENGES  •  SCORE %d" % [
		GameState.total_kills, GameState.headshots, hs_pct, GameState.bosses_slain, GameState.commanders_slain, GameState.challenges_done, GameState.run_score("")]
	if not GameState.nemesis.is_empty():
		lines += "\nNEMESIS: %s %s — killed you %d time(s). It hunts you from round 4." % [String(GameState.nemesis.get("name", "")), "★".repeat(int(GameState.nemesis.get("tier", 3))), int(GameState.nemesis.get("kills", 1))]
	score_summary.text = lines


func _score_status_cell(state: String) -> void:
	match state:
		"alive": _score_icon_cell("heart", HI.GREEN)
		"down": _score_icon_cell("down", HI.AMBER)
		"exfil": _score_icon_cell("chopper", HI.CYAN)
		_: _score_icon_cell("skull", HI.RED)


# ---------------------------------------------------------------------------
# Objectives
# ---------------------------------------------------------------------------
func _build_objectives() -> void:
	event_box = HBoxContainer.new()
	event_box.position = Vector2(14, 30)
	event_box.add_theme_constant_override("separation", 7)
	event_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_box.visible = false
	add_child(event_box)
	move_child(event_box, 1)
	event_box.add_child(HI.icon("warning", 16, HI.AMBER))
	event_lbl = HI.label("", 15, HI.AMBER)
	event_lbl.add_theme_constant_override("outline_size", 5)
	event_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	event_box.add_child(event_lbl)
	challenge_box = HBoxContainer.new()
	challenge_box.position = Vector2(14, 54)
	challenge_box.add_theme_constant_override("separation", 7)
	challenge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	challenge_box.visible = false
	add_child(challenge_box)
	move_child(challenge_box, 1)
	challenge_box.add_child(HI.icon("target", 16, HI.CYAN))
	challenge_lbl = HI.label("", 14, HI.CYAN)
	challenge_lbl.add_theme_constant_override("outline_size", 5)
	challenge_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	challenge_box.add_child(challenge_lbl)


func _update_objectives() -> void:
	if event_lbl == null:
		return
	var ev := GameState.round_event
	if ev != "" and GameState.ROUND_EVENTS.has(ev):
		var info: Dictionary = GameState.ROUND_EVENTS[ev]
		event_lbl.text = "%s — %s" % [info["name"], info["desc"]]
		event_lbl.add_theme_color_override("font_color", info["color"])
		event_box.visible = true
	else:
		event_box.visible = false
	challenge_box.position.y = 54 if event_box.visible else 30
	if not is_instance_valid(_challenge):
		_challenge = get_parent().get_node_or_null("RoundChallenge")
	if _challenge:
		var ctxt := String(_challenge.hud_text()).replace("✔ ", "").replace("◆ ", "")
		challenge_lbl.text = ctxt
		challenge_box.visible = ctxt != ""
		challenge_lbl.add_theme_color_override("font_color", _challenge.hud_color())
	else:
		challenge_box.visible = false


# ---------------------------------------------------------------------------
# Commander bar
# ---------------------------------------------------------------------------
func _build_commander_bar() -> void:
	cmd_panel = PanelContainer.new()
	cmd_panel.anchor_left = 0.5
	cmd_panel.anchor_right = 0.5
	cmd_panel.offset_left = -260
	cmd_panel.offset_right = 260
	cmd_panel.offset_top = 18
	cmd_panel.visible = false
	cmd_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cmd_border = _panel(Color(0.06, 0.05, 0.07, 0.85), Color(1.0, 0.5, 0.1), 5, 1, 10)
	cmd_panel.add_theme_stylebox_override("panel", _cmd_border)
	add_child(cmd_panel)
	move_child(cmd_panel, 1)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	cmd_panel.add_child(v)
	var tr := HBoxContainer.new()
	tr.alignment = BoxContainer.ALIGNMENT_CENTER
	tr.add_theme_constant_override("separation", 6)
	v.add_child(tr)
	cmd_pips = HBoxContainer.new()
	cmd_pips.add_theme_constant_override("separation", 2)
	tr.add_child(cmd_pips)
	cmd_title = HI.label("", 14, HI.TEXT)
	tr.add_child(cmd_title)
	cmd_bar = ProgressBar.new()
	cmd_bar.custom_minimum_size = Vector2(0, 7)
	cmd_bar.show_percentage = false
	cmd_bar.add_theme_stylebox_override("background", _bar(Color(0.14, 0.08, 0.06)))
	_cmd_fill = _bar(Color(1.0, 0.5, 0.1))
	cmd_bar.add_theme_stylebox_override("fill", _cmd_fill)
	v.add_child(cmd_bar)
	var sr := HBoxContainer.new()
	sr.alignment = BoxContainer.ALIGNMENT_CENTER
	sr.add_theme_constant_override("separation", 6)
	v.add_child(sr)
	cmd_icon = HI.icon("warning", 13, HI.AMBER)
	sr.add_child(cmd_icon)
	cmd_status = HI.label("", 11, HI.DIM)
	sr.add_child(cmd_status)


func _update_commander_bar(delta: float) -> void:
	if cmd_panel == null:
		return
	_cmd_t -= delta
	if _cmd_t > 0.0:
		return
	_cmd_t = 0.12
	var best: ZombieEnemy = null
	var best_d := 70.0
	for c in get_tree().get_nodes_in_group("commanders"):
		var z := c as ZombieEnemy
		if z == null or z.is_dead:
			continue
		var d := z.global_position.distance_to(player.global_position) * (0.5 if z.is_nemesis else 1.0)
		if d < best_d:
			best_d = d
			best = z
	if best == null:
		cmd_panel.visible = false
		return
	cmd_panel.visible = true
	cmd_panel.offset_top = 136 if boss_panel.visible else 18
	var col: Color = ZombieEnemy.TIER_COLORS[best.tier]
	if cmd_pips.get_child_count() != best.tier:
		for c in cmd_pips.get_children():
			c.queue_free()
		for i in range(best.tier):
			cmd_pips.add_child(HI.icon("star", 12, col))
	cmd_title.text = "%s%s" % ["NEMESIS " if best.is_nemesis else "", best.commander_name]
	cmd_title.add_theme_color_override("font_color", col)
	_cmd_fill.bg_color = col.darkened(0.12)
	_cmd_border.border_color = col.darkened(0.2)
	cmd_bar.max_value = best.max_hp
	cmd_bar.value = best.hp
	var info: Dictionary = ZombieEnemy.CommanderBrain.SKILLS.get(best.stolen_skill, {})
	var status := ""
	var sicon := "warning"
	if best.shield_on:
		status = "SHIELDED — KILL BODYGUARDS"
		sicon = "shield"
	elif best.fx_cast_t > 0.0 and best.fx_cast == "scream":
		status = "PSYCHIC SCREAM — HEADSHOT TO INTERRUPT"
		sicon = "target"
	elif best.fx_cast_t > 0.0 and not info.is_empty():
		status = "%s — %s!" % [info["name"], info["tip"]]
		sicon = "bolt"
	elif best.fx_enraged:
		status = "ENRAGED — FIGHTS ALONE"
		sicon = "flame"
	elif not info.is_empty():
		status = "STOLEN %s: %s" % [info["from"], info["name"]]
		sicon = HI.borrowed_icon(best.stolen_skill)
	cmd_icon.texture = HI.tex(sicon)
	cmd_status.text = status


# ---------------------------------------------------------------------------
# Signals / input / pause
# ---------------------------------------------------------------------------
func _connect_signals() -> void:
	player.hp_changed.connect(_on_hp_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	player.hitmarker_triggered.connect(_on_hitmarker)
	player.kill_streak.connect(_on_kill_streak)
	player.status_banner_requested.connect(_show_banner)
	player.interact_prompt_changed.connect(_set_interact)
	player.player_died.connect(_on_player_died)
	player.damaged.connect(_on_player_damaged)
	player.stats_changed.connect(_refresh_stats_line)
	player.downed_changed.connect(_on_downed_changed)
	augment_menu = AugmentMenuScript.new()
	add_child(augment_menu)
	GameState.points_changed.connect(_on_points_changed)
	wave_mgr.round_started.connect(_on_round_started)
	wave_mgr.wave_status_changed.connect(_on_wave_status)
	wave_mgr.boss_spawned.connect(_on_boss_spawned)
	wave_mgr.boss_updated.connect(_update_boss_bar)
	wave_mgr.boss_defeated.connect(_on_boss_defeated)
	wave_mgr.exfil_won.connect(_on_exfil_won)
	wave_mgr.run_won.connect(_on_run_won)


func _on_wave_status(txt: String) -> void:
	# txt examples: "ZOMBIES: 9  (THEN BOSS)", "HOUNDS: 3 ...", "INTERMISSION",
	# "⚠ BOSS INCOMING!", "☠ ROUND BOSS FIGHT", "☢ EXTRACTION — N HOSTILES"
	var num := ""
	for ch in txt:
		if ch >= "0" and ch <= "9":
			num += ch
		elif num != "":
			break
	hostiles_lbl.text = num if num != "" else "—"
	var is_hound := txt.contains("HOUNDS")
	var is_boss := txt.contains("BOSS")
	var is_exfil := txt.contains("EXTRACTION")
	var is_inter := txt.contains("INTERMISSION")
	hostiles_icon.texture = HI.tex("paw" if is_hound else ("chopper" if is_exfil else ("clock" if is_inter else "skull")))
	hostiles_icon.modulate = HI.RED if not is_inter else HI.CYAN
	hostiles_boss.visible = is_boss and not is_exfil


func _unhandled_input(event: InputEvent) -> void:
	if augment_menu and augment_menu.visible:
		return
	if event.is_action_pressed("pause") and not player.is_dead and not player.extracted:
		_toggle_pause()


func open_augment_menu() -> void:
	if player.is_dead or is_paused:
		return
	augment_menu.open(player)


func _refresh_stats_line() -> void:
	var sig := ""
	for st in GameState.STATS:
		var lv := player.stat_level(st["id"])
		if lv > 0:
			sig += "%s%d," % [st["id"], lv]
	if sig != _perk_sig:
		_perk_sig = sig
		for c in perks_box.get_children():
			c.queue_free()
		for st in GameState.STATS:
			var lv := player.stat_level(st["id"])
			if lv > 0:
				var h := HBoxContainer.new()
				h.add_theme_constant_override("separation", 3)
				h.add_child(HI.icon(HI.stat_icon(st["id"]), 14, st["color"]))
				h.add_child(HI.label(str(lv), 12, st["color"]))
				perks_box.add_child(h)
	revive_row.visible = player.revives > 0


func _toggle_pause() -> void:
	is_paused = not is_paused
	get_tree().paused = is_paused and not Net.is_online()
	modal_overlay.visible = is_paused
	if is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		modal_icon.texture = HI.tex("pause")
		modal_icon.modulate = HI.RED
		modal_title.text = "MISSION PAUSED"
		modal_title.add_theme_color_override("font_color", HI.RED)
		resume_btn.visible = true
		settings_box.visible = true
		for c in modal_tiles.get_children():
			c.queue_free()
		modal_tiles.add_child(_modal_tile("flag", str(GameState.current_round), HI.TEXT))
		modal_tiles.add_child(_modal_tile("skull", str(GameState.total_kills), HI.RED))
		modal_tiles.add_child(_modal_tile("crown", str(GameState.bosses_slain), HI.PURPLE))
		modal_stats.text = ("CASUAL" if GameState.game_mode == "casual" else "INFINITE") + "  •  " + GameState.DIFFICULTY_NAMES[GameState.difficulty]
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if fps_lbl:
		fps_lbl.get_parent().visible = GameState.show_fps
		if GameState.show_fps:
			fps_lbl.text = "%d" % Engine.get_frames_per_second()
	_tick_cd = maxf(0.0, _tick_cd - delta)
	if hitmarker_timer > 0.0:
		hitmarker_timer -= delta
		hit_canvas.queue_redraw()
	if dmg_indicators.size() > 0:
		for ind in dmg_indicators:
			ind["life"] -= delta
		dmg_indicators = dmg_indicators.filter(func(ind: Dictionary): return ind["life"] > 0.0)
		dmg_canvas.queue_redraw()
	if banner_timer > 0.0:
		banner_timer -= delta
		if banner_timer <= 0.0:
			banner_lbl.visible = false
	if points_popup_timer > 0.0:
		points_popup_timer -= delta
		if points_popup_timer <= 0.0:
			points_popup_lbl.text = ""
	if not is_instance_valid(player):
		return
	var hp_ratio := clampf(player.hp / maxf(1.0, player.max_hp), 0.0, 1.0)
	var target_blood := clampf((0.82 - hp_ratio) * 1.25, 0.0, 0.92)
	blood_overlay.modulate.a = lerp(blood_overlay.modulate.a, target_blood, 8.0 * delta)
	var target_monster := 0.72 if player.is_monster_form else 0.0
	monster_overlay.modulate.a = lerp(monster_overlay.modulate.a, target_monster, 8.0 * delta)
	_update_skill_cards()
	_update_extra_tiles()
	_update_powerups()
	_update_ammo_hint()
	_update_crosshair()
	_update_heartbeat(delta)
	_update_exfil_label()
	_update_commander_bar(delta)
	_update_objectives()
	_update_scoreboard(delta)
	if minimap:
		minimap.visible = GameState.show_minimap and not player.is_dead and not modal_overlay.visible and GameState.horror() < 0.55
	_update_flash_label()
	if player.is_downed:
		if player.self_reviving:
			downed_bar.value = 1.0 - player.downed_timer / PlayerController.DOWNED_TIME
			downed_sub.text = "SECOND WIND IN %.1fs — KEEP SHOOTING!" % maxf(0.0, player.downed_timer)
		else:
			downed_bar.value = player.bleedout_timer / PlayerController.BLEEDOUT_TIME
			downed_sub.text = "BLEEDING OUT %.0fs — A TEAMMATE CAN HOLD [E] TO REVIVE" % maxf(0.0, player.bleedout_timer)


var _heartbeat_t: float = 0.0


func _update_heartbeat(delta: float) -> void:
	if player.is_dead or get_tree().paused:
		return
	var ratio := player.hp / maxf(1.0, player.max_hp)
	if ratio < 0.35:
		_heartbeat_t -= delta
		if _heartbeat_t <= 0.0:
			_heartbeat_t = lerpf(0.55, 0.95, ratio / 0.35)
			GameState.play_sfx("heartbeat", lerpf(2.0, -6.0, ratio / 0.35), 1.0)


func _update_crosshair() -> void:
	var scoped := player.is_scoped()
	if scope_canvas.visible != scoped:
		scope_canvas.visible = scoped
		scope_canvas.queue_redraw()
	stamina_bar.value = player.stamina
	stamina_bar.modulate.a = 0.35 if player.stamina >= 0.999 else 1.0
	var hide_ch := player.is_dead or player.is_monster_form or player.is_sprinting or player.ads_t > 0.6
	var spread_rad := deg_to_rad(player.current_spread_deg())
	var half_fov := deg_to_rad(player.camera.fov * 0.5)
	var vh := get_viewport().get_visible_rect().size.y
	var gap := clampf(tan(spread_rad) / tan(half_fov) * vh * 0.5, 4.0, 90.0)
	var offsets := [Vector2(-gap - 8, -1), Vector2(gap, -1), Vector2(-1, -gap - 8), Vector2(-1, gap)]
	for i in range(cross_ticks.size()):
		cross_ticks[i].visible = not hide_ch and GameState.show_crosshair
		cross_ticks[i].position = offsets[i]
	grenade_lbl.text = str(player.grenades)
	var sig := "%d|" % player.active_slot
	for i in range(player.weapons_owned.size()):
		if i != player.active_slot:
			sig += "%d:%s," % [i + 1, player.weapons_owned[i]]
	if sig != _loadout_sig:
		_loadout_sig = sig
		for c in loadout_box.get_children():
			c.queue_free()
		for i in range(player.weapons_owned.size()):
			if i != player.active_slot:
				var h := HBoxContainer.new()
				h.add_theme_constant_override("separation", 4)
				h.add_child(HI.keycap(str(i + 1), 10))
				h.add_child(HI.icon(HI.weapon_icon(player.get_weapon_cfg(player.weapons_owned[i])["class"]), 14, HI.DIM))
				loadout_box.add_child(h)


func _draw_scope() -> void:
	var sz := scope_canvas.size
	var c := sz * 0.5
	var r := sz.y * 0.46
	var outer := c.length() + 4.0
	scope_canvas.draw_arc(c, (r + outer) * 0.5, 0, TAU, 128, Color.BLACK, outer - r + 2.0)
	scope_canvas.draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), Color(0, 0, 0, 0.85), 2.0)
	scope_canvas.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), Color(0, 0, 0, 0.85), 2.0)
	scope_canvas.draw_circle(c, 3.0, Color(1.0, 0.2, 0.15))


func _update_powerups() -> void:
	var active: Array = []
	if GameState.is_powerup_active("insta_kill"):
		active.append(["insta_kill", ceili(GameState.powerup_timers["insta_kill"])])
	if GameState.is_powerup_active("double_points"):
		active.append(["double_points", ceili(GameState.powerup_timers["double_points"])])
	if GameState.is_powerup_active("fire_sale"):
		active.append(["fire_sale", ceili(GameState.powerup_timers["fire_sale"])])
	var pl := get_tree().get_first_node_in_group("player")
	if pl and float(pl.get("adrenaline_timer")) > 0.0:
		active.append(["adrenaline", ceili(float(pl.get("adrenaline_timer")))])
	var sig := ""
	for a in active:
		sig += "%s%d," % [a[0], a[1]]
	if sig != _power_sig:
		_power_sig = sig
		for c in powerups_box.get_children():
			c.queue_free()
		for a in active:
			var pc := PanelContainer.new()
			pc.add_theme_stylebox_override("panel", _panel(HI.BG, HI.EDGE, 4, 1, 6))
			powerups_box.add_child(pc)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 6)
			pc.add_child(h)
			h.add_child(HI.icon(HI.powerup_icon(a[0]), 16, HI.AMBER))
			h.add_child(HI.label("%ds" % a[1], 14, HI.TEXT))
	var dp := GameState.is_powerup_active("double_points")
	points_lbl.add_theme_color_override("font_color", HI.GREEN if dp else HI.AMBER)


func _update_ammo_hint() -> void:
	if player.is_dead or player.is_monster_form or player.is_reloading or player.pap_timer > 0.0:
		ammo_hint_box.visible = false
		return
	var w_id := player.get_current_weapon_id()
	var mag: int = player.mag_ammo[w_id]
	var reserve: int = player.reserve_ammo[w_id]
	var mag_size: int = player.get_weapon_cfg(w_id)["mag_size"]
	var low := mag <= ceili(mag_size * 0.25)
	if mag <= 0 and reserve <= 0:
		ammo_hint_icon.texture = HI.tex("warning")
		ammo_hint_icon.modulate = HI.RED
		ammo_hint_key.visible = false
		ammo_hint_lbl.text = "NO AMMO — BUY AT A WALL"
		ammo_hint_lbl.add_theme_color_override("font_color", HI.RED)
		ammo_hint_box.visible = true
	elif low and reserve > 0:
		ammo_hint_icon.texture = HI.tex("reload")
		ammo_hint_icon.modulate = HI.AMBER
		ammo_hint_key.visible = true
		ammo_hint_lbl.text = "RELOAD"
		ammo_hint_lbl.add_theme_color_override("font_color", HI.AMBER)
		ammo_hint_box.visible = true
	else:
		ammo_hint_box.visible = false
	ammo_lbl.add_theme_color_override("font_color", Color(1.0, 0.38, 0.30) if low else Color(1.0, 0.96, 0.88))


func _set_interact(txt: String) -> void:
	if txt == "":
		interact_box.visible = false
		interact_lbl.text = ""
		return
	interact_box.visible = true
	var key := "E"
	var rest := txt
	if txt.begins_with("["):
		var close := txt.find("]")
		if close > 0:
			key = txt.substr(1, close - 1)
			rest = txt.substr(close + 1).strip_edges()
	interact_key.get_child(0).text = GameState.key_label("interact") if key == "E" else key
	var icon_name := "hand"
	var up := rest.to_upper()
	if up.contains("FORGE"):
		icon_name = "anvil"
	elif up.contains("RESUPPLY") or up.contains("AMMO"):
		icon_name = "bullet"
	elif up.contains("BUY") or up.contains("REFILL"):
		icon_name = "tag"
	elif up.contains("REVIVE"):
		icon_name = "cross"
	elif up.contains("SHARE") or up.contains("SEND ALL") or up.contains("POINTS"):
		icon_name = "coin"
	elif up.contains("DOOR") or up.contains("OPEN"):
		icon_name = "door"
	elif up.contains("CRATE"):
		icon_name = "crate"
	elif up.contains("RADIO"):
		icon_name = "radio"
	elif up.contains("POWER") or up.contains("GENERATOR"):
		icon_name = "bolt"
	elif up.contains("LADDER") or up.contains("BOARD"):
		icon_name = "chopper"
	elif up.contains("FURNACE") or up.contains("AUGMENT"):
		icon_name = "flame"
	interact_icon.texture = HI.tex(icon_name)
	interact_lbl.text = GameState.keyify(rest)


func _on_player_damaged(from_pos: Vector3) -> void:
	if from_pos == Vector3.ZERO:
		return
	dmg_indicators.append({"pos": from_pos, "life": 1.1})
	if dmg_indicators.size() > 6:
		dmg_indicators.pop_front()
	dmg_canvas.queue_redraw()


func _draw_damage_indicators() -> void:
	if not is_instance_valid(player):
		return
	var center := dmg_canvas.size * 0.5
	var inv := player.global_transform.basis.inverse()
	for ind in dmg_indicators:
		var local: Vector3 = inv * (ind["pos"] - player.global_position)
		var a := atan2(local.x, -local.z) - PI * 0.5
		var alpha := clampf(ind["life"] / 0.6, 0.0, 1.0)
		dmg_canvas.draw_arc(center, 170.0, a - 0.32, a + 0.32, 24, Color(0.95, 0.08, 0.06, 0.85 * alpha), 12.0, true)
		dmg_canvas.draw_arc(center, 158.0, a - 0.18, a + 0.18, 16, Color(1.0, 0.45, 0.35, 0.6 * alpha), 4.0, true)


func _draw_hitmarker() -> void:
	if hitmarker_timer <= 0.0:
		return
	var inner := 8.0 if hitmarker_big else 7.0
	var outer := 21.0 if hitmarker_big else 15.0
	var w := 3.5 if hitmarker_big else 2.5
	var col := hitmarker_color
	col.a = clampf(hitmarker_timer / 0.12, 0.0, 1.0)
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var dir: Vector2 = d.normalized()
		hit_canvas.draw_line(dir * inner, dir * outer, Color(0, 0, 0, col.a * 0.6), w + 2.0, true)
		hit_canvas.draw_line(dir * inner, dir * outer, col, w, true)


# ---------------------------------------------------------------------------
# Skill / explosive tiles
# ---------------------------------------------------------------------------
func _update_skill_cards() -> void:
	match player.char_id:
		"ravager":
			if player.is_monster_form:
				weapon_icon.texture = HI.tex("claw")
				weapon_icon.modulate = HI.RED
				weapon_name_lbl.text = "RAVAGER BEAST CLAWS"
				weapon_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.32, 0.20))
				ammo_lbl.text = "%.1f" % player.monster_timer
				reserve_lbl.text = "s"
				reload_icon.visible = false
				_set_tile(tile_q, "claw", 0.0, "", "", 0, 0, true)
				var slam_cd: float = player.monster_slam_cd
				_set_tile(tile_f, "slam", slam_cd / 6.0, ("%.0f" % slam_cd) if slam_cd > 0.0 else "", "", 0, 0, slam_cd <= 0.0)
			else:
				var lc: float = player.human_lunge_cd
				_set_tile(tile_q, "claw", lc / 8.0, ("%.0f" % lc) if lc > 0.0 else "", "", 0, 0, lc <= 0.0)
				var mc: float = player.monster_cd
				_set_tile(tile_f, "beast", mc / 60.0, ("%.0f" % mc) if mc > 0.0 else "", "", 0, 0, mc <= 0.0)
		"alchemist":
			_set_tile(tile_q, "syringe", 0.0, "", "", player.pain_drug_charges, player.pain_drug_max, player.pain_drug_charges > 0)
			if player.pain_drug_charges <= 0:
				var rem := maxf(0.0, player.pain_drug_synth_time - player.pain_drug_synth_progress)
				_set_tile(tile_q, "syringe", rem / maxf(1.0, player.pain_drug_synth_time), "%.0f" % rem, "", 0, player.pain_drug_max, false)
			if player.stim_timer > 0.0:
				_set_tile(tile_f, "pill", 0.0, "%.0f" % player.stim_timer, "", 0, 0, true)
			elif player.stim_cd > 0.0:
				_set_tile(tile_f, "pill", player.stim_cd / 45.0, "%.0f" % player.stim_cd, "", 0, 0, false)
			else:
				_set_tile(tile_f, "pill", 0.0, "", "", 0, 0, true)
		"warden":
			var tc: float = player.tesla_cd
			_set_tile(tile_q, "bolt", tc / 12.0, ("%.0f" % tc) if tc > 0.0 else "", "", 0, 0, tc <= 0.0)
			if player.pap_timer > 0.0:
				_set_tile(tile_f, "arc", 0.0, "%.0f" % player.pap_timer, "", 0, 0, true)
			elif player.pap_cd > 0.0:
				_set_tile(tile_f, "arc", player.pap_cd / 40.0, "%.0f" % player.pap_cd, "", 0, 0, false)
			else:
				_set_tile(tile_f, "arc", 0.0, "", "", 0, 0, true)


func _update_extra_tiles() -> void:
	var bx: bool = player.borrowed_skill != ""
	tile_x["panel"].visible = bx
	if bx:
		var cd: float = player.borrowed_cd
		_set_tile(tile_x, HI.borrowed_icon(player.borrowed_skill), cd / maxf(1.0, player.borrowed_cd_max), ("%.0f" % cd) if cd > 0.0 else "", "", 0, 0, cd <= 0.0)
	var bz: bool = player.borrowed_skill2 != ""
	tile_z["panel"].visible = bz
	if bz:
		var cd2: float = player.borrowed_cd2
		_set_tile(tile_z, HI.borrowed_icon(player.borrowed_skill2), cd2 / maxf(1.0, player.borrowed_cd_max2), ("%.0f" % cd2) if cd2 > 0.0 else "", "", 0, 0, cd2 <= 0.0)
	var placed: int = player.placed_c4()
	var bt: bool = player.c4_count > 0 or placed > 0
	tile_t["panel"].visible = bt
	if bt:
		_set_tile(tile_t, "box", 0.0, "", ("x%d" % player.c4_count) if placed == 0 else ("x%d +%d" % [player.c4_count, placed]), 0, 0, true)
	var bb: bool = player.mines > 0
	tile_b["panel"].visible = bb
	if bb:
		_set_tile(tile_b, "mine", 0.0, "", "x%d" % player.mines, 0, 0, true)


func _refresh_all() -> void:
	_on_hp_changed(player.hp, player.max_hp, player.overshield)
	_on_points_changed(GameState.points, 0)
	player._emit_ammo()


func _on_hp_changed(cur_hp: float, m_hp: float, shield: float) -> void:
	hp_bar.max_value = m_hp
	hp_bar.value = cur_hp
	hp_lbl.text = "%.0f / %.0f" % [cur_hp, m_hp]
	shield_row.visible = shield > 1.0
	if shield > 1.0:
		shield_bar.max_value = maxf(shield, 50.0)
		shield_bar.value = shield


func _on_ammo_changed(w_name: String, mag: int, reserve: int, reloading: bool, pap: bool) -> void:
	if player.is_monster_form:
		return
	weapon_icon.texture = HI.tex(HI.weapon_icon(player.get_weapon_cfg(player.get_current_weapon_id())["class"]))
	weapon_icon.modulate = HI.PURPLE if pap else HI.TEXT
	weapon_name_lbl.text = w_name
	weapon_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.42, 1.0) if pap else HI.TEXT)
	reload_icon.visible = reloading
	if reloading:
		ammo_lbl.text = "··"
		reserve_lbl.text = ""
	elif pap:
		ammo_lbl.text = "∞"
		reserve_lbl.text = "/ %d" % reserve
	else:
		ammo_lbl.text = str(mag)
		reserve_lbl.text = "/ %d" % reserve


func _on_points_changed(new_pts: int, delta_pts: int) -> void:
	points_lbl.text = str(new_pts)
	if delta_pts != 0 and is_instance_valid(points_lbl) and points_lbl.is_inside_tree():
		var pop := Label.new()
		pop.text = ("+%d" % delta_pts) if delta_pts > 0 else ("%d" % delta_pts)
		pop.add_theme_font_size_override("font_size", 20 if absi(delta_pts) < 100 else 26)
		pop.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35) if delta_pts > 0 else Color(1.0, 0.35, 0.3))
		pop.add_theme_constant_override("outline_size", 5)
		pop.add_theme_color_override("font_outline_color", Color.BLACK)
		add_child(pop)
		var start := points_lbl.global_position + Vector2(points_lbl.size.x + 12.0, randf_range(-14.0, 10.0))
		pop.position = start
		var tw := pop.create_tween()
		tw.set_parallel(true)
		tw.tween_property(pop, "position", start + Vector2(randf_range(60.0, 110.0), randf_range(-40.0, 10.0)), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(pop, "modulate:a", 0.0, 0.9).set_delay(0.25)
		tw.chain().tween_callback(pop.queue_free)


func _on_round_started(round_num: int, boss_cfg: Dictionary) -> void:
	tally_marks.set_round(round_num)
	round_sub_lbl.text = "ROUND %d" % round_num
	_show_banner("ROUND %s — ELIMINATE ALL ZOMBIES TO SUMMON %s!" % [GameState.to_roman(round_num), boss_cfg["name"]], boss_cfg["color"])
	var title := Label.new()
	title.text = "ROUND %d" % round_num
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.85, 0.08, 0.06))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.08, 0, 0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.anchor_top = 0.5
	title.anchor_bottom = 0.5
	title.offset_left = -400
	title.offset_right = 400
	title.offset_top = -190
	title.offset_bottom = -90
	title.modulate.a = 0.0
	title.pivot_offset = Vector2(400, 50)
	title.scale = Vector2(1.4, 1.4)
	add_child(title)
	var ttw := title.create_tween()
	ttw.set_parallel(true)
	ttw.tween_property(title, "modulate:a", 1.0, 0.4)
	ttw.tween_property(title, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ttw.chain().tween_interval(1.6)
	ttw.chain().tween_property(title, "modulate:a", 0.0, 0.8)
	ttw.chain().tween_callback(title.queue_free)


func _on_boss_spawned(boss: ZombieEnemy) -> void:
	boss_panel.visible = true
	_update_boss_bar(boss)
	_show_banner("BOSS ENGAGED: %s!" % boss.display_name, Color(1.0, 0.32, 0.22))


func _update_boss_bar(boss: ZombieEnemy) -> void:
	if not is_instance_valid(boss) or boss.is_dead:
		boss_panel.visible = false
		return
	boss_panel.visible = true
	boss_title_lbl.text = "ROUND %d  %s" % [GameState.current_round, boss.display_name]
	boss_sub_lbl.text = boss.boss_subtitle
	boss_hp_bar.max_value = boss.max_hp
	boss_hp_bar.value = boss.hp
	boss_hp_lbl.text = "%.0f / %.0f" % [boss.hp, boss.max_hp]
	for c in boss_status_box.get_children():
		c.queue_free()
	if boss.pain_drug_timer > 0.0:
		_boss_badge("syringe", "%.0fs" % boss.pain_drug_timer, Color(0.16, 1.0, 0.84))
	else:
		if boss.endurance > 0.0:
			_boss_badge("shield", "%.0f%%" % (boss.endurance * 100.0), HI.AMBER)
	if boss.stun_timer > 0.0:
		_boss_badge("bolt", "%.0fs" % boss.stun_timer, Color(1.0, 0.88, 0.22))


func _boss_badge(icon_name: String, txt: String, col: Color) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	boss_status_box.add_child(h)
	h.add_child(HI.icon(icon_name, 14, col))
	h.add_child(HI.label(txt, 13, col))


func _on_boss_defeated(b_name: String) -> void:
	boss_panel.visible = false
	_show_banner("%s ELIMINATED! MAX AMMO GRANTED!" % b_name, Color(1.0, 0.86, 0.25))


func _on_hitmarker(is_hs: bool, is_kill: bool, is_ability: bool) -> void:
	hitmarker_timer = 0.22 if is_kill else 0.14
	hitmarker_big = is_kill
	if is_kill or is_hs:
		hitmarker_color = Color(1.0, 0.18, 0.14)
	elif is_ability:
		hitmarker_color = Color(0.20, 0.98, 0.84)
	else:
		hitmarker_color = Color.WHITE
	hit_canvas.queue_redraw()
	if is_kill:
		GameState.play_sfx("kill_confirm", -5.0 if is_hs else -7.0, randf_range(0.95, 1.05))
	elif _tick_cd <= 0.0:
		_tick_cd = 0.04
		GameState.play_sfx("hit_tick", -10.0, randf_range(0.95, 1.08) * (1.2 if is_hs else 1.0))


const STREAK_NAMES := {2: "DOUBLE KILL", 3: "TRIPLE KILL", 4: "QUAD KILL", 5: "RAMPAGE"}


func _on_kill_streak(count: int) -> void:
	var name: String = STREAK_NAMES.get(count, "UNSTOPPABLE")
	streak_lbl.text = "%s  x%d   +%d" % [name, count, 25 * (count - 1)]
	var t := clampf(float(count - 2) / 6.0, 0.0, 1.0)
	var col := Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.25, 0.2), t)
	streak_lbl.add_theme_color_override("font_color", col)
	streak_icon.modulate = col
	streak_lbl.scale = Vector2.ONE * 1.35
	streak_lbl.get_parent().modulate.a = 1.0
	var tw := streak_lbl.create_tween()
	tw.tween_property(streak_lbl, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(streak_lbl.get_parent(), "modulate:a", 0.0, 0.4)
	if count == 3 or count == 5 or count % 5 == 0:
		GameState.play_sfx("streak_sting", -6.0, 1.0 + 0.04 * float(mini(count, 10)))


func _show_banner(txt: String, col: Color) -> void:
	banner_lbl.text = GameState.keyify(txt)
	banner_lbl.add_theme_color_override("font_color", col)
	banner_lbl.visible = true
	banner_timer = 3.8


func _on_player_died() -> void:
	if augment_menu:
		augment_menu.close()
	var ng := get_tree().get_first_node_in_group("net_game")
	if Net.is_online() and ng and not ng.game_over:
		return
	scope_canvas.visible = false
	var is_record := GameState.record_run()
	_set_interact("")
	ammo_hint_box.visible = false
	dmg_indicators.clear()
	await get_tree().create_timer(1.1).timeout
	var mode_best := GameState.best_round_infinite if GameState.game_mode == "infinite" else GameState.best_round
	var record_line := "NEW BEST ROUND!" if is_record else "BEST: ROUND %d" % mode_best
	_show_modal("skull", "YOUR SQUAD WAS OVERRUN" if Net.is_online() else "YOU WERE OVERRUN", HI.RED,
		[GameState.current_round, GameState.total_kills, GameState.headshots, GameState.bosses_slain],
		"%s\n\n%s" % [record_line, GameState.finish_run("death")])