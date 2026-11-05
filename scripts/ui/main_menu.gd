extends Node3D

var menu_cam: Camera3D
var cam_pivot: Node3D
var stage_pivot: Node3D
var char_buttons: Dictionary = {}
var detail_name: Label
var detail_code: Label
var detail_summary: Label
var detail_stats: Label
var detail_skills: VBoxContainer
var _orbit_time: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_3d_diorama()
	_build_menu_ui()
	_select_character(GameState.selected_character)


func _process(delta: float) -> void:
	_orbit_time += delta * 0.25
	if is_instance_valid(cam_pivot):
		cam_pivot.rotation.y = sin(_orbit_time) * 0.14
	if is_instance_valid(stage_pivot):
		stage_pivot.rotation.y = sin(_orbit_time * 1.4) * 0.18


func _build_3d_diorama() -> void:
	var arena := BunkerArena.new()
	add_child(arena)

	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(0.0, 0.0, 1.5)
	add_child(cam_pivot)

	menu_cam = Camera3D.new()
	menu_cam.position = Vector3(-1.4, 2.05, 8.2)
	menu_cam.rotation_degrees = Vector3(-5.0, -8.0, 0.0)
	menu_cam.fov = 58.0
	menu_cam.current = true
	cam_pivot.add_child(menu_cam)

	# Lit 3D Showcase Stage in the open Center-Right of the screen!
	stage_pivot = Node3D.new()
	stage_pivot.position = Vector3(1.1, 0.0, 2.8)
	add_child(stage_pivot)

	var key_spot := SpotLight3D.new()
	key_spot.light_color = Color(1.0, 0.72, 0.45)
	key_spot.light_energy = 6.5
	key_spot.spot_range = 14.0
	key_spot.spot_angle = 38.0
	key_spot.position = Vector3(1.4, 5.2, 6.5)
	key_spot.look_at_from_position(Vector3(1.4, 5.2, 6.5), Vector3(1.1, 1.4, 2.8), Vector3.UP)
	add_child(key_spot)

	var rim_light := OmniLight3D.new()
	rim_light.light_color = Color(0.95, 0.22, 0.16)
	rim_light.light_energy = 3.2
	rim_light.omni_range = 8.0
	rim_light.position = Vector3(2.8, 2.6, 0.8)
	add_child(rim_light)

	if ResourceLoader.exists("res://assets/models/boss_gun_zombie.glb"):
		var b1 := (load("res://assets/models/boss_gun_zombie.glb") as PackedScene).instantiate() as Node3D
		b1.position = Vector3(-1.35, 0.0, 0.25)
		b1.rotation_degrees.y = 195.0
		b1.scale = Vector3.ONE * 1.15
		stage_pivot.add_child(b1)

	if ResourceLoader.exists("res://assets/models/boss_gorilla.glb"):
		var b2 := (load("res://assets/models/boss_gorilla.glb") as PackedScene).instantiate() as Node3D
		b2.position = Vector3(1.15, 0.0, -0.35)
		b2.rotation_degrees.y = 162.0
		b2.scale = Vector3.ONE * 1.25
		stage_pivot.add_child(b2)


