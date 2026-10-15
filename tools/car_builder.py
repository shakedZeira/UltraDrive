# UltraDrive car builder — parameterized low-poly car generator.
# Run inside Blender (blender-mcp_execute_blender_code, or headless):
#   exec(open(r'<project>\tools\car_builder.py', encoding='utf-8').read())
#   build_car(CarSpec(name="Nissan_370Z_2010", length=4.24, ...))
# Nose points +Y. Real-world meters. Exports one GLB per car.
# At export the whole car is rotated 180 deg about Z (via matrix_basis, exact
# integer matrix) so the nose lands on GLB +Z; restored afterwards for renders.
# Wheels are Wheel_FL/FR/RL/RR empties at the hub centre with identity
# rotation — the game overwrites hub.rotation with (spin, steer, 0), so all
# per-corner geometry must live under the hub.

import bpy
import math
import mathutils
import os

# 180 deg about Z: (x, y, z) -> (-x, -y, z). Exact (integer) so F @ F == I.
_FLIP = mathutils.Matrix(((-1, 0, 0, 0),
						  (0, -1, 0, 0),
						  (0, 0, 1, 0),
						  (0, 0, 0, 1)))


class CarSpec:
	def __init__(self, **kw):
		# identity / export
		self.name: str = kw.get("name", "Car")
		self.out_dir: str = kw.get("out_dir", r"D:\AI Projects\UltraDrive\assets\cars")
		self.export: bool = kw.get("export", True)
		# real dims (m)
		self.length: float = kw.get("length", 4.30)
		self.width: float = kw.get("width", 1.84)
		self.height: float = kw.get("height", 1.30)
		self.wheelbase: float = kw.get("wheelbase", 2.55)
		self.wheel_radius: float = kw.get("wheel_radius", 0.33)
		self.track: float = kw.get("track", 1.60)  # centre-to-centre
		# proportions (fractions of length, measured from car centre, nose +Y)
		self.overhang_f: float = kw.get("overhang_f", 0.24)
		self.hood_len: float = kw.get("hood_len", 0.90)   # cowl -> nose
		self.cabin_f: float = kw.get("cabin_f", 0.10)     # windscreen base ahead of centre
		self.cabin_r: float = kw.get("cabin_r", 0.42)     # roof rear behind centre (neg)
		self.roof_drop: float = kw.get("roof_drop", 0.06) # roof peak below height
		self.roof_rake: float = kw.get("roof_rake", 0.35) # 0 flat .. 1 steeply raked
		self.waist: float = kw.get("waist", 0.58)         # shoulder z / height
		self.sill: float = kw.get("sill", 0.20)           # bottom z / height
		self.tumble: float = kw.get("tumble", 0.78)       # roof half-width / body half-width
		self.haunch: float = kw.get("haunch", 1.04)       # max half-width / body half-width
		self.tail_short: float = kw.get("tail_short", 0.06)  # deck shrink
		self.deck_raise: float = kw.get("deck_raise", 0.0)   # extra decklid height (m)
		# style
		self.body_color = tuple(kw.get("body_color", (0.72, 0.73, 0.75, 1.0)))
		self.metallic: float = kw.get("metallic", 0.5)
		self.roughness: float = kw.get("roughness", 0.25)
		self.clearcoat: float = kw.get("clearcoat", 1.0)
		self.spokes: int = kw.get("spokes", 5)
		self.body_style: str = kw.get("body_style", "coupe")  # coupe | sedan | hatch | suv
		self.lights: bool = kw.get("lights", True)
		self.mirrors: bool = kw.get("mirrors", True)
		# opt-in style kit — generic defaults keep the other specs byte-identical
		self.headlight_style: str = kw.get("headlight_style", "round")  # round | swept
		self.grille_style: str = kw.get("grille_style", "simple")       # simple | gtr
		self.quad_taillights: bool = kw.get("quad_taillights", False)
		self.rear_wing: bool = kw.get("rear_wing", False)
		self.quad_exhaust: bool = kw.get("quad_exhaust", False)
		self.hood_vents: bool = kw.get("hood_vents", False)
		self.side_vents: bool = kw.get("side_vents", False)
		self.front_splitter: bool = kw.get("front_splitter", False)
		self.shoulder_line: bool = kw.get("shoulder_line", False)
		self.fastback_glass: bool = kw.get("fastback_glass", False)


