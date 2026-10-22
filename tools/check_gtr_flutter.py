#!/usr/bin/env python3
"""Objective check for the GT-R flutter / blow-off WAVs (no Godot, numpy only).

Measures from the AUDIO (not from the generator's internals) and asserts the
properties that make a surge flutter read as real rather than a machine gun:
  * initial pulse rate 8..20 Hz, final rate < 0.75 x initial (decelerating)
  * inter-pulse-interval jitter present (detrended CV 0.03..0.30)
  * pulse amplitude decays (last third <= 0.65 x first third), with jitter
  * spectral centroid falls over the event; whistle band slides down
  * whistle present (-20..0 dB re the chuff band), tail ends clean, no clipping
  * variants are audibly distinct (different pulse trains)
Blow-off WAVs: 1-2 ms attack, noisy (not tonal) hiss, falling centroid.

Run:  py tools\\check_gtr_flutter.py [DIR]      (default: temp/ultradrive_flutter)
      py tools\\check_gtr_flutter.py --control   (run the same metrics on the
            CURRENT assets/audio/engine/gtr/flutter_hits.wav and bov_tail.wav;
            they are expected to FAIL several gates -- that is the diagnosis)
"""
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SR = 48000


def load(p):
    with wave.open(str(p), "rb") as w:
        assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float) / 32767.0


def bandpass(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, len(x))


def envelope(x, ms):
    k = max(int(ms * 1e-3 * SR), 1)
    return np.sqrt(np.convolve(x * x, np.ones(k) / k, "same"))


def detect_pulses(x):
    """Pulse onsets (s) and amplitudes from the 250..1800 Hz chuff envelope."""
    env = envelope(bandpass(x, 250.0, 1800.0), 4.0)
    d = 24
    e = env[::d]
    t = np.arange(len(e)) * d / SR
    peak = e.max()
    refr = int(0.028 * SR / d)   # 28 ms refractory (caps detectable rate ~35 Hz)
    idx = []
    for i in range(2, len(e) - 2):
        win = e[max(0, i - refr):i + refr + 1]
        if e[i] == win.max() and e[i] > 0.07 * peak:
            # prominence: the trough since the last accepted peak must be < 70 %
            if idx:
                trough = e[idx[-1]:i + 1].min()
                if trough > 0.75 * min(e[idx[-1]], e[i]):
                    if e[i] > e[idx[-1]]:
                        idx[-1] = i
                    continue
            idx.append(i)
    return t[idx], e[idx]


def centroid(x, lo=250.0, hi=8000.0):
    X = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    m = (f >= lo) & (f <= hi)
    return float((X[m] * f[m]).sum() / (X[m].sum() + 1e-12))


