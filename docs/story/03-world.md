# World

Release 1's three regions (Chapters 1 to 3, owner, 2026-10-15), with part of
the West village and the Wilds that connect them (owner, 2026-10-16), are only
the beginning. *Changed 2026-11-17 (owner, question 149): all of the West
village's town, Glimmerhill, is Release 1.* To feel like a Zelda world,
the game needs many more regions, and inside them dungeons, castles and mazes,
each with its own boss. This page lists what exists, what is sketched, and the
empty slots still to fill.

## Regions in order

| # | Region | Maps | Chapter | What has gone wrong (story) | Boss | Status |
|---|---|---|---|---|---|---|
| 1 | **Slimeshire Meadow** | `level-1`, `slime-home`, `mushroom-home` | 1 | Worms moved in, the smith fled, the Forge is cold and the Workshop is a ruin | Fatty One Eye | Built |
| 2 | **Gloop Forest** | `gloop-forest`, `gloop-hut`; the Weaver Hollow, its dungeon (built 2026-10-17); `gloop-cavern`, a small secret cave (owner, 2026-10-16, question 18) | 2 | The forest is choked with webs; the Matron's brood spreads | Orb-Weaver Matron | Built, in progress |
| 3 | **Crystal Caverns** | `crystal-caverns`; the Crystal Mine, its dungeon (built 2026-10-17) | 3 | Crystal grows over everything in the caves; the Colossus has blocked the smith's crystal mine | Crystal Colossus; his Pearl grants the Feral skin (owner, 2026-10-16) | In Release 1 since 2026-10-15; the chapter is a [sketch](chapters/chapter-3-crystal-caverns.md), with Planned beats of 2026-10-16. The mine camp and the Crystal Mine are built (2026-10-17), and the Bow (2026-11-20): Pip carves its rune in Slimeshire once Pearl 2 is home and the slime brings him the wood, the Matron's thread and the smith's crystal, so Pearl 3 waits for that (owner, 2026-11-20; not playtested) |
| — | **Glimmerhill**, the West village's town (named by the owner, 2026-11-17, question 149) | `west-village` (chunks A4, B4, A5, B5) and its 27 rooms | 1 to 3 | Asleep: dark, its fountains dry, its villagers in a trance, until the Pearls come home (Planned, owner, 2026-11-17) | None | Built 2026-11-01 to 2026-11-12; asleep and waking built 2026-11-20 (Market Hill with Pearl 1, West Hill with Pearl 2, the south gate's quarter with Pearl 3; the farms and the lake stay asleep: [below](#the-west-village)). All of it is Release 1 |
| 4 | **Sticky Swamp** | `sticky-swamp` (placeholder) | ? | Slow mud, poison, rain, spider-slimes | Old Gullet, the catfish, who swallows whatever falls in and hides in deep mud and water; his Pearl grants the Swim skin (owner, 2026-10-16, question 32) | Idea; its boss and skin Planned |
| 5 | **Frostpeak** | `frostpeak` (placeholder); `icege` is a candidate | ? | Ice physics and snow | Old Rimepaw, the polar bear (a working name), who slides across the frozen lake on his belly and cracks the floes with a slam; his Pearl grants the Polar skin (question 32) | Idea; its boss and skin Planned |
| 6 | **Volcano Ridge** | `volcano-ridge` (placeholder); `hot` and `emberleef` are candidates | Finale | Gorge's prison; the rumbling comes from here | On its slopes Cinder, the magma salamander, whose Pearl grants the Lava skin, the last, which opens the way into the crater; in the crater Gorge, the ninth and final boss, with no skin (question 32) | Idea / Proposal; the bosses and the skin Planned |
| ? | **Desert** | `desert` (placeholder) | ? | Dunes walled by cliffs | Sandmaw, the great sand worm, Gorge's worm general, who burrows under the dunes and bursts out; his Pearl grants the Sand skin (question 32) | Idea; its boss and skin Planned |
| ? | **Northern ruins** | `northern-ruins` (placeholder) | ? | A ruin maze on a plateau | Gale, the storm roc, which flies over the ruin maze and blows gusts; its Pearl grants the Cloud skin (question 32) | Idea; its boss and skin Planned |

The first map of each row is the region's world scene in the layout,
`godot/game/data/world-map.json`. A placeholder world is generated from the
layout by `godot/tools/build_region_worlds.gd` and stands in until the region
is built ([WORLD_ATLAS.md](../godot/WORLD_ATLAS.md)). The layout's other
regions are open slots with placeholder worlds too: Northern ruins
(`northern-ruins`), Desert (`desert`), and the North and South Wilds
(`north-wilds`, `south-wilds`) between the regions. *Changed 2026-11-17: the
West village (`west-village`) was a placeholder until its town, Glimmerhill,
was built over its four chunks (2026-11-01 to 2026-11-12), and all of it is
Release 1 (owner, question 149; [below](#the-west-village)). The desert holds
the elevation maze (2026-11-07), which is not Release 1 (owner, question 156).*
*Since 2026-10-16 (ninth round, question 32) every vassal region has its boss
and skin: one skin per vassal, each a new way through the world that opens
come-back secrets in the places before it. The order of the later regions,
and of their chapters, was question 10; the acid skin stays a spare.* *Answered 2026-11-21 (owner,
question 10): after Chapter 3 and Release 1 the map is open, only ability blockers stand in the way, and
the slime passes them as its powers grow, so the later regions have no set order.*

**Release 1's map (Planned, owner, 2026-10-16).** Release 1's content ends
when the Crystal Colossus falls, but the game goes on: the player explores the
first three chapters' regions, the West village and the Wilds that connect
them with the new powers, and the game says that from here on it is
exploration and that more areas come in later releases. Barriers in the world
close the ways to the regions that are not in Release 1 (a fallen bridge, a
landslide, a Thorn Guard post), and each says that more lies beyond (owner,
2026-10-16,
[question 73](07-decisions-archive.md#contradictions-left-after-the-review-2026-10-15)).
*Changed 2026-10-16 (eighth round, question 130): every border is a Thorn
Guard post, a striped barrier with a guard who says what lies beyond is
closed for now; no landslides or fallen bridges, which would read as the
Heavy Roll's rubble and tree bridge.*
From the Wilds, the Crystal Caverns are reached up a hill that only the Feral
skin climbs, so that way opens once Feral is won, and Gloop Forest through a
second web maze that only the Silk skin passes (owner, 2026-10-16,
question 87). So the Wilds never skip the Verdant Gate or the web-wall maze.
*As built (2026-11-14): no Thorn Guard post is built, and the Wilds are open
from Slimeshire's C5, Gloop Forest's E5, the Caverns' H4 and H5 and the West
village's A4 and B5. Their ways into Gloop Forest and the Caverns are plain
openings, not the web maze and the climb (question 164). The owner closed the
North Wilds' links into Slimeshire (C3 to C4) and Gloop Forest (F3 to F4) on
2026-10-31. The desert's elevation maze (A7 to C8, built 2026-11-07 in place of
the Sunscar Mesas) holds three heart quarters, with the orphaned Sunscar caves;
it is not Release 1 and stays as an idea of what comes next (owner,
2026-11-17, question 156), so a post must close the way to it.*
*Changed 2026-11-19 (owner, question 164): the Wilds are walled off for all of
Release 1, by terrain, with no guard posts; the web maze and the climb from the
Wilds wait for the release that opens them. Built 2026-11-20: the six ways
between the Wilds and Release 1's regions (Slimeshire's C5, Gloop Forest's E5,
the Caverns' H4 and H5, Glimmerhill's A4, and B5's south gate, closed on B5's
side already) are planted shut with trees or crystal groves on both sides of
the line, their exits and the map's passages gone
([WORLD_ATLAS.md](../godot/WORLD_ATLAS.md#the-wilds-walled-off-2026-11-20)).*

**The prologue (Planned, owner, 2026-10-16,
[question 97](07-decisions-archive.md#contradictions-left-after-the-review-2026-10-15)).**
Before Chapter 1 a short, closed place in the south, between chunks B4 and
C4, ringed by forest: the Wellspring in B4, where the slime is born, and the
glade on C4's south-west edge, where it saves Yoi. Its barred gate opens into
Slimeshire. Chunk content may move to fit it; if it does not fit naturally, it
can be an underground cavern. After the prologue a short forest path from
Slimeshire's south-west leads back to the Wellspring (question 98). The
[prologue design](../design/2026-10-16-prologue.md) has the screens.
*Changed 2026-10-16 (seventh round, question 112): in B4 the prologue takes
the south edge, sealed off by forest, and the West village's town sits in
B4's north and A4. The forest path to the Wellspring leaves Slimeshire, not
the town. The prologue cannot be saved, and the HUD appears right after the
birth scene (question 113).* *Built 2026-10-16 ([PROLOGUE.md](../godot/PROLOGUE.md)):
both screens lie on B4's south edge under a forest band, the Wellspring in its
south-west and the glade in its south-east, right against C4 (C4's south-west
edge holds the starter camp's yard and was too narrow to seal off); the
glade's barred gate and a short forest path come out on Slimeshire's west
edge (C4), and that same path leads back to the Wellspring afterwards. The
world map's markers and the West village's opening onto Slimeshire are still
to redraw: the old opening is now the prologue's path, so the town needs its
own.* *Since 2026-11-17 (owner): a fallen tree that only a Heavy Roll breaks
blocks the way to Glimmerhill's Market Hill, so the slime reaches the town only
with the Heavy skin.*

**Proposal: "What has gone wrong" always traces back to a Pearl.** It swelled
the boss, or it drove creatures out of their homes. This gives every region a
problem that the slime can actually fix.

**Open:** the order of regions 4 and 5, how many more regions the world needs,
and where castles and mazes fit. Zelda games have eight or more dungeons; at one
region per chapter, the world needs eight or more chapters.

**The great mountain (Planned, owner, 2026-11-17, question 154).** Part of the
North Wilds, the Northern ruins and all of Volcano Ridge become big mountains.
Selected entrances on the mountain floor lead up, and the mountain's high
levels use the sky floor ([SKY_FLOOR.md](../godot/SKY_FLOOR.md)): framed by the
camera, its sky is never seen from below, as Zelda paints its mountain. The
sky floor is built only in the playground so far.

**Tall cliffs, balconies and cliff caves (Planned, owner, 2026-11-17,
question 155).** Cliffs up to level 16, balconies that step out of a tall wall
and cave mouths on a cliff's face, reached up the Feral skin's vines, are in
Release 1, since the Feral skin is. Where they go is not set; today they are
only in the playground and the climb lab ([SKINS.md](../godot/SKINS.md#feral)).

## World size and screen

**Decided (2026-10-07):** the world is built on the grid of Zelda: A Link to
the Past's overworld (the reference is in `asset/Originals/MAPS/Maps/`:
`maps.md`, `zelda map.png` and `regions.png`). That world is 256 × 256 tiles,
cut into **8 × 8 chunks of 32 × 32 tiles**, and its regions are groups of
chunks: Kakariko Village, Hyrule Castle and the Lost Woods are 2 × 2 chunks
each, Death Mountain about 4 × 2.

| Unit | Tiles | Pixels (64 px tiles) |
|---|---|---|
| Tile | 1 | 64 × 64 |
| Screen (play area) | 16 × 14 | 1024 × 896 |
| Chunk | 32 × 32 (2 × 2.3 screens) | 2048 × 2048 |
| Region, usual size | 64 × 64 (2 × 2 chunks, 4 × 4.6 screens) | 4096 × 4096 |
| Whole overworld | 256 × 256 (8 × 8 chunks) | 16384 × 16384 |

Rules for every map:

1. **One tile is 64 × 64 px, and everything is sized in tiles.** The slime is
   about one tile, a tree 2 tiles wide and about 2.7 tall, a house 5 × 5.
2. **The screen shows 16 × 14 tiles**, as Zelda does. The play area is
   1024 × 896 px, and under it the HUD console takes a 128 px strip (2 tiles,
   since 2026-10-08), so the game's base view is 1024 × 1024 px. Godot scales
   it to fit the window: the play area is never smaller than 16 × 14 tiles,
   and a wider window shows more columns (a 16:9 window shows about 28 × 14).
   The menus and the HUD scale with it.
3. **An overworld map is a whole number of chunks**: its columns and rows are
   multiples of 32. A small area is one chunk (32 × 32), a region is usually
   2 × 2 chunks (64 × 64), and a large one, like Death Mountain, 4 × 2
   (128 × 64).
4. **The whole overworld is at most 8 × 8 chunks.** Each overworld map takes
   a place on that grid, and maps that touch on the grid connect through their
   shared edge.
5. **Interiors are not on the grid.** Houses, huts, caves and dungeons are their
   own maps. A room fits on one screen (16 × 14 tiles at most), as
   `slime-home` (14 × 11) and `mushroom-home` (16 × 12) already do; bigger
   caves and dungeons are made of whole screens. *Changed 2026-10-17 (owner):
   a room may be bigger than a screen; its doors are part of its wall art,
   always on its edge.*
6. **A map's edge is a wall** (forest, cliff or water, two or three tiles
   thick), broken only where an exit leads to the next map.
7. **Chunk lines are closed by terrain** (owner, 2026-11-01,
   [level design rule 11](../design/2026-10-16-level-design.md#the-rules-that-matter-most)):
   cliffs, water and canals, forest bands or walls, each chunk closing its own
   side. Two touching chunks meet at one to three crossings, each a road wide
   at most, never at a corner, and marked as a way out (a bridge, a ford,
   stairs, a gate, a trail gap between lantern posts). Owner: "the player can
   walk in zigzag from one chunk to another, what makes the game experience
   bad". Gloop Forest's lines are closed; the other regions' are not yet
   (`tools/check_chunk_lines.gd`).
8. **Physical barriers, not key gates** (owner, 2026-11-17): outside the
   dungeons a way is shut by something a power removes, not by a key gate. A
   fallen tree that a Heavy Roll breaks replaces the Verdant Gate
   (question 163), and another blocks the way to Glimmerhill's Market Hill.

| Map | Size (tiles) | Chunks | Status |
|---|---|---|---|
| `level-1` (Slimeshire Meadow) | 64 × 64 | 2 × 2 | Cut into four chunk scenes on 2026-10-14 (`level-1-c4` the village … `-d5`) |
| `gloop-forest` | 64 × 64 | 2 × 2 | Grown from 54 × 54 on 2026-10-12: its east and south strips are a tree wall (a ForestLayer), the river and the east road run on to the new edge, its camp moved 4 tiles west into chunk E4 |
| `crystal-caverns` | 64 × 64 | 2 × 2 | Grown from 54 × 54 on 2026-10-12: its east and south strips are cavern floor |
| Placeholder regions: `northern-ruins`, `sticky-swamp`, `frostpeak` | 64 × 64 | 2 × 2 | Built from the sketch by `godot/tools/build_region_worlds.gd` ([WORLD_ATLAS.md](../godot/WORLD_ATLAS.md)) |
| `west-village` (Glimmerhill) | 64 × 64 | 2 × 2 (A4, B4, A5, B5) | Built 2026-11-01 to 2026-11-12: a hill town over all four chunks, with 27 rooms; B4's south edge holds the prologue |
| `desert` | 64 × 64 | 2 × 2 | The elevation maze over A7 to C8 (with the South Wilds' C7 and C8), built 2026-11-07 in place of the Sunscar Mesas, whose five cave rooms are orphaned; not Release 1 (question 156) |
| Placeholder regions: `volcano-ridge` (L-shaped), `north-wilds`, `south-wilds` | 96 × 64, 256 × 96, 256 × 96 | their block | Only their own chunks are walkable |
| `icege`, `hot`, `emberleef` and the other dev candidates | 54 × 54 | not whole | Not on the map |
| `slime-home`, `mushroom-home`, `gloop-hut` | 16 × 12, 16 × 12, 14 × 11 | interior | Fit on one screen (the first two round mushroom rooms since 2026-11-20) |
| `gloop-cavern` | 22 × 14 | interior | Two screens wide; a small secret cave, the Goo Bomb's come-back secret, holding one of Gloop Forest's heart quarters (owner, 2026-10-16, question 18); a crystal-cave interior wall frame round an 18 × 10 floor since 2026-11-20, its only way out the ladder |

Each region's chunks (A1 in the north-west to H8 in the south-east) are in the
world map below, and the layout itself is the game's
`godot/game/data/world-map.json`. Slimeshire Meadow holds C4, D4, C5 and D5,
so `level-1`'s 64 × 64 tiles are exactly those four chunks.

## World map

A rough sketch of the whole world: which region sits where, its ground and
hills, and what connects to what. It is drawn with the world map tool
(`pnpm story:map`, then open http://127.0.0.1:3210; see
[TOOLING](../TOOLING.md#story)).

The tool saves three things:

- the drawing to
  [`godot/game/data/world-map.json`](../../godot/game/data/world-map.json);
- the picture to `world-map.png`;
- the block below, which it rewrites on each save.

That file is also the game's world layout. Each region names its overworld
scene (`world`) and its interiors. The in-game world map and the Godot world
atlas read the file. The region builder (`godot/tools/build_region_worlds.gd`)
makes the placeholder regions from it and writes back the openings between
touching regions. The tool's layout tools move whole regions or blocks of
chunks with everything on them.

The sketch is 128 × 128 cells, so one cell is 2 × 2 tiles and one chunk is
16 × 16 cells. Its ground, water and cliffs were traced from the A Link to the
Past reference, and its regions started in the reference's places. On
2026-10-10 the middle row was laid out as in the game, from west to east:

1. a west village;
2. Slimeshire Meadow;
3. Gloop Forest, through the Verdant Gate on `level-1`'s east edge;
4. the Crystal Caverns.

The other regions:

- Northern ruins and Volcano Ridge are on the great mountain to the north.
- Sticky Swamp and a frozen-lake Frostpeak are to the south.
- A desert is in the south-west.
- The **North Wilds** and **South Wilds** are the connecting zones between
  them all.

The ruins and the desert are empty slots, and part of the village joins
Release 1 (owner, 2026-10-16; [The West village](#the-west-village)). The
layout is a **Proposal**.

*Since 2026-10-16 (seventh round, question 112): the prologue takes B4's
south edge and the West village's town B4's north and A4; the sketch below
shows them so.*

*The block below predates world-map.json's changes of 2026-10-20 to 2026-11-20
(the Lair's secrets outside, Glimmerhill's rooms, the closed and moved
crossings, the fallen trees, the Wilds walled off); it needs a fresh save from
`pnpm story:map`.*

<!-- world-map:start -->
<!-- Generated by the world map tool (pnpm story:map) from godot/game/data/world-map.json. Draw on the map instead of editing this block. -->

![World map sketch](world-map.png)

The map is cut into 8 × 8 chunks, A1 in the north-west; a region's chunks are those where it holds most of the ground.

| Region | Chapter | Status | Chunks | Borders | World | Interiors | Boss | Notes |
|---|---|---|---|---|---|---|---|---|
| **Slimeshire Meadow** | 1 | Built | C4, D4, C5, D5 | North Wilds, West village (open), Gloop Forest, South Wilds | level-1 | slime-home, mushroom-home, fatty-lair | Fatty One Eye | The hub, in the middle of the world (the castle's place in the reference): the plaza ringed by water. Worms moved in, the smith left for his crystal mine, the Workshop is a heap of boards until Pearl 2 comes home and the Forge is cold until Pearl 3 does (owner, 2026-11-20); his son Pip keeps them. The prologue (the Wellspring and the glade) lies in the south-west, between B4 and C4, and teaches the Spear; Yoi's home lies under Lili's west yard; Fatty's Lair, the worms' burrow, opens in Fatty's Hollow, a red-rock hill in D5 behind the old fort's field maze and a bridge of falling slabs; the old Thorn Guard gate there only a Roll beats. Release 1. |
| **Gloop Forest** | 2 | In progress | E4, F4, E5, F5 | North Wilds, Slimeshire Meadow, Crystal Caverns, South Wilds | gloop-forest | gloop-hut, gloop-cavern, weaver-hollow-trunk, weaver-hollow-roots, weaver-hollow-boughs, weaver-hollow-crown | Orb-Weaver Matron | East of the hub, as in the game (moved 2026-10-10): the Verdant Gate on level-1's east edge leads in. Choked with webs; the Matron's brood spreads. A maze of web walls on its east side, which only the Silk skin (the Matron's Pearl) passes, leads to the Crystal Caverns. Release 1. From the Wilds a second web maze leads in, which only the Silk skin passes. The Matron lives at the top of the Weaver Hollow, Chapter 2's dungeon; the Watch Oak's root gate in F4 is its way in (owner, 2026-10-16, question 133). The small Gloop Cavern behind the cracked clearing's sinkhole is the Goo Bomb's come-back secret, with one of the forest's heart quarters (question 18). |
| **Crystal Caverns** | 3 | Planned | G4, H4, G5, H5 | North Wilds, Gloop Forest, South Wilds | crystal-caverns | crystal-mine | Crystal Colossus | East of Gloop Forest, as in the game (moved 2026-10-10; open without a key in the game for now). The west half of the great mountain: caves through the rock. The smith runs the crystal mine, which the Crystal Colossus has blocked; at his mine camp he gives the Lantern. A dark maze the Lantern lights, and the Colossus's arena ringed by four braziers. Pearl 3 grants the Feral skin. Reached from Gloop Forest through the web-wall maze (the Silk skin). Release 1 ends when the Colossus falls. From the Wilds a hill leads in, which only the Feral skin climbs, so that way opens once Feral is won. |
| **Volcano Ridge** | Finale | Idea | F1, G1, H1, F2, G2 | Northern ruins (open), North Wilds | volcano-ridge (placeholder) |  | Gorge | The east half of the great mountain, around the crater. Gorge's prison; the rumbling comes from here. Cinder, the magma salamander, guards the slopes with the Lava skin's Pearl, the last skin, which opens the way into Gorge's crater (question 32). |
| **Frostpeak** | ? | Idea | F7, G7, F8, G8 | South Wilds, Sticky Swamp | frostpeak (placeholder) |  | Old Rimepaw | Proposal: the great lake in the south-east, frozen, with snowy cliffs: ice physics and snow. Old Rimepaw, the polar bear, holds the Polar skin's Pearl: sure-footed on ice and every slippery surface, and a belly-slide Roll on ice (owner, 2026-10-16, question 32). |
| **Sticky Swamp** | ? | Idea | D7, E7, D8, E8 | South Wilds, Frostpeak | sticky-swamp (placeholder) |  | Old Gullet | South of the hub (the Great Swamp's place). Slow mud, poison, rain, spider-slimes. Old Gullet, the catfish, holds the Swim skin's Pearl (owner, 2026-10-16, question 32). |
| **West village (open)** | 1 | Planned | A4, B4, A5, B5 | North Wilds, Slimeshire Meadow, South Wilds | west-village (placeholder) |  |  | A second town (Kakariko's place). Its first part joins Release 1: the house of Burr the gatekeeper, where young Burr teaches the Roll, three or four more houses, a shop and a game to play. The rest comes in later releases. |
| **Northern ruins (open)** | ? | Idea | D1, E1, D2, E2 | North Wilds, Volcano Ridge | northern-ruins (placeholder) |  | Gale | Moved north 2026-10-10 (Crystal Caverns took the east). Empty slot: a ruin maze on a plateau (the Eastern Palace's place). A dungeon region. Gale, the storm roc, holds the Cloud skin's Pearl: floating across gaps from a ledge and riding updrafts (question 32). |
| **Desert (open)** | ? | Idea | A7, B7, A8, B8 | South Wilds | desert (placeholder) |  | Sandmaw | Empty slot: a desert walled by cliffs (the Desert of Mystery's place). Sandmaw, the great sand worm and Gorge's worm general, holds the Sand skin's Pearl: burrowing through soft sand, under sand walls and through quicksand (question 32). |
| **North Wilds** | ? | Idea | A1, B1, C1, A2, B2, C2, H2, A3, B3, C3, D3, E3, F3, G3, H3 | Northern ruins (open), Volcano Ridge, West village (open), Slimeshire Meadow, Gloop Forest, Crystal Caverns | north-wilds (placeholder) |  |  | The connecting fields north of the middle row (the Wilds split in two 2026-10-10). The connecting zones: the fields, roads, rivers and ledges between the regions. Every region opens onto them, so the hub reaches all of them. Open to explore in Release 1 after the Crystal Colossus; the ways to the regions that are not in Release 1 are closed by Thorn Guard posts: a striped barrier with a guard who says what lies beyond is closed for now (owner, 2026-10-16, question 130). |
| **South Wilds** | ? | Idea | A6, B6, C6, D6, E6, F6, G6, H6, C7, H7, C8, H8 | West village (open), Slimeshire Meadow, Gloop Forest, Crystal Caverns, Desert (open), Sticky Swamp, Frostpeak | south-wilds (placeholder) |  |  | The connecting fields south of the middle row: roads to the swamp, the desert and Frostpeak. Open to explore in Release 1 after the Crystal Colossus; the ways to the regions that are not in Release 1 are closed by Thorn Guard posts: a striped barrier with a guard who says what lies beyond is closed for now (owner, 2026-10-16, question 130). |

**Connections**

| Passage | Kind | Connects | Needs | Notes |
|---|---|---|---|---|
| Opening | Opening (generated) | Northern ruins (open) ↔ North Wilds | nothing | Cut by the region builder |
| Opening | Opening (generated) | Volcano Ridge ↔ Northern ruins (open) | nothing | Cut by the region builder |
| Ridge path | Gate / passage | Volcano Ridge ↔ North Wilds | ? |  |
| Opening | Opening (generated) | Volcano Ridge ↔ North Wilds | nothing | Cut by the region builder |
| Opening | Opening (generated) | West village (open) ↔ North Wilds | nothing | Cut by the region builder |
| Opening | Opening (generated) | Slimeshire Meadow ↔ North Wilds | nothing | Cut by the region builder |
| Opening | Opening (generated) | Gloop Forest ↔ North Wilds | nothing | Cut by the region builder |
| Opening | Opening (generated) | Crystal Caverns ↔ North Wilds | nothing | Cut by the region builder |
| 2 openings | Opening (generated) | Slimeshire Meadow ↔ West village (open) | nothing | Cut by the region builder |
| Verdant Gate | Gate / passage | Slimeshire Meadow ↔ Gloop Forest | Green key | level-1's east exit into Gloop Forest (the gate object stands at (3776, 768)) |
| Verdant Gate | Opening (generated) | Slimeshire Meadow ↔ Gloop Forest | nothing | Cut by the region builder |
| Web-wall maze | Gate / passage | Gloop Forest ↔ Crystal Caverns | Silk skin | gloop-forest's east way into the Crystal Caverns: a maze of web walls only the Silk skin passes (owner, 2026-10-16); open without a key in the game for now |
| Web-wall maze | Opening (generated) | Gloop Forest ↔ Crystal Caverns | nothing | Cut by the region builder |
| Opening | Opening (generated) | West village (open) ↔ South Wilds | nothing | Cut by the region builder |
| Plaza bridge | Gate / passage | Slimeshire Meadow ↔ South Wilds | nothing | The way out of Slimeshire into the Wilds |
| Plaza bridge | Opening (generated) | Slimeshire Meadow ↔ South Wilds | nothing | Cut by the region builder |
| Opening | Opening (generated) | Gloop Forest ↔ South Wilds | nothing | Cut by the region builder |
| Opening | Opening (generated) | Crystal Caverns ↔ South Wilds | nothing | Cut by the region builder |
| Opening | Opening (generated) | Desert (open) ↔ South Wilds | nothing | Cut by the region builder |
| Swamp road | Gate / passage | Sticky Swamp ↔ South Wilds | ? |  |
| Swamp road | Opening (generated) | Sticky Swamp ↔ South Wilds | nothing | Cut by the region builder |
| Lake bridge | Gate / passage | Frostpeak ↔ South Wilds | ? |  |
| Lake bridge | Opening (generated) | Frostpeak ↔ South Wilds | nothing | Cut by the region builder |
| Opening | Opening (generated) | Frostpeak ↔ Sticky Swamp | nothing | Cut by the region builder |
| Gloop Cavern | Cave / stairs | Gloop Forest → gloop-cavern | Goo Bomb (cracked ground) |  |
| Yoi's home | Cave / stairs | Slimeshire Meadow → interior | Gulp away the heap of crates over the hatch in Lili's west yard (optional) | Old Veteran Yoi's den, his home after the prologue: Lili's tip finds it; Yoi's war tips, Slimeshire's fifth heart quarter and a Roll Fragment in his chest, behind a Heavy statue maze (the whole Charged Roll until the owner's change of 2026-11-20); later the Spear's upgrades. Built 2026-11-20 (`slimeshire-yoi-home`) |

**Places on the map**

| Place | Kind | Region | Chunk | Needs | Notes |
|---|---|---|---|---|---|
| Crystal Mine | Dungeon | Crystal Caverns | G4 |  | The smith's crystal mine, taken by the Crystal Colossus (built 2026-10-17): six dark rooms the Lantern teaches, the Foreman's Gate's two keyholes, the Chasm's lens for the Bow; Pearl 3 (the Feral skin) in the Den behind the Shardback, and its take seals the mine; the Feral second half (root walls to climb, the big key on a balcony), then the Colossus, enraged, in his arena of four braziers, climbing his wall; the climb out to the Lookout |
| Mine camp | Town / hub | Crystal Caverns | G4 |  | The smith runs the crystal mine; he gives the Lantern, then his crystal for Pip's bow rune, and stays here after the Colossus (owner, 2026-11-20) |
| The Lookout | Landmark | Crystal Caverns | H4 |  | Daylight on the mountain in H4, where the climb out of the Colossus's arena arrives; a path down to the camp |
| Desert ruin? | Note / idea | Desert (open) | A7 |  | Empty slot |
| Forest camp | Town / hub | Gloop Forest | F5 |  |  |
| Weaver Hollow | Dungeon | Gloop Forest | F4 | Goo Bomb | The Watch Oak, an old Thorn Guard watch fort inside a giant oak (built 2026-10-17): a Goo Bomb blows its root gate; four floors climbed from the Roots to the Crown; Pearl 2 (the Silk skin) in the Hoard behind the Brood Warden, and its take seals the Hollow; the Silk second half (webbed rooms, the Spinning Loft), then the Orb-Weaver Matron at the top, enraged, fighting from a cocoon a blast tears open |
| Ruin maze? | Note / idea | Northern ruins (open) | E1 |  | Empty slot: a dungeon |
| Slimeshire plaza | Town / hub | Slimeshire Meadow | C4 |  | The middle of the world |
| Your house | House / interior | Slimeshire Meadow | C4 |  |  |
| Mushroom house | House / interior | Slimeshire Meadow | C4 |  | The red mushroom house near the plaza (where the Workshop stood until 2026-11-20); its door `mushroom-home-door` leads to `mushroom-home` |
| Dora the Fishergirl | NPC | Slimeshire Meadow | C5 |  | At the water around the plaza (renamed from Lily on 2026-10-11; the game says Dora since 2026-11-19) |
| Fatty's Lair | Dungeon | Slimeshire Meadow | D5 |  | The worms' burrow under the old Thorn Guard fort, in Fatty's Hollow, a red-rock hill in D5 behind the field maze and a bridge of falling slabs (built 2026-10-17, the mouth moved from D4 the same day): the drop gate a Roll beats, falling slabs over the void and spikes, Burr freed from his two-keyhole cell; Pearl 1 (the Heavy skin) in the Larder behind the Big Squint, and its take seals the Lair; the Heavy second half (the Weigh House, the big key), then Fatty One Eye, enraged, whose fall breaks the seals; the green key at the postern, out through a barricade a Heavy Roll breaks, by the bolt-hole near the Verdant Gate |
| The Lair's bolt-hole | Landmark | Slimeshire Meadow | D4 |  | Fatty's Lair's way out (arrival only), by the Verdant Gate; Burr waits here after Fatty |
| Fatty's Hollow | Landmark | Slimeshire Meadow | D5 |  | D5's red-rock hill, crowned with maples; the Lair's drop gate in a notch of its south face, over a paved forecourt (a campfire, an energy flower, a pot hiding a heart) |
| Field maze and moat slabs | Landmark | Slimeshire Meadow | D5 | Roll | The old fort's field before the hill: a maze of fieldstone walls cut by a dry moat; two falling slabs cross it in one Roll, a walk falls back to the rim |
| Hill crack | Secret / heart | Slimeshire Meadow | D5 | Goo Bomb | A crack in the hill's face beside the Lair's gate opens into a cave pocket with a goo heart, seen from the forecourt (a Chapter 2 come-back) |
| First bell and keeper storehouse | Secret / heart | Slimeshire Meadow | C4 |  | C4: the pond bell unlocks a timber storehouse; its coffer, pots and supplies are inside a separate furnished room. |
| Lookout bell | Secret / heart | Slimeshire Meadow | C5 |  | C5: a bell on a lookout rock; a pot thrown from its foot rings it and raises a hidden chest |
| Old pen, grey planks | Secret / heart | Slimeshire Meadow | D4 | Heavy skin | D4: an old Thorn Guard pen by the road, its gap shut by grey planks a Heavy Roll breaks; a goo heart inside (a come-back with Pearl 1) |
| Gorge | Boss | Volcano Ridge | F2 |  | Finale, in the crater |
| The Wellspring | Landmark | West village (open) | B4 |  | The prologue's lake, where the slime is born (owner, 2026-10-16): a pool of glowing goo ringed by forest, the first screen of the prologue in B4's south-west. The prologue's forest path from Slimeshire's south-west reaches it later; each Pearl comes home here |
| West village | Town / hub | West village (open) | A4 |  | Burr's house (young Burr teaches the Roll), a few houses, a shop and a game: Release 1's part |
| The glade | Landmark | West village (open) | B4 |  | The prologue's second screen, in B4's south-east: Yoi falls to four worms; the slime saves him by throwing things and learns the Spear. A barred gate (the Spear's lock) opens onto a forest path to Slimeshire's west edge |
<!-- world-map:end -->

## Slimeshire: the hub

Slimeshire is home. The slime comes back to it between chapters, and the town
grows as Pearls return.

| Place | What happens there | Status |
|---|---|---|
| The clearing | The slime's first steps; the first quests (Planned: NPCs give tips, and the journal keeps one main quest, question 60). *Since 2026-10-16 the first steps are the prologue's, and the slime comes out of the forest at the town's edge, where Plop meets it (questions 97 and 100)* | Built |
| **The Wellspring** | The prologue's lake, where the slime is born, between chunks B4 and C4 (owner, 2026-10-16, questions 97 and 98). After the prologue a short forest path from Slimeshire's south-west reaches it. Each Pearl's homecoming is a short scene here, and it brightens; each returned Pearl restores a building (question 60). A campfire stands by it (question 104). *Changed 2026-10-16 (seventh round): every Pearl goes home here, and its power flows into the town: the well comes back with Pearl 1, the Forge lights with Pearl 2 (question 110). It lies on B4's south edge, sealed off by forest, and its forest path leaves Slimeshire, not the West village's town (question 112)* *Changed 2026-11-20 (owner): Pearl 2 raises Slimeshire's Workshop and Pearl 3 lights its Forge* | Built 2026-10-16 as the prologue's first screen (B4's south-west); the homecoming scenes and its campfire built 2026-11-20: the Pearl rises out of the slime and sinks into the pool, which glows a step brighter for each Pearl home, a card names the part of Glimmerhill that wakes (Pearl 2's also tells of the Workshop rising, Pearl 3's of the Forge glowing), and for Pearl 1 the camera shows Market Hill's fountain burst into flow ([PROLOGUE.md](../godot/PROLOGUE.md#the-homecoming-2026-11-20)); the well's restoring is not built, and the energy refill went to Glimmerhill's woken fountains (built 2026-11-20); its campfire is a craft panel (until 2026-10-16: its own map east of level-1, the game's first map) |
| **The glade**, C4's south-west edge (*built in B4's south-east, against C4*) | The prologue: Yoi falls to four worms, and the slime saves him by throwing things and learns the Spear. An old Thorn Guard gate, its lever behind bars, opens into Slimeshire with a Spear thrust ([prologue](../design/2026-10-16-prologue.md)) | Built 2026-10-16 (planned by the owner the same day, question 97) |
| **Slimeshire's well** | Pearl 1 restores it when it comes home, and from then on it refills the slime's energy (owner, 2026-10-16, question 90). After Fatty, the freed Burr and the journal send the slime home, and the well comes back when the slime brings the Pearl to it (question 103); it gives a full refill, a drink in town (question 105). *Changed 2026-10-16 (seventh round): the slime takes Pearl 1 home to the Wellspring, and its power brings the well back (question 110); the well's refill grows back after a while, so it is not used up (question 113)* *Changed 2026-11-17 (owner, question 153): Glimmerhill's woken fountains refill energy, which takes over the well's job* | Planned; its refill moved to Glimmerhill's fountains (question 153), built there 2026-11-20 |
| **The town's campfire** | It makes Chapter 1's one or two recipes; campfires also stand by the Wellspring and at each camp, so a fresh save can always heal (owner, 2026-10-16, question 104). Potions and food are both crafted at a campfire (question 66) | Built 2026-11-20: any campfire opens the craft panel (C4's and C5's, the Wellspring's, the mine camp's), listing the recipes the slime knows ([crafting spec 12](../godot/specs/crafting.md#121-the-campfire-and-the-forge)) |
| Elder Plop's path | The main-line giver for Chapter 1. Planned: he hands over the 10-slot bag (question 74), and after the Spear he sends the slime to Burr in the West village (owner, 2026-10-16). *Changed 2026-10-16 (sixth round, question 100): he meets the slime at the town's edge as it comes out of the forest, gives it the bag and its first tips, with the exclamation mark, and later sends it to Burr* | Built |
| **Your house** (behind the round mushroom house in C4 since 2026-11-12; until then the red forge house, which has no door and so no room: owner, "since the forge does not have a door it should no have an interior") | Bed: sleep to recover (it heals today), and wake here after a defeat. Planned: a bed gives a full refill and restores life (questions 62 and 105); there are no save points, and the slime saves anywhere outside dungeons (question 62). A tub: a bath heals life but never sets where the slime wakes (built 2026-11-13; owner, 2026-11-17, question 153) | Built house; how it is given Planned; the vault waits for a later release (owner, 2026-10-16, question 53) |
| **Burr's house**, C4 | Burr's son waits inside and teaches the Roll (owner, 2026-11-17, question 150); Burr, freed from Fatty's Lair, comes home here, and later teaches the Bow. *Changed 2026-11-20 (owner): Burr thanks the slime and sends it to Pip for a bow rune; with the Bow he gives archery tips* | The house is built (2026-11-18): the blue cottage `burr-house` in C4, its door `burr-house-door` into `slimeshire-burr-house`, Burr's old gatehouse room with his armour, helmets, bow rack and hammer rack, and young Burr waiting inside (his lines are placeholders). His lesson is Planned. *Built 2026-11-20: Burr comes home here once he has talked by the bolt-hole, with his talks (his thanks and the bow rune's tip, then archery tips); the two crystal lenses of the Bow's first lock stood by the yard's dry ditch at first and moved to the lake camp's river in C5 the same day* |
| Mushroom house (the red one, near the plaza since 2026-11-20, where the Workshop stood) | A furnished room with a bed and a chest | Built (role Open) |
| **Yoi's home**, under Lili's west yard | An optional secret: Lili's tip finds it, and the slime sucks away a heap of crates to open its hatch (a heap of bricks and crates until 2026-10-16, when the bricks became crates so it no longer looks like a rubble heap: question 128). Inside are a heart quarter, Yoi's tips, and later the Spear's upgrades (owner, 2026-10-16, question 99). *Changed 2026-10-16 (seventh round, question 111): who upgrades the Spear, Yoi's techniques or the Forge, is decided after Release 1* *Changed 2026-11-17 (owner, question 151): its heart quarter is Slimeshire's fifth* *Changed 2026-11-17 (owner, question 160): the Charged Roll is found whole there* *Changed 2026-11-20 (owner): his chest holds one of the four Roll Fragments that make the Charged Roll, behind a Heavy statue maze, so it always comes after Burr's* | Built 2026-11-20: seven light crates on a hatch in C4 (south of Lili's mushroom house at first; at (169, 1313) since the owner moved it the same day); gulped away, the hatch opens for good with the secret jingle, and a stair leads down to Yoi's den (`slimeshire-yoi-home`): Yoi with four war tips, the fifth heart quarter, and a chest with a Roll Fragment (the whole Charged Roll earlier that day), behind stone dividers and two heavy statues that only pulling with the Heavy skin moves ([quests spec 14.8](../godot/specs/quests.md#148-finds-the-war-journal-the-recipe-page-and-the-charged-roll-2026-11-20)). *Until 2026-10-16 it was Yoi's Hideout, a war hideout whose water maze led to Yoi, who taught the Spear (owner, 2026-10-11; confirmed in question 50; [dungeons plan](../design/2026-10-11-release-1-dungeons-plan.md#4-yois-hideout))* |
| Forge yard (the forge was your house until 2026-11-12) | The Forge, relit in Chapter 2: Pip's story is relighting it (question 59). Planned: Pearl 2, the Matron's, relights it when it comes home, and Pip and the slime light it. From then on it brews the potions and knows their recipes (owner, 2026-10-16, questions 79 and 82), until evolutions arrive (question 51); its smelting timer leaves Release 1 with the materials. *Changed 2026-10-16 (seventh round, question 110): Pearl 2 goes home to the Wellspring, and its power lights the Forge* *Changed 2026-11-20 (owner): Pearl 3's homecoming lights it, after the Colossus; Pip keeps it with the Workshop, and the smith stays at his mine* | Built (smelting); Pearl 3's homecoming relights it (built 2026-11-20; the quest Rekindle the Forge is gone), and then it brews the Fizzy Brew, which Pip teaches |
| **The Workshop**, beside the Forge in C4's north-east corner (a ruin north of the plaza until 2026-11-20) | Rebuilt after Chapter 2. The smith comes home once the Crystal Colossus falls (question 59), and teaches the Hammer shape there in Chapter 5 or 6, after Release 1 (question 51). *Changed 2026-11-20 (owner): it is Pip's: he stands in front of it, keeping his dad's Workshop, and Pearl 2's homecoming raises it; then he carves the Bow's rune there. It has no crafting station, and the smith stays at his mine* | Built and parked; what it does in Release 1 was Open (question 51). Built 2026-11-20: the ruin beside the Forge (the owner moved it there that day; the red mushroom house took its old place north of the plaza), raised by Pearl 2's homecoming (`workshop.restored`), with Pip in front of it and his quest Pip's Workshop |
| The lake | Dora the Fishergirl (Lily until 2026-11-19) | Built |
| Worm camp, south-east | Worm Trouble. Today its worms spawn from an enemy-spawn area and come back on a timer; Planned: placed worms, each with its own wandering area ([Enemies in the world](#enemies-in-the-world-planned)) | Built |
| Fatty One Eye's camp, east | The guarded chest with the green key. *Since 2026-10-17 his camp is in his Lair, and its old clearing in D4 keeps a torn banner and the road south to the Lair's hill* | Moved into the Lair (2026-10-17) |
| **Fatty's Lair**, the worms' burrow | The old Thorn Guard gate, which a worm lever lifts and which drops shut too fast to walk through; falling slabs over holes; Burr in a cell, on the lair's main path (question 134); Fatty One Eye, Pearl 1 and his full heart (question 17); a way out that the new Heavy skin opens, its first lock (question 132); skeletons in its deep rooms (question 125) ([Chapter 1](chapters/chapter-1-the-clearing.md#fattys-lair-the-gate-the-slabs-and-burrs-cell-planned-owner-2026-10-16)). *Changed 2026-10-17: Pearl 1 lies in the lair before Fatty; taking it seals the lair's exits until he falls, the lair's second half teaches the Heavy skin, and his fight is its exam* *Changed 2026-10-17 (owner): its gate is in the face of a red-rock hill in D5 (Fatty's Hollow), reached through the old fort's field maze and over a moat's falling slabs, where the slime tries the Roll before the dungeon; its way out stays by the Verdant Gate in D4 ([Slimeshire's places](chapters/chapter-1-the-clearing.md#slimeshires-places-built-2026-10-17))* *Changed 2026-10-19 (owner): once Fatty falls the Lair caves in, as a Zelda dungeon is done for good; its mouth in D5 is buried, and its come-back secrets moved outside into Slimeshire ([the plan](../design/2026-10-19-lair-secrets-outside.md); the three rows below)* | Planned (owner, 2026-10-16): the slabs cross the void and spikes, and a slab falls a set time after it is touched (questions 70 and 71). Built 2026-10-17 ([DUNGEONS.md](../godot/DUNGEONS.md#fattys-lair-built)); one world per room since 2026-10-18; the cave-in built 2026-10-20 |
| **The sally port**, C4 | One of the Lair's come-back secrets, moved outside: an open hole in a fenced pen, with a hatch out (owner, 2026-10-19). Its planned prize is a campfire recipe | Built 2026-10-20; the recipe built 2026-11-20: its chest holds a recipe page for the Berry Basket |
| **The Glow-moss Burrow**, D4's dark-forest maze | The Lantern burns a dry trunk to open it; inside, a heart quarter, one of Slimeshire's (question 137) | Built 2026-10-20 |
| **The Old Armoury**, D4 | A level-2 hill with a hidden crack for the Goo Bomb; the Lantern opens its chest, which holds coins until its war-journal page is built | Built 2026-10-20; the page built 2026-11-20 (the war journal's first page, "The Old Gates") |
| The Verdant Gate, east | The way into Gloop Forest. *Changed 2026-11-17 (owner): a fallen tree that a Heavy Roll breaks replaces the gate, and the green key goes; what the Postern chest holds instead, and whether the place keeps its name, are question 163* *Answered 2026-11-19 (owner, question 163): the place keeps its name, its gate long gone and a grey fallen tree across its road; the Postern chest holds coins and a potion* | Built 2026-11-20: the gate object is gone, and a grey fallen tree lies across its road in D4 (`verdant-tree`, flag `level-1.verdant-tree-smashed`); only a Heavy Roll breaks it |

<a id="the-west-village"></a>

## Glimmerhill (the West village)

Glimmerhill is the West village's town, west of Slimeshire Meadow, named by the
owner on 2026-11-17 (question 149). All four of its chunks are Release 1.
*Until 2026-11-17: part of the West village joined Release 1 (owner,
2026-10-16), a small town like Kakariko
([question 73](07-decisions-archive.md#contradictions-left-after-the-review-2026-10-15)),
in B4's north and A4 (question 112).*

**Built (2026-11-01 to 2026-11-12, [VILLAGERS.md](../godot/VILLAGERS.md); not
played with the slime yet).** A hill town over A4 (West Hill), B4 (Market
Hill), A5 and B5, with 27 villagers, 47 animals and 27 rooms, one behind each
door: Dollop's shop, Burble's inn (the Bubbling Mug), Crumb's bakery, Mayor
Wobbleton's town hall, Bobbin's tailor, Auntie Suds's bathhouse, Granny
Thistle's herbalist and the family's home ([Characters](04-characters.md#the-west-village)).
Zing runs a throwing booth and Bram keeps the south gate. In the build the town
is awake, its villagers have no story lines yet (they keep waiting for Burr
after he is freed), and there is no shop system, no throwing game and nothing
to spend coins on. B4's south edge holds the prologue. *Since 2026-11-20
Dollop's shop sells for coins once Market Hill wakes
([VILLAGERS.md](../godot/VILLAGERS.md#rooms)).*

**Planned: the town wakes (owner, 2026-11-17, question 149).** Glimmerhill
starts asleep: dark and dead, its fountains dry. While a part's fountain is
dry, its villagers are in a trance, asleep on their feet, and say nothing.
Each Pearl that comes home gives the Wellspring, on B4's south edge just below
the town, the strength to fill one more fountain, and that part of town comes
to life. Pearl 1 wakes Market Hill, and each next Pearl the next part; some
parts stay shut or dead for Pearls 4 to 8: a secret underground, certain
buildings or areas. A fallen tree that only a Heavy Roll breaks blocks the way
to Market Hill, so the slime reaches the town only with the Heavy skin. A woken
fountain refills energy (question 153). *Built 2026-11-20: the Market Hill road
leaves Slimeshire's C4 at its west edge, and a grey fallen tree lies north to
south across it a little inside C4 (`market-hill-tree`, flag
`level-1.market-hill-tree-smashed`); only a Heavy Roll breaks it. The forest
path to the Wellspring stays open, and the town's ways into the Wilds (A4's
north road, B5's south gate, which Bram keeps closed) are planted shut.* Which part each next Pearl wakes, the
other ways into town and the art are question 159 (owner: "we may need to work
this a little better"). *Settled 2026-11-19 (question 159): Pearl 1 wakes
Market Hill (B4), Pearl 2 West Hill (A4) and lights Slimeshire's Forge, Pearl 3
the south gate's quarter (B5); the farms and the lake (A5) wait for Pearls 4 to
8; shader first. *Changed 2026-11-20 (owner): Pearl 2 raises Slimeshire's
Workshop instead, and Pearl 3 lights its Forge.* Built 2026-11-20: a sleeping part is greyed and darkened, its
fountain dry, its villagers frozen eyes shut with a drifting "z" (no talk), its
animals away; it wakes live when its Pearl comes home
([VILLAGERS.md](../godot/VILLAGERS.md#asleep-until-its-pearl-comes-home-2026-11-20)).
Built 2026-11-20 too: a woken fountain gives a drink that refills energy in
full, then rests a minute of play before the next; a dry one does nothing.
The secret underground is not built.*

| Place | What happens there | Status |
|---|---|---|
| **Burr's house** | Empty when the slime first comes: Burr, the gatekeeper, went to fight Fatty One Eye. His son, young Burr, teaches the Roll here ([Chapter 1](chapters/chapter-1-the-clearing.md#the-west-village-young-burrs-roll-built-2026-11-19-owner-2026-10-16)). Once freed, Burr waits here to thank the slime: he gives the Bow (question 80) when the slime comes back after Chapter 2, in Chapter 3 (owner, 2026-10-16, questions 85 and 94). *Changed 2026-10-16 (sixth round, questions 102 and 106): a visit before Pearl 2 gets his thanks and a tip ("I am making you something, come back when the forest is free"); he builds the Bow from the Matron's thread, a spool from her nest, with the other things already in his workshop, and teaches it once the slime brings the thread and Pearl 2 is home* *Since 2026-10-16 (eighth round, question 132): his yard holds the Roll's first lock, a rickety plank over a dry ditch, and later the Bow's first targets* *Changed 2026-11-17 (owner, question 150): Burr's house is in Slimeshire's C4, his son inside ([Slimeshire](#slimeshire-the-hub)); Glimmerhill's B4 gatehouse is no longer his: his room, bow rack and all, moved into the C4 house on 2026-11-18* *Changed 2026-11-20 (owner): Burr no longer teaches the Bow or takes the thread; his thanks sends the slime to Pip, who carves a bow rune* | Moved to C4 (question 150); young Burr's Roll lesson and the yard's ditch with its falling planks and chest Built 2026-11-19; Burr at home and the yard's two crystal lenses with their chest Built 2026-11-20; the lenses and their chest moved the same day to the lake camp's river in C5 (owner: C4 was overcrowded), and Pip's bow rune took Burr's lesson the same day |
| **The town** | Three or four more houses, a shop and a game to play (owner, 2026-10-16, question 73). The shop sells potions and food ingredients, so coins have a use (question 88). Which game it is, is not decided yet. *Since 2026-10-16 (seventh round, question 112): the town sits in B4's north and A4; B4's south edge is the prologue's, sealed off by forest* *Changed 2026-11-17 (owner, question 149): the town covers all four chunks. As built: Dollop runs the shop, and Zing's throwing booth is the game; neither works yet* *Built 2026-11-20: Dollop's counter sells potions, berries, crystal shards and one belt slot for coins, once Market Hill wakes* | Built in art, rooms and villagers; the shop built 2026-11-20; the game Planned |
| **A secret** | It teaches a simpler potion (owner, 2026-10-16, question 89). Where it is and which potion are not decided yet. *As built: Granny Thistle, the herbalist, hints at a secret potion; her red mushroom and mint are not items yet* | Planned |
| The rest of the village | It comes in later releases. *Changed 2026-11-17 (owner, question 149): all of Glimmerhill is Release 1; the parts left for Pearls 4 to 8 (a secret underground, certain buildings or areas) stay shut or dead until then* | Planned |

## Gloop Forest

| Place | What happens there | Status |
|---|---|---|
| Forest camp (the walled clearing at the forest's heart) | Mossy, Sunny, a workbench, and the hut with a bed | Built |
| Weaver thickets | Orb-weavers and weaver fangs. Placed orb-weavers since 2026-10-17, six in F4, E5 and F5 ([Enemies in the world](#enemies-in-the-world-planned)) | Built; the weaver fangs go (owner, 2026-10-16, question 63), though they still drop for the old quest |
| **Tom's maze** | The way to Tom, who teaches the Goo Bomb: a maze with several secrets and tests, solved with the Spear, the Roll, the Heavy skin and the Gulp. Its webs slow the slime and cannot be cut before the Silk skin (owner, 2026-10-16, question 95). Tom hangs at its end and teaches the Goo Bomb right there, as soon as he is freed (owner, 2026-10-16, question 113); his cocoon hangs by a thread with his face showing, and a cracked wall by him is the Goo Bomb's first lock, the maze's way back (questions 129 and 132) | Planned, with the owner: it lies in the forest's south-west woods, E5 (question 117). Built 2026-11-19: Tom's web hangs in a small clearing at the end of a short path off the trail there, he teaches the Goo Bomb as it tears, and a cracked rock in the ledge by his clearing opens a short way back to the trail |
| Iron hollow, south-east of the camp | Iron ore behind a gate opened by the Heavy skin standing on its plate (Planned; today a swallowed stone essence) | Built; its iron goes with harvesting (none in Release 1), and what the hollow holds instead is not decided yet. *Answered 2026-10-16 (owner, question 63): heart quarters, potions, coins or a piece of the story, such as a piece of Kiri's note (the 2026-10-11 plan's)* |
| Silk nook, north-west | A walled nook behind a web wall; it opens once the Silk skin is earned | Built; web wall Planned |
| Cracked clearing, south-west of the camp | Planned: the Goo Bomb breaks the ground (today a Squash Slam in the Stone form, and the Slam is removed; the Goo Bomb blows cracked walls, not ground yet). It drops into the Gloop Cavern, the Goo Bomb's come-back secret (owner, 2026-10-16, question 18). *As built (2026-11-14): the Goo Bomb breaks its cracked ground, but nobody teaches the Goo Bomb yet* | Built |
| **Gloop Cavern** | Today a chest, a Goo Heart and a ladder. The coffer with the 20-slot bag was Planned; Release 1 has one bag, Plop's 10-slot bag, and the 20-slot bag waits for the next release (owner, 2026-10-16, questions 53 and 74), so what the coffer holds is question 63. *Answered 2026-10-16 (owner, question 63): heart quarters, potions, coins or a piece of the story.* *Changed 2026-10-16 (eighth round, question 18): there is no Gloop Cavern in the plan, so its coffer goes too.* *Changed again 2026-10-16 (tenth round, question 18): the cave stays as a small secret, the Goo Bomb's come-back secret, holding one of Gloop Forest's four heart quarters (today's Goo Heart), with no four of its own; the coffer stays gone* | Built; its heart quarter built 2026-10-26 (`gloop-cavern`) |
| North stream | Sunny's basket and the lash bell post | Built; Stretch Lash waits for the next release, so they become come-back secrets (owner, 2026-10-16, question 94) |
| **The Matron's nest**, north-east | The boss arena; no web wall blocks the way in. Planned: after she falls, the slime takes the **Matron's thread**, a spool in her web, with the Silk skin; Burr builds the Bow from it (owner, 2026-10-16, question 106). *Changed 2026-10-16 (eighth round, question 133): the nest becomes the entrance to the **Weaver Hollow**, Chapter 2's dungeon, and the Matron lives at its top, where her thread hangs in her web* *Changed 2026-11-20 (owner): the thread is the string of Pip's bow rune* | The Weaver Hollow built 2026-10-17: a Goo Bomb blows its root gate in F4 (nobody teaches the Goo Bomb yet), and the Matron at its top drops her thread, which Pip takes for the bow rune's string (built 2026-11-20); the old nest arena is placed nowhere |
| Crystal Caverns exit, east | Planned: a maze of web walls that only the Silk skin passes leads to the caverns, so the Silk skin opens Chapter 3 (owner, 2026-10-16, question 81). Today the exit is open without a key (the crystal-key gate was removed 2026-10-10); since Gloop Forest's chunk lines were closed (2026-11-01), the web lane to the caverns is entered by a ford. *Built 2026-11-20: three web walls stand across the web lane in F4 (`web-lane`), so only the Silk skin passes* | Built: the web lane's three web walls (2026-11-20); the maze itself is designed with the owner later |
| The way in from the Wilds | A second web maze that only the Silk skin passes, so the Wilds do not skip the Verdant Gate (owner, 2026-10-16, question 87). *As built (2026-11-14): a plain opening from the South Wilds (E6 to E5); the owner closed the North Wilds' link (F3 to F4) on 2026-10-31: question 164* *Changed 2026-11-19 (owner, question 164): the Wilds are walled off in Release 1; this maze waits for the release that opens them. Built 2026-11-20: E5's trail south is planted shut* | Waits for a later release |

## Crystal Caverns

Planned in part (owner, 2026-10-16); the rest of the chapter is a
[sketch](chapters/chapter-3-crystal-caverns.md).

| Place | What happens there | Status |
|---|---|---|
| The dark maze | Dark caves that the Lantern lights | Built 2026-10-17 as the Crystal Mine's dark rooms ([DUNGEONS.md](../godot/DUNGEONS.md)); Gloomlings flee the light and attack in full dark (2026-11-13) |
| **The smith's mine camp** | The smith runs the crystal mine, which the Crystal Colossus has blocked. The slime finds him safe here, and he gives it the Lantern, the Forge's ember. He also sends the slime to Burr: the caverns' first half never needs the Bow (owner, 2026-10-16, question 134). *Since 2026-11-17 Burr lives in Slimeshire's C4 (question 150)* *Changed 2026-11-20 (owner): once the mine's gate is open he gives the slime the Smith's Crystal for his son Pip, who carves a bow rune with it, and after the Colossus falls he stays here: "the mine is mine"* | Built 2026-10-17: the smith gives the Lantern at his first talk; since 2026-11-20, once the gate is open, the Smith's Crystal (`mine-crystal`) for Pip, then reminders until the Bow and tips after it; once the Colossus falls he stays at the camp, proud of Pip. *Since 2026-11-21 the camp is his ore cave on the falling-slab maze's main road (the Spiral, roadmap 12.9): the Lantern and the crystal in one visit, his lamp freeing his one-way cart down to the mine's gate* |
| The mine's chasm | On the main path: a far eye switch across the chasm, which only the Bow's arrow reaches (owner, 2026-10-16, question 102). *Changed 2026-10-16 (eighth round, question 127): a crystal lens on a post, as an eye is always the Spear's* | Built 2026-10-17 (the lens); the Bow is built (2026-11-20): Pip carves its rune once Pearl 2 is home and the slime brings him the wood, the thread and the smith's crystal (not playtested) |
| **The Colossus's arena** | Four braziers ring it. With all four lit, a weak spot is bared on his armour at a random place; his stomps blow them out one at a time. He climbs out of reach to throw some of his minions down, and killed, they can drop energy shards. His Pearl grants the Feral skin, and Release 1's content ends when he falls. He leaves a full heart, and the slime climbs out of his arena with the new skin, its first lock (owner, 2026-10-16, questions 17 and 132). *Changed 2026-10-17: his Pearl lies in the mine before him; taking it seals the mine's exits until he falls, the mine's second half teaches the Feral skin, and his fight is its exam* | Built 2026-10-17 (M15); his fight changes with the boss pass (question 166) |
| The hill from the Wilds | A way into the caverns up a hill that only the Feral skin climbs, so it opens once Feral is won (owner, 2026-10-16, question 87). *As built (2026-11-14): a plain opening from the North Wilds (H3 to H4): question 164* *Changed 2026-11-19 (owner, question 164): the Wilds are walled off in Release 1; this climb waits for the release that opens them. Built 2026-11-20: the openings from the North Wilds (H3 to H4) and the South Wilds (H6 to H5) are planted shut with crystal groves* | Waits for a later release |

## Webs (Planned)

Built 2026-10-17 ([WEBS.md](../godot/WEBS.md)). The forest has two kinds of web (2026-10-15):

| | Webs | Web walls |
|---|---|---|
| **Without the Silk skin** | Speed −50% | Cannot pass |
| **With the Silk skin** | Full speed | Pass at −50% speed |

- The slowdown was 80% until the review of 2026-10-15; the Matron's fight is
  played with it before the number is fixed.
- The shapes cut webs only with the Silk skin (owner, 2026-10-15). A cut opens
  a web wall for good and frees things wrapped in silk (owner, 2026-10-16,
  question 55). In Release 1 the Spear, the only shape, does the cutting
  (question 94). *Changed 2026-11-17 (owner, question 146): shapes are gone;
  the Spear, an ability, cuts them.*
- No web wall blocks the way to the Matron. Her Pearl grants the Silk skin.
  *Changed 2026-10-17 (owner): her Pearl lies in the Weaver Hollow before
  her, so the slime meets her with the Silk skin; the Hollow's second half
  teaches it, and her fight is its exam.*
- A Roll sticks in a floor web; walking through one slows the slime until the
  Silk skin, and web walls block until the Silk skin (owner, 2026-10-16,
  question 131). The War Axe, in the next release, cuts webs without it
  (question 135).
- A maze of web walls on the forest's east side leads to the Crystal
  Caverns, so the Silk skin opens Chapter 3 (owner, 2026-10-16, question 81).
  *Built 2026-11-20 as three web walls across the web lane; the maze comes
  later, with the owner.*
- A second web maze, which only the Silk skin passes, leads into the forest
  from the Wilds (owner, 2026-10-16, question 87). *Changed 2026-11-19 (owner,
  question 164): it waits for the release that opens the Wilds.*
- Web walls are good places to hide secrets: they open on the way back,
  in Gloop Forest and in the maps already visited.

## Enemies in the world (Planned)

Decided by the owner on 2026-10-16; built 2026-10-17: placed enemies
(`placed-enemy.tscn` under each chunk's `Enemies`), each with its wandering
area, back each time a chunk is built again.

- Each world chunk holds a fixed number of enemies, placed by hand in the
  map. Each enemy has its own wandering area, as some camps have now.
- When the player reloads a chunk (leaves it and comes back), its enemies
  come back, as in Zelda.
- Spawn areas stay only in the playground (the bestiary pens and the
  testbed).
- Beaten bosses still never come back.

*Until 2026-10-17:* the camps of level-1 and Gloop Forest spawned from
enemy-spawn areas, each with a stay and a pursue shape, and refilled on the
area's timer up to its population. A world with no spawn areas, such as the
Crystal Caverns placeholder, spawned enemies around the player.

## Dungeons

*As built (2026-11-14): the three Release 1 dungeons are built
([DUNGEONS.md](../godot/DUNGEONS.md)). Fatty's Lair is one world per room since
2026-10-18 and caves in once Fatty falls (owner, 2026-10-19). The Weaver
Hollow's root gate needs the Goo Bomb, which nobody teaches yet. The Crystal
Mine's Chasm needs the Bow, built since 2026-11-20, which Pip's bow rune teaches once Pearl 2 is home. How each boss is hurt by
throws is question 166.* Until 2026-10-17 none were built. Chapter 1's is **Fatty's Lair**, the worms' burrow, with
its fast gate, falling slabs and Burr's cell (Planned, owner, 2026-10-16).
Chapter 2's is the **Weaver Hollow** of the
[2026-10-11 dungeons plan](../design/2026-10-11-release-1-dungeons-plan.md),
whose big chest holds a heart or the dungeon's big key instead of the War Axe
(owner, 2026-10-16, question 95). *Changed 2026-10-16 (seventh round,
question 113): it holds a heart quarter.* *Changed 2026-10-16 (eighth round,
questions 25 and 133): it is Chapter 2's dungeon, its entrance is the
Matron's old nest, and the Matron lives at its top. The skeletons in every
dungeon's deep rooms are the fallen Thorn Guard, whose bones Gorge's
vassals raised to guard the old forts (question 125).* The slime cannot save inside a
dungeon (question 62). *Since 2026-10-16 (seventh round, question 109):
quitting or fainting inside a dungeon resumes at its entrance, and the
dungeon keeps what the slime did there (small keys, opened doors, the map,
the big key); the autosave waits until the slime is out.* Each dungeon has two or three enemies of its own and a
mini-boss, which teach its tool before its boss needs it: Release 1's 29
enemies are in the [bestiary](../design/2026-10-16-bestiary.md), accepted by
the owner on 2026-10-16 (question 107).
**Proposal:** from Chapter 3 on, every region has at least one dungeon (a
cave, a castle or a maze) with three parts:

1. A first half that the slime can reach with what it already has.
2. The region's **key tool** in the middle: a shape or an ability.
3. A second half and a boss that both need that tool. The boss's Pearl then
   grants a skin.

*Changed 2026-10-17 (owner): every dungeon's Pearl lies inside it, before the
boss, as Zelda's dungeon item: a boss cannot swallow his Pearl whole, so he
hides it close to draw on its power. Taking it grants its skin; the boss
notices, enraged (his strength stays the same), and seals the exits, so the
only way out is to beat him. The second half teaches the Pearl's skin, and
the boss fight is its exam. Fainting or quitting after the Pearl resumes at
the entrance, inside, with the doors to the outside sealed until the boss
falls. The three built dungeons are reworked to match
([roadmap 12.8](../GAME_ROADMAP.md#the-2026-10-17-decisions)).*

The Crystal Caverns are a natural dungeon: a dark maze that the Lantern (an
ability, built in the rework mode) lights, given by the smith at his mine camp
(owner, 2026-10-16).

## Secrets per map (Planned)

- **Four heart quarters per map** for now, and four quarters make one heart.
  Each boss also gives a full heart (owner, 2026-10-16, question 17). Every
  Release 1 heart quarter can be reached with Release 1's powers
  (question 135). *Until 2026-10-16 it was Open whether the Gloop Cavern
  counted as its own map. It does not: it is a small secret cave holding one
  of Gloop Forest's four (owner, 2026-10-16, question 18).* *Built 2026-10-26:
  every hidden heart is a quarter. Changed 2026-11-17 (owner, question 151):
  Slimeshire holds five, D4's pen and cliff, the hill cave, the Glow-moss
  Burrow and Yoi's home.*
- **New kinds of find** (owner, 2026-11-17): besides heart quarters, Release 1
  hides the belt's four slots (each gives quick access to one kind of potion)
  and ability upgrades found whole in secret places (the Charged Roll first;
  the others are question 160), next to the manuscripts and coins, so its finds
  come in kinds that look apart, as in Metroid. *Built 2026-11-20: three belt
  slots in secret chests (Slimeshire's lookout-bell chest, Gloop Forest's iron
  hollow, the Crystal Mine's S1) and the fourth sold by Dollop.* *Built
  2026-11-20 too: the Charged Roll in Yoi's chest (with its card), the war
  journal's three pages (the Old Armoury, the Weaver Hollow's Old Cellar, the
  Crystal Mine's Prism Gallery: each opens a reading panel and is kept in the
  journal's War journal) and a recipe page in the sally port's chest.*
  *Changed 2026-11-20 (owner): the Charged Roll comes in four **Roll
  Fragments**, a kind of find of their own, and the fourth teaches it ("for
  now"): Burr's in Fatty's Lair, Yoi's chest behind a Heavy statue maze, the
  A4 barn in Glimmerhill and the Gloop Cavern's hidden chest in Gloop Forest.
  Each shows "Roll Fragment n of 4". Built the same day.*
- Some secrets should only open with powers from later chapters, such as the
  Silk skin, the Feral skin's climbing (walls with thick roots and rocky
  handholds, question 86), the Heavy skin's Roll (old dead or built things
  lying or leaning in the way: loose rocks, rubble heaps, rotten trunks
  across a path, grey leaning old trees, old fences, plank barricades,
  rotten mine timbers, question 93; the grey, leaning old tree it knocks over
  the river as a bridge, question 101), the Goo Bomb, the Lantern or later
  skins, so that going back pays off. A few optional secrets may combine a
  skin and an ability, each clearly different (owner, 2026-10-16,
  question 84). The War Axe's and Stretch Lash's locks (leafy vines, bushes,
  trees in leaf; Sunny's basket and the Lash's other uses) are come-back
  secrets for the next release (owner, 2026-10-16, question 94). The water secrets wait for the Swim skin (owner,
  2026-10-15), which comes from a later Pearl, after Release 1 (owner,
  2026-10-16, question 56): the deep-water secrets are come-back secrets
  (owner, 2026-10-16, question 75). *Since the ninth round (question 32): the
  Swim skin is Old Gullet's, and the later skins bring their own come-back
  secrets: ice and every slippery surface for the Polar skin, soft sand,
  sand walls and quicksand for the Sand skin, gaps and updrafts for the
  Cloud skin, lava and fire for the Lava skin.*
- **Bells** (Planned, owner, 2026-10-16, eighth round, question 115): a
  ranged lock across the world. A thrown pot or an arrow rings a bell; the
  Spear and the Stretch Lash never do. The first stands near the town's edge
  soon after the prologue, rung by a thrown pot (question 132), and the old
  plan's alarm bells and gongs become wooden clappers (question 127). *Since
  the tenth round the clappers are the worm army's alarms: any hit sets one
  off and calls the nearby camp, a trap, never a lock.* What a bell opens stays open for good, so a bell is a
  lock solved once (ninth round,
  [question 136](07-decisions-archive.md#open-after-the-eighth-round-2026-10-16)).
  *Until then (seventh round, question 114): Spear-only bells, a second kind
  of Spear lock that a thrown pot could not ring.*
- **Later locks** (question 135): only a few War Axe, Stretch Lash, Hammer
  and Swim locks show in Release 1, each with a line that says it needs
  something not found yet.

Chapter 1 second pass (2026-10-17): Slimeshire's south plateau has fences and north/south
stairs; the river lies on the C4/D4 seam. The larger lake has a charged-Roll island
bridge, a bomb cave, a shallow ford islet, a fishing jetty and a future Swim secret.
The three meadow hearts hide in chests, including the separate hollow-hill-cave.
