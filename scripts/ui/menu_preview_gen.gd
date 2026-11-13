class_name MenuPreviewGen
extends RefCounted

# Procedural illustrated banners (Maps, PvE Modes), Weapon Silhouettes,
# PBR Camo Swatch Thumbnails, and the Interactive 3D Tactical Map Diorama
# for the redesigned Main Menu, Gunsmith Armory, and Multiplayer Lobby.

static var _map_cache: Dictionary = {}
static var _mode_cache: Dictionary = {}
static var _camo_cache: Dictionary = {}
static var _wep_cache: Dictionary = {}
static var _map_mats: Dictionary = {}


# ---------------------------------------------------------------------------
# FAST PIXEL RASTER HELPERS
# ---------------------------------------------------------------------------
static func _fill_grad(img: Image, top_c: Color, mid_c: Color, bot_c: Color, mid_y: float = 0.56) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		var t := float(y) / maxf(1.0, float(h - 1))
		var c: Color
		if t < mid_y:
			c = top_c.lerp(mid_c, t / maxf(0.01, mid_y))
		else:
			c = mid_c.lerp(bot_c, (t - mid_y) / maxf(0.01, 1.0 - mid_y))
		for x in range(w):
			img.set_pixel(x, y, c)


static func _blend_px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 0.995:
		img.set_pixel(x, y, c)
		return
	var dst := img.get_pixel(x, y)
	img.set_pixel(x, y, dst.lerp(Color(c.r, c.g, c.b, 1.0), c.a))


static func _fill_rect(img: Image, x0: int, y0: int, rw: int, rh: int, c: Color) -> void:
	var x1 := mini(img.get_width(), x0 + rw)
	var y1 := mini(img.get_height(), y0 + rh)
	var sx := maxi(0, x0)
	var sy := maxi(0, y0)
	for y in range(sy, y1):
		for x in range(sx, x1):
			_blend_px(img, x, y, c)


