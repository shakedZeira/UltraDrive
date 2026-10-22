#!/usr/bin/env python3
# tools/record_menu_clips.py
#
# Records the three main-menu background clips (plan
# docs/plans/main_menu_video_bg_plan.md, §3B) with Godot's own Movie Writer:
#
#   1. Per shot, launches ONE windowed editor Godot at 1280x720/30 fps running
#      the shot's capture scene (scenes/capture/menu_clip_capture_<shot>.tscn)
#      with --write-movie into reports/menu_clips/<shot>_raw.ogv. The capture
#      scene's recorder (scripts/capture/menu_clip_recorder.gd) prints
#      CAPTURE_READY frame=<r> / CAPTURE_END frame=<e> markers; everything
#      outside them (world bootstrap, terrain bake, suspension settle) is
#      trimmed away here.
#   2. ffmpeg (via the imageio-ffmpeg wheel the repo already requires) trims
#      the raw to the marker window, strips the always-present stereo Vorbis
#      track (-an; MovieWriterOGV has no silent mode) and STREAM-COPIES the
#      Theora into assets/videos/<clip>.ogv — the exact paths
#      MenuVideoPlaylist.CANDIDATE_CLIPS resolves.
#
#      WHY STREAM COPY AND NOT A RE-ENCODE (measured 2026-10-16 — do not
#      "simplify" this back to `-c:v libtheora`): every Theora ENCODE this
#      wheel can produce is undecodable. `ffmpeg -ss 1.033 -t 18 -c:v
#      libtheora -q:v 8` exits 0 and writes an 18.00 s file, but decoding it
#      gives exit 69 with hundreds of `error in unpack_block_qpis` lines and
#      stops after 53 frames — exactly the defect the three shipped clips
#      had. The same is true at q:v 5/10, with the native `theora` encoder,
#      with a decode->rawvideo pipe, and with or without `-ss`. Plain
#      `-c:v copy` decodes exit 0 / 0 errors with the full frame count.
#      `-c:v copy` also re-muxes instead of encoding, so it is much faster.
#      The cut is snapped forward to the next keyframe: a stream copy can
#      only start on one, and a non-keyframe `-ss` point makes this ffmpeg
#      write `Duration: N/A` with a broken frame count (a keyframe-aligned
#      `-ss` yields `start: 0.000000` and a correct length).
#   3. After all shots: one --headless --import . so the new .ogv.import files
#      exist and ResourceLoader.exists() turns the menu background on.
#
# Hard requirements (learned the hard way — do not simplify):
#   - EDITOR build only: OGV movie recording is editor-only (GODOT_EXE_CONSOLE
#     from godot_path.bat; never an export template).
#   - 1280x720 needs an override.cfg: the project boots fullscreen 1920x1080
#     ([display] window/size/mode=3) and the Movie Writer prints/locks its
#     resolution BEFORE any scene script runs, so CLI `--windowed --resolution`
#     are ignored (project.godot wins) and forcing the window from the
#     recorder's _ready() is too late — both only leave 1920x1080. An
#     override.cfg at the project root overrides [display] for the run and
#     does work (verified: `recording movie in 1280×720`, mode=0). This tool
#     writes it just before recording and DELETES IT afterwards (a
#     pre-existing one is copied into reports/ first) — it must never be left
#     behind, or normal gameplay would open windowed at 720p. It is not
#     gitignored, so a leftover would also show up as a stray file.
#     The CLI flags are still passed as belt-and-braces (16:9 either way, so
#     no aspect crop).
#   - APPDATA is redirected to an absolute path under reports/menu_clips/ so
#     Godot's user:// (saves, engine logs) lands on the project drive, not C:.
#   - ONE GODOT AT A TIME: this is real-GPU windowed work; never run beside
#     the GDUnit parallel gate (tools/gdunit_parallel.py) or another Godot.
#   - Do not kill a recording with F8/Ctrl+C (can corrupt the container); the
#     recorder quits itself via get_tree().quit(). Ctrl+C here only kills the
#     PYTHON wrapper — the Godot child keeps recording until its countdown.
#
# Usage:
#   py tools\record_menu_clips.py            # all three shots, then import
#   py tools\record_menu_clips.py hub pan    # only the listed shots (no import)
#
# Exit codes: 0 = every requested shot recorded and trimmed; 1 = at least one
# shot failed (raw/log kept in reports/menu_clips/ for inspection).

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPORT_DIR = ROOT / "reports" / "menu_clips"
APPDATA_DIR = REPORT_DIR / "appdata"
CLIP_DIR = ROOT / "assets" / "videos"

