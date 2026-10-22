#!/usr/bin/env python3
# tools/make_gtr_flutter.py
#
# PROTOTYPE generator for the GT-R R35 lift-off compressor-surge "stu-tu-tu"
# flutter and a noise-based blow-off "pssh". Synthesised from first principles
# (see docs/research/turbo_flutter_sound.md); no recordings are read or bundled.
#
# It writes ONLY to --out (default: <system temp>/ultradrive_flutter). It never
# touches assets/. To install after the by-ear sign-off, run
#   py tools\make_gtr_flutter.py --out assets\audio\engine\gtr
# and see the execution plan in the research doc.
#
# Model (per variant):
#   * turbo speed s(t) = exp(-t / tau_spool)   (spool-down after the lift)
#   * surge-cycle rate f(t) = f_end + (f0 - f_end) * s(t)   -- DECELERATING
#     (f0 ~ 12..18 Hz by boost tier, f_end = 0.40 * f0); pulse times come from
#     integrating f(t), each inter-pulse interval jittered log-normally
#   * pulse k amplitude = a0 * r^k * lognormal jitter   (the trapped pressure
#     is partly dumped by every surge cycle, so each "tu" is weaker)
#   * each pulse = band-limited noise "chuff" through a pipe/intercooler
#     resonance (~0.9 kHz, drifting down) + a damped 110-140 Hz thump
#   * a compressor whistle (4.3 kHz -> ~2 kHz, tracking s(t)) that is DUCKED
#     by each pulse (the wheel stalls, then regrips between pulses)
# Blow-off: noise hiss with a falling spectral tilt and a 1 ms attack.
#
# Pure numpy + stdlib wave. Deterministic (seeded numpy Generator per variant).
#
# Run:  py tools\make_gtr_flutter.py [--out DIR]

import argparse
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 48000
PEAK = 0.85

# name, seed, tier, f0 (Hz, initial pulse rate), duration s, tau_spool s,
# amplitude ratio per pulse r, first-pulse gain, thump Hz, resonance Hz
FLUTTER_VARIANTS = [
    dict(name="flutter_lo_0", seed=101, f0=12.0, dur=0.62, tau=0.45, r=0.90, first=1.0, thump=118.0, res=820.0),
    dict(name="flutter_lo_1", seed=102, f0=13.0, dur=0.70, tau=0.47, r=0.88, first=1.0, thump=126.0, res=900.0),
    dict(name="flutter_mid_0", seed=201, f0=14.5, dur=0.90, tau=0.52, r=0.89, first=1.15, thump=122.0, res=880.0),
    dict(name="flutter_mid_1", seed=202, f0=15.5, dur=0.98, tau=0.55, r=0.91, first=1.15, thump=132.0, res=960.0),
    dict(name="flutter_hi_0", seed=301, f0=17.0, dur=1.20, tau=0.60, r=0.93, first=1.6, thump=114.0, res=1000.0),
    dict(name="flutter_hi_1", seed=302, f0=18.0, dur=1.30, tau=0.64, r=0.94, first=1.6, thump=124.0, res=1060.0),
]
BOV_VARIANTS = [
    dict(name="bov_0", seed=401, dur=0.26, tau_hi=0.035, tau_mid=0.070, tau_lo=0.110, hi=1.0),
    dict(name="bov_1", seed=402, dur=0.32, tau_hi=0.025, tau_mid=0.085, tau_lo=0.140, hi=0.45),
]


def band_noise(rng, n, lo, hi):
    """White noise band-limited to [lo, hi] Hz by an FFT brick wall with a
    raised-cosine skirt (no scipy dependency)."""
    x = rng.standard_normal(n)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    w = np.ones_like(f)
    sk_lo = max(lo * 0.35, 20.0)
    sk_hi = hi * 0.25
    w = np.where(f < lo, 0.5 - 0.5 * np.cos(np.pi * np.clip((f - (lo - sk_lo)) / sk_lo, 0, 1)), w)
    w = np.where(f > hi, 0.5 + 0.5 * np.cos(np.pi * np.clip((f - hi) / sk_hi, 0, 1)), w)
    y = np.fft.irfft(X * w, n)
    return y / (np.sqrt(np.mean(y * y)) + 1e-12)


def resonator(x, fc, q):
    """2nd-order resonant band-pass (RBJ biquad) -- the pipe/intercooler mode.
    fc may be an array (per-sample centre frequency, drifts down with turbo
    speed); coefficients are recomputed in blocks of 64 samples."""
    n = len(x)
    y = np.zeros(n)
    x1 = x2 = y1 = y2 = 0.0
    fc = np.broadcast_to(np.asarray(fc, dtype=float), (n,))
    b0 = b1 = b2 = a1 = a2 = 0.0
    for i in range(n):
        if i % 64 == 0:
            w0 = 2.0 * np.pi * fc[i] / SR
            al = np.sin(w0) / (2.0 * q)
            a0 = 1.0 + al
            b0 = al / a0
            b1 = 0.0
            b2 = -al / a0
            a1 = -2.0 * np.cos(w0) / a0
            a2 = (1.0 - al) / a0
        v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x[i]
        y2, y1 = y1, v
        y[i] = v
    return y


