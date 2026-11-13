extends Control
# MINIMAP (top-left corner, turns with you) and the full MAP (hold or tap [M],
# north up). Shows the zones, doors and stations, your squad, relics, the boss
# and commanders. Regular zombies are NOT shown: listen for them.
#
# Station glyphs use the shared HUD icon sheet: ammo, wall weapon, furnace,
# supply depot, second wind, mystery crate, generator, radio, forge, door.

const HI := preload("res://scripts/ui/hud_icons.gd")
const MINI := 172.0
const RANGE := 30.0 # metres from the centre of the minimap to its edge
const MAP_MIN := Vector2(-54.0, -62.0)
const MAP_MAX := Vector2(62.0, 42.0)
const ZONE_FILL := Color(0.32, 0.4, 0.5, 0.42)
const ZONE_LOCKED := Color(0.16, 0.17, 0.2, 0.5)
const ZONE_EDGE := Color(0.7, 0.8, 0.9, 0.75)

var player: Node3D
var arena: Node
var wave_mgr: Node
var big: bool = false
var _canvas: Control
var _big_canvas: Control
var _zone_lbl: Label
var _stations: Array = [] # {pos, icon, color, node}
var _fillable: Dictionary = {} # zone id -> polygon can be filled
var _font: Font
var _acc: float = 0.0
var _time: float = 0.0


func setup(p_player: Node3D, p_arena: Node, p_wave: Node) -> void:
	player = p_player
	arena = p_arena
	wave_mgr = p_wave
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var frame := Panel.new()
	frame.position = Vector2(14, 84)
	frame.size = Vector2(MINI, MINI)
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", HI.panel(Color(0.03, 0.04, 0.06, 0.78), Color(0.75, 0.2, 0.16, 0.9), 6, 2, 0))
	add_child(frame)
	_canvas = Control.new()
	_canvas.size = Vector2(MINI, MINI)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_mini)
	frame.add_child(_canvas)

	var zrow := HBoxContainer.new()
	zrow.position = Vector2(14, 84 + MINI + 6)
	zrow.add_theme_constant_override("separation", 6)
	zrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zrow)
	zrow.add_child(HI.icon("map", 14, HI.CYAN))
	_zone_lbl = HI.label("", 13, Color(0.8, 0.84, 0.9))
	_zone_lbl.add_theme_constant_override("outline_size", 5)
	_zone_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	zrow.add_child(_zone_lbl)
	zrow.add_child(HI.keycap(GameState.key_label("map"), 11))

	_big_canvas = Control.new()
	_big_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_canvas.visible = false
	_big_canvas.draw.connect(_draw_big)
	add_child(_big_canvas)

	for zid in arena.zone_polys:
		var ok := true
		for poly in arena.zone_polys[zid]:
			if Geometry2D.triangulate_polygon(poly).is_empty():
				ok = false
		_fillable[zid] = ok
	_index_stations.call_deferred()


