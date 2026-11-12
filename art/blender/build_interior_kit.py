# Dead Protocol - INTERIOR + STREET KIT (Blender 5.x, run headless after the map kit):
#   blender -b --factory-startup -P art/blender/build_interior_kit.py
# Furniture, fittings and street dressing that make the County's places read
# as real places: diner booths, store shelving, beds, sofas, kitchens, desks,
# cells, workbenches, school desks, turbines; outside: bushes, pines, corn,
# road signs, lights, hydrants, bins, wrecks, guardrails, porches, awnings,
# trailers and tents. Every solid piece carries "-colonly" boxes, so Godot
# makes the colliders and the navmesh steers zombies round the furniture.
# Front of a piece faces +Y (Godot -Z); origin on the floor.
import bpy, math, os, random, sys

sys.path.append(os.path.dirname(__file__))
import build_map_kit as K  # noqa: E402
from build_world_kit import load_textures, col, piece  # noqa: E402

B, C, R, Bl = K.box, K.cyl, K.rod, K.ball


def M(n, **kw):
    return K.mat(n, **kw)


# ------------------------------------------------------------- furniture
def p_table():
    W, S = M("wood_board"), M("gunmetal")
    P = [B((1.4, .8, .05), (0, 0, .75), W, bevel=.012)]
    for x in (-.62, .62):
        for y in (-.32, .32):
            P.append(B((.06, .06, .72), (x, y, .36), S))
    return piece("int_table", P, [col((1.4, .8, .78), (0, 0, .39))])


def p_chair():
    W, S = M("wood_board"), M("gunmetal")
    P = [B((.45, .45, .04), (0, 0, .45), W), B((.45, .04, .45), (0, -.21, .7), W)]
    for x in (-.19, .19):
        for y in (-.19, .19):
            P.append(B((.03, .03, .44), (x, y, .22), S, bevel=0))
    return piece("int_chair", P, [col((.45, .45, .9), (0, 0, .45))])


def p_booth():
    F, W = M("fabric_red"), M("wood_board")
    P = [B((1.6, .55, .45), (0, 0, .23), F, bevel=.04), B((1.6, .15, .7), (0, -.25, .8), F, bevel=.04),
         B((1.6, .5, .45), (0, 1.5, .23), F, bevel=.04), B((1.6, .15, .7), (0, 1.75, .8), F, bevel=.04),
         B((1.3, .7, .05), (0, .75, .74), M("paint_hospital"), bevel=.015), C(.06, .7, (0, .75, .38), M("gunmetal"), seg=6),
         B((.15, .1, .2), (.4, .7, .86), M("glass_dark", emit=(.7, .6, .4))), C(.04, .1, (-.3, .8, .82), M("paint_rust_red"), seg=6)]
    return piece("int_booth", P, [col((1.6, .7, 1.2), (0, -.05, .6)), col((1.6, .7, 1.2), (0, 1.55, .6)), col((1.3, .7, .78), (0, .75, .39))])


def p_counter():
    """4 m service counter (diner / store / bar), customer side +Y."""
    W, T = M("wood_board"), M("paint_hospital")
    P = [B((4.0, .7, 1.0), (0, 0, .5), W, bevel=.02), B((4.1, .85, .06), (0, .05, 1.03), T, bevel=.01),
         B((4.0, .05, .9), (0, .36, .5), M("panel"), bevel=0)]
    P += [B((.45, .35, .25), (-1.3, -.1, 1.19), M("gunmetal")), B((.3, .02, .14), (-1.3, .08, 1.25), M("glass_dark", emit=(.3, .8, .4)), bevel=0)]
    for x in (.2, .9, 1.5):
        P.append(C(.06, .2, (x, -.15, 1.16), M("glass_dark"), seg=6))
    return piece("int_counter", P, [col((4.0, .85, 1.08), (0, 0, .54))])


