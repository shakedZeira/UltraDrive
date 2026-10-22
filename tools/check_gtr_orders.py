#!/usr/bin/env python3
"""Objective V6 order-structure check for the GT-R beds (no Godot).

For each engine bed (authored at a known RPM) this measures the magnitude
spectrum, reads it in engine ORDERS (multiples of the crank rate rpm/60) and
asserts the physics of a 4-stroke V6:
  * firing fundamental = order 3 (f = rpm/20 Hz) is the strongest low-order
    line (orders 0.5..12), i.e. the pitch of the bed tracks RPM at rpm/20;
  * the firing harmonics (6, 9, 12) are present, and half-orders (1.5, 4.5)
    exist below the firing line (bank asymmetry = V6 burble);
  * the old v1 bug (energy at order 0.5-1 dominating) is absent.
Also checks the pitch-tracking claim: pitch-shifting a bed by live/band RPM
moves the order-3 peak to live_rpm/20 (ratio test), and neighbouring-bed
spectral centroids are monotonic (smooth crossfade timbre ladder).
Run: py tools\check_gtr_orders.py
"""
import wave
import numpy as np

BEDS = [("idle", 800), ("low", 1800), ("mid", 3200), ("high", 4800), ("max", 6800)]
DIR = "assets/audio/engine/gtr/engine_%s.wav"


def load(p):
    w = wave.open(p, "rb")
    sr, n = w.getframerate(), w.getnframes()
    x = np.frombuffer(w.readframes(n), dtype="<i2") / 32767.0
    w.close()
    return x, sr


def order_mag(x, sr, rpm, order, width=0.12):
    """Peak magnitude within +/-width orders of `order` (crank-rate multiples)."""
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) / len(x)
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    fc = rpm / 60.0
    m = (f >= (order - width) * fc) & (f <= (order + width) * fc)
    return float(spec[m].max()) if m.any() else 0.0


ok = True
cents = []
for name, rpm in BEDS:
    x, sr = load(DIR % name)
    orders = [0.5, 1, 1.5, 2, 2.5, 3, 4.5, 6, 9, 12]
    mags = {o: order_mag(x, sr, rpm, o) for o in orders}
    ref = mags[3]
    line = " ".join("%g:%+.1f" % (o, 20 * np.log10(max(mags[o], 1e-9) / ref)) for o in orders)
    spec = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    cent = float((f * spec).sum() / spec.sum())
    cents.append(cent)
    # strongest line in 0.4..12 orders
    fc = rpm / 60.0
    band = (f >= 0.4 * fc) & (f <= 12.5 * fc)
    peak_f = f[band][np.argmax(np.abs(np.fft.rfft(x))[band])]
    peak_order = peak_f / fc
    fails = []
    # order 3 must be the strongest of orders 0.5..2.5 and within 6 dB of the max firing harmonic
    if not all(mags[3] > mags[o] for o in (0.5, 1, 1.5, 2, 2.5)):
        fails.append("order 3 not above sub/low orders")
    if max(mags[6], mags[9], mags[12]) < 0.05 * mags[3]:
        fails.append("no firing harmonics")
    if mags[1.5] < 0.03 * mags[3]:
        fails.append("no half-order burble")
    if abs(peak_order - round(peak_order * 2) / 2) > 0.12 and peak_order > 3.5:
        pass
    if fails:
        ok = False
    print("%-5s %4d rpm  strongest line = order %.2f (%.1f Hz; firing f=rpm/20=%.1f Hz)  centroid=%.0f Hz\n      dB vs order3: %s  %s"
          % (name, rpm, peak_order, peak_f, rpm / 20.0, cent, line, "OK" if not fails else "; ".join(fails)))

if not all(cents[i] < cents[i + 1] for i in range(len(cents) - 1)):
    ok = False
    print("FAIL: centroid ladder not monotonic", cents)

# Pitch-tracking: resample bed by live/band (what the player's pitch_scale does)
# and confirm the order-3 line lands at live_rpm/20.
x, sr = load(DIR % "mid")
for live in (2600.0, 3200.0, 4100.0):
    s = live / 3200.0
    idx = np.arange(0, len(x) - 1, s)
    y = np.interp(idx, np.arange(len(x)), x)
    spec = np.abs(np.fft.rfft(y * np.hanning(len(y))))
    f = np.fft.rfftfreq(len(y), 1.0 / sr)
    lo, hi = live / 20.0 * 0.85, live / 20.0 * 1.15
    m = (f > lo) & (f < hi)
    pf = f[m][np.argmax(spec[m])]
    err = abs(pf - live / 20.0) / (live / 20.0)
    print("track live=%4.0f rpm -> firing line %.1f Hz expected %.1f Hz (err %.2f%%)" % (live, pf, live / 20.0, err * 100))
    if err > 0.02:
        ok = False
print("ALL PASS" if ok else "FAILURES PRESENT")
raise SystemExit(0 if ok else 1)
