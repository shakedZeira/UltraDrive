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


def build_details(M, body):
    out = []
    bvh = _bvh(body)
    # ---------------------------------------------------------------- underbody dark
    me = body.data
    for p in me.polygons:
        if p.normal.z < -0.55 and p.center.z < 0.30:
            p.material_index = 1  # DarkTrim
    me.update()
    bvh = _bvh(body)

    # ---------------------------------------------------------------- FRONT
    out.append(D("GrilleChrome", [(-0.405, 0.70), (-0.282, 0.563), (0.282, 0.563), (0.405, 0.70)], bpy.data.objects.get("UpperGrille") or body, M['Chrome'], 'front', offset=0.040, step=0.012, strip=0.020))
    out.append(D("BadgeFront", [(-0.038, 0.64), (0.038, 0.64), (0.038, 0.672), (-0.038, 0.672)], bpy.data.objects.get("UpperGrille") or body, M['Chrome'], 'front', offset=0.043, step=0.01))
    l, r = D("DRL_L", [(0.738, 0.468), (0.852, 0.474), (0.852, 0.506), (0.742, 0.500)], bpy.data.objects.get("IntakeCorner_L") or body, M['LampDRL'], 'front', offset=0.008, step=0.01, mirror_name="DRL_R")
    out += [l, r]
    # headlights: boomerang outline on the front-left corner, projected obliquely
    hd = Vector((-0.55, 0.80, -0.28))
    outline = [(0.585, -2.262, 0.700), (0.690, -2.255, 0.655), (0.800, -2.215, 0.640), (0.875, -2.120, 0.665), (0.910, -1.960, 0.730),
               (0.920, -1.790, 0.800), (0.915, -1.660, 0.860), (0.900, -1.630, 0.890), (0.870, -1.680, 0.905), (0.845, -1.840, 0.892),
               (0.815, -2.000, 0.862), (0.760, -2.140, 0.818), (0.680, -2.225, 0.785), (0.600, -2.258, 0.755)]
    hl, hr = D("HeadlightHousing_L", outline, body, M['LampHousing'], 'custom', direction=hd, offset=0.004, step=0.012, mirror_name="HeadlightHousing_R")
    out += [hl, hr]
    drl = [(0.600, -2.262, 0.712), (0.695, -2.255, 0.670), (0.800, -2.214, 0.656), (0.870, -2.120, 0.680), (0.902, -1.960, 0.740), (0.910, -1.800, 0.806), (0.905, -1.680, 0.858)]
    lens_parts = [D("HL_DRL", drl, body, M['Headlight'], 'custom', direction=hd, offset=0.007, step=0.006, strip=0.016)]
    # three projector eyes
    proj_c = [(0.680, -2.232, 0.728), (0.768, -2.180, 0.740), (0.840, -2.085, 0.768)]
    dn, du, dv = C._plane_frame(hd)
    rings = []
    for c in proj_c:
        c = Vector(c)
        circ = [c + (du * math.cos(2 * math.pi * k / 20) + dv * math.sin(2 * math.pi * k / 20)) * 0.036 for k in range(20)]
        rings.append(D("HL_Ring", circ, body, M['Chrome'], 'custom', direction=hd, offset=0.008, step=0.008))
        circ2 = [c + (du * math.cos(2 * math.pi * k / 20) + dv * math.sin(2 * math.pi * k / 20)) * 0.024 for k in range(20)]
        lens_parts.append(D("HL_Lens", circ2, body, M['Headlight'], 'custom', direction=hd, offset=0.011, step=0.007))
    amb = D("HL_Amber", [(0.905, -1.700, 0.874), (0.880, -1.700, 0.900), (0.862, -1.790, 0.893), (0.895, -1.790, 0.868)], body, M['LampAmber'], 'custom', direction=hd, offset=0.008, step=0.006)
    pr_extra = [amb]
    hlL = C.join(lens_parts, "Headlight_L")
    out += [hlL, C.mirror_copy(hlL, "Headlight_R")]
    pr = C.join(rings + pr_extra, "HeadlightProj_L")
    out += [pr, C.mirror_copy(pr, "HeadlightProj_R")]
    # front lip splitter from raycasts at z=0.19
    bm = bmesh.new()
    bvh_f = bvh_multi([body] + [bpy.data.objects.get(n) for n in ("FrontIntake", "IntakeCorner_L", "IntakeCorner_R")])
    xs = [i / 20 * 0.82 for i in range(-20, 21)]
    top, bot = [], []
    for x in xs:
        loc, n = hit(bvh_f, (x, -4.0, 0.20), (0, 1, 0))
        yf = loc.y if (loc and loc.y < -2.05) else -2.05
        o = Vector((x, yf - 0.035, 0.0))
        i = Vector((x * 0.97, yf + 0.14, 0.0))
        top.append((bm.verts.new((o.x, o.y, 0.188)), bm.verts.new((i.x, i.y, 0.188))))
        bot.append((bm.verts.new((o.x, o.y, 0.166)), bm.verts.new((i.x, i.y, 0.170))))
    for k in range(len(xs) - 1):
        bm.faces.new((top[k][0], top[k + 1][0], top[k + 1][1], top[k][1]))
        bm.faces.new((bot[k][1], bot[k + 1][1], bot[k + 1][0], bot[k][0]))
        bm.faces.new((bot[k][0], bot[k + 1][0], top[k + 1][0], top[k][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sp = C.new_obj("FrontSplitter", bm, [M['DarkTrim']], smooth=False)
    C.recenter(sp); out.append(sp)
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
