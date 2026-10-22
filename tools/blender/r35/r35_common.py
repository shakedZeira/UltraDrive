# Shared helpers for the R35 v5 builder (run inside Blender).
import bpy, bmesh, math
from mathutils import Vector, Matrix
from mathutils.geometry import delaunay_2d_cdt


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.cameras, bpy.data.lights, bpy.data.curves):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)


# ---------------------------------------------------------------- interpolation
def cr(keys, t):
    """Catmull-Rom through (t, v) keys (sorted), clamped at the ends."""
    if t <= keys[0][0]:
        return keys[0][1]
    if t >= keys[-1][0]:
        return keys[-1][1]
    for i in range(len(keys) - 1):
        t0, v0 = keys[i]
        t1, v1 = keys[i + 1]
        if t0 <= t <= t1:
            vm = keys[i - 1][1] if i > 0 else v0 - (v1 - v0)
            tm = keys[i - 1][0] if i > 0 else t0 - (t1 - t0)
            vp = keys[i + 2][1] if i + 2 < len(keys) else v1 + (v1 - v0)
            tp = keys[i + 2][0] if i + 2 < len(keys) else t1 + (t1 - t0)
            u = (t - t0) / (t1 - t0)
            # non-uniform tangents (finite differences), scaled to the segment
            m0 = ((v1 - v0) / (t1 - t0) + (v0 - vm) / (t0 - tm)) * 0.5 * (t1 - t0)
            m1 = ((vp - v1) / (tp - t1) + (v1 - v0) / (t1 - t0)) * 0.5 * (t1 - t0)
            # clamp tangents to avoid overshoot (monotone-ish)
            d = v1 - v0
            if d == 0:
                m0 = m1 = 0.0
            else:
                if m0 / d < 0: m0 = 0.0
                if m1 / d < 0: m1 = 0.0
                m0 = min(m0, 3 * d) if d > 0 else max(m0, 3 * d)
                m1 = min(m1, 3 * d) if d > 0 else max(m1, 3 * d)
            h00 = 2 * u ** 3 - 3 * u ** 2 + 1
            h10 = u ** 3 - 2 * u ** 2 + u
            h01 = -2 * u ** 3 + 3 * u ** 2
            h11 = u ** 3 - u ** 2
            return h00 * v0 + h10 * m0 + h01 * v1 + h11 * m1
    return keys[-1][1]


def lerp(a, b, t):
    return a + (b - a) * t


def qbez(p0, c, p1, t):
    return ((1 - t) ** 2) * p0 + 2 * (1 - t) * t * c + (t ** 2) * p1


# ---------------------------------------------------------------- materials
def mat(name, color, metal=0.0, rough=0.5, coat=0.0, coat_rough=0.03, emit=None, emit_strength=0.0,
        alpha=1.0, spec=0.5):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color[:3], 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = coat_rough
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = spec
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit[:3], 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    b.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
        try:
            m.blend_method = 'BLEND'
        except Exception:
            pass
    m.diffuse_color = (*color[:3], alpha)
    return m


def set_mats(obj, mats):
    obj.data.materials.clear()
    for m in mats:
        obj.data.materials.append(m)


# ---------------------------------------------------------------- objects
def new_obj(name, bm, mats=None, smooth=True, loc=None):
    me = bpy.data.meshes.new(name + "Mesh")
    for m in (mats or []):
        me.materials.append(m)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    if loc is not None:
        ob.location = loc
    return ob


