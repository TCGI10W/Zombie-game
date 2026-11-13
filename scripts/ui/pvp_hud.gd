class_name PvpHUD
extends CanvasLayer

# Competitive PvP HUD overlay: top match clock + 2/4/6-team score bar,
# mode-specific tracker (Gun Game ladder, S&D bomb/spectate, Domination A/B/C),
# live top-right kill feed, respawn countdown, and 32-player [Tab] scoreboard.

const HI := preload("res://scripts/ui/hud_icons.gd")

var player: PlayerController
var pvp_dir: PvpDirector

var _header_lbl: Label
var _timer_lbl: Label
var _team_row: HBoxContainer
var _team_pills: Array[Dictionary] = []

var _mode_bar: HBoxContainer
var _gg_pills: Array[PanelContainer] = []
var _obj_pills: Dictionary = {}

var _hold_box: VBoxContainer
var _hold_lbl: Label
var _hold_bar: ProgressBar

var _respawn_lbl: Label
var _spectate_lbl: Label
var _feed_box: VBoxContainer

var _sb_overlay: ColorRect
var _sb_title: Label
var _sb_grid: GridContainer
var _sb_force: bool = false

var _spec_idx: int = 0
var _spec_target: Node3D = null
var _ui_t: float = 0.0


func setup(p_player: PlayerController, p_dir: PvpDirector) -> void:
	player = p_player
	pvp_dir = p_dir
	layer = 7
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	pvp_dir.state_updated.connect(_refresh_header)
	pvp_dir.kill_feed_added.connect(_on_kill_feed_added)
	_refresh_header()


