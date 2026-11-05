extends Control
# Hand-scrawled blood-red round counter: tally strokes for rounds 1-5 (the
# fifth slashes across the other four), then a big chalky number. The newest
# mark draws itself in when a round starts.

var round_num: int = 1
var reveal: float = 1.0
var _font: Font


func _ready() -> void:
	custom_minimum_size = Vector2(150, 92)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func set_round(n: int) -> void:
	round_num = n
	reveal = 0.0
	var tw := create_tween()
	tw.tween_property(self, "reveal", 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(_v: float): queue_redraw(), 0.0, 1.0, 0.55)


func _stroke(a: Vector2, b: Vector2, stroke_seed: int, amount: float) -> void:
	# A wobbly, uneven brush stroke built from several jittered passes
	var rng := RandomNumberGenerator.new()
	rng.seed = stroke_seed
	var end := a.lerp(b, clampf(amount, 0.0, 1.0))
	if amount <= 0.0:
		return
	var dark := Color(0.32, 0.02, 0.02, 0.95)
	var core := Color(0.78, 0.07, 0.05, 1.0)
	for pass_i in range(3):
		var pts := PackedVector2Array()
		var segs := 7
		for i in range(segs + 1):
			var f := float(i) / float(segs)
			var p := a.lerp(end, f)
			var n := (end - a).orthogonal().normalized()
			p += n * rng.randf_range(-1.6, 1.6) * (1.0 + float(pass_i) * 0.3)
			pts.append(p)
		var w := 9.0 if pass_i == 0 else (6.0 if pass_i == 1 else 3.0)
		var col := dark if pass_i == 0 else core.lerp(Color(0.95, 0.2, 0.12), float(pass_i - 1) * 0.6)
		draw_polyline(pts, col, w, true)
	# Drips and spatter along the stroke
	for i in range(4):
		var f2 := rng.randf()
		var p2 := a.lerp(end, f2) + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-3.0, 3.0))
		draw_circle(p2, rng.randf_range(0.8, 2.2), Color(0.6, 0.04, 0.03, 0.8))
	if amount >= 1.0 and rng.randf() < 0.6:
		var drip_x := end.x + rng.randf_range(-2.0, 2.0)
		draw_line(Vector2(drip_x, end.y), Vector2(drip_x, end.y + rng.randf_range(6.0, 14.0)), Color(0.55, 0.03, 0.02, 0.9), 2.5, true)


func _draw() -> void:
	if round_num <= 5:
		var top := 6.0
		var bottom := 80.0
		var verticals := mini(round_num, 4)
		for i in range(verticals):
			var x := 14.0 + float(i) * 24.0
			var amt := 1.0
			if i == round_num - 1:
				amt = reveal
			_stroke(Vector2(x + 3.0, top + float(i % 2) * 3.0), Vector2(x - 2.0, bottom - float(i % 3) * 2.0), 1000 + i * 77, amt)
		if round_num == 5:
			_stroke(Vector2(0.0, bottom - 12.0), Vector2(98.0, top + 16.0), 5555, reveal)
	else:
		var txt := str(round_num)
		var fs := 74
		var pos := Vector2(4.0, 76.0)
		# Shadowed, smeared numerals
		draw_string_outline(_font, pos + Vector2(2, 3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color(0.15, 0.0, 0.0, 0.85))
		draw_string(_font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.4, 0.02, 0.02, 0.9))
		draw_string(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.82, 0.08, 0.06).lerp(Color(1.0, 0.85, 0.8), 1.0 - reveal))
