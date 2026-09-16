# Audio Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make UltraDrive no longer silent under its existing art-directed **synth-only** audio philosophy: keep the procedural engine loop, add audible tire-skid + wind/exhaust feedback and a low ambient wind bed — all generated at runtime, zero new binary assets — and lock the audio layer down with GDUnit4 tests (inventory D7) plus fix the stale asset probe (A10).

**Architecture:** One pure, deterministic synth module (`AudioSynth`, RefCounted static helpers) generates all PCM loops (seeded `RandomNumberGenerator`, 16-bit mono `AudioStreamWAV`, `LOOP_FORWARD`). `CarAudio` (an `AudioStreamPlayer3D` child of `VehiclePhysics`) keeps owning the engine loop exactly as today and gains two runtime child players — `SkidPlayer` and `WindPlayer` — on a new `SFX` bus. A new autoload `AudioRouting` ensures `Music`/`Ambience`/`SFX` buses (idempotent against `AudioServer`) and plays a quiet global `WindBed` on the `Ambience` bus. Engine-loop behavior stays byte-compatible (identical arithmetic, just extracted to statics + additive layers).

**Tech Stack:** Godot 4.7.2 GDScript, GDUnit4

**Spec:** inventory C8 (synth-only audio, game otherwise silent), A10 (stale `engine_loop.*` asset probe always falls back), D7 (CarAudio zero tests; seeded-loop determinism at `car_audio.gd:114`). Verified on disk: `assets/` has only `cars/`; `resources/` has only `cars/` + `materials/`; no audio dirs, no `default_bus_layout.tres`. `get_drive_info()` returns `{rpm, gear, speed_kmh, handling_mode}` — **no slip key**, so skid is a documented proxy computed in `CarAudio` from `get_steer_angle()` + `get_speed_kmh()` + `InputManager.is_handbrake()`. `settings_menu.gd:36` already drives the built-in `Master` bus; buses below plug in without touching it.

---

## Global Constraints

- **Never `git add -A`.** Stage only the intended files per task (`git add <file...>`), then `git commit` with a concise message. New `.uid` files are gitignored — never stage them. Keep `git status --short` free of non-ignored junk at every commit.
- **Do NOT touch:** `AGENTS.md`, `start_game.bat`, `play_game.bat`, `.godot/`, `addons/`.
- **Engine engine-loop byte-compat:** the generated loop PCM, seed formula (currently `int(loop_hz * 1000.0 + noise_gain * 100.0)`), and the `_physics_process` pitch/volume math must stay *arithmetically identical* — extraction to statics is allowed, changing values is not. Existing vehicle/race tests must stay green.
- **TAB indentation** in all GDScript.
- **GDUnit4 warnings-as-errors:** never use `:=` on a Variant-returning call (e.g. `Dictionary.get(...)`); write `var x: float = float(d.get(...))`. New helpers are fully typed so `:=` is only used where the RHS type is clearly not Variant.
- **No new binary assets.** Everything is `AudioStreamWAV` synthesized in code. One optional future artist override path is a *documented* string constant, not a probed file.
- **Per-task TDD loop:** one-action checkbox steps — (1) write the real failing test, (2) run the GDUnit suite and see it FAIL, (3) minimal implementation, (4) re-run and see PASS, (5) commit. Implementation MUST NOT move to the next step on a red suite.
- **Verification (verbatim from AGENTS.md), run at every task's commit gate AND at the end:**
  1. `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --import . 2>&1 | findstr /i "SCRIPT ERROR Parse Error Failed to load"` → expect **zero** matches (benign `resources still in use` / Terrain3D whitelist lines allowed).
  2. `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests > _gdunit.txt 2>&1` then `findstr /c:"Overall Summary:" _gdunit.txt` → baseline `Overall Summary: 69 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans`. Expected growth ≈ 25 new test functions → **~94 test cases, 0/0/0** (exact count comes from the actual run; the 16 orphans stay benign).
