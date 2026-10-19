# Fatty's Lair: every room its own world

*Status: **built 2026-10-18** (the owner approved the switch: "do the change, that's the way"); how
it works and how to edit it: [DUNGEON_ROOMS.md](../godot/DUNGEON_ROOMS.md#fattys-lair-one-world-per-room-2026-10-18).
What was built differs from this plan where marked **Built:** below; the rest of this page is the
plan as written for the review. Written read-only from
the Lair as it stands today: the shell `godot/game/scenes/worlds/fatty-lair.tscn`, its 24 room scenes
(`godot/game/scenes/worlds/rooms/fatty-lair/`), `game/fattys_lair/`, the dungeon kit
(`game/dungeon/`), the retired builder's tables (`tools/build_fattys_lair.gd`, for intent only) and
`tests/test_fattys_lair.gd`. Two headless probes that only load the room scenes and print were run
to list every node path, id and painted opening. "(unsure)" marks what was not checked in a
running game.*

## The decision (owner, 2026-10-18)

Today the Lair is **one world**: the shell lays its 24 room scenes side by side at their offsets
(`room_scene_shell.gd`), so the rooms must fit together exactly. The owner chose **the Zelda way**:

- every room is **its own world**, loaded when the slime walks in (like a house interior or a chunk);
- a room's edge door names **a target room and a door** there: no fitting of geometry;
- the change of room **scrolls the screen**, as between chunks: the old room's picture slides out
  while the next room loads behind it;
- anything that ties two rooms together becomes **a record** (DungeonState / RunState) that the
  other room reads when it is built;
- the dungeon map comes from **a layout** (which room sits in which map cell);
- **ordinary enemies come back** each time a room is entered; bosses, mini-bosses and won room
  fights (their shutters) stay beaten;
- **the seal on the Pearl's take**: no camera cut to the far entrance any more; for an instant a
  **still picture of the entrance sealing** (made in advance) shows, then the view is back in the
  slime's room;
- **the pocket rooms** (R1's store, R5's key alcove, the map nook, the sally port, R5's lower hall)
  each become **their own world with their own door** (the store's barricade is the door into the
  store's world).

**And the principle for building it** (owner): *"the more things I can do myself in the editor the
better; I don't like everything being code, because more surprises appear."* So the rooms and their
links are set up **in the editor**, never by a builder or a table in code: a door's target picked in
the Inspector, a cross-room record chosen by name on both objects, the map layout dragged in a layout
scene, live previews in the editor, **no generated scenes**. The pieces that are editor tools to
build are marked **[editor tool]** below.

## In short

- **39 links** found, in four kinds: **9 direct node links** across rooms (they break the moment the
  rooms are apart), **13 dungeon-wide services** (map, seal, entrance, resets, dev options), **12
  links that are already records** (they keep working if their record keys stay the same), and **5
  kinds of one-sided doors** (12 doors) whose far side needs a door object of its own.
- **28 openings** between rooms (23 painted doorways, the Inner Stair, Burr's cell door, three
  pocket doors) and **2 ways out** to the overworld.
- The biggest hidden risk: the kit keeps "done for good" under **the world's map id**
  (`DungeonState.object_key`: `"fatty-lair:bridge:fatty-lair-drawbridge"`). Rooms with their own map
  ids would lose every bolt, door, drawbridge, risen chest and key picked up. Fix: every room world
  keeps its records under `fatty-lair` (one setting on the Dungeon node). Old saves then still fit.
- **Surprises** (details in the sections): the map nook's crates and Fatty's clod spots are stored in
  **R10's scene** (they stand in R4 and in the arena); the Lair's director sits in the arena but
  drives Burr, the hub, the Larder and the nook; the map nook's opened gap is **not recorded at
  all**; the far-off roar's timer starts again in every world (with rooms of 20 s it would never
  sound); the quest arrow today points at Fatty from **any** room of the Lair.

---

## 1. Every cross-room link and how it becomes a record

Rooms by their scene names; cells A..E (west to east) and 2..6 (north to south) as in DUNGEONS.md.
"On build" = read when the room's world is built; "live" = both ends are in the same world after the
switch, nothing to record.

### 1a. Direct node links across rooms (they break when the rooms are apart)

| # | Rooms | What it does today | How it becomes a record | Player sees |
|---|---|---|---|---|
| 1 | hub (r3-pit-hall) → r8-guard-crypt | The Inner Stair (`Lair/inner-stair`, `stair_hatch.gd`) `target` = `../../Lair/crypt-stair-arrival`, a marker in R8's scene: walking in fades and moves the slime there. | Becomes a **travel door**: target room `r8-guard-crypt`, target door `crypt-stair-arrival` (the marker becomes the arrival door). Shut until the flag `fatty-lair.inner-stair-open` (already a flag, read on build). | Same fade (see question Q2). |
| 2 | r8-guard-crypt → hub | The crypt ladder (`Lair/crypt-stair`) `target` = `../../Lair/hub-stair-arrival` in the hub's scene. | Travel door: target room `r3-pit-hall`, door `hub-stair-arrival`. Always open. | Same. |
| 3 | arena (r13) → burr-cell + hub | `Lair/LairDirector` (in R13's scene) holds `burr` (in burr-cell), `burr_door`, `burr_exit`, `cell_door` (`hub-burr-cell-door`), `hatch` (`inner-stair`) and `call_room` (the hub's CameraRoom). Burr calls when the slime enters the hub, is freed when his door opens, winds the hatch and walks out through the hub. | The **Burr part of the director moves to the hub's world** (with Burr's cell, see Q1): all its paths are then live. Its records stay the flags it has: `fatty-lair.burr-called`, `fatty-lair.burr-freed`, `fatty-lair.inner-stair-open`. "Comes into the hub" = the hub world built (or the slime crossing the hub's room line, if the cell stays a camera room in it). | Same. |
| 4 | arena (r13) → larder (r12) | The director holds `pearl` (`pearl-1`) and `pearl_glint` (`r12-pearl-glow`): the glow goes when the Pearl is taken. | A small piece **in the Larder** (or the glow itself) reads the Pearl's flag `pearl.fatty-one-eye` on build and on `taken` (live). | Same. |
| 5 | R10's scene → arena | `Lair/clod-spots` (six spots for Fatty's mud clods) is **stored in R10's scene** at absolute positions (3744..4320, 2419..2841) that lie in the arena. The director in R13 uses it. | **Move the node into R13's scene** (by hand in the editor, or cut/paste): live. | Same. |
| 6 | R10's scene → r4-squint-den | `Objects/nook-blocked` (three crates, a sack and a `Barrier`) is **stored in R10's scene** at (1165..1242, 3552..3629), which is R4's west gap. The director opens the gap when every light thing is taken. | Move it **into R4's scene** with its own small script (the director's `_watch_blocked_gaps` part). New flag **`fatty-lair.nook-gap-open`**, set when the gap clears, read on build (the crates and barrier stay away). | **Change:** today nothing is recorded (after a quit the barrier is back, and the crates come back with the room); with the flag the gap stays open for good. |
| 7 | r10 → r9 | R10's plate (`Objects/r10-plate`, `gate_id` `fatty-lair-r9-north`, `shut_on_leave`) opens R9's north stone door (`r9-north-door`, `gate.gd`) by looking up gates with that id in the whole world, and shuts it when the statue leaves. Not saved. | A **session record** (kept for the run, not written to saves) chosen by name on both objects: R10's plate sets `fatty-lair.r10-plate-held` while a weight holds it down, clears it when released; R9's door reads it on build. When R10's world is torn down with the statue on the plate the record stays set; when R10 is built again its statue is back in the niche, so the record clears. | Plays the same (Q4 gives the alternative). |
| 8 | r5-eye-hall → r5-lower-hall | The eye latch over the inner wall (`r5-latch-inner`, in the eye hall) opens `r5-inner-door` (in the lower hall's scene) by `gate_id` `fatty-lair-r5-inner`, for good. | Already a record: the gate is opened for good in RunState (`map_id` `fatty-lair`, `gate_id` `fatty-lair-r5-inner`). The inner door becomes a **travel door pair** (eye hall side, lower hall side); both leaves read the gate record on build; the latch opens its own side's leaf live. | Same. |
| 9 | hub ↔ r1-gatehouse | The bolted shortcut: `hub-r1-shortcut` (bolt on the hub's side) and `r1-north-door` (`link_id` `fatty-lair-r1-shortcut`, `bolt_here` off) open together through the link group. | Already one record (`fatty-lair:fatty-lair-r1-shortcut`); each leaf reads it on build. The pair becomes a travel door pair. | Same. |

### 1b. Dungeon-wide services (they rely on the whole Lair being loaded)

| # | What | Today | After the switch |
|---|---|---|---|
| 10 | Heavy blocks reset with their room | The director snapshots every heavy block in the world and puts back the ones of the room the slime walks into (Dungeon `room_entered`). | **Nothing to do:** a room's world is built fresh each time it is entered, so its statues stand where the scene put them. The director's block code goes. Same for the player. |
| 11 | Enemies, pots and crates come back | `Dungeon._reset_room`: placed enemies spawned again, light things copied back, when another room is entered. | The fresh build does it (owner's decision). Won room fights (`once`) and bosses read their records on build and stay beaten (already so: `RoomFight._is_done_now`, `defeated_boss_ids`). |
| 12 | The Pearl's take seals the Lair | In R12, `pearl.gd` calls the Dungeon's `seal_now`: the record is sealed, every seal in the world shuts (R1's south, R13's north) and `seal_moment.gd` cuts the camera to R1's seal (`glimpse`) for 1.5 s. | The record is set as now (`DungeonState.seal`). Each seal reads it on build (already so). **The cut is replaced by the still picture** (owner's decision; section 2). |
| 13 | Fatty's fall breaks the seals | In R13, the Dungeon's `_watch_seal` sees him beaten, unseals the record and breaks every seal in the world. | R13's own seal breaks live; R1's reads the unsealed record when its world is built (stays down). |
| 14 | Travel out refused while sealed | `door.gd` / `DungeonState.exit_refusal`: R1's way out and the bolt-hole refuse while sealed; travel between a dungeon's own worlds goes on. | Works as is (already used by the Hollow's floors), **provided every room world has a Dungeon node** with `dungeon_id` `fatty-lair`. |
| 15 | His far-off roar | The Dungeon schedules a roar every 45..60 s, from when its world is registered. | **Would break:** each new room restarts the timer, so it would rarely sound. The next roar time moves to the session (DungeonState, not saved). |
| 16 | Dungeon map, minimap, map screen | `dungeon_map_draw.gd` draws the CameraRooms of **this world**, chest dots from chests in the tree, the boss mark from nodes in the tree (the director), seal bars from seals in the tree. | Drawn from **the layout** (section 5): rooms from the layout, visited from the record, chest dots from the layout's chests and their records, the boss's room and the seals' doors from the layout. The minimap maps the layout, not the room's world. |
| 17 | Rooms visited | Key `"<map id>/<room name>"` = `fatty-lair/r3-pit-hall`. | Key by room: keep `fatty-lair/<room name>` (the record id, see 32), so the map of an old save is kept. |
| 18 | Entrance, faint, resume | `dungeon-entrance` marker in the shell (in R1); the Dungeon is the respawn override; a quit writes the resume save at the entrance. | Every room's Dungeon node names the entrance world (`entrance_map_id` = R1's world); a faint travels there (`respawn_elsewhere`, already used by the Hollow). The marker moves into R1's scene. |
| 19 | Quest arrow ("Defeat Fatty One Eye") | `quest_waypoint.gd` points at the boss camp in the tree: inside the Lair that is R13 **from any room**. | It finds Fatty only inside R13 (Q7). D5's mouth (`boss_way_in`) still points the way in. |
| 20 | Dev options | `?room=<camera room>`, F6 on a room (`room_scene.gd` starts the whole Lair at that room), `?sealed` (takes "every Pearl of this world"), `dungeon.devPowers.fatty-lair` (by world id). | `?room=` and F6 open that room's world directly. `?sealed` works by dungeon (takes Pearl 1 by its flag, no Pearl node needed). `devPowers` looked up by dungeon id. |
| 21 | Shell-level nodes | `world-definition` (90 x 80 cells, spawn in R1), `player-spawn`, `dungeon-entrance`, the `Dungeon` node, `VoidShade` (rectangles for **all** rooms' voids, absolute), the two doors out (`fatty-lair-entrance` in R1, `fatty-lair-bolt-hole` in the bolt-hole), `room_connections` (5 signal hookups). | Each room world gets its own `world-definition`, Dungeon node and VoidShade (its own rectangles); the doors out move into R1's and the bolt-hole's scenes. The 5 `room_connections` are **already in R13's and R14's scenes** (the probe shows them): the shell's copies just go. |
| 22 | Shared layers | The shell gathers every room's `ground`, `elevation`, `walls`, `interior-walls` into one layer each; `cell_rooms` records which room painted each wall cell (a wall faces only its own room); one elevation cache `fatty-lair.res`. | Each room world uses its own layers as painted (no gathering, no `cell_rooms`). Each world gets its own elevation bake (`tools/bake_elevation.gd`, as for chunks). |

### 1c. Links that are already records (they keep working if their keys stay)

| # | Link | Record today | Note |
|---|---|---|---|
| 23 | Small keys (R5's alcove, R7) → Burr's cell door (hub) | DungeonState small-key counter; keyholes opened on `fatty-lair:fatty-lair-burr-cell` | keep the key |
| 24 | Big key (R9's hidden chest) → boss door (hub) | DungeonState item `big-key`; door `fatty-lair:fatty-lair-boss-door` | keep the key |
| 25 | The map (nook's chest) → the map screen | DungeonState item `map` | the map draws from the layout |
| 26 | Burr called / freed, the Inner Stair open, Burr outside (D4) | flags `fatty-lair.burr-called`, `.burr-freed`, `.inner-stair-open`, `.burr-outside` | unchanged |
| 27 | Pearl 1 taken (R12) → the seal, the Heavy skin | flag `pearl.fatty-one-eye`, the dungeon's seal record, SkinState | unchanged |
| 28 | Fatty beaten (R13) → seals, his heart, Burr outside | `defeated_boss_ids`, dungeon record `bosses` | unchanged |
| 29 | R1's inner winch → D5's outer gate | RunState gate `level-1-d5` / `fatty-lair-gate` | unchanged (already across two worlds) |
| 30 | Barricades (Larder north, R1's store, the Postern's bolt-hole way) | flags `fatty-lair.larder-smashed`, `.store-smashed`, `.bolt-hole-smashed` | each barricade becomes a travel door that opens when its flag is set |
| 31 | The sally port's crack (R5 ↔ sally port) | flag `fatty-lair.sally-port-open` (`cracked_wall.gd`) | `cracked_wall.gd` already has a "Door (once blown)" target: the blown hole travels to another world |
| 32 | **Kit "done for good"**: bolted doors, key doors, the drawbridge, risen chests, floor keys, won fights, winches, shutters | DungeonState `done` list, keys `"<world map id>:<kind>:<id>"` | **Key must stay `fatty-lair:...`**: a Dungeon setting `record_map_id = "fatty-lair"` used by `object_key` in every room world. Existing saves keep working. (The Hollow and the Mine keep their keys: the setting is off there.) |
| 33 | Chests' contents | RunState map record `fatty-lair` / chest `instance_id` | All Lair chests set `map_id = "fatty-lair"` except **R1's store chest**, which has no `map_id`, no `instance_id` and empty `initial_contents` in its scene today (the builder gave it 100 coins; unsure whether that was a hand edit). It needs `map_id` `fatty-lair` before the store becomes its own world. |
| 34 | Gates (latch doors, the Armoury's door, R7's gate, the Weigh House's doors, R11's drop gate) | RunState gates by explicit `map_id` `fatty-lair` | unchanged |

### 1d. One-sided doors (today one body blocks both sides; apart, the far side needs its own door)

| # | Doors | Today | After |
|---|---|---|---|
| 35 | Four bolted doors whose other side is a plain doorway in the neighbour: lower hall → R1 (`r5-way-back`), R7 → R2 (`r7-way-back`), R9 → R8 (`r9-way-back`), R11 → hub ledge (`r11-way-back`) | the door's body in the passage blocks from both sides; pushed from the back it says "Bolted from the other side." | Each gets a **partner leaf** in the neighbour's doorway (a bolted door with `bolt_here` off and `link_id` = the bolted one's `door_id`), as R1's north door already is for the hub's shortcut. One shared record per pair. |
| 36 | Three barricades: Larder north (→ Weigh House), R1's store, the Postern north (→ bolt-hole) | only from the near side; the far side is never reached before it is smashed | No partner needed: the far rooms are reached only through them. |
| 37 | Two shutters: the Larder's south (fight `fatty-lair-larder`), the arena's south (Fatty) | shut only while the slime is inside their room | No partner needed. |
| 38 | Two seals: R1 south (way out), R13 north (way to the Postern) | read the seal record | No partner needed (R14 is reached only through R13). |
| 39 | The map nook's gap (R4's west doorway) | the crates and barrier (stored in R10's scene, link 6) | R4's side only, with the new flag. |

**Checked and not cross-room** (they stay live in their room's world): the hazards' `Return` points
(all in their own rooms: the Armoury's and the Burrow's), the Larder's room fight and shutter, the
arena's shutter and the director's shutter scan (`fight_id` `fatty-lair-boss`), the Weigh House's two
plates and three doors, R7's bell and gate, the Armoury's sconces and door, R11's drop gate and lever,
R9's plate and hidden big chest, the hub's counterweight plate, drawbridge and chain, the falling
slabs, R2's landing.

---

## 2. What the switch changes or loses

| What | Today | Proposal |
|---|---|---|
| The seal's glimpse of the far entrance | the camera cuts from the Larder to R1's seal for 1.5 s; it slams up in view | **Decided:** a still picture made in advance. A capture tool renders R1's south doorway (framed clear of the HUD bar, which today hides half the seal) to a picture in `godot/asset/`; `seal_moment.gd` shows it full screen for `seal.glimpseMs`, with the boom at `glimpseSlamMs`, then the view is back in the Larder. Proposed: two pictures from the same capture, open then shut, swapped on the boom, so it still reads as slamming (Q3). The capture is redone with the tool when R1 is repainted. |
| His far-off roar | timer per world | session timer (link 15) |
| Burr's call "the first time the slime comes into the hub" | the hub's camera room in the director | the hub world's own Burr piece (link 3) |
| Statues pushed in a room | put back when the room is entered again | the same, by the fresh build |
| R10's statue holding R9's door | live across two rooms | session record (link 7) |
| The map nook's cleared gap | lost after a quit | recorded (link 6) |
| Enemies | come back when another room is entered | **Decided:** the same; bosses, mini-bosses, won fights stay beaten |
| Energy flower (the hub's ledge) | regrows 1 flower-time after it is drunk, also while the slime is elsewhere | a fresh build would show it full each time (free refills by stepping out and back): keep its regrow time in the session (Q6) |
| Falling slabs | come back 10 s after falling | the same (a fresh room has them all) |
| Seeing into the next room | the room mask darkens everything outside the current room, so little is seen; during a scroll both rooms show in the moving camera | **Decided:** the old room's picture slides out while the new one comes in, as between chunks: the same look. The dark rooms' prize glints are seen from inside the dark room's doorway (its own world) (unsure: the glint is drawn under the mask today, so it is probably not seen from R6 either). |
| The quest arrow | points at Fatty from any room | only inside R13 (Q7) |
| Fainting | wakes at the entrance in the same loaded world | travels to R1's world (as the Hollow's floors do) |
| The Inner Stair | a fade inside one world | a fade between two worlds (Q2) |
| Loading | the whole Lair once (about 2.8 s headless to load the shell with its shared art, the first time) | one room at a time. Headless, a room scene loads in 2 to 70 ms once the shared art is loaded (the first room pays for the art). The build of a room world (walls, collision, enemies) was not measured (unsure); a room is 18 x 16 cells against a chunk's 64 x 64, so it should be quicker than a chunk scroll today. The neighbours' scenes can be loaded in the background while the slime is in a room. |

---

## 3. Pocket rooms

**Decided by the owner:** the five pockets become their own worlds with their own doors. What each
needs:

| Pocket | Inside today | Its door | Work |
|---|---|---|---|
| R1's store (`r1-store`) | camera room inside R1's cell (north-east corner, 6 x 7 cells), `walls_in` R1; the chest | R1's barricade `r1-gatehouse-barricade-13-6` becomes the travel door (opens with `fatty-lair.store-smashed`) ↔ the store's south doorway | its chest needs `map_id` `fatty-lair` (link 33); its rim is partly R1's painting: paint the store's own rim |
| R5's key alcove (`r5-key-alcove`) | 6 x 5 cells under the lower hall, `walls_in` R5; small key 1 | the lower hall's `r5-alcove-door` (gate `fatty-lair-r5-alcove`, opened for good by the two latches) ↔ the alcove's north door | **no interior-walls layer of its own today**: paint its rim |
| The map nook (`map-nook`) | a full cell (A5) with a small carved room; the map chest | R4's west gap (crates, new flag) ↔ the nook's east doorway | move `nook-blocked` from R10's scene into R4's (link 6) |
| The sally port (`sally-port`) | a full cell (A6); a potion chest | R5's crack `r5-sally-crack` with its "Door (once blown)" target ↔ the sally port's east opening (painted blown, or reading the flag) | none beyond the door |
| R5's lower hall (`r5-lower-hall`) | the south 18 x 7 cells of R5's cell, L-shaped round the alcove, `walls_in` R5; two latches, the alcove door, the way back to R1 | north: the inner stone door ↔ the eye hall (gate `fatty-lair-r5-inner`, link 8); east: `r5-way-back` (bolted) ↔ R1's west doorway (partner leaf, link 35) | **no interior-walls layer of its own today**: R5's rim (painted in the eye hall's scene, 18 x 16) is cut in two, the eye hall keeps its north 9 rows; the inner wall between them is a built `walls` row in the eye hall's scene |

R5 is the most work: one painted rim and one built wall today serve the eye hall, the lower hall and
the alcove; after, three worlds each with their own rim.

**Burr's cell (`burr-cell`)** is a pocket too (`walls_in` the hub) but is not in the owner's list.
Recommended: **it stays part of the hub's world** (one more camera room in the hub's scene, or just
the hub's floor), because Burr's freeing is one live scene: his door opens in the hub, he talks, winds
the hatch in the hub and walks out across the hub. As its own world that scene would be cut in two.
Question Q1.

---

## 4. The room doors

Every opening between two rooms, from the painted `interior-walls` blocks (dungeon cells, the
block's top-left) and the door nodes. Each becomes **a travel door pair**: on each side a door with
`target_room` and `target_door` (the other side), picked in the Inspector. "Gate" is what must be done
for the passage to let the slime through.

| # | Side A (room, side, cell) | Side B | What stands there today (A / B) | Gate |
|---|---|---|---|---|
| 1 | r1-gatehouse N (44,64) | r3-pit-hall S (44,62) | `r1-north-door` bolted, no bolt / `hub-r1-shortcut` bolted | record `fatty-lair:fatty-lair-r1-shortcut` |
| 2 | r1-gatehouse E (52,75) | r2-slab-steps W (54,75) | doorway / doorway | none |
| 3 | r1-gatehouse W (36,75) | r5-lower-hall E (34,75) | doorway / `r5-way-back` bolted (in a doorway painted by the eye hall's scene) | record `fatty-lair:fatty-lair-r5-way-back`; partner leaf in R1 |
| 4 | r1-gatehouse inner (49,70) | r1-store S (50,69) | barricade / doorway | flag `fatty-lair.store-smashed` |
| 5 | r2-slab-steps N (62,64) | r3-pit-hall S (62,62) | doorway / doorway | none |
| 6 | r2-slab-steps E (70,68) | r7-bell-bridge W (72,68) | doorway / `r7-way-back` bolted | record `fatty-lair:fatty-lair-r7-way-back`; partner leaf in R2 |
| 7 | r3-pit-hall W (36,58) | r4-squint-den E (34,58) | doorway / doorway | none |
| 8 | r3-pit-hall E (70,55) | r6-pipe-gallery W (72,55) | doorway / doorway | none |
| 9 | r3-pit-hall N (44,48) | r11-drop-gate-bridge S (44,46) | doorway (the ledge) / `r11-way-back` bolted | record `fatty-lair:fatty-lair-r11-way-back`; partner leaf in the hub |
| 10 | r3-pit-hall N (62,48) | r13-fattys-arena S (62,46) | `hub-boss-door` (big key) / `r13-shutter-south` | boss door record; the shutter while Fatty fights |
| 11 | r3-pit-hall cell door (hub local 192,576) | burr-cell | `hub-burr-cell-door`, two keyholes | keyholes record; **stays inside the hub's world if Q1 says so** |
| 12 | r3-pit-hall Inner Stair (hub local 192,890) | r8-guard-crypt arrival | `inner-stair` hatch / `crypt-stair-arrival` marker | flag `fatty-lair.inner-stair-open` |
| 13 | r8-guard-crypt ladder (R8 local 224,1856) | r3-pit-hall arrival | `crypt-stair` ladder / `hub-stair-arrival` marker | none |
| 14 | r4-squint-den W (18,55) | map-nook E (16,55) | the crates and barrier / doorway | new flag `fatty-lair.nook-gap-open` |
| 15 | r4-squint-den S (26,62) | r5-eye-hall N (26,64) | doorway / doorway | none |
| 16 | r5-eye-hall W (18,69) | sally-port E (16,69) | cracked / cracked | flag `fatty-lair.sally-port-open` |
| 17 | r5-eye-hall S (inner wall) | r5-lower-hall N (lower hall local 608,0) | the latch's stone door, seen from the hall / `r5-inner-door` | gate `fatty-lair-r5-inner` |
| 18 | r5-lower-hall (local 224,128) | r5-key-alcove N | `r5-alcove-door` / the alcove's doorway | gate `fatty-lair-r5-alcove` |
| 19 | r6-pipe-gallery N (80,48) | glow-moss-burrow S (80,46) | doorway / doorway | none |
| 20 | r6-pipe-gallery S (80,62) | r7-bell-bridge N (80,64) | doorway / doorway | none |
| 21 | r8-guard-crypt W (18,39) | old-armoury E (16,39) | doorway / doorway | none |
| 22 | r8-guard-crypt W (18,23) | r9-watcher-hall E (16,23) | doorway / `r9-way-back` bolted | record `fatty-lair:fatty-lair-r9-way-back`; partner leaf in R8 |
| 23 | r8-guard-crypt E (34,44) | r11-drop-gate-bridge W (36,44) | doorway (door 3) / doorway | none |
| 24 | r9-watcher-hall N (8,16) | r10-dung-roller-run S (8,14) | `r9-north-door` stone door / doorway | session record `fatty-lair.r10-plate-held` (link 7) |
| 25 | r10-dung-roller-run E (34,9) | c2-weigh-house W (36,9) | doorway / doorway | none |
| 26 | c2-weigh-house S (47,14) | r12-larder N (47,16) | doorway / `r12-barricade` | flag `fatty-lair.larder-smashed` |
| 27 | r11-drop-gate-bridge N (48,32) | r12-larder S (48,30) | doorway / `r12-shutter-south` | the shutter while the Big Squint fights |
| 28 | r13-fattys-arena N (62,32) | r14-postern S (62,30) | `r13-seal` / doorway | the seal record |
| 29 | r14-postern N (62,16) | bolt-hole S (62,14) | `r14-barricade` / doorway | flag `fatty-lair.bolt-hole-smashed` |

**The ways out to the overworld** (already travel doors, `door.gd`; they move from the shell into the
rooms' scenes):

| Door | Room | Leads to | Today |
|---|---|---|---|
| `fatty-lair-entrance` (south, behind `r1-seal`) | r1-gatehouse (shell node at 2880, 5037) | `level-1-d5` door `fatty-lair-mouth` | refused while sealed |
| `fatty-lair-bolt-hole` (north) | bolt-hole (shell node at 4044, 172) | `level-1-d4` door `fatty-lair-bolt-hole-mouth` | the mouth is arrival-only |

D5's mouth names `target_area_id` `fatty-lair`; `world-chunks.json` and `world-map.json` name the
Lair `fatty-lair` too. Proposed: **R1's world keeps the map id `fatty-lair`**, the others are
`fatty-lair-<room>` (Q5), so the mouth, the world map, the quests and the tests' `fatty-lair` still
mean the way in.

### The room door **[editor tool]**

A `RoomDoor` node (one scene, `object.room-door`) placed in each painted opening:
- Inspector: **`target_room`** a dropdown of the dungeon's rooms (read from the layout scene,
  section 5) and **`target_door`** a dropdown of the doors in that room's scene; `side` from the wall
  it sits in; optionally **`gate_record`**, a dropdown of the record names already used in the
  dungeon (or type a new one).
- Live preview in the editor: an arrow and a label "→ r2-slab-steps / west" over the door; red when
  the target door does not exist or does not point back.
- A door kind that stands in the passage (bolted, key, boss, barricade, shutter, seal, latch door)
  stays as today; the RoomDoor's trigger lies behind it, so the slime reaches the trigger only once
  the door is open. No door code is copied.
- **A "Room links" dock [editor tool]**: lists every room door of the dungeon with its target, flags
  the ones without a partner or pointing at a door that does not point back, and every record name
  with the objects that set it and read it (so the R10 plate / R9 door pair shows as one line).
- Painting a doorway tile on `interior-walls` could place an empty RoomDoor by itself, as painting a
  closed door places its door today (owner's choice; the layer already does this for closed doors).

**Cross-room records in the editor:** the objects that set or read a record (a heavy plate, a gate, a
room door) get one Inspector field, the record name, with the same dropdown. R10's plate and R9's door
both say `fatty-lair.r10-plate-held`; nothing else ties them.

---

## 5. The map layout

The map is a **layout scene** the owner edits by dragging **[editor tool]**:
`game/scenes/worlds/rooms/fatty-lair/layout.tscn`, one `LayoutRoom` node per room on a grid of map
cells (one cell = 18 x 16 game cells, as today's rooms), each with:
- `room` (the room world, a dropdown of the dungeon's room scenes), its **cells** (dragged handles,
  snapping to quarter cells for the small pockets), an optional outline (the hub's L, R1's notch),
- marks: `boss` (Fatty's room), the seal doors (picked from the room's doors), the chests (picked
  from the room's chests, for the compass's dots).
The editor shows it as the map screen will (parchment rooms, gaps between them). The game reads the
scene (no JSON to type). The first layout is placed by hand from today's offsets:

| Room | Map cells | In cells (x, y, width, height) | Shape |
|---|---|---|---|
| r10-dung-roller-run | A2-B2 | 0, 0, 2, 1 | |
| c2-weigh-house | C2 | 2, 0, 1, 1 | |
| bolt-hole | D2 | 3, 0, 1, 1 | |
| r9-watcher-hall | A3 | 0, 1, 1, 1 | |
| r8-guard-crypt | B3-B4 | 1, 1, 1, 2 | |
| r12-larder | C3 | 2, 1, 1, 1 | |
| r14-postern | D3 | 3, 1, 1, 1 | |
| old-armoury | A4 | 0, 2, 1, 1 | dark |
| r11-drop-gate-bridge | C4 | 2, 2, 1, 1 | |
| r13-fattys-arena | D4 | 3, 2, 1, 1 | boss mark; seal north |
| glow-moss-burrow | E4 | 4, 2, 1, 1 | dark |
| map-nook | A5 | 0, 3, 1, 1 | (a small room carved in it: could be drawn smaller) |
| r4-squint-den | B5 | 1, 3, 1, 1 | |
| r3-pit-hall | C5-D5 | 2, 3, 2, 1 | L: without Burr's cell |
| burr-cell | C5 corner | 2, 3, 0.28, 0.56 | inside the hub (Q1) |
| r6-pipe-gallery | E5 | 4, 3, 1, 1 | |
| sally-port | A6 | 0, 4, 1, 1 | |
| r5-eye-hall | B6 north | 1, 4, 1, 0.56 | |
| r5-lower-hall | B6 south | 1, 4.56, 1, 0.44 | L: without the alcove |
| r5-key-alcove | B6 south-west | 1, 4.69, 0.33, 0.31 | |
| r1-gatehouse | C6 | 2, 4, 1, 1 | without the store's corner; seal south |
| r1-store | C6 north-east | 2.67, 4, 0.33, 0.44 | |
| r2-slab-steps | D6 | 3, 4, 1, 1 | |
| r7-bell-bridge | E6 | 4, 4, 1, 1 | |

E2 and E3 are empty. Chests for the compass's dots: the map nook's, R1's store's, the Armoury's, the
sally port's, R9's big chest, the Postern's green-key chest.

---

## 6. The build plan

No builder, no generated scenes: every room scene stays the owner's file, and each step is done (or
checked) in the editor.

| # | Piece | What | Kind |
|---|---|---|---|
| 1 | **Records** | `record_map_id` on the Dungeon node (keys stay `fatty-lair:...`); a session record store in DungeonState (not saved): held plates, the flower's regrow, the next far-off roar; the record name field on plates, gates and room doors. | code |
| 2 | **Room → world** | A dock button **"Make this room a world" [editor tool]** run by the owner on the open room scene: adds `world-definition` (map id, size from the room), an instance of one shared `fatty-lair-dungeon.tscn` (the Lair's Dungeon settings once: seal colour, roar, entrance world, `record_map_id`), the VoidShade with the room's own rectangles, and the line in `scene_index.json`; with the editor's undo. The room scene's `room_scene.gd` F6 then simply runs it. Then bake each world's elevation. | editor tool |
| 3 | **Room doors** | `object.room-door` with its Inspector dropdowns and preview; the Room links dock; partner leaves for the four one-sided bolts (placed by hand). | code + editor tool |
| 4 | **The scroll** | `main.gd`'s chunk scroll (`_scroll_travel`, `ChunkScroll`) taught to scroll through a door: the old room's picture laid so the two doors meet, the slime walking out of the new door; the neighbours' scenes loaded in the background. Stairs keep their fade. | code |
| 5 | **The director split** | Burr's part into the hub's scene; Fatty's part stays in R13; the Larder's glow reads the Pearl's flag; the nook's gap piece in R4 with its flag; the block reset deleted; `clod-spots` and `nook-blocked` moved out of R10's scene (by hand, cut and paste). | code + hand edits |
| 6 | **Pockets** | the store, the alcove, the lower hall, the nook, the sally port as worlds; R5's rims painted three ways (section 3); the store chest's `map_id`. | hand edits |
| 7 | **Map from the layout** | `LayoutRoom` + the layout scene with its editor drawing **[editor tool]**; `dungeon_map_draw.gd`, the minimap and the map page read it. | code + editor tool |
| 8 | **The seal's picture** | a capture tool for R1's seal (open and shut), the picture shown by `seal_moment.gd`; the far-off roar on the session timer. | code + tool |
| 9 | **Entrance, saves, dev** | entrance world on every Dungeon node; an old save resuming in "fatty-lair" lands at R1's entrance as now (R1 keeps the id, Q5); `?room=`, `?sealed`, `devPowers` by dungeon. | code |
| 10 | **Retire the Lair's shell** | the shell scene's `RoomScenes`, the gathered layers and `room_connections` go; `room_scene_shell.gd` stays for the Hollow and the Mine; the retired builder stays retired. | cleanup |
| 11 | **Tests** | `test_fattys_lair.gd` rewritten room by room (enter a room's world, walk through a door and arrive in the next; the records: R10's plate and R9's door, the latch and the lower hall's door, the shortcut's two leaves, the take in R12 then R1 built sealed, Fatty in R13 then R1 built unsealed, the nook's flag); a door-pair test (every room door's target exists and points back); a layout test (every room in it once); an old-save test (keys `fatty-lair:...` still read). `test_dungeon_rooms.gd` and `test_interior_walls.gd` lose their Lair-shell parts; `test_chapter_one_flow.gd` and `test_quests.gd` keep `fatty-lair` if Q5 is taken. | tests |
| 12 | **Docs** | DUNGEONS.md (Fatty's Lair), DUNGEON_ROOMS.md, INTERIOR_WALLS.md (`walls_in` for the Lair goes), CONVENTIONS.md (room doors), the tests' notes. | docs |

**Order:** 1 → 2 and 3 on a pilot pair (R1 and R2) → 4, so the pilot can be walked and judged by the
owner → the other rooms (2, 3, 5, 6) → 7 → 8 → 9 → 11 → 10 → 12.

**Estimate** (unsure; working sessions of a day): records 0.5; the world dock 1; room doors and the
links dock 2; the scroll through doors 1; the director split 0.5; pockets and R5's walls 1 (most of it
painting); the layout scene and map 1.5; the seal's picture 0.5; entrance, saves and dev 0.5; tests 2;
docs 0.5. **About 11 sessions**, the pilot (R1 and R2 walkable with the scroll) after about 4.

---

## Open questions for the owner

Each has a recommended answer; "all as recommended" is a complete reply.

**Built (2026-10-18), with these answers taken while the owner was away:** Q1: Burr's cell became its
own world like the other pockets (his door in the hub leads into it), and Burr himself stands in the
hub's world behind the door, so his freeing still plays as one scene in the hub. Q2: the stairs keep
their fade. Q3: two pictures. Q4: kept as is, joined by the session record. Q5: R1 keeps
`fatty-lair`. Q6: **not built**: the energy flower is full again each time its room is entered.
Q7: the arrow finds Fatty only in his arena (nothing else built). Q8: the gap stays clear for good
(`fatty-lair.nook-gap-open`). The one-sided bolts' far sides got no partner leaf: their room door
waits for the bolt's record (`requires`), which looks as before (the far door was always out of
sight behind the room mask). The pockets' walls: the lower hall, the alcove and Burr's cell got a copy
of the rim they shared. The plan's "Make this room a world" dock button was not built: the 24 rooms
were converted once by careful edits of their scenes; a new room is set up by hand (DUNGEON_ROOMS.md).
The Room links dock was not built either; the room doors check themselves in the editor (red when
wrong) and `test_lair_rooms.gd` checks every pair.

- **Q1 Burr's cell:** part of the hub's world (recommended: his freeing is one scene in the hub), or
  its own world like the other pockets?
- **Q2 The Inner Stair and the crypt ladder:** keep their fade (recommended: a stair is not a room
  edge), or scroll like the doors?
- **Q3 The seal's picture:** two pictures, open then shut with the boom (recommended), or one still of
  the shut seal?
- **Q4 R10's plate and R9's stone door:** keep them where they are, joined by a record
  (recommended: plays the same), or move the stone door to R10's south doorway so the plate and its
  door are in one room?
- **Q5 World ids:** R1 keeps `fatty-lair` and the others are `fatty-lair-<room>` (recommended: the
  way in, the world map and old saves keep working), or every room renamed?
- **Q6 The energy flower:** keeps its regrow time when the slime steps out (recommended), or is full
  again each time the room is entered?
- **Q7 The quest arrow inside the Lair:** only in Fatty's arena (recommended), or pointing at the
  door toward the arena from every room (needs the layout's paths)?
- **Q8 The map nook's gap:** once cleared it stays clear (recommended, a new flag), or it fills
  again each visit (no flag)?