static func _fill_disc(img: Image, cx: float, cy: float, rad: float, c: Color, soft: bool = false) -> void:
	var x0 := maxi(0, int(floor(cx - rad - 1.0)))
	var x1 := mini(img.get_width() - 1, int(ceil(cx + rad + 1.0)))
	var y0 := maxi(0, int(floor(cy - rad - 1.0)))
	var y1 := mini(img.get_height() - 1, int(ceil(cy + rad + 1.0)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(float(x) - cx, float(y) - cy).length()
			if d <= rad:
				var a := c.a * ((1.0 - d / maxf(0.01, rad)) if soft else clampf((rad - d) * 1.4, 0.0, 1.0))
				_blend_px(img, x, y, Color(c.r, c.g, c.b, a))


static func _draw_line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color, thick: int = 1) -> void:
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var steps := maxi(1, maxi(dx, dy))
	var half := thick / 2
	for s in range(steps + 1):
		var t := float(s) / float(steps)
		var px := int(roundf(lerpf(float(x0), float(x1), t)))
		var py := int(roundf(lerpf(float(y0), float(y1), t)))
		for oy in range(-half, half + 1):
			for ox in range(-half, half + 1):
				_blend_px(img, px + ox, py + oy, c)


static func _scanlines_and_frame(img: Image, accent: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(0, h, 3):
		for x in range(w):
			var d := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(d.r * 0.90, d.g * 0.90, d.b * 0.92, d.a))
	# Tactical grid hairlines
	for gx in range(32, w, 44):
		_fill_rect(img, gx, 0, 1, h, Color(accent.r, accent.g, accent.b, 0.08))
	for gy in range(24, h, 32):
		_fill_rect(img, 0, gy, w, 1, Color(accent.r, accent.g, accent.b, 0.08))
	# Bottom gradient fade + corner brackets
	_fill_rect(img, 0, h - 18, w, 18, Color(0.02, 0.03, 0.05, 0.45))
	_fill_rect(img, 0, 0, 14, 2, accent)
	_fill_rect(img, 0, 0, 2, 14, accent)
	_fill_rect(img, w - 14, h - 2, 14, 2, accent)
	_fill_rect(img, w - 2, h - 14, 2, 14, accent)


# ---------------------------------------------------------------------------
# 1. ILLUSTRATED MAP BANNERS (256x108)
# ---------------------------------------------------------------------------
static func map_banner(map_id: String) -> ImageTexture:
	if _map_cache.has(map_id):
		return _map_cache[map_id] as ImageTexture
	const W := 240
	const H := 102
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var accent := Color(0.95, 0.42, 0.28)

	match map_id:
		"nacht":
			accent = Color(0.95, 0.42, 0.28)
			_fill_grad(img, Color(0.05, 0.07, 0.14), Color(0.22, 0.11, 0.14), Color(0.06, 0.05, 0.07), 0.62)
			_fill_disc(img, 184, 30, 34, Color(0.98, 0.36, 0.22, 0.22), true)
			_fill_disc(img, 184, 26, 9, Color(0.92, 0.86, 0.78, 0.90))
			# Horizon bunkers & town skyline
			_fill_rect(img, 0, 68, W, 34, Color(0.05, 0.06, 0.08))
			_fill_rect(img, 18, 46, 56, 26, Color(0.11, 0.12, 0.15)) # Depot
			_fill_rect(img, 86, 52, 42, 20, Color(0.09, 0.10, 0.13)) # Bunker
			_fill_rect(img, 148, 34, 34, 38, Color(0.10, 0.09, 0.12)) # Church
			# Church steeple + beacon tower
			for s in range(18):
				_fill_rect(img, 165 - s / 2, 16 + s, maxi(2, s), 1, Color(0.10, 0.09, 0.12))
			_draw_line(img, 210, 12, 202, 68, Color(0.16, 0.18, 0.22), 2)
			_draw_line(img, 210, 12, 218, 68, Color(0.16, 0.18, 0.22), 2)
			_fill_disc(img, 210, 11, 3.2, Color(1.0, 0.25, 0.18, 0.95))
			# Glowing fire barrels
			_fill_disc(img, 76, 68, 12, Color(1.0, 0.45, 0.14, 0.40), true)
			_fill_disc(img, 136, 70, 10, Color(1.0, 0.40, 0.14, 0.35), true)
			_draw_line(img, 0, 74, W, 74, Color(accent.r, accent.g, accent.b, 0.45), 1)
		"dockyard":
			accent = Color(0.28, 0.78, 1.00)
			_fill_grad(img, Color(0.04, 0.14, 0.24), Color(0.14, 0.40, 0.56), Color(0.05, 0.10, 0.18), 0.58)
			_fill_disc(img, 62, 56, 46, Color(0.98, 0.62, 0.26, 0.32), true)
			# Gantry Cranes
			for cx in [52, 168]:
				_fill_rect(img, cx, 14, 4, 54, Color(0.84, 0.42, 0.18))
				_fill_rect(img, cx + 22, 20, 4, 48, Color(0.76, 0.38, 0.16))
				_fill_rect(img, cx - 18, 18, 58, 4, Color(0.90, 0.48, 0.22))
				_draw_line(img, cx + 2, 14, cx - 14, 22, Color(0.95, 0.65, 0.30), 1)
				_draw_line(img, cx + 2, 14, cx + 38, 22, Color(0.95, 0.65, 0.30), 1)
			# Shipping Containers
			_fill_rect(img, 0, 64, W, 38, Color(0.06, 0.10, 0.16))
			_fill_rect(img, 20, 48, 36, 16, Color(0.76, 0.20, 0.18))
			_fill_rect(img, 28, 36, 30, 12, Color(0.18, 0.48, 0.76))
			_fill_rect(img, 96, 50, 40, 14, Color(0.16, 0.50, 0.36))
			_fill_rect(img, 142, 46, 34, 18, Color(0.72, 0.54, 0.16))
			# Coastal water gleam
			_fill_rect(img, 0, 74, W, 28, Color(0.04, 0.16, 0.28, 0.85))
			for wx in range(10, W - 20, 26):
				_fill_rect(img, wx, 82 + (wx % 7), 16, 2, Color(0.45, 0.85, 1.0, 0.38))
		"black_site":
			accent = Color(0.48, 0.94, 1.00)
			_fill_grad(img, Color(0.03, 0.08, 0.16), Color(0.10, 0.26, 0.38), Color(0.55, 0.68, 0.78), 0.64)
			# Aurora ribbons
			for ax in range(0, W, 3):
				var ay := 16 + int(sin(float(ax) * 0.045) * 6.0)
				_fill_rect(img, ax, ay, 3, 8, Color(0.28, 0.95, 0.76, 0.24))
				_fill_rect(img, ax, ay + 6, 3, 5, Color(0.35, 0.82, 1.0, 0.22))
			# Arctic mountains
			for mx in range(0, W):
				var mh := 46 + int(absf(sin(float(mx) * 0.032) * 18.0 + cos(float(mx) * 0.07) * 6.0))
				_fill_rect(img, mx, mh, 1, 70 - mh, Color(0.22, 0.32, 0.42))
			# Radar dome & Cryo Silo
			_fill_disc(img, 54, 58, 16, Color(0.84, 0.92, 0.98))
			_fill_rect(img, 36, 58, 36, 12, Color(0.20, 0.28, 0.36))
			_fill_rect(img, 108, 44, 52, 26, Color(0.15, 0.22, 0.30))
			_fill_disc(img, 134, 62, 20, Color(0.35, 0.92, 1.0, 0.42), true)
			_fill_rect(img, 182, 48, 24, 22, Color(0.24, 0.34, 0.44))
			_fill_rect(img, 0, 70, W, 32, Color(0.72, 0.84, 0.94, 0.92))
		"quarry":
			accent = Color(1.00, 0.68, 0.22)
			_fill_grad(img, Color(0.18, 0.14, 0.24), Color(0.84, 0.44, 0.18), Color(0.42, 0.24, 0.12), 0.62)
			_fill_disc(img, 148, 46, 32, Color(1.0, 0.82, 0.32, 0.36), true)
			_fill_disc(img, 148, 46, 12, Color(1.0, 0.92, 0.60, 0.85))
			# Canyon mesas
			_fill_rect(img, 0, 52, 74, 22, Color(0.30, 0.16, 0.10))
			_fill_rect(img, 174, 48, 66, 26, Color(0.26, 0.14, 0.09))
			# Cracking towers & Oil Derrick
			_fill_rect(img, 88, 24, 14, 48, Color(0.18, 0.14, 0.14))
			_fill_rect(img, 108, 30, 12, 42, Color(0.22, 0.16, 0.14))
			_draw_line(img, 148, 18, 136, 72, Color(0.16, 0.12, 0.12), 2)
			_draw_line(img, 148, 18, 160, 72, Color(0.16, 0.12, 0.12), 2)
			_fill_disc(img, 95, 20, 9, Color(1.0, 0.56, 0.14, 0.72), true)
			_fill_disc(img, 95, 21, 4, Color(1.0, 0.92, 0.55, 0.95))
			_fill_rect(img, 0, 72, W, 30, Color(0.32, 0.19, 0.10))
		_: # "random"
			accent = Color(0.45, 0.90, 1.0)
			var ids := ["nacht", "dockyard", "black_site", "quarry"]
			var slice_w := W / 4
			for i in range(4):
				var sub := map_banner(ids[i]).get_image()
				for y in range(H):
					for x in range(i * slice_w, mini(W, (i + 1) * slice_w)):
						img.set_pixel(x, y, sub.get_pixel(x, y))
				if i > 0:
					_fill_rect(img, i * slice_w, 0, 2, H, Color(0.08, 0.10, 0.14, 0.85))
			_fill_disc(img, W * 0.5, H * 0.5, 16, Color(0.05, 0.08, 0.12, 0.72))

	_scanlines_and_frame(img, accent)
	var tex := ImageTexture.create_from_image(img)
	_map_cache[map_id] = tex
	return tex


# ---------------------------------------------------------------------------
# 2. ILLUSTRATED MODE BANNERS (240x58)
# ---------------------------------------------------------------------------
static func mode_banner(mode_id: String) -> ImageTexture:
	if _mode_cache.has(mode_id):
		return _mode_cache[mode_id] as ImageTexture
	const W := 240
	const H := 54
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var accent := Color(0.95, 0.30, 0.24)
	match mode_id:
		"casual":
			accent = Color(0.95, 0.30, 0.24)
			_fill_grad(img, Color(0.08, 0.09, 0.16), Color(0.24, 0.14, 0.18), Color(0.06, 0.07, 0.11), 0.65)
			_fill_disc(img, 194, 24, 24, Color(0.70, 0.80, 0.96, 0.28), true)
			_fill_rect(img, 14, 34, 48, 20, Color(0.11, 0.10, 0.13))
			_fill_rect(img, 76, 30, 62, 24, Color(0.10, 0.09, 0.12))
			_fill_rect(img, 152, 24, 28, 30, Color(0.11, 0.10, 0.13))
			# Warm streetlamp pools showing lit night outpost
			_fill_disc(img, 42, 34, 10, Color(1.0, 0.78, 0.42, 0.42), true)
			_fill_disc(img, 118, 30, 12, Color(1.0, 0.78, 0.42, 0.45), true)
			# Exfil chopper silhouette
			_fill_rect(img, 174, 15, 34, 2, Color(0.75, 0.80, 0.88, 0.70))
			_fill_rect(img, 184, 18, 16, 7, Color(0.14, 0.16, 0.20))
		"infinite":
			accent = Color(0.28, 0.82, 1.00)
			_fill_grad(img, Color(0.04, 0.07, 0.16), Color(0.10, 0.22, 0.38), Color(0.04, 0.08, 0.14), 0.62)
			_fill_disc(img, 190, 26, 24, Color(0.26, 0.78, 1.0, 0.26), true)
			for x in range(18, W - 18, 28):
				_fill_rect(img, x, 34 + (x % 9), 18, 20, Color(0.07, 0.12, 0.18))
			_draw_line(img, 24, 42, 216, 42, Color(0.28, 0.82, 1.0, 0.35), 1)
		"horror":
			accent = Color(0.92, 0.18, 0.22)
			_fill_grad(img, Color(0.02, 0.02, 0.03), Color(0.14, 0.03, 0.05), Color(0.02, 0.02, 0.03), 0.68)
			_fill_disc(img, 186, 22, 26, Color(0.88, 0.12, 0.16, 0.34), true)
			_fill_disc(img, 186, 22, 9, Color(0.03, 0.02, 0.03))
			_fill_rect(img, 14, 34, 40, 20, Color(0.05, 0.04, 0.05))
			_fill_rect(img, 84, 28, 34, 26, Color(0.04, 0.03, 0.05))
			# Crow wing silhouettes over blood moon
			for cx in [148, 174, 208]:
				var cy := 18 if cx == 174 else 24
				_draw_line(img, cx - 8, cy + 3, cx, cy, Color(0.95, 0.25, 0.25, 0.9), 2)
				_draw_line(img, cx, cy, cx + 8, cy + 3, Color(0.95, 0.25, 0.25, 0.9), 2)
		"overdrive":
			accent = Color(1.00, 0.78, 0.22)
			_fill_grad(img, Color(0.14, 0.24, 0.44), Color(0.86, 0.56, 0.20), Color(0.28, 0.18, 0.08), 0.66)
			_fill_disc(img, 188, 22, 28, Color(1.0, 0.86, 0.34, 0.45), true)
			_fill_disc(img, 188, 22, 9, Color(1.0, 0.96, 0.76, 0.90))
			_fill_rect(img, 0, 38, W, 16, Color(0.16, 0.12, 0.08))
			_draw_line(img, 18, 36, 42, 22, Color(1.0, 0.85, 0.30, 0.75), 2)
			_draw_line(img, 42, 22, 34, 34, Color(1.0, 0.85, 0.30, 0.75), 2)
			_draw_line(img, 34, 34, 58, 18, Color(1.0, 0.92, 0.45, 0.85), 2)
	_scanlines_and_frame(img, accent)
	var tex := ImageTexture.create_from_image(img)
	_mode_cache[mode_id] = tex
	return tex


# ---------------------------------------------------------------------------
# 3. WEAPON CAMO / TEXTURE SWATCHES (72x36)
# ---------------------------------------------------------------------------
static func camo_swatch(camo_id: String) -> ImageTexture:
	if _camo_cache.has(camo_id):
		return _camo_cache[camo_id] as ImageTexture
	const W := 72
	const H := 36
	var cd: Dictionary = WeaponCatalog.WEAPON_CAMOS.get(camo_id, WeaponCatalog.WEAPON_CAMOS["factory"])
	var ca: Color = cd.get("swatch_a", Color(0.3, 0.34, 0.4))
	var cb: Color = cd.get("swatch_b", Color(0.12, 0.14, 0.18))
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in range(H):
		for x in range(W):
			var col := cb
			match camo_id:
				"factory":
					var g := sin(float(x * 2 + y * 2) * 0.25) * 0.12 + 0.5
					col = cb.lerp(ca, clampf(g, 0.0, 1.0))
				"panzer":
					var band := clampf(1.0 - absf(float(x - y * 1.4 - 16)) / 18.0, 0.0, 1.0)
					col = cb.lerp(ca, band * 0.85 + 0.15)
				"woodland", "desert":
					var n := sin(float(x) * 0.14 + cos(float(y) * 0.18) * 2.1) + cos(float(y) * 0.16 - float(x) * 0.08)
					col = ca if n > 0.25 else (ca.lerp(cb, 0.55) if n > -0.45 else cb)
				"arctic":
					var cx_q := int(x / 6) * 13 + int(y / 6) * 29
					var pat := cx_q % 7
					col = ca if pat < 3 else (ca.lerp(cb, 0.5) if pat < 5 else cb)
				"crimson":
					var sx := absi((x + (y / 4) * 4) % 8 - 4) + absi(y % 8 - 4)
					col = ca if sx < 4 else cb
				"survivor":
					var rust := sin(float(x) * 0.23) * cos(float(y) * 0.29) + sin(float(x + y) * 0.11)
					col = ca if rust > 0.15 else cb
				"gilded":
					var d := absf(float(x) - float(y) * 1.5 - 12.0)
					col = ca if d < 6.0 else (ca.darkened(0.55) if d < 10.0 else cb)
			img.set_pixel(x, y, col)
	_fill_rect(img, 0, 0, W, 1, Color(1, 1, 1, 0.22))
	_fill_rect(img, 0, H - 1, W, 1, Color(0, 0, 0, 0.45))
	var tex := ImageTexture.create_from_image(img)
	_camo_cache[camo_id] = tex
	return tex


# ---------------------------------------------------------------------------
# 4. PROCEDURAL WEAPON SILHOUETTES (136x44)
# ---------------------------------------------------------------------------
static func weapon_silhouette(w_id: String, wc: Dictionary, accent: Color) -> ImageTexture:
	var key := "%s_%s" % [w_id, accent.to_html(false)]
	if _wep_cache.has(key):
		return _wep_cache[key] as ImageTexture
	const W := 136
	const H := 44
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var cls := String(wc.get("class", "rifle"))
	var st: Dictionary = wc.get("style", {})
	var metal := Color(0.86, 0.90, 0.96, 0.95)
	var trim := accent.lerp(Color.WHITE, 0.35)
	trim.a = 0.92
	var dark := Color(0.45, 0.50, 0.58, 0.90)

	# Blueprint backdrop grid
	for gx in range(16, W, 24):
		_fill_rect(img, gx, 4, 1, H - 8, Color(accent.r, accent.g, accent.b, 0.12))
	_fill_rect(img, 6, H / 2, W - 12, 1, Color(accent.r, accent.g, accent.b, 0.14))

	if bool(st.get("rpg_tube", false)):
		# RPG-7 Tube + Venturi + Cone Warhead
		_fill_rect(img, 30, 17, 68, 7, trim)
		_fill_rect(img, 14, 15, 16, 11, dark)
		_fill_rect(img, 54, 16, 22, 9, Color(0.68, 0.44, 0.24, 0.95))
		_fill_rect(img, 56, 24, 6, 12, dark)
		_fill_rect(img, 84, 24, 6, 10, dark)
		_fill_rect(img, 98, 18, 12, 5, metal)
		for f in range(8):
			_fill_rect(img, 108 + f * 2, 15 + f / 2, 3, maxi(2, 11 - f), metal)
	elif bool(st.get("gl_barrel", false)):
		# M79 / M32 Launcher
		_fill_rect(img, 18, 22, 22, 10, dark)
		_fill_rect(img, 40, 15, 38, 13, metal)
		_fill_rect(img, 78, 16, 34, 8, trim)
		_fill_rect(img, 46, 28, 7, 11, dark)
		if bool(st.get("drum_mag", false)):
			_fill_disc(img, 60, 22, 9, trim)
	elif bool(st.get("xbow_limbs", false)):
		# Tactical Crossbow
		_fill_rect(img, 16, 19, 26, 7, dark)
		_fill_rect(img, 42, 16, 56, 6, metal)
		_fill_rect(img, 92, 8, 5, 24, trim)
		_draw_line(img, 64, 20, 94, 10, Color(0.85, 0.92, 1.0, 0.75), 1)
		_draw_line(img, 64, 20, 94, 30, Color(0.85, 0.92, 1.0, 0.75), 1)
		_fill_rect(img, 52, 22, 7, 13, dark)
	elif cls == "pistol":
		# Pistol / Revolver
		_fill_rect(img, 42, 12, 46, 8, metal) # Slide
		_fill_rect(img, 46, 20, 38, 5, trim) # Frame
		_fill_rect(img, 44, 24, 11, 14, dark) # Grip
		if w_id == "revolver":
			_fill_rect(img, 60, 14, 14, 10, trim) # Cylinder
			_fill_rect(img, 74, 13, 24, 5, metal)
		if bool(st.get("suppressor", false)):
			_fill_rect(img, 88, 13, 22, 6, dark)
	elif cls == "smg":
		# Compact SMG + Foregrip/Extended Mag
		_fill_rect(img, 24, 18, 18, 6, dark)
		_fill_rect(img, 42, 15, 42, 10, metal)
		_fill_rect(img, 84, 17, 22, 5, trim)
		_fill_rect(img, 46, 25, 8, 13, dark)
		_fill_rect(img, 66, 24, 7, 16, trim)
		if bool(st.get("suppressor", false)):
			_fill_rect(img, 106, 16, 18, 7, dark)
	elif cls == "shotgun":
		# Pump / Semi Shotgun
		_fill_rect(img, 14, 20, 26, 9, dark)
		_fill_rect(img, 40, 15, 36, 9, metal)
		_fill_rect(img, 76, 15, 44, 4, metal)
		_fill_rect(img, 76, 20, 36, 4, trim)
		_fill_rect(img, 80, 21, 20, 6, Color(0.62, 0.40, 0.22, 0.92))
	elif cls == "lmg":
		# Heavy LMG / Minigun
		_fill_rect(img, 14, 18, 22, 10, dark)
		_fill_rect(img, 36, 14, 48, 13, metal)
		_fill_rect(img, 84, 16, 40, 6, trim)
		_fill_rect(img, 54, 27, 22, 12, Color(0.45, 0.52, 0.28, 0.95)) # Ammo box
		_fill_rect(img, 40, 27, 7, 11, dark)
	elif cls == "sniper":
		# Long Bolt/Anti-Materiel Rifle + Scope
		_fill_rect(img, 10, 19, 26, 9, dark)
		_fill_rect(img, 36, 17, 40, 8, metal)
		_fill_rect(img, 76, 18, 50, 4, metal)
		_fill_rect(img, 42, 10, 34, 6, trim) # Scope
		_fill_rect(img, 46, 25, 7, 12, dark)
		_fill_rect(img, 62, 25, 11, 9, trim)
		if bool(st.get("suppressor", false)):
			_fill_rect(img, 114, 17, 16, 6, dark)
	elif cls == "wonder":
		# Sci-Fi Arc Cannon
		_fill_rect(img, 20, 18, 22, 9, dark)
		_fill_rect(img, 42, 12, 48, 16, metal)
		_fill_rect(img, 90, 15, 30, 10, trim)
		_fill_disc(img, 68, 19, 6, accent)
		_fill_rect(img, 48, 28, 8, 12, dark)
	else:
		# Assault Rifle / Battle Rifle
		_fill_rect(img, 14, 18, 24, 9, dark) # Stock
		_fill_rect(img, 38, 15, 42, 10, metal) # Receiver + Handguard
		_fill_rect(img, 80, 17, 34, 4, metal) # Barrel
		_fill_rect(img, 44, 25, 7, 12, dark) # Grip
		_fill_rect(img, 62, 25, 8, 14, trim) # Curved mag
		if String(st.get("optic", "")) != "":
			_fill_rect(img, 44, 10, 18, 5, trim)
		if bool(st.get("suppressor", false)):
			_fill_rect(img, 106, 16, 18, 6, dark)

	var tex := ImageTexture.create_from_image(img)
	_wep_cache[key] = tex
	return tex


# ---------------------------------------------------------------------------
# 5. INTERACTIVE 3D ROTATABLE TACTICAL MAP DIORAMA
# ---------------------------------------------------------------------------
static func _holo_mat(prefix: String, tint: Color, rough: float = 0.72, met: float = 0.15) -> StandardMaterial3D:
	var key := "holo_%s_%s_%.2f_%.2f" % [prefix, tint.to_html(true), rough, met]
	if _map_mats.has(key):
		return _map_mats[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = rough
	mat.metallic = met
	var ap := "res://assets/textures/%s_albedo.png" % prefix
	var np := "res://assets/textures/%s_normal.png" % prefix
	if ResourceLoader.exists(ap):
		mat.albedo_texture = load(ap)
	if ResourceLoader.exists(np):
		mat.normal_enabled = true
		mat.normal_scale = 0.85
		mat.normal_texture = load(np)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_scale = Vector3(1.6, 1.6, 1.6)
	_map_mats[key] = mat
	return mat


static func _holo_emissive(col: Color, energy: float = 1.9, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "holoem_%s_%.2f_%.2f" % [col.to_html(true), energy, alpha]
	if _map_mats.has(key):
		return _map_mats[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r, col.g, col.b, alpha)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	if alpha < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_map_mats[key] = mat
	return mat


static func _hbox(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation.y = rot_y
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _hcyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 24
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func build_map_diorama(root: Node3D, map_id: String, pvp_mode: String, team_preset: int) -> void:
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()

	var resolved_id := map_id if GameState.PVP_MAPS.has(map_id) else "dockyard"
	var mp: Dictionary = GameState.PVP_MAPS.get(resolved_id, GameState.PVP_MAPS["nacht"])
	var accent: Color = mp.get("accent", Color(0.28, 0.78, 1.0))

	# Circular Hologram Table Plinth
	var table_mat := _holo_mat("gunmetal", Color(0.16, 0.19, 0.24), 0.35, 0.85)
	_hcyl(root, 1.56, 0.14, Vector3(0.0, -0.10, 0.0), table_mat)
	var ring_m := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 1.50
	tor.outer_radius = 1.55
	tor.rings = 56
	tor.ring_segments = 8
	ring_m.mesh = tor
	ring_m.position = Vector3(0.0, -0.02, 0.0)
	ring_m.material_override = _holo_emissive(accent, 1.6)
	root.add_child(ring_m)

	var conc := _holo_mat("concrete", Color(0.58, 0.62, 0.68), 0.72, 0.1)
	var steel := _holo_mat("panzer_steel", Color(0.45, 0.50, 0.56), 0.38, 0.75)

	# Arena Terrain + Signature 3D Architecture
	match resolved_id:
		"nacht":
			_hbox(root, Vector3(2.35, 0.06, 1.95), Vector3(0, 0.0, 0), _holo_mat("asphalt", Color(0.32, 0.35, 0.40), 0.75, 0.1))
			# Perimeter walls
			_hbox(root, Vector3(2.35, 0.16, 0.07), Vector3(0, 0.10, -0.94), conc)
			_hbox(root, Vector3(2.35, 0.16, 0.07), Vector3(0, 0.10, 0.94), conc)
			# Memorial Obelisk Plaza (center)
			_hcyl(root, 0.24, 0.04, Vector3(0, 0.04, 0), conc)
			_hbox(root, Vector3(0.11, 0.36, 0.11), Vector3(0, 0.21, 0), steel)
			# Gothic Church + Steeple (East)
			_hbox(root, Vector3(0.42, 0.26, 0.52), Vector3(0.76, 0.15, 0.0), _holo_mat("concrete", Color(0.46, 0.42, 0.40)))
			_hbox(root, Vector3(0.16, 0.48, 0.16), Vector3(0.78, 0.26, -0.18), steel)
			# Rail Depot + Freight Car (West)
			_hbox(root, Vector3(0.38, 0.22, 0.54), Vector3(-0.76, 0.13, 0.05), _holo_mat("rusted_metal", Color(0.65, 0.38, 0.24)))
			_hbox(root, Vector3(0.14, 0.14, 0.36), Vector3(-0.48, 0.09, -0.15), _holo_mat("rusted_metal", Color(0.72, 0.30, 0.20)))
			# Warehouse (North) & Hospital (South)
			_hbox(root, Vector3(0.64, 0.22, 0.34), Vector3(-0.05, 0.13, -0.64), conc)
			_hbox(root, Vector3(0.60, 0.20, 0.32), Vector3(0.05, 0.12, 0.64), _holo_mat("concrete", Color(0.74, 0.78, 0.82)))
		"dockyard":
			# Sea channels + Main Concrete Pier Deck
			_hbox(root, Vector3(2.40, 0.03, 2.00), Vector3(0, -0.01, 0), _holo_emissive(Color(0.06, 0.26, 0.46), 0.75))
			_hbox(root, Vector3(2.26, 0.08, 1.56), Vector3(0, 0.02, 0), conc)
			# Coastal Helipad (North)
			_hcyl(root, 0.28, 0.06, Vector3(0.0, 0.08, -0.66), steel)
			_hbox(root, Vector3(0.16, 0.01, 0.04), Vector3(0.0, 0.115, -0.66), _holo_emissive(Color(1.0, 0.78, 0.22), 1.4))
			# Twin Gantry Cranes
			for cx in [-0.46, 0.46]:
				_hbox(root, Vector3(0.07, 0.52, 0.07), Vector3(cx, 0.30, -0.32), _holo_emissive(Color(0.92, 0.46, 0.14), 0.55))
				_hbox(root, Vector3(0.07, 0.52, 0.07), Vector3(cx, 0.30, 0.32), _holo_emissive(Color(0.92, 0.46, 0.14), 0.55))
				_hbox(root, Vector3(0.10, 0.06, 0.88), Vector3(cx, 0.56, 0.0), _holo_emissive(Color(0.96, 0.52, 0.18), 0.65))
			# Stacked 3-lane Shipping Containers
			_hbox(root, Vector3(0.28, 0.14, 0.14), Vector3(-0.32, 0.13, 0.0), _holo_mat("gunmetal", Color(0.84, 0.24, 0.20)))
			_hbox(root, Vector3(0.28, 0.14, 0.14), Vector3(0.32, 0.13, 0.0), _holo_mat("gunmetal", Color(0.20, 0.52, 0.86)))
			_hbox(root, Vector3(0.16, 0.14, 0.32), Vector3(0.0, 0.13, 0.38), _holo_mat("gunmetal", Color(0.22, 0.68, 0.42)))
			_hbox(root, Vector3(0.16, 0.14, 0.30), Vector3(-0.68, 0.13, -0.22), _holo_mat("gunmetal", Color(0.86, 0.62, 0.18)))
			_hbox(root, Vector3(0.16, 0.14, 0.30), Vector3(0.68, 0.13, 0.22), _holo_mat("gunmetal", Color(0.84, 0.24, 0.20)))
		"black_site":
			# Polar snow basin + steel Cryo Lab + Recessed Central Silo
			_hbox(root, Vector3(2.40, 0.05, 2.00), Vector3(0, 0.0, 0), _holo_mat("concrete", Color(0.76, 0.86, 0.96), 0.6, 0.05))
			_hbox(root, Vector3(1.85, 0.04, 1.55), Vector3(0, 0.03, 0), steel)
			# Central Missile Silo Ring + Glowing Core
			_hcyl(root, 0.30, 0.05, Vector3(0, 0.06, 0), _holo_emissive(Color(0.25, 0.90, 1.0), 1.4))
			_hbox(root, Vector3(0.22, 0.26, 0.22), Vector3(0, 0.18, 0), _holo_mat("gunmetal", Color(0.22, 0.28, 0.35)))
			# Radar Dome (North) & Cryo Silos (West)
			var dome := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.22; sp.height = 0.44
			dome.mesh = sp
			dome.position = Vector3(0.0, 0.18, -0.62)
			dome.material_override = _holo_mat("concrete", Color(0.86, 0.92, 0.98))
			root.add_child(dome)
			for cz in [-0.24, 0.24]:
				_hcyl(root, 0.12, 0.34, Vector3(-0.74, 0.20, cz), _holo_mat("concrete", Color(0.60, 0.82, 0.96)))
				_hcyl(root, 0.12, 0.30, Vector3(0.74, 0.18, cz), steel)
		"quarry":
			# Red sandstone desert floor + Canyon Rim Cliffs
			_hbox(root, Vector3(2.40, 0.05, 2.00), Vector3(0, 0.0, 0), _holo_mat("concrete", Color(0.76, 0.50, 0.30), 0.85, 0.04))
			_hbox(root, Vector3(0.32, 0.26, 1.80), Vector3(-1.02, 0.14, 0), _holo_mat("concrete", Color(0.62, 0.34, 0.18)))
			_hbox(root, Vector3(0.32, 0.26, 1.80), Vector3(1.02, 0.14, 0), _holo_mat("concrete", Color(0.62, 0.34, 0.18)))
			# Twin Refinery Cracking Towers + Flare Flame + Oil Derrick
			for rx in [-0.26, 0.26]:
				_hcyl(root, 0.11, 0.54, Vector3(rx, 0.29, -0.18), _holo_mat("rusted_metal", Color(0.55, 0.42, 0.32)))
				_hcyl(root, 0.05, 0.12, Vector3(rx, 0.60, -0.18), _holo_emissive(Color(1.0, 0.52, 0.12), 2.5))
			# Catwalk & Pipelines
			_hbox(root, Vector3(0.95, 0.05, 0.16), Vector3(0.0, 0.22, -0.18), steel)
			_hcyl(root, 0.04, 1.40, Vector3(0.0, 0.08, 0.38), _holo_mat("rusted_metal", Color(0.66, 0.44, 0.26)), Vector3(0, 0, PI * 0.5))
			_hbox(root, Vector3(0.38, 0.20, 0.28), Vector3(-0.56, 0.12, 0.44), steel)
			_hbox(root, Vector3(0.38, 0.20, 0.28), Vector3(0.56, 0.12, 0.44), steel)

	# Team Spawn Beacons for selected Team Preset (2, 4, or 6 teams)
	var team_count := clampi(team_preset, 2, 6)
	var sp_coords := [
		Vector3(-0.88, 0.07, 0.0),
		Vector3(0.88, 0.07, 0.0),
		Vector3(0.0, 0.07, -0.76),
		Vector3(0.0, 0.07, 0.76),
		Vector3(-0.72, 0.07, -0.64),
		Vector3(0.72, 0.07, 0.64),
	]
	for tid in range(team_count):
		var tcol := GameState.pvp_team_color(tid)
		var spos: Vector3 = sp_coords[tid]
		_hcyl(root, 0.11, 0.04, spos, _holo_emissive(tcol, 2.0))
		var lbl := Label3D.new()
		lbl.text = String(GameState.PVP_TEAMS[tid]["code"])
		lbl.pixel_size = 0.0038
		lbl.font_size = 28
		lbl.modulate = tcol.lightened(0.25)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = spos + Vector3(0.0, 0.14, 0.0)
		root.add_child(lbl)

	# Objective Pillars for Domination [A/B/C] or S&D [SITE A / SITE B]
	if pvp_mode == "dom":
		var dom_pts := [["A", Vector3(-0.48, 0.10, -0.10)], ["B", Vector3(0.0, 0.12, 0.0)], ["C", Vector3(0.48, 0.10, 0.10)]]
		for dp in dom_pts:
			var p_pos: Vector3 = dp[1]
			_hcyl(root, 0.028, 0.34, p_pos + Vector3(0, 0.17, 0), _holo_emissive(Color(0.32, 0.92, 1.0), 1.8))
			var fl := Label3D.new()
			fl.text = "FLAG %s" % String(dp[0])
			fl.pixel_size = 0.0035
			fl.font_size = 26
			fl.modulate = Color(0.55, 0.96, 1.0)
			fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			fl.position = p_pos + Vector3(0.0, 0.42, 0.0)
			root.add_child(fl)
	elif pvp_mode == "snd":
		var snd_pts := [["SITE A", Vector3(-0.34, 0.10, -0.34)], ["SITE B", Vector3(0.34, 0.10, 0.34)]]
		for sp in snd_pts:
			var p_pos: Vector3 = sp[1]
			_hbox(root, Vector3(0.16, 0.16, 0.16), p_pos + Vector3(0, 0.08, 0), _holo_emissive(Color(1.0, 0.70, 0.18), 1.8))
			var bl := Label3D.new()
			bl.text = String(sp[0])
			bl.pixel_size = 0.0042
			bl.font_size = 30
			bl.modulate = Color(1.0, 0.84, 0.32)
			bl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			bl.position = p_pos + Vector3(0.0, 0.28, 0.0)
			root.add_child(bl)
