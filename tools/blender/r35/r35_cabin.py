# R35 cockpit cabin v2 — authored in DRIVER-EYE space, now CONSISTENT with the exterior body.
# Cabin frame (this file): X = eye-right (toward the car centreline), Y = forward, Z = up, eye at origin.
# glTF (+Y up) maps it to Godot eye space: x = X, y = Z, z = -Y.
# Exterior (r35_body, Blender): Xb = car-left, Yb = rear, Zb = up, ground 0.
# Eye = CarConfig seat anchor (height 1.08, forward -0.18, lateral -0.36) = exterior (0.36, 0.18, 1.08):
#     Xc = 0.36 - Xb,   Yc = 0.18 - Yb,   Zc = Zb - 1.08
#   blender --background --factory-startup --python r35_cabin.py -- render|export <out.glb>
import sys, os, math, importlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy, bmesh
from mathutils import Vector, Matrix
import r35_common as C; importlib.reload(C)
import r35_body as B; importlib.reload(B)

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else ['render']
EYE_B = Vector((0.36, 0.18, 1.08))
XC = 0.36           # car centreline in cabin X
BAND = 0.051        # sightline band split (test band is +-0.05)
# wheel / dial layout solved by wheel_fit.py (dials fully visible through the rim's upper half)
WHEEL_C = Vector((0.0, 0.48, -0.30)); WHEEL_TILT = math.radians(30)
DIAL_Y, DIAL_Z, DIAL_DX, DIAL_R = 0.84, -0.335, 0.064, 0.05


def T(p):
    return Vector((0.36 - p[0], 0.18 - p[1], p[2] - 1.08))


def M_():
    E = 0.15
    M = {}
    def m(name, col, metal=0.0, rough=0.8, emit_k=1.0):
        mm = C.mat(name, col, metal, rough, emit=col, emit_strength=E * emit_k)
        mm.use_backface_culling = False
        M[name] = mm
    m('CabBlack', (0.035, 0.035, 0.040), 0.0, 0.78)
    m('CabSoft', (0.030, 0.030, 0.034), 0.0, 0.92)
    m('CabTan', (0.42, 0.205, 0.090), 0.0, 0.55)
    m('CabAlloy', (0.58, 0.58, 0.61), 0.9, 0.28)
    m('CabGloss', (0.014, 0.014, 0.016), 0.2, 0.12)
    m('CabHeadliner', (0.055, 0.055, 0.060), 0.0, 0.95)
    m('CabCarpet', (0.026, 0.026, 0.028), 0.0, 1.0)
    m('CabMirror', (0.30, 0.33, 0.37), 1.0, 0.05, emit_k=0.5)
    M['CabCarbon'] = C.textured(C.mat('CabCarbon', (0.05, 0.05, 0.055), 0.35, 0.32, emit=(0.05, 0.05, 0.055), emit_strength=E),
                                C.diamond_texture('CarbonWeave', size=128, cells=16, strand=0.07, hole=0.035, width=0.25))
    M['CabVent'] = C.textured(C.mat('CabVent', (0.02, 0.02, 0.022), 0.2, 0.6, emit=(0.02, 0.02, 0.022), emit_strength=E),
                              C.diamond_texture('VentMesh', size=128, cells=10, strand=0.08, hole=0.008, width=0.18))
    for k in ('CabCarbon', 'CabVent'):
        M[k].use_backface_culling = False
    return M


# ------------------------------------------------------------------ helpers
def loft(bm, sections, mat=0, cap0=False, cap1=False, closed=False):
    rings = [[bm.verts.new(Vector(p)) for p in sec] for sec in sections]
    n = len(rings[0]); fs = []
    for i in range(len(rings) - 1):
        for k in range(n if closed else n - 1):
            a, b = rings[i][k], rings[i][(k + 1) % n]
            c, d = rings[i + 1][(k + 1) % n], rings[i + 1][k]
            f = bm.faces.new((a, b, c, d)); f.material_index = mat; fs.append(f)
    if cap0:
        f = bm.faces.new(rings[0][::-1]); f.material_index = mat; fs.append(f)
    if cap1:
        f = bm.faces.new(rings[-1]); f.material_index = mat; fs.append(f)
    return fs


