# HUD: current HP (no minus) + live torque in Nm — implementation plan

Status: PLANNED (2026-10-16). Scope: driving HUD only — the Forza/GT-style
`%Cluster` readout. Godot 4.7.2, project root = res://.

User request: *"when driving, i want to show the current HP (like it's currently
but without the minus) and also show the torque in Newton meters (nm)"*.

---

## 1. Current-state analysis (exact refs)

**Where the HP is drawn**

- `scripts/race/power_gauge.gd:86-89` — `PowerGauge.format_text(config, rpm)`
  returns `"%d hp  %s" % [roundi(power_hp(config, rpm)),
  signed_hp(hp_delta_hp(config, rpm))]`. The **second token is the minus**: it
  is the SIGNED current-minus-peak gap (`hp_delta_hp`, doc at
  `power_gauge.gd:70-76`: *"Negative while the engine is off its power peak"*).
  Off-peak (i.e. almost always) it renders like `312 hp  -47`.
- `scripts/race/race_ui.gd:470-475` — `_refresh_power_readout(info, cfg)` builds
  `PowerGauge.format_text(cfg, info["rpm"])` every frame and assigns
  `%PowerValue.text` only when the string changed (`if power_value.text != text`).
  Called from `_process` at `race_ui.gd:166` (car present) and `:140`
  (no car → `({}, null)` → placeholder `"-- hp"`).
- `scenes/ui/hud.tscn:375-387` — the `PowerValue` Label: child of
  `Root/Cluster`, `unique_name_in_owner`, local rect `x 360..552, y 250..286`
  (bottom-right of the cluster), right-aligned, font size 20, font color
  `Color(0.62, 0.86, 1, 1)`, outline 3, default text `"-- hp"`.
- `race_ui.gd:29` — `@onready var power_value: Label = %PowerValue`.

**Cluster geometry (for fit checks)**

- `hud.tscn:273-285` — `Cluster` (script `tachometer.gd`) local rect
  `x 0..560, y 0..306` (offsets 24..584 / −330..−24 from the bottom-left);
  `Tachometer.DESIGN_SIZE` is `560×330` (`tachometer.gd:14`).
- Occupied: gear digit `x120..250,y44..156`, speed `x400..540,y58..166`,
  class badge `x480..528,y206..246`, `RpmValue` `x130..240,y240..284`,
  `RpmUnit` `x150..220,y288..310`, `PowerValue` `x360..552,y250..286`,
  `BoostGauge` `x370..470,y92..200` (hidden until turbo), `TractionLamp`
  `x462..504,y4..46`. **Free: `x360..552, y≈288..314`** (right side under
  PowerValue; nothing but empty panel there; `ClusterBackdrop`
  (`hud.tscn:260-271`) extends 12 px below the cluster, so a line bottoming at
  y≈312 still sits on the backdrop). Controls do not clip children
  (`clip_contents` off) — `RpmUnit` already bottoms at 310 > 306.

**Available live values**

- `scripts/vehicle/vehicle_physics.gd:482-506` — `get_drive_info()` exposes
  `rpm` (drivetrain engine rpm), `gear`, `speed_kmh`, `throttle`, `boost_bar`,
  … but **no torque**; torque must be derived from the config curve.
- `scripts/vehicle/car_config.gd:181-194` — `get_engine_torque(rpm)` returns
  **crank torque from the spec curve** (Nm): `max_torque*0.5` below idle, linear
  ramp to `max_torque` at `peak_rpm`, parabolic falloff to 0 at `redline_rpm`
  (0 above redline). **Throttle-independent** — `drivetrain.gd:118` multiplies
  it by throttle when applying force; `max_torque` (`car_config.gd:34`,
  "Nm at peak RPM") is the .tres spec-sheet figure (GTR 634 Nm).
- Engine rpm floor is `idle_rpm * 0.8` (`drivetrain.gd:111-115`), so at rest the
  curve reads just below idle → `0.5 * max_torque` (same sample the HP formula
  already uses, see below).

