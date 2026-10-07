# Terrain edges: hand-made transitions between grounds

> **Status:** in every world since 2026-10-05. The owner approved the terrain lab and asked for
> edges on every ground, water shores included. The lab
> (`godot/game/dev/terrain_lab/terrain_lab.tscn`) is the showcase and the place to try new art.

## Owner decisions (2026-10-05)

- **Art density: 128 px of art per 64-unit cell** (2 px per world unit). The grid stays 64 units,
  so maps, collision, speeds and coordinates do not change; only the art gets sharper. 256 px was
  rejected: at the 1280×720 base view a cell covers 96–120 screen px on 1080p (192–240 on 4K), so
  128 px is sharp on 1080p at every zoom, while 256 px would cost 4× the memory and download (a
  19×19 ground sheet would be 4864 px, above many phones' 4096 px texture limit).
- **Transitions are hand-made tiles**, not a code blend like Phaser's `TerrainBlendField`. The art
  is generated with Magnific (GPT 2.5) and cut into tiles by a tool.

## What you see

Where two grounds meet, the higher one's border is drawn as painted art over the lower one: grass
tufts over sand, a sandy rim over water, fallen leaves over grass, crystal shards over cavern rock.
Corners are rounded; a one-cell hole is round; the plain ground continues without seams.

**The lab:** open `godot/game/dev/terrain_lab/terrain_lab.tscn` and press F6 (WASD or arrows pan,
the mouse wheel zooms, Home resets, **T switches the edges off and on**). It has every pair the
worlds have: a beach lake with a deep middle, ponds ringed by moss and fallen leaves, moss on
forest soil, crystal in snow, a cobble road through grass, a cavern with crystal, deep water and a
rock wall. To paint: select `Ground`, open the TileMap panel's Tiles tab and paint with any
terrain source; the edges and the water follow, in the editor too (painted frames snap to the
cell's sheet-wrap frame).

## How it works

`game/world/terrain_edges/terrain_edges.gd` (`TerrainEdges.mount(ground)`, called by
`WorldService.register_world` right after the water surface) adds a `TerrainEdges` node under the
ground layer with four TileMapLayers on a **dual grid**: half a cell up and left, so each of their
cells covers the corner shared by four ground cells.

1. Each ground cell's **ground** comes from its tile id (`TerrainMaterials.TILE_GROUNDS`: the
   authored tile set's transition material; `water` and `deep-water` are one water ground).
2. Grounds **stack** in `TerrainMaterials.ORDER`, bottom to top: water < cavern floor < forest
   floor < sand < grass < fallen leaves < snow < cobble < moss < crystal. That keeps Phaser's
   transition priorities (water 4–5 < natural grounds 10 < cobble 12 < moss, crystal 20) and breaks
   the ties so the ground that "lies on top" wins.
3. At a corner where grounds meet, **level 0** fills the corner with the lowest of them (its fully
   covered tile, or the animated water), and **each higher ground** draws its edge tile on the next
   level: index = TL + 2·TR + 4·BL + 8·BR, with 1 where the cell's ground stacks at least that
   high. Corners with one ground, a hard-edged tile (rock wall, wood and mushroom floors), the
   map border, or cells of different elevation levels (the cliff draws its own rims there,
   [ELEVATION.md](ELEVATION.md)) get nothing.

The edge tiles are art. Alpha is where the ground covers, colour its painted rim, and a second
image with the same layout (`…-edges-rim.png`) says where that rim shows.
`terrain_edge.gdshader` draws the ground's own sheet there in world space, at the texel the ground
layer shows (sheet-wrap: position mod 1216), so an edge tile meets the plain cells around it with
no seam; uncovered pixels are transparent and the level below shows.

**Shores.** Water is the lowest ground, so land edge tiles draw over a water fill.
`terrain_edge_water.gdshader` draws exactly what the water surface draws: both include
`game/world/water_surface.gdshaderinc` and the fill copies the surface's mask, sheets and grid. The
`TerrainEdges` node is a child of the ground after `WaterSurface`, so it draws over the surface and
the shore foam shows only on the water side of the land's rim.

Visual only: the ground cells stay the gameplay truth (walkability, collision, footsteps).

**Cost** (web build, headless Brave on the owner's machine, 2026-10-05): level-1 adds about 2,400
edge tiles. Every measured view still holds 60 fps; uncapped, the busiest view (town) runs at
211 fps (4.7 ms a frame). At the lake, draw calls go from 339 to 374, and the web pack grows by
0.5 MB.

### Why a dual grid, not Godot's terrain brush

Godot's "Match Corners" terrain mode decides each corner by the majority of the cells around it and
puts tiles on the painted cells themselves. In a probe a painted 2×2 block came out with a hole in
its middle, a single cell lost a corner, snow spilt half a cell past what was painted, and the
edges had to be painted on a separate layer from the gameplay ground. The dual grid is the usual
fix: you paint the ground, the tiles follow.

**Comparison lab:** `game/dev/terrain_lab/terrain_layers_lab.tscn` (built by
`tools/build_terrain_layers_lab.gd`) draws the lab's layout with Godot's Terrains only, with a free
painting area at the top that the builder keeps. Its tile set (`terrain_layers_tileset.tres`) is one
"Match Corners and Sides" terrain set, tagged the way the owner set up sand, snow and cobble in the
TileSet editor (2026-10-05): a corner or a side is the ground where the art covers it, and only the
tiles with three or four covered corners carry the ground as their centre. Every ground has its own
TileMapLayer in `ORDER`, painted in Connect mode as the Terrains tab paints (empty cells vote:
`ignore_empty_terrains = false`; GDScript's default `true` paints nothing for one-cell features).
Copy A paints each ground only on its own cells; copy B also paints it under the grounds above it.

`tools/compare_terrain_edges.gd` measures both systems on the same cells (run it windowed; it
writes `report.md` and pictures). Results on 2026-10-05:

- **Shapes:** the dual grid shows each cell's own ground on 99.5% of the drawing; Godot Terrains
  on 88%. With the owner's tagging, Godot puts a rim on the cells around the painted ones, so every
  ground grows about half a cell over its neighbours; one-cell-wide features survive but come out
  two cells wide, and with only 16 tiles (the mode wants 47) neighbouring tiles disagree in places.
- **Shores:** the visible shore sits +1 unit from the collision line with the dual grid, +16 to
  +20 units into the water with Godot Terrains (half a cell is 32).
- **Paint order:** the dual grid gives the same tiles in any order. Godot's depend on how you
  paint: one stroke, a slow drag (cell by cell), going over twice, or erasing half a shape give
  different tiles, and a slow drag leaves notches.
- **level-1:** dual grid 2,448 edge tiles on 4 layers, built in 7 ms; Godot Terrains 5,197 tiles
  on 11 layers in 553 ms (23,641 tiles and 2.4 s with every ground also under the higher ones). On
  a game-sized view Godot's layers draw in 6 to 9 draw calls, the dual grid's view in 527, of which
  396 are the plain ground layer and water: one layer per ground batches far better.

### Why the grounds are drawn in world space

In the first try each edge tile carried its own painted ground: that showed a lighter band around
every area, where the generated texture met the ground sheet, and square holes. With world-space
sheets the tiles only decide where each ground shows and where its rim is.

## Making edge art for a ground

1. Generate two images with Magnific (`gpt-2-mini`, 1:1, 1k, `transparentBackground: true`;
   [Magnific guide](../assets/magnific-mcp-guide.md)), each prompt starting with the style block,
   with **two references**: a 1024 px crop of the ground's sheet, and the snow island (or snow hole)
   as the composition reference, so every set shares the same geometry.
   - **Island:** "one flat patch lying on the ground, seen from above, shaped as a square with
     softly rounded corners, centered, filling about two thirds of the frame, its border running
     straight along each side. The patch is made of <ground>… The patch border is natural and
     irregular: <rim>…, the same width all around. Terrain only, no outline… Isolated on a
     transparent background…"
   - **Hole:** "a flat field that fills the whole frame edge to edge… with one round hole in the
     exact center about one third of the frame wide; inside the hole there is nothing, fully
     transparent…"
   Generate two of each and keep the cleanest (a hole filled with a half-opaque fog is unusable;
   a faint fog is cleaned by the tool). Save them as
   `asset/Originals/grounds/generated/terrain-edges/<ground>-island.png` and `<ground>-hole.png`.
2. Add the ground to `MATERIALS` in `scripts/art/build-terrain-edge-tiles.py` (its 64 px sheet,
   the colour reference) and run `python scripts/art/build-terrain-edge-tiles.py <ground>
   [--preview DIR]` (needs numpy and Pillow). The tool:
   - finds the island's rim and the hole's circle (clearing generator fog from the hole);
   - scales them so every border crosses a tile side at its midpoint;
   - cuts the 16 tiles (convex corners and straight sides from the island, inner corners from the
     hole, diagonals from two corners), picks straight windows whose ends match, and blends every
     tile's border strips to a shared join, so any two tiles that can touch match exactly;
   - writes `godot/game/world/terrain_edges/art/<ground>-edges.png` (528 px with 2 px gutters) and
     `<ground>-edges-rim.png`.
3. Let the editor import them (edge sheets lossless, `compress/mode=0`), add the ground to
   `TerrainMaterials` (`ORDER`, `TILE_GROUNDS`) and run `pnpm test:godot --filter=terrain_edges`.

The 2026-10-05 sets (9 grounds) used about 4,000 Magnific credits.

## Limits

- Three or four grounds at one corner: an intermediate ground is drawn under the higher ones over
  their whole quadrant, so its rim can peek out between a higher ground and a lower one.
- Very small features stay blocky: a one-cell strip is a cell wide with rounded ends.
- Hard-edged tiles (rock wall, wood and mushroom floors) keep hard edges, as in Phaser.
- Water and deep water blend inside the water surface itself (its deep factor), not with tiles.

## Next steps

1. Regenerate the ground sheets at 128 px per cell (about 180 credits each; the tool's
   `--grounds-2x` turns padded Magnific upscales into seamless 2432 px sheets) and draw grounds and
   edges from them.
2. Variants: more islands per ground as alternative tiles, so long straight borders repeat less.

## Files

| Path | What |
|---|---|
| `scripts/art/build-terrain-edge-tiles.py` | Art tool: 16 edge tiles + rim weights per ground |
| `asset/Originals/grounds/generated/terrain-edges/` | Generated islands and holes (and padded upscales) |
| `godot/game/world/terrain_edges/art/` | Tool output (+ `.import`: edge sheets lossless) |
| `godot/game/world/terrain_edges/terrain_edges.gd` | `TerrainEdges`: the dual-grid tile picker (`@tool`) |
| `godot/game/world/terrain_edges/terrain_materials.gd` | Grounds, their stacking order and art paths |
| `godot/game/world/terrain_edges/terrain_edge.gdshader`, `terrain_edge_water.gdshader` | Land edges and the water fill |
| `godot/game/world/water_surface.gdshaderinc` | The water maths shared by the surface and the shores |
| `godot/tools/build_terrain_lab.gd` | Builds the lab scene |
| `godot/tools/build_terrain_layers_lab.gd` | Builds the comparison lab (Godot Terrains, a layer per ground) and its tile set |
| `godot/tools/compare_terrain_edges.gd` | Measures the dual grid against Godot Terrains: shapes, shores, paint order, level-1 |
| `godot/game/dev/terrain_lab/` | The lab (`terrain_lab.gd` camera and T toggle, `terrain_lab_ground.gd`) |
| `godot/tests/test_terrain_edges.gd` | Coverage, stacking, shores, hard edges, level-1 |