def face_eye(bm):
    """Orient every face toward the eye (origin) — for open shells around the driver."""
    for f in bm.faces:
        c = f.calc_center_median()
        if f.normal.dot(-c) < 0:
            f.normal_flip()


def obj(name, bm, mats, smooth=True, sharp=40, toward_eye=True):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.normal_update()
    if toward_eye:
        face_eye(bm)
    o = C.new_obj(name, bm, mats, smooth=smooth)
    if smooth:
        o.data.set_sharp_from_angle(angle=math.radians(sharp))
    return o


def _bisect_keep(me, co, no, keep_positive):
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6, plane_co=co, plane_no=no,
                           clear_inner=keep_positive, clear_outer=not keep_positive)
    bm.to_mesh(me); n = len(bm.faces); bm.free()
    return n


def split_pieces(o, x_split=None, y_split=None):
    """Split o into sightline-safe pieces: Z <= -BAND / band / >= BAND, each band/low piece
    optionally split at X = x_split (driver vs passenger side)."""
    pieces = []
    zones = [('Lo', [((0, 0, -BAND), (0, 0, 1), False)]),
             ('Mid', [((0, 0, -BAND), (0, 0, 1), True), ((0, 0, BAND), (0, 0, 1), False)]),
             ('Hi', [((0, 0, BAND), (0, 0, 1), True)])]
    for suf, cuts in zones:
        sides = [('', [])]
        if x_split is not None and suf != 'Hi':
            sides = []
            for fb, fcut in (('F', ((0, 0, 0), (0, 1, 0), True)), ('R', ((0, 0, 0), (0, 1, 0), False))):
                sides.append(('D' + fb, [((x_split, 0, 0), (1, 0, 0), False), fcut]))
                sides.append(('P' + fb, [((x_split, 0, 0), (1, 0, 0), True), fcut]))
        for sname, scut in sides:
            me = o.data.copy(); n = 1
            for co, no, keep in cuts + scut:
                n = _bisect_keep(me, co, no, keep)
                if n == 0:
                    break
            if n == 0:
                bpy.data.meshes.remove(me); continue
            p = bpy.data.objects.new(o.name + suf + sname, me); me.name = p.name + "Mesh"
            bpy.context.scene.collection.objects.link(p)
            for poly in me.polygons:
                poly.use_smooth = True
            pieces.append(p)
    bpy.data.objects.remove(o, do_unlink=True)
    return pieces


# ------------------------------------------------------------------ exterior-derived greenhouse
def greenhouse_shell(M):
    """Roof, A/B/C-pillars and rails = the exterior body's non-glass greenhouse faces, inset
    25 mm, with a 25 mm return along every window edge so pillars read as solid trim."""
    mats = {k: C.mat(k, (0.5, 0.5, 0.5)) for k in ('CarPaint', 'GlassW', 'GlassS', 'GlassR', 'DarkTrim')}
    body, ys, L = B.build_body(mats)
    sd = body.modifiers.new('sd', 'SUBSURF'); sd.levels = 1
    C.bake_modifiers(body)
    me = body.data
    bm = bmesh.new(); bm.from_mesh(me)
    bm.normal_update()
    keep = []
    for f in bm.faces:
        c = f.calc_center_median()
        if f.material_index in (0, 4) and c.z > 0.985 and -0.80 < c.y < 1.62 and abs(c.x) < 0.84:
            keep.append(f)
    ks = set(keep)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in ks], context='FACES')
    bm.normal_update()
    orig = {v: v.co.copy() for v in bm.verts}
    for v in bm.verts:
        v.co = v.co - v.normal * 0.025
    bnd = [e for e in bm.edges if e.is_boundary]
    new_of = {}
    for v in {v for e in bnd for v in e.verts}:
        new_of[v] = bm.verts.new(orig[v] - v.normal * 0.004)
    for e in bnd:
        a, b = e.verts
        try:
            bm.faces.new((a, b, new_of[b], new_of[a]))
        except ValueError:
            pass
    for f in bm.faces:
        f.material_index = 0
    for v in bm.verts:
        v.co = T(v.co)
    bpy.data.objects.remove(body, do_unlink=True)
    o = obj("CabShell", bm, [M['CabHeadliner']], sharp=55)
    return split_pieces(o, x_split=XC)


