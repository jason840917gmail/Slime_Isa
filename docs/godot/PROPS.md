# Props: scenery painted from a palette, or placed from the Scenery dock

> **Status:** 2026-10-14. Scenery comes two ways: the mass of small things painted, and the props to
> place and nudge one by one dragged in as nodes from the **Scenery dock** (below). Trees are
> painted only on the forest layer ([FORESTS.md](FORESTS.md)). Since 2026-10-13 (evening) new
> scenery is painted on two layers sized to the world's 64-unit cell:
> `cell-props` (64 units) and `details` (32 units), in every world that has prop layers (level-1,
> the chunk worlds, the interiors). What was painted before stays where it is on the older layers,
> `old-props` (8 units) and `large-props` (64 units): about 2,300 props absorbed earlier that day from
> the scenes placed by hand. The dev worlds still hold their props as nodes. Built stone walls have
> their own layer, the WallLayer ([WALLS.md](WALLS.md)).

Placing scenery one scene at a time meant knowing every scene's name and left world scenes with
thousands of nodes. A **prop layer** is a palette instead: pick a rock, a lily pad or a kitchen shelf
by its picture and paint it. Nothing is random: a painted cell shows exactly the prop, size and
mirror painted there. A painted prop is no node: it cannot be selected or dragged like one. For the
props you want to place freely and move around, the **Scenery dock** lists the same pictures, and
dragging one into the map places the prop's scene as a normal node. A prop with its own logic (a
secret, a resource, a gate, a liftable rock) is placed as a normal instance too.

## The Scenery dock: props as nodes

The **Scenery** dock (right side, beside the Inspector; the `scenery_dock` editor plugin) shows every
prop of the `cell-props` and `details` palettes by its picture: pick a category, or type in the
search box to look through all of them by name. Pick a **Size** (small 70 %, normal, big 130 %),
then **drag a picture into the 2D view**: the prop's scene is placed there as a node under the
world's `Scenery` node (made when missing, y-sorted with the world), at that size (its Scale). It is
an ordinary node: select it, move it freely, mirror or scale it, edit it in the Inspector, delete it
with Delete; Ctrl+Z undoes the drop. **Reload** reads the palettes again after
`tools/build_prop_palettes.gd`. Use it for the props you place one by one; paint the mass of small
scenery (grass, flowers, pebbles, leaves) on the layers below, which keeps the scene tree small.

**Painted props to nodes:** `tools/paint_to_nodes.gd` (headless, the world closed in the editor:
`--path godot -s res://tools/paint_to_nodes.gd -- --scene=<world> [--scene=...] [--keep=<prefixes>]
[--dry]`) turns a world's painted props into nodes under `Scenery`, each picture exactly where the
painted one was, and erases their cells; props whose scene path starts with a `--keep` prefix stay
painted (by default the ground details and the water life). A node's size and mirror are its own
Scale (negative x when mirrored), as for props dropped from the dock, so its collision follows its
size (a painted prop's collision kept the scene's size). The four level-1 chunks had theirs turned on
2026-10-14: 120 props became nodes (13 mirrored, 22 resized), 745 stayed painted.

## Using it

1. Select the world's `cell-props` or `details` layer (a new world: **Add Node > PropLayer**, same
   position as the ground layer, its **Tile Set** `game/world/props/props_cell_tileset.tres` or
   `props_detail_tileset.tres`). The TileMap panel at the bottom lists the palette's sources on the
   left:

   | Layer | Cell | Sources |
   |---|---|---|
   | `cell-props` | 64 units, a ground tile | nature, rocks, water life, rock walls, crystal walls, houses, every interior set |
   | `details` | 32 units, a quarter of a ground tile | ground: leaves, branches, roots, pebbles, petals, clover, flowers, mushrooms, moss, stones |

2. Every prop takes a **block of whole cells** just big enough for it: a flower, a rock or a lily
   pad 1 x 1, a fence 2 x 1, a lamp post 1 x 2, the campfire or the tent 2 x 2, the well or a house
   more. The palette shows the props at their true size, each block on the palette's own grid, so a
   palette square is a map cell. Click a prop and paint: the cell you click is the block's
   **bottom-left** cell, and the prop stands centred in the block on its floor. The brush preview
   and the painted squares show the prop exactly where it will stand.
3. **Sizes:** a sized source (nature, rocks, crystal walls, interior decor, mushroom decor, ground) shows each prop three times side by side: small (70 %), normal and big (130 %).
   "Normal" is the prop's own size, or a little smaller when that lets it fit a block of one or two
   cells (a picture up to 25 % bigger than the block is shrunk to fit it; bigger props keep their
   size). **Mirror:** the TileMap panel's flip-horizontally button paints the prop mirrored, about
   the painted cell's middle (a 2-wide prop then covers the cell and the one to its left), exactly
   as the preview shows it.
4. **Erase:** right-click (or the eraser) on the painted cell, the block's bottom-left one.
5. `paint_opacity` (Inspector, 0.3 by default) draws the painted tiles faintly over the props in
   the editor, as the forest layer does (0 hides them; always hidden in the game). The TileMap
   toolbar's grid button (or **Editor Settings > Editors > Tiles Editor > Display Grid**) hides the
   cell lines.

Props on raised ground stand at level 0, as placed ones do.

### Free placement: `old-props`

