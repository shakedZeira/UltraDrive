# Nissan GT-R R35 — Tail/Brake Lights, Reverse Light, and Transparent Glass

**Plan status:** PROPOSED (analysis complete; no code changed). Planning-only document.
**Author session date:** 2026-10-16
**Scope of the change:** three visual defects on the builder-generated Nissan GT-R
R35 2017 (`assets/cars/nissan_gt-r_r35_2017.glb`), fixed in the **runtime visual
pipeline** (`scripts/vehicle/car_visuals.gd` and its two call sites). The binary
GLBs are **not** edited.

---

## 1. Symptoms and one-line causes

| # | Symptom (reported) | Root cause | Fix location |
|---|---|---|---|
| 1 | Only 2 of the 4 tail lamps glow on brake | The player caches **one** taillight material; the R35 rear cluster is **two** mesh nodes, so only the first node's lamps respond to brake | `car_visuals.gd` (new collector) + `player_car_controller.gd` cache/apply |
| 2 | No reverse (white) light at all | No reverse-lamp geometry or material exists in the GLB, the builder, or any runtime code | `car_visuals.gd` (runtime white lamp builder) + player & rival call sites |
| 3 | Windshield renders as a black panel | `_glass_clone` keeps the near-black GLB albedo and leaves transparency **disabled** (`refraction_enabled = false`, opaque) | `car_visuals.gd::_glass_clone` |

All three are fixed on the **CarVisuals side** so the fix survives GLB
regeneration by `tools/car_builder.py` and applies to *every* car that routes
through the shared paint pipeline, not just the R35.

---

## 2. Root-cause analysis (with evidence)

### 2.0 Verified facts

- `project.godot:167` → `renderer/rendering_method="forward_plus"` (transparency
  and the transparent render pass are available).
- The player visual is painted by `CarVisuals.apply_paint()`
  (`scripts/vehicle/car_visuals.gd:531`) **before** the materials are cached in
  `PlayerCarController._cache_visuals()`
  (`scripts/player/player_car_controller.gd:248-252`, paint at line 232, cache at
  line 233). `apply_paint` gives **every GLB surface its own cloned
  `StandardMaterial3D`** (`_paint_mesh_instance` → `_make_override`,
  `car_visuals.gd:561-595`). So the runtime material graph is one clone per
  *surface*, not one per GLB material.
- `find_named_material` (`car_visuals.gd:287-306`) is a depth-first search that
  returns on the **first** match (`return material` at line 300, recursion
  returns at line 305).
- Rivals share the same pipeline: `RivalCarVisual.build()`
  (`scripts/vehicle/rival_car_visual.gd:89-103`) calls the same
  `CarVisuals.apply_paint(instance, profile)` at line 99.
- No reverse-light symbol exists anywhere in `scripts/` or `resources/`
  (`brake_light` / `reverse_light` / `reverse` material ⇒ no matches in the
  visual layer; only the *drivetrain* reverse-gear code exists).

### 2.1 GLB dump — `assets/cars/nissan_gt-r_r35_2017.glb`

Extracted directly from the GLB JSON chunk (materials + mesh/node inventory):

```
=== assets/cars/nissan_gt-r_r35_2017.glb
MATERIALS 9
  0 'CarPaint'  base=[0.07,0.24,0.55,1]  metal=0.5  rough=0.25  ext={'KHR_materials_clearcoat': {clearcoatFactor:1, roughness:0.04}}
  1 'Glass'     base=[0.02,0.03,0.04,1]  metal=0.9  rough=0.05  ext={'KHR_materials_transmission': {transmissionFactor:0.7}}  doubleSided=True
  2 'BrakeDisc' base=[0.32,0.32,0.33,1]  metal=0.9  rough=0.35
  3 'Rim'       base=[0.75,0.75,0.78,1]  metal=-  rough=0.20
  4 'Tyre'      base=[0.03,0.03,0.03,1]  metal=0.0  rough=0.85
  5 'Caliper'   base=[0.55,0.03,0.03,1]  metal=0.55 rough=0.32
  6 'Headlight' base=[0.9,0.9,0.85,1]  metal=0.1 rough=0.1  emis=[1,1,0.95]      ext={'KHR_materials_emissive_strength': {emissiveStrength:2}}
  7 'Taillight' base=[0.7,0.02,0.02,1] metal=0.1 rough=0.15 emis=[1,0.05,0.05]   ext={'KHR_materials_emissive_strength': {emissiveStrength:1.5}}
  8 'DarkTrim'  base=[0.02,0.02,0.02,1] metal=0.2 rough=0.5
MESHES 75  (only the taillight + glass meshes are relevant)
  47 'Cylinder.008' surfaces=['Taillight']
  49 'Cylinder.010' surfaces=['Taillight']
   1 'GlassMesh'         surfaces=['Glass']
  38 'WindscreenMesh'    surfaces=['Glass']
  41 'GlassFastbackMesh' surfaces=['Glass']
NODES(mesh) translation
   1 'Glass'          mesh='GlassMesh'          surfaces=['Glass']
  42 'Windscreen'     mesh='WindscreenMesh'     surfaces=['Glass']
  45 'GlassFastback'  mesh='GlassFastbackMesh' surfaces=['Glass']
  50 'Headlight_L'    mesh='Cube.024'  t=[ 0.492, 0.759,  2.020]  surfaces=['Headlight']
  51 'Taillight_L'    mesh='Cylinder.008' t=[ 0.320, 0.788, -2.238] surfaces=['Taillight']
  52 'Headlight_R'    mesh='Cube.025'  t=[-0.492, 0.759,  2.020]  surfaces=['Headlight']
  53 'Taillight_R'    mesh='Cylinder.010' t=[-0.320, 0.788, -2.238] surfaces=['Taillight']
```

