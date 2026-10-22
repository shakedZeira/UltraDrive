#!/usr/bin/env python3
# tools/make_gtr_beds.py  (v2, order-based V6 model)
#
# Synthesize the Nissan GT-R R35 VR38DETT (3.8 L 60-degree V6, twin-turbo)
# five steady-state loop beds for EngineAudio's per-timbre bed-family system,
# PLUS two support layers that EngineAudio mixes by load / road speed:
#   gtr/intake_roar.wav  - throttle-dependent induction roar (AM at firing rate)
#   gtr/gear_whine.wav   - GR6 dual-clutch gear/final-drive whine (pitch = road speed)
#
# v1 bug fixed here: v1 treated 1/cycle (= rpm/120, the CAM rate, order 0.5) as
# the "firing frequency" and stacked its growl harmonics on that, so the
# dominant audible content sat at the wrong orders. v2 is built in engine
# ORDERS (multiples of the crank rate fc = rpm/60):
#   * 4-stroke V6 = 6 firing events per 720 deg = 3 per crank rev, so the
#     firing fundamental is order 3 -> f_fire = 3*fc = rpm/20 Hz
#     (40 Hz @ 800 rpm ... 340 Hz @ 6800 rpm) and it is the dominant tone;
#   * events are placed every 120 deg crank, banks alternating L-R. The two
#     banks have different pipe lengths (different resonance formants and a
#     small level offset) which creates the half-orders 1.5 / 4.5 / 7.5 that
#     give the VR38 its off-beat "burble"; per-event amplitude / timing jitter
#     (larger at idle) gives the lumpy idle yet the loop stays seamless
#     because pulses are placed circularly over the whole file;
#   * each event is a real exhaust PRESSURE PULSE (fast attack, exp decay
#     whose width is a fraction of the firing period) plus bank-specific pipe
#     resonances at FIXED Hz (physical pipe, does not move with rpm) and a
#     short high-passed 'bark' burst that grows with rpm;
#   * small crank-order terms (1, 2) and valvetrain tick noise; muffler
#     low-pass (opens with rpm) and a gentle tanh edge at the top.
# Turbo whistle / BOV / wastegate are NOT in the beds (they are separate
# layers), so the bed no longer carries v1's mistuned 12.5x tonal 'whine'.
#
# Every component is exactly periodic over the file length -> seamless under
# LOOP_FORWARD with loop_end == frame count (EngineAudio.load_beds_for()).
#
# Output: assets/audio/engine/gtr/engine_{idle,low,mid,high,max}.wav
#         assets/audio/engine/gtr/{intake_roar,gear_whine}.wav
# 48000 Hz, mono, 16-bit PCM. Deterministic (seeded). Needs numpy.
#
# Run:  py tools\make_gtr_beds.py

import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 48000
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio" / "engine" / "gtr"

# name, rpm, tau_frac (pulse decay / firing period), jitter_deg, amp_jitter,
#   lp_hz (muffler), bark, tick, drive, target_rms, order_boost
BANDS = [
    ("idle", 800,  0.30, 5.0, 0.20,  900.0, 0.00, 0.010, 1.00, 0.115),
    ("low",  1800, 0.33, 2.6, 0.12, 1250.0, 0.02, 0.015, 1.10, 0.125),
    ("mid",  3200, 0.34, 1.4, 0.08, 1800.0, 0.05, 0.022, 1.22, 0.138),
    ("high", 4800, 0.32, 0.9, 0.06, 2500.0, 0.09, 0.030, 1.45, 0.148),
    ("max",  6800, 0.30, 0.7, 0.05, 3400.0, 0.14, 0.040, 1.80, 0.152),
]

# Pipe resonances (Hz, weight). Physical => fixed in Hz for every bed.
FORMANTS = {
    "L": [(92.0, 1.00), (214.0, 0.55), (388.0, 0.30)],
    "R": [(108.0, 0.88), (247.0, 0.50), (441.0, 0.28)],
}
BANK_LEVEL = {"L": 1.00, "R": 0.80}
FORMANT_GAIN = 0.55
FORMANT_TAU = 0.006


def _cycle_geometry(rpm, min_seconds=2.0):
    """Loop of N whole 4-stroke cycles; N rounded up to even, >= min_seconds."""
    cycle = 120.0 / rpm
    cycles = max(2, int(np.ceil(min_seconds / cycle)))
    cycles += cycles % 2
    n = int(round(cycles * cycle * SAMPLE_RATE))
    return cycle, cycles, n


