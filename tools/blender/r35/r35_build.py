# R35 v5 exterior builder. Usage:
#   blender --background --factory-startup --python r35_build.py -- render side front34 ...
#   blender --background --factory-startup --python r35_build.py -- export <out.glb>
import sys, os, importlib, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy, bmesh
from mathutils import Vector, Matrix
import r35_common as C; importlib.reload(C)
import r35_body as B; importlib.reload(B)
import r35_wheels as W; importlib.reload(W)

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else ['render', 'side']


def materials():
    M = {}
    M['CarPaint'] = C.mat('CarPaint', (0.07, 0.24, 0.55), 0.5, 0.25, coat=1.0, coat_rough=0.04)
    M['Glass'] = C.mat('Glass', (0.02, 0.03, 0.04), 0.0, 0.05, alpha=0.35)
    for k in ('GlassW', 'GlassS', 'GlassR'):
        M[k] = C.mat(k, (0.02, 0.03, 0.04), 0.0, 0.05)
    M['DarkTrim'] = C.mat('DarkTrim', (0.025, 0.025, 0.028), 0.2, 0.5)
    M['Graphite'] = C.mat('Graphite', (0.085, 0.087, 0.095), 0.6, 0.35)
    M['GrilleMesh'] = C.textured(C.mat('GrilleMesh', (0.010, 0.010, 0.012), 0.3, 0.55), C.diamond_texture('GrilleDiamond'))
    M['Chrome'] = C.mat('Chrome', (0.86, 0.86, 0.88), 1.0, 0.08)
    M['Headlight'] = C.mat('Headlight', (0.80, 0.83, 0.87), 0.1, 0.1, emit=(1.0, 1.0, 0.95), emit_strength=1.2)
    M['LampHousing'] = C.mat('LampHousing', (0.06, 0.065, 0.07), 0.85, 0.12)
    M['LampDRL'] = C.mat('LampDRL', (0.9, 0.92, 0.95), 0.0, 0.2, emit=(0.95, 0.97, 1.0), emit_strength=3.0)
    M['Taillight'] = C.mat('Taillight', (0.55, 0.02, 0.02), 0.1, 0.15, emit=(1.0, 0.05, 0.05), emit_strength=1.5)
    M['TailInner'] = C.mat('TailInner', (0.78, 0.78, 0.80), 0.9, 0.15)
    M['LampBezel'] = C.mat('LampBezel', (0.03, 0.03, 0.035), 0.5, 0.3)
    M['LampRed'] = C.mat('LampRed', (0.40, 0.02, 0.02), 0.0, 0.2)
    M['LampAmber'] = C.mat('LampAmber', (0.85, 0.42, 0.05), 0.0, 0.2)
    M['ExhaustTip'] = C.mat('ExhaustTip', (0.50, 0.42, 0.33), 1.0, 0.22)
    M['ExhaustInner'] = C.mat('ExhaustInner', (0.01, 0.01, 0.01), 0.0, 0.9)
    M['Plate'] = C.mat('Plate', (0.90, 0.90, 0.88), 0.0, 0.5)
    M['WheelWell'] = C.mat('WheelWell', (0.012, 0.012, 0.013), 0.0, 0.9)
    M['Interior'] = C.mat('Interior', (0.035, 0.035, 0.04), 0.0, 0.85)
    M['InteriorSeat'] = C.mat('InteriorSeat', (0.05, 0.045, 0.045), 0.0, 0.7)
    M['Rim'] = C.mat('Rim', (0.27, 0.275, 0.29), 1.0, 0.32)
    M['RimLip'] = C.mat('RimLip', (0.86, 0.87, 0.89), 1.0, 0.16)
    M['RimCap'] = C.mat('RimCap', (0.55, 0.56, 0.58), 1.0, 0.2)
    M['Tire'] = C.mat('Tire', (0.028, 0.028, 0.03), 0.0, 0.9)
    M['BrakeDisc'] = C.mat('BrakeDisc', (0.34, 0.34, 0.35), 0.9, 0.42)
    M['BrakeHat'] = C.mat('BrakeHat', (0.06, 0.06, 0.065), 0.4, 0.5)
    M['Caliper'] = C.mat('Caliper', (0.80, 0.46, 0.07), 0.25, 0.32)
    M['MirrorChrome'] = C.mat('MirrorChrome', (0.70, 0.74, 0.78), 1.0, 0.03)
    for k in ('Rim', 'RimLip', 'RimCap', 'Tire', 'BrakeDisc', 'BrakeHat', 'Interior', 'InteriorSeat', 'WheelWell'):
        M[k].use_backface_culling = False
    for k, m in M.items():
        if k not in ('Rim', 'RimLip', 'RimCap', 'Tire', 'BrakeDisc', 'BrakeHat', 'Interior', 'InteriorSeat', 'WheelWell'):
            m.use_backface_culling = True
    return M


