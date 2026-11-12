# The crew's truck, the salvage beacon and the exit marker (METRO 9 M9): their textures.
# Every surface starts from the project's own baked CC0 photo scans (assets/models/slip7/_src/scans,
# ambientCG; M4b's rubber and vinyl tiles), graded and dressed with SLIP 7's helpers, which are exec'd
# from _make_slip7_textures.py (read only). Drawn graphics (lenses, gauges, stencils, chevrons, the
# treadplate's lugs over a Metal scan) stay drawn. 256 px a metre on the builder's metric UVs, nearest
# filtering in Godot. Palette: faded hazard yellow, oily black, rust, dull steel, amber.
# Run `python make_truck_textures.py` from anywhere. Output: ../tex/<name>.png (TruckKit reads there).
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
S7 = os.path.join(ROOT, "assets", "models", "slip7", "_src", "_make_slip7_textures.py")
_g = {"__name__": "truck_textures", "__file__": S7}
exec(open(S7, encoding="utf-8").read(), _g)
scan, grade, lum, relief, tint, fbm, vnoise, col, mix, grime, rust_spots, stencil = (_g[k] for k in (
		"scan", "grade", "lum", "relief", "tint", "fbm", "vnoise", "col", "mix", "grime", "rust_spots", "stencil"))
OUT = os.path.join(HERE, "..", "tex")
os.makedirs(OUT, exist_ok=True)
PROPS_TEX = os.path.join(ROOT, "assets", "models", "metro9", "props", "tex")
AMBER = (214, 150, 30)
HAZARD = (206, 152, 26)


def save(name, img):
	img = np.clip(img, 0, 1)
	mode = "RGBA" if img.shape[2] == 4 else "RGB"
	Image.fromarray((img * 255).astype(np.uint8)).convert(mode).save(os.path.join(OUT, name + ".png"))


def tile(name, S):
	im = Image.open(os.path.join(PROPS_TEX, name + ".png")).convert("RGB")
	if im.size != (S, S):
		im = im.resize((S, S), Image.LANCZOS)
	return np.asarray(im).astype(float) / 255.0


def chips(S, seed, amount):
	"""Paint chipped off at the edges of patches (a sharp, broken mask)."""
	n = fbm(S, 10, 4, seed)
	return np.clip((n - (1.0 - amount)) * 9, 0, 1)


# --- Surfaces -------------------------------------------------------------------------------

def paint(S=256):
	"""The cab and hood: hazard-yellow enamel faded by decades of sun. PaintedMetal009's light carries
	the relief under the yellow; small chips show grey primer, and the scan's rust breaks through."""
	base = relief(np.ones((S, S, 3)) * col((172, 132, 40)), "PaintedMetal009", 0.38)
	base = mix(base, base * col((120, 110, 100)) * 1.6, np.clip((fbm(S, 3, 3, 1100) - 0.5) * 2, 0, 1) * 0.35)  # sun-faded patches
	primer = tint(scan("PaintedMetal013", S), (104, 50, 34))  # red-oxide primer under the yellow
	img = mix(base, primer, np.clip((fbm(S, 24, 3, 1101) - 0.74) * 10, 0, 1) * 0.85)
	img = mix(img, grade(scan("Rust003", S), 0, 1.0, 0.75), np.clip((fbm(S, 12, 4, 1103) - 0.7) * 6, 0, 1) * 0.8)
	img *= (1 - grime(S, 1105, 0.3))[..., None]
	return img


def paint_worn(S=256):
	"""The rockers, wheel arches and the hood's leading edge: the same paint gone to rust, streaks
	running down."""
	img = paint(S)
	y = np.mgrid[0:S, 0:S][0] / S
	streaks = np.clip((np.tile(vnoise(S, 28, 1111)[0], (S, 1)) - 0.55) * 4, 0, 1) * np.clip(y * 1.4, 0, 1)
	rust = grade(scan("Rust003", S), 0, 1.0, 0.8)
	img = mix(img, rust, np.clip(np.clip((fbm(S, 10, 4, 1113) - 0.5) * 4, 0, 1) + streaks * 0.6, 0, 1) * 0.85)
	img *= (1 - grime(S, 1115, 0.45))[..., None]
	return img


