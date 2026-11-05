extends Node3D
# SUPPLY DEPOT: the late-game place to spend points once the furnace stats
# are maxed. Each item gets pricier every time you buy it this run.
# [E] opens the menu (the game keeps running in co-op; solo pauses).

const ITEMS := [
	{"id": "grenades", "name": "FRAG GRENADES x3", "desc": "Refill your grenade belt", "base": 750, "step": 0},
	{"id": "plate", "name": "ARMOR PLATE", "desc": "+60 shield on top of your health (max 150)", "base": 1000, "step": 400},
	{"id": "revive", "name": "SECOND WIND CHARGE", "desc": "Get back up by yourself (hold up to 3)", "base": 3500, "step": 1500},
	{"id": "relic", "name": "RELIC CACHE", "desc": "A random relic: stats or another operator's skill", "base": 5000, "step": 2500},
]

var interact_radius: float = 2.6
var _bought: Dictionary = {}
var _layer: CanvasLayer
var _player: Node3D
var _buttons: Array[Button] = []
var _was_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("wall_stations")
	if ResourceLoader.exists("res://assets/models/prop_lockers.glb"):
		add_child((load("res://assets/models/prop_lockers.glb") as PackedScene).instantiate())
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.6, 2.0, 0.7)
	cs.shape = bs
	cs.position.y = 1.0
	body.add_child(cs)
	add_child(body)
	var lbl := Label3D.new()
	lbl.text = "SUPPLY DEPOT\n[E] SHOP"
	lbl.font_size = 34
	lbl.outline_size = 10
	lbl.pixel_size = 0.0045
	lbl.modulate = Color(0.55, 0.9, 1.0)
	lbl.position = Vector3(0, 2.35, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.5, 0.85, 1.0)
	lamp.light_energy = 0.9
	lamp.omni_range = 3.5
	lamp.position = Vector3(0, 2.2, -0.6)
	add_child(lamp)


func price(id: String) -> int:
	for it in ITEMS:
		if it["id"] == id:
			return int(it["base"]) + int(it["step"]) * int(_bought.get(id, 0))
	return 0


func get_prompt(_p: Node3D) -> String:
	return "" if _layer else "[E] SUPPLY DEPOT — GRENADES, ARMOR, SECOND WIND, RELICS"


func try_purchase(p: Node3D) -> void:
	if _layer == null and not p.is_dead and not p.is_downed:
		_open(p)


func _open(p: Node3D) -> void:
	_player = p
	_layer = CanvasLayer.new()
	_layer.layer = 20
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -230
	panel.offset_bottom = 230
	_layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := Label.new()
	title.text = "SUPPLY DEPOT"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	v.add_child(title)
	_buttons.clear()
	for it in ITEMS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 62)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		var id: String = it["id"]
		b.pressed.connect(func(): _buy(id))
		b.set_meta("id", id)
		v.add_child(b)
		_buttons.append(b)
	var close := Button.new()
	close.text = "CLOSE  [ESC]"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(_close)
	v.add_child(close)
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.is_online():
		_was_paused = get_tree().paused
		get_tree().paused = true


func _refresh() -> void:
	for b in _buttons:
		var id: String = b.get_meta("id")
		for it in ITEMS:
			if it["id"] == id:
				var note := ""
				if id == "revive" and int(_player.revives) >= 3:
					note = "   (FULL)"
				elif id == "plate" and float(_player.overshield) >= 150.0:
					note = "   (FULL)"
				b.text = "  %s  —  %d PTS%s\n  %s" % [it["name"], price(id), note, it["desc"]]
				b.disabled = note != "" or GameState.points < price(id)


func _buy(id: String) -> void:
	if not is_instance_valid(_player) or not GameState.try_pay(_player, price(id)):
		return
	_bought[id] = int(_bought.get(id, 0)) + 1
	match id:
		"grenades":
			_player.add_grenades(3)
			_player.status_banner_requested.emit("+3 FRAG GRENADES", Color(0.55, 0.9, 1.0))
		"plate":
			_player.overshield = minf(150.0, _player.overshield + 60.0)
			_player.hp_changed.emit(_player.hp, _player.max_hp, _player.overshield)
			_player.status_banner_requested.emit("ARMOR PLATE INSERTED  +60 SHIELD", Color(0.55, 0.9, 1.0))
		"revive":
			_player.revives = mini(3, int(_player.revives) + 1)
			_player.stats_changed.emit()
			_player.status_banner_requested.emit("SECOND WIND CHARGES: %d" % _player.revives, Color(0.4, 1.0, 0.6))
		"relic":
			var wm := get_tree().current_scene.get_node_or_null("WaveManager")
			if wm:
				wm._apply_relic(wm._roll_relic(true))
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _layer and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _process(_d: float) -> void:
	if _layer and (not is_instance_valid(_player) or _player.is_dead or _player.is_downed or _player.global_position.distance_to(global_position) > 4.0):
		_close()


func _close() -> void:
	if _layer:
		_layer.queue_free()
		_layer = null
	if not Net.is_online():
		get_tree().paused = _was_paused
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