def p_stool():
    S, F = M("gunmetal"), M("fabric_red")
    P = [C(.2, .1, (0, 0, .72), F, seg=8), C(.04, .65, (0, 0, .36), S, seg=6), C(.22, .04, (0, 0, .02), S, seg=8)]
    return piece("int_stool", P, [col((.4, .4, .78), (0, 0, .39))])


def p_store_shelf():
    """2.4 m double-sided gondola stacked with (partly looted) goods."""
    S, G = M("shelf_metal"), M("goods")
    P = [B((2.4, .1, 1.8), (0, 0, .9), S, bevel=0), B((2.4, .9, .12), (0, 0, .06), S, bevel=0)]
    for z in (.45, .9, 1.35, 1.75):
        P.append(B((2.4, .9, .03), (0, 0, z), S, bevel=0))
    for s in (-1, 1):
        for z in (.15, .6, 1.05):
            g = B((2.3, .36, .3), (0, s * .24, z + .16), G, bevel=0)
            K.face_uv(g)
            P.append(g)
    for x in (-1.2, 1.2):
        P.append(B((.05, .92, 1.85), (x, 0, .92), S, bevel=0))
    return piece("int_store_shelf", P, [col((2.45, .95, 1.85), (0, 0, .92))])


def p_fridge_row():
    """3 glass-door fridges against a wall (front +Y)."""
    S, G, In = M("paint_hospital"), M("glass_dark"), M("goods")
    P = [B((2.7, .8, 2.1), (0, 0, 1.05), S, bevel=.03), B((2.75, .82, .2), (0, 0, 2.2), M("sign"))]
    for i in range(3):
        x = -.9 + i * .9
        inner = B((.8, .02, 1.7), (x, .38, 1.0), In, bevel=0)
        K.face_uv(inner)
        P += [inner, B((.82, .03, 1.75), (x, .41, 1.0), G, bevel=0),
              B((.03, .05, .4), (x + .35, .44, 1.1), M("gunmetal"), bevel=0)]
    P.append(B((2.6, .02, .05), (0, .42, 1.9), M("glass_dark", emit=(.7, .9, 1.0)), bevel=0))
    return piece("int_fridge_row", P, [col((2.75, .85, 2.3), (0, 0, 1.15))])


def p_bed():
    W, L, F = M("wood_board"), M("linen"), M("fabric")
    P = [B((1.4, 2.0, .3), (0, 0, .3), W, bevel=.02), B((1.35, 1.95, .2), (0, 0, .55), L, bevel=.05),
         B((1.4, .1, .9), (0, -1.0, .45), W), B((1.4, .08, .5), (0, 1.0, .3), W),
         B((1.0, .4, .12), (0, -.7, .7), L, bevel=.05), B((1.36, 1.1, .06), (0, .35, .67), F, rot=(0, 2, 0), bevel=.03)]
    return piece("int_bed", P, [col((1.45, 2.05, .75), (0, 0, .38))])


def p_sofa():
    F = M("fabric")
    P = [B((2.0, .85, .42), (0, 0, .25), F, bevel=.06), B((2.0, .25, .55), (0, -.32, .7), F, bevel=.06),
         B((.25, .85, .3), (-.9, 0, .6), F, bevel=.06), B((.25, .85, .3), (.9, 0, .6), F, bevel=.06),
         B((.8, .7, .16), (-.45, .05, .52), F, bevel=.05), B((.8, .7, .16), (.45, .05, .52), M("fabric_red"), rot=(4, 0, 0), bevel=.05)]
    return piece("int_sofa", P, [col((2.0, .9, .9), (0, 0, .45))])


