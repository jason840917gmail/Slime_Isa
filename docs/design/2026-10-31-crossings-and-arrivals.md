# Crossings and arrivals (2026-10-31)

## The owner's words

> I have animation for going down a door stairs and up stairs. I'm wondering if entry point of a
> world scene make sense anymore, because the entry point should match the door or coordinates the
> player is crossing to the other map … I don't only want animation leaving the room but arriving at
> the new scene by the door, and this has to apply to lateral doors and south doors, as well as in the
> open world. … All have to be testable on the playground.

## The rule

Every way between two places is a **crossing with two ends**. You arrive at the end paired with the
one you left by, never at a loose marker, and **arriving plays the mirror of leaving**: you come out
of the door, stairs, ladder or edge you went into on the other side. In the open world, where there
are no doors, the end is the **crossing coordinate**: you come out at the same place on the far side
of the border.

`player-spawn` stays as a fallback only (new game, F6 on a world, `?map=`, a broken link, a save
without a valid spot). It is never the target of a crossing.

## What was there (2026-10-31)

| Crossing | Count | Arrival | Arrival animation | Leaving animation |
|---|---|---|---|---|
| Door with a side (door.gd, iris) | 35 links | paired door | walks out, leaf closes | leaf opens; **openings: none** |
| Dungeon room door (scroll) | 20 | paired door | scroll, walks in | scroll, walks |
| Chunk seam (`keep_along`) | 132 | same place along the edge | scroll, walks on | scroll |
| Region border (exit → `arrive-from-*` marker) | 36 | named marker, not tied to the exit | **none (fade)** | **none (fade)** |
| Edge exit → `player-entry-<edge>` | ~48 | one marker per edge | **none (fade)** | **none (fade)** |
| Stair door (`target_marker` / `target`) | 4 | loose marker | **none (fade)** | walk in, two steps |
| Ladder (`ladder_down` / `ladder_up`) | 2 | paired door | **none** | sink / climb |
| Fall (hole, cracked floor, silk drop, well) | 4 | loose marker | **none** | spin and shrink |

231 `player-entry-*` markers sit in 68 worlds. At least one `arrive-from-*` marker that an exit names
is missing (`arrive-from-south-wilds-1` in level-1). That is the drift a one-sided link allows.

## Decisions taken while the owner was away (review them)

- **D1. One contract, no new class tree.** A crossing end is a node in the `door` group with a
  `door_id`, `arrival_point()`, `inward()`, `has_side()`, `on_arrival()` and a new
  `play_arrival(player) -> float` (the ms it holds the slime). door.gd, the stair doors and the new
  landing all answer it, so `main.gd` arrives the same way at all of them.
- **D2. Stairs pair like doors.** A stair door names the stair door it leads to (`target_door`, plus
  `target_world` when it leads into another world), in place of a marker. The stairs keep their
  black fade (the owner's choice of 2026-10-24); the arrival steps play while the black lifts.
- **D3. Arrival = leaving played backwards**, on the slime's effects channel (its picture moves, its
  body stands at the arrival spot), as the leaving does:
  - stairs leading **up** (you came down them): the slime comes down two steps out of the doorway's
    mouth, then walks out onto the floor;
  - stairs leading **down** (you came up them): it rises out of the dark, small and faint, to full
    size in the mouth, one step down, then walks out;
  - **ladder foot** (you came down): it slides down from above the foot, fading in;
  - **ladder hatch** (you came up): it rises out of the hole, small to full size;
  - **landing** (a fall, one way): it drops in from above with a squash and the landing sound
    (Zelda). A landing is a new small object, an arrival end only, in place of the fall's marker.
- **D4. Sided doors get a leaving walk.** A sided door with no lead-in (an opening) walks the slime
  into the doorway while the iris closes: north doors up into the dark, east, west and south doors
  sideways or down, fading as the wall hides it. Arriving still walks out (unchanged).
- **D5. Region borders cross by coordinates and scroll.** All overworld chunk worlds lie on the atlas
  grid (2048 units a chunk, `A1` north-west), so an edge exit into a neighbouring region arrives at the
  same global point across the border, exactly as chunk seams do. It scrolls like a chunk seam. The
  exit's `entry_marker` stays as a fallback until the cleanup. Two worlds off the grid (the
  playground and its test annex) are laid side by side by hand: their `keep_along` exits carry an
  `along_offset` (the far frame's shift along the edge). `worldNavigation.regionBorderScroll`
  (1 = coordinates and scroll, 0 = the old markers and fade) switches the region borders.
- **D6. Links are checked.** The pairing check `room_door.gd` has (`pairing_problem`) grows into a
  shared check for every crossing end: an editor warning and a red label on a broken link, and a
  headless tool, `godot/tools/check_crossings.gd`, that lists every link in every world and what is
  wrong with it.
- **D7. The old markers are not deleted yet.** Code stops needing them where a pair or a coordinate
  exists. Deleting them (and teaching the region builders not to write them) waits for the owner's
  playground verdict, then goes scene by scene, as the owner wants scene edits done.

## The playground test corner

A **crossings corner** on the playground's east side (x 5400-7900, y 6000-8800, the free ground east
of the webs corner), with a sign at each station:

