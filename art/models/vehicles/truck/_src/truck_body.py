# SS-07, round 2 (the user, 2026-11-04: "look more like this toyota", a Land Cruiser 79 double-cab pickup,
# assets/_ref/truck/; "a bit bigger"; then "the truck bed needs to be longer and the driver is on the left",
# "too boxy, no curves"): the truck's pieces. Exec'd after truck_build.py (its helpers: face, img, bolt).
# 1.4x the real truck with a longer tray: 8.1 m bumper to bumper, 2.62 m body, 2.78 m over the flares, a
# 4.8 m wheelbase, 1.06 m wheels. A double cab (the driver on the left, a front passenger, a rear bench for
# two), four real doors (their own pieces, hinged on their front edges: the hand grab swings them), a tray
# bed 2.7 m long the crew can stand in. Rounded where the Toyota is: the roof's rolled edges, the cab's
# sides leaning in above the belt, rolled shoulders and rockers, rounded rear cab corners, rolled fender
# tops and hood edges, a wrap-round bumper, a rounded grille surround and tray rails. Faded sand-beige with
# red-brown side stripes, black flares, a grey steel front bumper, a snorkel up the left A pillar.
#
# Built in a design space whose front axle sits at y AXF; DY then moves everything so the origin lies on
# the ground under the middle of the wheelbase. The nose at Blender +Y (Godot -Z).

AXF, AXR = 2.225, -2.575            # the axles (design space)
DY = -(AXF + AXR) / 2               # design space -> model space (the origin mid-wheelbase)
WR, TW, TRACK = 0.53, 0.37, 1.08    # wheel radius, tyre width, the wheels' centres off the middle line
ARCH, ARCH_R = 0.68, 0.66           # the front and rear arches' radii (the rear clears the bed floor)
HW = 1.31                            # the body's half width (doors' outer skin)
FLARE = 1.39                         # the flares' outer face
RAIL_X = 0.6                         # the chassis rails' centres
RAIL_Z = 0.73                        # ... and their height: their undersides on the axles (0.62 m clear)
BUMP_R_Z = (0.62, 0.76)              # the rear step bumper's underside and top
Y_GRILLE = 3.42
Y_BUMP_F = 3.59                      # the front bumper's face
Y_COWL = 1.55                        # the windscreen's base
Y_A = 1.45                           # the front doors' hinge line
Y_B0, Y_B1 = 0.20, 0.08              # the B pillar
Y_C = -1.15                          # the rear doors' rear edge
Y_CAB_B = -1.48                      # the cab's back
R_CAB = 0.15                         # the cab's rear corners' radius (in plan)
Y_BED_F = -1.58                      # the bed's front wall (outer)
Y_BED_R = -4.32                      # the bed's inner rear: the tailgate's hinge line
Y_BUMP_R = Y_BED_R - 0.22
Z_SILL = 0.66
Z_FLOOR = 0.95
Z_DOOR0 = 0.80
Z_BELT = 1.86
Z_WIN_TOP = 2.585                    # the door frames' top rail
Z_RAIL = 2.62                        # the roof's lower edge
Z_ROOF = 2.72
Z_HOOD_B, Z_HOOD_F = 1.88, 1.78
Z_FENDER = 1.775                     # the fender tops
BED_FLOOR, BED_RIM = 1.20, 1.75
BED_HW = 1.12
GATE_H = BED_RIM - BED_FLOOR         # the tailgate's height
# The side stripes' run (u 0 at the front door's front edge, 1 at the bed's rear post) and band: above the
# flares, under the door handles.
STRIPE_Y = (1.44, Y_BED_R + 0.06)
STRIPE_Z = (1.36, 1.64)
# The cab side's profile below the belt (z, out from HW): a rocker tucked under, a shoulder rolled in.
SIDE = [(Z_SILL, -0.06), (0.72, -0.03), (0.80, -0.012), (0.90, 0.0), (Z_BELT - 0.07, 0.0), (Z_BELT - 0.03, -0.012), (Z_BELT, -0.035)]
# Above the belt the cab leans in: 9 % narrower at the roof (TUMBLE).
TUMBLE = 0.09
# The steering wheel's hub (the driver on the left), its column's slope (TruckModel.STEER_TILT, -0.62 rad,
# down into the dash), the map screen (on the dash top, turned toward the driver).
STEER_HUB = (-0.58, 1.05, 1.82)
STEER_DIR = (0.0, math.cos(0.62), -math.sin(0.62))
SCREEN_C, SCREEN_RZ = (0.12, 1.36, 2.02), -0.35


def tumble(q):
	"""The cab's tumblehome: above the belt its sides lean in."""
	t = max(0.0, min(1.0, (q[2] - Z_BELT) / (Z_ROOF - Z_BELT)))
	return (q[0] * (1.0 - TUMBLE * t), q[1], q[2])


def side_x(z):
	"""The cab side's outward offset from HW at height z (below the belt)."""
	if z <= SIDE[0][0]:
		return SIDE[0][1]
	for (za, oa), (zb, ob) in zip(SIDE, SIDE[1:]):
		if z <= zb:
			return oa + (ob - oa) * (z - za) / (zb - za)
	return SIDE[-1][1]


def arc(cx, cy, r, a0, a1, n):
	return [(cx + r * math.cos(a0 + (a1 - a0) * k / n), cy + r * math.sin(a0 + (a1 - a0) * k / n)) for k in range(n + 1)]


def path_of(*parts):
	"""Joins point lists into one path, dropping repeated points."""
	out = []
	for part in parts:
		for q in part:
			if not out or math.hypot(q[0] - out[-1][0], q[1] - out[-1][1]) > 1e-5:
				out.append(q)
	return out


def wrap(p, path, prof, m, closed=False, ring=False, zf=None, m_of=None, caps=True):
	"""A profile swept round a plan path. path [(x, y)] is walked with the outside on its right
	(counter-clockwise round a shape seen from above); prof [(out, z)] is walked with the outside on its
	right too (up an outer wall, then inward over a top); z is over zf(x, y) when given. `ring` closes
	the profile loop and `closed` the path; an open path's ends are capped when the profile is a ring.
	Returns each path point's ring of points."""
	n, k = len(path), len(prof)
	norms = []
	for i in range(n):
		a = path[(i - 1) % n] if (closed or i > 0) else path[i]
		b = path[(i + 1) % n] if (closed or i < n - 1) else path[i]
		tx, ty = b[0] - a[0], b[1] - a[1]
		ln = math.hypot(tx, ty) or 1.0
		norms.append((ty / ln, -tx / ln))
	rings = []
	for i, (x, y) in enumerate(path):
		nx, ny = norms[i]
		row = []
		for (o, z) in prof:
			px, py = x + nx * o, y + ny * o
			row.append((px, py, z + (zf(px, py) if zf else 0.0)))
		rings.append(row)
	for i in (range(n) if closed else range(n - 1)):
		i2 = (i + 1) % n
		nx, ny = norms[i][0] + norms[i2][0], norms[i][1] + norms[i2][1]
		for j in (range(k) if ring else range(k - 1)):
			j2 = (j + 1) % k
			do, dz = prof[j2][0] - prof[j][0], prof[j2][1] - prof[j][1]
			p.poly([rings[i][j], rings[i2][j], rings[i2][j2], rings[i][j2]], m_of(j) if m_of else m, (nx * dz, ny * dz, -do))
	if ring and not closed and caps:
		for (i, a, b, s) in ((0, 0, 1, -1), (n - 1, n - 2, n - 1, 1)):
			t = (path[b][0] - path[a][0], path[b][1] - path[a][1], 0.0)
			p.poly(rings[i], m_of(0) if m_of else m, (t[0] * s, t[1] * s, 0.0))
	return rings


def side_skin(p, sx, y0, y1, z0, z1, m, m_low=None, z_split=1.05, inner=0.08):
	"""A cab side panel over y0..y1 and z0..z1 following SIDE (its rocker and shoulder), its inside
	flat at HW - inner, its top, bottom and ends closed; below z_split it takes m_low."""
	zs = sorted(set([z0, z1] + [z for (z, _) in SIDE if z0 < z < z1] + ([z_split] if m_low and z0 < z_split < z1 else [])))
	ya, yb = max(y0, y1), min(y0, y1)
	xin = sx * (HW - inner)
	outer = [(sx * (HW + side_x(z)), z) for z in zs]
	for (xa, za), (xb, zb) in zip(outer, outer[1:]):
		mm = m_low if (m_low and zb <= z_split + 1e-6) else m
		p.poly([(xa, yb, za), (xa, ya, za), (xb, ya, zb), (xb, yb, zb)], mm, (sx * (zb - za), 0, -(side_x(zb) - side_x(za))))
	p.poly([(xin, yb, z0), (xin, ya, z0), (xin, ya, z1), (xin, yb, z1)], m, (-sx, 0, 0))
	p.poly([(outer[-1][0], yb, z1), (outer[-1][0], ya, z1), (xin, ya, z1), (xin, yb, z1)], m, (0, 0, 1))
	p.poly([(outer[0][0], yb, z0), (outer[0][0], ya, z0), (xin, ya, z0), (xin, yb, z0)], m_low or m, (0, 0, -1))
	for (y, sy) in ((ya, 1), (yb, -1)):
		p.poly([(x, y, z) for (x, z) in outer] + [(xin, y, z1), (xin, y, z0)], m, (0, sy, 0))