def p_kitchen():
    """3 m kitchen run against a wall: cabinets, sink, stove, fridge (front +Y)."""
    W, T, S = M("wood_board"), M("paint_hospital"), M("gunmetal")
    P = [B((2.2, .6, .88), (-.4, 0, .44), W, bevel=.02), B((2.25, .65, .05), (-.4, .02, .9), T, bevel=.01),
         B((.5, .4, .05), (-1.0, .05, .91), S, bevel=0), C(.02, .25, (-1.0, -.2, 1.05), S, seg=5),
         B((.6, .6, .9), (.4, 0, .45), S, bevel=.02), B((.55, .02, .35), (.4, .31, .5), M("glass_dark"), bevel=0)]
    for x in (.27, .53):
        for y in (-.12, .12):
            P.append(C(.09, .01, (x, y, .91), M("rubber"), seg=8, bevel=0))
    P += [B((.75, .7, 1.85), (1.15, 0, .93), T, bevel=.04), B((.02, .05, .5), (1.47, .36, 1.3), S, bevel=0),
          B((2.2, .35, .6), (-.4, -.12, 1.9), W, bevel=.02)]
    for i in range(4):
        P.append(B((.03, .02, .1), (-1.3 + i * .55, .3, .7), S, bevel=0))
    return piece("int_kitchen", P, [col((3.0, .7, 1.9), (0.0, 0, .95))])


def p_filing_cabinet():
    S = M("panel")
    P = [B((.5, .65, 1.3), (0, 0, .65), S, bevel=.02)]
    for z in (.2, .55, .9, 1.2):
        P += [B((.46, .02, .28), (0, .33, z), S, bevel=.005), B((.12, .02, .02), (0, .345, z + .05), M("gunmetal"), bevel=0)]
    P.append(B((.5, .4, .04), (0, .45, .9), S, rot=(0, 0, 0), bevel=0))  # one drawer hangs open
    return piece("int_filing_cabinet", P, [col((.5, .7, 1.3), (0, 0, .65))])


def p_cell_bars():
    """4 m wall of cell bars with a door, for the police station."""
    S = M("gunmetal", metal=.6)
    P = [B((4.0, .1, .1), (0, 0, 2.5), S), B((4.0, .1, .1), (0, 0, .05), S), B((4.0, .1, .1), (0, 0, 1.2), S)]
    for i in range(17):
        x = -1.9 + i * .2375
        if 0.2 < x < 1.1:
            continue  # the cell door gap
        P.append(C(.02, 2.5, (x, 0, 1.25), S, seg=5, bevel=0))
    for i in range(5):  # swung-open door
        P.append(C(.02, 2.3, (.3 + i * .05, .2 + i * .19, 1.2), S, seg=5, bevel=0))
    return piece("int_cell_bars", P, [col((4.0, .15, 2.6), (0, 0, 1.3))])


def p_keg():
    S = M("gunmetal", metal=.6)
    P = [C(.22, .55, (0, 0, .3), S, seg=10), C(.23, .04, (0, 0, .15), S, seg=10, bevel=0), C(.23, .04, (0, 0, .45), S, seg=10, bevel=0)]
    return piece("int_keg", P, [col((.45, .45, .6), (0, 0, .3))])


def p_workbench():
    W, S = M("wood_board"), M("gunmetal")
    P = [B((2.0, .7, .08), (0, 0, .9), W, bevel=.01), B((2.0, .05, 1.0), (0, -.35, 1.4), M("panel"), bevel=0)]
    for x in (-.95, .95):
        for y in (-.3, .3):
            P.append(B((.07, .07, .88), (x, y, .44), S, bevel=0))
    P += [B((1.9, .6, .05), (0, 0, .25), W, bevel=0), B((.3, .2, .15), (-.6, 0, 1.0), M("paint_rust_red")),
          B((.35, .25, .2), (.5, .1, 1.04), M("gunmetal")), R((-.2, .1, .95), (.1, .2, .96), .015, S)]
    for i in range(6):
        P.append(B((.03, .02, .25), (-.7 + i * .28, -.32, 1.5), S, bevel=0))
    return piece("int_workbench", P, [col((2.0, .75, .98), (0, 0, .49))])