1. **Four doorways**, one in each side (north, east, south, west), into a small hut world
   (`playground-crossings-hut`) with a doorway in each wall: leaving walks in, arriving walks out, on
   all four sides both ways.
2. **Stairs into another world**: a stair door down to a cellar world
   (`playground-crossings-cellar`) and its stair door back up. The same-world pair already on the
   playground (stair-door-test) pairs too.
3. **A ladder**: a ladder hatch down to the cellar's ladder foot and back.
4. **A fall**: a hole that drops the slime onto a landing in the cellar.
5. **A border crossing**: the playground's east edge at the corner leads into a small annex world
   (`playground-crossings-annex`) laid beside it on the shared frame; crossing scrolls and comes out
   at the same height, and the annex's west edge leads back.

## Built (2026-10-31, overnight; not playtested, tests not run)

1. **The arrival contract** (main.gd `_start_arrival`): every end answers `door_id`,
   `arrival_point`, `exact_arrival`, `has_side`, `inward`, `on_arrival`, `play_arrival(player,
   delay_ms) -> ms`. The arrival starts after the iris's black hold (at once under the fade) and the
   slime is held until it ends.
2. **Stair doors pair** (`stair_hatch.gd` `target_door`, `arrival_offset`; `door_id` = `hatch_id`,
   in the `door` group): the Lair's Inner Stair and the crypt's stair, the playground's pair. Their
   arrival (`stair_door.gd` `play_arrival`) is the way in backwards: two steps of
   `worldNavigation.stairArrivalStepMs` (380) and a walk of `stairArrivalWalkMs` (260), shorter than
   the way in (350 + 2 × 550), since stairs are taken back and forth. (The old markers went the same day: below.)
3. **Ladders and landings:** a ladder's foot slides the slime down onto it (with its walk out), a
   ladder's hole raises it out (door.gd `play_arrival`). `object.landing` (`landing.gd`) is the end of
   a one-way fall: drop from 320 above over 420 ms, `DropLand`, a squash. The Well Room's floor and
   the Crown's bough drop now land on landings (`roots-landing`, `weaver-hollow-silk-drop`: the old
   marker nodes became landings of the same name).
4. **The leaving walk** (door.gd `_walk_in`, `doorWalkInMs` 240): every door with a side, after a real
   door's leaf has opened. Room doors (their own `use`) are unchanged.
5. **Border crossings** (`game/world/crossings/border_crossing.gd`, world_exit.gd
   `_cross_by_coordinates`, main.gd `travel_to` `scroll_across` / `along_shift`): the chunk across the
   edge, the same place along it, a scroll. **Guard added while building:** only where the far chunk
   has an exit back at that place (`way_back_along`, read from its scene's state). The checker found
   eight region openings drawn on one side only (the wilds into level-1, gloop-forest and
   crystal-caverns); landing those by coordinates would put the slime in the far side's trees, so
   they keep their marker and fade. 19 region exits cross by coordinates.
6. **The checker** (`tools/check_crossings.gd`). Its report on 2026-10-31, besides the eight above:
   two broken links that were already there, `slimeshire-glow-moss-burrow`'s cave ladder (it keeps
   the `cave-ladder` scene's placeholder link, `unassigned / sinkhole`) and `slimeshire-sally-port`'s
   ladder (its `sally-port-way-out` is in no world); one one-way pair, `fatty-lair-bolt-hole` to
   level-1-d4's `fatty-lair-bolt-hole-mouth` (an arrival point only). No editor warnings yet (door.gd
   and the stair doors are not tool scripts).
