#!/usr/bin/env python3
"""Stationarize gtr/turbo_whine.wav so the sustained whistle has NO built-in
pitch/level movement (turbo wobble fix, audio side).

The recorded WRX spool loop (make_wrx_turbo_loop.py) is a snapshot of a real
spool: over its 2 s the spectral centroid drifts ~4.0 -> 5.2 -> 3.6 kHz, which
repeats every loop as an audible pitch wander ("goes up and down"). This tool
keeps the TIMBRE (long-term power spectrum, lightly smoothed) but rebuilds the
loop with random phases, which makes it statistically stationary (no drift)
and still exactly periodic over the file (seamless LOOP_FORWARD).

Idempotent: skipped when the loop is already stationary (centroid drift < 15%).
Run after make_wrx_turbo_loop.py:  py tools\make_gtr_turbo_stable.py
"""
import sys
import wave
from pathlib import Path

import numpy as np

PATH = Path(__file__).resolve().parent.parent / "assets" / "audio" / "engine" / "gtr" / "turbo_whine.wav"
WIN = 4096


def centroid_track(x, sr):
    cents = []
    for i in range(0, len(x) - WIN, WIN // 2):
        seg = x[i:i + WIN] * np.hanning(WIN)
        s = np.abs(np.fft.rfft(seg)) ** 2
        f = np.fft.rfftfreq(WIN, 1.0 / sr)
        cents.append((f * s).sum() / s.sum())
    return np.array(cents)


def drift(x, sr):
    c = centroid_track(x, sr)
    return (c.max() - c.min()) / c.mean()


def main():
    with wave.open(str(PATH), "rb") as w:
        sr, n = w.getframerate(), w.getnframes()
        x = np.frombuffer(w.readframes(n), dtype="<i2") / 32767.0
    d0 = drift(x, sr)
    print("before: centroid drift %.1f%%" % (d0 * 100))
    if d0 < 0.15:
        print("already stationary; nothing to do")
        return
    rms0 = np.sqrt(np.mean(x ** 2))
    spec = np.abs(np.fft.rfft(x))
    k = int(round(30.0 * n / sr))              # ~30 Hz smoothing kernel
    ker = np.hanning(2 * k + 1)
    ker /= ker.sum()
    pw = np.convolve(spec ** 2, ker, mode="same")
    mag = np.sqrt(pw)
    rng = np.random.default_rng(4242)
    ph = np.exp(1j * rng.uniform(0, 2 * np.pi, len(mag)))
    ph[0] = 1.0
    y = np.fft.irfft(mag * ph, n)
    y *= rms0 / np.sqrt(np.mean(y ** 2))
    peak = np.max(np.abs(y))
    if peak > 0.95:
        y *= 0.95 / peak
    d1 = drift(y, sr)
    print("after : centroid drift %.1f%%, rms %.4f, peak %.3f" % (d1 * 100, np.sqrt(np.mean(y ** 2)), np.max(np.abs(y))))
    pcm = np.clip(np.round(y * 32767.0), -32767, 32767).astype("<i2")
    with wave.open(str(PATH), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    sys.exit(main())