func _index_stations() -> void:
	_stations.clear()
	for n in get_tree().get_nodes_in_group("wall_stations"):
		var n3 := n as Node3D
		if n3 == null or n3.is_in_group("barricades"):
			continue
		var icon := ""
		var col := Color.WHITE
		var path: String = (n3.get_script() as Script).resource_path if n3.get_script() else ""
		if n3 is WallStation:
			match (n3 as WallStation).station_type:
				"ammo_box":
					icon = "bullet"
					col = Color(1.0, 0.8, 0.25)
				"forge":
					icon = "anvil"
					col = Color(1.0, 0.5, 0.2)
				_:
					icon = "rifle"
					col = Color(0.4, 0.85, 1.0)
		elif path.ends_with("augment_furnace.gd"):
			icon = "flame"
			col = Color(1.0, 0.55, 0.2)
		elif path.ends_with("supply_depot.gd"):
			icon = "box"
			col = Color(0.5, 1.0, 0.55)
		elif path.ends_with("second_wind_station.gd"):
			icon = "cross"
			col = Color(0.4, 1.0, 0.6)
		elif path.ends_with("mystery_crate.gd"):
			icon = "crate"
			col = Color(0.8, 0.55, 1.0)
		elif path.ends_with("power_generator.gd"):
			icon = "bolt"
			col = Color(1.0, 0.95, 0.4)
		elif path.ends_with("exfil_radio.gd"):
			icon = "radio"
			col = Color(0.6, 0.95, 1.0)
		elif path.ends_with("zone_door.gd"):
			icon = "door"
			col = Color(1.0, 0.4, 0.3)
		elif path.ends_with("defense_pad.gd"):
			var is_turret: bool = String(n3.get("pad_kind")) == "turret"
			icon = "target" if is_turret else "arc"
			col = Color(0.35, 0.92, 1.0) if is_turret else Color(0.76, 0.48, 1.0)
		if icon != "":
			_stations.append({"pos": n3.global_position, "icon": icon, "color": col, "node": n3})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		big = not big
		_big_canvas.visible = big
		_big_canvas.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_acc += delta
	if _acc < 0.05 or not is_instance_valid(player):
		return
	_acc = 0.0
	if big and (player.get("is_dead") == true or get_tree().paused):
		big = false
		_big_canvas.visible = false
	_canvas.queue_redraw()
	if big:
		_big_canvas.queue_redraw()
	var zid := String(arena.zone_at(player.global_position))
	_zone_lbl.text = arena.zone_names.get(zid, "OUTSIDE")


# ---------------------------------------------------------------------------
# Things worth a marker: [world pos, kind, colour, pinned to the edge when far]
# ---------------------------------------------------------------------------
func _markers() -> Array:
	var out: Array = []
	if GameState.is_pvp():
		var my_t: int = int(player.team_id) if "team_id" in player else Net.my_team
		for c in get_tree().get_nodes_in_group("pvp_combatants"):
			var cn := c as Node3D
			if cn == null or cn == player or not is_instance_valid(cn) or ("is_dead" in cn and cn.is_dead):
				continue
			if "team_id" in cn and int(cn.team_id) == my_t:
				out.append([cn.global_position, "mate", GameState.pvp_team_color(my_t), false])
		for z in get_tree().get_nodes_in_group("pvp_objectives"):
			if is_instance_valid(z):
				var zcol: Color = Color(1.0, 0.25, 0.2) if ("is_planted" in z and z.is_planted) else (
					GameState.pvp_team_color(int(z.owner_team)) if ("owner_team" in z and int(z.owner_team) >= 0) else Color(1.0, 0.85, 0.25)
				)
				out.append([(z as Node3D).global_position, "pvp_obj_" + String(z.zone_id), zcol, true])
		var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
		if pvp_dir and pvp_dir.has_method("get_minimap_pings"):
			for ping in pvp_dir.get_minimap_pings():
				out.append([Vector3(ping["pos"]), "fire_ping", Color(1.0, 0.24, 0.2), false])
		for hb in get_tree().get_nodes_in_group("hazard_barrels"):
			if is_instance_valid(hb) and hb.has_method("is_intact") and hb.is_intact():
				out.append([(hb as Node3D).global_position, "barrel", Color(1.0, 0.38, 0.16), false])
		return out
	for p in get_tree().get_nodes_in_group("net_players"):
		if p == player or not is_instance_valid(p) or p.get("is_dead") == true or p.get("extracted") == true:
			continue
		var down: bool = p.get("is_downed") == true
		var col: Color = Color(1.0, 0.25, 0.2) if down else (p.get("color") if p.get("color") != null else Color(0.5, 0.9, 1.0))
		out.append([(p as Node3D).global_position, "down" if down else "mate", col, down])
	for c in get_tree().get_nodes_in_group("commanders"):
		if is_instance_valid(c) and not c.is_dead:
			out.append([(c as Node3D).global_position, "commander", ZombieEnemy.TIER_COLORS[c.tier], true])
	if wave_mgr:
		var had_boss := false
		for b in wave_mgr.active_bosses:
			if is_instance_valid(b) and not b.is_dead:
				out.append([b.global_position, "boss", Color(1.0, 0.2, 0.15), true])
				had_boss = true
		if not had_boss and is_instance_valid(wave_mgr.active_boss) and not wave_mgr.active_boss.is_dead:
			out.append([wave_mgr.active_boss.global_position, "boss", Color(1.0, 0.2, 0.15), true])
	for dp in get_tree().get_nodes_in_group("draft_pedestals"):
		if is_instance_valid(dp):
			var dcol: Color = dp.get("accent") if dp.get("accent") != null else Color(1.0, 0.85, 0.25)
			out.append([(dp as Node3D).global_position, "draft", dcol, true])
	for bz in get_tree().get_nodes_in_group("blitz_zones"):
		if is_instance_valid(bz):
			out.append([(bz as Node3D).global_position, "blitz", Color(1.0, 0.86, 0.22), true])
	for hb in get_tree().get_nodes_in_group("hazard_barrels"):
		if is_instance_valid(hb) and hb.has_method("is_intact") and hb.is_intact():
			out.append([(hb as Node3D).global_position, "barrel", Color(1.0, 0.38, 0.16), false])
	for pu in get_tree().get_nodes_in_group("net_powerups"):
		if is_instance_valid(pu):
			var mine: bool = pu.get("owner_peer") == null or int(pu.get("owner_peer")) == 0 or int(pu.get("owner_peer")) == Net.my_id()
			out.append([(pu as Node3D).global_position, "relic", Color(0.85, 0.6, 1.0) if mine else Color(0.5, 0.45, 0.6), mine])
	for tr in get_tree().get_nodes_in_group("zombie_traps"):
		if is_instance_valid(tr):
			out.append([(tr as Node3D).global_position, "trap", Color(1.0, 0.3, 0.2), false])
	if wave_mgr and int(wave_mgr.exfil_state) != 0:
		out.append([wave_mgr.lz_pos, "lz", Color(0.4, 1.0, 0.55), true])
	return out