def _mat(name, color, metal=0.0, rough=0.5, extra=None, update=False):
	m = bpy.data.materials.get(name)
	if m:
		if not update:
			return m
		b = m.node_tree.nodes["Principled BSDF"]
		b.inputs["Base Color"].default_value = (*color[:3], 1.0)
		b.inputs["Metallic"].default_value = metal
		b.inputs["Roughness"].default_value = rough
		if extra:
			for k, v in extra.items():
				if k in b.inputs:
					b.inputs[k].default_value = v
		return m
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	b = m.node_tree.nodes["Principled BSDF"]
	b.inputs["Base Color"].default_value = (*color[:3], 1.0)
	b.inputs["Metallic"].default_value = metal
	b.inputs["Roughness"].default_value = rough
	if extra:
		for k, v in extra.items():
			if k in b.inputs:
				b.inputs[k].default_value = v
	return m


def _mesh_obj(name, verts, faces, material, parent, smooth=True):
	me = bpy.data.meshes.new(name + "Mesh")
	me.from_pydata(verts, [], faces)
	me.update()
	if smooth:
		for p in me.polygons:
			p.use_smooth = True
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	ob.parent = parent
	if material:
		ob.data.materials.append(material)
	return ob


def _box(name, loc, size, rot, material, parent):
	"""size = full (x, y, z) dimensions of a unit cube."""
	bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot or (0, 0, 0))
	ob = bpy.context.object
	ob.name = name
	ob.scale = size
	if material:
		ob.data.materials.append(material)
	ob.parent = parent
	return ob


def _cyl(name, loc, radius, depth, rot, material, parent, vertices=24):
	bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=vertices,
										location=loc, rotation=rot or (0, 0, 0))
	ob = bpy.context.object
	ob.name = name
	if material:
		ob.data.materials.append(material)
	ob.parent = parent
	for p in ob.data.polygons:
		p.use_smooth = True
	return ob


def _body_bvh(body):
	"""BVH of the body's EVALUATED (subdivided) mesh, for surface placement."""
	dg = bpy.context.evaluated_depsgraph_get()
	ev = body.evaluated_get(dg)
	me = ev.to_mesh()
	verts = [v.co.copy() for v in me.vertices]
	polys = [tuple(p.vertices) for p in me.polygons]
	ev.to_mesh_clear()
	return mathutils.bvhtree.BVHTree.FromPolygons(verts, polys, all_triangles=False,
												  epsilon=0.0)


def _hw_at(secs, y):
	"""Linearly interpolated half-width of the loft at y (sections ascend)."""
	if y <= secs[0][0]:
		return secs[0][1]
	if y >= secs[-1][0]:
		return secs[-1][1]
	for i in range(len(secs) - 1):
		y0, w0 = secs[i][0], secs[i][1]
		y1, w1 = secs[i + 1][0], secs[i + 1][1]
		if y0 <= y <= y1:
			if y1 <= y0:
				return w1
			return w0 + (w1 - w0) * (y - y0) / (y1 - y0)
	return secs[-1][1]


def _clear_scene():
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	# drop stale data so the next car never inherits the previous paint
	for me in list(bpy.data.meshes):
		if me.users == 0:
			bpy.data.meshes.remove(me)
	for m in list(bpy.data.materials):
		if m.users == 0:
			bpy.data.materials.remove(m)


