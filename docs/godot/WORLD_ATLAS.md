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

- **What it shows:** the chunk grid with the chunk names (faint, so the map shows through); every
  region's world scene, live (read from disk and drawn as the game draws it, one world per frame
  while it loads); the interiors on a shelf under the grid. With **`show_signs`** on (Inspector, off
  by default since 2026-11-01, owner: the signs hid the maps): region outlines, names and chunks; the
  openings; the markers; the interiors' titles; every exit of
  every world as an arrow: **green** (it leads to the region across its edge, which leads back),
  **amber** (no way back), **red** (it leads somewhere that is not across its edge, or arrives on an
  edge without a marker). The sketch's colours show where a region has no world yet.
- **What you can change:** only the layout. The worlds are instances with no owner: they are never
  saved into the atlas and cannot be selected or edited there. To change a world, select its region
  and press **Open world** (Inspector), edit it in its own tab, save, then **Refresh worlds** on
  the atlas's root. To edit several chunks at once (a river or a road across their lines), press
  **Edit area** ([below](#editing-an-area-2026-11-01)).
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
  `show_live_worlds`, `show_signs` (`show_exits` and `show_markers` choose among the signs),
  `show_interiors`, `edit_area` (the chunks **Edit area** opens). `tools/render_world_atlas.gd` renders with the signs on. A region's `live` switches its
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

## Editing an area (2026-11-01)

Rivers, roads and ridges cross chunk lines, and shaping them one chunk tab at a time is hard. An
**area** is a few chunk worlds joined into one temporary scene, edited with the usual tools and
written back into the chunk scenes (`game/dev/area_edit/area_edit.gd`; the area's root:
`area_root.gd`). The chunk scenes stay the scenes of record.

- **Open:** type the chunks in the atlas root's `edit_area` (`E4:F5`, or one chunk `E4`; at most
  6 chunks, as a bigger scene makes the editor slow) and press **Edit area**, or press **Edit
  area** on a region's slot (its block). The atlas writes `game/dev/area_edit/areas/area-e4-f5.tscn`
  (not in git) and opens it; an area already open opens as it is. Any rectangle of whole chunks
  works, across regions too. Refused (a dialog says why) while one of its chunks is open in a tab
  (the tab keeps its own copy, and saving it would undo the write-back), while another area open in
  a tab holds one of its chunks, or while moves are pending. Closing an area's tab keeps the area
  (and its edits not written back) until **Close area**; another area holding some of the chunks
  whose tab is closed is dropped when it has no edits, else a dialog asks: discard its edits and
  open, or open that area instead (to write it back). The atlas draws the chunks
  picked (dashed) and the areas open (tinted), with the signs off too, and lists the open areas in
  its warnings.
- **What it holds:** each painted layer (ground, forest, elevation, cliffs, level-collision, walls,
  fences, the prop layers) once over the whole area; a chunk's layer joins the area's of its name,
  else the one of its kind (script and tile set) at its offset, and a forest joins any forest
  (level-1's `ForestLayer` joins Gloop's `forest`; `walls` and `walls-shifted-32-0` never join),
  and paint goes back into the chunk's own layer. A joined layer stands where the first chunk's
  stands; a chunk whose layer stands elsewhere (level-1's are offset: ground (1, 0), ForestLayer
  (0, -23), elevation (0, -22)) or is hidden draws shifted there, and the area's root warns about it.
  Each chunk's nodes (exits, spawn, NPCs, enemies, groups, doors, landings) stand under a locked
  holder named after its chunk world, at the chunk's place. The chunk lines and names are drawn
  over it. Scenery a chunk keeps from a neighbour (its picture reaches across the line) is hidden
  in the neighbour's holder, so each piece shows once. What the chunks keep past the area's edges
  (canopies, the walls of tops north of it) shows too, under a shade: it is not written back.
- **Edit** as in a chunk scene: paint any layer across the lines, drag nodes, drop props and
  enemies from the Scenery dock (they go under the area's own `Scenery` and `Enemies`), save.
- **Write back** (the area root's Inspector) saves the area, cuts it into the chunk files and reads
  them back into the area, then says what it did:
  - the ground's sheet frames: the area shows its ground counted from the area's corner (set on
    opening, so its edges meet the plain cells); a chunk whose ground is written gets every ground
    cell's frame counted from its own corner, as the game draws it, also a cell the editor left with
    the frame picked in the palette (noted per chunk; [TERRAIN_LAB.md "Sheet-wrap
    frames"](TERRAIN_LAB.md));
  - each painted, erased or changed cell inside the area goes to every chunk that keeps it: its
    own, and the margins of `tools/lib/chunk_cut.gd` (elevation rows above, forest one cell around
    and three below, walls one cell around, a prop cell whose picture reaches in); a cell changed
    past the area's edge is not written (it belongs to a chunk outside the area) and is noted;
  - a node dragged across a chunk line moves to the chunk it stands in (a `map_id` naming the old
    chunk names the new one; a name already taken there gets a number); a new node goes to the
    chunk under it; a node dragged out of the area, and an exit or a player spawn dragged into
    another chunk, goes back where it stood (noted);
  - scenery new or moved is copied into each chunk of the area its picture reaches into; a hidden
    copy goes when its original moves or goes; scenery moved or deleted whose picture reaches past
    the area's edge is noted (the chunk beyond keeps its copy: check it there);
  - each chunk keeps its own root, metadata, script and layer settings; its nodes come back each
    after the layer it followed in the file, new ones last. Only the chunks that changed are
    written, as close to the old file as Godot allows (the resource ids, sub-resource ids and node
    ids it had, its line endings);
  - all or nothing: every chunk is cut first, and when one that changed cannot be written (it does
    not come back exactly, or cannot be cut) nothing is written and the reason is shown; the edits
    stay in the area;
  - a door that changed chunks moves in `world-chunks.json`; every chunk written and every chunk
    around one gets its elevation cache baked when it paints elevation
    (`tools/bake_elevation.gd -- --world=<chunk worlds>`, run headless: the cache's key holds the
    ground, the cliffs and the elevation, and a chunk's neighbours' paint past its edges,
    [ELEVATION.md "Across chunk lines"](ELEVATION.md#across-chunk-lines)); an open world atlas
    reads the worlds again;
  - nothing is written when a chunk's file changed on disk since the area was opened (a hash per
    chunk: **Discard edits** reads the chunks again) or one of its chunks is open in a tab.
- **Discard edits** reads the chunks again (the edits not written back are lost); **Close area**
  closes the tab and deletes the area.
- **Play (F6)** on the area's tab runs the game in one of its chunk worlds, from that chunk's spawn,
  as F6 on a chunk scene does: the chunk in the middle of the 2D view when the area was last saved
  (Godot saves it before running; the note is `user://area_edit/area-<rect>.play.txt`), else the
  area's first chunk. The game reads the chunk files, so edits not written back do not show: the
  output warns when there are some. (Until 2026-11-10 F6 on an area failed: each chunk's
  `world-definition` swapped the scene, and the ones after the first found no tree.)
- **Exactness:** opening an area checks that each chunk comes back from it exactly as Godot saves
  that chunk alone, with nothing edited; a write-back that would change a chunk that does not
  writes nothing (a warning on the area's root). On 2026-11-01 all 64 chunks came back exactly.
  An instance a chunk's file holds changes inside without its being editable (an override of a
  node in it, a node added under one of its nodes) loses them on any save: Godot drops them. The
  area marks such instances editable, noted when it opens, so they survive; a written chunk gains
  their `[editable]` lines, and Godot then also stores the texture of the sprite inside them. Found
  in level-1-c4 (the two sally-port door scripts) and level-1-d4 (the burrow trunk's door and
  arrival); both files got their `[editable]` lines on 2026-11-01, so no chunk needs it now. Saving a chunk again (here or in its
  own tab) brings the overrides inside its instanced scenes up to date, so a written chunk can show
  such lines besides the edit (Gloop E5's cracked ground). A node a script wrote into a chunk without
  its `unique_id` gets a new random one on every save; until 2026-11-17 such a chunk never came back
  exactly and had to be saved once first (West village A4, A5 and B4, their villagers, animals,
  routes and doors placed by a script on 2026-11-01, were saved so on 2026-11-11). Now the check
  and the write-back leave such a node without an id, as its file has it
  (`SceneSave._keep_unique_ids`): level-1-c4's `home-door` and its `door-script`, written in when
  the slime's home moved, were the case that stopped C4.
- **Seen in the area as in the chunks:** a ForestLayer in an area seeds its trees by each cell's
  place in its chunk (`seed_period`), so trees grow as in each chunk's scene; cliffs, stairs,
  water, walls, fences and props look the same (checked on Gloop E4:F5 and Slimeshire C4:D5). Only
  along a chunk line can trees differ: a chunk also draws the neighbour's trees in its forest
  margin, seeded its own way, while the area draws each tree once, as its own chunk grows it.
- **Headless:** `AreaEdit.open(rect, map)` joins an area, `AreaEdit.write_back(path, dry_dir)`
  writes it back (into `dry_dir` instead of the chunks when given), `AreaEdit.round_trip(path)`
  counts the lines each chunk would change with nothing edited.
- **First demo** (2026-11-01, Gloop E4:F5, written to a scratch folder, not to the chunks): a pond
  painted across the E4|F4 line, a lantern dragged from E4 into F4 and a lily pad dropped on the
  line came back as E4 and F4 each with its half of the pond, the lantern in F4, the lily pad in F4
  with its copy in E4; E5 and F5 unchanged.
- Drawing rivers, roads and ridges as lines over the atlas (phase 3) is not built yet.

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
  the openings line up. An opening has a clear corridor of road on each side. It never lies across
  a chunk corner (owner, 2026-11-01: walking through one changed between four chunks): it stays in
  one chunk on each side, `CHUNK_MARGIN_CELLS` (one cell) off that chunk's sides
  (`region_plan.gd` `_inside_one_chunk`).
- **Roads** join a region's openings and its landmarks (cheapest path on the cells): stairs where a
  road climbs one level (two tiles wide), a bridge over one to three cells of deep
  water (the wooden footbridge prop on east-west crossings), fords through shallow water. In the
  Wilds, trails reach every chunk. A cell on a chunk's side costs a road more
  (`CHUNK_SIDE_COST`), so roads cross chunk lines straight instead of running along them (owner,
  2026-11-01).
- **No dead ends:** every place a ledge drop (any unfenced rim) leads to has a way back to an
  opening: the builder floods each world with the game's movement rules and adds a flight of
  stairs, fences the rims (stone) or levels a small pocket where one has none.
- **Trees** on the sketch's forests and the border bands, on a `forest` layer
  ([FORESTS.md](FORESTS.md)), each theme its own trees: forest and meadow oak, beech, birch and
  pine; the Wilds those and autumn maples and ginkgos by noise; desert cacti; volcano ember and
  ash trees; swamp cypress and mangrove; frost snowy firs and frost trees; crystal crystal trees
  and cave mushrooms; ruins gnarled and ivy trees; village apple and cherry trees.
- **Exits:** an exit at every opening (the slime comes out at the same place across the border, in
  the neighbour's opening: [border crossings](#border-crossings-by-coordinates-2026-10-31) below;
  [specs/world.md](specs/world.md)), `player-spawn` (three tiles inside the first opening); the
  sketch's markers as **MapNotes** (`map_note.gd`: an icon and a label
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

**The prologue in B4 (2026-10-16):** `west-village-b4`'s south (rows 13-31) is the prologue, made by
hand ([PROLOGUE.md](PROLOGUE.md)); its file no longer has the hash `world-chunks.json` recorded, so
the cut leaves it alone. Its exit to level-1 moved to the east edge's y 1600-1792 and leads straight
to `level-1-c4`, which has the exit back (`exit-to-west-village-1`) at the same place:
that opening is the prologue's forest path, so the West village's town needs its own opening onto
Slimeshire when the layout is redrawn. (The layout's second West village – Slimeshire passage, at
C4 rows 6-9, had no crossing in the scenes and was taken out on 2026-11-01, so the map draws no
link there; the town's opening adds its passage when it is built. The same day a leftover road stub
on the South Wilds C8 – Sticky Swamp D8 border, open on both sides with no exit, and one on D8's
side at row 26 were planted over.) The release "Web" preset ships `west-village-b4` (it
excludes `west-village-a*` and `west-village-b5*` only); `build_region_worlds.gd` rewrites the
presets, so check that line after running it.

**Openings on hand-made worlds:** a placeholder's exit into level-1, gloop-forest or crystal-caverns
works one way until the hand-made world has its own opening and exit there: until then the player
arrives at that world's spawn. The builder prints, for each such opening, where it is (block
tiles), the opening and the exit the hand-made world needs (`target_area_id` = the placeholder,
`entry` = the opposite edge); `tools/check_crossings.gd` lists a one-sided one ("border"). Since
2026-10-31 each has its other side, drawn by hand in the hand-made chunks at the same place along
the border (pictures: [design/border-openings/](../design/border-openings/)), each with an exit
back (`exit-to-<placeholder>-1`, `target_area_id` = the placeholder region, `entry` = the opposite
edge), or is closed:

| Opening | Hand-made side | Drawn as |
|---|---|---|
| North Wilds H3 → crystal-caverns H4 (north, 256-512) | `crystal-caverns-h4` | a crystal grove each side of the gap (forest layer, crystal mix); a lookout rock stands in the lane |
| level-1 C5 → South Wilds C6 (south, 1536-1792) | `level-1-c5` | a gap in the band of trees past C5's south edge, out of the meadow |
| gloop-forest E5 → South Wilds E6 (south, 1536-1792) | `gloop-forest-e5` | a dirt trail through the forest band (13 rows of trees erased) |
| crystal-caverns H5 → South Wilds H6 (south, 384-640) | `crystal-caverns-h5` | a crystal grove each side of the gap |

**Closed (owner, 2026-10-31):** North Wilds ↔ level-1 (C3/C4) and North Wilds ↔ gloop-forest
(F3/F4) have no opening: `north-wilds-c3` and `north-wilds-f3` lost their exit, their road's last
stretch to the border and the gap in their border trees, and the layout lost both passages (the
in-game map draws no link there). A way into Gloop Forest from the north may come later (a Lash
crossing or a bridge west of the region). Running `build_region_worlds.gd` again would put both
openings back (it plans one per stretch of border two regions share). In C3 level-1's river now
goes on north: four cells wide on the C/D chunk line (`north-wilds-c3` and `-d3`), under a
footbridge where the road crosses (one deck in each chunk at the same place), to a pond across the
chunk line.

**Off the chunk corners (owner, 2026-11-01):** five openings lay across a chunk corner, two tiles
in each of four chunks, so walking through one changed chunks for nothing. Each moved into one
chunk on each side, by hand in its scenes: the new gap in both border bands (and in the
neighbour's trees a chunk draws past its edge), a road lane to the nearest road, the old gap
planted and its road stub turned back to ground, one exit per side (the other chunk's exit
deleted) and the passage in the layout moved with it:

| Opening | Was | Now |
|---|---|---|
| level-1 ↔ South Wilds (Plaza bridge) | C5/D5 ↔ C6/D6 | C5 ↔ C6, x 1536-1792; `level-1-d5` back as it was |
| North Wilds ↔ crystal-caverns | G3/H3 ↔ G4/H4 | H3 ↔ H4, x 256-512; `crystal-caverns-g4` back as it was |
| North Wilds ↔ Northern Ruins | C1/C2 ↔ D1/D2 | C1 ↔ D1, y 1664-1920 |
| Northern Ruins ↔ Volcano Ridge | E1/E2 ↔ F1/F2 | E1 ↔ F1, y 1664-1920 |
| South Wilds ↔ Sticky Swamp (Swamp road) | D6/E6 ↔ D7/E7 | E6 ↔ E7, x 256-512, straight onto the swamp's road |

The Web-wall maze's passage moved one cell up in the layout (y 61) to where its fenced lane meets
the border (gloop-forest F4 rows 26-27). The Verdant Gate's way (level-1 D4 → gloop-forest E4)
was walled on the gloop side: `gloop-forest-e4`'s border trees are open at rows 7-10, where D4's
lane past the gate meets the border, and D4's `exit-1` has no gate of its own any more (the gate
object before it takes the green key, so the border is never reached locked).

**Roads off the chunk lines (owner, 2026-11-01; not enough on its own: the owner then asked for
the lines to be closed, see [Chunk worlds](#chunk-worlds-2026-10-12)):** roads that ran along a chunk line inside a
region (walking along one changed chunks over and over) were moved off it by hand, keeping their
links and crossing lines straight (picture `roads-off-chunk-lines.png`): Northern Ruins D1 (straight
on from the opening at rows 26-27) and E1/E2 (two straight crossings, the strip along E2's top row
gone); South Wilds D6/E6 (down D6 cols 26-27, its stair moved there, then east on rows 28-29),
G6/H6 (the road two tiles into H6, cols 2-3), A6 (a stub trimmed), F6/G6 (the sand loop two tiles
into G6, its rock with it); Volcano Ridge F1/G1 (the road on rows 28-29, its climb to the fenced pit
in G1 cols 4-5); North Wilds C2's bend moved two rows down; Sticky Swamp E7's old stub trimmed. What
is left on a line is a road crossing it straight (four tiles wide at most).
`south-wilds-d6`'s elevation changed (the stair), so its cache needs a bake.

The in-game map draws every passage's link since then ([specs/map.md](specs/map.md)).

**Border crossings by coordinates (2026-10-31,
[design/2026-10-31-crossings-and-arrivals.md](../design/2026-10-31-crossings-and-arrivals.md) D5):**
every chunk world is a square of the atlas grid, so an exit into a neighbouring region needs no
arrival marker: the slime comes out at the same place across the border, in the
chunk there (`game/world/crossings/border_crossing.gd`: the chunk across the edge the exit lies on,
whichever of the target region's chunks it is), and the screen scrolls as between a region's
chunks (`worldNavigation.regionBorderScroll`; the music changes as it does through a door). This
comes out through the far side's exit back: at that place when there is one there, else at the
nearest exit back along the same border line, in whichever of the region's chunks it lies
(`BorderCrossing.opening_back` and `way_back_along`, read from the scenes without building them;
the scroll is shifted to meet it: gloop-forest's long west edge comes out at level-1's one gate).
An opening drawn on one side only would land at the region's spawn with the fade until its other
side is drawn. `tools/check_crossings.gd` lists those ("border") and the ones drawn apart
("apart"); on 2026-10-31, once six of the eight placeholder openings into level-1, gloop-forest
and crystal-caverns had their other side and two were closed (above), 43 region exits cross at the
same place and 2 at the opening back elsewhere, and none is one-sided (the five openings moved off
chunk corners on 2026-11-01 have one exit a side, ten fewer). The arrival markers (`arrive-from-*`,
`player-entry-<edge>`) were deleted that day (owner).

## Chunk worlds (2026-10-12)

Worlds one chunk in size, the player walking from one into the next as in *A Link to the Past*'s
screens (owner: the big Wilds took long to load). A region is cut into one world scene per chunk,
and **the chunks are the scenes to edit** from then on (owner, 2026-10-12): the region's whole
scene is deleted.

**Chunk lines are closed; chunks meet at a few marked crossings** (owner, 2026-11-01; the rule:
[level design rule 11](../design/2026-10-16-level-design.md#the-rules-that-matter-most)). Terrain
closes every line two chunk worlds share, inside a region or between two: cliffs, water and
canals, forest bands, walls, each chunk closing its own side. Two touching chunks meet at one to
three crossings, each inside those two chunks (never at a corner), a road wide at most, marked as
a way out (a bridge, a ford, stairs, a gate, a trail gap between lantern posts, the
`decoration-world-solid--lantern-post` scene). `tools/check_chunk_lines.gd` loads every chunk world
alone, tries the slime's circle every 32 units just inside each edge and lists each line's
crossings, flagging one wider than a road, near a corner, more than three (or none inside a
region) and a stretch open on one side only:

```bash
"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/check_chunk_lines.gd [-- --world=<text>] [--all]
```

Built first in **Gloop Forest** (picture `docs/design/chunk-lines/gloop-forest.png`): a stream from
the river down the E|F line in row 4 with a footbridge (one deck per chunk at the same place) on
the Verdant Gate's trail to the Watch Oak; a canal along E4/E5 east of the camp and along F4/F5
with a ford (shallow water) where the web lane's south wall opens; forest bands with a trail gap
on E4/E5 (cols 15-16) and E5|F5 (rows 8-9); lantern posts at every gap; sand trails joining every
crossing; the silk nook and the weaver nest made rooms with one way in. Found on the way: the camp's
east gate never reached the web lane (the blue cottage and the camp wall fill it), so the lane, the
way to the Crystal Caverns, could not be reached from Gloop; it is entered by the ford now and its
west end is walled. The Crystal Caverns' west edges (G4, G5) are closed by crystal trees except
the lane's end. The Wilds, the Ruins, the Volcano, the Swamp, the Desert, Frostpeak, the West
village, Slimeshire and the Crystal Caverns' own lines are not yet closed: the checker lists them.

```bash
"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/split_region_chunks.gd -- --region=north-wilds,volcano-ridge,south-wilds
```

Cut (2026-10-12): every placeholder region (52 chunks: North Wilds 15, A1-C2, H2, A3-H3; Volcano
Ridge 5, F1-H1, F2-G2; South Wilds 12, A6-H6, C7-C8, H7-H8; Frostpeak, Sticky Swamp, West Village,
Northern Ruins and Desert 4 each) and the hand-made Gloop Forest (E4-F5) and Crystal Caverns
(G4-H5), and on 2026-10-14 Slimeshire Meadow (level-1: C4 the village, D4 the Verdant Gate and
Fatty's camp (since 2026-10-17 the Lair's bolt-hole and Fatty's old camp clearing), C5 the lake, D5
the autumn grove (since 2026-10-17 Fatty's Hollow, the hill with the Lair's gate; the four reworked
by `tools/build_slimeshire_chunks.gd`, [Chapter 1](../story/chapters/chapter-1-the-clearing.md#slimeshires-places-built-2026-10-17))):
64 chunks, every region. The tool writes
`godot/game/scenes/worlds/chunks/<world>-<chunk>.tscn` (scene id `world.<world>-<chunk>`, e.g.
`world.south-wilds-c6`) for every chunk the region holds (`WorldMapData.region_chunks`), 32 × 32
tiles each, cut from the region's world scene:

- its ground, forest and fence cells in the chunk, and its elevation with `Elevation.MAX_ROWS_ABOVE`
  rows above it (the walls of tops just north of the chunk still hang in; since 2026-11-06 a chunk's
  cliffs read every neighbour's own paint past its edges instead, [ELEVATION.md "Across chunk
  lines"](ELEVATION.md#across-chunk-lines), and the copied rows count only where no chunk lies
  north); its props, map notes and arrival markers;
- its exits to other regions: one lying just past the chunk's edge (the generator puts them past
  the region's border) is moved in against it, and an opening across two chunks is split between
  them (`_exit_part`);
- a `player-spawn` on the open cell nearest the chunk's middle;
- **scenery across the border:** a static prop (scene file names starting `tree-`,
  `wall-stone-solid`, `rock-world-wall`, `decoration-world-`, `crystal-cluster-wall`,
  `house-world-solid`, `water-life`: `SCENERY`) whose picture or collision reaches into a chunk is
  in that chunk too, so a house or a tree on a border shows on both sides; forest cells come with a
  margin past the edges (1 cell, 3 below) for the canopies; chests, items, NPCs and doors live in
  one chunk only;
- along every edge it shares with another chunk of the region, an exit the whole edge long, a line
  4 units deep at the very edge (the slime crosses only when it reaches the screen's limit), with
  `keep_along` ([specs/world.md](specs/world.md) §8): the player comes out at the same place along
  the neighbour's opposite edge, 64 units in. The crossing scrolls the screen as in Zelda
  (`game/world/chunk_scroll.gd`, 2026-10-14): a picture of the old view (the world only, without the
  slime) is taken, the next chunk is built behind it, the picture is laid beside the new chunk where
  the old one lay, and the camera slides from the old view into the new one over
  `worldNavigation.edgeScrollMs` (650) while the slime walks in from where it left; no fade. Exits
  to other regions and doors still fade.

The scenes are registered in `scene_index.json`; the placeholder regions' chunks
(`chunks/<world>-*`) are kept out of the release "Web" export, the hand-made worlds' ship. The tool also writes `godot/game/data/world-chunks.json` (read by
`game/world/atlas/world_chunks.gd`): each cut world's chunks, which chunk holds each of its doors
(its `arrivals`, the old markers' table, is empty since 2026-10-31), its spawn chunk, and a hash of
every chunk file it wrote. A cut region has no whole scene: travel into it (a door, a named spot,
an edge), a launch option (`?map=north-wilds`) or a save naming it goes to the chunk that holds the
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
2026-10-12: four full chunks each). World enemies are placed, not spawned (roadmap 5.25,
[specs/enemy.md](specs/enemy.md) §3.3): the cut turns a world's `enemy-spawn` areas into
`enemy-wander` areas with their `maxPopulation` of placed enemies under the chunk's `Enemies`
node, and a live `metadata.spawns` table (a world without spawn areas) into at most 5 placed
enemies in each chunk, in two camps with a new `enemy-wander` rect each (`<chunk>-camp-<n>`,
`tools/lib/enemy_placement.gd`); a dead table (the world has spawn areas) is dropped. It reads open ground from cells
only, so it notes each camp for a look at its spots, and notes a placed enemy whose wander area
lies in another chunk.

**Enemies come back with the chunk.** A chunk's placed enemies stand once it is built and are
never spawned again while the slime is in it; walking back into it (or a door back out, a load)
builds it again, and every one of them stands on its spot once more, as in Zelda. Beaten bosses
keep their camps' own rule.

**Tests:** a test file names its starting chunk (`MAP_ID := "gloop-forest-f4"`) or travels to the
one holding what it tests; after a travel into a cut region `t.in_world("gloop-forest")` is true
in any of its chunks (tests/lib/test_context.gd).

**Walking between chunks of one region:** the area banner shows the region's name once, on
entering the region (`Shell._on_world_registered`); quests see the region's world entered too
(`QuestService.on_world_built`); the world music carries on without a fade when the next chunk
plays the same track (`MusicDirector._adopt_world`, `Main.is_travelling_within_region`); after a
leave fade (quit to title, a travel out of the region) the world's music fades in anew.

**Editing and rebuilding.** Edit a chunk in its own scene, or a few at once as an area ([Editing an
area](#editing-an-area-2026-11-01)); the rules for what a chunk keeps of its neighbours are shared
by the cut and the area (`tools/lib/chunk_cut.gd`). The atlas shows a cut region's chunks in
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
villagers' story variant outside C4) is dropped there. Chunks that paint elevation have baked
elevation caches like any world (a chunk builds its cliffs in about 0.3 s without one; level-1's
chunks loaded in 2.2-2.7 s from a cold start against 2.8 s for the whole level with its cache; a
crossing is ready about 0.6 s after touching the edge). Hills and mountains run on across chunk
lines: each chunk builds its cliffs over its neighbours' paint past its edges ([ELEVATION.md
"Across chunk lines"](ELEVATION.md#across-chunk-lines)).

Timings (headless, this machine): North Wilds' whole world builds in about 4.0 s from a cold start,
one of its chunks in 1.4 s (both with the game's own start); walking into a chunk's edge holds
the picture while the next chunk builds (about 0.2-1.4 s), then scrolls for 0.65 s.

## Limits

- The placeholders have no enemies (none placed; `build_region_worlds.gd` places none), and lava is
  a pit, not a hazard ground.
- The atlas instances every world in the editor's memory: opening it takes a few seconds.
- After the Wilds' blocks were moved on 2026-10-10 some sketch rivers and roads stop at a block's
  edge inside the Wilds; repaint them in the sketch tool and rebuild the placeholders.

### Slimeshire second pass (2026-10-17)

C4 now has a fenced level-1 plateau, north/south stairs and three drop gaps. The river
runs across the C4/D4 border, with the road bridge centred on that seam. C5 expands the
lake, adds an island reached by charged Roll over falling planks, a ford islet, a jetty
and a future Swim secret. `lake-island-cave` and `hollow-hill-cave` are separate interiors.
D4's pen and plateau hearts and the hill cave heart hide in chests.