# Movie Writer fps (project.godot [editor] movie_writer/fps=30 and the
# --fixed-fps flag agree): marker frames convert to clip seconds at this rate.
FPS = 30.0
# Per-clip size budget the plan set (intro.ogv is ~538 KB/s). Quality is
# decided at RECORD time (project.godot editor/movie_writer/video_quality);
# the trim stream-copies, so it cannot change quality or bitrate.
CLIP_BUDGET_BYTES = 6 * 1024 * 1024

# Stream copy can only cut on a keyframe, and a non-keyframe cut point gives a
# broken container (see the header). MovieWriterOGV places one keyframe every
# `editor/movie_writer/ogv/keyframe_interval` frames (project.godot = 64;
# I-frames were measured at 0,64,128,... in the raws), so the marker start is
# snapped forward to the next multiple of this before cutting.
KEYFRAME_INTERVAL = 64

# The Movie Writer's resolution follows the window, which the project pins to
# 1920x1080 fullscreen (project.godot [display] window/size/mode=3). A
# transient override.cfg at the project root is the only lever that changes it
# — see the header note. It is written before recording and restored after.
OVERRIDE_CFG = ROOT / "override.cfg"
OVERRIDE_BODY = (
    "[display]\n"
    "\n"
    "window/size/mode=0\n"
    "window/size/viewport_width=1280\n"
    "window/size/viewport_height=720\n"
    "window/size/window_width_override=1280\n"
    "window/size/window_height_override=720\n"
)

# shot -> (capture scene filename, tracked clip filename in assets/videos/).
# The clip names MUST match MenuVideoPlaylist.CANDIDATE_CLIPS exactly or the
# menu will silently keep showing the gradient fallback (D6).
SHOTS = {
    "hub": ("menu_clip_capture_hub.tscn", "menu_drive_hub.ogv"),
    "pass": ("menu_clip_capture_pass.tscn", "menu_drive_pass.ogv"),
    "pan": ("menu_clip_capture_pan.tscn", "menu_pan_vista.ogv"),
}

READY_RE = re.compile(r"CAPTURE_READY frame=\s*(\d+)")
END_RE = re.compile(r"CAPTURE_END frame=\s*(\d+)")
ERROR_RE = re.compile(r"CAPTURE_ERROR\s*(.*)")
# "Movie Maker mode enabled, recording movie in 1280×720 @ 30 FPS..." — the
# only in-log proof of the real capture resolution (the 'x' is U+00D7).
MOVIE_SIZE_RE = re.compile(r"recording movie in\s+(\d+)\D+(\d+)")


def resolve_godot_console() -> str:
    """The console-subsystem editor binary via godot_path.bat (verified recipe:
    cmd delayed expansion after `call`, so the bat's endlocal&set survives)."""
    out = subprocess.run(
        ["cmd", "/v:on", "/c", "call godot_path.bat & echo !GODOT_EXE_CONSOLE!"],
        cwd=str(ROOT), capture_output=True, text=True,
    )
    exe = out.stdout.strip().splitlines()[-1].strip() if out.stdout.strip() else ""
    if not exe or not Path(exe).exists():
        raise SystemExit(
            "Could not resolve GODOT_EXE_CONSOLE via godot_path.bat "
            "(stdout=%r stderr=%r). Is Godot 4.7.2 installed?" % (out.stdout, out.stderr)
        )
    return exe


def godot_env() -> dict:
    env = dict(os.environ)
    APPDATA_DIR.mkdir(parents=True, exist_ok=True)
    # Absolute: a relative APPDATA resolves against the child CWD and would
    # silently land user:// somewhere random (AGENTS.md parallel-gate note).
    env["APPDATA"] = str(APPDATA_DIR.resolve())
    return env


# Any override.cfg found before a run is copied here for safety — but it is
# deliberately NOT restored: this tool must leave no override.cfg behind.
# reports/ is gitignored.
_OVERRIDE_BAK = REPORT_DIR / "override.cfg.bak"


def _write_override() -> None:
    """Force a real 1280x720 window for the Movie Writer run (header note)."""
    if OVERRIDE_CFG.exists():
        _OVERRIDE_BAK.write_bytes(OVERRIDE_CFG.read_bytes())
        print("  existing override.cfg copied to %s" % _OVERRIDE_BAK.relative_to(ROOT))
    OVERRIDE_CFG.write_text(OVERRIDE_BODY, encoding="utf-8")


def _restore_override() -> None:
    """Remove the recording-only override.cfg. It is NOT gitignored and would
    otherwise force windowed 720p on every normal launch of the game, so it
    must be gone by the time this tool exits — even on Ctrl+C (main's finally).
    Anything that was there beforehand is preserved in reports/override.cfg.bak."""
    try:
        OVERRIDE_CFG.unlink()
    except FileNotFoundError:
        return
    msg = "  override.cfg removed"
    if _OVERRIDE_BAK.exists():
        msg += " (a pre-existing copy is in %s)" % _OVERRIDE_BAK.relative_to(ROOT)
    print(msg)