**Key facts embedded above**

- There are **two** taillight nodes (`Taillight_L`, `Taillight_R`); each mesh is
  a **joined 2-lamp** mesh with a **single** surface → **4 lamps, 2 surfaces, 1
  shared GLB material index 7 (`Taillight`)**.
- There are **three** glass nodes (`Glass`, `Windscreen`, `GlassFastback`), all
  surface material index 1 (`Glass`), whose base colour is **near-black**
  `[0.02, 0.03, 0.04, 1]`.
- **No** reverse/white material and **no** reverse mesh node exists. Material 7
  and its emissive strength are the *only* rear-lamp definition.

Contrast — `assets/cars/sports_coupe.glb` (why that car "looks right"):

```
  3 'Taillight' base=[0,0,0,1] metal=0.0 rough=0.3 emis=[1,0.089,0.067] ext={emissiveStrength:3.6}
NODES(mesh)
   3 'Taillights' mesh='Cube.017' t=[0, 0.470, -1.980] surfaces=['Taillight']   # ONE node, ONE surface
  1 'Glass'      mesh='Glass'    surfaces=['Glass']  base=[0.02,0.03,0.05,1] metal=0.0 rough=0.05 transmission=1.0
```

`sports_coupe` has a **single** `Taillights` node → a single surface → a single
clone → `find_named_material` finds *the* taillight and both of its lamps glow.
The R35's two-node cluster is exactly what the single-match cache cannot handle.

### 2.2 FIX 1 — why only 2 of 4 lamps glow

1. `apply_paint` clones the shared GLB material 7 **twice** — once for
   `Taillight_L`'s surface, once for `Taillight_R`'s surface
   (`car_visuals.gd:584-585` routes a `taillight`-named material to
   `_light_clone`, which does `source.duplicate()` at `car_visuals.gd:675-679`).
2. `_cache_visuals` stores only the **first** match:
   `_taillight_material = CarVisuals.find_named_material(instance, "taillight")`
   (`player_car_controller.gd:250`).
3. `_process` ramps only that one clone:
   `CarVisuals.apply_brake_glow(_taillight_material, brake)`
   (`player_car_controller.gd:61`, definition `car_visuals.gd:311-315`).
4. Result: `Taillight_L`'s clone ramps to `BRAKE_GLOW_MAX = 5.0`; `Taillight_R`'s
   clone keeps whatever the import gave it → the two halves disagree. The user
   sees "only 2 glow."

Depth-first `find_named_material` reaches whichever taillight node the tree walk
visits first (deterministic, but only one of the two).

### 2.3 FIX 2 — why there is no reverse light

There is simply nothing to light: no white/clear material, no reverse mesh, and
no runtime builder. `Headlights` (`scripts/car/headlights.gd`) is a *front*
SpotLight pair only; the CarVisuals night layer
(`car_visuals.gd:317-529`) builds 2 forward spots + 1 rear red **OmniLight** — no
reverse cue. Rivals have **no** brake or reverse driving code at all:
`RivalCarVisual._process` (`rival_car_visual.gd:108-118`) only spins wheels.

The drive inputs already exist: `VehiclePhysics.get_drive_info()`
(`scripts/vehicle/vehicle_physics.gd:482-506`) returns `"brake"`
(line 498, clamp 0..1) and `"gear"` (line 494; reverse is `-1`, a real gear).
So both lamps can be driven from the existing per-frame `get_drive_info()` poll.

### 2.4 FIX 3 — why the windshield is black

`_glass_clone` (`car_visuals.gd:666-673`):

```gdscript
static func _glass_clone(source: StandardMaterial3D, profile: Dictionary) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	if profile.has("glass_color"):
		cloned.albedo_color = profile["glass_color"]
	cloned.metallic = profile["glass_metallic"]     # DEFAULT_PAINT = 0.9
	cloned.roughness = profile["glass_roughness"]   # 0.05
	cloned.refraction_enabled = false
	return cloned
```

- For **builder/AI cars** (R35, sports_coupe, muscle, rally) the profile is
  `DEFAULT_PAINT` (`car_visuals.gd:30-42`), which has **no `glass_color`** —
  `paint_profile_for` only injects `glass_color`/`tire_color` for the CC0 ids
  (`car_visuals.gd:542-552`). So the clone **keeps the near-black GLB albedo**
  `[0.02,0.03,0.04,1]`.
- `transparency` is **never set**, so it stays whatever the source was (the GLB
  ships opaque; see 2.5). `refraction_enabled = false`.
- Net result: an **opaque, near-black, metallic(0.9)** panel. From the chase cam
  the windshield reads as black glass/metal.

