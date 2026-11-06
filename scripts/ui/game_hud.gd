class_name GameHUD
extends CanvasLayer

var player: PlayerController
var wave_mgr: WaveManager

# Overlays
var blood_overlay: TextureRect
var monster_overlay: TextureRect

# Top Boss & Wave UI
var boss_panel: PanelContainer
var boss_title_lbl: Label
var boss_sub_lbl: Label
var boss_hp_bar: ProgressBar
var boss_status_lbl: Label
var hostiles_lbl: Label
var banner_lbl: Label
var banner_timer: float = 0.0

# Center Crosshair & Prompts
var crosshair_root: Control
var hit_canvas: Control
var streak_lbl: Label
var sub_lbl: Label
var _tick_cd: float = 0.0
var hitmarker_timer: float = 0.0
var hitmarker_color: Color = Color.WHITE
var hitmarker_big: bool = false
var interact_lbl: Label
var ammo_hint_lbl: Label

# Damage direction arcs around the crosshair
var dmg_canvas: Control
var dmg_indicators: Array = []

# Active power-ups (top-right, under the hostiles pill)
var powerups_lbl: Label

# Bottom-Left Round Tally, Points, Health
var tally_lbl: Label
var tally_marks: Control
const TallyMarksScript := preload("res://scripts/ui/tally_marks.gd")
var round_sub_lbl: Label
var points_lbl: Label
var points_popup_lbl: Label
var points_popup_timer: float = 0.0
var hp_bar: ProgressBar
var hp_lbl: Label
var perks_lbl: Label

# Bottom-Right Weapon & Skills
var weapon_name_lbl: Label
var ammo_lbl: Label
var skill_q_panel: PanelContainer
var skill_q_title: Label
var skill_q_state: Label
var skill_f_panel: PanelContainer
var skill_f_title: Label
var skill_f_state: Label

# Pause & Game Over Modal
var modal_overlay: ColorRect
var modal_title: Label
var modal_stats: Label
var resume_btn: Button
var settings_box: Control
var is_paused: bool = false

const AugmentMenuScript := preload("res://scripts/ui/augment_menu.gd")
var augment_menu: Control
var cross_ticks: Array[ColorRect] = []
var scope_canvas: Control
var stamina_bar: ProgressBar
var loadout_lbl: Label

# Extraction
var exfil_lbl: Label

# Last stand
var revive_lbl: Label
var downed_box: VBoxContainer
var downed_sub: Label
var downed_bar: ProgressBar


var borrowed_lbl: Label
var fps_lbl: Label


func setup(p_player: PlayerController, p_wave: WaveManager) -> void:
	player = p_player
	wave_mgr = p_wave
	fps_lbl = Label.new()
	fps_lbl.position = Vector2(12, 6)
	fps_lbl.add_theme_font_size_override("font_size", 15)
	fps_lbl.add_theme_constant_override("outline_size", 5)
	fps_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	fps_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	add_child(fps_lbl)
	borrowed_lbl = Label.new()
	borrowed_lbl.anchor_left = 1.0
	borrowed_lbl.anchor_right = 1.0
	borrowed_lbl.anchor_top = 1.0
	borrowed_lbl.anchor_bottom = 1.0
	borrowed_lbl.offset_left = -560
	borrowed_lbl.offset_right = -30
	borrowed_lbl.offset_top = -300
	borrowed_lbl.offset_bottom = -270
	borrowed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	borrowed_lbl.add_theme_font_size_override("font_size", 17)
	borrowed_lbl.add_theme_constant_override("outline_size", 6)
	borrowed_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	borrowed_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(borrowed_lbl)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	_build_ui()
	_build_downed_overlay()
	_build_exfil_label()
	_connect_signals()
	_refresh_all()


func _build_downed_overlay() -> void:
	downed_box = VBoxContainer.new()
	downed_box.anchor_left = 0.5
	downed_box.anchor_right = 0.5
	downed_box.anchor_top = 0.5
	downed_box.anchor_bottom = 0.5
	downed_box.offset_left = -260
	downed_box.offset_right = 260
	downed_box.offset_top = 70
	downed_box.offset_bottom = 170
	downed_box.alignment = BoxContainer.ALIGNMENT_CENTER
	downed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	downed_box.visible = false
	add_child(downed_box)
	var title := Label.new()
	title.text = "DOWNED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.95, 0.15, 0.1))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.0))
	downed_box.add_child(title)
	downed_sub = Label.new()
	downed_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	downed_sub.add_theme_font_size_override("font_size", 17)
	downed_sub.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	downed_box.add_child(downed_sub)
	downed_bar = ProgressBar.new()
	downed_bar.custom_minimum_size = Vector2(0, 10)
	downed_bar.max_value = 1.0
	downed_bar.show_percentage = false
	downed_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.15, 0.05, 0.05)))
	downed_bar.add_theme_stylebox_override("fill", _make_bar_style(Color(0.35, 1.0, 0.6)))
	downed_box.add_child(downed_bar)


func _build_exfil_label() -> void:
	exfil_lbl = Label.new()
	exfil_lbl.anchor_left = 0.5
	exfil_lbl.anchor_right = 0.5
	exfil_lbl.offset_left = -360
	exfil_lbl.offset_right = 360
	exfil_lbl.offset_top = 196
	exfil_lbl.offset_bottom = 238
	exfil_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exfil_lbl.add_theme_font_size_override("font_size", 26)
	exfil_lbl.add_theme_constant_override("outline_size", 8)
	exfil_lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.0))
	exfil_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	exfil_lbl.visible = false
	add_child(exfil_lbl)


