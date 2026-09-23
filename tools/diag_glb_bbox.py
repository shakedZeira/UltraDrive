import struct, json, sys, math

def load(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:4] == b'glTF'
    length = struct.unpack('<I', data[8:12])[0]
    pos = 12
    jdata = None
    while pos < length:
        clen, ctype = struct.unpack('<II', data[pos:pos+8])
        chunk = data[pos+8:pos+8+clen]
        if ctype == 0x4E4F534A:
            jdata = json.loads(chunk.decode('utf-8'))
        pos += 8 + clen
    return jdata

ZERO = [0.0]*16
def ident():
    return [1.0,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]

def trs(t, r, s):
    x,y,z,w = r
    R = [1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w), 0,
         2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w), 0,
         2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y), 0,
         0,0,0,1]
    T = [1,0,0,0, 0,1,0,0, 0,0,1,0, t[0],t[1],t[2],1]
    S = [s[0],0,0,0, 0,s[1],0,0, 0,0,s[2],0, 0,0,0,1]
    # column-major: M = T * R * S
    return mm(mm(T,R),S)

def mm(a,b):
    # a,b column-major 4x4 -> c = a*b
    c=[0.0]*16
    for col in range(4):
        for row in range(4):
            c[col*4+row] = sum(a[k*4+row]*b[col*4+k] for k in range(4))
    return c

def xform_point(m, p):
    x,y,z = p
    return (m[0]*x+m[4]*y+m[8]*z+m[12],
            m[1]*x+m[5]*y+m[9]*z+m[13],
            m[2]*x+m[6]*y+m[10]*z+m[14])

def main(path):
    j = load(path)
    nodes = j.get('nodes', [])
    accessors = j.get('accessors', [])
    bufferViews = j.get('bufferViews', [])
    meshes = j.get('meshes', [])

    def node_mat(i, parent):
        n = nodes[i]
        if 'matrix' in n:
            m = n['matrix']
        else:
            m = trs(n.get('translation',[0,0,0]), n.get('rotation',[0,0,0,1]), n.get('scale',[1,1,1]))
        return mm(parent, m)

    # walk tree with matrices
    def walk(i, parent):
        n = nodes[i]
        m = node_mat(i, parent) if i < len(nodes) else parent
        prim_bounds = []
        # check node mesh (handles 'mesh' at node, and also children nodes with mesh)
        node_mesh_index = n.get('mesh')
        yield (node_mesh_index, m, i)
        for c in n.get('children', []):
            yield from walk(c, m)

    # Compute for each mesh primitive its accessor min/max transformed by world matrix
    all_bounds = []
    root_indices = j['scenes'][0]['nodes'] if 'scenes' in j and j['scenes'] else list(range(len(nodes)))
    for root_i in root_indices:
        # also treat every node as a root if scenes missing; walk from each
        for (mesh_i, m, ni) in walk(root_i, ident()):
            if mesh_i is None or mesh_i >= len(meshes):
                continue
            mesh = meshes[mesh_i]
            for prim in mesh.get('primitives', []):
                pos_acc = prim.get('attributes', {}).get('POSITION')
                if pos_acc is None:
                    continue
                acc = accessors[pos_acc]
                mini = acc.get('min', [-1e9,-1e9,-1e9])
                maxi = acc.get('max', [1e9,1e9,1e9])
                corners = [
                    [mini[0],mini[1],mini[2]], [maxi[0],mini[1],mini[2]],
                    [mini[0],maxi[1],mini[2]], [maxi[0],maxi[1],mini[2]],
                    [mini[0],mini[1],maxi[2]], [maxi[0],mini[1],maxi[2]],
                    [mini[0],maxi[1],maxi[2]], [maxi[0],maxi[1],maxi[2]],
                ]
                for c in corners:
                    all_bounds.append(xform_point(m, c))
    if not all_bounds:
        print('NO BOUNDS')
        return
    mn = [min(p[k] for p in all_bounds) for k in range(3)]
    mx = [max(p[k] for p in all_bounds) for k in range(3)]
    print('WORLD_AABB min=', [round(v,3) for v in mn], 'max=', [round(v,3) for v in mx])
    print('size=', [round(mx[k]-mn[k],3) for k in range(3)])
    print('center=', [round((mn[k]+mx[k])/2,3) for k in range(3)])

if __name__ == '__main__':
    main(sys.argv[1])