7. **The crossings corner** (`game/dev/corners/crossings_corner.tscn`, built by
   `tools/build_crossings_lab.gd`) and `playground-crossings-hut`, `-cellar`, `-annex` (left out of
   the release Web export, as the playground's other rooms).
8. **Docs:** CONVENTIONS "Doors", WORLD_ATLAS (border crossings), DUNGEONS (the Inner Stair, the open
   hole), specs/interaction.md §3.2, specs/world.md §8, AGENTS.md (the checker).

**Not in the playground corner:** a real house door with a leaf (try level-1's houses), a dungeon
room door (the Lair, the box-room lab), a region border (try the wilds: north-wilds to the other
placeholder regions, or level-1-c4's west edge into the West village).

**What else depends on the markers** (the inventory, for the cleanup): the region builders write
them (`tools/region_worlds/region_canvas.gd`, `region_scene.gd`, `split_region_chunks.gd`,
`build_region_worlds.gd`, `build_mine_outside.gd`, `build_crystal_mine.gd`,
`weaver_hollow/hollow_floors.gd`); `WorldChunks.redirect` still sends an edge travel without a
coordinate to the chunk holding `player-entry-<edge>`; the tests travel to `player-entry-<edge>` in
about 30 places (`travel_to(world, "<edge>")`) and test_travel.gd asserts the marker order; the
world atlas draws an exit red when its target lacks the marker. **Not crossings, keep them:** the
prologue's `prologue-birth`, the dungeons' `dungeon-entrance` (respawn and resume), the dev `?room=`
`RoomEntry`, the Colossus climb-out's `exit_marker`, the mine and its camp (world exits naming
markers both ways: they could become a door pair).

## The owner's verdict (2026-10-31, morning) and the cleanup

1. Region borders: **keep the scroll.** 2. Stairs: **keep the fade.** 3. Arrival lengths are fine,
but **coming out of a stair the slime showed its back** (it faced the way it walked in): fixed,
the stair's arrival plays its walk clip facing into the room (stair_door.gd `play_arrival` calls
player.gd `walk_in`; `face` alone keeps the clip's row). 4. **Delete the old markers: done.**

- **Deleted:** every `player-entry-<edge>` (231 in 68 worlds), every `arrive-from-*`, the old stair
  arrivals (`crypt-stair-arrival`, `stair-door-arrival`, `hub-stair-arrival`, the playground's
  `up-door-arrival` / `down-door-arrival`); the fields `entry_marker` (world_exit.gd),
  `target_marker` (door.gd, cracked_floor.gd), the stair doors' `target`, `target_marker` and
  `arrival_facing`, the climb wall's `exit_marker`; the edge-marker step in
  `AreaTravel.arrival_point` and `WorldChunks.redirect`, and their entries in world-chunks.json.
- **Turned into ends:** the mine and its camp (G4's `camp-mine-mouth`, the mine's `mine-entrance`,
  H4's `lookout-from-mine`: arrival-only doors, door.gd with no target) named by the exits'
  new `target_door_id` and the climb wall's `exit_door`; a door with no `target_door_id` arrives at
  the target's `player-spawn` (the dev labs' ways back).
- **Borders drawn apart** come out of the far side's opening back (`BorderCrossing.opening_back`):
  gloop-forest's long west edge comes out at level-1's one gate. The emberleef, hot and icege
  worlds' whole-edge exits keep their place along the edge (`keep_along`).
- **Kept** (not crossings): `player-spawn`, the prologue's `prologue-birth`, the dungeons'
  `dungeon-entrance`, the rooms' `RoomEntry`, the unused `sally-port-landing` (Slimeshire's sally
  port; it became the sally port's landing the same evening, below). The dead `metadata.player.entries` in world-definitions stay.
- **Builders** (`region_canvas.gd`, `region_scene.gd`, `split_region_chunks.gd`,
  `build_region_worlds.gd`, `build_mine_outside.gd`, `build_crystal_mine.gd`,
  `weaver_hollow/hollow_floors.gd`, the dungeon and box-room labs, the watchkeeper hideout) no
  longer write markers. Tests updated: test_travel, test_dungeon_rooms, test_lair_rooms,
  test_mine_camp, test_weaver_bombs (not run). The atlas no longer judges exits by markers.
- **Rolls go through open doors** (owner, same morning): a rolling ball counts as pushing into a door
  or a stair door (player.gd `get_travel_intent`) and travels at once, instead of bonking off the
  room's edge behind the doorway.

## The other side of the eight openings (2026-10-31, evening)

The owner: "draw the other side as best as you can and send me images of the final result for the
8 one side openings. investigate what the two ladder use to link."

- **Drawn:** the six places (two openings straddle two chunks) are drawn in the hand-made chunks at
  the wilds' openings, each with its exit back, so all eight cross by coordinates both ways (the
  table in [WORLD_ATLAS.md](../godot/WORLD_ATLAS.md), "Openings on hand-made worlds"; before and
  after pictures in [border-openings/](border-openings/)). Each scene was edited on its own: only
  the painted cells' `tile_map_data`, the moved rocks and the new exit nodes changed. A path check
  (physics bodies on the slime's layers and solid ground tiles along each new way) found them clear;
  level-1 C4's cliff gap is about 190 units wide at its top (the side walls). The checker: 47 border
  crossings, no "border" left. The in-game map now draws every passage's link.
- **Two closed instead** (owner, the same evening: "c3 to c4, there is not connection there so set
  it back to what it was, also continue the river in c3"; "f3 to f4 remove it as well i dont like
  that connection neither, we can create something with the lash or a bridge to the left of the
  region later"): `level-1-c4` and `gloop-forest-f4` are back as they were (C4's cache rebaked);
  `north-wilds-c3` and `north-wilds-f3` lost their exit, their road's last stretch and their tree
  gap; both passages left `world-map.json` (a rerun of `build_region_worlds.gd` would add them
  again). Level-1's river, which stopped at the C3/C4 border, goes on north four cells wide on the
  C/D chunk line (`north-wilds-c3` and `-d3`), under a footbridge on the road (one deck per chunk,
  at the same place; the game counts the water under a deck as open), to a pond across the chunk
  line (pictures `closed-*.png`). The checker: 43 border crossings, none one-sided.
- **The ladders:** both rooms (2026-10-19, `design/2026-10-19-lair-secrets-outside.md`) were never
  linked at their outdoor end, and the burrow lost its own link the same night:
  - *Glow-moss Burrow:* its `ladder` (a `cave-ladder` instance) had `door_id` `burrow-ladder`,
    target `level-1-d4` / `burrow-way-out` when it was built (b4ca2a64); the override is gone in the
    next commit, e73ad413 (other sessions' pending work, 20 minutes later), so it falls back to the scene's
    `unassigned / sinkhole`. Outside, D4's `Chapter1/burrow-trunk` (`dry-trunk-hole`) has no ids on
    its two doors: its `Hole` (`ladder_down`) leads nowhere and its `Arrival` is not
    `burrow-way-out`. So the Burrow can be neither entered nor left.
  - *Sally port:* its ladder (`sally-port-ladder` → `level-1-c4` / `sally-port-way-out`) is right,
    but in C4 the `SallyPort/sally-port-way-out` hatch (`hatch-exit`) has an empty `door_id` (only
    its node has the name), and `SallyPort/sally-port-hole` (`open-hole`, a fall) has no target: the
    room's `sally-port-landing` is unused. So the hole does not drop in and the ladder finds no hatch.
  - **Fixed** (owner: "Fix the ladders"), one scene at a time by text: C4's hatch got `door_id`
    `sally-port-way-out`; C4's hole falls (`sally-port-hole`) onto the room's `sally-port-landing`,
    now a landing (`object.landing`) where the marker stood; the D4 trunk's `Hole` door is
    `burrow-hole`, paired with the Burrow's `burrow-ladder` (its link back restored), with an
    `arrival` child at the trunk's old `Arrival` spot, so the slime rises out of the hole and steps off
    it (the trunk's own `Arrival` door stays unused); `world-chunks.json` names `burrow-hole` for
    level-1-d4. The checker: no broken link left; the sally port is one way (the hatch slams shut
    behind the slime, as the Lair's bolt-hole does). Not played.

## Openings off the chunk corners (2026-11-01)

The owner: "c5 to c6 is wrong also it can't join 4 chunks, move to the left so it only joins c5 an
c6, make sure all connections only join 2 chunks. things like this should be avoid cause simple
walking can make the player change between 4 diferents chunks for no reason."

- **Five openings lay across a chunk corner** (two tiles in each of four chunks), all from the
  builder, which put an opening in the middle of a shared border, and regions are whole chunks:
  level-1 C5/D5 ↔ South Wilds C6/D6, North Wilds G3/H3 ↔ crystal G4/H4, North Wilds C1/C2 ↔ Ruins
  D1/D2, Ruins E1/E2 ↔ Volcano F1/F2, South Wilds D6/E6 ↔ Swamp D7/E7. Each moved into one chunk a
  side (C5/C6 as asked; the others to the side their roads already ran, so no road had to climb a
  level): the table in [WORLD_ATLAS.md](../godot/WORLD_ATLAS.md), "Off the chunk corners";
  pictures `3-*`, `4-*` and `moved-*.png` in [border-openings/](border-openings/). Edited one scene
  at a time by text: tile cells (the gap in each border band, a sand lane to the nearest road, the
  old gap planted, its stub turned back to the ground around it), the trees a Wilds chunk draws of
  its neighbour past its edge (`north-wilds-c1`/`-c2` col 32, `south-wilds-d6`/`-e6` rows 32-33),
  exits moved or deleted, and the passages in `world-map.json`. `level-1-c5` kept the owner's own
  edits since the evening (only its tree cells there and its exit changed); `level-1-d5` and
  `crystal-caverns-g4` are back as they were before the evening's drawing. A path check found each
  new lane clear and each old gap blocked; every border exit has its exit back at the same place.
- **The builder** keeps openings off chunk corners from now on (`region_plan.gd`
  `CHUNK_MARGIN_CELLS`, `_inside_one_chunk`): an opening stays a cell off its chunks' sides. Its plan
  would still differ from the hand-edited layout elsewhere (the closed passages, the Verdant Gate),
  so it is not rerun.
- **The Web-wall maze** was already inside F4/G4 (its fenced lane meets the border at F4 rows
  26-27); only its passage moved a cell up in the layout to match.
- **The Verdant Gate** (owner: "also fix connection between d4 and e4, e4 side is block by trees";
  "remove the code that does not let you pass without the key ... you can't reach the border without
  opening the gate first"): `gloop-forest-e4`'s border trees are open at rows 7-10, where D4's lane
  meets the border, and D4's `exit-1` lost its `gate` (the gate object keeps the key and the id);
  `test_travel.gd` now gives the exit a gate of its own to try `Main._pass_gate`. Not played, tests
  not run.
- **Roads along chunk lines** (owner: "fix the roads"): a scan for road tiles beside a chunk line
  inside a region, with open ground on one level across it, found ten runs of five tiles or more
  (the Desert left out: its ground is sand). Eight were roads along a line in five places (Ruins
  D1/D2 and E1/E2, South Wilds D6/E6 and G6/H6, Volcano F1/F2/G1/G2), one a straight crossing with a
  stub on the line (A6|B6), one a sand loop (F6/G6); each was moved by hand one scene at a time
  (the list in
  [WORLD_ATLAS.md](../godot/WORLD_ATLAS.md), "Roads off the chunk lines"; picture
  `border-openings/roads-off-chunk-lines.png`), and the builder's roads now pay `CHUNK_SIDE_COST`
  on a chunk's side cells. A path check found every moved road clear; the scan finds only straight
  crossings left.

## Later

- Respawn at the crossing the slime last came in by, in dungeons (Zelda).
- Stair doors in side walls (they need side-view art); south walls cannot show stairs in this view.

## Chunk lines closed by terrain (2026-11-01, Gloop Forest first)

The owner, after the roads above: "make gloop-forest more interesting, with tree maze openings etc
in the 4 chunks, the path has to be clear and visible, with 1 to 3 connections between chunks, but
never more than 2 chunks at a time and connections not wider than a road; it should be a directive
when building maps"; "the player can walk in zigzag from one chunk to another, what makes the game
experience bad"; "always try to separate most of the chunks by the terrain, mountains, water,
canals, forest etc."

- **The directive** is level design rule 11 ([2026-10-16-level-design.md](2026-10-16-level-design.md#the-rules-that-matter-most),
  spelt out in §9 and its checklist), in `AGENTS.md`'s architecture rules and in
  [WORLD_ATLAS.md](../godot/WORLD_ATLAS.md#chunk-worlds-2026-10-12). Moving roads off the lines
  (above) does not meet it on its own: open ground on both sides still lets the slime zigzag.
- **The checker:** `tools/check_chunk_lines.gd` (new) loads each chunk world alone and lists the
  crossings on every shared line. Its first full run: [chunk-lines/check-2026-11-01.txt](chunk-lines/check-2026-11-01.txt),
  73 of 112 lines flagged, every region but Gloop: the to-do list.
- **Gloop Forest** (picture [chunk-lines/gloop-forest.png](chunk-lines/gloop-forest.png)): the
  E|F stream with a footbridge, canals with a ford, forest bands with lantern-marked trail gaps,
  sand trails, two rooms with one way in; the web lane (the way to the Crystal Caverns) was not
  reachable from Gloop (the camp's east gate is filled by the blue cottage), and is entered by the
  ford now. The Crystal Caverns' west edges are closed except the lane's end, level-1 D4's top
  corner and Gloop E4's north tip too. All 12 of Gloop's lines pass; a flood-fill check reaches
  every place from each arrival. Edited by text, one scene at a time (tile cells, two footbridge
  decks, 18 lantern posts, four wall cells). Not played, tests not run; `gloop-forest-e4` and
  `level-1-d4` were open in the editor.