def finish_body(body, M):
    sd = body.modifiers.new('sd', 'SUBSURF'); sd.levels = 1; sd.render_levels = 1
    C.bake_modifiers(body)
    # wheel-arch cutters (one object, 4 cylinders)
    bm = bmesh.new()
    for corner, (hx, hy, hz) in W.HUBS.items():
        r = 0.383 if hy < 0 else 0.386
        sgn = 1 if hx > 0 else -1
        C.ring_tube(bm, (sgn * 0.50, hy, hz), (sgn, 0, 0), [(0.0, r), (0.9, r)], segs=72, cap_start=True, cap_end=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    cut = C.new_obj("ArchCutter", bm, [M['WheelWell']], smooth=False)
    bo = body.modifiers.new('arch', 'BOOLEAN')
    bo.operation = 'DIFFERENCE'; bo.solver = 'EXACT'; bo.object = cut
    try:
        bo.material_mode = 'TRANSFER'
    except Exception:
        pass
    C.bake_modifiers(body)
    bpy.data.objects.remove(cut, do_unlink=True)
    # split glass regions into their own objects
    me = body.data
    names = [m.name for m in me.materials]
    split = {'GlassW': 'Windscreen', 'GlassS': 'Glass', 'GlassR': 'GlassFastback'}
    for mname, oname in split.items():
        if mname not in names:
            continue
        idx = names.index(mname)
        bm = bmesh.new(); bm.from_mesh(me)
        kill = [f for f in bm.faces if f.material_index != idx]
        bmesh.ops.delete(bm, geom=kill, context='FACES')
        for f in bm.faces:
            f.material_index = 0
        # inset glass 4 mm inward along normals so pillars/rails stand proud
        bm.normal_update()
        for v in bm.verts:
            v.co -= v.normal * 0.004
        g = C.new_obj(oname, bm, [M['Glass']])
        C.recenter(g)
    bm = bmesh.new(); bm.from_mesh(me)
    glass_idx = [names.index(k) for k in split if k in names]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in glass_idx], context='FACES')
    # compact material slots: CarPaint, DarkTrim, WheelWell
    keep = ['CarPaint', 'DarkTrim', 'WheelWell', 'Graphite']
    remap = {names.index(k): i for i, k in enumerate(keep) if k in names}
    for f in bm.faces:
        f.material_index = remap.get(f.material_index, 0)
    me.materials.clear()
    for k in keep:
        me.materials.append(M[k])
    bm.to_mesh(me); bm.free()
    apply_recesses(body)
    for p in me.polygons:
        p.use_smooth = True
    try:
        me.set_sharp_from_angle(angle=math.radians(42))
    except Exception as e:
        print("sharp-from-angle failed", e)
    return body


def _mx(poly):
    return [(-x, z) for (x, z) in poly][::-1]


FLOORS = {}   # tag -> (object name, plane)


