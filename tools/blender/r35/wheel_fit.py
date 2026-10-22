# Eye-space (x right, y forward, z up). Find wheel + dial layout with both dials unoccluded.
import math, itertools
def occluded(p, C, alpha, R_in=0.145, R_out=0.182, hub=0.074):
    # wheel plane: through C, normal n = (0, -cos a, sin a)?? plane tilted alpha from vertical, top leaning forward
    a = alpha
    up = (0.0, math.sin(a), math.cos(a))       # in-plane 'up' (forward+up)
    n = (0.0, -math.cos(a), math.sin(a))        # toward driver & up
    # ray from eye (0,0,0) to p: t*p ; intersect plane (x - C).n = 0
    dn = p[1]*n[1] + p[2]*n[2]
    if abs(dn) < 1e-9: return False
    t = (C[1]*n[1] + C[2]*n[2]) / dn
    if t <= 0 or t >= 1: return False
    q = (p[0]*t - C[0], p[1]*t - C[1], p[2]*t - C[2])
    u = q[0]; v = q[1]*up[1] + q[2]*up[2]
    r = math.hypot(u, v)
    if R_in - 0.004 <= r <= R_out + 0.004: return True
    if r <= hub + 0.006: return True
    if abs(v + 0.012) < 0.020 and r < R_in: return True     # 3/9 o'clock spokes
    if abs(u) < 0.020 and v < 0 and r < R_in: return True   # bottom spoke
    return False
def elev(p): return math.degrees(math.atan2(p[2], p[1]))
def azim(p): return math.degrees(math.atan2(p[0], p[1]))
best = None
for Yc in [0.42, 0.45, 0.48, 0.51, 0.54]:
  for Zc in [-0.24, -0.26, -0.28, -0.30, -0.32]:
    for adeg in [20, 25, 30]:
      a = math.radians(adeg); C = (0.0, Yc, Zc)
      top_el = elev((0, Yc + 0.182*math.sin(a), Zc + 0.182*math.cos(a)))
      for Yd in [0.72, 0.76, 0.80, 0.84]:
        for rd in [0.030, 0.034, 0.038, 0.042, 0.046, 0.050]:
          for dx in [x/1000 for x in range(40, 90, 4)]:
            if dx < rd + 0.004: continue
            for zd in [x/1000 for x in range(-340, -150, 5)]:
              ok = True; lowest = 0; highest = -90
              for cx in (-dx, dx):
                for k in range(24):
                  for rr in (rd, rd*0.6, rd*0.2):
                    ang = 2*math.pi*k/24
                    p = (cx + rr*math.cos(ang), Yd, zd + rr*math.sin(ang))
                    if occluded(p, C, a): ok = False; break
                    lowest = min(lowest, elev(p)); highest = max(highest, elev(p))
                  if not ok: break
                if not ok: break
              if ok and lowest > -28.0 and highest < top_el - 0.3:
                score = rd*1000 - abs(top_el + 14)*0.1
                if best is None or score > best[0]:
                  best = (score, dict(Yc=Yc, Zc=Zc, alpha=adeg, Yd=Yd, rd=rd, dx=dx, zd=zd, wheel_centre_elev=round(elev(C),1), rim_top_elev=round(top_el,1), dial_lowest=round(lowest,1)))
print(best)
