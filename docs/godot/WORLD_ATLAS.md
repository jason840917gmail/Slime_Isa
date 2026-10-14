# World map: layout, atlas and region worlds

> **Status:** first version, 2026-10-11. The whole overworld (an 8 × 8 chunk grid) can be seen and
> rearranged in the editor; every region has a world scene, the regions without a hand-made world
> have generated placeholders. The layout is a proposal ([docs/story/03-world.md](../story/03-world.md)).

## The pieces

| What | Where | Does |
|---|---|---|
| **The layout** | `godot/game/data/world-map.json` | The one source: a sketch of the overworld on a grid of cells, which regions own them, each region's world scene and interiors, markers, and the openings between regions |
| Data API | `godot/game/world/atlas/world_map_data.gd` | Loads and saves the layout; region blocks, neighbours; moves blocks of chunks |
| **Sketch tool** | `scripts/story/world-map/` (`pnpm story:map`, port 3210) | Paints terrain, heights, regions and markers in the browser; moves and swaps regions; saves the layout, `docs/story/world-map.png` and the world-map block of `03-world.md` ([TOOLING.md](../TOOLING.md)) |
| **World atlas** | `godot/game/dev/world_atlas.tscn` | The whole world in the editor: every region's world side by side, live; drag regions to rearrange them |
| **Region worlds** | `godot/game/scenes/worlds/<world>.tscn` | One overworld scene per region; the placeholders are built by `godot/tools/build_region_worlds.gd` |
| In-game world map | `godot/game/ui/map/world_map_window.gd` | The M map draws the regions, the discovered ones, the current one and the openings from the layout ([specs/map.md](specs/map.md)) |

## The layout file

`world-map.json` (format `slime-isa-world-map`, version 2) keeps the sketch tool's layout: the
head, then the three grids one row per line.

- **Grid:** `cols` × `rows` cells (128 × 128), cut into `chunks` (8 × 8, so 16 × 16 cells each).
  One cell is `tilesPerCell` × `tilesPerCell` tiles (2 × 2) of `tileSize` (64) units: a chunk is
  32 × 32 tiles (2048 units), the overworld 256 × 256 tiles. Chunk A1 is the north-west corner.
- **Grids:** `terrain` (one character per cell: `g` grass, `f` forest, `p` path, `t` town, `h`
  bridge, `b` beach, `d` desert, `r` rock / badlands, `m` mountain, `s` shallow water, `w` deep
  water, `x` swamp, `n` snow, `i` ice, `l` lava, `k` crystal, `c` cave, `v` abyss, `.` unplanned),
  `elevation` (digits 0-4) and `regionCells` (the region key of each cell).
- **`regions`:** `key`, `name`, `color`, `chapter`, `status`, `id`, `world` (the overworld scene:
  `res://game/scenes/worlds/<world>.tscn`, scene id `world.<world>`), `interiors` (scene ids off
  the grid), `placeholder` (true: built by the generator and safe to rebuild), `theme` (meadow,
  forest, crystal, volcano, frost, swamp, village, ruins, desert, wilds), `boss`, `notes`.
- **`markers`:** places on the map (`type`, `x`, `y` in cells, `label`, optional `to`, `needs`,
  `map`, `notes`).
- **`passages`:** written by the generator: one opening per stretch of border between two touching
  regions, `{a, b, x, y, w, h}` in cells (the cells on both sides), `kind` (road, path, gate, exit)
  and the `label` of a marker that named it.

**Moving regions** (sketch tool, atlas, `world_map_data.gd`; all three behave the same): a move
carries whole blocks of chunks with everything on them (the three grids, markers and openings), so
nothing is lost, and every allowed move is undone by the opposite move.

- **Swap:** two blocks of the same size that do not overlap trade places (a region dropped onto
  another of its size swaps with it).
- **Slide:** a block moves chunk by chunk along one axis; the strip it moves onto goes to the side
  it left. A diagonal slide is refused (slide along one axis at a time).