func set_scoreboard_forced(on: bool) -> void:
	_sb_force = on
	if _sb_overlay:
		_sb_overlay.visible = on
		if on:
			_rebuild_scoreboard()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- TOP-CENTER MATCH HEADER & TEAM SCORE PILLS ---
	var top_c := VBoxContainer.new()
	top_c.anchor_left = 0.5
	top_c.anchor_right = 0.5
	top_c.offset_left = -360
	top_c.offset_right = 360
	top_c.offset_top = 10
	top_c.offset_bottom = 120
	top_c.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_c.add_theme_constant_override("separation", 5)
	top_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_c)

	var head_panel := PanelContainer.new()
	head_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head_panel.add_theme_stylebox_override("panel", HI.panel(Color(0.05, 0.06, 0.09, 0.88), Color(0.28, 0.34, 0.44), 4, 1, 8))
	top_c.add_child(head_panel)

	var head_h := HBoxContainer.new()
	head_h.add_theme_constant_override("separation", 16)
	head_panel.add_child(head_h)

	_header_lbl = HI.label("PVP", 13, Color(0.88, 0.91, 0.96))
	head_h.add_child(_header_lbl)
	_timer_lbl = HI.label("10:00", 17, HI.AMBER)
	head_h.add_child(_timer_lbl)

	_team_row = HBoxContainer.new()
	_team_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_team_row.add_theme_constant_override("separation", 6)
	top_c.add_child(_team_row)

	for tid in range(pvp_dir.team_count):
		var t_col: Color = GameState.pvp_team_color(tid)
		var is_mine: bool = (tid == Net.my_team)
		var pill := PanelContainer.new()
		pill.custom_minimum_size = Vector2(104 if pvp_dir.team_count <= 4 else 92, 34)
		var sb := HI.panel(
			t_col.darkened(0.76) if is_mine else Color(0.05, 0.06, 0.09, 0.86),
			t_col if is_mine else t_col.darkened(0.35),
			4,
			2 if is_mine else 1,
			5
		)
		pill.add_theme_stylebox_override("panel", sb)
		var ph := HBoxContainer.new()
		ph.alignment = BoxContainer.ALIGNMENT_CENTER
		ph.add_theme_constant_override("separation", 6)
		pill.add_child(ph)
		var code_l: Label = HI.label(GameState.pvp_team_code(tid), 12, t_col)
		ph.add_child(code_l)
		var score_l: Label = HI.label("0", 16, Color.WHITE)
		ph.add_child(score_l)
		_team_row.add_child(pill)
		_team_pills.append({"panel": pill, "code": code_l, "score": score_l})

	# --- MODE SUB-BAR (GUN GAME LADDER / S&D SITES / DOM FLAGS) ---
	_mode_bar = HBoxContainer.new()
	_mode_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_mode_bar.add_theme_constant_override("separation", 4)
	top_c.add_child(_mode_bar)
	_build_mode_bar()

	# --- PLANT / DEFUSE HOLD PROGRESS ---
	_hold_box = VBoxContainer.new()
	_hold_box.anchor_left = 0.5
	_hold_box.anchor_right = 0.5
	_hold_box.anchor_top = 0.5
	_hold_box.anchor_bottom = 0.5
	_hold_box.offset_left = -160
	_hold_box.offset_right = 160
	_hold_box.offset_top = 86
	_hold_box.offset_bottom = 128
	_hold_box.visible = false
	_hold_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hold_box)

	_hold_lbl = HI.label("", 14, HI.AMBER)
	_hold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hold_lbl.add_theme_constant_override("outline_size", 5)
	_hold_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_hold_box.add_child(_hold_lbl)

	_hold_bar = ProgressBar.new()
	_hold_bar.custom_minimum_size = Vector2(0, 8)
	_hold_bar.max_value = 1.0
	_hold_bar.show_percentage = false
	_hold_bar.add_theme_stylebox_override("background", HI.bar(Color(0.08, 0.09, 0.12), 2))
	_hold_bar.add_theme_stylebox_override("fill", HI.bar(HI.AMBER, 2))
	_hold_box.add_child(_hold_bar)

	# --- RESPAWN & SPECTATE BANNERS ---
	_respawn_lbl = HI.label("", 22, HI.AMBER)
	_respawn_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_respawn_lbl.offset_left = -260
	_respawn_lbl.offset_right = 260
	_respawn_lbl.offset_top = -170
	_respawn_lbl.offset_bottom = -132
	_respawn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_lbl.add_theme_constant_override("outline_size", 6)
	_respawn_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_respawn_lbl.visible = false
	root.add_child(_respawn_lbl)

	_spectate_lbl = HI.label("", 15, Color(0.82, 0.92, 1.0))
	_spectate_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spectate_lbl.offset_left = -320
	_spectate_lbl.offset_right = 320
	_spectate_lbl.offset_top = -136
	_spectate_lbl.offset_bottom = -104
	_spectate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectate_lbl.add_theme_constant_override("outline_size", 5)
	_spectate_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_spectate_lbl.visible = false
	root.add_child(_spectate_lbl)

	# --- TOP-RIGHT KILL FEED ---
	_feed_box = VBoxContainer.new()
	_feed_box.anchor_left = 1.0
	_feed_box.anchor_right = 1.0
	_feed_box.offset_left = -380
	_feed_box.offset_right = -16
	_feed_box.offset_top = 14
	_feed_box.offset_bottom = 220
	_feed_box.add_theme_constant_override("separation", 4)
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed_box)

	# --- 32-PLAYER MULTI-TEAM SCOREBOARD OVERLAY ---
	_sb_overlay = ColorRect.new()
	_sb_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sb_overlay.color = Color(0.02, 0.03, 0.05, 0.72)
	_sb_overlay.visible = false
	_sb_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_sb_overlay)

	var sb_panel := PanelContainer.new()
	sb_panel.anchor_left = 0.5
	sb_panel.anchor_right = 0.5
	sb_panel.anchor_top = 0.5
	sb_panel.anchor_bottom = 0.5
	sb_panel.offset_left = -630
	sb_panel.offset_right = 630
	sb_panel.offset_top = -365
	sb_panel.offset_bottom = 365
	sb_panel.add_theme_stylebox_override("panel", HI.panel(Color(0.04, 0.05, 0.08, 0.96), Color(0.32, 0.38, 0.50), 6, 1, 14))
	_sb_overlay.add_child(sb_panel)

	var sb_v := VBoxContainer.new()
	sb_v.add_theme_constant_override("separation", 8)
	sb_panel.add_child(sb_v)

	_sb_title = HI.label("", 16, Color.WHITE)
	sb_v.add_child(_sb_title)

	_sb_grid = GridContainer.new()
	_sb_grid.columns = 2
	_sb_grid.add_theme_constant_override("h_separation", 14)
	_sb_grid.add_theme_constant_override("v_separation", 8)
	_sb_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sb_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sb_v.add_child(_sb_grid)


