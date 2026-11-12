# The beacon, the exit marker and the shared helpers and export for METRO 9 M9's truck kit. Exec'd after
# truck_header.py by run_truck.py in a background Blender; truck_body.py (the truck itself: SS-07's body,
# doors, wheels, steering wheel, tailgate, button) is exec'd after this file and uses its helpers.


def img(p, pts, m, rect=(0.0, 0.0, 1.0, 1.0)):
	"""A quad (bottom-left, bottom-right, top-right, top-left seen from its front) showing an image."""
	u0, v0, u1, v1 = rect
	p.poly(pts, m, None, ("img", [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]))


def face(p, c, n, up, w, h, m, rect=(0.0, 0.0, 1.0, 1.0)):
	"""An image quad centred on c facing n, its top toward `up`, w x h (the image reads the right way
	round from the front)."""
	n, up = _norm(n), _norm(up)
	r = _cross(up, n)
	hw, hh = _mul(r, w / 2), _mul(up, h / 2)
	bl = _sub(_sub(c, hw), hh)
	br = _sub(_add3(c, hw), hh)
	tr = _add3(_add3(c, hw), hh)
	tl = _add3(_sub(c, hw), hh)
	img(p, [bl, br, tr, tl], m, rect)


def chain(p, a, b, sag, n, m="steel", w=0.05):
	"""A hanging chain from a to b: n flat links along a sag, alternating their faces."""
	for k in range(n):
		t = (k + 0.5) / n
		q = _lerp(a, b, t)
		q = (q[0], q[1], q[2] - sag * 4 * t * (1 - t))
		t2 = min(1.0, t + 0.5 / n)
		q2 = _lerp(a, b, t2)
		q2 = (q2[0], q2[1], q2[2] - sag * 4 * t2 * (1 - t2))
		d = _sub(q2, q)
		yaw = math.atan2(d[1], d[0])
		pitch = math.atan2(d[2], math.hypot(d[0], d[1]))
		if k % 2 == 0:
			p.box((w, 0.012, 0.03), q, m, ry=-pitch, rz=yaw)
		else:
			p.box((w, 0.03, 0.012), q, m, ry=-pitch, rz=yaw)


def bolt(p, c, axis="y", r=0.012, m="steel"):
	p.cyl(r, 0.012, c, m, axis=axis, sides=6)


# =====================================================================================
# The salvage beacon
# =====================================================================================

BCN_Y = -0.19    # the box's middle, out from the wall
BCN_TOP = 0.12

