# Engine audio assets — source & licenses

The engine sound is **synthesized** from a physical acoustic model, not a
short pitched-up sample. Source: **enginesound v1.5.0** CLI
(`enginesound-cli.exe`, MIT licensed), by **DasEtwas** —
https://github.com/DasEtwas/enginesound — loosely based on the paper
"Physically informed car engine sound synthesis for virtual and augmented
environments" (Delle Monache / Rocchesso). MIT License (see
`LICENSE` in [the repo](https://github.com/DasEtwas/enginesound)).

## Why simulated instead of the free Sonniss GDC recordings

The free GDC bundles (archived at archive.org: `gdc-2023-game-audio-bundle`,
`sonniss-gdc-2024-game-audio-bundle-normalized`) contain **pole-position
vehicle "takes"** (start / drive / gearshift / stop sequences) and no clean,
sustained, steadily-held-RPM loop pads for a single car. Slicing such takes
into idle/mid/high beds produces pitch- and load-drift artifacts at the loop
seam and between rungs. An engine simulator gives an **endlessly coherent
same-engine ladder at EXACT RPMs** with native seamless-loop crossfades —
directly addressing the old "chipmunk" complaint (0.85→1.3× pitch-sweep of
short Free previews). Enginesound is MIT and headless, so it was preferred
over AngeTheGreat's engine-sim (GUI only) for reproducibility.

## Engine parameters (this is a 10-cylinder V10)

Config file used verbatim: `example1.esc` from the enginesound repository
(saved locally next to this file as `sports_v10.esc`). Synthesized with:

- `cylinders`: 10 (even-firing V10 geometry in the example preset)
- acoustic **waveguide per cylinder** (exhaust / intake / extractor pipes),
  reflecting `alpha`/`beta` plus `intake_*_refl` / `exhaust_*_refl` as authored
  in the preset
- **intake_noise** (air noise) low-passed; **engine_vibrations** filtered
- **muffler**: straight_pipe + 4 sequential muffler waveguides
- `crankshaft_fluctuation` 0.1426 with its own low-pass
- valve timing shifts `intake_valve_shift -0.061` / `exhaust_valve_shift +0.062`

Recording recipe per rung (README pseudocode, sealed loop):

```
wavelength = 120 / rpm   # one 4-stroke cycle
cycles     = ceil(4.0 / wavelength)
crossfade  = 2 * wavelength
length     = wavelength * cycles + crossfade / 2   → output ≈ 4.00 s seamless loop
warmup     = 3 s (resonance settle)   samplerate 48000   monophonic
```

## Files

| File | Line (RPM) | Loop | Source CLI |
| --- | --- | --- | --- |
| `engine_idle.wav` | 800 | seamless (~4.0 s) | `enginesound-cli -h -c example1.esc -r 800 ...` |
| `engine_low.wav` | 2000 | seamless (~4.0 s) | `... -r 2000 ...` |
| `engine_mid.wav` | 3500 | seamless (~4.0 s) | `... -r 3500 ...` |
| `engine_high.wav` | 5500 | seamless (~4.0 s) | `... -r 5500 ...` |
| `engine_max.wav` | 6900 | seamless (~4.0 s) | `... -r 6900 ...` |

`example1.esc` is licensed under the MIT license of the enginesound repo, so
these derivative WAVs inherit that permissive license (use, copy, modify,
merge, publish, distribute, sublicense).

## Muscle V8 bed set (`muscle/`, `muscle_v8.esc`)

Same enginesound v1.5.0 CLI as the V10, but with a big-bore V8 recipe
(`muscle_v8.esc`, saved next to this file). Derived from the repository's
`example1.esc` structure, re-parameterized for an even-firing 8-cylinder
geometry: exhaust/intake pipe delays lengthened (exhaust ~0.0009–0.00115 s —
the long-pipe rumble), `exhaust_volume 0.70`, and a heavier
`crankshaft_fluctuation 0.11`. Bed RPMs mirror the V8's ~6200 redline:

| File | Line (RPM) | Loop |
| --- | --- | --- |
| `muscle/engine_idle.wav` | 800 | seamless |
| `muscle/engine_low.wav` | 1700 | seamless |
| `muscle/engine_mid.wav` | 3000 | seamless |
| `muscle/engine_high.wav` | 4500 | seamless |
| `muscle/engine_max.wav` | 6000 | seamless |

## Rally turbo-4 bed set (`rally/`, `rally_i4.esc`)

High-rev 4-cylinder recipe (`rally_i4.esc`, saved next to this file), again a
derivative of `example1.esc`: 4 cylinders, short exhaust delays
(~0.00015–0.0002 s — the raspy bark), `intake_volume 0.48`,
`intake_noise_factor 0.42` so turbo suck-through reads, and a light
`crankshaft_fluctuation 0.05`. Bed RPMs climb to the 4-pot's ~8200 redline:

| File | Line (RPM) | Loop |
| --- | --- | --- |
| `rally/engine_idle.wav` | 800 | seamless |
| `rally/engine_low.wav` | 2200 | seamless |
| `rally/engine_mid.wav` | 4000 | seamless |
| `rally/engine_high.wav` | 6000 | seamless |
| `rally/engine_max.wav` | 7900 | seamless |

Both families use the same seamless-loop recipe as the V10 (wavelength =
120/rpm, crossfade = 2×wavelength, resealed to the same RMS loudness and
48 kHz mono 16-bit PCM). Both `muscle_v8.esc` and `rally_i4.esc` are MIT
derivatives of the enginesound repository, so the WAVs inherit that permissive
license. The car's bed set is picked per-car via `CarConfig.engine_bed_set`
(else `engine_timbre`, else the V10 `sport` family) — see `EngineAudio`,
`scripts/audio/engine_audio.gd`.

## GT-R twin-turbo V6 bed set (`gtr/`, `tools/make_gtr_beds.py`) -- v2 order-based model

Hand-synthesized in-repo for the VR38DETT 3.8 L 60-degree V6 twin-turbo
(Nissan GT-R R35). Not an enginesound derivative -- generated by
`tools/make_gtr_beds.py` (numpy additive/time-domain synthesis, no external
audio tools or samples, deterministic seeds), so it carries only this
project's own license. Reference facts used (web research was thin: owner
forums/videos, no measured spectra; physics from first principles): 4-stroke V6
= 6 firings per 720 deg crank = 3 per crank rev, so the firing fundamental is
**order 3, f = rpm/20 Hz** (40 Hz idle ... 340 Hz at 6800 rpm); idle ~800 rpm,
redline 7000; two banks with different pipe lengths; GR6 dual-clutch gearbox
whine; turbo whistle + wastegate flutter + overrun crackle as separate layers.