def _arch_pts(yc, r, zmin, n=10):
	"""The arch's points (y, z) above zmin, from its front foot over the top to its rear foot."""
	s = max(-1.0, min(1.0, (zmin - WR) / r))
	a0 = math.asin(s)
	return [(yc + r * math.cos(a0 + (math.pi - 2 * a0) * k / n), WR + r * math.sin(a0 + (math.pi - 2 * a0) * k / n)) for k in range(n + 1)]


def arch_panel(p, x_out, x_in, y0, y1, z0, z1, yc, r, m, lip="black", n=10, ends=False):
	"""A side panel (outer face at x_out, inner at x_in) over y0..y1, z0..z1 with a wheel arch cut from
	its bottom edge, built in convex strips; the arch's lip joins the two faces."""
	sg = 1 if x_out > x_in else -1
	pts = _arch_pts(yc, r, z0, n)
	ya, yb = pts[-1][0], pts[0][0]  # the arch's rear and front feet
	strips = []
	if ya > y0 + 1e-4:
		strips.append([(y0, z0), (ya, z0), (ya, z1), (y0, z1)])
	for k in range(n, 0, -1):
		a, b = pts[k], pts[k - 1]
		strips.append([a, b, (b[0], z1), (a[0], z1)])
	if yb < y1 - 1e-4:
		strips.append([(yb, z0), (y1, z0), (y1, z1), (yb, z1)])
	for s in strips:
		p.poly([(x_out, y, z) for (y, z) in s], m, (sg, 0, 0))
		p.poly([(x_in, y, z) for (y, z) in s], m, (-sg, 0, 0))
	for k in range(n):
		a, b = pts[k], pts[k + 1]
		c = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
		p.poly([(x_out, a[0], a[1]), (x_out, b[0], b[1]), (x_in, b[0], b[1]), (x_in, a[0], a[1])], lip, (0, yc - c[0], WR - c[1]))
	for (ya_, yb_) in ((y0, ya), (yb, y1)):
		if yb_ - ya_ > 1e-4:
			p.poly([(x_out, ya_, z0), (x_out, yb_, z0), (x_in, yb_, z0), (x_in, ya_, z0)], lip, (0, 0, -1))
	p.poly([(x_out, y0, z1), (x_out, y1, z1), (x_in, y1, z1), (x_in, y0, z1)], m, (0, 0, 1))
	if ends:
		for (y, sy) in ((y0, -1), (y1, 1)):
			p.poly([(x_out, y, z0), (x_in, y, z0), (x_in, y, z1), (x_out, y, z1)], m, (0, sy, 0))
	return pts


def stripe(p, sx, y0, y1, x=None):
	"""The side stripes between y0 (front) and y1 (back) on the side sx, 4 mm off the panel at x."""
	ya, yb = max(y0, y1), min(y0, y1)
	ua = (STRIPE_Y[0] - ya) / (STRIPE_Y[0] - STRIPE_Y[1])
	ub = (STRIPE_Y[0] - yb) / (STRIPE_Y[0] - STRIPE_Y[1])
	x = sx * ((HW if x is None else x) + 0.004)
	z0, z1 = STRIPE_Z
	pts = [(x, ya, z0), (x, yb, z0), (x, yb, z1), (x, ya, z1)]
	uv = [(ua, 1.0), (ub, 1.0), (ub, 0.0), (ua, 0.0)]
	p.poly(pts, "stripes", (sx, 0, 0), ("img", uv))


def flare(p, sx, yc, r0, z_low, x_in):
	"""A black over-fender round an arch: a squared band standing out from the body to FLARE, its outer
	edge rolled."""
	n = 10
	r1 = r0 + 0.11
	a0 = math.asin(max(-1.0, min(1.0, (z_low - WR) / r1)))
	pts_o, pts_i = [], []
	for k in range(n + 1):
		a = a0 + (math.pi - 2 * a0) * k / n
		sq = 1.0 + 0.12 * math.sin(a) ** 6  # pushed toward a trapezoid
		pts_o.append((yc + r1 * math.cos(a) * sq, WR + r1 * math.sin(a), a))
		pts_i.append((yc + r0 * math.cos(a), WR + r0 * math.sin(a)))
	xo, xm, xi = sx * FLARE, sx * (FLARE - 0.035), sx * x_in
	# the band's outer edge rolled: its face at xo stops 3.5 cm short of the rim, which bends in to xm
	rim = [(o[0] + 0.035 * math.cos(o[2]), o[1] + 0.035 * math.sin(o[2])) for o in pts_o]
	for k in range(n):
		a, b = pts_o[k], pts_o[k + 1]
		c, d = pts_i[k + 1], pts_i[k]
		p.poly([(xo, a[0], a[1]), (xo, b[0], b[1]), (xo, c[0], c[1]), (xo, d[0], d[1])], "plastic", (sx, 0, 0))
		p.poly([(xo, a[0], a[1]), (xo, b[0], b[1]), (xm, rim[k + 1][0], rim[k + 1][1]), (xm, rim[k][0], rim[k][1])], "plastic", (sx, b[0] - yc, b[1] - WR))
		p.poly([(xm, rim[k][0], rim[k][1]), (xm, rim[k + 1][0], rim[k + 1][1]), (xi, rim[k + 1][0], rim[k + 1][1]), (xi, rim[k][0], rim[k][1])], "plastic", (0, b[0] - yc, b[1] - WR))
		p.poly([(xo, d[0], d[1]), (xo, c[0], c[1]), (xi, c[0], c[1]), (xi, d[0], d[1])], "plastic", (0, yc - c[0], WR - c[1]))
	for (o, r, i) in ((pts_o[0], rim[0], pts_i[0]), (pts_o[-1], rim[-1], pts_i[-1])):
		p.poly([(xi, r[0], r[1]), (xm, r[0], r[1]), (xo, o[0], o[1]), (xo, i[0], i[1]), (xi, i[0], i[1])], "plastic", (0, 0, -1))


def _screen_point():
	q = rot((0.0, -0.103, 0.0), 0.0, 0.0, SCREEN_RZ)
	return (SCREEN_C[0] + q[0], SCREEN_C[1] + q[1], SCREEN_C[2])


def _hood_z(x, y):
	hb, hf = Y_COWL + 0.07, Y_GRILLE + 0.02
	return Z_HOOD_B + (y - hb) * (Z_HOOD_F - Z_HOOD_B) / (hf - hb)


