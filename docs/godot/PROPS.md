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
then **drag a picture into the 2D view**: Godot shows the prop under the mouse at that size and
places its scene where you drop it; the plugin then moves the node under the world's `Scenery`
node (made when missing, y-sorted with the world) and sets that size (its Scale), one step that
Ctrl+Z undoes (a second Ctrl+Z removes the prop). It is an ordinary node: select it, move it freely,
mirror or scale it, edit it in the Inspector, delete it with Delete. **Reload** reads the palettes again after
`tools/build_prop_palettes.gd`. Use it for the props you place one by one; paint the mass of small
scenery (grass, flowers, pebbles, leaves) on the layers below, which keeps the scene tree small.

**Villagers** and **Animals** (2026-11-01): the West town's people and animals by their scene's
picture ([VILLAGERS.md](VILLAGERS.md)); a drag places the scene at its own size under the world's
`NPCs` or `Animals` node, where its wander circle, route or `follow` is set in the Inspector.
**Cave animals** (2026-11-12) lists the caves' harmless animals the same way (fireflies and a
swarm, the glow-worm, the pill bug, the cave newt, the crystal snail, the lantern moth; under
`Animals` too): [VILLAGERS.md](VILLAGERS.md#cave-animals-2026-11-12).

**Suckables** (the very last category, owner 2026-10-19): every liftable kind of
`game/data/liftables.json` (the 67 light things the Gulp sucks in and throws: pots, jars, crates,
rocks, pinecones ...), by its picture on the liftables sheet, its hover text giving its usual weight and its throw effect;
none of a mechanic's own (the
skeleton's skull and bone, the Goo Bomb, essences, the enemies' shots). Dragging one places
`object.liftable` (`game/scenes/objects/liftable.tscn`) under Scenery with its **`kind`** set, at its
own size. Select it to change it in the Inspector, on the node itself (`game/scripts/liftable_root.gd`):
**`kind`** (a list of the kinds; the picture follows at once) and **`under`**, what it leaves where it
stood when the slime sucks it up (Zelda's heart under a pot; game/dungeon/pot_loot.gd): `keep` (the
scene's own, as the dungeon pot's random one), `none`, `heart`, `energy`, `coins` or `random`. For
throw combat also **`weight`** (`light`, `medium` or `heavy`: picking a kind fills in its
usual weight, [THROW_COMBAT.md](THROW_COMBAT.md)), the source of truth for that thing's weight. Like
any part of its world scene it is back each time the map is entered, and so is what it hides.

