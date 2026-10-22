# R35 body loft. Blender frame: X = car left (+), Y = rear (+) (nose at -Y), Z up, ground z = 0.
# Hubs at (+-0.80, -+1.39, 0.355) exactly like the shipped GLB (physics contract).
import bpy, bmesh, math
from mathutils import Vector, Matrix

YF, YR = -2.355, 2.355
COWL, HEADER, BP0, BP1, ROOFBACK, KINK, DECK = -0.75, -0.14, 0.565, 0.645, 0.87, 1.08, 1.57

K = {
    'zb': [(-2.355, 0.205), (-2.33, 0.18), (-2.25, 0.168), (-2.10, 0.163), (-1.6, 0.16), (2.0, 0.165), (2.22, 0.172), (2.30, 0.180), (2.355, 0.195)],
    'wb': [(-2.355, 0.66), (-2.33, 0.75), (-2.25, 0.80), (-2.10, 0.825), (-1.8, 0.84), (-1.2, 0.855), (0.0, 0.86), (1.2, 0.86), (1.8, 0.85), (2.15, 0.81), (2.30, 0.75), (2.355, 0.67)],
    'zmax': [(-2.355, 0.36), (-2.30, 0.44), (-2.2, 0.50), (-1.4, 0.60), (-0.6, 0.56), (0.4, 0.55), (1.4, 0.64), (2.2, 0.60), (2.355, 0.52)],
    'wmax': [(-2.355, 0.76), (-2.33, 0.83), (-2.28, 0.87), (-2.20, 0.898), (-2.0, 0.925), (-1.7, 0.942), (-1.40, 0.9475), (-1.05, 0.942), (-0.70, 0.928), (0.0, 0.922), (0.55, 0.926), (1.0, 0.942), (1.40, 0.9475), (1.80, 0.942), (2.05, 0.930), (2.18, 0.912), (2.26, 0.888), (2.32, 0.855), (2.355, 0.78)],
    'dsh': [(-2.355, 0.03), (-1.4, 0.022), (-0.6, 0.035), (0.4, 0.040), (1.4, 0.022), (2.355, 0.03)],
    'zsh': [(-2.355, 0.46), (-2.33, 0.54), (-2.28, 0.62), (-2.2, 0.70), (-1.9, 0.79), (-1.4, 0.83), (-1.0, 0.85), (-0.6, 0.865), (0.3, 0.88), (0.9, 0.895), (1.4, 0.93), (2.0, 0.95), (2.2, 0.93), (2.30, 0.875), (2.355, 0.74)],
    'zbelt': [(-2.355, 0.50), (-2.33, 0.585), (-2.28, 0.67), (-2.2, 0.765), (-2.05, 0.84), (-1.9, 0.875), (-1.6, 0.915), (-1.33, 0.94), (-1.0, 0.965), (-0.75, 0.99), (-0.3, 1.0), (0.3, 1.008), (0.6, 1.012), (1.08, 1.03), (1.4, 1.03), (1.57, 1.04), (1.9, 1.04), (2.18, 1.02), (2.25, 0.985), (2.30, 0.925), (2.355, 0.785)],
    'wbelt': [(-2.355, 0.73), (-2.33, 0.80), (-2.28, 0.845), (-2.2, 0.872), (-1.9, 0.885), (-1.4, 0.89), (-1.0, 0.865), (-0.75, 0.80), (-0.3, 0.784), (0.3, 0.784), (0.6, 0.79), (1.08, 0.812), (1.4, 0.862), (1.6, 0.875), (1.9, 0.875), (2.18, 0.858), (2.25, 0.84), (2.30, 0.81), (2.355, 0.745)],
    'zra': [(-2.355, 0.52), (-2.33, 0.605), (-2.28, 0.69), (-2.2, 0.785), (-2.05, 0.865), (-1.9, 0.905), (-1.6, 0.945), (-1.33, 0.968), (-1.0, 0.99), (-0.75, 1.012), (-0.6, 1.085), (-0.40, 1.19), (-0.2, 1.29), (HEADER, 1.318), (0.0, 1.338), (0.3, 1.345), (BP1, 1.328), (0.80, 1.245), (0.95, 1.13), (KINK, 1.042), (1.3, 1.048), (1.57, 1.058), (1.9, 1.055), (2.18, 1.035), (2.25, 0.992), (2.30, 0.932), (2.355, 0.795)],
    'wra': [(-2.355, 0.68), (-2.33, 0.745), (-2.28, 0.79), (-2.2, 0.812), (-1.9, 0.812), (-1.4, 0.792), (-1.0, 0.765), (-0.75, 0.758), (-0.6, 0.722), (-0.40, 0.662), (-0.2, 0.602), (HEADER, 0.586), (0.0, 0.580), (0.3, 0.580), (BP1, 0.592), (0.80, 0.66), (0.95, 0.74), (KINK, 0.805), (1.3, 0.845), (1.57, 0.852), (1.9, 0.852), (2.18, 0.836), (2.25, 0.818), (2.30, 0.788), (2.355, 0.72)],
    'zrb': [(-2.355, 0.51), (-2.33, 0.595), (-2.28, 0.675), (-2.2, 0.765), (-2.05, 0.84), (-1.9, 0.875), (-1.6, 0.915), (-1.33, 0.94), (-1.0, 0.968), (-0.75, 1.006), (-0.6, 1.09), (-0.40, 1.20), (-0.2, 1.30), (HEADER, 1.33), (0.0, 1.352), (0.3, 1.357), (BP1, 1.346), (ROOFBACK, 1.312), (KINK, 1.255), (1.3, 1.185), (DECK, 1.10), (1.75, 1.08), (1.9, 1.066), (2.18, 1.04), (2.25, 0.996), (2.30, 0.936), (2.355, 0.80)],
    'wrb': [(-2.355, 0.64), (-2.33, 0.70), (-2.28, 0.745), (-2.2, 0.765), (-1.9, 0.76), (-1.4, 0.742), (-1.0, 0.725), (-0.75, 0.73), (-0.6, 0.695), (-0.40, 0.635), (-0.2, 0.578), (HEADER, 0.562), (0.0, 0.556), (0.3, 0.556), (BP1, 0.562), (ROOFBACK, 0.572), (KINK, 0.580), (1.3, 0.585), (DECK, 0.592), (1.66, 0.66), (1.75, 0.76), (1.9, 0.80), (2.18, 0.80), (2.25, 0.785), (2.30, 0.758), (2.355, 0.70)],
    'ztop': [(-2.355, 0.50), (-2.33, 0.585), (-2.28, 0.67), (-2.2, 0.76), (-2.05, 0.83), (-1.9, 0.865), (-1.6, 0.905), (-1.33, 0.932), (-1.0, 0.962), (-0.80, 0.99), (COWL, 1.0), (-0.6, 1.088), (-0.4, 1.20), (-0.2, 1.31), (HEADER, 1.345), (0.0, 1.362), (0.2, 1.37), (0.4, 1.37), (BP1, 1.355), (ROOFBACK, 1.322), (KINK, 1.268), (1.32, 1.20), (DECK, 1.125), (1.71, 1.10), (1.97, 1.065), (2.18, 1.04), (2.25, 1.0), (2.30, 0.94), (2.355, 0.80)],
}