func _make_card_style(bg: Color, border: Color, bw: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _build_menu_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 38)
	margin.add_theme_constant_override("margin_right", 38)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	layer.add_child(margin)

	var main_v := VBoxContainer.new()
	main_v.add_theme_constant_override("separation", 14)
	margin.add_child(main_v)

	# --- HEADER ---
	var header_h := HBoxContainer.new()
	main_v.add_child(header_h)

	var title_v := VBoxContainer.new()
	title_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_h.add_child(title_v)

	var tag_lbl := Label.new()
	tag_lbl.text = "CLASSIFIED OUTBREAK PROTOCOL  //  OUTPOST NACHT-7"
	tag_lbl.add_theme_font_size_override("font_size", 14)
	tag_lbl.add_theme_color_override("font_color", Color(0.95, 0.30, 0.22))
	tag_lbl.add_theme_constant_override("outline_size", 5)
	tag_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_v.add_child(tag_lbl)

	var game_title := Label.new()
	game_title.text = "DEAD PROTOCOL: ZOMBIES"
	game_title.add_theme_font_size_override("font_size", 42)
	game_title.add_theme_color_override("font_color", Color(0.97, 0.95, 0.93))
	game_title.add_theme_constant_override("outline_size", 8)
	game_title.add_theme_color_override("font_outline_color", Color.BLACK)
	title_v.add_child(game_title)

	if GameState.best_round > 0:
		var best_lbl := Label.new()
		best_lbl.text = "BEST RUN: ROUND %d   •   MOST KILLS: %d" % [GameState.best_round, GameState.best_kills]
		if GameState.exfils > 0:
			best_lbl.text += "   •   EXTRACTIONS: %d" % GameState.exfils
		best_lbl.add_theme_font_size_override("font_size", 15)
		best_lbl.add_theme_color_override("font_color", Color(0.98, 0.80, 0.35))
		best_lbl.add_theme_constant_override("outline_size", 5)
		best_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		title_v.add_child(best_lbl)

	var tally_badge := Label.new()
	tally_badge.text = "||||/"
	tally_badge.add_theme_font_size_override("font_size", 52)
	tally_badge.add_theme_color_override("font_color", Color(0.88, 0.12, 0.10))
	tally_badge.add_theme_constant_override("outline_size", 6)
	tally_badge.add_theme_color_override("font_outline_color", Color.BLACK)
	header_h.add_child(tally_badge)

	# --- BODY: LEFT ROSTER + OPEN CENTER 3D STAGE + RIGHT COMPACT DOSSIER ---
	var body_h := HBoxContainer.new()
	body_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_h.add_theme_constant_override("separation", 20)
	main_v.add_child(body_h)

	# Left Column: Operator Roster + Boss Intel
	var left_v := VBoxContainer.new()
	left_v.custom_minimum_size = Vector2(370, 0)
	left_v.add_theme_constant_override("separation", 10)
	body_h.add_child(left_v)

	var sel_hdr := Label.new()
	sel_hdr.text = "SELECT OPERATOR"
	sel_hdr.add_theme_font_size_override("font_size", 16)
	sel_hdr.add_theme_color_override("font_color", Color(0.90, 0.90, 0.94))
	sel_hdr.add_theme_constant_override("outline_size", 5)
	sel_hdr.add_theme_color_override("font_outline_color", Color.BLACK)
	left_v.add_child(sel_hdr)

	for cid in ["ravager", "alchemist", "warden"]:
		var cdata: Dictionary = GameState.CHARACTERS[cid]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 76)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "  %s\n  %s" % [cdata["name"], cdata["codename"]]
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(func():
			GameState.play_sfx("buy_ching", -5.0, 1.15)
			_select_character(cid)
		)
		left_v.add_child(btn)
		char_buttons[cid] = btn

	var boss_intel := PanelContainer.new()
	boss_intel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	boss_intel.add_theme_stylebox_override("panel", _make_card_style(Color(0.04, 0.05, 0.07, 0.84), Color(0.62, 0.16, 0.14), 1))
	left_v.add_child(boss_intel)

	var bi_v := VBoxContainer.new()
	bi_v.add_theme_constant_override("separation", 5)
	boss_intel.add_child(bi_v)

	var bi_hdr := Label.new()
	bi_hdr.text = "☠ UNIQUE BOSS EVERY ROUND"
	bi_hdr.add_theme_font_size_override("font_size", 14)
	bi_hdr.add_theme_color_override("font_color", Color(1.0, 0.42, 0.30))
	bi_v.add_child(bi_hdr)

	for line in [
		"• R1: Corp. Vex — Armed Rifle Zombie",
		"• R2: Subject Goliath — Slow Tank Gorilla",
		"• R3: Patient Zero-9 — Toxic Spitter",
		"• R4: Panzer-Krieg — Flamethrower Mech",
		"• R5+: Volt Reaper & Omega Variants",
	]:
		var bl := Label.new()
		bl.text = line
		bl.add_theme_font_size_override("font_size", 13)
		bl.add_theme_color_override("font_color", Color(0.82, 0.84, 0.88))
		bi_v.add_child(bl)

	# Open Center Spacer so the live 3D Bunker & Boss Showcase Stage shines clearly!
	var center_spacer := Control.new()
	center_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_h.add_child(center_spacer)

	# Right Compact Translucent Loadout & Deploy Panel
	var right_card := PanelContainer.new()
	right_card.custom_minimum_size = Vector2(520, 0)
	right_card.size_flags_vertical = Control.SIZE_SHRINK_END
	right_card.add_theme_stylebox_override("panel", _make_card_style(Color(0.04, 0.05, 0.08, 0.84), Color(0.85, 0.22, 0.18), 2))
	body_h.add_child(right_card)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right_card.add_child(rv)

	detail_code = Label.new()
	detail_code.add_theme_font_size_override("font_size", 13)
	rv.add_child(detail_code)

	detail_name = Label.new()
	detail_name.add_theme_font_size_override("font_size", 26)
	detail_name.add_theme_color_override("font_color", Color.WHITE)
	rv.add_child(detail_name)

	detail_summary = Label.new()
	detail_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_summary.add_theme_font_size_override("font_size", 14)
	detail_summary.add_theme_color_override("font_color", Color(0.84, 0.86, 0.90))
	rv.add_child(detail_summary)

	detail_stats = Label.new()
	detail_stats.add_theme_font_size_override("font_size", 13)
	detail_stats.add_theme_color_override("font_color", Color(0.98, 0.80, 0.35))
	rv.add_child(detail_stats)

	detail_skills = VBoxContainer.new()
	detail_skills.add_theme_constant_override("separation", 6)
	rv.add_child(detail_skills)

	var controls_lbl := Label.new()
	controls_lbl.text = "[WASD] Move • [Shift] Sprint • [C] Crouch / Slide (while sprinting) • [Space] Jump • [LMB] Fire • [RMB] Aim • [R] Reload • [V] Knife • [G] Grenade • [1/2] Swap • [Q]/[F] Operator skills • [E] Buy / hold to rebuild windows • [ESC] Pause
