# Mine Dungeons resource pack

The item art for the Mine Dungeons network (minedungeons.net), for Java and Bedrock.

- **Java:** `minedungeons-pack.zip`, a 1.21.4+ resource pack (`item_model`). It works for clients up to 26.3 (pack format 97.1). Every custom item carries `minecraft:item_model = minedungeons:<id>`, set by the plugins.
- **Bedrock:** `minedungeons-bedrock.mcpack`, sent to Bedrock players by Geyser, plus `minedungeons-geyser.json`, Geyser's custom item mappings (format 2). The mappings map each Java item model to a Bedrock item `minedungeons:<id>`.

## Layout

| Path | What |
|---|---|
| `items.json` | Every item: id, base Java item, name. Copied from the plugins repo (`tools/pack/items.json`), where a test keeps it equal to the plugins |
| `art/items/<id>.png` | Item icons (16×16, or 32×32 for helmet skins) |
| `art/equipment/<skin>.png` | Each helmet skin's worn look (64×32), used as `equipment/<skin>.json` |
| `art/trims/<pattern>_humanoid[_leggings].png` | Trim patterns (64×32), in the eight trim-palette greys only; the client tints them per material |
| `art/gui/<id>.png` | Menu backgrounds, cropped to 176 wide by the height in `gui.json` |
| `gui.json` | The `minedungeons:gui` font: background glyphs and negative spaces. Copied from the plugins repo, where a test keeps it equal to MDSeasons' `GuiTitles` |
| `pack.png` | The pack icon |
| `provenance/voxelforge.json` | The VoxelForge asset (and revision) each texture came from; update the revision when an asset is edited in the studio |
| `tools/Import-VoxelForge.ps1` | Copies textures out of a VoxelForge Java export |
| `build.ps1` | Builds `dist/` |

## Art

All art is made in VoxelForge (16×16, vanilla style). To change a texture:
1. Edit or regenerate the asset in the studio.
2. Point `provenance/voxelforge.json` at it.
3. Export those assets as a Java pack, then run `./tools/Import-VoxelForge.ps1 -Zip <export>`.

   **What the import does to some assets:**
   - **Skins:** both the icon and the worn texture come in.
   - **Trims:** a pattern's head, chest and boots layers are merged and quantised to the trim palette.

## Build and release

```powershell
./build.ps1                # version from VERSION (Windows: the image checks use System.Drawing)
```

- **What the build does:** it fails, naming each problem, if any art is missing or the wrong size or colours. The same inputs always give the same files (same SHA-1) on any machine.
- **Releasing:**
  1. Bump `VERSION`, then build.
  2. Make a GitHub release `vX.Y.Z` with `dist/minedungeons-pack.zip`, `dist/minedungeons-pack.zip.sha1`, `dist/minedungeons-bedrock.mcpack` and `dist/minedungeons-geyser.json`.
  3. From the plugins repo, run `tools/deploy/Deploy-Pack.ps1 -Stage Release -Tag vX.Y.Z`.