**The GLB's `KHR_materials_transmission` does not save it.** `StandardMaterial3D`
has no transmission property; `_glass_clone` forces `refraction_enabled = false`
and never enables transparency, so the runtime outcome is opaque regardless of
what the importer did with the extension. (In the earlier analysis pass the
decompressed `*.glb-*.scn` import artifact's property-name table contained
`refraction_enabled` and `transparency` but **zero** `transmission_enabled`
entries — i.e. the extension did not arrive as a usable transmission. This is a
*previously observed* detail: re-confirm at implementation time with an
`--import` + material probe if desired; the fix below does not depend on it.)

The current opaque-glass behaviour is **intentional in the old design** and is
pinned by tests — that pin is what must be re-decided:

- `tests/suites/test_car_paint_materials.gd:94-108` asserts
  `refraction_enabled == false` **and** `transparency == TRANSPARENCY_DISABLED`.
- `tests/suites/test_car_visuals.gd:61-67` asserts `metallic == 0.9` and
  `transparency == TRANSPARENCY_DISABLED`.
- `tests/suites/test_cockpit_visibility.gd:160-209` asserts the AI-car glass is
  `TRANSPARENCY_DISABLED` outside cockpit and flips to `TRANSPARENCY_ALPHA`
  *only* while the cockpit camera is active.

`car_visuals.gd:714-722` documents the old intent: *"the paint pipeline ships
glass OPAQUE on purpose (mirror-clean from the chase cam)"* — the exact design
this task reverses.

### 2.5 Open verification item (does not block the fix)

Whether Godot's glTF importer maps `KHR_materials_transmission` onto a
`StandardMaterial3D` at all was only ever observed (not re-verified in this
pass — the `.godot/imported` tree is absent on this checkout). It is **not a
dependency** of the fix: `_glass_clone` fully dictates the runtime result, so
making the clone explicitly tinted + `TRANSPARENCY_ALPHA` fixes it either way.

---

## 3. Design decisions and rationale

Guiding rule from the task: **prefer runtime CarVisuals-side fixes over binary
`.glb` edits** (the GLBs are regenerated by `tools/car_builder.py`), and make the
fixes work for **player and rivals through one shared seam**.

### 3.1 FIX 1 — collect **all** matching materials

- Add `CarVisuals.find_named_materials(root, filter) -> Array[StandardMaterial3D]`
  that walks the tree exactly like `find_named_material` but **accumulates every**
  matching surface-override (deduplicated by `material.get_instance_id()`).
- Re-implement the existing `find_named_material` as a thin wrapper returning the
  **first** element (or `null`). This keeps every existing call/test valid
  (`find_named_material` is pinned by `test_car_visuals.gd:309-320` and
  `test_car_paint_materials.gd:122`).
- Add `CarVisuals.apply_brake_glow_all(materials: Array[StandardMaterial3D], brake)`
  that loops the existing `apply_brake_glow` (no new math, no allocation per call).
- Call site: the player caches the **array** and ramps every element; the rival
  caches the same array and ramps every element.
- **Why dedup by instance:** the same override could be reachable twice (e.g. a
  mesh re-used under two nodes). Glowing it twice is harmless but the dedup keeps
  `find_named_materials().size()` a meaningful "number of lit lamp materials" for
  tests.

This is the minimal change that fixes the R35 (2 taillight nodes → both glow)
without special-casing the car, and it is what makes the sport coupé still work
(it has 1 node → 1 material).

### 3.2 FIX 2 — a runtime white reverse lamp, built and driven in CarVisuals

No GLB material or mesh exists to reuse, so build the lamps at runtime, positioned
from the **measured GLB tail geometry**.

- `CarVisuals.build_reverse_lamps(visual_root) -> Node3D` builds a holder
  (`"ReverseLamps"`, group `"reverse_lamps"`) parented **under the visual root
  (the GLB instance)** so `CAR_ORIENT` applies automatically and positions are
  authored in GLB space exactly like the GLB's own nodes.
- Mount positions are **derived from the GLB**: for each `MeshInstance3D` whose
  resolved material name contains `"taillight"`, place one white bar at that
  node's local origin, nudged **inboard, slightly down and slightly rearward**
  (so it reads as a distinct lamp segment rather than a white sticker over the
  red pair). R35 → 2 nodes → 2 white bars; sports_coupe → 1 node → 1 white bar.
  A per-car override table (`REVERSE_LAMP_LOCALS`, optional) can pin exact
  positions later without touching code.
- Each lamp is a thin `BoxMesh` (`Vector3(0.30, 0.10, 0.05)` in GLB space:
  lateral × vertical × depth) with a white emissive `StandardMaterial3D`
  (`resource_name = "ReverseLight"`, `emission_enabled`, white, energy
  `REVERSE_LIGHT_ENERGY`). A **mesh**, not a `Light3D`: reverse lamps light the
  road *indirectly* at most and the project has a light budget — this costs
  nothing extra and stays headless-testable.
- Ship **hidden** (`visible = false`); `apply_reverse_glow(lamps, active)` is the
  single idempotent switch (`lamps.visible = active`).
- **Empty-safe:** if no taillight node is found (e.g. the CC0 Comet, which has no
  taillight mesh), `build_reverse_lamps` returns an **empty hidden holder** and
  `apply_reverse_glow` is a no-op.

**"Driven from the same place the brake glow is driven":** both brake glow and
reverse glow are driven in the *same per-frame visual update* that already reads
`get_drive_info()` — `PlayerCarController._process`
(`player_car_controller.gd:45-64`) and `RivalCarVisual._process`
(`rival_car_visual.gd:108-118`). The reverse lamp uses `info["gear"] < 0`
(reverse gear is `-1`).