def record_shot(godot: str, shot: str, scene_file: str) -> bool:
    """Runs one windowed Movie-Writer session. Returns True on CAPTURE_END."""
    raw = REPORT_DIR / ("%s_raw.ogv" % shot)
    log = REPORT_DIR / ("%s.log" % shot)
    if raw.exists():
        raw.unlink()
    # The whole line MUST be one string, not a list: given a list, Windows
    # subprocess applies list2cmdline() and backslash-escapes the inner quotes
    # around the exe path, so cmd sees `\"D:\Godot\...exe\"` as an executable
    # name and dies with "'\"...\"' is not recognized". With a string the
    # command line is passed through verbatim and cmd's own /c quote handling
    # (strip first+last quote, since `&` is a special char) does the rest.
    inner = (
        '"%s" --path . --windowed --resolution 1280x720 --fixed-fps 30 '
        '--write-movie reports\\menu_clips\\%s_raw.ogv '
        'res://scenes/capture/%s' % (godot, shot, scene_file)
    )
    with open(log, "w", encoding="utf-8") as logf:
        result = subprocess.run(
            'cmd /v:on /c "call godot_path.bat & %s"' % inner,
            cwd=str(ROOT), env=godot_env(), stdout=logf, stderr=subprocess.STDOUT,
        )
    text = log.read_text(encoding="utf-8", errors="replace")
    err = ERROR_RE.search(text)
    if err is not None:
        print("  CAPTURE_ERROR from recorder: %s" % err.group(1).strip())
        return False
    if result.returncode != 0:
        print("  Godot exited with code %d — see %s" % (result.returncode, log))
        return False
    if END_RE.search(text) is None or READY_RE.search(text) is None:
        print("  No CAPTURE_READY/CAPTURE_END markers in %s — see %s" % (log.name, log))
        return False
    # Report the real capture resolution. A wrong one is a WARNING, not a
    # failure: the recorder may still be usable at 1920x1080 if override.cfg
    # ever stops working (1080p is an acceptable fallback, just bigger).
    m_size = MOVIE_SIZE_RE.search(text)
    if m_size is None:
        print("  WARNING: no 'recording movie in WxH' line in %s — "
              "capture resolution unconfirmed" % log.name)
    elif (m_size.group(1), m_size.group(2)) != ("1280", "720"):
        print("  WARNING: recorded at %sx%s, NOT 1280x720 — override.cfg did "
              "not take effect (see %s)"
              % (m_size.group(1), m_size.group(2), log.name))
    else:
        print("  capture resolution: %sx%s (log %s)"
              % (m_size.group(1), m_size.group(2), log.name))
    return True


def _verify_clip(ffmpeg: str, path: Path) -> bool:
    """Fully decodes the finished clip and demands exit 0 with ZERO error
    lines. This is the 'never ship a file that does not fully decode' gate
    (Phase 1: every re-encode fails it with rc=69 / `unpack_block_qpis`)."""
    dec = subprocess.run(
        [ffmpeg, "-hide_banner", "-v", "error", "-i", str(path), "-f", "null", "-"],
        cwd=str(ROOT), capture_output=True, text=True,
    )
    errs = [l for l in (dec.stderr or "").splitlines() if l.strip()]
    if dec.returncode != 0 or errs:
        print("  VERIFY FAILED: %s decodes with exit %d and %d error line(s):"
              % (path.name, dec.returncode, len(errs)))
        for line in errs[:5]:
            print("    %s" % line.strip())
        if len(errs) > 5:
            print("    ... (%d more)" % (len(errs) - 5))
        return False
    return True


