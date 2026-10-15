#!/usr/bin/env python3
# tools/make_gtr_beds.py
#
# Synthesize the Nissan GT-R R35 VR38DETT (3.8L 60-degree V6 twin-turbo) five
# steady-state loop beds for EngineAudio's per-timbre bed-family system.
#
# The shipped families were authored with enginesound's waveguide model; this
# family is pure-Python additive synthesis of the same character targets:
#   * a 4-stroke V6 firing ladder (one firing every 120 deg crank, banks
#     alternating L-R-L-R-L-R) whose FUNDAMENTAL is the firing rate rpm/20
#     (40 Hz at idle, 340 Hz at 6800 rpm);
#   * a "growl" harmonic stack (strong 1x/3x/5x, notch at 4x) rolled off hard
#     in the low bands (muffled twin-turbo, flat off-boost) and opened toward
#     the top band (hard-edged roar near redline);
#   * per-bank exhaust pulses tuned to pipe formants a few firing-harmonics up,
#     with a small +/-6 deg firing stagger between banks so the idle has the
#     VR38's lumpy burble rather than a metronomic even-fire line;
#   * a sub-octave crank "body" rumble (0.5x..3x of firing rate) that fades as
#     the rpm rises;
#   * a two-tone turbo whine plus a band-limited air/compressor hiss, both nil
#     at idle and ramping hard with band index (boost spool character);
#   * a tanh waveshaper whose drive grows from ~1 (idle) to 2 (max) so the top
#     end gets the hard edge without digital clipping.
#
# EVERY component is periodic across the loop length: the exhaust/hum/body
# pattern repeats each 4-stroke cycle, and the whine/hiss components are forced
# to an integer number of cycles across the whole file. The output is therefore
# seamless under LOOP_FORWARD when the loop spans the entire file -- exactly
# what EngineAudio.load_beds_for() demands (loop_end == frame count).
#
# Output: assets/audio/engine/gtr/engine_{idle,low,mid,high,max}.wav
# 48000 Hz, mono, 16-bit PCM -- identical format to the muscle/rally beds.
# Pure stdlib (wave + math + random), deterministic per band name.
#
# Run:  py tools\\make_gtr_beds.py

import math
import os
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 48000
TWO_PI = 2.0 * math.pi
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio" / "engine" / "gtr"

# (band_name, authored_rpm, hum, pulse, body, whistle, noise, drive, target_rms)
# name matches BAND_ORDER and the filename convention engine_<name>.wav
BANDS = [
    ("idle", 800, 0.52, 0.42, 0.50, 0.008, 0.012, 1.05, 0.115),
    ("low", 1800, 0.55, 0.48, 0.34, 0.050, 0.028, 1.15, 0.125),
    ("mid", 3200, 0.58, 0.55, 0.22, 0.085, 0.050, 1.32, 0.138),
    ("high", 4800, 0.60, 0.60, 0.12, 0.110, 0.075, 1.60, 0.148),
    ("max", 6800, 0.62, 0.65, 0.06, 0.140, 0.100, 2.00, 0.152),
]

# Harmonics of the firing rate that carry the "growl": strong 1x/3x/5x, notch
# at 4x, roll-off beyond.
GROWL = [1.00, 0.55, 0.80, 0.28, 0.52, 0.40]
GROWL_ROLL = 0.88   # per-order decay after the first six
GROWL_OPEN = {      # high-frequency open factor: muffled low bands -> open top
    "idle": 0.42,
    "low": 0.58,
    "mid": 0.76,
    "high": 0.92,
    "max": 1.08,
}
GROWL_MAX_K = {"idle": 20, "low": 24, "mid": 28, "high": 32, "max": 38}

# Sub-octave crank rumble orders (fractions of the firing rate).
BODY_ORDERS = [(0.5, 0.45), (1.0, 1.0), (1.5, 0.60), (2.0, 0.42), (2.5, 0.30), (3.0, 0.20)]