@piece("truck", note="SS-07's body (round 2): nose at Blender +Y (Godot -Z), origin under the wheelbase's middle")
def body(p):
	# --- the chassis, tucked up under the body: the rails sit on the axles (a lifted truck's clearance;
	# the user, 2026-11-05: the under parts were too low) ------------------------------------------
	rail0 = Y_BUMP_R + 0.14
	for sx in (-1, 1):
		p.bevel_box((0.12, 3.5 - rail0, 0.22), (sx * RAIL_X, (3.5 + rail0) / 2, RAIL_Z), "black", b=0.02)
	for y in (Y_BED_R - 0.12, AXR - 0.33, -1.0, 0.6, 2.0, 3.1):
		p.bx(-RAIL_X, RAIL_X, y - 0.05, y + 0.05, RAIL_Z - 0.09, RAIL_Z + 0.05, "black")
	for yax in (AXR, AXF):
		p.cyl(0.085, 2.0, (0.0, yax, WR), "rust", axis="x", sides=8)
		for sx in (-1, 1):
			# the leaf springs outboard of the rails, on the axle, hung from brackets on the rails' sides
			xs = sx * (RAIL_X + 0.13)
			p.sweep([(xs, yax - 0.75, 0.73), (xs, yax - 0.35, 0.67), (xs, yax, 0.64), (xs, yax + 0.35, 0.67), (xs, yax + 0.75, 0.73)], 0.035, "rust", sides=4, flat=0.35)
			for ye in (yax - 0.75, yax + 0.75):
				p.bx(min(sx * (RAIL_X + 0.06), xs), max(sx * (RAIL_X + 0.06), xs), ye - 0.03, ye + 0.03, 0.7, RAIL_Z + 0.06, "black")
			p.cyl(0.035, 0.42, (sx * 0.86, yax + 0.22, 0.74), "steel", rx=0.35, sides=6)
	p.lathe([(0.0, -0.17), (0.12, -0.12), (0.15, 0.0), (0.12, 0.12), (0.0, 0.17)], "rust", sides=8, center=(0.15, AXR, WR), ry=math.pi / 2)
	p.lathe([(0.0, -0.15), (0.1, -0.1), (0.13, 0.0), (0.1, 0.1), (0.0, 0.15)], "rust", sides=8, center=(-0.12, AXF, WR), ry=math.pi / 2)
	p.cyl(0.05, 3.4, (0.05, -0.3, 0.6), "steel", axis="y", sides=6)
	p.bevel_box((0.6, 1.2, 0.28), (0.0, 2.6, 0.8), "black", b=0.04)  # the engine's sump and bell housing
	p.bevel_box((0.45, 0.9, 0.12), (-0.92, -0.5, 0.6), "black", b=0.03)  # the fuel tank, flat under the cab floor
	# the exhaust: along the right rail's inside, out to the side ahead of the rear wheel
	p.sweep([(0.3, 2.2, 0.68), (0.45, 1.6, 0.6), (0.45, -1.0, 0.6), (0.85, -1.5, 0.62), (1.12, -1.72, 0.62)], 0.05, "rust", sides=6)
	p.cyl(0.055, 0.12, (1.2, -1.72, 0.62), "soot", axis="x", sides=8)
	p.cyl(0.5, 0.3, (0.0, Y_BED_R + 0.47, 0.82), "rubber", sides=12)  # the spare slung under the tray's tail
	p.cyl(0.33, 0.305, (0.0, Y_BED_R + 0.47, 0.82), "rust", sides=8)

	# --- the front: grille, lamps, bumper ----------------------------------------------------------
	gy = Y_GRILLE
	p.poly([(-1.08, gy - 0.06, 1.06), (1.08, gy - 0.06, 1.06), (1.08, gy - 0.06, 1.7), (-1.08, gy - 0.06, 1.7)], "dark", (0, 1, 0))
	for z in (1.3, 1.42, 1.54):
		p.bevel_box((1.08, 0.04, 0.05), (0.0, gy, z), "steel", b=0.012)
	p.bx(-0.56, 0.56, gy - 0.06, gy + 0.01, 1.19, 1.23, "plastic")
	p.bx(-0.56, 0.56, gy - 0.06, gy + 0.01, 1.6, 1.64, "plastic")
	for sx in (-1, 1):
		p.bx(min(sx * 0.56, sx * 0.62), max(sx * 0.56, sx * 0.62), gy - 0.06, gy + 0.01, 1.1, 1.66, "plastic")
	# the surround: a rounded frame round the grille and both lamps
	ring = path_of(arc(1.02, 1.12, 0.07, -math.pi / 2, 0.0, 3), arc(1.02, 1.57, 0.07, 0.0, math.pi / 2, 3),
			arc(-1.02, 1.57, 0.07, math.pi / 2, math.pi, 3), arc(-1.02, 1.12, 0.07, math.pi, 1.5 * math.pi, 3))
	p.sweep([(x, gy + 0.005, z) for (x, z) in ring + [ring[0]]], 0.035, "plastic", sides=5, caps=(False, False))
	for sx in (-1, 1):
		hx = sx * 0.83
		p.lathe([(0.15, -0.06), (0.175, -0.04), (0.175, 0.03), (0.16, 0.045)], "steel", sides=12, center=(hx, gy, 1.39), rx=-math.pi / 2, caps=(False, False))
		p.cyl(0.155, 0.06, (hx, gy - 0.03, 1.39), "black", axis="y", sides=12)
		mk = p.mark()
		p.poly([(math.cos(2 * math.pi * k / 12) * 0.15, 0.0, math.sin(2 * math.pi * k / 12) * 0.15) for k in range(12)], "lens_head", (0, 1, 0),
				("img", [(0.5 + 0.5 * math.cos(2 * math.pi * k / 12), 0.5 - 0.5 * math.sin(2 * math.pi * k / 12)) for k in range(12)]))
		p.place(mk, t=(hx, gy + 0.03, 1.39))
		p.bevel_box((0.07, 0.04, 0.13), (sx * 1.125, gy + 0.005, 1.42), "lens_amber", b=0.012)  # the indicator on the fender's front
	# the emblem: a plain steel ring on a dark disc (no maker's mark)
	p.cyl(0.095, 0.03, (0.0, gy + 0.03, 1.42), "steel", axis="y", sides=12)
	p.cyl(0.075, 0.035, (0.0, gy + 0.033, 1.42), "plastic", axis="y", sides=12)
	p.bx(-1.1, 1.1, gy - 0.06, gy + 0.005, 0.96, 1.06, "sand_worn")  # the valance under the grille
	# the bumper: grey steel wrapped round the corners, a lower lip, the plate, fog lamps, hazard ends, tow hooks
	bf = Y_BUMP_F
	bump = path_of([(1.33, gy - 0.12)], arc(1.13, bf - 0.2, 0.2, 0.0, math.pi / 2, 4), arc(-1.13, bf - 0.2, 0.2, math.pi / 2, math.pi, 4), [(-1.33, gy - 0.12)])
	wrap(p, bump, [(-0.17, 0.64), (-0.02, 0.64), (0.0, 0.67), (0.0, 0.97), (-0.025, 1.0), (-0.17, 1.0)], "steel", ring=True)
	p.bevel_box((2.2, 0.12, 0.08), (0.0, gy + 0.06, 0.6), "black", b=0.015)
	face(p, (0.0, bf + 0.004, 0.8), (0, 1, 0), (0, 0, 1), 0.52, 0.17, "stencil_plate")
	for sx in (-1, 1):
		p.cyl(0.075, 0.05, (sx * 0.86, bf + 0.01, 0.84), "black", axis="y", sides=10)
		p.cyl(0.062, 0.006, (sx * 0.86, bf + 0.037, 0.84), "lens_dead", axis="y", sides=10)
		face(p, (sx * 1.04, bf + 0.004, 0.82), (0, 1, 0), (0, 0, 1), 0.14, 0.2, "hazard", (0.0, 0.0, 0.14, 0.2))
		p.sweep([(sx * 0.55, bf - 0.02, 0.7), (sx * 0.55, bf + 0.06, 0.66), (sx * 0.55, bf + 0.06, 0.6), (sx * 0.55, bf, 0.58)], 0.025, "rust", sides=4)
	p.bx(-0.55, 0.55, 2.7, gy, 0.62, 0.66, "steel")  # the skid plate

	# --- the hood (its edges rolled, its front corners round) and the fenders -----------------------
	hb, hf, rh = Y_COWL + 0.07, gy + 0.02, 0.12
	hood = path_of([(1.08, hb)], arc(1.08 - rh, hf - rh, rh, 0.0, math.pi / 2, 3), arc(-1.08 + rh, hf - rh, rh, math.pi / 2, math.pi, 3), [(-1.08, hb)])
	rings = wrap(p, hood, [(0.0, -0.1), (0.0, -0.04), (-0.02, -0.012), (-0.06, 0.0)], "sand", zf=_hood_z)
	p.poly([r[-1] for r in rings], "sand", (0, 0, 1))
	# (2026-11-08, the user: the truck was see-through from below) the hood's underside, and a belly pan
	# over the rails closing the engine bay from the firewall to the grille: the bay was open underneath and
	# the one-sided hood skin let the world behind show through it
	p.poly([r[0] for r in rings], "black", (0, 0, -1))
	p.poly([(-0.9, Y_COWL - 0.05, 0.86), (0.9, Y_COWL - 0.05, 0.86), (0.9, gy - 0.05, 0.86), (-0.9, gy - 0.05, 0.86)], "black", (0, 0, -1))
	p.bevel_box((0.2, 0.03, 0.05), (0.0, hf + 0.012, 1.73), "steel", b=0.008)  # the latch
	for sx in (-1, 1):
		# the fender's side (its wheel arch cut), its front, and its top rolled over the outer edge and
		# round the front corner
		rf = 0.14
		arch_panel(p, sx * HW, sx * (HW - 0.05), Y_COWL, gy - rf, Z_SILL, Z_FENDER - 0.15, AXF, ARCH, "sand", lip="plastic")
		corner = arc(HW - rf, gy - rf, rf, 0.0, math.pi / 2, 4)
		top = path_of([(HW, Y_COWL)], corner, [(1.08, gy)])
		if sx < 0:
			top = [(-x, y) for (x, y) in reversed(top)]
			corner = [(-x, y) for (x, y) in reversed(corner)]
		rings = wrap(p, top, [(0.0, Z_FENDER - 0.15), (0.0, Z_FENDER - 0.1), (-0.02, Z_FENDER - 0.035), (-0.055, Z_FENDER - 0.008), (-0.1, Z_FENDER)], "sand")
		inner = [r[-1] for r in rings]
		p.poly(inner + [(sx * 1.08, Y_COWL, Z_FENDER)] if sx > 0 else [(sx * 1.08, Y_COWL, Z_FENDER)] + inner, "sand", (0, 0, 1))
		wrap(p, corner, [(0.0, Z_SILL), (0.0, 1.06), (0.0, Z_FENDER - 0.15)], "sand", m_of=lambda j: "sand_worn" if j == 0 else "sand")
		xa, xb = sorted((sx * 1.08, sx * (HW - rf)))
		p.poly([(xa, gy, 1.06), (xb, gy, 1.06), (xb, gy, Z_FENDER - 0.15), (xa, gy, Z_FENDER - 0.15)], "sand", (0, 1, 0))
		p.poly([(xa, gy, Z_SILL), (xb, gy, Z_SILL), (xb, gy, 1.06), (xa, gy, 1.06)], "sand_worn", (0, 1, 0))
		p.poly([(sx * 0.9, AXF - ARCH, Z_SILL), (sx * 0.9, AXF + ARCH, Z_SILL), (sx * 0.9, AXF + ARCH, 1.7), (sx * 0.9, AXF - ARCH, 1.7)], "black", (-sx, 0, 0))
		p.poly([(sx * 0.9, AXF - ARCH, 1.7), (sx * (HW - 0.05), AXF - ARCH, 1.7), (sx * (HW - 0.05), AXF + ARCH, 1.7), (sx * 0.9, AXF + ARCH, 1.7)], "black", (0, 0, -1))
		# (2026-11-08) the well's wall seen from the wheel too, and the well's front and back walls, and the
		# fender's bottom ahead of the well: from the arch the bay showed through
		p.poly([(sx * 0.9, AXF - ARCH, Z_SILL), (sx * 0.9, AXF + ARCH, Z_SILL), (sx * 0.9, AXF + ARCH, 1.7), (sx * 0.9, AXF - ARCH, 1.7)], "black", (sx, 0, 0))
		for (yw, fy) in ((AXF - ARCH, 1), (AXF + ARCH, -1)):
			p.poly([(sx * 0.9, yw, Z_SILL), (sx * (HW - 0.05), yw, Z_SILL), (sx * (HW - 0.05), yw, 1.7), (sx * 0.9, yw, 1.7)], "black", (0, fy, 0))
		p.poly([(sx * 0.9, AXF + ARCH, Z_SILL), (sx * (HW - 0.01), AXF + ARCH, Z_SILL), (sx * (HW - 0.01), gy, Z_SILL), (sx * 0.9, gy, Z_SILL)], "black", (0, 0, -1))
		flare(p, sx, AXF, ARCH, Z_SILL, HW)
		flare(p, sx, AXR, ARCH_R, 0.95, HW - 0.03)
	# the snorkel up the left A pillar: a black pipe off the fender, clamped, its ram head over the roof
	p.sweep([(-1.27, 1.85, Z_FENDER), (-1.33, 1.78, 1.92), (-1.32, 1.56, 2.36), (-1.28, 1.42, 2.76), (-1.27, 1.38, 2.88)], 0.065, "plastic", sides=8)
	p.bevel_box((0.18, 0.26, 0.17), (-1.27, 1.45, 2.95), "plastic", b=0.03, rx=-0.15)
	p.bx(-1.39, -1.25, 1.535, 1.565, 2.38, 2.43, "steel")
	p.bx(-1.35, -1.21, 1.435, 1.465, 2.64, 2.69, "steel")

	# --- the cab shell (its upper half leaned in by tumble): sills, pillars, rear corners, roof ------
	mk_cab = p.mark()
	for sx in (-1, 1):
		side_skin(p, sx, Y_CAB_B + R_CAB, Y_COWL, Z_SILL, Z_DOOR0, "sand_worn", inner=0.07)
		side_skin(p, sx, Y_A, Y_COWL, Z_DOOR0, Z_BELT, "sand", "sand_worn")
		side_skin(p, sx, Y_B1, Y_B0, Z_DOOR0, Z_BELT, "sand", "sand_worn")
		side_skin(p, sx, Y_CAB_B + R_CAB, Y_C, Z_DOOR0, Z_BELT, "sand", "sand_worn")
		x0, x1 = sorted((sx * (HW - 0.01), sx * (HW - 0.07)))
		p.xprism([(Y_A, Z_BELT), (Y_COWL, Z_BELT), (1.29, Z_RAIL), (1.2, Z_RAIL)], x0, x1, "sand", caps=(True, True))
		p.xprism([(Y_B1, Z_BELT), (Y_B0, Z_BELT), (Y_B0, Z_RAIL), (Y_B1, Z_RAIL)], x0, x1, "sand", caps=(True, True))
		p.xprism([(Y_CAB_B + R_CAB, Z_BELT), (Y_C, Z_BELT), (Y_C, Z_RAIL), (Y_CAB_B + R_CAB, Z_RAIL)], x0, x1, "sand", caps=(True, True))
		stripe(p, sx, Y_B0, Y_B1)
		stripe(p, sx, Y_C, Y_CAB_B + R_CAB)
		# the rear corner, rounded in plan, its inside closed
		corner = arc(HW - R_CAB, Y_CAB_B + R_CAB, R_CAB, -math.pi / 2, 0.0, 4)
		if sx < 0:
			corner = [(-x, y) for (x, y) in reversed(corner)]
		prof = [(o, z) for (z, o) in SIDE] + [(-0.01, Z_BELT + 0.002), (-0.01, Z_RAIL)]
		wrap(p, corner, prof, "sand", m_of=lambda j: "sand_worn" if j < 2 else "sand")
		# the corner's trim inside, over the C pillar to its seal (split at the belt, where the lean starts)
		xt = sx * (HW - 0.09)
		for (za, zb) in ((Z_FLOOR, Z_BELT), (Z_BELT, Z_RAIL + 0.025)):  # (up behind the headliner's edge)
			p.poly([(xt, Y_CAB_B + 0.05, za), (xt, Y_C + 0.05, za), (xt, Y_C + 0.05, zb), (xt, Y_CAB_B + 0.05, zb)], "dash", (-sx, 0, 0))
		# the door seals: the rubber round each opening, inside the doors' frames, from the door's foot
		# to the roof
		s0, s1 = sorted((sx * (HW - 0.085), sx * (HW - 0.07)))
		p.xprism([(Y_A + 0.02, Z_BELT), (Y_A - 0.05, Z_BELT), (1.15, Z_RAIL + 0.02), (1.22, Z_RAIL + 0.02)], s0, s1, "rubber", caps=(True, True))
		p.xprism([(Y_A + 0.02, Z_DOOR0), (Y_A - 0.05, Z_DOOR0), (Y_A - 0.05, Z_BELT), (Y_A + 0.02, Z_BELT)], s0, s1, "rubber", caps=(True, True))
		for (ya, yb) in ((Y_B1 - 0.05, Y_B0 + 0.05), (Y_C - 0.02, Y_C + 0.05)):  # the B pillar's whole inside, the C edge
			for (za, zb) in ((Z_DOOR0, Z_BELT), (Z_BELT, Z_RAIL + 0.02)):  # (split at the belt, where the lean starts)
				p.xprism([(ya, za), (yb, za), (yb, zb), (ya, zb)], s0, s1, "rubber", caps=(True, True))
		for (ya, yb) in ((Y_B0 - 0.02, 1.22), (Y_C - 0.02, Y_B1 + 0.02)):
			p.xprism([(ya, Z_WIN_TOP - 0.04), (yb, Z_WIN_TOP - 0.04), (yb, Z_RAIL + 0.02), (ya, Z_RAIL + 0.02)], s0, s1, "rubber", caps=(True, True))
		# the door hinges' halves on the body
		for z in (1.0, 1.72):
			p.cyl(0.025, 0.12, (sx * (HW + 0.012), Y_A + 0.01, z), "steel", sides=6)
			p.cyl(0.025, 0.12, (sx * (HW + 0.012), Y_B1 - 0.01, z), "steel", sides=6)
	# the back wall (an empty hole at the belt makes its rows break there, so the lean starts at the belt)
	hole = [(-0.8, 0.8, 2.0, 2.48), (0.0, 0.0, Z_BELT, Z_BELT)]
	p.wall(-1, Y_CAB_B, -HW + R_CAB, HW - R_CAB, Z_SILL, Z_RAIL + 0.02, hole, "sand")
	p.wall(1, Y_CAB_B + 0.05, -HW + 0.08, HW - 0.08, Z_FLOOR, Z_RAIL + 0.02, hole, "dash")
	for (x0, x1, z0, z1) in ((-0.8, 0.8, 1.995, 2.005), (-0.8, 0.8, 2.475, 2.485), (-0.805, -0.795, 2.0, 2.48), (0.795, 0.805, 2.0, 2.48)):
		p.bx(x0, x1, Y_CAB_B, Y_CAB_B + 0.05, z0, z1, "rubber")
	p.poly([(-0.8, Y_CAB_B + 0.025, 2.0), (0.8, Y_CAB_B + 0.025, 2.0), (0.8, Y_CAB_B + 0.025, 2.48), (-0.8, Y_CAB_B + 0.025, 2.48)], "glass", (0, -1, 0))
	# the roof: its edge rolled all round, the rear corners as round as the cab's, a flat top
	roof = path_of(arc(HW - R_CAB, Y_CAB_B + R_CAB, R_CAB, -math.pi / 2, 0.0, 3), arc(HW - 0.1, 1.2, 0.1, 0.0, math.pi / 2, 3),
			arc(-HW + 0.1, 1.2, 0.1, math.pi / 2, math.pi, 3), arc(-HW + R_CAB, Y_CAB_B + R_CAB, R_CAB, math.pi, 1.5 * math.pi, 3))
	rings = wrap(p, roof, [(0.0, Z_RAIL), (0.0, Z_RAIL + 0.025), (-0.02, Z_ROOF - 0.032), (-0.055, Z_ROOF - 0.007), (-0.09, Z_ROOF)], "sand", closed=True)
	p.poly([r[-1] for r in rings], "sand", (0, 0, 1))
	# the headliner (matte, no specks), its front edge up behind the windscreen's header
	p.poly([(-HW + 0.07, Y_CAB_B + 0.05, 2.64), (HW - 0.07, Y_CAB_B + 0.05, 2.64), (HW - 0.07, 1.31, 2.64), (-HW + 0.07, 1.31, 2.64)], "liner", (0, 0, -1))
	# the windscreen: two panes (the passenger's, the right, cracked), its frame and wipers
	wb, wt = (Y_COWL + 0.01, Z_BELT + 0.01), (1.29, 2.62)
	for (xa, xb, m) in ((-1.29, 0.0, "glass"), (0.0, 1.29, "glass_cracked")):  # (its side edges inside the pillars)
		img(p, [(xa, wb[0], wb[1]), (xb, wb[0], wb[1]), (xb, wt[0], wt[1]), (xa, wt[0], wt[1])], m)
	p.sweep([(0.0, wb[0] + 0.01, wb[1]), (0.0, wt[0] + 0.01, wt[1])], 0.035, "sand", sides=4)
	p.sweep([(-1.2, wt[0] + 0.01, wt[1] + 0.005), (1.2, wt[0] + 0.01, wt[1] + 0.005)], 0.035, "sand", sides=4)
	p.sweep([(-1.26, wb[0] + 0.02, wb[1]), (1.26, wb[0] + 0.02, wb[1])], 0.03, "rubber", sides=4)
	ln = math.hypot(wb[0] - wt[0], wt[1] - wb[1])
	up = ((wt[0] - wb[0]) / ln, (wt[1] - wb[1]) / ln)  # up the glass
	on = (up[1], -up[0])  # out of the glass
	for x in (-0.55, 0.55):
		wiper = [(x - 0.22 * t / 0.42, wb[0] + up[0] * t + on[0] * 0.02, wb[1] + up[1] * t + on[1] * 0.02) for t in (0.03, 0.42)]
		p.sweep(wiper, 0.012, "black", sides=4)
	p.apply(mk_cab, tumble)
	# the floor (a rubber mat), the firewall under the dash, the cowl and its vent
	p.bx(-HW + 0.07, HW - 0.07, Y_CAB_B, Y_COWL, Z_SILL, Z_FLOOR, "black", skip=("+z",))
	p.poly([(-HW + 0.07, Y_CAB_B + 0.05, Z_FLOOR), (HW - 0.07, Y_CAB_B + 0.05, Z_FLOOR), (HW - 0.07, Y_COWL, Z_FLOOR), (-HW + 0.07, Y_COWL, Z_FLOOR)], "rubber", (0, 0, 1))
	p.poly([(-HW + 0.07, Y_COWL, Z_FLOOR), (HW - 0.07, Y_COWL, Z_FLOOR), (HW - 0.07, Y_COWL, Z_HOOD_B + 0.01), (-HW + 0.07, Y_COWL, Z_HOOD_B + 0.01)], "dash", (0, -1, 0))
	p.poly([(-HW + 0.07, Y_COWL, Z_HOOD_B + 0.01), (HW - 0.07, Y_COWL, Z_HOOD_B + 0.01), (HW - 0.07, Y_COWL + 0.07, Z_HOOD_B + 0.01), (-HW + 0.07, Y_COWL + 0.07, Z_HOOD_B + 0.01)], "sand", (0, 0, 1))
	for k in range(10):
		x = -0.81 + k * 0.18
		p.bx(x - 0.06, x + 0.06, Y_COWL + 0.02, Y_COWL + 0.05, Z_HOOD_B + 0.01, Z_HOOD_B + 0.016, "black")
	p.bevel_box((0.3, 0.03, 0.1), (0.0, 1.32, 2.48), "black", b=0.012)  # the rear-view mirror
	p.cyl(0.07, 0.03, (0.0, 0.2, 2.625), "lens_dead", sides=8)  # the dome lamp

	# --- inside: the seats, the dash, the column (the driver on the left), the console -------------
	for sx in (-1, 1):
		x = sx * 0.6
		p.bevel_box((0.72, 0.66, 0.2), (x, 0.78, 1.25), "seat", b=0.05)
		p.bevel_box((0.7, 0.16, 0.86), (x, 0.36, 1.8), "seat", b=0.05, rx=0.14)
		p.bevel_box((0.36, 0.12, 0.2), (x, 0.28, 2.36), "seat", b=0.04, rx=0.14)
		p.bx(x - 0.3, x + 0.3, 0.5, 1.05, Z_FLOOR, 1.15, "black")
	p.bevel_box((2.3, 0.62, 0.2), (0.0, -0.82, 1.25), "seat", b=0.05)
	p.bevel_box((2.3, 0.16, 0.86), (0.0, -1.27, 1.8), "seat", b=0.05, rx=0.1)
	p.bx(-1.15, 1.15, -1.13, -0.51, Z_FLOOR, 1.15, "black")
	p.bevel_box((0.28, 0.9, 0.3), (0.0, 0.85, 1.1), "dash", b=0.03)  # the console between the front seats
	p.cyl(0.012, 0.42, (0.0, 1.08, 1.4), "steel", rx=0.3, sides=4)
	p.lathe([(0.0, 0.0), (0.035, 0.02), (0.035, 0.06), (0.0, 0.08)], "black", sides=6, center=(0.0, 1.02, 1.6))
	p.bevel_box((2.5, 0.26, 0.32), (0.0, 1.42, 1.69), "dash", b=0.04)
	dx = STEER_HUB[0]
	p.bevel_box((0.46, 0.12, 0.05), (dx, 1.25, 1.875), "dash", b=0.015)  # the cluster's visor, before the driver
	face(p, (dx, 1.287, 1.74), (0, -1, 0), (0, 0, 1), 0.42, 0.2, "gauges")
	for k in range(4):
		p.cyl(0.01, 0.05, (0.21 + k * 0.08, 1.28, 1.64), "steel", axis="y", sides=4)
	# the START button's guard and label (its cap is the button piece), right of the column
	bx0 = -0.27
	p.sweep([(bx0, 1.3, 1.6), (bx0, 1.25, 1.6), (bx0, 1.25, 1.7), (bx0, 1.3, 1.7)], 0.007, "steel", sides=4, caps=(False, False))
	p.bx(bx0 - 0.05, bx0 + 0.05, 1.285, 1.29, 1.575, 1.595, "hazard")
	# the map screen's housing on the dash, turned to the driver; its face carries the map in game
	mk = p.mark()
	p.bevel_box((0.36, 0.2, 0.28), (0.0, 0.0, 0.0), "black", b=0.02)
	face(p, (0.0, -0.103, 0.0), (0, -1, 0), (0, 0, 1), 0.3, 0.22, "crt")
	for (bx_, bz) in ((-0.16, -0.12), (0.16, -0.12), (-0.16, 0.12), (0.16, 0.12)):
		bolt(p, (bx_, -0.103, bz), r=0.009)
	p.place(mk, rz=SCREEN_RZ, t=SCREEN_C)
	p.bx(SCREEN_C[0] - 0.14, SCREEN_C[0] + 0.14, 1.28, 1.44, 1.85, 1.865, "steel")
	# the CB radio under the dash, its cord and mic; the column, pedals, hand brake
	p.bevel_box((0.28, 0.2, 0.08), (0.55, 1.26, 1.49), "black", b=0.012)
	p.sweep([(0.48, 1.17, 1.47), (0.46, 1.08, 1.36), (0.5, 1.12, 1.26)], 0.007, "black", sides=4)
	p.bevel_box((0.06, 0.035, 0.09), (0.5, 1.12, 1.22), "black", b=0.01)
	h = STEER_HUB
	p.sweep([(h[0], h[1] + STEER_DIR[1] * 0.04, h[2] + STEER_DIR[2] * 0.04), (h[0], h[1] + STEER_DIR[1] * 0.34, h[2] + STEER_DIR[2] * 0.34)], 0.04, "black", sides=6)
	for x in (-0.4, -0.58, -0.75):
		p.bx(x - 0.06, x + 0.06, 1.38, 1.4, 1.0, 1.14, "steel")
		p.bx(x - 0.012, x + 0.012, 1.4, 1.52, 1.1, 1.13, "steel")
	p.cyl(0.014, 0.42, (-0.18, 1.12, 1.25), "steel", rx=0.5, sides=4)

	# --- the bed: a steel tray the crew can stand in -----------------------------------------------
	p.bx(-BED_HW, BED_HW, Y_BED_R, Y_BED_F - 0.04, BED_FLOOR - 0.08, BED_FLOOR, "black", skip=("+z",))
	p.poly([(-BED_HW, Y_BED_R, BED_FLOOR), (BED_HW, Y_BED_R, BED_FLOOR), (BED_HW, Y_BED_F - 0.04, BED_FLOOR), (-BED_HW, Y_BED_F - 0.04, BED_FLOOR)], "tread", (0, 0, 1))
	for k in range(5):
		y = (Y_BED_F - 0.17) + ((Y_BED_R + 0.12) - (Y_BED_F - 0.17)) * k / 4
		p.bx(-BED_HW + 0.02, BED_HW - 0.02, y - 0.05, y + 0.05, 1.0, BED_FLOOR - 0.08, "black")  # cross bearers
		for sx in (-1, 1):
			p.bx(sx * RAIL_X - 0.06, sx * RAIL_X + 0.06, y - 0.05, y + 0.05, 0.58, 1.0, "black")  # risers on the rails
	p.bx(-BED_HW, BED_HW, Y_BED_R - 0.07, Y_BED_R - 0.01, 0.95, BED_FLOOR - 0.08, "sand_worn")  # the apron under the gate
	for sx in (-1, 1):
		xo = HW - 0.03
		arch_panel(p, sx * xo, sx * BED_HW, Y_BED_R - 0.06, Y_BED_F, 0.95, BED_RIM, AXR, ARCH_R, "sand", lip="black", ends=True)
		for (ya, yb) in ((AXR + 0.56, Y_BED_F), (Y_BED_R - 0.06, AXR - 0.56)):
			p.poly([(sx * (xo + 0.005), yb, 0.95), (sx * (xo + 0.005), ya, 0.95), (sx * (xo + 0.005), ya, 1.0), (sx * (xo + 0.005), yb, 1.0)], "sand_worn", (sx, 0, 0))
		# the rail along the side's top: a rounded cap
		xc = sx * (HW - 0.12)
		rail = [(xc, Y_BED_R - 0.06), (xc, Y_BED_F)] if sx > 0 else [(xc, Y_BED_F), (xc, Y_BED_R - 0.06)]
		wrap(p, rail, [(-0.1, BED_RIM), (0.095, BED_RIM), (0.115, BED_RIM + 0.022), (0.095, BED_RIM + 0.048), (-0.095, BED_RIM + 0.048), (-0.115, BED_RIM + 0.022)], "sand", ring=True)
		for y in (Y_BED_R + 0.4, (Y_BED_R + Y_BED_F) / 2, Y_BED_F - 0.27):
			p.bx(xc - 0.035, xc + 0.035, y - 0.04, y + 0.04, BED_RIM + 0.047, BED_RIM + 0.05, "dark")
		for y in (Y_BED_R + 0.3, (Y_BED_R + Y_BED_F) / 2, Y_BED_F - 0.3):
			p.bx(sx * BED_HW - (0.02 if sx > 0 else 0.0), sx * BED_HW + (0.0 if sx > 0 else 0.02), y - 0.05, y + 0.05, BED_FLOOR + 0.2, BED_FLOOR + 0.26, "steel")
			p.sweep([(sx * (BED_HW - 0.02), y - 0.04, BED_FLOOR + 0.23), (sx * (BED_HW - 0.07), y - 0.04, BED_FLOOR + 0.18), (sx * (BED_HW - 0.07), y + 0.04, BED_FLOOR + 0.18), (sx * (BED_HW - 0.02), y + 0.04, BED_FLOOR + 0.23)], 0.008, "steel", sides=4)
		stripe(p, sx, Y_BED_F, STRIPE_Y[1], x=xo)
		# the rear corner posts with the tail lamps (the left one cracked dark)
		x0, x1 = sorted((sx * BED_HW, sx * (HW - 0.015)))
		p.bx(x0, x1, Y_BED_R - 0.08, Y_BED_R + 0.04, 0.94, BED_RIM + 0.05, "sand")
		face(p, (sx * 1.21, Y_BED_R - 0.084, 1.44), (0, -1, 0), (0, 0, 1), 0.1, 0.38, "lens_tail" if sx > 0 else "lens_dead")
	p.bx(-BED_HW, BED_HW, Y_BED_F - 0.04, Y_BED_F, 0.95, BED_RIM, "sand")
	p.cyl(0.05, 0.02, (-(HW - 0.02), AXR - 0.95, 1.2), "steel", axis="x", sides=8)  # the fuel filler
	# the four mag strips along the floor; their glow line lights in game when they hold loot
	for x in (-0.66, -0.22, 0.22, 0.66):
		p.bx(x - 0.05, x + 0.05, Y_BED_R + 0.15, Y_BED_F - 0.2, BED_FLOOR, BED_FLOOR + 0.012, "black", skip=("+z",))
		p.poly([(x - 0.05, Y_BED_R + 0.15, BED_FLOOR + 0.012), (x + 0.05, Y_BED_R + 0.15, BED_FLOOR + 0.012), (x + 0.05, Y_BED_F - 0.2, BED_FLOOR + 0.012), (x - 0.05, Y_BED_F - 0.2, BED_FLOOR + 0.012)], "mag", (0, 0, 1))
		p.poly([(x - 0.012, Y_BED_R + 0.17, BED_FLOOR + 0.016), (x + 0.012, Y_BED_R + 0.17, BED_FLOOR + 0.016), (x + 0.012, Y_BED_F - 0.22, BED_FLOOR + 0.016), (x - 0.012, Y_BED_F - 0.22, BED_FLOOR + 0.016)], "maglow", (0, 0, 1))
	# the cab guard: a steel tube frame at the bed's front, braced back to the rails
	gy2 = Y_BED_F - 0.1
	for sx in (-1, 1):
		p.sweep([(sx * 1.1, gy2, BED_RIM + 0.04), (sx * 1.1, gy2, 2.78), (sx * 1.04, gy2, 2.88), (sx * 0.94, gy2, 2.92)], 0.04, "steel", sides=6)
		p.sweep([(sx * 1.1, gy2, 2.45), (sx * 1.15, gy2 - 0.6, BED_RIM + 0.06)], 0.03, "steel", sides=6)
	p.sweep([(-0.94, gy2, 2.92), (0.94, gy2, 2.92)], 0.045, "steel", sides=6)
	p.sweep([(-1.1, gy2, 2.3), (1.1, gy2, 2.3)], 0.03, "steel", sides=6)
	# a jerrycan strapped in the bed's front left corner
	p.bevel_box((0.2, 0.36, 0.5), (-0.9, Y_BED_F - 0.24, BED_FLOOR + 0.25), "can", b=0.03)
	for k in range(3):
		p.bx(-0.96 + k * 0.06 - 0.01, -0.96 + k * 0.06 + 0.01, Y_BED_F - 0.3, Y_BED_F - 0.16, BED_FLOOR + 0.5, BED_FLOOR + 0.53, "steel")
	# the rear bumper (a step, rounded, diamond plate on its top), the hitch, a reverse lamp
	rb = path_of(arc(-1.07, Y_BUMP_R + 0.15, 0.15, math.pi, 1.5 * math.pi, 3), arc(1.07, Y_BUMP_R + 0.15, 0.15, 1.5 * math.pi, 2 * math.pi, 3))
	z0, z1 = BUMP_R_Z
	wrap(p, rb, [(-0.14, z0), (-0.015, z0), (0.0, z0 + 0.015), (0.0, z1 - 0.015), (-0.015, z1), (-0.14, z1)], "black", ring=True,
			m_of=lambda j: "tread" if j == 4 else "black")
	zm = (z0 + z1) / 2
	for sx in (-1, 1):
		face(p, (sx * 0.95, Y_BUMP_R - 0.004, zm), (0, -1, 0), (0, 0, 1), 0.18, 0.1, "hazard", (0.0, 0.0, 0.18, 0.1))
	p.bx(-0.07, 0.07, Y_BUMP_R - 0.06, Y_BUMP_R + 0.2, z0 - 0.06, z0 + 0.01, "steel")
	p.lathe([(0.0, 0.0), (0.03, 0.0), (0.03, 0.05), (0.05, 0.08), (0.0, 0.12)], "steel", sides=8, center=(0.0, Y_BUMP_R - 0.03, z0 + 0.01))
	p.bevel_box((0.12, 0.03, 0.07), (0.62, Y_BUMP_R - 0.005, zm), "lens_white", b=0.008)
	for sx in (-1, 1):
		p.bx(sx * 0.95 - 0.07, sx * 0.95 + 0.07, Y_BED_R - 0.1, Y_BED_R, BED_FLOOR - 0.08, BED_FLOOR, "steel")  # the tailgate's hinges
	# the mud flaps behind both axles
	for sx in (-1, 1):
		x0, x1 = sorted((sx * 0.9, sx * 1.3))
		p.bx(x0, x1, AXF - ARCH - 0.06, AXF - ARCH - 0.035, 0.38, Z_SILL + 0.04, "rubber")
		p.bx(x0, x1, AXR - ARCH_R - 0.06, AXR - ARCH_R - 0.035, 0.38, 0.98, "rubber")
	_truck_boxes(p)
	# design space -> model space
	p.apply(0, lambda q: (q[0], q[1] + DY, q[2]))
	p.boxes = [((c[0], c[1] + DY, c[2]), s, r) for (c, s, r) in p.boxes]
	p.meta["points"] = truck_points()


