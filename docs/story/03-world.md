# World

Release 1's three regions (Chapters 1 to 3, owner, 2026-10-15), with part of
the West village and the Wilds that connect them (owner, 2026-10-16), are only
the beginning. To feel like a Zelda world,
the game needs many more regions, and inside them dungeons, castles and mazes,
each with its own boss. This page lists what exists, what is sketched, and the
empty slots still to fill.

## Regions in order

| # | Region | Maps | Chapter | What has gone wrong (story) | Boss | Status |
|---|---|---|---|---|---|---|
| 1 | **Slimeshire Meadow** | `level-1`, `slime-home`, `mushroom-home` | 1 | Worms moved in, the smith fled, the Forge is cold and the Workshop is a ruin | Fatty One Eye | Built |
| 2 | **Gloop Forest** | `gloop-forest`, `gloop-hut`; the Weaver Hollow, its dungeon (Planned); `gloop-cavern`, a small secret cave (owner, 2026-10-16, question 18) | 2 | The forest is choked with webs; the Matron's brood spreads | Orb-Weaver Matron | Built, in progress |
| 3 | **Crystal Caverns** | `crystal-caverns` (exists; open without a key for now) | 3 | Crystal grows over everything in the caves; the Colossus has blocked the smith's crystal mine | Crystal Colossus; his Pearl grants the Feral skin (owner, 2026-10-16) | In Release 1 since 2026-10-15; the chapter is a [sketch](chapters/chapter-3-crystal-caverns.md) (Idea), with Planned beats of 2026-10-16 |
| 4 | **Sticky Swamp** | `sticky-swamp` (placeholder) | ? | Slow mud, poison, rain, spider-slimes | Old Gullet, the catfish, who swallows whatever falls in and hides in deep mud and water; his Pearl grants the Swim skin (owner, 2026-10-16, question 32) | Idea; its boss and skin Planned |
| 5 | **Frostpeak** | `frostpeak` (placeholder); `icege` is a candidate | ? | Ice physics and snow | Old Rimepaw, the polar bear (a working name), who slides across the frozen lake on his belly and cracks the floes with a slam; his Pearl grants the Polar skin (question 32) | Idea; its boss and skin Planned |
| 6 | **Volcano Ridge** | `volcano-ridge` (placeholder); `hot` and `emberleef` are candidates | Finale | Gorge's prison; the rumbling comes from here | On its slopes Cinder, the magma salamander, whose Pearl grants the Lava skin, the last, which opens the way into the crater; in the crater Gorge, the ninth and final boss, with no skin (question 32) | Idea / Proposal; the bosses and the skin Planned |
| ? | **Desert** | `desert` (placeholder) | ? | Dunes walled by cliffs | Sandmaw, the great sand worm, Gorge's worm general, who burrows under the dunes and bursts out; his Pearl grants the Sand skin (question 32) | Idea; its boss and skin Planned |
| ? | **Northern ruins** | `northern-ruins` (placeholder) | ? | A ruin maze on a plateau | Gale, the storm roc, which flies over the ruin maze and blows gusts; its Pearl grants the Cloud skin (question 32) | Idea; its boss and skin Planned |

