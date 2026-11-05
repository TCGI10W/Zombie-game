extends Node3D
# SUPPLY DEPOT: the late-game place to spend points once the furnace stats
# are maxed. Equipment and supplies get pricier every time you buy them this
# run; perks are bought once and last the whole run.
# [E] opens the shop (the game keeps running in co-op; solo pauses).

const AutoSentry := preload("res://scripts/world/auto_sentry.gd")
const FragScript := preload("res://scripts/player/frag_grenade.gd")

const CATS := ["ALL", "EQUIPMENT", "SUPPLIES", "PERKS"]
const TIER_NAMES := ["COMMON", "RARE", "EPIC", "LEGENDARY"]
const TIER_COLORS := [Color(0.82, 0.84, 0.86), Color(0.35, 0.65, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.78, 0.25)]

const ITEMS := [
	# EQUIPMENT
	{"id": "grenades", "cat": "EQUIPMENT", "icon": "◉", "name": "FRAG GRENADES x3", "desc": "Refill your grenade belt.", "base": 750, "step": 0},
	{"id": "plate", "cat": "EQUIPMENT", "icon": "▣", "name": "ARMOR PLATE", "desc": "+60 shield on top of your health (max 150).", "base": 1000, "step": 400},
	{"id": "mines", "cat": "EQUIPMENT", "icon": "✱", "name": "PROXIMITY MINES x2", "desc": "[B] drop one. It arms and blows when zombies step close.", "base": 1200, "step": 400},
	{"id": "c4", "cat": "EQUIPMENT", "icon": "▤", "name": "C4 CHARGES x2", "desc": "Tap [T] to toss and stick, hold [T] to detonate.", "base": 1500, "step": 500},
	{"id": "revive", "cat": "EQUIPMENT", "icon": "✚", "name": "SECOND WIND CHARGE", "desc": "Get back up by yourself (hold up to 3).", "base": 3500, "step": 1500},
	{"id": "relic", "cat": "EQUIPMENT", "icon": "◆", "name": "RELIC CACHE", "desc": "A random relic: stats or another operator's skill.", "base": 5000, "step": 2500},
	{"id": "magup", "cat": "EQUIPMENT", "icon": "▥", "name": "EXTENDED MAGS", "desc": "+50% magazine size on every gun. No level cap.", "base": 2500, "step": 0, "levels": true},
	{"id": "ammoup", "cat": "EQUIPMENT", "icon": "▦", "name": "AMMO BELT", "desc": "+50% max spare ammo on every gun. No level cap.", "base": 1500, "step": 0, "levels": true},
	# SUPPLIES (instant or timed)
	{"id": "medkit", "cat": "SUPPLIES", "icon": "✚", "name": "FIELD MEDKIT", "desc": "Instantly restore all your health.", "base": 800, "step": 200},
	{"id": "adrenaline", "cat": "SUPPLIES", "icon": "⚡", "name": "ADRENALINE SHOT", "desc": "30s: +30% move speed, +20% fire rate and reload speed.", "base": 2500, "step": 500},
	{"id": "goldrush", "cat": "SUPPLIES", "icon": "$", "name": "GOLD RUSH", "desc": "60s of double points for you.", "base": 4000, "step": 1000},
	{"id": "insta", "cat": "SUPPLIES", "icon": "☠", "name": "EXECUTION ROUNDS", "desc": "20s: every hit kills a regular zombie.", "base": 7500, "step": 2500},
	{"id": "airstrike", "cat": "SUPPLIES", "icon": "✈", "name": "AIRSTRIKE BEACON", "desc": "Bombs the 10 closest zombies within 30m.", "base": 12000, "step": 3000},
	{"id": "sentry", "cat": "SUPPLIES", "icon": "⌖", "name": "AUTO-SENTRY", "desc": "Deploys a turret that guns down zombies for 60s.", "base": 18000, "step": 4000},
	{"id": "orbital", "cat": "SUPPLIES", "icon": "☀", "name": "ORBITAL STRIKE", "desc": "Wipes out every regular zombie on the map. Bosses lose 25% health.", "base": 100000, "step": 0},
	# PERKS (once per run)
	{"id": "hands", "cat": "PERKS", "icon": "✋", "name": "QUICK HANDS", "desc": "Permanent: +25% reload, swap and aim speed.", "base": 6000, "step": 0, "perk": true},
	{"id": "kevlar", "cat": "PERKS", "icon": "⛨", "name": "KEVLAR WEAVE", "desc": "Permanent: take 15% less damage.", "base": 8000, "step": 0, "perk": true},
	{"id": "hollow", "cat": "PERKS", "icon": "➶", "name": "HOLLOW-POINT ROUNDS", "desc": "Permanent: +15% damage with everything.", "base": 10000, "step": 0, "perk": true},
	{"id": "vampire", "cat": "PERKS", "icon": "♥", "name": "BLOOD PACT", "desc": "Permanent: every kill heals you 4 HP.", "base": 20000, "step": 0, "perk": true},
	{"id": "banker", "cat": "PERKS", "icon": "¤", "name": "BANKER'S CHIP", "desc": "Permanent: +20% points earned.", "base": 25000, "step": 0, "perk": true},
	{"id": "titan", "cat": "PERKS", "icon": "▲", "name": "TITAN FRAME", "desc": "Permanent: +60 max health.", "base": 40000, "step": 0, "perk": true},
	{"id": "laststand", "cat": "PERKS", "icon": "✦", "name": "LAST STAND", "desc": "A killing blow leaves you at 1 HP with 3s invulnerability. Recharges in 2 min.", "base": 50000, "step": 0, "perk": true},
	{"id": "mastery", "cat": "PERKS", "icon": "★", "name": "WEAPON MASTERY", "desc": "Permanent: +35% damage and +15% fire rate.", "base": 75000, "step": 0, "perk": true},
]