def sand(S=256):
	"""The body (the user's round 1, 2026-11-04: a Land Cruiser 79's sand-beige): the beige enamel gone
	chalky in the sun, PaintedMetal009's relief under it, small chips to red-oxide primer, rust breaking
	through, grime. Round 2: held darker and warmer (the first read near-white under the torch), far
	fewer chips and rust patches (it read as a rusty fridge), and only the scan's fine relief (its big
	blotches read as camouflage)."""
	l = lum(scan("PaintedMetal009", S))
	fine = l / np.maximum(_blur(l, 16), 1e-3)
	base = np.ones((S, S, 3)) * col((146, 128, 95)) * (0.9 + 0.1 * np.clip(fine, 0.0, 2.0))[..., None]
	base = mix(base, base * 1.06 + 0.02, np.clip((fbm(S, 3, 3, 1300) - 0.5) * 2, 0, 1) * 0.1)  # chalky, sun-bleached patches
	primer = tint(scan("PaintedMetal013", S), (104, 50, 34))
	img = mix(base, primer, np.clip((fbm(S, 24, 3, 1301) - 0.84) * 10, 0, 1) * 0.85)
	img = mix(img, grade(scan("Rust003", S), 0, 1.0, 0.75), np.clip((fbm(S, 12, 4, 1303) - 0.82) * 6, 0, 1) * 0.7)
	img *= (1 - grime(S, 1305, 0.08))[..., None]
	return img


def _blur(a, r):
	"""A wrapping box blur (the tile stays seamless)."""
	for axis in (0, 1):
		a = sum(np.roll(a, d, axis) for d in range(-r, r + 1)) / (2 * r + 1)
	return a


def sand_worn(S=256):
	"""The rockers, the lower doors and the bed's lower edge: the sand paint going to rust, streaks
	running down, mud."""
	img = sand(S)
	y = np.mgrid[0:S, 0:S][0] / S
	streaks = np.clip((np.tile(vnoise(S, 28, 1311)[0], (S, 1)) - 0.55) * 4, 0, 1) * np.clip(y * 1.4, 0, 1)
	img = mix(img, grade(scan("Rust003", S), 0, 1.0, 0.8), np.clip(np.clip((fbm(S, 10, 4, 1313) - 0.6) * 4, 0, 1) + streaks * 0.5, 0, 1) * 0.75)
	mud = np.clip((y - 0.55) * 2.5, 0, 1) * np.clip(fbm(S, 6, 3, 1315) * 1.4, 0, 1)
	img = mix(img, col((62, 52, 40)), mud * 0.6)
	return img


def plastic(S=128):
	"""The fender flares, the mirror heads, the grille's surround: black textured plastic gone grey in
	the sun (PaintedMetal013's relief, low), dusty."""
	img = relief(np.ones((S, S, 3)) * col((34, 33, 31)), "PaintedMetal013", 0.25)
	return mix(img, col((88, 84, 76)), np.clip((fbm(S, 6, 3, 1321) - 0.5) * 2, 0, 1) * 0.45)


def stripes(W=512, H=64):
	"""The side stripes (the user's Toyota): three red-brown bands along the body, cut by slashes, a
	pointed tip at the front (u 0) and a swept end at the back (u 1); faded and peeling (RGBA)."""
	y, x = np.mgrid[0:H, 0:W].astype(float)
	u, v = x / W, y / H
	bands = [((0.18, 0.30), (112, 34, 26)), ((0.36, 0.62), (150, 58, 34)), ((0.68, 0.80), (178, 104, 52))]
	rgb = np.zeros((H, W, 3))
	alpha = np.zeros((H, W))
	for k, ((v0, v1), c) in enumerate(bands):
		inside = (v >= v0) & (v <= v1)
		tip = u > 0.02 + 0.06 * np.abs((v - 0.5) * 2.0) ** 1.5  # the pointed front tip
		end = u < 0.97 - 0.05 * (v - v0) / max(v1 - v0, 1e-3) - 0.03 * k  # a swept, stepped end
		slash = ((x + y * 1.6) % 160) > 7  # thin diagonal cuts, every so often
		m = inside & tip & end & slash
		rgb[m] = col(c)
		alpha[m] = 1.0
	S = 1 << (max(W, H) - 1).bit_length()
	fade = 0.75 + 0.35 * fbm(S, 10, 3, 1331)[:H, :W]
	rgb *= fade[..., None]
	peel = np.clip((fbm(S, 24, 3, 1333)[:H, :W] - 0.68) * 8, 0, 1)  # flakes where the decal lifted
	alpha *= (1 - peel) * 0.93
	return np.dstack([np.clip(rgb, 0, 1), alpha])