def _sections(spec: CarSpec):
	"""Loft cross-sections: (y, half_w, z_bottom, z_shoulder, z_top)."""
	h = spec.height
	hw = spec.width * 0.5
	H = spec.wheel_radius * 2  # ride height reference
	y_nose = spec.length * 0.5
	y_tail = -spec.length * 0.5 + spec.tail_short
	y_cowl = y_nose - spec.hood_len
	y_ws = y_cowl                     # windscreen base
	y_roof_f = spec.cabin_f           # roof front (ahead of centre)
	y_roof_r = spec.cabin_r           # roof rear (behind centre)
	z_top = h - spec.roof_drop
	z_sh = h * spec.waist
	z_bot = h * spec.sill
	rake = spec.roof_rake

	# (y,            half_w,               z_bot, z_sh,   z_top)
	pts = [
		(y_tail, hw * 0.86, z_bot + 0.10, z_sh * 0.92, z_sh * 1.02),          # tail
		(y_tail * 0.72, hw * 0.98, z_bot, z_sh, z_sh * 1.14),                  # rear quarter
		(spec.wheelbase * -0.5, hw * spec.haunch, z_bot, z_sh, h * 0.74),      # rear haunch
		(y_roof_r, hw * spec.tumble, z_bot, z_sh, z_top - 0.02),               # roof rear
		((y_roof_f + y_roof_r) * 0.5, hw * spec.tumble * 1.0, z_bot, z_sh, z_top),  # roof peak
		(y_roof_f, hw * spec.tumble, z_bot, z_sh, z_top - 0.01 * rake),        # roof front
		(y_ws, hw * 0.94, z_bot, z_sh, z_top - (z_top - z_sh) * rake),         # windscreen base
		(y_cowl, hw * 0.96, z_bot, z_sh * 0.97, z_sh + 0.10),                  # cowl
		(y_nose - spec.overhang_f * 0.4, hw * 0.94, z_bot + 0.02, z_sh * 0.92, z_sh * 0.95),  # hood
		(y_nose, hw * 0.84, z_bot + 0.08, z_sh * 0.86, z_sh * 0.88),           # nose
	]
	if spec.body_style == "hatch":
		pts[1] = (y_tail * 0.72, hw * 0.98, z_bot, z_sh, z_top - 0.04)  # steep hatch
	if spec.body_style == "suv":
		pts[0] = (y_tail, hw * 0.90, z_bot + 0.16, z_sh * 0.96, z_sh * 1.10)
		pts[9] = (y_nose, hw * 0.88, z_bot + 0.14, z_sh * 0.92, z_sh * 0.96)
	if spec.deck_raise:
		# high, flat decklid (GT-R style): lift the tail quarters and taper the
		# extra height out before the rear haunch so the silhouette stays smooth.
		dr = spec.deck_raise
		pts[0] = (pts[0][0], pts[0][1], pts[0][2], z_sh * 0.96, z_sh * 1.02 + dr)
		pts[1] = (pts[1][0], pts[1][1], pts[1][2], z_sh, z_sh * 1.14 + dr * 0.7)
		pts[2] = (pts[2][0], pts[2][1], pts[2][2], z_sh, h * 0.74 + dr * 0.3)
	return pts


def _ring(y, hw, zb, zs, zt, tumble):
	return [(-hw, y, zb), (-hw, y, zs), (-hw * tumble, y, zt - 0.06),
			(0.0, y, zt + 0.05), (hw * tumble, y, zt - 0.06), (hw, y, zs),
			(hw, y, zb), (0.0, y, zb)]


def _flip_objects(parts):
	# Rotate the whole car 180 deg about Z (nose +Y -> -Y -> GLB +Z).
	# Meshes (incl. hub children): exact basis transform (parent chain
	# matrix_parent_inverse all identity). Wheel hubs are EMPTY nodes: the game
	# overwrites hub.rotation, so only the LOCATION may be negated — children
	# then get their own basis flipped, which composes to exactly
	# world_new = F @ world_old (T(F@h) @ F == F @ T(h) for linear F).
	# Involution: calling twice restores bit-exact transforms (F is integer).
	for ob in parts:
		if ob.type == 'EMPTY':
			loc = ob.location
			ob.location = (-loc.x, -loc.y, loc.z)
		else:
			ob.matrix_basis = _FLIP @ ob.matrix_basis


