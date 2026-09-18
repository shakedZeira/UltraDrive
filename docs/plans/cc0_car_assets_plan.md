# UltraDrive — CC0 Handcrafted Car Asset Plan

> Swap the AI-scripted car geometry (Hyper3D rodin silhouette flow) for a
> library of **handcrafted CC0 (public-domain) vehicle models** downloaded from
> open asset markets, normalized in Blender and consumed as GLB PackedScenes —
> the exact pipeline the existing `assets/cars/*.glb` (sports_coupe, muscle_car,
> rally_hatch) already uses.
>
> **Written:** 2026-09-18 · **Inputs:** Gemini recommendation (assets → CC0
> marketplace swap), web research (`docs/research/cc0_car_sources.md` if kept),
> `AGENTS.md` Blender-MCP + car conventions · **Format:** GLB → Godot 4.7 native
> import (`PackedScene`), PBR metal-roughness, wheels as separate child meshes.

---

## Why

The D4 "PNG → silhouette → model" flow (Hyper3D rodin) is slow, low-quality, and
hostile to *mathematically smooth* car surfaces. Handcrafted public-domain models
look better, import cleanly, and carry no license debt. CC0 = public domain = no
attribution, no per-use fees, safe for a shipping title.

## Asset selection (researched, verifiable)

| Asset | Source | License | Format | Auto-download |
|---|---|---|---|---|
| Kenney Car Kit (sedan/van/taxi/pickup/kart…) | `kenney.nl/assets/car-kit` | **CC0** | OBJ/FBX/glTF (zip) | ✅ direct zip |
| Free Concept Car 037 (public domain) | GitHub raw (Vivekkk-1/3D-Models) | **CC0** | GLB | ✅ raw URL |
| Quaternius Cars Pack | poly.pizza bundle | CC0 (verify per model) | GLB/FBX | API key required |

**Rejected:** CGTrader free ("Royalty Free"), TurboSquid free ("Royalty Free") —
not CC0. Khronos CarConcept — repo is CC-BY 4.0, acceptable only with
attribution; not primary.

## Pipeline

1. **Download** shortlist into `assets/cars/cc0/` (new dir, gitignored? No —
   committed; binaries tracked like existing `.glb`).
2. **Normalize in Blender (MCP or headless `-b -P`)**: orient nose to -Z
   (Godot camera forward) so `CAR_ORIENT` (180° Y) keeps the nose facing
   forward at runtime, split wheels into separate child meshes, bake transforms,
   triangulate, export GLB to `assets/cars/`.
3. **Consume like the existing pipeline**: `player_car_controller.gd`
   `_apply_visual()` swaps the `CarBody` glb per active car from
   `Garage.new_from_save().get_active_car()`; `CarVisuals` per-model wheel/
   brake-glow tables; `car_config.gd` D/C/B/A/S classes.
4. **Test gate**: GDUnit — each new car loads as a `PackedScene`, the visual
   swap instantiates without error, wheels resolve for spin/steer, garage
   registry lists the new cars, existing suites (car_visuals, car_audio,
   settings_presets) stay green.

## Blender MCP setup (D4 — this machine currently has NO Blender)

- Install Blender 4.5.x (match reference box 4.5.13) → `C:\Program Files\Blender Foundation`.
- Install `uv` (astral.sh installer) → then addon install:
  `uvx mcp-for-blender install-addon` (package renamed from `blender-mcp`;
  `uvx blender-mcp` is legacy).
- Enable "Interface: MCP for Blender" addon in Blender; Start MCP Server
  (port 9876).
- Add to `~/.config/opencode/opencode.jsonc`:
  ```jsonc
  "mcp": {
    "blender-mcp": {
      "type": "local",
      "command": ["uvx", "mcp-for-blender"],
      "enabled": true,
      "environment": { "BLENDER_HOST": "localhost", "BLENDER_PORT": "9876" }
    }
  }
  ```
- Tools appear in opencode sessions AFTER restart; verify with
  `opencode mcp list` + `blender-mcp_get_addon_status`.

## Acceptance

- `assets/cars/cc0/` holds ≥ 3 handcrafted CC0 GLBs, imported with **zero**
  `SCRIPT ERROR` / `Parse Error` on the headless import probe.
- Every new car is selectable in the garage and drivable (body swap + wheels
  spin/steer), per `test_car_visuals` discipline.
- GDUnit suite green (baseline 166 + new car-load tests, monotonic growth).

## STATUS — 2026-09-18 (implemented)

- **Blender MCP:** Blender 4.5.13 LTS portable at `C:\Blender\...\blender.exe`;
  `uv` + **`mcp-for-blender`** installed; addon `blender_mcp` installed to the
  per-user `%APPDATA%\Blender Foundation\Blender\4.5\scripts\addons` and
  verified importable headless; MCP entry added to
  `~/.config/opencode/opencode.jsonc`. To connect: start Blender, enable
  "Interface: MCP for Blender", Start MCP Server (9876), then restart opencode
  (`blender-mcp_*` tools appear).
- **Assets landed:** full Kenney Car Kit (GLB-only) at
  `assets/cars/cc0/kenney_car-kit/` (License.txt = CC0) + `free_concept_car_037.glb`
  (CC0, high-poly — parked for a future Blender decimation/split pass).
- **Integrated cars (3):** `cc0_sedan_sports` (Comet, C), `cc0_hatchback_sports`
  (Hooligan, B), `cc0_race` (Interceptor, A). Each: `assets/cars/cc0_*.glb` +
  `resources/cars/cc0_*.tres`, plus `CarVisuals.WHEEL_GROUPS` entries
  (Kenney top-level wheel nodes) and `Garage.STARTER_CARS` (owned from the
  start). Probed headless: all three face +Z (nose forward), four wheel meshes
  resolve per corner, wheels are X-axle discs.
- **Test-gate:** `tests/suites/test_cc0_cars.gd` (config resolve, GLB instantiate,
  +Z facing, 4-corner `resolve_wheel_nodes`, garage ownership); the corner-table
  invariant in `test_car_visuals.gd` was widened to the new ids.

*Plan ends. Research data (licenses, download URLs, API quirks) is captured in
this file's Asset selection table; re-verify the Kenney zip hash URL when
re-running (it changes on asset updates).*