Burn points at the AUGMENT FURNACE to level up Strength, Speed, Endurance, Stamina and more. Open doors to reach the Mystery Crate, turn on the GENERATOR to power the Weapon Forge, electric trap and field radio. Buy a SECOND WIND to get back up once when you go down. Every 5th round the hounds come with the lightning. From round 8, use the radio between rounds to call the extraction chopper and escape... or hunt the three glowing skulls."
	controls_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_lbl.add_theme_font_size_override("font_size", 12)
	controls_lbl.add_theme_color_override("font_color", Color(0.68, 0.76, 0.85))
	rv.add_child(controls_lbl)

	var deploy_btn := Button.new()
	deploy_btn.text = "▶  DEPLOY TO OUTBREAK (ROUND I)"
	deploy_btn.custom_minimum_size = Vector2(0, 52)
	deploy_btn.add_theme_font_size_override("font_size", 20)
	deploy_btn.add_theme_stylebox_override("normal", _make_card_style(Color(0.72, 0.12, 0.10), Color(1.0, 0.38, 0.28), 2))
	deploy_btn.add_theme_stylebox_override("hover", _make_card_style(Color(0.88, 0.18, 0.14), Color(1.0, 0.58, 0.38), 2))
	deploy_btn.pressed.connect(func():
		GameState.play_sfx("round_sting", -2.0, 1.0)
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	)
	rv.add_child(deploy_btn)

	var coop_btn := Button.new()
	coop_btn.text = "▶▶  CO-OP — PLAY WITH FRIENDS (UP TO 8)"
	coop_btn.custom_minimum_size = Vector2(0, 44)
	coop_btn.add_theme_font_size_override("font_size", 17)
	coop_btn.add_theme_stylebox_override("normal", _make_card_style(Color(0.08, 0.2, 0.3), Color(0.35, 0.8, 1.0), 2))
	coop_btn.add_theme_stylebox_override("hover", _make_card_style(Color(0.1, 0.28, 0.42), Color(0.55, 0.9, 1.0), 2))
	coop_btn.pressed.connect(func(): _open_coop())
	rv.add_child(coop_btn)
	_build_coop_panel(layer)


func _select_character(cid: String) -> void:
	GameState.selected_character = cid
	Net.set_character(cid)
	var cdata: Dictionary = GameState.CHARACTERS[cid]
	var accent: Color = cdata["accent"]

	for id_key in char_buttons.keys():
		var b: Button = char_buttons[id_key]
		var is_sel: bool = (id_key == cid)
		var col: Color = GameState.CHARACTERS[id_key]["accent"]
		b.add_theme_stylebox_override(
			"normal",
			_make_card_style(
				Color(0.15, 0.12, 0.16, 0.94) if is_sel else Color(0.05, 0.06, 0.08, 0.82),
				col if is_sel else Color(0.28, 0.30, 0.35),
				2 if is_sel else 1
			)
		)

	detail_code.text = cdata["codename"]
	detail_code.add_theme_color_override("font_color", accent)
	detail_name.text = cdata["name"]
	detail_summary.text = cdata["summary"]
	detail_stats.text = "VITALITY: %.0f HP   •   SPEED: %.1f m/s   •   SIDEARM: M1911" % [cdata["max_hp"], cdata["move_speed"]]

	for ch in detail_skills.get_children():
		ch.queue_free()

	for s_line in cdata["skills"]:
		var sl := Label.new()
		sl.text = s_line
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.add_theme_font_size_override("font_size", 13)
		sl.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98))
		detail_skills.add_child(sl)