def trim_shot(shot: str, clip_file: str) -> bool:
    """Trims the raw to the marker window, strips audio and STREAM-COPIES the
    Theora into assets/videos/<clip>.ogv (see the header: this ffmpeg's Theora
    encoder is unusable). The start is snapped forward to the next keyframe so
    the cut lands on a frame boundary a stream copy can actually open on."""
    log = REPORT_DIR / ("%s.log" % shot)
    text = log.read_text(encoding="utf-8", errors="replace")
    m_ready = READY_RE.search(text)
    m_end = END_RE.search(text)
    if m_ready is None or m_end is None:
        print("  No CAPTURE_READY/CAPTURE_END markers in %s" % log.name)
        return False
    ready = int(m_ready.group(1))
    end = int(m_end.group(1))
    if end <= ready:
        print("  Empty window: CAPTURE_END(%d) <= CAPTURE_READY(%d)" % (end, ready))
        return False
    # Snap the cut forward to the next keyframe (ceil to KEYFRAME_INTERVAL).
    # Consequence, by design: up to one GOP of pre-roll after CAPTURE_READY is
    # traded for a cut the stream copy can open cleanly. Only the frames the
    # recorder spends before READY (the loading screen) are dropped either way.
    start_frame = -(-ready // KEYFRAME_INTERVAL) * KEYFRAME_INTERVAL
    if start_frame >= end:
        start_frame = ready
    if start_frame != ready:
        print("  keyframe snap: frame %d -> %d (interval %d), last %d GOP frames dropped"
              % (ready, start_frame, KEYFRAME_INTERVAL, start_frame - ready))
    start_s = start_frame / FPS
    dur_s = (end - start_frame) / FPS
    if dur_s <= 0.0:
        print("  Empty window after keyframe snap: ready=%d end=%d" % (ready, end))
        return False
    raw = REPORT_DIR / ("%s_raw.ogv" % shot)
    out = CLIP_DIR / clip_file
    try:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception as exc:  # noqa: BLE001 - any import/lookup failure is fatal here
        raise SystemExit("imageio-ffmpeg required for the trim pass: %s" % exc)
    result = subprocess.run(
        [ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
         "-ss", "%.6f" % start_s, "-i", str(raw),
         "-t", "%.6f" % dur_s,
         "-an", "-c:v", "copy", str(out)],
        cwd=str(ROOT), capture_output=True, text=True,
    )
    if result.returncode != 0 or not out.exists():
        print("  ffmpeg trim failed: %s" % (result.stderr or result.stdout))
        return False
    # Ship nothing that does not decode completely (see _verify_clip).
    if not _verify_clip(ffmpeg, out):
        try:
            out.unlink()
        except FileNotFoundError:
            pass
        print("  kept the raw + log in %s for inspection"
              % REPORT_DIR.relative_to(ROOT))
        return False
    size = out.stat().st_size
    print("  wrote %s (%.1f s, %.2f MB)"
          % (out.relative_to(ROOT), dur_s, size / 1048576.0))
    if size > CLIP_BUDGET_BYTES:
        print("  WARNING: over the %.0f MB budget — consider re-recording with a "
              "lower editor/movie_writer/video_quality." % (CLIP_BUDGET_BYTES / 1048576.0))
    return True


def import_clips(godot: str) -> bool:
    """One headless import so the new .ogv files resolve through
    ResourceLoader.exists() (the menu only turns on after this)."""
    env = godot_env()
    result = subprocess.run(
        # Single string, not a list: see the list2cmdline note in record_shot.
        'cmd /v:on /c "call godot_path.bat & "%s" --headless --import ."' % godot,
        cwd=str(ROOT), env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    if result.returncode != 0:
        print("  --headless --import failed (code %d): %s" % (result.returncode, result.stdout[-2000:]))
        return False
    return True


def main() -> int:
    requested = sys.argv[1:]
    unknown = [s for s in requested if s not in SHOTS]
    if unknown:
        print("Unknown shot(s): %s (choose from %s)" % (unknown, ", ".join(SHOTS)))
        return 1
    shots = requested if requested else list(SHOTS)

    print("NOTE: recording is real-GPU windowed work — one Godot at a time.")
    print("      Never run this beside the GDUnit parallel gate or another Godot.")
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    CLIP_DIR.mkdir(parents=True, exist_ok=True)
    godot = resolve_godot_console()
    print("Godot (console): %s" % godot)

    # Force the capture window to 1280x720 for the run only; deleted again
    # even on Ctrl+C (finally) so a recording attempt can never change how the
    # game launches.
    _write_override()
    print("override.cfg -> windowed 1280x720 (deleted when this script exits)")

    failed = []
    try:
        for shot in shots:
            scene_file, clip_file = SHOTS[shot]
            print("[%s] recording res://scenes/capture/%s ..." % (shot, scene_file))
            if not record_shot(godot, shot, scene_file):
                print("  FAILED to record %s (raw/log kept in %s)"
                      % (shot, REPORT_DIR.relative_to(ROOT)))
                failed.append(shot)
                continue
            print("[%s] trimming -> assets/videos/%s ..." % (shot, clip_file))
            if not trim_shot(shot, clip_file):
                failed.append(shot)

        if failed:
            print("DONE WITH FAILURES: %s" % ", ".join(failed))
            return 1
        if requested:
            print("DONE: %s recorded." % ", ".join(shots))
            return 0
        print("All clips recorded. Importing so the menu picks them up ...")
        if not import_clips(godot):
            return 1
    finally:
        _restore_override()

    print("DONE. Eyall the menu over each clip, then run the gate suite once.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