func _build_mode_bar() -> void:
	match GameState.pvp_mode:
		"gungame":
			var short_names := {
				"pistol": "PIS", "deagle_50": "DGL", "spas12": "SPS", "vector_45": "VEC",
				"m4_carbine": "M4", "scar_h": "SCR", "mk14_ebr": "EBR", "m249_saw": "SAW",
				"awm_magnum": "AWM", "volt": "VLT", "rpg7": "RPG", "knife": "KNF",
			}
			for i in range(GameState.GUN_GAME_LADDER.size()):
				var w: String = GameState.GUN_GAME_LADDER[i]
				var pc := PanelContainer.new()
				pc.custom_minimum_size = Vector2(46, 24)
				pc.add_theme_stylebox_override("panel", HI.panel(Color(0.06, 0.07, 0.1, 0.8), Color(0.22, 0.25, 0.32), 3, 1, 3))
				var lbl: Label = HI.label("%d.%s" % [i + 1, short_names.get(w, w.substr(0, 3).to_upper())], 11, Color(0.75, 0.78, 0.85))
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				pc.add_child(lbl)
				_mode_bar.add_child(pc)
				_gg_pills.append(pc)
		"snd":
			for sid in ["A", "B"]:
				var pc := PanelContainer.new()
				pc.custom_minimum_size = Vector2(96, 24)
				pc.add_theme_stylebox_override("panel", HI.panel(Color(0.06, 0.07, 0.1, 0.82), HI.AMBER.darkened(0.3), 3, 1, 4))
				var lbl: Label = HI.label("SITE %s" % sid, 12, HI.AMBER)
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				pc.add_child(lbl)
				_mode_bar.add_child(pc)
				_obj_pills[sid] = {"panel": pc, "label": lbl}
		"dom":
			for fid in ["A", "B", "C"]:
				var pc := PanelContainer.new()
				pc.custom_minimum_size = Vector2(96, 24)
				pc.add_theme_stylebox_override("panel", HI.panel(Color(0.06, 0.07, 0.1, 0.82), Color(0.5, 0.55, 0.65), 3, 1, 4))
				var lbl: Label = HI.label("FLAG %s" % fid, 12, Color.WHITE)
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				pc.add_child(lbl)
				_mode_bar.add_child(pc)
				_obj_pills[fid] = {"panel": pc, "label": lbl}


func _process(delta: float) -> void:
	if not is_instance_valid(pvp_dir) or not is_instance_valid(player):
		return
	_ui_t += delta
	if _ui_t >= 0.1:
		_ui_t = 0.0
		_refresh_header()
		_refresh_mode_bar()
		_refresh_kill_feed()

	# Plant / Defuse hold progress
	if pvp_dir.local_hold_text != "":
		_hold_box.visible = true
		_hold_lbl.text = pvp_dir.local_hold_text
		_hold_bar.value = pvp_dir.local_hold_prog
	else:
		_hold_box.visible = false

	# Respawn timer or S&D Spectate
	_update_death_and_spectate()

	# 32-player Scoreboard ([Tab])
	var want_sb: bool = _sb_force or (Input.is_action_pressed("scoreboard") and not pvp_dir.match_ended)
	if want_sb != _sb_overlay.visible:
		_sb_overlay.visible = want_sb
		if want_sb:
			_rebuild_scoreboard()
	elif want_sb and _ui_t == 0.0:
		_rebuild_scoreboard()


