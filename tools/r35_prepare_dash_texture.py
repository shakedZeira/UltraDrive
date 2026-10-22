#!/usr/bin/env python3
"""Prepare the Phase-1 GT-R R35 forward dash billboard texture.

Deterministic and re-runnable (fixed crop/grade constants, no randomness):

  1. crop the UPPER DASH BAND from the driver's-eye reference photo — strictly
     ABOVE the steering-wheel rim (the wheel stays real 3D + animated; a baked
     wheel would double it),
  2. mirror horizontally (the reference photos are LHD, the game R35 is RHD:
     config cockpit_seat_lateral -0.36, tests require DoorCardRight.x < 0 and
     CentreStackRiser.x > 0),
  3. colour-grade to the in-game NIGHT cabin brightness, pre-graded in the image
     so no runtime dimming is needed (hence no cockpit_rig.gd edit),
  4. resize to 2048x1152 and write
     assets/interiors/r35/r35_dash_forward.png.

Also prints the resulting quad width so the billboard's aspect
(scene: DashPad QuadMesh, height 0.50 m) matches the crop aspect exactly and
the photo is displayed without vertical/horizontal distortion.

Crop rows (fractions of the 1920x1440 source, measured on 2026-10-18):
  top    420  - windscreen base / cowl line (local vision model line probe
               "COWL=C" on the annotated photo; the centre-column luminance
               cliff sits at y 470-490, so 420 keeps the sunlit dash-top edge
               under the glass WITHOUT baking any windscreen glass)
  bottom 855  - top edge of the steering-wheel rim at frame centre (luminance
               profile: darkest band starts y~860; line probe "WHEEL_TOP=G" =
               860). Bottom is 855 so NO rim pixel is baked.

Usage: py tools\\r35_prepare_dash_texture.py [--check-only]
"""

import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(
    ROOT, "assets", "interiors", "r35", "reference",
    "File_The_interior_of_Nissan_GT-R_Premium_Edition_2017_year_model_at_Ni.jpg",
)
DST = os.path.join(ROOT, "assets", "interiors", "r35", "r35_dash_forward.png")

# --- crop box (source pixels, 1920x1440) -----------------------------------
CROP_TOP = 420
CROP_BOTTOM = 855          # exclusive; strictly above the wheel rim
CROP_LEFT = 0
CROP_RIGHT = 1920

# --- night-cabin grade ------------------------------------------------------
# The trim in the scene renders at albedo 0.12-0.16 with emission x0.15 under a
# dark night ambient; the unshaded billboard must sit in the same brightness
# band, so the daylight photo is pre-graded down (multiply -> gamma -> slight
# desaturation -> faint cool night shift).
EXPOSURE = 0.82
GAMMA = 1.05
SATURATION = 0.85
TINT = (0.98, 1.00, 1.03)

# --- output -----------------------------------------------------------------
OUT_W, OUT_H = 2048, 1152
QUAD_H = 0.50              # m, scene height of the DashPad quad


def grade(rgb: np.ndarray) -> np.ndarray:
    x = rgb.astype(np.float32) / 255.0
    x = x * EXPOSURE
    lum = 0.2126 * x[..., 0] + 0.7152 * x[..., 1] + 0.0722 * x[..., 2]
    x = SATURATION * x + (1.0 - SATURATION) * lum[..., None]
    x = np.power(np.clip(x, 0.0, 1.0), GAMMA)
    x = x * np.array(TINT, dtype=np.float32)
    return np.clip(x, 0.0, 1.0)


def stats(name: str, rgb: np.ndarray) -> None:
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    print(
        "%-10s mean=%.3f p05=%.3f p50=%.3f p95=%.3f max=%.3f"
        % (name, lum.mean(), np.percentile(lum, 5), np.percentile(lum, 50),
           np.percentile(lum, 95), lum.max())
    )


def main() -> int:
    check_only = "--check-only" in sys.argv
    if not os.path.exists(SRC):
        print("ERROR: missing source", SRC)
        return 1
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    print("source", w, h)
    if not (0 <= CROP_TOP < CROP_BOTTOM <= h):
        print("ERROR: crop box outside image")
        return 1

    crop = im.crop((CROP_LEFT, CROP_TOP, CROP_RIGHT, CROP_BOTTOM))
    crop_w, crop_h = crop.size
    aspect = crop_w / float(crop_h)
    quad_w = QUAD_H * aspect
    print("crop %dx%d aspect=%.4f -> quad %.2f x %.2f m (eye y -0.56..-0.06)"
          % (crop_w, crop_h, aspect, quad_w, QUAD_H))
    stats("crop", np.asarray(crop))

    mirrored = crop.transpose(Image.FLIP_LEFT_RIGHT)

    graded = grade(np.asarray(mirrored))
    stats("graded", graded)
    if check_only:
        return 0

    out = Image.fromarray((graded * 255.0 + 0.5).astype(np.uint8))
    out = out.resize((OUT_W, OUT_H), Image.LANCZOS)
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    out.save(DST)
    print("wrote", DST, out.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