def door_trims(M):
    """Inner door + quarter trims following the exterior side section (inset 90-110 mm)."""
    out = []
    zs = [0.30, 0.42, 0.55, 0.62, 0.68, 0.80, 0.92]
    ys = [-0.78, -0.62, -0.40, -0.15, 0.10, 0.35, 0.55, 0.80, 1.05, 1.30]
    def x_at(half, z):
        best = None
        for (x0, z0), (x1, z1) in zip(half[:-1], half[1:]):
            if min(z0, z1) <= z <= max(z0, z1) and z1 != z0 and x0 > 0.5 and x1 > 0.5:
                t = (z - z0) / (z1 - z0); x = x0 + (x1 - x0) * t
                best = x if best is None else max(best, x)
        return best if best is not None else 0.85
    for side, sgn in (('Drv', 1), ('Pas', -1)):
        bm = bmesh.new()
        secs = []
        for yb in ys:
            half, L = B.half_profile(yb)
            zbelt = half[L['belt']][1]
            sec = []
            for z in zs + [zbelt - 0.03]:
                inset = 0.11 if z < 0.75 else 0.085
                if abs(z - 0.62) < 0.05:
                    inset = 0.135   # armrest bulge
                sec.append(T((sgn * (x_at(half, z) - inset), yb, z)))
            xo = x_at(half, zbelt - 0.01)
            sec.append(T((sgn * (xo - 0.03), yb, zbelt + 0.004)))   # window sill
            secs.append(sec)
        fs = loft(bm, secs, 0)
        for f in fs:
            c = f.calc_center_median()
            zb = c.z + 1.08; yb = 0.18 - c.y
            if 0.56 < zb < 0.69 and -0.55 < yb < 0.55:
                f.material_index = 1
        out.append(obj("CabDoor" + side, bm, [M['CabBlack'], M['CabTan']], sharp=35))
    return out


# ------------------------------------------------------------------ dash / binnacle / stack
XD, XP = -0.36, 1.08


