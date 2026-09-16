# Graphics Lift — Accepted Godot 4 Ceilings

Record of known Godot 4.7 Forward+ limitations accepted for the graphics lift.

## Accepted ceilings (Godot 4, Forward+)

- **No real-time ray-traced reflections.** RT reflections are unavailable in Godot's Forward+ renderer. The closest-to-RT finish is per-car ReflectionProbe combined with SSR and SDFGI.
- **No BT.2020 / wide-gamut pipeline and no photometric (HDR-pair) paint capture.** Paint color is authored procedurally; no measured wide-gamut or HDR paint workflow exists in the engine.
- **No built-in cinematic tone operator in the exact FH5/GT7 form.** Godot provides ACES (mode 3) and AgX (mode 4) tonemap modes only. The lift standardizes on ACES; AgX is exposed as a settings option.
- **FSR 2.2 is the built-in implementation only.** Available via `rendering/scaling_3d/mode` and `scale` in the Godot project settings. No standalone FSR 2.2 DLL workflow or asset downloads (C2 decided procedural-only).
- **Multi-sample anti-aliasing is a one-frame MSAA choice.** TAA is available in Godot but not defaulted; the lift standardizes on MSAA.

## Deferred to Phase 2 (Blender MCP follow-up)

- Authored texture sets: paint, ORM (occlusion/roughness/metallic), flake/coat.
- Wheel and suspension visual split, brake calipers and discs.
- Showroom and photo mode.
- Interior light bakes.

## Where to revisit

- Per-car ReflectionProbe update-rate and resolution are gated by the perf-tachometer plan; revisit once profiling data is available.
- SKID, WIND, and TRANSMISSION audio beds were explicitly deferred by D1-minimal; consider alongside any Phase 2 visual pass.
