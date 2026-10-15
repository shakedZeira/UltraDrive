import csv, collections, sys

label = sys.argv[1] if len(sys.argv) > 1 else "after"
path = r"reports/parallel/agent3/%s.csv" % label
rows = list(csv.DictReader(open(path)))
print("rows", len(rows))
brk = [float(r["brk"]) for r in rows]
print("brk nonzero", sum(1 for b in brk if b > 0.001), "of", len(brk), "max", max(brk))

per = collections.defaultdict(list)
for r in rows:
    per[(r["name"], r["tier/class"])].append(r)
for key, rs in per.items():
    speeds = [float(r["speed_kmh"]) for r in rs]
    lat = [float(r["lateral_m"]) for r in rs]
    yaw = [float(r["yaw_err_deg"]) for r in rs]
    # wedge: consecutive samples with speed<3
    wedge = 0.0
    best = 0.0
    for r in rs:
        if float(r["speed_kmh"]) < 3.0:
            wedge += 0.5
            best = max(best, wedge)
        else:
            wedge = 0.0
    moving = sum(1 for s in speeds if s >= 3.0) * 0.5
    print("%s %s: avg=%.1f max=%.1f  lat(avg/max)=%.1f/%.1f  yaw(avg/max)=%.0f/%.0f  moving=%.0fs wedged(maxrun)=%.1fs" % (
        key[0], key[1], sum(speeds)/len(speeds), max(speeds),
        sum(lat)/len(lat), max(lat), sum(yaw)/len(yaw), max(yaw), moving, best))