def _rfft_filter(x, mag_fn):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / SAMPLE_RATE)
    return np.fft.irfft(spec * mag_fn(freqs), len(x))


def _periodic_noise(n, lo, hi, rng, tilt=0.0):
    """Exactly-periodic band-limited noise (random-phase spectrum)."""
    freqs = np.fft.rfftfreq(n, 1.0 / SAMPLE_RATE)
    mag = ((freqs >= lo) & (freqs <= hi)).astype(float)
    if tilt:
        mag *= (np.maximum(freqs, 1.0) / 1000.0) ** tilt
    spec = mag * np.exp(1j * rng.uniform(0, 2 * np.pi, len(freqs)))
    x = np.fft.irfft(spec, n)
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


def synth_band(name, rpm, tau_frac, jitter_deg, amp_jit, lp_hz, bark, tick, drive, target_rms):
    cycle, cycles, n = _cycle_geometry(rpm)
    rng = np.random.default_rng(abs(hash(("gtr2", name))) % (2 ** 32) if False else
                                {"idle": 11, "low": 22, "mid": 33, "high": 44, "max": 55}[name])
    cyc_samples = n / cycles
    t_fire = cycle / 6.0
    tau_d = tau_frac * t_fire
    tau_a = 0.00025

    x = np.zeros(n)
    tail = int(min(0.060, 4.5 * tau_d + 3 * FORMANT_TAU) * SAMPLE_RATE)
    tt = np.arange(tail) / SAMPLE_RATE
    attack = 1.0 - np.exp(-tt / tau_a)
    base_pulse = np.exp(-tt / tau_d) * attack
    ring = {b: sum(w * np.sin(2 * np.pi * f * tt) for f, w in FORMANTS[b]) * np.exp(-tt / FORMANT_TAU)
            for b in ("L", "R")}
    bark_band = None

    for c in range(cycles):
        for e in range(6):
            bank = "L" if e % 2 == 0 else "R"
            deg = e * 120.0 + rng.normal(0.0, jitter_deg)
            pos = (c * 720.0 + deg) / 720.0 * cyc_samples
            amp = BANK_LEVEL[bank] * (1.0 + rng.normal(0.0, amp_jit))
            pulse = base_pulse + FORMANT_GAIN * ring[bank] * (tau_d / (tau_d + 0.004))
            if bark > 0.0:
                burst = rng.normal(0.0, 1.0, tail) * np.exp(-tt / (0.35 * tau_d + 0.0004))
                pulse = pulse + bark * burst
            i0 = int(round(pos))
            idx = (i0 + np.arange(tail)) % n
            np.add.at(x, idx, amp * pulse)

    x -= np.mean(x)

    # Crank-order terms (imbalance 1x / 2x) and the half-order bank beat.
    t = np.arange(n) / SAMPLE_RATE
    fc = rpm / 60.0
    rms_pulse = np.sqrt(np.mean(x ** 2))
    for order, a in ((0.5, 0.020), (1.0, 0.035), (1.5, 0.045), (2.0, 0.030), (4.5, 0.030)):
        x += a * rms_pulse * 6.0 * np.sin(2 * np.pi * fc * order * t + rng.uniform(0, 2 * np.pi)) * (
            1.0 if order >= 1.0 else 1.0)

    # Valvetrain / injector tick noise, amplitude-modulated at the firing rate.
    tick_noise = _periodic_noise(n, 1800.0, 6500.0, rng)
    f_fire = rpm / 20.0
    am = 0.55 + 0.45 * np.cos(2 * np.pi * f_fire * t)
    x += tick * 6.0 * rms_pulse * tick_noise * am

    # Muffler / tailpipe shaping: HP 28 Hz, LP (2nd order) that opens with rpm.
    def mag(f):
        hp = (f / 28.0) ** 2 / (1.0 + (f / 28.0) ** 2)
        lp = 1.0 / (1.0 + (f / lp_hz) ** 4)
        # chest/body emphasis around the V6 'boom'
        body = 1.0 + 0.9 * np.exp(-0.5 * ((f - 140.0) / 70.0) ** 2)
        return hp * lp * body
    x = _rfft_filter(x, mag)

    x = np.tanh(drive * x / (3.0 * np.sqrt(np.mean(x ** 2)))) / np.tanh(drive)
    return _gain_stage(x, target_rms), n / SAMPLE_RATE


