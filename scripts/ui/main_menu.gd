extends Node3D
# Main menu: the outpost as a slowly drifting 3D backdrop, a navigation rail
# on the left (Continue / Play / Co-op / Career / Options / Quit) and one
# content panel on the right for the selected section.

const ACCENT := Color(0.95, 0.32, 0.22)
const ACCENT_BLUE := Color(0.45, 0.85, 1.0)
const MODES := {
	"casual": {"name": "CASUAL", "desc": "Survive 20 rounds, then kill THE PROGENITOR to contain the outbreak. Escape by chopper from round 8."},
	"infinite": {"name": "INFINITE", "desc": "Endless rounds that keep getting harder. No final boss — just how long you last."},
}

var menu_cam: Camera3D
var cam_pivot: Node3D
var stage_pivot: Node3D
var _orbit_time: float = 0.0

var _pages: Dictionary = {}
var _nav: Dictionary = {}
var _content_title: Label
var _char_cards: Dictionary = {}
var _mode_cards: Dictionary = {}
var _diff_buttons: Array[Button] = []
var _diff_info: Label
var _deploy_btn: Button
var _detail_name: Label
var _detail_code: Label
var _detail_summary: Label
var _detail_stats: Label
var _detail_skills: Label
var _coop_settings: Label

# Co-op lobby widgets
var coop_status: Label
var coop_roster: Label
var coop_ip: LineEdit
var coop_start: Button
var coop_resume: Button
var coop_invite: Button
var coop_host_steam: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_3d_diorama()
	_build_ui()
	_select_character(GameState.selected_character)
	_show_page("coop" if Net.is_online() or Net.status_text != "" else "play")


func _process(delta: float) -> void:
	_orbit_time += delta * 0.25
	if is_instance_valid(cam_pivot):
		cam_pivot.rotation.y = sin(_orbit_time) * 0.14
	if is_instance_valid(stage_pivot):
		stage_pivot.rotation.y = sin(_orbit_time * 1.4) * 0.18


# ---------------------------------------------------------------------------
# 3D BACKDROP
# ---------------------------------------------------------------------------
func _build_3d_diorama() -> void:
	var arena := BunkerArena.new()
	add_child(arena)
	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(0.0, 0.0, 1.5)
	add_child(cam_pivot)
	menu_cam = Camera3D.new()
	menu_cam.position = Vector3(-2.6, 2.0, 8.4)
	menu_cam.rotation_degrees = Vector3(-5.0, -14.0, 0.0)
	menu_cam.fov = 58.0
	menu_cam.current = true
	cam_pivot.add_child(menu_cam)
	stage_pivot = Node3D.new()
	stage_pivot.position = Vector3(-0.6, 0.0, 2.8)
	add_child(stage_pivot)
	var key_spot := SpotLight3D.new()
	key_spot.light_color = Color(1.0, 0.72, 0.45)
	key_spot.light_energy = 6.5
	key_spot.spot_range = 14.0
	key_spot.spot_angle = 38.0
	key_spot.look_at_from_position(Vector3(0.0, 5.2, 6.5), Vector3(-0.6, 1.4, 2.8), Vector3.UP)
	add_child(key_spot)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.95, 0.22, 0.16)
	rim.light_energy = 3.2
	rim.omni_range = 8.0
	rim.position = Vector3(1.4, 2.6, 0.8)
	add_child(rim)
	for m in [["res://assets/models/zombie_soldier_v2.glb", Vector3(-1.3, 0, 0.3), 200.0, 1.0],
			["res://assets/models/boss_gorilla.glb", Vector3(0.9, 0, -0.5), 165.0, 1.25],
			["res://assets/models/zombie_walker_v2.glb", Vector3(-0.1, 0, 0.9), 185.0, 1.0]]:
		if ResourceLoader.exists(m[0]):
			var n := (load(m[0]) as PackedScene).instantiate() as Node3D
			n.position = m[1]
			n.rotation_degrees.y = m[2]
			n.scale = Vector3.ONE * float(m[3])
			stage_pivot.add_child(n)


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
	th.set_color("font_color", "Button", Color(0.9, 0.92, 0.95))
	th.set_color("font_hover_color", "Button", Color(1, 1, 1))
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.5))
	th.set_font_size("font_size", "Button", 16)
	th.set_font_size("font_size", "Label", 15)
	th.set_color("font_color", "Label", Color(0.86, 0.88, 0.92))
	th.set_stylebox("normal", "LineEdit", _box(Color(0.04, 0.05, 0.07, 0.95), Color(1, 1, 1, 0.15), 1))
	return th