var interact_radius: float = 2.6
var _bought: Dictionary = {}
var _layer: CanvasLayer
var _player: Node3D
var _cards: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _tab: String = "ALL"
var _points_lbl: Label
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


static func item(id: String) -> Dictionary:
	for it in ITEMS:
		if it["id"] == id:
			return it
	return {}


static func tier_of(cost: int) -> int:
	if cost >= 40000:
		return 3
	if cost >= 10000:
		return 2
	if cost >= 3000:
		return 1
	return 0


static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func price(id: String) -> int:
	var it := item(id)
	if it.is_empty():
		return 0
	if id == "magup" and is_instance_valid(_player):
		var l := int(_player.mag_lv)
		return 2500 + 2500 * l + 500 * l * l
	if id == "ammoup" and is_instance_valid(_player):
		var l2 := int(_player.reserve_lv)
		return 1500 + 1500 * l2 + 300 * l2 * l2
	return int(it["base"]) + int(it["step"]) * int(_bought.get(id, 0))


# Live text for the level-up items: what the current gun goes from -> to.
func _level_desc(id: String) -> String:
	var w_id: String = _player.get_current_weapon_id()
	var base: Dictionary = GameState.WEAPONS[w_id]
	var up: bool = _player.upgraded.has(w_id)
	if id == "magup":
		var lv := int(_player.mag_lv)
		var b := float(base["mag_size"]) * (1.5 if up else 1.0)
		return "LV %d → %d  •  +50%% mag size on every gun.\n%s mag: %d → %d" % [lv, lv + 1, base["name"], int(ceil(b * (1.0 + 0.5 * lv))), int(ceil(b * (1.0 + 0.5 * (lv + 1))))]
	var lv2 := int(_player.reserve_lv)
	var b2 := float(base["reserve_max"]) * (2.0 if up else 1.0)
	return "LV %d → %d  •  +50%% max spare ammo on every gun.\n%s spare: %d → %d" % [lv2, lv2 + 1, base["name"], int(ceil(b2 * (1.0 + 0.5 * lv2))), int(ceil(b2 * (1.0 + 0.5 * (lv2 + 1))))]