# hood: shallow centre power bulge + valleys at the fender peaks (front stations only)
def hood_dip(y):
    if y > COWL or y < -2.25:
        return 0.0
    return 0.012 * math.sin(math.pi * (y - COWL) / (-2.25 - COWL))


def param(name, y):
    from r35_common import cr
    return cr(K[name], y)


def half_profile(y):
    """Points (x, z) from bottom centre to top centre (x >= 0). Returns pts, landmark indices."""
    from r35_common import lerp, qbez
    zb = param('zb', y); wb = param('wb', y)
    zmax = param('zmax', y); wmax = param('wmax', y)
    zsh = param('zsh', y); wsh = wmax - param('dsh', y)
    zbe = param('zbelt', y); wbe = param('wbelt', y)
    zra = param('zra', y); wra = param('wra', y)
    zrb = param('zrb', y); wrb = param('wrb', y)
    zt = param('ztop', y)
    zt = max(zt, zrb - 0.004)
    V = Vector
    pts = []
    L = {}
    # bottom
    A0 = V((0, zb)); A1 = V((wb * 0.90, zb)); A2 = V((wb, zb + 0.03))
    for k in range(4):
        pts.append(A0.lerp(A1, k / 4))
    L['A1'] = len(pts); pts.append(A1)
    pts.append(qbez(A1, V((wb, zb)), A2, 0.5))
    L['A2'] = len(pts); pts.append(A2)
    A3 = V((wmax, zmax))
    c = V((wmax - 0.004, zb + 0.06))
    for t in (0.33, 0.66):
        pts.append(qbez(A2, c, A3, t))
    L['A3'] = len(pts); pts.append(A3)
    A4 = V((wsh, zsh))
    c = V((wmax + 0.006, (zmax + zsh) * 0.5))
    for t in (0.33, 0.66, 0.90):
        pts.append(qbez(A3, c, A4, t))
    L['A4'] = len(pts); pts.append(A4)
    A5 = V((wbe, zbe))
    c = V((wsh - 0.012, zbe - 0.004))
    for t in (0.12, 0.5):
        pts.append(qbez(A4, c, A5, t))
    L['belt'] = len(pts); pts.append(A5)
    A6 = V((wra, zra))
    seg = A6 - A5
    nrm = V((seg.y, -seg.x))
    if nrm.length > 1e-6:
        nrm.normalize()
    bow = min(0.02, seg.length * 0.08)
    c = (A5 + A6) * 0.5 + nrm * bow
    for t in (0.2, 0.4, 0.6, 0.8):
        pts.append(qbez(A5, c, A6, t))
    L['ra'] = len(pts); pts.append(A6)
    A7 = V((wrb, zrb))
    c = V((wra - (wra - wrb) * 0.25, zrb + 0.004))
    for t in (0.33, 0.66):
        pts.append(qbez(A6, c, A7, t))
    L['rb'] = len(pts); pts.append(A7)
    dip = hood_dip(y)
    n_top = 8
    for k in range(1, n_top):
        t = k / n_top
        x = wrb * (1 - t)
        z = zrb + (zt - zrb) * (1 - (1 - t) ** 2.3)
        # hood valley between fender peak and centre bulge
        z -= dip * math.sin(math.pi * min(1.0, t * 1.6)) * 0.9
        pts.append(V((x, z)))
    L['top'] = len(pts); pts.append(V((0, zt)))
    return pts, L


