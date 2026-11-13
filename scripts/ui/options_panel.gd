class_name OptionsPanel
extends VBoxContainer
# Categorized AAA Settings UI shared across MainMenu and in-game Pause Menu.
# Five tabs (DISPLAY, GAMEPLAY, CONTROLS, AUDIO, KEYBINDS); changes apply and save immediately.

const ACCENT := Color(0.95, 0.32, 0.22)
const CYAN := Color(0.24, 0.84, 1.0)
const DIM := Color(0.58, 0.62, 0.68)
const TEXT := Color(0.88, 0.90, 0.94)

const TABS: Array = [
	["display", "DISPLAY"],
	["gameplay", "GAMEPLAY"],
	["controls", "CONTROLS"],
	["audio", "AUDIO"],
	["keybinds", "KEYBINDS"],
]

var _active_tab: String = "display"
var _tab_btns: Dictionary = {}
var _tab_pages: Dictionary = {}
var _reset_btn: Button
var _hint_lbl: Label
var _listening: String = ""
var _listen_btn: Button
var _key_buttons: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build_all()


func _build_all() -> void:
	for c in get_children():
		c.queue_free()
	_tab_btns.clear()
	_tab_pages.clear()
	_key_buttons.clear()
	_listening = ""
	_listen_btn = null

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6)
	add_child(tab_bar)

	for pair in TABS:
		var tid: String = String(pair[0])
		var tlabel: String = String(pair[1])
		var b := Button.new()
		b.text = tlabel
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		var cap_id: String = tid
		b.pressed.connect(func():
			GameState.play_sfx("hit_tick", -14.0, 1.2)
			select_tab(cap_id))
		tab_bar.add_child(b)
		_tab_btns[tid] = b

	var rule := ColorRect.new()
	rule.color = Color(ACCENT, 0.40)
	rule.custom_minimum_size = Vector2(0, 1)
	add_child(rule)

	for pair in TABS:
		var tid: String = String(pair[0])
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 7)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(page)
		_tab_pages[tid] = page

	_build_display(_tab_pages["display"] as VBoxContainer)
	_build_gameplay(_tab_pages["gameplay"] as VBoxContainer)
	_build_controls(_tab_pages["controls"] as VBoxContainer)
	_build_audio(_tab_pages["audio"] as VBoxContainer)
	_build_keybinds(_tab_pages["keybinds"] as VBoxContainer)

	var foot_rule := ColorRect.new()
	foot_rule.color = Color(1.0, 1.0, 1.0, 0.08)
	foot_rule.custom_minimum_size = Vector2(0, 1)
	add_child(foot_rule)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	add_child(foot)

	_hint_lbl = Label.new()
	_hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_lbl.add_theme_font_size_override("font_size", 11)
	_hint_lbl.add_theme_color_override("font_color", DIM)
	foot.add_child(_hint_lbl)

	_reset_btn = Button.new()
	_reset_btn.custom_minimum_size = Vector2(180, 30)
	_reset_btn.focus_mode = Control.FOCUS_NONE
	_reset_btn.add_theme_font_size_override("font_size", 11)
	_reset_btn.add_theme_stylebox_override("normal", _pill_box(Color(0.14, 0.05, 0.05, 0.92), ACCENT.darkened(0.25), 1))
	_reset_btn.add_theme_stylebox_override("hover", _pill_box(Color(0.22, 0.07, 0.07, 0.96), ACCENT, 1))
	_reset_btn.pressed.connect(func():
		GameState.play_sfx("hit_tick", -10.0, 0.9)
		GameState.reset_settings_category(_active_tab)
		var cur_tab: String = _active_tab
		_build_all()
		select_tab(cur_tab))
	foot.add_child(_reset_btn)

	select_tab(_active_tab)


func select_tab(tab_id: String) -> void:
	if not _tab_pages.has(tab_id):
		return
	_active_tab = tab_id
	_listening = ""
	if _listen_btn:
		_listen_btn = null
	for pair in TABS:
		var tid: String = String(pair[0])
		var active: bool = tid == tab_id
		(_tab_pages[tid] as Control).visible = active
		var b: Button = _tab_btns[tid] as Button
		b.add_theme_stylebox_override("normal", _pill_box(ACCENT.darkened(0.62) if active else Color(0.05, 0.065, 0.09, 0.92), ACCENT if active else Color(1, 1, 1, 0.10), 2 if active else 1))
		b.add_theme_stylebox_override("hover", _pill_box(ACCENT.darkened(0.50) if active else Color(0.09, 0.11, 0.15, 0.95), ACCENT if active else Color(1, 1, 1, 0.24), 2 if active else 1))
		b.add_theme_color_override("font_color", Color.WHITE if active else DIM)

	if is_instance_valid(_reset_btn):
		_reset_btn.text = "RESET %s DEFAULTS" % tab_id.to_upper()
	if is_instance_valid(_hint_lbl):
		match tab_id:
			"display": _hint_lbl.text = "Changes apply immediately. Lower render scale boosts framerate cleanly."
			"gameplay": _hint_lbl.text = "Customize HUD overlays, reticle color, camera shake, and bob."
			"controls": _hint_lbl.text = "Double-tap Sprint for Tactical Sprint unless Auto Tac-Sprint is enabled."
			"audio": _hint_lbl.text = "Independent mix controls for combat weapons, footstep intel, and hitmarkers."
			"keybinds": _hint_lbl.text = "Click a bind, then press key or mouse button. Esc cancels. Duplicates swap."


