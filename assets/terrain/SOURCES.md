# assets/terrain - ground texture sources

All layers are CC0 1.0 (public domain) materials from ambientCG, https://ambientcg.com
(license: https://docs.ambientcg.com/license/). No attribution is required; it is
recorded here for provenance. Downloaded 2026-10-22 as `<AssetId>_1K-JPG.zip`
(`https://ambientcg.com/get?file=<AssetId>_1K-JPG.zip`) and packed with
`tools/pack_terrain_textures.py` into Terrain3D's layout:

- `textures/<name>_alb_ht.png`: Color RGB + Displacement in A
- `textures/<name>_nrm_rgh.png`: NormalGL RGB + Roughness in A

| Texture id | Name | ambientCG asset | Used for |
|---|---|---|---|
| 0 | grass | Grass004 | lowland/plains ground |
| 1 | meadow | Ground037 | grass-and-dirt patches, alpine meadows |
| 2 | dirt | Ground048 | dirt spots, road fringe |
| 3 | rock | Rock030 | steep slopes, alpine band |
| 4 | sand | Ground054 | coast/sea beaches |
| 5 | snow | Snow006 | above the ~850 m snowline |
| 6 | gravel | Gravel043 | road shoulders |
| 7 | forest | Grass001 | forest floor, highland band |

The id order must match `TerrainTexturing.LAYERS` (`scripts/world/terrain_texturing.gd`)
and `LAYERS` in the packer.