- All `AudioServer`/`AudioStreamPlayer` code must be headless-safe (Dummy driver): `add_bus()`, `play()`, string `bus` assignment, and 3D positioned players all work silently under `--headless`.
- Optional menu music is **explicitly deferred** (written note in Task 6) — the `Music` bus exists and is wired to Master, but no music source is added; ambience is a single quiet always-on wind bed, not per-scene.

---

## Task 1 — Extract engine mapping into typed statics (D7 lock base)

**Files:** `scripts/vehicle/car_audio.gd`, `tests/test_car_audio.gd` (new)

**Interfaces:**
- Consumes: existing `_physics_process` (lines 80-91) rpm/speed extraction and config resolution.
- Produces (new statics on `CarAudio`, arithmetic copied byte-for-byte from current lines 85-91):
  - `static func norm_rpm(rpm: float, redline: float, idle: float) -> float` → `clampf((rpm - idle) / (redline - idle), 0.0, 1.0)`
  - `static func engine_pitch(base_pitch: float, redline_pitch: float, norm: float) -> float` → `lerpf(base_pitch, redline_pitch, norm)`
  - `static func engine_volume_db(speed_kmh: float) -> float` → `lerpf(-8.0, 0.0, clampf(speed_kmh / 140.0, 0.0, 1.0))`

- [ ] 1.1 Add to `tests/test_car_audio.gd` (below, minimal): `test_norm_rpm_idle_is_zero`, `test_norm_rpm_redline_is_one`, `test_norm_rpm_midpoint`, `test_norm_rpm_clamped_outside`, `test_engine_pitch_at_idle`, `test_engine_pitch_at_redline`, `test_engine_pitch_midpoint`, `test_engine_volume_at_rest`, `test_engine_volume_at_full_speed`, `test_engine_volume_midpoint`. Expected values: `norm_rpm(800,7000,800)==0.0`, `(7000,...,800)==1.0`, `(3900,...,800)==0.5`; `engine_pitch(0.8,2.2,0.0)==0.8`, `(..,1.0)==2.2`, `(..,0.5)==1.5`; `engine_volume_db(0.0)==-8.0`, `(140.0)==0.0`, `(70.0)==-4.0`.
- [ ] 1.2 Run suite → these tests FAIL (parse error: static members do not exist; whole file errors red).
- [ ] 1.3 Add the three statics to `car_audio.gd` and rewire `_physics_process` to call them — the *exact same float expressions* as today, no value changes. Engine pitch/volume output is byte-identical.
- [ ] 1.4 Run suite → PASS (69 + 10). Run headless import probe → zero errors.
- [ ] 1.5 `git add scripts/vehicle/car_audio.gd tests/test_car_audio.gd && git commit -m "audio: extract engine pitch/volume mapping into typed statics"`

---

## Task 2 — Lock seeded-loop determinism + profile selection (D7)

**Files:** `tests/test_car_audio.gd` (add tests; no game code — characterization of existing behavior)

**Interfaces:** Consumes `CarAudio._generate_engine_loop()`, `CarAudio.PROFILES`, `CarAudio._profile` (defaults to `PROFILES["sport"]`), seed at current `car_audio.gd:114`.

- [ ] 2.1 Add: `test_profile_table_has_three_timbres` (keys == `["sport","muscle","rally"]`), `test_default_profile_is_sport`, `test_generate_engine_loop_is_deterministic` (two `.new()` instances; compare `data.size()` and `data.hash()` via `.is_equal`), `test_different_timbres_generate_different_loops` (sport vs muscle `.hash()` differ), `test_engine_loop_wav_properties` (`format == FORMAT_16_BITS`, `mix_rate == 44100`, `stereo == false`, `loop_mode == LOOP_FORWARD`, `loop_begin == 0`, `loop_end == loop_begin + (data.size()/2)`).
  - Gotcha note for the writer: `PackedByteArray` `==` semantics are version-sensitive — compare with `data.hash()` and `data.size()`, not array `==`, to keep the test deterministic across engines.
