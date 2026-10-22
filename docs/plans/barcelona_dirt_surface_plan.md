# Barcelona RX — DIRT surface look fix (plan)

Status: **IMPLEMENTED 2026-10-22** (D1 + D2 + D3 shipped; the circuit is now MIXED asphalt/dirt, see below). Original text below is the pre-fix analysis.

> **Shipped (supersedes parts of this plan).**
> - D1/D2/D3: `TrackBuilder.tier_surface_albedo/roughness` + triplanar noise for a DIRT-tier road with no profile; DIRT edge strips recoloured earth.
> - Barcelona RX is one closed road with `RoadDef.point_surfaces` (asphalt + one dirt section, `BarcelonaRxLayout.DIRT_SECTIONS` = 72-525 m, 40 % of the lap), rendered by `shaders/road_mixed_surface.gdshader` and gripped per segment by `SurfaceRegistry` (GRAVEL 0.85/0.80 on the dirt, asphalt elsewhere) from the SAME table. The old "do not touch SurfaceRegistry" constraint was lifted by the task (grip VALUES are unchanged).
> - The near-black road on EVERY TrackBuilder track was a separate back-face winding bug (road top was a back face under cull-disabled materials). Fixed in `track_builder.gd` (`_append_up_quad`, `_frame_normal`), guarded by `tests/suites/test_track_builder_winding.gd`.
> - There is no joker branch in the layout (it is a single loop); a joker lane needs an alternative route plus a per-car counter and is not modelled.

Owner surface: `scripts/track/track_builder.gd` (shared) + `scripts/track/barcelona_rx.gd` (scene polish)
Related: `docs/plans/track_barcelona_rallycross.md` (build plan), `docs/HANDOFF_BARCELONA_RALLYCROSS.md`

---

## 1. GOAL + ACCEPTANCE

### Goal
`barcelona_rx` is the `TrackRegistry` layout **Barcelona Rallycross** (`Tier.DIRT` +
`Surface.GRAVEL`, `scripts/track/barcelona_rx.gd:160-171`). Today the 12 m-wide road
surface it renders is a **flat, untextured, pale tan strip** (`Color(0.55, 0.48, 0.38)`,
roughness `0.95`) that reads as a worn **asphalt/tarmac** road, not dirt. Make the
`DIRT` tier render as **unmistakable dirt**: a dark, saturated earth albedo with a
matte, mottled surface, and no pale "kerb" edge line that can be mistaken for paving.

The grip is already correct (`Tier.DIRT -> GRAVEL = 0.85 lateral / 0.80 longitudinal`,
`scripts/vehicle/surface_registry.gd:30-46`) and dust already fires off-asphalt
(`scripts/vehicle/vehicle_fx.gd:88`). **Only the LOOK is wrong.**

### Acceptance criteria (all must hold)
1. A GDUnit4 test that **fails on today's tree** (albedo r ≈ 0.55) and **passes after
   the fix**, asserting the road surface material the scene actually renders is the
   DIRT profile (dark earth albedo, matte roughness) and is **not** the pale GRAVEL /
   asphalt surface.
2. Every non-DIRT road is byte-for-byte unchanged in look: the ASPHALT default test
   stays green and the oval / `mountain_pass` / `northern_isle` roads keep their
   current material (see §6 blast radius).
3. `tests/suites/test_road_graph.gd` DIRT material expectations are updated so the
   suite is green after the change.
4. A car driving Barcelona RX sees a dirt-looking surface from the chase camera
   (manual playtest — the gateway cannot screenshot).

---

## 2. CURRENT STATE — ROOT CAUSE (verified against live source)

**Root cause: `Tier` never reaches the road surface material.** The DIRT tier only
affects the two 1 m edge strips; the 12 m carriageway is driven **solely by
`def.surface`**, which for Barcelona is `GRAVEL` — a pale, low-saturation tan.

Chain of evidence:

- `scripts/track/track_builder.gd:35-41` — `TIER_EDGE_COLORS`. The `4: DIRT` entry
  (line 40, `Color(0.55,0.40,0.28)` / `Color(0.60,0.55,0.48)`) is read **only** at
  `:111` and applied **only** to the two edge-strip meshes at `:112-122`
  (`RoadEdgeRight` / `RoadEdgeLeft`, each 1.0 m wide, `:107-110`). It is **not** the
  surface and **not** a vertex colour.
- `scripts/track/track_builder.gd:103` — the surface material is built from `surface`
  alone: `var material := _surface_material(surface)`.
- `scripts/track/track_builder.gd:237-251` — `_surface_material` calls
  `surface_albedo(surface)` / `surface_roughness(surface)`; **`tier` is never passed
  in** even though it is in scope at `:87`.
- `scripts/track/track_builder.gd:44-65` — `surface_albedo(GRAVEL) = Color(0.55,0.48,0.38)`
  (`:48-49`), `surface_roughness(GRAVEL) = 0.95` (`:60-61`). The `_` fallback is the
  dark "asphalt" neutral `Color(0.16,0.17,0.19)` (`:52-53`); ASPHALT's own value is
  the same fallback. So DIRT/GRAVEL renders as **pale tan**, i.e. it looks paved.
- `scripts/world/road_def.gd:242-247` — `default_surface(Tier.DIRT) = Surface.GRAVEL`;
  `barcelona_rx.gd:167` passes `RoadDef.Surface.GRAVEL` explicitly. `make()` at
  `road_def.gd:116-127` is the only construction path.
- `scripts/world/road_network.gd:29-40` — `add_road_def` builds a `TrackBuilder` and
  calls `build_track(def.points, def.closed, def)`; the builder is a **child of the
  `RoadNetwork` node** and its surface mesh is named `RoadSurface` (`:99-105`). This
  is how the scene test will read the real material.
- `scripts/track/track_builder.gd:301-355` — `_build_mesh` emits **VERTEX / INDEX /
  NORMAL only** (`:348-354`). **No UVs, no COLOR.** Consequence: the shared roughness
  noise map set at `:242-250` is sampled at a constant UV and is therefore
  **effectively inert/flat** — the surface is a solid colour, which is exactly why it
  reads as a smooth paved strip rather than textured dirt.
- `scripts/track/barcelona_rx.gd:54,425-426` — the ground tint is a dry olive
  `GRASS_COLOR = Color(0.34,0.33,0.20)`, so the surrounding terrain does **not** help
  the road read as dirt either.

**Why the build plan's assumption is wrong:** `docs/plans/track_barcelona_rallycross.md:102-105`
claims the DIRT/GRAVEL road "already reads as dirt-brown … zero new material code".
That conflates the 1 m **edge colour** with the **surface material**. The surface was
never DIRT-aware.

**Existing test that PINS the wrong look:** `tests/suites/test_road_graph.gd:516-548`
(`test_track_builder_dirt_surface_and_edge_colors`) asserts the surface albedo
`0.55/0.48/0.38` and roughness `0.95` (`:529-532`). This test must be **updated** by
the fix — it is not a regression guard, it is the encoded bug. The neighbouring
ASPHALT-default test (`:491-498`) asserts `0.16/0.17/0.19` / `0.92` and **must stay
unchanged and green**.

`tests/suites/test_barcelona_rx_track.gd:185-190` asserts the def is
`DIRT`/`GRAVEL` but **never asserts the material**, which is the gap this plan closes.

---

## 3. DESIGN DECISIONS

### D1 — Fix the shared `TrackBuilder` tier→material mapping (RECOMMENDED)
Add an explicit **DIRT tier overlay** to `track_builder.gd`, applied *in addition to*
the surface (not instead of it):

```gdscript
const DIRT_ALBEDO := Color(0.34, 0.24, 0.15, 1.0)  # dark saturated earth
const DIRT_ROUGHNESS := 1.0                        # fully matte

static func tier_surface_albedo(tier: int, surface: int) -> Color:
    if tier == RoadDef.Tier.DIRT:
        return DIRT_ALBEDO
    return surface_albedo(surface)

static func tier_surface_roughness(tier: int, surface: int) -> float:
    if tier == RoadDef.Tier.DIRT:
        return DIRT_ROUGHNESS
    return surface_roughness(surface)
```

