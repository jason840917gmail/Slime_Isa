# The dungeon kit

> **Status:** built 2026-10-17 for the three Release 1 dungeons (Fatty's Lair, the Weaver Hollow,
> the Crystal Mine; their designs in `docs/design/2026-10-16-dungeon-*.md`). Every piece below is
> **usable**: it compiles, it is placed in the dungeon lab and its numbers are in
> `game-constants.json` `dungeon`. Code: `godot/game/dungeon/`; scenes:
> `godot/game/scenes/objects/dungeon/` (ids `object.<name>` in `scene_index.json`); tests:
> `godot/tests/test_dungeon_kit.gd`. **The seal** and the Pearl's take inside the dungeon
> ([below](#the-seal); the owner's decision of 2026-10-17, the plan
> `docs/design/2026-10-17-pearl-mid-dungeon.md`) were added the same day: tests
> `godot/tests/test_dungeon_seal.gd`.

The shared pieces a dungeon is built from: the dungeon state (no saving, resume at the entrance),
keys and locked doors, chests, the dungeon map, doors that open one way or for good, shutters and
room fights, winches and drawbridges, the void with falling slabs and spike pits, refills that grow
back, the dark rooms' shadow path and glints, the seal that the Pearl's take sets until the
boss falls, and (2026-11-23) the mechanisms a throw lets go: the knock target, the ram and the
runaway cart ([below](#mechanisms-the-knock-target-the-ram-the-runaway-cart)). Each dungeon's own pieces (its boss, its lock looks, its enemies) are built by its own
work on top of these.

## Placing pieces: the rules they share

- **Rooms are camera rooms** (`game/world/camera_room.gd`, [PROLOGUE.md](PROLOGUE.md#camera-rooms)):
  one per room, 1024 x 896 (16 x 14 cells) or bigger.
- **Walk into it to use it** (no interact key, as doors and gates: CONVENTIONS.md "Doors"): locked
  doors, bolts and winches are pushed (`game/dungeon/push_probe.gd`: the slime's body within
  `worldNavigation.gatePushReachPx` of the object's body, its movement pointing at it, for
  `worldNavigation.doorPushMs`; a winch for `dungeon.winch.turnMs`). Chests open with the interact
  key, as every chest.
- **Records:** what a piece did for good is kept by id in the dungeon's record (DungeonState
  `mark_done`, keys `"<map id>:<kind>:<id>"`, the map id being the Dungeon node's `record_map_id`
  when it has one: Fatty's Lair's rooms all keep theirs under `fatty-lair`); outside a dungeon in the map record's
  `object_states` (a winch or a drawbridge works in any world). Give every piece its id (`door_id`,
  `winch_id`, `bridge_id`, `shutter_id`, `fight_id`, `pickup_id`, a chest's `instance_id`), else
  the node's name is used: names must then be unique in the world.
- **The generic hookup** (`DungeonState.fire`): a winch's `targets`, a room fight's `reward` and
  anything connected to it set a node off through its `trigger(payload)`, else `appear`,
  `open_for_good`, `lower` or `open`; a node without one (a chest's root) passes it to its first
  child that has one. Every kit piece that something opens has `trigger`: Shutter, Drawbridge, the
  hidden chest; the game's gates (`gate.gd`) and the kit's doors answer `open_for_good`. Connect a
  bell's `rung`, a cracked post's `cracked`, a lens's hit or any signal to `trigger`.
- **Walls and doorways:** the raw kit/lab uses the painted walls below. Fatty's Lair's rooms are
  drawn by interior walls ([INTERIOR_WALLS.md](INTERIOR_WALLS.md)); so are the rebuilt Weaver Hollow's
  and Crystal Mine's (2026-11-25; their worlds before drew continuous wall courses and opening pieces
  through `doorway_art.gd`, deleted with them at step 5). A doorway two cells wide through a wall painted on
  the `elevation` layer works as the lab's do: a north-south one is a two-cell gap through the wall
  rows; an east-west one also clears the two rows above it, because the wall above hangs its face
  over them (one row a level) and the slime walks under it. A door in a wall turns with `wall`
  (north is the front view; east, south and west turn the front art, as Zelda draws side and bottom
  doors; in an east or west wall the art is foreshortened to `SIDE_DEPTH`, 0.55 of its height, so it
  stays inside a two-cell wall).

## Dungeon state: no saving, resume at the entrance

`object.dungeon` (`game/dungeon/dungeon.gd`, class `Dungeon`): one in each world of the dungeon,
with the same `dungeon_id`. Set `display_name` (the map screen's title), `entrance_marker` (the name
of a Node2D in the entrance world: its position is the slime's centre on a resume), and
`entrance_map_id` when the entrance is in another world of the dungeon.

- **No saving** (decisions archive question 109): while a world with a Dungeon node is played,
  `RunState.saving_blocked_reason()` is `"dungeon"`: Save is greyed out in the pause menu with "No
  saving in a dungeon: you will resume at its entrance", no slot can be saved, and the autosave
  waits until the slime is out.
- **Quitting resumes at the entrance:** Quit to Title and a closed window write the autosave slot
  with the run as it is and its location moved to the entrance (`DungeonState.resume_data`), so the
  title's Continue starts there with everything kept. `resume_saves` off (the dev lab) writes
  nothing, as the playground writes no autosave.
- **Fainting resumes at the entrance:** the Dungeon node is the player's respawn override
  (`player.gd` `RESPAWN_OVERRIDE_GROUP`; it wins over the last bed): the slime wakes at the marker,
  full health; in another world of the dungeon it travels there (`respawn_elsewhere`).
- **What is kept** (RunState `world["dungeons"][<id>]`, `game/dungeon/dungeon_state.gd`): small keys
  held and found, the big key, the map, the compass, the keyholes and doors opened, everything done
  for good (bolts, winches, bridges, chests risen, fights cleared, keys picked up), bosses beaten
  (also in `world.defeated_boss_ids`), the rooms visited and the entrance. Chests' contents are the
  map record's chests, as for every chest.
- **Rooms come back:** walking into another camera room brings back every beaten placed enemy
  (`EnemyPopulation.spawn_placed`: "ordinary room enemies come back when a room is entered again")
  and puts back the room's light things that were taken (pots, crates: a copy of each liftable
  standing in a room is kept when the world is built). `room_resets` turns both off. A room fight
  that is won once keeps its enemies away for good. A dungeon of one world per room (Fatty's Lair)
  gets the same by building each room afresh when it is entered.
- **Dev launch options** (once a session): `keys=<n>` (small keys), `bigkey`, `dmap` (the map and
  the compass), `room=<CameraRoom name>` (start in that room, at its `RoomEntry` child or its
  middle; a room of another world of the dungeon's layout: it travels there), with `map=<world>`:
  `?map=dungeon-lab&keys=2&room=B1`.
- **F6 on a dungeon's world** (owner, 2026-10-17): the run gets the powers the slime has by then,
  `dungeon.devPowers.<world>` in game-constants.json (Fatty's Lair and its hill outside,
  `level-1-d5`: the Spear and the Roll; the
  Weaver Hollow's floors: also the Heavy skin and the Goo Bomb; the Crystal Mine and the lab: also
  the Silk skin and the Lantern; West village B5 and its snail house: the Spear, the Roll and the
  Goo Bomb, for the house's weak wall), lent for the session in the body-shapes mode, with the autosave
  off ([CONVENTIONS.md](CONVENTIONS.md#running-a-world)). A new dungeon world gets a line there; a
  room world of a dungeon of one world per room takes its dungeon's line (`fatty-lair`).

## Keys and the map

The dungeon items (`game/dungeon/dungeon_items.gd`): **small keys** (a counter, never a bag item),
the **big key**, the **map**, the **compass**. Their icons are the 2 x 2 sheet
`godot/asset/UI/items/dungeon-items.webp`. Getting one: the ceremony (`AbilityCeremony.request_entry`)
for the big key, the map, the compass and the run's first small key; later small keys are held up
over the slime for a moment (`item_pop.gd`) with "Small Key!" and a jingle.

- **In a chest:** put `"dungeon-small-key"`, `"dungeon-big-key"`, `"dungeon-map"` or
  `"dungeon-compass"` (count 1) in a dungeon chest's contents (its root's `contents`, below).
- **On the floor:** `object.dungeon-key` (`dungeon_key_pickup.gd`): `item`, `pickup_id`. The slime
  walks over it. `DungeonKeyPickup.drop(item, at, id)` drops one at run time: an
  enemy that spits out a key it swallowed (the Weaver Hollow's Cocoon Mimic).
- **From code:** `DungeonItems.give(tree, item)`; `DungeonState.add_small_key`, `give_item`,
  `small_keys`, `has_item`, `spend_small_key`.
- **The HUD** (`dungeon_hud.gd`): beside the coin chip, the key icon and "x N", then the big key, the
  map and the compass once held, while the slime is in the dungeon.
- **The dungeon map** (`dungeon_map_draw.gd`): the rooms are the Dungeon world's camera rooms, or,
  for a dungeon of one world per room, every room of its layout (the Dungeon's `layout`: a
  DungeonLayout scene whose rooms and marks are dragged in the editor, DUNGEON_ROOMS.md). On the
  map screen (`M`; the world map window shows the dungeon's page, `dungeon_map_page.gd`, titled with
  `display_name`, keys and items on its summary line): a room the slime stood in is filled in
  parchment; with the map every other room shows dim (fog lifted); without it a room not visited is
  not drawn; the room the slime is in has a gold ring. With the map, a red mark is on the boss's
  room (a room fight with a `boss_id` not beaten, or a node in group `dungeon_map_mark` with
  `mark = "boss"`); with the compass, a gold dot on every chest not opened yet. (2026-10-26: the
  boss moved from the compass to the map; no dungeon chest holds the compass in Fatty's Lair.)
  Doors, shutters and stairs are drawn on the map from each room's scene (`scene_features`, read
  from the scene's state like the chests), each known by its script. **One mark per doorway**
  (2026-10-31, the owner: three bars stood where there is one door): every room scene holds its own
  side of a doorway (its room door on the wall's line, and maybe a door leaf, a shutter or a
  barricade in the wall's two cells), so the pieces are merged (`_doorways`): the two rooms' ways
  through (room doors, a door out with a side) within `DOORWAY_MERGE` (72) of each other on one wall
  line are one doorway, drawn between them on the wall the rooms share, and a leaf, shutter or
  barricade up to `DOORWAY_DEPTH` (160) deep in that wall belongs to it. Its mark shows the first of
  what still holds it (`_doorway_look`): the boss door (dark crimson, a gold keyhole), a small-key
  door (grey, a gold keyhole), a barricade until smashed (brown, slatted), a bolted door (grey, a
  dark bolt), a room door whose `requires` record is not set (grey, a dark bolt), a fight's shutter
  (red, last: open until its fight starts; not the seal: it has its own bar); else open (gold). A dungeon door counts until it is opened
  for good. A piece with no doorway near is a mark of its own. A stair door is an arrow up or down
  (gold). A value the
  scene leaves at its default (a north wall, an up stair) is not stored in it: it is read from the
  instanced scene, else the script's default. The room scene is the layout's `room_scene` for
  another room, or `layout_scene_of` for this world's own; a point of it lies at the room's place
  on the layout less its `camera_offset` (R5's lower hall and key alcove are not at their scene's
  origin), and a world of several rooms draws each of its features once, in the room that holds it.
  **Floors** (2026-10-26): each layout room has `floor_level` (0 the ground, 1 above, -1 below;
  `layout_room.gd`, set in `layout.tscn`; a world's own rooms read it through `floor_of_room`). The
  map page shows one tab per floor the dungeon has (`DungeonMapDraw.floors`, highest first; none
  for one floor), opening on the slime's own floor each time it opens (the slime's dot only on that
  floor's tab); the minimap shows the slime's room whatever
  its floor. Fatty's Lair: only R8 (the crypt, -1) is set so far, from the R3 stair down to it; the
  rest are on the ground, to be confirmed by the owner. The HUD minimap
  (`dungeon_minimap.gd`, under its player dot, clipped to its box) shows **the slime's room only**,
  with the seals and the map's and compass's marks inside it (`only_current`; owner, 2026-10-19: in Fatty's Lair the
  rooms around it, drawn at the minimap's scale, covered the play area); the rooms found are on the
  map screen.

## Chests

**Set a chest on its root** (owner, 2026-11-23: "a list of items on a coffer property by default,
then a list of what is left"): every chest scene (`object.chest-wooden`, `object.dungeon-chest`,
`object.dungeon-big-chest`) has `game/scripts/chest_root.gd` on its root, and the Inspector shows
the placed chest's **Contents** ({item_id: count}, what it holds at the start), **Heart Id**,
**Starts Hidden** (dungeon chests) and, under **Save record**, **Chest Id** and **Map Id** (empty:
the chest's name and the world's map). The run keeps what is left in the map's chest record
(RunState `ensure_chest` makes it from Contents the first time the chest is seen; `chest_remaining`
is what the slime has not taken), so a chest emptied in one visit stays empty. The root hands its
values to the `ChestScript` child in the game only; overrides on the child itself (the older way,
still read when the root's are empty) are lost when the chest's Editable Children is turned off,
which emptied chests until 2026-11-22. All 75 placed chests moved to their roots on 2026-11-23; the
one-shot builders in `godot/tools/` still write the child (with Editable Children on).

`object.dungeon-chest` (the wooden chest) and `object.dungeon-big-chest` (the big chest, for the big
key): `game/dungeon/dungeon_chest.gd` on the `ChestScript` child, which is the game's chest
(`chest.gd`: its record, the "Open chest" prompt, the chest window) plus:

- the dungeon items in its contents (the root's `contents`, the child's `initial_contents`) go
  straight to the dungeon when it opens; any loot beside them ("coins", potions...) opens the chest
  window as any chest;
- `hidden` (the root's `starts_hidden`): not there until set off (a room fight's `reward`, a winch target, any signal on
  `appear` or `trigger`): it rises with a puff and the secret jingle, and stays;
- `map_id` and `instance_id` may stay empty: the world's id and the chest root's name.

**No heart quarter inside a dungeon** (owner, 2026-11-23: "no quarter inside the dungeons, they are outside-world secrets"): a dungeon's chests hold keys, the map, the compass,
coins, potions, manuscripts and belt slots, and its only heart is its boss's full heart. What follows is for
the chests of the open world, its caves and its house rooms.

**A heart quarter inside** (owner, 2026-10-17: most hearts are hidden in chests; a quarter since 2026-10-26): any chest, the world's
(`game.chest`, `chest.gd`) or the dungeon's, has `heart_id` on its root (`goo_heart_id` on its `ChestScript`; empty: no
heart; a heart id unique across maps, as an `object.goo-heart`'s `heart_id`). Opening it the first
time lifts the heart out of the chest (it rises over it, `item_pop.gd`) and grants it exactly as the
pickup does (`goo_heart.gd` `grant`: the flag `goo-heart.<id>`, one heart quarter; the fourth completes
a heart, +20 max HP and health full), once; the chest shows the quarter's text ("Heart quarter 2 of 4") and asks for the ceremony once the heart has risen
(`HEART_RISE_MS`, 1.5 s of gameplay time; a load or a travel meanwhile skips them). The flag is the
chest's record: it holds something until the flag is set, and is open (empty) after, in every save.
With only the heart inside no chest window opens; with other things too (or a dungeon chest's loot
beside its dungeon items), the window shows them after the heart has risen and its ceremony has
played, as Zelda does (the window pauses the world, which would freeze the rise). The chest sends
one `open_requested` as it opens. The chests and the loose quarter are in the Scenery dock's
**Hearts & chests** category since 2026-11-18 ([PROPS.md](PROPS.md)), with a loose Roll Fragment
(`collectible-roll-fragment`) since 2026-11-20; a chest holds one as `"roll-fragment": 1` in its
contents (quests spec 14.8).

## Locked doors

`object.key-door` and `object.boss-door` (`game/dungeon/key_door.gd`, on `dungeon_door.gd`): the
dungeon door (iron-banded oak in a carved fort arch) with its padlocks, and the great door with the
sapphire lock. Stand the node in the doorway, at the middle of the two-cell gap, on the floor line of
the room its face looks into; `wall` is that room's wall; `door_id`.

- **Small-key door:** `keyholes` 1 or 2 (the padlocks show how much the lock needs). Walked into
  with a small key: one key spent, one padlock springs open and drops (`dungeon.door.keyholeMs`);
  with every keyhole open the door opens for good (the shut look rises and fades over
  `dungeon.door.openMs`). A second keyhole takes the next key while the slime keeps pushing, or
  later (the record keeps the first). Without a key: "Locked. A small key opens it." / "Two locks.
  Each wants a small key." (`locked_text` to change it). It opens from either side.
- **Boss door:** `lock = "big"`: opens with the big key, which stays held; else "A great lock. It
  wants the big key."
- Its body blocks a gap 128 (boss door 136) wide and 40 deep at the floor line.

## Doors and room logic

- **Bolted one-way door:** `object.bolted-door` (`bolted_door.gd`): the same door with a sliding
  bolt on its face. Turn it (`wall`) so the face looks into the room the bolt is on: walked into
  from there, the bolt slides back (`dungeon.bolt.slideMs`) and the door opens for good; from the
  back: "Bolted from the other side." (`locked_text`). A wing's way back.
- **Paired doors:** the two leaves of one passage between two rooms (one in each room's wall) are
  one door when they share a link: a door's link is its `link_id`, else its `door_id`, so give the
  second leaf `link_id` = the first's `door_id`. Linked doors share one record and open together:
  when one opens for good, the others open with it, and a world built again finds all of them open.
  A bolted door with `bolt_here` off has no bolt of its own (the far side of a passage whose bolt is
  on its partner): from either side it says its `locked_text` and opens with its partner. Fatty's
  Lair: R1's north door `r1-north-door` (`link_id` "fatty-lair-r1-shortcut", `bolt_here` off) is the
  hub's bolted shortcut's other leaf (`test_the_gatehouse_shortcut_opens_on_both_sides`).
- **Shutters:** `object.shutter` (`shutter.gd`): a stone block that rises out of a doorway's floor
  (`dungeon.shutter.moveMs`) and sinks back. Placed like a door (`wall`); `fight_id` ties it to a room
  fight. `starts_shut` makes it a shut door that something opens for good (`trigger`,
  `open_for_good`, recorded under `shutter_id`): the Crystal Mine's iron shutter lifted by a crank,
  a hatch.
- **Room fights:** `object.room-fight` (`room_fight.gd`, class `RoomFight`): its room is `size` from
  its position (put it on the camera room). Once the slime is `dungeon.shutter.insetPx` inside the
  room and as far from each of its shutters, while a living enemy stands in it, every shutter with
  its `fight_id` shuts. **Its enemies are whatever lives in its room now** (owner, 2026-11-21: "no
  alive enemies in the room; never count the dead enemies, because I can remove or add enemies"):
  every enemy whose centre is in its rectangle and that is not beaten, asked each step
  (`game/enemy/live_enemies.gd`, the one helper every "open once the enemies are beaten" piece
  asks), never a kill count, a stored number or a list made with the scene. Placed enemies added to
  the room or taken out of it in the editor need no wiring; one hatched or walking in during the
  fight (an egg sac's Broodlings) holds the shutters too; one the slime carries in its mouth still
  lives. With no living enemy left, after `dungeon.shutter.openDelayMs` the shutters open and
  `reward` is set off (a hidden chest, a drawbridge). A fight's shutters shut from the start
  (`starts_shut`, R4's) in a room where nothing lives open the same way once the slime is in the
  room, so an emptied room is never stuck shut; a room without them and without enemies never
  shuts. `once`: an ambush won once never runs again and the placed enemies of its room never come
  back.
  `boss_id`: a boss or mini-boss fight (once by itself): won, the boss is recorded beaten; the
  map marks its room until then, once the map is held (only the dungeon's boss when the Dungeon
  node names one). Fainting or leaving the room ends a fight unwon (the shutters
  open, the beaten enemies come back with the room). Signals `started`, `cleared`, `reset`. A
  boss camp (`boss_camp.gd`, Fatty's) keeps its own arena: connect its `boss_engaged` to each
  shutter's `shut` and its `boss_defeated` to `open` (both take the payload).
- **Winches and cranks:** `object.winch` (`winch.gd`, class `Winch`): walked into for
  `dungeon.winch.turnMs` (the crank turns, it creaks; letting go starts again), it sets off every
  node in `targets` (NodePaths) and stays turned (`winch_id`). `done_text`: a line when walked into
  again.
- **Drawbridge:** `object.drawbridge` (`drawbridge.gd`, class `Drawbridge`): the node stands at the
  hinge, the middle of the bridge's end on the far rim; it lowers `toward` (south: down the screen)
  over `length` cells, `width` wide. Raised it stands upright there; `trigger()` (or `lower()`)
  brings it down for good (`dungeon.drawbridge.lowerMs`, a thud and a shake), its record
  (`bridge_id`) keeps it down. Lowered it is a deck over the void (below) and opens its passage over
  the elevation hole. `starts_lowered` for a bridge that is simply there.

## The void, slabs and spikes

One hazard script for the void, spikes and lava (question 70; roadmap 5.14):

- **Paint the void as a hole** on the world's `elevation` layer (question 70: the void works like
  the elevation's holes: the rim holds the slime, a push drops it in) and lay an `object.hazard`
  (`hazard.gd`, class `Hazard`) over the hole: its rectangle `size` from its position, `kind`
  "void", `rim_level` the level of the ground around it (0). In a world without elevation the
  hazard is flat floor. It draws its look (`draw_look`): the void a black abyss whose top
  `top_fade_px` fades in (set it to the hole's far wall, 64 a level, so the wall sinks into the dark),
  spikes and lava on the pit's floor below that line. Keep a hazard above its decks in the tree (they
  draw over it at the same depth). Over painted elevation the hazard follows the paint (2026-10-19):
  its floor is the lowest level painted under it (or a pit's `level` when set), its rim the lowest
  painted level above that floor next to it, and a void or water catches only on the cells painted
  below the rim, so an islet painted at rim level inside its rectangle is ground and never catches;
  settings that disagree with the paint are ignored, with one warning.
- **The slime is in a hazard** when its feet are on a cell the hazard covers (above) and no deck
  holds them, or when it walks on a lower level than the rim (it dropped into the hole). `HazardWatch` (`hazard_watch.gd`, made
  by the world's first hazard or deck) watches it every step (not while it flies, is on stairs or
  is dead).
- **Void:** the slime spins and shrinks away (`dungeon.void.fallMs`, the `FallDown` cue), then is put
  back on the rim it fell from and loses `dungeon.void.damage` (true damage; `damage` per hazard): the
  last safe ground it stood on (its body clear of every hazard and every slab, or its feet on a safe
  deck: never half on the bridge, touching a slab that would give again), or, when the hazard has
  return points (`return_points`, else its children named `Return...`), the one nearest to that
  ground: the bridge's start, a path's mouth. A fall that faints it wakes it at the entrance. A pit
  fall with no pit floor within reach below (a bridge over a hole with no room to land) puts the
  slime back on the rim as from the void. With `fixed_return` (a NodePath to any Node2D, shared by several hazards if wanted) every fall from the hazard returns to that one spot instead, wherever the slime fell (2026-10-18, owner: one known safe spot so a fall never misplaces it or leaves it stuck; D5's two moat holes use `Chapter1Hazards/moat-safe-spot`).
- **Spikes / lava** (`kind` "spikes" or "lava"): a sunken pit (a hole `pit_depth` levels deep with a
  flight of stairs out). In it the slime is hurt (`dungeon.spikes.damage`, `lava.damage`) each time
  its invulnerability ends (the Roll's i-frames pass), until it walks out by the stair. A slab gone
  from under it drops it into the pit first (`dungeon.spikes.fallMs`).
- **Levels** (2026-10-18, the owner's R7): one hazard per floor level; it hurts only on its level.
  A spikes or lava hazard's floor (its `level` when set, else the lowest level painted under it; over
  painted elevation `pit_depth` and `rim_level` come from the paint) is the floor it covers: it
  catches the slime only on the cells the `elevation` layer paints at that level (`Hazard.covers`),
  draws its look only there, under the upper floors' walls (INTERIOR_WALLS.md "Pits and holes"), and
  ignores a slime above its rim (a bridge, a higher floor) inside its rectangle. The rest of the kit
  reacts only at its own level: a deck (slab, landing) is touched only by a slime on its
  `deck_level`, so walking the channel under a bridge never cracks it; a key pickup, an energy flower
  and a heavy plate react only to a slime on the level under them (`DungeonState.on_level_of`: the
  object's `level` property when set, else the elevation under it). A deck opens the cells it covers
  (place it on whole cells: R7's north slabs were 3 to 5 units off and opened a column and a row
  more; they were put back on their cells, 2026-10-19). Not level-aware yet: pots
  and other liftables, the bell's lash, switches, enemies. An object standing on a deck that holds
  takes the deck's level (`deck_level`; a key on a slab over a pit is reached from the slab, not the
  pit), else the walkable level under it (2026-10-19).
- **Hazards never block movement:** a hazard and its watch have no collision; the slime walks in and
  is then caught. The decks hold it by the watch and the passages they open in the elevation. A
  deck's passage is open only while the deck holds (2026-10-19, owner: "when the slab is missing the
  player does not fall as normal"): when a slab falls the watch closes its passage, so the floor's rim
  is back across the gap and holds the slime with the outdoor ledge drop; when the slab rises the
  passage opens again (`HazardWatch._sync_passages`, `Elevation.close_passage`). It waits to close
  until the slime's body on the deck's level is clear of the deck by a quarter cell, so the rim never
  traps it; a slime on the slab as it falls is caught by the hazard as before.
- **Decks** hold the slime over a hazard (group `hazard_deck`, `hazard_deck.gd`, class
  `HazardDeck`): `object.hazard-deck` is a landing (a flagstone, `draw_floor`; turn it off for an
  islet that is just ground), `size` from its position, `level` (the rim's), `safe`. Over an
  elevation hole every deck opens a passage at its level when the world is built (merged into as
  few rectangles as its cells allow, `Elevation.open_passage`), so the slime walks onto it from the
  rim.
- **Falling slabs:** `object.falling-slab` (`falling_slab.gd`, class `FallingSlab`; questions 70,
  71): a loose cracked flagstone, `size` (64 x 64 for one cell; the lab's are 128 x 64, two cells
  wide). Touched by the slime's body it cracks and shakes, and falls `dungeon.slab.fallDelayMs`
  (300 ms; `fall_delay_ms` for one) later; its spot is the hazard then. It comes back
  `dungeon.slab.returnMs` (10 s) after it fell. Not safe ground (a fall goes back to the rim).

  **The timing:** the slime stands where the middle of its body is (its 30 x 26 collision box's
  centre, 13 units above its feet; `hazard_watch.gd`): it falls when that point is over a fallen
  slab, and a standing slab holds it only while that point is on it (2026-10-19: by the feet, the
  front of the body walking south, a walker on a bridge of slabs reached the next slab 4 units
  before the one behind fell, and sometimes crossed). From a slab's first touch the middle of the
  body walks 77 to 79 units to the next slab or the far rim, whichever way it goes: 385 ms or more
  at walking speed (200 units/s), so a slab always falls under a walker; a Roll crosses one in under 270 ms (the
  classic Roll launches at 460 units/s; the rework's quick Roll covers 165 units in 330 ms, ending
  at 333 units/s). The slime cannot wait on a slab between two Rolls (the Roll's cooldown is longer
  than the delay), so **a bridge longer than one Roll needs a solid landing where each Roll ends**
  (a HazardDeck, as Fatty's Lair's R7 has): one quick Roll from the rim's edge crosses two slabs
  (128 + the body's 26 units = 154 of its 165), and holding the way on after the Roll walks the
  last few units off. On a landing the slime walks to its far edge, then Rolls on (from the middle
  of a one-cell landing a quick Roll falls short of the far rim by about 20 units); the classic
  Roll (about 185 units) has room to spare. The charged (held) Roll crosses any bridge. (These Roll
  figures were measured with the feet rule; with the middle of the body a Roll going east or west is
  the same, one going south needs 13 units more and one going north 13 less. R7's Roll tests in
  `test_fattys_lair.gd` check the west slabs.)

### Falling planks over water

The slabs' twin over deep water (owner, 2026-10-17: Slimeshire's lake, a falling bridge to an island):

- **`object.falling-plank`** (`falling_plank.gd`, class `FallingPlank`, on `falling_slab.gd`): a
  loose, cracked plank, `size` 64 x 64 (one cell; lay one per cell). The slab's states and numbers
  (`dungeon.slab.fallDelayMs` 300, `returnMs` 10 s, `riseMs`, `shakePx`): touched it creaks
  (`GroundCreak`) and shakes, then drops into the water with a splash (`WaterSplash` cue, rings:
  `water_splash.gd`) and sinks over `dungeon.plank.sinkMs`. `east_west` turns the boards for a bridge
  that runs east-west.
- **`object.plank-landing`** (`plank_landing.gd`, class `PlankLanding`, a HazardDeck): the whole,
  nailed plank that never falls; safe ground where a Roll may end, as a slab bridge's landing.
- **The water hazard:** an `object.hazard` with `kind` "water" over the bridge's lane only (the cells
  under its planks, not the banks: the slime is in it when its feet are inside and no plank holds
  them). It draws nothing (the water shows). Fallen in, the slime sinks with a splash
  (`dungeon.water.fallMs`), loses `dungeon.water.damage` (10) and is put back on its bank: the
  hazard's `Return...` children (put one on each bank: the nearest to the slime's last safe ground
  wins), else that ground. A form that swims (the Frog) never falls in; enemies never walk in (one knocked in by a blow
  drowns: [THROW_COMBAT.md](THROW_COMBAT.md#knocked-enemies-and-the-ground-2026-11-16)).
- **The lane:** every plank and landing opens the deep water's collision under its cells when the
  world is built (`plank_look.gd` adds a `bridge_deck.gd` child, docs/godot/specs/water.md §10), and
  the cells stay open after a plank falls, so the slime over a fallen plank is caught by the hazard,
  never held or pushed by the water. The lane is one cell wide; deep water on both sides keeps the
  slime on it. Monsters and NPCs never step onto a plank bridge (the owner, 2026-10-31: "monster
  should not walk on water"; an archer had followed the slime over a lane whose planks had fallen):
  each piece also lays a wall over its cell on the stairs layer, which every walker but the slime
  collides with in a world with elevation (`plank_look.gd` `open_lane`, as the stairs).
- **A long bridge with no landing** (the owner's come-back secret) is crossed only by a Roll that
  keeps rolling: in the body-shapes mode (the story's mode after the prologue) the **charged Roll,
  the `roll-charge` upgrade** (since 2026-11-20 the fourth of four Roll Fragments teaches it:
  [quests spec 14.8](specs/quests.md#148-finds-the-war-journal-the-recipe-page-and-the-charged-roll-2026-11-20)), held all the way; in the classic game the Roll
  held. The quick Roll (one or two planks), quick Rolls in a row (the cooldown is longer than the
  fall delay) and walking fall in. A bridge meant for the quick Roll needs a landing every two planks.
- Tried in the plank lab, `world.playground-planks` (`game/dev/planks/playground-planks.tscn`, built
  by `tools/build_plank_lab.gd`; `?map=playground-planks`): an eight-plank bridge with no landing,
  a stepped bridge (two planks, a landing, two, a landing, two), and the heart chests on the island.
  `tools/film_planks.gd` films it. Tests: `tests/test_falling_planks.gd`, `tests/test_heart_chest.gd`.
- **Over a dry ditch** (2026-11-19, the Roll's first lock: young Burr's lesson, quests spec §14.3):
  a falling plank with `dry` on falls as a slab does, with a wooden clatter (`BreakWood`) and dust
  and no splash, over a hole painted on the `elevation` layer (level -1 in level-0 ground) with a
  void hazard over it whose `draw_look` is off, so the ditch's own earth walls and floor show. Like
  every deck it opens its passage over the hole at its `level`. Built in **Burr's yard**
  (`level-1-c4`, node `BurrYard`): a ditch one level deep, two rows by three cells, across the side yard west
  of the blue cottage (cells x 0-2, rows 3-4; its floor painted forest soil, its walls `mountain-dirt`
  on a `cliffs` layer), two dry planks across it at x 2, the void `ditch-void` (damage 5) returning
  every fall to `ditch-safe-spot` on the yard side, and beyond it, in the nook against the north
  cliff, the chest `burr-yard-chest` (15 coins). A blocker (`burr-house-back`) closes the strip behind
  the cottage, so the nook is reached only over the planks: one quick Roll from the rim crosses
  both; walking drops into the ditch.
- **Lily pads** (2026-11-21, Gloop Forest's Mere, F3): the same pieces with a lily look,
  `game/world/water/sinking_lily_pad.gd` (a falling plank: the water-life sheet's round pad on its
  idle loop, a dip cue `WaterEnter`) and `lily_pad_landing.gd` (a HazardDeck like the plank landing:
  the white-lily pad); laid by `tools/build_gloop_river_roads.gd` with the water hazard over the
  lane ([the design](../design/2026-11-21-gloop-river-roads.md)).

## Holes and hatches

The ways down and up, for any world (owner, 2026-10-19), in the Scenery dock's **Holes & hatches**
category (placed under `Objects`; set the DoorScript's target in the Inspector):

- **Open hole** (`object.open-hole`, `scenes/objects/open-hole.tscn`): broken flagstones round a
  black shaft (`goo-bomb/floor-hole.webp`), always open: stepping in, the slime falls (`kind` `fall`)
  to `target_area_id`, onto the landing (`object.landing`) named by `target_door_id` there, dropping
  in from above (2026-10-31; no landing named: the world's spawn). One-way.
- **Open hole with a ladder** (`object.open-hole-ladder`): the grassy hole with a ladder
  (`gulp-props` frame 1), `kind` `ladder_down`, its `arrival` child below it for the way back up.
- **Cracked floor** and **cracked ground**: the same holes, shut until a Goo Bomb blast (or a Heavy
  slam) breaks them (`cracked_floor.gd`, `cracked_ground.gd`); **cracked wall**: a cave mouth or a hole
  in a wall the bomb opens (`cracked_wall.gd`).
- **Hatch exit** (`object.hatch-exit`): the trapdoor (`stair-hatch-2x1.webp`) a way up arrives at:
  arrival only (set `door_id`, point the ladder's `target_door_id` at it); it opens as the slime comes
  out and slams shut behind it (`bolt_hole_hatch.gd`, the bolt-hole's; `dungeon.boltHole`).
- **Cave ladder**: the cave's ladder up. (The Lair's stair hatch went on 2026-10-24: its stairs
  are stair doors, `object.stair-door`, [the Inner Stair](#the-lairs-own-pieces).)
- **Hill doorway** (`object.hill-doorway`): an old fort-stone doorway with two cold iron sconces, for a
  hill's face, always open (a DoorScript of side north; set its target).
- **Cave mouth** (`object.cave-mouth`) and **wall hole** (`object.wall-hole`), 2026-11-13: an arched
  cave opening (160 units wide) and a small round hole (112) framed in the wall's own stones, for a
  cliff's face: at its foot, or on the wall at a balcony's back edge
  ([Balconies](SKINS.md#balconies)). Both are a DoorScript of side north, always open (set the
  target); their node stands on the threshold (the hole's opening a little above it). **They take
  the style of the wall they stand in** by themselves (2026-11-14): their Visual
  (`game/world/elevation/wall_door_picture.gd`) reads the style the elevation draws the face in just
  above the node and shows that style's picture, again when the node is moved in the editor or the
  elevation is rebuilt; its **Wall Style** in the Inspector picks one by hand instead ("from the
  wall" is the default), and **Foot Px** sets how high the picture's bottom edge stands over the
  node. Art: `asset/MAPS/objects/cave-mouth-<style>.webp` (320 px wide) and
  `wall-hole-<style>.webp` (224), cropped to their art (sources in
  `asset/Originals/elevation/wall-doors/`, packed by `scripts/art/pack-wall-pictures.py`), one for
  each of the 25 wall styles (a style added later shows the meadow rock's until its pictures are
  made).
- The Scenery dock's **Holes & hatches** tab lists every door object since 2026-11-13: the holes
  (open, with a ladder, drop hole, cracked floor and ground, dry trunk hole), the doors in a wall
  (cave mouth, wall hole, hill doorway, cracked wall, the Watchkeeper's hideout, the Lair's mouth and
  its bolt-hole's mouth), and the ways up (hatch exit, ladder hatch, cave ladder, stair door).
- A cracked wall's `crack_tint` (2026-10-19) tones its crack to its rock: a lower alpha hides a
  secret crack in the stone.

### A weak wall in a house

A house room's wall can hide a way out (owner, 2026-11-19: "not so evident that the wall is
different", worn and weak; a Goo Bomb opens it). The first is in `west-village-b5-snail-house`, on
its west wall, not yet played.

- The room's walls are the `cottage` interior walls ([INTERIOR_WALLS.md](INTERIOR_WALLS.md#the-cottage)):
  the weak stretch is the cottage's **cracked** block painted in the west rim (cells (0, 5) to
  (1, 6)), the same plaster panel with a few hairline cracks, a damp stain and a chip; a
  `cracked-wall` (`side-wall-crack`) stands on the floor line in its middle with
  `frame_drawn_by_wall` on, as in the box-room lab. The bomb turns the block into the **blown** hole
  (laths, daylight and leaves behind) and opens it; the flag
  `west-village.b5-snail-house-side-wall` keeps it open.
- With its door group set (`door_side` west, `arrival_offset` (48, 0)) the hole is a door to the
  chunk: pushing west into it travels to `west-village-b5-snail-house-side`, a door node on the
  shell's west side (`side` east, no picture), where the slime walks out into the lawn between the
  two houses. Nothing leads there before the wall is blown: the lawn is fenced in.
- F6 on `west-village-b5` or on the room lends the Goo Bomb (`dungeon.devPowers`), to try it.
- The outside shows no mark of the hole on the shell yet.
- Until 2026-11-19 (the same day) the weak wall was a picture laid over the old painted back wall,
  coming out behind the shell where the house's picture hid the slime; the owner moved it to a side
  wall, which needed the four-wall interior.

The second is level-1's **mushroom-home** (owner, 2026-11-21: a crack in the back wall that a bomb
opens onto the back yard where C4's heart quarter is):

- The room is round (`round-walls`, the mushroom style): `round-walls/back-crack` is a **cracked**
  opening at the top of the ring (the mushroom set's cracked panel), and `back-wall-crack`, a
  `cracked-wall` with `frame_drawn_by_wall` on, stands on the floor line in front of it (512, 136).
  The blast turns the panel into the **blown** hole (leaves and daylight behind) and opens it; the
  flag `level-1.mushroom-home-back-wall` keeps it open. The wall holds the door (`back-wall-hole`,
  side north): pushing up into the hole travels to C4.
- The yard is the fenced pocket east of the mushroom house, under the cliff, the heart quarter in
  its middle; nothing else leads there (the cliff behind the house leaves no room to come out
  there). Its end is `mushroom-home-yard` in level-1-c4 (704, 204): a door with no side on the
  house's east face, so the slime lands at the cap's edge beside the heart (its `arrival`, snapped
  to the yard's top-left tile: feet (736, 188)) and walks left into the house's side to go back in.
  A door without a side is not held to the north–south pairing.
- The outside shows no mark of the hole on the house yet.
- The yard's back wall (the three-level cliff on C4's north edge, its top in North Wilds C3)
  carries a **Feral climb to C3** (owner, 2026-11-21: "a climb vine here in this wall that allows
  the player to climb to the other chunk"; "a both way entrance"; painted on the vine tilemap, not
  stretched): vines painted on each chunk's `vines` VineLayer, going on past the chunk line
  ([Across a chunk line](SKINS.md#across-a-chunk-line)).
  - C4 `vines`: column 12, rows -1 to 1, the face above the yard (row -1 past C4's top edge, the
    face's top part, says they go on into C3). The slime takes hold at the yard's foot facing up.
  - C3 `vines`: column 13, rows 31 to 33, the face under the strip (rows 32–33 past C3's bottom
    edge). The slime takes hold on the strip's lip facing down. The trees at forest cells (12, 30)
    and (13, 30) were erased to open a gap beside the old one at (14, 30)–(15, 30); the two columns
    differ (the tree crown at (11, 30) covers the strip over column 12), so a crossing keeps the
    slime on the nearest painted column (x 846 coming up, 818 coming down).
  - Crossing, the slime arrives **still clinging** on the other chunk's vines (owner: "keep him
    climbing if he holds W", not dropped in from above): with the interact key held through the
    crossing it climbs on (up over C3's rim onto the strip, or down C4's face to the yard); let go,
    it drops. The heart quarter stands at (804, 208) since the owner moved it.

  The Wilds stay shut until the Feral skin (Pearl 3), as the open map after Release 1 wants
  ([decision 10](../story/07-decisions-archive.md)).

## Mechanisms: the knock target, the ram, the runaway cart

> **Status:** built 2026-11-23 as step 1 of the
> [dungeons 2 and 3 rework](../design/2026-11-23-dungeons-2-3-rework.md), in a lab world; no dungeon
> uses them yet. A fix round on 2026-11-24 (the slime shoved across the ram's lane, true blows on
> enemies, the rope and the haul chain, the cart's front view; the handover:
> [2026-11-23-dungeons-rework.md](../handover/2026-11-23-dungeons-rework.md)). Filmed
> (`scripts/godot/film-mechanisms.sh`), not played with a keyboard, and `tests/test_mechanisms.gd`
> is written but has not been run.

One trigger and two mechanisms it lets go. A mechanism is never a lock that stays open: thrown at,
it strikes, and winds itself back. What it strikes can be a lock (the bricked arch, the rail gate),
an enemy, the slime, or a boss that answers a hook.

| Piece | Scene id | Script |
|---|---|---|
| Knock target | `object.knock-target` | `game/dungeon/knock_target.gd` (`KnockTarget`) |
| Ram | `object.ram` | `game/dungeon/ram.gd` (`Ram`) |
| Bricked arch | `object.bricked-arch` | `game/dungeon/bricked_arch.gd` (`BrickedArch`) |
| Runaway cart | `object.ram-cart` | `game/crystal_mine/ram_cart.gd` (`RamCart`) |
| Rail gate | `object.rail-gate` | `game/crystal_mine/rail_gate.gd` (`RailGate`) |

All five scenes are in `game/scenes/objects/dungeon/`. Shared code: `game/dungeon/mechanism_strike.gd`
(what a moving part does to what it sweeps) and `game/dungeon/mechanism_debris.gd` (the bricks,
planks and ore that fly).

### The knock target

A round wooden practice target (red and white rings, a straw back) on a short post, about a cell of
body, a rope from its hook to the mechanism it holds back.

- **What knocks it:** a thrown thing (a hit tagged `thrown`: a pot, a bone, a stunned enemy), the
  Bow's arrow (`on_arrow_hit`) and a Goo Bomb's blast (`receive_blast`), as the bell takes them. A
  thrown thing reaches it only from its own elevation level (as every thrown thing does): put the
  target on the level it is thrown from.
- **Everything else** (the Spear, a Roll, the slime's body pushing on its post) is refused as
  `immune` with a wooden knock and, once per visit, its `refusal_text`: "A good knock from afar would
  trip it." The line comes back once the slime has gone `lineResetPx` away.
- **Knocked:** it spins and rocks (`spinMs`), emits `knocked` and sets off every node in `targets`
  (NodePaths) through `DungeonState.fire`, with the payload `{"source": the target, "targetId"}`:
  each time, never for good, nothing recorded. Then it hangs slack (tilted, the rope sagging) and
  further hits only rock it, until its mechanism calls `rearm()` (it snaps upright with a clack and
  emits `rearmed`). A target none of whose `targets` is a mechanism (the group `knock_mechanisms`)
  rearms by itself after `rearmMs`.
- **The rope** (drawn by code): a hemp rope of two twisted strands (a light strand with the darker
  one's slanted twist marks, a dark outline, a shine on its upper edge) with a soft shadow on the
  floor. It hangs from the disc's hook down the back of the disc to the floor beside the post and
  just behind it, on the side it runs to (right when it runs straight up or down the screen), so it
  never crosses the target's face; then it lies along the floor to its end, pinned by small iron eyelets (a riveted plate and a ring it runs through): one where it meets
  the floor, one at each of `rope_points`, and on a run without corners one or two along it (two or
  three in all). Armed it is taut and straight; slack, each run between two pins lies in a loose
  curve, the next one the other way; a knock sends a quick whip along it from the hook to its end,
  held still at the eyelets, and the snap upright a smaller one.
- **Properties:** `target_id`; `targets`; `rope_points` (points on the floor the rope passes, from
  the node, to route it round a pit or along a wall; each is an eyelet); `rope_to` (a Node2D where
  the rope ends; empty: the first target that has `rope_anchor()`); `refusal_text`.
- A mechanism let go by anything else calls the target's `go_slack()`, so it never shows armed while
  its mechanism is away. The target tells each mechanism who holds it (`set_knock_target`) when the
  world is built.

### The ram

An iron-capped log hung by two chains from a timber gantry.

- **Placing:** the node stands at the lane's start, the middle of its rest end. The lane runs
  `toward` (north, south, east, west) for `length` cells, `width` wide (128: two cells). The log
  rests behind the node, under its gantry: that bay (about 220 units deep; 80 wide for a lane across
  the screen, 160 for one up or down it) is solid. The lane is free floor with worn grooves drawn
  along it (the tell). Its swing reaches the lane's end: a breakable standing on that line (the
  bricked arch in the wall there) is struck.
- **The cycle:** held back → `trigger()` → the shudder `windupMs` (it shakes, the chains rattle,
  dust falls from the gantry's feet) → the swing out `swingMs` (speeding up) → held at full reach
  `holdMs` → the swing back `returnMs` (it hangs loose and low) → the winch `rewindMs` (a ratchet
  click every `ratchetEveryMs`, the log creeping back and up a tooth at a time, the cog turning) →
  ready: it calls its knock target's `rearm()` and emits `ready_again`. `trigger()` does nothing
  until then. Signals: `released`, `swung` (with how many things it struck), `ready_again`.
- **What the swing strikes** (each thing once per swing, only on the ram's own elevation level):
  a node in the group `ram_breakable` gets `on_ram_hit(ram)`; a node with `on_mechanism_hit` (below)
  gets that call instead of damage and the log swings on through it; an enemy takes `damage` as a
  [mechanism's blow](#a-mechanisms-blow-on-an-enemy) and is knocked down the lane through the knock
  system (walls splat, ledges and hazards apply:
  [THROW_COMBAT.md](THROW_COMBAT.md#knocked-enemies-and-the-ground-2026-11-16)).
- **The slime is shoved across the lane, never carried down it** (`MechanismStrike.shove_slime`):
  to the side its feet stand on (down the screen, or right, from the middle line), far enough to
  stand `slimeClearPx` past the lane's edge, at `slimeKnockSpeed`. It is shoved as soon as the head
  would reach its near side (`slimeBodyPx` counts as its half width) in the time that takes, so it is
  out of the lane before the head arrives and the log passes beside it; at the swing's speed that is
  when the head is about a cell away. It takes `slimeDamage` (true damage). Its invulnerability after
  a hit and a Roll's i-frames refuse the hit (and the shove): then the log passes over it. A slime that
  shrugs knockback off (the Heavy form, the improved Slam, on stairs) is hurt but stays where it is.
- **Looks:** one gantry picture (seen from the front, whichever way the lane runs); the log from the
  side for east and west, on end for north and south; the chains, the shadow and the grooves are
  drawn by code. `rope_anchor()` (where a target's rope ends) is the foot of the cog's post.

### The bricked arch

A doorway bricked up with old bricks, with **no crack**: a crack is the Goo Bomb's mark, and this is
not a bomb lock. Only a mechanism opens it.

- **Placing:** as a door object in an interior wall's doorway
  ([INTERIOR_WALLS.md](INTERIOR_WALLS.md#the-door-objects-in-the-opening)): paint the plain doorway
  block, then put the arch on the floor line of the room its face looks into, in the middle of the
  passage, `wall` that room's wall; `interior_style` names the wall's style (its panel is laid where
  that style's door leaf lies). Its picture is its own sheet, not a leaf of the interior walls yet.
- **Until it is burst it blocks.** A weapon, a throw or a slam says "Bricked up, and solid. Only
  something heavy would break it." (`refusal_text`); a blast says "Not even a crack to work on."
  (`blast_text`). Its hurtbox reaches past its body toward the room and it names its bricks' body
  (`get_body`, so they do not hide their own hurtbox from a throw's line test): a thrown thing meets
  it before it breaks on the bricks as on a wall. A blast counts when its ellipse holds the bricks'
  middle (`blast_point`): a bomb laid against either face does.
- **`on_ram_hit` bursts it for good** (its record, `arch_id`): half the bricks at once, the rest a
  moment later, bricks flying, dust, a shake, the stone break cue and the secret jingle. Rubble lies
  in the doorway and the way is open. Signal `burst`.

### The runaway cart

A cart heaped with ore, held on a slope by a brake (a lever and a chock) that a knock target's rope
holds. It is not the mine's travel cart (`mine_cart.gd`), which the slime rides.

- **Placing:** the node is the cart's place while held; `points` is its line from there (world units
  from the node, the first point (0, 0)). A straight line is what it is made for; a line with a bend
  is followed leg by leg (the cart turns at the corner at once, its picture swapping between its side
  and its front view). It draws its own rails along the line (`draw_rails`), its brake beside the
  start, a buffer stop past the line's end (`buffer_stop`) and, with `returns`, the pulley post and
  the counterweight behind the start.
- **The cycle:** held (it rocks against its chock, the ore glints) → `trigger()` → the brake snaps
  `brakeMs` → it rolls from `startSpeed` up to `maxSpeed` by `accel` (the wheels turn, sparks, the
  rattle's pitch rises) → the line's end (a bump, a shake, ore jumps out) or a node it stops
  against. With `returns`: after `restMs` the counterweight's chain hauls it back over `returnMs` (a
  click every `ratchetEveryMs`; a heavy iron chain from the pulley post, its links drawn big enough to
  read at game size, with a shadow), the chock drops, its target is rearmed, `ready_again`. Without:
  it stays where it ended, for good (its record, `cart_id`), which is how a cart opens a shortcut.
  Signals: `released`, `bumped` (with what it stopped against), `ready_again`.
- **Into the next room** (2026-11-25, the rebuilt Mine's M7 and M1): with `rolls_out` the cart's line
  ends in a doorway's passage; at its end it rolls on out of the room (it fades over its last 90 units,
  as into a tunnel) and is gone for good (its record), with no buffer stop. The room it rolls into has a
  cart with `arrives` and the same `cart_id` on a line from that doorway to a buffer stop: no brake and
  no cart until the record is set, then the cart stands at its line's end. A spent cart built again
  leaves its knock target slack.
- **Through and kicked back** (2026-11-24, the Colossus's plate fight): with `through` the cart is a
  passing mine cart: it comes out of a tunnel at its line's start, rolls the whole line and goes into
  the tunnel at its end, and the next cart comes out of the start a moment later. A boss that it hits
  can hold it and send it home: `hold_for_kick`, `kick_back` (it rolls back fast into its start
  tunnel and its target rearms), `let_go`. The details:
  [The crystal fight](#the-crystal-fight-step-2-of-the-rework-three-crystals-since-2026-11-25).
- **What it rams** (each thing once per run, only on its own elevation level): a `ram_breakable`
  (the rail gate) gets `on_ram_hit(cart)` and the cart runs on through; a node with
  `on_mechanism_hit` is found a little ahead and the cart rolls on until its front touches the near
  edge of that node's hurtbox (its front: the side picture's bumper, `CONTACT_SIDE` 42 units ahead of
  its place, or its footprint's front edge seen from the front, `CONTACT_FRONT` 8), and stops there:
  the call, the bump, the dust and the sparks all come at that touch, and the ore falls back round
  the cart instead of onto the node; an enemy takes `damage` as a
  [mechanism's blow](#a-mechanisms-blow-on-an-enemy) and is knocked aside, off the rails; the slime
  takes `slimeDamage` and is knocked aside too (at contact, `slimeKnockback`). Standing still (held,
  or at its line's end) the cart is solid; rolling and hauled back it is not.
- A line across the screen shows the cart from the side with its wheels turning and sparks flying
  behind. A line up or down the screen shows it from the front (one picture for both ways), cut in
  two at the rim: as each axle crosses a sleeper's joint the bin jolts up and rocks to one side, then
  the other on the next sleeper; the ore heap jostles in the bin a moment later and two loose stones
  on it hop on the harder jolts; sparks fly at both wheels above `sparkSpeed`. Hauled back it rattles
  the same, gently.

### The rail gate

Timber and iron across the rails, chained. `rails` is the way the track runs through it:
"north-south" (seen from the front) or "east-west" (the front picture turned and foreshortened, as
the kit's doors in a side wall). Until it is smashed it blocks ("Chained shut across the rails.",
for weapons, throws and blasts alike; its hurtbox reaches past its posts and it names its planks'
body (`get_body`), so a pot thrown along the rails meets it before it breaks on the planks as on a
wall; from the side its posts stop a throw as a wall does); `on_ram_hit` smashes it open for good (its record, `gate_id`):
the planks and the chain fly, the wood break cue, the secret jingle. Its two posts stay and still
block; the way between them is open. Signal `smashed`.

### The hooks

- **`on_ram_hit(source: Node)`** on a node in the group `ram_breakable`: a mechanism's moving part
  reached it. `ram_rect()` (a global Rect2; else a small box at its position) is what must be
  reached. The bricked arch and the rail gate have it; a new breakable needs only the group, the
  method and the rectangle.
- **`on_mechanism_hit(kind: StringName, source: Node)`** on a hurtbox's receiver, or on a node up to
  four levels above the hurtbox: called INSTEAD of damage, once per swing or run, with kind `&"ram"`
  or `&"cart"`. For bosses and mini-bosses (step 2 of the rework): the node decides what the blow
  does. The cart stops with its front against such a node's hurtbox and calls it at that touch; the
  ram calls it as its head reaches it and swings on. Who answers it: the Matron (the rework's fight)
  and, since 2026-11-25, the Brood Warden (the ram: knocked flat, BESTIARY.md row 22) and the
  Shardback (the cart: brittle, his shell shatters; cold, it clangs off; row 28).
- A mechanism is any node in the group `knock_mechanisms` that has `trigger(payload)` and calls the
  payload's `source.rearm()` when it is ready again.

### A mechanism's blow on an enemy

The ram's log and the runaway cart hit an enemy as the heaviest blow in the game
(`mechanism_strike.gd` `_strike_enemy`; the reactions read it in `hit_reaction.gd` and
`enemy_reactions.gd`):

- **True damage:** the request's `true_damage` makes `EnemyReactions.damage_scale` skip the part's,
  the phase's and a knockdown's multipliers: `damage` lands whole (a Thorn Guard takes the whole 60).
  A shut gate's 0 stays (a blow the gate zeroes: a shut part in a phase the blow does not land
  through).
- **It lands through a shield** (the hit's `true_blow`, `HitReaction.blow_lands`): a phase's
  immunities, a shut part and a patterned enemy's `_shields` let it through (a sleeping statue, a
  charging boar, a walking Squint, a Dung Roller with its ball, a Cocoon Mimic holding still), and so
  do the wake guard, the break-free armor and a phase's armor (a body another blow has just bowled
  still takes the ram's). It does not land:
  - on a boss (the boss answers the hook instead);
  - in a phase marked `noSleep` (the sleep throw's mark, reused: the phases where the body is out of
    reach): a Popworm burrowed, surfacing or sinking; a Hopper, a Squint or Big Squint and a Bone
    Leaper in the air; a Pipe Worm in its pipe; a Pick Mole ducked or lining up behind its crates; a
    Crystal Mite waiting or dropping. The Worm Bulwark's charge and skid carry the mark too, but
    nothing shields him there, so a blow lands on him then as at any time;
  - on an enemy **invulnerable by design** (`EnemyReactions.invulnerable_by_design`: it answers
    `is_invulnerable()` with true): the Prism Eye with `pattern.invulnerable` (owner, 2026-11-21:
    "make prism eye invulnerable, you have to go around him") clinks under the ram and the cart as
    under everything else. Of the other shielded enemies none is invulnerable by an owner's rule but
    two that a blow cannot hurt anyway: the Gloomling has no hurtbox (only light moves it), and the
    Carnivore Plant ("only fire kills them") takes no damage from a thrown-class hit, which a blow
    is: it dozes off as under a thrown pot.
- **It moves the body at least `hit.resistFloor` of the way** (0.6: the hit's `resist_floor` raises a
  low `knockbackScale` for its launch, its knock slide and the kill's send-off): a heavy enemy
  (`knockbackScale` 0.2) on a ram's lane slides 2.25 cells (filmed: a marching Thorn Guard, 147 units).
  An enemy whose `knockbackScale` is 0 stays unmovable, and so does one rooted while stunned
  (`_slides_when_stunned` false); they are struck where they stand:
  - `knockbackScale` 0 (the knock system's unmovable class besides the bosses): Spitcap, Rook Thief,
    Pipe Worm, Dung Roller, Silk Lurker, Egg Sac, Brood Warden, Gloomling, Glint Bat, Crystal Crawler,
    Prism Eye, Pick Mole, Bone Marcher, Watcher Eye, Rock Chucker, Spiny Caterpillar, Ledge Raven,
    Carnivore Plant, Jelly Bouncer;
  - rooted while stunned, always: Brood Warden, Carnivore Plant, Crystal Crawler, Dung Roller, Egg
    Sac, Glint Bat, Jelly Bouncer, Ledge Raven, Pick Mole, Pipe Worm, Prism Eye, Rock Chucker, Rook
    Thief, Silk Lurker, Spiny Caterpillar, Spitcap, Bone Marcher; in some phases: the Thorn Guard
    asleep or waking (a statue: the ram cracks it for 60 and it does not budge), the Cocoon Mimic held
    or disguised, the Squint unless open or walking, a skeleton lying as a pile.

### The numbers (`game-constants.json` `dungeon`)

| Key | Value | What |
|---|---|---|
| `knockTarget.rearmMs`, `spinMs`, `spinTurns`, `rearmSnapMs` | 3000, 400, 2.5, 180 | a target with no mechanism rearming by itself; the knocked spin and its turns; the snap upright |
| `knockTarget.slackTiltDeg`, `rockDeg`, `rockMs`, `swayDeg`, `swayPeriodMs` | 34, 16, 420, 3.5, 2600 | how far it hangs over when slack; a hit's rocking; the armed target's slow sway |
| `knockTarget.lineResetPx`, `lineMs`, `tapEveryMs`, `reachPx` | 480, 2600, 700, 8 | how far the slime goes before the line is said again; how long it shows; the wooden knock at most this often; the push's reach |
| `ram.windupMs`, `swingMs`, `holdMs`, `returnMs`, `rewindMs` | 350, 420, 150, 600, 8000 | the ram's cycle |
| `ram.damage`, `slimeDamage`, `slimeKnockback` | 60, 20, 760 | to an enemy (true damage); to the slime (true damage); the slime's knockback (aside) if the head reaches it before the shove does |
| `ram.slimeKnockSpeed`, `slimeClearPx`, `slimeBodyPx` | 1800, 16, 22 | the shove across the lane: its speed, how far past the lane's edge the slime ends, the slime's half width |
| `ram.cockPx`, `hangPx`, `loosePx`, `dipPx`, `shudderPx`, `ratchetEveryMs` | 44, 16, 3, 5, 2.5, 500 | how far back it is held; its height held, hanging loose and at the swing's lowest; the shudder; a ratchet click |
| `ram.shakeMs`, `shakeIntensity` | 220, 0.007 | the thud at the swing's end |
| `ram.hit` (`hitClass`, `launchSpeed`, `knockbackPx`, `knockbackSpeedScale`, `resistFloor`, `bowlDamage`, `hitStopMs`, `trauma`, `kickPx`, `sparks`) | thrown-heavy, 760, 240, 2, 0.6, 15, 110, 0.6, 9, 16 | the hit an enemy takes: its reaction class, its knock (at least `resistFloor` of it, however heavy), what bowling into others costs, and the feel |
| `ramCart.brakeMs`, `startSpeed`, `maxSpeed`, `accel` | 120, 140, 560, 520 | the brake's snap; the roll |
| `ramCart.damage`, `slimeDamage`, `slimeKnockback` | 60, 20, 460 | to an enemy (true damage); to the slime and its knockback aside |
| `ramCart.restMs`, `returnMs`, `ratchetEveryMs` | 1500, 8000, 400 | the wait at the line's end; the haul back; a click |
| `ramCart.sparkEveryPx`, `sparkSpeed`, `bumpShakeMs`, `bumpShakeIntensity` | 46, 260, 200, 0.006 | sparks under the wheels above that speed; the bump |
| `ramCart.hit` | thrown-heavy, 700, 220, 2, 0.6, 15, 100, 0.55, 8, 14 | as the ram's |
| `burst.shakeMs`, `shakeIntensity`, `jingleDelayMs`, `lineEveryMs` | 260, 0.008, 350, 1500 | the arch's and the gate's break: the shake, the secret jingle after it, a refusal line at most this often (real time, as the kit's doors space their lines: the spacing is presentation only) |

### Art and sound

Art: Magnific GPT 2.5 (`gpt-2-mini`, transparent, the Lili creation as style reference), six sheets,
243 credits; sources and prompts in `asset/Originals/dungeon-kit/mechanisms/`, packed by
`python scripts/art/pack-mechanism-art.py` into `godot/asset/MAPS/objects/mechanisms/`. The
pictures load through `game/runtime/sheet_sprite.gd`, so they show before the editor imports them.
The chains, ropes, shadows, grooves and glints are drawn by code; the cart's rails are
`mine_rails.gd`'s.

Sound: ten cues under `Effects` in `global.tscn` (Sound Picker round 15,
[audio spec §17](specs/audio.md#17-round-15-the-dungeon-mechanisms)): `KnockTargetHit`,
`KnockTargetTap`, `KnockTargetRearm`, `RamWindup`, `RamSwing`, `RamThud`, `RamRatchet` (the cart's
haul back clicks with it too), `CartBrake`, `CartRoll` (a loop, its pitch raised with the cart's
speed; redone 2026-11-24 as option "b": a heavy rumble with the wheels' clatter on the joints,
played as loud as the one-shots less 2 dB), `CartBump`. They are the builder's defaults: the owner
has not heard or picked them. Their
players name packed copies of the takes (`asset/audio/sfx/packed/world/*.res`, written by
`tools/pack_cue_sounds.gd`), which play without an editor import. The arch plays `BreakStone`, the
gate `BreakWood`, both `SecretFound`.

### The mechanism lab

`game/dev/mechanisms/mechanism-lab.tscn` (`world.mechanism-lab`; dev only: `game/dev/` is left out
of the release export). `?map=mechanism-lab` (web) or `-- --map=mechanism-lab` (desktop); F6 on the
scene lends the Spear, the Roll, the Goo Bomb and the Bow (`dungeon.devPowers.mechanism-lab`).
Built by `"<Godot console exe>" --headless --path godot -s res://tools/build_mechanism_lab.gd -- --force`
(it overwrites hand edits). One hall of cave rock (interior walls, `cave-rock`), three screens wide,
a lane a screen, with a pocket room north of lane A behind the arch (48 x 20 cells); a Dungeon node
(`resume_saves` off), so its pots and enemies come back when a lane is entered again. The arch, the
gate and the first cart stay as they end for the session.

| Lane | What it shows |
|---|---|
| A | pots; a void pit with a knock target on its far side, its rope routed round the pit; a ram aimed north at the bricked arch; a chest in the pocket behind the arch |
| B | a ram across a pen of three enemies (a Slime Spider, a Worm Brawler, a Thorn Guard), its target on the pen's edge, pots: bait enemies onto the grooves, or throw a stunned one at the target |
| C | a cart that stays where it ends (its target, a rail gate on its line, the line running on to a buffer stop); a cart that is hauled back, aimed across a pen of one enemy |

`bash scripts/godot/film-mechanisms.sh <name> --film=<film>` films a lane frame by frame into
`output/mechanisms/<name>/` (`godot/tools/film_mechanisms.gd`; one game window at a time; what each
shows is in the tool's head): `ram-arch`, `ram-enemies` (the Thorn Guard put in its march by the
tool: asleep it is rooted), `ram-slime` (the slime on the middle line, then near the far end),
`ram-south` and `ram-west` (lane B's ram moved and turned by the tool), `target-refuse`,
`target-arrow`, `target-blast` (a Goo Bomb spat beside the target), `target-roll`, `arch-refuse`,
`gate-refuse`, `cart-gate`, `cart-enemy`, `cart-return`, `cart-hook` (a standing dummy that answers
`on_mechanism_hit`, `tests/lib/mechanism_hook_probe.gd` with the training dummy's picture: the cart
stops against it, the log swings through it), `look`.

### The Matron lab (a boss that answers the hook)

`game/dev/bosses/matron-lab.tscn` (`world.matron-lab`, 2026-11-24): the Orb-Weaver Matron's ram
fight, step 2 of the rework, in a 20 x 16 root-rock room with five rams along its north wall (the
owner's drawing), each ram's target straight below its lane by the south wall (the owner moved them
there from across the room, 2026-11-24: the ropes were too hard to follow). Her missed webs leave web
balls (a liftable, `web-ball`) to throw when the pots run out. The rams are both sides' tools: she
answers `on_mechanism_hit` (a ram flings her out of a dive, knocks her cocoon down), and she trips
a ram at the slime herself by spitting a glob of web at its target, from the floor too after a dive
(she lies 4 s), down her own lane as well: a slime that waits in her lane and steps out when she
spits makes her log fling her. Her full heart rises in the room's middle. The fight, the lab and its films
(`scripts/godot/film-matron.sh`): [matron spec §9](specs/matron.md#9-the-ram-fight-the-rework-built-2026-11-24-in-a-lab-the-hollows-since-2026-11-25).
The Weaver Hollow's Crown keeps the built fight until it is rebuilt with rams (step 3).

### Limits

- A thrown thing hits only on the thrower's level, so a target is knocked only from its own level.
- The ram's gantry and the cart's front view have one picture each: a ram aimed south uses them too
  (filmed, `ram-south`); a cart rolling up the screen has not been filmed.
- The slime is shoved when the head is about a cell away (it must be out of the lane before the head
  arrives); at 60 frames a second that reads as a hard shove from the swing, not a touch.
- The cart stops against a hooked node where its front meets the node's hurtbox: a boss whose
  hurtbox is narrower than its picture is overlapped by that much (the film's dummy has a hurtbox as
  wide as its arms). Seen from the front (a line up or down the screen) the node is found up to 28
  units before the touch and the cart rolls on to it; filmed only from the side (`cart-hook`).
- The rail gate across an east-west track is the front picture turned (not filmed).
- Enemies never avoid a lane or the rails by themselves; a mechanism strikes whatever is there.
- The cart's rattle is one global looping player: two carts rolling at once share its pitch.
- The bricked arch's panel is its own sheet for the cave rock's north doorway; in another style or
  wall it is the same panel turned and fitted to that style's leaf (not filmed).

## Refills that grow back

- **Energy flower:** `object.energy-flower` (`energy_flower.gd`): walked into while energy is not
  full, the slime drinks `dungeon.refill.flowerEnergy`; the bloom closes into a bud and opens again
  `dungeon.refill.flowerRegrowMs` of play later.
- **Pots that hide a refill:** `object.dungeon-pot`: a clay pot (a liftable) with a `PotLoot` child
  (`pot_loot.gd`; any liftable can get one): when the slime sucks it up, what it hid is left where it
  stood: `loot` "heart" (`dungeon.refill.heartHp`), "energy" (an energy shard,
  `dungeon.refill.potEnergy`), "coins" (`dungeon.refill.potCoins`) or "random" (`weights`). The pot
  and its loot come back when its room is entered again. The heart and coins are
  `dungeon_pickup.gd` (walk-over pickups; a heart stays while health is full).

## Dark-room extras

- **Shadow path:** `object.shadow-path` (`shadow_path.gd`, class `ShadowPath`): glow-moss on a hidden
  ledge over the void, drawn only within light: the slime's ember glow in a dark room (160 units,
  once the Lantern is learned: before it the slime sees nothing there), the Lantern's flame, candles,
  braziers, a bomb's flash (every light source); it fades over
  `dungeon.shadowPath.fadePx` at a light's edge, and shows in full outside a dark room that is still
  dark. Its `cells` are 64-unit cells from its position (put it on a cell corner). It is always a
  safe deck: a slime crossing blind by memory may; a step off is a fall (put a void hazard under
  it, with a `Return...` point at its mouth).
  **Painted** (2026-10-19, owner): add a `shadow-path` TileMapLayer beside `ground` at (0, 0) with
  `game/world/void/shadow_path_layer.gd` (it takes `shadow_path_tileset.tres`, a one-tile palette: the
  moss patch; `tools/pack_shadow_path_tile.gd` packs it) and paint the ledge cell by cell; the layer
  keeps one ShadowPath over the painted cells as you paint (never saved). Paint the pit as holes on
  the `elevation` layer, lay one `void` hazard over the whole room (it catches only where holes are
  painted) with `fixed_return` at the mouth, and set the `VoidShade`'s `from_paint` so its dark
  follows the painted holes. The Glow-moss Burrow is built this way.
- **Prize glint:** `object.prize-glint` (`prize_glint.gd`): a little star that twinkles over a
  prize, drawn above a dark room's darkness (z 46, as the Gloomling's eyes), so the slime sees from
  the doorway that something waits inside. `tint`, `phase`, `only_in_dark`, `lit_strength`.

## The seal

The owner's decision of 2026-10-17 ([decisions archive](../story/07-decisions-archive.md), "the Pearl
inside the dungeon"; the plan [2026-10-17-pearl-mid-dungeon.md](../design/2026-10-17-pearl-mid-dungeon.md)
"The shared pieces"): each dungeon's Pearl lies inside it, guarded by its mini-boss. Taking it seals
the doors out of the dungeon until the boss falls; a faint or a quit after it resumes at the
entrance, inside, with the seal still on. Only the doors out seal: everything inside, and
everything opened for good, stays as it is.

**Setting a dungeon up.** On the Dungeon node of every world of the dungeon (`dungeon.gd`, its
Inspector group "The seal"): `boss_id` (his camp's or his room fight's `boss_id`: `fatty-one-eye`,
`orb-weaver-matron`, `crystal-colossus`), `boss_name` (the lines: "Fatty One Eye"), `seal_color`
(the boss's colour: Fatty's mud red, the Matron's violet, the Colossus's smoky violet), `roar_sound`
and `roar_pitch` (his roar: `asset/audio/sfx/library/boss/fatty-roar.ogg`; the Matron's hiss
`asset/audio/sfx/synth/enemy/spider-hiss.wav` at 0.4), `dust_color` (the dust his roar shakes down:
crystal dust in the Mine, silk in the Hollow). With `boss_id` empty nothing seals.

**The seal shutter:** `object.dungeon-seal` (`game/dungeon/dungeon_seal.gd`, class `DungeonSeal`,
on the kit's `shutter.gd`): the dressed-stone block with a dark pearl set in its face, bound by a
ring of light in the boss's colour that beats slowly like a heart (its picture is one, tinted by the
Dungeon's `seal_color`). It takes no power and looks like no lock in the look book.

- **Place one** in every doorway that leads out of the dungeon (the entrance; the way out past the
  boss) and nowhere else, like a shutter: in the doorway, on the floor line of the room inside,
  `wall` that room's wall. It needs no id. `glimpse` marks the seal the take's camera shows (else the
  one nearest the entrance marker).
- **While the dungeon is sealed** it is shut and blocks (read when its world is built: after a
  resume it is shut from the start). Walked into, it hums and refuses: "Sealed. Fatty One Eye's rage
  holds it shut." (the Dungeon's `seal_text`); every hit and a Goo Bomb's blast are refused the same
  way. A winch, a bell or a room fight never opens it. On the dungeon map (the minimap and the map
  screen) it is a red bar across its doorway, with or without the compass.
- **Every travel out refuses too:** while sealed, a door or a world exit (`door.gd`, main.gd
  `request_exit`) and a climbable wall with an `exit_area_id` (`climb_wall.gd`) whose target world
  holds no Dungeon node with this `dungeon_id` refuse with the seal's line
  (`DungeonState.exit_refusal`; each world's dungeon id is read once from its scene). Travel between a
  dungeon's own worlds (the Weaver Hollow's floors) goes on.

**The Pearl and its guard.** The Pearl (`object.pearl`, `pearl-two`, `pearl-three`; `pearl.gd`)
stands on its altar (`decoration-world-solid--pearl-altar`) in the mini-boss's room, with a
`object.prize-glint` over it so its glow is seen from the door. Set its `boss_id` to the mini-boss's
room fight's `boss_id` (`fatty-lair-big-squint`, `weaver-hollow-brood-warden`,
`crystal-mine-shardback`): it rises when that fight is won. The map marks only the dungeon's
boss (the Dungeon's `boss_id`), not the guard. `seals_dungeon` (on by default) is what makes its take
seal.

**The take.** Walked into: its card ("Pearl of the Wellspring (n of 8)"), its skin granted
(`SkinState.grant`; the everyday look stays as it was: a skin shows only while it works,
[SKINS.md](SKINS.md)). The card is the skin's celebration and description, and the skin's own
floating lines do not show beside it (owner, 2026-11-21, question 141: they ran on after the card,
under the roar's line); only once the player accepts the card do the roar and the glimpse follow.
Then the Dungeon's `seal_now`: the record is sealed at once
(`DungeonState.seal`), every seal of this world but the glimpse's shuts out of sight, and as the
card closes (`game/dungeon/seal_moment.gd`, real time):

1. **The roar:** his `roar_sound`, a hard shake (`seal.roarShake*`), `seal.roarDust` motes of
   `dust_color` falling over the screen, and the line over the slime: "Fatty One Eye roars! The way
   out slams shut."
2. **The glimpse**, `seal.glimpseDelayMs` later: the world pauses and the view cuts to the entrance's
   seal for `seal.glimpseMs` (1.5 s); it slams up out of its doorway `seal.glimpseSlamMs` in, with a
   boom, and glows; the view cuts back. No seal in this world (the entrance on another floor) or one
   already in view: no cut, the line and the map's red mark tell it. A dungeon of one world per room
   (Fatty's Lair: the take is in the Larder, the entrance's seal in R1's world) shows instead the
   Dungeon's `glimpse_pictures` full screen over the paused world for `glimpseMs`: the doorway open,
   then from `glimpseSlamMs`, with the boom and a shake, the seal up (made in advance by
   `tools/capture_lair_seal.gd`).

**While sealed** (presentation only): his roar sounds far off every `seal.distantRoarMinMs` to
`MaxMs` (45 to 60 s; softer, lower, a light shake and a little dust), not while his fight is on.
When his fight starts (a boss camp's or the Colossus arena's `boss_engaged`, or a room fight with
his `boss_id` starting) he shows his rage: `EnragedLook` (`game/bosses/enraged_look.gd`) adds a copy
of each big sprite of his in `seal_color` that swells and fades (`enraged.pulseMs`, `strength`) and
puffs dust from his top (`enraged.puffEveryMs`), and the boss bar shows his name in red. His health,
damage, speed and patterns stay the built ones. A room-fight boss (the lab's) also roars as it starts.

**His fall** (his id in the dungeon's beaten bosses or in `defeated_boss_ids`: a room fight, a boss
camp, the Lair's director and the Colossus's arena all record it): `seal.breakDelayMs` later (after
"defeated!") every seal of the world sinks with a chime, its ring shatters, "The seals break!", and
it stays down for good; the travels out go again. A Pearl taken after its dungeon's boss fell (an
old save) seals nothing.

**Resume:** unchanged in the kit. A faint wakes the slime at the entrance marker, inside the seal,
with full health; a quit writes the resume save at the entrance; the record keeps the seal and
everything opened for good, so the short way back to the boss stays open.

**Dev:** `?sealed` (with `map=`): every Pearl of the world taken quietly (its guard's fight finished,
its skin won) and the dungeon sealed without the moment; `skins=` lends skins on a floor without the
Pearl. `tools/render_dungeon_seal.gd` (windowed: `"<Godot console exe>" --path godot -s
res://tools/render_dungeon_seal.gd -- --out=<dir>`) renders the lab's take, glimpse, seal, rage and
fall for tuning.

**The API:** `DungeonState.seal(run, id, boss_id, by)`, `is_sealed`, `sealed_by`, `unseal`,
`exit_refusal(tree, target_map_id)`, `world_dungeon_id(map_id)`; the Dungeon's `seal_now(by, moment)`,
`is_sealed`, `seal_text`, `roar_text`, `play_roar`, `seals`, `glimpse_seal`; the seal's `slam`,
`shut_quietly`, `engage`, `break_seal`, signal `refused`; `EnragedLook.attach(boss, color)`,
`is_on(boss)`; `RoomFight.members`, `finish_quietly`.

## The dungeon lab

`game/scenes/worlds/dev/dungeon-lab.tscn` (`world.dungeon-lab`; dev only: not in the release export).
Launch it with `?map=dungeon-lab` (web) or `-- --map=dungeon-lab` (desktop). Rebuild it with
`"<Godot console exe>" --headless --path godot -s res://tools/build_dungeon_lab.gd -- --force` (it
overwrites hand edits). Nine screens, masonry walls on the elevation layer (cobble ground), entered
at B3:

| Room | What it shows |
|---|---|
| B3 the entrance | the entrance marker (a faint resumes here), a small-key chest, the map chest, three pots hiding a heart, energy and coins, an energy flower; north: the small-key door; west: the back of the bolted door; south: the way out (a door to the playground) with the dungeon's seal in its doorway (`glimpse`) |
| C1 the Pearl room | the Pearl on its altar (its glint over it) behind its guard: a room fight with a mini-boss's `boss_id` (`dungeon-lab-guard`, a Worm Brawler) and its shutter; won, the Pearl rises; taken, it grants the Feral skin and seals the lab |
| C3 | an ambush (`once`): shutters on both doorways, two worms, a chest that rises with a small key |
| C2 | falling slabs: two over a narrow void (one Roll), two + a landing + two over a wide one; a small key on the far side |
| B2 the hub | the door with two keyholes (north) |
| B1 | the winch, the drawbridge over the void, the big chest (the big key), the boss door (north) |
| B0 | the boss room: a room fight with a boss (a Big Squint, `dungeon-lab-boss`: the Dungeon node's `boss_id`) behind its shutter; his full heart (`object.full-heart`); sealed, he shows his rage, and his fall breaks the seal |
| A2 dark | the shadow path over the void to an islet, a glinting chest with the compass |
| A3 | slabs and a landing over a spike pit with a stair out; the bolted door back into the entrance; a worm that is back each time the room is entered again |

Three small keys open three keyholes, in any order. The dark room's shadow path shows in the
slime's ember light once the Lantern is learned. The lab's Dungeon node writes no resume save
(`resume_saves` off): Continue never starts in the lab. `?keys=3&bigkey&dmap` skips the hunt.
**The sealed example:** from the hub B2 east into C2's top and north into C1; beat the guard, take
the Pearl: the roar, the glimpse of B3's seal slamming shut; B3's way out now refuses; beat the Big
Squint in B0 (the big key and the boss door, as before): the seal sinks. `?map=dungeon-lab&sealed`
starts sealed.

## Numbers (`game-constants.json` `dungeon`)

| Key | Value | What |
|---|---|---|
| `door.keyholeMs`, `door.openMs`, `door.lineEveryMs` | 380, 650, 1500 | a padlock dropping; the shut door rising away; a refusal line at most this often |
| `bolt.slideMs` | 420 | the bolt sliding back before the door opens |
| `shutter.moveMs`, `shutter.insetPx`, `shutter.openDelayMs` | 260, 80, 600 | a shutter rising or sinking; how far inside the room (and from its shutters) a fight starts; the pause before they open |
| `winch.turnMs`, `winch.reachPx` | 900, 8 | how long to push a winch; its push reach |
| `drawbridge.lowerMs`, `shakeMs`, `shakeIntensity` | 650, 240, 0.006 | the bridge coming down and its thud |
| `boltHole.clearPx`, `minOpenMs`, `closeAfterMs`, `shakeMs`, `shakeIntensity` | 72, 350, 2500, 160, 0.004 | the Lair's bolt-hole hatch: how far the slime walks off (and how long the hatch shows open at least) before it slams shut, the longest it stays open, the slam's shake |
| `void.damage`, `void.fallMs` | 10, 600 | a fall's cost and length |
| `spikes.damage`, `spikes.fallMs`; `lava.damage`, `lava.fallMs` | 10, 320; 10, 320 | a hit each time the invulnerability ends; the drop into the pit |
| `slab.fallDelayMs`, `dropMs`, `returnMs`, `riseMs`, `shakePx` | 300, 380, 10000, 450, 2.5 | the slab's timing (above) |
| `refill.flowerEnergy`, `flowerRegrowMs`, `flowerReachPx` | 25, 20000, 30 | the energy flower |
| `refill.heartHp`, `potEnergy`, `potCoins`, `pickupRadiusPx` | 20, 15, 5, 22 | what a pot hides; the pickups' reach (and the floor key's) |
| `shadowPath.fadePx` | 48 | the moss fading at a light's edge |
| `glint.periodMs`, `glint.sizePx` | 1700, 16 | the glint's twinkle |
| `seal.glimpseDelayMs`, `glimpseMs`, `glimpseSlamMs` | 600, 1500, 350 | the take: the roar to the glimpse; the glimpse's length; its slam into it |
| `seal.roarShakeMs`, `roarShakeIntensity`, `roarDust`; `slamShakeMs`, `slamShakeIntensity` | 700, 0.012, 140; 420, 0.01 | the roar's shake and its dust motes; the seal's slam |
| `seal.breakDelayMs`, `pulseMs`, `lineEveryMs` | 900, 1300, 1500 | the seals breaking after his fall; the ring's heartbeat; the refusal line at most this often |
| `seal.distantRoarMinMs`, `MaxMs`, `Db`, `Pitch`; `distantShakeMs`, `distantShakeIntensity`, `distantDust` | 45000, 60000, -14, 0.85; 320, 0.0025, 14 | the far-off roar while sealed |
| `enraged.pulseMs`, `strength`, `puffEveryMs`, `puffRisePx` | 1600, 0.45, 900, 110 | the boss's rage: the red pulse over his art, the puffs from his top |

## Art

Magnific GPT 2.5 (`gpt-2-mini`, transparent background, the Lili creation as style reference),
2026-10-17, 16 generations (1,600 credits; the spike tile and the big chest were taken twice).
Sources in `asset/Originals/dungeon-kit/generated/`, packed at 2 px a unit by
`python scripts/art/pack-dungeon-art.py` into `godot/asset/MAPS/objects/dungeon/` (`door-2x1`,
`boss-door-2x1`: shut and open, the open doorway cut see-through so the floor and the slime show
through the arch; `padlock-2x1`, `bolt-2x1`, `winch-2x1`, `shutter`, `drawbridge-down`,
`drawbridge-up`, `slab-2x1`, `spikes` (made seamless), `glow-moss`, `big-chest-2x1`,
`pickups-2x2`: the flower, its bud, the heart, the coins) and `godot/asset/UI/items/dungeon-items.webp`.
The pictures load through `game/runtime/sheet_sprite.gd` until the editor imports them. No bars,
eyes or levers anywhere (the clarity rule: those are the Spear's).

**The seal** (2026-10-17, the same model and style reference, 4 generations, 400 credits: two
blocks, two rings; one of each taken): `dungeon-seal.png` (the block with the dark pearl) and
`seal-ring.png` (a ring of white light, tinted in the game) in `asset/Originals/dungeon-kit/generated/`,
packed by `python scripts/art/pack-dungeon-seal-art.py` into `dungeon-seal.webp` (136 units wide, as
the shutter) and `seal-ring.webp`; the packer prints where the pearl sits, the scene's `Ring` node
numbers.

## Limits

- Elevation passages: the decks open theirs over holes (lower ground), which works in a world built
  from its painting and in one loaded from its baked cache (a cache bug that broke it was fixed on
  2026-10-17: `test_passages_open_in_a_world_loaded_from_its_elevation_cache`). A passage through a
  side-walls cliff face (a blown cracked wall) opens the drawn walls too, for walking and collision
  (fixed the same day: `test_a_passage_through_a_face_opens_the_drawn_wall`, ELEVATION.md).
- After rebuilding the lab, rebake it: `tools/bake_elevation.gd -- --world=dungeon-lab`.
- After repacking the art, import it (the editor, or a headless `--import`): the game reads the
  imported picture when there is one, and a stale import shows the old art.
- A door, a shutter or a bolt in an east, west or south wall shows the front art turned (foreshortened
  in a side wall); no side or back views are drawn, so a bolted door in a side wall shows its bolt
  from both rooms. *As built (2026-11-22): that holds in the cliff-walled Hollow and Mine; in rooms
  with interior walls (Fatty's Lair's) every opening is the north piece turned and a
  bolted door's far side shows the plain shut slab (`bolt_here` off: [INTERIOR_WALLS.md](INTERIOR_WALLS.md)).*
- The void watches the player only for walking: enemies do not walk in (they keep to their wander
  areas and do not drop off rims). An enemy a blow knocks or throws over a void's rim dies falling,
  one knocked into spikes or lava is hurt on the slime's rhythm until it is out or dead (owner,
  2026-11-16: [THROW_COMBAT.md](THROW_COMBAT.md#knocked-enemies-and-the-ground-2026-11-16)).
- Rooms reset only within one world: a dungeon of several worlds rebuilds a world on each travel
  (all its enemies and pots back), as any world does.
- The map shows the rooms of the world the slime is in (the Hollow: its floor). *Since 2026-10-19
  a dungeon of one world per room (Fatty's Lair) draws every room of its layout instead
  ([Keys and the map](#keys-and-the-map)).*
- **The seal:** a seal in a south doorway shows the turned block (as every kit piece there); at a
  world's south edge (the lab's B3, most entrances) half of it lies under the HUD console. The
  dungeon's music does not carry the boss's drums while sealed (the plan's open point 4: only the
  far-off roar is built). *Since 2026-11-19 the journal's main quest shows the Pearl slots, and the
  take's flag `pearl.<id>` marks its slot won (▶) until the Pearl is home
  ([quests spec 14.7](specs/quests.md#147-the-journal-tips-and-the-pearl-slots)).* The boss bar shows only for bosses with a camp (Fatty, the Matron,
  the Colossus), not for a room-fight boss such as the lab's Big Squint. The first travel refused
  while sealed reads its target world's scene once (a short hitch).
- **Music (2026-10-18):** every dungeon world (each room world of Fatty's Lair, the Weaver Hollow
  and the Crystal Mine) has a `MusicPlayer` playing `asset/audio/music/dungeon.wav` (volume 0.5); a
  travel between two worlds keeps the track's place (it dips with the leave fade and fades back in);
  a room-to-room scroll keeps it playing. Every boss fight
  with a camp crossfades to `audio.global`'s `BossMusic`, `boss-fight.wav`
  ([audio spec §1.2](specs/audio.md#12-authored-audio)).

## The Crystal Mine (built)

Chapter 3's dungeon, from [its design](../design/2026-10-16-dungeon-crystal-caverns.md), reworked for
the Pearl inside it before the Colossus ([the plan](../design/2026-10-17-pearl-mid-dungeon.md#the-crystal-mine-chapter-3-the-feral-skin)).
Since 2026-11-25 (step 4 of [the dungeons rework](../design/2026-11-23-dungeons-2-3-rework.md#the-crystal-mine))
it is **one world per room**: 15 room worlds in `godot/game/scenes/worlds/rooms/crystal-mine-rooms/`
(`crystal-mine-m1-mine-mouth` to `crystal-mine-m15-colossus-arena`, each `world.<id>` in
`scene_index.json`) with the crystal-cave interior walls, as [Fatty's Lair](#fattys-lair-built) and
[the Weaver Hollow](#the-weaver-hollow-built) are built, one dungeon record (`crystal-mine`). The
four wings below say what each room holds. Its code is `godot/game/crystal_mine/` and the Colossus's
`game/scripts/crystal_colossus.gd`; its art `scripts/art/pack-mine-art.py` (sources and prompts in
`asset/Originals/mine/`). Tests: `godot/tests/test_crystal_mine.gd` and `test_mine_camp.gd`.
*From 2026-10-17 until the rebuild the Mine was one world, `crystal-mine` (80 x 70 tiles, 14 camera
rooms, written by `tools/build_crystal_mine.gd`); step 5 retired it on 2026-11-25 with its builder
and its unused room copies, and a save standing in it wakes in M1
([the switch-over](#the-switch-over-the-mine-2026-11-25)). What it was:
[the archive](../archive/2026-11-25-old-hollow-and-mine.md#the-crystal-mine-as-one-world-2026-10-17-to-2026-11-25).*

**Its shape** (the plan's dungeon template): the first half uses what the slime brings and is the
Lantern's (six dark rooms, the maze), the Heavy Roll's and the Bow's (the Chasm, its last lock); the
Shardback guards **Pearl 3** in his Den; its take seals the mine; the second half teaches the
**Feral skin** (teach, test, twist, then the known way down); the Colossus is its exam.

### The Crystal Mine rebuilt: wing 1, the Mouth and the High Line (step 4, 2026-11-25)

Step 4 of [the dungeons rework](../design/2026-11-23-dungeons-2-3-rework.md#the-crystal-mine): the
Crystal Mine rebuilt as **one world per room** with the crystal-cave interior walls, as the Weaver
Hollow was ([its rooms](#the-weaver-hollow-rebuilt-the-trunk-and-the-roots-step-3-2026-11-25)), built
**beside** the one-scene Mine of the time a wing at a time; the
game enters it since the switch-over after the last wing, and step 5 retired the old world
([below](#the-switch-over-the-mine-2026-11-25)). Four wings, each walked and reviewed alone; the wings, every room's links and the engine pieces
still to build: [the handover's "Step 4: the Mine"](../handover/2026-11-23-dungeons-rework.md#step-4-the-mine).
Wing 1 is built:

| Room | World | What is there |
|---|---|---|
| M1 the Mine Mouth | `crystal-mine-m1-mine-mouth` | the way in (south, the seal's doorway; out to G4 `camp-mine-mouth`), the travel cart's station (its line to the Chasm is wing 2's), the rail gate in the east doorway (shut, its rails running under it), the runaway cart's buffer stop on this side; the S5 shelf (L1) with its chest, vines up its face (Feral) |
| M2 the Lamp Tunnel | `crystal-mine-m2-lamp-tunnel` | dark: rails north-south, two voids west of them, three lamps that light it for good (`crystal-mine.lamp-tunnel-lit`); west to the Tally Room (wing 2) |
| M4 the Great Shaft (2 x 1) | `crystal-mine-m4-great-shaft` | the gallery round the shaft (a void); north the Foreman's Gate (two keyholes, the old Mine's `foremans-gate`); key 2's chest on the high ledge (L1) in the south-east corner, in sight from the gallery, reached only by the High Line; the west shelf (L1, vines: the Feral secret of wings 2-3); since wing 4 the ore lift's upper landing on the shaft's north lip (below, "Wing 4") |
| M6 the Bat Gallery (2 x 1) | `crystal-mine-m6-bat-gallery` | dark: the rails to the rotten timbers (a Heavy Roll; the old Mine's flag `crystal-mine.rotten-timbers`, on both sides), two Glint Bats, two lamps (`crystal-mine.bat-gallery-lit`); the high walk (L1, crystal floor) along the north and east walls with two Glint Bats on it; S3 (Silk): a chest behind a web wall in a corner walled off by crates (below, "The wing's polish") |
| M7 the Ore Store (2 x 1) | `crystal-mine-m7-ore-store` | **the cart's teach:** a loaded cart held at the top of its line, the brake's knock target straight above it, pots beside the target; thrown at, the cart runs west, bursts the rail gate in the west doorway and rolls on into M1 (the short way back, for good); the Bone Leaper; the crate loft (L1, boards) with the Pick Mole behind his crates, its front stair the only way up, its north doorway the High Line's start |

- **The scenes** are `godot/game/scenes/worlds/rooms/crystal-mine-rooms/<room>.tscn` (`world.<id>` in
  `scene_index.json`; the old world's dead copies `rooms/crystal-mine/M*.tscn` went at step 5), their
  map `layout.tscn` (one floor, the old world's 5 x 5 grid at 1152 x
  1024 a screen), their Dungeon node an instance of `game/scenes/objects/dungeon/crystal-mine-dungeon.tscn`
  (`dungeon_id` and `record_map_id` `crystal-mine`, the old world's id; the entrance M1; the
  Colossus's seal settings as they were). `tools/build_crystal_mine_rooms.gd` wrote their first version (`-- --room=<name>[,...] |
  --all [--layout] [--force]`); **from now on the scenes are edited by hand** and the tool refuses to
  overwrite one without `--force`. Bake a room after painting its `elevation`
  (`tools/bake_elevation.gd -- --world=crystal-mine-<room>`).
- **Running it:** `?map=crystal-mine-m1-mine-mouth` (or any room's world; F6 on a room scene): the run
  gets the Mine's powers (`dungeon.devPowers.crystal-mine`, read for every room world of the dungeon).
- **The way through:** M1 north to M2 (light its lamps), M4 (the Foreman's Gate holds; key 2 glints on
  the ledge out of reach), south into M6's floor (dark; its walk out of reach), a Heavy Roll through the
  timbers into M7: a pot at the brake's target lets the cart go, it bursts the rail gate into M1. The
  High Line: up the loft's stair, its north doorway onto M6's high walk (L1, the bats on it, a drop off
  its edge), along it to its north doorway onto M4's ledge: **key 2**; a drop off the ledge onto the
  gallery, unhurt. Key 2 opens one of the Foreman's Gate's two locks (key 1 is the Tally Room's,
  wing 2).
- **Floors:** the cavern floor painted on the `ground` layer (the walls' own floor off), crystal floor
  patches with their edges, gravel under the rails, crystal floor on the raised walks (M1's shelf, M4's
  ledge and shelf, M6's high walk), boards on M7's loft. One floor trim in every room: crystal studs in
  crystal blue (`crystal-crystal`). The voids draw their depth with `pit_depth.gd` (below, "The wing's
  polish").
- **The crystal cave's door leaves** (key doors, the seal, the barricade, the boss door, the shutter,
  the bolted door) are the cave rock's ([INTERIOR_WALLS.md](INTERIOR_WALLS.md#crystal-cave)).
- **Dressing:** ore heaps and baskets, lumber, tools, crates, barrels and sacks, standing
  ore carts, crystal clusters with soft glows, mine lanterns on the lit rooms' north walls, cave
  animals that move (a crystal snail, moths, glow worms, pill bugs, a newt, a firefly). Nothing on a
  rail line, the cart's line or between the target and where the slime throws from.
- **Films:** `tools/film_crystal_mine_rooms.gd` (windowed): `--film=walk` plays the built wings from M1 with a
  check a step (a picture each and `walk.json`; PASS or FAIL); `--film=cart` films the teach frame by
  frame (the Spear refused at the target, a pot thrown, the brake, the run, the gate burst, the cart
  gone; `film.json` for `scripts/godot/mechanism-film-sheet.py`) and stills of M7 and M1 after;
  `--film=look --world=<room> --at=<x>,<y> --zoom=<z> [--slime=<x>,<y>] [--lit] [--bright]` a still of
  a room in the game (`--lit` lights its lamps, `--bright` hides the darkness of a room that stays dark);
  since wing 2 `--film=walk` plays both wings (`--from=wing2`: wing 2 alone, key 2 given) and
  `--film=ride` films the travel cart from the Chasm to the Mouth; since wing 4 it plays all four wings
  from the camp in G4 (below, "Wing 4"). Enemies are calmed and health kept full (the walk proves the way,
  not a fight).
- **Switched over** (2026-11-25, [below](#the-switch-over-the-mine-2026-11-25)); the old world and its
  copies retired at step 5. Tests: `test_crystal_mine.gd` (rewritten for the rooms at step 5, not run
  yet); not played with a keyboard.

### The wing's polish (the reviewer's five points, 2026-11-25)

- **The voids read deep:** `game/dungeon/pit_depth.gd` (`PitDepth`, presentation only) lies over each
  hole (M2's two pits, M4's shaft, M8's void, M9's chasm), right after the `ground` layer in the tree at
  z -2, so the room's own faces round the hole draw over it: from their foot the dark falls off
  smoothly to black (the far wall seen a little further down), dust motes drift down and fade as they
  sink, faint crystal glints twinkle deep down; it can also hang ropes from the far rim (`cables`, unused
  until the lift). The void's hazard keeps catching and putting the slime back; its own flat abyss is
  off (`draw_look`).
- **M4's shaft is painted** (the owner's yes to the credits, 2026-11-25): one GPT 2.5 still of the
  shaft's inside (timber cribbing, a ladder and two lift ropes, crystal veins in the slate, going down
  into the dark; source `asset/Originals/dungeon-kit/pits/mine-shaft-a.png`, stripped), packed by
  `tools/pack_pit_picture.gd` into `godot/asset/MAPS/interiors/mine-shaft.res` (a texture resource:
  no import). `PitDepth`'s `picture` draws it from the faces' inner edge (`picture_margins`), cropped
  about its middle to the hole's shape; the dark over it reaches only `picture_dark` (0.55), and the
  dust and glints move over both.
- **The natural holes are painted** too (2026-11-25): M9's chasm (`mine-chasm.res`, a rock rift of
  slate ledges and crystal veins) and M8's void and M2's two pits (`mine-pit.res`, a square pit, cropped
  about its middle to each), packed whole by `tools/pack_pit_picture.gd` from
  `asset/Originals/dungeon-kit/pits/` (its README: the sources, prompts and crops), the dust and
  glints over them as over the shaft.
- **The Mine's dressing** (2026-11-25, the dungeon decor set's `mine-*` props, PROPS.md "Dungeon
  decor"): M14, the shaft's foot, has a ladder's foot against the north wall, a lift gantry straddling
  the lift's landing and a pit-prop frame by the boss door, as M4's painted shaft shows them above (its
  second wall lantern went where the ladder stands); M1 a lantern post by the mouth and a stack of
  spare props; M5 a pickaxe and shovel by a crate; M10 a tipped ore cart; M11 fallen slate on the
  rift's floor, off its crossing. None stands in a doorway, on a line, in a throw's lane or a climb.
  (The plain wall planks, `interior-structure-beam-wood*`, are still gone: they never read as pit
  props.)
- **S3:** the Silk lock is a web wall (the only Silk lock there is), now across a three-row nook walled
  off by crates, clear of the floor trim's row (a barrel closes the row under it); its prize is a chest
  in the Mine's look (`crystal-mine-M6-S3-chest`: 30 coins, an energy potion) where the one-scene Mine had a
  silk parcel, shown only to a save that never freed that parcel (a StoryVariant on its flag), so the
  prize is never had twice.
- **The burst rail gate leaves its whole doorway open:** `rail_gate.gd` `posts_solid_when_smashed`
  (on by default: the lab's gate as before) is off on the Mine's two gates, which stand in side
  doorways whose jambs already block beside the passage; smashed, their posts stand but no longer
  narrow the passage. The walk crosses it off the rails, near either edge of the doorway.
- **Doors into rooms not built yet** never load a world: a room door whose room is not on the layout
  has no target world, and `door.gd` never travels without one (an arrival point only); the slime
  stops in the passage inside the room. After wing 2 only M9's south doorway (to the Den, wing 3) is
  such a door; the walk pushes into it and checks the slime stays in M9, inside its bounds.

### Wing 2, the Lantern's half (2026-11-25)

The Mine's first half's west and north: four more room worlds in `rooms/crystal-mine-rooms/`, on the
layout with wing 1's.

| Room | World | What is there |
|---|---|---|
| M5 the Tally Room | `crystal-mine-m5-tally-room` | dark for good (no lamps): four crystal pillars, the tally desk, a Gloomling sitting on key 1 (the old Mine's floor key `tally-k1`; light drives it off); the cracked north wall (the Goo Bomb, the old Mine's flag `crystal-mine.survey-wall`, on both sides) to the Survey Office |
| M3 the Survey Office | `crystal-mine-m3-survey-office` | lit: the map chest (the old Mine's record) by the surveyor's table, a Crystal Crawler round its pillar; the shelf (L1) along the north wall, out of reach from the floor: from the hub's west shelf (east doorway, the Feral secret) to a doorway north onto the maze's west wall |
| M8 the Dark Maze (2 x 2) | `crystal-mine-m8-dark-maze` | dark: its inner walls raised (L1, two cells thick, crystal tops): the north wall, the west wall down to the south rim, the east wall, the goal's enclosure; lines of crystal clusters (one cell, the `crystal walls` props at 1.25, whose collision then closes each cell to the slime) part its floor into branches and dead ends, something in every dead end (S4's chest, pots, an ore heap, a Gloomling); four candles (`burn_ms` 90 s, group `dark-maze`), each at the end of its own branch, lit at once open the exit gate (`dark-maze-exit`, the old Mine's) for good; each lifts a share of the maze's dark while it burns (half with the first, DARKNESS.md "A share of the room per candle"); the goal's brazier beyond it; the void across the middle and the shadow path over it; a Gloomling on the north-west candle, another on S4's chest (the old Mine's record); three Glint Bats; a pot. **S1's chest** (the old Mine's record `crystal-mine-M4-S1-chest`: 50 coins and the belt slot) stands on the north wall's east end, glinting over the maze: reached only along the wall tops from the Survey Office's shelf (the Feral skin, after Pearl 3) |
| M9 the Chasm | `crystal-mine-m9-the-chasm` | lit: the chasm (a void) wall to wall; the plank drawbridge raised on the far rim, the crystal lens beside it (`chasm-bridge`, the old Mine's): the Bow's arrow lowers it for good; the Bone Thrower on the far rim; the south doorway down to the Shardback's Den (wing 3); the travel cart's station, where the cart starts |

- **The way:** from the Lamp Tunnel west into the Tally Room (the Lantern's ember keeps the Gloomling
  off; key 1 where it sat; a Goo Bomb on the north crack: the Survey Office and the map), back to the
  hub, keys 1 and 2 in the Foreman's Gate, the Dark Maze (its four candles lit with the Lantern within
  their 90 s: in the best order, south-east, north-east, north-west, south-west, 128 cells of walking
  from the first flame to the last (45.5 s at the slime's 180 units a second, the faces' footprint
  counted as whole cells) and about 50 s with the north-west Gloomling driven off and four flames; the
  walk lights them by walking in 49.8 s; the exit gate opens for good), the
  enclosure's east doorway into the Chasm (the Bow's arrow over the chasm into the lens: the bridge
  comes down). The first half ends at the Chasm's far rim (the Den, wing 3).
- **The travel cart between worlds** (`mine_cart.gd` `partner_world`, `partner_station`,
  `partner_door`): the Chasm's station and the Mine Mouth's are each in their own world; the interact
  key at the station that holds the cart rides it to the other world as a door does (a fade), the slime
  coming out at the arrival point beside that station (`m1-cart-arrival`, `m9-cart-arrival`); which
  station holds it is kept under the dungeon's record (`crystal-mine`), so both worlds, as the one-scene
  Mine did, read the same answer. A line whose other world is not in `scene_index.json` does not
  ride. Off (no `partner_world`), a line rides inside one world as before.
- **The wall tops** (the Feral secret, after Pearl 3): the vines up the hub's west shelf's face, its
  west doorway onto the Survey Office's shelf, the shelf's north doorway onto the maze's west wall, its
  top north and the north wall's top east to S1's chest; a drop off the west wall's side lands on the
  maze's floor (a drop south off the north wall lands in the void: one row lies between them). The walk
  plays it after Pearl 3 (wing 3), with the skin the route gave.
- **Faces in the maze:** a raised wall's front face fills the cell south of it and its side and back
  faces about half the cells beside and north of it, and the void keeps a rim on the floor round it
  (ELEVATION.md "Faces in rooms"): the maze's corridors are laid with those cells counted as blocked
  (the void cols 14-21 x rows 14-22).
- **The crystal cave's cracked wall and blown hole** are made from its plain frame
  ([INTERIOR_WALLS.md](INTERIOR_WALLS.md#crystal-cave)).

### Wing 3, the Den and the Feral half (2026-11-25)

The Pearl room and the Feral skin's three rooms: four more room worlds in `rooms/crystal-mine-rooms/`,
on the layout with wings 1 and 2's.

| Room | World | What is there |
|---|---|---|
| M13 Shardback's Den | `crystal-mine-m13-shardback-den` | dark (each of its two braziers lifts its share of the dark while it burns, both light it: DARKNESS.md). The Shardback's fight (`room-fight`, once, `boss_id` `crystal-mine-shardback`, the old Mine's): the north shutter (`shardback-den`) shuts behind the slime from the Chasm; won, it opens and the broken south rim's shutter (`den-ledge`, `starts_shut`, the fight's reward) sinks for good. **The cart line** across the Den's south part (row 12.6): the loaded cart held at the west end (it is hauled back after each run, `returns`), its knock target past the line's east end in its line, the rope along the rails (as the Hollow's B5), no buffer stop (it would catch the throw), two braziers north of the rails (20 s, his slam puts the nearest out); two pots by the target, and his slams knock crystal chunks loose for more. **Pearl 3** (the Feral skin; its take seals the mine) rises on its cradle of crystal when he falls, its glint seen from the doorway through the fight (`CrystalMine` node: the glint goes once it is taken). The ledge (L1) in the north-east holds the east door to M11; vines up its face (the teach) |
| M11 the Crystal Veil | `crystal-mine-m11-crystal-veil` | dark (lit while the veil's brazier burns: DARKNESS.md). The test: two landings (L1) along the north, the Den's door on the west one, the Fort Hall's on the east one; the rift (L0) between them and along the south; vines down and up each landing's face. The optional Lantern wing: the crystal veil across the east landing's north doorway, open while the brazier on the landing burns (20 s); two Glint Bats; a pot |
| M10 the Prism Gallery | `crystal-mine-m10-prism-gallery` | lit: the Prism Eye (invulnerable), the iron-banded ore crate (a heavy block), the war journal's third page in its chest (the old Mine's record), the stone essence; a second veil on this side of the doorway, open while this room's brazier burns |
| M12 the Fort Hall | `crystal-mine-m12-fort-hall` | the old fort under the mountain: **fort stone walls** (the Lair's `lair-stone`, its `framed-cream` trim), cobble floors; lit. The balcony (L1) along the north wall with the big chest (the big key, the old Mine's record), two stretches of vines up its face; the Watcher Eye, the Bone Marcher on his loop past the vines' feet, five armour statues, two watch-fires; a drop off the balcony lands on the floor |

- **The way:** the Chasm's far rim south into the Den: his fight. Light a brazier with the Lantern,
  stand on the rails by the target: he plods toward the slime along them into the light (brittle,
  his shell glowing); a throw at the target lets the cart go and it strikes him from behind: his shell
  shatters, he falls (`shardback.gd`, BESTIARY.md row 28). Cold, the cart only clangs off and staggers
  him, and the counterweight hauls it back for another go. Pearl 3: the Feral skin, the mine sealed.
  Up the ledge's vines, east into the rift: down the west landing, across, up the east landing, into the
  Fort Hall: up the balcony's vines (when the eye looks away and the Marcher has passed), the big key, a
  drop to the floor. Optional: the veil (the landing's brazier), the Prism Gallery's chest, the veil on
  its side (its own brazier) back. Back across the rift, down the ledge, the broken rim: the way down
  to the shaft's floor (wing 4). The wall-top secret (S1) is open from here on (the skin is had).
- **The Shardback and the cart:** `on_mechanism_hit(&"cart", cart)` on him (`shardback.gd`, his numbers
  in `enemy-types.json`): brittle, `cartShatterDamage` (more than his health) and the shatter's burst
  and shake; cold, `cartColdDamage` and a stagger. His slam's crystal chunk (`slam_chunk_kind`) keeps
  the throws coming while the shutter holds the slime in.
- **Vines in rooms:** every climb of the wing (the Den's ledge, the rift's two landings, the Fort
  Hall's balcony, the hub's west shelf) is painted vines on the room's front faces, one level each
  (a room's face is one level), so none needs a balcony to rest on.
- **Films:** `tools/film_crystal_mine_rooms.gd --film=walk` plays all three wings from M1 (the Feral
  wall-top secret after Pearl 3, the walk ending at the sealed mouth); `--from=wing3` starts on the
  Chasm's far rim (the bridge let down by the tool); `--film=shardback` films his fight frame by frame
  (a cold clang, then the brittle blow and his fall; the Den's darkness hidden so the blow shows).

### Wing 4, the Shaft and the Colossus (2026-11-25)

The shaft's floor and the Colossus's arena: two more room worlds in `rooms/crystal-mine-rooms/`, on the
layout's floor -1.

| Room | World | What is there |
|---|---|---|
| M14 the Shaft Floor | `crystal-mine-m14-shaft-floor` | the bottom of the Great Shaft, lit, the calm room before him: north-east the foot of the Den's broken rim, a ledge (L1) the rim's doorway opens onto, roots (vines) down its face (Feral); north-west **the ore lift's lower landing**, its crank, straight below M4's upper landing on the map; north **the boss door** (the big key, the old Mine's `colossus-door`) into the arena's nook; the old Mine's three pots (two hearts, one energy) and its energy flower; under the shaft the ore, rubble and a crate that fell down it, a cold light from far above |
| M15 the Colossus's Arena | `crystal-mine-m15-colossus-arena` | **the Colossus lab's world carried over as it is** (`game/dev/bosses/colossus-lab.tscn`, [The Colossus lab](#the-colossus-lab)): its paint (crystal rock at level 3 round the cavern floor at -1, the north wall four courses high, the void dips), his arena node, the four roots, the three runaway carts and their targets, the four braziers, the fourteen pots and their loot, the dark (0.6), every one at the lab's own coordinates; the room adds the mine's pieces (below) |

- **Carried to the decimal:** `tools/build_crystal_mine_rooms.gd` loads the lab's scene and saves it as
  the room, so nothing is copied by hand: the arena at (832, 862) with `arena_rect` (64, 320, 1536,
  1024), `floor_rect` (192, 320, 1280, 1024), `wall_rect` (64, 64, 1536, 296), `post` (0, -40), the
  climb spots (640, 300) and (1024, 300), the carts, targets, braziers, roots, pots and dips where the
  lab has them. What the room changes: its name and world; the lab's Dungeon node and entrance marker
  go (the crystal mine's Dungeon stands where the lab's stood; the mine's entrance is M1); the lab's
  note goes; the nook (cols 12-13, rows 21-22) ends at a mine tunnel's mouth in the south rock
  (`m15-nook-tunnel`: the carts' tunnels' timber doorway, `mine-gate-leaves.webp`, laid as a south
  wall's mouth; 2026-11-25, before it was cut on to the room's edge, a bare gap), the room door
  `m15-south` in it (to M14's boss door; the slime comes out 96 units inside the nook); his camp's ids are the old Mine's
  (`crystal-mine-colossus`, `crystal-colossus`; the arena's defaults), his fight is once (`refights`
  off: his fall is recorded); `seal_cells` grow crystal over the nook's first row behind the slime while
  he lives; `climb_wall` is the climb out. His fight (`crystal_colossus.gd`, the arena script, the lab)
  is unchanged.
- **The climb out** (the old Mine's `M15-root-wall`'s numbers): roots up the north wall's east end at (1344,
  340), clear of his four claw roots and the east dip, to Crystal Caverns H4 (`lookout-from-mine`);
  sealed until he falls (climb_wall.gd refuses while the mine is sealed), the dungeon seal at its foot.
- **His full heart** (the old Mine's `crystal-colossus`, its flag `full-heart.crystal-colossus`) on the floor's
  middle north of the lower line, built as the room's own nodes (a Node2D, its picture, a
  `FullHeartScript` node), not an instance of `full-heart.tscn`: its values are not on an instance's
  inner node, which an editor save can drop.
- **The ore lift between worlds** (`ore_lift.gd` `partner_world`, `partner_door`; as the travel cart):
  the upper landing `m4-lift` on M4's north lip at (22, 4.4), the lower `m14-lift` at (4, 4.4) in M14,
  each naming the other world and the arrival point beside the other landing. It waits down, its crank
  below: from the gallery it is not offered ("The lift is down. Its crank is down there."); worked once
  from M14 it rides up, and from then on both ways. Its states (`ore-lift:great-shaft-lift`,
  `:working`) are kept under the dungeon's record `crystal-mine`, the old Mine's lift's id: an old save that
  worked the old Mine's lift finds this one working. M4's painted shaft and M14 agree on the lift's place: the
  upper landing stands under the painting's right-hand rope, the lower one straight below it.
- **The way:** after Pearl 3, the Den's rim (its shutter sunk by his fall) drops onto M14's ledge; the
  roots down (Feral). The boss door holds without the big key; the lift's crank rides up to the hub
  (the shortcut back). With the big key (M12), the boss door, the nook, his fight (the lab's crystal fight: a brazier
  lit, a cart bursts a shoulder's plate in its ring, the Spear destroys its crystal, twice; the roots,
  his claws, his chest's plate and crystal on his back); his fall sinks the
  seals (Pearl 3's: the mouth's, the climb out's), lights the braziers for good, raises his full heart
  and shows Release 1's end card (`chapter-3-complete`); the climb out to the Lookout.
- **Films:** the walk plays all four wings from the camp in G4 (its first step puts the slime through
  to M1's mouth, as the switch-over will route G4's door), his fight ended by the tool, the end card
  closed by it (in play "Return to title" saves and the run goes on), out by the climb to H4 and back
  out of the mouth to G4 (`--from=wing4`: wing 4 alone from M14). `tools/film_colossus_arena.gd` films
  his fight in M15 with `tools/film_colossus.gd`'s films and staging, only the world changed and the
  Feral skin lent (`scripts/godot/film-colossus.sh <name> --film=<film> --tool=film_colossus_arena`,
  into `output/dungeon-rework/mine/arena-films/<name>/`); burst, clang, wall, poses, phase1, phase2,
  phase3 and fight say PASS or FAIL.

### The switch-over (the Mine, 2026-11-25)

The owner's word given in advance ("make the switch when ready i will test and fix after"), made once
the reviewer passed wing 4: the game enters the rebuilt Mine. Step 5 retired the one-scene Mine
(`world.crystal-mine`) and its dead room copies (`rooms/crystal-mine/M*.tscn`) the same day
([the archive](../archive/2026-11-25-old-hollow-and-mine.md#the-crystal-mine-as-one-world-2026-10-17-to-2026-11-25)).

- **The way in and out:** G4's `exit-to-crystal-mine` (behind the mine's gate) leads to M1
  (`target_area_id` `crystal-mine-m1-mine-mouth`; `target_door_id` `mine-entrance`, the old world's
  door id); M1's way out (`mine-entrance`) lands at the camp (`camp-mine-mouth`); the climb out of M15
  lands at the Lookout (H4 `lookout-from-mine`) as it did. Nothing else in the open world leads into the
  Mine (the smith's cart ends in G4's yard), and no joined area copy holds G4.
  `tools/build_caverns_spiral.gd` writes the same target.
- **His fight:** the crystal fight (the plate fight until 2026-11-25), in M15 as in the lab; the old
  world's first fight went with it,
  its code too ([The Crystal Colossus](#the-crystal-colossus-roadmap-124)).
- **The names:** the world map (the Caverns' `interiors`, the dungeon marker's `map`), the area banner
  and the dev powers name the Mine by its record id `crystal-mine` (the old world's id too), so they
  hold for the rooms (one banner, "Crystal Mine", for every room: the shell names a room world by its
  record id). `?sealed` works in every room (`crystal-mine-dungeon.tscn`'s `dev_pearl_*`: Pearl 3, the
  Shardback, Feral), as `?map=crystal-mine-m14-shaft-floor&sealed`; `?map=crystal-mine` opened the old
  world until step 5.
- **Saves:** a save standing in the retired world loads into M1 at its entrance, inside (RunState
  `RETIRED_WORLDS`, one table of every retired world and where it leads, the Hollow's four floors and
  the Mine; `moved_world`; `load_slot` checks the moved world, so such a save loads although its world
  is gone); a record entrance naming it is forgotten (M1 records it again). The record `crystal-mine`
  is the same dungeon's, and the rooms keep the old world's ids (the keys, the Foreman's Gate's and
  the boss door's keyholes, the chests, the lift, the travel cart's stations, Pearl 3, both bosses, his
  full heart), so a half-played save goes on; the handover lists what carries over.
  `tools/film_crystal_mine_rooms.gd --film=old-save` writes such a save (sealed by Pearl 3, a key held,
  a lock open, the lift worked, the cart at the mouth) to the tool runs' own save folder and loads it:
  it wakes in M1 at its entrance and the rooms read its records.
- **The walk** starts at the camp: the gate holds, the Lantern lights its brazier, up through G4's door
  into M1; after his fall, out by the climb to the Lookout, round to the camp, in by the mouth again
  (its seal sunk) and out.

### The mine's own pieces (`game/crystal_mine/`)

- **Mine cart** (`mine_cart.gd`, `object` scene `mine-cart.tscn`): two stations of one line
  (`line_id`, `station_id`); the cart starts at `starts_with_cart` (the Chasm). The interact key at
  the station that holds it rides to the other (`mine_travel.gd`: a fade out, the slime and the
  camera there, its level taken, a fade in), and the cart moves there (RunState object state
  `mine-cart:<line>`). An empty station tells "The cart is at the far end of the line."
- **Ore lift** (`ore_lift.gd`, `ore-lift.tscn`): a lower and an upper landing. Worked from below
  ("Work the crank: ride up") it rides up and works from then on, both ways; from the gallery
  before that: "The lift is down. Its crank is down there." (object state `ore-lift:<id>`). Between
  two room worlds (`partner_world`, `partner_door`; the rebuilt Mine's M4 and M14, 2026-11-25) it rides
  as a door does and keeps its states under the dungeon's record ([Wing 4](#wing-4-the-shaft-and-the-colossus-2026-11-25)).
- **Crystal lens** (`crystal_lens.gd`, `crystal-lens.tscn`, `object.crystal-lens`): the Bow's
  target (`bow_targets`, `on_arrow_hit`); struck for good (DungeonState), it glows gold, opens the
  gates (group `gate`) named in `opens` and sets off every node in `targets` through the kit's
  `DungeonState.fire` (the drawbridges).
- **Crystal veil** (`crystal_veil.gd`, `object.crystal-veil`): smoky black crystal across a passage,
  `size` wide; open while any of its `braziers` burns, it grows back from both ends over `grow_ms`
  when the last goes out and pushes a slime standing in it to the nearer side; every hit clinks
  ("Cold, dark crystal. It shrinks from fire.").
- **Lantern gate** (`lantern_gate.gd`, `lantern-gate.tscn`): the mine's timber gate with two lamp
  cups, in the group `gate`: candles whose `gate_id` is its own open it for good (the Dark Maze's
  four, the camp's brazier); open, its cups burn and light the dark.
- **Rotten timbers** (`rotten-timbers.tscn`): Fatty's Lair's plank barricade (`plank_barricade.gd`)
  in the mine's look: only a Heavy Roll (any Roll with the Heavy skin: [SKINS.md](SKINS.md#heavy))
  smashes it; flag `crystal-mine.rotten-timbers`.
- **Heavy ore crate** (`heavy-ore-crate.tscn`): `heavy_block.gd` with the iron-banded crate.
- **Climbable walls** (`object.climb-wall`: `game/scripts/climb_wall.gd`, `climb-wall.tscn`): thick
  living roots and rocky handholds (the Feral skin's lock). With the Feral skin
  ([SKINS.md](SKINS.md#feral)) an interact press clings to it (a toggle since 2026-11-24: a second
  press lets go) and the movement keys climb it to `top` and back (since 2026-11-12; the held key
  alone climbed before), letting go drops the
  slime unhurt, the level is taken at the top. In the rebuilt Mine the climbs are painted vines (the `vines` layer,
  [SKINS.md](SKINS.md#painting-vines): M1's shelf, M4's west shelf, the Den's ledge, M11's faces, M12's
  balcony, M14's roots); placed climb walls stand only in M15: his four claw roots (`holds_at_top`:
  the climb ends on the face, the slime clings at his height until it lets go or moves away) and the
  climb out (`exit_area_id` `crystal-caverns-h4`, `exit_door` `lookout-from-mine`), which refuses
  while the mine is sealed.
- **The rails** (`mine_rails.gd`): drawn rails along `points` (the leading line), no collision.
- **The world script** (`crystal_mine.gd`, node `CrystalMine`): keeps each placed enemy to the
  camera room it stands in (its arena), so bats, eyes and Gloomlings fight in their own room.
- **The small golem** (`small_golem.gd`): the Colossus shrunk back once beaten; presentation only.

### The Crystal Colossus (roadmap 12.4)

`character.crystal-colossus` (`game/scenes/characters/crystal-colossus.tscn`,
`game/scripts/crystal_colossus.gd`, a patterned enemy; 180 health, three crystals of 60; his numbers in
`enemy-types.json` `crystal-colossus.pattern`; drawn by his look, `game/bosses/colossus_look.gd`,
[below](#the-crystal-fight-step-2-of-the-rework-three-crystals-since-2026-11-25): the scene still names the first fight's nine-pose
sheet, `godot/asset/MAPS/enemies/384x384-tile_9x1-crystal-colossus.webp`, which his look blanks). His arena is
`colossus_arena.gd` (node `ColossusArena` in M15 and in his lab), a boss camp for the HUD's boss bar
and the boss music, and the map's boss mark (`dungeon_map_mark`) until he falls. The slime arrives
with the Feral skin, the mine sealed: his fight starts enraged in look (`EnragedLook`, the seal's: his
strength the built one).

His fight is **the crystal fight** ([below](#the-crystal-fight-step-2-of-the-rework-three-crystals-since-2026-11-25)), his only one: the
plate fight of 2026-11-24 with his health moved into three crystals (2026-11-25). It grew out of the
fight first built for the one-scene Mine on 2026-10-17, whose own rules (a weak spot
cracked open while all four braziers burned, the climb after three stomps, every stomp putting a
brazier out) are in [the archive](../archive/2026-11-25-old-hollow-and-mine.md#the-colossuss-first-fight):
that fight went with the one-scene Mine on 2026-11-25, and its code went from `crystal_colossus.gd`
and `colossus_arena.gd` the same day (with the `plate_fight` switch that chose between the two, and
its numbers in `enemy-types.json`). What the crystal fight keeps of it:

- **The start:** the slime's centre in `arena_rect`: crystal grows over the way in behind it
  (`seal_cells`, the BreakGlass cue and a shake), the four braziers go cold, he stands at `post` and
  wakes after `wake_ms` (1200) with a roar. A slime at his wall's foot or on it (`wall_rect`) is in
  the fight too.
- **His stomp** (the tell: a foot raised for `raiseMs` 650 over a darkening ring `stompRx` x
  `stompRy` 116 x 78; within `stompRangePx` 120 of the slime or every `stompEveryMs` 2600): 40 damage
  in the ring. Which brazier it puts out, and when: his dousing (below).
- **On the wall, the Feral skin's exam (2026-10-17):** when the crystal fight says so ("The wall",
  below) he leaps onto the north wall at the climb spot nearest the slime (`climb_spots`) and
  clings there, throwing a Crystal Mite down every `throwEveryMs` (1300;
  `mitesPerClimb` 2, at most `maxMites` 4 alive; at a climbing slime the mite drops straight down the
  face onto it, `climberHitPx` 30, and its hit knocks the slime off: no cost but the hit). Roots run
  up the wall beside each spot. The slime climbs them to his height and strikes
  his gripping claws with the Spear from the face (the strike while clinging: an attack press aims
  the Spear left or right along the face, player.gd `_climb_strike`, at the Feral tempo); while he
  clings his hurtbox rides up the face with his pose and only a Spear hit from a climbing slime
  counts (no damage). **`clawHits` (3)** and he loses his grip: he crashes down from the wall over
  `fallMs` (450) across a cart's line (`fallDropPx` 70 out from the wall in an arena with no
  `crash_carts`) with no landing stomp (no brazier goes out), a hard shake, and lies on his back
  (`plateFallStunMs`: below). Then he gets up and fights on. If the slime does not reach him, he stays
  up there and comes down only to quake (his last phase, below; put up his wall before his last
  phase, as only a film can, he leaps down at the slime after `climbMs` 5200, a landing ring).
- **His rage** (from phase `rageFromPhase` 2, once a crystal is dead; until 2026-11-25 his "second
  phase", below half his health; not the Pearl's rage): a quicker walk and quicker stomps, more
  mites, quakes sooner, and while he douses a landing puts out two braziers. Chosen so the fight gets
  harder as his crystals die: phase 1 his calm pace, phase 2 the rage, phase 3 the rage and the wall's
  rocks (with 3 phase 2 would be as easy as phase 1).
- In the rework mode a killed mite can drop an energy shard (the generic `combat.energyShard` roll);
  the arena holds no other refill.
- **Fainting** or leaving the arena while he stands starts it over (he goes, the mites go, the
  braziers go out, the crystal over the way in goes).
- **His fall:** he joins `defeated_boss_ids` and the dungeon's beaten bosses, which breaks the seal
  ("The seals break!": M1's and the climb-out's seals sink); the soaked-up power gone, his heap sheds
  and a small calm crystal golem walks out of it and off (`small_golem.gd`, real time); the four
  braziers burn for good (the cavern is lit); his **full heart** (`object.full-heart`,
  `crystal-colossus`, +20 max HP and max energy) rises; the way in stays shut, so the way out is the
  climb up the roots of his wall's east end, to the Lookout (H4).

#### The crystal fight (step 2 of the rework, three crystals since 2026-11-25)

> **The three crystals (2026-11-25):** the owner, after playing the plate fight: "colossus have 3
> phases like the 3 crystals in his body, once a phase end is because we broke the crystal in his body
> starting from the 2 arms and finally the one in the chest while climbing. to simulate a broken
> crystal we can paint it dark" (the crystals under the plates). Built the same day, in the lab and
> in M15 at once (one script): his health moved from the plates into the three crystals, a cart's
> burst only bares one, one crystal a phase in a fixed order. Filmed (`poses`, `phase1`, `phase2`,
> `phase3`, `fight`, in both); tested by `test_crystal_mine.gd`; not played with a keyboard.
>
> **Status:** built 2026-11-24 in the Colossus lab, from [the plan](../design/2026-11-23-dungeons-2-3-rework.md#the-crystal-colossus)
> (the owner approved his new look and frames, then "Yes, build the fights"), with the owner's
> changes of the same day (a bigger room, void dips along its sides, carts out of tunnels that pass
> through, his kick). Since 2026-11-25 the lab's world is also the rebuilt Mine's M15
> ([Wing 4](#wing-4-the-shaft-and-the-colossus-2026-11-25)): the fight the game plays. Filmed in both
> (`scripts/godot/film-colossus.sh`), not played with a keyboard; tested in M15 by
> `test_crystal_mine.gd` since step 5 (its 19 passed on 2026-11-25, again after the first fight's
> code was taken out).

**His only fight:** the arena that makes him (`colossus_arena.gd`, M15's and the lab's) gives him its
braziers and its `crash_carts`. The `plate_fight` switch on both scripts, and the first fight it kept
([the archive](../archive/2026-11-25-old-hollow-and-mine.md#the-colossuss-first-fight)), were taken
out on 2026-11-25, the day the one-scene Mine went: everything below is how he fights.

- **His look** (`game/bosses/colossus_look.gd`, under the enemy's Visual, which draws nothing and
  carries the hit flash): his packed frames (`godot/asset/MAPS/enemies/bosses/colossus/`,
  `frames.json`; `scripts/art/boss_frames.py pack colossus`): the bare body (a crystal of rose quartz
  in each plate's socket) with each plate he still wears laid on it, cold (pale cyan) or hot (orange,
  pulsing); a plate gone shows its crystal, **live** (as drawn, pulsing brighter, a rose glow over
  the dark room's darkness: his health in sight) or **dead** (dark slate, cracked, no glow, for good).
  The dead pieces are made by the pack from the live ones (no generated art: the same pixels on a
  slate ramp, cracks drawn from the middle with one seed a crystal, so they hold still from frame to
  frame), packed in each animation's plate atlas beside the plates; every pose (the three walks, the
  raise, the stomp, the leap, the cling, the fall) shows them (film `poses`). He faces four ways, from his walk (a new way wins once it leads by a
  fifth): the walk toward the viewer, the side walk (mirrored for the left, its near shoulder piece
  then his left shoulder) and the walk away, a frame every 11 units walked. The stomp's raise, rear
  and slam, the stagger (the stomp sheet's fourth frame), the leap (crouch, then from behind), the
  cling (two grips, the second also his throw), the fall (off the wall, the crash in dust, then on his
  back, dazed). The stomp and the stagger are drawn facing the viewer only, so he turns to the viewer
  for them. A shadow lies under him. Plates: **L** his right shoulder, **C** his breastplate, **R**
  his left shoulder.
- **His health:** 180 (the scene's `max_health`, `maxHp` in the data: the number for the owner to tune
  when he plays) = three crystals of 60 (`crystal_share`, a third each): his health is what his
  crystals have left, and the boss bar shows it falling in thirds. **A phase is one crystal**, in a
  fixed order (`CRYSTAL_ORDER`, one constant to flip the shoulders): **L** (the shoulder on the screen's
  left as he faces the viewer, his right), then **R**, then **C** (his chest). Nothing hurts a plate;
  a cart's burst only bares its crystal (no harm); only Spear hits and thrown things on the bare
  crystal take its health, never more than it has left (each phase ends at its third): five Spear
  hits (12) a crystal, three of the Spear's Lunge (its Ability Box power, 25), ten thrown things.
- **Brittle:** only this phase's plate (`current_plate`, the one a cart takes) heats, so the one that
  glows is the one that goes: a shoulder plate with his feet within a lit brazier's ring (its light:
  `light_radius` round its flame, the lab's 150), or **while all four braziers burn, anywhere** (the
  owner, 2026-11-24: "when all 4 braziers are on make the plater brittler also"); the breastplate only
  on his back (below), never on the floor. One lit brazier is enough to make him brittle in its ring. The ring is the brazier's pool
  of light in the dark (the lab's dark room). The braziers are lit by the Lantern (its flame flies a
  short line from the slime's mouth: stand within about a cell of the brazier, facing it).
- **Heat cues** (the owner, the same day: so "the player knows something change"): as this phase's
  plate heats, a burst of embers off it, a flash and `FireIgnite`; while it glows, embers rise off it
  and the knock target of the cart line his feet stand on (within 90 of its rails, the cart held
  ready, the target armed) glows warm and pulses over the dark; as they cool, a puff of steam
  (`_step_heat`).
- **The clang hint:** the first time in a fight a cart clangs off a cold shoulder plate, `clang_hint_text`
  ("Too cold to crack. Heat it in a brazier's light!") shows over the slime for 6 s, following it,
  opaque, kept on screen (`GameFeel.hint_text`), and every unlit brazier flashes three times under a
  bobbing arrow, embers rising off it (`game/feel/hint_cue.gd`; the owner, 2026-11-24: the hint must
  stay long enough to read, and "the braziers need to flash 2 or 3 times ... many games do that";
  the rule: [GAME_GUIDELINES.md "Hints"](../GAME_GUIDELINES.md#hints)). The runaway cart has a getter
  for its target now (`ram_cart.gd` `get_knock_target()`).
- **His stomps put braziers out only while he douses** (the owner, 2026-11-24: the stomp put them
  out so often he never had them all lit; "it should only happen after all braziers are on and after
  colossus had receive damage, or a long period of time to allow time for the player to make
  mistakes"): hurt while every brazier burns (a plate's burst counts, though it costs him no health:
  `_harm`), he douses: each stomp (and a landing from his wall)
  puts out the lit brazier nearest him (`stompPutsOut`), until none burns. Else his stomps leave the
  braziers alone until `douseAfterMs` (45 s) has passed with no brazier lit or put out: the wait
  starts again at the fight's start and every time a brazier is lit or goes out (the owner: "that
  way the player have 45 seconds after lighting a brazier to make his move"); once it is over his
  next stomp puts one out, which starts the wait again (`_step_douse`, `is_dousing()`,
  `douse_wait_left()`).
- **His leap** (the owner, the same day: the fight felt slow, he "does not have a jump or a charge to
  follow you"): a slime more than `hopFarPx` (300) from him for `hopAfterMs` (1200) while he walks,
  and he crouches (`hopCrouchMs` 350, the leap's crouch, a ring on the floor where he will land),
  leaps (`hopAirMs` 650, the stomp's reared frame, an arc of `hopArcPx` 90; nothing reaches him and a
  cart passes under him) and lands `hopShortPx` (150) short of the slime, at most `hopMaxPx` (520) a
  leap, kept on his floor: the slam (`hopDamage` 20 to a slime in the ring, `hopKnockback` 300, a
  shake), no brazier out and no stomp counted, then he recovers as from a stomp. The first leap at
  the earliest `firstHopMs` (2500) after he wakes, the next `hopCooldownMs` (5000) after a landing.
- **His quake** (the owner, 2026-11-24: "the queke last 5 secodns and it make damage over time the
  way to avoid it is by climbing . a warning have to be issue by colossus so is clear that attack is
  coming"): `quakeFirstMs` (14 s) after he wakes, then `quakeEveryMs` (22 s, a third sooner while he
  rages) after each one starts, with the slime on the floor and climb walls up his wall
  (those within 260 of a climb spot). **The warning** (`quakeWarnMs` 2500): a roar and
  `GroundCreak`, he rears (the stomp's foot-and-fists-up frame, facing the viewer) and trembles harder
  and harder, the screen rumbling and dust falling, while glowing cracks run out from his feet over
  his whole floor and the climb walls light up (a light in the dark room and glowing specks on each:
  the safe place). **The quake** (`quakeMs` 5000): he pounds the floor every `quakePoundMs` (450;
  `ColossusStomp`, a shake, dust), the cracks glow and pulse, the floor glows, craters break open
  over it every `quakeCrackEveryMs` (280; `BreakStone` every other one); a slime on
  his floor takes `quakeTickDamage` (6) every `quakeTickMs` (600: longer than the slime's 500 ms of
  hit invulnerability), no knockback, about 50 over the whole quake; a slime climbing (or dropping
  off) a wall takes nothing. Then he recovers as from a stomp. A cart's blow stops it (he staggers).
  The look is `game/bosses/colossus_quake.gd`: painted fissures (`effects/colossus-quake-fissures-1x4.webp`)
  laid end to end along nine wandering rays from his feet, each growing from its near end as the
  crack spreads, a glowing copy of each pulsing while the floor shakes; painted craters
  (`effects/colossus-quake-craters-4x1.webp`) that pop in, lie a moment and fade; nothing drawn past
  his floor's edge (a clip by world position). The art: two Magnific stills (2026-11-24, 80 credits),
  `scripts/art/pack-quake-art.py`, sources in `asset/Originals/dungeon-kit/bosses/colossus/quake/`.
- **Falling rocks** (the owner, 2026-11-24: the pots run out; "colossus need to make rocks or
  cristals on every single attack they fall from the roof in ramdom spots making damage if they fall
  on you, thy never block the rails"): every stomp drops `debrisPerStomp` (2; a landing from his
  wall is a stomp), every leap's landing `debrisPerHop` (1), every `debrisEveryPounds`-th (2nd) pound
  of a quake one. Each falls on a random free spot of his floor: never within `debrisRailClearPx`
  (72) of a cart's line or in a ram's lane, `debrisClearOfHimPx` (110) of him, nor by a brazier, a
  knock target or another thing to throw (`debrisClearPx` 56). Its shadow grows there (Fatty's clod
  shadow) as the rock's picture falls into it from `debrisFallPx` (420) over `debrisFallMs` (750;
  each next one `debrisStaggerMs` 180 later; `game/bosses/colossus_debris.gd`); landing, a slime
  within `debrisHitPx` (34) takes `debrisDamage` (10, `debrisKnockback` 160), `DropLand`, dust and
  chips, and it lies there: a liftable of one of `debris_kinds` (ore rock, crystal cluster, geode)
  that lands as `debris_weight` (light: any Gulp lifts it, as the mud balls), nothing under it. At
  most `debrisMax` (8) lie at once; the oldest crumbles away (`get_debris()` lists them).
- **The cart** (the runaway cart, its hook `on_mechanism_hit(&"cart", cart)`) only ever strikes
  **this phase's plate, whichever side it meets him from** (the owner, 2026-11-25: the first two blows
  take the shoulders in order; the plate fight's side-of-impact choice is gone): a spark where it
  meets him, and a brittle plate **bursts** for good on its own shoulder: no harm (its crystal is
  bare), the eight hot shards of `shards.webp` flying the way the cart pushed, the crystal dust and a
  flash (`game/bosses/colossus_shards.gd`), his hurt flash, a roar and a shake; he staggers
  `burstStaggerMs` (1800). So a cart arriving on his dead shoulder's side in phase 2 sparks there and
  bursts the hot plate on the other shoulder (film `phase2`). A cold plate **clangs** (sparks, the
  plate flashes white) and he staggers `staggerMs` (1100). **This phase's plate already gone** (its
  crystal bare, still live): the cart clangs off his rock and staggers him, no harm, no hint: a free
  window to strike. The next shoulder's plate never goes early (one bare crystal at a time). The
  breastplate bursts only on his back; standing, a cart clangs off it (no heat hint: it cannot heat
  there). A stomp on the way is cut short (no brazier goes out).
- **His kick** (the owner, 2026-11-24): the cart that struck him waits against him; his feet back,
  furious (a roar), he turns to it, draws a foot back and kicks it (`kickMs` 760, the side walk's
  stride in profile, leaning in): it rolls back up its line into the tunnel it came from in
  `kickBackMs` (1200), fast at first; then the line is ready again. A cart that struck him as he lay
  he kicks as he gets up. If he falls or leaves the fight first, it rolls home slowly.
- **The bare crystal** (`_shields`, `_hit_meets`): a Spear hit on this phase's crystal, bare and
  **showing to the hitter**, hurts (`shapes.spear.baseDamage`, 12; the Lunge 25); a thrown thing
  (a pot, a rock, a stunned Crystal Mite) `thrownShare` (0.5) of one (6). A crystal shows where the
  art draws it (`SHOWS_FROM`): a shoulder's from his front, his back and its own side; the chest's from
  his front and both sides; on his back every one faces the sky. **A deliberate change** (2026-11-25)
  from the plate fight's rule, "a side whose plate is gone": he turns to face the slime as he walks,
  so a shoulder's side was almost never in reach outside his staggers. Every other hit clinks: the
  Spear's own clink (the router's refusal), a cyan spark off a plate or grey grit off a dead crystal
  or his rock; any other weapon, a blast, an arrow clink as before.
- **The clink's line** (one a phase, at its first clink): while this phase's crystal still wears its
  plate, `plated_hint_text` ("The plate holds. Crack it with a hot cart!") and the plate flashing under
  a bobbing arrow; once it is bare, `dead_hint_text` ("That crystal is dead. Strike the glowing one!")
  when the hit met a dead crystal, else `crystal_hint_text` ("Strike the glowing crystal!"), and the
  live crystal flashing under the arrow. The line stays 6 s over the slime, the arrow follows him
  (`game/feel/hint_cue.gd`, [GAME_GUIDELINES.md "Hints"](../GAME_GUIDELINES.md#hints)).
- **A crystal destroyed** (`crystal_broken`): rose shards burst from it (the burst's cold shards
  tinted), a roar, `ColossusShatter`, the burst's shake; it shows dead (dark, cracked) for good in
  every pose, and he staggers `crystalBreakStaggerMs` (1400: the beat). After L he walks on into
  phase 2; after R, once the stagger (and a kick) is over, he leaps up his wall (phase 3); the chest's
  is his fall.
- **His last phase: he lives on his wall** (both shoulder crystals dead, his chest's left; the owner,
  2026-11-24: "the last phase he stay on the vines and only comes down to do the quake them goes up
  again , he does not wander around confusing the player , so the player knows he have to climb and
  do something"): whenever he is on his feet (up from a fall, after a kick, a stagger or a quake) he
  leaps straight up his wall at the climb spot nearest the slime and stays there, no time limit
  (`_last_phase`). Up there his mites as before, and **every `wallRockEveryMs` (5 s; the first
  `wallRockFirstMs` 2 s after he is up) a rock at the slime** ("this rock can hit you even in the
  vines so you are not safe anywhere"): thrown from his hand in an arc over `wallRockFlightMs` (800)
  to where the slime is, its shadow growing there, `wallRockDamage` (10) to a slime within
  `wallRockHitPx` (40), on the floor or up the roots; on the floor (off the rails) it lies as a rock to
  throw (more ammo for the cart's target), on the wall or by the rails it shatters (`_throw_rock`,
  `ThrowToss`). He comes down only when his quake is due: he leaps to the middle of his floor (the
  landing a stomp), warns, quakes, and leaps back up. Film `last`: up at once; a rock hits the slime
  on the floor (10) and lies there; one hits it up the roots (10) and shatters; a quake due: down,
  quake (the slime on the roots unhurt), back up.
- **The wall** (his last phase): he leaps at once once the second shoulder crystal's stagger (and
  his kick) is over (and whenever he is on his feet, above); the climb, the mites and the claws are as above ("On the wall"). Struck loose, he
  crashes across the nearest line of the arena's `crash_carts` (his feet on its nearest point; the
  lab's run down the room right under his two climb spots, so he falls straight onto one) and lies
  on his back **`plateFallStunMs` (4000)** (the first fight's stun was 2500): the slime must drop from the roots,
  take a pot and throw at that line's target first. His breastplate shows hot there (the fall cracked
  it; standing, it never glows, so the floor's carts only clang off it and the Feral climb stays
  needed); the cart bursts it. While he lies the Spear and thrown things hurt his chest crystal from
  every side. **The chest crystal:** its hits rarely all fit in one stun after the cart's walk, so
  he usually gets up (kicking the cart home) and goes back up his wall; the next fall his chest is
  already bare and the Spear goes straight at it (film `phase3`: two strikes the first time, then the
  second fall). Its last hit is his fall for good: the chest goes dark with him, a last burst of cold
  shards, the fall frames, and the arena's small golem as built.
- **The roots as a refuge** (the owner, 2026-11-24: standing at the wall's foot under a climbing
  slime he left it no way down): while the slime climbs (engaged or not: a climbing slime is no
  target) he goes to the middle of his floor, by his leap when he is more than `retreatLeapPx` (140)
  from it and the leap is ready, else walking; no leap at the slime, no quake, his stomps on their own
  pace. Climbing to his wall's height when he is due to climb still brings him to the spot nearest
  the slime. Film `climb`: he stands under the west roots as the slime climbs; he leaps to the
  middle; Roll presses on the wall do nothing; letting go, the slime lands in front of the wall,
  unhurt.
- **Drawn in front of his wall** while he leaps up, clings, leaps down, falls off it or leaps on the
  floor (`UP_PHASES`, z 3): over the tunnel doorways (z 2, drawn over their carts) and the root
  climbs (the owner, 2026-11-24: he was "painted behind the doors while jumping and in the vines");
  on the floor at 0, sorted by his feet.
- **His hurtbox** follows the art: standing, his footprint and lower body (`plateHurtFront` 150 or
  `plateHurtSide` 110 wide by `plateHurtHeight` 110, its middle `plateHurtRise` 45 over his feet), so a
  cart meets him when his feet are about on its rails and stops with its front against him; lying,
  his length (`lyingHurtW` 180 x `lyingHurtH` 90).
- **Numbers** (`crystal-colossus.pattern`, new; `plateHp` and `phaseTwoShare` went with the plate
  fight on 2026-11-25, `crystalBreakStaggerMs` and `rageFromPhase` came with the crystals): `thrownShare`, `staggerMs`,
  `burstStaggerMs`, `burstShakeMs`/`burstShake`, `clangShakeMs`/`clangShake`, the hurtbox's six,
  `kickMs`, `kickBackMs`, `kickShakeMs`/`kickShake`, `plateFallStunMs`; the leap's `firstHopMs`,
  `hopFarPx`, `hopAfterMs`, `hopCooldownMs`, `hopCrouchMs`, `hopAirMs`, `hopArcPx`, `hopShortPx`,
  `hopMaxPx`, `hopDamage`, `hopKnockback`, `hopShakeMs`/`hopShake`, `afterHopStompMs`; `douseAfterMs`;
  the quake's `quakeFirstMs`, `quakeEveryMs`, `quakeWarnMs`, `quakeMs`, `quakeFirstTickMs`,
  `quakeTickMs`, `quakeTickDamage`, `quakePoundMs`, `quakeCrackEveryMs`, `quakeShakeMs`/`quakeShake`,
  `quakeRumble`, `afterQuakeStompMs`; the falling rocks' `debrisPerStomp`, `debrisPerHop`,
  `debrisEveryPounds`, `debrisFallMs`, `debrisStaggerMs`, `debrisFallPx`, `debrisHitPx`,
  `debrisDamage`, `debrisKnockback`, `debrisMax`, `debrisClearPx`, `debrisClearOfHimPx`,
  `debrisRailClearPx`.
  His reactions' state `hop` (in the air) is immune, as his other leaps.
- **Sounds** by name, silent until staged (Sound Picker round 16): `ColossusStomp` (the stomp, the
  crash, the kick), `ColossusRoar` (the wake, a burst, a crystal destroyed, the leap, the fury before
  a kick, the grip lost), `ColossusShatter` (a burst, a crystal destroyed, his fall), `ColossusClang`. The raise keeps `ColossusRaise`.

**The runaway cart for this fight** (`ram_cart.gd`, two additions): `through` makes a line run tunnel
to tunnel (its first and last points inside the walls; each mouth is the mine gate's open
doorway, `doorways/mine-gate-leaves.webp`, turned and foreshortened as the kit's side-wall doors,
drawn over the cart; in a north wall, opening down the screen, it stands whole, face on, and is
sorted with the wall by where it meets the floor, so what stands on the floor before it is drawn over
it and a cart inside the tunnel behind it (2026-11-24: the Colossus was drawn behind the top tunnels);
in the south wall it is turned over and foreshortened): held, the cart waits in its start tunnel (its brake is in there, where the
target's rope runs: no lever, chock, buffer or counterweight); let go it rolls the whole line, over
the void dips on its rails; meeting nothing it rolls on into the far tunnel and is gone (it fades
out), and `restMs` later the next comes out of the start tunnel (`APPEAR_MS`), its target rearmed. And
a kick: a node it stopped against may `hold_for_kick()` it (no haul back) and `kick_back(ms)` it home;
`let_go()` returns it to its haul back.

#### The Colossus lab

`game/dev/bosses/colossus-lab.tscn` (`world.colossus-lab`; dev only), `?map=colossus-lab` (web) or
`-- --map=colossus-lab` (desktop); F6 lends `dungeon.devPowers.colossus-lab` (the Spear, the Roll,
the Lantern, the Bow, the Goo Bomb, the Feral, Silk and Heavy skins). Built by
`"<Godot console exe>" --headless --path godot -s res://tools/build_colossus_lab.gd -- --force` (it
overwrites hand edits). Painted as the mine paints (crystal rock at level 3 round a cavern floor at
-1: the north wall four courses, the wall he climbs), 24 x 20 cells inside:

- **The north wall:** four root climbs beside his two climb spots (`holds_at_top`; three cells
  either side of the floor's middle, a root climb either side of each).
- **The void dips:** two cells wide down the west and east sides, from under the wall to the south
  wall (holes at -3, a `void` hazard over each): a fall costs `dungeon.void.damage` (10) and puts the
  slime back where it stepped off. They lie in the arena's `arena_rect` (the fight goes on) and out
  of its new `floor_rect` (his floor: where he walks, lands and drops his mites; empty, the arena).
- **The two down lines** (2026-11-24; they replaced an upper line across the room under the wall,
  which the owner never used: "the top ram make no sense ... remove it and put to verticals"): one
  under each climb spot, rolling south out of a tunnel in the north wall's foot, down the room (over
  the lower line's rails) into a tunnel in the south wall: his crash lines
  (`crash_carts`). Each one's target stands beside it, outward, about three cells below the wall,
  its rope in beside the rails and up along them into the tunnel; pots by it.
- **The lower line** across the arena's south half, rolling west; its target by the east dip; pots.
- **Four braziers** (`burn_ms` -1, `stomp_puts_out`, `light_radius` 150): one beside each down line,
  outward, below its target, and two south of the lower line; the hall is a dark room
  (`darkness_override` 0.6, no candles to light it for good), so each lit brazier's pool of light is
  its ring.
- **The arena** is the whole floor (16 rows; the owner, 2026-11-24: "the fight reset every time i
  wal to the bottom of the scene": the lobby was the floor's last two rows).
- **The lobby:** a nook two cells wide and deep cut into the south wall below the floor's middle,
  outside the arena (clear of the down lines' tunnels): the slime starts there; walking back into it
  starts the fight over. Four pots stand on the floor by it. The arena's `refights` is on: his fall
  is not recorded (boss id `colossus-lab`), the braziers are lit but not for good, and the next walk
  in starts a new fight.

`bash scripts/godot/film-colossus.sh <name> --film=<film>` films it frame by frame into
`output/boss-rework/colossus-films/<name>/` (`godot/tools/film_colossus.gd`; the mechanisms' lock,
one game window at a time; what each stages is in the tool's head; his strips and atlases are read
from disk, so a pack the editor has not imported yet still films as packed): `look`, `poses` (every
frame, five plate and crystal states, for checking the plates and crystals sit on him: PASS when every
bare crystal shows), `walks`, `glow` (the Lantern lights a
brazier, his first plate glows in its ring, his stomp leaves it lit), `hop` (his leap at a far slime,
twice), `heat` (one brazier lit: cold outside its ring, hot inside with the lower target glowing,
cold again; all four lit: hot far from every ring), `quake` (twice: the slime stays on the floor and is hurt, then climbs the roots in the
warning and is not), `rocks` (every pot taken away: his stomps drop rocks, none by the rails, one on
the slime hurts it, a thrown one trips the lower cart and it bursts his first plate), `douse` (all four lit, a burst, then his stomps put them out one by one; two relit restart
the long wait and survive a stomp; the wait staged as over, one goes out and the wait restarts, so
the next stomp leaves the other), `burst` and `clang` (his first plate, with his kick; `clang` shows
the hint), `pass` (a cart that meets nothing), `dip`, `wall` (the last phase: the crash on the west
down line, the cart bursting his breastplate), and the crystal fight's own, each with a PASS or FAIL:
`phase1` (from the wake: the first clink and its line, the Lantern, the cart bursts plate L, the kick,
crystal L struck until dark, phase 2), `phase2` (L dead, staged: turned north, the cart meets his dead
side and bursts plate R; R struck until dark; up his wall), `phase3` (both shoulders dead, staged: the
claws, the fall, the cart bursts the breastplate on his back, two strikes, he gets up and climbs again,
the second fall, the chest struck until dark, his fall for good) and `fight` (the three in a row,
nothing staged on his crystals or plates). The tool puts the slime where it strikes (his front, the
crystal's side or his back, by turns), and stages him only where the head says (on the line as the
pot leaves, turned north in phase 2). The films that stage him somewhere hold his stomps and his leap
(`_hold_stomps`). `bare` and `core` went with the plate fight.

**Limits of the crystal fight:**

- Played in M15 and the lab; neither played with a keyboard.
- The stomp and the stagger are drawn facing the viewer only: he turns to the viewer for them. In
  the stagger his raised fist hides most of his left shoulder (R), plate and crystal: the art's.
- The dead crystals are the live ones' pixels on a slate ramp with cracks drawn on (no painted
  frames): flat next to the hand-painted plates; a painted dead look is one GPT edit of each bare sheet
  if the owner wants it.
- The kick is the side walk's stride in profile (no kick frame was drawn); a cart up or down the
  screen gets the stomp's raise and lift (from the front) or the walk away (from behind), not filmed.
- The tunnel mouths are the mine gate's doorway turned on its side (no tunnel art was made); the
  rails cross the void dips on their sleepers, with no trestle under them.
- The down lines cross the lower line's rails: two carts rolling at once pass through each other at
  the crossing (no cart stops another).
- His leap's frames face the viewer (the leap's crouch, the stomp's reared frame, its slam) whichever
  way he leaps.
- The quake's warning is the stomp's reared frame held and shaken (no pose of its own); its cracks
  and craters lie under the dark room's darkness, so dimmer than on a lit floor; its sounds are
  `ColossusRoar`, `GroundCreak`, `ColossusStomp` and `BreakStone`. The climb walls' light is the
  glow moss's (`glow_moss.gd`).
- A falling rock's picture is its liftable's own; the rocks' landing sound is the item drop's
  (`DropLand`).
- `plateFallStunMs` (4 s) is longer than the plan's 2.5 s, for the carts from the far wall; the
  owner kept it ("Keep 4 seconds", 2026-11-24).

### Darkness and fire in the mine

[DARKNESS.md](DARKNESS.md) has the pieces: candles that burn until put out (`burn_ms` < 0), `put_out`
and `put_out_near` (the Shardback's slam ring puts out the Den's braziers, the Colossus's stomp, while he
douses, the nearest of his four), and candles a Gloomling smothers (the Dark Maze's north-west candle refuses a
flame while one sits on it: "The shadow smothers the wick."). Since 2026-11-13 a Gloomling hunts a
slime that has no light on it in a dark room ([BESTIARY.md](BESTIARY.md#23-gloomling-shadow)): in
M5 and M8 the Lantern's ember keeps them off, and another ability on the box (the Goo Bomb for M5's
cracked wall) brings them at the slime. The dark rooms: M2 and M6 light for
good once their sconces burn; M5, M8, M11, M13 stay dark (in M11 the slime's ember shows the rift's
handholds); M15 lights while its four braziers burn, and for good once he falls. *In the rebuilt
Mine (2026-11-25) every candle or brazier inside a dark room lifts its share of the dark while it
burns ([DARKNESS.md](DARKNESS.md#a-share-of-the-room-per-candle-2026-11-25)): M8's four candles, M11's
veil brazier and M13's two braziers now lighten their rooms; M5 stays dark; M15 keeps its rings.*

### Dev

- **F6** on any room scene (or `?map=crystal-mine-<room>`) lends `dungeon.devPowers.crystal-mine`
  (the Spear, the Roll, the Heavy and Silk skins, the Goo Bomb, the Lantern, the Bow), read for every
  room world of the dungeon: the first half. The Feral skin is won in the Den.
- **The second half without playing the first:** `?sealed` in any room (`crystal-mine-dungeon.tscn`'s
  `dev_pearl_*`) takes Pearl 3 quietly (the Shardback's fight finished, Feral won) and seals the mine,
  as `?map=crystal-mine-m14-shaft-floor&sealed` (desktop `-- --map=crystal-mine-m14-shaft-floor
  --sealed`). To lend Feral alone (unsealed): `?skins=feral` (`-- --skins=feral`, also in the editor's
  Main Run Args for F6).

### Outside: the Spiral

Since 2026-11-21 (roadmap 12.9; the design and its pictures:
[the Spiral](../design/2026-11-20-caverns-spiral.md)) the Caverns' outside is a falling-slab maze:
rings round a central peak, the main ring climbing from level 0 in G4's west to 3 in G5's west, four
LONG runs and three short ones over the void (most of the damage area: a fall costs 10 and sets the
slime back), a spike canyon along the ring's south side, five chunk-line crossings between lantern
posts. Laid one chunk a run by `tools/build_caverns_spiral.gd -- --chunk=<g4|h4|g5|h5>` (its nodes
under `Spiral`, its `elevation`, `forest` and `vines` layers its own), the caves by
`tools/build_caverns_rooms.gd -- --room=<id>`; then bake the four chunks. The old camp's tool
(`build_mine_outside.gd`) is deleted.

- **G4, the first yard** (by the way in from Gloop Forest, level 0): the gate mountain (level 2,
  crystal top) with the mine's mouth in a notch of its face: the mine gate (`lantern-gate.tscn`,
  `crystal-mine-gate`) and its cold brazier (lit for good, group `mine-camp-gate`, instance id
  `mine-gate-brazier`: one flame opens the gate for good, and its flag
  `candle-lit.mine-gate-brazier` tells the smith); behind the gate the way in (`exit-to-crystal-mine`
  to M1's `mine-entrance`), in front of it the arrival door `camp-mine-mouth` (the mine's south
  doorway, not while the mine is sealed); beside it the end of the smith's cart line
  (`yard-cart-station`, a MineCartStation with `cart_flag` `smith-cart.ridden`: the cart stands there
  once ridden, and never rides back) and its arrival door `yard-cart`.
- **The smith's cave** (`crystal-caverns-smith-cave`, the peak's south face in H5, roadmap 12.3): the
  smith, Pip's dad (`smith.tscn`, `smith_actor.gd`), at his anvil in his camp (two tents, campfire,
  cauldron, cot: a bed, a full refill), talks through `mine_camp.gd` (`Objects/MineCamp`): the first
  talk gives the **Lantern** (its ceremony; flag `mine-camp.lantern-given`) and, in the same visit,
  the **Smith's Crystal** (`mine-crystal`, once: `mine-camp.crystal-given`, set only when it fits in
  the bag; none with the Bow learned already) for Pip's bow rune (a full bag: "your bag is stuffed
  full. Make some room and come back for it", and he offers it before anything else at the next
  talk; until 2026-11-22 a full bag lost it for good), then "My ore cart runs down the old line to the gate ... Give it a
  flame". His lamp (`smith-cave-lamp`, lit for good: `candle-lit.smith-cave-lamp`) frees his cart
  (`smith_cart.gd`): it rides once, one way (a fade, a door's travel) down to the yard. Later talks:
  the lamp's lesson while it is cold, "ride it down" until the gate burns, the crystal's errand until
  the Bow, then tips; after the Colossus (`chapter-3-complete`, or the boss in `defeated_boss_ids`)
  he stays (owner, 2026-11-20), proud of Pip. *Until 2026-11-21 his camp stood in G4 by the gate, and
  he gave the crystal only once the gate was open; before 2026-11-20 he sent the slime to Burr.*
- **H4, the Lookout:** kept as it was: the plateau (level 2) with its two-wide flight down its face
  at x 10, 11 and the arrival door `lookout-from-mine` on top, where the climb out of the arena comes
  up; its foot is the outer ring's north stretch (Short 3 back to the main road).
- **The caves:** the Corner Cave (main road, lit), the Bay Cave (side way, by ladders), the Dark
  Nook and the Under-line Tunnel (dark, deadthorn at their mouths: the Lantern, later):
  [the Spiral, "The caves"](../design/2026-11-20-caverns-spiral.md#the-caves-room-worlds-crystal-cave-walls).
- **Not built outside:** the Feral hill up to the Lookout from the Wilds (it waits for the Wilds).

### The mine's limits

- The **Bow** is built (2026-11-20, [BODY_SHAPES.md](BODY_SHAPES.md#the-bow-2026-11-20)): the Chasm's
  lens takes its arrow's hook (`on_arrow_hit`) and nothing else strikes it, so the Chasm is
  crossed with it (it is in the Mine's F6 powers). In the story Pip carves its rune in Slimeshire
  once the Matron's Pearl is home (its homecoming raises his Workshop) and the slime brings him 5
  wood, the Matron's thread and the smith's crystal; the mine cart is the Bow-less slime's quick way
  out to him and back in. Not playtested.
- **No heart quarter inside a dungeon** (owner, 2026-11-23; the Caverns' four lie outside). S1's chest
  (on M8's north wall) holds 50 coins and the potion belt's slot
  ([crafting spec 12.4](specs/crafting.md#124-the-potion-belt-step-b3-2026-11-20)); the war journal's
  third page is in M10's chest ([quests spec 14.8](specs/quests.md#148-finds-the-war-journal-the-recipe-page-and-the-charged-roll-2026-11-20)).
- The strike while clinging runs in the body-shapes mode only (the shapes strike there); in the
  classic game an attack press on a wall does nothing.
- Tests: `test_crystal_mine.gd` (19, rewritten for the rooms at step 5, 2026-11-25: the rooms and
  their doors, the keys and the Foreman's Gate, the travel cart, the lift, the lens, the veils, the
  timbers, the Feral climbs, the Den, the boss door, his crystal fight in M15 (four tests since
  2026-11-25: his first plate burst without harm, clanged cold, the bare crystal where it shows, the
  carts' order) and his fall, an old save;
  the candles and dark rooms are `test_dark_room_candles.gd`'s) and
  `test_mine_camp.gd` (the Spiral: the yard's gate and cart end, the first talk's Lantern and crystal,
  the lamp freeing the one-way cart, the gate, the mine's way in and out through M1, the seal, the
  later talks, the Bow first, his stay after the Colossus); not run since step 5 (the owner decides
  when the suite runs). The seal test closes Release 1's end card, which opens over the game (and
  pauses it) when the Colossus is marked beaten.

## The Weaver Hollow (built)

Chapter 2's dungeon: the Thorn Guard's old watch fort inside the Watch Oak, climbed from its roots to
the Matron's web at its top, from [its design](../design/2026-10-16-dungeon-weaver-hollow.md),
reworked for the Pearl inside it ([the plan](../design/2026-10-17-pearl-mid-dungeon.md#the-weaver-hollow-chapter-2-the-silk-skin),
the owner's decision of 2026-10-17): the first half is the Goo Bomb's, up to the Brood Warden, who
guards Pearl 2 in the Hoard; its take grants the Silk skin and seals the way out; the second half
teaches the Silk skin, and the Matron's fight is its exam. Its forecourt is the open world's
`gloop-forest-f4`.

Since 2026-11-25 (step 3 of [the dungeons rework](../design/2026-11-23-dungeons-2-3-rework.md#the-weaver-hollow))
it is **one world per room**: 23 room worlds in `godot/game/scenes/worlds/rooms/weaver-hollow/` (each
`world.<id>` in `scene_index.json`) with the root-rock interior walls, one dungeon record
(`weaver-hollow`); the Trunk, the Roots, the Boughs and the Crown below. Its pieces: the webs
([WEBS.md](WEBS.md)), the bomb's cracked floor, cracked winch post and blast kegs
([BODY_SHAPES.md](BODY_SHAPES.md) "Goo Bomb"), the rams and knock targets
([Mechanisms](#mechanisms-the-knock-target-the-ram-the-runaway-cart)) and the Matron's ram fight
([specs/matron.md](specs/matron.md) section 9). Tests: `godot/tests/test_weaver_hollow.gd`,
`test_weaver_webs.gd`, `test_weaver_bombs.gd`, `test_matron.gd`.
*From 2026-10-17 until the rebuild it was four floor worlds (`weaver-hollow-trunk`, `-roots`,
`-boughs`, `-crown`, written by `tools/build_weaver_hollow.gd`); step 5 retired them on 2026-11-25
with their builder, their room copies and the cocoon fight's copied encounter, and a save standing in
one wakes in T1 ([the switch-over](#the-switch-over-2026-11-25)). What they were:
[the archive](../archive/2026-11-25-old-hollow-and-mine.md#the-weaver-hollow-on-four-floors-2026-10-17-to-2026-11-25).*

### The Weaver Hollow rebuilt: the Trunk and the Roots (step 3, 2026-11-25)

The first piece of step 3 of [the dungeons rework](../design/2026-11-23-dungeons-2-3-rework.md#the-weaver-hollow):
the Hollow's ground floor (the Trunk) and cellar (the Roots) rebuilt as **one world per room** with
the root-rock interior walls, exactly as [Fatty's Lair](#fattys-lair-built) is built (room doors that
scroll, records instead of links, a layout for the map). It was built **beside** the four floor worlds of the time, and since
[the switch-over](#the-switch-over-2026-11-25) (2026-11-25) the game enters it: the forecourt's root
gate leads into the new T1; step 5 retired the four floors the same day. Every link (rooms,
cells, levels, doors, locks): [the handover's list](../handover/2026-11-23-dungeons-rework.md#the-list-of-links-written-before-any-scene).

| Room | World | Its level |
|---|---|---|
| T1 Root Door | `weaver-hollow-t1-root-door` | the corner loft (L1) with a chest (100 coins, a Slime Tonic), seen from the floor, reached later from the hub's east gallery (Silk) |
| T2 the Hollow Heart (2 x 2) | `weaver-hollow-t2-hollow-heart` | the gallery (L1) round three sides: key 1 west, the Crown Door and the winch north, the east gallery behind a web wall; its stair blocked by a stone block |
| T3 the Larder | `weaver-hollow-t3-larder` | the walk (L1) down the east wall, cut by a gap the drawbridge crosses |
| T3's map nook | `weaver-hollow-t3-map-nook` | - (behind T3's west crack: the map) |
| T4 the Well Room | `weaver-hollow-t4-well-room` | the ledge (L1) down the east side, the Guard's stair at its top |
| R1 Root Fall | `weaver-hollow-r1-root-fall` | the landing ledge (L1), a front flight down |
| R2 the Bone Cellar (2 x 1) | `weaver-hollow-r2-bone-cellar` | - (the Watcher Eye, two Bone Throwers, pillars) |
| R2's compass pocket | `weaver-hollow-r2-compass-pocket` | - (behind R2's north crack: the compass) |
| R3 the Ram Cellar | `weaver-hollow-r3-ram-cellar` | - (the ram, the bricked arch, the target on an island in a void) |
| D1 the Old Cellar | `weaver-hollow-d1-old-cellar` | - (dark, as on the four floors) |

- **The scenes** are `godot/game/scenes/worlds/rooms/weaver-hollow/<room>.tscn` (each `world.<id>` in
  `scene_index.json`), their map `layout.tscn` (the Trunk on floor 0, the Roots on floor -1), their
  Dungeon node an instance of `game/scenes/objects/dungeon/weaver-hollow-dungeon.tscn` (`dungeon_id`
  and `record_map_id` `weaver-hollow`, the final ids; the entrance T1; the Matron's seal settings).
  `tools/build_weaver_hollow_rooms.gd` wrote their first version (`-- --room=<name>[,...] | --all
  [--layout] [--force]`); **from now on the scenes are edited by hand** and the tool refuses to
  overwrite one without `--force`. After painting a room's `elevation`, bake it
  (`tools/bake_elevation.gd -- --world=weaver-hollow-<room>`) or let the next run from the project do it.
- **Running it:** `?map=weaver-hollow-t1-root-door` (or any room's world; F6 on a room scene): the
  run gets the Hollow's first-half powers (`dungeon.devPowers.weaver-hollow`: the Spear, the Roll,
  the Heavy skin, the Goo Bomb). `?room=<room>` travels to a room as in the Lair.
- **The way through:** T1, north into the hub (key 1 and the Crown Door in sight on the gallery, the
  stair's foot shut by a stone block); west into T3 (two orb-weavers): a Goo Bomb on the west crack
  opens the map nook, one on the north crack opens T4; in T4 a bomb breaks the cracked floor, a fall
  (one way) onto R1's landing ledge over the egg sac; R2 (a bomb on the north crack for the compass);
  R3: a pot thrown over the void at the knock target lets the ram go, its log bursts the bricked
  arch, and the Guard's stair behind it climbs to **T4's ledge**, above the room the slime left; the
  wall-walk: the ledge's south doorway into T3's walk, a Goo Bomb spat at the gap's edge, sucked in and
  thrown over the gap at the cracked winch post, which lets the bridge down; over it and east into the
  hub's west gallery: **key 1**; the north gallery's winch sinks the stair block for good (the short
  way up after a faint); key 1 opens the hub's south door. A drop off any walk or gallery lands
  unhurt on the floor below (the ledge drop), and the walk starts again.
- **Upper doorways** (the walk, the gallery, the loft, the ledge): the doorway's block and the rim
  cells beside a raised floor are painted at its level on the `elevation` layer (INTERIOR_WALLS.md
  "Pits and holes"); a room door's scroll carries the slime's level into the next room
  (`main.gd` `_arrival_level`), which arrives on the far doorway's level. Nothing else was needed.
- **A drawbridge over a floor** (T3): the kit's drawbridge at `level` 1 over level-0 floor, as R7's
  slabs over its pit; lowered, its deck opens the level-1 passage across the gap and the orb-weavers
  walk under it. It stands raised on the gap's near edge (where the slime comes in), held by a chain
  from the cracked winch post on the far rim (`chain_end`: the marker `t3-bridge-top`).
  `winch_post.gd` gained `blast_rise` (opt-in, 0 by default: every post placed before reaches as it
  did): T3's post has 56, the middle of its hurtbox, since a bomb thrown at it from the north stops at
  the top of its hurtbox, 104 units above its foot, out of the blast's reach (60) from the foot.
- **The Guard's stair** is a stair door (`object.stair-door`, `stair_door.gd`) in the north wall's
  **stairs** opening, its own picture hidden (the wall draws the stairs) and its well raised into the
  passage (`trigger_rect` (-40, -112, 80, 56)), so the bricked arch in front of it holds it until the
  ram bursts it; its pair stands in T4's ledge's stairs opening (level 1).
- **R3's lesson:** the ram (`toward` north, 4 cells) aimed at the arch; its knock target on a
  two-by-two island in a void (level -2, a `void` hazard, `draw_look` off) straight below the ram, its
  rope up to the ram's post; dungeon pots on the void's west rim (they grow back). Only a throw
  reaches the target; the lane's grooves show where the log swings.
- **The hub's stair block** is a shutter (`starts_shut`, `wall` north, the kit's own block) at the foot
  of the gallery's front flight; the winch on the gallery sinks it for good.
- **The cracks** stand on both sides of a doorway with one flag (T3/T4), or in front of a pocket
  world entered with the iris (the nook, R2's pocket; the pocket's own side a blown hole). The
  root-rock wall's cracked piece was remade on 2026-11-25 (`scripts/art/make-root-cracked.py`: the
  generated one had see-through gaps), and `root-rock.webp` repacked (only its eight cracked pieces
  changed).
- **D1** is parted as on the four floors, its corridor walled off by stacked casks (solid) where
  their rock column stood (a one-cell raised strip read as a walk), and keeps the old Roots' record for
  its chest (`weaver-hollow-roots-old-cellar-chest` on map
  `weaver-hollow-roots`), so the war journal's page cannot be had twice.
- **Floors:** the Trunk's rooms are packed earth (T1 to T4 and the map nook: the wall layer's
  `draw_floor` off, the `ground` painted garden soil), with gravel paths between doors (the hub, T1,
  T3), a grass bed at the hub's heart and wood planks in the Larder's store corner, each ground's edge
  art over the soil (TERRAIN_LAB.md); the Roots keep the root-rock stone floor. A room is all ground or
  all wall-style floor: a ground patch beside the wall style's floor draws its base ground in a ring
  round it, and a ground without a 128 px sheet (forest-moss) loses its edge under garden soil's.
  One floor trim in every room, `rubble-umber`.
- **Dressing:** the Scenery dock's props (root posts and humps, hanging roots, glow mushrooms, moss
  beds, stepping stones in the Roots, the Guard's racks, casks, sacks, bones, chains, the loft's silk),
  sconces, braziers and fireflies that move. **No cocoon or egg sac for show** (the Hollow's clarity
  rule, [its design](../design/2026-10-16-dungeon-weaver-hollow.md): a cocoon or an egg sac in here is
  a lock or an enemy); the first versions had them, taken out of every room on 2026-11-25, and the
  rooms that read thin after were dressed by hand (T1, R1, B1, B4, B5, the Hoard, D2: bones, webs,
  silk, mushrooms; [the handover's list](../handover/2026-11-23-dungeons-rework.md#the-dressing-after-the-clean-out-2026-11-25-the-reviewers-round)).
- **No old doorway art:** `doorway_art.gd` drew the cliff-wall doorway frames of the four-floor
  Hollow and the one-scene Mine (chosen by world id) and skipped any world with an `interior-walls`
  layer (it had turned the hub's stair block into a root arch); it went with those worlds at step 5.
- **Films:** `tools/film_weaver_hollow_rooms.gd` (windowed) plays it: `--film=walk` the whole way
  with a check a step (a picture each and `walk.json`; PASS or FAIL), `--film=ram` R3's lesson and
  `--film=wall-walk` the wall-walk frame by frame; `--film=look --world=<room> --at=<x>,<y> --zoom=<z>` (`--slime=<x>,<y>`: where the slime stands)
  a still picture of a room in the game (its ground edges show there, not in the editor render). The enemies are calmed and the slime's health kept
  full while it runs (the walk proves the way, not a fight).
- **Switched over** (2026-11-25, [below](#the-switch-over-2026-11-25)): the forecourt's root gate
  enters the new T1, and T1's way out leads to the forecourt. T1's loft is reached through the east gallery's web wall (Silk, after
  Pearl 2). Tests: `test_weaver_hollow.gd` (rewritten for the rooms at step 5, not run yet); not played
  with a keyboard.

### The Boughs (step 3's second piece, 2026-11-25)

The Hollow's upper floor, built the same way (entered since the switch-over): ten more room worlds in
`rooms/weaver-hollow/` (floor 1 on the map, the stair foot on floor 0), their links in
[the handover](../handover/2026-11-23-dungeons-rework.md#step-3-the-boughs).

| Room | World | What is there |
|---|---|---|
| The stair foot | `weaver-hollow-stair-foot` | behind the hub's south key door (key 1): the Guard's stair up |
| B1 the Bough Stair | `weaver-hollow-b1-bough-stair` | a Silk Lurker, floor webs; D2 west |
| B2 the Drawbridge (2 x 1) | `weaver-hollow-b2-drawbridge` | a void down the middle (four cells), the drawbridge raised on its west rim, chained to a cracked post on the east rim's edge: a Goo Bomb thrown over the void lets it down; the Warden's key door (key 2) east; the rafters (L1) along the north wall, cut by the void: slab, landing, slab, slab under floor webs |
| B3 the Mimic's Pantry | `weaver-hollow-b3-mimics-pantry` | the Cocoon Mimic (key 2); the rafters (L1) with the big chest (the big key) in sight from the floor, and an open hole: the drop onto the hub's north gallery; S2's three parcels behind a web wall |
| B4 the Nursery | `weaver-hollow-b4-nursery` | the optional ambush (once), its chest |
| B5 the Warden's Den | `weaver-hollow-b5-wardens-den` | the Brood Warden (a room fight, his `boss_id` the four floors'); a ram across the den (lane east, rows 10-11), its knock target at the lane's east end, the rope along the lane; won, the Hoard's shutter sinks |
| The Hoard | `weaver-hollow-hoard` | Pearl 2 on the brood's altar (Silk; the seal); the loft (L1) on the west, its stair behind a web wall (the Silk skin's first lock) |
| B6 the Spinning Loft | `weaver-hollow-b6-spinning-loft` | two rows of web walls, two Slime Spiders, key 3 in a silk parcel (no levels inside: reached only from the Rafter Run) |
| B7 the Pillar | `weaver-hollow-b7-pillar` | the optional wing's end: four blast kegs on a parapet in a void to the cracked post, the drawbridge to the far shore, its chest (40 coins, an energy potion; no heart quarter) |
| D2 the Dark Bough | `weaver-hollow-d2-dark-bough` | dark, as on the four floors: three candles, its chest (the old Boughs' record) |

- **The way:** the hub's south door (key 1), the stair foot, the stair up to B1, B2 (the bomb over the
  void, the bridge), B3 (the Mimic's key 2), the Warden's door, B5 (lure the Warden onto the ram's
  lane, throw at the target from beside it: knocked flat, his plates open), the Hoard (Pearl 2, the
  Silk skin, the seal), the loft's web wall, the Spinning Loft (key 3), B2's rafters (the webbed
  slabs: a Roll sticks without the skin and falls with its slab; with it a quick Roll from the east
  rim's edge to the landing, a second from the landing's west edge), B3's rafters (the big key), the
  hole down onto the hub's north gallery by the Crown Door. The Silk skin then opens the hub's east
  gallery web wall and T1's loft chest (built in the first piece).
- **Levels across rooms:** a room-door scroll keeps the slime's level when it stands at the doorway
  or at the spot it walks out onto, and otherwise takes the level of that spot (`main.gd`, 2026-11-25:
  the doorway spot of a room door lies off the painted floor, past it in an east or south wall, above
  it in a north one, where the level read 0). So a walk on L1 runs on through upper doorways on every
  side, and the Spinning Loft needs no levels of its own.
- **Floors:** packed earth (garden soil) with gravel paths, wood planks on the rafters, the loft and
  the Spinning Loft, grass round the Hoard's altar, cavern stone in the voids; one floor trim.
- **The Warden and the ram:** `brood_warden.gd` `on_mechanism_hit` (above, "The hooks"); his numbers
  `ramDamage`, `ramSlidePx`, `ramSlideMs`, `knockedMs` in `enemy-types.json`.
- **A slab under a floor web:** the kit's falling slab and the `webs` layer as they are; the room's
  `webs` layer at z 0 (the decks draw at z -1), so the webs show over the slabs. A hazard drops only
  a body at its rim (the lowest level painted round it), so the one void has two: the floor's
  (rows 4-13, rim 0) and the rafters' crossing (rows 2-3, rim 1); with one, a slime stuck on a fallen
  slab up there stood on the air. Proven in the walk and `--film=webbed-slab`.
- **Films:** `tools/film_weaver_hollow_rooms.gd --film=walk` now runs on from the hub's south door to
  the big key, the gallery and T1's loft (`--from=boughs` starts there); `--film=warden-ram`,
  `--film=webbed-slab`.
- **Not checked:** the map layout places the Boughs on floor 1 and the Crown on floor 2, but the
  minimap's floor tabs were not looked at.

### The Crown (step 3's third piece, 2026-11-25)

The Hollow's top floor, the last piece of step 3, built the same way (entered since the
switch-over): three more room worlds in `rooms/weaver-hollow/` (floor 2 on the
map), their links in [the handover](../handover/2026-11-23-dungeons-rework.md#step-3-the-crown).

| Room | World | What is there |
|---|---|---|
| C1 the Crown Stair | `weaver-hollow-c1-crown-stair` | behind the hub's Crown Door (the big key; a room door `t2-north-crown` behind it in the hub): floor webs wall to wall on the floor (L0), the front flight up (cols 8-9) choked by a web wall (with the Silk skin the slime wades it, or a Spear hit cuts it for good: `weaver-hollow.c1-stair-web`); the top (L1, planks): four pots (two hearts, two energy) by the key 3 door, the calm spot before her |
| C2 the Crown | `weaver-hollow-c2-crown` | the Matron's ram fight, **her lab's arena at the lab's coordinates** (24 x 20: five rams, their targets, her camp, twelve pots); the boss shutter south, the seal east |
| C3 the Outer Bough | `weaver-hollow-c3-outer-bough` | 18 x 8: a timber walk past the sunk seal, her web wall across it wall to wall (`weaver-hollow.c3-web-wall`), the open hole at its end in a patch of bark: the drop to the forecourt (`gloop-forest-f4`, the marker `weaver-hollow-silk-drop`: the four floors' landing, by S1's nook) |

- **Her arena is the lab's** (`game/dev/bosses/matron-lab.tscn`, [above](#the-matron-lab-a-boss-that-answers-the-hook)),
  carried into the room as it is, the room sized to it: the same floor (cols 2-21, rows 2-17), the
  rams `ram-1` to `ram-5` at x 288, 524.8, 768, 1011.2 and 1248 on y 358.4 (lanes south, 9 cells), the
  targets `target-1` to `target-5` straight below on y 1075.2, her camp at (768, 640) with the lab's
  arena (1280 x 1024) and wake (1280 x 864, 80 up) shapes, `spawn` and `boss_overrides`, the pots
  `pot-1` to `pot-12` where the lab has them, the slime's way in (the south door, cols 9-10) where the
  lab's slime starts, between targets 2 and 3. `matron_ram.gd`, her scene and the lab are unchanged.
  The builder's `CROWN_*` constants hold the lab's numbers.
- **Her camp** is the encounter (`encounter.weaver-hollow-matron`), whose own values are the lab's
  since the switch-over: `boss_scene` `character.orb-weaver-matron-rework`, `boss_id`
  `orb-weaver-matron`, `camp_id` `weaver-hollow-matron`, `map_id` `weaver-hollow-c2-crown`, `spawn`
  (0, -30), the wake and arena shapes, `respawn_ms` -1 (a dungeon boss never returns); C2 sets only the
  arena's position (0, 0).
  Her roar, her full heart (raises the maximum energy; no heart quarter) and her thread are the
  encounter's. Her camp's `boss_engaged` shuts the boss shutter (`weaver-hollow-crown-shutter`) behind
  the slime and `boss_defeated` opens it (connections in the scene, as in the four floors' Crown). Her fall goes
  into `defeated_boss_ids` and the Hollow's record, which breaks the seals: C2's east doorway and T1's
  way out.
- **The way:** the hub's gallery, the Crown Door, C1 (through the floor webs, the web wall at the
  flight's foot, up the flight), the key 3 door (one keyhole), C2: she wakes as the slime walks in and
  the shutter shuts; the seal holds the east doorway; her fall sinks it and opens the shutter; C3: her
  web wall, the hole, down to the forecourt.
- **A faint** in her fight wakes the slime at T1 (the Hollow's entrance), everything kept, and the way
  back up is short, every lock on it open for good: T1, the hub, the gallery's stair (its block sunk by
  the winch), the Crown Door, C1's flight, the key 3 door: four doors, no key spent (proven in the walk).
- **The nest's dressing:** sconces and her silk on the north wall between the rams' gantries, a web in
  the north-east corner and a spool of her silk below it on the east strip, the bones of her prey on the side strips, glow mushrooms, floor scraps between
  the lanes: nothing on a lane, nothing between a target and where the slime throws from. No cocoon or
  egg sac for show (her cocoon is the lock) and no floor webs (the lab's floor is bare; they would slow
  the slime in her fight).
- **Films:** the walk runs on through the Crown (her fight ended by the tool; `--from=crown` starts at
  the Crown Door). `tools/film_crown.gd` films her fight in C2 with `tools/film_matron.gd`'s own films
  and staging, only the world changed and the Silk skin lent (`scripts/godot/film-matron.sh <name>
  --film=<film> --tool=film_crown`, into `output/dungeon-rework/hollow/crown-films/<name>/`); round1,
  ram-catch and round3 say PASS or FAIL.
- **Switched over** (2026-11-25): the walk now starts in the forecourt (a Goo Bomb on the root gate,
  in through it), and after C3's drop goes in through the gate again and out by T1's way out.

### The switch-over (2026-11-25)

The owner's call ("Switch it over"), made before he had played the rebuilt rooms: the game enters the
rebuilt Hollow. Step 5 retired the four floor worlds the same day, with their room copies, their
builder, the cocoon fight's copied encounter and their tests ([the archive](../archive/2026-11-25-old-hollow-and-mine.md#the-weaver-hollow-on-four-floors-2026-10-17-to-2026-11-25)).

- **The way in:** the forecourt's root gate (`gloop-forest-f4`, `weaver-hollow-forecourt/root-gate`)
  leads to the new T1 (`target_area_id` `weaver-hollow-t1-root-door`, `target_door_id`
  `weaver-hollow-entrance`); T1's way out lands at the gate. The atlas's area scene
  `game/dev/area_edit/areas/area-e4-f5.tscn` (not in git) has the same two lines, and its write-back
  refuses anyway: F4 changed on disk since it was opened (each chunk's hash), so nothing is written.
- **Her fight:** `encounter.weaver-hollow-matron`'s own values are the rework's (above); C2 keeps only
  its arena's position and the `[editable path]` line that its camp-to-shutter connections need, so an
  editor save that loses the line loses the shutter's wiring but never brings the old fight back. The
  copy of the encounter as it was (`weaver-hollow-matron-old.tscn`, the four floors' Crown's) went at
  step 5; the cocoon fight's own scene (`character.orb-weaver-matron`, `matron.gd`) stays: the ram
  fight extends it, and the nest camp (`encounter.gloop-matron-nest`) and `test_matron.gd` use it.
- **The names:** the world map lists the Hollow by its record id (`weaver-hollow`, as `fatty-lair`:
  `interiors` and the marker's `map`); the area banner is one for all its rooms (`AreaTitles`
  `weaver-hollow`; the four floors' names stay for an old save's slot label); the dev powers are one
  line, `dungeon.devPowers.weaver-hollow`; the second-half dev run starts in the Hoard.
- **Saves:** a save standing in one of the retired floors loads into the new T1 at its entrance,
  inside, as a dungeon's resume save does (RunState `moved_world`, `RETIRED_WORLDS`; `load_slot`
  checks the moved world, so such a save loads although its world is gone); a record entrance naming
  one of them is forgotten (T1 records it again). The record (`weaver-hollow`) is the same dungeon's,
  so small keys held, the big key, the map, the seal and her defeat carry over; Pearl 2, the Silk skin,
  the Warden's fall and her full heart are the run's own. The prizes keep the four floors' records
  (D1's page, D2's chest, B4's chest, S2's three parcels), so none is had twice. A boss fight whose
  boss fell elsewhere gives its reward when its room is built (`room_fight.gd`
  `_reward_if_beaten_elsewhere`: the Warden beaten in the old Boughs, the Hoard's shutter). A
  half-played save loses its doors, bridges, winches, webs and fights (the old floors' object keys;
  played again), the doors its small keys opened (the keys spent there are gone, and the new chests and
  the Mimic give theirs again, so it holds at least enough, often more), the rooms on its map, and S3's
  30 coins and B6's heart quarter if not taken (gone with the rework).

### The forecourt (`gloop-forest-f4`)

- **Gone from the open world:** the Matron's nest camp (`gloop-ch2-matron-nest`), its guarded
  chest, its silk Gulp spot and the Goo Heart that appeared there after her fall; the ring's
  decorative cocoons, egg sacs and ground webs (the clarity rule: inside, the egg sacs, the Mimic
  and the floor webs are real), and the trees and webs where the oak stands.
- **Its enemies stay** (owner, 2026-11-25): the forecourt's terraces hold real placed enemies, two
  Cocoon Mimics by the path and three Egg Sacs (with a Silk Lurker and two Worm Swordsmen), placed in
  the chunk scene. They are not decoration, so the clarity rule holds outside as inside: a wrapped
  shape on the forecourt is always a Mimic or an egg sac.
- **`weaver-hollow-forecourt`:** the Watch Oak (`watch-oak`: its picture
  `asset/MAPS/landmarks/watch-oak.webp` at 0.6, drawn at z -1 like a wall's face so the slime, the
  trees and the gate's decals draw over it; its upper trunk fades into the forest painted behind
  it (since 2026-11-21 the oak stands at (964, 265), its root gate at (964, 271), placed by the owner
  in the editor: the fade lies
  under the canopy wall over the glade, never over open ground, the owner); `Trunk` collision in bands round its silhouette); the root gate (`object.cracked-wall` on the
  bricked arch, `weaver-hollow.root-gate`; its `blocker` is the `ArchBricks` body; blown, a door to
  T1's `weaver-hollow-entrance`; to the four floors' `trunk-entrance` until 2026-11-25); S1 (a web wall closing a nook in the forest's edge east of the gate, its parcel
  inside); the marker `weaver-hollow-silk-drop` where C3's drop lands.
- The forecourt has no elevation, so it needs no bake.

### The Hollow's own pieces

- The Spinning Loft's dressing (B6; C4 on the four floors) and the brood's altar
  (`game/scenes/objects/weaver-hollow/`: `loft-rafter`, `loft-peg-rail` hang on the north wall's face,
  `loft-spool`, `loft-spinning-wheel` stand solid in the corridors' corners, `brood-altar`): Magnific
  GPT 2.5 (`gpt-2-mini`, transparent, the Lili creation as style reference), 2026-10-17, two
  generations (200 credits), sources and prompts in `asset/Originals/weaver-hollow/loft/`, packed by
  `python scripts/art/pack-loft-art.py` into `godot/asset/MAPS/props/weaver-hollow/`; the rebuilt
  rooms dress with them too (T1, T2, B1 to B3, B6, the Hoard, C1, C2).
- **F6 on the second half with the Silk skin:** F6 on a room scene gives the Hollow's dev powers (the
  Spear, the Roll, the Heavy skin, the Goo Bomb: Silk is won mid-dungeon, from Pearl 2; one line,
  `dungeon.devPowers.weaver-hollow`, read for every world of the dungeon). F6 on
  `game/dev/weaver-hollow-second-half.tscn` (`game/dev/second_half_run.gd`; dev only) runs the Hoard
  (`weaver-hollow-hoard`; the four floors' Crown before the switch-over) the same way and lends the
  Silk skin for the session, worn; on the web or a desktop launch `?map=weaver-hollow-hoard&skins=silk`
  does the same, and `?sealed` takes Pearl 2 quietly and seals.
- *Gone with the four floors at step 5:* the hub's latched hatch (`latched_hatch.gd`: the rebuilt hub
  has none) and `room_arenas.gd` (each placed enemy kept to its camera room; a room world is one room).

### Limits

- B6's rows of web walls hide the slime behind them only partly: an "across" web fades to 0.45 while
  the slime stands behind it (`web_wall.gd`).
- A Slime Spider's web shot (`spider-web`, 5 since 2026-11-24) is the Gloop Forest's, untuned for the
  Loft; web walls stop shots (they are solid on the world layer), so the spiders hit the slime while
  its body shows above a row it wades, or through a cut lane.
- Not built: Mossy's tip at the ring's south gap, the Matron's three-way lash (8.7; if built it
  pulls but never traps a silk-skinned slime). Her defeat in the Crown counts for the main quest's
  second stage and sets `chapter-2-complete` (the old quest "The Matron's Nest" is retired since
  2026-11-19: [quests spec §14](specs/quests.md#14-the-main-quest-talks-and-tips-2026-11-19)).
- Walked by `tools/film_weaver_hollow_rooms.gd --film=walk` (124 checks, from the forecourt and back
  out), not played through by the owner.

## Fatty's Lair (built)

Chapter 1's dungeon, built 2026-10-17 from [its design](../design/2026-10-16-dungeon-fattys-lair.md)
(its status lists what moved) and **reworked the same day for the Pearl inside the dungeon**
([the plan](../design/2026-10-17-pearl-mid-dungeon.md#fattys-lair-chapter-1-the-heavy-skin)): the
Thorn Guard's old fort that Gorge's worms took, Fatty One Eye's lair below it. The first half tests
what the slime brings (the Roll, the Spear, the Gulp's throw) and ends in the Larder, where the Big
Squint guards **Pearl 1**; its take grants the Heavy skin and seals the Lair ([The seal](#the-seal));
the second half teaches, tests and twists the Heavy skin, and Fatty's phase two is its exam.
**One world per room since 2026-10-18** (the owner's decision; [DUNGEON_ROOMS.md](DUNGEON_ROOMS.md#fattys-lair-one-world-per-room-2026-10-18)):
21 rooms in 19 worlds (24 in 22 until the Armoury, the Burrow and the sally port moved outside on
2026-10-19, below), each built when the slime walks in (R1 the Gatehouse is `world.fatty-lair`;
R5's eye hall, lower hall and key alcove are one world behind their dividers;
the others `world.fatty-lair-<room>`), joined by room doors that scroll the screen, laid on a 5 x 5
map of rooms of 18 x 16 cells (a little more than a screen: the camera moves inside them; the map is
the layout scene `rooms/fatty-lair/layout.tscn`), two of them dark. What ties two rooms is a record
the other room reads when it is built. **Interior walls since 2026-10-18** ([INTERIOR_WALLS.md](INTERIOR_WALLS.md)): every
room's rim is Zelda's bevelled frame, two cells deep, in its style (fort stone `lair-stone`, the
Deep's `cave-rock`, the arena's and the burrows' `root-rock`), each with its own plain floor; the
doors in a rim draw only their leaves; the elevation keeps only the voids, the spike pit and its
stairs. The room tables below are in the old 16 x 14 room's cells: the builder moves each room's
layout one cell in (`_map_local`; a two-wide or two-tall room three cells past its INSERT, the hub's
at its column 20), so every puzzle keeps its cells and every doorway lands on the new floor line;
each room's layout starts one cell in from its own scene's origin. Its ways in and out are outside
(below). **Edited in the editor** since 2026-10-18: its 19 room scenes
(`game/scenes/worlds/rooms/fatty-lair/`) are the source of truth (DUNGEON_ROOMS.md).
`tools/build_fattys_lair.gd`, which first built it, is retired and writes nothing. After painting
holes or stairs in a room, bake that room's world (`tools/bake_elevation.gd -- --world=fatty-lair-<room>`;
R1's is `fatty-lair`).
Its code is `godot/game/fattys_lair/` and the scene scripts `game/scripts/drop_gate.gd`,
`gate_winch.gd`, `eye_latch.gd`, `plank_barricade.gd`, `stair_door.gd` (on `stair_hatch.gd`), `heavy_plate.gd`,
`pearl.gd` and Fatty's phase two in `fatty.gd`; its art `python scripts/art/pack-fattys-lair-art.py`
and, for the Weigh House's props, `python scripts/art/pack-weigh-house-art.py` (sources in
`asset/Originals/fattys-lair/generated/`) into `godot/asset/MAPS/objects/fattys-lair/` and Burr's
sheet `godot/asset/characters/authored/npcs/burr.webp`. Tests: `godot/tests/test_fattys_lair.gd`.

- **The paint:** rock at level 2 (its top forest floor) with the rooms carved out at level 0, every
  camera room keeping a one-cell rim (two-cell bands between rooms; an east or west doorway also
  clears the two rows its lintel hangs over). Walls on the `cliffs` layer: masonry for the upper
  fort and the Weigh House (the Thorn Guard's built hall), cave rock for the Deep (R8 to R12, the
  Armoury), root rock where the worms dug (the arena, the Burrow, the bolt-hole). Floors: cobble,
  the Deep's earth (the amberleaf sheet) in R10, the Armoury, the Burrow and the bolt-hole. The
  voids are holes at -3 floored with dark cavern stone, darkened a little more by `VoidShade`
  (`game/fattys_lair/void_shade.gd`, presentation only); R7's spike pit is a hole at -1 with a
  flight of stairs out. The pockets (R1's store, Burr's cell) are rock behind their parent room's
  own bevel faces; R5's inner wall and alcove, R7's platform gate, the Armoury's closet and the
  Weigh House's inner walls are dividers (FENCES.md "Dungeon dividers"); R11's low wall is built
  (`walls` layer). R10's statue niche is cut into its north rock, R9's big-chest alcove into its south rim.
- **Kit pieces used:** the Dungeon (`fatty-lair`, "Fatty's Lair", resume at `dungeon-entrance` in
  R1; its seal: `boss_id` `fatty-one-eye`, "Fatty One Eye", his mud red `#b4462c`, his roar
  `fatty-roar.ogg` at pitch 0.9, earthy dust), a `RoomEntry` in every camera room (`?room=<name>`);
  small keys 1 and 2 in chests (R5's alcove, R7's landing; owner 2026-10-19: keys are never left floating) for Burr's door (two keyholes); the boss door; the big
  chest in R9's alcove (hidden: R9's plate raises it); chests for the map (the nook), R1's store
  and R14 (the Armoury's went outside with it); five bolted doors (the hub to R1, R5 to R1, R7 to R2, R9 to R8,
  R11 to the ledge); shutters (the Larder's, the arena's south one, R4's two and R8's east one) and
  room fights (R4's, R8's, and the Larder's: `once`, `boss_id` `fatty-lair-big-squint`, the
  mini-boss, Pearl 1's guard); two seals
  (`object.dungeon-seal`: R1's south doorway, the take's glimpse, and R13's north doorway, the way
  out past Fatty); the hub's drawbridge; 24 falling slabs (R2, R7, R11) and R2's landing (a
  `hazard-deck`); a void hazard over every rectangle of hole cells (`draw_look` off; the Armoury's
  and the Burrow's, with `Return` points at their doorways, went outside with those rooms) and a spikes hazard over the pit; the
  prize glint over the Larder's altar (the shadow path and the Burrow's and the Armoury's glints went
  outside with those rooms); pots that
  grow back; an energy flower on the ledge. The arena's south shutter is driven by the boss camp
  through the Lair's director. No compass is placed (the director is the map's boss mark, group
  `dungeon_map_mark`; the Larder's fight, with its `boss_id`, is marked too until it is won).
- **The Heavy skin's locks** ([SKINS.md](SKINS.md#heavy)), all in the second half or after the
  Pearl: three plank barricades (the Larder's north doorway, R1's store, the bolt-hole), four heavy
  plates (the Weigh House's two, R10's, R9's; the hub's two drawbridge plates are not heavy since
  2026-10-19: two bodies, the slime and Burr), three armour statues that are
  heavy blocks (the Weigh House's, R10's, R9's: since 2026-11-01 R9's other three are solid
  scenery statues, `decoration-world-solid--armor-statue`, and the Weigh House has one since
  2026-11-22) and the Weigh House's loose prize. Nothing
  before the Pearl needs a plate or the skin.

### The rooms

Columns A to E (west to east), rows 2 to 6 (north to south), as the design names them.

| Room | Cell | What is there |
|---|---|---|
| R1 the Gatehouse | C6 | the entrance (south, to Fatty's Hollow), the store behind planks (its own world, `fatty-lair-r1-store`: a chest with 100 coins, `r1-store-chest`) |
| R2 the Slab Steps | D6 | an L of void: two slabs over its west arm; two over its north arm to a landing |
| R3 the Pit Hall | C5-D5 | the hub: the chasm round the north ledge, Burr's cell in the west gallery, the Inner Stair's door in the north wall, the drawbridge, the boss door |
| R4 the Squint Den | B5 | Squints (two since 2026-11-21: the owner's room) and a room fight (`r4-squint-den`, the whole room): its west shutter (to the map nook) and its south one (to R5) are shut (`starts_shut`) each time the room is built, until no living enemy is left in the room, however many the scene holds |
| R5 the Eye Hall | B6 | the north maze (2026-10-19): low dividers, two eye latches (three until 2026-11-21) struck in order on a timer, three Squints on guard, three gates opening together; the alcove's timed pair, small key 1 |
| R6 the Pipe Gallery | E5 | two Pipe Worms (the Burrow's mouth walled 2026-10-19: the Burrow moved to D4) |
| R7 the Bell Bridge | E6 | the spike pit, the bell on its rock, the turning slab bridge, small key 2 |
| R8 the Guard Crypt | B3-B4 | the Inner Stair's foot (its stair door up, in the north wall), skeletons (Bone Marchers and a Bone Leaper: the owner's room), the Thorn Guard's statues, door 3 into R11 (the east doorway near the bottom): *since 2026-11-21 (owner)* a shutter in it (`r8-east-shutter`, cave rock, `starts_shut`) and a room fight over the whole room (`r8-guard-crypt`), so it opens once no living enemy is left in the room (a skeleton's bone pile still lives until it is broken), shut again each time the room is built; an empty `fences` layer to paint fences and dividers on |
| R9 the Watcher Hall | A3 | the Heavy skin's twist: the Watcher Eye among four armour statues (since 2026-11-01 one heavy block to push, the other three solid scenery statues: cover), a war banner, pots; a plate in its sight that raises the big chest in the south alcove (**the big key**); its north stone door held by R10's plate; its east door bolted on its side |
| R10 the Dung Roller Run | A2-B2 | the Heavy skin's test: the Dung Roller's lane, a statue in the north niche, a plate before the corridor down to R9's stone door. *As built (2026-11-22): three Dung Rollers and a Carnivore Plant* |
| R11 the Drop-gate Bridge | C4 | the inner drop gate, the slab bridge with its turn, a Pipe Worm |
| R12 the Larder | C3 | the Pearl room: Fatty's hoard, the Big Squint's ambush, the worms' altar with Pearl 1's glow, the north doorway nailed shut (the Heavy skin's first lock) |
| C2 the Weigh House | C2 | the Heavy skin's teach (planned with no enemy): a plate before the east stone door, a statue and a plate that holds the west stone door only while it stands on it; scale pans and weights; a pouch in a scale pan on the east wall. *As built (2026-11-22):* a Watcher Eye and two Worm Swordsmen (since 2026-10-19), an invulnerable Prism Eye at (600, 309), a solid armour statue at (412, 329) (scenery, not pushed: the owner's placement), two hanging chains, pots |
| R13 Fatty's Arena | D4 | Fatty One Eye (since 2026-11-21 the Spear and thrown things on his eye; the Heavy skin's exam before); the south shutter; the north doorway's seal; his full heart |
| R14 the Postern | D3 | after Fatty: a chest with 25 coins and a Slime Tonic (`hp-potion`; `fatty-lair-postern-chest`; the green key until 2026-11-20, question 163), the bolt-hole's barricade. *Since 2026-11-22* the chest stands at (541, 381) on a raised floor (level 1, five cells square, a three-wide flight down its south side) painted on the room's `Elevation` layer (`room_back_faces` on; no baked cache yet) |
| the bolt-hole | D2 | a tunnel up to daylight in level-1-d4 |
| the map nook | A5 | a small room behind R4's crates |

### The main path

1. **Fatty's Hollow** (`level-1-d5`'s hill, since 2026-10-17; [Outside](#outside-fattys-hollow-and-the-bolt-hole)):
   through the old fort's field maze and over its moat's slab bridge to the forecourt; pull the worm
   lever in front of the gate, then Roll north under the old gate before it drops (walking from the
   lever never makes it).
2. **R1:** East into R2: a Roll over two slabs, then two more to the landing; north into the hub,
   where Burr calls from his cell. The outer gate is not held up: going back out, or coming back,
   means the lever and the Roll again, the same way as the first time.
3. **The west wing:** R4's Squints, then R5's **north maze** (owner, 2026-10-19; it replaced the
   single teach latch): the hall north of the inner door is a maze of low dividers (a row across
   with two gaps, a pocket each side, a gatehouse in the middle holding G1 and G2 above the inner
   door, G3). Two eye latches, I under the west pocket's divider and II under the east pocket's,
   must be thrust in that order (`order`), both within I's 20 s (its `open_ms`; a broken run opens
   the later one too): out of order the run starts over. *Until 2026-11-21 a third, III on the north
   wall (the old inner latch, `r5-latch-inner`), came last; the owner took it out, and II now opens
   the inner door too (its `more_gate_ids`; the door keeps its gate id and record,
   `fatty-lair-r5-inner`).* Three Squints guard the top corridor and the two lower lanes.
   Solved, the three gates sink together, for good (each latch its own `gate_id`; together, so a
   failed run never shuts the slime between two gates). Then the alcove's two eyes each stay shut
   3 s, and both shut at once open it: **small key 1**.
4. **The east wing:** R6's Pipe Worms, then R7: a thrown pot rings the bell, which opens the
   platform's door; two slabs to the rock, two to the platform: **small key 2**.
5. **Burr's cell:** two keys, two keyholes; *since 2026-11-20 (owner)* he first walks out of his cell
   (through its doorway and a step to the slime's east side, `_out_of_cell_path`, so he never walks
   into the slime that just turned the keys) and turns to it, then thanks it, opens the Inner
   Stair's door and warns of the bones. *Since 2026-11-20 (owner: Burr's must be the first fragment)*, between his
   thanks ("My boy taught you the trick...") and the Inner Stair he gives the first **Roll
   Fragment**: he has been perfecting a better trick, the Charged Roll, carved into a training disc
   years ago; Gorge's lot broke it in four and hid the pieces; he kept this one in his boot; find
   the other three (`lair_director.gd` `FRAGMENT_LINES`, `_give_fragment`, `FRAGMENT_ITEM`, flag
   `fatty-lair.burr-fragment`; its toast "Roll Fragment 1 of 4"). A save that freed him before this
   gets it counted quietly on load (`RunState.install`); the four fragments: quests spec 14.8. Then (owner, 2026-10-19) **the drawbridge takes two**: its chains run to two
   plates on the hub's south walk, one body on each, at once; Burr walks to the west one and holds
   it ("That drawbridge takes two ... I'll hold this one. You take the other."). The slime sinks the
   east one: both down, the bridge comes down for good, the short way to the north ledge and the boss
   door. Burr says goodbye, wishes the slime luck and walks out (he waits by the bolt-hole after
   Fatty), once: the flag `fatty-lair.burr-left` (`FLAG_LEFT`) keeps him gone. Left before the bridge
   is down, he is back on his plate each time the hub is built; once it is down he is gone, read from
   the bridge's record before the bridge restores itself (drawbridge.gd `is_down_for_good`; until
   2026-11-20 he stood on his plate on every visit and said goodbye again).
   Alone, the slime sinks its plate in vain.
6. **The Deep:** down the Inner Stair into R8's crypt (Bone Marchers); door 3, an open doorway, into
   R11.
7. **R11:** its lever lifts the inner gate for 500 ms (a Roll north makes it); two slabs north, two
   east; north into **R12 the Larder**, where the shutter shuts behind the slime until the Big
   Squint falls (Pearl 1's glow over the altar all the while).
8. **The Pearl:** Pearl 1 rises on the worms' altar; walked into, its card, the Heavy skin (won and
   worn), Fatty's roar from his hall next door and, for an instant, a picture of R1's seal slamming
   up (made in advance: R1 is another world): the Lair is
   sealed until he falls.
9. **The second half, the Heavy skin:** a Heavy Roll smashes the Larder's north planks (*teach*).
   **C2 the Weigh House** (*teach*): the slime stands on the first plate, turns stony as it sinks,
   and the east door opens while it rises; in the north hall it pushes the statue onto the second
   plate, which holds the west door only while the statue stays. **R10** (*test*): it pulls the
   statue out of its niche and pushes it along the patrolled lane onto the plate while the Dung
   Roller's ball is away; the ball turns back at the statue, and the plate holds R9's stone door.
   **R9** (*twist*): under the Watcher Eye's gaze, a statue pushed onto the plate (or one as cover
   while the slime sinks it) raises the big chest in the south alcove: **the big key**. The chest
   stands only while the plate is held (owner, 2026-11-01: "the pedal has to stay pressed or the
   chest hides again"; the plate's `hold_targets` and `shut_on_leave`): it sinks away the moment the
   weight leaves, so a statue must hold the plate while the slime walks to the alcove. R9's bolt
   opens into R8, the crypt's stair door leads up to the hub.
10. **The hub:** the drawbridge is down since Burr's freeing (step 5): the short way from the entrance
   to the boss door; the north ledge (the calm spot: pots, an energy flower); the boss door with the
   big key.
11. **R13:** Fatty One Eye, enraged (below); his fall breaks the seals. Then **R14 the Postern:** a
   chest with 25 coins and a Slime Tonic, and a Heavy Roll through the bolt-hole's barricade, up to
   daylight by the Verdant Gate, where Burr waits. The Verdant Gate is a grey fallen tree since
   2026-11-20 (owner, question 163: the green key went with the gate): the slime's next Heavy Roll
   breaks it ([SKINS.md](SKINS.md#heavy)).

**The way back after a resume** (a faint or a quit wakes the slime at R1, inside the seal): R1, the
bolt to the hub, the drawbridge (down since Burr's freeing), the ledge, the boss door. Were it still
up (Burr not freed): the hub, the Inner Stair, R8, then door 3 and R11 to the Larder (or R9's bolt,
once opened from inside). Nothing the main path needs lies outside after the take.

Secrets: the map nook (behind R4's west shutter, which sinks when R4's Squints fall), R1's store (planks: the Heavy Roll, inside, after the
Pearl, on the walk back after a faint or at the end; 100 coins), the Weigh House's pouch (a Heavy
Roll into the east wall shakes the old scale pan's pouch down: 30 coins), the Old Armoury (its four sconces lit for good open its
stone door: the Lantern, Chapter 3; its chest holds the war journal's first page since 2026-11-20,
[quests spec 14.8](specs/quests.md#148-finds-the-war-journal-the-recipe-page-and-the-charged-roll-2026-11-20)) and the Glow-moss Burrow (the shadow path: the
Lantern; a goo heart). *Changed 2026-10-19 (owner): the Lair caves in once Fatty falls, so its
come-back secrets move outside ([the plan](../design/2026-10-19-lair-secrets-outside.md)). The sally
port is now `slimeshire-sally-port` (`game/scenes/worlds/rooms/c4/slimeshire-sally-port.tscn`), under C4's
fenced pen below the town wall: the slime drops off the wall into the pen, a Goo Bomb breaks its
cracked ground (`SallyPort/sally-port-crack`, flag `level-1.sally-port-crack`) and it falls in; a
ladder climbs back to `sally-port-way-out` south of the pen. R5's crack is plain wall.* *Changed
again the same day: an open hole in the pen (no bomb), a winding room, the way out a hatch on the
town's east side ([Holes and hatches](#holes-and-hatches)). Linked on 2026-10-31 (they never were):
C4's `SallyPort/sally-port-hole` falls onto the room's landing `sally-port-landing`
(`object.landing`), the room's ladder climbs to C4's hatch `sally-port-way-out`. Since 2026-11-20
its chest (`sally-chest`) holds its planned prize, a recipe page for the Berry Basket (it held two
Slime Tonics).* *The Glow-moss Burrow (2026-10-19) is now
`slimeshire-glow-moss-burrow` (`game/scenes/worlds/rooms/d4/slimeshire-glow-moss-burrow.tscn`, its heart
`slimeshire-burrow-quarter`): in D4's south-west, a dark-forest maze (medium beeches and pines on the
forest layer, two spiders and a worm) on the road down to D5 hides a clearing at the end of its
longest dead end with an old dry trunk over a hole (`object.dry-trunk-hole`,
`Chapter1/burrow-trunk`): the Lantern burns it (`burnt.level-1.burrow-trunk`); burnt, it shows the
mossy hole with its ladder over the ash (the burnable's `reveal`), which the slime climbs down into
the Burrow, whose ladder climbs back beside the ash. The hole and the ladder are a pair (linked
2026-10-31; the ladder's link had been lost): the trunk's `Hole` door `burrow-hole` ↔ the Burrow's
`burrow-ladder`; coming up, the slime rises out of the hole and steps off it to its `arrival`, south
of the ash. R6's tunnel to it is plain wall.* *The Old Armoury (2026-10-19) is now
`slimeshire-old-armoury` (`game/scenes/worlds/rooms/d4/slimeshire-old-armoury.tscn`; its candle group and
gate `slimeshire-armoury`, `slimeshire-armoury-gate`): in D4's north-east a hill (elevation level
2, cells 23-30, rows 1-3) stands where the woods were, its south face hidden behind a row of trees but
for a gap from the statue's garden; there a cracked wall (`Chapter1/armoury-crack`, flag
`level-1.armoury-crack`) whose crack barely shows on the stone (`crack_tint`, alpha 0.42: owner,
"the crack has to match the wall") opens to a Goo Bomb and leads in; the room's east doorway
(`armoury-way-out`) leads back. So the Armoury takes the Goo Bomb to enter and the Lantern for its
chest. R8's doorway to it is plain wall.*

**The cave-in** (2026-10-19, owner: once Fatty falls the Lair is done for good, as a Zelda dungeon).
The Dungeon node's `done_exit_map_id` / `done_exit_point` (`fatty-lair-dungeon.tscn`: `level-1-d4`,
south of the bolt-hole's hatch) make it `collapsed()` once `boss_id` has fallen: "The seals break!"
is followed by "The tunnels are caving in! Get out!", the tunnels shake now and then with falling
dust while the slime is still inside (`dungeon.collapse`), and a faint or a quit wakes it at that
spot outside (the entrance record moves there), never at R1. `game/fattys_lair/lair_collapse.gd`
buries the way in: the mouth in Fatty's Hollow shows its rubble and its door and R1's way out refuse
("Rubble buries the way. The Lair has caved in."). The way out is R14 and the bolt-hole, where the
Postern's chest waits.

**Dev:** F6 on the world gives the Spear and the Roll (`dungeon.devPowers.fatty-lair`), the first
half's powers; the Heavy skin is won at the Larder. To try the second half straight away, lend it:
`?map=fatty-lair-c2-weigh-house&shapes&skins=heavy` (or `?map=fatty-lair&shapes&skins=heavy&room=c2-weigh-house`,
which travels there) on the web, `-- --map=fatty-lair-c2-weigh-house --shapes
--skins=heavy --room=c2-weigh-house` on the desktop (or those user arguments in the editor's run
settings for F6); `?sealed` takes Pearl 1 quietly and seals the Lair.

### The Lair's own pieces

- **Drop gate and worm lever** (`object.drop-gate`, `drop_gate.gd`, `game/world_objects/worm_lever.gd`):
  the old oak gate in its rock mound; the lever (interact key, the interaction's `usable` group)
  raises it over `rise_ms` (220), it stays up `open_ms` (620 outside, 500 in R11) and drops in
  `drop_ms` (140), shoving out a slime caught under it; a push on the shut gate says its line.
  `hold_open_for_good()` keeps it up (recorded as the gate unlocked).
- **Eye latches** (`object.eye-latch`, `eye_latch.gd`) over **divider gates** (since 2026-10-19,
  FENCES.md "Dungeon dividers"; R9's in its doorway is still an `object.latch-door`, its slab the
  wall's shutter leaf): only a thrust (the `spear` tag) shuts the
  eye; a lone latch opens its doors for good; latches sharing a `group_id` (R5's alcove) each stay
  shut `open_ms` and solve their gate only while all are shut at once. With an `order` (1, 2, 3 ...;
  R5's north maze, 2026-10-19) they must be struck in it: struck while an earlier one is still open,
  a latch clinks (`order_text`) and the group's shut latches open again; a latch whose time runs out
  opens every later one of its group with it, so the first one's `open_ms` is the run's time. A timed
  latch's eye flickers in its last 1.5 s. Solved, each latch opens its own `gate_id` and any
  `more_gate_ids` (gates keeping their own ids: R5's inner door, on eye II since eye III was taken
  out). A group is the latches with its `group_id` in the world now, however many the scene holds:
  taking one out of the scene leaves the rest a shorter run (give its gate to another latch's
  `more_gate_ids`, or nothing opens that gate).
- **The plank barricade** (`object.plank-barricade`, `plank_barricade.gd`): only the Heavy Roll smashes
  it (`game/fattys_lair/heavy_check.gd`: a Roll's bonk with the Heavy skin on, which carries the
  `heavy` tag; [SKINS.md](SKINS.md#heavy)); anything else bonks with its line. Kept smashed by
  `flag_id` (`fatty-lair.larder-smashed`, `.store-smashed`, `.bolt-hole-smashed`).
- **Heavy plates** (`object.heavy-plate`, `heavy_plate.gd`; [SKINS.md](SKINS.md#heavy)): two exports
  added for the Lair (2026-10-17). `targets` (NodePaths) are set off each time the plate reaches the
  bottom (DungeonState.fire, as a winch's): R9's raises the hidden big chest. Since 2026-10-19
  `heavy_only` (off: any slime, and Burr, sinks it; the `plate_weights` group) and `pair_id` (plates
  sharing it set off their targets only while all are down at once): the hub's **two drawbridge
  plates**, a pair that is not heavy-only, lower the drawbridge for good when the slime and Burr
  stand on them. `shut_on_leave` shuts its gates the moment the weight
  leaves, so the door is held only while something stands on the plate: the Weigh House's second
  plate and R10's, which a statue must hold (the slime could not stand there and walk through).
  `hold_targets` takes its targets back when it lets go, as its gates shut (DungeonState.take_back:
  a hidden chest's `vanish`, which sinks it with a puff and forgets that it rose): R9's big chest
  stands only while the plate is held.
  The Weigh House's first plate is a plain one (its door stays open while it rises, 5 s). The
  counterweight's chains (`game/fattys_lair/counterweight_chain.gd`, presentation) hang from the
  raised bridge to each plate in its `plates` (the east counterweight plate and the burr plate),
  pull taut as each sinks and go once the bridge is down. It is a tool script: it draws in the
  editor, and its top point is the `Top` Marker2D child (drag it; the plates are dragged where they
  stand).
- **Heavy blocks reset with their room** (the guide's no-softlock rule): since the Lair is one world
  per room, each room is built afresh when it is entered, its statues where its scene puts them, as
  the room's enemies and pots come back (the director's own reset for a world of several rooms went
  on 2026-10-19: every Lair world has one room). A statue pushed into a corner never blocks the way;
  the plates are not saved, the drawbridge is (the big chest only once opened: it rises again with
  its plate, empty).
- **The Inner Stair** (`object.stair-door`, `stair_door.gd` on `stair_hatch.gd`; since 2026-10-24,
  when it replaced the floor hatch and the crypt's ladder): a stair door in the hub's north wall,
  shut until Burr winds it ("Its winch is behind the cell door."); open, the slime walks into the
  doorway, takes two steps down (shrinking and fading into the dark stairwell) and the fade takes
  it to R8; the crypt's stair door up in its north wall (`crypt-north-stair`, open from the start)
  climbs it back up the same way (the second half's way back to the hub). Only the slime's picture
  walks (the player's effects channel, door.gd `effect_step`). The two are paired (2026-10-31,
  `target_door`: [design/2026-10-31-crossings-and-arrivals.md](../design/2026-10-31-crossings-and-arrivals.md)):
  the slime comes out of the other stair door, up out of the dark or down the flight into its
  doorway, and walks out facing down, at the door's `arrival_offset` (the crypt's at the old
  marker's spot, the hub's just below its well). The old arrival markers went on 2026-10-31. The playground has a pair in
  one world (`stair-door-test`) and one into another world (the crossings corner's cellar).
- **Burr** (`character.burr`, `game/fattys_lair/burr_actor.gd`) and **the Lair's director**
  (`game/fattys_lair/lair_director.gd`): his call the first time the slime comes into the hub
  (flag `fatty-lair.burr-called`), his freeing when his door opens (`fatty-lair.burr-freed`), the
  Inner Stair's door, his walk to his plate (`burr_plate`) and his hold there while the drawbridge (`bridge`) is up,
  his goodbye and walk out once it is down; Fatty's phase two, the clods and the arena's shutter;
  blocked gaps (`blocked_gaps`, `gap_flag`; none since R4's room fight took the map nook's gap,
  2026-10-28); the Larder's glow, which goes once Pearl 1 is taken. One world per room: a director
  stands in each room that needs one with that room's paths (the hub's: Burr, who stands in the
  hub's world behind his cell door; the arena's: Fatty, the map's boss mark; the Larder's; R4's,
  with none set).
- **Fatty's fight** (`fatty.gd` `configure_phase_two`, its `phase_two_*` exports; the clods: the
  director's `_on_clods_requested`; [specs/boss.md](specs/boss.md) section 3.8), the owner's rework of
  2026-11-21: his eye is his weak spot, the Spear hurts him there and a thrown thing for half a Spear
  hit (6). Every leap cycle's last landing brings dirt from the roof: the clods from the last fall
  melt away (leaving nothing), and new ones (6 in phase one, 10 in phase two) fall at the arena's
  clod spots picked at random and scattered a little, after a shadow (`game/fattys_lair/clod_shadow.gd`),
  hurting where they land and lying as liftable `mud-ball`s, the slime's ammo (a used one leaves a heart
  or an energy shard: `under`, liftable_root.gd; a Roll breaks one: `clod_hurtbox.gd`). **Phase one:** a
  hit that lands shuts his eye for 3 s, every hit clinking meanwhile. **Phase two** (under half his
  health): he leaps twice in a row, the first landing sending a mud ripple over the floor
  (`game/fattys_lair/mud_ripple.gd`) that a Roll's i-frames carry through, the second bringing the dirt;
  his eye stays shut, but two thrown things (a leap does not reset the count) knock him down for 3 s:
  "Off balance!", he lies back and wobbles, stars over him, his eye wide open, and the Spear lands (a
  throw for its half); the first hit ends the fall. No Heavy Roll any more (a Roll bonks off him): the
  Lair's second half tests the Heavy skin. Enraged while the Lair is sealed (the kit's `EnragedLook`,
  the same numbers). Beaten: the dungeon records him, the seals break, the power he soaked up pours
  from him into the Pearl the slime carries (the director's sparkles, a flash of light on the slime)
  and his full heart shows (`object.full-heart`, `fatty-one-eye`: +20 max HP and max energy, as every
  boss's; the Pearl plan's open point 12). *Until 2026-11-21 phase two was the Heavy skin's exam (a
  thrown mud ball threw him out of balance, a Heavy Roll knocked him down) and the clods fell only then.*
- **The Pearl** (`object.pearl`, `pearl.gd`, on `decoration-world-solid--pearl-altar`): Pearl 1 lies
  on the worms' altar in the Larder, its `boss_id` the Larder fight's (`fatty-lair-big-squint`): it
  rises once the Big Squint falls. A warm glow and a glint over the altar show from the door all
  through the fight. Walked into from any side of its altar, it plays its card, sets
  `pearl.fatty-one-eye`, grants and wears the Heavy skin (`skin_id`: SkinState.grant,
  [SKINS.md](SKINS.md)) and seals the Lair ([The seal](#the-seal): Fatty's roar, the picture of R1's
  seal).
- **The interaction's `usable` group** (`interaction_controller.gd` USABLE_GROUP): any node with
  `origin()`, `interact_radius`, `prompt`, `badge_rise`, `use()` and an optional `can_use()` is
  offered to the interact key (the worm levers, Burr outside).

### Outside: Fatty's Hollow and the bolt-hole

The way in is on D5's hill (`level-1-d5`, since 2026-10-17; until then at (192, 1012) in D4, the
old camp clearing's north-west edge), the way out by the Verdant Gate in D4 (`level-1-d4`). D5 is
built by `tools/build_slimeshire_chunks.gd` (its map: [Chapter 1](../story/chapters/chapter-1-the-clearing.md#slimeshires-places-built-2026-10-17)).

- **Fatty's Hollow** (D5): a red-rock hill (level 3) crowned with maples; in its south face a
  notch (level 1) holds the mouth, over a paved forecourt (level 1: the worms' campfire, crates, a
  pot hiding a heart, an energy flower). In front of it the old fort's field, a maze of fieldstone
  walls cut by a dry moat (a void hole, the kit's `object.hazard` with two `Return` points) that a
  bridge of two falling slabs crosses: one Roll from the rim's edge; a walk drops the slime and puts
  it back on the rim (`damage` 5). Stairs climb from the maze's far end to the forecourt; its west
  rim is a ledge drop back to the maze's door.
- **The hill crack** opens `hollow-hill-cave` with the Goo Bomb: a separate cave room,
  pots and a chest hiding `meadow-autumn-thicket`; the former visible hill pocket is closed.
- **The way in** (`object.fatty-lair-mouth`, `game/scenes/objects/fatty-lair-mouth.tscn`, at
  (1401, 704) in D5, the notch's foot, since the map edits of 0a6b9954): the drop gate (`fatty-lair-gate`, `map_id` `level-1-d5`,
  `open_ms` 620; its lever 3.7 cells in front of it, `interact_radius` 46), a closed mound round the
  passage behind it, and the north door `fatty-lair-mouth` into R1; coming out, the slime walks out
  of the gate's doorway even when the leaf is down. The race, tuned for the quick Roll (the story's
  Roll: a run after the prologue plays in the body-shapes mode) and filmed 2026-10-17: pressed 0,
  150 or 250 ms after the lever, a quick Roll north passes under the leaf at 0.48, 0.65 or 0.73 s,
  before it starts to drop at 0.87 s; a walk, even with north held as the lever is pulled, reaches
  the leaf as it drops and is pushed back. The classic Roll (its 260 ms spin-up; runs without the
  shapes) only makes it pressed at once. The node is in group `boss_way_in` (metadata `boss_id`), so the tracked quest's "Defeat
  Fatty One Eye" points at it in D5 (`game/quests/quest_waypoint.gd`). `world-chunks.json` lists
  both mouths under level-1's `doors`.
- **Fatty's old camp left D4** with its guarded chest (the green key went to the shrine, then to the
  Postern; since 2026-11-20 nothing needs it, question 163). The camp's
  scene, `encounter.level-1-fatty-camp`, stays as the boss-camp tests' fixture
  (`godot/tests/lib/fatty_camp_fixture.gd` puts it back in the clearing for `test_boss.gd`,
  `test_audio.gd`, `test_chest_window.gd`, `test_interaction.gd`).
- **The bolt-hole's mouth** (`object.fatty-lair-bolt-hole-mouth`, at (1408, 960), south-west of the
  Verdant Gate; `game/fattys_lair/bolt_hole_hatch.gd`): a hatch kept shut over an arrival-only south
  door (nothing leads back down). When the slime climbs out it shows open; once the slime is
  `dungeon.boltHole.clearPx` away (after `minOpenMs` at least), or after `closeAfterMs` at most, it
  slams shut behind it with a thud, dust and a shake (`shakeMs`, `shakeIntensity`), so the Lair cannot
  be entered that way (owner, 2026-10-18).
- **Burr outside** (`character.burr-outside`, `game/fattys_lair/burr_outside.gd`, beside it): there
  once he is freed and Fatty is beaten; talked to, he says the town must see the Pearl and walks off
  home (flag `fatty-lair.burr-outside`).

### Limits

- R2's landing shows the kit's flat deck floor.
- R1's seal stands in the south doorway at the room's bottom edge, where the HUD's bar covers half
  of it while the slime is in R1; the take's glimpse is a picture made without the HUD
  (`tools/capture_lair_seal.gd`).
- The Weigh House's, R5's, R7's and the Armoury's latch doors are divider gates in low dividers
  (FENCES.md "Dungeon dividers"; the Armoury's divider is fort stone in a cave room until the cave
  style is made).
- Not built: the journal pointing home after Burr's talk (question 103, roadmap 5.17),
  the worm mural, Fatty's shrinking into a small calm slime (his built death clip plays), the
  drill hall's weights (the plan's other way for his exam). *Heart quarters were listed here until
  2026-10-26, when they were built: the Burrow's goo heart is one (`slimeshire-burrow-quarter`).*
- The clods' art is the liftable `mud-ball`; a generated clod picture was not used.

### Separate room scenes and integrated doorways (2026-10-17)

The three dungeons now have 60 editable room scenes assembled by a shared shell, retaining
their dungeon ids, puzzle paths and records. F6 on a room starts there. The camera covers
anything beyond the current outline with darkness; Burr's cell is separate from the
L-shaped Pit Hall. Doorways use the wall's own courses with two-cell arches (root arches
in the Hollow, timber in the Mine), and moving leaves/blocks sit inside them. See
[Dungeon room scenes](DUNGEON_ROOMS.md) for editing, builders, art packing and checks.
*As built (2026-11-25): no dungeon is assembled from room scenes any more. Fatty's Lair is one world
per room since 2026-10-18, the Weaver Hollow and the Crystal Mine since 2026-11-25; the Hollow's four
floors (assembled from `RoomScenes`) and the Mine's one world went at step 5, with the room splitter
(`tools/lib/dungeon_room_splitter.gd`) and the doorway frames (`doorway_art.gd`). The shell
(`room_scene_shell.gd`) still assembles the box-room lab.*

**Interior walls (2026-10-18, awaiting the owner's verdict):** the replacement for these cliff walls
and doorway frames is the InteriorWallLayer ([INTERIOR_WALLS.md](INTERIOR_WALLS.md)): a room scene
paints its rim two cells thick and the wall is Zelda's bevelled frame, four sloping faces mitred at the
corners, every opening cut into its face; the door objects take `frame_drawn_by_wall` and draw only their leaf or block. So
far only the box-room lab (`?map=box-room-lab`) uses it.