- [ ] 2.2 Run suite → PASS (these lock *current* behavior; no implementation step). 79/0/0.
- [ ] 2.3 `git add tests/test_car_audio.gd && git commit -m "audio: characterization tests lock seeded engine-loop determinism (D7)"`

---

## Task 3 — `AudioSynth.noise_loop`: deterministic runtime noise (C8 foundation)

**Files:** `scripts/audio/audio_synth.gd` (new), `tests/test_audio_synth.gd` (new)

**Interfaces:**
- Produces (`class_name AudioSynth extends RefCounted`, `const SAMPLE_RATE: int = 44100`):
  - `static func noise_loop(samples: int, rng_seed: int, smoothing: float = 0.0) -> AudioStreamWAV` — seeded white noise; `smoothing` (clamped 0.0..0.999) is a one-pole leaky integrator `sample = white * (1 - s) + prev * s` so `smoothing == 0.0` is tire-hiss and `smoothing == 0.9` is wind rumble. Every parameter contributes to the seed path ⇒ fully deterministic. Returns 16-bit mono `AudioStreamWAV` at 44100 Hz, `LOOP_FORWARD`, `loop_begin=0`, `loop_end=samples`.
- Consumes: nothing (pure RefCounted, safe under headless).

- [ ] 3.1 Add tests: `test_noise_loop_is_deterministic_same_seed` (`noise_loop(4096, 123, 0.9)` twice → equal `data.hash()`/`size`), `test_noise_loop_different_seeds_differ`, `test_noise_loop_smoothing_changes_spectrum` (`(...,0.0)` hash != `(...,0.9)` hash), `test_noise_loop_wav_properties` (format/mix_rate/stereo/loop as above, `loop_end == samples`, `data.size() == samples * 2`).
- [ ] 3.2 Run suite → FAIL (script `scripts/audio/audio_synth.gd` missing → load error).
- [ ] 3.3 Implement `audio_synth.gd` per the interface above.
- [ ] 3.4 Run suite → PASS. Run headless import probe → zero errors (new script’s auto-generated `.uid` is gitignored — do not stage it).
- [ ] 3.5 `git add scripts/audio/audio_synth.gd tests/test_audio_synth.gd && git commit -m "audio: add deterministic AudioSynth.noise_loop runtime generator"`

---

## Task 4 — Skid + wind mapping statics (C8 behavior logic)

**Files:** `scripts/vehicle/car_audio.gd`, `tests/test_car_audio.gd` (add tests)

**Interfaces:**
- Produces (statics on `CarAudio`):
  - `static func skid_intensity(steer_deg: float, speed_kmh: float, handbrake: bool) -> float` → `clampf((absf(steer_deg) / 40.0) * clampf(speed_kmh / 90.0, 0.0, 1.0) * 1.5 + (0.8 if handbrake else 0.0) * clampf(speed_kmh / 40.0, 0.0, 1.0), 0.0, 1.0)`. Zero when straight/stopped; no physics change (A10/documentation note: there is intentionally no `slip` key in `get_drive_info()`).
  - `static func wind_volume_db(speed_kmh: float, throttle: float) -> float` → `maxf(lerpf(-70.0, -18.0, clampf(speed_kmh / 150.0, 0.0, 1.0)), lerpf(-70.0, -30.0, clampf(throttle, 0.0, 1.0)))`.
  - `static func wind_pitch(speed_kmh: float, rpm: float, redline: float) -> float` → `lerpf(0.8, 1.6, clampf(speed_kmh / 150.0, 0.0, 1.0) * 0.7 + clampf(rpm / redline, 0.0, 1.0) * 0.3)`.
- Consumes: nothing.