def truck_points():
	"""Named points (design space, moved by DY) turned to Godot space for the manifest."""
	pts = {
		"wheel_fl": (-TRACK, AXF, WR), "wheel_fr": (TRACK, AXF, WR), "wheel_rl": (-TRACK, AXR, WR), "wheel_rr": (TRACK, AXR, WR),
		"seat": (-0.6, 0.78, 1.35), "seat_front": (0.6, 0.78, 1.35), "seat_rear_l": (-0.55, -0.8, 1.35), "seat_rear_r": (0.55, -0.8, 1.35),
		"eye": (-0.6, 0.62, 2.25), "steer": STEER_HUB, "screen": _screen_point(),
		"button": (-0.27, 1.29, 1.65), "tailgate": (0.0, Y_BED_R, BED_FLOOR), "steps": (0.0, Y_BED_R - GATE_H, BED_FLOOR - 0.06),
		"door_fl": (-HW, Y_A - 0.01, 0.0), "door_fr": (HW, Y_A - 0.01, 0.0), "door_rl": (-HW, Y_B1 - 0.01, 0.0), "door_rr": (HW, Y_B1 - 0.01, 0.0),
		"headlight_l": (-0.83, Y_GRILLE + 0.04, 1.39), "headlight_r": (0.83, Y_GRILLE + 0.04, 1.39),
		"tail_l": (-1.21, Y_BED_R - 0.09, 1.44), "tail_r": (1.21, Y_BED_R - 0.09, 1.44), "reverse": (0.62, Y_BUMP_R - 0.03, sum(BUMP_R_Z) / 2),
		"exhaust": (1.27, -1.72, 0.62), "snorkel": (-1.27, 1.45, 3.03),
		"bed_min": (-BED_HW, Y_BED_R, BED_FLOOR), "bed_max": (BED_HW, Y_BED_F - 0.04, BED_FLOOR + 2.5),
		"cab_min": (-HW + 0.07, Y_CAB_B + 0.05, Z_FLOOR - 0.1), "cab_max": (HW - 0.07, Y_A, 2.64),
		"bumper": (0.0, Y_BUMP_R + 0.07, BUMP_R_Z[1]), "running_l": (-1.3, 0.0, 0.5), "running_r": (1.3, 0.0, 0.5),
		"front": (0.0, Y_BUMP_F, 0.8), "rear": (0.0, Y_BUMP_R, sum(BUMP_R_Z) / 2),
	}
	return {k: [_r(x) for x in _to_g((v[0], v[1] + DY, v[2]))] for k, v in pts.items()}