def stations():
    ys = set()
    def rng(a, b, n):
        for k in range(n + 1):
            ys.add(round(a + (b - a) * k / n, 5))
    rng(YF, -2.28, 4)
    rng(-2.28, -2.10, 5)
    rng(-2.10, -1.80, 4)
    rng(-1.80, COWL, 14)
    rng(COWL, HEADER, 9)
    rng(HEADER, BP0, 9)
    rng(BP0, BP1, 2)
    rng(BP1, ROOFBACK, 3)
    rng(ROOFBACK, KINK, 4)
    rng(KINK, DECK, 7)
    rng(DECK, 2.10, 8)
    rng(2.10, 2.30, 6)
    rng(2.30, YR, 3)
    return sorted(ys)


def build_body(mats):
    """mats: dict with CarPaint, GlassW, GlassS, GlassR, DarkTrim. Returns object 'Body' (unsubdivided)."""
    ys = stations()
    bm = bmesh.new()
    rings = []
    landmarks = None
    for y in ys:
        half, L = half_profile(y)
        if landmarks is None:
            landmarks = L
        n = len(half) - 1  # index of top
        ring = []
        for (x, z) in half:
            ring.append(bm.verts.new((x, y, z)))
        # mirrored side going back down (exclude top and bottom centre)
        for k in range(n - 1, 0, -1):
            x, z = half[k]
            ring.append(bm.verts.new((-x, y, z)))
        rings.append(ring)
    N = len(rings[0])
    n = landmarks['top']
    belt, ra, rb = landmarks['belt'], landmarks['ra'], landmarks['rb']
    slot = {k: i for i, k in enumerate(['CarPaint', 'GlassW', 'GlassS', 'GlassR', 'DarkTrim'])}

    def mirror_idx(j):
        return (N - j) % N

    for s in range(len(rings) - 1):
        y0, y1 = ys[s], ys[s + 1]
        ym = (y0 + y1) * 0.5
        for j in range(N):
            a, b = rings[s][j], rings[s][(j + 1) % N]
            c, d = rings[s + 1][(j + 1) % N], rings[s + 1][j]
            f = bm.faces.new((a, d, c, b))
            # material regions
            jl = j  # left side edge index (j -> j+1)
            mi = slot['CarPaint']
            # side glass left: belt..ra ; right mirrored
            in_left_side = belt <= j < ra
            in_right_side = mirror_idx(ra) <= j < mirror_idx(belt)
            in_top = rb <= j < mirror_idx(rb)
            if (in_left_side or in_right_side) and COWL <= ym <= KINK:
                mi = slot['DarkTrim'] if BP0 <= ym <= BP1 else slot['GlassS']
            elif in_top and COWL <= ym <= HEADER:
                mi = slot['GlassW']
            elif in_top and ROOFBACK <= ym <= DECK:
                mi = slot['GlassR']
            f.material_index = mi
    # crisp character lines: shoulder (full length) + front fender peaks + belt over the doors
    cl = bm.edges.layers.float.get('crease_edge') or bm.edges.layers.float.new('crease_edge')
    a4 = landmarks['A4']
    for s in range(len(rings) - 1):
        ym = (ys[s] + ys[s + 1]) * 0.5
        lines = []
        if -2.22 < ym < 2.26:
            lines.append((a4, 0.92))
        if -2.24 < ym < COWL - 0.02:
            lines.append((ra, 0.95))
            lines.append((belt, 0.55))
        for j, val in lines:
            for jj in (j, mirror_idx(j)):
                e = bm.edges.get((rings[s][jj], rings[s + 1][jj]))
                if e is not None:
                    e[cl] = val
    # end caps (fans)
    # quad 'ladder' caps: row k joins ring[k] (x>0) to its mirror ring[N-k] through MI
    # interior points (no fan pole -> clean cuts/recesses on the fascia and rear panel)
    MI = 9
    for s, sign in ((0, -1), (len(rings) - 1, 1)):
        ring = rings[s]
        rows = []
        for k in range(1, n):
            a, b = ring[k], ring[N - k]
            row = [a]
            for i in range(1, MI + 1):
                t = i / (MI + 1)
                p = a.co.lerp(b.co, t)
                p.y += sign * 0.006 * (1 - (2 * t - 1) ** 2)
                row.append(bm.verts.new(p))
            row.append(b)
            rows.append(row)
        for r0, r1 in zip(rows[:-1], rows[1:]):
            for i in range(len(r0) - 1):
                f = bm.faces.new((r0[i], r0[i + 1], r1[i + 1], r1[i]))
                f.material_index = slot['CarPaint']
        bot, top = ring[0], ring[n]
        for row, apex in ((rows[0], bot), (rows[-1], top)):
            for i in range(len(row) - 1):
                f = bm.faces.new((row[i], row[i + 1], apex))
                f.material_index = slot['CarPaint']
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    from r35_common import new_obj
    ob = new_obj("Body", bm, [mats['CarPaint'], mats['GlassW'], mats['GlassS'], mats['GlassR'], mats['DarkTrim']])
    return ob, ys, landmarks