The first map of each row is the region's world scene in the layout,
`godot/game/data/world-map.json`. A placeholder world is generated from the
layout by `godot/tools/build_region_worlds.gd` and stands in until the region
is built ([WORLD_ATLAS.md](../godot/WORLD_ATLAS.md)). The layout's other
regions are open slots with placeholder worlds too: West village
(`west-village`), Northern ruins (`northern-ruins`), Desert (`desert`), and
the North and South Wilds (`north-wilds`, `south-wilds`) between the regions.
Part of the West village joins Release 1 ([below](#the-west-village)).
*Since 2026-10-16 (ninth round, question 32) every vassal region has its boss
and skin: one skin per vassal, each a new way through the world that opens
come-back secrets in the places before it. The order of the later regions,
and of their chapters, is still
[question 10](06-open-questions.md#story); the acid skin stays a spare.*

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
own.*

**Proposal: "What has gone wrong" always traces back to a Pearl.** It swelled
the boss, or it drove creatures out of their homes. This gives every region a
problem that the slime can actually fix.

**Open:** the order of regions 4 and 5, how many more regions the world needs,
and where castles and mazes fit. Zelda games have eight or more dungeons; at one
region per chapter, the world needs eight or more chapters.

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
   caves and dungeons are made of whole screens.
6. **A map's edge is a wall** (forest, cliff or water, two or three tiles
   thick), broken only where an exit leads to the next map.

| Map | Size (tiles) | Chunks | Status |
|---|---|---|---|
| `level-1` (Slimeshire Meadow) | 64 × 64 | 2 × 2 | Cut into four chunk scenes on 2026-10-14 (`level-1-c4` the village … `-d5`) |
| `gloop-forest` | 64 × 64 | 2 × 2 | Grown from 54 × 54 on 2026-10-12: its east and south strips are a tree wall (a ForestLayer), the river and the east road run on to the new edge, its camp moved 4 tiles west into chunk E4 |
| `crystal-caverns` | 64 × 64 | 2 × 2 | Grown from 54 × 54 on 2026-10-12: its east and south strips are cavern floor |
| Placeholder regions: `west-village`, `northern-ruins`, `desert`, `sticky-swamp`, `frostpeak` | 64 × 64 | 2 × 2 | Built from the sketch by `godot/tools/build_region_worlds.gd` ([WORLD_ATLAS.md](../godot/WORLD_ATLAS.md)) |
| Placeholder regions: `volcano-ridge` (L-shaped), `north-wilds`, `south-wilds` | 96 × 64, 256 × 96, 256 × 96 | their block | Only their own chunks are walkable |
| `icege`, `hot`, `emberleef` and the other dev candidates | 54 × 54 | not whole | Not on the map |
| `slime-home`, `mushroom-home`, `gloop-hut` | 14 × 11, 16 × 12, 14 × 11 | interior | Fit on one screen |
| `gloop-cavern` | 22 × 14 | interior | Two screens wide; a small secret cave, the Goo Bomb's come-back secret, holding one of Gloop Forest's heart quarters (owner, 2026-10-16, question 18) |

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

<!-- world-map:start -->
<!-- Generated by the world map tool (pnpm story:map) from godot/game/data/world-map.json. Draw on the map instead of editing this block. -->

![World map sketch](world-map.png)

The map is cut into 8 × 8 chunks, A1 in the north-west; a region's chunks are those where it holds most of the ground.

| Region | Chapter | Status | Chunks | Borders | World | Interiors | Boss | Notes |
|---|---|---|---|---|---|---|---|---|
| **Slimeshire Meadow** | 1 | Built | C4, D4, C5, D5 | North Wilds, West village (open), Gloop Forest, South Wilds | level-1 | slime-home, mushroom-home, fatty-lair | Fatty One Eye | The hub, in the middle of the world (the castle's place in the reference): the plaza ringed by water. Worms moved in, the smith left for his crystal mine, the Forge is cold until Pearl 2 comes home. The prologue (the Wellspring and the glade) lies in the south-west, between B4 and C4, and teaches the Spear; Yoi's home lies under Lili's west yard; Fatty's Lair, the worms' burrow, opens in Fatty's Hollow, a red-rock hill in D5 behind the old fort's field maze and a bridge of falling slabs; the old Thorn Guard gate there only a Roll beats. Release 1. |
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
| Yoi's home | Cave / stairs | Slimeshire Meadow → interior | Suck away the heap in Lili's west yard (optional) | Old Veteran Yoi's hideout, his home after the prologue: Lili's tip finds it; a heart quarter, his tips, later the Spear's upgrades |

**Places on the map**

| Place | Kind | Region | Chunk | Needs | Notes |
|---|---|---|---|---|---|
| Crystal Mine | Dungeon | Crystal Caverns | G4 |  | The smith's crystal mine, taken by the Crystal Colossus (built 2026-10-17): six dark rooms the Lantern teaches, the Foreman's Gate's two keyholes, the Chasm's lens for the Bow; Pearl 3 (the Feral skin) in the Den behind the Shardback, and its take seals the mine; the Feral second half (root walls to climb, the big key on a balcony), then the Colossus, enraged, in his arena of four braziers, climbing his wall; the climb out to the Lookout |
| Mine camp | Town / hub | Crystal Caverns | G4 |  | The smith runs the crystal mine; he gives the Lantern |
| The Lookout | Landmark | Crystal Caverns | H4 |  | Daylight on the mountain in H4, where the climb out of the Colossus's arena arrives; a path down to the camp |
| Desert ruin? | Note / idea | Desert (open) | A7 |  | Empty slot |
| Forest camp | Town / hub | Gloop Forest | F5 |  |  |
| Weaver Hollow | Dungeon | Gloop Forest | F4 | Goo Bomb | The Watch Oak, an old Thorn Guard watch fort inside a giant oak (built 2026-10-17): a Goo Bomb blows its root gate; four floors climbed from the Roots to the Crown; Pearl 2 (the Silk skin) in the Hoard behind the Brood Warden, and its take seals the Hollow; the Silk second half (webbed rooms, the Spinning Loft), then the Orb-Weaver Matron at the top, enraged, fighting from a cocoon a blast tears open |
| Ruin maze? | Note / idea | Northern ruins (open) | E1 |  | Empty slot: a dungeon |
| Slimeshire plaza | Town / hub | Slimeshire Meadow | C4 |  | The middle of the world |
| Your house | House / interior | Slimeshire Meadow | C4 |  |  |
| Mushroom house | House / interior | Slimeshire Meadow | D4 |  |  |
| Dora the Fishergirl | NPC | Slimeshire Meadow | C5 |  | At the water around the plaza (renamed from Lily on 2026-10-11; the game still says Lily) |
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
| **The Wellspring** | The prologue's lake, where the slime is born, between chunks B4 and C4 (owner, 2026-10-16, questions 97 and 98). After the prologue a short forest path from Slimeshire's south-west reaches it. Each Pearl's homecoming is a short scene here, and it brightens; each returned Pearl restores a building (question 60). A campfire stands by it (question 104). *Changed 2026-10-16 (seventh round): every Pearl goes home here, and its power flows into the town: the well comes back with Pearl 1, the Forge lights with Pearl 2 (question 110). It lies on B4's south edge, sealed off by forest, and its forest path leaves Slimeshire, not the West village's town (question 112)* | Built 2026-10-16 as the prologue's first screen (B4's south-west); the homecoming scenes and its campfire are Planned (until 2026-10-16: its own map east of level-1, the game's first map) |
| **The glade**, C4's south-west edge (*built in B4's south-east, against C4*) | The prologue: Yoi falls to four worms, and the slime saves him by throwing things and learns the Spear. An old Thorn Guard gate, its lever behind bars, opens into Slimeshire with a Spear thrust ([prologue](../design/2026-10-16-prologue.md)) | Built 2026-10-16 (planned by the owner the same day, question 97) |
| **Slimeshire's well** | Pearl 1 restores it when it comes home, and from then on it refills the slime's energy (owner, 2026-10-16, question 90). After Fatty, the freed Burr and the journal send the slime home, and the well comes back when the slime brings the Pearl to it (question 103); it gives a full refill, a drink in town (question 105). *Changed 2026-10-16 (seventh round): the slime takes Pearl 1 home to the Wellspring, and its power brings the well back (question 110); the well's refill grows back after a while, so it is not used up (question 113)* | Planned |
| **The town's campfire** | It makes Chapter 1's one or two recipes; campfires also stand by the Wellspring and at each camp, so a fresh save can always heal (owner, 2026-10-16, question 104). Potions and food are both crafted at a campfire (question 66) | Planned |
| Elder Plop's path | The main-line giver for Chapter 1. Planned: he hands over the 10-slot bag (question 74), and after the Spear he sends the slime to Burr in the West village (owner, 2026-10-16). *Changed 2026-10-16 (sixth round, question 100): he meets the slime at the town's edge as it comes out of the forest, gives it the bag and its first tips, with the exclamation mark, and later sends it to Burr* | Built |
| **Your house** (the red forge house, its door leading to the Slime Home) | Bed: sleep to recover (it heals today), and wake here after a defeat. Planned: a bed gives a full refill and restores life (questions 62 and 105); there are no save points, and the slime saves anywhere outside dungeons (question 62) | Built house; how it is given Planned; the vault waits for a later release (owner, 2026-10-16, question 53) |
| Mushroom house | A furnished room with a bed and a chest | Built (role Open) |
| **Yoi's home**, under Lili's west yard | An optional secret: Lili's tip finds it, and the slime sucks away a heap of crates to open its hatch (a heap of bricks and crates until 2026-10-16, when the bricks became crates so it no longer looks like a rubble heap: question 128). Inside are a heart quarter, Yoi's tips, and later the Spear's upgrades (owner, 2026-10-16, question 99). *Changed 2026-10-16 (seventh round, question 111): who upgrades the Spear, Yoi's techniques or the Forge, is decided after Release 1* | Planned. *Until 2026-10-16 it was Yoi's Hideout, a war hideout whose water maze led to Yoi, who taught the Spear (owner, 2026-10-11; confirmed in question 50; [dungeons plan](../design/2026-10-11-release-1-dungeons-plan.md#4-yois-hideout))* |
| Forge yard, beside your house | The Forge, relit in Chapter 2: Pip's story is relighting it (question 59). Planned: Pearl 2, the Matron's, relights it when it comes home, and Pip and the slime light it. From then on it brews the potions and knows their recipes (owner, 2026-10-16, questions 79 and 82), until evolutions arrive (question 51); its smelting timer leaves Release 1 with the materials. *Changed 2026-10-16 (seventh round, question 110): Pearl 2 goes home to the Wellspring, and its power lights the Forge* | Built (smelting; the quest Rekindle the Forge restores it for ore); Planned: Pearl 2 relights it (question 79) |
| Workshop ruin, north of the plaza | Rebuilt after Chapter 2. The smith comes home once the Crystal Colossus falls (question 59), and teaches the Hammer shape there in Chapter 5 or 6, after Release 1 (question 51) | Built and parked; what it does in Release 1 is Open (question 51) |
| The lake | Lily the Fishergirl | Built |
| Worm camp, south-east | Worm Trouble. Today its worms spawn from an enemy-spawn area and come back on a timer; Planned: placed worms, each with its own wandering area ([Enemies in the world](#enemies-in-the-world-planned)) | Built |
| Fatty One Eye's camp, east | The guarded chest with the green key. *Since 2026-10-17 his camp is in his Lair, and its old clearing in D4 keeps a torn banner and the road south to the Lair's hill* | Moved into the Lair (2026-10-17) |
| **Fatty's Lair**, the worms' burrow | The old Thorn Guard gate, which a worm lever lifts and which drops shut too fast to walk through; falling slabs over holes; Burr in a cell, on the lair's main path (question 134); Fatty One Eye, Pearl 1 and his full heart (question 17); a way out that the new Heavy skin opens, its first lock (question 132); skeletons in its deep rooms (question 125) ([Chapter 1](chapters/chapter-1-the-clearing.md#fattys-lair-the-gate-the-slabs-and-burrs-cell-planned-owner-2026-10-16)). *Changed 2026-10-17: Pearl 1 lies in the lair before Fatty; taking it seals the lair's exits until he falls, the lair's second half teaches the Heavy skin, and his fight is its exam* *Changed 2026-10-17 (owner): its gate is in the face of a red-rock hill in D5 (Fatty's Hollow), reached through the old fort's field maze and over a moat's falling slabs, where the slime tries the Roll before the dungeon; its way out stays by the Verdant Gate in D4 ([Slimeshire's places](chapters/chapter-1-the-clearing.md#slimeshires-places-built-2026-10-17))* | Planned (owner, 2026-10-16): the slabs cross the void and spikes, and a slab falls a set time after it is touched (questions 70 and 71). Built 2026-10-17 ([DUNGEONS.md](../godot/DUNGEONS.md#fattys-lair-built)) |
| The Verdant Gate, east | The way into Gloop Forest | Built |

## The West village

Planned in part (owner, 2026-10-16): part of the West village joins Release 1,
with more NPCs, houses and things to do, like Zelda's town. It lies west of
Slimeshire Meadow (`west-village`, a placeholder world today). Its Release 1
part is a small town, like Kakariko
([question 73](07-decisions-archive.md#contradictions-left-after-the-review-2026-10-15)).

| Place | What happens there | Status |
|---|---|---|
| **Burr's house** | Empty when the slime first comes: Burr, the gatekeeper, went to fight Fatty One Eye. His son, young Burr, teaches the Roll here ([Chapter 1](chapters/chapter-1-the-clearing.md#the-west-village-young-burrs-roll-planned-owner-2026-10-16)). Once freed, Burr waits here to thank the slime: he gives the Bow (question 80) when the slime comes back after Chapter 2, in Chapter 3 (owner, 2026-10-16, questions 85 and 94). *Changed 2026-10-16 (sixth round, questions 102 and 106): a visit before Pearl 2 gets his thanks and a tip ("I am making you something, come back when the forest is free"); he builds the Bow from the Matron's thread, a spool from her nest, with the other things already in his workshop, and teaches it once the slime brings the thread and Pearl 2 is home* *Since 2026-10-16 (eighth round, question 132): his yard holds the Roll's first lock, a rickety plank over a dry ditch, and later the Bow's first targets* | Planned |
| **The town** | Three or four more houses, a shop and a game to play (owner, 2026-10-16, question 73). The shop sells potions and food ingredients, so coins have a use (question 88). Which game it is, is not decided yet. *Since 2026-10-16 (seventh round, question 112): the town sits in B4's north and A4; B4's south edge is the prologue's, sealed off by forest* | Planned |
| **A secret** | It teaches a simpler potion (owner, 2026-10-16, question 89). Where it is and which potion are not decided yet | Planned |
| The rest of the village | It comes in later releases | Planned |

## Gloop Forest

| Place | What happens there | Status |
|---|---|---|
| Forest camp (the walled clearing at the forest's heart) | Mossy, Sunny, a workbench, and the hut with a bed | Built |
| Weaver thickets | Orb-weavers and weaver fangs. Today the orb-weavers spawn from enemy-spawn areas; Planned: placed orb-weavers ([Enemies in the world](#enemies-in-the-world-planned)) | Built; the weaver fangs go (owner, 2026-10-16, question 63) |
| **Tom's maze** | The way to Tom, who teaches the Goo Bomb: a maze with several secrets and tests, solved with the Spear, the Roll, the Heavy skin and the Gulp. Its webs slow the slime and cannot be cut before the Silk skin (owner, 2026-10-16, question 95). Tom hangs at its end and teaches the Goo Bomb right there, as soon as he is freed (owner, 2026-10-16, question 113); his cocoon hangs by a thread with his face showing, and a cracked wall by him is the Goo Bomb's first lock, the maze's way back (questions 129 and 132) | Planned; where in the forest it lies is not decided (today Tom's web hangs in the south-west spider thicket) |
| Iron hollow, south-east of the camp | Iron ore behind a gate opened by the Heavy skin standing on its plate (Planned; today a swallowed stone essence) | Built; its iron goes with harvesting (none in Release 1), and what the hollow holds instead is not decided yet. *Answered 2026-10-16 (owner, question 63): heart quarters, potions, coins or a piece of the story, such as a piece of Kiri's note (the 2026-10-11 plan's)* |
| Silk nook, north-west | A walled nook behind a web wall; it opens once the Silk skin is earned | Built; web wall Planned |
| Cracked clearing, south-west of the camp | Planned: the Goo Bomb breaks the ground (today a Squash Slam in the Stone form, and the Slam is removed; the Goo Bomb blows cracked walls, not ground yet). It drops into the Gloop Cavern, the Goo Bomb's come-back secret (owner, 2026-10-16, question 18) | Built |
| **Gloop Cavern** | Today a chest, a Goo Heart and a ladder. The coffer with the 20-slot bag was Planned; Release 1 has one bag, Plop's 10-slot bag, and the 20-slot bag waits for the next release (owner, 2026-10-16, questions 53 and 74), so what the coffer holds is question 63. *Answered 2026-10-16 (owner, question 63): heart quarters, potions, coins or a piece of the story.* *Changed 2026-10-16 (eighth round, question 18): there is no Gloop Cavern in the plan, so its coffer goes too.* *Changed again 2026-10-16 (tenth round, question 18): the cave stays as a small secret, the Goo Bomb's come-back secret, holding one of Gloop Forest's four heart quarters (today's Goo Heart), with no four of its own; the coffer stays gone* | Built; its heart quarter Planned |
| North stream | Sunny's basket and the lash bell post | Built; Stretch Lash waits for the next release, so they become come-back secrets (owner, 2026-10-16, question 94) |
| **The Matron's nest**, north-east | The boss arena; no web wall blocks the way in. Planned: after she falls, the slime takes the **Matron's thread**, a spool in her web, with the Silk skin; Burr builds the Bow from it (owner, 2026-10-16, question 106). *Changed 2026-10-16 (eighth round, question 133): the nest becomes the entrance to the **Weaver Hollow**, Chapter 2's dungeon, and the Matron lives at its top, where her thread hangs in her web* | Built (the arena); the Hollow and the thread Planned |
| Crystal Caverns exit, east | Planned: a maze of web walls that only the Silk skin passes leads to the caverns, so the Silk skin opens Chapter 3 (owner, 2026-10-16, question 81). Today the exit is open without a key (the crystal-key gate was removed 2026-10-10) | Built; the web-wall maze Planned |
| The way in from the Wilds | A second web maze that only the Silk skin passes, so the Wilds do not skip the Verdant Gate (owner, 2026-10-16, question 87) | Planned |

## Crystal Caverns

Planned in part (owner, 2026-10-16); the rest of the chapter is a
[sketch](chapters/chapter-3-crystal-caverns.md).

| Place | What happens there | Status |
|---|---|---|
| The dark maze | Dark caves that the Lantern lights | Proposal |
| **The smith's mine camp** | The smith runs the crystal mine, which the Crystal Colossus has blocked. The slime finds him safe here, and he gives it the Lantern, the Forge's ember. He also sends the slime to Burr: the caverns' first half never needs the Bow (owner, 2026-10-16, question 134) | Planned (questions 59 and 134) |
| The mine's chasm | On the main path: a far eye switch across the chasm, which only the Bow's arrow reaches (owner, 2026-10-16, question 102). *Changed 2026-10-16 (eighth round, question 127): a crystal lens on a post, as an eye is always the Spear's* | Planned |
| **The Colossus's arena** | Four braziers ring it. With all four lit, a weak spot is bared on his armour at a random place; his stomps blow them out one at a time. He climbs out of reach to throw some of his minions down, and killed, they can drop energy shards. His Pearl grants the Feral skin, and Release 1's content ends when he falls. He leaves a full heart, and the slime climbs out of his arena with the new skin, its first lock (owner, 2026-10-16, questions 17 and 132). *Changed 2026-10-17: his Pearl lies in the mine before him; taking it seals the mine's exits until he falls, the mine's second half teaches the Feral skin, and his fight is its exam* | Planned (questions 56, 58, 59 and 69) |
| The hill from the Wilds | A way into the caverns up a hill that only the Feral skin climbs, so it opens once Feral is won (owner, 2026-10-16, question 87) | Planned |

## Webs (Planned)

The forest has two kinds of web (2026-10-15):

| | Webs | Web walls |
|---|---|---|
| **Without the Silk skin** | Speed −50% | Cannot pass |
| **With the Silk skin** | Full speed | Pass at −50% speed |

- The slowdown was 80% until the review of 2026-10-15; the Matron's fight is
  played with it before the number is fixed.
- The shapes cut webs only with the Silk skin (owner, 2026-10-15). A cut opens
  a web wall for good and frees things wrapped in silk (owner, 2026-10-16,
  question 55). In Release 1 the Spear, the only shape, does the cutting
  (question 94).
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
- A second web maze, which only the Silk skin passes, leads into the forest
  from the Wilds (owner, 2026-10-16, question 87).
- Web walls are good places to hide secrets: they open on the way back,
  in Gloop Forest and in the maps already visited.

## Enemies in the world (Planned)

Decided by the owner on 2026-10-16; not built.

- Each world chunk holds a fixed number of enemies, placed by hand in the
  map. Each enemy has its own wandering area, as some camps have now.
- When the player reloads a chunk (leaves it and comes back), its enemies
  come back, as in Zelda.
- Spawn areas stay only in the playground (the bestiary pens and the
  testbed).
- Beaten bosses still never come back.

Today the camps of level-1 and Gloop Forest spawn from enemy-spawn areas,
each with a stay and a pursue shape, and refill on the area's timer up to its
population. A world with no spawn areas, such as the Crystal Caverns
placeholder, spawns enemies around the player.

## Dungeons

None are built yet. Chapter 1's is **Fatty's Lair**, the worms' burrow, with
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
  of Gloop Forest's four (owner, 2026-10-16, question 18).*
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
