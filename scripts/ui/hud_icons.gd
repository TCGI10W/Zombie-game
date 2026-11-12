class_name HudIcons
extends RefCounted
# Shared visual language for the in-match HUD: a single vector icon sheet
# (assets/ui/hud_icons.svg, 8x7 grid of 24px cells rasterised at 2x) sliced into
# AtlasTextures, plus the panel / bar / keycap / theme builders every HUD surface
# uses so the whole match reads as one coherent tactical kit.

const SHEET := "res://assets/ui/hud_icons.svg"
const CELL := 48.0 # raster pixels per cell (svg authored 24 viewBox @2x)
const COLS := 8

# Night-outbreak palette: gunmetal surfaces, blood red, amber points, cyan info,
# green ready, purple arc / borrowed, warm white text.
const BG := Color(0.045, 0.055, 0.075, 0.86)
const BG_SOLID := Color(0.055, 0.065, 0.09, 0.96)
const EDGE := Color(0.30, 0.36, 0.44, 0.9)
const RED := Color(0.88, 0.14, 0.12)
const AMBER := Color(1.0, 0.78, 0.25)
const CYAN := Color(0.35, 0.85, 1.0)
const GREEN := Color(0.45, 1.0, 0.65)
const PURPLE := Color(0.75, 0.5, 1.0)
const TEXT := Color(0.93, 0.95, 0.98)
const DIM := Color(0.60, 0.66, 0.74)

const INDEX := {
	"skull": 0, "crown": 1, "heart": 2, "shield": 3, "bolt": 4, "bullet": 5, "grenade": 6, "knife": 7,
	"coin": 8, "target": 9, "syringe": 10, "pill": 11, "claw": 12, "beast": 13, "slam": 14, "arc": 15,
	"flame": 16, "box": 17, "mine": 18, "radio": 19, "door": 20, "anvil": 21, "cross": 22, "tag": 23,
	"map": 24, "pause": 25, "play": 26, "restart": 27, "home": 28, "clock": 29, "star": 30, "down": 31,
	"user": 32, "gauge": 33, "reload": 34, "warning": 35, "chopper": 36, "paw": 37, "dumbbell": 38, "boot": 39,
	"swap": 40, "hourglass": 41, "flag": 42, "pistol": 43, "smg": 44, "rifle": 45, "shotgun": 46, "lmg": 47,
	"sniper": 48, "wonder": 49, "crate": 50, "compass": 51, "eye": 52, "hand": 53, "key": 54, "snow": 55,
}

static var _sheet: Texture2D = null
static var _atlas: Dictionary = {}


static func tex(name: String) -> Texture2D:
	if _atlas.has(name):
		return _atlas[name]
	if _sheet == null:
		_sheet = load(SHEET) as Texture2D
	var i: int = INDEX.get(name, 0)
	var a := AtlasTexture.new()
	a.atlas = _sheet
	a.region = Rect2(Vector2(i % COLS, i / COLS) * CELL, Vector2(CELL, CELL))
	_atlas[name] = a
	return a


static func icon(name: String, px: float, col: Color = TEXT) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.size = Vector2(px, px)
	t.modulate = col
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


# A keyboard key rendered as a physical cap: dark face, lit edge, mono letter.
static func keycap(label: String, px: float = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.16, 0.95)
	sb.border_color = Color(0.55, 0.62, 0.72, 0.9)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", int(px))
	l.add_theme_color_override("font_color", TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func panel(bg: Color = BG, border: Color = EDGE, corner: int = 4, bw: int = 1, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.7
	sb.content_margin_bottom = margin * 0.7
	return sb


static func bar(col: Color, corner: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(corner)
	return sb


static func label(text: String, px: int, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Theme for the interactive surfaces (pause options, furnace buttons, scrollbars)
# so sliders / buttons / scrollbars match the HUD instead of default grey.
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = ThemeDB.fallback_font
	var btn := panel(Color(0.10, 0.12, 0.16, 0.95), EDGE, 4, 1, 10)
	var btn_h := panel(Color(0.16, 0.20, 0.26, 0.98), CYAN, 4, 1, 10)
	var btn_p := panel(Color(0.22, 0.10, 0.10, 0.98), RED, 4, 1, 10)
	var btn_d := panel(Color(0.08, 0.09, 0.11, 0.6), Color(0.2, 0.24, 0.3), 4, 1, 10)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_stylebox("disabled", "Button", btn_d)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_font_size("font_size", "Button", 15)
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 14)
	var grab := bar(CYAN, 3)
	var grab_h := bar(Color.WHITE, 3)
	t.set_stylebox("slider", "HSlider", bar(Color(0.14, 0.17, 0.22), 3))
	t.set_stylebox("grabber_area", "HSlider", bar(Color(0.25, 0.55, 0.7), 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", bar(CYAN, 3))
	t.set_icon("grabber", "HSlider", _dot(CYAN))
	t.set_icon("grabber_highlight", "HSlider", _dot(Color.WHITE))
	t.set_icon("grabber_disabled", "HSlider", _dot(DIM))
	var sb_bg := bar(Color(0.10, 0.12, 0.16), 3)
	var sb_thumb := bar(Color(0.45, 0.16, 0.14), 3)
	var sb_thumb_h := bar(RED, 3)
	t.set_stylebox("scroll", "VScrollBar", sb_bg)
	t.set_stylebox("scroll", "HScrollBar", sb_bg)
	t.set_stylebox("grabber", "VScrollBar", sb_thumb)
	t.set_stylebox("grabber", "HScrollBar", sb_thumb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_thumb_h)
	t.set_stylebox("grabber_highlight", "HScrollBar", sb_thumb_h)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_thumb_h)
	t.set_stylebox("grabber_pressed", "HScrollBar", sb_thumb_h)
	t.set_constant("scrollbar_width", "VScrollBar", 8)
	return t


static func _dot(col: Color) -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([col, col])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 14
	gt.height = 14
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	return gt


# --- semantic mappings -------------------------------------------------------
static func stat_icon(id: String) -> String:
	match id:
		"strength": return "dumbbell"
		"speed": return "boot"
		"endurance": return "shield"
		"stamina": return "bolt"
		"dexterity": return "swap"
		"reflexes": return "target"
		"vitality": return "heart"
		"fortune": return "coin"
	return "star"


static func weapon_icon(wclass: String) -> String:
	if INDEX.has(wclass):
		return wclass
	return "rifle"


static func skill_icon(char_id: String, slot: String, monster: bool = false) -> String:
	match char_id:
		"ravager":
			if monster:
				return "claw" if slot == "q" else "slam"
			return "claw" if slot == "q" else "beast"
		"alchemist":
			return "syringe" if slot == "q" else "pill"
		"warden":
			return "bolt" if slot == "q" else "arc"
	return "star"


static func borrowed_icon(id: String) -> String:
	match id:
		"feral_slash": return "claw"
		"pain_dart": return "syringe"
		"stim": return "pill"
		"tesla": return "bolt"
		"overcharge": return "arc"
	return "star"


static func powerup_icon(id: String) -> String:
	match id:
		"insta_kill": return "skull"
		"double_points": return "coin"
		"fire_sale": return "tag"
		"adrenaline": return "bolt"
	return "star"