import csv, sys, math
label = sys.argv[1]
rows = list(csv.DictReader(open(r"reports/parallel/agent3/%s.csv" % label)))
names = sorted(set(r["name"] for r in rows))
# Build per-time snapshots
by_t = {}
for r in rows:
    by_t.setdefault(float(r["t"]), {})[r["name"]] = r

print("=== %s : min gap to nearest rival, and worst contact frame ===" % label)
overall = {}
for t in sorted(by_t):
    snap = by_t[t]
    present = [n for n in names if n in snap]
    for a in present:
        pa = (float(snap[a]["px"]), float(snap[a]["pz"]))
        best = 1e9; who = ""
        for b in present:
            if b == a:
                continue
            pb = (float(snap[b]["px"]), float(snap[b]["pz"]))
            d = math.hypot(pa[0] - pb[0], pa[1] - pb[1])
            if d < best:
                best = d; who = b
        if a not in overall or best < overall[a][0]:
            overall[a] = (best, t, who)
for a in names:
    if a in overall:
        print("  %-20s min gap %.2f m to %s at t=%.2f" % (a, overall[a][0], overall[a][2], overall[a][1]))

# print per-frame gaps for the whole early period, focused on the Expert spin
who = sys.argv[2] if len(sys.argv) > 2 else None
print("\n--- gap timeline t=0..25 (all cars) ---")
for t in sorted(by_t):
    if t > 25:
        break
    snap = by_t[t]
    line = "t=%6.2f " % t
    for a in names:
        if a not in snap:
            continue
        pa = (float(snap[a]["px"]), float(snap[a]["pz"]))
        best = 1e9
        for b in names:
            if b == a or b not in snap:
                continue
            pb = (float(snap[b]["px"]), float(snap[b]["pz"]))
            best = min(best, math.hypot(pa[0] - pb[0], pa[1] - pb[1]))
        line += "| %s gap=%5.1f spd=%5.1f yaw=%5.1f " % (a.replace("@RigidBody3D@", "R"), best, float(snap[a]["speed_kmh"]), float(snap[a]["yaw_err_deg"]))
    print(line)