def p_tool_cabinet():
    R_ = M("paint_rust_red")
    P = [B((.9, .55, 1.1), (0, 0, .6), R_, bevel=.02)]
    for i in range(6):
        P.append(B((.8, .02, .12), (0, .28, .2 + i * .16), M("gunmetal"), bevel=0))
    for x in (-.35, .35):
        for y in (-.2, .2):
            P.append(C(.05, .05, (x, y, .03), M("rubber"), seg=6, rot=(0, 90, 0)))
    return piece("int_tool_cabinet", P, [col((.9, .6, 1.15), (0, 0, .6))])


def p_school_desk():
    W, S = M("wood_board"), M("gunmetal")
    P = [B((.7, .5, .04), (0, .1, .72), W, rot=(-6, 0, 0)), B((.4, .4, .04), (0, -.4, .44), W), B((.4, .04, .35), (0, -.62, .65), W)]
    for x in (-.3, .3):
        P += [B((.03, .03, .7), (x, .1, .36), S, bevel=0), B((.03, .03, .44), (x * .55, -.4, .22), S, bevel=0)]
    return piece("int_school_desk", P, [col((.72, 1.1, .78), (0, -.15, .39))])


def p_chalkboard():
    P = [B((3.0, .05, 1.2), (0, 0, 1.6), M("chalkboard"), bevel=0), B((3.1, .08, .08), (0, 0, 2.22), M("wood_board")),
         B((3.1, .12, .05), (0, .05, .98), M("wood_board"))]
    for i in range(3):
        P.append(B((.08, .02, .02), (-1 + i * .3, .08, 1.02), M("linen"), bevel=0))
    return piece("int_chalkboard", P, [])


def p_bookshelf():
    W, G = M("wood_board"), M("goods")
    P = [B((1.2, .35, 2.0), (0, 0, 1.0), W, bevel=.01)]
    for z in (.4, .8, 1.2, 1.6):
        g = B((1.1, .28, .32), (0, .02, z - .17), G, bevel=0)
        K.face_uv(g)
        P.append(g)
    return piece("int_bookshelf", P, [col((1.2, .38, 2.0), (0, 0, 1.0))])


def p_boxes():
    Cb = M("cardboard")
    rnd = random.Random(21)
    P = []
    for i, (x, y, z, s) in enumerate(((0, 0, 0, .6), (.65, .05, 0, .5), (.1, .05, .6, .5), (-.6, .2, 0, .45), (.7, .1, .5, .35))):
        b = B((s, s * .9, s * .8), (x, y, z + s * .4), Cb, rot=(0, 0, rnd.uniform(-15, 15)), bevel=.015)
        K.face_uv(b)
        P.append(b)
    return piece("int_boxes", P, [col((1.9, .7, .9), (0.05, .1, .45))])


def p_control_panel():
    Pn = M("panel")
    P = [B((2.4, .8, 1.0), (0, 0, .5), Pn, bevel=.02), B((2.4, .5, .6), (0, -.15, 1.25), Pn, taper=(1, .5)),
         B((2.0, .02, .3), (0, .12, 1.25), M("glass_dark", emit=(.3, .9, .5)), rot=(-40, 0, 0), bevel=0)]
    for i in range(10):
        P.append(C(.03, .03, (-1 + i * .22, .35, 1.02), M("paint_rust_red" if i % 3 else "hazard"), seg=6))
    for i in range(4):
        P.append(C(.09, .03, (-.8 + i * .5, .05, 1.45), M("glass_dark"), seg=8, rot=(50, 0, 0), bevel=0))
    return piece("int_control_panel", P, [col((2.4, .85, 1.6), (0, 0, .8))])