and wire it in `_surface_material(surface, tier)` (`:237-251`), called as
`_surface_material(surface, tier)` at `:103`.

**Justification.**
- DIRT is a **tier** semantic (`road_def.gd:11-17`), and the tier is the thing the
  player recognises as "dirt". Keying the look off `surface` alone is the bug itself:
  `default_surface(DIRT) = GRAVEL` means a DIRT road is indistinguishable from a
  generic gravel road by construction.
- It fixes the defect **class**, not one track: the same pale-tan read affects the
  open-world `dirt-a` / `dirt-b` cuts (`scripts/world/corridor_planner.gd:177-180`,
  both `RoadDef.make(RoadDef.Tier.DIRT, …)`).
- The DIRT colour lives in **one place** (`DIRT_ALBEDO`), tunable like `GRASS_COLOR`,
  rather than duplicated per scene.

### D2 — DIRT-only triplanar albedo detail (fixes the inert noise map)
The road mesh has no UVs (`track_builder.gd:348-354`), so:
- set `material.uv1_triplanar = true` and `material.uv1_scale = Vector3(0.08,0.08,0.08)`
  on the DIRT material so the existing roughness noise map **actually samples** across
  the world instead of at one UV, and
- attach a `NoiseTexture2D` as `albedo_texture` (seed fixed, deterministic) so the
  dirt is **mottled**, not a solid slab.

This is the smallest change that satisfies "looks like dirt" without touching the
vertex format: **do NOT add UVs to `_build_mesh`** (that would touch the collision
trimesh path at `:150-158` and every existing road — see §7).

### D3 — Recolour the DIRT edge strips (optional polish; keep 2 edge meshes)
`TIER_EDGE_COLORS[DIRT]` (`:40`) is `[mid-brown, pale grey-tan]`. The pale
`Color(0.60,0.55,0.48)` outer strip is 1 m wide and reads as a **kerb line**, which
reinforces the "paved" impression. Recolour **both** DIRT entries to earth tones
(e.g. `Color(0.40,0.29,0.19)` / `Color(0.30,0.22,0.15)`). This reduces the road to
`RoadSurface + 2 edge strips + CollisionBody` = **4 children** (unchanged), so
`test_road_graph.gd:522` (`get_child_count() == 4`) stays valid. Optional because the
surface is the dominant read; include it only if the playtest still shows a kerb.

### D4 — Dry the ground / scene tint (optional polish)
`barcelona_rx.gd:54` `GRASS_COLOR` and the `_build_ground` colour bake (`:425-426`)
are local to this scene; a drier, browner tint (closer to earth than the current
olive) helps the road blend into the infield. Zero blast radius (const used only in
this file). Optional; defer until the core fix is seen in playtest.

### D5 — REJECTED: per-track material via a new `RoadDef` export
Giving rallycross its own material through a new `RoadDef` field has **zero**
open-world blast radius, but: (a) it leaves the DIRT **class** bug in place (the two
open-world dirt cuts still look paved), and (b) it adds a load-bearing field to a
shared resource consumed by the road graph, rails and map. D1 is strictly better for
the same risk budget.

---

## 4. IMPLEMENTATION STEPS

1. **`scripts/track/track_builder.gd`**
   - Add `const DIRT_ALBEDO` / `const DIRT_ROUGHNESS` next to `TIER_EDGE_COLORS`
     (`:35-41`).
   - Add `static func tier_surface_albedo(tier, surface)` and
     `tier_surface_roughness(tier, surface)` near `surface_albedo`/`surface_roughness`
     (`:43-65`).
   - Change `_surface_material(surface: int)` (`:237`) to
     `_surface_material(surface: int, tier: int)` and use the new tier functions for
     `albedo_color` / `roughness` (`:239-240`).
   - In `_surface_material`, when `tier == RoadDef.Tier.DIRT`, also set
     `uv1_triplanar` / `uv1_scale` and attach the deterministic mottling
     `NoiseTexture2D` as `albedo_texture` (D2).
   - Update the call site at `:103` to pass `tier` (already in scope from `:87`).
   - (Optional, D3) recolour the `DIRT` entry of `TIER_EDGE_COLORS` at `:40`.