def apply_recesses(body):
    """Real depth: grille/intake/vent pockets (floors split into named objects later) and
    V-groove panel gaps. Body slots: 0 CarPaint, 1 DarkTrim, 2 WheelWell, 3 Graphite."""
    import r35_recess as RC; importlib.reload(RC)
    FLOORS.clear()
    me = body.data
    bm = bmesh.new(); bm.from_mesh(me)
    tagn = [0]

    def pocket(name, poly, plane, depth, inner):
        tagn[0] += 1
        FLOORS[tagn[0]] = (name, plane)
        return RC.recess(bm, poly, plane, depth, 1, inner=inner, tag=tagn[0])
    n = 0
    # material regions first (depth 0 = cut + recolour only; negative = proud)
    n += RC.recess(bm, [(-0.878, 0.448), (0.878, 0.448), (0.870, 0.05), (-0.870, 0.05)], 'rear', 0.0, 1)
    n += RC.recess(bm, [(-0.535, 0.538), (0.535, 0.538), (0.568, 0.383), (-0.568, 0.383)], 'front', -0.006, 3)
    # front openings
    n += pocket("UpperGrille", [(-0.40, 0.692), (0.40, 0.692), (0.535, 0.540), (-0.535, 0.540)], 'front', 0.045, 0.010)
    n += pocket("FrontIntake", [(-0.566, 0.380), (0.566, 0.380), (0.588, 0.178), (-0.588, 0.178)], 'front', 0.050, 0.010)
    ci = [(0.715, 0.555), (0.858, 0.565), (0.878, 0.245), (0.728, 0.225)]
    n += pocket("IntakeCorner_L", ci, 'front', 0.035, 0.008)
    n += pocket("IntakeCorner_R", _mx(ci), 'front', 0.035, 0.008)
    hv = [(0.300, -1.020), (0.425, -1.050), (0.432, -0.930), (0.318, -0.885)]
    n += pocket("HoodVent_L", hv, 'top', 0.016, 0.005)
    n += pocket("HoodVent_R", [(-x, y) for (x, y) in hv][::-1], 'top', 0.016, 0.005)
    hl = [(0.705, -2.165), (0.715, -1.70), (0.70, -1.20), (0.69, -0.80)]
    for line in (hl, [(-x, y) for (x, y) in hl], [(-0.69, -0.80), (0.69, -0.80)], [(-0.70, -2.17), (0.70, -2.17)]):
        n += RC.recess(bm, line, 'top', 0.004, 1, groove_width=0.006)
    sv = [(-0.928, 0.786), (-0.872, 0.792), (-0.612, 0.418), (-0.658, 0.400)]
    door = [(-0.700, 1.000), (-0.672, 0.86), (-0.648, 0.62), (-0.630, 0.315), (-0.55, 0.300), (0.40, 0.292),
            (0.452, 0.300), (0.55, 0.55), (0.625, 0.80), (0.662, 1.000)]
    n += pocket("SideVent_L", sv, 'side', 0.025, 0.006)
    n += pocket("SideVent_R", sv, 'sideR', 0.025, 0.006)
    for pl in ('side', 'sideR'):
        n += RC.recess(bm, door, pl, 0.004, 1, groove_width=0.006)
    n += RC.recess(bm, [(-0.60, 1.03), (-0.44, 0.885), (0.44, 0.885), (0.60, 1.03)], 'rear', 0.004, 1, groove_width=0.006)
    n += RC.recess(bm, [(-0.405, 0.665), (-0.325, 0.445), (0.325, 0.445), (0.405, 0.665)], 'rear', 0.018, None, inner=0.006)
    ex = [(0.462, 0.402), (0.858, 0.408), (0.856, 0.198), (0.470, 0.192)]
    n += pocket("ExhaustMesh_L", ex, 'rear', 0.040, 0.008)
    n += pocket("ExhaustMesh_R", _mx(ex), 'rear', 0.040, 0.008)
    n += pocket("DiffuserChannel", [(-0.40, 0.330), (0.40, 0.330), (0.27, 0.190), (-0.27, 0.190)], 'rear', 0.030, 0.008)
    bm.to_mesh(me); bm.free()
    print("recessed faces", n)


def split_floors(body, M):
    """Detach each tagged pocket floor into its own object (GrilleMesh, planar UVs)."""
    import r35_recess as RC
    me = body.data
    out = []
    for tag, (name, plane) in FLOORS.items():
        bm = bmesh.new(); bm.from_mesh(me)
        tl = bm.faces.layers.int.get('rid')
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[tl] != tag], context='FACES')
        if not bm.faces:
            bm.free(); print("empty floor", name); continue
        to2 = RC.PLANES[plane][0]
        uvl = bm.loops.layers.uv.new("UVMap")
        for f in bm.faces:
            f.material_index = 0
            for lp in f.loops:
                u, v = to2(lp.vert.co)
                lp[uvl].uv = (u / 0.12, v / 0.12)
        o = C.new_obj(name, bm, [M['GrilleMesh']])
        C.recenter(o)
        out.append(o)
    bm = bmesh.new(); bm.from_mesh(me)
    tl = bm.faces.layers.int.get('rid')
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[tl] != 0], context='FACES')
    bm.to_mesh(me); bm.free()
    return out