func _update_exfil_label() -> void:
	var st: int = wave_mgr.exfil_state
	exfil_lbl.visible = st == 1 or st == 2
	if st == 1:
		var tl := maxf(0.0, wave_mgr.exfil_timer)
		exfil_lbl.text = "☢ EXTRACTION INBOUND  %d:%02d" % [int(tl) / 60, int(tl) % 60]
		exfil_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.25))
	elif st == 2:
		var tl2 := maxf(0.0, wave_mgr.exfil_timer)
		var pct := int(wave_mgr.board_progress * 100.0)
		var tail := ("   BOARDING %d%%" % pct) if pct > 0 else ""
		exfil_lbl.text = "▲ GET TO THE LADDER!  %d:%02d%s" % [int(tl2) / 60, int(tl2) % 60, tail]
		exfil_lbl.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55) if pct > 0 else Color(1.0, 0.85, 0.3))


func _on_exfil_won() -> void:
	if augment_menu:
		augment_menu.close()
	scope_canvas.visible = false
	interact_lbl.text = ""
	ammo_hint_lbl.visible = false
	downed_box.visible = false
	await get_tree().create_timer(3.6).timeout
	modal_overlay.visible = true
	resume_btn.visible = false
	settings_box.visible = false
	modal_title.text = "EXFIL SUCCESSFUL"
	modal_title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	modal_stats.text = "YOU ESCAPED OUTPOST NACHT-7 ON ROUND %d
EXTRACTIONS: %d

TOTAL ZOMBIE KILLS: %d
HEADSHOTS: %d
UNIQUE BOSSES SLAIN: %d" % [
		GameState.current_round,
		GameState.exfils,
		GameState.total_kills,
		GameState.headshots,
		GameState.bosses_slain,
	]
	modal_stats.text += "\n\n" + GameState.finish_run("exfil")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_run_won() -> void:
	if augment_menu:
		augment_menu.close()
	scope_canvas.visible = false
	interact_lbl.text = ""
	downed_box.visible = false
	await get_tree().create_timer(2.5).timeout
	modal_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_btn.visible = false
	settings_box.visible = false
	modal_title.text = "OUTBREAK CONTAINED"
	modal_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	modal_stats.text = "THE PROGENITOR IS DEAD. NACHT-7 IS SILENT.\n\nTOTAL ZOMBIE KILLS: %d\nHEADSHOTS: %d\nBOSSES SLAIN: %d\n\n%s" % [
		GameState.total_kills, GameState.headshots, GameState.bosses_slain, GameState.finish_run("victory")]


func _on_downed_changed(downed: bool) -> void:
	downed_box.visible = downed
	scope_canvas.visible = false
	_refresh_stats_line()