@piece("beacon", note="the origin on the wall's face at the plate's centre; it stands out along -Y (Godot +Z)")
def beacon_body(p):
	# the wall plate and its bolts, the stand-off arms
	p.bevel_box((0.3, 0.015, 0.4), (0.0, -0.0075, -0.04), "steel", b=0.005)
	for bx_ in (-0.12, 0.12):
		for bz in (-0.21, 0.13):
			p.cyl(0.012, 0.012, (bx_, -0.018, bz), "steel", axis="y", sides=6)
	for bz in (-0.08, 0.06):
		p.bx(-0.1, 0.1, -0.11, -0.015, bz - 0.015, bz + 0.015, "black")
	# the box: oily black, a hazard band round its top, lid screws, the stencil, the relay's window
	p.bevel_box((0.3, 0.16, 0.24), (0.0, BCN_Y, 0.0), "black", b=0.015)
	p.bevel_box((0.304, 0.164, 0.035), (0.0, BCN_Y, 0.085), "hazard", b=0.006)
	for sx in (-1, 1):
		for sy in (-1, 1):
			p.cyl(0.008, 0.006, (sx * 0.12, BCN_Y + sy * 0.055, BCN_TOP + 0.002), "steel", sides=6)
	face(p, (0.0, BCN_Y - 0.083, -0.0125), (0, -1, 0), (0, 0, 1), 0.26, 0.065, "stencil_beacon")
	# the relay window: the relay behind, glass, a steel frame (each a few mm proud of the last)
	img(p, [(0.03, BCN_Y - 0.082, 0.025), (0.12, BCN_Y - 0.082, 0.025), (0.12, BCN_Y - 0.082, 0.065), (0.03, BCN_Y - 0.082, 0.065)], "relay")
	p.poly([(0.03, BCN_Y - 0.085, 0.025), (0.12, BCN_Y - 0.085, 0.025), (0.12, BCN_Y - 0.085, 0.065), (0.03, BCN_Y - 0.085, 0.065)], "glass", (0, -1, 0))
	for (x0, x1, z0, z1) in ((0.025, 0.125, 0.018, 0.026), (0.025, 0.125, 0.064, 0.072), (0.025, 0.033, 0.018, 0.072), (0.117, 0.125, 0.018, 0.072)):
		p.bx(x0, x1, BCN_Y - 0.088, BCN_Y - 0.08, z0, z1, "steel")
	# the three pip sockets (their lenses are the pip piece); the gland and conduit into the wall
	for k in range(3):
		p.cyl(0.022, 0.012, ((k - 1) * 0.07, BCN_Y - 0.084, -0.08), "steel", axis="y", sides=8, caps=False)
	p.cyl(0.018, 0.03, (0.08, BCN_Y, -0.135), "steel", sides=6)
	p.sweep([(0.08, BCN_Y, -0.15), (0.08, BCN_Y, -0.24), (0.08, BCN_Y + 0.06, -0.3), (0.08, -0.04, -0.33), (0.08, -0.005, -0.33)], 0.012, "rust", sides=6)
	p.bx(0.05, 0.11, -0.02, -0.012, -0.345, -0.315, "steel")
	# the lamp's collar, its guard cage (four bars, two rings, a top cap)
	p.cyl(0.075, 0.03, (0.0, BCN_Y, BCN_TOP + 0.015), "steel", sides=10)
	for k in range(4):
		a = math.pi / 4 + k * math.pi / 2
		x, y = math.cos(a) * 0.082, BCN_Y + math.sin(a) * 0.082
		p.sweep([(x, y, BCN_TOP + 0.03), (x, y, BCN_TOP + 0.17), (x * 0.4, BCN_Y + (y - BCN_Y) * 0.4, BCN_TOP + 0.205)], 0.0045, "steel", sides=4)
	for (zr, rr) in ((BCN_TOP + 0.1, 0.082), (BCN_TOP + 0.17, 0.082)):
		ring = [(rr * math.cos(2 * math.pi * k / 10), BCN_Y + rr * math.sin(2 * math.pi * k / 10), zr) for k in range(11)]
		p.sweep(ring, 0.004, "steel", sides=4, caps=(False, False))
	p.cyl(0.035, 0.012, (0.0, BCN_Y, BCN_TOP + 0.21), "steel", sides=8)
	p.meta["points"] = {k: [_r(x) for x in _to_g(v)] for k, v in {
		"lamp": (0.0, BCN_Y, BCN_TOP + 0.03), "pip_0": (-0.07, BCN_Y - 0.09, -0.08), "pip_1": (0.0, BCN_Y - 0.09, -0.08),
		"pip_2": (0.07, BCN_Y - 0.09, -0.08), "dust": (0.0, BCN_Y, BCN_TOP + 0.05), "front": (0.0, BCN_Y - 0.09, 0.0)}.items()}


@piece("beacon", note="the amber dome; its origin on the collar's top")
def beacon_dome(p):
	p.lathe([(0.066, 0.0), (0.066, 0.07), (0.06, 0.11), (0.042, 0.14), (0.0, 0.152)], "dome_amber", sides=10, caps=(False, False))


@piece("beacon", note="the turning reflector and bulb; its origin on the axis at the collar's top")
def beacon_rotor(p):
	p.cyl(0.04, 0.008, (0.0, 0.0, 0.004), "black", sides=8)
	p.cyl(0.012, 0.06, (0.0, 0.0, 0.045), "bulb", sides=6)
	n = 6
	for k in range(n):
		a0 = math.pi * k / n
		a1 = math.pi * (k + 1) / n
		pa = (0.05 * math.cos(a0), 0.05 * math.sin(a0) - 0.0, 0.012)
		pb = (0.05 * math.cos(a1), 0.05 * math.sin(a1), 0.012)
		p.poly([pa, pb, (pb[0], pb[1], 0.1), (pa[0], pa[1], 0.1)], "reflector", (-math.cos((a0 + a1) / 2), -math.sin((a0 + a1) / 2), 0))


