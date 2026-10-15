import csv, sys
label = sys.argv[1] if len(sys.argv) > 1 else "after2"
rows = list(csv.DictReader(open(r"reports/parallel/agent3/%s.csv" % label)))
# corner band = nearest_idx 55..95
print("=== %s : rows with nearest_idx in 55..95 (the R=60 corner) ===" % label)
for name in sorted(set(r["name"] for r in rows)):
    sub = [r for r in rows if r["name"] == name and 55 <= int(r["nearest_idx"]) <= 95]
    if not sub:
        continue
    sp = [float(r["speed_kmh"]) for r in sub]
    brk = [float(r["brk"]) for r in sub]
    thr = [float(r["thr"]) for r in sub]
    print("%-20s n=%3d speed(min/avg/max)=%5.1f/%5.1f/%5.1f  brk_nonzero=%d/%d maxbrk=%.1f  thr_avg=%.2f" % (
        name, len(sub), min(sp), sum(sp)/len(sp), max(sp),
        sum(1 for b in brk if b > 0.001), len(sub), max(brk), sum(thr)/len(thr)))
# Print a time slice for each car around when it is in the corner
print("\n--- slice: first entry into corner band per car ---")
for name in sorted(set(r["name"] for r in rows)):
    sub = [r for r in rows if r["name"] == name]
    inband = [r for r in sub if 55 <= int(r["nearest_idx"]) <= 95]
    if not inband:
        continue
    start = sub.index(inband[0])
    print(name)
    for r in sub[start:start+14]:
        print("  t=%5.2f near=%3s tgt=%3s lat=%4.1f spd=%5.1f thr=%.2f brk=%.2f steer=%5.2f yaw=%5.1f" % (
            float(r["t"]), r["nearest_idx"], r["target_idx"], float(r["lateral_m"]),
            float(r["speed_kmh"]), float(r["thr"]), float(r["brk"]),
            float(r["steer"]), float(r["yaw_err_deg"])))