**Consumers / blast radius**

- `PowerGauge.format_text` has exactly ONE runtime consumer: `race_ui.gd:473`.
  The other references are tests: `tests/suites/test_traction_hud.gd:227, 293,
  295-311`.
- `hp_delta_hp` / `signed_hp` / `peak_power_hp` are used by tests only at
  runtime-adjacent scope (`test_traction_hud.gd:237-311`); garage peak power
  uses a *different* class, `TuningProfile.peak_power_hp`
  (`garage_ui.gd:440`, `tuning_profile.gd:148`).
- `CockpitDash` (`cockpit_dash.gd:69-79`) mirrors only speed/rpm/gear — it does
  NOT duplicate the HP line, so no second readout to change (and in cockpit
  mode the whole `%Cluster`, incl. any new label, auto-dims to ~20 % via
  `cockpit_dash.gd:106-113` — correct behaviour).
- `race_ui.gd` (script `hud.tscn` line 4) is instanced only by
  `scenes/ui/hud.tscn` — one scene to edit.

---

## 2. Design decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| D1 | HP value | **Current crank hp, positive integer**, `"%d hp"` (`roundi(PowerGauge.power_hp(cfg, rpm))`), placeholder `"-- hp"` unchanged | Exactly "like currently but without the minus": same `power_hp` source, drop the trailing signed-delta token only. |
| D2 | Torque value | **Live crank (spec-sheet) Nm**, `"%d Nm"` from `cfg.get_engine_torque(rpm)` at the *same* rpm sample the HP uses; no throttle, no gear/final-drive, no boost multiplier | (a) matches `max_torque` in the .tres files (634 Nm GTR = what you'd see on a spec sheet); (b) throttle-independent keeps it consistent with the HP readout, which is also curve-only — otherwise HP could read `0 hp` while torque reads `480 Nm`; (c) `P = τ·ω` stays auditable: the on-screen hp and Nm are the two factors of the same product. Wheel Nm (× gear × final drive) would show 10 000+ Nm in 1st — rejected. |
| D3 | Unit casing | `"Nm"` (capital N, lowercase m), never `"nm"` | SI convention; the user's "nm" is just casual typing. |
| D4 | Placement | **New `TorqueValue` Label under `PowerValue`**, right-aligned stack: `x 360..552, y 288..312`, same font size 20 / color `Color(0.62,0.86,1,1)` / outline 3 as `PowerValue` | Mirrors the existing `RpmValue`+`RpmUnit` stacked-pair idiom; `PowerValue` keeps its exact current rect (minimal diff); the free zone verified in §1. **Alternative rejected**: one combined line `"312 hp  480 Nm"` in `PowerValue` — fits, but two stats on one line at font 20 reads cramped next to the class badge and couples the two refreshes' widths. |
| D5 | API | Change `PowerGauge.format_text` in place to `"%d hp"` / `"-- hp"`; ADD `PowerGauge.torque_nm(config, rpm)` + `PowerGauge.format_torque_text(config, rpm)` (`"-- Nm"` for null config) | `format_text`'s only runtime consumer is this HUD, so its contract should follow the HUD contract; keeping a dead delta-format function alive purely for tests is worse. `power_hp`/`peak_power_hp`/`max_power_rpm`/`hp_delta_hp`/`signed_hp` all stay byte-identical — every existing curve/delta test keeps passing; only the format test is rewritten (§4). |
| D6 | Update cost | Keep the existing pattern: format each frame, assign only on change (`race_ui.gd:474-475`). No new per-frame work beyond one extra format+compare | The codebase already formats unguarded every frame (`coords_label`, `race_ui.gd:178`); adding a second `"%d"` format is within the existing budget. Optional micro-gate (recompute only when `roundi(rpm)` changes) documented in §5, NOT in the first pass. |
| D7 | Naming | class stays `PowerGauge`; header doc gains one line saying it also formats the torque readout | Renaming the class would touch imports/tests for zero user value. |

Formatting examples (all integers, no decimals, no `+`/`−` anywhere):

```
HP:    "312 hp"   "0 hp"   "-- hp"     (null config / no car)
Torque:"480 Nm"   "0 Nm"   "-- Nm"
```

---

## 3. Step-by-step implementation

### Step 1 — `scripts/race/power_gauge.gd`

1. `format_text` (line 86-89) → return `"-- hp"` for null config, else
   `"%d hp" % roundi(power_hp(config, rpm))`. Delete the `signed_hp` call from
   this function only.
2. Add below `hp_delta_hp`:

   ```gdscript
   ## Live crank torque (Nm) at `rpm`: the same CarConfig curve sample the hp
   ## readout uses (throttle/gear independent — spec-sheet style, matching
   ## max_torque). Zero for a null config.
   static func torque_nm(config: CarConfig, rpm: float) -> float:
       if config == null:
           return 0.0
       return config.get_engine_torque(maxf(rpm, 0.0))

   ## HUD line: "<current> Nm", "-- Nm" when there is no config.
   static func format_torque_text(config: CarConfig, rpm: float) -> String:
       if config == null:
           return "-- Nm"
       return "%d Nm" % roundi(torque_nm(config, rpm))
   ```

3. Extend the class doc (lines 5-16) with one sentence: the HUD shows current
   crank hp and live crank Nm; `hp_delta_hp` remains the rated-peak gap kept
   for tests/diagnostics but is no longer rendered.
4. Do **not** touch `power_hp`, `peak_power_hp`, `max_power_rpm`,
   `hp_delta_hp`, `signed_hp`, `WATTS_PER_HP`, `PEAK_SCAN_STEP_RPM`.

### Step 2 — `scenes/ui/hud.tscn`

Add ONE node, after `PowerValue` (insert at line ~388, before `BoostGauge`):

```
[node name="TorqueValue" type="Label" parent="Root/Cluster"]
unique_name_in_owner = true
offset_left = 360.0
offset_top = 288.0
offset_right = 552.0
offset_bottom = 312.0
horizontal_alignment = 2
vertical_alignment = 1
text = "-- Nm"
theme_override_colors/font_color = Color(0.62, 0.86, 1, 1)
theme_override_colors/font_outline_color = Color(0.02, 0.04, 0.09, 1)
theme_override_constants/outline_size = 3
theme_override_font_sizes/font_size = 20
```

- Plain theme-override properties only → **no new `[ext_resource]` /
  `[sub_resource]`, leave `[gd_scene load_steps=17 format=3]` (line 1) alone.**
- No change to `PowerValue`, `Cluster`, `ClusterBackdrop`.

### Step 3 — `scripts/race/race_ui.gd`

1. Next to line 29 add:
   `@onready var torque_value: Label = %TorqueValue`
2. `_refresh_power_readout` (lines 468-475) — extend to drive both labels,
   keep the name (both call sites stay valid), update its doc comment:

   ```gdscript
   ## HP + torque lines under the cluster: current crank power (hp) and live
   ## crank torque (Nm) at the current rpm — both curve-only, no sign tokens.
   func _refresh_power_readout(info: Dictionary, cfg: CarConfig) -> void:
       if power_value == null:
           return
       var rpm := float(info.get("rpm", 0.0))
       var text := PowerGauge.format_text(cfg, rpm)
       if power_value.text != text:
           power_value.text = text
       if torque_value == null:
           return
       var torque_text := PowerGauge.format_torque_text(cfg, rpm)
       if torque_value.text != torque_text:
           torque_value.text = torque_text
   ```

3. Call sites (`:140` no-car, `:166` per-frame) unchanged — null config yields
   `"-- hp"` / `"-- Nm"` automatically.
4. Nothing else in `_process` changes (rpm/gear/speed gating at 152-160 is
   tachometer-specific and untouched).

### Step 4 — tests (see §4), then gate

Run only the touched suites first (`test_traction_hud.gd`, plus
`test_cockpit_hud.gd` + `test_hud_contrast.gd` as cluster-layout canaries)
via the `docs/GDUNIT_GATE.md` headless recipe; a full parallel gate only if
those are green. Remember: import probe first, `--ignoreHeadlessMode` AFTER
the tool-script path, prefer dispatching the full gate as a background
sub-agent per AGENTS.md.

---

## 4. New / updated GDUnit tests

All in `tests/suites/test_traction_hud.gd` (the file that already owns the
`# --- HP delta readout ---` section, lines 235-311) — match its conventions
exactly: `extends GdUnitTestSuite`, `assert_that(x).is_equal(...)`,
`is_equal_approx(v, eps)`, `is_less/is_greater/is_between/contains/
begins_with/ends_with`, tabs, explicit types (gdUnit treats warnings as
errors), cleanup via `_managed` / `after_test`.

### Updated — rewrite `test_format_text_renders_current_hp_and_the_signed_delta`
(lines 295-311) → `test_format_text_renders_current_hp_with_no_sign_token`:

```gdscript
func test_format_text_renders_current_hp_with_no_sign_token() -> void:
	var cfg := CarConfig.new()
	var at_peak := PowerGauge.max_power_rpm(cfg)
	# Exactly "<n> hp": current crank power, no delta, no sign.
	assert_that(PowerGauge.format_text(cfg, at_peak)).is_equal(
		"%d hp" % roundi(PowerGauge.peak_power_hp(cfg)))
	assert_that(PowerGauge.format_text(cfg, cfg.idle_rpm)).is_equal(
		"%d hp" % roundi(PowerGauge.power_hp(cfg, cfg.idle_rpm)))
	# Above the redline the curve is zero, and it must read "0 hp" not "-<n>".
	assert_that(PowerGauge.format_text(cfg, cfg.redline_rpm + 500.0)).is_equal("0 hp")
	# The placeholder contract is unchanged (also asserted by the wiring test).
	assert_that(PowerGauge.format_text(null, 5000.0)).is_equal("-- hp")
	# No sign character can appear anywhere in a rendered line.
	assert_that(PowerGauge.format_text(cfg, cfg.idle_rpm).contains("-")).is_false()
	assert_that(PowerGauge.format_text(cfg, at_peak).contains("+")).is_false()
```

- `signed_hp` tests (309-311) **stay as-is** — the function is unchanged and
  still covered. `test_null_config_is_safe_everywhere` (289-293) stays as-is
  (add `PowerGauge.torque_nm(null, 5000.0) == 0.0` and
  `PowerGauge.format_torque_text(null, 5000.0) == "-- Nm"` lines to it).
- Tests 237-287 (curve / delta invariants) untouched — they gate the kept
  functions.

### New — `test_torque_nm_reads_the_spec_sheet_curve_in_newton_metres`

```gdscript
func test_torque_nm_reads_the_spec_sheet_curve_in_newton_metres() -> void:
	var cfg := CarConfig.new()
	cfg.max_torque = 300.0
	cfg.peak_rpm = 6500.0
	cfg.idle_rpm = 800.0
	cfg.redline_rpm = 7500.0
	# At peak_rpm the curve is exactly max_torque (the .tres spec figure).
	assert_that(PowerGauge.torque_nm(cfg, cfg.peak_rpm)).is_equal_approx(300.0, 0.01)
	# The displayed hp and Nm are the same curve sample: P = tau * omega.
	var rpm := cfg.idle_rpm
	while rpm <= cfg.redline_rpm:
		var expected_hp := PowerGauge.torque_nm(cfg, rpm) * rpm * TAU / 60.0 / PowerGauge.WATTS_PER_HP
		assert_that(PowerGauge.power_hp(cfg, rpm)).is_equal_approx(expected_hp, 0.001)
		assert_that(PowerGauge.format_torque_text(cfg, rpm)).is_equal(
			"%d Nm" % roundi(PowerGauge.torque_nm(cfg, rpm)))
		rpm += 500.0
	# Past the redline the curve is zero → "0 Nm", never a negative number.
	assert_that(PowerGauge.torque_nm(cfg, cfg.redline_rpm + 500.0)).is_equal(0.0)
	assert_that(PowerGauge.format_torque_text(cfg, cfg.redline_rpm + 500.0)).is_equal("0 Nm")
	# A bigger engine shows more torque (spec-sheet monotonicity).
	var fast := CarConfig.new()
	fast.max_torque = 600.0
	assert_that(PowerGauge.torque_nm(fast, fast.peak_rpm)).is_greater(
		PowerGauge.torque_nm(cfg, cfg.peak_rpm))
```

### New/extended — HUD wiring (extend `test_hud_wires_the_lamp_and_power_line_from_a_stub_car`,
lines 216-233, keep its name or rename to `..._power_and_torque_lines_...`):

