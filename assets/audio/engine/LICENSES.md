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

## GT-R twin-turbo V6 bed set (`gtr/`, `tools/make_gtr_beds.py`)

Hand-synthesized in-repo for the VR38DETT 3.8 L V6 twin-turbo (Nissan GT-R
R35). Not an enginesound derivative — generated by `tools/make_gtr_beds.py`
(pure Python stdlib: `wave` + `math` + `random`, no external audio tools or
samples), so it carries only this project's own license. The recipe per bed:

- **V6 firing geometry**: exhaust pulse rate = 6 cylinders / 4-stroke = 1.5 ×
  crank RPM (i.e. `rpm / 40` order), split across six per-bank firings with
  ±6° firing-order stagger (the lumpy VR38 idle burble), each pulse carrying
  an exhaust-pipe formant peak (L-bank 6.4×, R-bank 7.1× the firing frequency)
  and a short Gaussian envelope.
- **Growl stack**: 1×/3×/5× harmonics with a 4× notch for the characteristic
  V6 mid-band growl, plus a 0.5×–3× sub-octave body-rumble harmonic series.
- **Twin-turbo whine**: two stable tones at 12.5× and 12.9× firing frequency
  plus a widened band-limited suction hiss that gets broadband with RPM.
- **Seamlessness**: the loop length is forced to an EVEN number of engine
  cycles so half-order (0.5×/1.5×/…) phasing lands phase-coherent at the wrap,
  and the exhaust burst noise is pre-drawn per cycle so it replays identically
  (a continuously-advancing noise stream breaks the seam).
- Two-pass gain staging reseals every rung to a target RMS (0.115 idle →
  0.152 max) with a hard 0.95 peak cap — quieter flat than the V10, so the
  on-throttle +6 dB load lift reads as a genuine turbo boost build.

Bed RPM ladder mirrors the R35's 7000 RPM redline (span `Vector2(800, 7000)`,
pitch clamp window `(0.45, 1.5)`, master trim −2.0 dB):

| File | Line (RPM) | Loop |
| --- | --- | --- |
| `gtr/engine_idle.wav` | 800 | seamless |
| `gtr/engine_low.wav` | 1800 | seamless |
| `gtr/engine_mid.wav` | 3200 | seamless |
| `gtr/engine_high.wav` | 4800 | seamless |
| `gtr/engine_max.wav` | 6800 | seamless |

Regenerate with `py tools\make_gtr_beds.py`; independent sanity gate in
`tools/check_gtr_beds.py` (format parity vs the muscle reference, duration,
peak, loop-wrap step vs interior step distribution).

The turbo layer on top consists of two in-repo-synthesized one-shots
(`gtr/bov_tail.wav`) generated by `tools/make_gtr_turbo.py` (pure-Python
stdlib pipeline, project-owned license) plus two REAL recorded turbo voices,
each a user-supplied sound processed by a small tool:
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