func get_prompt(_p: Node3D) -> String:
	return "" if _layer else "[E] SUPPLY DEPOT — EQUIPMENT, SUPPLIES & PERKS"


func try_purchase(p: Node3D) -> void:
	if _layer == null and not p.is_dead and not p.is_downed:
		_open(p)


# ---------------------------------------------------------------------------
# GUI
func _box(bg: Color, border: Color, bw: int = 1, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _open(p: Node3D) -> void:
	_player = p
	_layer = CanvasLayer.new()
	_layer.layer = 20
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.07
	panel.anchor_bottom = 0.93
	var psb := _box(Color(0.045, 0.06, 0.075, 0.97), Color(0.3, 0.75, 0.95, 0.8), 2, 10)
	psb.content_margin_left = 24
	psb.content_margin_right = 24
	psb.content_margin_top = 18
	psb.content_margin_bottom = 16
	psb.shadow_color = Color(0, 0, 0, 0.6)
	psb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", psb)
	_layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	# Header: title on the left, wallet on the right
	var head := HBoxContainer.new()
	v.add_child(head)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(_label("SUPPLY DEPOT", 34, Color(0.55, 0.9, 1.0)))
	tv.add_child(_label("Equipment and supplies cost more each time you buy them. Perks last the whole run.", 14, Color(0.6, 0.68, 0.74)))
	var wallet := PanelContainer.new()
	wallet.add_theme_stylebox_override("panel", _box(Color(0.12, 0.1, 0.04), Color(1.0, 0.78, 0.25, 0.7), 1, 8))
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(wallet)
	_points_lbl = _label("", 24, Color(1.0, 0.82, 0.3))
	wallet.add_child(_points_lbl)

	# Category tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	_tab_buttons.clear()
	for c in CATS:
		var tb := Button.new()
		tb.text = "  %s  " % c
		tb.custom_minimum_size = Vector2(130, 36)
		tb.add_theme_font_size_override("font_size", 15)
		tb.focus_mode = Control.FOCUS_NONE
		var cat: String = c
		tb.pressed.connect(func(): _set_tab(cat))
		tb.set_meta("cat", c)
		tabs.add_child(tb)
		_tab_buttons.append(tb)
	v.add_child(HSeparator.new())

	# Item grid
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	_cards.clear()
	for it in ITEMS:
		var card := _make_card(it)
		grid.add_child(card)
		_cards.append(card)

	# Footer
	var foot := HBoxContainer.new()
	v.add_child(foot)
	var hint := _label("Click BUY   •   [ESC] close", 14, Color(0.55, 0.62, 0.68))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	for t in range(4):
		foot.add_child(_label("■ %s  " % TIER_NAMES[t], 13, TIER_COLORS[t]))
	var close := Button.new()
	close.text = "  CLOSE  "
	close.custom_minimum_size = Vector2(120, 36)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close)
	foot.add_child(close)

	_set_tab(_tab)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.is_online():
		_was_paused = get_tree().paused
		get_tree().paused = true