**Rivals gain brake glow too, for free,** because the shared seam that drives the
reverse lamp also drives the brake ramp on the same cached taillight array. This
is required so that "reverse works for rivals" is literally driven from the same
place the brake glow is; it is not a separate feature.

### 3.3 FIX 3 — tinted, transparent glass by default

Re-decide the old "opaque mirror glass" contract:

- New default tint for cars with no `glass_color` in their profile:
  `DEFAULT_GLASS_COLOR := Color(0.42, 0.50, 0.58, 0.45)` (cool, semi-clear;
  alpha < 1 is the point).
- `DEFAULT_PAINT["glass_metallic"]` 0.9 → **0.0** (a metallic pane with alpha is
  still a dark mirror; a *clear* pane is non-metallic).
- `_glass_clone` becomes:
  - `albedo_color = profile.get("glass_color", DEFAULT_GLASS_COLOR)`
  - `metallic = profile["glass_metallic"]` (now 0.0)
  - `roughness = profile["glass_roughness"]` (0.05)
  - `transparency = BaseMaterial3D.TRANSPARENCY_ALPHA`
  - `refraction_enabled = false` (**unchanged** — refraction needs a screen
    texture and stays off by design)

**Why this is safe for the cockpit path** (`cockpit_rig.gd` / interior view): the
cockpit pass **value-snapshots** the current `transparency` and `albedo_color.a`
into meta and restores them on exit
(`car_visuals.gd:810-834`); it does not assume the baseline is
`TRANSPARENCY_DISABLED`. So shipping `TRANSPARENCY_ALPHA / 0.45` as the baseline
is transparent to the cockpit pass — while the cockpit camera owns the viewport
it lowers alpha to `COCKPIT_GLASS_ALPHA = 0.18` and, on exit, restores `0.45`.
Cockpit logic, the rig, and the R35 interior all keep working.

**Render priority:** considered, **not needed.** Transparent surfaces render in
the transparent pass after all opaque geometry, and glass sits above an opaque
body, so no explicit `render_priority` change is required. (Leave at the default
`0`; revisit only if a real sorting artifact appears.)

**Double-sided note (risk, see §6):** the GLB glass is `doubleSided`, so both the
outer and inner faces of a pane render; with alpha they composite to roughly
double the tint. This is acceptable and is captured as a tuning risk rather than a
code change.

---

## 4. Step-by-step implementation

### 4.1 `scripts/vehicle/car_visuals.gd`

**(a) New constants** (near the existing glass/paint constants):

```gdscript
## Default cool-tinted, semi-transparent glass for cars whose paint profile
## carries no glass_color (builder/AI cars). alpha < 1 is the whole point: the
## pane must transmit, not mirror.
const DEFAULT_GLASS_COLOR := Color(0.42, 0.50, 0.58, 0.45)

## Reverse-lamp geometry/behaviour (FIX 2). Reverse is a runtime-built white
## emissive bar measured off the taillight nodes; it is a MESH (no Light3D) to
## stay inside the light budget.
const REVERSE_LAMP_HOLDER := "ReverseLamps"
const REVERSE_LAMP_GROUP := "reverse_lamps"
const REVERSE_LIGHT_NAME := "ReverseLight"
const REVERSE_LIGHT_COLOR := Color(1.0, 0.98, 0.92, 1.0)
const REVERSE_LIGHT_ENERGY := 6.0
const REVERSE_LIGHT_SIZE := Vector3(0.30, 0.10, 0.05)  # GLB space: x,y,z
const REVERSE_LAMP_INBOARD := 0.16      # pull each lamp toward centreline
const REVERSE_LAMP_DOWN := 0.02
const REVERSE_LAMP_REARWARD := 0.03
```

**(b) `DEFAULT_PAINT`:** change `"glass_metallic": 0.9` → `"glass_metallic": 0.0`
(line 39).

**(c) Collect every match (FIX 1):**

```gdscript
## DFS for EVERY StandardMaterial3D whose resource_name contains name_filter
## (case-insensitive), deduped by instance. Surface overrides are checked first
## so the live clones produced by apply_paint() are found. Sibling of
## find_named_material(), which is kept as the "first match" convenience.
static func find_named_materials(root: Node3D, name_filter: String) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	if root == null:
		return out
	_collect_named_materials(root, name_filter.to_lower(), out, {})
	return out

static func _collect_named_materials(node: Node3D, needle: String,
		out: Array[StandardMaterial3D], seen: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material: Material = mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh.surface_get_material(surface_index)
				if material is StandardMaterial3D \
						and material.resource_name.to_lower().contains(needle):
					var id := material.get_instance_id()
					if not seen.has(id):
						seen[id] = true
						out.append(material as StandardMaterial3D)
	for child: Node in node.get_children():
		if child is Node3D:
			_collect_named_materials(child as Node3D, needle, out, seen)

static func find_named_material(root: Node3D, name_filter: String) -> StandardMaterial3D:
	var all := find_named_materials(root, name_filter)
	return all[0] if not all.is_empty() else null
```

**(d) Ramp every material (FIX 1):**

