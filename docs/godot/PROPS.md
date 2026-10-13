# Props: scenery painted from a palette

> **Status:** first version, 2026-10-13. level-1, the chunk worlds and the interiors (gloop-hut,
> gloop-cavern, mushroom-home, slime-home) had their placed scenery absorbed into prop layers (about
> 2,600 props). The dev worlds still hold their props as nodes.

Placing scenery one scene at a time meant knowing every scene's name and left world scenes with
thousands of nodes. A **prop layer** is a palette instead: pick a wall, a rock, a lily pad or a
kitchen shelf by its picture and paint it. Nothing is random: a painted cell shows exactly the prop,
size and mirror painted there. The original scenes stay; a prop with its own logic (a secret, a
resource, a gate, a liftable rock) is still placed as a normal instance.

## Using it

1. A world gets its layers from `tools/absorb_props.gd` (below), or by hand: **Add Node >
   PropLayer** (same position as the ground layer) and set its **Tile Set** to
   `game/world/props/walls_tileset.tres` (name the node `walls`) or `props_tileset.tres` (`props`).
2. Select the layer; the TileMap panel at the bottom lists the palette's sources on the left:

   | Layer | Grid | Sources |
   |---|---|---|
   | `walls` | 64 units: a drag or a line paints one clean row | stone walls, rock walls, crystal walls, houses |
   | `props` | 8 units: anything, anywhere | nature, rocks, water life, trees, ground (pebbles, roots, petals...), every interior set, and the walls and houses again for off-grid spots |

3. Click a prop and paint; erase to remove. **Sizes:** a sized source (nature, rocks, trees, ground,
   crystal walls, interior decor and mushroom decor) shows one row per prop, from 50 % to 130 % of
   its size; pick the size you want. **Mirror:** the TileMap panel's flip-horizontally button paints
   the prop mirrored.
4. `paint_opacity` (Inspector) shows the palette squares over the props (0 hides them; always hidden
   in the game).

Each prop stands at its tile's **anchor** in the cell: on the `props` layer the cell's corner, on
`walls` where that scene usually stood on the 64 grid (a stone wall at the cell's bottom middle,
crystal clusters 10 units higher). Props on raised ground stand at level 0, as placed ones do.

## How it works

`game/world/props/prop_layer.gd` (`PropLayer`, `@tool`, a TileMapLayer): every painted cell gets an
instance of its tile's scene (custom data `prop_scene`) at the cell plus the tile's anchor
(`prop_anchor`), its `Visual` scaled by `prop_size` and mirrored when the cell's tile is flipped. The
instances live in an unowned child `Props` (y-sorted with the world), so the scene saves only the
cells and the editor neither lists nor selects them; they keep their collision and idle animations.
The layer updates only the cells that changed when you paint.

`tools/build_prop_palettes.gd` (windowed: it renders) builds the palettes: every scene under
`game/scenes/objects/` whose path matches a source and whose only scripts are presentation (idle
animation, sound) gets a thumbnail rendered with the game's own drawing
(`godot/asset/MAPS/palettes/<layer>-<source>.png`) and a tile in the tile set (written as text).
Scenes with gameplay scripts (resources, collectibles, chests, beds, workbenches, bridge decks,
liftables...) stay out. `game/world/props/prop_palettes.json` keeps each scene's place and anchor,
so a rebuild never moves a painted prop: new scenes are appended, a deleted one leaves a gap. Run
it after adding scenery scenes, then let the editor import the images.

**Absorbing placed props:** `tools/absorb_props.gd` (headless: `--path godot -s
res://tools/absorb_props.gd -- --scene=<world> [--scene=...] [--dry]`) turns every instance of a
palette scene in a world into a painted cell and removes it, making the `walls` and `props` layers
when missing. A prop goes on the `walls` layer only when it sits exactly on its grid, else on
`props` (moved at most 4 units). Its Visual's size becomes the nearest size tile (within 0.06),
its mirror the flip, its Visual offset part of its position. A prop stays a node when anything
else about it would be lost: other overrides, extra children, groups, signal connections, a size
outside 50-130 %, or a cell already taken. The tool reports the kept ones by reason and puts back
the uids Godot's headless save drops. Close or reload the world in the editor afterwards.

## Limits

- One prop per cell per layer; two props closer than the grid need the other layer or a node.
- `tools/split_region_chunks.gd` does not cut prop layers yet: absorb a region's chunks after
  cutting it.
- Painted props have no save ids: anything the game must remember per prop stays a placed scene.

## Files

| Path | What |
|---|---|
| `godot/game/world/props/prop_layer.gd` | The layer: instances, sizes, mirror |
| `godot/game/world/props/walls_tileset.tres`, `props_tileset.tres` | The palettes (tool output) |
| `godot/game/world/props/prop_palettes.json` | Each scene's place and anchor in the palettes |
| `godot/asset/MAPS/palettes/` | The thumbnails (tool output) |
| `godot/tools/build_prop_palettes.gd` | Builds the palettes |
| `godot/tools/absorb_props.gd` | Turns placed props into paint |