func _refresh_header() -> void:
	var sec: int = maxi(0, ceili(pvp_dir.match_time_left))
	_timer_lbl.text = "%02d:%02d" % [sec / 60, sec % 60]
	var flash_bomb: bool = GameState.pvp_mode == "snd" and pvp_dir.snd_planted_site != ""
	_timer_lbl.add_theme_color_override("font_color", HI.RED if flash_bomb else HI.AMBER)

	var map_short: String = String(GameState.pvp_map_info().get("short", "NACHT-7"))
	match GameState.pvp_mode:
		"tdm":
			_header_lbl.text = "%s  ·  TEAM DEATHMATCH  ·  FIRST TO %d" % [map_short, pvp_dir.score_limit]
		"gungame":
			var me: Dictionary = pvp_dir.roster.get("peer_%d" % Net.my_id(), {})
			var t: int = int(me.get("gg_tier", 0)) + 1
			_header_lbl.text = "%s  ·  GUN GAME  ·  TIER %d / %d" % [map_short, t, GameState.GUN_GAME_LADDER.size()]
		"snd":
			if pvp_dir.snd_planted_site != "":
				_header_lbl.text = "%s  ·  S&D R%d  ·  BOMB AT %s" % [map_short, pvp_dir.snd_round, pvp_dir.snd_planted_site]
			else:
				_header_lbl.text = "%s  ·  SEARCH & DESTROY  ·  R%d (FIRST TO %d)" % [map_short, pvp_dir.snd_round, pvp_dir.snd_win_target]
		"dom":
			_header_lbl.text = "%s  ·  DOMINATION  ·  FIRST TO %d" % [map_short, pvp_dir.score_limit]

	for i in range(mini(_team_pills.size(), pvp_dir.team_scores.size())):
		var lbl: Label = _team_pills[i]["score"]
		lbl.text = str(pvp_dir.team_scores[i])


func _refresh_mode_bar() -> void:
	if GameState.pvp_mode == "gungame":
		var me: Dictionary = pvp_dir.roster.get("peer_%d" % Net.my_id(), {})
		var cur: int = clampi(int(me.get("gg_tier", 0)), 0, _gg_pills.size() - 1)
		for i in range(_gg_pills.size()):
			var pc: PanelContainer = _gg_pills[i]
			var lbl: Label = pc.get_child(0) as Label
			if i == cur:
				pc.add_theme_stylebox_override("panel", HI.panel(Color(0.22, 0.16, 0.04, 0.95), HI.AMBER, 3, 2, 3))
				lbl.add_theme_color_override("font_color", Color.WHITE)
			elif i < cur:
				pc.add_theme_stylebox_override("panel", HI.panel(Color(0.05, 0.14, 0.08, 0.85), HI.GREEN.darkened(0.3), 3, 1, 3))
				lbl.add_theme_color_override("font_color", HI.GREEN)
			else:
				pc.add_theme_stylebox_override("panel", HI.panel(Color(0.06, 0.07, 0.1, 0.78), Color(0.22, 0.25, 0.32), 3, 1, 3))
				lbl.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	elif GameState.pvp_mode == "snd" or GameState.pvp_mode == "dom":
		for z in get_tree().get_nodes_in_group("pvp_objectives"):
			var oz := z as PvpObjectiveZone
			if oz == null or not _obj_pills.has(oz.zone_id):
				continue
			var d: Dictionary = _obj_pills[oz.zone_id]
			var pc: PanelContainer = d["panel"]
			var lbl: Label = d["label"]
			if oz.zone_kind == "bomb_site":
				if oz.is_planted:
					pc.add_theme_stylebox_override("panel", HI.panel(Color(0.28, 0.06, 0.05, 0.95), HI.RED, 3, 2, 4))
					lbl.text = "%s ARMED %ds" % [oz.zone_id, ceili(oz.bomb_timer)]
					lbl.add_theme_color_override("font_color", HI.RED)
				else:
					pc.add_theme_stylebox_override("panel", HI.panel(Color(0.06, 0.07, 0.1, 0.82), HI.AMBER.darkened(0.35), 3, 1, 4))
					lbl.text = "SITE %s" % oz.zone_id
					lbl.add_theme_color_override("font_color", HI.AMBER)
			else:
				var col: Color = GameState.pvp_team_color(oz.owner_team) if oz.owner_team >= 0 else Color(0.75, 0.78, 0.85)
				if oz.contested:
					col = HI.AMBER
				pc.add_theme_stylebox_override("panel", HI.panel(col.darkened(0.78), col, 3, 2 if oz.owner_team >= 0 else 1, 4))
				lbl.text = "%s · %s" % [oz.zone_id, "CONT" if oz.contested else (GameState.pvp_team_code(oz.owner_team) if oz.owner_team >= 0 else "OPEN")]
				lbl.add_theme_color_override("font_color", col)