- [ ] 4.1 Add tests: `test_skid_zero_when_straight_and_still` (`skid_intensity(0,0,false)==0.0`), `test_skid_rises_with_steer_and_speed` (`(40,90,false)` == `1.0` > `(20,45,false)` ~ `0.375`), `test_skid_handbrake_boosts` (`(10,60,true)` == `1.0` > `(10,60,false)`), `test_skid_clamped_to_unit_interval` (max case == `1.0`), `test_wind_silent_at_rest_no_throttle` (`(0,0)==-70.0`), `test_wind_louder_with_speed` (`(150,0)==-18.0` > `(0,0)`), `test_wind_throttle_whoosh_at_rest` (`(0,1.0)==-30.0`), `test_wind_pitch_bounds_and_rises_with_speed` (at `(0,800,800)` in `[0.8,1.6]`, `(150,800,800)` > `(0,800,800)`).
- [ ] 4.2 Run suite → FAIL (statics missing → parse error).
- [ ] 4.3 Implement the three statics with the exact formulas above.
- [ ] 4.4 Run suite → PASS. Probe → zero errors.
- [ ] 4.5 `git add scripts/vehicle/car_audio.gd tests/test_car_audio.gd && git commit -m "audio: deterministic skid/wind intensity + volume mapping statics"`

---

## Task 5 — Fix A10 stale asset probe

**Files:** `scripts/vehicle/car_audio.gd`, `tests/test_car_audio.gd` (add tests)

**Interfaces:**
- Consumes: current `ASSET_CANDIDATES` (4 stale `engine_loop.*` paths in non-existent dirs) + `_load_loop_or_generate()`.
- Produces: replace `ASSET_CANDIDATES` with `const ENGINE_LOOP_OVERRIDE: String = "res://assets/audio/engine_loop.ogg"` and rewrite `_load_loop_or_generate()` as:
  - `if ResourceLoader.exists(ENGINE_LOOP_OVERRIDE): return load(ENGINE_LOOP_OVERRIDE) as AudioStream` else `return _generate_engine_loop()`. Doc comment states the synth-only intent: one documented place an artist may drop a replacement; the probe is deliberate, not stale.

- [ ] 5.1 Add: `test_single_explicit_override_path` (`CarAudio.ENGINE_LOOP_OVERRIDE == "res://assets/audio/engine_loop.ogg"`), `test_fallback_generates_loop_when_no_asset` (`CarAudio.new()._load_loop_or_generate()` is `AudioStreamWAV`).
- [ ] 5.2 Run suite → FAIL (constant unknown → parse error).
- [ ] 5.3 Remove `ASSET_CANDIDATES`; add `ENGINE_LOOP_OVERRIDE`; rewrite `_load_loop_or_generate()` as above. No other behavior change.
- [ ] 5.4 Run suite → PASS. Probe → zero errors.
- [ ] 5.5 `git add scripts/vehicle/car_audio.gd tests/test_car_audio.gd && git commit -m "audio: consolidate stale engine_loop asset probe into one explicit override path (A10)"`

---

## Task 6 — `AudioRouting` autoload: buses + global wind bed (ambience, d-criteria)

**Files:** `scripts/audio/audio_routing.gd` (new), `project.godot` (add autoload), `tests/test_audio_routing.gd` (new)

**Interfaces:**
- Produces (`class_name AudioRouting extends Node`, autoload `AudioRouting="*res://scripts/audio/audio_routing.gd"`).
  - `const BUS_NAMES: Array[String] = ["Music", "Ambience", "SFX"]`
  - `func ensure_buses() -> void` — for each name: if `AudioServer.get_bus_index(name) == -1`, `AudioServer.add_bus()` then `AudioServer.set_bus_name(AudioServer.bus_count - 1, name)`. New buses default-send to Master. Idempotent (safe to call repeatedly, tests call it again).
  - `func _ready() -> void` — `ensure_buses()`; then `_ensure_wind_bed()` which creates child `AudioStreamPlayer` named `WindBed`, `bus = "Ambience"`, `stream = AudioSynth.noise_loop(88200, 555001, 0.92)` (2 s smooth rumble), `volume_db = -26.0`, `play()`. Guard with `if has_node("WindBed"): return`.
