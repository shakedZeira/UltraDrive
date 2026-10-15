# THROWAWAY (agent 3) - dump Northern Isle centerline curvature / corner-speed
# targets to see why the AI's curvature braking barely fires. DELETE WHEN DONE.
extends SceneTree

const NI := "res://scripts/track/northern_isle_layout.gd"

func _init() -> void:
    var layout = load(NI)
    var line: Array[Vector3] = layout.build_centerline()
    var n := line.size()
    print("[track] points=%d width=%.1f" % [n, layout.WIDTH])
    var spacing := 0.0
    for i in n:
        spacing += line[i].distance_to(line[(i + 1) % n])
    spacing /= float(n)
    print("[track] mean_spacing=%.2f m  perimeter=%.0f m" % [spacing, spacing * n])
    # Raw per-point curvature (1/R) from the immediate triplet.
    var kmax := 0.0
    var tight: Array = []
    for i in n:
        var a := line[(i - 1 + n) % n]
        var b := line[i]
        var c := line[(i + 1) % n]
        var k := _curv(a, b, c)
        if k > kmax:
            kmax = k
        tight.append([i, k])
    print("[track] max raw curvature=%.5f (R=%.1f m)" % [kmax, 1.0 / maxf(kmax, 1e-6)])
    # Corner-speed target sqrt(a/k) for a few lat-accel budgets, at each index
    # using the immediate-triplet curvature (a good proxy for a tight corner).
    for budget in [7.0, 5.0]:
        var worst := INF
        var worst_i := -1
        for e in tight:
            var i: int = e[0]
            var k: float = e[1]
            if k <= 1e-6:
                continue
            var target := sqrt(budget / k)
            if target < worst:
                worst = target
                worst_i = i
        print("[track] budget=%.1f m/s^2 -> tightest corner idx=%d target=%.1f m/s (%.0f km/h)" % [
            budget, worst_i, worst, worst * 3.6])
    # Per-index curvature in the problem band (idx 55..95), the wedge zone.
    for i in range(55, 96):
        var a := line[(i - 1 + n) % n]
        var b := line[i]
        var c := line[(i + 1) % n]
        var k := _curv(a, b, c)
        var tgt := sqrt(7.0 / k) if k > 1e-6 else 999.0
        print("  idx=%d k=%.5f R=%.1f target7=%.1f (%.0f km/h)" % [
            i, k, 1.0 / maxf(k, 1e-6), tgt, tgt * 3.6])
    quit(0)

func _curv(a: Vector3, b: Vector3, c: Vector3) -> float:
    var ab := b - a
    var bc := c - b
    var ca := c - a
    ab.y = 0.0
    bc.y = 0.0
    ca.y = 0.0
    var la := ab.length()
    var lb := bc.length()
    var lc := ca.length()
    if la < 1e-4 or lb < 1e-4 or lc < 1e-4:
        return 0.0
    var cross2 := ab.x * bc.z - ab.z * bc.x
    return 2.0 * absf(cross2) / (la * lb * lc)