func _update_death_and_spectate() -> void:
	if not player.is_dead or pvp_dir.match_ended:
		_respawn_lbl.visible = false
		_spectate_lbl.visible = false
		if is_instance_valid(_spec_target) and "spectated" in _spec_target:
			_spec_target.spectated = false
		_spec_target = null
		return

	if GameState.pvp_mode != "snd":
		_spectate_lbl.visible = false
		var me: Dictionary = pvp_dir.roster.get("peer_%d" % Net.my_id(), {})
		var rem: float = maxf(0.0, float(me.get("respawn_t", 0.0)))
		_respawn_lbl.visible = true
		_respawn_lbl.text = "ELIMINATED  ·  RESPAWNING IN %.1fs" % rem
		return

	_respawn_lbl.visible = false
	# S&D Spectate living teammate (fallback to any living combatant if team wiped)
	var allies: Array[Node3D] = []
	var others: Array[Node3D] = []
	for key in pvp_dir.nodes_by_key.keys():
		var e: Dictionary = pvp_dir.roster.get(key, {})
		if bool(e.get("dead", true)):
			continue
		var n: Node3D = pvp_dir.nodes_by_key[key] as Node3D
		if n == null or n == player or not is_instance_valid(n):
			continue
		if int(e.get("team", -1)) == player.team_id:
			allies.append(n)
		else:
			others.append(n)
	var pool: Array[Node3D] = allies if not allies.is_empty() else others
	if pool.is_empty():
		_spectate_lbl.visible = false
		return
	if Input.is_action_just_pressed("fire"):
		_spec_idx += 1
	var tgt: Node3D = pool[_spec_idx % pool.size()]
	if _spec_target != tgt:
		if is_instance_valid(_spec_target) and "spectated" in _spec_target:
			_spec_target.spectated = false
		_spec_target = tgt
		if "spectated" in _spec_target:
			_spec_target.spectated = true

	var dname: String = String(tgt.display_name) if "display_name" in tgt else "OPERATIVE"
	_spectate_lbl.visible = true
	_spectate_lbl.text = "SPECTATING %s  ·  [CLICK] NEXT  ·  RESPAWNS NEXT ROUND" % dname
	player.global_position = tgt.global_position
	player.rotation.y = tgt.rotation.y
	player.head_pivot.position.y = player.head_y()
	player.head_pivot.rotation.x = float(tgt.pitch) if "pitch" in tgt else 0.0
	player.camera.position = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO


func _on_kill_feed_added(_entry: Dictionary) -> void:
	_refresh_kill_feed()


