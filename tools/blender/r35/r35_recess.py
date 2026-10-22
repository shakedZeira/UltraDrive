# Real recesses / panel gaps: bisect the (subdivided) body along a 2D outline seen from a
# projection plane, then push the enclosed vertices INTO the body along the view direction.
#   grille / vents / plate pocket : polygon + inner offset cut -> steep walls, flat floor
#   panel gaps                    : polyline -> 6 mm strip + centreline cut -> V-groove
import bmesh, math
from mathutils import Vector
from r35_common import point_in_poly, strip_poly

PLANES = {
    #        2D from 3D                 3D from 2D (depth arg)            view dir (into body)   face filter
    'front': (lambda v: (v.x, v.z), lambda p, k: Vector((p[0], k, p[1])), Vector((0, 1, 0)), lambda c, n: c.y < -1.4 and n.y < -0.15),
    'rear':  (lambda v: (v.x, v.z), lambda p, k: Vector((p[0], k, p[1])), Vector((0, -1, 0)), lambda c, n: c.y > 1.4 and n.y > 0.15),
    'side':  (lambda v: (v.y, v.z), lambda p, k: Vector((k, p[0], p[1])), Vector((-1, 0, 0)), lambda c, n: c.x > 0.35 and n.x > 0.2),
    'sideR': (lambda v: (v.y, v.z), lambda p, k: Vector((k, p[0], p[1])), Vector((1, 0, 0)), lambda c, n: c.x < -0.35 and n.x < -0.2),
    'top':   (lambda v: (v.x, v.y), lambda p, k: Vector((p[0], k, p[1])) if False else Vector((p[0], p[1], k)), Vector((0, 0, -1)), lambda c, n: c.z > 0.6 and n.z > 0.25),
}


def _seg_dist(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def offset_poly(poly, w):
    """Inward offset of a simple polygon by w (either winding)."""
    n = len(poly)
    area = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n)) * 0.5
    s = 1.0 if area > 0 else -1.0  # CCW -> inward normal is left of edge
    lines = []
    for i in range(n):
        a = Vector(poly[i]); b = Vector(poly[(i + 1) % n])
        d = (b - a).normalized()
        nrm = Vector((-d.y, d.x)) * s
        lines.append((a + nrm * w, d))
    out = []
    for i in range(n):
        p1, d1 = lines[i - 1]; p2, d2 = lines[i]
        den = d1.x * d2.y - d1.y * d2.x
        if abs(den) < 1e-9:
            out.append(tuple(p2)); continue
        t = ((p2.x - p1.x) * d2.y - (p2.y - p1.y) * d2.x) / den
        out.append(tuple(p1 + d1 * t))
    return out


def _cut_segment(bm, a, b, plane):
    to2, to3, d, filt = PLANES[plane]
    A3, B3 = to3(a, 0.0), to3(b, 0.0)
    nrm = (B3 - A3).cross(d)
    if nrm.length < 1e-9:
        return
    nrm.normalize()
    faces = []
    for f in bm.faces:
        c = f.calc_center_median()
        if not filt(c, f.normal):
            continue
        if _seg_dist(to2(c), a, b) < 0.05:
            faces.append(f)
    if not faces:
        return
    verts = {v for f in faces for v in f.verts}
    edges = {e for f in faces for e in f.edges}
    bmesh.ops.bisect_plane(bm, geom=list(verts) + list(edges) + faces, dist=1e-5, plane_co=A3, plane_no=nrm)


def recess(bm, poly, plane, depth, mat_idx=None, inner=None, groove_width=None, closed=True, tag=0, floor_mat=None):
    """poly: 2D outline (closed) or polyline (groove). Returns number of faces recessed."""
    to2, to3, d, filt = PLANES[plane]
    tl = bm.faces.layers.int.get('rid') or bm.faces.layers.int.new('rid')
    if groove_width:
        line = poly
        poly = strip_poly(line, groove_width)
        segs = [(poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly))]
        segs += [(line[i], line[i + 1]) for i in range(len(line) - 1)]
    else:
        segs = [(poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly))]
        if inner:
            ip = offset_poly(poly, inner)
            segs += [(ip[i], ip[(i + 1) % len(ip)]) for i in range(len(ip))]
    for a, b in segs:
        _cut_segment(bm, a, b, plane)
    bm.faces.ensure_lookup_table()
    inside = set()
    for f in bm.faces:
        c = f.calc_center_median()
        if filt(c, f.normal) and point_in_poly(to2(c), poly):
            inside.add(f)
    if not inside:
        return 0
    outside_verts = set()
    for f in bm.faces:
        if f not in inside:
            outside_verts.update(f.verts)
    moved = [v for f in inside for v in f.verts if v not in outside_verts]
    for v in set(moved):
        v.co += d * depth
    moved = set(moved)
    for f in inside:
        if mat_idx is not None:
            f.material_index = mat_idx
        if tag and all(v in moved for v in f.verts):
            f[tl] = tag
            if floor_mat is not None:
                f.material_index = floor_mat
    return len(inside)