def _truck_boxes(p):
	"""The hull's collision boxes (design space), for the driving step (and to stand on in the look round)."""
	p.solid(-HW, HW, Y_CAB_B, Y_COWL, Z_SILL, Z_ROOF)
	p.solid(-HW, HW, Y_COWL, Y_GRILLE, Z_SILL, Z_HOOD_B)
	p.solid(-1.32, 1.32, Y_GRILLE, Y_BUMP_F, 0.64, 1.0)
	p.solid(-BED_HW, BED_HW, Y_BED_R, Y_BED_F, BED_FLOOR - 0.08, BED_FLOOR)
	for sx in (-1, 1):
		p.solid(min(sx * BED_HW, sx * HW), max(sx * BED_HW, sx * HW), Y_BED_R - 0.08, Y_BED_F, 0.95, BED_RIM + 0.05)
	p.solid(-BED_HW, BED_HW, Y_BED_F - 0.04, Y_BED_F, 0.95, BED_RIM)
	p.solid(-1.15, 1.15, Y_BED_F - 0.14, Y_BED_F - 0.06, BED_RIM, 2.96)
	p.solid(-1.22, 1.22, Y_BUMP_R, Y_BED_R - 0.08, BUMP_R_Z[0], BUMP_R_Z[1])
	p.solid(-0.66, 0.66, Y_BED_R - 0.08, 3.4, RAIL_Z - 0.11, 0.95)