```gdscript
## Applies apply_brake_glow to every cached taillight material (the R35 rear
## cluster is TWO nodes / two clones). Never allocates.
static func apply_brake_glow_all(materials: Array[StandardMaterial3D], brake: float) -> void:
	for material in materials:
		apply_brake_glow(material, brake)
```

**(e) Reverse lamps (FIX 2):**

```gdscript
## GLB-space mounts for the reverse lamps: one per taillight mesh node, nudged
## inboard / down / rearward so the white bar reads as its own segment. Empty
## when the visual carries no taillight mesh (safe no-op).
static func reverse_lamp_mounts(visual_root: Node3D) -> Array[Vector3]:
	var mounts: Array[Vector3] = []
	for node in _taillight_meshes(visual_root):
		var p := (node as MeshInstance3D).position
		var inboard := -signf(p.x) * REVERSE_LAMP_INBOARD
		mounts.append(p + Vector3(inboard, -REVERSE_LAMP_DOWN, -REVERSE_LAMP_REARWARD))
	return mounts

## Builds the reverse lamp holder under the visual root (so CAR_ORIENT applies).
## Lamps ship hidden; apply_reverse_glow() is the only switch. Returns the holder
## even when empty, so call sites never need a null check on construction.
static func build_reverse_lamps(visual_root: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = REVERSE_LAMP_HOLDER
	holder.add_to_group(REVERSE_LAMP_GROUP)
	holder.visible = false
	if visual_root != null:
		var material := StandardMaterial3D.new()
		material.resource_name = REVERSE_LIGHT_NAME
		material.albedo_color = REVERSE_LIGHT_COLOR
		material.emission_enabled = true
		material.emission = REVERSE_LIGHT_COLOR
		material.emission_energy_multiplier = REVERSE_LIGHT_ENERGY
		for mount in reverse_lamp_mounts(visual_root):
			var lamp := MeshInstance3D.new()
			lamp.name = REVERSE_LIGHT_NAME
			var box := BoxMesh.new()
			box.size = REVERSE_LIGHT_SIZE
			box.material = material
			lamp.mesh = box
			lamp.position = mount
			lamp.visible = false
			holder.add_child(lamp)
		visual_root.add_child(holder)
	return holder

static func apply_reverse_glow(lamps: Node3D, active: bool) -> void:
	if lamps == null:
		return
	lamps.visible = active

static func reverse_lamp_count(lamps: Node3D) -> int:
	return 0 if lamps == null else lamps.get_child_count()
```

Plus a small `_taillight_meshes(root) -> Array[Node3D]` helper mirroring the
`find_named_materials` walk but returning the `MeshInstance3D` nodes (not the
materials). *(Implementation detail: collect the nodes whose resolved material
name contains `"taillight"`.)*

**(f) Cockpit classification:** add `"reverse"` to the OTHER branch of
`_material_cockpit_role` (`car_visuals.gd:799-802`) so the cockpit pass never
hides/repurposes the reverse lamps. (Harmless either way — a rear lamp is
invisible from the cockpit — but this keeps the role table honest.)

**(g) `_glass_clone` (FIX 3):**

```gdscript
static func _glass_clone(source: StandardMaterial3D, profile: Dictionary) -> StandardMaterial3D:
	var cloned: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	cloned.albedo_color = profile.get("glass_color", DEFAULT_GLASS_COLOR)
	cloned.metallic = profile["glass_metallic"]
	cloned.roughness = profile["glass_roughness"]
	cloned.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloned.refraction_enabled = false
	return cloned
```

### 4.2 `scripts/player/player_car_controller.gd`

- Replace the field at line 13:

```gdscript
var _taillight_materials: Array[StandardMaterial3D] = []
var _reverse_lamps: Node3D = null
```

- `_cache_visuals` (lines 248-252):

```gdscript
func _cache_visuals(instance: Node3D) -> void:
	_visual_wheels = CarVisuals.resolve_wheel_nodes(instance, _car_id)
	_taillight_materials = CarVisuals.find_named_materials(instance, "taillight")
	_reverse_lamps = CarVisuals.build_reverse_lamps(instance)
	_spin_angle = 0.0
	_visual_ready = true
```

- `_process` (line 61 area):

```gdscript
	CarVisuals.apply_brake_glow_all(_taillight_materials, brake)
	CarVisuals.apply_reverse_glow(_reverse_lamps, int(info["gear"]) < 0)
```

`_reverse_lamps` is built under the GLB `instance`, which `_apply_visual` clears
and re-creates on every car swap (line 229-233), so no stale holder survives.

### 4.3 `scripts/vehicle/rival_car_visual.gd`

Same seam as the player so rivals get reverse + brake glow:

- New fields: `var _taillight_materials: Array[StandardMaterial3D] = []`,
  `var _reverse_lamps: Node3D = null`.
- `build()` (after `CarVisuals.apply_paint`, lines 99-101):

```gdscript
	_taillight_materials = CarVisuals.find_named_materials(instance, "taillight")
	_reverse_lamps = CarVisuals.build_reverse_lamps(instance)
```

- `_clear()`: reset both to empty/null.
- `_process` (lines 108-118) — restructure so lights run even when no wheels
  resolved:

