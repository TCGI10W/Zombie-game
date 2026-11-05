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

	_section("CONTROLS")
	_slider("MOUSE SENSITIVITY", 0.2, 3.0, GameState.mouse_sens_mult, func(v: float):
		GameState.mouse_sens_mult = v)
	_toggle("INVERT MOUSE Y", GameState.invert_y, func(on: bool):
		GameState.invert_y = on)

	_section("VIDEO")
	_slider("FIELD OF VIEW", 65.0, 110.0, GameState.fov_setting, func(v: float):
		GameState.fov_setting = v
		var p := get_tree().get_first_node_in_group("player")
		if p:
			p.base_fov = v)
	_choice("GRAPHICS", ["LOW (FASTEST)", "MEDIUM", "HIGH"], GameState.graphics_quality, func(i: int):
		GameState.graphics_quality = i
		GameState.apply_graphics())
	_toggle("FULLSCREEN", GameState.fullscreen, func(on: bool):
		GameState.fullscreen = on
		GameState.apply_graphics())
	_toggle("VSYNC  (OFF = LESS INPUT DELAY)", GameState.vsync_on, func(on: bool):
		GameState.vsync_on = on
		GameState.apply_graphics())
	_toggle("FILM GRAIN & LENS EFFECTS", GameState.post_fx_enabled, func(on: bool):
		GameState.post_fx_enabled = on
		var pfx := get_tree().current_scene.get_node_or_null("PostFX") if get_tree().current_scene else null
		if pfx:
			pfx.visible = on)
	_toggle("SHOW FPS", GameState.show_fps, func(on: bool):
		GameState.show_fps = on)
	_toggle("SHOW CROSSHAIR", GameState.show_crosshair, func(on: bool):
		GameState.show_crosshair = on)
	_toggle("DAMAGE NUMBERS", GameState.damage_numbers, func(on: bool):
		GameState.damage_numbers = on)


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