func _make_card(it: Dictionary) -> Control:
	var t := tier_of(int(it["base"]))
	var col: Color = TIER_COLORS[t]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 150)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("id", it["id"])
	card.set_meta("cat", it["cat"])
	card.add_theme_stylebox_override("panel", _box(Color(col.r * 0.08 + 0.05, col.g * 0.08 + 0.055, col.b * 0.08 + 0.065), Color(col, 0.55), 1, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	# Icon tile
	var icon_bg := PanelContainer.new()
	icon_bg.custom_minimum_size = Vector2(58, 58)
	icon_bg.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var isb := _box(Color(col, 0.16), Color(col, 0.8), 2, 8)
	isb.content_margin_left = 0
	isb.content_margin_right = 0
	isb.content_margin_top = 0
	isb.content_margin_bottom = 0
	icon_bg.add_theme_stylebox_override("panel", isb)
	var icon := _label(String(it["icon"]), 30, col)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_bg.add_child(icon)
	h.add_child(icon_bg)
	# Text + buy row
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)
	var kind := "PERK" if it.get("perk", false) else ("GEAR" if it["cat"] == "EQUIPMENT" else "SUPPLY")
	v.add_child(_label("%s  •  %s" % [TIER_NAMES[t], kind], 11, Color(col, 0.9)))
	v.add_child(_label(String(it["name"]), 18, Color(0.95, 0.96, 0.97)))
	var desc := _label(String(it["desc"]), 13, Color(0.66, 0.72, 0.77))
	desc.name = "Desc"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)
	var row := HBoxContainer.new()
	v.add_child(row)
	var pl := _label("", 17, Color(1.0, 0.82, 0.3))
	pl.name = "Price"
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(pl)
	var b := Button.new()
	b.name = "Buy"
	b.custom_minimum_size = Vector2(110, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", _box(Color(col, 0.22), Color(col, 0.9), 1, 6))
	b.add_theme_stylebox_override("hover", _box(Color(col, 0.42), Color(col, 1.0), 2, 6))
	b.add_theme_stylebox_override("pressed", _box(Color(col, 0.6), Color(col, 1.0), 2, 6))
	b.add_theme_stylebox_override("disabled", _box(Color(0.1, 0.1, 0.11), Color(0.25, 0.25, 0.27), 1, 6))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.47, 0.5))
	var id: String = it["id"]
	b.pressed.connect(func(): _buy(id))
	row.add_child(b)
	return card


func _set_tab(cat: String) -> void:
	_tab = cat
	for tb in _tab_buttons:
		var on: bool = tb.get_meta("cat") == cat
		var c := Color(0.55, 0.9, 1.0)
		tb.add_theme_stylebox_override("normal", _box(Color(c, 0.25) if on else Color(0.08, 0.1, 0.12), Color(c, 0.9 if on else 0.25), 1, 6))
		tb.add_theme_stylebox_override("hover", _box(Color(c, 0.3), Color(c, 0.9), 1, 6))
		tb.add_theme_color_override("font_color", Color(0.95, 1.0, 1.0) if on else Color(0.6, 0.7, 0.76))
	for card in _cards:
		card.visible = cat == "ALL" or card.get_meta("cat") == cat
	_refresh()


func _full_note(id: String) -> String:
	match id:
		"revive":
			return "FULL" if int(_player.revives) >= 3 else ""
		"plate":
			return "FULL" if float(_player.overshield) >= 150.0 else ""
		"c4":
			return "FULL" if int(_player.c4_count) >= 4 else ""
		"mines":
			return "FULL" if int(_player.mines) >= 4 else ""
		"medkit":
			return "FULL HP" if float(_player.hp) >= float(_player.max_hp) else ""
		"adrenaline":
			return "ACTIVE" if float(_player.adrenaline_timer) > 0.0 else ""
		"goldrush":
			return "ACTIVE" if GameState.is_powerup_active("double_points") else ""
		"insta":
			return "ACTIVE" if GameState.is_powerup_active("insta_kill") else ""
		"airstrike", "orbital":
			return "NO TARGETS" if _targets(9999.0).is_empty() else ""
	if item(id).get("perk", false) and _player.has_perk(id):
		return "OWNED"
	return ""


func _refresh() -> void:
	if not is_instance_valid(_player):
		return
	_points_lbl.text = "◆ %s PTS" % fmt(GameState.points)
	for card in _cards:
		var id: String = card.get_meta("id")
		var cost := price(id)
		var note := _full_note(id)
		var pl := card.find_child("Price", true, false) as Label
		var b := card.find_child("Buy", true, false) as Button
		pl.text = "%s PTS" % fmt(cost)
		if item(id).get("levels", false):
			(card.find_child("Desc", true, false) as Label).text = _level_desc(id)
		pl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3) if GameState.points >= cost else Color(1.0, 0.4, 0.35))
		if note != "":
			b.text = note
			b.disabled = true
		elif GameState.points < cost:
			b.text = "NEED %s" % _short(cost - GameState.points)
			b.disabled = true
		else:
			b.text = "BUY"
			b.disabled = false
		card.modulate = Color(1, 1, 1, 0.6) if note == "OWNED" else Color.WHITE


