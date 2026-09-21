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

## Usage in game (`EngineAudio`, `scripts/audio/engine_audio.gd`)

- Five crossfaded bands; each is an independent looping `AudioStreamPlayer3D`
  child. `curve_idle/low/mid/high/max` map live RPM onto each band's gain
  (RPM gained from `car.get_drive_info()` / `VehiclePhysics`), so pitch no
  longer sweeps 0.85→1.3 — bands blend at their authored RPMs instead.
- Off-load decay is the same ladder shaped by the load xfade (throttle→weight
  between on- and off-load curves); see `scripts/audio/engine_audio.gd`.