@piece("beacon", note="one pip's lens; its origin on the box's face, it faces -Y")
def beacon_pip(p):
	p.cyl(0.016, 0.012, (0.0, -0.002, 0.0), "pip", axis="y", sides=8)


# =====================================================================================
# The exit marker
# =====================================================================================

@piece("exit", note="a chevron post; its origin on the road under the base, the chevrons facing -Y (Godot +Z)")
def exit_post(p):
	p.bevel_box((0.46, 0.46, 0.07), (0.0, 0.0, 0.035), "rubber", b=0.02)
	p.cyl(0.07, 0.08, (0.0, 0.0, 0.1), "rubber", sides=8)
	p.cyl(0.032, 1.6, (0.0, 0.0, 0.92), "steel", sides=8)
	mk = p.mark()
	p.bx(-0.21, 0.21, -0.0125, 0.0125, 0.0, 0.92, "black")
	p.place(mk, t=(0.0, -0.05, 0.6))
	for side in (-1, 1):
		yv = -0.05 + side * 0.0135
		pts = [(-0.205, yv, 0.605), (0.205, yv, 0.605), (0.205, yv, 1.515), (-0.205, yv, 1.515)]
		if side > 0:
			pts = [pts[1], pts[0], pts[3], pts[2]]
		img(p, pts, "chevron")
	for z in (0.75, 1.36):
		p.bx(-0.045, 0.045, -0.065, 0.035, z - 0.02, z + 0.02, "steel")
	# the flasher's box on top (its two lenses are the flash piece), the battery box, the cable
	p.bevel_box((0.16, 0.12, 0.13), (0.0, 0.0, 1.785), "black", b=0.012)
	for side in (-1, 1):
		p.cyl(0.05, 0.012, (0.0, side * 0.062, 1.785), "black", axis="y", sides=8, caps=False)
	p.bevel_box((0.2, 0.14, 0.16), (0.16, 0.1, 0.15), "black", b=0.012)
	p.bx(0.08, 0.24, 0.028, 0.03, 0.18, 0.22, "hazard")
	p.sweep([(0.12, 0.05, 0.23), (0.04, 0.035, 0.4), (0.035, 0.035, 0.7), (0.035, 0.035, 1.72)], 0.006, "black", sides=4)
	p.meta["points"] = {k: [_r(x) for x in _to_g(v)] for k, v in {"flash": (0.0, 0.0, 1.785)}.items()}


@piece("exit", note="the flasher's two amber lenses; the origin at the flasher box's centre")
def exit_flash(p):
	for side in (-1, 1):
		p.lathe([(0.044, 0.0), (0.044, 0.01), (0.03, 0.025), (0.0, 0.032)], "lens_amber", sides=8, rx=-side * math.pi / 2, center=(0.0, side * 0.068, 0.0))


@piece("exit", note="the boom barrier's post; its origin on the road under it, the pivot hub at +X")
def exit_boom_post(p):
	p.bx(-0.26, 0.26, -0.26, 0.26, 0.0, 0.03, "steel")
	for sx in (-1, 1):
		for sy in (-1, 1):
			p.cyl(0.018, 0.04, (sx * 0.2, sy * 0.2, 0.04), "steel", sides=6)
	p.bevel_box((0.32, 0.32, 0.95), (0.0, 0.0, 0.505), "black", b=0.02)
	p.bevel_box((0.324, 0.324, 0.1), (0.0, 0.0, 0.88), "hazard", b=0.01)
	p.bevel_box((0.36, 0.36, 0.04), (0.0, 0.0, 1.0), "steel", b=0.01)
	p.cyl(0.085, 0.1, (0.21, 0.0, 0.8), "steel", axis="x", sides=10)
	p.cyl(0.05, 0.03, (0.0, 0.0, 1.035), "black", sides=8)
	p.lathe([(0.04, 0.0), (0.04, 0.04), (0.02, 0.07), (0.0, 0.075)], "lens_dead", sides=8, center=(0.0, 0.0, 1.05))
	p.bevel_box((0.2, 0.01, 0.26), (0.0, -0.165, 0.45), "steel", b=0.004)
	p.meta["points"] = {k: [_r(x) for x in _to_g(v)] for k, v in {"pivot": (0.29, 0.0, 0.8)}.items()}


