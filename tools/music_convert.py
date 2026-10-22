#!/usr/bin/env python3
"""Convert a folder of music to what the UltraDrive FreeRoam radio can play.

Godot 4 decodes only MP3, Ogg Vorbis and WAV at runtime. FLAC, M4A/AAC, Opus
and WebM audio are listed in-game as "need conversion". This tool mirrors a
source tree into an output folder:

  * flac / m4a / aac / mp4 / opus / webm  -> Ogg Vorbis (libvorbis, -q:a 6),
    tags preserved (-map_metadata 0)
  * mp3 / ogg / oga / wav                 -> copied unchanged (--no-copy to skip)
  * embedded cover art                    -> sibling "<stem>.jpg" sidecar (the
    game reads it; ffmpeg does not reliably write Vorbis picture blocks)
  * idempotent: an output at least as new as its source is skipped
  * "*.part.*" in-flight downloads, dot-files and unknown extensions are ignored

Needs ffmpeg on PATH (or --ffmpeg PATH) ONLY for the conversion step; the game
itself never requires it. Nothing is downloaded or uploaded, and no music is
bundled with the game.

    python tools/music_convert.py "D:/Music/Source" "D:/Music/UltraDrive"
    python tools/music_convert.py SRC DST --dry-run
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

CONVERT_EXT = {".flac", ".m4a", ".aac", ".mp4", ".opus", ".webm"}
COPY_EXT = {".mp3", ".ogg", ".oga", ".wav"}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp"}


@dataclass(frozen=True)
class Job:
    kind: str  # "convert" | "copy"
    src: Path
    dst: Path
    cover: Path  # sidecar path (<dst stem>.jpg)


def is_partial(name: str) -> bool:
    n = name.lower()
    return ".part." in n or n.endswith((".part", ".tmp", ".crdownload", ".download"))


def up_to_date(src: Path, dst: Path) -> bool:
    try:
        return dst.stat().st_size > 0 and dst.stat().st_mtime >= src.stat().st_mtime
    except OSError:
        return False


def plan(src_root: Path, dst_root: Path, copy: bool = True) -> list[Job]:
    """Pure planning step (no ffmpeg): every file that needs work."""
    jobs: list[Job] = []
    for dirpath, dirnames, filenames in os.walk(src_root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for name in sorted(filenames):
            if name.startswith(".") or is_partial(name):
                continue
            src = Path(dirpath) / name
            ext = src.suffix.lower()
            rel = src.relative_to(src_root)
            if ext in CONVERT_EXT:
                dst = (dst_root / rel).with_suffix(".ogg")
                kind = "convert"
            elif ext in COPY_EXT and copy:
                dst = dst_root / rel
                kind = "copy"
            else:
                continue
            jobs.append(Job(kind, src, dst, dst.with_suffix(".jpg")))
    return jobs


def pending(jobs: list[Job]) -> list[Job]:
    out = []
    for j in jobs:
        if not up_to_date(j.src, j.dst):
            out.append(j)
    return out


def find_ffmpeg(explicit: str | None) -> str | None:
    if explicit:
        return explicit if shutil.which(explicit) or Path(explicit).exists() else None
    return shutil.which("ffmpeg")


def run_job(job: Job, ffmpeg: str | None, quality: int) -> tuple[Job, str]:
    job.dst.parent.mkdir(parents=True, exist_ok=True)
    if job.kind == "copy":
        shutil.copy2(job.src, job.dst)
        return job, "copied"
    assert ffmpeg is not None
    tmp = job.dst.with_name(job.dst.stem + ".part.ogg")
    cmd = [ffmpeg, "-nostdin", "-loglevel", "error", "-y", "-i", str(job.src),
           "-vn", "-map", "0:a:0", "-map_metadata", "0",
           "-c:a", "libvorbis", "-q:a", str(quality), str(tmp)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0 or not tmp.exists() or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        return job, "failed: " + (res.stderr.strip().splitlines() or ["ffmpeg error"])[-1]
    os.replace(tmp, job.dst)
    os.utime(job.dst, (job.src.stat().st_atime, max(job.src.stat().st_mtime, job.dst.stat().st_mtime)))
    return job, "converted"


def extract_cover(job: Job, ffmpeg: str) -> bool:
    """Embedded picture -> sibling .jpg (best effort; sources with no art just return False)."""
    if job.cover.exists() and job.cover.stat().st_size > 0:
        return True
    cmd = [ffmpeg, "-nostdin", "-loglevel", "error", "-y", "-i", str(job.src),
           "-an", "-map", "0:v:0", "-frames:v", "1", str(job.cover)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0 or not job.cover.exists() or job.cover.stat().st_size == 0:
        job.cover.unlink(missing_ok=True)
        return False
    return True


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path, help="source music folder")
    ap.add_argument("dst", type=Path, help="output folder (mirrors the source tree)")
    ap.add_argument("--quality", type=int, default=6, help="libvorbis -q:a (default 6, about 192 kbps)")
    ap.add_argument("--jobs", type=int, default=2, help="parallel ffmpeg processes (default 2)")
    ap.add_argument("--no-copy", action="store_true", help="do not copy mp3/ogg/wav, convert only")
    ap.add_argument("--no-covers", action="store_true", help="skip cover sidecar extraction")
    ap.add_argument("--ffmpeg", default=None, help="path to ffmpeg (default: PATH)")
    ap.add_argument("--dry-run", action="store_true", help="list what would be done and exit")
    args = ap.parse_args(argv)

    src = args.src.resolve()
    dst = args.dst.resolve()
    if not src.is_dir():
        print(f"source folder not found: {src}", file=sys.stderr)
        return 2
    if src == dst or dst in src.parents:
        print("output folder must differ from (and not contain) the source folder", file=sys.stderr)
        return 2

    todo = pending(plan(src, dst, copy=not args.no_copy))
    n_convert = sum(1 for j in todo if j.kind == "convert")
    print(f"{len(todo)} file(s) to process ({n_convert} to convert, {len(todo) - n_convert} to copy)")
    if args.dry_run:
        for j in todo:
            print(f"  {j.kind:7} {j.src} -> {j.dst}")
        return 0
    ffmpeg = find_ffmpeg(args.ffmpeg)
    if n_convert and ffmpeg is None:
        print("ffmpeg not found on PATH: install it (https://ffmpeg.org) or pass --ffmpeg PATH. "
              "mp3 / ogg / wav files need no conversion and play as they are.", file=sys.stderr)
        todo = [j for j in todo if j.kind == "copy"]
        if not todo:
            return 1
    failed = 0
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for job, status in pool.map(lambda j: run_job(j, ffmpeg, args.quality), todo):
            print(f"  {status:9} {job.src.name}")
            if status.startswith("failed"):
                failed += 1
            elif job.kind == "convert" and not args.no_covers and ffmpeg:
                extract_cover(job, ffmpeg)
    print(f"done, {failed} failure(s)")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