def stencil_plate():
	"""The front bumper's plate: SS-07 on a black plate, the crew's hazard yellow (RGBA)."""
	img = stencil("SS-07", HAZARD, 192, 64)
	plate = np.dstack([np.ones((64, 192, 3)) * col((20, 20, 18)), np.ones((64, 192)) * 0.95])
	a = img[..., 3:4]
	return np.concatenate([img[..., :3] * a + plate[..., :3] * (1 - a), plate[..., 3:4]], axis=2)


def black(S=256):
	"""Oily black chassis paint (the bed, frame, bumpers, the beacon's box): PaintedMetal013's relief
	under a near-black, chipped to rust, an oil sheen in patches."""
	s13 = scan("PaintedMetal013", S)
	img = tint(s13, (30, 28, 25))
	img = mix(img, grade(scan("Rust003", S), 0, 0.9, 0.6), chips(S, 1121, 0.14) * 0.8)
	sheen = np.clip((fbm(S, 5, 3, 1123) - 0.55) * 3, 0, 1)
	img = mix(img, col((12, 11, 10)), sheen * 0.5)
	return img


def tread(S=256):
	"""Diamond treadplate (the bed floor, the steps): Metal055C's steel with drawn raised lugs (40 mm,
	exaggerated for the low-res frame), alternating 45-degree lugs, lit from the top left, worn bright
	on their tops, oil and grit between them."""
	metal = grade(scan("Metal055C", S), 0, 0.45, 0.6)
	y, x = np.mgrid[0:S, 0:S].astype(float)
	P = S / 8.0  # a 0.125 m cell; two lugs each, crossed
	h = np.zeros((S, S))
	for flip in (0, 1):
		ox = P / 2 if flip else 0.0
		cx = (x + ox) % P - P / 2
		cy = (y + ox) % P - P / 2
		d = 0.7071
		u = (cx * d + cy * d) if flip else (cx * d - cy * d)
		v = (-cx * d + cy * d) if flip else (cx * d + cy * d)
		lug = np.clip(1.0 - (np.abs(u) / (P * 0.36)) ** 2 - (np.abs(v) / (P * 0.085)) ** 2, 0, 1)
		h = np.maximum(h, np.clip(lug * 4.0, 0, 1))
	gy, gx = np.gradient(h)
	shade = np.clip(1.0 - (gx + gy) * 1.6, 0.45, 1.6)
	img = metal * (0.72 + 0.28 * h)[..., None] * shade[..., None]
	img = mix(img, np.clip(img * 1.3 + 0.06, 0, 1), (h > 0.9) * 0.6)
	dirt = np.clip((fbm(S, 6, 4, 1133) - 0.4) * 2, 0, 1) * (1 - h)
	img = mix(img, col((22, 18, 14)), dirt * 0.7)
	img = mix(img, grade(scan("Rust003", S), 0, 0.9, 0.7), np.clip((fbm(S, 8, 4, 1135) - 0.62) * 5, 0, 1) * (1 - h * 0.6) * 0.75)
	return img