```gdscript
	var torque := scene.get_node("%TorqueValue") as Label
	assert_that(torque).is_not_null()
	# No player car → both placeholders, no sign tokens anywhere.
	assert_that(power.text).is_equal(PowerGauge.format_text(null, 0.0))
	assert_that(power.text).is_equal("-- hp")
	assert_that(torque.text).is_equal(PowerGauge.format_torque_text(null, 0.0))
	assert_that(torque.text).is_equal("-- Nm")
```

### New — `test_hud_power_and_torque_lines_track_a_registered_stub_car`

Mirror the stub-car pattern used in `test_race_results.gd:77` /
`test_open_world_hud.gd:78` (`VehiclePhysics.new()` + `config = CarConfig.new()`
+ `VehicleManager.register_player_car(car)`, append to `_managed`, register a
`before_test`/`after_test` deregistration):

```gdscript
func test_hud_power_and_torque_lines_track_a_registered_stub_car() -> void:
	var car := VehiclePhysics.new()
	car.config = CarConfig.new()
	car.config.max_torque = 500.0
	_managed.append(car)
	VehicleManager.register_player_car(car)
	var runner := scene_runner("res://scenes/ui/hud.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as RaceUI
	var power := scene.get_node("%PowerValue") as Label
	var torque := scene.get_node("%TorqueValue") as Label
	# Idle-stub drive info (rpm 0 → hp 0, torque = half curve below idle).
	var rpm := 0.0
	assert_that(power.text).is_equal("%d hp" % roundi(
		PowerGauge.power_hp(car.config, rpm)))
	assert_that(torque.text).is_equal("%d Nm" % roundi(
		PowerGauge.torque_nm(car.config, rpm)))
	# THE user-facing contract: no leading minus on either readout.
	assert_that(power.text.begins_with("-")).is_false()
	assert_that(torque.text.contains("-")).is_false()
	VehicleManager.remove_car(car)
```