**v2 change (why the old beds did not sound like the car):** v1 built its
"growl" on `1/cycle` = rpm/120 (the cam rate, order 0.5) and called it the
firing frequency, so the strongest components sat at orders 0.5-1 (inaudible
sub-bass), the V6 firing line was a weak mid harmonic, and the "twin-turbo
whine" was a pair of tones at 12.5x/12.9x that cycle rate (83 Hz at idle, i.e.
not a whistle at all). The doc previously also stated rpm/40; the correct V6
4-stroke firing rate is rpm/20. v2 recipe per bed:

- **Firing events**: 6 per 720 deg at 120 deg spacing, banks alternating L-R.
  Each is an exhaust pressure pulse (0.25 ms attack, exponential decay whose
  width is 0.30-0.34 of the firing period) plus bank-specific fixed-Hz pipe
  resonances (L 92/214/388 Hz, R 108/247/441 Hz) and an rpm-growing
  high-passed bark burst. Bank level offset (R = 0.8) + per-event timing and
  amplitude jitter (5 deg / 20 % at idle shrinking to 0.7 deg / 5 % at max)
  produce the half-orders (1.5 / 4.5) and the lumpy idle burble. Pulses are
  placed circularly over the whole loop so the file is exactly periodic.
- **Crank orders** 0.5 / 1 / 1.5 / 2 / 4.5 at low level (imbalance, cam,
  bank beat) and valvetrain tick noise AM-ed at the firing rate.
- **Muffler / body**: 28 Hz high-pass, 4th-order low-pass that opens with rpm
  (0.9 -> 3.4 kHz), +body emphasis near 140 Hz, tanh edge growing with rpm.
- Gain-staged to RMS 0.115 (idle) -> 0.152 (max), peak cap 0.95.
- The beds contain **no turbo tones** any more (turbo is its own layer).

New support layers, same tool (`gtr/intake_roar.wav`, `gtr/gear_whine.wav`),
mixed by `EngineAudio` only for the gtr bed set and never headless:

- `intake_roar.wav` -- 2.0 s noise loop, induction humps at ~260 / 620 Hz,
  AM at the firing rate of 3500 rpm (175 Hz); pitch = live_rpm/3500 so the
  pulsing tracks the engine; level = throttle x rpm (mute when off throttle).
- `gear_whine.wav` -- 2.0 s GR6 gear-mesh whine: 1 kHz fundamental + 2nd/3rd
  harmonics with +/-7/14 Hz tooth sidebands; pitch = road speed km/h / 90,
  level fades in with speed, louder on throttle than on coast.

Bed RPM ladder mirrors the R35's 7000 RPM redline (span `Vector2(800, 7000)`,
pitch clamp window `(0.45, 1.5)`, master trim -2.0 dB):