def pulse_env(n, t0, tau_a, tau_d):
    """Sharp-attack exponential pulse envelope starting at sample t0."""
    e = np.zeros(n)
    m = min(n - t0, int(tau_d * 6 * SR))
    if m <= 0:
        return e
    t = np.arange(m) / SR
    e[t0:t0 + m] = (1.0 - np.exp(-t / tau_a)) * np.exp(-t / tau_d)
    return e


def synth_flutter(v):
    rng = np.random.default_rng(v["seed"])
    n = int(v["dur"] * SR)
    t = np.arange(n) / SR
    s = np.exp(-t / v["tau"])                         # turbo speed (norm.)
    f_end = 0.40 * v["f0"]
    rate = f_end + (v["f0"] - f_end) * s              # pulse rate, Hz

    # --- pulse times: integrate the rate, jitter each interval -------------
    times = []
    tt = 0.004 + 0.012 * rng.random()
    while tt < v["dur"] - 0.04:
        times.append(tt)
        r_here = rate[min(int(tt * SR), n - 1)]
        tt += (1.0 / r_here) * float(np.exp(rng.normal(0.0, 0.09)))
    times = np.array(times)

    # --- sources ------------------------------------------------------------
    nz_mid = band_noise(rng, n, 350.0, 2600.0)
    nz_hi = band_noise(rng, n, 1800.0, 6000.0)
    nz_res = resonator(band_noise(rng, n, 200.0, 5000.0), 900.0 * (0.80 + 0.20 * s) * v["res"] / 900.0, 3.0)
    nz_res /= np.sqrt(np.mean(nz_res ** 2)) + 1e-12

    chuff = np.zeros(n)
    thump = np.zeros(n)
    duck = np.zeros(n)
    for k, tk in enumerate(times):
        amp = v["first"] * (v["r"] ** k) * float(np.exp(rng.normal(0.0, 0.22)))
        i0 = int(tk * SR)
        # later pulses are softer AND duller: tau grows slightly, hi band fades
        tau_d = 0.020 + 0.012 * min(k / 8.0, 1.0) * float(np.exp(rng.normal(0.0, 0.15)))
        e = pulse_env(n, i0, 0.0035, tau_d)
        hi_amt = 0.55 * (v["r"] ** (2 * k))
        chuff += amp * e * (0.65 * nz_res + 0.45 * nz_mid + hi_amt * nz_hi)
        th = pulse_env(n, i0, 0.004, 0.024)
        tf = v["thump"] * float(np.exp(rng.normal(0.0, 0.04)))
        thump += 0.9 * amp * th * np.sin(2 * np.pi * tf * (t - tk) * (1.0 - 0.15 * np.clip((t - tk) / 0.04, 0, 1)))
        duck += 0.6 * pulse_env(n, i0, 0.003, 0.030) * min(amp, 1.2)
    duck = np.clip(duck, 0.0, 1.0)

    # --- whistle: tracks turbo speed, ducked by every surge pulse ------------
    fw = 2000.0 + (4300.0 - 2000.0) * s
    ph = 2 * np.pi * np.cumsum(fw) / SR
    wh = 0.8 * np.sin(ph) + 0.35 * np.sin(1.013 * ph + 1.0)
    a_w = 0.16 * (s ** 0.8) * (1.0 - 0.9 * duck)
    a_w *= np.clip(t / 0.020, 0.0, 1.0)               # no click at t=0
    whistle = a_w * wh

    y = chuff + thump + whistle
    # tail fade (60 ms cosine) so it ends without a click
    nf = int(0.06 * SR)
    y[-nf:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, nf))
    y -= np.mean(y)
    y *= PEAK / np.max(np.abs(y))
    return y, times


def synth_bov(v):
    rng = np.random.default_rng(v["seed"])
    n = int(v["dur"] * SR)
    t = np.arange(n) / SR
    atk = 1.0 - np.exp(-t / 0.0008)                   # ~1 ms attack
    hi = band_noise(rng, n, 3500.0, 11000.0) * np.exp(-t / v["tau_hi"]) * v["hi"]
    mid = band_noise(rng, n, 1400.0, 4200.0) * np.exp(-t / v["tau_mid"]) * 0.85
    lo = band_noise(rng, n, 450.0, 1500.0) * np.exp(-t / v["tau_lo"]) * 0.55
    pop = np.sin(2 * np.pi * 135.0 * t) * np.exp(-t / 0.014) * 0.7
    y = atk * (hi + mid + lo + pop)
    nf = int(0.04 * SR)
    y[-nf:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, nf))
    y -= np.mean(y)
    y *= PEAK / np.max(np.abs(y))
    return y


def write_wav(path, y):
    pcm = np.clip(np.round(y * 32767.0), -32767, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path(tempfile.gettempdir()) / "ultradrive_flutter"))
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for v in FLUTTER_VARIANTS:
        y, times = synth_flutter(v)
        write_wav(out / (v["name"] + ".wav"), y)
        print("  %-14s %.2fs pulses=%d peak=%.2f first_ioi=%.0fms last_ioi=%.0fms"
              % (v["name"], len(y) / SR, len(times), np.max(np.abs(y)),
                 1000 * (times[1] - times[0]), 1000 * (times[-1] - times[-2])))
    for v in BOV_VARIANTS:
        y = synth_bov(v)
        write_wav(out / (v["name"] + ".wav"), y)
        print("  %-14s %.2fs peak=%.2f" % (v["name"], len(y) / SR, np.max(np.abs(y))))
    print("wrote to %s" % out)


if __name__ == "__main__":
    main()