# =====================================================================================
# The doors: four pieces, hinged on their front edges (the hand grab swings them open)
# =====================================================================================

def _door(p, sx, front):
	"""A door in design space (closed), then moved so the piece's origin is its hinge line's foot."""
	y0 = (Y_A - 0.01) if front else (Y_B1 - 0.01)
	y1 = (Y_B0 + 0.01) if front else (Y_C + 0.01)
	xo = sx * HW
	# the lower door: its skin following the side's profile (mud on its foot), the inner card, the arm
	# rest, the inner handle
	side_skin(p, sx, y0, y1, Z_DOOR0 + 0.01, Z_BELT, "sand", "sand_worn")
	ci = sx * (HW - 0.115)
	p.bx(min(ci, sx * (HW - 0.085)), max(ci, sx * (HW - 0.085)), y1 + 0.04, y0 - 0.04, Z_DOOR0 + 0.08, Z_BELT - 0.03, "dash")
	p.bevel_box((0.07, abs(y0 - y1) * 0.5, 0.06), (sx * (HW - 0.15), (y0 + y1) / 2, 1.42), "dash", b=0.015)
	p.bx(min(sx * (HW - 0.13), sx * (HW - 0.115)), max(sx * (HW - 0.13), sx * (HW - 0.115)), y1 + 0.12, y1 + 0.24, 1.56, 1.6, "steel")
	stripe(p, sx, y0, y1)
	# the window (leaned in with the cab): a thin frame (the front door's front post raked along the A
	# pillar), its glass, the seal
	mk = p.mark()
	wf, wr = y0 - 0.03, y1 + 0.03
	xm = sx * (HW - 0.035)
	top = Z_WIN_TOP
	yf_top = 1.2 if front else wf  # the front post's top

	def yf(z):
		return wf + (z - Z_BELT) * (yf_top - wf) / (top - Z_BELT)

	p.sweep([(xm, wr, Z_BELT), (xm, wr, top)], 0.03, "sand", sides=4)
	p.sweep([(xm, wr, top), (xm, yf_top, top)], 0.03, "sand", sides=4)
	p.sweep([(xm, yf_top, top), (xm, wf, Z_BELT)], 0.03, "sand", sides=4)
	zg0, zg1 = Z_BELT - 0.01, top - 0.015
	pane = [(xm, wr + 0.02, zg0), (xm, yf(zg0) - 0.02, zg0), (xm, yf(zg1) - 0.02, zg1), (xm, wr + 0.02, zg1)]
	p.poly(pane, "glass_cracked" if (not front and sx < 0) else "glass", (sx, 0, 0))
	p.sweep([(sx * (HW - 0.03), wr, Z_BELT + 0.005), (sx * (HW - 0.03), wf, Z_BELT + 0.005)], 0.018, "rubber", sides=4)
	p.apply(mk, tumble)
	# the outer handle and its lock, the hinge halves on the door
	hy = y1 + 0.2
	p.bevel_box((0.035, 0.2, 0.05), (xo + sx * 0.02, hy, 1.72), "steel", b=0.01)
	p.cyl(0.014, 0.02, (xo + sx * 0.01, hy - 0.14, 1.72), "steel", axis="x", sides=6)
	for z in (1.0, 1.72):
		p.bx(min(xo, xo + sx * 0.02), max(xo, xo + sx * 0.02), y0 - 0.1, y0 - 0.02, z - 0.04, z + 0.04, "steel")
	if front:
		# the mirror on its arm off the door's front top corner
		p.sweep([(xo - sx * 0.04, y0 - 0.12, 1.94), (xo + sx * 0.11, y0 - 0.1, 1.98), (xo + sx * 0.17, y0 - 0.1, 2.05)], 0.015, "black", sides=4)
		p.bevel_box((0.1, 0.06, 0.3), (xo + sx * 0.2, y0 - 0.1, 2.13), "plastic", b=0.015)
		p.poly([(xo + sx * 0.2 - 0.04, y0 - 0.131, 2.0), (xo + sx * 0.2 + 0.04, y0 - 0.131, 2.0), (xo + sx * 0.2 + 0.04, y0 - 0.131, 2.26), (xo + sx * 0.2 - 0.04, y0 - 0.131, 2.26)], "glass", (0, -1, 0))
	# the piece's origin on the hinge line's foot (Godot: the door turns about Y there)
	p.apply(0, lambda q: (q[0] - xo, q[1] - y0, q[2]))


