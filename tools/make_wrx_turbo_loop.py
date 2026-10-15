#!/usr/bin/env python3
# tools/make_wrx_turbo_loop.py
#
# Build the R35 turbo-whine loop bed from the user-supplied real recording
# `wrx_turbo.mp3` (project root). The R35 + turbo layer ships this recorded
# WRX/STI turbo spool instead of the fully-synthesised whine -- the user's
# explicit call: "a better turbo sound to use 'wrx_turbo.mp3'".
#
# Pipeline (deterministic):
#   1. Decode wrx_turbo.mp3 -> 48000 Hz mono 16-bit PCM (ffmpeg, via the
#      imageio-ffmpeg wheel the repo already requires for audio tooling).
#   2. Scan 2.0 s windows and pick the flattest, most spectrally-stationary
#      one (lowest envelope std/mean among frames with enough level) -- the
#      file is one long spool with natural surge, so a flat region loops
#      without a repeating "wah".
#   3. Seamless loop: an equal-power crossfade joins the window's tail to its
#      head so LOOP_FORWARD over the whole file is click-free (the wrx master
#      itself has no natural loop point).
#   4. Light RMS flatten (local 80 ms gain clamped 0.6..1.6) so boost-gating
#      reads as a constant sustained spool, then gain-stage to a target RMS
#      with a hard peak cap.
#   5. Write assets/audio/engine/gtr/turbo_whine.wav and sanity-verify it
#      (format parity with the muscle beds, duration, peak, loop-wrap jump).
#
# The whine is still consumed exactly as before: 48 kHz mono s16, seamless
# LOOP_FORWARD, 2.0 s -- EngineAudio.load_turbo_assets() and the
# test_turbo_audio.gd contract are unchanged.
#
# Run:  py tools\\make_wrx_turbo_loop.py
# Depends on the imageio-ffmpeg wheel (pip). Falls back to an existing
# decoded WAV (reports/wrx_decode.wav) if ffmpeg is unavailable.

import math
import struct
import subprocess
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC_MP3 = ROOT / "wrx_turbo.mp3"
OUT = ROOT / "assets" / "audio" / "engine" / "gtr" / "turbo_whine.wav"

SAMPLE_RATE = 48000
LOOP_LENGTH_S = 2.0
CROSSFADE_S = 0.03
FRAME_S = 0.08              # window-flatness analysis frame (5 ms sub-frames)
MIN_FRAME_RMS = 0.035       # windows whose quietest frame falls below this are rejected
FLAT_GAIN_LO = 0.6          # per-block gain clamp (keeps micro-texture, kills surge)
FLAT_GAIN_HI = 1.6
FLAT_WIN_S = 0.02           # block-gain window
FLAT_HOP_S = 0.005
FLAT_SMOOTH_S = 0.05
TARGET_RMS = 0.09
PEAK_CAP = 0.95

TMP_WAV = ROOT / "reports" / "wrx_decode.wav"


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
        raise SystemExit("wrx_turbo.mp3 needs ffmpeg (pip install imageio-ffmpeg); also tried %s" % TMP_WAV)
    with wave.open(str(TMP_WAV), "rb") as w:
        if (w.getnchannels(), w.getsampwidth(), w.getframerate()) != (1, 2, SAMPLE_RATE):
            raise SystemExit("tmp decode not 48k mono s16")
        n = w.getnframes()
        d = w.readframes(n)
    x = np.frombuffer(d, dtype="<i2").astype(np.float64) / 32767.0
    return x


