# Terrain lab: hand-made terrain transitions

> **Status: trial** (2026-10-05), in `godot/game/dev/terrain_lab/`. Nothing in the
> game uses it yet; the converted worlds keep hard tile edges until the owner
> approves the look and it is wired into worlds (see [Next steps](#next-steps)).

## Owner decisions (2026-10-05)

- **Art density: 128 px of art per 64-unit cell** (2 px per world unit). The grid
  stays 64 units, so maps, collision, speeds and coordinates do not change; only
  the art gets sharper. New art is made at this density and drawn at scale 0.5.
  256 px was considered and rejected: at the 1280×720 base view a cell covers
  96–120 screen px on a 1080p screen (192–240 on 4K), so 128 px is already sharp
  on 1080p at every zoom, while 256 px would cost 4× the memory and download
  (a 19×19 ground sheet would be 4864 px, above the 4096 px texture limit of
  many phones) for detail only a 4K screen shows.
- **Transitions are hand-made tiles**, not a code blend like Phaser's
  `TerrainBlendField`. The art is generated with Magnific (GPT 2.5) and cut into
  tiles by a tool.

## What you see

Run `godot/game/dev/terrain_lab/terrain_lab.tscn` with F6 (WASD or arrows pan,
the mouse wheel zooms, Home resets). Left: today's look, 64 px sheets with hard
cell edges. Right: the same cells with 128 px art and snow edge tiles: rounded
corners, round one-cell holes, a frosty rim, and snow that runs on without seams.

**Painting:** select `EdgeTiles/Ground`, open the TileMap panel's Tiles tab and
paint with the frozen swatch (source 1) or the sand swatch (source 0). The
`SnowEdges` layer updates by itself, in the editor too. You only ever paint the
ground, so the ground cells stay the gameplay truth (walkability, footsteps).

## How it works

Two layers, both at scale 0.5 over 128 px tiles:

1. **`Ground`**: one swatch tile per ground. Its tile material
   (`game/world/terrain_edges/ground_world.gdshader`) draws the ground's seamless
   19×19 sheet in world space: the same picture as Phaser's sheet-wrap frames
   (cell x mod 19, y mod 19), but the painter picks one tile instead of the right frame.
2. **`SnowEdges`**: a *dual grid*. The layer sits half a cell up and left, so each
   of its cells covers a corner shared by four ground cells.
   `game/world/terrain_edges/terrain_edges.gd` places the edge tile whose index is
   `TL + 2·TR + 4·BL + 8·BR` (1 = that ground cell is snow), at atlas
   `(index % 4, index / 4)`; corners with no snow cell or only snow cells get no
   tile. The script only picks tiles. It rebuilds when the ground changes.

The edge tiles are art. Alpha is where snow covers, colour is the painted rim, and
a second image with the same layout (`…-snow-edges-rim.png`) says where the
painted rim shows. `terrain_edges.gdshader` draws, per pixel, sand or snow taken
from their sheets in world space and mixed by the tile's alpha, with the painted
rim on top. Both sheets line up with the `Ground` swatches, so an edge tile meets
the plain cells around it with no seam. The overlay is opaque: where a tile rounds
a corner away, it shows sand over the snow cell.

### Why not Godot's terrain brush

Godot's "Match Corners" terrain mode decides each corner by the majority of the
cells around it and places tiles on the painted cells themselves. In a probe, a
painted 2×2 block came out with a hole in its middle, and a single cell lost one
corner. Snow also spills half a cell past what you paint, and you would paint the
edges on a separate layer from the gameplay ground. The dual grid is the usual fix
for this in Godot: you paint the ground, and the 16 tiles follow from it.

### Why the snow is drawn in world space

In the first try each edge tile carried its own painted snow. That gave a lighter
band around every snow area, where the generated snow met the ground sheet, and
square sand holes where a cell was surrounded. With world-space sheets, the tiles
only decide where each ground shows and where the rim is.

## Making edge art

1. Generate two images with Magnific (`gpt-2-mini`, 1:1, 1k,
   `transparentBackground: true`), following the
   [Magnific guide](../assets/magnific-mcp-guide.md). Each prompt starts with the
   style block, and the reference image is the two ground sheets side by side.
   - **Island:** "Terrain overlay art for a ground tile set: one flat patch of
     packed snow lying on the ground, seen from above, shaped as a square with
     softly rounded corners, centered, filling about two thirds of the frame. …
     The patch border is natural and irregular but runs straight along each side,
     the same width all around: a thin slightly raised frosty crust … Terrain only,
     no outline around the snow patch. Isolated on a transparent background …"
   - **Hole:** the same snow as a field filling the frame, "with one round hole in
     the exact center where the snow ends … about one third of the frame wide, and
     inside the hole there is nothing: fully transparent".
   Keep the raw images in `asset/Originals/grounds/generated/terrain-edges/`.
2. `python scripts/art/build-terrain-edge-tiles.py [--preview out.png]` (needs
   numpy and Pillow):
   - finds the island's rim and the hole's circle;
   - scales them so every border crosses a tile side at its midpoint;
   - cuts the 16 tiles: convex corners and straight sides from the island, inner
     corners from the hole, diagonals from two corners;
   - picks the straight windows whose ends match, and blends every tile's border
     strips to a shared join, so any two tiles that can touch match exactly;
   - writes the 528 px sheets (2 px gutters) and the rim weights;
   - also upscales and seams the 2× ground sheets from the padded Magnific upscales.
3. Let the editor import the files, then rebuild the lab:
   `"<Godot console exe>" --headless --path godot -s res://tools/build_terrain_lab.gd`.

The trial used 760 Magnific credits: two 2× upscales at 180 each and two
generations of two images at 100 each.

## Limits

- One edge layer joins **one upper ground to one lower ground** (here snow over
  sand); the lower ground is a material parameter. Snow next to grass needs its
  own material (an alternative tile per lower ground, or another layer). Where
  three grounds meet at one corner, cells that are not snow all draw as the
  layer's lower ground.
- The rim follows the generated island, which is fairly regular. More variety
  means more generated islands as alternative tiles; the tool already makes any
  set join.
- The lab does not cover water (solid, with its own surface shader on top),
  elevation, or decorations along borders.

## Next steps

1. Owner review of the look (left vs right panel) and of painting in the editor.
2. Edge sets for the other pairs that meet in the worlds. The tile set's
   `transition.priority` gives the upper ground of each pair.
3. Wire it into worlds: the converter would emit swatch tiles with world-space
   materials and the 128 px sheets instead of sheet-wrap frames, plus an edge
   layer per pair. Or the world loader adds the edge layers, as it does for
   water (the [water spec](./specs/water.md) wants terrain edges drawn between
   the tiles and the water surface).
4. Regenerate the remaining ground sheets at 128 px (about 180 credits each) and
   measure the web build's memory and frame time.

## Files

| Path | What |
|---|---|
| `scripts/art/build-terrain-edge-tiles.py` | Art tool: 2× sheets and the 16 edge tiles |
| `asset/Originals/grounds/generated/terrain-edges/` | Raw Magnific output (island, hole, padded upscales) |
| `godot/game/dev/terrain_lab/art/` | Tool output (+ `.import` settings: mipmaps on the sheets, lossless edges) |
| `godot/game/world/terrain_edges/terrain_edges.gd` | Dual-grid tile picker (`@tool`) |
| `godot/game/world/terrain_edges/terrain_edges.gdshader` | Edge overlay shader |
| `godot/game/world/terrain_edges/ground_world.gdshader` | World-space ground swatch shader |
| `godot/tools/build_terrain_lab.gd` | Builds the lab scene, tile sets and materials |
| `godot/game/dev/terrain_lab/terrain_lab.tscn`, `.gd`, `*.tres` | The lab (built; `terrain_lab.gd` is the camera) |