```gdscript
func _process(delta: float) -> void:
	var car := _find_car()
	if car == null or _visual_root == null:
		return
	var info := car.get_drive_info()
	var speed_kmh := float(info.get("speed_kmh", 0.0))
	var steer := float(info.get("steer", 0.0))
	if not _wheels.is_empty():
		_spin_angle = _spin_angle + CarVisuals.wheel_spin_rate(speed_kmh, CarVisuals.WHEEL_RADIUS) * delta
		CarVisuals.apply_wheel_visuals(_wheels, steer, _spin_angle)
	CarVisuals.apply_brake_glow_all(_taillight_materials, float(info.get("brake", 0.0)))
	CarVisuals.apply_reverse_glow(_reverse_lamps, int(info.get("gear", 0)) < 0)
```

Add read-only test accessors mirroring `visual_root()` / `paint_profile()`:
`taillight_materials() -> Array[StandardMaterial3D]` and
`reverse_lamps() -> Node3D`.

### 4.4 No change required

`tools/car_builder.py`, `scripts/car/headlights.gd`, `scripts/vehicle/cockpit_rig.gd`,
the CarVisuals night-lamp layer, and all binary `assets/cars/*.glb`.

---

## 5. Tests (GDUnit4, headless-safe)

Conventions to honour: `assert_that(...).is_equal` / `.is_equal_approx(..., tol)`;
**vector** `is_equal_approx` needs a **same-type** approx arg (e.g.
`Vector3(0.001, 0.001, 0.001)`) never a float; GDScript **warnings are errors**
(no unused vars, no `:=` from a `Variant`-returning call); manually-built nodes
freed in `after_test`; no `await` needed for pure material inspection.

### 5.1 New suite — `tests/suites/test_car_reverse_lights.gd`

Covers FIX 2's CarVisuals API and the player/rival seams headlessly.

- `test_find_named_materials_collects_every_taillight_clone` — build a root with
  two `MeshInstance3D` nodes named `Taillight_L`/`Taillight_R`, each with a
  `StandardMaterial3D` named `"Taillight"`; `apply_paint(root, DEFAULT_PAINT)`;
  assert `find_named_materials(root, "taillight").size() == 2` and that the two
  returned instances are **distinct** (`get_instance_id()`), and that
  `find_named_material(...)` still returns non-null (first).
  Also apply `apply_brake_glow_all(all, 1.0)` and assert **both** have
  `emission_energy_multiplier == BRAKE_GLOW_MAX` (the direct R35 "4 lamps" fix).
- `test_reverse_lamps_are_built_hidden_from_taillight_geometry` — hand-built
  visual root with two `Taillight` nodes at `(±0.32, 0.788, -2.238)`; assert
  `build_reverse_lamps(root)` returns a holder, `reverse_lamp_count == 2`, every
  child is hidden, and each child material `resource_name == "ReverseLight"` with
  `emission_enabled` and a **white** emission (`emission.r >= emission.b`).
- `test_apply_reverse_glow_toggles_the_holder` — `apply_reverse_glow(holder, true)`
  ⇒ `holder.visible`; `... false` ⇒ hidden; `apply_reverse_glow(null, true)` is a
  safe no-op; `reverse_lamp_count(null) == 0`.
- `test_reverse_lamps_are_empty_and_safe_without_taillights` — a root with only a
  `Paint` node ⇒ holder built, `reverse_lamp_count == 0`, `apply_reverse_glow`
  no-op.
