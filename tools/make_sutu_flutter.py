#!/usr/bin/env python3
# tools/make_sutu_flutter.py
#
# Build the R35 wastegate/overrun flutter one-shot from the user-supplied
# real recording `sututututch.mp3` (project root) -- the classic low-mid
# "stustu/sututututch" pop-rattle that follows a lift or gear change on a
# tuned turbo car. This REPLACES the synthesized flutter cracker
# (`flutter_hits.wav`), which was a pitched 1.7/2.6 kHz tchet; the real
# recording is a continuous sub-1.6 kHz pop texture, which is what a WRX/STI
# really sounds like on the overrun.
#
# Pipeline (deterministic):
#   1. Decode sututututch.mp3 -> 48000 Hz mono 16-bit PCM (ffmpeg, imageio-
#      ffmpeg wheel).
#   2. Scan 20 ms frames for zero-crossing rate + level and pick the 0.9 s
#      window with the densest, most articulated pop content (the recording is
#      flat across its 18.3 s; the densest phrase sits around t = 13.2 s).
#   3. Ramp attack (5 ms) and fade the tail (40 ms) so the one-shot fires and
#      ends without clicks.
#   4. Gain-stage to the previous synthetic flutter's level (rms ~= 0.12,
#      peak ~= 0.9) so EngineAudio's `flutter_gain_db(boost)` keeps working.
#   5. Write assets/audio/engine/gtr/flutter_hits.wav as a looped one-shot:
#      LOOP_OFF with loop_end == 0 -- the contract test_turbo_audio.gd and
#      EngineAudio's _update_turbo() expect (played via one-shot .play() on
#      the gear-change edge).
#
# This script does NOT regenerate turbo_whine.wav (that comes from
# tools/make_wrx_turbo_loop.py) and does NOT touch bov_tail.wav (still
# synthesized by tools/make_gtr_turbo.py).
#
# Run:  py tools\\make_sutu_flutter.py

import math
import struct
import subprocess
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC_MP3 = ROOT / "sututututch.mp3"
OUT = ROOT / "assets" / "audio" / "engine" / "gtr" / "flutter_hits.wav"

SAMPLE_RATE = 48000
CUT_S = 0.9
ATTACK_S = 0.005
RELEASE_S = 0.04
TARGET_RMS = 0.12
PEAK_CAP = 0.9

TMP_WAV = ROOT / "reports" / "sutu_decode.wav"


def decode_mp3():
    try:
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        ff = None
    TMP_WAV.parent.mkdir(parents=True, exist_ok=True)
    if ff is not None:
        r = subprocess.run(
            [ff, "-y", "-hide_banner", "-loglevel", "error", "-i", str(SRC_MP3),
             "-ac", "1", "-ar", str(SAMPLE_RATE), str(TMP_WAV)],
            capture_output=True, text=True)
        if r.returncode != 0 or not TMP_WAV.exists():
            raise SystemExit("ffmpeg decode failed: %s" % (r.stderr or r.stdout))
    elif not TMP_WAV.exists():
        raise SystemExit("sututututch.mp3 needs ffmpeg (pip install imageio-ffmpeg)")
    with wave.open(str(TMP_WAV), "rb") as w:
        if (w.getnchannels(), w.getsampwidth(), w.getframerate()) != (1, 2, SAMPLE_RATE):
            raise SystemExit("tmp decode not 48k mono s16")
        d = w.readframes(w.getnframes())
    return np.frombuffer(d, dtype="<i2").astype(np.float64) / 32767.0


def pick_window(x):
    frm = int(0.02 * SAMPLE_RATE)
    zcr = []
    rms = []
    for s in range(0, len(x) - frm, frm):
        seg = x[s:s + frm]
        z = float((np.abs(np.diff(np.sign(seg))) > 0).sum()) / frm
        zcr.append(z)
        rms.append(math.sqrt(np.mean(seg * seg)))
    zcr = np.array(zcr)
    rms = np.array(rms)
    t_hop = 0.02
    W = int(round(CUT_S / t_hop))
    best = (0.0, 0, 0.0, 0.0)
    for i in range(len(zcr) - W):
        z = float(zcr[i:i + W].mean())
        r = float(rms[i:i + W].mean())
        score = z * 1000.0 + min(r, 0.4) * 10.0
        if score > best[0]:
            best = (score, i * 20, z, r)
    return best, W * 20


def write_wav(path, y):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        frames = bytearray(len(y) * 2)
        for i in range(len(y)):
            struct.pack_into("<h", frames, i * 2, int(y[i] * 32767.0))
        w.writeframes(bytes(frames))


def verify(path):
    with wave.open(str(path), "rb") as w:
        ch = w.getnchannels()
        sw = w.getsampwidth()
        rate = w.getframerate()
        d = w.readframes(w.getnframes())
    s = np.frombuffer(d, dtype="<i2").astype(np.float64) / 32767.0
    dur = len(s) / float(rate)
    peak = float(np.max(np.abs(s)))
    ok = (ch == 1 and sw == 2 and rate == SAMPLE_RATE and dur > 0.02
          and 0.01 < peak <= 1.0)
    print("  %-18s ch%d sw%d rate%d dur=%.4fs peak=%.3f rms=%.4f %s"
          % (path.name, ch, sw, rate, dur, peak, math.sqrt(np.mean(s * s)),
             "OK" if ok else "FAIL"))
    return ok


def main():
    if not SRC_MP3.exists():
        raise SystemExit("missing %s" % SRC_MP3)
    x = decode_mp3()
    print("decoded sututututch.mp3 -> %.3fs mono %d Hz (rms=%.4f peak=%.3f)"
          % (len(x) / SAMPLE_RATE, SAMPLE_RATE, math.sqrt(np.mean(x * x)),
             np.max(np.abs(x))))

    (score, start_ms, z, r), cut_len_s = pick_window(x)
    cut_s = start_ms / 1000.0
    print("selected 0.9s window start=%.2fs (flutter score=%.1f zcr=%.2f rms=%.3f)"
          % (cut_s, score, z, r))

    seg = x[int(cut_s * SAMPLE_RATE):int((cut_s + CUT_S) * SAMPLE_RATE)]
    a = int(ATTACK_S * SAMPLE_RATE)
    for i in range(a):
        seg[i] *= float(i) / a
    rel = int(RELEASE_S * SAMPLE_RATE)
    for i in range(rel):
        seg[-(i + 1)] *= float(i) / rel

    rms = math.sqrt(np.mean(seg * seg))
    scale = TARGET_RMS / rms
    if scale * np.max(np.abs(seg)) > PEAK_CAP:
        scale = PEAK_CAP / np.max(np.abs(seg))
    y = np.clip(seg * scale, -32767.0 / 32768.0, 32767.0 / 32768.0)
    write_wav(OUT, y)
    print("gain=%.3f wrote %s" % (scale, OUT))
    ok = verify(OUT)
    TMP_WAV.unlink(missing_ok=True)
    print("done" if ok else "FAILURE: flutter_hits.wav failed sanity")
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()