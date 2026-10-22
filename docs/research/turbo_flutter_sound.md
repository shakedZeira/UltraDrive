# GT-R lift-off turbo flutter ("stu-tu-tu") and blow-off: research, diagnosis, design

Status: research + prototype only. No game file, asset or test was modified.
Prototype: `tools/make_gtr_flutter.py` (writes to a scratch folder), objective check
`tools/check_gtr_flutter.py`. Everything is synthesised from first principles; no
recording is read, downloaded or bundled.

## 1. What real flutter is (physics)

1. The driver lifts, the throttle plate snaps shut, the engine stops drawing air
   but the turbine is still spinning and still pushing air into the charge pipe.
   Pressure ratio is high and mass flow is near zero, so the compressor operating
   point crosses the surge line on the map.
2. Flow separates from the blades (aerodynamic stall, not the shaft stopping) and
   air flows backwards out of the compressor. Pipe pressure drops, the blades
   regrip, residual shaft momentum rebuilds pressure, and the cycle repeats until
   the shaft has slowed enough or the throttle/valve opens. Each cycle is one "tu".
3. The cycle is a Helmholtz-type oscillation of compressor + charge pipe +
   intercooler + closed throttle. A small downstream volume gives a fast,
   low-amplitude surge; a large volume gives slow, high-amplitude surge
   (Wikipedia). Mild surge sits near the system Helmholtz frequency, deep surge
   (reverse flow) is slower (reported 3-10 Hz).
4. Consequences used in the design:
   - Pulse train DECELERATES: as turbo speed falls the pressure ratio the
     compressor can sustain falls, so the cycle slows and stops.
   - Each pulse dumps part of the trapped charge, so pulses get weaker
     (geometric amplitude decay) and duller.
   - A tonal compressor whistle exists in the gaps (blade-pass frequency
     proportional to shaft speed), falls in pitch with turbo speed and drops out
     at each stall.
   - Each "tu" has a broadband turbulent chuff shaped by the pipe/intercooler
     resonance, plus a low pressure thump.
5. Vented BOV: dumps pressure to atmosphere before the compressor reaches surge,
   audible as one sharp broadband "pssh" (1-2 ms attack, hiss that gets duller as
   pressure drops, 0.2-0.4 s). No flutter if sized/set correctly. Flutter with a
   BOV fitted means it opened late/too little/too small (GFB; Wikipedia).
6. Recirculating (factory) diverter: dumps back to the inlet, much quieter
   ("whoosh"), but at high boost on a fast lift a stock valve can still be
   overwhelmed: mild flutter, mostly right after a high-boost lift. Aftermarket
   vent-to-atmosphere or sequential valves make the "sututu" louder/more common.
   Intake mods remove silencers and make all of it more audible (motor1, forum).
7. Dependence on lift conditions (design assumptions, see section 6): higher
   boost at lift gives more trapped energy: higher initial rate, more pulses,
   longer event, louder. A fast throttle close is required; a slow lift lets the
   flow decay gradually and gives no flutter. Cabin: pipes are not in the cabin,
   so the thump and low chuff dominate and the whistle is muffled; outside you
   hear the bright chuff and whistle.

## 2. Sources and what each actually supports

| Source | URL | Supports |
|---|---|---|
| Wikipedia, Surge in compressors | https://en.wikipedia.org/wiki/Surge_in_compressors | surge cycles "few to dozens per second"; mild vs deep surge; Helmholtz; small volume = fast low-amp, large = slow high-amp |
| Wikipedia, Blowoff valve | https://en.wikipedia.org/wiki/Blowoff_valve | flutter = surge sound; vent vs recirculate; cyclic loading |
| GFB, "What's in a name?" (compressor surge) | https://gfb.com.au/tech/tech-articles/11-the-truth-about-compressor-surge/ | stall/regrip cycle description; sound comes from the turbo not the BOV; valve too small/late causes it. No numbers |
| Motor1, turbocharger sounds explained | https://www.motor1.com/features/809044/why-turbochargers-make-whooshing-sound/ | flutter = unstable compressor flow after rapid throttle close; vented BOV audible; intake/BOV mods make it louder |
| SAE 2013-01-1886, Instabilities at the low-flow range of a turbocharger compressor | https://saemobilus.sae.org/content/2013-01-1886 | mild surge frequency set by up/downstream ducting geometry, near system Helmholtz resonance, well below 100 Hz (from abstract snippet) |
| Loughborough thesis, air induction noise during turbocharger surge (petrol) | https://repository.lboro.ac.uk/articles/Air_induction_noise_investigation_during_turbocharger_surge_events_in_petrol_engines/9219035/files/16795913.pdf | a surge noise component near 3250 Hz in STFT (search snippet only: the PDF returned HTTP 403) |
| Owner forums (srtforums, dsmtuners, bimmerpost) | https://www.srtforums.com/threads/turbo-flutter-compressor-surge-wtf.240327/ | anecdotal: "tsu tsu tsu", factory diverter is a whoosh not flutter |
| Vendor pages for R35 valves (Turbosmart, GReddy FV2, HKS SQV4) | https://turbosmart.com/products/dual-port-smart-port-nissan-gt-r-r35-kit | the R35 has one factory recirculation valve per turbo; marketing only |