def bake_modifiers(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    me.name = ob.name + "Mesh"
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return ob


def recenter(ob, pivot=None):
    """Move object origin to pivot (default: bbox centre) keeping geometry fixed."""
    me = ob.data
    if pivot is None:
        if not me.vertices:
            return ob
        mn = Vector((min(v.co.x for v in me.vertices), min(v.co.y for v in me.vertices), min(v.co.z for v in me.vertices)))
        mx = Vector((max(v.co.x for v in me.vertices), max(v.co.y for v in me.vertices), max(v.co.z for v in me.vertices)))
        pivot = ob.matrix_world @ ((mn + mx) * 0.5)
    local = ob.matrix_world.inverted() @ Vector(pivot)
    me.transform(Matrix.Translation(-local))
    ob.matrix_world = ob.matrix_world @ Matrix.Translation(local)
    return ob


def apply_xform(ob):
    me = ob.data
    me.transform(ob.matrix_basis)
    ob.matrix_basis = Matrix.Identity(4)


def tri_count(ob):
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def mirror_copy(ob, name):
    """Mirror across X (x -> -x) into a new object, fixing winding."""
    me = ob.data.copy()
    me.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
    me.flip_normals()
    o2 = bpy.data.objects.new(name, me)
    me.name = name + "Mesh"
    bpy.context.scene.collection.objects.link(o2)
    L = ob.location
    o2.location = (-L.x, L.y, L.z)
    return o2


# ---------------------------------------------------------------- 2D polygon fill
def resample(poly, step):
    out = []
    n = len(poly)
    for i in range(n):
        a = Vector(poly[i]); b = Vector(poly[(i + 1) % n])
        L = (b - a).length
        k = max(1, int(math.ceil(L / step)))
        for j in range(k):
            out.append(a.lerp(b, j / k))
    return out


def point_in_poly(p, poly):
    x, y = p
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if x < xi:
                inside = not inside
    return inside


def fill_poly_2d(poly, step=0.02):
    """Constrained-Delaunay fill of a 2D polygon with interior grid points.
    Returns (verts2d, faces)."""
    bnd = resample(poly, step)
    xs = [p.x for p in bnd]; ys = [p.y for p in bnd]
    pts = [(p.x, p.y) for p in bnd]
    nb = len(pts)
    g = step
    x = min(xs) + g * 0.5
    bp = [(p.x, p.y) for p in bnd]
    while x < max(xs):
        y = min(ys) + g * 0.5
        while y < max(ys):
            if point_in_poly((x, y), bp):
                # keep away from boundary
                ok = True
                for q in bnd:
                    if (q.x - x) ** 2 + (q.y - y) ** 2 < (g * 0.45) ** 2:
                        ok = False; break
                if ok:
                    pts.append((x, y))
            y += g
        x += g
    edges = [(i, (i + 1) % nb) for i in range(nb)]
    vs, es, fs, _, _, _ = delaunay_2d_cdt([Vector(p) for p in pts], edges, [], 1, 1e-6)
    return [tuple(v) for v in vs], fs


def strip_poly(polyline, width):
    """Turn an open 2D polyline into a closed strip polygon of given width."""
    pl = [Vector(p) for p in polyline]
    left = []; right = []
    for i, p in enumerate(pl):
        if i == 0:
            d = pl[1] - pl[0]
        elif i == len(pl) - 1:
            d = pl[-1] - pl[-2]
        else:
            d = (pl[i + 1] - pl[i - 1])
        d.normalize()
        nrm = Vector((-d.y, d.x)) * (width * 0.5)
        left.append(p + nrm); right.append(p - nrm)
    return [tuple(v) for v in left + right[::-1]]


# ---------------------------------------------------------------- decals
def _plane_frame(direction):
    d = Vector(direction).normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((0, 1, 0))
    u = up.cross(d).normalized()   # right
    v = d.cross(u).normalized()
    return d, u, v


def decal(name, poly, target, material, plane='front', direction=None, offset=0.003, step=0.02,
          origin3d=None, mirror_name=None, extra_mats=None, strip=None, uv_scale=None):
    """Project a 2D polygon onto `target` with a shrinkwrap (project mode).
    plane: 'front' (x,z) looking +Y; 'rear' (x,z) looking -Y; 'side' (y,z) looking -X (car left, +X);
    'top' (x,y) looking -Z; 'custom': poly given as 3D points, projected along `direction`."""
    if plane == 'front':
        to3 = lambda p: Vector((p[0], -4.0, p[1])); d = Vector((0, 1, 0))
    elif plane == 'rear':
        to3 = lambda p: Vector((p[0], 4.0, p[1])); d = Vector((0, -1, 0))
    elif plane == 'side':
        to3 = lambda p: Vector((4.0, p[0], p[1])); d = Vector((-1, 0, 0))
    elif plane == 'top':
        to3 = lambda p: Vector((p[0], p[1], 4.0)); d = Vector((0, 0, -1))
    elif plane == 'custom':
        d, u, v = _plane_frame(direction)
        pts3 = [Vector(p) for p in poly]
        c = sum(pts3, Vector()) / len(pts3)
        poly = [((p - c).dot(u), (p - c).dot(v)) for p in pts3]
        base = c - d * 2.5
        to3 = lambda p, u=u, v=v, base=base: base + u * p[0] + v * p[1]
    if strip:
        poly = strip_poly(poly, strip)
    vs, fs = fill_poly_2d(poly, step)
    bm = bmesh.new()
    bv = [bm.verts.new(to3(p)) for p in vs]
    for f in fs:
        try:
            face = bm.faces.new([bv[i] for i in f])
        except ValueError:
            pass
    if uv_scale is None and material.name == 'GrilleMesh':
        uv_scale = 0.12
    if uv_scale:
        uvl = bm.loops.layers.uv.new("UVMap")
        for f in bm.faces:
            for lp in f.loops:
                i = bv.index(lp.vert) if False else None
        bm.verts.index_update()
        for f in bm.faces:
            for lp in f.loops:
                p2 = vs[lp.vert.index]
                lp[uvl].uv = (p2[0] / uv_scale, p2[1] / uv_scale)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # make faces point back toward the viewer (against d)
    if bm.faces and bm.faces[0].normal.dot(d) > 0:
        for f in bm.faces:
            f.normal_flip()
    ob = new_obj(name, bm, [material] + (extra_mats or []))
    # shrinkwrap along d using a world-space projection: rotate an empty frame
    sw = ob.modifiers.new("sw", 'SHRINKWRAP')
    sw.target = target
    sw.wrap_method = 'PROJECT'
    sw.wrap_mode = 'ABOVE_SURFACE'
    sw.offset = offset
    sw.use_negative_direction = False
    sw.use_positive_direction = True
    sw.cull_face = 'OFF'
    # project along local axis: we orient the object so local -Z == d is awkward; instead
    # use the 'normal' projection (no axis) which projects along vertex normals == -d.
    sw.use_project_x = sw.use_project_y = sw.use_project_z = False
    # vertex normals point against d, so project in the NEGATIVE normal direction
    sw.use_negative_direction = True
    sw.use_positive_direction = False
    sw.project_limit = {'front': 2.0, 'rear': 2.0, 'side': 3.25, 'top': 3.2}.get(plane, 2.75)
    bake_modifiers(ob)
    # drop verts that missed the target (still far away)
    me = ob.data
    bm = bmesh.new(); bm.from_mesh(me)
    far = [v for v in bm.verts if (v.co - to3((0, 0))).dot(d) < 0.3]
    if far:
        bmesh.ops.delete(bm, geom=far, context='VERTS')
    bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = True
    recenter(ob, origin3d)
    if mirror_name:
        return ob, mirror_copy(ob, mirror_name)
    return ob


# ---------------------------------------------------------------- primitives
def ring_tube(bm, axis_o, axis_d, profile, segs=32, cap_start=False, cap_end=False, mat_idx=None):
    """Revolve a profile [(t, r), ...] around axis (origin, unit dir). Returns rings."""
    d = Vector(axis_d).normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = up.cross(d).normalized(); v = d.cross(u).normalized()
    rings = []
    for (t, r) in profile:
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            p = Vector(axis_o) + d * t + (u * math.cos(a) + v * math.sin(a)) * r
            ring.append(bm.verts.new(p))
        rings.append(ring)
    faces = []
    for i in range(len(rings) - 1):
        for k in range(segs):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k]))
            faces.append(f)
    if cap_start:
        faces.append(bm.faces.new(rings[0][::-1]))
    if cap_end:
        faces.append(bm.faces.new(rings[-1]))
    if mat_idx is not None:
        for f in faces:
            f.material_index = mat_idx
    return rings, faces