def build_car(spec: CarSpec) -> bpy.types.Object:
	_clear_scene()
	root = bpy.data.objects.new(spec.name, None)
	bpy.context.scene.collection.objects.link(root)

	m_paint = _mat("CarPaint", spec.body_color, spec.metallic, spec.roughness,
				   {"Coat Weight": spec.clearcoat, "Coat Roughness": 0.04}, update=True)
	m_glass = _mat("Glass", (0.02, 0.03, 0.04), 0.9, 0.05, {"Transmission Weight": 0.7})
	m_tyre = _mat("Tyre", (0.03, 0.03, 0.03), 0.0, 0.85)
	m_rim = _mat("Rim", (0.75, 0.75, 0.78), 1.0, 0.2)
	m_brake = _mat("BrakeDisc", (0.32, 0.32, 0.33), 0.9, 0.35)
	m_cal = _mat("Caliper", (0.55, 0.03, 0.03), 0.55, 0.32)
	m_trim = _mat("DarkTrim", (0.02, 0.02, 0.02), 0.2, 0.5)
	m_head = _mat("Headlight", (0.9, 0.9, 0.85), 0.1, 0.1,
				  {"Emission Strength": 2.0, "Emission Color": (1, 1, 0.95, 1)})
	m_tail = _mat("Taillight", (0.7, 0.02, 0.02), 0.1, 0.15,
				  {"Emission Strength": 1.5, "Emission Color": (1, 0.05, 0.05, 1)})

	# ---- body shell ----
	secs = _sections(spec)
	tumble = spec.tumble
	verts = [p for s in secs for p in _ring(*s, tumble)]
	n = 8
	faces = []
	for i in range(len(secs) - 1):
		for j in range(n):
			a = i * n + j
			b = i * n + (j + 1) % n
			c = (i + 1) * n + (j + 1) % n
			d = (i + 1) * n + j
			faces.append((a, b, c, d))
	faces.append(tuple(range(n - 1, -1, -1)))
	last = (len(secs) - 1) * n
	faces.append(tuple(last + j for j in range(n)))
	body = _mesh_obj("Body", verts, faces, m_paint, root)
	sub = body.modifiers.new("Subd", 'SUBSURF')
	sub.levels = 2
	sub.render_levels = 2

	# ---- glass greenhouse ----
	# Side windows only: two flank bands, roof centre stays body colour
	# (a strip across the top turned the whole roof black). The windscreen
	# is a separate probed skin added after the surface probes exist.
	roof = [s for s in secs if s[0] >= spec.cabin_r and s[0] <= spec.cabin_f]
	gv, gf = [], []
	for (y, hw, zb, zs, zt) in roof:
		gw = hw * 0.97
		gv += [(-gw, y, zs - 0.04), (-gw * 0.95, y, zt - 0.06),
			   (gw * 0.95, y, zt - 0.06), (gw, y, zs - 0.04)]
	for i in range(len(roof) - 1):
		for j in (0, 2):  # left band + right band — never cross the roof
			a = i * 4 + j
			gf.append((a, a + 1, a + 5, a + 4))
	if gv:
		glass = _mesh_obj("Glass", gv, gf, m_glass, root)
		glass.modifiers.new("Subd", 'SUBSURF').levels = 2
		glass.modifiers.new("Solid", 'SOLIDIFY').thickness = 0.02

	# ---- wheels ----
	R = spec.wheel_radius
	tr = spec.track * 0.5
	ax_f = spec.wheelbase * 0.5
	ax_r = -spec.wheelbase * 0.5
	# x signs are PRE-FLIP: after _flip_nose (x -> -x) FL must land on GLB +X
	# (car's left, nose +Z), so FL/RL are built on -x and L accents on -sx.
	corners = (("FL", ax_f, -tr), ("FR", ax_f, tr), ("RL", ax_r, -tr), ("RR", ax_r, tr))
	for tag, y, x in corners:
		hub = bpy.data.objects.new("Wheel_" + tag, None)
		hub.empty_display_type = 'PLAIN_AXES'
		hub.empty_display_size = 0.25
		hub.location = (x, y, R)
		bpy.context.scene.collection.objects.link(hub)
		hub.parent = root

		def _under_hub(ob):
			# keep world pose while parenting: basis' = T(-hub) @ basis
			# (parent/root and matrix_parent_inverse both identity)
			b = ob.matrix_basis.copy()
			ob.parent = hub
			ob.matrix_basis = mathutils.Matrix.Translation((-x, -y, -R)) @ b

		bpy.ops.mesh.primitive_torus_add(major_radius=R * 0.80, minor_radius=R * 0.22,
										 major_segments=32, minor_segments=12,
										 location=(x, y, R), rotation=(0, math.radians(90), 0))
		tyre = bpy.context.object
		tyre.name = "Tyre_" + tag
		tyre.data.materials.append(m_tyre)
		_under_hub(tyre)
		for p in tyre.data.polygons:
			p.use_smooth = True

		s = 1.0 if x > 0 else -1.0
		xs = x + s * R * 0.03    # rotor/caliper plane, just behind the spokes
		xf = x + s * R * 0.14    # face plane: lip, spokes, hub cap

		# Brake rotor: closes the barrel centre (spoke gaps must not be
		# see-through) and reads as dark metal behind the spokes.
		bpy.ops.mesh.primitive_cylinder_add(radius=R * 0.60, depth=tr * 0.10, vertices=32,
											location=(xs, y, R), rotation=(0, math.radians(90), 0))
		rotor = bpy.context.object
		rotor.name = "BrakeDisc_" + tag
		rotor.data.materials.append(m_brake)
		_under_hub(rotor)
		for p in rotor.data.polygons:
			p.use_smooth = True

		# Rim = outer lip ring only; the old solid dish hid the brakes.
		bpy.ops.mesh.primitive_torus_add(major_radius=R * 0.70, minor_radius=R * 0.06,
										 major_segments=32, minor_segments=10,
										 location=(xf, y, R), rotation=(0, math.radians(90), 0))
		rim = bpy.context.object
		rim.name = "Rim_" + tag
		rim.data.materials.append(m_rim)
		_under_hub(rim)
		for p in rim.data.polygons:
			p.use_smooth = True

		for k in range(spec.spokes):
			a = k * 2 * math.pi / spec.spokes
			bpy.ops.mesh.primitive_cube_add(size=1, location=(
				xf, y + R * 0.36 * math.cos(a), R + R * 0.36 * math.sin(a)))
			sp = bpy.context.object
			sp.name = f"Spoke_{tag}_{k}"
			sp.scale = (0.02, R * 0.10, R * 0.64)
			sp.rotation_euler = (a, 0, 0)
			sp.data.materials.append(m_rim)
			_under_hub(sp)

		# Hub cap over the spoke centre.
		bpy.ops.mesh.primitive_cylinder_add(radius=R * 0.17, depth=tr * 0.07, vertices=24,
											location=(xf, y, R), rotation=(0, math.radians(90), 0))
		cap = bpy.context.object
		cap.name = "HubCap_" + tag
		cap.data.materials.append(m_rim)
		_under_hub(cap)
		for p in cap.data.polygons:
			p.use_smooth = True

		# Fixed caliper — root-parented on purpose: hub.rotation is written
		# every frame, which would orbit a hub-child caliper around the axle
		# like a spoke. On the root it just sits still on the upright.
		bpy.ops.mesh.primitive_cube_add(size=1, location=(
			xs, y - R * 0.32, R + R * 0.44))
		capr = bpy.context.object
		capr.name = "Caliper_" + tag
		capr.scale = (tr * 0.13, R * 0.24, R * 0.42)
		capr.rotation_euler = (math.radians(-16), 0, 0)
		capr.data.materials.append(m_cal)
		capr.parent = root

	# ---- lights / mirrors / trim ----
	y_nose = spec.length * 0.5
	y_tail = -spec.length * 0.5 + spec.tail_short
	hw_nose = spec.width * 0.42
	z_sh = spec.height * spec.waist
	z_bot = spec.height * spec.sill
	# Probes against the EVALUATED (subdivided) shell: the cage sits well
	# outside the rendered surface, so style-kit parts are placed on hits.
	_probe = {}

	def _surface(origin, direction):
		if "bvh" not in _probe:
			_probe["bvh"] = _body_bvh(body)
		hit = _probe["bvh"].ray_cast(mathutils.Vector(origin),
									mathutils.Vector(direction).normalized())[0]
		return hit

	def _down(x, y, fallback):
		h = _surface((x, y, 6.0), (0, 0, -1))
		return h.z if h is not None else fallback

	def _nose_y(x, z, fallback):
		h = _surface((x, y_nose + 1.2, z), (0, -1, 0))
		return h.y if h is not None else fallback

	def _rear_y(x, z, fallback):
		h = _surface((x, y_tail - 1.2, z), (0, 1, 0))
		return h.y if h is not None else fallback

	def _flank_x(y, z, sx, fallback):
		h = _surface((sx * (hw_nose + 0.6), y, z), (-sx, 0, 0))
		return h.x if h is not None else fallback

	# Probed windscreen skin on the cowl -> roof-front slope (this slope used
	# to ship as bare body colour — a painted windscreen). 7 columns so the
	# chord cannot sag under the convex shell (3 columns left the body
	# poking through the middle); winding gives UP-facing normals (Godot
	# culls backfaces).
	ws_y0 = y_nose - spec.hood_len + 0.05   # just behind the cowl edge
	ws_y1 = spec.cabin_f - 0.06             # stops before the roof panel
	wv, wf = [], []
	ws_rows = 6
	cols = 7
	for r in range(ws_rows):
		t = r / float(ws_rows - 1)
		y = ws_y0 + (ws_y1 - ws_y0) * t
		half = _hw_at(secs, y) * 0.90
		fallback = z_sh + 0.10
		for c in range(cols):
			fx = -1.0 + 2.0 * c / (cols - 1)
			x = half * fx
			wv.append((x, y, _down(x, y, fallback) + 0.045))
	for r in range(ws_rows - 1):
		for c in range(cols - 1):
			a = r * cols + c
			wf.append((a + cols, a + cols + 1, a + 1, a))
	if wf:
		ws = _mesh_obj("Windscreen", wv, wf, m_glass, root)
		ws.modifiers.new("Solid", 'SOLIDIFY').thickness = 0.02

	if spec.lights:
		for sx, side in ((-1, "L"), (1, "R")):
			if spec.headlight_style == "swept":
				# slim blade raked from the grille corner back into the fender,
				# outer tip riding high (GT-R nose signature)
				x0, y0 = 0.22, y_nose - 0.05
				x1, y1 = hw_nose * 0.96, y_nose - 0.62
				cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
				ang = math.atan2(y1 - y0, x1 - x0)
				ln = math.hypot(x1 - x0, y1 - y0)
				hz = _down(cx, cy, spec.height * 0.56) - 0.03
				bpy.ops.mesh.primitive_cube_add(size=1, location=(sx * cx, cy, hz))
				h = bpy.context.object
				h.name = "Headlight_" + side
				h.scale = (ln, 0.11, 0.10)
				h.rotation_euler = (0, math.radians(-9 * sx), sx * ang)
				h.data.materials.append(m_head)
				h.parent = root
			else:
				bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, segments=16, ring_count=8,
													 location=(hw_nose * 0.72 * sx, y_nose - 0.10, spec.height * 0.46))
				h = bpy.context.object
				h.name = "Headlight_" + side
				h.scale = (1.5, 0.35, 0.7)
				h.rotation_euler = (0, 0, math.radians(-12 * sx))
				h.data.materials.append(m_head)
				h.parent = root
				for p in h.data.polygons:
					p.use_smooth = True

			if spec.quad_taillights:
				# two round lamps per side on one Taillight_L/R node — the GT-R
				# four-lamp ring. Probe the rear face so they sit ON the panel.
				z_lamp = z_sh * 1.02 + spec.deck_raise - 0.15
				lamps = []
				for dx in (0.32, 0.62):
					y_face = _rear_y(sx * dx, z_lamp, y_tail)
					bpy.ops.mesh.primitive_cylinder_add(radius=0.125, depth=0.07, vertices=24,
														location=(sx * dx, y_face - 0.015, z_lamp),
														rotation=(math.radians(90), 0, 0))
					lt = bpy.context.object
					lt.data.materials.append(m_tail)
					for p in lt.data.polygons:
						p.use_smooth = True
					lamps.append(lt)
				bpy.ops.object.select_all(action='DESELECT')
				for lt in lamps:
					lt.select_set(True)
				bpy.context.view_layer.objects.active = lamps[0]
				bpy.ops.object.join()
				t = bpy.context.object
				t.name = "Taillight_" + side
				t.parent = root
			else:
				bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, segments=16, ring_count=8,
													 location=(hw_nose * 0.70 * sx, y_tail + 0.06, spec.height * 0.50))
				t = bpy.context.object
				t.name = "Taillight_" + side
				t.scale = (1.6, 0.3, 0.65)
				t.data.materials.append(m_tail)
				t.parent = root
				for p in t.data.polygons:
					p.use_smooth = True
	if spec.mirrors:
		for sx, side in ((-1, "L"), (1, "R")):
			# Probed onto the flank so the arm never floats off the body.
			my = spec.cabin_f + 0.10
			mz = spec.height * 0.71
			fx = _flank_x(my, mz, sx, spec.width * 0.42)
			_box("MirrorArm_" + side, (fx + sx * 0.05, my, mz),
				 (0.16, 0.035, 0.035), None, m_paint, root)
			_box("Mirror_" + side, (fx + sx * 0.155, my - 0.01, mz + 0.01),
				 (0.09, 0.15, 0.10), None, m_paint, root)

	# front end
	if spec.grille_style == "gtr":
		# big lower rectangular intake (the FrontIntake node, resized) sitting
		# flush on the probed nose face — GT-R's fascia is mostly opening
		z_in = spec.height * 0.30
		y_in = _nose_y(0.0, z_in, y_nose) + 0.02
		inp = _box("FrontIntake", (0, y_in, z_in), (spec.width * 0.56, 0.10, 0.24),
				   None, m_trim, root)
		# slim upper slot between the headlights, just under the hood edge
		z_up = z_sh * 0.86
		y_up = _nose_y(0.0, z_up, y_nose) + 0.015
		_box("UpperGrille", (0, y_up, z_up), (spec.width * 0.46, 0.07, 0.05),
			 None, m_trim, root)
		# corner brake-cooling ducts
		for sx, side in ((-1, "L"), (1, "R")):
			z_c = spec.height * 0.34
			y_c = _nose_y(sx * spec.width * 0.35, z_c, y_nose) + 0.015
			_box("IntakeCorner_" + side, (sx * spec.width * 0.35, y_c, z_c),
				 (0.22, 0.08, 0.16), None, m_trim, root)
	else:
		_box("FrontIntake", (0, y_nose + 0.01, spec.height * 0.30),
			 (spec.width * 0.36, 0.06, 0.10), None, m_trim, root)

	if spec.front_splitter:
		z_sp = z_bot * 0.75
		y_sp = _nose_y(0.0, z_sp + 0.04, y_nose)
		_box("FrontSplitter", (0, y_sp - 0.03, z_sp),
			 (spec.width * 0.47, 0.20, 0.045), None, m_trim, root)

	if spec.hood_vents:
		# twin heat extractors either side of the power bulge
		for sx in (-1, 1):
			vx = sx * spec.width * 0.16
			vy = y_nose - spec.hood_len * 0.62
			vz = _down(vx, vy, spec.height * 0.62)
			_box("HoodVent_" + ("L" if sx < 0 else "R"), (vx, vy, vz - 0.012),
				 (0.085, 0.42, 0.05), (0, 0, math.radians(-4 * sx)), m_trim, root)

	if spec.side_vents:
		# fender exit vent just behind the front wheel
		for sx in (-1, 1):
			vy = spec.wheelbase * 0.5 - 0.48
			vz = z_sh * 0.70
			vx = _flank_x(vy, vz, sx, spec.width * 0.42)
			_box("SideVent_" + ("L" if sx < 0 else "R"), (vx, vy, vz),
				 (0.05, 0.34, 0.10), None, m_trim, root)

	if spec.shoulder_line:
		# raised character line along the flank, one ribbon per side, sampled
		# on the loft so it hugs the body from rear quarter to cowl
		for sx, tag in ((-1, "L"), (1, "R")):
			sv, sf = [], []
			for (y, hw, zb, zs, zt) in secs[1:-1]:
				sv += [(sx * hw * 1.012, y, zs - 0.045),
					   (sx * hw * 1.012, y, zs + 0.045)]
			for i in range(len(secs) - 3):
				a = i * 2
				sf.append((a, a + 1, a + 3, a + 2))
			sb = _mesh_obj("Shoulder_" + tag, sv, sf, m_paint, root, smooth=False)
			sb.modifiers.new("Solid", 'SOLIDIFY').thickness = 0.03

	if spec.fastback_glass:
		# sloping rear screen from the roof's trailing edge down onto the deck
		i_r = i_h = None
		for i, s in enumerate(secs):
			if abs(s[0] - spec.cabin_r) < 1e-6:
				i_r = i
			if abs(s[0] + spec.wheelbase * 0.5) < 1e-6:
				i_h = i
		if i_r is not None and i_h is not None and i_r > i_h:
			y_r, y_h = secs[i_r][0], secs[i_h][0]
			z_r, z_h = secs[i_r][4], secs[i_h][4]
			klass = 5
			fb_pts = []
			for k in range(klass + 1):
				t = k / float(klass)
				y = y_r + (y_h - y_r) * t
				half = _hw_at(secs, y) * tumble * (0.95 - 0.05 * t)
				fallback = z_r + (z_h - z_r) * t + 0.012
				row = []
				for fx in (-1.0, 0.0, 1.0):
					x = half * fx
					z = _down(x, y, fallback) + 0.012
					row.append((x, y, z))
				fb_pts.append(row)
			fv, ff = [], []
			for row in fb_pts:
				fv += row
			for k in range(klass):
				a = k * 3
				ff.append((a, a + 1, a + 4, a + 3))
				ff.append((a + 1, a + 2, a + 5, a + 4))
			fb = _mesh_obj("GlassFastback", fv, ff, m_glass, root)
			fb.modifiers.new("Solid", 'SOLIDIFY').thickness = 0.02

	if spec.rear_wing:
		y_deck = -spec.length * 0.5 + spec.tail_short * 0.5
		z_deck = z_sh * 1.14 + spec.deck_raise * 0.5
		_box("RearWing", (0, y_deck, z_deck + 0.19),
			 (spec.width * 0.82, 0.20, 0.035),
			 (math.radians(6), 0, 0), m_paint, root)
		for sx, side in ((-1, "L"), (1, "R")):
			_box("RearWingPost_" + side,
				 (sx * spec.width * 0.28, y_deck + 0.02, z_deck + 0.08),
				 (0.045, 0.14, 0.16), None, m_trim, root)

	if spec.quad_exhaust:
		# two polished tips per side, poking out of the rear valance
		z_ex = z_bot + 0.16
		for sx in (-1, 1):
			for k, dx in enumerate((0.30, 0.46)):
				y_ex = _rear_y(sx * dx, z_ex, y_tail)
				_cyl("Exhaust_%s%d" % ("L" if sx < 0 else "R", k + 1),
					 (sx * dx, y_ex - 0.03, z_ex), 0.05, 0.16,
					 (math.radians(90), 0, 0), m_rim, root, vertices=20)

	# rear valance
	if spec.grille_style == "gtr":
		z_df = z_bot + 0.06
		y_df = _rear_y(0.0, z_df + 0.12, y_tail)
		_box("Diffuser", (0, y_df - 0.03, z_df), (spec.width * 0.44, 0.14, 0.16),
			 None, m_trim, root)
		for dx in (-0.30, -0.10, 0.10, 0.30):
			_box("DiffuserFin_%d" % int(dx * 100 + 40), (dx, y_df - 0.09, z_df - 0.04),
				 (0.02, 0.16, 0.14), None, m_trim, root)
	else:
		_box("Diffuser", (0, y_tail - 0.01, spec.height * 0.23),
			 (spec.width * 0.38, 0.05, 0.10), None, m_trim, root)

	# ---- export ----
	if spec.export:
		parts = [ob for ob in bpy.data.objects if ob != root and _is_child(ob, root)]
		_flip_objects(parts)  # nose +Y -> GLB +Z
		# Lift root-level parts to top level (root is identity, pinv identity,
		# so basis == world and unparenting is world-preserving). The GLB then
		# ships WITHOUT a wrapper node: Godot's importer parents the parts
		# straight under the file-named scene root, which is what
		# CarVisuals.resolve_wheel_nodes / get_node_or_null("Wheel_FL") expect.
		for ob in parts:
			if ob.parent == root:
				ob.parent = None
		os.makedirs(spec.out_dir, exist_ok=True)
		path = os.path.join(spec.out_dir, spec.name.lower() + ".glb")
		for ob in bpy.data.objects:
			ob.select_set(ob in parts)
		bpy.context.view_layer.objects.active = parts[0]
		bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB',
								  export_yup=True, export_apply=True)
		print(f"exported {path} ({os.path.getsize(path)} bytes)")
		_flip_objects(parts)  # restore nose +Y so studio renders look at the front
		for ob in parts:
			if ob.parent is None:
				ob.parent = root
	return root