func _make_panel_style(bg: Color, border: Color, corner: int = 6, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _make_bar_style(col: Color, corner: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(corner)
	return sb


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 1. Screen Vignettes
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

	# 2. Top-Right Hostiles Pill
	var top_right := PanelContainer.new()
	top_right.anchor_left = 1.0
	top_right.anchor_right = 1.0
	top_right.offset_left = -335
	top_right.offset_right = -24
	top_right.offset_top = 20
	top_right.offset_bottom = 66
	top_right.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.06, 0.08, 0.82), Color(0.65, 0.14, 0.12)))
	root.add_child(top_right)

	hostiles_lbl = Label.new()
	hostiles_lbl.text = "ZOMBIES: 0"
	hostiles_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hostiles_lbl.add_theme_font_size_override("font_size", 17)
	hostiles_lbl.add_theme_color_override("font_color", Color(0.95, 0.86, 0.82))
	top_right.add_child(hostiles_lbl)

	powerups_lbl = Label.new()
	powerups_lbl.anchor_left = 1.0
	powerups_lbl.anchor_right = 1.0
	powerups_lbl.offset_left = -335
	powerups_lbl.offset_right = -24
	powerups_lbl.offset_top = 74
	powerups_lbl.offset_bottom = 130
	powerups_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	powerups_lbl.add_theme_font_size_override("font_size", 18)
	powerups_lbl.add_theme_constant_override("outline_size", 6)
	powerups_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(powerups_lbl)

	# 3. Top-Center Round Boss Health & Status Bar
	boss_panel = PanelContainer.new()
	boss_panel.anchor_left = 0.5
	boss_panel.anchor_right = 0.5
	boss_panel.offset_left = -360
	boss_panel.offset_right = 360
	boss_panel.offset_top = 18
	boss_panel.offset_bottom = 128
	boss_panel.visible = false
	boss_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.05, 0.07, 0.88), Color(0.85, 0.18, 0.14), 8, 2))
	root.add_child(boss_panel)

	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 4)
	boss_panel.add_child(bv)

	boss_title_lbl = Label.new()
	boss_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_title_lbl.add_theme_font_size_override("font_size", 20)
	boss_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.34, 0.24))
	bv.add_child(boss_title_lbl)

	boss_sub_lbl = Label.new()
	boss_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_sub_lbl.add_theme_font_size_override("font_size", 12)
	boss_sub_lbl.add_theme_color_override("font_color", Color(0.78, 0.78, 0.82))
	bv.add_child(boss_sub_lbl)

	boss_hp_bar = ProgressBar.new()
	boss_hp_bar.custom_minimum_size = Vector2(0, 18)
	boss_hp_bar.show_percentage = false
	boss_hp_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.16, 0.06, 0.06)))
	boss_hp_bar.add_theme_stylebox_override("fill", _make_bar_style(Color(0.88, 0.16, 0.14)))
	bv.add_child(boss_hp_bar)

	boss_status_lbl = Label.new()
	boss_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_status_lbl.add_theme_font_size_override("font_size", 14)
	boss_status_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	bv.add_child(boss_status_lbl)

	# Tactical Banner below Boss Bar
	banner_lbl = Label.new()
	banner_lbl.anchor_left = 0.5
	banner_lbl.anchor_right = 0.5
	banner_lbl.offset_left = -460
	banner_lbl.offset_right = 460
	banner_lbl.offset_top = 142
	banner_lbl.offset_bottom = 182
	banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_lbl.add_theme_font_size_override("font_size", 19)
	banner_lbl.add_theme_constant_override("outline_size", 6)
	banner_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	banner_lbl.visible = false
	root.add_child(banner_lbl)

	# 4. Center Crosshair, Hitmarker & Wall-Buy Prompt
	crosshair_root = Control.new()
	crosshair_root.anchor_left = 0.5
	crosshair_root.anchor_right = 0.5
	crosshair_root.anchor_top = 0.5
	crosshair_root.anchor_bottom = 0.5
	crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair_root)

	for rect_cfg in [
		Vector4(-13, -1, 8, 2),
		Vector4(5, -1, 8, 2),
		Vector4(-1, -13, 2, 8),
		Vector4(-1, 5, 2, 8),
	]:
		var tick := ColorRect.new()
		tick.position = Vector2(rect_cfg.x, rect_cfg.y)
		tick.size = Vector2(rect_cfg.z, rect_cfg.w)
		tick.color = Color(0.95, 0.95, 0.95, 0.85)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair_root.add_child(tick)
		cross_ticks.append(tick)

	# Sniper scope overlay
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

	streak_lbl = Label.new()
	streak_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	streak_lbl.set_anchors_preset(Control.PRESET_CENTER)
	streak_lbl.offset_left = -300
	streak_lbl.offset_right = 300
	streak_lbl.offset_top = 46
	streak_lbl.offset_bottom = 96
	streak_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	streak_lbl.add_theme_font_size_override("font_size", 26)
	streak_lbl.add_theme_constant_override("outline_size", 8)
	streak_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	streak_lbl.pivot_offset = Vector2(300, 25)
	streak_lbl.modulate.a = 0.0
	root.add_child(streak_lbl)

	# Commander speech subtitles
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

	ammo_hint_lbl = Label.new()
	ammo_hint_lbl.anchor_left = 0.5
	ammo_hint_lbl.anchor_right = 0.5
	ammo_hint_lbl.anchor_top = 0.5
	ammo_hint_lbl.anchor_bottom = 0.5
	ammo_hint_lbl.offset_left = -200
	ammo_hint_lbl.offset_right = 200
	ammo_hint_lbl.offset_top = 88
	ammo_hint_lbl.offset_bottom = 118
	ammo_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_hint_lbl.add_theme_font_size_override("font_size", 17)
	ammo_hint_lbl.add_theme_constant_override("outline_size", 6)
	ammo_hint_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	ammo_hint_lbl.visible = false
	root.add_child(ammo_hint_lbl)

	interact_lbl = Label.new()
	interact_lbl.anchor_left = 0.5
	interact_lbl.anchor_right = 0.5
	interact_lbl.anchor_top = 0.5
	interact_lbl.anchor_bottom = 0.5
	interact_lbl.offset_left = -280
	interact_lbl.offset_right = 280
	interact_lbl.offset_top = 46
	interact_lbl.offset_bottom = 84
	interact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_lbl.add_theme_font_size_override("font_size", 19)
	interact_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.48))
	interact_lbl.add_theme_constant_override("outline_size", 6)
	interact_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(interact_lbl)

	# 5. Bottom-Left: COD Zombies Blood Chalk Tally + Points + HP
	var bl_box := VBoxContainer.new()
	bl_box.anchor_top = 1.0
	bl_box.anchor_bottom = 1.0
	bl_box.offset_left = 28
	bl_box.offset_right = 410
	bl_box.offset_top = -262
	bl_box.offset_bottom = -24
	bl_box.add_theme_constant_override("separation", 6)
	root.add_child(bl_box)

	tally_lbl = Label.new()
	tally_lbl.text = "I"
	tally_lbl.add_theme_font_size_override("font_size", 58)
	tally_lbl.add_theme_color_override("font_color", Color(0.86, 0.10, 0.08))
	tally_lbl.add_theme_constant_override("outline_size", 8)
	tally_lbl.add_theme_color_override("font_outline_color", Color(0.12, 0.01, 0.01))
	tally_lbl.visible = false
	bl_box.add_child(tally_lbl)
	tally_marks = TallyMarksScript.new()
	bl_box.add_child(tally_marks)

	round_sub_lbl = Label.new()
	round_sub_lbl.text = "ROUND 1"
	round_sub_lbl.add_theme_font_size_override("font_size", 14)
	round_sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.65, 0.62))
	bl_box.add_child(round_sub_lbl)

	var pts_row := HBoxContainer.new()
	pts_row.add_theme_constant_override("separation", 12)
	bl_box.add_child(pts_row)

	points_lbl = Label.new()
	points_lbl.text = "500 PTS"
	points_lbl.add_theme_font_size_override("font_size", 28)
	points_lbl.add_theme_color_override("font_color", Color(0.98, 0.78, 0.25))
	points_lbl.add_theme_constant_override("outline_size", 6)
	points_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	pts_row.add_child(points_lbl)

	points_popup_lbl = Label.new()
	points_popup_lbl.text = ""
	points_popup_lbl.add_theme_font_size_override("font_size", 20)
	points_popup_lbl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.45))
	pts_row.add_child(points_popup_lbl)

	var hp_panel := PanelContainer.new()
	hp_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.06, 0.08, 0.85), Color(0.42, 0.45, 0.52), 6, 1))
	bl_box.add_child(hp_panel)

	var hp_v := VBoxContainer.new()
	hp_v.add_theme_constant_override("separation", 4)
	hp_panel.add_child(hp_v)

	hp_lbl = Label.new()
	hp_lbl.add_theme_font_size_override("font_size", 14)
	hp_lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	hp_v.add_child(hp_lbl)

	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 14)
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.15, 0.15, 0.18)))
	hp_bar.add_theme_stylebox_override("fill", _make_bar_style(Color(0.84, 0.18, 0.18)))
	hp_v.add_child(hp_bar)

	stamina_bar = ProgressBar.new()
	stamina_bar.custom_minimum_size = Vector2(0, 6)
	stamina_bar.show_percentage = false
	stamina_bar.max_value = 1.0
	stamina_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.15, 0.15, 0.18), 2))
	stamina_bar.add_theme_stylebox_override("fill", _make_bar_style(Color(0.95, 0.85, 0.35), 2))
	hp_v.add_child(stamina_bar)

	perks_lbl = Label.new()
	perks_lbl.text = ""
	perks_lbl.add_theme_font_size_override("font_size", 13)
	perks_lbl.add_theme_color_override("font_color", Color(1.0, 0.65, 0.35))
	hp_v.add_child(perks_lbl)

	revive_lbl = Label.new()
	revive_lbl.text = ""
	revive_lbl.add_theme_font_size_override("font_size", 13)
	revive_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	hp_v.add_child(revive_lbl)

	# 6. Bottom-Right: Weapon Ammo & Character Skills [Q] / [F]
	var br_box := VBoxContainer.new()
	br_box.anchor_left = 1.0
	br_box.anchor_right = 1.0
	br_box.anchor_top = 1.0
	br_box.anchor_bottom = 1.0
	br_box.offset_left = -548
	br_box.offset_right = -28
	br_box.offset_top = -262
	br_box.offset_bottom = -24
	br_box.add_theme_constant_override("separation", 8)
	root.add_child(br_box)

	var skills_row := HBoxContainer.new()
	skills_row.add_theme_constant_override("separation", 10)
	br_box.add_child(skills_row)

	skill_q_panel = PanelContainer.new()
	skill_q_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_q_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.08, 0.11, 0.88), Color(0.35, 0.78, 0.92)))
	skills_row.add_child(skill_q_panel)
	var qv := VBoxContainer.new()
	skill_q_panel.add_child(qv)
	skill_q_title = Label.new()
	skill_q_title.add_theme_font_size_override("font_size", 14)
	skill_q_title.add_theme_color_override("font_color", Color(0.85, 0.94, 1.0))
	qv.add_child(skill_q_title)
	skill_q_state = Label.new()
	skill_q_state.add_theme_font_size_override("font_size", 13)
	skill_q_state.add_theme_color_override("font_color", Color(0.45, 1.0, 0.72))
	qv.add_child(skill_q_state)

	skill_f_panel = PanelContainer.new()
	skill_f_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_f_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.06, 0.09, 0.88), Color(0.92, 0.35, 0.25)))
	skills_row.add_child(skill_f_panel)
	var fv := VBoxContainer.new()
	skill_f_panel.add_child(fv)
	skill_f_title = Label.new()
	skill_f_title.add_theme_font_size_override("font_size", 14)
	skill_f_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.84))
	fv.add_child(skill_f_title)
	skill_f_state = Label.new()
	skill_f_state.add_theme_font_size_override("font_size", 13)
	skill_f_state.add_theme_color_override("font_color", Color(1.0, 0.75, 0.32))
	fv.add_child(skill_f_state)

	var wep_panel := PanelContainer.new()
	wep_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.06, 0.08, 0.88), Color(0.55, 0.56, 0.62)))
	br_box.add_child(wep_panel)
	var wvv := VBoxContainer.new()
	wvv.add_theme_constant_override("separation", 2)
	wep_panel.add_child(wvv)
	var wv := HBoxContainer.new()
	wvv.add_child(wv)
	loadout_lbl = Label.new()
	loadout_lbl.add_theme_font_size_override("font_size", 13)
	loadout_lbl.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	wvv.add_child(loadout_lbl)

	weapon_name_lbl = Label.new()
	weapon_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_name_lbl.add_theme_font_size_override("font_size", 18)
	weapon_name_lbl.add_theme_color_override("font_color", Color(0.90, 0.92, 0.96))
	wv.add_child(weapon_name_lbl)

	ammo_lbl = Label.new()
	ammo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_lbl.add_theme_font_size_override("font_size", 32)
	ammo_lbl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	wv.add_child(ammo_lbl)

	# 7. Pause & Game Over Modal
	modal_overlay = ColorRect.new()
	modal_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_overlay.color = Color(0.02, 0.02, 0.03, 0.82)
	modal_overlay.visible = false
	add_child(modal_overlay)

	var m_card := PanelContainer.new()
	m_card.anchor_left = 0.5
	m_card.anchor_right = 0.5
	m_card.anchor_top = 0.5
	m_card.anchor_bottom = 0.5
	m_card.offset_left = -260
	m_card.offset_right = 260
	m_card.offset_top = -215
	m_card.offset_bottom = 215
	m_card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.07, 0.09, 0.96), Color(0.82, 0.16, 0.14), 10, 2))
	modal_overlay.add_child(m_card)

	var mv := VBoxContainer.new()
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", 16)
	m_card.add_child(mv)

	modal_title = Label.new()
	modal_title.text = "PAUSED"
	modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_title.add_theme_font_size_override("font_size", 34)
	modal_title.add_theme_color_override("font_color", Color(0.92, 0.18, 0.15))
	mv.add_child(modal_title)

	modal_stats = Label.new()
	modal_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_stats.add_theme_font_size_override("font_size", 17)
	modal_stats.add_theme_color_override("font_color", Color(0.88, 0.88, 0.90))
	mv.add_child(modal_stats)

	var opt_scroll := ScrollContainer.new()
	opt_scroll.custom_minimum_size = Vector2(560, 300)
	opt_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mv.add_child(opt_scroll)
	settings_box = opt_scroll
	var opts := OptionsPanel.new()
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_scroll.add_child(opts)

	resume_btn = Button.new()
	resume_btn.text = "RESUME COMBAT"
	resume_btn.custom_minimum_size = Vector2(0, 44)
	resume_btn.pressed.connect(_toggle_pause)
	mv.add_child(resume_btn)

	var restart_btn := Button.new()
	restart_btn.text = "BACK TO LOBBY (WHOLE SQUAD)" if Net.is_online() else "RESTART OUTBREAK"
	restart_btn.visible = not Net.is_client()
	restart_btn.custom_minimum_size = Vector2(0, 44)
	restart_btn.pressed.connect(func():
		if Net.is_online():
			Net.return_to_lobby()
			return
		get_tree().paused = false
		GameState.reset_run()
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	)
	mv.add_child(restart_btn)

	var menu_btn := Button.new()
	menu_btn.text = "LEAVE SQUAD" if Net.is_online() else "MAIN MENU"
	menu_btn.custom_minimum_size = Vector2(0, 44)
	menu_btn.pressed.connect(func():
		Net.leave()
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	mv.add_child(menu_btn)


func _add_slider_row(parent: Control, title: String, min_v: float, max_v: float, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = title
	lbl.custom_minimum_size = Vector2(190, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.80, 0.82, 0.86))
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.05
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(48, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.text = "%.2f" % value
	row.add_child(val_lbl)
	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%.2f" % v
		on_change.call(v)
	)


func _connect_signals() -> void:
	player.hp_changed.connect(_on_hp_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	player.hitmarker_triggered.connect(_on_hitmarker)
	player.kill_streak.connect(_on_kill_streak)
	player.status_banner_requested.connect(_show_banner)
	player.interact_prompt_changed.connect(func(txt: String): interact_lbl.text = GameState.keyify(txt))
	player.player_died.connect(_on_player_died)
	player.damaged.connect(_on_player_damaged)
	player.stats_changed.connect(_refresh_stats_line)
	player.downed_changed.connect(_on_downed_changed)

	augment_menu = AugmentMenuScript.new()
	add_child(augment_menu)

	GameState.points_changed.connect(_on_points_changed)
	wave_mgr.round_started.connect(_on_round_started)
	wave_mgr.wave_status_changed.connect(func(txt: String): hostiles_lbl.text = txt)
	wave_mgr.boss_spawned.connect(_on_boss_spawned)
	wave_mgr.boss_updated.connect(_update_boss_bar)
	wave_mgr.boss_defeated.connect(_on_boss_defeated)
	wave_mgr.exfil_won.connect(_on_exfil_won)
	wave_mgr.run_won.connect(_on_run_won)


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
	var parts: Array[String] = []
	for st in GameState.STATS:
		var lv := player.stat_level(st["id"])
		if lv > 0:
			parts.append("%s %d" % [String(st["name"]).substr(0, 3), lv])
	perks_lbl.text = "  ".join(parts)
	revive_lbl.text = "✚ SECOND WIND READY" if player.revives > 0 else ""


func _toggle_pause() -> void:
	is_paused = not is_paused
	get_tree().paused = is_paused and not Net.is_online() # online the world keeps going
	modal_overlay.visible = is_paused
	if is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		modal_title.text = "MISSION PAUSED"
		resume_btn.visible = true
		settings_box.visible = true
		modal_stats.text = ("CASUAL" if GameState.game_mode == "casual" else "INFINITE") + "  •  ROUND %d  •  KILLS: %d  •  BOSSES SLAIN: %d" % [GameState.current_round, GameState.total_kills, GameState.bosses_slain]
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if fps_lbl:
		fps_lbl.visible = GameState.show_fps
		if GameState.show_fps:
			fps_lbl.text = "%d FPS" % Engine.get_frames_per_second()
	if borrowed_lbl and is_instance_valid(player):
		var lines: Array[String] = []
		for slot in [[player.borrowed_skill, player.borrowed_cd, "X"], [player.borrowed_skill2, player.borrowed_cd2, "Z"]]:
			if slot[0] != "":
				var sk_name: String = PlayerController.BORROWED_SKILLS[slot[0]]["name"]
				lines.append("[%s] %s — %s" % [slot[2], sk_name, "READY" if slot[1] <= 0.0 else "%ds" % int(ceil(slot[1]))])
		var placed: int = player.placed_c4()
		if player.c4_count > 0 or player.mines > 0 or placed > 0:
			lines.append("[T] C4 x%d%s   [B] MINES x%d" % [player.c4_count, ("  (HOLD T: BOOM x%d)" % placed) if placed > 0 else "", player.mines])
		if player.pending_skill_t > 0.0:
			lines.append("NEW: %s — PRESS [X]%s TO SWAP (%ds)" % [PlayerController.BORROWED_SKILLS[player.pending_skill]["name"], "/[Z]" if GameState.has_unlock("skill_slot") else "", int(ceil(player.pending_skill_t))])
		borrowed_lbl.text = "\n".join(lines)
		borrowed_lbl.offset_top = -300 - 24 * maxi(0, lines.size() - 1)
		borrowed_lbl.add_theme_color_override("font_color", Color(0.75, 0.5, 1.0))
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

	# Update screen overlays & live skill timers
	var hp_ratio := clampf(player.hp / maxf(1.0, player.max_hp), 0.0, 1.0)
	var target_blood := clampf((0.82 - hp_ratio) * 1.25, 0.0, 0.92)
	blood_overlay.modulate.a = lerp(blood_overlay.modulate.a, target_blood, 8.0 * delta)

	var target_monster := 0.72 if player.is_monster_form else 0.0
	monster_overlay.modulate.a = lerp(monster_overlay.modulate.a, target_monster, 8.0 * delta)

	_update_skill_cards()
	_update_powerups()
	_update_ammo_hint()
	_update_crosshair()
	_update_heartbeat(delta)
	_update_exfil_label()
	if player.is_downed:
		if player.self_reviving:
			downed_bar.value = 1.0 - player.downed_timer / PlayerController.DOWNED_TIME
			downed_sub.text = "SECOND WIND IN %.1fs — KEEP SHOOTING!" % maxf(0.0, player.downed_timer)
		else:
			downed_bar.value = player.bleedout_timer / PlayerController.BLEEDOUT_TIME
			downed_sub.text = "BLEEDING OUT %.0fs — A TEAMMATE CAN HOLD [E] ON YOU TO REVIVE" % maxf(0.0, player.bleedout_timer)


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
	var others: Array[String] = []
	for i in range(player.weapons_owned.size()):
		if i != player.active_slot:
			others.append("[%d] %s" % [i + 1, player.get_weapon_cfg(player.weapons_owned[i])["name"]])
	loadout_lbl.text = "%s    GRENADES [G]: %d" % ["   ".join(others), player.grenades]


func _draw_scope() -> void:
	var sz := scope_canvas.size
	var c := sz * 0.5
	var r := sz.y * 0.46
	# Black everywhere outside the lens: one very thick ring
	var outer := c.length() + 4.0
	scope_canvas.draw_arc(c, (r + outer) * 0.5, 0, TAU, 128, Color.BLACK, outer - r + 2.0)
	scope_canvas.draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), Color(0, 0, 0, 0.85), 2.0)
	scope_canvas.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), Color(0, 0, 0, 0.85), 2.0)
	scope_canvas.draw_circle(c, 3.0, Color(1.0, 0.2, 0.15))


