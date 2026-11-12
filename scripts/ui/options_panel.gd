class_name OptionsPanel
extends VBoxContainer
# One options screen for the main menu and the in-game pause menu.
# Every change applies immediately and is saved.

const ACCENT := Color(0.95, 0.32, 0.22)


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_section("AUDIO")
	_slider("MASTER VOLUME", 0.0, 1.0, GameState.master_volume, func(v: float):
		GameState.master_volume = v
		GameState.apply_volume())
	_slider("EFFECTS VOLUME", 0.0, 1.0, GameState.sfx_volume, func(v: float):
		GameState.sfx_volume = v
		GameState.apply_volume())
	_slider("ZOMBIE FOOTSTEPS", 0.0, 2.0, GameState.step_volume, func(v: float):
		GameState.step_volume = v
		GameState.write_save())

	_section("CONTROLS")
	_slider("MOUSE SENSITIVITY", 0.2, 3.0, GameState.mouse_sens_mult, func(v: float):
		GameState.mouse_sens_mult = v)
	_toggle("INVERT MOUSE Y", GameState.invert_y, func(on: bool):
		GameState.invert_y = on)

	_section("VIDEO")
	_slider("FIELD OF VIEW", 65.0, 112.0, GameState.fov_setting, func(v: float):
		GameState.fov_setting = v
		GameState.write_save()
		var p := get_tree().get_first_node_in_group("player")
		if p:
			p.base_fov = v)
	_choice("GRAPHICS", ["LOW (FASTEST)", "MEDIUM", "HIGH"], GameState.graphics_quality, func(i: int):
		GameState.graphics_quality = i
		GameState.apply_graphics())
	var res_opts: Array = GameState.resolution_options()
	var res_names: Array = []
	for r in res_opts:
		res_names.append("NATIVE (SCREEN)" if r == "native" else String(r).replace("x", " x "))
	_choice("RESOLUTION", res_names, maxi(0, res_opts.find(GameState.resolution)), func(i: int):
		GameState.resolution = res_opts[i]
		GameState.apply_graphics())
	_toggle("FULLSCREEN", GameState.fullscreen, func(on: bool):
		GameState.fullscreen = on
		GameState.apply_graphics())
	_toggle("VSYNC  (OFF = LESS INPUT DELAY)", GameState.vsync_on, func(on: bool):
		GameState.vsync_on = on
		GameState.apply_graphics())
	_toggle("BODYCAM FISHEYE & REC OSD", GameState.bodycam_mode, func(on: bool):
		GameState.bodycam_mode = on
		GameState.write_save())
	_toggle("FILM GRAIN & LENS EFFECTS", GameState.post_fx_enabled, func(on: bool):
		GameState.post_fx_enabled = on
		GameState.write_save()
		var pfx := get_tree().current_scene.get_node_or_null("PostFX") if get_tree().current_scene else null
		if pfx:
			pfx.visible = on)
	_toggle("SHOW FPS", GameState.show_fps, func(on: bool):
		GameState.show_fps = on
		GameState.write_save())
	_toggle("SHOW CROSSHAIR", GameState.show_crosshair, func(on: bool):
		GameState.show_crosshair = on
		GameState.write_save())
	_toggle("DAMAGE NUMBERS", GameState.damage_numbers, func(on: bool):
		GameState.damage_numbers = on
		GameState.write_save())
	_toggle("MINIMAP", GameState.show_minimap, func(on: bool):
		GameState.show_minimap = on
		GameState.write_save())
	_build_keys()


# ---------------------------------------------------------------------------
# KEY BINDINGS: click a key, then press the new key or mouse button (Esc cancels)
# ---------------------------------------------------------------------------
var _listening: String = ""
var _listen_btn: Button
var _key_buttons: Dictionary = {}


func _build_keys() -> void:
	_section("KEY BINDINGS")
	var hint := Label.new()
	hint.text = "Click a key, then press the new key or mouse button. Esc cancels. Taken keys swap."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	add_child(hint)
	for pair in GameState.REBINDABLE:
		var action: String = pair[0]
		var h := _row(pair[1])
		var b := Button.new()
		b.custom_minimum_size = Vector2(160, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.text = GameState.key_label(action)
		b.pressed.connect(func(): _start_listen(action, b))
		h.add_child(b)
		_key_buttons[action] = b
	var reset := Button.new()
	reset.text = "RESET KEYS TO DEFAULT"
	reset.custom_minimum_size = Vector2(0, 32)
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func():
		GameState.reset_key_binds()
		_refresh_keys())
	add_child(reset)


func _start_listen(action: String, b: Button) -> void:
	if _listen_btn:
		_listen_btn.text = GameState.key_label(_listening)
	_listening = action
	_listen_btn = b
	b.text = "PRESS A KEY..."


func _refresh_keys() -> void:
	for action in _key_buttons:
		(_key_buttons[action] as Button).text = GameState.key_label(action)


func _input(event: InputEvent) -> void:
	if _listening == "" or not is_visible_in_tree():
		return
	var code := ""
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


func _row(label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
	h.add_child(l)
	add_child(h)
	return h


func _section(title: String) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", ACCENT)
	if get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		add_child(gap)
	add_child(l)
	var line := ColorRect.new()
	line.color = Color(ACCENT, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	add_child(line)


func _slider(label: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var h := _row(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	s.custom_minimum_size = Vector2(240, 22)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := Label.new()
	val.custom_minimum_size = Vector2(46, 0)
	val.add_theme_font_size_override("font_size", 13)
	var fmt := func(v: float) -> String:
		return ("%d" % int(round(v))) if hi > 5.0 else ("%d%%" % int(round(v * 100.0)) if hi <= 1.0 else "%.2f" % v)
	val.text = fmt.call(value)
	s.value_changed.connect(func(v: float):
		val.text = fmt.call(v)
		on_change.call(v)
		GameState.write_save())
	h.add_child(s)
	h.add_child(val)


func _toggle(label: String, value: bool, on_change: Callable) -> void:
	var h := _row(label)
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(func(on: bool):
		on_change.call(on)
		GameState.write_save())
	h.add_child(c)


func _choice(label: String, items: Array, value: int, on_change: Callable) -> void:
	var h := _row(label)
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.selected = value
	o.custom_minimum_size = Vector2(200, 0)
	o.item_selected.connect(func(i: int):
		on_change.call(i)
		GameState.write_save())
	h.add_child(o)
