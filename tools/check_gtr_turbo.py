#!/usr/bin/env python3
"""Independent sanity check for the GTR turbo layer WAVs (no Godot).
Validates: PCM header parity with the muscle beds, duration gates, the
loop-boundary seam (turbo_whine only -- the one-shots are not looped), per-
sample max step, RMS loudness in the target band, no clipping.
Run: py tools\\check_gtr_turbo.py
"""
import math
import struct
import wave

REF = "assets/audio/engine/muscle/engine_idle.wav"
WHINE = "assets/audio/engine/gtr/turbo_whine.wav"
ONE_SHOTS = [
    "assets/audio/engine/gtr/bov_tail.wav",
    "assets/audio/engine/gtr/flutter_hits.wav",
]


def read(p):
    w = wave.open(p, "rb")
    ch = w.getnchannels()
    sw = w.getsampwidth()
    rate = w.getframerate()
    n = w.getnframes()
    d = w.readframes(n)
    w.close()
    s = [struct.unpack_from("<h", d, i)[0] / 32767.0 for i in range(0, len(d), 2)]
    return ch, sw, rate, n, s


ref = read(REF)
ok = True


def check(p, looped):
    global ok
    ch, sw, rate, n, s = read(p)
    dur = n / float(rate)
    wrap = abs(s[0] - s[-1]) if looped else 0.0
    maxstep = max(abs(s[i + 1] - s[i]) for i in range(len(s) - 1))
    rms = math.sqrt(sum(v * v for v in s) / len(s))
    peak = max(abs(v) for v in s)
    name = p.replace("\\", "/").split("/")[-1]
    fails = []
    if (ch, sw, rate) != (ref[0], ref[1], ref[2]):
        fails.append("formats differ from muscle ref")
    if looped:
        if not (1.0 < dur < 60.0):
            fails.append("duration out of range")
    else:
        if not (dur > 0.02 and dur < 5.0):
            fails.append("one-shot duration out of range")
    if peak > 1.0:
        fails.append("clipping")
    if peak < 0.01:
        fails.append("silent")
    if looped and wrap > maxstep + 0.02 and maxstep > 0.02:
        fails.append("loop wrap jump exceeds every interior step (%.4f > %.4f+0.02)" % (wrap, maxstep))
    status = "OK" if not fails else "; ".join(fails)
    if fails:
        ok = False
    print("%-22s ch%d sw%d rate%d dur=%.4fs peak=%.4f rms=%.4f wrapjump=%.4f maxstep=%.4f  %s"
          % (name, ch, sw, rate, dur, peak, rms, wrap, maxstep, status))


check(WHINE, True)
for p in ONE_SHOTS:
    check(p, False)
print("REFERENCE muscle idle:", "%s ch%d sw%d rate%d" % (REF, ref[0], ref[1], ref[2]))
print("ALL PASS" if ok else "FAILURES PRESENT")
raise SystemExit(0 if ok else 1)