func _update_powerups() -> void:
	var lines: Array[String] = []
	if GameState.is_powerup_active("insta_kill"):
		lines.append("☠ INSTA-KILL  %ds" % ceili(GameState.powerup_timers["insta_kill"]))
	if GameState.is_powerup_active("double_points"):
		lines.append("x2 DOUBLE POINTS  %ds" % ceili(GameState.powerup_timers["double_points"]))
	if GameState.is_powerup_active("fire_sale"):
		lines.append("$ FIRE SALE  %ds" % ceili(GameState.powerup_timers["fire_sale"]))
	var pl := get_tree().get_first_node_in_group("player")
	if pl and float(pl.get("adrenaline_timer")) > 0.0:
		lines.append("⚡ ADRENALINE  %ds" % ceili(float(pl.get("adrenaline_timer"))))
	powerups_lbl.text = "\n".join(lines)
	var dp := GameState.is_powerup_active("double_points")
	points_lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.45) if dp else Color(0.98, 0.78, 0.25))


func _update_ammo_hint() -> void:
	if player.is_dead or player.is_monster_form or player.is_reloading or player.pap_timer > 0.0:
		ammo_hint_lbl.visible = false
		return
	var w_id := player.get_current_weapon_id()
	var mag: int = player.mag_ammo[w_id]
	var reserve: int = player.reserve_ammo[w_id]
	var mag_size: int = player.get_weapon_cfg(w_id)["mag_size"]
	var low := mag <= ceili(mag_size * 0.25)
	if mag <= 0 and reserve <= 0:
		ammo_hint_lbl.text = "NO AMMO — BUY AT A WALL OR AMMO CACHE"
		ammo_hint_lbl.add_theme_color_override("font_color", Color(1.0, 0.30, 0.25))
		ammo_hint_lbl.visible = true
	elif low and reserve > 0:
		ammo_hint_lbl.text = "[R] RELOAD"
		ammo_hint_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		ammo_hint_lbl.visible = true
	else:
		ammo_hint_lbl.visible = false
	ammo_lbl.add_theme_color_override("font_color", Color(1.0, 0.38, 0.30) if low else Color(1.0, 0.96, 0.88))


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
		# Straight ahead points to the top of the screen; clockwise is positive.
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