- A move is refused when it would leave the map, or tear another region apart: leave it in more
  pieces than before, or stop it being a whole rectangle of chunks when it was one. Regions that
  are not such a rectangle (the North and South Wilds, Volcano Ridge) cannot be moved; they fill
  what the others leave.
- Saving never overwrites newer edits: if the file changed on disk since it was read (the sketch
  tool, the atlas or the region builder saved it), the save is refused (`WorldMapData.save_file`
  returns `ERR_ALREADY_IN_USE`); the atlas then reads the new file and applies its pending moves
  to it, and the sketch tool asks first.

The current layout (2026-10-11; Gloop Forest east of Slimeshire and Crystal Caverns east of Gloop
Forest, as the game's exits are):

```
     A  B  C  D  E  F  G  H
  1  j  j  j  h  h  d  d  d      a Slimeshire Meadow (level-1)    g West village
  2  j  j  j  h  h  d  d  j      b Gloop Forest (gloop-forest)     h Northern ruins
  3  j  j  j  j  j  j  j  j      c Crystal Caverns                i Desert
  4  g  g  a  a  b  b  c  c      d Volcano Ridge                  j North Wilds
  5  g  g  a  a  b  b  c  c      e Frostpeak                      k South Wilds
  6  k  k  k  k  k  k  k  k      f Sticky Swamp
  7  i  i  k  f  f  e  e  k
  8  i  i  k  f  f  e  e  k
```

## The world atlas

Open `game/dev/world_atlas.tscn` in the editor (it is a dev scene: not in `scene_index.json`, not in
the release export).

- **What it shows:** the chunk grid with the chunk names; every region's world scene, live (read
  from disk and drawn as the game draws it, one world per frame while it loads); region outlines,
  names and chunks; the openings; the markers; the interiors on a shelf under the grid; every exit of
  every world as an arrow: **green** (it leads to the region across its edge, which leads back),
  **amber** (no way back), **red** (it leads somewhere that is not across its edge, or arrives on an
  edge without a marker). The sketch's colours show where a region has no world yet.
- **What you can change:** only the layout. The worlds are instances with no owner: they are never
  saved into the atlas and cannot be selected or edited there. To change a world, select its region
  and press **Open world** (Inspector), edit it in its own tab, save, then **Refresh worlds** on
  the atlas's root.
- **Rearranging:** drag a region (click anywhere on it). It snaps to whole chunks. Dropped on a block
  of its size, it swaps with what is there (shown at once); dropped overlapping its old place, it
  slides. Each drag is a new move after the others (a drag follows the mouse until the button is
  released; dropped back where it began, it is no move). A refused drop is drawn red with the
  reason. Moves stay pending (dashed outline) until **Save layout** (root, Inspector) writes them to
  `world-map.json` (the old file is kept as `world-map.json.bak`) and reloads. If the file changed
  on disk meanwhile, nothing is written: the atlas shows the new file with the moves played on it
  again (those that no longer work in red) and the next Save layout writes it. **Reload** drops
  pending moves.
- **After a layout change:** the placeholder worlds are out of date (the atlas says so, in its
  warnings): rebuild them (below). Hand-made worlds keep their content; check their exits' arrows.
- **Root options (Inspector):** `map_path`, `show_sketch`, `sketch_under_worlds`,
  `show_live_worlds`, `show_exits`, `show_markers`, `show_interiors`. A region's `live` switches its
  world off (level-1 and the Wilds are big: switch them off to lighten the editor).
- **Warnings** (the yellow sign on the root and on a slot): a world whose size is not its block's
  (the rest of the block is hatched), a region
  or interior without a scene, exits that are one-way, wrong or arrive without a marker, and
  placeholder worlds older than the layout.
- **Render it outside the editor** (windowed, it renders):
  `"<Godot 4.7.2 console exe>" --path godot -s res://tools/render_world_atlas.gd -- --out=<dir>`.

Editor calls go through `Engine.get_singleton(&"EditorInterface")` guarded by
`Engine.is_editor_hint()` (in 4.7.2 `has_singleton` is true outside the editor too), so the scripts
load in exported builds.

## Region worlds and the placeholder generator