def _gain_stage(x, target_rms):
    x = x - np.mean(x)
    r = np.sqrt(np.mean(x ** 2))
    scale = target_rms / r if r > 0 else 0.0
    peak = np.max(np.abs(x)) * scale
    if peak > 0.95:
        scale *= 0.95 / peak
    return x * scale


def synth_intake_roar():
    """Induction roar loop, authored as if the engine were at ROAR_REF_RPM.

    Broadband 120-1400 Hz body with two induction humps, amplitude-modulated
    at the firing rate (so it pulses with the engine when pitch-scaled by
    live_rpm / ROAR_REF_RPM). Exactly periodic over 2.0 s.
    """
    ref_rpm = 3500.0
    n = 2 * SAMPLE_RATE
    rng = np.random.default_rng(77)
    x = _periodic_noise(n, 90.0, 2200.0, rng, tilt=-0.5)

    def mag(f):
        return (1.0 + 1.6 * np.exp(-0.5 * ((f - 260.0) / 90.0) ** 2)
                + 1.0 * np.exp(-0.5 * ((f - 620.0) / 160.0) ** 2)) / (1.0 + (f / 1500.0) ** 4)
    x = _rfft_filter(x, mag)
    t = np.arange(n) / SAMPLE_RATE
    f_fire = ref_rpm / 20.0          # 175 Hz; 350 cycles over 2 s -> periodic
    x *= 0.6 + 0.4 * np.cos(2 * np.pi * f_fire * t + 0.7)
    return _gain_stage(x, 0.14), ref_rpm


def synth_gear_whine():
    """GR6 gear-mesh whine loop at a 1000 Hz reference tone (2.0 s).

    Fundamental + 2nd/3rd gear-mesh harmonics and +/-7/14 Hz sidebands (tooth
    run-out modulation). EngineAudio pitches it with road speed.
    """
    n = 2 * SAMPLE_RATE
    t = np.arange(n) / SAMPLE_RATE
    rng = np.random.default_rng(88)
    x = np.zeros(n)
    for k, a in ((1, 1.0), (2, 0.42), (3, 0.18)):
        f0 = 1000.0 * k
        ph = rng.uniform(0, 2 * np.pi)
        x += a * np.sin(2 * np.pi * f0 * t + ph)
        for sb, sa in ((7, 0.22), (-7, 0.22), (14, 0.08), (-14, 0.08)):
            x += a * sa * np.sin(2 * np.pi * (f0 + sb) * t + rng.uniform(0, 2 * np.pi))
    x += 0.05 * _periodic_noise(n, 700.0, 6000.0, rng)
    return _gain_stage(x, 0.10), 1000.0


def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767.0), -32767, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm.tobytes())
    return pcm


def verify(path):
    with wave.open(str(path), "rb") as w:
        ch, sw, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        data = w.readframes(frames)
    x = np.frombuffer(data, dtype="<i2") / 32767.0
    dur = frames / float(rate)
    peak = float(np.max(np.abs(x)))
    ok = ch == 1 and sw == 2 and rate == SAMPLE_RATE and dur > 1.0 and 0.01 < peak <= 1.0
    return dur, peak, ok, float(np.sqrt(np.mean(x ** 2)))


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("writing GTR beds + layers to %s" % OUT_DIR)
    ok_all = True
    for name, rpm, tau_frac, jit, ajit, lp, bark, tick, drive, trms in BANDS:
        x, _ = synth_band(name, rpm, tau_frac, jit, ajit, lp, bark, tick, drive, trms)
        path = OUT_DIR / ("engine_%s.wav" % name)
        write_wav(path, x)
        dur, peak, ok, r = verify(path)
        ok_all &= ok
        print("  %-10s rpm=%-4d dur=%.4fs peak=%.3f rms=%.4f %s" % (name, rpm, dur, peak, r, "OK" if ok else "FAIL"))
    for fname, (x, ref) in (("intake_roar", synth_intake_roar()), ("gear_whine", synth_gear_whine())):
        path = OUT_DIR / ("%s.wav" % fname)
        write_wav(path, x)
        dur, peak, ok, r = verify(path)
        ok_all &= ok
        print("  %-10s ref=%-6.0f dur=%.4fs peak=%.3f rms=%.4f %s" % (fname, ref, dur, peak, r, "OK" if ok else "FAIL"))
    if not ok_all:
        raise SystemExit("FATAL: one or more beds failed sanity")
    print("done")
    return 0


if __name__ == "__main__":
    main()
