# UltraDrive — Custom Dynamic Per-Car Interiors (Cockpit) Plan

> Research + phased implementation plan for giving **every car its own cockpit**:
> per-car geometry (dash / A-pillars / door cards / steering wheel), per-car
> placement (dash size, wheel diameter + tilt, seat anchor), per-car material
> "vibe" (trim palette, emission accents), optional **dynamic in-cockpit
> gauges**, and a seat-anchor/camera interplay that builds on — never fights —
> the already-shipped per-car seat-height and camera-override hooks.
>
> **Written:** 2026-09-23 · **Inputs:** `AGENTS.md` (house conventions, "No tech
> ceiling", plan-doc format), `docs/ROADMAP.md` (garage depth / cockpit north
> star), `docs/plans/open_world_seeding_plan.md` (structure + STATUS conventions
> mirrored), `docs/plans/first_person_view_plan.md` (F2b verdict), `docs/plans/
> first_person_camera_plan.md`, `docs/plans/cc0_car_assets_plan.md` (CC0 lane) ·
> **Grounded in (read-only survey):** `scripts/vehicle/cockpit_rig.gd`,
> `scenes/vehicle/cockpit_rig.tscn`, `scripts/vehicle/car_config.gd`,
> `scripts/vehicle/car_visuals.gd`, `scripts/player/player_car_controller.gd`,
> `scenes/vehicle/player_car.tscn`, `scripts/camera/cockpit_camera.gd`,
> `scripts/camera/hood_camera.gd`, `scripts/camera/chase_camera.gd`,
> `scripts/race/cockpit_dash.gd`, `scripts/race/race_ui.gd`,
> `scripts/race/tachometer.gd`, `tests/suites/test_cockpit_interior.gd`,
> `tests/suites/test_cockpit_hud.gd.
>
> **No code was changed to write this document.** It is the plan, not the
> execution (see STATUS).

---

## §0 EXECUTION CONVENTIONS (read before delegating any phase)

> Standing house contract, mirrored from `open_world_seeding_plan.md §3.0`.

- **Delegation.** Each phase goes to one sub-agent (one owner per file set)
  with the phase text verbatim + guardrails. The orchestrator owns the full
  GDUnit gate (AGENTS.md headless recipe: **import probe FIRST**, then the
  `-s` run with `--ignoreHeadlessMode` AFTER the tool-script path). Sub-agents
  never commit and never run the engine while the gate sub-agent owns it —
  **one Godot process at a time**.
- **API contracts are fixed BEFORE parallel agents start.** The InteriorResource
  field names, the node-anchor names (`SteeringWheel` / `Dash` / `SeatRoot` /
  `GaugeRPM` / `GaugeSpeed`) and the fallback order are the contract (§4). Diffs
  split by file (resource type → rig loader → per-car `.tres` data) merge
  without conflict.
- **No code comments** unless asked; tabs in `.gd`; warnings-as-errors (type
  every `var`); vector `is_equal_approx` needs a SAME-TYPE approx arg
  (`Vector3(0.001, 0.001, 0.001)`), floats get a float epsilon.
- Any headless diag runs under a watchdog (a script error during a headless run
  can hang Godot forever — AGENTS.md).

---

## §1 VISION & SCOPE

"Custom dynamic interior per car" means the cockpit view stops being one generic
box and becomes a **per-car instrumented cabin**:

- **Per-car geometry.** Each car in the garage wears its own cabin: dash
  profile, A-pillar rake, windshield header, door cards, and a steering wheel
  sized/tilted to the car's personality (low thin wheel on the sports coupé,
  big bench wheel on the muscle car, high boxy dash on the rally hatch, rounded
  street dash on the CC0/Kenney line).
- **Per-car placement.** Dash width/height/depth, wheel diameter/axle/tilt, and
  an interior `SeatRoot` are per-car data, so the cabin surrounds the *driver
  eye* the same way for every body — a tall-dash hatchback eye sits correctly
  even though its `cockpit_seat_height` override moves the whole view.
- **Per-car material vibe.** Interior trim albedo (dark navy vs. charcoal vs.
  tan) + a mild emission accent budget kept inside the F2a discipline (mild
  self-emission, no cabin OmniLight dynamic pass — `cockpit_rig.gd:8-11`).
- **Dynamic gauges.** An optional set of in-cockpit instrument pods on each
  car's dash (needle + face), driven from the **same** `get_drive_info()` feed
  `race_ui.gd` already uses for the screen cluster (`race_ui.gd:84-97`). This
  is the "dash-as-HUD", moved into the 3D cabin.
- **Seat-anchor + camera interplay (hooks, not conflicts).** The recent per-car
  override work — `cockpit_seat_height` / `cockpit_seat_forward` and
  `hood_cam_height` / `hood_cam_forward` in `car_config.gd:94-97`, consumed by
  `cockpit_rig.gd:_sync_to_seat_anchor()` (`cockpit_rig.gd:95-106`) and
  `cockpit_camera.gd:get_seat_anchor()` (`cockpit_camera.gd:148-160`) — becomes
  the **single source of truth** for where the camera eye and every interior sit.
  The interior is authored in EYE space (rig origin = drive eye), so a seat
  raise moves body, cabin and camera together with zero re-authoring.

**Out of scope this plan:** mirrors (F4 rear-view mirror exists as
`scenes/ui/rear_view_mirror.tscn`), VR, cabin collision/interactive dash, and
full photo-real interiors (those are the art-lane upgrade path in §3/§5-P5).

---

## §2 RESEARCH FINDINGS

### 2.1 What exists today (the F2a baseline)

- **The single shared interior** is `scenes/vehicle/cockpit_rig.tscn` —
  five primitives under a rigid root whose transform is the drive eye
  `(0, 0.55, -0.55)` in car space (`cockpit_rig.tscn:33`): `Dashboard`
  (1.55×0.22×0.6 box at z −0.75, `:36-39`), `PillarLeft`/`PillarRight`
  (angled boxes, `:41-49`), `HeaderBar` (`:51-54`), `SteeringWheel`
  (`TorusMesh` inner 0.11 / outer 0.16, transform `(0, −0.20, −0.4)` with a
  strong Y-tilt, `:56-59`).
- **It is a sibling of `CarBody`, not a child** (`player_car.tscn:28`) so
  `_apply_visual()` (which clears CarBody's children on every car swap,
  `player_car_controller.gd:119-123`) can never wipe it.
- **It is already "smart" in three ways this plan builds on:** (1) the
  steering-wheel animation reads `get_drive_info()["steer"]` and right-multiplies a
  Y-rotation onto the captured base basis so the physical tilt survives
  (`cockpit_rig.gd:59-88`, lock `STEER_VISUAL_MAX_RAD_CABIN = 2.2` at `:38`);
  (2) `_sync_to_seat_anchor()` already lifts/moves the whole eye per `CarConfig`
  (`cockpit_rig.gd:95-106`); (3) `sync_visibility()`/`sync_shell_view()` poll the
  cockpit camera's `is_current_view()` and flip both the interior and the
  exterior shell see-through state (`cockpit_rig.gd:111-165`, `car_visuals.gd:
  450-530`) — entirely headless-safe.
- **Tests pin it:** `test_cockpit_interior.gd` asserts the branch placement
  (sibling, `:54-81`), the visibility gate across all four cameras (`:86-133`),
  the steer-spin math (`:245-313`, `_recover_steer_spin` at `:317`), and the
  wheel sits just below the drive eye at the authored transform
  (`:225-238`, `wheel.position.z == -0.4`, `wheel.position.y` in `[-0.18,-0.22]`,
  torus outer radius above `0.0`).
- **The external HUD already has a cockpit twin.** `%Cluster`
  (`scenes/ui/hud.tscn`) is driven by `race_ui.gd`; `cockpit_dash.gd` mirrors
  the same feed onto a screen-space panel and dims `%Cluster` in cockpit mode
  (`cockpit_dash.gd:5-13`). So "in-cockpit gauges" already exist in 2D — this
  plan moves an *optional* 3D version into each cabin and decides how the two
  coexist (§3, §4.4).

### 2.2 Candidate sourcing options

**(a) Hand-authored Godot `Node3D` tree per car** — one `.tscn` per car whose
nodes are MeshInstance3D + primitive meshes (+ optional fused ArrayMesh), in the
exact style of `cockpit_rig.tscn` itself. This is what the F2a rig already is,
and the repo has a strong runtime-primitives precedent: `prop_scatterer.gd`
builds guardrails/tents/poles from fused primitives with zero external assets
(`prop_scatterer.gd:6-7, 330-360`).

- Effort: **S–M** per car (copy rig scene, re-place ~6-10 boxes; no Blender).
  Total across 6 cars is the cheapest route to *visible* diversity.
- Art pipeline: none (editor work only). File size: tiny (a few KB `.tscn`).
- Maintainability: additive (new car = new scene with a few named anchors);
  drift risk is low because the loader contract is small.
- Licensing: none (engine-native, no binary assets).

**(b) Per-car interior GLB packed scenes** — the F2b lane
(`first_person_view_plan.md:144-145`, "heavy, L-sized, likely future"). An
interior authored in Blender (via MCP/Hyper3D rodin or sliced out of CC0 kit
cars), exported GLB → `PackedScene`, consumed like body GLBs.

- Effort: **L** per car (Blender authoring/UV/materials + normalize + test).
- Art pipeline: full (Blender → normalize → GLB → probe). File size: KBs–MBs
  per interior.
- Maintainability: artefacts are binary; per-car slice of a CC0 kit car needs a
  re-export whenever the kit changes; anchor contract must be re-verified per
  model.
- Licensing: must be **CC0** (the `License.txt = CC0` precedent at
  `assets/cars/cc0/kenney_car-kit/`; `cc0_car_assets_plan.md:31-33` rejects
  "Royalty Free" sources). The Kenney kit cars technically carry cabin
  geometry inside their whole-car GLBs, but are one fused whole-car mesh — a
  dash/interior slice requires a Blender split pass; nothing in `assets/`
  currently ships a ready interior GLB. `free_concept_car_037.glb` is high-poly
  and parked.

**(c) Procedural/parametric rig + per-car tweak tables in the `.tres`** — one
parametric cabin builder (a `CockpitRig` that reads a data resource and emits a
Node3D tree at runtime), varianted per car by a small data block in
`resources/cars/*.tres`. This is the `CarVisuals.WHEEL_GROUPS` data-table
philosophy (`car_visuals.gd:134-172`) applied to the cabin, and the existing
per-car exports (`cockpit_seat_height`, `hood_cam_*`, `car_config.gd:94-97`) are
already exactly that pattern for cameras.

- Effort: **S** to build the engine once, then **S** per car (fill in ~12
  numbers + a palette). Biggest leverage on a 6–10 car roster.
- Art pipeline: none (data + primitives). File size: negligible.
- Maintainability: one builder + data; every future car ships an interior by
  filling a table, no mesh authoring; deterministic + headless-testable.
- Licensing: none.

### 2.3 Comparison

| | (a) authored Node3D trees | (b) interior GLBs | (c) parametric + data |
|---|---|---|---|
| Effort/car | S–M | L | S (builder once, data per car) |
| Art pipeline | none (editor) | Blender + normalize | none |
| File size / car | KBs `.tscn` | KBs–MBs `.glb` | ~1 KB `.tres` block |
| Maintainability | new scene per car | re-export on kit change, re-verify anchors | data row per car |
| Licensing | none | CC0 required, verify per source | none |
| Fidelity ceiling | boxy (F2a look) | high (photo-real) | boxy, but parameterized enough for personality |
| Headless-safety | yes (scene instantiate) | yes (PackedScene, probe-able) | yes (pure builder) |

---

## §3 RECOMMENDED APPROACH

**Primary: parametric rig + per-car `InteriorResource` tweak tables (option c).**

Rationale: it directly extends the two seams the codebase already committed to —
(1) the Rig/Camera per-car-anchor data pattern (`car_config.gd:94-97`, consumed
by `cockpit_rig.gd:95-106`) and (2) the data-table-visuals pattern
(`CarVisuals.WHEEL_GROUPS`). With a 6-car roster and "garage depth" as the
ROADMAP's go-to-war strategy (`ROADMAP.md`, "a believable garage — curated cars
you can tune, upgrade, paint"), a data-driven cabin costs ~1 sprint per every
future car and never asks the art lane for a new mesh. The `No tech ceiling`
rule is respected: the **parametric builder is the floor**, and the resource
carries an **optional `interior_scene: PackedScene` override** — option (b) is
wired into the same contract as the upgrade path, so the moment an interior gets
Blender-authored (or sliced from a CC0 kit car), it drops into the `.tres` and
the loader prefers it with zero rig changes.

**Fallback: per-car authored `Node3D` interior scenes (option a)** when the
param space proves too blocky for a specific car, authored in the exact
`cockpit_rig.tscn` style; the loader treats them as packable "overrides" too
(via `interior_scene`, or a per-car `.tscn` in the scene's override slot).

**Gauge decision: keep the external HUD always; add per-car 3D gauges as an
OPTIONAL dynamic part.** GT7's "HUD-friendly cockpit" principle — keep the info
layer (`first_person_camera_plan.md:234-236`, dash-as-HUD already shipped in
`cockpit_dash.gd`) — stays the default so no car ever loses its readout. A car
that ships real 3D instruments (named gauge anchors) triggers a new
`InteriorResource` flag `suppress_hud_dash` that hides `CockpitDash`'s generic
2D panel and keeps `%Cluster` at full opacity (the 3D cabin *is* the HUD then).
No car is ever worse than today.

---

## §4 ARCHITECTURE DESIGN

### 4.1 New resource: `InteriorResource` (`scripts/vehicle/interior_resource.gd`, `class_name InteriorResource extends Resource`)

Per-car cabin definition. Default-constructed instance == today's F2a rig, so a
new car needs no table to keep the current look.

```gdscript
@export var interior_scene: PackedScene      # optional override — option (b) lane
@export var dash_width := 1.55
@export var dash_height := 0.22
@export var dash_depth := 0.6
@export var dash_z := -0.75                   # eye-space (eye at local 0,0,0)
@export var pillar_width := 0.08
@export var pillar_height := 0.62
@export var wheel_inner_radius := 0.11
@export var wheel_outer_radius := 0.16
@export var wheel_pos := Vector3(0, -0.20, -0.4)
@export var wheel_basis := <python-style-basis-default // the tscn torus tilt>
@export var trim_color := Color(0.1, 0.1, 0.13, 1)
@export var emission_energy := 0.15
@export var seat_root := Vector3(0, 0, 0)     # interior-local seat marker (reserved)
@export var suppress_hud_dash := false        # real gauges → hide generic dash panel
@export var gauge_layout := {}                # GaugeRPM / GaugeSpeed anchor defs
```

`CarConfig` gains one export:
`@export var interior: InteriorResource` (null = fall back to the literal
`cockpit_rig.tscn` — every existing `.tres` stays byte-identical).

### 4.2 Node contract — named anchors the loader requires

All interiors (parametric or GLB) are authored **in eye space**: the cabin root's
origin is the drive eye; `_sync_to_seat_anchor()` already applies the seat
override by moving `position` (`cockpit_rig.gd:95-106`), so interior content is
never re-positioned by the rig.

| Anchor | Type | Contract |
|---|---|---|
| `SteeringWheel` | `Node3D`/`MeshInstance3D` | **REQUIRED.** Local **Y = wheel axle**; `_capture_steering_wheel()` stashes `basis` and `set_steer_visual()` right-multiplies `Basis(Vector3.UP, steer*STEER_VISUAL_MAX_RAD_CABIN)` (`cockpit_rig.gd:59-88`). An interior with no such child degrades to the default wheel (never a crash). |
| `Dash` | `Node3D` | Optional dash root (any child meshes). |
| `SeatRoot` | `Node3D` | Optional interior-local seat marker; future seat-slider seam; the rig may read it when config has no override. |
| `GaugeRPM` / `GaugeSpeed` | `Node3D` | Optional dynamic gauge pods (see 4.4). |

The loader keeps today's public surface — `sync_visibility()`,
`apply_drive_info()`, `set_steer_visual()`, `STEER_VISUAL_MAX_RAD_CABIN` — so
`test_cockpit_interior.gd`'s existing asserts keep compiling unchanged wherever
they assert on the default-equivalent.

### 4.3 Loading + fallback chain (in `CockpitRig._ready`)

1. `cfg = get_parent().config as CarConfig`; `res = cfg.interior`.
2. `res == null` → keep the tree exactly as `cockpit_rig.tscn` authored (no
   change, byte-identical behavior for any car without a table).
3. `res.interior_scene != null` → instantiate it as a child named `Interior`
   (stable sibling of `Dashboard`-etc.); resolve anchors under it. Missing
   `SteeringWheel` → spawn the default wheel under a fresh `SteeringWheel`
   node. Any load/instance error → fall through to (4) (never block the car).
4. else → `_build_parametric(res)` emits an `Interior` subtree (dash/pillars/
   header/wheel from primitives + one trim `StandardMaterial3D` with the
   author's albedo + emission energy). Parametric == the resource's default
   values, which ARE today's rig dims (`cockpit_rig.tscn:36-59`).

Rebuild is data-driven (fires on `_ready`); an explicit `rebuild_interior()`
public method is the test/car-reconfig hook. Old `Interior` subtree is
`queue_free()`d before rebuild (orphan hygiene, §6).

### 4.4 Dynamic parts

- **Steering wheel:** reused unchanged — this is the `STEER_VISUAL_MAX_RAD_CABIN`
  seam (`cockpit_rig.gd:38, 75-81`). GLB wheels must be authored axle-along-Y;
  missing/misnamed → default wheel fallback.
- **Gauges:** optional pods (a disc face + a needle MeshInstance rotated about
  the pod's local X axis; pod faces back toward the eye, local +Z → driver).
  `race_ui.gd`'s existing feed (`car.get_drive_info()` — speed_kmh / gear / rpm,
  `race_ui.gd:84-97`) is consumed **read-only** by a small `_sync_gauges()`
  polled in `_process` next to `_sync_steer_visual()` (`cockpit_rig.gd:50-53`).
  Pure rotation math → headless-safe and unit-testable like the wheel spin.
  When any gauge exists and `res.suppress_hud_dash`, `cockpit_dash.gd`'s panel
  hides and `%Cluster` stays full-opacity (a one-line mode-coupling in
  `cockpit_dash.gd:51-56` reads the active car's flag).

### 4.5 Camera interplay (hooks in, no conflicts)

- **Single seat-anchor source.** `CockpitCamera.get_seat_anchor()`
  (`cockpit_camera.gd:148-160`) and `CockpitRig._sync_to_seat_anchor()`
  (`cockpit_rig.gd:95-106`) both read the SAME `CarConfig.cockpit_seat_height/forward`;
  P4 refactors them onto one pure helper (e.g. `CarConfig.seat_anchor_local()`
  or a `CockpitRig.seat_anchor_for(cfg)`) so the camera eye, the rig eye and the
  interior cradle can never disagree.
- `hood_cam_height/forward` (`car_config.gd:94-97`, `hood_camera.gd:102-114`)
  stay untouched — hood view is shell-side, interiors do not participate.
- Interior authored in eye space means the already-authored overrides
  (`rally_hatch.tres:37-39` `cockpit_seat_height = 0.72`; `muscle_car.tres:33-34`
  hood overrides) compose for free: raise the seat → camera + cabin + dash crane
  up together.

### 4.6 Headless safety & test hooks

- Building geometry from resource primitives and rotating needle/wheel nodes is
  render-free (`cockpit_rig.gd` already is — "fully headless-safe: no render
  signals, no MainLoop dependency", `cockpit_rig.gd:27-29`). No `SubViewport`,
  no `Camera3D` creation in the interior.
- New test hooks (pure seam): `rebuild_interior()`, `get_active_interior() ->
  {resource | "fallback_tscn"}`, `get_gauges()`, plus the existing
  `apply_drive_info()`/`sync_visibility()` surfaces.
- Any `interior_scene` referenced by a `.tres` is probe-able headless
  (instantiate + node check) — same discipline as `test_cc0_cars` loading GLBs.

---

## §5 PHASED IMPLEMENTATION PLAN

Phases are small, independently shippable, each with a named suite gate
(`tests/suites/test_custom_interiors*.gd` per house naming). Existing suites
must stay green unchanged in every phase. Effort = T-shirt (S/M/L).

### P0 — `InteriorResource` type + `CarConfig.interior` export (null default)

- **What/Why:** the data home, with zero behaviour change. A null default keeps
  all six `.tres` byte-identical and the runtime on the literal rig.
- **Files:** new `scripts/vehicle/interior_resource.gd`;
  `scripts/vehicle/car_config.gd` (+1 `@export var interior: InteriorResource`).
- **Gate:** new `tests/suites/test_custom_interiors_resources.gd` —
  default resource == today's rig constants (dash 1.55×0.22×0.6, wheel
  outer 0.16, wheel pos (−0.2, −0.4)); `CarConfig` round-trips a settable
  `interior`; existing six car `.tres` parse with null interior.
- **Effort:** S.

### P1 — Rig loader + parametric builder + fallback order

- **What:** `cockpit_rig.gd` gains a data path: `interior != null` →
  `interior_scene` override, else `_build_parametric(res)`; null → keep the
  literal scene tree. The builtin default resource reproduces today's rig
  bit-for-bit (same nodes/transforms), so `test_cockpit_interior` keeps its
  exact geometry asserts (including `test_steering_wheel_sits_just_below_drive_eye`,
  `test_cockpit_interior.gd:225-238`).
- **Files:** `scripts/vehicle/cockpit_rig.gd`; no `.tscn` edits this phase.
- **Gate:** extend `test_cockpit_interior.gd` (or a new
  `test_custom_interiors_loader.gd`): a car with a default `InteriorResource`
  instantiates identical anchors (Dashboard/SteeringWheel names + transforms);
  a car with `interior_scene` set to the rig scene resolves anchors;
  a bogus scene path degrades to parametric with zero error.
- **Effort:** M.

### P2 — Parametric per-car vibe (data tables for all six cars)

- **What:** author an `InteriorResource` sub-resource per car in
  `resources/cars/*.tres`. Story: sports/Striker low-slung dark dash + small
  wheel; muscle wide bench dash + big 0.19 wheel; rally tall boxy dash + high
  cockpit seat; CC0 Comet/Hooligan/Interceptor rounded street cabins + the
  per-body trim palette. Contained in data — no new meshes.
- **Files:** `resources/cars/{starter_car,muscle_car,rally_hatch,cc0_*}.tres`
  (+ a shared `resources/cars/interiors/*.tres` set for reuse).
- **Gate:** `test_custom_interiors_variants.gd` — every car `interior` resolves;
  at least one geometry param differs from the default for ≥3 cars; wheel
  animation spins for every car through the real seam (drive `apply_drive_info`,
  `_recover_steer_spin` mirror); shell see-through `sync_shell_view()` still
  flips per camera for a custom interior.
- **Effort:** S (data) + S (tests).

### P3 — Dynamic gauges (3D instrument pods)

- **What:** `_sync_gauges()` + gauge anchor contract (`GaugeRPM`/`GaugeSpeed`);
  needle rotation from `get_drive_info()` (rpm normalized to the config
  `redline_rpm`/`idle_rpm`, speed to a face max). `suppress_hud_dash` coupling
  in `cockpit_dash.gd` so a gauged car keeps the screen cluster and hides the
  generic 2D panel.
- **Files:** `scripts/vehicle/cockpit_rig.gd`, `scripts/race/cockpit_dash.gd`,
  one demonstrator gauge layout on the muscle-car interior.
- **Gate:** `test_custom_interiors_gauges.gd` — needle angles are a pure
  clamping function of (rpm, idle, redline) and (speed, face_max); gauged car
  hides `DashPanel` and leaves `%Cluster` opacity 1.0; non-gauged cars keep
  `cockpit_dash`'s existing dim + panel behavior (`test_cockpit_hud.gd` green
  unchanged).
- **Effort:** M.

### P4 — Seat-anchor single source + interplay audit

- **What:** extract the eye computation currently duplicated in
  `cockpit_rig.gd:95-106` and `cockpit_camera.gd:148-160` into one helper, and
  assert camera-eye == rig-eye == interior `SeatRoot` for every car (incl. the
  `rally_hatch` seat override).
- **Files:** `car_config.gd` (or a cockpit helper), `cockpit_rig.gd`,
  `cockpit_camera.gd`.
- **Gate:** `test_custom_interiors_seat_anchor.gd` — for each car, the three
  eye derivations agree within 1 cm; raising `cockpit_seat_height` moves
  rig+camera+SeatRoot together by exactly the same delta; existing
  `test_cockpit_camera.gd` anchor asserts stay green.
- **Effort:** S–M.

### P5 — Interior GLB override lane (option b bridge, optional)

- **What:** ship ONE art interior as a `PackedScene` override — e.g. a dash +
  wheel slice authored/split from a CC0 kit car in Blender (MCP lane) or a
  hand-built `Node3D` interior scene (option a fallback) — wired into one car's
  `interior.interior_scene`. Prove the upgrade path end-to-end.
- **Files:** one interior asset (`assets/cars/cc0/interiors/…` if GLB,
  `scenes/vehicle/interiors/…` if authored), its `.tres` wiring.
- **Gate:** `test_custom_interiors_scene_override.gd` — the override scene
  instantiates headless, wheels resolve anchor + spin, visibility gate holds,
  fallback-to-parametric verified when the path is cleared; license note for any
  external source is recorded in the asset folder (CC0, `License.txt` precedent).
- **Effort:** L (first art interior) / S once the rig slice is standard.

---

## §6 RISKS / GOTCHAS

- **Seat-anchor glue vs. interior origins.** The rig root is the eye and
  `_sync_to_seat_anchor()` mutates `position.y/z` every frame
  (`cockpit_rig.gd:95-106`). Any interior authoring MUST be eye-space; a
  car-space interior would double-shift under a seat override. P4's single-source
  helper is the guardrail; every new interior is tested with seat overrides on.
- **Torus-wheel axle assumptions.** The spin math captures the wheel's base
  basis then right-multiplies a **Y** rotation (`cockpit_rig.gd:75-88`), and the
  existing test pins `wheel.position.z == -0.4`, `position.y ∈ [-0.18,-0.22]`,
  torus outer radius above 0.0 (`test_cockpit_interior.gd:225-238`). Parametric
  wheels derive from those constants; **GLB wheels must be authored axle-along-Y
  in eye space** or they fall to the default wheel. If a future interior
  legitimately moves the wheel, relax those two asserts to anchor-relative
  checks in the SAME suite (explicitly, not silently).
- **GDUnit discipline.** Warnings-as-errors (type every `var`; no
  `<Variant-return>` value inference), and vector `is_equal_approx` needs a
  same-type approx arg (`Vector3(0.001,…)`), floats get a float epsilon —
  AGENTS.md. The gauge math tests compare angles with float epsilons.
- **Orphan hygiene.** Each `rebuild_interior()` must `queue_free()` the previous
  `Interior` subtree; suites that rebuild interiors free managed nodes in
  `after_test` (mirror `test_cockpit_interior.gd:31-37`). Interior GLB swaps use
  the `player_car_controller.gd:119-123` clear-and-rebuild pattern — never leak
  the to-be-replaced child. GDUnit's orphan baseline is a gate.
- **GLB transform conventions.** Body GLBs are nose-+Z in GLB space and carry
  `CAR_ORIENT` (180° Y) at instantiation (`car_visuals.gd:11`,
  `player_car_controller.gd:5, 128`; CC0 kit verified same — `cc0_car_assets_plan.md:99`).
  An interior GLB must be authored **in rig/eye space** (origin = eye, forward =
  −Z looking out, +X = driver right) and must NOT be wrapped in `CAR_ORIENT` —
  wrapping it would face the dash backwards. Probe asserts nose-facing in tests.
- **CC0 licensing.** Interior sources must be CC0 with no attribution debt; the
  `License.txt` precedent at `assets/cars/cc0/kenney_car-kit/` is the template
  for any new kit. "Royalty Free" marketplace assets are rejected
  (`cc0_car_assets_plan.md:31-33`). Kenney kit interiors are whole-car fused
  meshes — require a Blender slice pass, document the source + license next to
  each GLB.
- **Visibility/shell interplay.** Interior geometry must only be visible while
  the cockpit camera owns the viewport (`sync_visibility`, `cockpit_rig.gd:111-117`);
  `CarVisuals.set_cockpit_view` separately handles the OUTER shell
  (`cockpit_rig.gd:143-165`). A custom interior must not re-hide shell meshes or
  fight the glass-alpha pass — it replaces the screen-space dash, never the
  see-through mechanics.
- **HUD regression risk.** Existing `test_cockpit_hud.gd` pins the F4
  dash-as-HUD panel + dim. P3's `suppress_hud_dash` must keep default cars
  byte-identical (flag false) so that suite stays untouched.
- **Quality ladder / perf.** Parametric interiors are a handful of primitives
  (cost like today's rig); the Low preset and iGPU path must not add subviewports
  or dynamic lights (the F2a no-OmniLight discipline, `cockpit_rig.gd:8-11`).
  Interior GLBs are bounded by the existing body-GLB probe discipline.

---

## §7 STATUS

**This document is the RESEARCH + PLAN, not the execution.** No game code or
scene file was modified to produce it (verified: read-only survey only). Nothing
is ticked until a phase's suite is green via the AGENTS.md headless recipe.

- [ ] P0 — `InteriorResource` + `CarConfig.interior` export (null default)
- [ ] P1 — rig loader + parametric builder + fallback chain
- [ ] P2 — per-car interior data for the six cars
- [ ] P3 — dynamic 3D gauges + HUD coupling
- [ ] P4 — seat-anchor single source + camera interplay audit
- [ ] P5 — interior scene-override lane (first GLB/authored interior)
- [ ] P6 — full-suite gate + windowed cockpit captures per car (vision-bridge
      `capture_game_window` in cockpit mode for geometry/see-through sign-off)

*Plan ends. When adopted, fold P0–P6 into ROADMAP.md as a "Custom interiors"
item under the believable-garage pillar and note the `InteriorResource` data
contract as the per-car authoring convention.*