NOT found in any source: a measured pulses-per-second figure for road-car lift-off
flutter, a measured spectrum, or R35-specific measured behaviour. The 5-20 Hz band,
deceleration shape, amplitude decay ratios and tier boundaries are DESIGN CHOICES
that agree with the "few to dozens of cycles per second, below 100 Hz" literature
and with the commonly heard "tu-tu-tu" cadence; they are not measurements.

## 3. Objective diagnosis of the current sound

Measured with numpy (`py tools\check_gtr_flutter.py --control`) on
`assets/audio/engine/gtr/flutter_hits.wav` (a 0.9 s cut of the user-supplied
`sututututch.mp3`) and `bov_tail.wav` (`tools/make_gtr_turbo.py`):

| Property | Current flutter_hits.wav | Real surge flutter (target) |
|---|---|---|
| Pulse rate | 29 Hz initial (detector), ~37 Hz by IOI mean (27 ms); 20-24 pulses in 0.9 s | 8-20 Hz, ~6-15 pulses |
| Deceleration | none: 29.2 -> 25.5 Hz | end < 0.75 x start |
| Amplitude decay | none: last third / first third = 1.73 (it gets LOUDER) | <= 0.65 |
| RMS by third | 0.124 / 0.124 / 0.112: flat, then cut by a 40 ms fade | decaying |
| Tail | abruptly cut: last 10 ms = 15 % of peak | clean fade |
| Spectrum | 75 % of energy below 300 Hz, strongest lines 120-126 Hz (engine/background rumble of the source recording, not a turbo thump); centroid ~4 kHz from mp3 hiss | chuff 0.5-2.5 kHz, falling centroid |
| Spectral motion | centroid 3868 -> 3498 Hz (flat); whistle ridge not tracking | centroid and whistle fall with turbo speed |
| Boost dependence | fixed 0.9 s sample at any boost; only gain changes | rate, length, level scale with boost |
| Randomness | identical every time (one file) | varies per event |
| Retrigger | `.play()` on every lift edge, no cooldown, restarts mid-sample | cooldown |

Verdict: it is a fixed-rate rattle (30+ Hz is a buzz/machine gun, not "tu-tu-tu")
with no spool-down, no decay and a 120 Hz rumble that belongs to someone else's
engine. It also plays at the same time as `bov_tail.wav`.

`bov_tail.wav` (0.13 s): seven sine partials sweeping 4.2 -> 1.4 kHz. Spectral
flatness 0.000 (pure tone lines, peaks at 3.1-3.4 kHz), -20 dB at 23 ms: it is a
tonal chirp, not turbulent air. This is probably part of why the lift-off sounds
synthetic even though the user likes the rest; replacement noise-based variants
are included (bov_0 sharp/vented, bov_1 soft/recirculating) but it is the user's
call whether to touch it.

Gate summary on the control: flutter_hits fails 7 of 11 gates (rate, deceleration,
IOI jitter too chaotic at 0.30, amplitude growth, flat centroid, no whistle slide,
abrupt tail); bov_tail fails 1 of 5 (tonal, flatness 0.000). 8 failed gates total.

## 4. Chosen synthesis (tools/make_gtr_flutter.py)

Per variant: turbo speed s(t)=exp(-t/tau_spool); pulse rate f(t)=0.4 f0 + 0.6 f0 s(t);
pulse times from integrating f, each interval multiplied by a log-normal jitter
(sigma 0.09); pulse amplitude a0 * r^k * log-normal(sigma 0.22); pulse = chuff
(noise through a 3-Q resonator at 820-1060 Hz drifting down to 80 % + 350-2600 Hz
noise + a hi band that fades quickly), plus a 114-132 Hz damped thump (tau 24 ms,
frequency glide -15 %); whistle 4300 -> 2000 Hz tracking s(t), two slightly
detuned partials, ducked 90 % by each pulse; 60 ms cosine tail; normalised to peak 0.85.

