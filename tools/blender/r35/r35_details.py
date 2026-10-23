# R35 exterior detailing: fascia, lamps, vents, panel lines, aero, mirrors, exhausts.
import bpy, bmesh, math
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
import r35_common as C

D = C.decal


def _bvh(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    return BVHTree.FromObject(ob, dg)


def bvh_multi(objs):
    bm = bmesh.new()
    for o in objs:
        if o is None:
            continue
        me = o.data.copy(); me.transform(o.matrix_world)
        bm.from_mesh(me); bpy.data.meshes.remove(me)
    t = BVHTree.FromBMesh(bm); bm.free()
    return t


def hit(bvh, origin, direction):
    loc, nrm, idx, dist = bvh.ray_cast(Vector(origin), Vector(direction).normalized(), 10.0)
    return loc, nrm


def lamp(bm_map, center, axis, R, kind='tail'):
    """Round lamp at `center` facing `axis`. bm_map: dict part->bmesh."""
    a = Vector(axis).normalized()
    up = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((1, 0, 0))
    u = up.cross(a).normalized(); v = a.cross(u).normalized()
    segs = 40

    def rev(bm, prof):
        rings = []
        for (t, r) in prof:
            rings.append([bm.verts.new(center + a * t + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r)
                          for k in range(segs)])
        for i in range(len(rings) - 1):
            for k in range(segs):
                bm.faces.new((rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k]))
    # chrome-dark bezel ring
    rev(bm_map['bezel'], [(-0.05, R + 0.016), (0.004, R + 0.016), (0.012, R + 0.010), (0.014, R + 0.002), (0.008, R - 0.002)])
    # red lens: domed annulus
    rev(bm_map['lens'], [(0.008, R - 0.002), (0.016, R * 0.92), (0.020, R * 0.75), (0.019, R * 0.56), (0.014, R * 0.48), (0.004, R * 0.46)])
    # inner reflector cup + centre lamp
    rev(bm_map['inner'], [(0.004, R * 0.46), (-0.008, R * 0.40), (-0.012, R * 0.28), (-0.006, R * 0.20), (0.000, R * 0.12), (0.002, 0.0005)])



class LensField:
    """Smooth quadratic y = f(x, z) fitted to the body over an outline (front view), pushed out so
    it clears every bump. Lamp lenses/DRL/amber layers are built on it => clean glass, no facet ripple."""

    def __init__(self, poly, bvh, margin=0.004, grid=0.012):
        import numpy as np
        self.np = np
        xs = [p[0] for p in poly]; zs = [p[1] for p in poly]
        pts = []
        x = min(xs)
        while x <= max(xs):
            z = min(zs)
            while z <= max(zs):
                if C.point_in_poly((x, z), poly):
                    loc, n = hit(bvh, (x, -4.0, z), (0, 1, 0))
                    if loc is not None:
                        pts.append((x, z, loc.y))
                z += grid
            x += grid
        for q in C.resample(poly, grid):
            loc, n = hit(bvh, (q.x, -4.0, q.y), (0, 1, 0))
            if loc is not None:
                pts.append((q.x, q.y, loc.y))
        A = np.array([[1, x, z, x * x, x * z, z * z] for (x, z, y) in pts])
        Y = np.array([y for (x, z, y) in pts])
        self.coef = np.linalg.lstsq(A, Y, rcond=None)[0]
        res = Y - A @ self.coef
        self.shift = float(res.min()) - margin
        print("LensField samples", len(pts), "rms", float(np.sqrt((res ** 2).mean())), "shift", self.shift)

    def y(self, x, z):
        c = self.coef
        return float(c[0] + c[1] * x + c[2] * z + c[3] * x * x + c[4] * x * z + c[5] * z * z + self.shift)

    def normal(self, x, z):
        c = self.coef
        fx = c[1] + 2 * c[3] * x + c[4] * z
        fz = c[2] + c[4] * x + 2 * c[5] * z
        return Vector((fx, -1.0, fz)).normalized()

    bulge = None

    def layer(self, name, poly, mat, dy=0.0, step=0.012, wall_to=None, wall_mat=None):
        """Triangulated polygon on the field (offset dy along -y). Optional skirt down to the body."""
        vs, fs = C.fill_poly_2d(poly, step)
        bm = bmesh.new()
        bg = self.bulge or (lambda x, z: 0.0)
        bv = [bm.verts.new((x, self.y(x, z) + dy + bg(x, z), z)) for (x, z) in vs]
        for f in fs:
            try:
                bm.faces.new([bv[i] for i in f])
            except ValueError:
                pass
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if bm.faces and bm.faces[0].normal.y > 0:
            for f in bm.faces:
                f.normal_flip()
        mats = [mat]
        if wall_to is not None:
            wi = len(mats); mats.append(wall_mat)
            ring = C.resample(poly, 0.02)
            top_v, bot_v = [], []
            for q in ring:
                loc, n = hit(wall_to, (q.x, -4.0, q.y), (0, 1, 0))
                yt = self.y(q.x, q.y) + dy + bg(q.x, q.y)
                yb = loc.y if loc is not None else yt + 0.012
                if yb < yt:
                    yb = yt
                top_v.append(bm.verts.new((q.x, yt, q.y))); bot_v.append(bm.verts.new((q.x, yb + 0.004, q.y)))
            nr = len(ring)
            for k in range(nr):
                f = bm.faces.new((top_v[k], bot_v[k], bot_v[(k + 1) % nr], top_v[(k + 1) % nr]))
                f.material_index = wi
        ob = C.new_obj(name, bm, mats)
        return ob


