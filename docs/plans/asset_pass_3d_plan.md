# UltraDrive — 3D Asset Pass (CC0-first, low-poly 3D pipeline)

> Fix the "looks awful" finding with a **CC0-first, low-poly 3D model pipeline**:
> replace fused-primitive scenery with handcrafted, verifiably public-domain
> models pulled through the wired Blender-MCP tools into the repo's existing
> MultiMesh / PackedScene systems.
>
> **Written:** 2026-09-20 · **Inputs:** asset-round research, `AGENTS.md`
> (Blender MCP + headless recipe), `docs/plans/cc0_car_assets_plan.md` (Kenney
> car-line, shipped) · **Grounded in:** live survey of `scripts/world/foliage.gd`,
> `scripts/world/prop_scatterer.gd`, `scripts/world/region_dresser.gd`,
> `scripts/vehicle/car_visuals.gd`, `tests/suites/test_cc0_cars.gd`,
> `tests/test_dressing_road_clearance.gd`.

## Goal

UltraDrive's geometry stops reading as placeholder. Every non-player object the
camera lingers on — trees, bushes, rocks, buildings/pit structures, track barriers
— becomes a handcrafted, permissively-licensed low-poly model, herd-instanced
through the existing MultiMesh paths. Terrain stays on `terrain_baker.gd`'s fBm
pipeline; only the *dressing* is reskinned.

## Scope

1. **CARS:** keep the shipped Kenney CC0 swap; optionally add ONE bespoke hero
   car via Hyper3D Rodin (nose +Z in GLB space, `CAR_ORIENT`, 4 split wheels).
2. **BUILDINGS:** Poly Pizza CC0 into `PropScatterer` presets or a slim builder.
3. **MOUNTAIN ROCKS:** replace ONLY `PropScatterer._build_rock_mesh` fused
   primitives with Poly Haven boulders (MultiMesh herd).
4. **TREES/BUSHES:** 2–4 low-poly trees as new ArrayMesh sources in `foliage.gd`
   while keeping `shaders/foliage_wind.gdshader`.
5. **TRACK PROPS:** Kenney Racing Kit CC0 (barriers, cones, grandstands,
   guardrails) into the `PropScatterer` presets.

## CC0-first licensing policy (the gate)

