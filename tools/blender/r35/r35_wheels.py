# 20" twin-Y-spoke forged wheel, 255/40R20-ish tyre, drilled-look disc, caliper.
import bpy, bmesh, math
from mathutils import Vector, Matrix
import r35_common as C

HUBS = {'FL': (0.80, -1.39, 0.355), 'FR': (-0.80, -1.39, 0.355),
        'RL': (0.80, 1.39, 0.355), 'RR': (-0.80, 1.39, 0.355)}
SEGS = 64


def _revolve(bm, profile, segs=SEGS, mat_idx=0):
    """profile [(x, r)] revolved about local X. Returns faces."""
    rings = []
    for (x, r) in profile:
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            ring.append(bm.verts.new((x, r * math.cos(a), r * math.sin(a))))
        rings.append(ring)
    fs = []
    for i in range(len(rings) - 1):
        for k in range(segs):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k]))
            f.material_index = mat_idx
            fs.append(f)
    return fs


def tyre_mesh():
    bm = bmesh.new()
    prof = [(0.116, 0.262), (0.126, 0.274), (0.133, 0.295), (0.137, 0.320), (0.134, 0.340), (0.124, 0.351),
            (0.105, 0.3555), (0.06, 0.3565), (0.0, 0.357), (-0.06, 0.3565), (-0.105, 0.3555), (-0.124, 0.351),
            (-0.134, 0.340), (-0.137, 0.320), (-0.133, 0.295), (-0.126, 0.272), (-0.116, 0.258)]
    # shallow circumferential grooves
    out = []
    for (x, r) in prof:
        out.append((x, r))
    _revolve(bm, out, SEGS)
    return bm


def _spoke(bm, ang0, ang1, half_w0, half_w1, mat_idx):
    """One spoke arm from hub (r0) to rim (r1); angles in rad for centreline at hub/rim."""
    n = 7
    r0, r1 = 0.072, 0.240
    secs = []
    for i in range(n + 1):
        t = i / n
        r = r0 + (r1 - r0) * t
        a = ang0 + (ang1 - ang0) * (t ** 0.85)
        hw = half_w0 + (half_w1 - half_w0) * t
        # concave dish: face x rises from hub (recessed) to rim lip
        xf = 0.062 + 0.050 * (t ** 1.35)
        xb = xf - 0.040 + 0.012 * t
        hw_ang = hw / r
        pts = []
        for (aa, xx) in ((a - hw_ang, xb), (a - hw_ang * 0.8, xf), (a + hw_ang * 0.8, xf), (a + hw_ang, xb)):
            pts.append(bm.verts.new((xx, r * math.cos(aa), r * math.sin(aa))))
        secs.append(pts)
    for i in range(n):
        A, B = secs[i], secs[i + 1]
        for k in range(3):
            f = bm.faces.new((A[k], A[k + 1], B[k + 1], B[k])); f.material_index = mat_idx
        f = bm.faces.new((A[3], A[0], B[0], B[3])); f.material_index = mat_idx
    f = bm.faces.new(secs[0][::-1]); f.material_index = mat_idx


def _spoke_root(bm, a, mat_idx):
    n = 3
    secs = []
    for i in range(n + 1):
        t = i / n
        r = 0.072 + 0.06 * t
        hw = 0.030 - 0.012 * t
        xf = 0.062 + 0.050 * ((r - 0.072) / 0.168) ** 1.35 + 0.002
        xb = xf - 0.040
        pts = []
        for (aa, xx) in ((a - hw / r, xb), (a - hw / r * 0.8, xf), (a + hw / r * 0.8, xf), (a + hw / r, xb)):
            pts.append(bm.verts.new((xx, r * math.cos(aa), r * math.sin(aa))))
        secs.append(pts)
    for i in range(n):
        A, B = secs[i], secs[i + 1]
        for k in range(3):
            f = bm.faces.new((A[k], A[k + 1], B[k + 1], B[k])); f.material_index = mat_idx
        f = bm.faces.new((A[3], A[0], B[0], B[3])); f.material_index = mat_idx
    f = bm.faces.new(secs[-1]); f.material_index = mat_idx