def build_details(M, body):
    out = []
    bvh = _bvh(body)
    # ---------------------------------------------------------------- underbody dark
    me = body.data
    import r35_body as _B
    for p in me.polygons:
        if p.normal.z < -0.55 and p.center.z < 0.30:
            p.material_index = 1  # DarkTrim
        elif p.center.y < -1.9 and p.center.z < _B.param('zb', p.center.y) + 0.062:
            p.material_index = 1  # carbon lower lip band (clean, row-aligned)
    me.update()
    bvh = _bvh(body)

    # ---------------------------------------------------------------- FRONT
    import r35_recess as RC
    UG = bpy.data.objects.get("UpperGrille") or body
    FI = bpy.data.objects.get("FrontIntake") or body
    # V-motion bar: satin chrome V on the lower edge of the black upper opening
    out.append(D("GrilleChrome", [(-0.386, 0.594), (-0.298, 0.514), (0.298, 0.514), (0.386, 0.594)], UG, M['Chrome'], 'front', offset=0.054, step=0.010, strip=0.030))
    # graphite bumper bar: a smooth bulged sheet over the cut region (sells the convex bar of the reference)
    BAR = [(-0.535, 0.500), (0.535, 0.500), (0.568, 0.338), (-0.568, 0.338)]
    bvh_bar = bvh_multi([body])
    LB = LensField([(-0.52, 0.476), (0.52, 0.476), (0.55, 0.345), (-0.55, 0.345)], bvh_bar, margin=0.002)
    LB.bulge = lambda x, z: -0.016 * math.sin(math.pi * min(1.0, max(0.0, (z - 0.338) / 0.162))) * max(0.0, 1.0 - (x / 0.62) ** 4)
    bar = LB.layer("GraphiteBar", RC.offset_poly(BAR, 0.004), M['BumperBar'], dy=-0.001, step=0.016, wall_to=bvh_bar, wall_mat=M['BumperBar'])
    flap = [(0.362, 0.462), (0.438, 0.462), (0.448, 0.452), (0.448, 0.385), (0.438, 0.375), (0.362, 0.375), (0.352, 0.385), (0.352, 0.452)]
    f_out = LB.layer("TowFlapEdge", flap, M['LampBezel'], dy=-0.0035, step=0.012)
    f_in = LB.layer("TowFlap", RC.offset_poly(flap, 0.0035), M['BumperBar'], dy=-0.0045, step=0.012)
    circ0 = [(0.497 + 0.0105 * math.cos(2 * math.pi * k / 14), 0.424 + 0.0105 * math.sin(2 * math.pi * k / 14)) for k in range(14)]
    sens0 = LB.layer("PSensorBar", circ0, M['LampBezel'], dy=-0.0045, step=0.01)
    barg = C.join([bar, f_out, f_in, sens0], "GraphiteBar_L") if False else None
    barobj = C.join([bar, f_out, f_in, sens0], "FrontBar")
    out.append(barobj)
    # GT-R badge: black plate, chrome "GT" bar, red "R" block
    bdg = [D("BadgePlate", [(-0.047, 0.538), (0.047, 0.538), (0.047, 0.600), (-0.047, 0.600)], UG, M['LampBezel'], 'front', offset=0.052, step=0.01),
           D("BadgeGT", [(-0.036, 0.578), (0.036, 0.578), (0.036, 0.592), (-0.036, 0.592)], UG, M['Chrome'], 'front', offset=0.055, step=0.008),
           D("BadgeR", [(-0.020, 0.546), (0.032, 0.546), (0.032, 0.572), (-0.020, 0.572)], UG, M['LampRed'], 'front', offset=0.055, step=0.008)]
    out.append(C.join(bdg, "BadgeFront"))
    # intercooler core + cross bars seen through the lower mouth (depth cue)
    core = D("IntercoolerCore", [(-0.520, 0.318), (0.520, 0.318), (0.540, 0.214), (-0.540, 0.214)], FI, M['GrilleMesh'], 'front', offset=0.030, step=0.02, uv_scale=0.05)
    bars = [D("MouthBarH", [(-0.575, 0.268), (0.575, 0.268)], FI, M['DarkTrim'], 'front', offset=0.034, step=0.02, strip=0.014),
            D("MouthBarV1", [(-0.14, 0.325), (-0.14, 0.205)], FI, M['DarkTrim'], 'front', offset=0.034, step=0.02, strip=0.012),
            D("MouthBarV2", [(0.14, 0.325), (0.14, 0.205)], FI, M['DarkTrim'], 'front', offset=0.034, step=0.02, strip=0.012)]
    out.append(C.join([core] + bars, "IntercoolerCore"))
    # chrome lip along the bottom of the mouth
    out.append(D("MouthLip", [(-0.588, 0.172), (0.588, 0.172)], body, M['Chrome'], 'front', offset=0.004, step=0.012, strip=0.008))
    # corner intake DRL (LED bar)
    segs_ = []
    for k in range(4):
        x0 = 0.742 + k * 0.0245; x1 = x0 + 0.0195
        zb0 = 0.423 + (x0 - 0.742) * 0.07; zb1 = 0.423 + (x1 - 0.742) * 0.07
        segs_.append(D("DRLseg", [(x0, zb0), (x1, zb1), (x1, zb1 + 0.036), (x0, zb0 + 0.036)], bpy.data.objects.get("IntakeCorner_L") or body, M['LampDRL'], 'front', offset=0.020, step=0.01))
    drl_c = C.join(segs_, "DRL_L")
    out += [drl_c, C.mirror_copy(drl_c, "DRL_R")]

    # ---- headlight cluster (front-view coordinates measured on the reference, left lamp = +X)
    HL = [(0.851, 0.802), (0.789, 0.818), (0.739, 0.812), (0.682, 0.722), (0.625, 0.636), (0.633, 0.587),
          (0.682, 0.577), (0.808, 0.590), (0.859, 0.603), (0.861, 0.709)]
    bvh_f = bvh_multi([body])
    LF = LensField(HL, bvh_f)
    hl_h = LF.layer("HL_Housing", HL, M['LampHousing'], dy=-0.001, step=0.010, wall_to=bvh_f, wall_mat=M['LampHousing'])
    reflector = LF.layer("HL_Reflector", RC.offset_poly(HL, 0.009), M['LampReflector'], dy=-0.004, step=0.010)

    def strip_layer(nm, line, width, mat, dy):
        return LF.layer(nm, C.strip_poly(line, width), mat, dy=dy, step=0.006)
    # LED guide: arc over the projectors and down the inner edge, plus the lower edge line
    drl_a = strip_layer("HL_DRL_A", [(0.852, 0.742), (0.795, 0.756), (0.735, 0.750), (0.680, 0.720), (0.644, 0.680), (0.636, 0.632)], 0.011, M['LampDRL'], -0.008)
    drl_b = strip_layer("HL_DRL_B", [(0.640, 0.603), (0.684, 0.592), (0.808, 0.601), (0.850, 0.614)], 0.008, M['LampDRL'], -0.008)
    amber = LF.layer("HL_Amber", [(0.812, 0.786), (0.745, 0.800), (0.724, 0.758), (0.800, 0.742)], M['LampAmber'], dy=-0.007, step=0.008)
    hh = C.join([hl_h, reflector], "HeadlightHousing_L")
    out += [hh, C.mirror_copy(hh, "HeadlightHousing_R")]
    drl_l = C.join([drl_a, drl_b], "HeadlightDRL_L")
    out += [drl_l, C.mirror_copy(drl_l, "HeadlightDRL_R")]
    # projector cups (3D): chrome ring + dark bore + glassy lens dome, seated on the lens field
    bm_ring = bmesh.new(); bm_bore = bmesh.new(); bm_lens = bmesh.new(); bm_lens2 = bmesh.new()
    for (ex, ez, R) in ((0.806, 0.696, 0.027), (0.745, 0.686, 0.027), (0.682, 0.658, 0.037)):
        o = Vector((ex, LF.y(ex, ez) - 0.003, ez))
        ax = LF.normal(ex, ez)
        C.ring_tube(bm_ring, o, ax, [(-0.002, R + 0.008), (0.006, R + 0.008), (0.012, R + 0.005), (0.012, R - 0.002), (0.002, R - 0.008)], segs=24)
        C.ring_tube(bm_bore, o, ax, [(0.002, R - 0.008), (-0.006, R * 0.80), (-0.010, 0.0005)], segs=24)
        lp = [(0.001, R * 0.78), (0.007, R * 0.62), (0.010, R * 0.30), (0.011, 0.0005)]
        C.ring_tube(bm_lens, o, ax, lp, segs=24)
        C.ring_tube(bm_lens2, o, ax, lp, segs=24)
    parts = []
    for nm, b_, mm in (("HL_Ring", bm_ring, 'Chrome'), ("HL_Bore", bm_bore, 'LampBezel'), ("HL_Lens", bm_lens, 'Headlight')):
        bmesh.ops.recalc_face_normals(b_, faces=b_.faces)
        parts.append(C.new_obj(nm, b_, [M[mm]]))
    pr = C.join(parts + [amber], "HeadlightProj_L")
    out += [pr, C.mirror_copy(pr, "HeadlightProj_R")]
    # Headlight_L/R: the glassy lens node (tests + night-lamp mounts key on the name)
    bmesh.ops.recalc_face_normals(bm_lens2, faces=bm_lens2.faces)
    lens_only = C.recenter(C.new_obj("Headlight_L", bm_lens2, [M['Headlight']]))
    out += [lens_only, C.mirror_copy(lens_only, "Headlight_R")]
    # fender swept tail: thin dark slot + LED line along the crown
    hd = Vector((-0.55, 0.80, -0.28))
    tail_pts = [(0.850, -2.135, 0.800), (0.870, -2.050, 0.815), (0.880, -1.950, 0.820), (0.882, -1.850, 0.822), (0.880, -1.760, 0.818)]
    tail = D("HL_Tail", tail_pts, body, M['LampHousing'], 'custom', direction=hd, offset=0.003, step=0.010, strip=0.026)
    tail_l = D("HL_TailLED", [(0.860, -2.120, 0.808), (0.875, -2.050, 0.822), (0.884, -1.950, 0.828), (0.886, -1.860, 0.829)], body, M['LampDRL'], 'custom', direction=hd, offset=0.007, step=0.008, strip=0.008)
    tl = C.join([tail, tail_l], "HeadlightTail_L")
    out += [tl, C.mirror_copy(tl, "HeadlightTail_R")]
    # parking sensors
    sens = []
    for (sx, sz) in ((0.720, 0.540),):
        circ = [(sx + 0.0105 * math.cos(2 * math.pi * k / 14), sz + 0.0105 * math.sin(2 * math.pi * k / 14)) for k in range(14)]
        sens.append(D("PSensor", circ, body, M['LampBezel'], 'front', offset=0.002, step=0.006))
    ps = C.join(sens, "ParkSensors_L")
    out += [ps, C.mirror_copy(ps, "ParkSensors_R")]
    # front lip splitter (carbon) with corner blades, from raycasts at the lip
    bm = bmesh.new()
    bvh_s = bvh_multi([body] + [bpy.data.objects.get(n) for n in ("FrontIntake", "IntakeCorner_L", "IntakeCorner_R")])
    xs = [i / 24 * 0.90 for i in range(-24, 25)]
    top, bot = [], []
    for x in xs:
        loc, n = hit(bvh_s, (x, -4.0, 0.150), (0, 1, 0))
        yf = loc.y if (loc and loc.y < -2.0) else -2.05
        o = Vector((x, yf - 0.030, 0.0))
        i = Vector((x * 0.97, yf + 0.16, 0.0))
        top.append((bm.verts.new((o.x, o.y, 0.131)), bm.verts.new((i.x, i.y, 0.131))))
        bot.append((bm.verts.new((o.x, o.y, 0.108)), bm.verts.new((i.x, i.y, 0.112))))
    for k in range(len(xs) - 1):
        bm.faces.new((top[k][0], top[k + 1][0], top[k + 1][1], top[k][1]))
        bm.faces.new((bot[k][1], bot[k + 1][1], bot[k + 1][0], bot[k][0]))
        bm.faces.new((bot[k][0], bot[k + 1][0], top[k + 1][0], top[k][0]))
    # corner blades: thin carbon fins rising at the outer ends
    for sgn in (1, -1):
        cols = []
        for t in range(0, 9):
            x = sgn * (0.72 + 0.18 * t / 8)
            loc, n = hit(bvh_s, (x, -4.0, 0.150), (0, 1, 0))
            yf = (loc.y if (loc and loc.y < -1.9) else -2.0) - 0.030
            zt = 0.131 + 0.070 * (t / 8) ** 1.5
            cols.append((bm.verts.new((x, yf, 0.108)), bm.verts.new((x, yf, zt)),
                         bm.verts.new((x, yf + 0.014, 0.108)), bm.verts.new((x, yf + 0.014, zt - 0.004))))
        for k in range(len(cols) - 1):
            a, b = cols[k], cols[k + 1]
            for (p0, p1, p2, p3) in ((a[0], b[0], b[1], a[1]), (a[1], b[1], b[3], a[3]), (a[3], b[3], b[2], a[2]), (a[2], b[2], b[0], a[0])):
                bm.faces.new((p0, p1, p2, p3))
        e = cols[-1]
        bm.faces.new((e[0], e[2], e[3], e[1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sp = C.new_obj("FrontSplitter", bm, [M['DarkTrim']], smooth=False)
    C.recenter(sp); out.append(sp)
    # brake-cooling ducts: dark hose mouths aimed at the discs, behind the corner intakes
    bm = bmesh.new()
    for sgn in (1, -1):
        C.ring_tube(bm, (sgn * 0.745, -1.800, 0.285), (-sgn * 0.30, 0.95, -0.12), [(0.0, 0.050), (0.16, 0.045)], segs=16, cap_end=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    out.append(C.recenter(C.new_obj("BrakeDucts", bm, [M['DarkTrim']], smooth=False)))
    # hood vents: louver slats over the pocket floor
    hv_floor = bpy.data.objects.get("HoodVent_L")
    if hv_floor is not None:
        slats = []
        for k in range(4):
            t = (k + 0.5) / 4
            p0 = (0.282 + (0.426 - 0.282) * t, -1.100 + (-0.925 + 1.100) * t)
            p1 = (0.322 + (0.470 - 0.322) * t, -1.150 + (-0.975 + 1.150) * t)
            slats.append(D("VentSlat", [(p0[0] - 0.004, p0[1] + 0.002), (p1[0] + 0.004, p1[1] - 0.002)], hv_floor, M['Graphite'], 'top', offset=0.004, step=0.008, strip=0.008))
        vs_ = C.join(slats, "HoodVentSlats_L")
        out += [vs_, C.mirror_copy(vs_, "HoodVentSlats_R")]
    # hood vents + wipers
    ws = bpy.data.objects.get("Windscreen")
    if ws:
        out.append(C.join([D("WiperA", [(0.60, -0.705), (0.30, -0.700), (-0.04, -0.668)], ws, M['DarkTrim'], 'top', offset=0.010, step=0.01, strip=0.018),
                            D("WiperB", [(0.02, -0.705), (-0.30, -0.700), (-0.60, -0.672)], ws, M['DarkTrim'], 'top', offset=0.010, step=0.01, strip=0.018)], "Wipers"))

    # ---------------------------------------------------------------- SIDES (built on the left, mirrored)
    side = []
    side.append(D("VentChrome", [(-1.00, 0.800), (-0.84, 0.812)], body, M['Chrome'], 'side', offset=0.006, step=0.008, strip=0.014))
    side.append(D("DoorHandle", [(0.442, 0.884), (0.600, 0.884), (0.606, 0.910), (0.448, 0.910)], body, M['Chrome'], 'side', offset=0.004, step=0.01))
    side.append(D("Reflector", [(2.03, 0.78), (2.075, 0.80), (2.095, 0.955), (2.055, 0.945)], body, M['LampRed'], 'side', offset=0.004, step=0.01))
    side.append(D("Marker", [(-1.92, 0.640), (-1.74, 0.652), (-1.74, 0.668), (-1.92, 0.658)], body, M['LampAmber'], 'side', offset=0.004, step=0.01))
    sk = D("SideSkirt", [(-1.02, 0.150), (1.02, 0.150), (1.02, 0.262), (0.0, 0.268), (-1.02, 0.262)], body, M['DarkTrim'], 'side', offset=0.004, step=0.03)
    sl = C.join(side, "SideTrim_L")
    out += [sl, C.mirror_copy(sl, "SideTrim_R"), sk, C.mirror_copy(sk, "SideSkirt_R")]
    sk.name = "SideSkirt_L"

    # mirrors: angular wedge housing (convex hull) on a stalk from the door top, glass faces rearward
    hull = [(0.00, -0.020, -0.022), (0.00, 0.008, -0.022), (0.00, -0.024, 0.026), (0.00, 0.008, 0.026),
            (0.11, -0.078, -0.034), (0.11, 0.012, -0.040), (0.11, -0.072, 0.040), (0.11, 0.012, 0.044),
            (0.19, -0.052, -0.030), (0.19, 0.012, -0.036), (0.19, -0.048, 0.034), (0.19, 0.012, 0.040),
            (0.205, -0.012, 0.000), (0.06, -0.060, 0.044), (0.06, -0.056, -0.034)]
    for sgn, tag in ((1, 'L'), (-1, 'R')):
        bm = bmesh.new()
        vs = [bm.verts.new((sgn * (0.865 + x * 1.05), -0.305 + y * 1.3, 1.040 + z * 1.3)) for (x, y, z) in hull]
        res = bmesh.ops.convex_hull(bm, input=vs)
        bmesh.ops.delete(bm, geom=[g for g in res['geom_interior'] if isinstance(g, bmesh.types.BMVert)], context='VERTS')
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mi = C.new_obj("Mirror_" + tag, bm, [M['CarPaint']], smooth=True)
        mi.data.set_sharp_from_angle(angle=math.radians(28))
        C.recenter(mi); out.append(mi)
        bm = bmesh.new()
        sec0 = [(0.792, -0.375, 0.975), (0.792, -0.335, 0.975), (0.800, -0.335, 1.000), (0.800, -0.375, 1.000)]
        sec1 = [(0.880, -0.328, 1.012), (0.880, -0.302, 1.012), (0.880, -0.302, 1.030), (0.880, -0.328, 1.030)]
        r0 = [bm.verts.new((sgn * x, y, z)) for (x, y, z) in sec0]
        r1 = [bm.verts.new((sgn * x, y, z)) for (x, y, z) in sec1]
        for k in range(4):
            bm.faces.new((r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k]))
        bm.faces.new(r0[::-1]); bm.faces.new(r1)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        arm = C.new_obj("MirrorArm_" + tag, bm, [M['DarkTrim']], smooth=False)
        C.recenter(arm); out.append(arm)
        bm = bmesh.new()
        quad = [(0.885, 0.997), (1.045, 0.996), (1.045, 1.088), (0.885, 1.072)]
        f = bm.faces.new([bm.verts.new((sgn * x, -0.288, z)) for (x, z) in quad])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if f.normal.y < 0:
            f.normal_flip()
        mg = C.new_obj("MirrorFace_" + tag, bm, [M['MirrorChrome']], smooth=False)
        C.recenter(mg); out.append(mg)

    # ---------------------------------------------------------------- REAR
    bms = {'bezel': bmesh.new(), 'lens': bmesh.new(), 'inner': bmesh.new()}
    bms_r = {'bezel': bmesh.new(), 'lens': bmesh.new(), 'inner': bmesh.new()}
    for (x, z, R) in ((0.730, 0.870, 0.104), (0.514, 0.842, 0.083)):
        for sgn, target in ((1, bms), (-1, bms_r)):
            loc, n = hit(bvh, (sgn * x, 4.0, z), (0, -1, 0))
            if loc is None:
                print("lamp miss", x, z); continue
            axis = (n.normalized() + Vector((0, 2.2, 0))).normalized()
            lamp(target, loc - axis * 0.002, axis, R)
    for side_tag, d in (('L', bms), ('R', bms_r)):
        for part, mname, oname in (('bezel', 'LampBezel', 'TailBezel_'), ('lens', 'Taillight', 'Taillight_'), ('inner', 'TailInner', 'TailInner_')):
            bmesh.ops.recalc_face_normals(d[part], faces=d[part].faces)
            ob = C.new_obj(oname + side_tag, d[part], [M[mname]])
            C.recenter(ob); out.append(ob)
    # lower rear: diffuser band, honeycomb, silver U, plate, lines, badges
    out.append(D("DiffuserU", [(-0.47, 0.37), (-0.30, 0.205), (0.30, 0.205), (0.47, 0.37)], body, M['Chrome'], 'rear', offset=0.009, step=0.01, strip=0.022))
    out.append(D("Plate", [(-0.168, 0.470), (0.168, 0.470), (0.168, 0.645), (-0.168, 0.645)], body, M['Plate'], 'rear', offset=0.010, step=0.02))
    bad = []
    circ = [(0.046 * math.cos(2 * math.pi * k / 24), 0.952 + 0.040 * math.sin(2 * math.pi * k / 24)) for k in range(24)]
    bad.append(D("NissanBadge", circ, body, M['Chrome'], 'rear', offset=0.008, step=0.01))
    bad.append(D("GTRBadge", [(-0.43, 0.775), (-0.35, 0.775), (-0.35, 0.815), (-0.43, 0.815)], body, M['Chrome'], 'rear', offset=0.006, step=0.01))
    out.append(C.join(bad, "RearBadges"))
    # exhausts (quad)
    bvh_e = bvh_multi([body] + [bpy.data.objects.get(n) for n in ("ExhaustMesh_L", "ExhaustMesh_R")])
    bm_t = bmesh.new(); bm_i = bmesh.new()
    for x in (0.614, 0.754, -0.614, -0.754):
        loc, n = hit(bvh_e, (x, 4.0, 0.268), (0, -1, 0))
        ys = loc.y if loc else 2.32
        c = Vector((x, ys, 0.268))
        a = Vector((0, 1, 0))
        C.ring_tube(bm_t, c, a, [(-0.06, 0.060), (0.034, 0.0625), (0.046, 0.0610), (0.050, 0.0575), (0.046, 0.0545), (-0.03, 0.0525)], segs=28)
        C.ring_tube(bm_i, c, a, [(-0.03, 0.0525), (-0.04, 0.0001)], segs=28)
    for b in (bm_t, bm_i):
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
    out.append(C.recenter(C.new_obj("Exhaust_Tips", bm_t, [M['ExhaustTip']])))
    out.append(C.recenter(C.new_obj("Exhaust_Inner", bm_i, [M['ExhaustInner']])))
    # rear wing: main plane + end plates + centre stalk
    out += build_wing(M, bvh)
    return out


def airfoil(chord, thick, n=10):
    """Return upper+lower points (s along chord 0..1 -> (dy, dz))."""
    up, lo = [], []
    for i in range(n + 1):
        s = (1 - math.cos(math.pi * i / n)) / 2
        t = 5 * thick * (0.2969 * math.sqrt(s) - 0.1260 * s - 0.3516 * s ** 2 + 0.2843 * s ** 3 - 0.1036 * s ** 4)
        camber = 0.06 * thick * 4 * s * (1 - s)
        up.append((s * chord, camber + t))
        lo.append((s * chord, camber - t))
    return up, lo


def build_wing(M, bvh):
    out = []
    bm = bmesh.new()
    chord, thick = 0.30, 0.11
    up, lo = airfoil(chord, thick)
    prof = up + lo[::-1][1:-1]
    xs = [-0.69 + 1.38 * i / 16 for i in range(17)]
    secs = []
    aoa = math.radians(-8)  # trailing edge up
    for x in xs:
        zc = 1.142 + 0.010 * (x / 0.69) ** 2
        y0 = 1.925
        sec = []
        for (dy, dz) in prof:
            yy = dy * math.cos(aoa) - dz * math.sin(aoa)
            zz = dy * math.sin(-aoa) + dz * math.cos(aoa)
            sec.append(bm.verts.new((x, y0 + yy, zc + zz)))
        secs.append(sec)
    m = len(prof)
    for i in range(len(secs) - 1):
        for k in range(m):
            bm.faces.new((secs[i][k], secs[i][(k + 1) % m], secs[i + 1][(k + 1) % m], secs[i + 1][k]))
    bm.faces.new(secs[0][::-1]); bm.faces.new(secs[-1])
    # end plates: from the deck up to the wing tips (swept fins)
    for sgn in (1, -1):
        x = sgn * 0.69
        loc0, _ = hit(bvh, (x, 2.02, 3.0), (0, 0, -1))
        loc1, _ = hit(bvh, (x, 2.11, 3.0), (0, 0, -1))
        z0 = (loc0.z if loc0 else 1.05) - 0.02
        z1 = (loc1.z if loc1 else 1.03) - 0.02
        zd = (z0 + z1) * 0.5
        pts = [(2.02, zd + 0.005), (2.11, zd), (2.232, 1.150), (2.215, 1.172), (2.13, 1.162)]
        th = 0.018
        ring_o = [bm.verts.new((x + sgn * th / 2, y, z)) for (y, z) in pts]
        ring_i = [bm.verts.new((x - sgn * th / 2, y, z)) for (y, z) in pts]
        bm.faces.new(ring_o); bm.faces.new(ring_i[::-1])
        n = len(pts)
        for k in range(n):
            bm.faces.new((ring_o[k], ring_i[k], ring_i[(k + 1) % n], ring_o[(k + 1) % n]))
    # centre stalk
    loc, _ = hit(bvh, (0, 2.05, 3.0), (0, 0, -1))
    zd = (loc.z if loc else 1.05) - 0.02
    C.box(bm, (0, 2.06, (zd + 1.14) / 2), (0.028, 0.11, 1.14 - zd), 0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    w = C.new_obj("RearWing", bm, [M['CarPaint']], smooth=True)
    w.data.set_sharp_from_angle(angle=math.radians(40))
    C.recenter(w)
    out.append(w)
    return out