func _label(text: String, size: int, col: Color = Color(0.86, 0.88, 0.92), wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _header(parent: Control, text: String) -> void:
	var l := _label(text, 13, ACCENT)
	parent.add_child(l)


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

	# Dark fade on the left so the rail reads over the 3D scene
	var fade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.01, 0.01, 0.02, 0.92))
	grad.set_color(1, Color(0.01, 0.01, 0.02, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	fade.texture = gt
	fade.anchor_bottom = 1.0
	fade.offset_right = 760
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)

	# Title + career line
	var title_box := VBoxContainer.new()
	title_box.position = Vector2(56, 44)
	title_box.add_theme_constant_override("separation", 0)
	root.add_child(title_box)
	title_box.add_child(_label("OUTPOST NACHT-7  //  CLASSIFIED", 13, ACCENT))
	var t1 := _label("DEAD PROTOCOL", 58, Color(0.96, 0.96, 0.98))
	t1.add_theme_constant_override("outline_size", 6)
	t1.add_theme_color_override("font_outline_color", Color.BLACK)
	title_box.add_child(t1)
	title_box.add_child(_label("NACHT OUTBREAK", 22, Color(0.75, 0.77, 0.82)))
	var lvl := GameState.career_level()
	var career := _label("CAREER LEVEL %d   •   %d XP" % [lvl, GameState.career_xp], 14, ACCENT_BLUE)
	title_box.add_child(Control.new())
	title_box.add_child(career)

	# Navigation rail
	var rail := VBoxContainer.new()
	rail.position = Vector2(56, 250)
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
	_nav_button(rail, "intel", "INTEL", "ZOMBIE RANKS, EVENTS & TIPS", func(): _show_page("intel"))
	_nav_button(rail, "options", "OPTIONS", "AUDIO, CONTROLS, VIDEO", func(): _show_page("options"))
	_nav_button(rail, "quit", "QUIT", "", func(): get_tree().quit())

	var foot := _label("[WASD] MOVE   [SHIFT] SPRINT   [C] CROUCH/SLIDE   [SPACE] JUMP   [LMB/RMB] FIRE/AIM   [R] RELOAD   [V] KNIFE   [G] GRENADE   [Q]/[F] SKILLS   [X]/[Z] RELIC SKILLS   [T] C4   [B] MINE   [E] USE   [ESC] PAUSE", 11, Color(0.55, 0.58, 0.63))
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 56
	foot.offset_top = -34
	root.add_child(foot)

	# Content panel
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -690
	panel.offset_right = -40
	panel.offset_top = 40
	panel.offset_bottom = -40
	var pst := _box(Color(0.03, 0.035, 0.045, 0.9), Color(1, 1, 1, 0.06), 1)
	pst.border_width_top = 3
	pst.border_color = ACCENT
	pst.content_margin_left = 26
	pst.content_margin_right = 26
	pst.content_margin_top = 20
	pst.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", pst)
	root.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 12)
	panel.add_child(pv)
	_content_title = _label("", 30, Color(0.97, 0.97, 0.99))
	pv.add_child(_content_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)

	_pages["play"] = _build_play_page()
	_pages["coop"] = _build_coop_page()
	_pages["career"] = _build_career_page()
	_pages["intel"] = _build_intel_page()
	var opts := OptionsPanel.new()
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages["options"] = opts
	for k in _pages:
		stack.add_child(_pages[k])


func _nav_button(parent: Control, key: String, title: String, sub: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = "%s\n%s" % [title, sub] if sub != "" else title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(300, 58 if sub != "" else 46)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0), 0, 3))
	b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.06), ACCENT, 0, 4))
	b.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.1), ACCENT, 0, 4))
	b.pressed.connect(func():
		GameState.play_sfx("buy_ching", -12.0, 1.4)
		on_press.call()
	)
	parent.add_child(b)
	_nav[key] = b