func _update_skill_cards() -> void:
	match player.char_id:
		"ravager":
			if player.is_monster_form:
				weapon_name_lbl.text = "RAVAGER BEAST CLAWS"
				weapon_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.32, 0.20))
				ammo_lbl.text = "%.1fs" % player.monster_timer

				skill_q_title.text = "[LMB] SKILL 1: SAVAGE REND"
				skill_q_state.text = "1-TARGET • 480 HIGH DMG (READY)"
				skill_f_title.text = "[RMB / Q] SKILL 2: SEISMIC SLAM"
				if player.monster_slam_cd > 0.0:
					skill_f_state.text = "COOLDOWN %.1fs" % player.monster_slam_cd
				else:
					skill_f_state.text = "AOE + 4.0s STUN (READY!)"
			else:
				skill_q_title.text = GameState.keyify("[Q] FERAL LUNGE SLASH")
				skill_q_state.text = ("CD %.1fs" % player.human_lunge_cd) if player.human_lunge_cd > 0.0 else "READY"
				skill_f_title.text = GameState.keyify("[F] MONSTER TRANSFORM")
				skill_f_state.text = ("RECHARGING %.1fs" % player.monster_cd) if player.monster_cd > 0.0 else "READY — PRESS [F]!"

		"alchemist":
			skill_q_title.text = GameState.keyify("[Q] NOCICEPT-X PAIN DRUG")
			if player.pain_drug_charges > 0:
				skill_q_state.text = "%d / %d DOSES READY (FOR BOSS!)" % [player.pain_drug_charges, player.pain_drug_max]
			else:
				var rem := maxf(0.0, player.pain_drug_synth_time - player.pain_drug_synth_progress)
				skill_q_state.text = "SYNTHESIZING (%.1fs)" % rem
			skill_f_title.text = GameState.keyify("[F] PAINKILLER STIM")
			if player.stim_timer > 0.0:
				skill_f_state.text = "ACTIVE %.1fs" % player.stim_timer
			elif player.stim_cd > 0.0:
				skill_f_state.text = "CD %.1fs" % player.stim_cd
			else:
				skill_f_state.text = "READY (+HEAL & +1 DRUG)"

		"warden":
			skill_q_title.text = GameState.keyify("[Q] TESLA CONCUSSION")
			skill_q_state.text = ("CD %.1fs" % player.tesla_cd) if player.tesla_cd > 0.0 else "READY (AOE + 2.5s STUN)"
			skill_f_title.text = GameState.keyify("[F] ARC OVERCHARGE")
			if player.pap_timer > 0.0:
				skill_f_state.text = "ACTIVE %.1fs (2.2x DMG)" % player.pap_timer
			elif player.pap_cd > 0.0:
				skill_f_state.text = "CD %.1fs" % player.pap_cd
			else:
				skill_f_state.text = "READY!"