@piece("truck", note="the front left (the driver's) door; the origin on its hinge line's foot")
def door_fl(p):
	_door(p, -1, True)


@piece("truck", note="the front right door; the origin on its hinge line's foot")
def door_fr(p):
	_door(p, 1, True)


@piece("truck", note="the rear left door; the origin on its hinge line's foot")
def door_rl(p):
	_door(p, -1, False)


@piece("truck", note="the rear right door; the origin on its hinge line's foot")
def door_rr(p):
	_door(p, 1, False)


# =====================================================================================
# The wheels, the steering wheel, the tailgate, the START button
# =====================================================================================

@piece("truck", note="the hub's centre at the origin, its axle along X; the outer face at +X")
def wheel(p):
	# authored at the round-1 size (lugs' middle at 0.462, 0.31 wide), then scaled to WR and TW
	tyre = [(0.31, -0.135), (0.39, -0.155), (0.43, -0.145), (0.45, -0.115), (0.45, 0.115), (0.43, 0.145), (0.39, 0.155), (0.31, 0.135)]
	p.lathe(tyre, "rubber", sides=14, ry=math.pi / 2, caps=(False, False))
	# the tread's lugs: two rows of chunky blocks, offset half a pitch
	n = 12
	for row, xo in ((0, -0.06), (1, 0.06)):
		for k in range(n):
			a = 2 * math.pi * (k + 0.5 * row) / n
			c = (xo, math.cos(a) * 0.462, math.sin(a) * 0.462)
			p.box((0.1, 0.075, 0.03), c, "rubber", rx=a - math.pi / 2, skip=("-z",))
	# the dished steel rim, its hub and six lug nuts, the dark holes in its face
	rim = [(0.31, 0.135), (0.3, 0.1), (0.24, 0.07), (0.19, 0.1), (0.1, 0.11), (0.07, 0.12)]
	p.lathe(rim, "rim", sides=12, ry=math.pi / 2, caps=(False, False))
	p.cyl(0.31, 0.27, (0.0, 0.0, 0.0), "black", axis="x", sides=12, caps=False)
	p.cyl(0.3, 0.004, (-0.12, 0.0, 0.0), "black", axis="x", sides=12)
	p.cyl(0.07, 0.05, (0.135, 0.0, 0.0), "rust", axis="x", sides=8)
	for k in range(6):
		a = 2 * math.pi * k / 6
		p.cyl(0.016, 0.03, (0.12, math.cos(a) * 0.1, math.sin(a) * 0.1), "steel", axis="x", sides=6)
		a2 = a + math.pi / 6
		cy, cz = math.cos(a2) * 0.145, math.sin(a2) * 0.145
		p.poly([(0.112, cy + 0.022 * math.cos(a2 + q * math.pi / 2), cz + 0.022 * math.sin(a2 + q * math.pi / 2)) for q in range(4)], "dark", (1, 0, 0))
	kr, kx = (WR - 0.01) / 0.462, TW / 0.31  # the lugs' outer edge a hair past WR (they bite the ground)
	p.apply(0, lambda q: (q[0] * kx, q[1] * kr, q[2] * kr))