`old-props` (8-unit cells, `props_tileset.tres`) holds the props absorbed on 2026-10-13 from the
scenes placed by hand, and stays the layer for placing a prop anywhere: its fine grid puts a prop's
foot on any 8-unit spot (the cell's corner). Its palette (`tools/build_old_prop_palettes.gd`) shows
every prop at its true size, each tile at least a 64 px square (32 px for the ground details) so it
is easy to see and pick. A sized source gives small, normal (the prop's true size) and big (130 %);
the small one fills about one such square (never under 70 %), and a prop already that small has
only normal and big. Sizes painted that the palette no longer offers are kept as hidden
alternatives of the prop's normal tile (`legacy` in the manifest: 191 of them). The brush preview
shows the prop where it will stand, except a mirrored one, 8 units right (Godot mirrors a tile about
its cell's middle, these props mirror about their foot).

`large-props` (64-unit cells, `walls_tileset.tres`) holds the rock and crystal walls and houses
absorbed on the 64 grid; its palette is kept as it is.

## How it works

`game/world/props/prop_layer.gd` (`PropLayer`, `@tool`, a TileMapLayer): every painted cell gets an
instance of its tile's scene (custom data `prop_scene`) at the cell plus the tile's anchor
(`prop_anchor`, where the scene's origin goes so its picture is centred in its block), its `Visual`
scaled by `prop_size` and mirrored when the cell's tile is flipped; with `prop_mirror` (the
`cell-props` and `details` palettes) a mirrored prop is also moved so it mirrors about the painted
cell's middle, as Godot draws the mirrored tile. The instances live in an unowned child `Props`
(y-sorted with the world), so the scene saves only the cells and the editor neither lists nor
selects them; they keep their collision and idle animations. The layer updates only the cells that
changed when you paint.

`tools/build_prop_palettes.gd` (windowed: it renders) builds the `cell-props` and `details`
palettes: every scene under `game/scenes/objects/` whose path matches a source and whose only
scripts are presentation (idle animation, sound) is measured by its visible pixels, given its block,
rendered with the game's own drawing at its true size, a unit a pixel, into its slot of
`godot/asset/MAPS/palettes/<palette>-<source>.png` (blocks packed in rows, a scene's three sizes
side by side, a sheet about three times wider than tall), and written as a tile covering that slot
(`size_in_atlas`) whose texture origin puts the texture's bottom-left cell on the painted cell.
Scenes with gameplay scripts (resources, collectibles, chests, beds, workbenches, bridge decks,
liftables...) stay out.

`game/world/props/prop_palettes.json` keeps each scene's place and each tile's slot, so a rebuild
never moves a painted prop to another tile: new scenes get new slots after the last row, a deleted
one leaves a gap, and a source taken out of the builder's list stays as a retired source with no
tiles (its id is kept). A prop whose picture outgrew its block gets a new slot, and the builder
moves the painted cells of every world that used the old one. Run the builder **with the editor
closed** (the editor would save its own copies of the tile sets and worlds over the new ones), after
adding scenery scenes; then open the editor to import the images. `tools/build_old_prop_palettes.gd`
builds the `old-props` palette ("props" in the manifest) the same way: true-size pictures in slots of
16 px squares (at least 64 px, 32 for the ground), a foot-anchored tile per size, painted cells moved
when their tile moves, sizes no longer offered kept as `legacy` alternatives. The `large-props`
palette ("walls") is kept as it is. Both builders share `tools/lib/prop_pictures.gd` (scenery scenes,
visible-pixel measuring).

**Absorbing placed props:** `tools/absorb_props.gd` (headless: `--path godot -s
res://tools/absorb_props.gd -- --scene=<world> [--scene=...] [--dry]`) turns every instance of a
palette scene in a world into a painted cell of the older layers and removes it, making the
`large-props` and `old-props` layers when missing: their fine grid keeps a prop where it stood. A
prop goes on `large-props` only when it sits exactly on its grid, else on `old-props` (moved at most
4 units). Old stone walls are converted by `tools/convert_stone_walls.gd` instead
([WALLS.md](WALLS.md)). Its Visual's size becomes the nearest size tile (70, 100 or 130 %, within
0.06), its mirror the flip, its Visual offset part of its position. A prop stays a node when
anything else about it would be lost: other overrides, extra children, groups, signal connections,
another size, or a cell already taken. The tool reports the kept ones by reason and puts back the
uids Godot's headless save drops. Close or reload the world in the editor afterwards.

## Limits

- One prop per cell per layer; a prop's block may overlap its neighbours' (only the painted cell is
  taken).
- `tools/split_region_chunks.gd` does not cut prop layers yet: absorb a region's chunks after
  cutting it.
- Painted props have no save ids: anything the game must remember per prop stays a placed scene.

## Files

| Path | What |
|---|---|
| `godot/game/world/props/prop_layer.gd` | The layer: instances, sizes, mirror |
| `godot/game/world/props/props_cell_tileset.tres`, `props_detail_tileset.tres` | The `cell-props` and `details` palettes (tool output) |
| `godot/game/world/props/props_tileset.tres`, `walls_tileset.tres` | The `old-props` palette (tool output) and the older `large-props` one (kept) |
| `godot/game/world/props/prop_palettes.json` | Each scene's place and each tile's slot |
| `godot/asset/MAPS/palettes/` | The palette pictures (tool output) |
| `godot/tools/build_prop_palettes.gd` | Builds the `cell-props` and `details` palettes |
| `godot/tools/build_old_prop_palettes.gd` | Builds the `old-props` palette |
| `godot/tools/lib/prop_pictures.gd` | What the builders share: scenery scenes, visible pictures |
| `godot/tools/absorb_props.gd` | Turns placed props into paint (older layers) |
| `godot/addons/scenery_dock/` | The Scenery dock: props by picture, dragged in as nodes |
| `godot/tools/paint_to_nodes.gd` | Turns painted props into nodes under `Scenery` |