(Adjust `rpm`/expected values to whatever the treeless stub reports through
`get_drive_info()` — the test must compute expectations from the SAME
`info["rpm"]` the HUD reads, not hard-code numbers. If a treeless
`VehiclePhysics.new()` reports rpm 0, the assertions above already hold.)

---

## 5. Risks / gotchas

1. **Per-frame String formatting** — two formats + two compares per frame in
   `_refresh_power_readout`. Within the existing budget (`coords_label`
   formats every frame unguarded at `race_ui.gd:178`), and the assign-guard
   prevents Label re-layout. If `test_perf_gate.gd` ever flags it, the
   follow-up micro-gate is: skip both formats while
   `roundi(rpm) == _last_readout_rpm` (sentinel −1 at start) — the displayed
   integers can only change when the integer rpm changes. Not in pass 1.
2. **Test contract change** — `format_text`'s rendered string changes, so
   `test_traction_hud.gd:295-311` must be rewritten in the SAME change set or
   the suite goes red. Lines 227 and 293 (`"-- hp"`) survive untouched.
3. **gdUnit warnings = errors** — no `:=` on Variant-returning calls, type all
   locals (`var rpm := float(...)`), tabs for indentation, and vector
   `is_equal_approx` needs a same-type epsilon (not used here, but don't
   "helpfully" compare `Vector2` with a float).