2. **(Optional, D4)** `scripts/track/barcelona_rx.gd` — retune `GRASS_COLOR` (`:54`)
   and/or the `_build_ground` shade (`:425-426`) toward drier earth. No API change.
3. **`tests/suites/test_road_graph.gd`** — update
   `test_track_builder_dirt_surface_and_edge_colors` (`:516-548`) expected albedo /
   roughness to the DIRT profile (and the edge colours if D3 landed). **Leave
   `:491-498` (ASPHALT default) untouched.**
4. **`tests/suites/test_barcelona_rx_track.gd`** — add the scene-level gate in §5.
5. **`docs/plans/track_barcelona_rallycross.md:102-105`** — correct the stale
   "zero new material code" claim so the next reader does not re-trip on it.
6. Run the gate (§5 commands) and confirm green.

**Do NOT** change `RoadDef.default_surface`, the grip table, or `Surface.GRAVEL`'s
values — see §7.

---

## 5. TEST PLAN

### 5a. New failing-then-passing gate (the requested test)
Suite: **`tests/suites/test_barcelona_rx_track.gd`** (already owns the Barcelona
scene; `SCENE_BARCELONA` at `:30`). Add a scene-level test plus one helper. It asserts
**literal** values (not a new constant) so on today's tree it fails by **assertion**
(today `r ≈ 0.55`), never by a parse error from an unknown symbol:

```gdscript
## DIRT look gate (docs/plans/barcelona_dirt_surface_plan.md §5): the road surface
## the scene actually renders must be the dark, matte DIRT profile, NOT the pale
## tan GRAVEL/asphalt surface that ships today. Fails today (r 0.55) and passes
## once TrackBuilder overlays the DIRT tier.
func test_scene_road_surface_reads_as_dirt_not_pale_gravel() -> void:
	var runner := scene_runner(SCENE_BARCELONA)
	await runner.simulate_frames(3)
	var scene := runner.scene()
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var network := scene.get_node_or_null("RoadNetwork") as RoadNetwork
	assert_that(network).is_not_null()
	if network == null:
		return
	var mat := _road_surface_material(network)
	assert_that(mat).is_not_null()
	if mat == null:
		return
	# Literal DIRT profile — fails via ASSERTION today, not a parse error.
	assert_float(mat.albedo_color.r).is_equal_approx(0.34, 0.01)
	assert_float(mat.albedo_color.g).is_equal_approx(0.24, 0.01)
	assert_float(mat.albedo_color.b).is_equal_approx(0.15, 0.01)
	assert_float(mat.roughness).is_equal_approx(1.0, 0.01)
	# Semantic guard: unmistakably darker than the pale GRAVEL surface it replaced.
	assert_float(mat.albedo_color.r).is_less(0.45)

## The scene's rendered road surface: the sole TrackBuilder child of RoadNetwork
## has a child 0 named "RoadSurface" (track_builder.gd:99-105).
func _road_surface_material(network: RoadNetwork) -> StandardMaterial3D:
	for child in network.get_children():
		var builder := child as TrackBuilder
		if builder == null:
			continue
		var surface := builder.get_node_or_null("RoadSurface") as MeshInstance3D
		if surface != null:
			return surface.material_override as StandardMaterial3D
	return null
```

### 5b. Update the existing pinned test
`tests/suites/test_road_graph.gd:516-548` — change `:529-532` to the DIRT profile and
`:537-542` if D3 recoloured the edges. This is a **required** change: left as-is it
would go red the moment the surface is fixed.

### 5c. Guard that must stay green (regression)
- `tests/suites/test_road_graph.gd:491-498` — the ASPHALT default material
  (`0.16/0.17/0.19` / `0.92`) must be untouched. Proves non-DIRT roads are unaffected.
- `tests/suites/test_barcelona_rx_track.gd:328-344` — dirt grip classification
  (GRAVEL 0.85/0.80) must stay green; this plan does not touch grip.
