# The crew's truck, the salvage beacon and the exit marker (METRO 9 M9): the geometry header.
# A frozen copy of M4b's builder header (assets/models/metro9/props/_src/metro9_props.py, itself a copy
# of M4a's kit header; read only: its later changes never reach this file): the Piece class with its
# faces, prisms, bevel boxes, cylinders, sweeps and lathes, metric UVs by default, ("img", ...) and
# ("m", ...) UV specs. Run only in a background Blender (run_truck.py).
#
# CONVENTIONS (Blender: metres, Z up; Godot (x, y, z) = Blender (x, z, -y)):
#   * the truck: its nose at Blender +Y (Godot -Z, Godot's forward), the driver on its left (Blender -X),
#     the origin on the ground under the middle of the wheelbase.
#   * a wheel: the hub's centre at the origin, its axle along X.
#   * the tailgate: the origin on its hinge line (the bed floor's rear edge, its middle), closed upright.
#   * the steering wheel: the origin on the column's top, the wheel's plane facing the driver.
#   * the beacon: the origin on the wall's face at the mounting plate's centre; it stands out along
#     Blender -Y (Godot +Z), the wall at y = 0.
#   * the exit post and boom: the origin on the road under the base, the boom's pivot over it.
import bpy, math, os, json, random

ROOT = r"E:\Godot Games\scrap-shift"
OUT = os.path.join(ROOT, "assets", "models", "vehicles", "truck")
SRC = os.path.join(OUT, "_src")
BLEND = os.path.join(SRC, "truck.blend")
MANIFEST = os.path.join(OUT, "truck.json")
os.makedirs(OUT, exist_ok=True)
PREFIX = "trk_"
SCENE = "truck"

PAL = {}


def mat(name):
	m = bpy.data.materials.get(PREFIX + name)
	if not m:
		m = bpy.data.materials.new(PREFIX + name)
		m.use_nodes = True
	return m


def rot(p, rx=0.0, ry=0.0, rz=0.0):
	x, y, z = p
	if rx:
		c, s = math.cos(rx), math.sin(rx)
		y, z = y * c - z * s, y * s + z * c
	if ry:
		c, s = math.cos(ry), math.sin(ry)
		x, z = x * c + z * s, -x * s + z * c
	if rz:
		c, s = math.cos(rz), math.sin(rz)
		x, y = x * c - y * s, x * s + y * c
	return (x, y, z)


def _cross(a, b):
	return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _sub(a, b):
	return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _add3(a, b):
	return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _mul(a, k):
	return (a[0] * k, a[1] * k, a[2] * k)


def _len(a):
	return math.sqrt(_dot(a, a))


def _norm(a):
	l = _len(a) or 1.0
	return (a[0] / l, a[1] / l, a[2] / l)


def _lerp(a, b, t):
	return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))


def _newell(pts):
	n = [0.0, 0.0, 0.0]
	for i in range(len(pts)):
		a, b = pts[i], pts[(i + 1) % len(pts)]
		n[0] += (a[1] - b[1]) * (a[2] + b[2])
		n[1] += (a[2] - b[2]) * (a[0] + b[0])
		n[2] += (a[0] - b[0]) * (a[1] + b[1])
	return tuple(n)


CUT_X = (0.75, 1.5, 2.25)
CUT_Z = (0.9, 1.75, 2.6, 3.5)
CUT_MIN = 2.2


def _cuts(a, b, lines):
	lo, hi = min(a, b), max(a, b)
	pts = [lo]
	if hi - lo > CUT_MIN:
		pts += [c for c in lines if lo + 0.05 < c < hi - 0.05]
	pts.append(hi)
	return pts


def _even(a, b, step=1.8):
	"""Cut points at most `step` apart over a..b (big faces: the PSX warp stays mild)."""
	n = max(1, int(math.ceil(abs(b - a) / step - 1e-6)))
	return [a + (b - a) * i / n for i in range(n + 1)]


AX = {"x": 0, "y": 1, "z": 2}


def rng(seed):
	return random.Random(seed)