def steel(S=256):
	"""Dull bare steel (the bull bar, the rack, chains, brackets, bolts): Metal053C, greyed."""
	img = grade(scan("Metal053C", S), 0, 0.35, 0.8)
	img = mix(img, grade(scan("Rust003", S), 0, 0.9, 0.75), rust_spots(S, 1141, 0.3) * 0.6)
	img *= (1 - grime(S, 1143, 0.3))[..., None]
	return img


def rust(S=256):
	"""Seized iron (springs, the winch drum, the exhaust): Rust003 with dark scale and pits."""
	img = grade(scan("Rust003", S), 0, 0.95, 0.82)
	dark = np.clip((fbm(S, 8, 4, 1151) - 0.5) * 3, 0, 1)
	img = mix(img, col((28, 18, 12)), dark * 0.45)
	pit = np.random.default_rng(1153).random((S, S))
	img[pit > 0.985] *= 0.5
	return img


def soot(S=256):
	"""The exhaust stack's tip and the cab's back above it: rust under black soot."""
	img = rust(S)
	return mix(img, col((14, 13, 12)), np.clip(fbm(S, 4, 3, 1157) * 1.2, 0, 1) * 0.8)


def rubber(S=128):
	"""Tyres, seals, mats and the beacon's feet: M4b's rubber scan, a little dust."""
	img = grade(tile("m9p_rubber", S), 0, 0.6, 0.9)
	dust = np.clip((fbm(S, 6, 3, 1161) - 0.55) * 3, 0, 1)
	return mix(img, col((70, 64, 56)), dust * 0.35)


def seat(S=128):
	"""The bench seat's cracked vinyl (M4b's tile), darkened, split and patched with tape."""
	img = grade(tile("m9p_seat", S), 0, 0.8, 0.8)
	y, x = np.mgrid[0:S, 0:S]
	# the tape runs straight along the tile and dull, near the vinyl's own tone: a light diagonal strip stair-
	# stepped in big texels over the seat backs (the director's walk5 check, 15-20 px steps at 3440 x 1440)
	tape_band = (np.abs(x - S * 0.35) < S * 0.05)
	img[tape_band] = mix(img, col((70, 66, 58)), np.ones((S, S)) * 0.65)[tape_band]
	return img


def dash(S=128):
	"""The dash and its panels: a dark grey-green painted steel, matte, worn where hands go."""
	img = relief(np.ones((S, S, 3)) * col((46, 50, 44)), "PaintedMetal013", 0.35)
	img = mix(img, grade(scan("Metal053C", S), 0, 0.3, 0.7), np.clip((fbm(S, 20, 3, 1171) - 0.76) * 9, 0, 1) * 0.7)
	return img


def liner(S=128):
	"""The cab's headliner: the dash's dark grey-green with its worn specks clamped out (on a ceiling seen
	up close, lit by a lamp, they read as pinholes of light), a touch darker."""
	img = dash(S)
	l = lum(img)
	img = img * np.clip(np.median(l) * 1.12 / np.maximum(l, 1e-3), 0.0, 1.0)[..., None]
	return img * 0.88