- `test_player_controller_caches_all_taillights_and_drives_reverse` — instantiate
  the controller script, hand-build a GLB-like instance (two taillight nodes),
  call `_cache_visuals(instance)`, assert the cached array size is 2 and
  `build_reverse_lamps` produced 2 lamps; then set the parent's fake drive info
  is out of scope here — drive the seam by calling the CarVisuals functions and
  asserting state (mirrors `test_night_headlights.gd`'s seam style).

### 5.2 Update — `tests/suites/test_car_visuals.gd`

- `test_apply_paint_on_two_level_tree_applies_clearcoat_paint_and_glass`
  (lines 61-67): change the glass assertions to the new contract —
  `metallic == 0.0`, `roughness == 0.05`, `refraction_enabled` false,
  `transparency == TRANSPARENCY_ALPHA`, and `albedo_color ==
  CarVisuals.DEFAULT_GLASS_COLOR` (the source had no `glass_color`).
- `test_default_paint_profile_values_are_sane` (line 189): `glass_metallic` now
  `0.0`.
- `test_find_named_material_locates_taillight_on_tree` /
  `..._returns_null_when_absent` (309-320): unchanged (wrapper preserved).
- Optional new: `test_find_named_materials_dedups_shared_material`.

### 5.3 Update — `tests/suites/test_car_paint_materials.gd`

- Header comment (lines 7-9): replace "glossy mirrored-glass … transmission-free"
  with "tinted transparent glass".
- `test_window_and_windshield_names_get_the_glossy_glass_response` (94-113):
  rename to `..._get_the_tinted_transparent_glass_response`; assert
  `metallic == 0.0`, `roughness == 0.05`, `refraction_enabled` false,
  `transparency == TRANSPARENCY_ALPHA`, `albedo_color.a < 1.0`.
- `test_taillight_material_still_resolves_and_emits_after_paint` (115-129):
  unchanged (still valid), optionally extend to assert a **two-node** tree ramps
  both via `apply_brake_glow_all`.

### 5.4 Update — `tests/suites/test_cockpit_visibility.gd`

- Header comment (lines 9-10): "ships it OPAQUE" → "ships it tinted transparent".
- `test_ai_car_glass_is_transparent_only_while_cockpit_active` (160-209):
  the baseline is no longer `TRANSPARENCY_DISABLED`. Change lines 192, 197, 208 to
  assert `TRANSPARENCY_ALPHA` with baseline alpha ≈ `DEFAULT_GLASS_COLOR.a`; while
  active still `TRANSPARENCY_ALPHA` and alpha ≈ `COCKPIT_GLASS_ALPHA`; after
  restore alpha ≈ baseline. (Transparency value no longer *changes*, only alpha —
  the test must reflect that.)

### 5.5 Update — `tests/suites/test_gtr_r35.gd`

Add R35-specific gates (loads the real GLB, no scene tree — the existing
`_instantiate` pattern):

- `test_r35_has_two_taillight_materials_and_all_brake_glow` — instantiate the
  GLB, `apply_paint(instance, paint_profile_for(CAR_ID))`, assert
  `find_named_materials(instance, "taillight").size() == 2`; `apply_brake_glow_all`
  at `1.0`; assert both `emission_energy_multiplier == BRAKE_GLOW_MAX`.
- `test_r35_windshield_is_tinted_transparent_glass` — find the `Glass` material
  override via `find_named_material(instance, "glass")`; assert
  `transparency == TRANSPARENCY_ALPHA`, `albedo_color.a < 1.0`,
  `metallic == 0.0`, `refraction_enabled` false.
- `test_r35_builds_two_hidden_reverse_lamps` — `build_reverse_lamps(instance)`
  ⇒ `reverse_lamp_count == 2`, holder hidden, lamps hidden.

### 5.6 Sanity — no change needed but re-run

`tests/suites/test_night_headlights.gd` (night-lamp layer untouched),
`tests/suites/test_cockpit_hud.gd` (HUD-only assertions; its stale "opaque glass"
comment at 311-315 may be updated for accuracy but the test is unaffected),
`tests/suites/test_cc0_cars.gd`.

### 5.7 Gate to run (implementation stage; **not run in this planning pass**)

Touched suites only, one `-a` per suite (never comma-joined — that is a documented
false-green in `docs/GDUNIT_GATE.md`):
`test_car_visuals`, `test_car_paint_materials`, `test_cockpit_visibility`,
`test_gtr_r35`, `test_gtr_r35_interior`, `test_night_headlights`,
`test_cockpit_hud`, `test_cc0_cars`, and the new `test_car_reverse_lights`.
Run `--headless --import .` first (filter for `SCRIPT ERROR`/`Parse Error`), then
one GDUnit `-s` run; prefer `py tools\gdunit_parallel.py -j 4` if running the
whole suite.

---

## 6. Risks and gotchas

1. **Glass is now transparent everywhere (all cars), not just the R35.** This is
   intended, but it is a *global* visual change. From the chase cam a
   transparent windshield exposes the body's interior backfaces (a dark cavity)
   on cars with **no** interior. Mitigation if it reads badly: raise
   `DEFAULT_GLASS_COLOR.a` (e.g. 0.45 → 0.6) so the cavity reads as tinted glass;
   do **not** re-enable metallic or refraction.
2. **Double-sided glass** (`doubleSided=True` in the GLB) composites two alpha
   layers → ~2× tint. Optional tuning: set `cull_mode = CULL_BACK` on the glass
   clone; decide from a screenshot, not by guess. Keep the change isolated to
   `_glass_clone` if adopted.
3. **`TRANSPARENCY_ALPHA` requires `albedo_color.a < 1`.** If a future profile
   supplies `glass_color` with `a == 1`, the pane silently becomes opaque. Guard
   by asserting `a < 1` in the new tests (done) and documenting the constant.
4. **Rivals changed behaviour:** rivals now show brake glow + reverse. This is
   new (previously none). Low risk, but it touches every rival spawn and the
   `_process` early-return — make sure the glow still runs when `_wheels` is empty
   (the restructure in §4.3 handles it).
5. **CC0 Comet has no taillight node** → empty reverse holder; make sure
   `build_reverse_lamps` never dereferences a null mount list.
6. **Reverse lamp placement is derived from taillight node origins.** If a future
   GLB nests its taillight meshes under a rotated parent, the derived offset is
   still parent-relative; for the shipped cars they are direct children of the
   visual root, so this is exact. The optional `REVERSE_LAMP_LOCALS` table is the
   escape hatch.
7. **`geo` note:** the reverse lamp is emissive *geometry* only (no `Light3D`) —
   it will not cast a white pool unless a light is added later. That is deliberate
   (light budget).
8. **Warnings-as-errors:** `find_named_materials` and the collectors must be
   explicitly typed (`Array[StandardMaterial3D]`), and `_collect_named_materials`
   must not shadow/omit types.
9. **Two existing tests actively encode the old opaque-glass contract** and MUST
   be updated in the same change or the suite goes red:
   `test_car_paint_materials.gd:108`, `test_car_visuals.gd:63-66`,
   `test_cockpit_visibility.gd:192/197/208`. This is the single biggest
   "forgot to update the test" trap.
10. **Single Godot process at a time:** the gate run must not overlap another
    Godot/gate run.

---

## 7. Explicit DO-NOT-TOUCH list

- **Do not edit any `assets/cars/*.glb`** — they are build artifacts regenerated
  by `tools/car_builder.py`.
- **Do not edit `tools/car_builder.py`** — out of scope (a future pass could add a
  real `Reverse` material + mesh, but that is a separate builder task).
- **Do not edit `scripts/car/headlights.gd`** — the front SpotLight pair and the
  traffic twin are independent of these three fixes.
- **Do not touch the CarVisuals night-lamp layer**
  (`build_night_lamps`, `apply_lamp_intensity`, `HEADLIGHT_*`/`TAIL_LIGHT_*`,
  `car_visuals.gd:317-529`).
- **Do not change `CarVisuals.CAR_ORIENT` / `CAR_ORIENT_BASIS` / `body_mount`.**
- **Do not change `COCKPIT_GLASS_ALPHA` (0.18) or the `_set_glass_cockpit`
  snapshot/restore semantics** — the cockpit transparent-glass contract must stay
  byte-for-byte in behaviour.
- **Do not edit `scripts/vehicle/cockpit_rig.gd`** or the R35 interior scene /
  `.tres`.
- **Do not edit `scripts/track/*` or other transparent-material users**
  (`track_builder.gd:257`, `oval_dressing.gd:413`, `replay_playback.gd:108`).
- **Keep `refraction_enabled = false`** on the glass clone (no screen-texture
  dependency, quality-ladder safe at Low).
- **Do not re-introduce a single-material taillight assumption** anywhere; the
  whole point of FIX 1 is that matching materials are plural.

---

## 8. Definition of done

1. On the R35, **all four** rear lamps brighten on brake (both `Taillight_*`
   clones ramp to `BRAKE_GLOW_MAX`).
2. A **white** reverse lamp lights when `gear == -1`, on the **player and
   rivals**, driven from the per-frame `get_drive_info()` poll.
3. The R35 windshield (and every car's glass) renders as **tinted transparent**
   glass, not a black panel; the R35 cockpit / interior view is unaffected.
4. Updated + new suites in §5 pass headless; only the touched suites are gated.
5. `graphify update .` run after implementation (per the project knowledge-graph
   rule) — note GDScript is outside the graph's extractor, so this is a formality
   for any tooling/docs touched, not for `scripts/**.gd`.

---

## 9. REVISION (2026-10-16) — task 4 / FIX 2's built white reverse lamp is SUPERSEDED

**Superseded:** the runtime-built white reverse lamp of §3.2 —
`CarVisuals.build_reverse_lamps()` (holder `"ReverseLamps"`, group
`"reverse_lamps"`, `BoxMesh` bars sized `REVERSE_LIGHT_SIZE`, mounts offset by
`REVERSE_LAMP_INBOARD/DOWN/REARWARD`, per-lamp material `resource_name =
"ReverseLight"`), the visibility switch `apply_reverse_glow(lamps: Node3D, ...)`,
and the accessors `reverse_lamps()` / `reverse_lamp_count()` on both the player
controller and `RivalCarVisual`.

**Replaced by:** *"the existing rear lamps glow bright white while reversing."*
`CarVisuals.apply_reverse_glow(materials: Array[StandardMaterial3D], active: bool)`
drives the car's EXISTING taillight materials — the same cached clones the brake
ramp already drives — with **no geometry added at all**:

- `active` → `emission_enabled = true`, `emission = REVERSE_LIGHT_COLOR`
  (bright white), `emission_energy_multiplier = REVERSE_LIGHT_ENERGY`.
- The GLB-authored base emission colour is saved once to meta
  `REVERSE_GLOW_META` (`"ud_reverse_base_emission"`) and restored when `active`
  goes false, so the red brake ramp resumes. This save/restore is **required**,
  not cosmetic: `apply_brake_glow()` only ever sets `emission_energy_multiplier`,
  never `material.emission` — leaving the white in place would keep the tail
  lights white forever.
- Cost-neutral, headless-testable, and empty/null-safe (empty array, or a null
  element, is a no-op).
- Same per-frame seam and same `gear < 0` key, now passed the cached taillight
  array: `player_car_controller.gd` and `rival_car_visual.gd`.

**Reason (playtest):** *"when i go in reverse it adds a white light, that wasnt
my intent, my intent was: make the rear lights glow bright white when
reversing."* The added bar read as an EXTRA lamp rather than the taillights
themselves brightening.

**Historical text to read as superseded:** §3.2, §4 (§4.1(e), §4.2 and §4.3 —
the `build_reverse_lamps()` snippet, the `_reverse_lamps` field, and the old
`apply_reverse_glow(lamps: Node3D, ...)` switch), the §5.1 / §5.5 reverse test
descriptions, §6 items 5-7, and §8 item 2 all describe the removed design. The
tests named there were rewritten:
`test_r35_builds_two_hidden_reverse_lamps`,
`test_reverse_lamps_are_built_hidden_from_taillight_geometry`,
`test_reverse_lamp_mounts_sit_inboard_of_the_taillights`,
`test_apply_reverse_glow_toggles_the_holder`,
`test_reverse_lamps_are_empty_and_safe_without_taillights`,
`test_null_reverse_holder_is_a_safe_no_op` and
`test_player_controller_caches_all_taillights_and_drives_reverse`.