@piece("exit", note="the boom; its origin on the pivot, lying along Blender +Y (Godot -Z); raise it about X")
def exit_boom(p):
	p.bevel_box((0.08, 4.2, 0.1), (0.0, 2.15, 0.0), "hazard", b=0.012)
	p.bevel_box((0.12, 0.38, 0.2), (0.0, -0.3, 0.0), "black", b=0.02)
	p.bevel_box((0.1, 0.06, 0.12), (0.0, 4.26, 0.0), "steel", b=0.01)
	p.cyl(0.03, 0.025, (0.0, 4.0, 0.065), "lens_dead", sides=6)
	p.cyl(0.06, 0.14, (0.0, 0.0, 0.0), "steel", axis="x", sides=8)


# =====================================================================================
# Build and export
# =====================================================================================

_C = ((1, 0, 0), (0, 0, 1), (0, -1, 0))


def _to_g(v):
	return (v[0], v[2], -v[1])


def _r(x):
	return round(x, 4) + 0.0


def _boxes_g(boxes):
	out = []
	for (c, s, rr) in boxes:
		out.append([_r(x) for x in list(_to_g(c)) + [s[0], s[2], s[1]]])
	return out


def manifest_entry(p, tris):
	verts = [_to_g(v) for v in p.verts]
	lo = [min(v[k] for v in verts) for k in range(3)]
	hi = [max(v[k] for v in verts) for k in range(3)]
	e = dict(META.get(p.name[len(PREFIX):], {}))
	e.update({"tris": tris, "aabb": [[_r(x) for x in lo], [_r(x) for x in hi]], "boxes": _boxes_g(p.boxes),
			"materials": list(p.mat_names)})
	e.update(p.meta)
	return e


IMPORT_SIDECAR = '[remap]\n\nimporter="scene"\nimporter_version=1\n\n[params]\n\nmeshes/generate_lods=false\n'


def build():
	sc = bpy.data.scenes.get(SCENE)
	if sc is None:
		sc = bpy.context.scene
		sc.name = SCENE
		for ob in list(sc.collection.objects):
			bpy.data.objects.remove(ob, do_unlink=True)
	coll = sc.collection
	# every object, the startup scene's cube in its child collection included
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	for c in list(coll.children):
		coll.children.unlink(c)
	for me in list(bpy.data.meshes):
		if me.users == 0:
			bpy.data.meshes.remove(me)
	report, entries = {}, {}
	for i, (name, fn) in enumerate(PIECES.items()):
		p = Piece(PREFIX + name)
		fn(p)
		ob = p.build(coll)
		ob.location = ((i % 6) * 8.0, (i // 6) * 8.0, 0.0)
		t = p.tris()
		report[name] = t
		entries[name] = manifest_entry(p, t)
	globals()["_ENTRIES"] = entries
	return {"tris": report, "total": sum(report.values())}


def export():
	sc = bpy.data.scenes[SCENE]
	vl = sc.view_layers[0]
	with bpy.context.temp_override(scene=sc, view_layer=vl):
		coll = sc.collection
		tmp = bpy.data.collections.new("trk_export")
		coll.children.link(tmp)
		vl.active_layer_collection = vl.layer_collection.children[tmp.name]
		done = []
		for ob in [o for o in coll.objects if o.name.startswith(PREFIX)]:
			name = ob.name[len(PREFIX):]
			glb = os.path.join(OUT, name + ".glb")
			if not os.path.exists(glb + ".import"):
				with open(glb + ".import", "w", encoding="utf-8", newline="\n") as f:
					f.write(IMPORT_SIDECAR)
			loc = ob.location.copy()
			ob.location = (0, 0, 0)
			tmp.objects.link(ob)
			bpy.ops.export_scene.gltf(filepath=glb, use_selection=False, use_active_collection=True, use_active_scene=True,
					export_apply=True, export_yup=True, export_materials="EXPORT")
			tmp.objects.unlink(ob)
			ob.location = loc
			done.append(name)
		coll.children.unlink(tmp)
		bpy.data.collections.remove(tmp)
	data = {"version": 1, "convention": "Godot space; the truck's nose at -Z; docs/design/place_metro9.md (M9)",
			"pieces": dict(sorted(globals().get("_ENTRIES", {}).items()))}
	with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
		json.dump(data, f, indent=1)
	bpy.data.libraries.write(BLEND, {sc}, fake_user=True)
	return {"exported": len(done), "names": done}
