import bpy, math
from mathutils import Vector

VIEWS = {
    # name: (camera location, look-at, focal mm)
    'front34': ((4.6, -6.2, 1.55), (0.0, -0.35, 0.62), 50),
    'side':    ((11.5, 0.0, 0.78), (0.0, 0.0, 0.66), 85),
    'rear34':  ((4.4, 6.4, 1.75), (0.0, 0.45, 0.70), 50),
    'front':   ((0.0, -11.0, 0.95), (0.0, 0.0, 0.62), 85),
    'rear':    ((0.0, 11.0, 1.05), (0.0, 0.0, 0.66), 85),
    'top':     ((0.0, 0.0, 14.0), (0.0, 0.0, 0.0), 85),
    'wheel':   ((2.6, -1.39, 0.40), (0.80, -1.39, 0.36), 50),
}


def setup_studio(res=(1280, 720), samples=24):
    sc = bpy.context.scene
    for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    try:
        sc.eevee.taa_render_samples = samples
    except Exception:
        pass
    try:
        sc.view_settings.view_transform = 'AgX'
        sc.view_settings.look = 'AgX - Medium High Contrast'
    except Exception:
        try:
            sc.view_settings.view_transform = 'Filmic'
        except Exception:
            pass
    w = bpy.data.worlds.get('Studio') or bpy.data.worlds.new('Studio')
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputWorld')
    bg = nt.nodes.new('ShaderNodeBackground')
    grad = nt.nodes.new('ShaderNodeTexGradient')
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    nt.links.new(tc.outputs['Generated'], mp.inputs['Vector'])
    mp.inputs['Rotation'].default_value = (0, -math.pi / 2, 0)
    nt.links.new(mp.outputs['Vector'], grad.inputs['Vector'])
    nt.links.new(grad.outputs['Fac'], ramp.inputs['Fac'])
    ramp.color_ramp.elements[0].color = (0.18, 0.19, 0.21, 1)
    ramp.color_ramp.elements[1].color = (0.75, 0.78, 0.82, 1)
    nt.links.new(ramp.outputs['Color'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = 0.9
    nt.links.new(bg.outputs['Background'], out.inputs['Surface'])
    # floor
    if 'Floor' not in bpy.data.objects:
        bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
        fl = bpy.context.active_object
        fl.name = 'Floor'
        m = bpy.data.materials.new('FloorMat'); m.use_nodes = True
        b = m.node_tree.nodes['Principled BSDF']
        b.inputs['Base Color'].default_value = (0.32, 0.33, 0.35, 1)
        b.inputs['Roughness'].default_value = 0.35
        fl.data.materials.append(m)
    # lights
    def light(name, kind, loc, energy, size=None, rot=None):
        if name in bpy.data.objects:
            return
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        if size and kind == 'AREA':
            ld.size = size
        ob = bpy.data.objects.new(name, ld)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = loc
        if rot:
            ob.rotation_euler = rot
        else:
            d = Vector((0, 0, 0.6)) - Vector(loc)
            ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    light('KeySun', 'SUN', (5, -4, 8), 3.2)
    light('SoftTop', 'AREA', (0, 0, 6), 900, size=6)
    light('RimBack', 'AREA', (-4, 7, 3), 500, size=4)
    light('FillFront', 'AREA', (-3, -7, 2.5), 350, size=4)


def render_view(name, path, views=VIEWS):
    loc, tgt, f = views[name]
    cam = bpy.data.objects.get('RCam')
    if cam is None:
        cd = bpy.data.cameras.new('RCam')
        cam = bpy.data.objects.new('RCam', cd)
        bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    d = Vector(tgt) - Vector(loc)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    cam.data.lens = f
    cam.data.clip_end = 200
    if name == 'top':
        cam.data.type = 'ORTHO'; cam.data.ortho_scale = 5.6
        cam.rotation_euler = (0.0, 0.0, math.pi / 2)
    else:
        cam.data.type = 'PERSP'
    bpy.context.scene.camera = cam
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_ortho_match(path, view='side'):
    """Orthographic render matched to the reference photos (px/m from the wheelbase)."""
    sc = bpy.context.scene
    cam = bpy.data.objects.get('RCam')
    if cam is None:
        cd = bpy.data.cameras.new('RCam'); cam = bpy.data.objects.new('RCam', cd)
        sc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    cam.data.clip_end = 200
    sc.render.film_transparent = True
    floor = bpy.data.objects.get('Floor')
    if floor: floor.hide_render = True
    if view == 'side':   # nc_04: 1920x1440, hubs (375,1135) / (1530,1135)
        ppm = 1155.0 / 2.78
        sc.render.resolution_x, sc.render.resolution_y = 1920, 1440
        cam.data.ortho_scale = 1920 / ppm
        yc = -1.39 + (960 - 375) / ppm
        zc = 0.355 + (1135 - 720) / ppm
        cam.location = (25, yc, zc); cam.rotation_euler = (math.pi / 2, 0, math.pi / 2)
    elif view == 'front':  # nc_08: 1920x1440, body 245..1675 => 1.895 m; ground at 1135
        ppm = 1430 / 1.895
        sc.render.resolution_x, sc.render.resolution_y = 1920, 1440
        cam.data.ortho_scale = 1920 / ppm
        cam.location = (0, -25, (1135 - 720) / ppm); cam.rotation_euler = (math.pi / 2, 0, 0)
    elif view == 'rear':   # nc_10: body 255..1675 ; ground 1160
        ppm = 1420 / 1.895
        sc.render.resolution_x, sc.render.resolution_y = 1920, 1440
        cam.data.ortho_scale = 1920 / ppm
        cam.location = (0, 25, (1160 - 720) / ppm); cam.rotation_euler = (math.pi / 2, 0, math.pi)
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    sc.render.film_transparent = False
    if floor: floor.hide_render = False
VIEWS['frontlow'] = ((1.6, -5.2, 0.55), (0.0, -2.2, 0.45), 70)
VIEWS['rearlow'] = ((-1.4, 5.0, 0.6), (0.0, 2.2, 0.5), 70)
VIEWS['deck'] = ((1.5, 4.2, 2.6), (0.0, 1.8, 1.0), 45)
VIEWS['nose34'] = ((2.9, -4.6, 1.05), (0.15, -2.0, 0.55), 55)
VIEWS['nosefront'] = ((0.0, -6.5, 0.85), (0.0, -2.0, 0.52), 60)
VIEWS['hlclose'] = ((2.2, -3.6, 0.95), (0.75, -2.1, 0.68), 85)
VIEWS['noseside'] = ((5.0, -2.9, 0.8), (0.4, -2.0, 0.6), 60)
VIEWS['mouthcorner'] = ((1.8, -3.5, 0.55), (0.6, -2.3, 0.32), 70)
VIEWS['hood'] = ((1.3, -3.2, 1.9), (0.2, -1.3, 0.9), 55)