Every region's `world` is a world scene of its chunk block's size (a 2 × 2-chunk region is 64 × 64
tiles; the Wilds' blocks are 256 × 96). Hand-made worlds (`placeholder: false`: level-1,
gloop-forest, crystal-caverns) are never touched by the tools. The others are built from the layout:

```bash
"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_region_worlds.gd
```

`-- --only=<region key or world id>,...` builds some (the openings stay planned for the whole
map), `--dry-run` writes nothing, `--force` overwrites a scene whose root lacks the metadata
`world_map_placeholder = true` (a placeholder someone took over: remove that metadata to keep the
tool off it). It takes about 20 s for all eight and is deterministic. It prints a summary per
world, a WARNINGS block (an opening no road reaches after a layout change) and the openings on
hand-made worlds.

How a placeholder is made (`godot/tools/region_worlds/`: `region_plan.gd` plans the whole map at
once, `region_canvas.gd` paints one region, `region_scene.gd` writes the scene):

- **Ground** from the sketch (2 × 2 tiles per cell): grass, forest moss under trees, light sand roads
  (dark earth in the desert), cobble towns, sand, water, deep water, snow, crystal; rock and
  badlands are bare earth (leaf litter in the volcano and desert, snow in Frostpeak); ice is water;
  lava and abyss are pits.
- **Heights:** the sketch's digits, smoothed and set per region so its low ground is level 0;
  mountains one level higher; lava a −1 pit, abyss a −3 pit (with stone fences). Other regions'
  cells inside a block (the Wilds' blocks hold the regions they surround) are an unwalkable backdrop.
- **Borders, the Zelda rule:** every region is walled along its whole outline by a band of trees
  two tiles deep, except at its **openings**: one per stretch of border with each neighbour, two
  cells wide, chosen where the sketch has a road, path, gate or an existing exit crossing, else in
  the middle of the longest run of open ground on one level. Both regions leave the same gap, so
  the openings line up. An opening has a clear corridor of road on each side.
- **Roads** join a region's openings and its landmarks (cheapest path on the cells): stairs where a
  road climbs one level (two tiles wide), a bridge over one to three cells of deep
  water (the wooden footbridge prop on east-west crossings), fords through shallow water. In the
  Wilds, trails reach every chunk.
- **No dead ends:** every place a ledge drop (any unfenced rim) leads to has a way back to an
  opening: the builder floods each world with the game's movement rules and adds a flight of
  stairs, fences the rims (stone) or levels a small pocket where one has none.
- **Trees** on the sketch's forests and the border bands, on a `forest` layer
  ([FORESTS.md](FORESTS.md)), each theme its own trees: forest and meadow oak, beech, birch and
  pine; the Wilds those and autumn maples and ginkgos by noise; desert cacti; volcano ember and
  ash trees; swamp cypress and mangrove; frost snowy firs and frost trees; crystal crystal trees
  and cave mushrooms; ruins gnarled and ivy trees; village apple and cherry trees.
- **Exits:** an exit at every opening (`entry_marker = arrive-from-<world>-<n>`, an arrival marker of
  that name inside the neighbour's opening; [specs/world.md](specs/world.md)), `player-entry-<edge>`
  markers, `player-spawn`; the sketch's markers as **MapNotes** (`map_note.gd`: an icon and a label
  in the editor, nothing in the game).
- **Dressing:** boulders on rock, crystal clusters on crystal, broken walls around the ruins'
  landmark, houses around the village's town.
- It writes `passages` into the layout, adds `world.<world>` to `scene_index.json` and the scene to
  the release "Web" export's exclude list (the placeholders ship only in "Web (dev)").

**Taking a placeholder over:** set its region's `placeholder` to false (sketch tool, region
inspector) or remove `world_map_placeholder` from its scene root, so the builder leaves it alone;
when it is ready to ship, take its path out of the "Web" preset's `exclude_filter`
(`godot/export_presets.cfg`). The builder rewrites `scene_index.json` and `export_presets.cfg` on
disk: with the editor open, do not save from the editor's Export dialog right after running it (the
editor keeps its own copy of the presets; reopen the project or the dialog first).