func _short(n: int) -> String:
	if n >= 1000:
		return "%.1fK" % (float(n) / 1000.0)
	return str(n)


# ---------------------------------------------------------------------------
# Buying
func _targets(radius: float) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var z := n as ZombieEnemy
		if z and not z.is_dead and z.global_position.distance_to(_player.global_position) <= radius:
			out.append(z)
	return out


func _buy(id: String) -> void:
	if not is_instance_valid(_player) or _full_note(id) != "":
		return
	if id == "airstrike" and _targets(30.0).is_empty():
		_player.status_banner_requested.emit("NO ZOMBIES WITHIN 30m", Color(1.0, 0.35, 0.3))
		return
	if not GameState.try_pay(_player, price(id)):
		return
	_bought[id] = int(_bought.get(id, 0)) + 1
	var cyan := Color(0.55, 0.9, 1.0)
	if item(id).get("perk", false):
		_player.perks[id] = true
		_player._apply_stats()
		_player.stats_changed.emit()
		GameState.play_sfx("level_up", 0.0, 1.1)
		_player.status_banner_requested.emit("PERK ACQUIRED: %s" % item(id)["name"], TIER_COLORS[tier_of(price(id))])
		_refresh()
		return
	match id:
		"grenades":
			_player.add_grenades(3)
			_player.status_banner_requested.emit("+3 FRAG GRENADES", cyan)
		"plate":
			_player.overshield = minf(150.0, _player.overshield + 60.0)
			_player.hp_changed.emit(_player.hp, _player.max_hp, _player.overshield)
			_player.status_banner_requested.emit("ARMOR PLATE INSERTED  +60 SHIELD", cyan)
		"revive":
			_player.revives = mini(3, int(_player.revives) + 1)
			_player.stats_changed.emit()
			_player.status_banner_requested.emit("SECOND WIND CHARGES: %d" % _player.revives, Color(0.4, 1.0, 0.6))
		"c4":
			_player.c4_count = mini(4, int(_player.c4_count) + 2)
			_player.status_banner_requested.emit("C4 x%d — TAP [T] TO THROW, HOLD [T] TO DETONATE" % _player.c4_count, Color(1.0, 0.6, 0.3))
		"mines":
			_player.mines = mini(4, int(_player.mines) + 2)
			_player.status_banner_requested.emit("MINES x%d — PRESS [B] TO DROP ONE" % _player.mines, Color(1.0, 0.6, 0.3))
		"magup":
			_player.mag_lv += 1
			_player._emit_ammo()
			GameState.play_sfx("mag_in", 0.0, 0.9)
			_player.status_banner_requested.emit("EXTENDED MAGS LV %d — RELOAD TO FILL THE BIGGER MAG" % _player.mag_lv, Color(0.55, 0.9, 1.0))
		"ammoup":
			_player.reserve_lv += 1
			for w in _player.weapons_owned:
				var cfg: Dictionary = _player.get_weapon_cfg(w)
				var gain := int(ceil(float(GameState.WEAPONS[w]["reserve_max"]) * 0.5))
				_player.reserve_ammo[w] = mini(int(cfg["reserve_max"]), int(_player.reserve_ammo.get(w, 0)) + gain)
			_player._emit_ammo()
			GameState.play_sfx("mag_in", 0.0, 0.8)
			_player.status_banner_requested.emit("AMMO BELT LV %d — MORE SPARE AMMO" % _player.reserve_lv, Color(0.55, 0.9, 1.0))
		"relic":
			var wm := get_tree().current_scene.get_node_or_null("WaveManager")
			if wm:
				wm._apply_relic(wm._roll_relic(true))
		"medkit":
			_player.hp = _player.max_hp
			_player.hp_changed.emit(_player.hp, _player.max_hp, _player.overshield)
			GameState.play_sfx("second_wind", -4.0, 1.2)
			_player.status_banner_requested.emit("FULLY HEALED", Color(0.4, 1.0, 0.6))
		"adrenaline":
			_player.adrenaline_timer = 30.0
			GameState.play_sfx("second_wind", -2.0, 1.4)
			_player.status_banner_requested.emit("ADRENALINE!  FASTER EVERYTHING FOR 30s", Color(1.0, 0.85, 0.3))
		"goldrush":
			GameState.activate_powerup("double_points", 60.0)
			_player.status_banner_requested.emit("GOLD RUSH — DOUBLE POINTS FOR 60s", Color(1.0, 0.82, 0.3))
		"insta":
			GameState.activate_powerup("insta_kill", 20.0)
			_player.status_banner_requested.emit("EXECUTION ROUNDS — ONE HIT KILLS FOR 20s", Color(0.92, 0.94, 1.0))
		"airstrike":
			_airstrike()
		"sentry":
			var s := AutoSentry.new()
			s.owner_player = _player
			get_tree().current_scene.add_child(s)
			var fwd: Vector3 = -_player.global_basis.z
			fwd.y = 0.0
			s.global_position = _player.global_position + fwd.normalized() * 1.4
			s.rotation.y = _player.rotation.y
			GameState.play_sfx("power_on", -2.0, 1.2)
			_player.status_banner_requested.emit("AUTO-SENTRY DEPLOYED (60s)", Color(0.4, 1.0, 0.55))
		"orbital":
			_orbital()
	_refresh()