func _show_page(key: String) -> void:
	var titles := {"play": "PLAY", "coop": "CO-OP SQUAD", "career": "CAREER", "intel": "INTEL", "options": "OPTIONS"}
	_content_title.text = titles.get(key, "")
	for k in _pages:
		_pages[k].visible = k == key
	for k in _nav:
		var on: bool = k == key
		(_nav[k] as Button).add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.08) if on else Color(0, 0, 0, 0), ACCENT if on else Color(0, 0, 0, 0), 0, 4 if on else 0))
	if key == "coop":
		_refresh_coop()
	elif key == "career":
		_pages["career"].queue_free()
		_pages["career"] = _build_career_page()
		_pages["play"].get_parent().add_child(_pages["career"])
		_pages["career"].visible = true


# ---------------------------------------------------------------------------
# PLAY
# ---------------------------------------------------------------------------
func _build_play_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
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
		b.pressed.connect(func():
			GameState.play_sfx("buy_ching", -8.0, 1.15)
			_select_character(cid)
		)
		row.add_child(b)
		_char_cards[cid] = b
	_detail_code = _label("", 13, ACCENT)
	v.add_child(_detail_code)
	_detail_name = _label("", 22, Color(0.97, 0.97, 0.99))
	v.add_child(_detail_name)
	_detail_summary = _label("", 14, Color(0.78, 0.8, 0.85), true)
	v.add_child(_detail_summary)
	_detail_stats = _label("", 13, Color(1.0, 0.8, 0.4))
	v.add_child(_detail_stats)
	_detail_skills = _label("", 13, Color(0.86, 0.88, 0.92), true)
	v.add_child(_detail_skills)

	_header(v, "MODE")
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	v.add_child(mrow)
	for mid in ["casual", "infinite"]:
		var b := Button.new()
		b.text = "%s\n%s" % [MODES[mid]["name"], MODES[mid]["desc"]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func():
			GameState.game_mode = mid
			GameState.write_save()
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
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i >= 3:
			b.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4).lerp(Color(1.0, 0.2, 0.2), float(i - 3) / 3.0))
		var idx := i
		b.pressed.connect(func():
			GameState.difficulty = idx
			GameState.write_save()
			_refresh_play())
		drow.add_child(b)
		_diff_buttons.append(b)
	_diff_info = Label.new()
	_diff_info.add_theme_font_size_override("font_size", 14)
	_diff_info.add_theme_color_override("font_color", Color(0.82, 0.85, 0.9))
	_diff_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_diff_info)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	var deploy := Button.new()
	deploy.text = "DEPLOY"
	deploy.custom_minimum_size = Vector2(0, 58)
	deploy.add_theme_font_size_override("font_size", 24)
	deploy.add_theme_stylebox_override("normal", _box(Color(0.72, 0.12, 0.1), Color(1.0, 0.4, 0.3), 1))
	deploy.add_theme_stylebox_override("hover", _box(Color(0.88, 0.18, 0.14), Color(1.0, 0.6, 0.4), 1))
	_deploy_btn = deploy
	deploy.pressed.connect(func():
		GameState.play_sfx("round_sting", -2.0, 1.0)
		# Hosting a squad: start the co-op game so everyone loads in together
		if Net.is_online():
			if Net.is_host():
				Net.start_game(false)
			return
		GameState.reset_run()
		GameState.run_id = GameState.new_run_id()
		GameState.pending_resume = false
		GameState.late_join = false
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	)
	v.add_child(deploy)
	_refresh_play.call_deferred()
	return v


func _refresh_play() -> void:
	for mid in _mode_cards:
		var on: bool = mid == GameState.game_mode
		(_mode_cards[mid] as Button).add_theme_stylebox_override("normal", _box(Color(0.2, 0.08, 0.07, 0.95) if on else Color(0.07, 0.08, 0.1, 0.92), ACCENT if on else Color(1, 1, 1, 0.08), 2 if on else 1))
	for i in range(_diff_buttons.size()):
		var on: bool = i == GameState.difficulty
		_diff_buttons[i].add_theme_stylebox_override("normal", _box(Color(0.2, 0.08, 0.07, 0.95) if on else Color(0.07, 0.08, 0.1, 0.92), ACCENT if on else Color(1, 1, 1, 0.08), 2 if on else 1))
	if _deploy_btn:
		if Net.is_online() and Net.is_host():
			_deploy_btn.text = "START CO-OP GAME  (%d PLAYERS)" % Net.players.size()
			_deploy_btn.disabled = false
		elif Net.is_online():
			_deploy_btn.text = "WAITING FOR THE HOST TO START..."
			_deploy_btn.disabled = true
		else:
			_deploy_btn.text = "DEPLOY"
			_deploy_btn.disabled = false
	if _diff_info:
		_diff_info.text = "%s:   %s" % [GameState.DIFFICULTY_NAMES[GameState.difficulty], "   •   ".join(GameState.diff_lines(GameState.difficulty))]
	if _coop_settings:
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
	_refresh_play()