def whistle_track(x):
    """Tonal ridge (1.5..6.5 kHz) in 40 ms frames (hop 20 ms): spectrum divided
    by its running median so a broadband noise hump is not mistaken for the
    whistle; only frames with a clear line (ratio > 6) are kept. Returns the
    median ridge frequency of the first and last 40 % of the kept frames."""
    w = int(0.04 * SR)
    pts = []
    for i in range(0, len(x) - w, w // 2):
        s = x[i:i + w]
        X = np.abs(np.fft.rfft(s * np.hanning(w))) + 1e-12
        f = np.fft.rfftfreq(w, 1.0 / SR)
        k = 21
        med = np.median(np.lib.stride_tricks.sliding_window_view(np.pad(X, k // 2, mode="edge"), k), axis=1)
        r = X / med
        m = (f > 1500) & (f < 6500)
        j = int(np.argmax(r[m]))
        if r[m][j] > 6.0:
            pts.append(float(f[m][j]))
    if len(pts) < 5:
        return [0.0, 0.0]
    q = max(int(len(pts) * 0.4), 2)
    return [float(np.median(pts[:q])), float(np.median(pts[-q:]))]


def flatness(x, lo=500.0, hi=8000.0):
    P = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    P = P[(f >= lo) & (f <= hi)] + 1e-18
    # smooth over 40 bins so single noise-line scatter does not dominate
    P = np.convolve(P, np.ones(40) / 40, "valid")
    return float(np.exp(np.mean(np.log(P))) / np.mean(P))


def flutter_metrics(x):
    t, a = detect_pulses(x)
    m = {"n": len(t)}
    if len(t) < 4:
        return m
    ioi = np.diff(t)
    k = max(len(ioi) // 3, 2)
    m["rate0"] = float(1.0 / np.median(ioi[:k]))
    m["rate1"] = float(1.0 / np.median(ioi[-k:]))
    # detrended jitter: residual of log(IOI) around a linear fit vs index
    li = np.log(ioi)
    c = np.polyfit(np.arange(len(li)), li, 1)
    m["cv"] = float(np.std(li - np.polyval(c, np.arange(len(li)))))
    m["slope"] = float(c[0])
    third = max(len(a) // 3, 1)
    m["amp_ratio"] = float(np.mean(a[-third:]) / np.mean(a[:third]))
    la = np.log(a + 1e-9)
    ca = np.polyfit(np.arange(len(la)), la, 1)
    m["amp_jit"] = float(np.std(la - np.polyval(ca, np.arange(len(la)))))
    h = len(x) // 3
    m["cent0"] = centroid(x[:h])
    m["cent1"] = centroid(x[-h:])
    wt = whistle_track(x)
    m["wh0"], m["wh1"] = wt[0], wt[-1]
    m["wh_ok"] = wt[0] > 0
    chuff = np.sqrt(np.mean(bandpass(x, 250, 1800) ** 2))
    whis = np.sqrt(np.mean(bandpass(x, 2000, 6000) ** 2))
    m["wh_db"] = float(20 * np.log10(whis / chuff + 1e-9))
    m["peak"] = float(np.max(np.abs(x)))
    tail = x[-int(0.01 * SR):]
    m["tail"] = float(np.max(np.abs(tail)) / m["peak"])
    m["times"] = t
    m["env"] = envelope(bandpass(x, 250, 1800), 6.0)[::240]
    return m


def gates(m):
    g = []
    n = m["n"]
    g.append(("pulses 5..20", 5 <= n <= 20, n))
    if "rate0" not in m:
        return g
    g.append(("initial rate 8..20 Hz", 8.0 <= m["rate0"] <= 20.0, round(m["rate0"], 1)))
    g.append(("decelerates: end < 0.75 x start", m["rate1"] < 0.75 * m["rate0"],
              "%.1f -> %.1f Hz" % (m["rate0"], m["rate1"])))
    g.append(("IOI jitter 0.03..0.30", 0.03 <= m["cv"] <= 0.30, round(m["cv"], 3)))
    g.append(("amplitude decays <= 0.65", m["amp_ratio"] <= 0.65, round(m["amp_ratio"], 2)))
    g.append(("amplitude jitter >= 0.08", m["amp_jit"] >= 0.08, round(m["amp_jit"], 2)))
    g.append(("centroid falls (end < 0.9 start)", m["cent1"] < 0.9 * m["cent0"],
              "%.0f -> %.0f Hz" % (m["cent0"], m["cent1"])))
    g.append(("whistle slides down (end < 0.8 start)", m["wh_ok"] and m["wh1"] < 0.8 * m["wh0"],
              "%.0f -> %.0f Hz" % (m["wh0"], m["wh1"])))
    g.append(("whistle present, <= 0 dB re chuff", -20.0 <= m["wh_db"] <= 0.0, round(m["wh_db"], 1)))
    g.append(("peak <= 0.95", m["peak"] <= 0.95, round(m["peak"], 2)))
    g.append(("clean tail (<5 % of peak)", m["tail"] < 0.05, round(m["tail"], 3)))
    return g


def bov_gates(x):
    env = envelope(x, 1.0)
    pk = env.max()
    t90 = np.argmax(env >= 0.5 * pk) / SR
    t20 = np.argmax((np.arange(len(env)) > np.argmax(env)) & (env < 0.1 * pk)) / SR
    h = len(x) // 3
    return [
        ("attack to 50 % <= 3 ms", t90 <= 0.003, round(t90 * 1000, 2)),
        ("-20 dB point 30..200 ms", 0.03 <= t20 <= 0.2, round(t20 * 1000, 0)),
        ("noisy not tonal (flatness > 0.02)", flatness(x) > 0.02, round(flatness(x), 3)),
        ("centroid falls (end < 0.9 start)", centroid(x[h:2 * h], 400, 12000) < 0.9 * centroid(x[:h], 400, 12000),
         "%.0f -> %.0f" % (centroid(x[:h], 400, 12000), centroid(x[h:2 * h], 400, 12000))),
        ("peak <= 0.95", float(np.max(np.abs(x))) <= 0.95, round(float(np.max(np.abs(x))), 2)),
    ]


def report(name, gs):
    bad = [x for x in gs if not x[1]]
    print("%-16s %s" % (name, "PASS (%d gates)" % len(gs) if not bad else "FAIL %d/%d" % (len(bad), len(gs))))
    for label, ok, val in gs:
        print("    [%s] %-38s %s" % ("ok" if ok else "XX", label, val))
    return len(bad)


def main():
    args = [a for a in sys.argv[1:]]
    if "--control" in args:
        d = ROOT / "assets" / "audio" / "engine" / "gtr"
        bad = report("CONTROL flutter_hits", gates(flutter_metrics(load(d / "flutter_hits.wav"))))
        bad += report("CONTROL bov_tail", bov_gates(load(d / "bov_tail.wav")))
        print("control failed %d gates (expected: the current sound is the problem)" % bad)
        return 0
    d = Path(args[0]) if args else Path(tempfile.gettempdir()) / "ultradrive_flutter"
    files = sorted(f for t in ("lo", "mid", "hi") for f in d.glob("flutter_%s_*.wav" % t))
    bovs = sorted(d.glob("bov_[0-9]*.wav"))  # bov_tail.wav is the retired tonal chirp (control only)
    if len(files) < 4 or len(bovs) < 1:
        print("need >=4 flutter_*.wav and >=1 bov_*.wav in %s" % d)
        return 2
    fails = 0
    ms = []
    for p in files:
        m = flutter_metrics(load(p))
        ms.append(m)
        fails += report(p.name, gates(m))
    for p in bovs:
        fails += report(p.name, bov_gates(load(p)))
    # variant distinctness (same tier excluded from pulse-count compare)
    for i in range(len(ms)):
        for j in range(i + 1, len(ms)):
            a, b = ms[i], ms[j]
            if "times" not in a or "times" not in b:
                continue
            k = min(len(a["times"]), len(b["times"]), 5)
            dt = float(np.mean(np.abs(a["times"][:k] - b["times"][:k])))
            if dt < 0.004:
                print("  variants %s/%s pulse trains too alike (%.1f ms)" % (files[i].name, files[j].name, dt * 1000))
                fails += 1
    print("ALL PASS" if fails == 0 else "%d FAILED GATES" % fails)
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