func _refresh_all() -> void:
	_on_hp_changed(player.hp, player.max_hp, player.overshield)
	_on_points_changed(GameState.points, 0)
	player._emit_ammo()


func _on_hp_changed(cur_hp: float, m_hp: float, shield: float) -> void:
	hp_bar.max_value = m_hp
	hp_bar.value = cur_hp
	var sh_txt := ("  [+%.0f SHIELD]" % shield) if shield > 1.0 else ""
	hp_lbl.text = "VITALITY: %.0f / %.0f%s" % [cur_hp, m_hp, sh_txt]


func _on_ammo_changed(w_name: String, mag: int, reserve: int, reloading: bool, pap: bool) -> void:
	if player.is_monster_form:
		return
	weapon_name_lbl.text = ("[ARC] " if pap else "") + w_name
	weapon_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.42, 1.0) if pap else Color(0.90, 0.92, 0.96))
	if reloading:
		ammo_lbl.text = "RELOAD..."
	elif pap:
		ammo_lbl.text = "∞ / %d" % reserve
	else:
		ammo_lbl.text = "%d / %d" % [mag, reserve]


func _on_points_changed(new_pts: int, delta_pts: int) -> void:
	points_lbl.text = "%d PTS" % new_pts
	if delta_pts != 0 and is_instance_valid(points_lbl) and points_lbl.is_inside_tree():
		# Floating "+10" popups that drift off the score, like the classic zombies HUD
		var pop := Label.new()
		pop.text = ("+%d" % delta_pts) if delta_pts > 0 else ("%d" % delta_pts)
		pop.add_theme_font_size_override("font_size", 22 if absi(delta_pts) < 100 else 28)
		pop.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35) if delta_pts > 0 else Color(1.0, 0.35, 0.3))
		pop.add_theme_constant_override("outline_size", 6)
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
	# Authentic COD Zombies tally marks for Rounds 1-5, Roman numerals afterwards
	var tallies := ["", "I", "II", "III", "IIII", "||||/"]
	tally_lbl.text = tallies[round_num] if round_num <= 5 else GameState.to_roman(round_num)
	tally_marks.set_round(round_num)
	round_sub_lbl.text = "ROUND %d  //  BOSS: %s" % [round_num, boss_cfg["name"]]

	# Flash round counter white -> blood red!
	tally_lbl.add_theme_color_override("font_color", Color.WHITE)
	var tw := create_tween()
	tw.tween_property(tally_lbl, "theme_override_colors/font_color", Color(0.86, 0.10, 0.08), 1.8)

	_show_banner("ROUND %s — ELIMINATE ALL ZOMBIES TO SUMMON %s!" % [GameState.to_roman(round_num), boss_cfg["name"]], boss_cfg["color"])

	# Big blood-red round title in the middle of the screen
	var title := Label.new()
	title.text = "ROUND %d" % round_num
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.85, 0.08, 0.06))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.08, 0.0, 0.0))
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
	_show_banner("⚠ BOSS ENGAGED: %s!" % boss.display_name, Color(1.0, 0.32, 0.22))


