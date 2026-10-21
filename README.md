# Mine Dungeons resource pack

The item art for the Mine Dungeons network (minedungeons.net), for Java and Bedrock.

- **Java:** `minedungeons-pack.zip`, a 1.21.4+ resource pack (`item_model`). It works for clients up to 26.3 (pack format 97.1). Every custom item carries `minecraft:item_model = minedungeons:<id>`, set by the plugins.
- **Bedrock:** `minedungeons-bedrock.mcpack`, sent to Bedrock players by Geyser, plus `minedungeons-geyser.json`, Geyser's custom item mappings (format 2). The mappings map each Java item model to a Bedrock item `minedungeons:<id>`.

## Layout

| Path | What |
|---|---|
| `items.json` | Every item: id, base Java item, name. Copied from the plugins repo (`tools/pack/items.json`), where a test keeps it equal to the plugins |
| `art/items/<id>.png` | The 16×16 textures |
| `pack.png` | The pack icon |
| `provenance/voxelforge.json` | The VoxelForge asset each texture came from |
| `tools/Import-VoxelForge.ps1` | Copies textures out of a VoxelForge Java export |
| `build.ps1` | Builds `dist/` |

## Art

All art is made in VoxelForge (16×16, vanilla style). To change a texture:
1. Edit or regenerate the asset in the studio.
2. Point `provenance/voxelforge.json` at it.
3. Export those assets as a Java pack, then run `./tools/Import-VoxelForge.ps1 -Zip <export>`.

## Build and release

```powershell
./build.ps1                # version from VERSION
```

- **What the build does:** it fails, naming each problem, if an item has no 16×16 texture. The same inputs always give the same files (same SHA-1).
- **Releasing:**
  1. Bump `VERSION`, then build.
  2. Make a GitHub release `vX.Y.Z` with `dist/minedungeons-pack.zip`, `dist/minedungeons-pack.zip.sha1`, `dist/minedungeons-bedrock.mcpack` and `dist/minedungeons-geyser.json`.
  3. From the plugins repo, run `tools/deploy/Deploy-Pack.ps1 -Stage Release -Tag vX.Y.Z`.