func _draw_marker(cv: Control, at: Vector2, kind: String, col: Color, s: float) -> void:
	var pulse := 0.75 + 0.25 * sin(_time * 6.0)
	if kind.begins_with("pvp_obj_"):
		var zid: String = kind.substr(8)
		cv.draw_circle(at, 7.0 * s * pulse, Color(col.r, col.g, col.b, 0.35))
		cv.draw_arc(at, 6.2 * s, 0.0, TAU, 18, col, 1.8 * s)
		cv.draw_string(_font, at + Vector2(-4, 4) * s, zid, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), Color.WHITE)
		return
	match kind:
		"fire_ping":
			cv.draw_circle(at, 4.5 * s * pulse, col)
			cv.draw_arc(at, 6.5 * s, 0.0, TAU, 14, col, 1.2 * s)
		"mate":
			cv.draw_circle(at, 4.0 * s, Color.BLACK)
			cv.draw_circle(at, 3.0 * s, col)
		"down":
			cv.draw_circle(at, 6.0 * s * pulse, Color(col.r, col.g, col.b, 0.45))
			cv.draw_line(at + Vector2(-4, 0) * s, at + Vector2(4, 0) * s, col, 2.5 * s)
			cv.draw_line(at + Vector2(0, -4) * s, at + Vector2(0, 4) * s, col, 2.5 * s)
		"commander":
			var d := 5.5 * s * pulse
			cv.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0)]), col)
			cv.draw_polyline(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0), at + Vector2(0, -d)]), Color.BLACK, 1.0)
		"boss":
			cv.draw_circle(at, 7.5 * s * pulse, Color(col.r, col.g, col.b, 0.4))
			cv.draw_circle(at, 4.5 * s, col)
			cv.draw_arc(at, 7.5 * s, 0.0, TAU, 20, Color.BLACK, 1.0)
		"relic":
			var r := 5.0 * s
			cv.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.35, -r * 0.3), at + Vector2(r, 0), at + Vector2(r * 0.35, r * 0.3),
				at + Vector2(0, r), at + Vector2(-r * 0.35, r * 0.3), at + Vector2(-r, 0), at + Vector2(-r * 0.35, -r * 0.3)]), col)
		"trap":
			cv.draw_line(at + Vector2(-3, -3) * s, at + Vector2(3, 3) * s, col, 1.5 * s)
			cv.draw_line(at + Vector2(-3, 3) * s, at + Vector2(3, -3) * s, col, 1.5 * s)
		"lz":
			cv.draw_arc(at, 6.0 * s, 0.0, TAU, 20, col, 2.0 * s)
			cv.draw_string(_font, at + Vector2(-4, 4) * s, "H", HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), col)
		"draft":
			cv.draw_circle(at, 6.5 * s * pulse, Color(col.r, col.g, col.b, 0.38))
			cv.draw_circle(at, 3.8 * s, col)
			cv.draw_arc(at, 6.2 * s, 0.0, TAU, 18, Color.WHITE, 1.0)
		"blitz":
			var br := 7.2 * s * pulse
			cv.draw_arc(at, br, 0.0, TAU, 20, col, 1.8 * s)
			cv.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -4.6) * s, at + Vector2(4.6, 0) * s, at + Vector2(0, 4.6) * s, at + Vector2(-4.6, 0) * s]), col)
			cv.draw_polyline(PackedVector2Array([at + Vector2(0, -4.6) * s, at + Vector2(4.6, 0) * s, at + Vector2(0, 4.6) * s, at + Vector2(-4.6, 0) * s, at + Vector2(0, -4.6) * s]), Color.BLACK, 1.0)
		"barrel":
			cv.draw_circle(at, 3.0 * s, Color.BLACK)
			cv.draw_circle(at, 2.1 * s, col)


