# Forests: tree walls painted like a terrain

> **Status:** first version, 2026-10-10. level-1 has a `ForestLayer`; its "Forest Border" is being
> converted with the layer's "Absorb trees" button (417 of its 468 tree instances still placed).
> The generated placeholder region worlds paint their woods and border walls on a `forest` layer
> too ([WORLD_ATLAS.md](WORLD_ATLAS.md)).

A tree wall placed tree by tree is hard to keep in order: hundreds of nodes, and with Editable
Children on, a click in the 2D view picks a tree's picture (`Visual`), so a drag moves the picture
away from its collision. The **forest layer** stores only painted cells; the trees, their sway and
their collision follow the paint.

## Using it

1. In a world scene, **Add Node > ForestLayer**, beside the `ground` layer (same grid, position
   (0, 0)). It takes `game/world/forest/forest_tileset.tres` by itself.
2. Paint with the palette (TileMap panel at the bottom):
   - **top row, mixes** (light frame): mixed (the level-1 wall: pines and dark broadleaf), pine,
     green, light green, autumn, dead, snow. Each cell picks a tree of the mix.
   - **rows below, single trees:** the cell takes exactly that tree (all 44 trees of the sway sheet,
     less one empty frame).
   - Erase cells to cut a gap or a path; paint over a cell to change its tree.
3. Inspector: `variation` (another number rerolls every tree's pick, shift, size and flip),
   `shift` (how far a tree may stand from its place, units across and down), `size_range`,
   `paint_opacity` (the squares over the trees in the editor; 0 hides them; always hidden in the
   game).
4. A one-off tree (a landmark) is still placed as a normal instance.

**Absorb trees:** set `absorb_from` (Inspector, group "Absorb trees") to the node holding wall tree
instances, for example `Forest Border`, and press **Absorb trees**: every child drawn from the trees
sway sheet becomes a painted cell of the same tree, and is removed (Ctrl+Z undoes it). Its cell is
the one whose tree place is nearest the tree's foot; when two trees fall in one cell the first
wins. Other children are left alone and listed in the Output. Save, and delete the empty group.

## How it works

`game/world/forest/forest_layer.gd` (`ForestLayer`, `@tool`, a TileMapLayer):

- Each painted cell grows one Sprite2D of the sheet
  `res://asset/MAPS/trees/128x170-tile_16x22-trees-sway.webp`, standing at (32, 54) in its cell
  (where the wall tree scenes stood on the grid), shifted, sized and flipped by a random number
  seeded with the cell and `variation`. The sprites live in an unowned child `Trees`, so the scene
  saves only the cells. The layer is y-sorted, so trees sort with the player like placed trees.
- **Sway:** 8 frames at 4 per second with a seeded phase per tree, in the game only (real time,
  presentation). The editor shows a still frame.
- **Collision (game only):** a StaticBody2D `Collision` (layer 1, world) with one rectangle per run
  of cells along a row: from the trunks' tops (44 units above the foot, as the trunk box of the tree
  scenes) to their feet, reaching the cell's top or bottom where the next row is painted too, so a
  painted area is solid with no gaps between rows.
- The tile's custom data `forest_trees` holds the first frames of its trees and `forest_mix` its
  name; `scripts/art/build-forest-paint-tiles.py` writes the palette
  (`godot/asset/MAPS/forest/forest_paint_tiles.png`) and the tile set from the list of mixes in it.

## Limits

- One tree per cell on the 64-unit grid: a forest is as regular as the old wall rows (the shift
  hides the grid; a denser or looser wood needs a second layer or another rule).
- Trees on raised ground (the elevation) stand at level 0's collision layer, as placed trees do.
- Only the trees of the sway sheet; other tree art needs its own tiles.

## Files

| Path | What |
|---|---|
| `godot/game/world/forest/forest_layer.gd` | The layer: trees, sway, collision, Absorb trees |
| `godot/game/world/forest/forest_tileset.tres` | The palette tile set (tool output) |
| `godot/asset/MAPS/forest/forest_paint_tiles.png` | The palette art (tool output) |
| `scripts/art/build-forest-paint-tiles.py` | Builds both from the trees sway sheet and its mixes |