4. **Redline interplay** — above redline the curve is 0, so the lines read
   `0 hp` / `0 Nm` while the tach rpm digit is red and the shift light blinks.
   This is truthful (it already reads `0 hp  -<peak>` today) but will look
   "broken" to a tester — document it in the PR description; do NOT tint the
   two labels red (that's `tachometer.gd`'s rpm digit job, line 97).
5. **Standstill artifact** — rpm floors at `idle_rpm*0.8`
   (`drivetrain.gd:111-115`), below idle the curve returns
   `0.5*max_torque`, so a parked car shows ~50 % torque (e.g. `317 Nm` for the
   634 Nm GTR) and a small non-zero hp. Same sample the HP already shows today;
   accepted for D2 consistency (throttle-gating would desync hp from Nm).
6. **Cockpit dash does NOT duplicate these** (`cockpit_dash.gd` shows
   speed/rpm/gear only) — nothing to add there. In cockpit mode the new label
   inherits the cluster's ~20 % dim automatically (it's a `%Cluster` child) —
   desired "subtract cluster" behaviour, not a bug.
7. **Scene edits are node-only** — no new ext/sub resources, so
   `load_steps=17` must NOT be bumped; a bumped header means you accidentally
   added a resource.
8. **Sim vs arcade** — `handling_mode` grip multipliers
   (`car_config.gd:151-162`) do not touch the torque curve, so both readouts
   are mode-independent; no branching needed.