func _draw_station(cv: Control, at: Vector2, st: Dictionary, s: float) -> void:
	var node: Node = st["node"]
	if not is_instance_valid(node):
		return
	if node is Node3D and not (node as Node3D).visible:
		return
	if st["icon"] == "door" and node.get("_opened") == true:
		return
	var col: Color = st["color"]
	var r := 8.0 * s
	cv.draw_rect(Rect2(at - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), Color(0.02, 0.03, 0.05, 0.88))
	cv.draw_rect(Rect2(at - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), Color(col.r, col.g, col.b, 0.5), false, 1.0)
	cv.draw_texture_rect(HI.tex(st["icon"]), Rect2(at - Vector2(6, 6) * s, Vector2(12, 12) * s), false, col)


# ---------------------------------------------------------------------------
# MINIMAP: you are the centre, forward is up
# ---------------------------------------------------------------------------
func _draw_mini() -> void:
	if not is_instance_valid(player) or arena == null:
		return
	var c := Vector2(MINI, MINI) * 0.5
	var scale_px := (MINI * 0.5) / RANGE
	var yaw := player.rotation.y
	var cs := cos(yaw)
	var sn := sin(yaw)
	var origin := Vector2(player.global_position.x, player.global_position.z)
	var to_map := func(w: Vector2) -> Vector2:
		var r := w - origin
		return c + Vector2(r.x * cs - r.y * sn, r.x * sn + r.y * cs) * scale_px
	for zid in arena.zone_polys:
		var open: bool = arena.is_zone_open(zid)
		for poly in arena.zone_polys[zid]:
			var pts := PackedVector2Array()
			for p in poly:
				pts.append(to_map.call(p))
			if _fillable.get(zid, false):
				_canvas.draw_colored_polygon(pts, ZONE_FILL if open else ZONE_LOCKED)
			pts.append(pts[0])
			_canvas.draw_polyline(pts, ZONE_EDGE if open else Color(0.4, 0.42, 0.48, 0.6), 1.5)
	for st in _stations:
		var sp: Vector3 = st["pos"]
		var at: Vector2 = to_map.call(Vector2(sp.x, sp.z))
		if at.distance_to(c) < MINI * 0.5 - 6.0:
			_draw_station(_canvas, at, st, 1.0)
	for m in _markers():
		var wp: Vector3 = m[0]
		var at: Vector2 = to_map.call(Vector2(wp.x, wp.z))
		var off := at - c
		var lim := MINI * 0.5 - 9.0
		if absf(off.x) > lim or absf(off.y) > lim:
			if not m[3]:
				continue
			# Far away: pin it to the edge so it still points the way
			off = off * (lim / maxf(absf(off.x), absf(off.y)))
			at = c + off
		_draw_marker(_canvas, at, m[1], m[2], 1.0)
	# North
	var north := Vector2(sn, -cs) # where world north (-Z) points on the turned map
	_canvas.draw_string(_font, c + north * (MINI * 0.5 - 11.0) + Vector2(-4, 4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.85, 0.4))
	# You
	_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(5.5, 6), c + Vector2(0, 3), c + Vector2(-5.5, 6)]), Color(1, 1, 1))
	_canvas.draw_polyline(PackedVector2Array([c + Vector2(0, -8), c + Vector2(5.5, 6), c + Vector2(0, 3), c + Vector2(-5.5, 6), c + Vector2(0, -8)]), Color.BLACK, 1.0)


