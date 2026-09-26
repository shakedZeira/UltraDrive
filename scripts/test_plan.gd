extends RefCounted

func _init():
    var defs := CorridorPlanner.plan(CorridorPlanner.MASTER_SEED)
    print("Plan returned ", defs.size(), " road defs")
    for i in range(defs.size()):
        print("  [", i, "] ", defs[i].id, " points=", defs[i].points.size(), " width=", defs[i].width, " closed=", defs[i].closed, " tier=", defs[i].tier)
    print("TOTAL POINTS: ", defs.size())