| File | dur | f0 Hz | tau_spool | r | pulses | rate start -> end | amp last/first third |
|---|---|---|---|---|---|---|---|
| flutter_lo_0 | 0.62 s | 12.0 | 0.45 | 0.90 | 6 | 11.8 -> 7.8 | 0.42 |
| flutter_lo_1 | 0.70 | 13.0 | 0.47 | 0.88 | 7 | 10.6 -> 7.9 | 0.63 |
| flutter_mid_0 | 0.90 | 14.5 | 0.52 | 0.89 | 9 | 14.4 -> 8.8 | 0.54 |
| flutter_mid_1 | 0.98 | 15.5 | 0.55 | 0.91 | 11 | 14.8 -> 9.0 | 0.53 |
| flutter_hi_0 | 1.20 | 17.0 | 0.60 | 0.93 | 15 | 17.5 -> 8.7 | 0.54 |
| flutter_hi_1 | 1.30 | 18.0 | 0.64 | 0.94 | 15 | 17.0 -> 10.9 | 0.51 |
| bov_0 | 0.26 | vented, sharp (hi band) | | | | | |
| bov_1 | 0.32 | recirculating, soft (hi band x0.45) | | | | | |

The `hi` tier has a 1.6x first pulse (the "blow-off" crack of a hard high-boost
lift) so the flutter itself carries the sharp onset; bov_* are separate.
Detrended IOI jitter in the output measures 0.05-0.18, amplitude jitter 0.22-0.34
(log units). Output is deterministic (identical md5 on re-run).

Checker results (scratch output): 6 flutter x 11 gates + 2 bov x 5 gates, ALL PASS.
Control (current assets): 8 gates fail. The checker measures the audio only
(onset detection, IOI regression, centroid, ridge tracking), not generator
internals.

## 5. What could not be verified (needs the user's ears)

- Whether 8-18 Hz initial rate matches the R35's felt cadence. No measured GT-R
  figure was found; the tiers are adjustable via `f0` and the playback pitch scale.
- Whistle level (-3 to -5 dB re chuff in the 2-6 kHz vs 250-1800 Hz bands) and its
  4.3 -> 2 kHz range relative to the existing `turbo_whine.wav` (peak 4.4 kHz).
  Too prominent a whistle would sound like a siren; lower `a_w` in synth_flutter.
- Chuff timbre ("pipe resonance" 820-1060 Hz) and thump (114-132 Hz): spectral
  design only. Possible failure modes: "farty" (thump too strong), "typewriter"
  (pulses too sharp: raise the attack tau 0.0035), "hissy" (hi band).
- Cabin vs outside. Not implemented per-camera; if the cockpit view needs it the
  executor can attenuate the chuff above 3 kHz with an extra bus effect (do not
  touch `_ensure_lpf`, owned by the music agent).
- Whether stock-GT-R-like behaviour should be rarer than aftermarket. Suggested
  gating: factory valve = only fast lifts above 0.6 boost.
- Loudness balance versus the engine beds; `flutter_gain_db` trim must be set by ear.
- I could not fetch the Loughborough PDF (403); the 3.25 kHz surge noise line is
  from the search snippet only.

## 6. Execution plan (next agent, in order)

Rules: re-read `scripts/audio/engine_audio.gd` fresh before editing, touch only
the turbo flutter/blow-off code (consts ~L124-137, `_create_turbo_players`
~L318, `_update_turbo` ~L376-415, `flutter_gain_db`/`bov_gain_db` ~L1068-1081,
`load_turbo_assets`); never reformat other lines; `_ensure_lpf` is another
agent's. No Godot run until `D:/Temp/claude/d--AI-Projects-UltraDrive/godot.lock`
is free (`mkdir` it, `rmdir` after, shell timeout, `GODOT_EXE_CONSOLE` set).

1. Generate assets: `py tools\make_gtr_flutter.py --out assets\audio\engine\gtr`
   then `py tools\check_gtr_flutter.py assets\audio\engine\gtr` (must print ALL
   PASS; the checker only globs flutter_lo/mid/hi_*.wav and bov_*.wav, so the old
   flutter_hits.wav and bov_tail.wav in that folder are ignored). Let Godot
   import (generates `.wav.import`; do not hand-write them).