def dash(M):
    out = []
    bm = bmesh.new()
    secs = []
    for i in range(25):
        x = XD + (XP - XD) * i / 24
        dd = abs(x - XC) / 0.72
        cy = 0.955 - 0.07 * dd ** 2
        secs.append([(x, cy, -0.090), (x, 0.86, -0.094), (x, 0.76, -0.104), (x, 0.69, -0.118), (x, 0.655, -0.132), (x, 0.635, -0.152), (x, 0.628, -0.180)])
    loft(bm, secs, 0)
    C.box(bm, (XC, 0.925, -0.0885), (1.10, 0.035, 0.003), 1)       # defroster strip
    out.append(obj("CabDashTop", bm, [M['CabSoft'], M['CabVent']]))
    # dash face either side of the binnacle (tan band on the passenger side)
    bm = bmesh.new()
    prof = [(0.628, -0.180), (0.622, -0.215), (0.612, -0.250), (0.590, -0.330), (0.555, -0.420), (0.515, -0.500), (0.475, -0.570)]
    for (x0, x1) in ((XD, -0.185), (0.505, XP)):
        n = 10 if x1 - x0 > 0.4 else 5
        fs = loft(bm, [[(x0 + (x1 - x0) * i / n, y, z) for (y, z) in prof] for i in range(n + 1)], 0)
        for f in fs:
            c = f.calc_center_median()
            if -0.262 < c.z < -0.205 and (c.x > 0.52 or c.x < -0.20):
                f.material_index = 1
    out.append(obj("CabDashFace", bm, [M['CabBlack'], M['CabTan']]))
    # binnacle cowl: lip above the dials' top ray (dial top at -18.7 deg), top below the cowl line
    bm = bmesh.new()
    def arch(y, ztop, half, zfoot):
        pts = [(-half - 0.012, y, zfoot)]
        for i in range(11):
            t = -1 + 2 * i / 10
            pts.append((half * t, y, ztop - 0.032 * t * t))
        pts.append((half + 0.012, y, zfoot))
        return pts
    secs = [arch(0.625, -0.168, 0.185, -0.40), arch(0.645, -0.152, 0.190, -0.40), arch(0.72, -0.134, 0.195, -0.38),
            arch(0.82, -0.112, 0.20, -0.36), arch(0.88, -0.100, 0.20, -0.32)]
    loft(bm, secs, 0)
    out.append(obj("CabBinnacle", bm, [M['CabSoft']]))
    # gauge tunnel: backdrop + carbon surround ring, knee panel, column shroud
    bm = bmesh.new()
    C.box(bm, (0.0, DIAL_Y + 0.022, DIAL_Z + 0.01), (0.38, 0.01, 0.22), 1)
    for sx in (-1, 1):
        C.box(bm, (sx * 0.19, 0.74, -0.31), (0.012, 0.24, 0.20), 1)
    kp = [(0.630, -0.405), (0.600, -0.460), (0.545, -0.530), (0.490, -0.585)]
    loft(bm, [[(-0.185 + 0.69 * i / 6, y, z) for (y, z) in kp] for i in range(7)], 1)
    ax = Vector((0, -0.866, 0.5))   # wheel axis toward the driver (cabin frame)
    C.ring_tube(bm, WHEEL_C - ax * 0.10, -ax, [(0.0, 0.050), (0.14, 0.056), (0.20, 0.070)], segs=16, cap_start=True, mat_idx=1)
    out.append(obj("CabGaugeTunnel", bm, [M['CabGloss'], M['CabBlack']], sharp=35))
    # round end vents
    for nm, (vx, vz) in (("CabVentDrv", (XD + 0.10, -0.232)), ("CabVentPas", (XP - 0.10, -0.232))):
        bm = bmesh.new()
        c = Vector((vx, 0.612, vz)); a = Vector((0, -1, 0))
        C.ring_tube(bm, c, a, [(-0.03, 0.058), (0.004, 0.058), (0.010, 0.054), (0.010, 0.046), (0.0, 0.044), (-0.02, 0.044)], segs=28, mat_idx=0)
        C.ring_tube(bm, c - a * 0.02, a, [(0.0, 0.044), (0.0, 0.002)], segs=28, mat_idx=1)
        for k in range(5):
            ang = 2 * math.pi * k / 5
            d = Vector((math.cos(ang), 0, math.sin(ang)))
            C.box(bm, tuple(c - a * 0.012 + d * 0.022), (0.042 * abs(math.cos(ang)) + 0.006, 0.004, 0.042 * abs(math.sin(ang)) + 0.006), 1)
        out.append(obj(nm, bm, [M['CabAlloy'], M['CabGloss']], sharp=30, toward_eye=False))
    return out


STACK_FACE = [(0.800, -0.112), (0.780, -0.160), (0.755, -0.220), (0.720, -0.300), (0.680, -0.400), (0.640, -0.480), (0.600, -0.540)]


def stack_y(z):
    for (y0, z0), (y1, z1) in zip(STACK_FACE[:-1], STACK_FACE[1:]):
        if z1 <= z <= z0:
            return y0 + (y1 - y0) * (z - z0) / (z1 - z0)
    return STACK_FACE[-1][0]