- `tests/suites/test_barcelona_rx_track.gd:118-200` — scene skeleton unchanged.
- `tests/test_track_system.gd` — registry/checkpoint suite. Checked: it makes **no**
  material assertions, so it is context only and needs no change.

### 5d. Gate commands (cmd.exe on the PC; see `docs/GDUNIT_GATE.md`)
Single suites first, then the parallel gate (one Godot process at a time — never run
these beside another Godot process):

```
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless --import . 2>&1"
cmd /v:on /c "call godot_path.bat & !GODOT_EXE_CONSOLE! --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/suites/test_barcelona_rx_track.gd -a res://tests/suites/test_road_graph.gd -rd reports/dirt_look > _gdunit_dirt.txt 2>&1"
py tools\gdunit_parallel.py -j 4
```

Confirm `_gdunit_dirt.txt` is not 0 bytes and read `Overall Summary:`. The full run
goes to a background sub-agent, never the foreground session.

---

## 6. RISKS

- **Blast radius is provably DIRT-tier only.** The overlay triggers only when
  `tier == RoadDef.Tier.DIRT`. Verified non-DIRT users:
  `scripts/track/northern_isle.gd:150-158` (ARTERIAL/ASPHALT),
  `scripts/track/mountain_pass.gd:54-57` and `scripts/test_circuit.gd:42` (no def →
  default ARTERIAL/ASPHALT), and every open-world corridor except `dirt-a`/`dirt-b`
  (`corridor_planner.gd:177-180`). Only Barcelona RX and those two cuts use
  `Tier.DIRT` — all three *should* look like dirt.
- **`surface_albedo` / `surface_roughness` have no external callers** (verified by
  grep across `*.gd`: only `track_builder.gd` itself). Adding tier-aware wrappers
  cannot break an outside consumer.
- **Only `test_road_graph.gd:516-548` pins the old DIRT look.** If it is not updated
  in the same commit it goes red — expected and intended (it encoded the bug).
- **`uv1_triplanar` + a `NoiseTexture2D` albedo** costs one extra texture bind for
  DIRT roads only, and adds no geometry. It cannot affect the ASPHALT test, which
  reads `albedo_color`/`roughness` only.
- **`DIRT_ALBEDO` may need one playtest iteration** to hit the intended brown at the
  project's tonemapper. It is a single constant — tune it in one place.
- **Grip is deliberately out of scope.** `TIER_SURFACE[4] = GRAVEL` (`surface_registry.gd:40-46`)
  and the `DIRT` grip row `0.80/0.75` (`:30-37`) are **not** changed — the handoff
  (`docs/HANDOFF_BARCELONA_RALLYCROSS.md:88-92`) makes the grip decision final. A road
  still cannot *classify* as `DIRT`; only its **material** becomes dirt.

---

## 7. DO NOT TOUCH

- **`scripts/vehicle/surface_registry.gd` grip table / `TIER_SURFACE`** — the grip and
  dust decisions are final (handoff §3, lines 86-95). This is a look-only fix.
- **`track_builder.gd._build_mesh` vertex format** — do **not** add UVs/COLOR; that
  changes the collision trimesh (`:150-158`) and every existing road. Use triplanar.
- **`tests/suites/test_road_graph.gd:491-498`** (ASPHALT default) — must stay green.
- **`Surface` enum values / `surface_albedo` ASPHALT/CONCRETE/SNOW values** — other
  tiers depend on them.
- **Concurrent-agent-owned files (do not edit, do not reformat):**
  - race-menu / track-select UI;
  - race HUD (`scripts/race/race_ui.gd`, `scenes/ui/hud.tscn`, `tachometer.gd`);
  - speed-trap HUD;
  - cockpit view (`scripts/camera/cockpit_camera.gd`, `hood_camera.gd`);
  - `opencode` plugins (`.opencode/plugins/**`).
- **Car assets/materials, camera scripts, garage UI, vehicle audio,
  `scripts/world/spline.gd`** — per the handoff's non-touch list.
- **Never `git add -A`** (`.uid` files are gitignored); the repo has large uncommitted
  prior-session work. Commit only the files named in §4.