# ---------------------------------------------------------------------------
# CO-OP LOBBY
# ---------------------------------------------------------------------------
var coop_panel: PanelContainer
var coop_status: Label
var coop_roster: Label
var coop_ip: LineEdit
var coop_start: Button
var coop_invite: Button
var coop_host_steam: Button


func _coop_button(text: String, on_press: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func():
		GameState.play_sfx("buy_ching", -8.0, 1.2)
		on_press.call()
	)
	parent.add_child(b)
	return b


func _build_coop_panel(layer: CanvasLayer) -> void:
	coop_panel = PanelContainer.new()
	coop_panel.set_anchors_preset(Control.PRESET_CENTER)
	coop_panel.offset_left = -340
	coop_panel.offset_right = 340
	coop_panel.offset_top = -290
	coop_panel.offset_bottom = 290
	coop_panel.add_theme_stylebox_override("panel", _make_card_style(Color(0.03, 0.05, 0.08, 0.97), Color(0.35, 0.8, 1.0), 2))
	coop_panel.visible = false
	layer.add_child(coop_panel)

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	coop_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	var title := Label.new()
	title.text = "CO-OP SQUAD"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	v.add_child(title)
	var sub := Label.new()
	sub.text = "Online play runs through Steam's relay network: no port forwarding, IPs stay private, and long-distance links take Valve's fast routes. Up to 8 survivors; zombie numbers and boss health scale with the squad."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.7, 0.78, 0.86))
	v.add_child(sub)

	coop_status = Label.new()
	coop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coop_status.add_theme_font_size_override("font_size", 15)
	coop_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	v.add_child(coop_status)

	var steam_row := HBoxContainer.new()
	steam_row.add_theme_constant_override("separation", 8)
	v.add_child(steam_row)
	coop_host_steam = _coop_button("HOST STEAM SQUAD", func(): Net.host_steam(), steam_row)
	coop_invite = _coop_button("INVITE STEAM FRIENDS", func(): Net.invite_friends(), steam_row)

	var ip_hdr := Label.new()
	ip_hdr.text = "DIRECT CONNECTION (LAN / PORT %d OPEN ON THE HOST)" % Net.PORT
	ip_hdr.add_theme_font_size_override("font_size", 12)
	ip_hdr.add_theme_color_override("font_color", Color(0.6, 0.66, 0.74))
	v.add_child(ip_hdr)
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	v.add_child(ip_row)
	coop_ip = LineEdit.new()
	coop_ip.placeholder_text = "HOST IP ADDRESS"
	coop_ip.custom_minimum_size = Vector2(220, 40)
	ip_row.add_child(coop_ip)
	_coop_button("HOST DIRECT", func(): Net.host_direct(), ip_row)
	_coop_button("JOIN IP", func(): Net.join_direct(coop_ip.text if coop_ip.text.strip_edges() != "" else "127.0.0.1"), ip_row)

	var roster_hdr := Label.new()
	roster_hdr.text = "SQUAD"
	roster_hdr.add_theme_font_size_override("font_size", 16)
	v.add_child(roster_hdr)
	coop_roster = Label.new()
	coop_roster.custom_minimum_size = Vector2(0, 150)
	coop_roster.add_theme_font_size_override("font_size", 15)
	v.add_child(coop_roster)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	v.add_child(bottom)
	coop_start = _coop_button("▶ START GAME", func(): Net.start_game(), bottom)
	_coop_button("LEAVE", func():
		Net.leave()
		Net.status_text = ""
		_refresh_coop()
	, bottom)
	_coop_button("CLOSE", func(): coop_panel.visible = false, bottom)

	Net.lobby_changed.connect(_refresh_coop)
	Net.status_changed.connect(func(_t: String): _refresh_coop())
	_refresh_coop()
	if Net.is_online() or Net.status_text != "":
		coop_panel.visible = true # back from a game, or a connection message to show


func _open_coop() -> void:
	coop_panel.visible = true
	_refresh_coop()


func _refresh_coop() -> void:
	if coop_panel == null or not is_instance_valid(coop_panel):
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