def centre_stack(M):
    out = []
    bm = bmesh.new()
    x0, x1 = XC - 0.145, XC + 0.145
    loft(bm, [[(x0 + (x1 - x0) * i / 8, y, z) for (y, z) in STACK_FACE] for i in range(9)], 0)
    for x, sgn in ((x0, -1), (x1, 1)):
        prof = [(x, y + 0.002, z) for (y, z) in STACK_FACE]
        outer = [(x + sgn * 0.025, y - 0.01, z) for (y, z) in STACK_FACE]
        deep = [(x + sgn * 0.025, 0.95, z) for (y, z) in STACK_FACE]
        loft(bm, [prof, outer, deep], 1)
    out.append(obj("CabStack", bm, [M['CabBlack'], M['CabTan']]))
    bm = bmesh.new()
    def panel(xa, xb, za, zb, inset, mat):
        ya, yb = stack_y(za) - inset, stack_y(zb) - inset
        loft(bm, [[(xa, ya, za), (xa, yb, zb)], [(xb, ya, za), (xb, yb, zb)]], mat)
    panel(XC - 0.125, XC + 0.125, -0.140, -0.290, 0.004, 0)    # screen bezel (MFD quad in front)
    panel(XC - 0.120, XC + 0.120, -0.305, -0.350, 0.004, 1)    # centre vents
    panel(XC - 0.110, XC + 0.110, -0.370, -0.440, 0.004, 0)    # climate surround (NavScreen in front)
    panel(XC - 0.120, XC + 0.120, -0.455, -0.520, 0.004, 2)    # switch bank
    out.append(obj("CabStackPanels", bm, [M['CabGloss'], M['CabVent'], M['CabAlloy']], smooth=False))
    return out


def console(M):
    out = []
    bm = bmesh.new()
    x0, x1 = XC - 0.15, XC + 0.15
    prof_y = [0.60, 0.45, 0.20, -0.05, -0.15, -0.42]
    top_z = [-0.540, -0.540, -0.540, -0.544, -0.500, -0.490]
    secs = [[(x0 - 0.01, y, -0.86), (x0, y, zt - 0.04), (x0 + 0.02, y, zt), (x1 - 0.02, y, zt), (x1, y, zt - 0.04), (x1 + 0.01, y, -0.86)]
            for y, zt in zip(prof_y, top_z)]
    fs = loft(bm, secs, 0, cap1=True)
    for f in fs:
        c = f.calc_center_median()
        if c.z > -0.56 and c.y < -0.08:
            f.material_index = 1
        elif c.z > -0.55 and abs(c.x - XC) < 0.13 and c.y > -0.08:
            f.material_index = 2
    out.append(obj("CabConsole", bm, [M['CabBlack'], M['CabTan'], M['CabCarbon']], sharp=35, toward_eye=False))
    bm = bmesh.new()
    C.ring_tube(bm, (XC, 0.43, -0.524), (0, -0.25, 1), [(0.0, 0.012), (0.07, 0.011)], segs=12, mat_idx=0)
    C.ring_tube(bm, (XC, 0.413, -0.455), (0, -0.25, 1), [(-0.005, 0.016), (0.02, 0.022), (0.055, 0.020), (0.07, 0.012), (0.075, 0.001)], segs=16, mat_idx=1)
    out.append(obj("CabShifter", bm, [M['CabAlloy'], M['CabTan']], toward_eye=False))
    return out


def floor_rear(M):
    out = []
    bm = bmesh.new()
    secs = [[(x, -0.55, -0.86), (x, 0.55, -0.86), (x, 0.80, -0.80), (x, 1.00, -0.58), (x, 1.04, -0.30)]
            for x in [XD - 0.04 + (XP - XD + 0.08) * i / 8 for i in range(9)]]
    loft(bm, secs, 0)
    out.append(obj("CabFloor", bm, [M['CabCarpet']], smooth=False))
    # rear seats, bulkhead and parcel shelf (seen in the look-around and the rear glass)
    bm = bmesh.new()
    for xc in (0.0, 0.72):
        C.box(bm, (xc, -0.95, -0.62), (0.46, 0.42, 0.12), 0)
        C.box(bm, (xc, -1.17, -0.38), (0.46, 0.10, 0.50), 0, rot=Matrix.Rotation(math.radians(-18), 3, 'X'))
    C.box(bm, (XC, -1.42, -0.10), (1.40, 0.42, 0.03), 1)
    out.append(obj("CabRear", bm, [M['CabTan'], M['CabBlack']], smooth=False, toward_eye=False))
    return out