func _airstrike() -> void:
	var zs := _targets(30.0)
	var me := _player.global_position
	zs.sort_custom(func(a, b): return a.global_position.distance_to(me) < b.global_position.distance_to(me))
	GameState.play_sfx("radio_beep", 0.0, 1.0)
	_player.status_banner_requested.emit("AIRSTRIKE INBOUND!", Color(1.0, 0.55, 0.25))
	for i in range(mini(10, zs.size())):
		var g: RigidBody3D = FragScript.new()
		g.thrower = _player
		g.radius = 7.0
		g.damage = 1400.0
		g.freeze = true
		g.set("_fuse", 1.2 + 0.18 * float(i))
		get_tree().current_scene.add_child(g)
		g.global_position = (zs[i] as Node3D).global_position + Vector3(0, 0.3, 0)


func _orbital() -> void:
	GameState.play_sfx("lightning_strike", 3.0, 0.7)
	GameState.play_sfx("thunder_far", 2.0, 0.8)
	_player.add_camera_shake(0.8)
	_player.status_banner_requested.emit("ORBITAL STRIKE!", Color(1.0, 0.95, 0.75))
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.97, 0.88, 0.9)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fl := CanvasLayer.new()
	fl.layer = 30
	fl.add_child(flash)
	get_tree().current_scene.add_child(fl)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.0, 1.2)
	tw.tween_callback(fl.queue_free)
	for z in _targets(9999.0):
		var zz := z as ZombieEnemy
		var dmg: float = zz.max_hp * 0.25 if zz.is_boss else zz.hp * 20.0 + 100000.0
		var res: Dictionary = zz.take_damage(dmg, zz.global_position + Vector3(0, 1.0, 0), true, "explosive")
		if res.get("killed", false):
			_player._on_enemy_killed_by_player(zz, false)


func _unhandled_input(event: InputEvent) -> void:
	if _layer and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


var _refresh_t: float = 0.0


func _process(d: float) -> void:
	if _layer and (not is_instance_valid(_player) or _player.is_dead or _player.is_downed or _player.global_position.distance_to(global_position) > 4.0):
		_close()
		return
	if _layer:
		_refresh_t -= d
		if _refresh_t <= 0.0:
			_refresh_t = 0.25
			_refresh()


func _close() -> void:
	if _layer:
		_layer.queue_free()
		_layer = null
	if not Net.is_online():
		get_tree().paused = _was_paused
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