- Consumes: `AudioSynth.noise_loop` (Task 3). **Written note in this task’s doc comment:** music is deferred — the `Music` bus exists and is Master-routed, but no music source is added; ambience is a single always-on quiet wind bed (deliberately not per-scene to keep scope tight).

- [ ] 6.1 Add tests (autoload is already registered as *not yet existing*, so references to `AudioRouting` parse-fail today): `test_audio_buses_exist` (`AudioServer.get_bus_index` of `Master` >= 0 and `Music`/`Ambience`/`SFX` >= 0), `test_ensure_buses_is_idempotent` (record `AudioServer.bus_count`, call `AudioRouting.ensure_buses()`, count unchanged), `test_wind_bed_playing_on_ambience_bus` (`get_node_or_null("WindBed") as AudioStreamPlayer` not null, `.bus == "Ambience"`, `.stream is AudioStreamWAV`, `.playing == true`).
- [ ] 6.2 Run suite → FAIL (load error: `AudioRouting` autoload unresolved).
- [ ] 6.3 Add the autoload entry to `project.godot` under `[autoload]` (append after `SceneTransition`) and create `audio_routing.gd` per the interface. `get_bus_index` may legitimately return `-1` on the first frame before `_ready` — `_ready` guarantees creation, tests run post-ready.
- [ ] 6.4 Run suite → PASS. Probe → zero errors. Also confirm `settings_menu.gd` `Master` bus path still works (unchanged; suite covers it indirectly).
- [ ] 6.5 `git add scripts/audio/audio_routing.gd project.godot tests/test_audio_routing.gd && git commit -m "audio: AudioRouting autoload ensures Music/Ambience/SFX buses + global WindBed (defer music)"`

---

## Task 7 — Wire `SkidPlayer` + `WindPlayer` into `CarAudio` (C8 audible)

**Files:** `scripts/vehicle/car_audio.gd`, `tests/test_car_audio.gd` (add tests)

**Interfaces:**
- Consumes: `AudioSynth.noise_loop` (Task 3), `skid_intensity`/`wind_volume_db`/`wind_pitch` (Task 4), `SFX` bus (Task 6), existing `_car.get_steer_angle()`/`InputManager.is_handbrake()`/`InputManager.get_throttle()`.
- Produces (members + `_ready`/`_physics_process` additions; engine loop untouched):
  - `const SKID_SAMPLES: int = 17640` (0.4 s), `const SKID_SEED: int = 20260913`, `const WIND_SAMPLES: int = 44100`, `const WIND_SEED: int = 19830211`
  - `var _skid_player: AudioStreamPlayer3D = null`, `var _wind_player: AudioStreamPlayer3D = null`
  - In `_ready` after the engine stream is set: build each child — `AudioStreamPlayer3D.new()`, `name = "SkidPlayer"` / `"WindPlayer"`, `stream = AudioSynth.noise_loop(SKID_SAMPLES, SKID_SEED, 0.0)` / `AudioSynth.noise_loop(WIND_SAMPLES, WIND_SEED, 0.9)`, `unit_size = 2.0`, `max_distance = 60.0`, `bus = "SFX"`, `add_child(...)`, `play()`.
  - In `_physics_process` after the existing engine block (reusing already-declared `rpm`, `redline`, `speed_kmh` vars, with null guards):
    - `var slip: float = skid_intensity(_car.get_steer_angle(), speed_kmh, InputManager.is_handbrake())` → `_skid_player.volume_db = lerpf(-48.0, -8.0, slip)`, `_skid_player.pitch_scale = lerpf(1.0, 1.5, slip)`
    - `var throttle: float = InputManager.get_throttle()` → `_wind_player.volume_db = wind_volume_db(speed_kmh, throttle)`, `_wind_player.pitch_scale = wind_pitch(speed_kmh, rpm, redline)`
  - No changes to the engine pitch/volume lines — byte-compatible.