func _refresh_kill_feed() -> void:
	for c in _feed_box.get_children():
		c.queue_free()
	var now: float = Time.get_ticks_msec() / 1000.0
	var shown: int = 0
	for e in pvp_dir.kill_feed:
		if now - float(e["time"]) > 6.5:
			continue
		if shown >= 5:
			break
		shown += 1
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_SHRINK_END
		pc.add_theme_stylebox_override("panel", HI.panel(Color(0.04, 0.05, 0.08, 0.80), Color(0.22, 0.26, 0.34), 3, 1, 5))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		pc.add_child(row)
		var k_col: Color = GameState.pvp_team_color(int(e["k_team"])) if int(e["k_team"]) >= 0 else HI.DIM
		var v_col: Color = GameState.pvp_team_color(int(e["v_team"]))
		row.add_child(HI.label(String(e["killer"]), 12, k_col))
		var mid: String = "[%s%s]" % [String(e["weapon"]), " HS" if bool(e["hs"]) else (" HUMILIATED!" if bool(e["humil"]) else "")]
		row.add_child(HI.label(mid, 11, HI.AMBER if bool(e["hs"]) or bool(e["humil"]) else HI.DIM))
		row.add_child(HI.label(String(e["victim"]), 12, v_col))
		_feed_box.add_child(pc)


func _rebuild_scoreboard() -> void:
	if _sb_grid == null or pvp_dir == null:
		return
	var sec: int = maxi(0, ceili(pvp_dir.match_time_left))
	var map_name: String = String(GameState.pvp_map_info().get("name", "OUTPOST NACHT-7"))
	_sb_title.text = "%s  ·  %s  ·  %d TEAMS / %d COMBATANTS  ·  %02d:%02d" % [
		map_name,
		GameState.PVP_MODES.get(GameState.pvp_mode, {}).get("name", "PVP"),
		pvp_dir.team_count,
		pvp_dir.roster.size(),
		sec / 60,
		sec % 60
	]
	for c in _sb_grid.get_children():
		c.queue_free()

	var row_font: int = 12 if pvp_dir.team_count == 2 else (11 if pvp_dir.team_count == 4 else 10)
	var row_sep: int = 2 if pvp_dir.team_count == 2 else 1
	var my_key: String = "peer_%d" % Net.my_id()

	for tid in range(pvp_dir.team_count):
		var t_col: Color = GameState.pvp_team_color(tid)
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", HI.panel(Color(0.05, 0.06, 0.09, 0.90), t_col.darkened(0.25), 4, 1, 6))
		_sb_grid.add_child(card)

		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", row_sep)
		card.add_child(v)

		var hdr := HBoxContainer.new()
		v.add_child(hdr)
		var t_name_l: Label = HI.label("%s  (SCORE %d)" % [GameState.pvp_team_name(tid), pvp_dir.team_scores[tid]], row_font + 1, t_col)
		t_name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.add_child(t_name_l)
		var col_hdr: Label = HI.label("K / D / A   PTS", row_font - 1, HI.DIM)
		hdr.add_child(col_hdr)

		# Collect & sort players on this team by score desc
		var members: Array[Dictionary] = []
		for e in pvp_dir.roster.values():
			var d: Dictionary = e
			if int(d["team"]) == tid:
				members.append(d)
		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["score"]) != int(b["score"]):
				return int(a["score"]) > int(b["score"])
			return int(a["kills"]) > int(b["kills"])
		)

		for m in members:
			var is_me: bool = (String(m["key"]) == my_key)
			var is_dead_m: bool = bool(m["dead"])
			var row := HBoxContainer.new()
			v.add_child(row)
			var prefix: String = "★ " if is_me else ("✕ " if is_dead_m else "  ")
			var nl: Label = HI.label(prefix + String(m["name"]), row_font, HI.AMBER if is_me else (HI.DIM if is_dead_m else Color(0.92, 0.94, 0.98)))
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nl.clip_text = true
			row.add_child(nl)
			var tier_tag: String = ("T%d " % (int(m["gg_tier"]) + 1)) if GameState.pvp_mode == "gungame" else ""
			var stats_l: Label = HI.label("%s%d / %d / %d   %d" % [tier_tag, int(m["kills"]), int(m["deaths"]), int(m["assists"]), int(m["score"])], row_font, HI.AMBER if is_me else Color(0.8, 0.84, 0.9))
			row.add_child(stats_l)