func _update_boss_bar(boss: ZombieEnemy) -> void:
	if not is_instance_valid(boss) or boss.is_dead:
		boss_panel.visible = false
		return
	boss_panel.visible = true
	boss_title_lbl.text = "☠ ROUND %d BOSS: %s" % [GameState.current_round, boss.display_name]
	boss_sub_lbl.text = boss.boss_subtitle
	boss_hp_bar.max_value = boss.max_hp
	boss_hp_bar.value = boss.hp

	var badges: Array[String] = []
	if boss.pain_drug_timer > 0.0:
		badges.append("💉 PAIN DRUG ACTIVE (%.1fs): -55%% ATK | -45%% SPD | ARMOR SHATTERED (+60%% VULN)" % boss.pain_drug_timer)
		boss_status_lbl.add_theme_color_override("font_color", Color(0.16, 1.0, 0.84))
	else:
		if boss.endurance > 0.0:
			badges.append("🛡 %.0f%% ENDURANCE ARMOR" % (boss.endurance * 100.0))
		boss_status_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))

	if boss.stun_timer > 0.0:
		badges.append("⚡ STUNNED (%.1fs)" % boss.stun_timer)
		boss_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.22))

	boss_status_lbl.text = "   •   ".join(badges) if badges.size() > 0 else ("HP: %.0f / %.0f" % [boss.hp, boss.max_hp])


