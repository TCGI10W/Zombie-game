extends Control
# The Augment Furnace screen. Pick a stat, burn points into it, and its bar
# fills toward the next level. Each level costs more than the last.
# The game is paused while this is open.

signal closed()

var player: PlayerController
var _points_lbl: Label
var _cards: Dictionary = {} # stat id -> {level, bar, progress, now}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.01, 0.0, 0.8)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -640
	panel.offset_right = 640
	panel.offset_top = -330
	panel.offset_bottom = 330
	panel.add_theme_stylebox_override("panel", _style(Color(0.07, 0.05, 0.05, 0.97), Color(1.0, 0.45, 0.15), 10, 2, 22))
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	var title := Label.new()
	title.text = "AUGMENT FURNACE"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.22))
	tv.add_child(title)
	var sub := Label.new()
	sub.text = "Burn points to permanently boost a stat for this run. The more you burn, the stronger you get — each level costs more."
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.85, 0.78, 0.72))
	tv.add_child(sub)
	_points_lbl = Label.new()
	_points_lbl.add_theme_font_size_override("font_size", 28)
	_points_lbl.add_theme_color_override("font_color", Color(0.98, 0.8, 0.3))
	_points_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_points_lbl)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)

	for st in GameState.STATS:
		grid.add_child(_build_card(st))

	var foot := Label.new()
	foot.text = "[E] or [ESC] — CLOSE"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 14)
	foot.add_theme_color_override("font_color", Color(0.7, 0.66, 0.62))
	v.add_child(foot)


func _style(bg: Color, border: Color, corner: int, bw: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.7
	sb.content_margin_bottom = margin * 0.7
	return sb


func _build_card(st: Dictionary) -> Control:
	var col: Color = st["color"]
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style(Color(0.1, 0.08, 0.08, 0.95), col.darkened(0.35), 8, 2, 12))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)

	var row := HBoxContainer.new()
	cv.add_child(row)
	var name_lbl := Label.new()
	name_lbl.text = st["name"]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", col)
	row.add_child(name_lbl)
	var lvl := Label.new()
	lvl.add_theme_font_size_override("font_size", 17)
	lvl.add_theme_color_override("font_color", Color(1, 1, 1))
	row.add_child(lvl)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.18, 0.14, 0.13)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	cv.add_child(bar)

	var prog := Label.new()
	prog.add_theme_font_size_override("font_size", 13)
	prog.add_theme_color_override("font_color", Color(0.8, 0.78, 0.75))
	cv.add_child(prog)

	var per := Label.new()
	per.text = "Per level: " + st["per_level"]
	per.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	per.add_theme_font_size_override("font_size", 13)
	per.add_theme_color_override("font_color", Color(0.72, 0.72, 0.74))
	cv.add_child(per)

	var now := Label.new()
	now.add_theme_font_size_override("font_size", 14)
	now.add_theme_color_override("font_color", col.lightened(0.3))
	cv.add_child(now)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(spacer)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	cv.add_child(btns)
	var id: String = st["id"]
	for spec in [["+250", 250], ["+1000", 1000], ["NEXT LV", -1]]:
		var b := Button.new()
		b.text = spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 34)
		b.focus_mode = Control.FOCUS_NONE
		var amount: int = spec[1]
		b.pressed.connect(func(): _burn(id, amount))
		btns.add_child(b)

	_cards[id] = {"level": lvl, "bar": bar, "progress": prog, "now": now}
	return card


func open(p: PlayerController) -> void:
	player = p
	# Fill the screen (a hidden Control under a CanvasLayer may not have been sized yet)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	get_tree().paused = not Net.is_online()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.play_sfx("furnace_burn", -6.0, 0.8)
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	if is_instance_valid(player) and not player.is_dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()


func _burn(id: String, requested: int) -> void:
	var prog := GameState.stat_progress(int(player.stat_burned.get(id, 0)))
	if prog["level"] >= GameState.STAT_MAX_LEVEL:
		GameState.play_sfx("dry_fire", -2.0, 0.7)
		return
	var amount := requested
	if requested < 0:
		amount = int(prog["need"]) - int(prog["into"])
		if GameState.points < amount:
			GameState.play_sfx("dry_fire", -2.0, 0.7)
			_points_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
			return
	amount = mini(amount, mini(GameState.points, player.stat_room(id)))
	if amount <= 0:
		GameState.play_sfx("dry_fire", -2.0, 0.7)
		_points_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
		return
	GameState.spend_points(amount)
	var gained := player.burn_into_stat(id, amount)
	GameState.play_sfx("furnace_burn", -3.0, randf_range(0.95, 1.1))
	get_tree().call_group("augment_furnace", "flare")
	if gained > 0:
		GameState.play_sfx("level_up", 0.0, 1.0)
		var name: String = ""
		for st in GameState.STATS:
			if st["id"] == id:
				name = st["name"]
		player.status_banner_requested.emit("%s RAISED TO LEVEL %d!" % [name, player.stat_level(id)], Color(1.0, 0.6, 0.25))
	_refresh()


func _refresh() -> void:
	_points_lbl.text = "%d PTS" % GameState.points
	_points_lbl.add_theme_color_override("font_color", Color(0.98, 0.8, 0.3))
	for st in GameState.STATS:
		var id: String = st["id"]
		var c: Dictionary = _cards[id]
		var prog := GameState.stat_progress(int(player.stat_burned.get(id, 0)))
		var lv: int = prog["level"]
		(c["level"] as Label).text = "LV %d / %d" % [lv, GameState.STAT_MAX_LEVEL]
		var bar: ProgressBar = c["bar"]
		if lv >= GameState.STAT_MAX_LEVEL:
			bar.max_value = 1
			bar.value = 1
			(c["progress"] as Label).text = "MAXED OUT"
		else:
			bar.max_value = prog["need"]
			bar.value = prog["into"]
			(c["progress"] as Label).text = "%d / %d pts to LV %d" % [prog["into"], prog["need"], lv + 1]
		(c["now"] as Label).text = "Now: " + _effect_text(id, lv)


func _effect_text(id: String, lv: int) -> String:
	if lv == 0:
		return "no bonus yet"
	match id:
		"strength":
			return "+%d%% damage" % (8 * lv)
		"speed":
			return "+%d%% move speed" % (4 * lv)
		"endurance":
			return "+%d HP, %.1f%% resist" % [15 * lv, 2.5 * lv]
		"stamina":
			return "%.1fs sprint" % (3.4 * (1.0 + 0.2 * lv))
		"dexterity":
			return "+%d%% handling speed" % (7 * lv)
		"reflexes":
			return "+%d%% fire rate" % (4 * lv)
		"vitality":
			return "+%d%% regen, %.1fs delay" % [15 * lv, maxf(1.6, 3.8 - 0.22 * lv)]
		"fortune":
			return "+%d%% points" % (6 * lv)
	return ""