def roof_details(M):
    out = []
    bm = bmesh.new()
    C.box(bm, (XC, 0.352, 0.221), (0.06, 0.05, 0.010), 0)              # mount pad on the header
    C.box(bm, (XC, 0.396, 0.193), (0.018, 0.018, 0.108), 0, rot=Matrix.Rotation(math.radians(58.6), 3, "X"))  # stalk header->mirror
    C.box(bm, (XC, 0.455, 0.135), (0.215, 0.026, 0.056), 0)
    C.box(bm, (XC, 0.4415, 0.135), (0.203, 0.003, 0.046), 1)
    out.append(obj("CabRearMirror", bm, [M['CabBlack'], M['CabMirror']], smooth=False, toward_eye=False))
    bm = bmesh.new()
    C.box(bm, (-0.10, 0.27, 0.221), (0.30, 0.16, 0.012), 0)
    C.box(bm, (0.82, 0.27, 0.221), (0.30, 0.16, 0.012), 0)
    out.append(obj("CabVisors", bm, [M['CabSoft']], smooth=False, toward_eye=False))
    return out


def seats(M):
    out = []
    for nm, xc in (("CabSeatDrv", 0.0), ("CabSeatPas", 0.72)):
        bm = bmesh.new()
        secs = []
        for y in (-0.34, -0.12, 0.10, 0.24):
            secs.append([(xc - 0.27, y, -0.84), (xc - 0.27, y, -0.64), (xc - 0.20, y, -0.60), (xc - 0.15, y, -0.66),
                         (xc + 0.15, y, -0.66), (xc + 0.20, y, -0.60), (xc + 0.27, y, -0.64), (xc + 0.27, y, -0.84)])
        loft(bm, secs, 0, cap0=True, cap1=True)
        secs = []
        for t in (0.0, 0.3, 0.6, 0.85, 1.0):
            z = -0.64 + 0.70 * t
            y = -0.32 - 0.17 * t
            w = 0.27 - 0.05 * t
            bol = 0.07 * (1 - t) + 0.03
            secs.append([(xc - w, y + bol, z), (xc - w + 0.03, y - 0.05, z), (xc - 0.14, y - 0.01, z), (xc + 0.14, y - 0.01, z),
                         (xc + w - 0.03, y - 0.05, z), (xc + w, y + bol, z), (xc + w - 0.05, y - 0.16, z), (xc - w + 0.05, y - 0.16, z)])
        loft(bm, secs, 0, cap1=True, closed=True)
        C.box(bm, (xc, -0.52, 0.12), (0.24, 0.09, 0.15), 1)
        o = obj(nm, bm, [M['CabTan'], M['CabBlack']], sharp=50, toward_eye=False)
        if nm == "CabSeatDrv":
            out += split_y(o, -0.20)
        else:
            out.append(o)
    return out


def split_y(o, ycut):
    pieces = []
    for keep_front, suf in ((True, 'Cushion'), (False, 'Back')):
        me = o.data.copy()
        _bisect_keep(me, (0, ycut, 0), (0, 1, 0), keep_front)
        p = bpy.data.objects.new(o.name + suf, me); me.name = p.name + "Mesh"
        bpy.context.scene.collection.objects.link(p)
        for poly in me.polygons:
            poly.use_smooth = True
        pieces.append(p)
    bpy.data.objects.remove(o, do_unlink=True)
    return pieces