func _on_boss_defeated(b_name: String) -> void:
	boss_panel.visible = false
	_show_banner("☠ %s ELIMINATED! MAX AMMO GRANTED!" % b_name, Color(1.0, 0.86, 0.25))


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
	streak_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.25, 0.2), t))
	streak_lbl.scale = Vector2.ONE * 1.35
	streak_lbl.modulate.a = 1.0
	var tw := streak_lbl.create_tween()
	tw.tween_property(streak_lbl, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(streak_lbl, "modulate:a", 0.0, 0.4)
	if count == 3 or count == 5 or count % 5 == 0:
		GameState.play_sfx("streak_sting", -6.0, 1.0 + 0.04 * float(mini(count, 10)))


func _show_banner(txt: String, col: Color) -> void:
	banner_lbl.text = GameState.keyify(txt)
	banner_lbl.add_theme_color_override("font_color", col)
	banner_lbl.visible = true
	banner_timer = 3.8


func _on_player_died() -> void:
	var ng := get_tree().get_first_node_in_group("net_game")
	if Net.is_online() and ng and not ng.game_over:
		return # spectating until the next round (NetGame)
	if augment_menu:
		augment_menu.close()
	scope_canvas.visible = false
	var is_record := GameState.record_run()
	interact_lbl.text = ""
	ammo_hint_lbl.visible = false
	dmg_indicators.clear()
	# Let the death camera fall before the screen comes up.
	await get_tree().create_timer(1.1).timeout
	modal_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # co-op deaths keep the mouse captured for spectating
	resume_btn.visible = false
	settings_box.visible = false
	modal_title.text = "YOUR SQUAD WAS OVERRUN" if Net.is_online() else "YOU WERE OVERRUN"
	var record_line := "★ NEW BEST ROUND! ★" if is_record else "BEST: ROUND %d" % GameState.best_round
	modal_stats.text = "YOU SURVIVED %d ROUND(S)\n%s\n\nTOTAL ZOMBIE KILLS: %d\nHEADSHOTS: %d\nUNIQUE BOSSES SLAIN: %d" % [
		GameState.current_round,
		record_line,
		GameState.total_kills,
		GameState.headshots,
		GameState.bosses_slain
	]
	modal_stats.text += "\n\n" + GameState.finish_run("death")