**Openings on hand-made worlds:** a placeholder's exit into level-1, gloop-forest or crystal-caverns
works one way until the hand-made world has its own exit there: it carries
`entry_marker = arrive-from-<placeholder>-1`, and while the hand-made world has no Node2D of that
name the player arrives at its `player-entry-<edge>` marker or its spawn (with a warning in the
Output). The builder prints, for each such opening, where it is (block tiles and units), the exit
the hand-made world needs (`target_area_id` = the placeholder, `entry` = the opposite edge,
`entry_marker = arrive-from-<world>-1`) and the arrival marker it needs; the atlas draws these
exits amber or red and the in-game map draws no link for them. On 2026-10-11 they are level-1's
west, north and south (the Plaza bridge) edges and the north and south edges of gloop-forest and
crystal-caverns. Since 2026-10-12 those two worlds fill their 64 × 64 blocks (they were 54 × 54), so
their north and south openings lie on their edges; the exits back are still to make.

## Chunk worlds (2026-10-12)

Worlds one chunk in size, the player walking from one into the next as in *A Link to the Past*'s
screens (owner: the big Wilds took long to load). A region is cut into one world scene per chunk,
and **the chunks are the scenes to edit** from then on (owner, 2026-10-12): the region's whole
scene is deleted.

```bash
"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/split_region_chunks.gd -- --region=north-wilds,volcano-ridge,south-wilds
```

Cut (2026-10-12): every placeholder region (52 chunks: North Wilds 15, A1-C2, H2, A3-H3; Volcano
Ridge 5, F1-H1, F2-G2; South Wilds 12, A6-H6, C7-C8, H7-H8; Frostpeak, Sticky Swamp, West Village,
Northern Ruins and Desert 4 each) and the hand-made Gloop Forest (E4-F5) and Crystal Caverns
(G4-H5), and on 2026-10-14 Slimeshire Meadow (level-1: C4 the village, D4 the Verdant Gate and
Fatty's camp, C5 the lake, D5 the autumn grove): 64 chunks, every region. The tool writes
`godot/game/scenes/worlds/chunks/<world>-<chunk>.tscn` (scene id `world.<world>-<chunk>`, e.g.
`world.south-wilds-c6`) for every chunk the region holds (`WorldMapData.region_chunks`), 32 × 32
tiles each, cut from the region's world scene:

- its ground, forest and fence cells in the chunk, and its elevation with `Elevation.MAX_ROWS_ABOVE`
  rows above it (the walls of tops just north of the chunk still hang in); its props, map notes and
  arrival markers;
- its exits to other regions: one lying just past the chunk's edge (the generator puts them past
  the region's border) is moved in against it, and an opening across two chunks is split between
  them (`_exit_part`);
- a `player-spawn` on the open cell nearest the chunk's middle and `player-entry-<edge>` markers;
- **scenery across the border:** a static prop (scene file names starting `tree-`,
  `wall-stone-solid`, `rock-world-wall`, `decoration-world-`, `crystal-cluster-wall`,
  `house-world-solid`, `water-life`: `SCENERY`) whose picture or collision reaches into a chunk is
  in that chunk too, so a house or a tree on a border shows on both sides; forest cells come with a
  margin past the edges (1 cell, 3 below) for the canopies; chests, items, NPCs and doors live in
  one chunk only;
- along every edge it shares with another chunk of the region, an exit the whole edge long (24 units
  deep) with `keep_along` ([specs/world.md](specs/world.md) §8): the player comes out at the same
  place along the neighbour's opposite edge, 64 units in. The crossing fades like any exit.

The scenes are registered in `scene_index.json`; the placeholder regions' chunks
(`chunks/<world>-*`) are kept out of the release "Web" export, the hand-made worlds' ship. The tool also writes `godot/game/data/world-chunks.json` (read by
`game/world/atlas/world_chunks.gd`): each cut world's chunks, which chunk holds each of its arrival
markers (`arrive-from-*`, `player-entry-<edge>`) and doors, its spawn chunk, and a hash of every
chunk file it wrote. A cut region has no whole scene: travel into it (an exit's marker, a door, an
edge), a launch option (`?map=north-wilds`) or a save naming it goes to the chunk that holds the
place (`WorldChunks.redirect` in `Main.travel_to`, `_build_world` and `resolve_map_id`), else its
spawn chunk; the region's world id stays its name in the layout. A chunk world also discovers its
region's world, and the in-game map (M) draws the player's dot in its chunk. **F6 on any chunk
scene** starts the game there. Where a tree band or a river runs along a chunk border the crossing
is only where the ground is open, as in the region.

