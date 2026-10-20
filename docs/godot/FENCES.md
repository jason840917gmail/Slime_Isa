# Paintable fences

> **Status:** seven styles in **Fence Park** (`?map=fence-park`, `-- --map=fence-park`). Paint every
> fence on one `fences` layer, on ordinary ground or any elevation. The picture palette shows the
> material and connection direction. Fences add their own shadows and level-matched collision;
> elevation rims remain independent.

## The rule

There is one `fences` TileMapLayer and one renderer everywhere. A fence tile chooses a material and
one of eight directions, connects to neighboring painted cells, and brings its own collision and
ground shadow. Fences never paint or change elevation rims. Placement is explicit in the scene; the
runtime does not infer fences from cliff edges.

## What you see

A fence is built at the cells painted on the `fences` layer. A post stands at each painted cell
(its foot at the cell's centre); rails span to the neighbours it links to. The eight arrow pictures
show which neighbour a tile selects; the all-neighbour picture joins every all-neighbour neighbour.
Cells on different elevation levels never join. Each of the eight style columns is one fixed style:
wood, snow-capped wood, stone, sandstone, twig, picket, crystal and the Lair's dungeon divider (the
ground never chooses it); the two columns after them hold the divider gates' tiles
([Dungeon dividers](#dungeon-dividers)).

| Direction | What shows |
|---|---|
| North, east, south or west | rails join the selected neighboring cell along that direction |
| North-east, south-east, south-west or north-west | rails join the diagonal neighbor; posts stay upright and the rail face is shaded with the direction of the light |

Posts and rails Y-sort with bodies and write a silhouette into the elevation depth map. Shadows fall
to the lower right, with a contact shadow at each post. A fence in a hole darkens with depth like
the cliffs ([ELEVATION.md](ELEVATION.md)).

## Authoring fences

Each world has one `fences` TileMapLayer beside `ground` (and `elevation`, when it has one), using
`game/world/fences/fence_tileset.tres` and `game/world/fences/fence_layer.gd`. Paint one tile in
every cell where a fence post should stand. Choose its style by the column and its connection by the
row. The renderer uses that paint for art, soft shadows, depth and collision. Fences never create or
reshape cliff rims, and leave elevation painting and caches alone.

The palette (`scripts/art/build-fence-paint-tiles.py` writes it and the TileSet) has one column per
style (columns 0–7). Its top row is the all-neighbour tile; the eight rows below are the north,
north-east, east, south-east, south, south-west, west and north-west arrows. Columns 8 and 9 hold the
divider gates' tiles (the eye at (8, 0), the pen at (9, 0), their pictures the gates themselves), at
fixed places: a style added later takes column 10 and on, so no painted tile ever moves.

**When two cells link** (`Fences._can_link`): never across levels; two all-neighbour tiles always;
otherwise only where an arrow points, the first cell's arrow at the second or the second's arrow
back at the first. An arrow tile therefore refuses every neighbour it does not point to and that
does not point at it, all-neighbour tiles included. Paint arrows where two runs pass one cell apart
(two all-neighbour runs one row apart would join across); a run of east arrows joins only along its
row. A diagonal link is skipped when a two-link cardinal route already joins the same cells, so
corners do not get a doubled brace; it stays where direction or level blocks that route.

**Mixed styles:** a link's rails take the style of the cell whose arrow asks for it; between two
all-neighbour tiles (or two arrows pointing at each other) the north-west cell's style (the first
in reading order, north to south then west to east). Each post keeps its own cell's style.

**A lone tile** (no links) is a short fence of two posts: its own at the cell's centre and a second
half a cell the way its arrow points (on the cell's edge; a diagonal's on its corner), the rail
between them. A lone all-neighbour tile has no arrow and points east (`Fences.lone_stub`).

**Level:** a fence takes the level of its cell on the `elevation` layer (level 0 in a flat world). A
fence on a stairs or ramp cell takes the level that cell is built at, the ground the flight leads
down to (`Elevation.painted_levels`); avoid painting fences on stairs.

**Collision** is thin and sits at the rails' feet, so a body stops where the art says
(`game-constants.json` `fences`, read once per build): every link is one band from post foot to post
foot, from `bandAbove` (10) to `bandBelow` (2) units above the posts' foot line (8 thick; a 45° link
the same band, rotated); a north-south link is `sideHalfWidth` (7) each side of the post column
instead; every post is a rect at the band's height as wide as its kit draws the post (`posts.half_width`
of `<style>.json` each side: about 12 wide for wood, 24 for the Lair divider), 8 tall; a lone tile is
its two posts and the band between them; a divider gate's cell is a band from each post beside it to
the gate's block, the block being the gate's own body ([Dungeon dividers](#dungeon-dividers)). From the north a body's feet stop 10 above the posts' feet, its lower part hidden behind the
rails; from the south its head stops 2 above them, overlapping the feet a little (the Zelda overlap).
Run ends are open; corners are closed by the posts. Each level's collision is a static body on its
`level <n>` physics layer. In a world without levels (no `elevation` paint, no Elevation to put a
body on a level layer) the level-0 body is on the `world` layer instead, as a wall is, so every
walker meets it (2026-10-19; before, the Lair's flat rooms' dividers stopped nothing; whatever else
collides with walls, a thrown thing or a ray, meets such a fence too). `Fences.blocks_rect` and
`blocks_sweep` test the same boxes, so
`Elevation.body_fits` (landings, hop steps) checks a body's whole rect and `ledge_below` the whole
way from its side to its ledge probe: a hop or a drop never passes a band thinner than the body.

In the editor, a paint stroke rebuilds only the fences (on the Elevation's grid and depth map when
the world has one); hide the `fences` layer (eye icon) to see the generated fence without its paint
figures. The pieces stay while the scene's tab is in the background and go with the fences node
(freed, not merely out of the tree). The game hides the paint layer; an exported game has no palette
pictures (the Scenery plugin's export step, `addons/scenery_dock/palette_export.gd`, strips
`fence_paint_tiles` from the tile set: the fences read only the tiles' data). A painted cell outside
the world's grid is not built; it is named in a warning once a session.

World scenes now use this same `fences` layer for every painted fence. There is no separate ground
layer or cliff-edge mode.

## How it works

`Elevation.rebuild()` calls `Fences.mount(ground, self, grid, occlusion, collide)`
(`game/world/fences/fences.gd`); a flat world (no `elevation` layer) calls the same mount from
`Elevation.mount` with no elevation, and the fences go beside the ground layer on a level-0 grid of
the map's size. Only the node's parent, the cell levels, the depth map and the collision's physics
layer (`world` on flat ground) differ; paint, links, art, shadows and collision boxes all use one
path. Of the elevation the fences use only `ElevationGrid` (a
cell's level), `ElevationOcclusion` (the depth map), the mesh helper and the shader includes.

- **Connections** (`connected_links`): each linked neighbouring pair (above) is drawn once.
- **Pieces and depth.** Posts and rails are generated `MeshInstance2D` nodes under a Y-sorted
  `FencePieces` holder beside the ground layer. Their material comes from the style kit and
  `fence.gdshader`. Each opaque piece writes its level and height into the depth map
  (`fence_depth.gdshader`, `ElevationOcclusion.add_occluder`; a rebuild of the fences alone takes
  its old silhouettes out again), so fences sort with bodies and terrain.
- **Shadows and collision.** Posts cast contact and soft shadows; the collision boxes are above.

## Making the art

A style is one Magnific image (`gpt-2-mini`, `transparentBackground: true`, 21:9,
[Magnific guide](../assets/magnific-mcp-guide.md)), the style block first, then: "A game sprite of
one long straight rustic wooden rail fence seen from the front, running horizontally across the whole
width of the image: five thick round wooden posts evenly spaced, each with a rounded weathered top
that shows a little of its top face, joined by two chunky horizontal split-log rails (an upper rail
and a lower rail) that run behind the posts from the left edge of the image to the right edge. The
posts stand perfectly upright, the rails are perfectly straight and horizontal, the bottoms of all
posts sit on one straight baseline. Same wood, colours and painting as the wooden fence in the
reference sheet. Isolated on a transparent background, no ground, no grass, no ground shadow plate,
no scenery." References: the decorations sheet with the game's wooden fences
(`godot/asset/MAPS/decorations/128x128-tile_8x3.webp`) and the mushroom furniture style sheet.

The other styles were generated with the wood front view (`wood-front-b.png`) as their first
reference, "exactly the same layout", and the material in the prompt: snow caps and icicles; square
stone pillars with a lower dry-stone wall between them (the cliff sample as a second reference);
rounded sandstone pillars with an adobe-brick wall; gnarled branch posts with vine-wrapped branch
rails; tall pointed posts with a row of shorter pickets; crystal clusters on rock bases with two taut
ropes. Every source is in `asset/Originals/fences/` (`<style>-front-a.png` is used, `-b` is
the spare).

`python scripts/art/build-fence-art.py [style ...] [--preview DIR]` (numpy, Pillow) finds the posts
(the most opaque columns, `post_share` of the most opaque one) and the rails (rows opaque between the
posts), scales the post to `post_height` (40 units for wood) at 2 px per unit and writes the kit into
`godot/asset/MAPS/fences/`: `<style>-posts.png` (every post, feet on one row, the rails
behind them removed, moss kept), `<style>-rails.png` (the rails between posts joined into a strip that
repeats sideways), `<style>-rails-side.png` (the upper rail turned a quarter left: seen from above,
lit on its left; for a wall its whole band, for pickets their tips, squeezed to `side_width`) and
`<style>.json` (the measures). A new style is a new entry in its `STYLES` and a new palette column:
add it at the end of `STYLES` in `scripts/art/build-fence-paint-tiles.py` and run it (it writes the
palette picture `fence_paint_tiles.png` and `fence_tileset.tres`), then
`"<Godot console exe>" --headless --path godot -s res://tools/pack_fence_paint_tiles.gd`, which saves
the picture as `fence_paint_tiles.res`, the native texture the tile set uses (no editor import). The
new style takes the next column after the gates' (10 on). Do not edit the TileSet by hand, and do not
insert a style before others: painted scenes store each cell's column and row.

The wood set used 400 credits (two front views, of which `wood-front-b.png` is used, and two rails
seen from above, unused: the turned front rail matches the front better); the other six styles 1,200
(two front views each).

## Styles

| Palette style | Look | Post height |
|---|---|---|
| `wood` | round posts, two split-log rails, moss at the feet | 40 |
| `snow` | the same with snow caps on posts and rails, icicles, drifts | 40 |
| `stone` | square stone pillars, a low dry-stone wall between them | 34 |
| `sandstone` | rounded sandstone pillars, a low adobe-brick wall | 36 |
| `twig` | gnarled branch posts, vine-wrapped branch rails, tiny mushrooms | 40 |
| `picket` | tall pointed posts, a row of shorter pickets, fallen leaves | 42 |
| `crystal` | crystal clusters on rock bases, two taut ropes | 44 |
| `lair-divider` | a dungeon divider: square fort-stone posts with capstones, low squared bars ([Dungeon dividers](#dungeon-dividers)) | 47 |

Every painted fence stands one post a cell, 64 units apart, whatever the style. The kits' JSON also
carries `spacing` and `inset` (64 or 80, 10 or 12), left from the cliff-edge fences of before; nothing
reads them now.

Walls fit the same kit: their pillars are the posts, the wall between them the rails, the wall seen
from above its side rail. All seven await the owner's verdict.

## Dungeon dividers

Inside a dungeon room a division is not a wall with a door (owner, 2026-10-19, after Zelda ALttP's
room dividers): it is a **divider**, a one-cell line of low stone posts with capstones joined by low
bars, painted on the `fences` layer like any fence (`lair-divider`, the Lair's fort stone; cave and
root styles later), with the fences' own collision. Its one special piece is a **divider gate**
(`object.divider-gate`, `game/dungeon/divider_gate.gd`, `game/scenes/objects/dungeon/divider-gate.tscn`)
on the cell between two posts:

- **eye** (`lair-divider-eye`): a carved stone block with an eye (44 units wide) that sinks into
  the floor: for secret or latch-opened passages (an eye latch, a bell);
- **pen** (`lair-divider-pen`): low iron bars (42 wide) that swing open on their west hinge and fold
  back flat behind the west rail, up against the west post (their tops show over the rail): for
  switch or key gates (a plate, a key).

Paint the gate cell with its gate tile (palette columns 8 and 9, row 0, their pictures the gates
themselves): the cell draws no post and the fence layer keeps a divider gate object on it under the
scene's `Objects` (`fence_layer.gd` `sync_gates`, as you paint, and only in the scene being edited: a
world shown inside another scene, such as the world atlas, gets no gates made there). A divider gate
already standing there (directly under `Objects` or in a folder in it) and not yet tagged is
adopted, else one is made, with a record of its own (its `GateScript`'s `gate_id`
`<room>-gate-<x>-<y>`, `map_id` the world's record id: `fatty-lair` in the Lair). Erasing the tile
removes a gate the layer made and nobody has changed since; a gate with a setting of its own (an
id, a message) or one placed by hand is never removed: the layer lets go of it with a warning and
adopts it again when its tile is painted back (Ctrl+Z), settings and all
(`game/world/painted_objects.gd`); delete it by hand when it should go.

**A shut gate closes its whole cell** (2026-10-19; before, its body covered 52 units and nothing
joined it to the posts, so a 31-unit hole on each side let the 30-wide slime through). The fences
treat the gate cell as part of the divider run (`Fences._add_gate_links`): the posts on each side of
it along its line join it whatever their arrows, with the divider's own rails from the post up to
the gate's block (the block's width from its picture, `DividerGate.block_half_width`) and their bands
from the post's foot to the block's edge; the rails' ends at the gate are finished with a slice of
the kit's post side (a north-south run: a slice of its front rails as the end's face), seen when the
gate is open. The gate's own body (`Doors`, 46 × 10, a unit past the block each side) covers the
block. The gate stands in the line its neighbours make (`Fences.gate_axis`: east-west when a fence
cell is painted east or west of it, else north-south); in a north-south line it turns its body with
the line (`DividerGate.fit_to_line`; its picture, a front view of the block or the bars, stays).

A divider cell beside a gate always joins it. One with no other neighbour keeps its stub only when
its arrow points away from the gate (a short fence on the far side, its second post on the cell's
edge, to meet a wall, as R7's gate and R5's alcove gate have); pointed at the gate, or an
all-neighbour tile, it is its post and the rails to the gate.

**A run's end against a wall reaches it** (2026-10-19, any fence, by itself): a painted cell joined
once (to a post or a gate) whose next cell the other way is a dungeon room's wall (the
`interior-walls` layer's `is_wall`) or a built wall (a `walls` WallLayer cell) gets the same stub, a
second post on its cell's edge at the wall's foot and the rail to it, with their collision
(`Fences._wall_beyond`). Before, a run ended on its last cell's middle post, 32 units short of the
wall, and the 30-wide slime walked through the gap (the Weigh House, R5). Paint the run up to the
cell beside the wall; no arrow is needed.

The gate's `GateScript` child (`game/scripts/gate.gd`) is the gate as before: plates, bells, eye
latches and keys find it by `gate_id`, its records are the gate's. A key gate takes an inventory key
(`required_item_id` the item), or a dungeon small key with `required_item_id` "small-key": a push with
one held in the current dungeon (DungeonState) opens it for good and spends the key. A push counts
only from the slime on the gate's level (`DungeonState.on_level_of`). The divider gate shows it shut
or open on the gameplay clock (650 ms) and opens the passage when the block has sunk or the bars
have swung (`GateScript.release_doors`), as in Zelda; a gate opened while its room is being built
(its record, a plate already held) shows open at once, without the dust. The picture sorts at the
gate's foot (a slime behind the gate is drawn behind it). It writes no silhouette into the depth
map (the fence pieces do; the gate is a moving sprite): a body behind it on a higher level is not
ghosted through it.

The Lair's latch doors and their fieldstone chunks became dividers on 2026-10-19 (R5, one world
again with its eye hall, lower hall and key alcove behind two dividers, the alcove's east side a
divider line where its fieldstone wall stood; R7, the Weigh House, the Old Armoury: each latch door's
node, `gate_id` and records
kept); R9's latch already stood in its north doorway, drawn by the room's wall (its slab the
wall's shutter leaf). The art: `asset/Originals/dungeon-kit/dividers/` (Magnific, GPT 2.5), the kit
cut by `scripts/art/build-fence-art.py lair-divider`, the gates' pictures
`asset/MAPS/objects/dungeon/divider-eye-block.png` and `divider-pen-gate.png`; the paint palette
by `scripts/art/build-fence-paint-tiles.py` then `tools/pack_fence_paint_tiles.gd` (a native
texture, no import needed).

## Test world

`python scripts/maps/build-fence-park.py` writes `godot/game/scenes/worlds/fence-park.tscn` (a dev
world, left out of the release export): connected fences on a level-1 square (with an east gap and
stairs down its south and west sides; the player spawns on it), a level-2 diamond, a level-1 octagon
with a level-2 octagon on top, a square and an octagon hole, a level-2 square fenced on its south
side only, a diamond fenced on its east half and a level-3 block, all wood. Below them are two rows
of plots on different grounds, each with its own hill (octagons, diamonds, squares, a terrace, a
hole) and explicitly painted materials, including styles that contrast with their ground.
`res://tools/render_fence_park.gd` renders it with the game's own drawing (windowed:
`--path godot -s res://tools/render_fence_park.gd -- --out=<dir>`), test slimes placed in front of and
behind the painted fences, and prints where a body with the player's collision stops at each kind of
fence and whether it can drop or hop there. Its connected-fence sample includes eight isolated directions on
ordinary ground, a connected twig run, and an all-neighbor wood run on a raised platform whose
other edges are not fenced. `asset/Originals/fences/wood-review.png` (the wood set)
and `styles-review.jpg` (every style, and bodies behind fences) are its output. `godot/tests/test_fences.gd` checks the same in the game.

## Limits and next steps

- Gates exist for the dungeon dividers only (painted gate tiles, [Dungeon dividers](#dungeon-dividers));
  the outdoor styles have none: leave an opening in the painted run for a world gate.
- A divider gate in a north-south line turns its body but keeps its front picture: a block reads
  right from any side, the pen's bars face south.
- Walls on a 45° run show only their front face, sheared, so they look thinner than on a straight
  run (no top face is drawn along the diagonal).
- The cut-away part of a body behind a fence follows the depth map's 2-unit grid, so its edge along
  a rail can step by a pixel or two where the sort could not put the body first.
- Enemies collide with fences on their level; navigation does not path around them yet.
- A fence's depth silhouette counts as ground of its level for the cast shadows (fences do not cast
  their own long shadows on lower ground yet).

## Files

| Path | What |
|---|---|
| `godot/game/world/fences/fences.gd` | Links, pieces, shadows, depth silhouettes, collision, the rails and bands joining divider gates, `blocks_point` (the tests' probe) / `blocks_rect` / `blocks_sweep` (`@tool`) |
| `godot/game/world/fences/fence.gdshader`, `fence_depth.gdshader` | The fence art; its silhouette in the depth map |
| `godot/game/world/fences/fence_layer.gd`, `fence_tileset.tres`; `godot/asset/MAPS/fences/fence_paint_tiles.res` | The painted layer (and its divider gates, `sync_gates`) and its tiles (`scripts/art/build-fence-paint-tiles.py` writes the tile set and `fence_paint_tiles.png`; `godot/tools/pack_fence_paint_tiles.gd` saves the `.res` the tile set uses) |
| `godot/game/dungeon/divider_gate.gd`, `godot/game/scenes/objects/dungeon/divider-gate.tscn` | The divider gate (`object.divider-gate`): its picture shut and open, its body; its `GateScript` is `godot/game/scripts/gate.gd` |
| `godot/asset/MAPS/objects/dungeon/divider-eye-block.png`, `divider-pen-gate.png` | The gates' pictures |
| `godot/asset/MAPS/fences/` | Kits (`scripts/art/build-fence-art.py`) |
| `asset/Originals/fences/` | Generated sources and the review sheet |
| `scripts/maps/build-fence-park.py`, `godot/game/scenes/worlds/fence-park.tscn` | The Fence Park |
| `godot/tools/render_fence_park.gd` | Renders and probes the Fence Park |
| `godot/tools/render_divider_gates.gd` | Renders the Lair's divider gates shut and open, with slimes walking into each gate and beside it (windowed: `--path godot -s res://tools/render_divider_gates.gd -- --out=<dir>`) |
| `godot/game/world/painted_objects.gd` | What a painted layer may remove by itself: a gate (or interior-wall door) it made and nobody changed |
| `godot/tests/test_fences.gd` | Mounting (Fence Park, C4, a flat world), links, the bands (straight, diagonal, a lone tile), posts as wide as their kit, movement (a flat world's fence stops a body), hops and drops, painted gates' records and settings, the gate tiles where the scenes paint them, a shut gate closing its cell (eye, pen, north-south, beside lone tiles) and opening, a gate opened as its room is built, a small-key gate, pieces kept out of the tree |
