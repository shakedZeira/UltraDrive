import csv, sys
label = sys.argv[1]
who = sys.argv[2] if len(sys.argv) > 2 else None
t0 = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
t1 = float(sys.argv[4]) if len(sys.argv) > 4 else 1e9
step = int(sys.argv[5]) if len(sys.argv) > 5 else 1
rows = list(csv.DictReader(open(r"reports/parallel/agent3/%s.csv" % label)))
names = sorted(set(r["name"] for r in rows))
for name in names:
    if who and who.lower() not in name.lower():
        continue
    sub = [r for r in rows if r["name"] == name and t0 <= float(r["t"]) <= t1]
    print("=== %s (%s) rows=%d ===" % (name, sub[0]["tier/class"] if sub else "?", len(sub)))
    for i, r in enumerate(sub):
        if i % step:
            continue
        print("  t=%6.2f near=%3s tgt=%3s lat=%4.1f spd=%5.1f thr=%.2f brk=%.2f steer=%5.2f yaw=%6.1f gear=%s rpm=%.0f" % (
            float(r["t"]), r["nearest_idx"], r["target_idx"], float(r["lateral_m"]),
            float(r["speed_kmh"]), float(r["thr"]), float(r["brk"]),
            float(r["steer"]), float(r["yaw_err_deg"]), r["gear"], float(r["rpm"])))