func get_active_tab() -> String:
	return _active_tab


func _build_display(parent: VBoxContainer) -> void:
	_choice(parent, "QUALITY PRESET", ["LOW (FASTEST)", "MEDIUM", "HIGH"], GameState.graphics_quality, func(i: int):
		GameState.graphics_quality = i
		GameState.apply_graphics())
	_choice(parent, "ANTI-ALIASING (MSAA)", ["OFF", "2X MSAA", "4X MSAA"], GameState.msaa_level, func(i: int):
		GameState.msaa_level = i
		GameState.apply_graphics())
	_slider(parent, "3D RENDER SCALE", 0.70, 1.00, GameState.render_scale_setting, func(v: float):
		GameState.render_scale_setting = v
		GameState.apply_graphics())
	var res_opts: Array = GameState.resolution_options()
	var res_names: Array = []
	for r in res_opts:
		res_names.append("NATIVE (SCREEN)" if r == "native" else String(r).replace("x", " x "))
	_choice(parent, "RESOLUTION", res_names, maxi(0, res_opts.find(GameState.resolution)), func(i: int):
		GameState.resolution = res_opts[i]
		GameState.apply_graphics())
	_slider(parent, "FIELD OF VIEW", 65.0, 112.0, GameState.fov_setting, func(v: float):
		GameState.fov_setting = v
		var p := get_tree().get_first_node_in_group("player")
		if p:
			p.base_fov = v)
	_toggle(parent, "FULLSCREEN MODE", GameState.fullscreen, func(on: bool):
		GameState.fullscreen = on
		GameState.apply_graphics())
	_toggle(parent, "VSYNC (OFF = LOWER INPUT LAG)", GameState.vsync_on, func(on: bool):
		GameState.vsync_on = on
		GameState.apply_graphics())
	_toggle(parent, "FILM GRAIN & COLOR GRADING", GameState.post_fx_enabled, func(on: bool):
		GameState.post_fx_enabled = on
		var pfx := get_tree().current_scene.get_node_or_null("PostFX") if get_tree().current_scene else null
		if pfx:
			pfx.visible = on)
	_toggle(parent, "SHOW FPS TELEMETRY", GameState.show_fps, func(on: bool):
		GameState.show_fps = on)


func _build_gameplay(parent: VBoxContainer) -> void:
	_toggle(parent, "HIPFIRE CROSSHAIR", GameState.crosshair_enabled, func(on: bool):
		GameState.crosshair_enabled = on)
	_toggle(parent, "HORROR MODE CROSSHAIR", GameState.show_crosshair, func(on: bool):
		GameState.show_crosshair = on)
	_choice(parent, "CROSSHAIR COLOR", ["WHITE", "TACTICAL CYAN", "NEON GREEN", "AMBER GOLD", "CRIMSON RED"], GameState.crosshair_color, func(i: int):
		GameState.crosshair_color = i)
	_toggle(parent, "DAMAGE NUMBERS", GameState.damage_numbers, func(on: bool):
		GameState.damage_numbers = on)
	_toggle(parent, "TACTICAL MINIMAP", GameState.show_minimap, func(on: bool):
		GameState.show_minimap = on)
	_slider(parent, "VIEWMODEL & CAMERA BOB", 0.0, 1.0, GameState.viewmodel_bob, func(v: float):
		GameState.viewmodel_bob = v)
	_slider(parent, "COMBAT SCREEN SHAKE", 0.0, 1.0, GameState.screen_shake, func(v: float):
		GameState.screen_shake = v)


func _build_controls(parent: VBoxContainer) -> void:
	_slider(parent, "LOOK SENSITIVITY", 0.20, 3.00, GameState.mouse_sens_mult, func(v: float):
		GameState.mouse_sens_mult = v)
	_slider(parent, "ADS AIM SENSITIVITY", 0.30, 1.50, GameState.ads_sens_mult, func(v: float):
		GameState.ads_sens_mult = v)
	_toggle(parent, "INVERT MOUSE Y-AXIS", GameState.invert_y, func(on: bool):
		GameState.invert_y = on)
	_choice(parent, "SPRINT BEHAVIOR", ["HOLD (+2x TAP TAC-SPRINT)", "TOGGLE SPRINT", "AUTO TAC-SPRINT"], GameState.sprint_mode, func(i: int):
		GameState.sprint_mode = i)
	_choice(parent, "AIM DOWN SIGHTS (ADS)", ["HOLD TO AIM", "TOGGLE AIM"], GameState.ads_mode, func(i: int):
		GameState.ads_mode = i)
	_choice(parent, "CROUCH / SLIDE INPUT", ["TOGGLE CROUCH", "HOLD TO CROUCH"], GameState.crouch_mode, func(i: int):
		GameState.crouch_mode = i)