PULSE_TAU = {"idle": 0.100, "low": 0.095, "mid": 0.088, "high": 0.080, "max": 0.070}
PULSE_JITTER_DEG = [0, 5, -4, 3, -6, 2]   # per-bank stagger = lumpy idle burble
FORMANT_K = {"L": 6.4, "R": 7.1}          # pipe formants in firing-rate units
PULSE_HARMONIC_COUNT = 9
PULSE_DECAY = 0.95
PULSE_BURST = 0.035

TURBO_WHINE = (12.5, 12.9)   # compressor whine orders (non-integer => beats vs firing)
NOISE_COMPONENTS = 20
NOISE_BAND = {               # hiss passband widens as boost builds
    "idle": (1600, 4500),
    "low": (2000, 5500),
    "mid": (2400, 7000),
    "high": (2800, 8500),
    "max": (3000, 9500),
}


def synth_band(name, rpm, hum_amp, pulse_amp, body_amp, whistle_amp, noise_amp, drive, target_rms):
    cycle = 120.0 / rpm                # one 4-stroke cycle (720 deg crank)
    f0 = 1.0 / cycle                   # firing frequency (rpm / 20)
    cycles = max(2, int(round(1.6 / cycle)))
    # Body rumble carries half-order components (0.5x, 1.5x, 2.5x of the firing
    # frequency); those are only periodic when the loop spans an EVEN number of
    # engine cycles, so round the cycle count up to even.
    cycles += cycles % 2
    cycle_samples = max(1, int(round(cycle * SAMPLE_RATE)))
    n = cycles * cycle_samples
    duration = n / float(SAMPLE_RATE)

    rng = random.Random("gtr-%s" % name)
    brng = random.Random("gtr-burst-%s" % name)

    # --- growl hum ladder ---
    k_max = GROWL_MAX_K[name]
    openf = GROWL_OPEN[name]
    growl = []
    for k in range(1, k_max + 1):
        a = GROWL[k - 1] if k <= len(GROWL) else GROWL[-1] * GROWL_ROLL ** (k - len(GROWL))
        a *= openf if k > 6 else 1.0
        if k > 10:
            a *= 0.8 ** ((k - 10) // 4)
        growl.append((k, a, rng.random() * TWO_PI))

    body = [(o, wa, rng.random() * TWO_PI) for o, wa in BODY_ORDERS]

    # --- per-bank exhaust pulses ---
    pulses = []
    for i in range(6):
        frac = math.fmod((i * 120.0 + PULSE_JITTER_DEG[i]) / 720.0, 1.0)
        formant_k = FORMANT_K["L" if i % 2 == 0 else "R"]
        weights = []
        phases = []
        for k in range(1, PULSE_HARMONIC_COUNT + 1):
            peak = math.exp(-0.5 * ((k - formant_k) / 1.2) ** 2)
            weights.append((PULSE_DECAY ** k) * peak)
            phases.append(rng.random() * TWO_PI)
        pulses.append((frac, weights, phases))

    # --- turbo air hiss: periodic over the whole loop (integer cycle counts) ---
    noise = []
    lo, hi = NOISE_BAND[name]
    amin = int(math.ceil(lo * duration))
    amax = int(math.floor(hi * duration))
    for _ in range(NOISE_COMPONENTS):
        fc = rng.randint(amin, amax)
        freq = fc / duration
        amp = (0.4 + 0.6 * rng.random()) * noise_amp / math.sqrt(NOISE_COMPONENTS)
        noise.append((freq, amp, rng.random() * TWO_PI))

    # --- turbo whine (integer cycles across the loop) ---
    whines = []
    for order in TURBO_WHINE:
        fc = int(round(order * f0 * duration))
        whines.append((fc / duration, rng.random() * TWO_PI))

    tau = PULSE_TAU[name] * cycle

    # Per-cycle exhaust burst noise. Drawn ONCE per (cycle sample, active pulse)
    # from a dedicated generator, then replayed identically every cycle so the
    # burst layer is periodic over the loop (a continuously-advancing stream
    # would break the seam -- the random value at the wrap differs from the one
    # at the head).
    burst_cycle = [0.0] * cycle_samples
    for ci in range(cycle_samples):
        t = ci / float(SAMPLE_RATE)
        dt = math.fmod(t, cycle)
        total = 0.0
        for frac, weights, phases in pulses:
            ddt = math.fmod(t - frac * cycle, cycle)
            if ddt < 0.0:
                ddt += cycle
            env = math.exp(-math.pi * (ddt / tau) ** 2)
            if env >= 0.001:
                total += env * (brng.random() * 2.0 - 1.0)
        burst_cycle[ci] = PULSE_BURST * total

    raw = [0.0] * n
    for i in range(n):
        t = i / float(SAMPLE_RATE)
        s = 0.0
        for k, a, ph in growl:
            s += a * math.sin(t * TWO_PI * f0 * k + ph)
        s *= hum_amp
        for o, wa, ph in body:
            s += body_amp * wa * math.sin(t * TWO_PI * f0 * o + ph)
        for frac, weights, phases in pulses:
            ddt = math.fmod(t - frac * cycle, cycle)
            if ddt < 0.0:
                ddt += cycle
            env = math.exp(-math.pi * (ddt / tau) ** 2)
            if env < 0.001:
                continue
            carrier = 0.0
            for k in range(PULSE_HARMONIC_COUNT):
                carrier += weights[k] * math.sin(TWO_PI * f0 * (k + 1) * ddt + phases[k])
            s += pulse_amp * env * carrier
        s += burst_cycle[i % cycle_samples]
        for freq, ph in whines:
            s += whistle_amp * math.sin(TWO_PI * freq * t + ph)
        for freq, amp, ph in noise:
            s += amp * math.sin(TWO_PI * freq * t + ph)
        raw[i] = math.tanh(drive * s) / math.tanh(drive)

    # Gain stage: scale so the band meets its target RMS loudness; cap peak so
    # the 16-bit quantization never clips (headroom guard for the tanh edge).
    total = 0.0
    peak = 0.0
    for v in raw:
        total += v * v
        peak = max(peak, abs(v))
    rms_val = math.sqrt(total / n)
    scale = target_rms / rms_val if rms_val > 0.0 else 0.0
    if scale * peak > 0.95:
        scale = 0.95 / peak

    samples = bytearray(n * 2)
    for i in range(n):
        v = int(max(-32767.0, min(32767.0, raw[i] * scale * 32767.0)))
        struct.pack_into("<h", samples, i * 2, v)
    return bytes(samples), duration


def write_wav(path, samples, duration):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(samples)


def rms(samples):
    if not samples:
        return 0.0
    total = 0.0
    for i in range(0, len(samples), 2):
        v = struct.unpack_from("<h", samples, i)[0] / 32767.0
        total += v * v
    return math.sqrt(total / (len(samples) // 2))


def verify(path):
    with wave.open(str(path), "rb") as w:
        ch = w.getnchannels()
        sw = w.getsampwidth()
        rate = w.getframerate()
        frames = w.getnframes()
        data = w.readframes(frames)
    dur = frames / float(rate)
    peak = 0.0
    for i in range(0, len(data), 2):
        peak = max(peak, abs(struct.unpack_from("<h", data, i)[0] / 32767.0))
    ok = ch == 1 and sw == 2 and rate == SAMPLE_RATE and dur > 1.0 and peak > 0.01 and peak <= 1.0
    return dur, peak, ok, (ch, sw, rate)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("writing %d GTR beds to %s" % (len(BANDS), OUT_DIR))
    ok_all = True
    for name, rpm, hum, pulse, body, whistle, noise, drive, target_rms in BANDS:
        samples, duration = synth_band(name, rpm, hum, pulse, body, whistle, noise, drive, target_rms)
        path = OUT_DIR / ("engine_%s.wav" % name)
        write_wav(path, samples, duration)
        dur, peak, ok, (ch, sw, rate) = verify(path)
        status = "OK" if ok else "FAIL"
        if not ok:
            ok_all = False
        print("  %-6s rpm=%-4d dur=%.4fs ch=%d sw=%d rate=%d peak=%.3f rms=%.4f %s"
              % (name, rpm, dur, ch, sw, rate, peak, rms(samples), status))
    if ok_all:
        print("done: 5/5 beds passed sanity")
    else:
        raise SystemExit("FATAL: one or more beds failed sanity")
    return 0


if __name__ == "__main__":
    main()