def rim_mesh():
    bm = bmesh.new()
    # outer lip + barrel (double sided material)
    # machined outer lip (bright, slot 2) + dark barrel
    _revolve(bm, [(0.108, 0.236), (0.120, 0.243), (0.127, 0.254), (0.126, 0.262), (0.118, 0.266)], SEGS, 2)
    lip = [(0.118, 0.266), (0.104, 0.262), (0.070, 0.243), (0.0, 0.240), (-0.08, 0.240), (-0.110, 0.248), (-0.122, 0.262), (-0.116, 0.266)]
    _revolve(bm, lip, SEGS, 0)
    # inner face ring that spokes land on
    _revolve(bm, [(0.112, 0.236), (0.104, 0.228), (0.090, 0.226)], SEGS, 0)
    # hub face
    hub = [(0.030, 0.090), (0.062, 0.088), (0.066, 0.080), (0.068, 0.045), (0.074, 0.040), (0.076, 0.0001)]
    _revolve(bm, hub, 40, 0)
    # 6 twin spokes (Y pairs)
    for p in range(6):
        base = 2 * math.pi * p / 6
        for sgn in (-1, 1):
            a_h = base + sgn * math.radians(2.2)
            a_r = base + sgn * math.radians(10.5)
            _spoke(bm, a_h, a_r, 0.0165, 0.0135, 0)
        # solid spoke root that joins the pair at the hub
        _spoke_root(bm, base, 0)
    # lug nuts (5) + centre cap
    for k in range(5):
        a = 2 * math.pi * k / 5 + math.pi / 10
        c = Vector((0.068, 0.056 * math.cos(a), 0.056 * math.sin(a)))
        prof = [(0.0, 0.010), (0.016, 0.010), (0.018, 0.006), (0.0185, 0.0001)]
        rings = []
        for (x, r) in prof:
            ring = []
            for s in range(8):
                aa = 2 * math.pi * s / 8
                ring.append(bm.verts.new(c + Vector((x, r * math.cos(aa), r * math.sin(aa)))))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for s in range(8):
                f = bm.faces.new((rings[i][s], rings[i][(s + 1) % 8], rings[i + 1][(s + 1) % 8], rings[i + 1][s])); f.material_index = 1
    cap = [(0.074, 0.034), (0.084, 0.033), (0.088, 0.028), (0.090, 0.0001)]
    _revolve(bm, cap, 24, 1)
    return bm


def disc_mesh():
    bm = bmesh.new()
    # rotor face (outboard) + edge + hat
    prof = [(0.012, 0.105), (0.014, 0.190), (0.010, 0.197), (-0.020, 0.197), (-0.024, 0.190), (-0.022, 0.105)]
    _revolve(bm, prof, 48, 0)
    hat = [(0.040, 0.0001), (0.040, 0.085), (0.030, 0.095), (0.012, 0.105)]
    _revolve(bm, hat, 32, 1)
    return bm


def caliper_mesh(front=True):
    """Arc-shaped monoblock straddling the rotor at the rear-top. Local to hub frame."""
    bm = bmesh.new()
    a0, a1 = math.radians(18), math.radians(78)  # angle from +Y (rear) toward +Z (up)
    n = 8
    prof = [(0.045, 0.150), (0.050, 0.205), (0.036, 0.222), (-0.040, 0.222), (-0.050, 0.205), (-0.045, 0.150)]
    rings = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        ring = [bm.verts.new((x, r * math.cos(a), r * math.sin(a))) for (x, r) in prof]
        rings.append(ring)
    m = len(prof)
    for i in range(n):
        for k in range(m):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % m], rings[i + 1][(k + 1) % m], rings[i + 1][k]))
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_wheels(M):
    objs = []
    for corner, hub in HUBS.items():
        left = hub[0] > 0
        e = bpy.data.objects.new("Wheel_" + corner, None)
        e.empty_display_type = 'PLAIN_AXES'; e.empty_display_size = 0.2
        bpy.context.scene.collection.objects.link(e)
        e.location = hub
        parts = [("Tyre_" + corner, tyre_mesh(), [M['Tire']]),
                 ("Rim_" + corner, rim_mesh(), [M['Rim'], M['RimCap'], M['RimLip']]),
                 ("BrakeDisc_" + corner, disc_mesh(), [M['BrakeDisc'], M['BrakeHat']])]
        for name, bm, mats in parts:
            if not left:
                for v in bm.verts:
                    v.co.x = -v.co.x
                for f in bm.faces:
                    f.normal_flip()
            ob = C.new_obj(name, bm, mats)
            if name.startswith("Rim_"):
                ob.data.set_sharp_from_angle(angle=math.radians(35))
            ob.parent = e
            ob.location = (0, 0, 0)
            objs.append(ob)
        # caliper: root level (does not spin / steer)
        bm = caliper_mesh()
        if not left:
            for v in bm.verts:
                v.co.x = -v.co.x
            for f in bm.faces:
                f.normal_flip()
        cal = C.new_obj("Caliper_" + corner, bm, [M['Caliper']])
        cal.location = hub
        objs.append(cal)
        objs.append(e)
    return objs