def _is_child(ob, root):
	p = ob.parent
	while p is not None:
		if p == root:
			return True
		p = p.parent
	return False


def setup_studio():
	"""3-point lights + camera for review renders."""
	for name, loc, energy, size in (
			("Key", (4, 3, 5), 800, 4), ("Fill", (-4, 1, 3), 300, 5), ("Rim", (0, -5, 4), 500, 3)):
		ld = bpy.data.lights.new(name, 'AREA')
		ld.energy = energy
		ld.size = size
		lo = bpy.data.objects.new(name, ld)
		bpy.context.scene.collection.objects.link(lo)
		lo.location = loc
		d = lo.location
		lo.rotation_euler = (math.atan2(math.hypot(d[0], d[1]), d[2]), 0, math.atan2(-d[0], d[1]) + math.pi)
	cam_d = bpy.data.cameras.new("Cam")
	cam = bpy.data.objects.new("Cam", cam_d)
	bpy.context.scene.collection.objects.link(cam)
	cam.location = (5.2, 4.6, 2.1)
	cam.rotation_euler = (math.radians(72), 0, math.radians(131))
	bpy.context.scene.camera = cam
	sc = bpy.context.scene
	sc.render.resolution_x = 960
	sc.render.resolution_y = 540
	sc.render.image_settings.file_format = 'PNG'
	if not sc.world:
		sc.world = bpy.data.worlds.new("World")
	sc.world.use_nodes = True
	bg = sc.world.node_tree.nodes.get("Background")
	if bg:
		bg.inputs[0].default_value = (0.35, 0.37, 0.40, 1)


def render(path):
	sc = bpy.context.scene
	sc.render.filepath = path
	bpy.ops.render.render(write_still=True)
	return path