2. `engine_audio.gd` consts: add
   `TURBO_FLUTTER_VARIANTS: Dictionary` tier -> Array of paths (lo/mid/hi, two
   each), `TURBO_BOV_VARIANTS: Array[String]` (bov_0, bov_1),
   `TURBO_FLUTTER_COOLDOWN_S := 1.4`, `TURBO_FLUTTER_TIER_EDGES := [0.65, 0.85]`,
   `TURBO_FLUTTER_RATE_SCALE_MIN/MAX := 0.92 / 1.08`, `TURBO_FLUTTER_PITCH_JITTER := 0.03`.
   Keep `TURBO_ASSETS` keys "bov"/"flutter" (point them at bov_0 and
   flutter_mid_0) so the existing 3-player layout and tests keep working.
3. New pure statics (testable): `flutter_tier(boost) -> int` (0/1/2 by edges),
   `pick_variant(count, last, r01) -> int` (never equals `last` when count>1),
   `flutter_pitch_scale(boost, r01) -> float` (lerp 0.92..1.08 by boost, then
   times 1 +/- 0.03*(2r-1)), `flutter_should_fire(prev_throttle, throttle, boost,
   cooldown, has_wastegate) -> bool` (existing lift edge, boost >
   TURBO_FLUTTER_MIN_FRACTION, cooldown <= 0). Rename nothing existing.
   `load_flutter_variants() -> Dictionary` returning {"flutter": [[AudioStreamWAV]
   per tier], "bov": [AudioStreamWAV]}, `loop_mode = LOOP_DISABLED`; missing file
   degrades to empty array (silence), as `load_turbo_assets` does.
4. State + `_update_turbo`: add `_flutter_cooldown`, `_last_flutter_idx`,
   `_last_bov_idx`, a `RandomNumberGenerator`. Decrement cooldown by `delta`
   every call (also when no fire). Replace the BOV and flutter blocks: on fire,
   choose tier from `_prev_boost_fraction`, `pick_variant`, set `stream`,
   `pitch_scale = flutter_pitch_scale(...)`, volume = `flutter_gain_db(boost) +
   extra_trim_db`, `play()`, set cooldown = max(TURBO_FLUTTER_COOLDOWN_S,
   stream length / pitch). Do not call `play()` while `flutter.playing` and
   cooldown > 0. BOV uses the same edge with its own variant pick (vented
   bov_0 for boost > 0.75 else bov_1). Optional but recommended: also fire on
   an analog fast lift (throttle falls by > 0.45 within 0.12 s ending < 0.2)
   by tracking `_throttle_peak` with 0.12 s decay, since the single-frame
   edge `prev > 0.5 and now < 0.15` misses pedal lifts that pass through the
   0.15-0.5 range in more than one frame.
5. Re-level: new files peak 0.85 vs old 0.44 (flutter) so drop
   `TURBO_FLUTTER_TRIM_DB` from 6.0 by about 5.7 dB to start (about 0.3), BOV
   by ear. Update `flutter_gain_db` comment; keep its monotonic/MUTE_FLOOR contract.
6. Tests (gdUnit4, `tests/suites/`): in `test_turbo_audio.gd` extend `TURBO_PATHS`
   with the 8 new files; add tests for `flutter_tier` boundaries and monotonic
   tier with boost, `pick_variant` never repeats / stays in range over 200 draws,
   `flutter_pitch_scale` bounds (0.89..1.11) and monotonic mean, `flutter_should_fire`
   false during cooldown / below min boost / without wastegate / when
   throttle only dips to 0.3, true on a clean lift, `load_flutter_variants`
   returns 2+2+2 flutter and 2 bov streams, every stream `loop_end == 0`, lengths
   ascending by tier and within 0.3-1.5 s, bov length 0.15-0.5 s. Existing
   `test_turbo_wav_files_exist_and_load` and `..._loops_forward_over_whole_file`
   must still pass unchanged.
7. Python gates: add the new files to `ONE_SHOTS` in `tools/check_gtr_turbo.py`;
   run `py tools\check_gtr_flutter.py assets\audio\engine\gtr`.
8. Provenance: update `assets/audio/engine/LICENSES.md` (lines ~175-193): the new
   flutter and bov are synthesised by `tools/make_gtr_flutter.py`; flutter_hits.wav
   (cut from the user-supplied sututututch.mp3) is retired, tools/make_sutu_flutter.py
   marked superseded (leave the file and the mp3 untouched).
9. Run the gate: `GODOT_EXE_CONSOLE='D:\Godot\Godot_v4.7.2-stable_win64_console.exe'`
   `py tools\gdunit_parallel.py ...` (see docs/GDUNIT_GATE.md); confirm real
   test counts, not a "did not export a usable GODOT_EXE_CONSOLE" false green.
10. `graphify update .`; do not commit.
