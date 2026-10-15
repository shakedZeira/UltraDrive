import math

def rot_x(t):
    c, s = math.cos(t), math.sin(t)
    return [1,0,0, 0,c,-s, 0,s,c]

def rot_z(t):
    c, s = math.cos(t), math.sin(t)
    return [c,-s,0, s,c,0, 0,0,1]

def mmul(a, b):
    out = [0.0]*9
    for i in range(3):
        for j in range(3):
            out[i*3+j] = sum(a[i*3+k]*b[k*3+j] for k in range(3))
    return out

def axis_major(M):  # .tscn Transform3D stores basis vectors axis-major
    return [M[0], M[3], M[6],  M[1], M[4], M[7],  M[2], M[5], M[8]]

p = math.radians(32)
# LEFT  (+X post): pitch +25 (top falls back toward driver), roll +6 (top in)
# RIGHT (-X post): pitch +25, roll -6 -> pure rotation, symmetric, no winding flip
left  = axis_major(mmul(rot_z(math.radians(6)),  rot_x(p)))
right = axis_major(mmul(rot_z(math.radians(-6)), rot_x(p)))
print("LEFT ", " ".join("%.6f" % v for v in left))
print("RIGHT", " ".join("%.6f" % v for v in right))