9. **Turbo/boost cars** — displayed Nm is the NA curve value (no boost adder),
   consistent with how `power_hp` already ignores boost. The separate
   `BoostGauge` (`hud.tscn:389`) remains the boost story; don't fold boost
   into the Nm figure.
10. **`%` unique-name lookups fail hard at `_ready`** — `TorqueValue` MUST be
    added to `hud.tscn` before/with the `race_ui.gd` onready line, or every
    HUD scene load errors (it's the only scene using the script, so a single
    load test catches it).

---

## 6. Do-NOT-touch list

- `scripts/race/power_gauge.gd`: `power_hp`, `peak_power_hp`,
  `max_power_rpm`, `hp_delta_hp`, `signed_hp`, `WATTS_PER_HP`,
  `PEAK_SCAN_STEP_RPM` — semantics and signatures frozen (tests
  `test_traction_hud.gd:237-293, 309-311` gate them). Only `format_text`'s
  output changes; `hp_delta_hp` keeps its signed contract.
- `scripts/vehicle/car_config.gd` — `get_engine_torque` curve, `max_torque`,
  `with_overrides`, everything else.
- `scripts/vehicle/drivetrain.gd:118` (torque × throttle application) and the
  rpm clamps at `:111-115` — the sim must keep applying torque as-is; this
  plan only *reads* the curve.
- `scripts/vehicle/vehicle_physics.gd::get_drive_info()` — no new keys needed;
  rpm already flows.
- `scripts/race/cockpit_dash.gd` and `scenes/ui/cockpit_dash.tscn` — speed /
   rpm / gear only; HP/torque intentionally stay cluster-only.
- `scripts/race/tachometer.gd` — arc/needle/redline/shift-light drawing and
  its `_process` easing; the new label is a scene child, driven by `race_ui`.
- `scenes/ui/hud.tscn`: `PowerValue` node + rect + style, `Cluster`,
  `ClusterBackdrop`, `BoostGauge`, `TractionLamp`, and the `load_steps` header.
- `scripts/ui/garage_ui.gd` / `scripts/career/tuning_profile.gd` peak-power
  display (a different class, garage-screen concern).
- Test files other than `tests/suites/test_traction_hud.gd` (canaries
  `test_cockpit_hud.gd` / `test_hud_contrast.gd` are run, never edited).
- No new autoloads, no new resources (.tres/.res), no per-frame
  `queue_redraw()` on the cluster for these readouts.