func _continue_run(saved: Dictionary) -> void:
	GameState.reset_run()
	GameState.run_id = int(saved.get("run_id", 0))
	GameState.difficulty = int(saved.get("difficulty", 1))
	GameState.game_mode = String(saved.get("mode", "casual"))
	GameState.pending_resume = true
	GameState.late_join = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")


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
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT_BLUE
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bar.add_theme_stylebox_override("background", bg)
	v.add_child(bar)
	v.add_child(_label("%d / %d XP  —  every run's score turns into XP (1 per 10 points)" % [GameState.career_xp, hi], 13, Color(0.7, 0.73, 0.78)))
	_header(v, "UNLOCKS")
	for u in GameState.META_UNLOCKS:
		var got: bool = lvl >= int(u["level"])
		v.add_child(_label("%s  LEVEL %d  —  %s" % ["■" if got else "□", u["level"], u["text"]], 14, Color(0.55, 1.0, 0.6) if got else Color(0.55, 0.57, 0.62)))
	_header(v, "NEMESIS")
	if GameState.nemesis.is_empty():
		v.add_child(_label("None. Die while a commander is still standing and it will remember you.", 14, Color(0.7, 0.73, 0.78), true))
	else:
		var nm: Dictionary = GameState.nemesis
		var nt := clampi(int(nm.get("tier", 3)), 3, 5)
		v.add_child(_label("%s  %s %s" % [String(nm.get("name", "")), "★".repeat(nt), ZombieEnemy.TIER_NAMES[nt]], 18, ZombieEnemy.TIER_COLORS[nt]))
		v.add_child(_label("Killed you %d time(s). It hunts you from round 4 of your next runs. Kill it for +2500 points and a relic." % int(nm.get("kills", 1)), 13, Color(0.7, 0.73, 0.78), true))
	_header(v, "LIFETIME")
	v.add_child(_label("RUNS: %d   •   ZOMBIES KILLED: %d   •   BOSSES: %d" % [GameState.life_runs, GameState.life_kills, GameState.life_bosses], 14))
	v.add_child(_label("COMMANDERS SLAIN: %d   •   NEMESES SLAIN: %d" % [GameState.life_commanders, GameState.life_nemesis_slain], 14))
	_header(v, "RECORDS")
	v.add_child(_label("BEST ROUND (CASUAL): %d" % GameState.best_round, 14))
	v.add_child(_label("BEST ROUND (INFINITE): %d" % GameState.best_round_infinite, 14))
	v.add_child(_label("MOST KILLS IN A RUN: %d" % GameState.best_kills, 14))
	v.add_child(_label("SUCCESSFUL EXTRACTIONS: %d" % GameState.exfils, 14))
	v.visible = false
	return v


# ---------------------------------------------------------------------------
# INTEL: how the zombie ranks, special rounds and challenges work
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
	add.call("• The minimap shows zones, stations, your squad, relics, bosses and commanders, but not regular zombies. Press [M] for the full map, hold [TAB] for the scoreboard.")
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
	b.pressed.connect(func():
		GameState.play_sfx("buy_ching", -8.0, 1.2)
		on_press.call()
	)
	parent.add_child(b)
	return b


func _build_coop_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(_label("Online play runs through Steam's relay network: no port forwarding, IPs stay private, and long-distance links take Valve's fast routes. Up to 8 survivors; zombie numbers and boss health scale with the squad. Friends can join a game already in progress.", 13, Color(0.7, 0.75, 0.82), true))
	coop_status = _label("", 15, Color(1.0, 0.85, 0.45), true)
	v.add_child(coop_status)
	_coop_settings = _label("", 12, ACCENT_BLUE, true)
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
	coop_roster = _label("", 15)
	coop_roster.custom_minimum_size = Vector2(0, 120)
	v.add_child(coop_roster)
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
	Net.lobby_changed.connect(_refresh_coop)
	Net.lobby_changed.connect(_refresh_play)
	Net.status_changed.connect(func(_t: String): _refresh_coop())
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