# ------------------------------------------------------------------ previews / checks
def preview_standins(M):
    """Approximate the Godot primitives (wheel, hub, spokes, dials, screens) for Blender previews only."""
    ax = Vector((0, -math.cos(WHEEL_TILT), math.sin(WHEEL_TILT)))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.1625, minor_radius=0.0175, location=WHEEL_C)
    t = bpy.context.active_object; t.name = "Preview_Wheel"
    t.rotation_euler = ax.to_track_quat('Z', 'Y').to_euler()
    t.data.materials.append(M['CabBlack'])
    bpy.ops.mesh.primitive_cylinder_add(radius=0.072, depth=0.05, location=WHEEL_C - ax * 0.015)
    h = bpy.context.active_object; h.name = "Preview_Hub"; h.rotation_euler = t.rotation_euler; h.data.materials.append(M['CabBlack'])
    for nm, x, col in (("Preview_Speedo", -DIAL_DX, (0.8, 0.8, 0.85)), ("Preview_Tach", DIAL_DX, (0.9, 0.3, 0.2))):
        mm = C.mat(nm + "M", col, emit=col, emit_strength=0.6)
        bpy.ops.mesh.primitive_circle_add(vertices=32, radius=DIAL_R, fill_type='NGON', location=(x, DIAL_Y, DIAL_Z), rotation=(math.pi / 2, 0, 0))
        ob = bpy.context.active_object; ob.name = nm; ob.data.materials.append(mm)
    for nm, z, w, h in (("Preview_MFD", -0.215, 0.19, 0.12), ("Preview_Nav", -0.40, 0.17, 0.056)):
        mm = C.mat(nm + "M", (0.25, 0.5, 0.85), emit=(0.25, 0.5, 0.85), emit_strength=1.0)
        bpy.ops.mesh.primitive_plane_add(size=1, location=(XC, stack_y(z) - 0.006, z), rotation=(math.radians(90 - 22), 0, 0))
        ob = bpy.context.active_object; ob.name = nm; ob.scale = (w, h, 1); ob.data.materials.append(mm)


def sightline_report():
    bad = []
    for o in bpy.data.objects:
        if o.type != 'MESH' or o.name.startswith('Preview_') or o.name in ('Floor',) or not o.data.vertices:
            continue
        ws = [o.matrix_world @ v.co for v in o.data.vertices]
        xmin = min(v.x for v in ws); xmax = max(v.x for v in ws); ymax = max(v.y for v in ws)
        zmin = min(v.z for v in ws); zmax = max(v.z for v in ws)
        if -ymax >= 0:
            continue
        x_near = 0.0 if (xmin <= 0 <= xmax) else min(abs(xmin), abs(xmax))
        if (x_near - 0.3 * ymax) <= 0.0 and zmax > -0.05 and zmin < 0.05:
            bad.append((o.name, round(x_near, 3), round(0.3 * ymax, 3), round(zmin, 3), round(zmax, 3)))
    print("SIGHTLINE offenders:", bad if bad else "none")
    return bad


def build():
    C.clear_scene()
    M = M_()
    parts = (greenhouse_shell(M) + door_trims(M) + dash(M) + centre_stack(M) + console(M) + floor_rear(M)
             + roof_details(M) + seats(M))
    for p in parts:
        C.recenter(p)
    return M, parts


if __name__ == "__main__":
    M, parts = build()
    print("CABIN parts", len(parts), "tris", sum(C.tri_count(p) for p in parts), [p.name for p in parts])
    sightline_report()
    if ARGS[0] == 'render':
        import r35_render as R; importlib.reload(R)
        preview_standins(M)
        R.setup_studio(res=(1280, 720), samples=16)
        fl = bpy.data.objects.get('Floor'); fl.location.z = -1.08
        views = {'eye': ((0, 0, 0), (0, 1, 0), 0), 'eye_left': ((0, 0, 0), (-1, 0.9, -0.1), 0),
                 'eye_right': ((0, 0, 0), (1, 0.75, -0.2), 0)}
        sc = bpy.context.scene
        for name, (loc, tgt, f) in views.items():
            cam = bpy.data.objects.get('RCam') or bpy.data.objects.new('RCam', bpy.data.cameras.new('RCam'))
            if cam.name not in sc.collection.objects:
                sc.collection.objects.link(cam)
            cam.location = loc
            cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            cam.data.type = 'PERSP'; cam.data.sensor_fit = 'VERTICAL'; cam.data.angle_y = math.radians(60)
            cam.data.clip_start = 0.01
            sc.camera = cam
            sc.render.filepath = os.path.join(HERE, 'renders', 'cab2_' + name + '.png')
            bpy.ops.render.render(write_still=True)
    elif ARGS[0] == 'export':
        for o in bpy.data.objects:
            o.select_set(o.type == 'MESH' and not o.name.startswith('Preview_'))
        bpy.ops.export_scene.gltf(filepath=ARGS[1], export_format='GLB', use_selection=True, export_yup=True,
                                  export_apply=True, export_lights=False, export_cameras=False, export_materials='EXPORT')
        print("exported", ARGS[1])