**Hand-made worlds** (gloop-forest, crystal-caverns, level-1): `-- --region=<world>
--hand-made` writes a **preview**: the chunk scenes, registered (F6 on one walks them), while travel
still goes to the whole scene. `-- --hand-made --adopt` makes it real (the table entry, the whole
scene deleted). Each chunk is the whole scene instanced again with what lies outside the chunk taken
away (`_split_hand_made`, `_prune`): a group whose nodes all lie in one chunk stays whole there (the
Matron's nest, its story script keeping its node paths), a group across chunks is split node by
node (a split group with script nodes is noted for a look), nodes with no place (the definition,
music, scripts) are in every chunk; exits are clipped like the generated ones; every `map_id` that
names the world names the chunk; doors (`door.gd`) go in the table so travel back from an interior
lands in the chunk with the door; a world smaller than its block gives chunks along its right and
bottom only as wide as it reaches (gloop-forest and crystal-caverns were grown to 64 × 64 first,
2026-10-12: four full chunks each).

**Tests:** a test file names its starting chunk (`MAP_ID := "gloop-forest-f4"`) or travels to the
one holding what it tests; after a travel into a cut region `t.in_world("gloop-forest")` is true
in any of its chunks (tests/lib/test_context.gd).

**Walking between chunks of one region:** the area banner shows the region's name once, on
entering the region (`Shell._on_world_registered`); quests see the region's world entered too
(`QuestService.on_world_built`); the world music carries on without a fade when the next chunk
plays the same track (`MusicDirector._adopt_world`, `Main.is_travelling_within_region`).

**Editing and rebuilding.** Edit a chunk in its own scene. The atlas shows a cut region's chunks in
place (`AtlasRegion.show_chunks`, its exits and markers merged from the chunks,
`WorldSurvey.merge`); the region's **Open chunk** list picks the chunk "Open world" opens. Running
the tool again needs the region's whole scene: rebuild it from the sketch with
`build_region_worlds.gd -- --only=<region>`, then cut. The cut rewrites only the chunks nobody
edited since (their file still has the hash it recorded; `-- --force` rewrites the others too)
and deletes the whole scene again (`-- --keep-whole` keeps it).

**Prop layers, walls, scripts** (2026-10-14, level-1): each layer is clipped on its own cell
size; a PropLayer keeps every cell whose prop's picture reaches into the chunk (props draw well
past their cell); the `walls` WallLayer keeps one cell past each edge with `shown_cells` the
chunk's own, so pieces at the edge still join; props dragged in under `Scenery` count by their
picture; a script node whose node references point into another chunk (level-1's chapter-1
villagers' story variant outside C4) is dropped there. **No elevation cache** is baked for chunks:
a chunk builds its cliffs in about 0.3 s (level-1's chunks load in 2.2-2.7 s from a cold start
against 2.8 s for the whole level with its cache; a crossing is ready about 0.6 s after touching
the edge).

Timings (headless, this machine): North Wilds' whole world builds in about 4.0 s from a cold start,
one of its chunks in 1.4 s (both with the game's own start); walking into a chunk's edge has the
next chunk ready in about 0.5 s (the 0.32 s fade out and the build), then it fades in over 0.4 s.

## Limits

- The placeholders have no enemies (no spawns), and lava is a pit, not a hazard ground.
- The atlas instances every world in the editor's memory: opening it takes a few seconds.
- After the Wilds' blocks were moved on 2026-10-10 some sketch rivers and roads stop at a block's
  edge inside the Wilds; repaint them in the sketch tool and rebuild the placeholders.