def p_turbine():
    S, H = M("paint_olive"), M("hazard")
    P = [C(1.4, 5.0, (0, 0, 1.6), S, seg=12, rot=(0, 90, 0)), C(1.6, .3, (-2.6, 0, 1.6), S, seg=12, rot=(0, 90, 0)),
         C(1.6, .3, (2.6, 0, 1.6), S, seg=12, rot=(0, 90, 0)), B((6.0, 2.6, .4), (0, 0, .2), M("concrete")),
         B((6.2, 2.8, .1), (0, 0, .45), H), C(.5, 1.6, (2.0, 0, 3.2), M("gunmetal"), seg=8),
         R((-2.0, 0, 2.9), (-2.0, -1.8, 4.0), .25, M("gunmetal"), seg=8)]
    for x in (-1.6, -.6, .4, 1.4):
        P.append(C(1.45, .1, (x, 0, 1.6), M("gunmetal"), seg=12, rot=(0, 90, 0), bevel=0))
    return piece("int_turbine", P, [col((6.0, 2.8, 3.2), (0, 0, 1.6))])


def p_pipes():
    """4 m run of wall pipes with valves (industrial interiors)."""
    S, R_ = M("rusted_metal", metal=.5), M("paint_rust_red")
    P = []
    for z, r in ((.6, .14), (1.0, .1), (2.6, .2)):
        P.append(C(r, 4.0, (0, 0, z), S, seg=8, rot=(0, 90, 0)))
    for x in (-1.2, 1.3):
        P += [C(.2, .06, (x, .2, 1.0), R_, seg=8, rot=(90, 0, 0)), C(.03, .2, (x, .1, 1.0), S, seg=5, rot=(90, 0, 0))]
    for x in (-1.8, 0, 1.8):
        P.append(B((.06, .3, 2.6), (x, -.05, 1.5), M("gunmetal"), bevel=0))
    return piece("int_pipes", P, [col((4.0, .5, 2.9), (0, 0, 1.45))])


# ------------------------------------------------------------- outside
def p_bush():
    F = M("foliage")
    P = [Bl(.7, (0, 0, .5), F, seg=7, rings=5, scale=(1.2, 1, .8), jitter=.25, seed=1),
         Bl(.5, (.6, .2, .4), F, seg=6, rings=4, scale=(1, 1, .9), jitter=.25, seed=2),
         Bl(.45, (-.5, -.3, .35), F, seg=6, rings=4, jitter=.3, seed=3)]
    return piece("ext_bush", P, [])


def p_pine():
    F, Bk = M("foliage"), M("bark")
    P = [C(.25, 3.0, (0, 0, 1.5), Bk, seg=6, r2=.15)]
    for i, (z, r, h) in enumerate(((2.4, 2.4, 3.0), (4.2, 1.9, 2.6), (5.8, 1.4, 2.2), (7.2, .9, 1.8))):
        P.append(C(r, h, (0, 0, z), F, seg=7, r2=.05, bevel=0))
    return piece("ext_pine", P, [col((.6, .6, 3.0), (0, 0, 1.5))])


def p_corn():
    """8 x 4 m patch of corn rows (blocks sight lines, not movement)."""
    Cr = M("crops")
    rnd = random.Random(5)
    P = []
    for row in range(5):
        y = -1.6 + row * .8
        P.append(B((8.0, .12, .2), (0, y, .1), M("dirt"), bevel=0))
        for k in range(9):
            x = -3.6 + k * .9 + rnd.uniform(-.2, .2)
            h = rnd.uniform(1.5, 2.2)
            P.append(B((.5, .3, h), (x, y, h / 2), Cr, rot=(rnd.uniform(-6, 6), rnd.uniform(-6, 6), rnd.uniform(0, 90)), taper=(.3, .3), bevel=0))
    return piece("ext_corn", P, [])


def p_stop_sign():
    S = M("gunmetal")
    P = [C(.035, 2.3, (0, 0, 1.15), S, seg=5), C(.35, .03, (0, .05, 2.2), M("paint_rust_red"), seg=8, rot=(90, 22.5, 0), bevel=0),
         C(.3, .035, (0, .05, 2.2), M("paint_hospital"), seg=8, rot=(90, 22.5, 0), bevel=0)]
    return piece("ext_stop_sign", P, [col((.15, .15, 2.3), (0, 0, 1.15))])


