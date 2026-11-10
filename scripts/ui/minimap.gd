extends Control
# MINIMAP (top-left corner, turns with you) and the full MAP (hold or tap [M],
# north up). Shows the zones, doors and stations, your squad, relics, the boss
# and commanders. Regular zombies are NOT shown: listen for them.
#
# Station letters:  A ammo cache   W wall weapon   F augment furnace
#   $ supply depot   + second wind   ? mystery crate   G generator
#   R radio   U weapon forge   D locked door

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
var _stations: Array = [] # {pos, letter, color, node}
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.06, 0.72)
	sb.border_color = Color(0.75, 0.2, 0.16, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)
	_canvas = Control.new()
	_canvas.size = Vector2(MINI, MINI)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_mini)
	frame.add_child(_canvas)

	_zone_lbl = Label.new()
	_zone_lbl.position = Vector2(14, 84 + MINI + 2)
	_zone_lbl.add_theme_font_size_override("font_size", 13)
	_zone_lbl.add_theme_constant_override("outline_size", 5)
	_zone_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_zone_lbl.add_theme_color_override("font_color", Color(0.8, 0.84, 0.9))
	_zone_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_zone_lbl)

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
		var letter := ""
		var col := Color.WHITE
		var path: String = (n3.get_script() as Script).resource_path if n3.get_script() else ""
		if n3 is WallStation:
			match (n3 as WallStation).station_type:
				"ammo_box":
					letter = "A"
					col = Color(1.0, 0.8, 0.25)
				"forge":
					letter = "U"
					col = Color(1.0, 0.5, 0.2)
				_:
					letter = "W"
					col = Color(0.4, 0.85, 1.0)
		elif path.ends_with("augment_furnace.gd"):
			letter = "F"
			col = Color(1.0, 0.55, 0.2)
		elif path.ends_with("supply_depot.gd"):
			letter = "$"
			col = Color(0.5, 1.0, 0.55)
		elif path.ends_with("second_wind_station.gd"):
			letter = "+"
			col = Color(0.4, 1.0, 0.6)
		elif path.ends_with("mystery_crate.gd"):
			letter = "?"
			col = Color(0.8, 0.55, 1.0)
		elif path.ends_with("power_generator.gd"):
			letter = "G"
			col = Color(1.0, 0.95, 0.4)
		elif path.ends_with("exfil_radio.gd"):
			letter = "R"
			col = Color(0.6, 0.95, 1.0)
		elif path.ends_with("zone_door.gd"):
			letter = "D"
			col = Color(1.0, 0.4, 0.3)
		if letter != "":
			_stations.append({"pos": n3.global_position, "letter": letter, "color": col, "node": n3})


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
	_zone_lbl.text = "%s   %s MAP" % [arena.zone_names.get(zid, "OUTSIDE"), GameState.key_label("map")]


# ---------------------------------------------------------------------------
# Things worth a marker: [world pos, kind, colour, pinned to the edge when far]
# ---------------------------------------------------------------------------
func _markers() -> Array:
	var out: Array = []
	for p in get_tree().get_nodes_in_group("net_players"):
		if p == player or not is_instance_valid(p) or p.get("is_dead") == true or p.get("extracted") == true:
			continue
		var down: bool = p.get("is_downed") == true
		var col: Color = Color(1.0, 0.25, 0.2) if down else (p.get("color") if p.get("color") != null else Color(0.5, 0.9, 1.0))
		out.append([(p as Node3D).global_position, "down" if down else "mate", col, down])
	for c in get_tree().get_nodes_in_group("commanders"):
		if is_instance_valid(c) and not c.is_dead:
			out.append([(c as Node3D).global_position, "commander", ZombieEnemy.TIER_COLORS[c.tier], true])
	if wave_mgr and is_instance_valid(wave_mgr.active_boss) and not wave_mgr.active_boss.is_dead:
		out.append([wave_mgr.active_boss.global_position, "boss", Color(1.0, 0.2, 0.15), true])
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
	match kind:
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


func _draw_station(cv: Control, at: Vector2, st: Dictionary, s: float) -> void:
	var node: Node = st["node"]
	if not is_instance_valid(node):
		return
	if st["letter"] == "D" and node.get("_opened") == true:
		return
	var col: Color = st["color"]
	cv.draw_rect(Rect2(at - Vector2(5, 5) * s, Vector2(10, 10) * s), Color(0.02, 0.02, 0.03, 0.85))
	cv.draw_rect(Rect2(at - Vector2(5, 5) * s, Vector2(10, 10) * s), col, false, 1.0)
	cv.draw_string(_font, at + Vector2(-3.4, 3.6) * s, String(st["letter"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(9 * s), col)


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
	var vp := _big_canvas.size
	var span := MAP_MAX - MAP_MIN
	var scale_px := minf((vp.x * 0.62) / span.x, (vp.y * 0.78) / span.y)
	var size_px := span * scale_px
	var top_left := (vp - size_px) * 0.5
	var to_map := func(w: Vector2) -> Vector2:
		return top_left + (w - MAP_MIN) * scale_px
	var frame := Rect2(top_left - Vector2(18, 44), size_px + Vector2(36, 96))
	_big_canvas.draw_rect(frame, Color(0.02, 0.03, 0.045, 0.9))
	_big_canvas.draw_rect(frame, Color(0.75, 0.2, 0.16, 0.9), false, 2.0)
	_big_canvas.draw_string(_font, frame.position + Vector2(16, 28), "OUTPOST NACHT-7  —  TACTICAL MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.95, 0.98))
	_big_canvas.draw_string(_font, frame.position + Vector2(frame.size.x - 150, 28), "%s TO CLOSE" % GameState.key_label("map"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.72, 0.78))
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
	var legend := "A AMMO   W WEAPON   F FURNACE   $ SUPPLY DEPOT   + SECOND WIND   ? MYSTERY CRATE   G GENERATOR   U WEAPON FORGE   R RADIO   D LOCKED DOOR      ◆ COMMANDER   ● BOSS   ✦ RELIC"
	_big_canvas.draw_string(_font, Vector2(frame.position.x + 16, frame.end.y - 16), legend, HORIZONTAL_ALIGNMENT_LEFT, frame.size.x - 32, 12, Color(0.75, 0.78, 0.84))
