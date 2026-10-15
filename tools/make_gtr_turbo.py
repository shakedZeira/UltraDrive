#!/usr/bin/env python3
# tools/make_gtr_turbo.py
#
# Synthesize the Nissan GT-R R35 turbo audio layer -- the lop-off blow-off
# "psh" one-shot that sits on top of the "gtr" engine beds (make_gtr_beds.py).
# The other two turbo voices are REAL recordings, not synthesis:
#   * turbo_whine.wav  -- tools/make_wrx_turbo_loop.py  (wrx_turbo.mp3 spool)
#   * flutter_hits.wav -- tools/make_sutu_flutter.py    (sututututch.mp3
#                        wastegate/overrun pop-rattle)
# so a synthetic voice can never silently replace a recorded one.
#
#   * bov_tail.wav -- one-shot (~0.13 s) blow-off valve release: exponential
#     env exp(-t/0.030), a residual low sine ~150 Hz at 0.15*env, and 7
#     time-decaying partials each sweeping 4.2 kHz -> 1.4 kHz (a mid "psh",
#     not the old 6.5 kHz top sizzle).
#
# This script does NOT regenerate turbo_whine.wav or flutter_hits.wav.
#
# Format contract (identical to the engine beds): 48000 Hz, mono, 16-bit PCM,
# peak <= 0.95, deterministic random.Random seeds per asset, gain-staged to a
# per-asset target RMS. Pure stdlib (wave + math + random).
#
# Run:  py tools\\make_gtr_turbo.py

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 48000
TWO_PI = 2.0 * math.pi
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio" / "engine" / "gtr"

# --- bov_tail (one-shot) ---
BOV_SEED = "gtr-bov-tail"
BOV_DURATION = 0.13
BOV_TAU = 0.030
BOV_RESIDUAL_HZ = 150.0
BOV_RESIDUAL_GAIN = 0.15
BOV_PARTIALS = 7
BOV_SWEEP_START = 4200.0
BOV_SWEEP_END = 1400.0
BOV_TARGET_RMS = 0.16


def gain_stage(raw, target_rms):
    """Scale to the target RMS and cap the peak so 16-bit never clips."""
    n = len(raw)
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
    return bytes(samples), n / float(SAMPLE_RATE)


def synth_bov():
    n = int(round(BOV_DURATION * SAMPLE_RATE))
    duration = n / float(SAMPLE_RATE)
    rng = random.Random(BOV_SEED)

    # 7 high partials, each a linear frequency sweep with an analytic phase
    # integral (phase = 2*pi*(f0*t + (f1-f0)*t^2/(2T))); higher partials are
    # quieter and decay faster.
    partials = []
    for k in range(BOV_PARTIALS):
        f0 = BOV_SWEEP_START - 375.0 * k
        f1 = BOV_SWEEP_END - 180.0 * k
        amp = 0.55 / ((k + 1) ** 0.8)
        tau = BOV_TAU * (1.0 - 0.35 * k / 7.0)
        partials.append((f0, f1, amp, tau, rng.random() * TWO_PI))

    raw = [0.0] * n
    for i in range(n):
        t = i / float(SAMPLE_RATE)
        env = math.exp(-t / BOV_TAU)
        s = BOV_RESIDUAL_GAIN * env * math.sin(TWO_PI * BOV_RESIDUAL_HZ * t)
        for f0, f1, amp, tau, ph in partials:
            env_k = math.exp(-t / tau)
            phase = TWO_PI * (f0 * t + (f1 - f0) * t * t / (2.0 * duration))
            s += env_k * amp * math.sin(phase + ph)
        raw[i] = s * env ** 0.5
    return gain_stage(raw, BOV_TARGET_RMS)


def rms_of(samples):
    total = 0.0
    for i in range(0, len(samples), 2):
        v = struct.unpack_from("<h", samples, i)[0] / 32767.0
        total += v * v
    return math.sqrt(total / (len(samples) // 2))


def write_wav(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(samples)


def verify(path, min_duration):
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
    ok = (ch == 1 and sw == 2 and rate == SAMPLE_RATE
          and dur > min_duration and peak > 0.01 and peak <= 1.0)
    return dur, peak, ok, (ch, sw, rate)


ASSETS = [
    ("bov_tail.wav", synth_bov, 0.02),
]


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("writing %d GTR turbo one-shot to %s" % (len(ASSETS), OUT_DIR))
    ok_all = True
    for name, synth, min_dur in ASSETS:
        samples, duration = synth()
        path = OUT_DIR / name
        write_wav(path, samples)
        dur, peak, ok, (ch, sw, rate) = verify(path, min_dur)
        status = "OK" if ok else "FAIL"
        if not ok:
            ok_all = False
        print("  %-18s dur=%.4fs ch=%d sw=%d rate=%d peak=%.3f rms=%.4f %s"
              % (name, dur, ch, sw, rate, peak, rms_of(samples), status))
    print("NOTE: turbo_whine.wav  -> `py tools\\make_wrx_turbo_loop.py` (wrx_turbo.mp3);")
    print("      flutter_hits.wav -> `py tools\\make_sutu_flutter.py`  (sututututch.mp3).")
    if ok_all:
        print("done: 1/1 one-shot passed sanity")
    else:
        raise SystemExit("FATAL: one or more turbo one-shots failed sanity")
    return 0


if __name__ == "__main__":
    main()