def p_traffic_light():
    S, Bk = M("gunmetal"), M("rubber")
    P = [C(.1, 5.2, (0, 0, 2.6), S, seg=6), R((0, 0, 5.0), (0, 3.2, 5.0), .06, S),
         B((.35, .3, 1.0), (0, 3.0, 4.4), Bk), B((.35, .3, 1.0), (0, .25, 3.8), Bk)]
    for i, col_ in enumerate(((.8, .1, .05), (.6, .5, .1), (.1, .4, .2))):
        P.append(C(.11, .03, (0, 3.17, 4.75 - i * .32), M("glass_dark", emit=col_ if i == 0 else None), seg=8, rot=(90, 0, 0), bevel=0))
    return piece("ext_traffic_light", P, [col((.25, .25, 5.2), (0, 0, 2.6))])


def p_hydrant():
    R_ = M("paint_rust_red")
    P = [C(.14, .6, (0, 0, .3), R_, seg=8), Bl(.15, (0, 0, .62), R_, seg=8, rings=4), C(.07, .4, (0, 0, .35), R_, seg=6, rot=(90, 0, 0)),
         C(.2, .06, (0, 0, .03), R_, seg=8)]
    return piece("ext_hydrant", P, [col((.35, .35, .75), (0, 0, .37))])


def p_trash_can():
    G = M("paint_dumpster")
    P = [C(.3, .9, (0, 0, .45), G, seg=10, r2=.33), C(.36, .08, (.05, 0, .93), G, seg=10, rot=(8, 0, 0)),
         Bl(.2, (.15, .1, .95), M("rubber"), seg=6, rings=4, jitter=.2, seed=4)]
    return piece("ext_trash_can", P, [col((.65, .65, .95), (0, 0, .47))])


def p_picnic_table():
    W = M("wood_board")
    P = []
    for i in range(4):
        P.append(B((1.8, .18, .04), (0, -.27 + i * .18, .74), W, bevel=.008))
    for y in (-.7, .7):
        P.append(B((1.8, .3, .04), (0, y, .45), W, bevel=.008))
    for x in (-.7, .7):
        P += [B((.08, 1.6, .06), (x, 0, .4), W, rot=(0, 0, 0)), R((x, -.6, 0), (x, .2, .72), .04, W), R((x, .6, 0), (x, -.2, .72), .04, W)]
    return piece("ext_picnic_table", P, [col((1.8, 1.7, .78), (0, 0, .39))])


def p_bus_wreck():
    Y, G, T, S = M("paint_orange"), M("glass_dark"), M("rubber"), M("gunmetal")
    P = [B((2.5, 10.0, 2.4), (0, 0, 1.7), Y, bevel=.12), B((2.4, 9.6, .15), (0, 0, 2.95), Y, bevel=.05),
         B((2.55, 9.0, .65), (0, -.3, 2.25), G, bevel=0), B((2.3, .1, .9), (0, 5.02, 2.0), G, bevel=0),
         B((2.6, .3, .35), (0, 5.1, .7), S), B((2.6, .3, .35), (0, -5.1, .7), S), B((2.52, 9.0, .1), (0, 0, 1.55), M("hazard"), bevel=0)]
    for x in (-1.1, 1.1):
        for y in (3.4, -3.0):
            P.append(C(.5, .35, (x, y, .5 if y > 0 else .3), T, seg=10, rot=(0, 90, 0)))
    P[0].rotation_euler.y = math.radians(4)
    return piece("ext_bus_wreck", P, [col((2.6, 10.2, 3.0), (0, 0, 1.5))])