def box(bm, center, size, mat_idx=0, rot=None):
    cx, cy, cz = center; sx, sy, sz = [s * 0.5 for s in size]
    R = rot or Matrix.Identity(3)
    vs = []
    for dx, dy, dz in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]:
        vs.append(bm.verts.new(Vector((cx, cy, cz)) + R @ Vector((dx * sx, dy * sy, dz * sz))))
    idx = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    fs = []
    for q in idx:
        f = bm.faces.new([vs[i] for i in q]); f.material_index = mat_idx; fs.append(f)
    return fs


def join(objs, name):
    """Merge mesh objects (world space) into one new object; material slots unioned."""
    mats = []
    for o in objs:
        for m in o.data.materials:
            if m not in mats:
                mats.append(m)
    bm = bmesh.new()
    for o in objs:
        me = o.data.copy()
        me.transform(o.matrix_world)
        remap = [mats.index(m) for m in o.data.materials]
        tmp = bmesh.new(); tmp.from_mesh(me)
        for f in tmp.faces:
            if remap:
                f.material_index = remap[f.material_index]
        tmp.to_mesh(me); tmp.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    ob = new_obj(name, bm, mats)
    recenter(ob)
    return ob


def diamond_texture(name, size=256, cells=8, strand=0.11, hole=0.010, width=0.16):
    import numpy as np
    img = bpy.data.images.get(name) or bpy.data.images.new(name, size, size, alpha=False)
    u = (np.arange(size) + 0.5) / size * cells
    U, V = np.meshgrid(u, u)
    a = np.abs(((U + V) % 1.0) - 0.5)
    b = np.abs(((U - V) % 1.0) - 0.5)
    f = np.maximum(a, b)
    m = np.clip((f - (0.5 - width)) / 0.03, 0, 1)
    shade = 0.6 + 0.4 * (1 - np.abs(((U + V) % 1.0) - 0.5) * 2)
    val = hole + (strand * shade - hole) * m
    px = np.zeros((size, size, 4), dtype=np.float32)
    px[..., 0] = val; px[..., 1] = val; px[..., 2] = val * 1.06; px[..., 3] = 1.0
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img


def textured(m, img):
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = 'Linear'
    nt.links.new(tex.outputs['Color'], b.inputs['Base Color'])
    return m