def hazard(S=256):
	"""Chevrons (the bull bar's ends, the tailgate band, the exit's boards and boom): yellow and black
	45° stripes, 0.1 m wide, painted on PaintedMetal009, worn at the edges."""
	y, x = np.mgrid[0:S, 0:S]
	stripe = ((x + y) // (S // 10)) % 2 == 0
	yellow = grade(scan("PaintedMetal009", S), -2, 0.85, 0.9)
	blk = tint(scan("PaintedMetal013", S), (26, 24, 22))
	img = np.where(stripe[..., None], yellow, blk)
	img = mix(img, grade(scan("Rust003", S), 0, 1.0, 0.75), np.clip((fbm(S, 16, 3, 1181) - 0.72) * 8, 0, 1) * 0.85)
	img *= (1 - grime(S, 1183, 0.3))[..., None]
	return img


def mag(S=64):
	"""A mag strip's coil (the bed floor): copper windings between steel cheeks."""
	y, x = np.mgrid[0:S, 0:S]
	copper = grade(scan("Metal053C", S), 22, 1.6, 0.85) * col((200, 120, 70)) * 1.6
	wind = (y % 4) < 3
	img = np.where(wind[..., None], copper, copper * 0.45)
	cheek = (x < S // 8) | (x >= S - S // 8)
	img[cheek] = grade(scan("Metal055C", S), 0, 0.4, 0.55)[cheek]
	return img


def relay(S=64):
	"""The beacon's relay behind its window: a coil, an armature, contacts, on a dark board."""
	img = tint(scan("PaintedMetal013", S), (20, 22, 18))
	y, x = np.mgrid[0:S, 0:S]
	coil = (np.abs(x - S * 0.35) < S * 0.18) & (np.abs(y - S * 0.55) < S * 0.3)
	copper = grade(scan("Metal053C", S), 22, 1.6, 0.85) * col((200, 120, 70)) * 1.5
	img[coil] = (copper * np.where((y % 3) < 2, 1.0, 0.5)[..., None])[coil]
	arm = (np.abs(y - S * 0.2) < S * 0.05) & (x > S * 0.15) & (x < S * 0.85)
	img[arm] = grade(scan("Metal055C", S), 0, 0.4, 0.8)[arm]
	for cx in (0.72, 0.84):
		c = (np.abs(x - S * cx) < S * 0.04) & (np.abs(y - S * 0.5) < S * 0.12)
		img[c] = col((190, 170, 120))
	return img


def mesh_rgba(S=128):
	"""Welded mesh (the headache rack's guard): 50 mm squares of steel wire, see-through (RGBA)."""
	y, x = np.mgrid[0:S, 0:S]
	bars = ((x % 16) < 2) | ((y % 16) < 2)
	rgb = grade(scan("Metal053C", S), 0, 0.3, 0.6)
	rgb = mix(rgb, grade(scan("Rust003", S), 0, 1.0, 0.75), rust_spots(S, 1191, 0.5) * 0.8)
	return np.dstack([rgb, bars.astype(float)])


def glass(S=128):
	"""The windscreen's good pane: grey-green glass, dust and a wiper arc cleaner than the rest.
	RGB only; ps1_glass takes its alpha from albedo_color."""
	img = np.ones((S, S, 3)) * col((70, 84, 80))
	y, x = np.mgrid[0:S, 0:S] / S
	arc = np.abs(np.hypot(x - 0.5, y - 1.05) - 0.62) < 0.25
	dust = np.clip(fbm(S, 6, 3, 1201) * 1.2, 0, 1)
	img = mix(img, col((120, 112, 96)), dust * np.where(arc, 0.25, 0.6))
	return img


def glass_cracked(S=128):
	"""The cracked pane: the same glass with a stone strike's star and its long cracks (drawn)."""
	img = glass(S)
	im = Image.fromarray((img * 255).astype(np.uint8))
	d = ImageDraw.Draw(im)
	rng = np.random.default_rng(1211)
	cx, cy = S * 0.62, S * 0.38
	for k in range(9):
		a = rng.uniform(0, np.pi * 2)
		r = rng.uniform(S * 0.25, S * 0.7)
		pts = [(cx, cy)]
		px, py = cx, cy
		for s in range(6):
			a += rng.uniform(-0.35, 0.35)
			px += np.cos(a) * r / 6
			py += np.sin(a) * r / 6
			pts.append((px, py))
		d.line(pts, fill=(205, 214, 210), width=1)
	for k in range(14):
		a = rng.uniform(0, np.pi * 2)
		d.line([(cx, cy), (cx + np.cos(a) * S * 0.06, cy + np.sin(a) * S * 0.06)], fill=(230, 236, 232), width=1)
	return np.asarray(im).astype(float) / 255.0


def _lens(S, inner, outer, seed, dead=False):
	"""A moulded lens seen face-on: prism rings and a grid of facets (drawn), scuffed."""
	y, x = (np.mgrid[0:S, 0:S] + 0.5) / S - 0.5
	r = np.hypot(x, y) * 2
	ring = 0.9 + 0.1 * np.cos(r * 40)
	facet = 0.88 + 0.12 * ((np.floor(x * 12) + np.floor(y * 12)) % 2)
	glow = np.clip(1.15 - r * 0.5, 0, 1.2)
	c = mix(np.ones((S, S, 3)) * col(inner), np.ones((S, S, 3)) * col(outer), np.clip(r, 0, 1))
	img = c * (ring * facet * glow)[..., None]
	scuff = np.clip((fbm(S, 6, 3, seed) - 0.5) * 2, 0, 1)
	img = mix(img, col((60, 56, 50)), scuff * (0.6 if dead else 0.25))
	if dead:
		img *= 0.28
	return img


def lens_head(S=64):
	return _lens(S, (255, 244, 214), (214, 190, 140), 1221)


def lens_tail(S=64):
	return _lens(S, (238, 52, 30), (150, 22, 16), 1223)


def lens_amber(S=64):
	return _lens(S, (255, 190, 70), (200, 110, 20), 1225)


def lens_dead(S=64):
	return _lens(S, (200, 160, 110), (120, 90, 60), 1227, dead=True)


def can(S=128):
	"""The jerrycans and the START button's cap: red enamel on PaintedMetal009's relief, chipped."""
	img = relief(np.ones((S, S, 3)) * col((132, 30, 22)), "PaintedMetal009", 0.4)
	img = mix(img, grade(scan("Rust003", S), 0, 1.0, 0.7), np.clip((fbm(S, 12, 3, 1251) - 0.74) * 8, 0, 1) * 0.8)
	return img


def chevron(W=128, H=256):
	"""A chevron board's face (the exit posts): hazard-yellow chevrons on black, pointing down the
	board, painted on PaintedMetal009 and worn at the edges."""
	y, x = np.mgrid[0:H, 0:W].astype(float)
	v = (y + np.abs(x - W / 2) * 0.9) % (H / 4)
	band = v < H / 8
	sq = max(W, H)
	ys = relief(np.ones((sq, sq, 3)) * col(HAZARD), "PaintedMetal009", 0.35)[:H, :W]
	bs = tint(scan("PaintedMetal013", sq), (24, 22, 20))[:H, :W]
	img = np.where(band[..., None], ys, bs)
	return mix(img, grade(scan("Rust003", sq), 0, 1.0, 0.75)[:H, :W], np.clip((fbm(sq, 12, 3, 1261)[:H, :W] - 0.72) * 8, 0, 1) * 0.8)


def crt(W=128, H=96):
	"""The cab's map screen, idle: dark amber-green phosphor, scanlines, a dim survey grid and the
	crew's header (the map itself is drawn in game, M9 step 3)."""
	img = np.zeros((H, W, 3))
	y, x = np.mgrid[0:H, 0:W]
	img[:] = col((14, 26, 16))
	grid = ((x % 16) == 0) | ((y % 16) == 0)
	img[grid] = col((40, 74, 40))
	img[(y % 2) == 1] *= 0.6
	im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
	d = ImageDraw.Draw(im)
	font = ImageFont.load_default()
	d.rectangle([2, 2, W - 3, 12], fill=(14, 26, 16))
	d.text((4, 2), "SS-07  NAV  -  NO FIX", fill=(170, 210, 120), font=font)
	img = np.asarray(im).astype(float) / 255.0
	r = np.hypot((x / W - 0.5) * 1.3, (y / H - 0.5))
	return img * np.clip(1.15 - r * 0.6, 0, 1)[..., None]


def gauges(W=128, H=64):
	"""Three dials on the cluster's face (oil, temperature, speed), drawn, on the dash's paint."""
	img = np.ones((H, W, 3)) * col((18, 18, 16))
	im = Image.fromarray((img * 255).astype(np.uint8))
	d = ImageDraw.Draw(im)
	for k, (cx, r) in enumerate(((22, 16), (64, 26), (106, 16))):
		cy = 32
		d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(200, 192, 168), outline=(70, 66, 58))
		for t in range(9):
			a = np.radians(220 - t * 260 / 8)
			d.line([(cx + np.cos(a) * r * 0.75, cy - np.sin(a) * r * 0.75), (cx + np.cos(a) * r * 0.92, cy - np.sin(a) * r * 0.92)], fill=(30, 28, 24))
		a = np.radians(220 - [3, 6, 1][k] * 260 / 8)
		d.line([(cx, cy), (cx + np.cos(a) * r * 0.8, cy - np.sin(a) * r * 0.8)], fill=(170, 40, 24), width=2 if r > 20 else 1)
	img = np.asarray(im).astype(float) / 255.0
	return mix(img, col((90, 80, 60)), np.clip((fbm(W, 6, 3, 1231)[:H, :W] - 0.55) * 2, 0, 1) * 0.4)


def stencil_tailgate():
	"""The tailgate's spray stencil: SS-07 / SALVAGE, the crew's hazard yellow (RGBA)."""
	return stencil("SS-07  SALVAGE", HAZARD, 256, 64)


def stencil_beacon():
	"""The beacon box's stencil (RGBA)."""
	return stencil("SALVAGE", HAZARD, 128, 32)


def arrows(W=256, H=128):
	"""The exit's spray on the road: two chevron arrows and EXIT, the crew's hazard yellow, sprayed
	freehand (overspray, drips, wear) (RGBA)."""
	small = Image.new("L", (W, H), 0)
	d = ImageDraw.Draw(small)
	for k in range(2):
		x0 = 30 + k * 64
		d.line([(x0, 18), (x0 + 40, 64), (x0, 110)], fill=255, width=14)
	tiny = Image.new("L", (32, 12), 0)
	ImageDraw.Draw(tiny).text((2, 0), "EXIT", fill=255, font=ImageFont.load_default())
	small.paste(tiny.resize((96, 36), Image.NEAREST), (150, 46))
	m = np.asarray(small.resize((W // 2, H // 2), Image.BILINEAR).resize((W, H), Image.BILINEAR)).astype(float) / 255
	S = 1 << (max(W, H) - 1).bit_length()
	wear = np.clip((fbm(S, 12, 3, 1241)[:H, :W] - 0.12) * 3, 0, 1)
	spray = np.clip((fbm(S, 40, 2, 1243)[:H, :W] - 0.5) * 2, 0, 1) * np.clip(m * 3 - 0.2, 0, 1) * 0.3
	alpha = np.clip(m * wear + spray, 0, 1) * 0.92
	rgb = np.ones((H, W, 3)) * col(HAZARD) * (0.8 + 0.3 * fbm(S, 8, 2, 1245)[:H, :W, None])
	return np.dstack([rgb, alpha])


SURFACES = {
	"paint": paint, "paint_worn": paint_worn, "black": black, "tread": tread, "steel": steel, "rust": rust,
	"soot": soot, "rubber": rubber, "seat": seat, "dash": dash, "liner": liner, "hazard": hazard, "mag": mag, "relay": relay,
	"mesh": mesh_rgba, "glass": glass, "glass_cracked": glass_cracked, "lens_head": lens_head,
	"lens_tail": lens_tail, "lens_amber": lens_amber, "lens_dead": lens_dead, "crt": crt, "gauges": gauges,
	"stencil_tailgate": stencil_tailgate, "stencil_beacon": stencil_beacon, "arrows": arrows, "can": can,
	"chevron": chevron, "sand": sand, "sand_worn": sand_worn, "plastic": plastic, "stripes": stripes,
	"stencil_plate": stencil_plate,
}

if __name__ == "__main__":
	for name, fn in SURFACES.items():
		save(name, fn())
	# Mean brightness per opaque tile, against SLIP 7's neighbours (hold within ~20 %).
	for name in ("paint", "sand", "sand_worn", "plastic", "black", "tread", "steel", "rust", "rubber", "hazard"):
		im = np.asarray(Image.open(os.path.join(OUT, name + ".png")).convert("RGB")).astype(float) / 255
		print("%-12s mean %.3f" % (name, lum(im).mean()))
	print("wrote", len(SURFACES), "textures to", os.path.normpath(OUT))
