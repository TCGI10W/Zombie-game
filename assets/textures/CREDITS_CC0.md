# Photo-scanned textures

These texture sets are built from photo scans on [Poly Haven](https://polyhaven.com),
released under **CC0** (public domain): free for any use, no attribution
required. They're credited here anyway — thanks to the artists.

`tools/import_scanned_textures.py` converts the downloaded maps (color,
OpenGL normal, roughness, ambient occlusion, displacement) into the game's
format; zombie clothes also get procedural dirt and blood layered on top.

| Game texture | Source scan | Artists | Real-world size |
|---|---|---|---|
| `asphalt` | [Asphalt 02](https://polyhaven.com/a/asphalt_02) | Rob Tuytel | 3.00 m |
| `concrete` | [Concrete Layers 02](https://polyhaven.com/a/concrete_layers_02) | Rob Tuytel | 2.00 m |
| `concrete_floor` | [Concrete Floor 02](https://polyhaven.com/a/concrete_floor_02) | Rob Tuytel | 2.00 m |
| `rusted_metal` | [Rusty Metal 04](https://polyhaven.com/a/rusty_metal_04) | Amal Kumar | 2.00 m |
| `wood_planks`, `wood_board` | [Old Planks 02](https://polyhaven.com/a/old_planks_02) | Rob Tuytel | 2.00 m |
| `wood_grain` | [Wood Table Worn](https://polyhaven.com/a/wood_table_worn) | Dimitrios Savva, Rico Cilliers | 0.55 m |
| `fabric` | [Cotton Jersey](https://polyhaven.com/a/cotton_jersey) | colormass, Rico Cilliers | 0.26 m |
| `denim` | [Denim Fabric 04](https://polyhaven.com/a/denim_fabric_04) | colormass, Rico Cilliers | 0.27 m |
| `leather` | [Brown Leather](https://polyhaven.com/a/brown_leather) | Rob Tuytel | 0.40 m |
| `burlap` | [Hessian 230](https://polyhaven.com/a/hessian_230) | colormass, Rico Cilliers | 0.27 m |

Still procedural (`tools/generate_textures_v4.py`): `zombie_skin`,
`gorilla_hide`, `monster_scales`, `camo`, `gunmetal`, `macro_noise`,
`sky_night`, `blood_vignette`.
