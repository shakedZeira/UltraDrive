#!/usr/bin/env python3
# tools/pack_terrain_textures.py
#
# Packs the open-world ground texture set for Terrain3D from ambientCG (CC0)
# 1K-JPG material folders. Terrain3D samples two texture arrays per layer:
#   <name>_alb_ht.png  = albedo RGB + height (displacement) in A
#   <name>_nrm_rgh.png = OpenGL normal RGB + roughness in A
# All layers must share one size and format, so every map is resized to SIZE.
#
# The layer table here must stay in sync with TerrainTexturing.LAYERS
# (scripts/world/terrain_texturing.gd): same order = same Terrain3D texture id.
#
# Source download (CC0, https://ambientcg.com, no attribution required):
#   https://ambientcg.com/get?file=<AssetId>_1K-JPG.zip  -> unzip into <src>/<AssetId>/
#
# usage: py -I tools/pack_terrain_textures.py <src_dir> [out_dir]
#   out_dir defaults to assets/terrain/textures (relative to the repo root).
# Then run a headless `--import` so Godot builds the .import files; the import
# settings come from the .import files committed next to the PNGs (VRAM
# compressed, mipmaps, normal-map detection off: Terrain3D wants raw channels).

import os
import sys

from PIL import Image

SIZE = 1024

# (layer name, ambientCG asset id) in Terrain3D texture-id order.
LAYERS = [
    ("grass", "Grass004"),
    ("meadow", "Ground037"),
    ("dirt", "Ground048"),
    ("rock", "Rock030"),
    ("sand", "Ground054"),
    ("snow", "Snow006"),
    ("gravel", "Gravel043"),
    ("forest", "Grass001"),
]


def _map(src_dir: str, asset: str, suffix: str) -> str:
    return os.path.join(src_dir, asset, "%s_1K-JPG_%s.jpg" % (asset, suffix))


def _load(path: str, mode: str) -> Image.Image:
    im = Image.open(path).convert(mode)
    if im.size != (SIZE, SIZE):
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
    return im


def pack_layer(src_dir: str, out_dir: str, name: str, asset: str) -> None:
    albedo = _load(_map(src_dir, asset, "Color"), "RGB")
    height = _load(_map(src_dir, asset, "Displacement"), "L")
    normal = _load(_map(src_dir, asset, "NormalGL"), "RGB")
    rough = _load(_map(src_dir, asset, "Roughness"), "L")
    r, g, b = albedo.split()
    Image.merge("RGBA", (r, g, b, height)).save(os.path.join(out_dir, name + "_alb_ht.png"))
    nr, ng, nb = normal.split()
    Image.merge("RGBA", (nr, ng, nb, rough)).save(os.path.join(out_dir, name + "_nrm_rgh.png"))


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__ or "usage: pack_terrain_textures.py <src_dir> [out_dir]")
        return 2
    src_dir = sys.argv[1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "assets", "terrain", "textures")
    os.makedirs(out_dir, exist_ok=True)
    for name, asset in LAYERS:
        pack_layer(src_dir, out_dir, name, asset)
        print("packed", name, "<-", asset)
    return 0


if __name__ == "__main__":
    sys.exit(main())
