"""Unit tests for tools/music_convert.py planning (no ffmpeg needed).

    python -m unittest tools/test_music_convert.py
"""
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import music_convert as mc  # noqa: E402


def touch(path: Path, data: bytes = b"x", mtime: float | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    if mtime is not None:
        os.utime(path, (mtime, mtime))


class PlanTests(unittest.TestCase):
    def test_plan_maps_formats_and_skips_junk(self):
        with tempfile.TemporaryDirectory() as td:
            src, dst = Path(td) / "src", Path(td) / "dst"
            touch(src / "A" / "one.flac")
            touch(src / "A" / "two.mp3")
            touch(src / "B" / "deep" / "three.m4a")
            touch(src / "B" / "id.part.m4a")  # in-flight download
            touch(src / ".hidden.flac")
            touch(src / "notes.txt")
            jobs = mc.plan(src, dst)
            got = {(j.kind, str(j.dst.relative_to(dst)).replace("\\", "/")) for j in jobs}
            self.assertEqual(got, {
                ("convert", "A/one.ogg"),
                ("copy", "A/two.mp3"),
                ("convert", "B/deep/three.ogg"),
            })

    def test_no_copy_skips_native_files(self):
        with tempfile.TemporaryDirectory() as td:
            src, dst = Path(td) / "src", Path(td) / "dst"
            touch(src / "x.mp3")
            touch(src / "y.opus")
            kinds = [j.kind for j in mc.plan(src, dst, copy=False)]
            self.assertEqual(kinds, ["convert"])

    def test_idempotent_by_mtime(self):
        with tempfile.TemporaryDirectory() as td:
            src, dst = Path(td) / "src", Path(td) / "dst"
            touch(src / "a.flac", mtime=1000)
            jobs = mc.plan(src, dst)
            self.assertEqual(len(mc.pending(jobs)), 1)
            touch(jobs[0].dst, mtime=2000)  # output newer than source
            self.assertEqual(mc.pending(jobs), [])
            os.utime(src / "a.flac", (3000, 3000))  # source changed -> redo
            self.assertEqual(len(mc.pending(jobs)), 1)

    def test_cover_sidecar_sits_next_to_output(self):
        with tempfile.TemporaryDirectory() as td:
            src, dst = Path(td) / "src", Path(td) / "dst"
            touch(src / "s" / "t.m4a")
            job = mc.plan(src, dst)[0]
            self.assertEqual(job.cover, dst / "s" / "t.jpg")

    def test_dry_run_and_bad_args(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td) / "src"
            touch(src / "a.flac")
            self.assertEqual(mc.main([str(src), str(Path(td) / "out"), "--dry-run"]), 0)
            self.assertEqual(mc.main([str(Path(td) / "missing"), str(Path(td) / "out")]), 2)
            self.assertEqual(mc.main([str(src), str(src)]), 2)


if __name__ == "__main__":
    unittest.main()