func _build_audio(parent: VBoxContainer) -> void:
	_slider(parent, "MASTER VOLUME", 0.0, 1.0, GameState.master_volume, func(v: float):
		GameState.master_volume = v
		GameState.apply_volume())
	_slider(parent, "COMBAT & WEAPON SFX", 0.0, 1.0, GameState.sfx_volume, func(v: float):
		GameState.sfx_volume = v
		GameState.apply_volume())
	_slider(parent, "INFECTED FOOTSTEPS", 0.0, 2.0, GameState.step_volume, func(v: float):
		GameState.step_volume = v)
	_toggle(parent, "HITMARKER AUDIO TICK", GameState.hitmarker_sfx, func(on: bool):
		GameState.hitmarker_sfx = on)
	_toggle(parent, "COMMAND HQ AMBIENCE & UI SFX", GameState.menu_sound, func(on: bool):
		GameState.menu_sound = on)


func _build_keybinds(parent: VBoxContainer) -> void:
	for pair in GameState.REBINDABLE:
		var action: String = String(pair[0])
		var h := _row(parent, String(pair[1]))
		var b := Button.new()
		b.custom_minimum_size = Vector2(165, 28)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.text = GameState.key_label(action)
		b.add_theme_stylebox_override("normal", _pill_box(Color(0.06, 0.08, 0.11, 0.94), Color(1, 1, 1, 0.16), 1))
		b.add_theme_stylebox_override("hover", _pill_box(Color(0.10, 0.13, 0.18, 0.98), CYAN, 1))
		b.pressed.connect(func(): _start_listen(action, b))
		h.add_child(b)
		_key_buttons[action] = b


func _start_listen(action: String, b: Button) -> void:
	if _listen_btn:
		_listen_btn.text = GameState.key_label(_listening)
	_listening = action
	_listen_btn = b
	b.text = "PRESS A KEY..."


func _refresh_keys() -> void:
	for action in _key_buttons:
		(_key_buttons[action] as Button).text = GameState.key_label(String(action))


func _input(event: InputEvent) -> void:
	if _listening == "" or not is_visible_in_tree():
		return
	var code: String = ""
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_listen_btn.text = GameState.key_label(_listening)
			_listening = ""
			_listen_btn = null
			return
		code = "k:%d" % (k.physical_keycode if k.physical_keycode != 0 else k.keycode)
	elif event is InputEventMouseButton and event.pressed:
		var mb := (event as InputEventMouseButton).button_index
		if mb == MOUSE_BUTTON_WHEEL_UP or mb == MOUSE_BUTTON_WHEEL_DOWN:
			return
		code = "m:%d" % mb
	if code == "":
		return
	get_viewport().set_input_as_handled()
	GameState.rebind(_listening, code)
	_listening = ""
	_listen_btn = null
	_refresh_keys()


func _row(parent: VBoxContainer, label: String) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _pill_box(Color(1.0, 1.0, 1.0, 0.025), Color(1.0, 1.0, 1.0, 0.06), 1, 10, 4))
	parent.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(220, 0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", TEXT)
	h.add_child(l)
	return h


func _slider(parent: VBoxContainer, label: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var h := _row(parent, label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	s.custom_minimum_size = Vector2(210, 22)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := Label.new()
	val.custom_minimum_size = Vector2(54, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 12)
	val.add_theme_color_override("font_color", CYAN)
	var fmt := func(v: float) -> String:
		return ("%d°" % int(round(v))) if hi > 5.0 else ("%d%%" % int(round(v * 100.0)) if hi <= 1.01 else "%.2fx" % v)
	val.text = fmt.call(value)
	s.value_changed.connect(func(v: float):
		val.text = fmt.call(v)
		on_change.call(v)
		GameState.write_save())
	h.add_child(s)
	h.add_child(val)


func _toggle(parent: VBoxContainer, label: String, value: bool, on_change: Callable) -> void:
	var h := _row(parent, label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var c := CheckButton.new()
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = value
	c.text = "ON" if value else "OFF"
	c.add_theme_font_size_override("font_size", 11)
	c.toggled.connect(func(on: bool):
		c.text = "ON" if on else "OFF"
		on_change.call(on)
		GameState.write_save())
	h.add_child(c)


func _choice(parent: VBoxContainer, label: String, items: Array, value: int, on_change: Callable) -> void:
	var h := _row(parent, label)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 12)
	for it in items:
		o.add_item(String(it))
	o.selected = clampi(value, 0, maxi(0, items.size() - 1))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size = Vector2(200, 26)
	o.item_selected.connect(func(i: int):
		on_change.call(i)
		GameState.write_save())
	h.add_child(o)


func _pill_box(bg: Color, border: Color, bw: int = 1, px: int = 8, py: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = px
	sb.content_margin_right = px
	sb.content_margin_top = py
	sb.content_margin_bottom = py
	return sb
