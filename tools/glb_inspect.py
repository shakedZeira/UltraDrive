import json
import struct
import sys

path = sys.argv[1] if len(sys.argv) > 1 else r"assets/cars/nissan_gt-r_r35_2017.glb"
d = open(path, "rb").read()
jl = struct.unpack("<I", d[12:16])[0]
j = json.loads(d[20:20 + jl])


def fmt(v):
    if v is None:
        return None
    return [round(x, 3) for x in v]


print("nodes:", len(j.get("nodes", [])))
for i, n in enumerate(j.get("nodes", [])):
    print(i, repr(n.get("name")),
          "t", fmt(n.get("translation")),
          "r", fmt(n.get("rotation")),
          "s", fmt(n.get("scale")),
          "children", n.get("children"),
          "mesh" if "mesh" in n else "")