**Dungeon decor** (2026-10-19) is a palette category like the others: the dungeons' own scenery
(the Lair's war banner, worm bunk, weigh scale and weights, pearl altar; the Weaver Hollow's loft
pieces and brood altar; the mine's ore heap and rock stump; braziers that only show a flame, the
crystal pillar, the cocoon prize) and the dungeon decor set of `game/scenes/objects/dungeon-decor/`
(2026-10-19: hanging chains, wall shackles, a hanging cage, a weapon rack, a guard table and bench,
a barrel stack, broken crates, a sarcophagus, a broken pillar, a bone pile, a worm-head statue, a
candelabra, a bookshelf, a floor grate, stalagmites; `scripts/art/pack-dungeon-decor-art.py` cuts
them from `asset/Originals/dungeon-kit/decor/` and writes their scenes; 2026-11-25, the mine's
dressing, `mine-*`, cut by `scripts/art/pack-mine-decor-art.py` from `asset/Originals/mine/mine-props-e.png`:
a pit-prop frame and a lift gantry the slime walks between the legs of and behind (a small box at each
leg), a ladder's foot (nothing blocks), and a stack of spare props, a slate heap, a lantern post, a
tipped ore cart and a pickaxe and shovel by a crate (each a foot box); the lantern's light flickers and
the slate heap's and tipped cart's crystals shine, `scripts/art/build-ambient-strips.py`). **Town** and **Garden** (2026-11-01, for the West village) are palette categories like the others;
their houses are under **houses**. Houses and town buildings (`game/scenes/objects/town/houses/`):
a jelly dome, a pumpkin, a tree stump, a snail shell, a timber townhouse, a drop-thatch cottage, a
general store, an inn, Burr's gatekeeper house and a throwing-game booth; buildings of several
homes, a door each: a duplex, a triplex row, two flats (the upper one up an outside stair) and twin
mushroom houses; and two large ones, a town hall and a goo bathhouse. A building with several homes
or a big one has a Marker2D `door-1`, `door-2` ... at the foot of each door (an upper flat's at the
foot of its stair): place a door node there for each home's interior. Every painted door has a
`DoorFrame` child on its house scene, where the leaf swings and the slime walks to
([CONVENTIONS.md](CONVENTIONS.md#doors) "Door frames"); a building with no door in its art (the
game booth) gets no door and no room, which is why the general store was repainted with a front
door (2026-11-12, the packer's `store` sheet). Town
(`town/props/`): a goo fountain, a market stall, a signpost, a notice board, a goo lamp, barrels,
crates, a bench, a flower cart, a mailbox, a slime statue, a clothesline, a wheelbarrow, a rain
barrel, a beehive and a water trough. Garden (`town/garden/`): cabbage and carrot beds, a pumpkin
patch, a tulip bed, a gravel square and stepping stones (flat: the slime walks over them and sorts
above them), a hedge and its corner, a picket fence piece, a herb planter, a berry bush and a
scarecrow. A hedge of any length is painted instead, the `hedge` style of the `walls` WallLayer
([WALLS.md](WALLS.md)); a longer picket fence, the picket style of the `fences` layer
([FENCES.md](FENCES.md)). Everything else blocks with a foot box; a building's box covers its lower part, so the
slime walks up to its door (a door is its own node, `game/scripts/door.gd`, placed at the door). The
goo fountain runs (rings over its pool, bobbing bubbles, the blob on top squashing, falling drops:
12 frames), the goo lamp's jar glows and swings from its hook, the jelly dome and the town hall's
jelly finial shimmer, the bathhouse's domes shimmer and its steam sways, the laundry sways, the bees
fly, the water of the trough and the rain barrel runs, the scarecrow leans in the wind, the
gatekeeper's, town hall's and game booth's banners wave, the inn's and the store's signs swing
(8-frame loops, random start) and the chimneys smoke (`effects/chimney-smoke.tscn`, placed in each
house scene); they are made to read at the game's size:
[Town loops](../assets/AMBIENT_ANIMATION.md#town-loops)). `scripts/art/pack-town-art.py` cuts them from the picked concept
sheets in `asset/Originals/town/concepts/` and writes their pictures and scenes
([TOOLING.md](../TOOLING.md)).

**Heavy skin**, **Silk skin** and **Feral skin** (2026-11-12, the owner: the skins' objects "need
their tab") list what each skin works on, placed as the dungeon pieces below under `Objects`: the
heavy plate, block, statues and ore crate, the Heavy Roll's breakables (plank barricade, rotten
timbers, old trunk, old fence, rubble heap, loose rock) and the loose prize; the floor web, web wall
and silk parcel; the climbable wall (vines are painted: [SKINS.md](SKINS.md#painting-vines)).

**Dungeon objects** (2026-10-19) lists the dungeon pieces with
logic by their scene's own picture (flipped when its sprite is: the statue facing the other way, 2026-10-31): every scene of `game/scenes/objects/dungeon/` but the world-level
Dungeon nodes, and the puzzle objects among the other objects (brazier, plates, heavy blocks and
statues (one of them flipped), cracked walls and floors, climb walls, hatches and ladders, gates, winches, barricades, the
mine cart, ore lift, lens and veil, Gulp spots, Pearls, the full heart). Dragging one places its scene
at its own size under the room's `Objects` node (a room door under `RoomDoors`, a hazard under
`Hazards`; made when missing); set its ids in the Inspector ([DUNGEONS.md](DUNGEONS.md)). The list
is `DUNGEON_EXTRAS` and `DUNGEON_SKIP` in `addons/scenery_dock/scenery_dock.gd`.

**Hearts & chests** (2026-11-18) lists the heart quarter (`goo-heart`), the full heart, the roll
fragment (since 2026-11-20: `collectible-roll-fragment`, a Roll Fragment pickup; on its
`CollectibleScript` set `map_id` to the world's id and an `instance_id` no other pickup in that world
uses, or put `"roll-fragment": 1` in a chest's contents instead; four teach the Charged Roll, quests
spec 14.8) and the three chests (the wooden one for any world, the dungeon's two), for any world. Dragging one places its
scene under `Objects` with **Editable Children** on, so its script node shows in the Scene dock.
A heart quarter or a full heart gets its own `heart_id` as it is dropped, `<world>-heart-<n>` (since
2026-11-20: one left with the scene's placeholder, `unassigned`, is never picked up; B5's first
quarter was). A chest's heart is set by hand: `goo_heart_id` on its `ChestScript`, a name no other
heart uses (empty: no heart). The hover text on each picture says which. A search for "quarter" or "chest" finds them. The list is `HEARTS`
in the same script. (Editable Children at the drop is not yet tried in the editor: tick it on the
node's right-click menu if the script node does not show.)

**A piece with no sprite in its scene** (2026-11-12; owner: "some objects ... show like this with
the film, why?"): the dock lists a scene by its biggest sprite, so a piece whose script draws it
or builds its look when it runs showed Godot's scene icon (a film clapper). Such a piece now gets
the picture `addons/scenery_dock/scene_pictures.gd` names for it: its own art's first frame (the
brazier, crystal veil, divider gate, dungeon key, falling plank and slab, floor web, heavy plate,
shadow path, silk parcel, web wall), or an icon in its editor colours for a marker with no art (the
room door, room fight, hazard, hazard deck, plank landing, prize glint:
`asset/MAPS/palettes/dock/`, drawn by `scripts/art/build-dock-icons.py`, left out of exported games
with the palettes). A new piece that shows the film icon needs a line in that table.

**Enemies** (2026-10-16, roadmap 5.25): every enemy type with a scene, by its
picture. Dragging one places a **placed enemy** (`game/scenes/encounters/placed-enemy.tscn`) of that
type where it is dropped, under the world's `Enemies` node (made when missing), at its own size; the
world's enemies are these nodes, spawned once each time the world is built
([specs/enemy.md](specs/enemy.md) §3.3). In the 2D view it shows the enemy, its type and its wander
outline: by default a circle of its own (`wander_radius`, in the Inspector); for a camp, give its
enemies the same `wander_area_id`, the `area_id` of an `enemy-wander` world area (an Area2D with a
rectangle or circle CollisionShape2D and a `world_area.gd` node of kind `enemy-wander`, as the
converted camps have under `Areas`), and they all wander in it. Move the node to move the enemy;
`overrides` changes one enemy's numbers (e.g. `{"max_health": 120}`). A Dung Roller also shows
**Patrol Axis** (Horizontal or Vertical) and **Patrol Length** in the Inspector: the line it rolls
back and forth on, drawn in the 2D view.

**Painted props to nodes:** `tools/paint_to_nodes.gd` (headless, the world closed in the editor:
`--path godot -s res://tools/paint_to_nodes.gd -- --scene=<world> [--scene=...] [--keep=<prefixes>]
[--group] [--dry]`) turns a world's painted props into nodes under `Scenery`, each picture exactly where the
painted one was, and erases their cells; props whose scene path starts with a `--keep` prefix stay
painted (by default the ground details and the water life). A node's size and mirror are its own
Scale (negative x when mirrored), as for props dropped from the dock, so its collision follows its
size (a painted prop's collision kept the scene's size). The four level-1 chunks had theirs turned on
2026-10-14: 120 props became nodes (13 mirrored, 22 resized), 745 stayed painted. `--group` files the new ground details and water life in y-sorted folders under `Scenery/Ground details/` by kind (Water life, Rocks, Twigs, Flowers, Plants, Mushrooms, Leaves, by a whole word of the name or its plural: "stone" in `stepping-stone-1`, not in a gravestone; else the scene's folder) so the scene tree stays tidy, and every other prop straight under `Scenery`; each node is placed in its folder's own space, so a folder moved since keeps its nodes where they were painted; `--keep=` (empty) converts every prop, the ground details too (level-1-c4's 136 painted props were converted this way on 2026-10-18).

## Using it

1. Select the world's `cell-props` or `details` layer (a new world: **Add Node > PropLayer**, same
   position as the ground layer, its **Tile Set** `game/world/props/props_cell_tileset.tres` or
   `props_detail_tileset.tres`). The TileMap panel at the bottom lists the palette's sources on the
   left:

   | Layer | Cell | Sources |
   |---|---|---|
   | `cell-props` | 64 units, a ground tile | nature, rocks, water life, rock walls, crystal walls, houses, every interior set, dungeon decor, town, garden |
   | `details` | 32 units, a quarter of a ground tile | ground: leaves, branches, roots, pebbles, petals, clover, flowers, mushrooms, moss, stones |

2. Every prop takes a **block of whole cells** just big enough for it: a flower, a rock or a lily
   pad 1 x 1, a fence 2 x 1, a lamp post 1 x 2, the campfire or the tent 2 x 2, the well or a house
   more. The palette shows the props at their true size, each block on the palette's own grid, so a
   palette square is a map cell. Click a prop and paint: the cell you click is the block's
   **bottom-left** cell, and the prop stands centred in the block on its floor. The brush preview
   and the painted squares show the prop exactly where it will stand.
3. **Sizes:** a sized source (nature, rocks, crystal walls, interior decor, mushroom decor, dungeon decor, town, garden, ground) shows each prop three times side by side: small (70 %), normal and big (130 %).
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

**In the game** the layers never draw their palette squares (each turns its tile drawing off; the
cells stay readable), and an **exported** game has no palette pictures at all: the Scenery plugin's
export step (`addons/scenery_dock/palette_export.gd`) exports the paint layers' tile sets (props,
walls, forest, fences, interior walls) with every tile and its data but placeholders of the same
size for their pictures, and leaves the picture files out (`asset/MAPS/palettes/`, the wall, forest,
fence and interior-wall palette images),
about 42 million pixels, some 170 MB of textures a world would otherwise load.

`tools/build_prop_palettes.gd` (windowed: it renders) builds the `cell-props` and `details`
palettes: every scene under `game/scenes/objects/` whose path matches a source and whose only
scripts are presentation (idle animation, sound, `sheet_sprite.gd`, a house's `door_frame.gd`) is measured by its visible pixels, given its block,
rendered with the game's own drawing at its true size, a unit a pixel, into its slot of
`godot/asset/MAPS/palettes/<palette>-<source>.png` (a new scene goes to the source with the longest
prefix it matches, so the Lair's `decoration-world-solid--war-banner` is dungeon decor, not
nature; a scene already listed keeps its source; blocks packed in rows, a scene's three sizes
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
adding scenery scenes; then open the editor to import the images.

**Spare rows** (2026-11-25): a game run builds a palette's tiles against its picture as the editor
last imported it, and a tile past that picture's edge is no tile: every world that paints the palette
fails to load ("TileSetAtlasSource has no tile at ..."), as the dungeon decor palette did when eight
props made its picture taller. So each picture keeps empty rows below its last tile (at least 4, or a
fifth of its tile rows), its height in cells kept in the manifest (`height`, beside `width`): a new
prop goes into a spare row and the picture keeps its size, so the worlds load before the editor has
imported the new picture (only the Scenery dock waits for that import). When the tiles outgrow the
spare rows the picture grows again, with new spare rows, and the builder ends with an error naming
the palettes whose tiles reach past their imported pictures: focus the editor (it imports them)
before any game run. A picture, tile set or manifest is written only when it changed.

`tools/build_old_prop_palettes.gd`
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
| `godot/addons/scenery_dock/` | The Scenery dock: props by picture, dragged in as nodes; its Enemies category places enemies, its Suckables category liftables, its Dungeon objects category the dungeon pieces with logic, its Hearts & chests category the heart quarter, the full heart, the roll fragment and the chests, its Villagers and Animals categories the towns' people and animals |
| `godot/game/enemy/placed_enemy.gd`, `godot/game/scenes/encounters/placed-enemy.tscn` | A placed enemy: its type, wander area and overrides, its picture in the editor |
| `godot/tools/paint_to_nodes.gd` | Turns painted props into nodes under `Scenery` |