def pick_window(x):
    n = len(x)
    L = int(round(LOOP_LENGTH_S * SAMPLE_RATE))
    hop = int(0.05 * SAMPLE_RATE)
    frm = int(FRAME_S * SAMPLE_RATE)
    best = None
    best_score = 1e18
    for s0 in range(int(0.05 * SAMPLE_RATE), n - L, hop):
        seg = x[s0:s0 + L]
        # per-frame RMS (5 ms) for flatness
        rfrm = int(0.005 * SAMPLE_RATE)
        nf = L // rfrm
        frms = np.array([np.sqrt(np.mean(seg[i * rfrm:(i + 1) * rfrm] ** 2))
                         for i in range(nf)])
        if frms.min() < MIN_FRAME_RMS or frms.mean() < 0.045:
            continue
        flat = float(np.std(frms) / np.mean(frms))
        # spectral stationarity: centroid drift between 8 sub-windows
        w8 = int(L // 8)
        cents = []
        for k in range(8):
            sub = seg[k * w8:(k + 1) * w8]
            P = np.abs(np.fft.rfft(sub * np.hanning(len(sub)))) ** 2
            f = np.fft.rfftfreq(len(sub), 1.0 / SAMPLE_RATE)
            cents.append(float((P * f).sum() / (P.sum() + 1e-9)))
        cdrift = max(cents) - min(cents) + abs(cents[0] - cents[-1]) * 2.0
        score = flat * 100.0 + cdrift / 500.0
        if score < best_score:
            best_score = score
            best = (s0, flat, cdrift, np.mean(frms))
    if best is None:
        raise SystemExit("no window passed the gate; n=%d" % n)
    return best, L


def crossfade_loop(seg):
    X = int(round(CROSSFADE_S * SAMPLE_RATE))
    out = seg.copy()
    # blend the tail into the head so the wrap leads back into the start
    for i in range(X):
        w = (i + 0.5) / X
        ca = math.cos(w * math.pi / 2.0)   # equal-power
        cb = math.sin(w * math.pi / 2.0)
        out[i] = ca * seg[i] + cb * seg[-(X - i)]
    return out


def rms_flat(seg):
    # Collapse the slow spool surge so a constant boost reads as a constant
    # whistle -- EngineAudio's pressure-following gain then needs no extra
    # dynamics ("if the pressure is the same, sound only the whistle").
    # Time-varying loudness: per-block (20 ms) amplitude gains, hop 5 ms,
    # gain envelope smoothed over 50 ms to keep the loop's micro-texture.
    # Measured effect on the wrx source: 50 ms RMS std/mean 0.215 -> 0.029
    # with the wrap head/tail ratio within 5%.
    win = int(FLAT_WIN_S * SAMPLE_RATE)
    hop = int(FLAT_HOP_S * SAMPLE_RATE)
    n = len(seg)
    rms_of_block = []
    pos_of_block = []
    for s in range(0, n - win + 1, hop):
        blk = seg[s:s + win]
        r = math.sqrt(np.mean(blk * blk)) + 1e-9
        rms_of_block.append(TARGET_RMS / r)
        pos_of_block.append(s + win / 2.0)
    g = np.array(rms_of_block, dtype=np.float64)
    k = max(1, int(round(FLAT_SMOOTH_S / FLAT_HOP_S)) | 1)
    g = np.convolve(np.pad(g, (k, k), mode="edge"), np.ones(k) / k, mode="same")[k:-k]
    g = np.clip(g, FLAT_GAIN_LO, FLAT_GAIN_HI)
    gg = np.interp(np.arange(n), np.array(pos_of_block), g,
                   left=float(g[0]), right=float(g[-1]))
    return seg * gg


def gain_stage(x):
    rms = math.sqrt(np.mean(x * x))
    peak = float(np.max(np.abs(x)))
    scale = TARGET_RMS / rms if rms > 0.0 else 0.0
    if scale * peak > PEAK_CAP:
        scale = PEAK_CAP / peak
    y = np.clip(x * scale, -32767.0 / 32768.0, 32767.0 / 32768.0)
    return y, scale


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
        ch = w.getnchannels(); sw = w.getsampwidth(); rate = w.getframerate()
        d = w.readframes(w.getnframes())
    s = np.frombuffer(d, dtype="<i2").astype(np.float64) / 32767.0
    dur = len(s) / float(rate)
    peak = float(np.max(np.abs(s)))
    wrap = abs(s[0] - s[-1])
    maxstep = float(np.max(np.abs(np.diff(s))))
    ok = (ch == 1 and sw == 2 and rate == SAMPLE_RATE and 1.0 < dur < 60.0
          and 0.01 < peak <= 1.0 and wrap <= maxstep + 0.02)
    print("  %-18s ch%d sw%d rate%d dur=%.4fs peak=%.4f rms=%.4f wrapjump=%.5f maxstep=%.4f %s"
          % (path.name, ch, sw, rate, dur, peak, math.sqrt(np.mean(s * s)), wrap, maxstep,
             "OK" if ok else "FAIL"))
    return ok


def main():
    if not SRC_MP3.exists():
        raise SystemExit("missing %s" % SRC_MP3)
    x = decode_mp3()
    print("decoded wrx_turbo.mp3 -> %.3fs mono %d Hz (rms=%.4f peak=%.3f)"
          % (len(x) / SAMPLE_RATE, SAMPLE_RATE, math.sqrt(np.mean(x * x)), np.max(np.abs(x))))

    (start, flat, cdrift, frms_mean), L = pick_window(x)
    seg = x[start:start + L]
    print("selected window start=%.3fs flatness(std/mean)=%.3f centroid_drift=%.0fHz mean_rms=%.3f"
          % (start / SAMPLE_RATE, flat, cdrift, frms_mean))

    loop = rms_flat(seg)          # AGC first: uniform level across the loop
    loop = crossfade_loop(loop)   # then seamless seam at that uniform level
    y, scale = gain_stage(loop)
    write_wav(OUT, y)
    print("rms-flatten applied=%s final_gain=%.3f wrote %s" % (True, scale, OUT))

    ok = verify(OUT)
    TMP_WAV.unlink(missing_ok=True)
    print("done" if ok else "FAILURE: turbo_whine.wav failed sanity")
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()