class Piece:
	def __init__(self, name):
		self.name = name
		self.verts, self.faces, self.mats, self.mat_names = [], [], [], []
		self.uv = []
		self.groups = []
		self.boxes = []   # collision: (centre, size, (rx, ry, rz)) in Blender space
		self.caps = []    # unseen climb caps, the same form
		self.meta = {}

	def _mi(self, m):
		if m not in self.mat_names:
			self.mat_names.append(m)
		return self.mat_names.index(m)

	def _add(self, pts, faces, m, uv=None, closed=True, uvs=None):
		base = len(self.verts)
		self.verts.extend(pts)
		mi = self._mi(m)
		f0 = len(self.faces)
		for k, f in enumerate(faces):
			self.faces.append(tuple(base + i for i in f))
			self.mats.append(mi)
			self.uv.append(uvs[k] if uvs is not None else uv)
		self.groups.append((f0, len(self.faces), closed))

	# --- transforms ----------------------------------------------------------------------------
	def mark(self):
		return len(self.verts)

	def apply(self, mark, fn):
		"""Moves every vertex made since `mark` through fn(p) -> p."""
		for i in range(mark, len(self.verts)):
			self.verts[i] = tuple(fn(self.verts[i]))

	def place(self, mark, rx=0.0, ry=0.0, rz=0.0, t=(0.0, 0.0, 0.0), about=(0.0, 0.0, 0.0)):
		"""Turns everything since `mark` about `about` (x, then y, then z), then moves it by t."""
		def fn(p):
			q = rot(_sub(p, about), rx, ry, rz)
			return _add3(_add3(q, about), t)
		self.apply(mark, fn)

	# --- faces ---------------------------------------------------------------------------------
	def poly(self, pts, m, facing=None, uv=None):
		"""One planar polygon; wound along `facing` when given (else as listed, counter-clockwise
		seen from its front). uv: None (metric projection), ("img", [...]) or ("m", [...])."""
		pts = list(pts)
		if facing is not None and _dot(_newell(pts), facing) < 0:
			pts.reverse()
			if isinstance(uv, tuple) and uv[0] in ("img", "m"):
				uv = (uv[0], list(reversed(uv[1])))
		self._add(pts, [tuple(range(len(pts)))], m, uv, closed=False)

	def quad(self, a, b, c, d, m, uv=None):
		self.poly([a, b, c, d], m, None, uv)

	def tri(self, a, b, c, m, uv=None):
		self.poly([a, b, c], m, None, uv)

	def rect(self, axis, sign, c, u0, u1, v0, v1, m, uv=None, cut=True):
		"""M4a's axis-aligned rectangle (cut at the standard lines when long)."""
		if u1 - u0 < 1e-5 or v1 - v0 < 1e-5:
			return
		us = _cuts(u0, u1, CUT_X) if cut else [u0, u1]
		vs = _cuts(v0, v1, CUT_Z if axis != "z" else CUT_X) if cut else [v0, v1]
		facing = [0, 0, 0]
		facing[AX[axis]] = sign
		for i in range(len(us) - 1):
			for j in range(len(vs) - 1):
				pts = []
				for (u, v) in ((us[i], vs[j]), (us[i + 1], vs[j]), (us[i + 1], vs[j + 1]), (us[i], vs[j + 1])):
					if axis == "y":
						pts.append((u, c, v))
					elif axis == "x":
						pts.append((c, u, v))
					else:
						pts.append((u, v, c))
				self.poly(pts, m, facing, uv)

	def grid(self, origin, ax, ay, w, h, m, nu=1, nv=1, lift=None, uv=None):
		"""A flat or lifted sheet: origin + ax * s + ay * t over w x h, nu x nv cells; `lift(s, t)`
		adds a height along ax x ay. Metric UVs from the sheet's own axes unless `uv` is "proj"."""
		n = _norm(_cross(ax, ay))
		P = {}
		for i in range(nu + 1):
			for j in range(nv + 1):
				s, t = w * i / nu, h * j / nv
				p = _add3(_add3(origin, _mul(ax, s)), _mul(ay, t))
				if lift:
					p = _add3(p, _mul(n, lift(s, t)))
				P[(i, j)] = p
		for i in range(nu):
			for j in range(nv):
				q = [P[(i, j)], P[(i + 1, j)], P[(i + 1, j + 1)], P[(i, j + 1)]]
				if uv == "proj":
					self.quad(*q, m)
				else:
					s0, s1, t0, t1 = w * i / nu, w * (i + 1) / nu, h * j / nv, h * (j + 1) / nv
					self.quad(*q, m, ("m", [(s0, t0), (s1, t0), (s1, t1), (s0, t1)]))

	def card(self, c, ax, ay, w, h, m, rect, nu=1, nv=1, bow=0.0, anchor="center", flip=False, sag=0.0):
		"""An atlas card: the image rect (u0, v0, u1, v1; image space, v from the top) on a w x h
		quad spanned by the unit axes ax (right) and ay (up), cut nu x nv; `anchor` 'center' or
		'bottom' (c is the bottom edge's middle); `bow` pushes the card's middle column out along its
		normal, `sag` pulls its lower edge out (hanging moss swinging off a ledge)."""
		ax, ay = _norm(ax), _norm(ay)
		n = _norm(_cross(ax, ay))
		o = _sub(c, _mul(ax, w / 2))
		if anchor == "center":
			o = _sub(o, _mul(ay, h / 2))
		u0, v0, u1, v1 = rect
		if flip:
			u0, u1 = u1, u0
		P, I = {}, {}
		for i in range(nu + 1):
			for j in range(nv + 1):
				fs, ft = i / nu, j / nv
				p = _add3(_add3(o, _mul(ax, w * fs)), _mul(ay, h * ft))
				p = _add3(p, _mul(n, bow * (1 - (2 * fs - 1) ** 2) + sag * (1 - ft) ** 2))
				P[(i, j)] = p
				I[(i, j)] = (u0 + (u1 - u0) * fs, v1 - (v1 - v0) * ft)
		for i in range(nu):
			for j in range(nv):
				ks = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
				self.poly([P[k] for k in ks], m, None, ("img", [I[k] for k in ks]))

	def wall(self, sign, y, x0, x1, z0, z1, holes, m, uv=None):
		zs = sorted(set([z0, z1] + [h[2] for h in holes] + [h[3] for h in holes]))
		zs = [z for z in zs if z0 - 1e-6 <= z <= z1 + 1e-6]
		for j in range(len(zs) - 1):
			za, zb = zs[j], zs[j + 1]
			if zb - za < 1e-5:
				continue
			zm = (za + zb) / 2
			blocks = sorted([(h[0], h[1]) for h in holes if h[2] < zm < h[3]])
			at = x0
			for (hx0, hx1) in blocks:
				if hx0 > at + 1e-5:
					self.rect("y", sign, y, at, min(hx0, x1), za, zb, m, uv)
				at = max(at, hx1)
			if x1 > at + 1e-5:
				self.rect("y", sign, y, at, x1, za, zb, m, uv)

	# --- solids --------------------------------------------------------------------------------
	def box(self, size, center, m, rx=0.0, ry=0.0, rz=0.0, uv=None, skip=()):
		sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
		pts = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
				(-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
		named = {"-z": (0, 3, 2, 1), "+z": (4, 5, 6, 7), "-y": (0, 1, 5, 4), "+x": (1, 2, 6, 5), "+y": (2, 3, 7, 6), "-x": (3, 0, 4, 7)}
		faces = [f for k, f in named.items() if k not in skip]
		pts = [rot(p, rx, ry, rz) for p in pts]
		cx, cy, cz = center
		self._add([(x + cx, y + cy, z + cz) for x, y, z in pts], faces, m, uv, closed=not skip)

	def bx(self, x0, x1, y0, y1, z0, z1, m, uv=None, skip=()):
		self.box((x1 - x0, y1 - y0, z1 - z0), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), m, uv=uv, skip=skip)

	def bevel_box(self, size, center, m, b=0.02, rx=0.0, ry=0.0, rz=0.0, skip_bottom=False):
		"""A box with its 12 edges chamfered by b (26 faces): crates, slabs, castings."""
		sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
		b = min(b, sx * 0.45, sy * 0.45, sz * 0.45)
		pts = []
		idx = {}
		for ix in (-1, 1):
			for iy in (-1, 1):
				for iz in (-1, 1):
					for k in range(3):
						# vertex k lies on the face of axis k, inset by b along the other two axes
						sg = (ix, iy, iz)
						p = [ix * sx, iy * sy, iz * sz]
						for j in range(3):
							if j != k:
								p[j] -= sg[j] * b
						idx[(ix, iy, iz, k)] = len(pts)
						pts.append(tuple(p))
		pts = [rot(p, rx, ry, rz) for p in pts]
		cx, cy, cz = center
		pts = [(x + cx, y + cy, z + cz) for x, y, z in pts]
		base = len(self.verts)
		faces = []
		# the six main faces (each from its corners' vertex that moved along that face's normal axis)
		for axis in range(3):
			for sgn in (-1, 1):
				if skip_bottom and axis == 2 and sgn == -1:
					continue
				cs = []
				for a in (-1, 1):
					for c2 in (-1, 1):
						key = [0, 0, 0]
						key[axis] = sgn
						o = [k for k in range(3) if k != axis]
						key[o[0]], key[o[1]] = a, c2
						cs.append(idx[(key[0], key[1], key[2], axis)])
				# order: (a-,c-), (a+,c-), (a+,c+), (a-,c+)
				f = [cs[0], cs[2], cs[3], cs[1]]
				faces.append(f)
		# the 12 edge chamfers
		for axis in range(3):
			o = [k for k in range(3) if k != axis]
			for a in (-1, 1):
				for c2 in (-1, 1):
					q = []
					for e in (-1, 1):
						key = [0, 0, 0]
						key[axis] = e
						key[o[0]], key[o[1]] = a, c2
						q.append((idx[(key[0], key[1], key[2], o[0])], idx[(key[0], key[1], key[2], o[1])]))
					faces.append([q[0][0], q[0][1], q[1][1], q[1][0]])
		# the 8 corner triangles
		for ix in (-1, 1):
			for iy in (-1, 1):
				for iz in (-1, 1):
					if skip_bottom and iz == -1:
						pass
					faces.append([idx[(ix, iy, iz, 0)], idx[(ix, iy, iz, 1)], idx[(ix, iy, iz, 2)]])
		self.verts.extend(pts)
		mi = self._mi(m)
		c0 = (cx, cy, cz)
		f0 = len(self.faces)
		for f in faces:
			ps = [pts[i] for i in f]
			fc = tuple(sum(p[k] for p in ps) / len(ps) for k in range(3))
			if _dot(_newell(ps), _sub(fc, c0)) < 0:
				f = list(reversed(f))
			self.faces.append(tuple(base + i for i in f))
			self.mats.append(mi)
			self.uv.append(None)
		self.groups.append((f0, len(self.faces), not skip_bottom))

	def _prism(self, outline, a0, a1, axis, m, caps, open_edges, uv):
		n = len(outline)
		area = sum(outline[i][0] * outline[(i + 1) % n][1] - outline[(i + 1) % n][0] * outline[i][1] for i in range(n)) / 2
		ccw = area > 0
		k = AX[axis]
		others = [i for i in range(3) if i != k]
		def P(p, a):
			out = [0.0, 0.0, 0.0]
			out[k] = a
			out[others[0]], out[others[1]] = p[0], p[1]
			return tuple(out)
		for i in range(n):
			if i in open_edges:
				continue
			j = (i + 1) % n
			e = (outline[j][0] - outline[i][0], outline[j][1] - outline[i][1])
			o2 = (e[1], -e[0]) if ccw else (-e[1], e[0])
			facing = [0.0, 0.0, 0.0]
			facing[others[0]], facing[others[1]] = o2
			self.poly([P(outline[i], a0), P(outline[j], a0), P(outline[j], a1), P(outline[i], a1)], m, facing, uv)
		if caps[0]:
			f = [0.0, 0.0, 0.0]
			f[k] = -1.0 if a1 > a0 else 1.0
			self.poly([P(o, a0) for o in outline], m, f, uv)
		if caps[1]:
			f = [0.0, 0.0, 0.0]
			f[k] = 1.0 if a1 > a0 else -1.0
			self.poly([P(o, a1) for o in outline], m, f, uv)

	def xprism(self, outline_yz, x0, x1, m, caps=(False, False), open_edges=(), uv=None):
		self._prism(list(outline_yz), x0, x1, "x", m, caps, list(open_edges), uv)

	def yprism(self, outline_xz, y0, y1, m, caps=(True, True), open_edges=(), uv=None):
		self._prism(list(outline_xz), y0, y1, "y", m, caps, list(open_edges), uv)

	def zprism(self, outline_xy, z0, z1, m, caps=(True, True), open_edges=(), uv=None):
		self._prism(list(outline_xy), z0, z1, "z", m, caps, list(open_edges), uv)

	def plate(self, outline_xy, thick, m, top_m=None, caps=(True, True)):
		"""A flat plate of `thick` under z = 0 with an (x, y) outline (slabs, boards, sheets); turn it
		into place with mark() / place(). Its top face can take another material."""
		mk = self.mark()
		self.zprism(outline_xy, -thick, 0.0, m, caps=(caps[0], False))
		if caps[1]:
			self.poly([(x, y, 0.0) for (x, y) in outline_xy], top_m or m, (0, 0, 1))
		return mk

	def cyl(self, r, length, center, m, axis="z", sides=8, r2=None, rx=0.0, ry=0.0, rz=0.0, caps=True, uv=None):
		r2 = r if r2 is None else r2
		pts = []
		for end, rr in ((-length / 2, r), (length / 2, r2)):
			for i in range(sides):
				a = 2 * math.pi * i / sides
				u, v = math.cos(a) * rr, math.sin(a) * rr
				pts.append({"z": (u, v, end), "x": (end, u, v), "y": (u, end, -v)}[axis])
		pts = [rot(p, rx, ry, rz) for p in pts]
		cx, cy, cz = center
		faces = []
		for i in range(sides):
			j = (i + 1) % sides
			faces.append((i, j, sides + j, sides + i))
		if caps:
			faces.append(tuple(reversed(range(sides))))
			faces.append(tuple(range(sides, 2 * sides)))
		self._add([(x + cx, y + cy, z + cz) for x, y, z in pts], faces, m, uv, closed=caps)
		# outward winding for any axis/rotation: fix faces by their centre
		self._fix_winding(len(self.faces) - len(faces), (cx, cy, cz))

	def _fix_winding(self, f0, center):
		for fi in range(f0, len(self.faces)):
			f = self.faces[fi]
			ps = [self.verts[i] for i in f]
			fc = tuple(sum(p[k] for p in ps) / len(ps) for k in range(3))
			d = _sub(fc, center)
			if _len(d) > 1e-6 and _dot(_newell(ps), d) < 0:
				self.faces[fi] = tuple(reversed(f))
				uv = self.uv[fi]
				if isinstance(uv, tuple) and uv[0] in ("img", "m"):
					self.uv[fi] = (uv[0], list(reversed(uv[1])))

	def sweep(self, path, radii, m, sides=6, caps=(True, True), uv_k=1.0, flat=None):
		"""A tube along a polyline, radius per point (or one radius), its rings carried along by
		parallel transport (no twist); metric UVs (round the girth, along the length). `flat` (a
		factor) squashes the section along the first frame axis (roots, cable flats)."""
		n = len(path)
		if isinstance(radii, (int, float)):
			radii = [radii] * n
		T = []
		for i in range(n):
			a = path[max(i - 1, 0)]
			b = path[min(i + 1, n - 1)]
			T.append(_norm(_sub(b, a)))
		up = (0, 0, 1) if abs(T[0][2]) < 0.9 else (1, 0, 0)
		N = _norm(_cross(_cross(T[0], up), T[0]))
		rings = []
		for i in range(n):
			if i > 0:
				N = _sub(N, _mul(T[i], _dot(N, T[i])))
				if _len(N) < 1e-6:
					N = _norm(_cross(T[i], (0, 0, 1) if abs(T[i][2]) < 0.9 else (1, 0, 0)))
				N = _norm(N)
			B = _cross(T[i], N)
			r = radii[i]
			ring = []
			for s in range(sides):
				t = 2 * math.pi * s / sides
				cn, sn = math.cos(t) * r, math.sin(t) * r
				if flat:
					cn *= flat
				ring.append(tuple(path[i][k] + N[k] * cn + B[k] * sn for k in range(3)))
			rings.append(ring)
		L = [0.0]
		for i in range(1, n):
			L.append(L[-1] + _len(_sub(path[i], path[i - 1])))
		base = len(self.verts)
		for ring in rings:
			self.verts.extend(ring)
		mi = self._mi(m)
		f0 = len(self.faces)
		for i in range(n - 1):
			C = 2 * math.pi * (radii[i] + radii[i + 1]) / 2 * uv_k
			for s in range(sides):
				t = (s + 1) % sides
				self.faces.append((base + i * sides + s, base + i * sides + t, base + (i + 1) * sides + t, base + (i + 1) * sides + s))
				self.mats.append(mi)
				self.uv.append(("m", [(s / sides * C, L[i] * uv_k), ((s + 1) / sides * C, L[i] * uv_k), ((s + 1) / sides * C, L[i + 1] * uv_k), (s / sides * C, L[i + 1] * uv_k)]))
		if caps[0] and radii[0] > 1e-4:
			self.faces.append(tuple(base + s for s in reversed(range(sides))))
			self.mats.append(mi)
			self.uv.append(None)
		if caps[1] and radii[-1] > 1e-4:
			self.faces.append(tuple(base + (n - 1) * sides + s for s in range(sides)))
			self.mats.append(mi)
			self.uv.append(None)
		self.groups.append((f0, len(self.faces), False))

	def lathe(self, profile, m, sides=8, center=(0.0, 0.0, 0.0), rx=0.0, ry=0.0, rz=0.0, caps=(True, True)):
		"""A profile [(r, z), ...] (bottom to top) turned about the local Z axis, then turned
		(rx, ry, rz) and moved to `center`; a ring with r 0 closes to a point."""
		rings = []
		for (r, z) in profile:
			ring = []
			for s in range(sides):
				a = 2 * math.pi * s / sides
				ring.append(rot((math.cos(a) * r, math.sin(a) * r, z), rx, ry, rz))
			rings.append([_add3(p, center) for p in ring])
		base = len(self.verts)
		for ring in rings:
			self.verts.extend(ring)
		mi = self._mi(m)
		f0 = len(self.faces)
		zs = [0.0]
		for i in range(1, len(profile)):
			zs.append(zs[-1] + math.hypot(profile[i][0] - profile[i - 1][0], profile[i][1] - profile[i - 1][1]))
		for i in range(len(profile) - 1):
			ra, rb = profile[i][0], profile[i + 1][0]
			if ra < 1e-6 and rb < 1e-6:
				continue
			C = 2 * math.pi * max(ra, rb)
			for s in range(sides):
				t = (s + 1) % sides
				uv = [(s / sides * C, zs[i]), ((s + 1) / sides * C, zs[i]), ((s + 1) / sides * C, zs[i + 1]), (s / sides * C, zs[i + 1])]
				f = [base + i * sides + s, base + i * sides + t, base + (i + 1) * sides + t, base + (i + 1) * sides + s]
				if ra < 1e-6:
					f = [f[0], f[2], f[3]]
					uv = [uv[0], uv[2], uv[3]]
				elif rb < 1e-6:
					f = [f[0], f[1], f[2]]
					uv = uv[:3]
				self.faces.append(tuple(f))
				self.mats.append(mi)
				self.uv.append(("m", uv))
		if caps[0] and profile[0][0] > 1e-6:
			self.faces.append(tuple(base + s for s in reversed(range(sides))))
			self.mats.append(mi)
			self.uv.append(None)
		if caps[1] and profile[-1][0] > 1e-6:
			k = len(profile) - 1
			self.faces.append(tuple(base + k * sides + s for s in range(sides)))
			self.mats.append(mi)
			self.uv.append(None)
		self.groups.append((f0, len(self.faces), False))

	def chunk(self, center, size, m, rx=0.0, ry=0.0, rz=0.0, seed=0, jitter=0.22):
		"""M4a's broken lump: a box whose eight corners are pulled in at random (12 facets)."""
		r = rng(seed)
		sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
		pts = []
		for (ix, iy, iz) in ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)):
			f = 1.0 - r.uniform(0.0, jitter)
			g = 1.0 - r.uniform(0.0, jitter)
			h = 1.0 - r.uniform(0.0, jitter)
			pts.append(rot((ix * sx * f, iy * sy * g, iz * sz * h), rx, ry, rz))
		cx, cy, cz = center
		pts = [(x + cx, y + cy, z + cz) for x, y, z in pts]
		quads = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
		for q in quads:
			for t in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
				tri = [pts[i] for i in t]
				fc = [sum(p[i] for p in tri) / 3 for i in range(3)]
				self.poly(tri, m, _sub(fc, center))

	# --- manifest data -------------------------------------------------------------------------
	def solid(self, x0, x1, y0, y1, z0, z1, rot_=(0.0, 0.0, 0.0)):
		self.boxes.append((((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), rot_))

	def solid_c(self, center, size, rot_=(0.0, 0.0, 0.0)):
		self.boxes.append((tuple(center), tuple(size), rot_))

	def cap(self, x0, x1, y0, y1, z0, z1):
		self.caps.append((((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), (0.0, 0.0, 0.0)))

	def tris(self):
		return sum(len(f) - 2 for f in self.faces)

	def longest_edge(self):
		best = 0.0
		for f in self.faces:
			ps = [self.verts[i] for i in f]
			for i in range(len(ps)):
				for j in range(i + 1, len(ps)):
					best = max(best, _len(_sub(ps[i], ps[j])))
		return best

	def build(self, coll):
		me = bpy.data.meshes.new(self.name)
		me.from_pydata(self.verts, [], self.faces)
		for n in self.mat_names:
			me.materials.append(mat(n))
		for p, mi in zip(me.polygons, self.mats):
			p.material_index = mi
		me.update()
		uvl = me.uv_layers.new(name="UVMap")
		for p in me.polygons:
			n = p.normal
			ax = max(range(3), key=lambda k: abs(n[k]))
			spec = self.uv[p.index] if p.index < len(self.uv) else None
			lis = list(p.loop_indices)
			if isinstance(spec, tuple) and spec[0] in ("img", "m") and len(spec[1]) == len(lis):
				for li, (u, v) in zip(lis, spec[1]):
					uvl.data[li].uv = (u, 1.0 - v) if spec[0] == "img" else (u, v)
				continue
			for li in lis:
				co = me.vertices[me.loops[li].vertex_index].co
				if ax == 0:
					u, v = co.y * (1 if n.x > 0 else -1), co.z
				elif ax == 1:
					u, v = co.x * (-1 if n.y > 0 else 1), co.z
				else:
					u, v = co.x, co.y * (1 if n.z > 0 else -1)
				uvl.data[li].uv = (u, v)
		ob = bpy.data.objects.new(self.name, me)
		coll.objects.link(ob)
		return ob


PIECES = {}
META = {}


def piece(family, **meta):
	def deco(fn):
		PIECES[fn.__name__] = fn
		META[fn.__name__] = dict(family=family, **meta)
		return fn
	return deco


def variant(name, fn, family, **meta):
	PIECES[name] = fn
	META[name] = dict(family=family, **meta)


def jag(x0, x1, n, lo, hi, seed, ends=None):
	r = random.Random(seed)
	pts = []
	for i in range(n + 1):
		x = x0 + (x1 - x0) * i / n
		h = r.uniform(lo, hi)
		if ends is not None and i in (0, n):
			h = ends
		pts.append((x, h))
	return pts