@piece("truck", note="the wheel's hub at the origin, its axis along Blender +Y (toward the dash)")
def steer(p):
	n = 14
	ring = [(0.2 * math.cos(2 * math.pi * k / n), 0.0, 0.2 * math.sin(2 * math.pi * k / n)) for k in range(n + 1)]
	p.sweep(ring, 0.018, "black", sides=5, caps=(False, False))
	for a in (math.pi / 2, math.pi * 7 / 6, math.pi * 11 / 6):
		mid = (0.1 * math.cos(a), 0.012, 0.1 * math.sin(a))
		p.box((0.19, 0.012, 0.03), mid, "steel", ry=-a)
	p.cyl(0.045, 0.05, (0.0, 0.02, 0.0), "black", axis="y", sides=8)
	for a0 in (0.3, 2.6):
		wrap_ = [(0.2 * math.cos(a0 + t * 0.12), 0.0, 0.2 * math.sin(a0 + t * 0.12)) for t in range(5)]
		p.sweep(wrap_, 0.022, "rubber", sides=5, caps=(False, False))
	p.apply(0, lambda q: (q[0] * 1.3, q[1] * 1.3, q[2] * 1.3))


@piece("truck", note="the origin on the hinge line's middle; closed upright, the outside at -Y")
def tailgate(p):
	W, T = BED_HW - 0.01, 0.06
	p.bx(-W, W, -T, 0.0, 0.0, GATE_H, "sand")
	p.bevel_box((2 * W + 0.02, T + 0.02, 0.04), (0.0, -T / 2, GATE_H + 0.02), "sand_worn", b=0.015)
	p.poly([(-W, -T - 0.002, 0.0), (W, -T - 0.002, 0.0), (W, -T - 0.002, 0.1), (-W, -T - 0.002, 0.1)], "sand_worn", (0, -1, 0))
	# the chevron band, the stencil, the latch handle, latch bolts and hinge knuckles
	face(p, (0.0, -T - 0.003, GATE_H - 0.08), (0, -1, 0), (0, 0, 1), 2 * W - 0.08, 0.1, "hazard", (0.0, 0.0, 2.2, 0.1))
	face(p, (0.0, -T - 0.004, 0.25), (0, -1, 0), (0, 0, 1), 1.6, 0.24, "stencil_tailgate")
	p.bx(-0.15, 0.15, -T - 0.006, -T, 0.39, 0.415, "steel")
	p.bx(-0.12, 0.12, -T - 0.014, -T - 0.006, 0.4, 0.44, "steel")
	for sx in (-1, 1):
		p.cyl(0.018, 0.07, (sx * (W + 0.025), -T / 2, GATE_H - 0.08), "steel", axis="x", sides=6)
		p.cyl(0.026, 0.14, (sx * 0.95, -0.02, 0.0), "steel", axis="x", sides=6)
	# the inside face: pressed ribs
	for k in range(3):
		z = 0.1 + k * 0.13
		p.bx(-W + 0.1, W - 0.1, 0.0, 0.01, z, z + 0.04, "sand_worn")


@piece("truck", note="the fold-down steps under the tailgate's end (shown while it's down); the origin under its end")
def steps(p):
	"""The steps under the tailgate (the user, 2026-11-05: "steps under the tailgate"): a steel stair hung
	from the tailgate's end when it's down, its treads at 0.92, 0.62 and 0.30 m each a step back, its feet
	on the ground; the chains that hold the tailgate flat, from the bed's rim corners."""
	y0, z0 = Y_BED_R - GATE_H, BED_FLOOR - 0.06
	W = 0.42
	RUN = 1.6  # the treads' noses on the line from the tailgate's top at its end to the ground RUN behind
	for sx in (-1, 1):
		p.sweep([(sx * W, y0 - 0.02, z0 - 0.02), (sx * W, y0 - RUN + 0.05, 0.03)], 0.03, "black", sides=4)
		p.bx(sx * W - 0.045, sx * W + 0.045, y0 - RUN - 0.05, y0 - RUN + 0.07, 0.0, 0.035, "rubber")
		chain(p, (sx * 1.1, Y_BED_R + 0.02, BED_RIM - 0.03), (sx * 1.1, y0 + 0.03, BED_FLOOR + 0.02), 0.05, 9)
		p.bx(sx * 1.1 - 0.02, sx * 1.1 + 0.02, y0 + 0.02, y0 + 0.06, BED_FLOOR - 0.01, BED_FLOOR + 0.03, "steel")
	for (top, a, b) in ((0.92, 0.22, 0.52), (0.62, 0.62, 0.92), (0.30, 1.05, 1.35)):
		ya, yb = y0 - a, y0 - b
		p.bx(-W + 0.02, W - 0.02, yb, ya, top - 0.035, top, "tread")
		p.bx(-W + 0.02, W - 0.02, yb - 0.015, yb, top - 0.07, top, "black")  # the nosing lip
		for sx in (-1, 1):
			p.bx(sx * (W - 0.03) - 0.012, sx * (W - 0.03) + 0.012, yb, ya, top - 0.09, top - 0.035, "black")  # brackets
	p.cyl(0.026, 2 * W + 0.08, (0.0, y0 - 0.02, z0 - 0.01), "steel", axis="x", sides=8)  # the hinge
	p.apply(0, lambda q: (q[0], q[1] - y0, q[2] - z0))


@piece("truck", note="the START button's red cap; the origin at its foot, pressed along Blender +Y")
def button(p):
	p.cyl(0.022, 0.012, (0.0, -0.006, 0.0), "steel", axis="y", sides=8)
	p.lathe([(0.0, 0.0), (0.018, 0.0), (0.018, 0.012), (0.012, 0.018), (0.0, 0.02)], "can", sides=8, rx=math.pi / 2, center=(0.0, -0.012, 0.0))
	p.apply(0, lambda q: (q[0] * 1.3, q[1] * 1.3, q[2] * 1.3))