def build_tub(M, ys):
    """Dark inward-facing cabin shell (seen through the glass) + simple seats/dash."""
    bm = bmesh.new()
    rings = []
    tys = [y for y in ys if -0.80 <= y <= 1.62]
    for y in tys:
        half, L = B.half_profile(y)
        pts = []
        for (x, z) in half:
            z2 = max(z, 0.34)
            pts.append((x, z2))
        # inset toward the cabin centre
        cz = 0.85
        ring_half = []
        for (x, z) in pts:
            ring_half.append(((x * 0.955), cz + (z - cz) * 0.965))
        n = len(ring_half) - 1
        ring = [bm.verts.new((x, y, z)) for (x, z) in ring_half]
        ring += [bm.verts.new((-ring_half[k][0], y, ring_half[k][1])) for k in range(n - 1, 0, -1)]
        rings.append(ring)
    N = len(rings[0])
    for s in range(len(rings) - 1):
        for j in range(N):
            bm.faces.new((rings[s][j], rings[s][(j + 1) % N], rings[s + 1][(j + 1) % N], rings[s + 1][j]))
    for s in (0, len(rings) - 1):
        bm.faces.new(rings[s] if s == 0 else rings[s][::-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:  # inward facing
        f.normal_flip()
    tub = C.new_obj("CabinTub", bm, [M['Interior']])
    # seats, dash, steering wheel silhouettes (driver on car-left = +X, matching the cockpit rig)
    bm = bmesh.new()
    for sx in (0.37, -0.37):
        C.box(bm, (sx, 0.30, 0.42), (0.50, 0.50, 0.12), 0)                       # cushion
        C.box(bm, (sx, 0.60, 0.78), (0.50, 0.14, 0.68), 0, rot=Matrix.Rotation(math.radians(-14), 3, 'X'))  # backrest
        C.box(bm, (sx, 0.68, 1.16), (0.26, 0.12, 0.16), 0)                       # headrest
        C.box(bm, (sx, 1.05, 0.62), (0.46, 0.40, 0.18), 0)                       # rear bench
    C.box(bm, (0.0, -0.62, 0.86), (1.42, 0.30, 0.22), 1)                         # dash
    C.box(bm, (0.0, -0.10, 0.52), (0.26, 1.10, 0.22), 1)                         # tunnel
    seats = C.new_obj("CabinSeats", bm, [M['InteriorSeat'], M['Interior']], smooth=False)
    bm = bmesh.new()
    rings, _ = C.ring_tube(bm, (0.37, -0.40, 0.86), (0, -0.6, 0.8), [(0.0, 0.17), (0.03, 0.17)], segs=24)
    sw = C.new_obj("CabinSteer", bm, [M['Interior']])
    return [tub, seats, sw]


def build_all():
    C.clear_scene()
    M = materials()
    body, ys, L = B.build_body(M)
    finish_body(body, M)
    objs = [body] + split_floors(body, M) + build_tub(M, ys) + W.build_wheels(M)
    try:
        import r35_details as D; importlib.reload(D)
        objs += D.build_details(M, body)
    except ImportError:
        print("no details module yet")
    return M, body


def report():
    tot = 0
    rows = []
    for ob in bpy.data.objects:
        if ob.type == 'MESH' and ob.name not in ('Floor',):
            t = C.tri_count(ob); tot += t
            rows.append((t, ob.name))
    rows.sort(reverse=True)
    print("TRIS TOTAL", tot)
    print(", ".join(f"{n}:{t}" for t, n in rows[:25]))


if __name__ == "__main__":
    M, body = build_all()
    report()
    if ARGS[0] == 'render':
        import r35_render as R; importlib.reload(R)
        res = (1280, 720)
        R.setup_studio(res=res, samples=24)
        out = os.path.join(HERE, "renders")
        os.makedirs(out, exist_ok=True)
        tag = os.environ.get('R35_TAG', 'v')
        for v in ARGS[1:]:
            R.render_view(v, os.path.join(out, f"{tag}_{v}.png"))
    elif ARGS[0] == 'ortho':
        import r35_render as R; importlib.reload(R)
        R.setup_studio(res=(1920, 1440), samples=8)
        tag = os.environ.get('R35_TAG', 'v')
        for v in ARGS[1:] or ['side', 'front', 'rear']:
            R.render_ortho_match(os.path.join(HERE, 'renders', f'{tag}_ortho_{v}.png'), v)
    elif ARGS[0] == 'export':
        path = ARGS[1]
        for ob in bpy.data.objects:
            ob.select_set(ob.type in ('MESH', 'EMPTY') and ob.name not in ('Floor',))
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                                  export_apply=True, export_lights=False, export_cameras=False,
                                  export_materials='EXPORT', export_normals=True, export_tangents=False)
        print("exported", path)
    elif ARGS[0] == 'save':
        bpy.ops.wm.save_as_mainfile(filepath=ARGS[1])