Every shipped model must be **verifiably public-domain (CC0)**: no attribution,
no per-use fees, safe for a shipping title. Non-CC0 "Royalty Free" marketplace
assets are rejected regardless of look (precedent: the car plan's rejected list).
Rodin is the single exception — the hero car is bespoke/owned and barred from
every other class.

## Resource list

| Asset class | Source | License note | Blender-MCP tool(s) |
|---|---|---|---|
| Cars (shipped) | Kenney Car Kit | CC0 | n/a — in `assets/cars/cc0/` already |
| Hero car (opt, P5) | Hyper3D Rodin | project-owned generation | `generate_hyper3d_model_via_images` (or `_via_text`) → `poll_rodin_job_status` → `import_generated_asset` |
| Buildings/pit (P3) | Poly Pizza | filter `licence="CC0"` (CC-BY out) | `search_polypizza_models` + `download_polypizza_model` (`normalize_size=true`, `target_size` real-world) |
| Mountain rocks (P4) | Poly Haven | CC0 (all Poly Haven) | `search_polyhaven_assets` (models, rocks) + `download_polyhaven_asset` |
| Trees/bushes (P1) | Poly Haven / Poly Pizza | CC0 | `search_polyhaven_assets` / `search_polypizza_models` + `download_polyhaven_asset` / `download_polypizza_model` |
| Track props (P2) | Kenney Racing Kit (kenney.nl) | CC0 | direct zip (car-kit pattern); import+normalize via `execute_blender_code` |

Verify visually with `get_viewport_screenshot` after import.

## End-to-end flow (every phase follows this)

1. **Search** — CC0-filtered `search_polypizza_models` / `search_polyhaven_assets`;
   2–4 candidates per class.
2. **Download** — `download_polypizza_model` (`normalize_size=true` + real-world
   `target_size`; Poly Pizza scale is arbitrary) or `download_polyhaven_asset`.
3. **Clean/normalize in Blender** (`execute_blender_code`): bake transforms,
   origin **at the base** (Y=0 on the ground), merge parts to one surface (car:
   4 split wheels kept separate), triangulate.
4. **Export GLB** to `assets/<class>/` — `trees/`, `rocks/`, `buildings/`,
   `track_props/`, `cars/` (the CC0-car pattern).
5. **Godot probe** — `--headless --import .` (binary below): expect **zero**
   `SCRIPT ERROR` / `Parse Error` (benign "resources still in use" + Terrain3D
   whitelist allowed). MUST precede any GDUnit `-s` run.
6. **Hook-up** — `load()` the GLB as `PackedScene` / merge into one `ArrayMesh`
   via `SurfaceTool.append_from` (the `_fuse` pattern, `prop_scatterer.gd:343`).
7. **GDUnit gate** — the phase's named suite(s) green, then the full-suite run (P6).

---

## §3 EXECUTION CONVENTIONS

> Standing contract for delegated work (mirrors `open_world_seeding_plan.md`
> §3.0). One phase = one sub-agent owning only its named files; the orchestrator
> runs the full headless suite and verifies; agents never commit, never `git
> add -A`, never run the engine concurrently (Godot locks `res://`).

- **Liveness first:** `blender-mcp_get_addon_status` → expect `up_to_date`,
  protocol 5, Blender 4.5.13 on 9876.
- **Determinism is load-bearing:** placement seeds, MultiMesh counts and
  per-region bit-identical re-entry stay fixed unless a suite asserts the new
  value; every reskin keeps the same `generate()` contract.
- **Iterate the dressing, not the terrain:** no changes to `terrain_baker.gd`
  bake math or region-anchor rules in this plan.

## Phases (dependency-ordered)

### P1 — Trees (foliage.gd MultiMesh swap)

- **Goal:** Replace the cone-cylinder primitive tree (`foliage.gd:180`) with
  2–4 low-poly Poly Haven / Poly Pizza trees as new ArrayMesh sources; keep
  `shaders/foliage_wind.gdshader` (height-UV bark/leaf split preserved via
  `_bake_tree_height_uvs:207`; `TREE_HEIGHT` per model).
- **Files touched:** `scripts/world/foliage.gd` (`_build_tree_mesh`, `TREE_HEIGHT`,
  model-source table), `assets/trees/*.glb`, `shaders/foliage_wind.gdshader`
  (read-only), foliage coverage in `tests/test_dressing_road_clearance.gd`.
- **MCP/asset steps:** search ×2–4 → download (`normalize_size` ~ tree meters)
  → bake transforms, origin at base, merge one surface, triangulate → export.
- **Test gate:** `test_foliage_*` coverage (`tests/test_dressing_road_clearance.gd`
  + `tests/suites/test_streaming_dressing.gd`) stays green AND a new assert that
  the tree MultiMesh sources a real model (non-primitive mesh).

### P2 — Track props (Kenney Racing into PropScatterer)

- **Goal:** Kenney Racing Kit CC0 barriers/cones/grandstands/guardrails become
  `PropScatterer` prop types (new `_mesh_builders` entries, road-adjacent
  dressing in `festival`/`highlands` presets).
- **Files touched:** `scripts/world/prop_scatterer.gd` (`_mesh_builders:47`,
  `_prop_material:256`, `default_preset:136`), `assets/track_props/*.glb`,
  `tests/test_dressing_road_clearance.gd`.
- **MCP/asset steps:** Racing Kit zip (car-kit install pattern) → import via
  `execute_blender_code` → bake transforms, origin at base, merge, triangulate.
- **Test gate:** `test_dressing_road_clearance.gd` + `test_streaming_dressing.gd`
  stay green; new props reject on road and preserve counts/bit-identity.

### P3 — Buildings / pit structures (Poly Pizza CC0)

- **Goal:** Poly Pizza CC0 buildings populate pit/start structures — via new
  `PropScatterer` presets or a slim `BuildingScatterer` (fused single-surface per
  building, MultiMesh'd like rocks/trees).
- **Files touched:** `scripts/world/prop_scatterer.gd` (or new
  `scripts/world/building_scatterer.gd`), `assets/buildings/*.glb`, new
  `tests/suites/test_building_placement.gd`, `open_world_root.tscn` wiring.
- **MCP/asset steps:** `search_polypizza_models` (Buildings, CC0) →
  `download_polypizza_model` (`target_size` ~6–10 m) → clean/merge/triangulate.
- **Test gate:** new `test_building_placement.gd` — deterministic per region
  seed, clear of roads, instance count bounded, re-entry bit-identical.

### P4 — Rock / herd replace (Poly Haven boulders)

- **Goal:** Swap `PropScatterer._build_rock_mesh:312` (octahedron + box fusion)
  for low-vert Poly Haven boulders; keep every placement rule (rejection
  sampling, `_rng` yaw/scale, MultiMesh herd, region determinism).
- **Files touched:** `scripts/world/prop_scatterer.gd` (`_build_rock_mesh`,
  rock `_prop_material` branch), `assets/rocks/*.glb`,
  `tests/suites/test_streaming_dressing.gd` (+ rock road-clearance asserts in
  `tests/test_dressing_road_clearance.gd`).
- **MCP/asset steps:** `search_polyhaven_assets` (rocks) →
  `download_polyhaven_asset` → bake transforms, origin at base, re-normalize to
  the ~0.8–2.4 m scale range, merge one surface, triangulate → export GLB.
- **Test gate:** a `test_region_dresser` variant (extends
  `test_streaming_dressing.gd`'s herd coverage) green — same count budget,
  bit-identical per-region placement, rock model non-primitive.

### P5 — Hero car via Rodin (optional)

- **Goal:** ONE bespoke hero car through Hyper3D Rodin, normalized exactly like
  the CC0 line: nose **+Z**, `CarVisuals.CAR_ORIENT` (180° Y), **4 split** wheel
  meshes per corner (Kenney-style top-level wheel nodes), X-axle discs. New
  `resources/cars/hero_*.tres` + `WHEEL_GROUPS` entry + `Garage` ownership.
- **Files touched:** `assets/cars/` (new GLB), `resources/cars/hero_*.tres`,
  `scripts/vehicle/car_visuals.gd` (`WHEEL_GROUPS`), `scripts/career/garage.gd`,
  `tests/suites/test_cc0_cars.gd`.
- **MCP/asset steps:** `generate_hyper3d_model_via_images` (or `_via_text`) →
  `poll_rodin_job_status` → `import_generated_asset` → split wheels, bake
  transforms, origin at base, triangulate → export GLB.
- **Test gate:** `test_cc0_cars.gd`-style — config resolves, GLB instantiates,
  +Z facing, 4-corner `resolve_wheel_nodes`, garage ownership, `+Z`/`-Z` asserts.

### P6 — Polish / final pass

- **Goal:** Prove the reskin end-to-end: in-editor screenshots
  (`blender-mcp_get_viewport_screenshot` before export is done in P1–P4), LOD /
  draw-call sanity across primes, orphan budget. Full suite green.
- **Files touched:** any stray dressing constants; `docs/ROADMAP.md` phase status.
- **MCP/asset steps:** n/a (verification pass).
- **Test gate:** full GDUnit suite green — **372 test cases, 0 errors, 0 failures,
  0 flaky** (post-S9 match-plan baseline + this plan's new suites), headless per
  AGENTS.md order; orphan count ≤ baseline; `test_perf_gate`-style draw-call
  sanity on the dressed open world.

---

## PROJECT CONVENTIONS

- **Godot binary:** `D:\Godot\Godot_v4.7.2-stable_win64.exe`. Headless order:
  `--headless --import .` FIRST (zero script/parse errors), THEN
  `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
  (`--ignoreHeadlessMode` AFTER the tool-script path, else exit 103). Grep
  `Overall Summary:`.
- **No `*.uid` noise:** `git status --short` must never list `*.uid`; never
  `git add -A`; stage only intended files.
- **Do not commit until told.** The orchestrator stages only the intended plan
  files once every phase gate is green.
- **GDUnit gotchas:** warnings-as-errors (`var x :=` every type); same-type
  `is_equal_approx` args; `pre_check`/`check_part_a`/`check_part_b` for two-frame
  scenes.

---

## STATUS — 2026-09-25

- **DONE (P1–P4), gate GREEN — 810 tests | 0 errors | 0 failures | 18 orphans.**
- **2026-09-20 — plan authored.** Research closed with the CC0-first low-poly
  decision; this plan encodes the decision, resource list, Blender-MCP flow and
  dependency-ordered P1–P6 gates.
- **P1 trees (2026-09-25):** three CC0 GLB trees (`tree_a/b/c.glb`) fused into
  the MultiMesh herd; `foliage.gd` height-UV bake kept.
  `tests/suites/test_foliage_models.gd` green. Note: `tree_c.glb` re-exported
  with EMBEDDED textures (remapped the stray external pine texture).
- **P2 track props (2026-09-25):** six Kenney Racing Kit GLBs
  (`racing_barrier_red/pylon/grandstand/rail_double/flag_checkers/tent`) added to
  `PropScatterer._mesh_builders` + `festival`/`highlands` presets.
  `tests/suites/test_track_props.gd` green (3/3).
- **P3/P4 buildings + rocks (shipped 2026-09-21 in 6c9b76b):** `assets/buildings/`
  (pit garage + office), `assets/rocks/rock_a.glb`, base `assets/track_props/`
  (barrier/cone/rail/grandstand/gantry/light pole) wired into `default_preset`
  zones. `tests/suites/test_building_placement.gd` green (3/3). This STATUS was
  previously stale (said UNSTARTED); the 09-21 commit had already shipped these.
- **P5 hero car: optional, not requested.** P6 polish folded into the green gate.

*Plan ends.*