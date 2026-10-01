# Asset Sheet And Size Guide

The shared sheet contract. Continue with the focused guide for the asset type:

- [Slime Sheet Guide](./slime-sheet-guide.md)
- [Terrain And Tile Guide](./terrain-tile-guide.md)
- [Houses And World Props Guide](./houses-and-world-props-guide.md)

## Sheet rules

- Uniform grids only: every frame the same size, frames indexed row-major
  (`frame = row * cols + col`). A partly filled last row sets `frame.count`.
- Transparent background (real alpha) for anything that is not a full tile.
- Keep every pixel inside its own cell; leave a small transparent margin.
- World props and furniture are bottom-centre anchored (`render.origin`
  `[0.5, 1]`) so the frame's bottom edge is the ground contact line.
- Name runtime files with frame size and grid, e.g.
  `128x128-tile_8x2-crystal-clusters.webp`.

## Current sizes

| Asset | Frame | Example |
| --- | --- | --- |
| World tile | `64 x 64` | map `tileSize` is 64 |
| Ground material | `64 x 64` cells, `19 x 19` sheet (`1216 x 1216`) | `MAPS/grounds/64x64-tile_19x19_forest-floor.webp` |
| Player slime | `256 x 256`, `8 x 8` | `characters/slime_normalized.webp` |
| NPC | `229 x 229`, `6 x 5` | `characters/authored/npcs/lili.webp` |
| Worm / spider enemy | `64 x 64` | `MAPS/enemies/64x64-8x6-worm-archer.webp` |
| Tree | `128 x 170` | `MAPS/trees/128X170-tiles_8x6.webp` |
| Rock / prop | `96`, `128`, or `256` square | `MAPS/rocks/96x96-tile_8x3.webp` |
| House | `320 x 320` | `MAPS/Houses/320-3x1.webp` |
| Item icon | `64 x 64`, `5 x 2` | `MAPS/items/gems-5x2.webp` |
| Interior furniture | `128`, `192`, or `256` square | `MAPS/interiors/` |
| Weapon / hit effect | `120`-`128` square | `MAPS/weapons/` |

## What needs changing for a new size

Frame size is not hardcoded. A new size needs:

- a manifest entry with the correct `frame` and `expect` values;
- a scene whose sprite-sheet subresource uses the same `frameWidth`/`frameHeight`,
  and whose `scale`, `origin`, collision shape, and depth/occlusion bounds fit
  the art (see [Adding Game Assets](./adding-assets.md)).

Changing the grid layout of an existing animated sheet also means updating the
frame indices in that scene's `AnimationPlayer` library.