- [ ] 7.1 Add test `test_ready_builds_aux_players` (scene-free tree probe): `var holder := auto_free(Node.new())`, `var audio := auto_free(CarAudio.new())`, `holder.add_child(audio)`, `get_tree().root.add_child(holder)`; assert `audio.get_node_or_null("SkidPlayer")` and `"WindPlayer"` are non-null `AudioStreamPlayer3D`, have non-null `stream`, `bus == "SFX"`, and `playing == true`. (`_physics_process` is safe: parent is a plain `Node`, so `_car` stays null and the function returns early each frame.) Also add `test_skid_and_wind_players_use_seeded_streams` asserting both streams are `AudioStreamWAV` (locked-synth guarantee).
- [ ] 7.2 Run suite → FAIL (`get_node_or_null("SkidPlayer")` is null).
- [ ] 7.3 Implement members + `_ready`/`_physics_process` additions per interface.
- [ ] 7.4 Run suite → PASS. Probe → zero errors.
- [ ] 7.5 `git add scripts/vehicle/car_audio.gd tests/test_car_audio.gd && git commit -m "audio: runtime skid + wind/exhaust layers on SFX bus (C8)"; game is no longer silent.`

---

## Final Verification (gate)

- [ ] F.1 `git status --short` — only intended files; no `*.uid` staged.
- [ ] F.2 Headless import probe (verbatim command above) → zero `SCRIPT ERROR`/`Parse Error`/`Failed to load`.
- [ ] F.3 GDUnit suite (verbatim command above) → `Overall Summary: ~94 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 16 orphans` (baseline 69 grew by the ~25 new tests; 0/0/0 is the hard gate; record the exact number from the run).
- [ ] F.4 Manual smoke intent (documented, not automated): driving the player car now yields engine loop + slip-driven skid hiss + speed/throttle-driven wind/exhaust whoosh; `WindBed` audible at −26 dB; all buses visible in the audio debugger.

---

## Self-Review: inventory → task mapping + placeholder scan

| Inventory item | Delivered by | Evidence |
|---|---|---|
| C8 — game no longer silent (synth-only, no binary assets) | Tasks 3, 4, 6, 7 | `AudioSynth.noise_loop` (Task 3), skid/wind mapping (Task 4), `WindBed` + buses (Task 6), `SkidPlayer`/`WindPlayer` wiring (Task 7); all PCM is code-generated, seeded `RandomNumberGenerator` |
| A10 — stale `engine_loop.*` probe | Task 5 | `ASSET_CANDIDATES` (4 dead paths) removed; single explicit `ENGINE_LOOP_OVERRIDE` + fallback test; synth-only intent documented at the probe site |
| D7 — CarAudio tests, incl. seeded-loop determinism | Tasks 1, 2, 3, 4, 5, 6, 7 | mapping statics (T1), determinism + profile + WAV-property locks (T2), synth determinism (T3), behavior statics (T4), probe lock (T5), bus/ambience (T6), aux-player wiring (T7); determinism proven by same-seed → identical `data.hash()` |
| Byte-compat engine loop | Tasks 1, 2 | statics reproduce current lines 85-91 formulae exactly; engine tests unchanged and green; no `VehiclePhysics`/`get_drive_info` edits (slip is a documented `CarAudio` proxy) |
| Deferred | Task 6 note | menu music (bus wired, no source) and per-scene ambience — explicitly written as deferred in the plan and in `audio_routing.gd` |

**Placeholder scan:** verified none — every task has concrete file paths, exact typed signatures, real values (`-8.0`/`0.0` dB endpoints, `SKID_SEED=20260913`, `WIND_BED_SEED=555001`, `AudioSynth.noise_loop(88200, 555001, 0.92)`), and one-action checkbox steps; the only intentionally open number is the final `~94` suite count, which the gate records from the real run.