# ---------------------------------------------------------------------------
# FULL MAP: north up, everything at once
# ---------------------------------------------------------------------------
func _draw_big() -> void:
	if not is_instance_valid(player) or arena == null:
		return
	var vp := get_viewport_rect().size
	var mb: Rect2 = arena.get_map_bounds() if arena.has_method("get_map_bounds") else Rect2(MAP_MIN, MAP_MAX - MAP_MIN)
	var map_min := mb.position
	var span := mb.size
	var max_h_frac: float = 0.66 if GameState.is_pvp() else 0.78
	var scale_px := minf((vp.x * 0.62) / span.x, (vp.y * max_h_frac) / span.y)
	var size_px := span * scale_px
	var top_left := (vp - size_px) * 0.5 + (Vector2(0.0, 38.0) if GameState.is_pvp() else Vector2.ZERO)
	var to_map := func(w: Vector2) -> Vector2:
		return top_left + (w - map_min) * scale_px
	var map_title: String = arena.get_map_title() if arena.has_method("get_map_title") else "OUTPOST NACHT-7"
	var frame := Rect2(top_left - Vector2(18, 44), size_px + Vector2(36, 96))
	_big_canvas.draw_rect(frame, Color(0.02, 0.03, 0.045, 0.96))
	_big_canvas.draw_rect(frame, Color(0.75, 0.2, 0.16, 0.9), false, 2.0)
	_big_canvas.draw_texture_rect(HI.tex("map"), Rect2(frame.position + Vector2(16, 11), Vector2(20, 20)), false, Color(0.95, 0.95, 0.98))
	_big_canvas.draw_string(_font, frame.position + Vector2(44, 28), "%s  —  TACTICAL MAP" % map_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.95, 0.98))
	_big_canvas.draw_string(_font, frame.position + Vector2(frame.size.x - 130, 28), "[%s] CLOSE" % GameState.key_label("map"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.72, 0.78))
	for zid in arena.zone_polys:
		var open: bool = arena.is_zone_open(zid)
		var centre := Vector2.ZERO
		var count := 0
		for poly in arena.zone_polys[zid]:
			var pts := PackedVector2Array()
			for p in poly:
				pts.append(to_map.call(p))
				centre += to_map.call(p)
				count += 1
			if _fillable.get(zid, false):
				_big_canvas.draw_colored_polygon(pts, ZONE_FILL if open else ZONE_LOCKED)
			pts.append(pts[0])
			_big_canvas.draw_polyline(pts, ZONE_EDGE if open else Color(0.4, 0.42, 0.48, 0.7), 2.0)
		if count > 0:
			centre /= float(count)
			var zname: String = arena.zone_names.get(zid, zid)
			var w := _font.get_string_size(zname, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			_big_canvas.draw_string(_font, centre + Vector2(-w * 0.5, 0), zname, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.95, 1.0, 0.95) if open else Color(0.6, 0.6, 0.65, 0.9))
			if not open:
				_big_canvas.draw_string(_font, centre + Vector2(-24, 17), "LOCKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.45, 0.35, 0.9))
	for st in _stations:
		var sp: Vector3 = st["pos"]
		_draw_station(_big_canvas, to_map.call(Vector2(sp.x, sp.z)), st, 1.5)
	for m in _markers():
		var wp: Vector3 = m[0]
		_draw_marker(_big_canvas, to_map.call(Vector2(wp.x, wp.z)), m[1], m[2], 1.6)
	# You: arrow turned to where you look
	var me: Vector2 = to_map.call(Vector2(player.global_position.x, player.global_position.z))
	var yaw := player.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	var tri := PackedVector2Array([me + fwd * 13.0, me - fwd * 8.0 + side * 8.0, me - fwd * 3.0, me - fwd * 8.0 - side * 8.0])
	_big_canvas.draw_colored_polygon(tri, Color(1, 1, 1))
	tri.append(tri[0])
	_big_canvas.draw_polyline(tri, Color.BLACK, 1.5)
	var lc := Color(0.75, 0.78, 0.84)
	if GameState.is_pvp():
		var px := frame.position.x + 18.0
		var py := frame.end.y - 16.0
		var pvp_legend := [
			["mate", "SQUADMATES", Color(0.35, 0.85, 1.0)],
			["pvp_obj_A", "OBJECTIVE", Color(1.0, 0.85, 0.25)],
			["fire_ping", "GUNFIRE PING", Color(1.0, 0.24, 0.2)],
			["barrel", "HAZARD DRUM", Color(1.0, 0.38, 0.16)],
		]
		for mk in pvp_legend:
			_draw_marker(_big_canvas, Vector2(px + 6.0, py - 4.0), mk[0], mk[2], 0.9)
			px += 20.0
			_big_canvas.draw_string(_font, Vector2(px, py), mk[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, lc)
			px += _font.get_string_size(mk[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24.0
		return
	_legend_row(_big_canvas, Vector2(frame.position.x + 16, frame.end.y - 32), [
		["bullet", "AMMO", Color(1.0, 0.8, 0.25)],
		["rifle", "WEAPON", Color(0.4, 0.85, 1.0)],
		["flame", "FURNACE", Color(1.0, 0.55, 0.2)],
		["box", "SUPPLY", Color(0.5, 1.0, 0.55)],
		["cross", "SECOND WIND", Color(0.4, 1.0, 0.6)],
		["crate", "CRATE", Color(0.8, 0.55, 1.0)],
	], lc)
	var x := _legend_row(_big_canvas, Vector2(frame.position.x + 16, frame.end.y - 12), [
		["bolt", "GENERATOR", Color(1.0, 0.95, 0.4)],
		["anvil", "FORGE", Color(1.0, 0.5, 0.2)],
		["radio", "RADIO", Color(0.6, 0.95, 1.0)],
		["door", "DOOR", Color(1.0, 0.4, 0.3)],
	], lc)
	var y2 := frame.end.y - 12
	var map_markers := [["commander", "COMMANDER", Color(1.0, 0.6, 0.2)], ["boss", "BOSS", Color(1.0, 0.2, 0.15)], ["relic", "RELIC", Color(0.85, 0.6, 1.0)], ["barrel", "DRUM", Color(1.0, 0.38, 0.16)]]
	if GameState.is_overdrive():
		map_markers.append(["blitz", "BLITZ POD", Color(1.0, 0.86, 0.22)])
	for mk in map_markers:
		_draw_marker(_big_canvas, Vector2(x + 6, y2 - 4), mk[0], mk[2], 0.8)
		x += 17
		_big_canvas.draw_string(_font, Vector2(x, y2), mk[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lc)
		x += _font.get_string_size(mk[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18


func _legend_row(cv: Control, at: Vector2, entries: Array, lc: Color) -> float:
	var x := at.x
	for e in entries:
		cv.draw_texture_rect(HI.tex(e[0]), Rect2(Vector2(x, at.y - 11), Vector2(13, 13)), false, e[2])
		x += 17
		cv.draw_string(_font, Vector2(x, at.y), e[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lc)
		x += _font.get_string_size(e[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18
	return x