| File | Line (RPM) | Loop |
| --- | --- | --- |
| `gtr/engine_idle.wav` | 800 | seamless |
| `gtr/engine_low.wav` | 1800 | seamless |
| `gtr/engine_mid.wav` | 3200 | seamless |
| `gtr/engine_high.wav` | 4800 | seamless |
| `gtr/engine_max.wav` | 6800 | seamless |

Regenerate with `py tools\make_gtr_beds.py`. Gates: `tools/check_gtr_beds.py`
(format parity, duration, peak, loop-wrap step) and `tools/check_gtr_orders.py`
(FFT in engine orders: order 3 = rpm/20 dominant, firing harmonics + half-order
present, centroid ladder monotonic, pitch-shifted firing line lands on
live_rpm/20).

**Turbo whistle stabilization (`tools/make_gtr_turbo_stable.py`)**: the
recorded WRX spool loop drifted ~45 % in spectral centroid across its 2 s
(audible repeating pitch wander). The tool keeps its long-term spectrum
(30 Hz smoothing) but rebuilds the loop with random phases (drift -> ~10 %,
same RMS, still seamless). Run it after `make_wrx_turbo_loop.py`; it is
idempotent. Runtime wobble fix is in `EngineAudio` (smoothed boost state, see
`turbo_boost_step`).

**Turbo flutter + blow-off (current, `tools/make_gtr_flutter.py`)**: the
lift-off "stu-tu-tu" and the blow-off are fully synthesised from first
principles (numpy, project-owned license; no recording is read or bundled):
`gtr/flutter_{lo,mid,hi}_{0,1}.wav` (six decelerating, jitter-timed,
per-pulse-decaying surge pulse trains with a pitch-falling whistle tail and a
noise chuff; 0.6-1.3 s) and `gtr/bov_0.wav` (vented, sharp) / `gtr/bov_1.wav`
(recirculating, soft). Design and sources: `docs/research/turbo_flutter_sound.md`.
Regenerate: `py tools\make_gtr_flutter.py --out assetsudio\engine\gtr`;
gate: `py tools\check_gtr_flutter.py assetsudio\engine\gtr` (ALL PASS).
Played only by the GT-R (the only turbo car) via `EngineAudio.load_flutter_variants()`.
RETIRED (files left on disk, no longer referenced by the game): `gtr/flutter_hits.wav`
(a cut of the user-supplied `sututututch.mp3`; `tools/make_sutu_flutter.py` is
superseded) and `gtr/bov_tail.wav` (tonal chirp from `tools/make_gtr_turbo.py`).

The turbo whistle loop is unchanged. History of the older turbo layer: two
in-repo-synthesized one-shots (`gtr/bov_tail.wav`) generated by
`tools/make_gtr_turbo.py` (pure-Python stdlib pipeline, project-owned license)
plus two REAL recorded turbo voices, each a user-supplied sound processed by a
small tool:
- `gtr/turbo_whine.wav` — a seamless, rms-flattened 2.0 s loop of the
  user-supplied `wrx_turbo.mp3` WRX/STI spool, built by
  `tools/make_wrx_turbo_loop.py` (ffmpeg decode → flattest-window pick →
  equal-power crossfade loop → gain stage).
- `gtr/flutter_hits.wav` — a 0.9 s cut of the user-supplied `sututututch.mp3`
  wastegate/overrun pop-rattle (the classic low-mid "stustu"), picked by the
  densest-pops window scan, built by `tools/make_sutu_flutter.py` (attack 5 ms,
  tail fade 40 ms, level-matched to the old synthetic flutter).

These two replaced the previously synthesized whine and flutter at the user's
request ("a better turbo sound to use 'wrx_turbo.mp3'"; "added a
turbo+blowoff sound … sututututch.mp3"). The BOV one-shot was concurrently
retuned to a real GT-R recording's character (mid 4.2→1.4 kHz "psh").
Regenerate: `py tools\make_gtr_turbo.py`, `py tools\make_wrx_turbo_loop.py`,
`py tools\make_sutu_flutter.py`; sanity gate for all three in
`tools/check_gtr_turbo.py`.

## Usage in game (`EngineAudio`, `scripts/audio/engine_audio.gd`)

- Five crossfaded bands; each is an independent looping `AudioStreamPlayer3D`
  child. `curve_idle/low/mid/high/max` map live RPM onto each band's gain
  (RPM gained from `car.get_drive_info()` / `VehiclePhysics`), so pitch no
  longer sweeps 0.85→1.3 — bands blend at their authored RPMs instead.
- Off-load decay is the same ladder shaped by the load xfade (throttle→weight
  between on- and off-load curves); see `scripts/audio/engine_audio.gd`.