def p_police_car():
    Bk, W, G, T = M("rubber"), M("paint_hospital"), M("glass_dark"), M("rubber")
    P = [B((1.85, 4.6, .55), (0, 0, .62), W, bevel=.06), B((1.86, 1.6, .56), (0, 1.5, .62), Bk, bevel=.06),
         B((1.86, 1.4, .56), (0, -1.6, .62), Bk, bevel=.06), B((1.6, 2.2, .5), (0, -.2, 1.15), W, taper=(.86, .8), bevel=.05),
         B((1.7, 1.8, .32), (0, -.2, 1.12), G, taper=(.9, .9), bevel=0),
         B((1.0, .25, .12), (0, -.2, 1.45), M("glass_dark", emit=(.8, .1, .05))), B((.4, .26, .13), (.3, -.2, 1.45), M("glass_dark", emit=(.1, .3, 1.0)))]
    for x in (-.82, .82):
        for y in (-1.4, 1.45):
            P.append(C(.34, .22, (x, y, .34), T, seg=10, rot=(0, 90, 0)))
    return piece("ext_police_car", P, [col((1.9, 4.6, 1.5), (0, 0, .75))])


def p_guardrail():
    S = M("gunmetal", metal=.5)
    P = [B((4.0, .08, .3), (0, 0, .65), S, bevel=.02)]
    for x in (-1.9, 0, 1.9):
        P.append(B((.1, .1, .75), (x, -.06, .37), S))
    return piece("ext_guardrail", P, [col((4.0, .25, .8), (0, 0, .4))])


def p_porch():
    """4 x 2 m porch for a house door: deck, steps, posts, little roof (front +Y)."""
    W, Rf = M("wood_board"), M("shingles")
    P = [B((4.0, 2.0, .25), (0, 1.0, .12), M("wood_planks"), bevel=.01), B((1.6, .5, .12), (0, 2.25, .06), W),
         B((4.3, 2.4, .1), (0, 1.0, 3.2), Rf, rot=(-8, 0, 0), bevel=0)]
    for x in (-1.9, 1.9):
        P += [B((.14, .14, 3.0), (x, 1.9, 1.6), W), B((.06, 1.9, .06), (x, 1.0, .95), W)]
    P.append(B((1.2, .06, .06), (-1.3, 1.9, .95), W))
    P.append(B((1.2, .06, .06), (1.3, 1.9, .95), W))
    P.append(B((.6, .6, .9), (1.3, 1.3, .7), M("wood_board"), rot=(0, 0, 10)))  # rocking-chair-ish crate seat
    return piece("ext_porch", P, [col((4.0, 2.0, .3), (0, 1.0, .15)), col((.2, .2, 3.0), (-1.9, 1.9, 1.5)), col((.2, .2, 3.0), (1.9, 1.9, 1.5))])


def p_awning():
    """4 m shop awning over a facade slot (front +Y)."""
    P = [B((4.0, 1.4, .06), (0, .7, 3.3), M("fabric_red"), rot=(-18, 0, 0), bevel=0), B((4.0, .06, .3), (0, 1.36, 3.0), M("fabric_red"), bevel=0)]
    for x in (-1.9, 1.9):
        P.append(R((x, 0, 3.5), (x, 1.35, 3.05), .02, M("gunmetal")))
    return piece("ext_awning", P, [])


def p_sign_board():
    """Blank shop sign plank; the game writes the name on it."""
    P = [B((3.2, .12, .8), (0, 0, 0), M("wood_board"), bevel=.02), B((3.0, .02, .62), (0, .065, 0), M("paint_hospital"), bevel=0)]
    for x in (-1.2, 1.2):
        P.append(R((x, -.06, .4), (x, -.3, .9), .02, M("gunmetal")))
    return piece("ext_sign_board", P, [])


def p_trailer():
    """Mobile home (trailer park): 12 x 3.6 m."""
    W, R_ = M("siding_white"), M("tin_roof")
    P = [B((12.0, 3.6, 2.6), (0, 0, 1.75), W, bevel=.05), B((12.2, 3.8, .12), (0, 0, 3.1), R_), B((12.0, 3.4, .4), (0, 0, .25), M("gunmetal")),
         B((1.0, .06, 2.0), (3.0, 1.83, 1.5), M("wood_board"), bevel=.01), B((1.6, .8, .4), (3.0, 2.3, .2), M("wood_board"))]
    for x in (-4.5, -1.5, 1.0, 5.0):
        P += [B((1.2, .05, .9), (x, 1.82, 2.0), M("window"), bevel=0), B((1.2, .05, .9), (x, -1.82, 2.0), M("window"), bevel=0)]
    for x in (-5, 0, 5):
        P.append(B((.4, .4, .5), (x, 0, .25), M("concrete")))
    return piece("ext_trailer", P, [col((12.0, 3.6, 3.1), (0, 0, 1.6)), col((1.6, .8, .4), (3.0, 2.3, .2))])


def p_tent():
    F = M("paint_olive")
    bm = K.bmesh.new()
    v = [bm.verts.new(p) for p in ((-1.2, -1.5, 0), (1.2, -1.5, 0), (0, -1.5, 1.6), (-1.2, 1.5, 0), (1.2, 1.5, 0), (0, 1.5, 1.6))]
    for f in ((0, 1, 2), (3, 5, 4), (0, 2, 5, 3), (1, 4, 5, 2)):
        bm.faces.new([v[i] for i in f])
    K.bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    t = K._obj("part", bm, F)
    P = [t, R((0, -1.6, 0), (0, -1.6, 1.7), .02, M("gunmetal")), R((0, 1.6, 0), (0, 1.6, 1.7), .02, M("gunmetal"))]
    return piece("ext_tent", P, [col((2.4, 3.0, 1.2), (0, 0, .6))])


def p_campfire():
    P = [K.ring(.45, .1, (0, 0, .08), M("rock"), seg=8, tseg=3)]
    for a in range(0, 360, 60):
        r = math.radians(a)
        P.append(R((math.cos(r) * .35, math.sin(r) * .35, .05), (0, 0, .35), .04, M("bark")))
    return piece("ext_campfire", P, [])


def p_barricade():
    """Survivor barricade: sheet metal, planks and tyres across a street."""
    M_, W = M("rusted_metal"), M("wood_board")
    P = [B((4.0, .1, 1.6), (0, 0, .8), M_, rot=(0, 4, 0), bevel=0), B((1.8, .1, 1.1), (1.4, .15, .55), M_, rot=(0, -6, 3), bevel=0)]
    for i in range(4):
        P.append(B((.15, .5, 2.0), (-1.6 + i * 1.05, -.2, 1.0), W, rot=(20, 0, (i * 9) % 13 - 6), bevel=.01))
    for x in (-1.2, .6):
        P.append(K.ring(.32, .12, (x, -.6, .12), M("rubber"), seg=10))
    return piece("ext_barricade", P, [col((4.0, .6, 1.8), (0, 0, .9))])


PROPS = [p_table, p_chair, p_booth, p_counter, p_stool, p_store_shelf, p_fridge_row, p_bed, p_sofa, p_kitchen,
         p_filing_cabinet, p_cell_bars, p_keg, p_workbench, p_tool_cabinet, p_school_desk, p_chalkboard, p_bookshelf,
         p_boxes, p_control_panel, p_turbine, p_pipes,
         p_bush, p_pine, p_corn, p_stop_sign, p_traffic_light, p_hydrant, p_trash_can, p_picnic_table, p_bus_wreck,
         p_police_car, p_guardrail, p_porch, p_awning, p_sign_board, p_trailer, p_tent, p_campfire, p_barricade]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    K.TEXEL = 1.5
    load_textures()
    roots = []
    for fn in PROPS:
        r = fn()
        K.export(r)
        roots.append(r)
    x = 0.0
    for r in roots:
        r.location.x = x
        x += 6.0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(K.ROOT, "art", "blender", "interior_kit.blend"))
    print("INTERIOR KIT OK %d props" % len(roots))


main()
