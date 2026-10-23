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
back, the dark rooms' shadow path and glints, and the seal that the Pearl's take sets until the
boss falls. Each dungeon's own pieces (its boss, its lock looks, its enemies) are built by its own
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
  drawn by interior walls ([INTERIOR_WALLS.md](INTERIOR_WALLS.md)); the Weaver Hollow and the Crystal
  Mine add continuous wall courses and matching opening pieces through `doorway_art.gd`
  ([room scenes](DUNGEON_ROOMS.md)). A doorway two cells wide through a wall painted on
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
  the Silk skin and the Lantern), lent for the session in the body-shapes mode, with the autosave
  off ([CONVENTIONS.md](CONVENTIONS.md#running-a-world)). A new dungeon world gets a line there; a
  room world of a dungeon of one world per room takes its dungeon's line (`fatty-lair`).

## Keys and the map

The dungeon items (`game/dungeon/dungeon_items.gd`): **small keys** (a counter, never a bag item),
the **big key**, the **map**, the **compass**. Their icons are the 2 x 2 sheet
`godot/asset/UI/items/dungeon-items.webp`. Getting one: the ceremony (`AbilityCeremony.request_entry`)
for the big key, the map, the compass and the run's first small key; later small keys are held up
over the slime for a moment (`item_pop.gd`) with "Small Key!" and a jingle.

- **In a chest:** put `"dungeon-small-key"`, `"dungeon-big-key"`, `"dungeon-map"` or
  `"dungeon-compass"` (count 1) in a dungeon chest's `initial_contents` (below).
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
  not drawn; the room the slime is in has a gold ring. With the compass, a red mark is on the boss's
  room (a room fight with a `boss_id` not beaten, or a node in group `dungeon_map_mark` with
  `mark = "boss"`) and a gold dot on every chest not opened yet. The HUD minimap
  (`dungeon_minimap.gd`, under its player dot, clipped to its box) shows **the slime's room only**,
  with the seals and compass marks inside it (`only_current`; owner, 2026-10-19: in Fatty's Lair the
  rooms around it, drawn at the minimap's scale, covered the play area); the rooms found are on the
  map screen.

## Chests

`object.dungeon-chest` (the wooden chest) and `object.dungeon-big-chest` (the big chest, for the big
key): `game/dungeon/dungeon_chest.gd` on the `ChestScript` child, which is the game's chest
(`chest.gd`: its record, the "Open chest" prompt, the chest window) plus:

- the dungeon items in `initial_contents` go straight to the dungeon when it opens; any loot beside
  them ("coins", potions...) opens the chest window as any chest;
- `hidden`: not there until set off (a room fight's `reward`, a winch target, any signal on
  `appear` or `trigger`): it rises with a puff and the secret jingle, and stays;
- `map_id` and `instance_id` may stay empty: the world's id and the chest root's name.

**A Goo Heart inside** (owner, 2026-10-17: most hearts are hidden in chests): any chest, the world's
(`game.chest`, `chest.gd`) or the dungeon's, has `goo_heart_id` on its `ChestScript` (empty: no
heart; a heart id unique across maps, as an `object.goo-heart`'s `heart_id`). Opening it the first
time lifts the heart out of the chest (it rises over it, `item_pop.gd`) and grants it exactly as the
pickup does (`goo_heart.gd` `grant`: the flag `goo-heart.<id>`, +`gooHeart.maxHpBonus` max HP, health
full), once; the chest shows the max-HP text and asks for the ceremony once the heart has risen
(`HEART_RISE_MS`, 1.5 s of gameplay time; a load or a travel meanwhile skips them). The flag is the
chest's record: it holds something until the flag is set, and is open (empty) after, in every save.
With only the heart inside no chest window opens; with other things too (or a dungeon chest's loot
beside its dungeon items), the window shows them after the heart has risen and its ceremony has
played, as Zelda does (the window pauses the world, which would freeze the rise). The chest sends
one `open_requested` as it opens.

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
  room and as far from each of its shutters, while one of its enemies stands, every shutter with its
  `fight_id` shuts. Its enemies: the PlacedEnemy nodes in `enemies` (or anything with
  `is_standing()` / `is_defeated()`), else every placed enemy in its room. With none standing, after
  `dungeon.shutter.openDelayMs` the shutters open and `reward` is set off (a hidden chest, a
  drawbridge). `once`: an ambush won once never runs again and its enemies never come back.
  `boss_id`: a boss or mini-boss fight (once by itself): won, the boss is recorded beaten; the
  compass marks its room until then. Fainting or leaving the room ends a fight unwon (the shutters
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
  wins), else that ground. A form that swims (the Frog) never falls in; enemies never fall.
- **The lane:** every plank and landing opens the deep water's collision under its cells when the
  world is built (`plank_look.gd` adds a `bridge_deck.gd` child, docs/godot/specs/water.md §10), and
  the cells stay open after a plank falls, so the slime over a fallen plank is caught by the hazard,
  never held or pushed by the water. The lane is one cell wide; deep water on both sides keeps the
  slime on it.
- **A long bridge with no landing** (the owner's come-back secret) is crossed only by a Roll that
  keeps rolling: in the body-shapes mode (the story's mode after the prologue) the **charged Roll,
  the `roll-charge` upgrade** (planned, not yet given anywhere in the story:
  [05-unlock-map.md](../story/05-unlock-map.md)), held all the way; in the classic game the Roll
  held. The quick Roll (one or two planks), quick Rolls in a row (the cooldown is longer than the
  fall delay) and walking fall in. A bridge meant for the quick Roll needs a landing every two planks.
- Tried in the plank lab, `world.playground-planks` (`game/dev/planks/playground-planks.tscn`, built
  by `tools/build_plank_lab.gd`; `?map=playground-planks`): an eight-plank bridge with no landing,
  a stepped bridge (two planks, a landing, two, a landing, two), and the heart chests on the island.
  `tools/film_planks.gd` films it. Tests: `tests/test_falling_planks.gd`, `tests/test_heart_chest.gd`.

## Holes and hatches

The ways down and up, for any world (owner, 2026-10-19), in the Scenery dock's **Holes & hatches**
category (placed under `Objects`; set the DoorScript's target in the Inspector):

- **Open hole** (`object.open-hole`, `scenes/objects/open-hole.tscn`): broken flagstones round a
  black shaft (`goo-bomb/floor-hole.webp`), always open: stepping in, the slime falls (`kind` `fall`)
  to `target_area_id`, landing on the Node2D `target_marker` there. One-way.
- **Open hole with a ladder** (`object.open-hole-ladder`): the grassy hole with a ladder
  (`gulp-props` frame 1), `kind` `ladder_down`, its `arrival` child below it for the way back up.
- **Cracked floor** and **cracked ground**: the same holes, shut until a Goo Bomb blast (or a Heavy
  slam) breaks them (`cracked_floor.gd`, `cracked_ground.gd`); **cracked wall**: a cave mouth or a hole
  in a wall the bomb opens (`cracked_wall.gd`).
- **Hatch exit** (`object.hatch-exit`): the trapdoor (`stair-hatch-2x1.webp`) a way up arrives at:
  arrival only (set `door_id`, point the ladder's `target_door_id` at it); it opens as the slime comes
  out and slams shut behind it (`bolt_hole_hatch.gd`, the bolt-hole's; `dungeon.boltHole`).
- **Stair hatch** and **cave ladder**: the Lair's hatch down, the cave's ladder up.
- **Hill doorway** (`object.hill-doorway`): an old fort-stone doorway with two cold iron sconces, for a
  hill's face, always open (a DoorScript of side north; set its target).
- A cracked wall's `crack_tint` (2026-10-19) tones its crack to its rock: a lower alpha hides a
  secret crack in the stone.

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
`crystal-mine-shardback`): it rises when that fight is won. The compass marks only the dungeon's
boss (the Dungeon's `boss_id`), not the guard. `seals_dungeon` (on by default) is what makes its take
seal.

**The take.** Walked into: its card ("Pearl of the Wellspring (n of 8)"), its skin granted
(`SkinState.grant`; the everyday look stays as it was: a skin shows only while it works,
[SKINS.md](SKINS.md)), and the Dungeon's `seal_now`: the record is sealed at once
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
| `spikes.damage`, `spikes.fallMs`; `lava.damage`, `lava.fallMs` | 8, 320; 12, 320 | a hit each time the invulnerability ends; the drop into the pit |
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
  from both rooms.
- The void watches the player only: enemies do not fall (they keep to their wander areas and do
  not drop off rims).
- Rooms reset only within one world: a dungeon of several worlds rebuilds a world on each travel
  (all its enemies and pots back), as any world does.
- The map shows the rooms of the world the slime is in.
- **The seal:** a seal in a south doorway shows the turned block (as every kit piece there); at a
  world's south edge (the lab's B3, most entrances) half of it lies under the HUD console. The
  dungeon's music does not carry the boss's drums while sealed (the plan's open point 4: only the
  far-off roar is built). No journal has a Pearl slot yet, so the take lights none (the flag
  `pearl.<id>` is there for it). The boss bar shows only for bosses with a camp (Fatty, the Matron,
  the Colossus), not for a room-fight boss such as the lab's Big Squint. The first travel refused
  while sealed reads its target world's scene once (a short hitch).
- **Music (2026-10-18):** every dungeon world (each of Fatty's Lair's 22 room worlds, the four
  `weaver-hollow-*` floors, `crystal-mine`) has a `MusicPlayer` playing `asset/audio/music/dungeon.wav`
  (volume 0.5); a room scene of a shell has none (the shell's plays through all its rooms). A travel
  between two floors keeps the track's place (it dips with the leave fade and fades back in); the
  Lair's room-to-room scroll keeps it playing. Every boss fight
  with a camp crossfades to `audio.global`'s `BossMusic`, `boss-fight.wav`
  ([audio spec §1.2](specs/audio.md#12-authored-audio)).

## The Crystal Mine (built)

Chapter 3's dungeon, built 2026-10-17 from [its design](../design/2026-10-16-dungeon-crystal-caverns.md)
and reworked the same day for the Pearl inside it, before the Colossus
([the plan](../design/2026-10-17-pearl-mid-dungeon.md#the-crystal-mine-chapter-3-the-feral-skin); as
built, below; the design's [status](../design/2026-10-16-dungeon-crystal-caverns.md) lists what moved).
One world, `world.crystal-mine` (`game/scenes/worlds/crystal-mine.tscn`), 80 x 70 tiles: a 5 x 5 grid
of screens, 14 camera rooms, 7 of them dark. **Built by a tool:**
`"<Godot console exe>" --headless --path godot -s res://tools/build_crystal_mine.gd [-- --dry]`
rebuilds the whole world (hand edits are lost), then bake its elevation
(`tools/bake_elevation.gd -- --world=crystal-mine`). Its code is `godot/game/crystal_mine/` and the
Colossus's `game/scripts/crystal_colossus.gd`; its art `scripts/art/pack-mine-art.py` (sources and
prompts in `asset/Originals/mine/`). Tests: `godot/tests/test_crystal_mine.gd` and
`test_mine_camp.gd`.

**Its shape** (the plan's dungeon template): the first half uses what the slime brings and is the
Lantern's (six dark rooms, the maze), the Heavy Roll's and the Bow's (the Chasm, its last lock); the
Shardback guards **Pearl 3** in his Den; its take seals the mine; the second half teaches the
**Feral skin** (teach, test, twist, then the known way down); the Colossus is its exam. About 40
minutes with the camp, 13 rooms on the main path.

- **The paint:** every cell is rock at level 2 (its top crystal floor, so its walls are crystal rock
  and it never reads as a room's floor; masonry and cobble round the old fort's hall); each room is
  carved out to level 0 with cavern floor and a one-cell rock border, the Den to level -1; doorways
  are two-cell gaps (an east or west one also clears the two rows its lintel hangs over). Holes: M2's
  two void pits (-2), the Dark Maze's void (-2), the Chasm (-3), the Great Shaft's floor with the
  boss door's way (-2), M11's rift (-2) and the Colossus's arena (-2). Raised: the S5 shelf in M1
  (1), the maze's inner walls (1), the shaft's spire (0), the Den's ledge (0, one level over its
  floor), M12's balcony (2) with the hall's north band and corner blocks at 3 (so the balcony never
  joins the mine's rock top). A front flight of stairs (the `elevation` layer's stairs row) leads from
  the Chasm's far rim down into the Den. The gallery's rim is fenced (`fences` layer) but for the
  spire plank's foot.
- **Kit pieces used:** the Dungeon (`crystal-mine`, "The Crystal Mine", resume at
  `dungeon-entrance` in M1; the seal's `boss_id` `crystal-colossus`, `boss_name` "The Crystal
  Colossus", `seal_color` smoky violet `#8a68c0`, his roar `fatty-roar.ogg` at pitch 0.6, crystal dust
  `#c8d4f0`), a floor key (K1), six chests (K2, the map, S1, S4, S5, M10's) and the big chest (on
  M12's balcony), the Foreman's Gate (`key-door`, two keyholes), the boss door, four shutters (M1's
  iron shutter `starts_shut`, the Den's north fight shutter, its two south rim shutters
  `starts_shut`), two seals (`object.dungeon-seal`: M1's mouth, `glimpse`; the climb-out's foot), the
  Den's room fight (`once`, `boss_id` `crystal-mine-shardback`), the crank (`winch` in M7, M1's
  shutter), two drawbridges (the Chasm's, the spire plank), four void hazards (`draw_look` off,
  `Return...` points), the shadow path, six pots that grow back, an energy flower and five prize
  glints (Pearl 3's goes once it is taken: `crystal_mine.gd`). `KitMarkers` keeps a marker for what
  nothing builds yet: the war journal's pages and S1's heart quarter (S1, S5 and M10's chest hold
  coins until then).

### The rooms

Screens by column (0 to 4, west to east) and row (0 to 4, north to south); the main path in order.

| Room | Screen | What is there |
|---|---|---|
| M1 Mine Mouth | (1, 4) | the entrance from the camp (south doorway; **the seal** stands in it from Pearl 3's take until the Colossus falls, and the take's glimpse shows it slam up), the resume marker, the empty cart station ("The cart is at the far end of the line."), the iron shutter in the east wall (lifted by M7's crank), the root wall up to the S5 shelf (Feral, a come-back after the Pearl) and its chest, pots |
| M2 Lamp Tunnel | (1, 3), dark 1 | rails north, two void pits west of them (a fall: back at the south door), three sconces (60 s) that light it for good, a pot that grows back |
| M5 Tally Room | (0, 3), dark 2 | west of M2: the desk, four crystal pillars, a Gloomling on K1 (a floor key); the cracked wall in its north wall (the Goo Bomb, S2) opens the way to M3 |
| M3 Survey Office | (0, 2), lit | optional: the map chest on the surveyor's table, a Crystal Crawler round its pillar |
| M4 The Great Shaft | (1-2, 2), lit | the hub: the gallery (two braziers burning for good) round the shaft (-2), the ore lift's two landings, the spire with its lens (the Bow) and the S1 chest; north the Foreman's Gate (two keyholes); the shaft's north wall: the roots down from the Den's broken rim (seen from the gallery on the first visit); M14, the shaft floor: pots (two hearts), an energy flower, the boss door east |
| M6 Bat Gallery | (2-3, 3), dark 3 | three Glint Bats over the rails, two sconces, the rotten timbers in the south-east doorway (a Heavy Roll), the S3 nook in the east wall behind a web wall (the Silk skin) with a silk parcel |
| M7 Ore Store | (2-3, 4), lit | east half: the Pick Mole behind its crates, K2 in the chest behind it; west half, past the divider: the Bone Leaper alone, and the crank that lifts M1's shutter |
| M8 The Dark Maze | (0-1, 0-1), dark 4 | four corner candles (60 s, group `dark-maze`): all four at once open the exit gate (the mine's lantern gate) for good; the goal brazier burning beyond it; the void across the middle with the shadow path over it; two Gloomlings (one smothering the north-west candle, one on S4's chest), three Glint Bats, a pot |
| M9 The Chasm | (2, 0), dim | the first half's last lock: the cart station (the cart starts here), the chasm (-3) with the raised drawbridge on the far rim and the lens beside it (an arrow lowers it, rows 8 and 9), the Bone Thrower on the far ledge, crystal vein glows; the far rim's way on is the stair down into the Den (x 44, 45); its old door east to M10 is bricked |
| M13 Shardback's Den | (2, 1), dark 6, level -1 | **the Pearl room.** The Shardback (two braziers, 20 s, `stomp_puts_out`: fire light makes his shell brittle); the room fight (`once`, `boss_id` `crystal-mine-shardback`) shuts the north shutter at the stair's foot; won, it opens and the two shutters of the broken south rim sink for good. Pearl 3 (`pearl-three.tscn`, `boss_id` the Shardback's) on its crystal cradle among four crystal clusters, its glint seen from the stair through the fight: it rises when he falls. **Teach:** the ledge (level 0) in the north-east holds the east door; its root wall (one level) is the Feral skin's first lock, a climb back down beside it |
| M11 Crystal Veil | (3, 1), dark 5 | **Test:** the rift (-2) between the west landing (the Den's door) and the east landing (M12's door): climb down the west landing's face, cross the rift's floor, climb up the east landing's (each face two levels, each with a climb down from its lip); a pot. The optional Lantern wing: the veil across the mouth of the doorway north to M10, its brazier on the east landing (20 s) and one on M10's side, two Glint Bats roosting over it |
| M10 Prism Gallery | (3, 0), lit | optional (the Lantern wing): the Prism Eye, the iron-banded ore crate (a heavy block), the chest of the war journal page that lay on M12's stand (30 coins until pages exist), the veil's far brazier |
| M12 The Fort Hall | (4, 1), lit | **Twist:** cobble and masonry; the balcony (level 2) along the north wall with the big chest (the big key), two root walls up its face (x 68 and 75); the Watcher Eye's beam finds a climber, the Bone Marcher's loop passes the walls' feet; five armour statues (heavy blocks, cover, three cells or more from the roots), two watch-fires; a drop off the balcony's west end lands by the west door |
| M15 The Colossus's Arena | (3, 2), dark | **the exam:** four braziers (until put out), the Colossus, four root walls on the north wall beside his three climb spots (they end on the face, `holds_at_top`), the climb out to the Lookout (its seal at its foot until he falls), his full heart |

**The second half's way:** from the Den up its ledge, through M11 (down, across, up), M12's balcony
and the big key, back through M11 and the Den, then down the roots of the shaft's north wall from
the Den's broken rim to the shaft floor (or let go: no cost), the boss door. The roots are also the
short way up from the shaft floor to the Den. **The way back after a resume** (the mouth sealed
behind): M1, the cart to the Chasm (it runs both ways, both stations inside the seal), the stair to
the Den; or M1, M2, the hub, the lift (once raised from the floor), the shaft floor and the boss door.
Nothing before the Chasm needs the Bow; a slime without it rides the cart to M1, walks out, and comes
back with it (all before the Pearl). The big key cannot be had without the Pearl: M11 and M12 are
reached only up the Den's ledge.

### The mine's own pieces (`game/crystal_mine/`)

- **Mine cart** (`mine_cart.gd`, `object` scene `mine-cart.tscn`): two stations of one line
  (`line_id`, `station_id`); the cart starts at `starts_with_cart` (the Chasm). The interact key at
  the station that holds it rides to the other (`mine_travel.gd`: a fade out, the slime and the
  camera there, its level taken, a fade in), and the cart moves there (RunState object state
  `mine-cart:<line>`). An empty station tells "The cart is at the far end of the line."
- **Ore lift** (`ore_lift.gd`, `ore-lift.tscn`): a lower and an upper landing. Worked from below
  ("Work the crank: ride up") it rides up and works from then on, both ways; from the gallery
  before that: "The lift is down. Its crank is down there." (object state `ore-lift:<id>`).
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
  ([SKINS.md](SKINS.md#feral)) a held interact climbs it to `top` and back, letting go drops the
  slime unhurt, the level is taken at the top. The builder places them in pairs (`_climb_pair`: the
  climb up from the foot and the climb down from the lip, sharing the roots' picture): the Den's
  ledge (one level), M11's two faces and M12's two (two levels), the shaft's north wall (one level,
  from the Den's rim at -1 to the floor at -2), M1's S5 shelf. M15's four `holds_at_top` (added
  2026-10-17): the climb ends on the face, the slime clings at his height until it lets go or climbs
  back. The climb out (`exit_area_id` `crystal-caverns-h4`, `arrive-from-crystal-mine`) refuses
  while the mine is sealed.
- **The rails** (`mine_rails.gd`): drawn rails along `points` (the leading line), no collision.
- **The world script** (`crystal_mine.gd`, node `CrystalMine`): keeps each placed enemy to the
  camera room it stands in (its arena), so bats, eyes and Gloomlings fight in their own room.
- **The small golem** (`small_golem.gd`): the Colossus shrunk back once beaten; presentation only.

### The Crystal Colossus (roadmap 12.4)

`character.crystal-colossus` (`game/scenes/characters/crystal-colossus.tscn`,
`game/scripts/crystal_colossus.gd`, a patterned enemy; 240 health; his numbers in
`enemy-types.json` `crystal-colossus.pattern`; nine poses in
`godot/asset/MAPS/enemies/384x384-tile_9x1-crystal-colossus.webp`, the ninth his stun). His arena is
`colossus_arena.gd` (node `ColossusArena` in M15), a boss camp for the HUD's boss bar and the boss
music, and the compass's boss mark (`dungeon_map_mark`) until he falls. The slime arrives with the
Feral skin, the mine sealed: his fight starts enraged in look (`EnragedLook`, the seal's: his
strength the built one).

- **The start:** the slime's centre in `arena_rect`: crystal grows over the way in behind it
  (`seal_cells`, the BreakGlass cue and a shake), the four braziers go cold, he stands at `post` and
  wakes after `wake_ms` (1200) with a roar. A slime at his wall's foot or on it (`wall_rect`) is in
  the fight too.
- **On the floor, the Lantern's exam (as built):** the braziers (candle.gd, `burn_ms` -1: they burn
  until put out, `stomp_puts_out`): while all four burn his weak spot is open (`set_exposed`): a plate
  of his armour cracks open on a side picked at random (front, back, left or right), glowing; he
  reels for `reelMs` (1800) when it opens. Every hit clinks off his crystal except the Spear's (tag
  `spear`) on the open weak spot from its side (the hit's source within `weakSideDot` 0.45 of that
  side's direction). **His stomp** (the tell: a foot raised for `raiseMs` 650 over a darkening ring
  `stompRx` x `stompRy` 116 x 78; within `stompRangePx` 120 of the slime or every `stompEveryMs`
  2600): 24 damage in the ring, and it puts out the lit `stomp_puts_out` brazier nearest to him
  (`stompPutsOut` 1; `CandleScript.put_out_near` nearest only), so the weak spot shuts.
- **On the wall, the Feral skin's exam (2026-10-17):** after `stompsPerClimb` (3) stomps he leaps
  onto the north wall at the climb spot nearest the slime (`climb_spots`: x 51.5, 54.5, 57.5) and
  clings for `climbMs` (5200), throwing a Crystal Mite down every `throwEveryMs` (1300;
  `mitesPerClimb` 2, at most `maxMites` 4 alive; at a climbing slime the mite drops straight down the
  face onto it, `climberHitPx` 30, and its hit knocks the slime off: no cost but the hit). Roots run
  up the wall beside each spot (x 50, 53, 56, 59). The slime climbs them to his height and strikes
  his gripping claws with the Spear from the face (the strike while clinging: an attack press aims
  the Spear left or right along the face, player.gd `_climb_strike`, at the Feral tempo); while he
  clings his hurtbox rides up the face with his pose and only a Spear hit from a climbing slime
  counts (no damage). **`clawHits` (3)** and he loses his grip: he crashes down `fallDropPx` (70) from
  the wall over `fallMs` (450) with no landing stomp (no brazier goes out), a hard shake, and lies
  stunned **`fallStunMs` (2500)**, sprawled, his back cracked open: any Spear hit lands, from any
  side. Then he gets up and fights on. If the slime does not reach him, he leaps down at it as built
  (kept on his floor: a landing ring, `landPutsOut` 1 brazier).
- **His second phase** (below `phaseTwoShare` 0.5 of his health; named so in code since 2026-10-17,
  not the Pearl's rage): quicker stomps, more mites, and a landing puts out two braziers.
- In the rework mode a killed mite can drop an energy shard (the generic `combat.energyShard` roll);
  the arena holds no other refill.
- **Fainting** or leaving the arena while he stands starts it over (he goes, the mites go, the
  braziers go out, the crystal over the way in goes).
- **His fall:** he joins `defeated_boss_ids` and the dungeon's beaten bosses, which breaks the seal
  ("The seals break!": M1's and the climb-out's seals sink); the soaked-up power gone, his heap sheds
  and a small calm crystal golem walks out of it and off (`small_golem.gd`, real time); the four
  braziers burn for good (the cavern is lit); his **full heart** (`object.full-heart`,
  `crystal-colossus`, +20 max HP and max energy) rises; the way in stays shut, so the way out is the
  climb up the roots at x 61, to the Lookout (H4).

### Darkness and fire in the mine

[DARKNESS.md](DARKNESS.md) has the pieces: candles that burn until put out (`burn_ms` < 0), `put_out`
and `put_out_near` (the Shardback's slam ring puts out the Den's braziers, the Colossus's stomp the
nearest of his four), and candles a Gloomling smothers (the Dark Maze's north-west candle refuses a
flame while one sits on it: "The shadow smothers the wick."). The dark rooms: M2 and M6 light for
good once their sconces burn; M5, M8, M11, M13 stay dark (in M11 the slime's ember shows the rift's
handholds); M15 lights while its four braziers burn, and for good once he falls.

### Dev

- **F6** on `crystal-mine.tscn` lends `dungeon.devPowers.crystal-mine` (the Spear, the Roll, the
  Heavy and Silk skins, the Goo Bomb, the Lantern): the first half. The Feral skin is won in the Den.
- **The second half without playing the first:** `?map=crystal-mine&sealed` (desktop
  `-- --map=crystal-mine --sealed`) takes Pearl 3 quietly (the Shardback's fight finished, Feral won)
  and seals the mine; add `&room=M11-crystal-veil` (any camera room's name) to start there. To lend
  Feral alone (unsealed): `?skins=feral` (`-- --skins=feral`, also in the editor's Main Run Args for
  F6).

### Outside: the camp, the Lookout, the cave road

`"<Godot console exe>" --headless --path godot -s res://tools/build_mine_outside.gd [-- --dry]` lays
them into three Crystal Caverns chunks (then bake: `tools/bake_elevation.gd --
--world=crystal-caverns-g4,crystal-caverns-h4`). Its nodes live under `MineOutside`, replaced on each
run; inside its rects it takes out the placeholder's props, trees and worm camps and lays cavern
floor; it owns G4's and H4's `elevation` layer.

- **G4, the smith's mine camp** (roadmap 12.3): the mountain along the north (level 2, crystal top);
  the mine's mouth in its face with the mine gate (`lantern-gate.tscn`, `crystal-mine-gate`) and the
  cold brazier beside it (lit for good, group `mine-camp-gate`: one flame opens the gate for good);
  behind the gate the way in (`exit-to-crystal-mine` to `arrive-from-camp`), and
  `arrive-from-crystal-mine` in front of it (the mine's south doorway leads there, but not while the
  mine is sealed). The smith, Pip's dad (`game/scenes/characters/smith.tscn`, `smith_actor.gd`: four
  poses, he works his anvil), talks through the camp's director (`mine_camp.gd`, node `MineCamp`):
  the first talk gives the **Lantern** (`learn_ability("lantern")`, its ceremony; flag
  `mine-camp.lantern-given`) and says "The lamp by the gate. Give it a flame."; while the gate is
  shut he says it again; once it is open he sends the slime to Burr for the Bow, needed at the
  Chasm before the Pearl (once, flag `mine-camp.sent-to-burr`), then gives tips. When the gate
  opens he calls "That's it! Mind the dark in there." Once the Colossus fell he is gone (home to
  Slimeshire; his place there is not built). The camp: two tents, the campfire, a cauldron, the
  smith's cot (a bed: sleep, a full refill), lantern posts, rails out of the mouth south to G5.
- **H4, the Lookout:** the mountain goes on as a plateau (level 2) with a two-wide flight of stairs
  down its face at x 10, 11; on top, `arrive-from-crystal-mine`, where the climb out of the arena
  comes up, under a soft daylight glow; the path west along its foot leads to the camp.
- **G5, the cave road:** a road from the west edge (Gloop Forest) and north to the camp, the mine's
  rails along it, lantern posts, and a Crystal Crawler circling a crystal pillar by the road, alone.
- **Not built outside:** the dark side cave by the road with its deadthorn plug (the Lantern's
  come-back), the Feral hill up to the Lookout from the Wilds (it needs the map's way to the Wilds),
  and the smith in Slimeshire.

### The mine's limits

- The **Bow** is not built: the two lenses take its arrow's hook (`on_arrow_hit`) and nothing else
  strikes them, so the Chasm cannot be crossed in play until it is (and so the Pearl and the second
  half cannot be reached in play from the camp; `?sealed` or `room=` reach them).
- **Heart quarters** and the **war journal's pages** are not built: S1, S5 and M10's chest hold coins
  until then (their `KitMarkers` say what goes there).
- The spire plank (S1) lands across the spire's own wall face; its walk across is untested.
- The strike while clinging runs in the body-shapes mode only (the shapes strike there); in the
  classic game an attack press on a wall does nothing.
- Tests: `test_crystal_mine.gd` (20) and `test_mine_camp.gd` (6), all passing on 2026-10-17 (run one
  file at a time with `pnpm test:godot -- --filter=<file>`). The strike while clinging is tested in
  the body-shapes mode turned on for the test (`test_the_spear_strikes_his_claws_from_the_face`).

## The Weaver Hollow (built)

Chapter 2's dungeon, built 2026-10-17 from [its design](../design/2026-10-16-dungeon-weaver-hollow.md)
(its status lists what moved in the build): the Thorn Guard's old watch fort inside the Watch Oak,
climbed from its roots to the Matron's web at its top. Four worlds are one dungeon (`weaver-hollow`,
"Weaver Hollow"); its forecourt is the open world's `gloop-forest-f4`. **Reworked the same day for
the Pearl inside the dungeon** ([the plan](../design/2026-10-17-pearl-mid-dungeon.md#the-weaver-hollow-chapter-2-the-silk-skin),
the owner's decision of 2026-10-17): the first half is the Goo Bomb's, up to the Brood Warden, who
guards Pearl 2 in the Hoard; its take grants the Silk skin and seals the way out; the second half
teaches the Silk skin (the Hoard's stair, C1, the new C4 the Spinning Loft), and the Matron's fight
is its exam.

| World | Floor | Camera rooms |
|---|---|---|
| `weaver-hollow-trunk` | the ground floor, the entrance | T1 Root Door, T2 the Hollow Heart (the hub, 2 x 2, its gallery along the north), T3 the Larder, T4 the Well Room (the map nook T3a sealed in its west), S3's nook |
| `weaver-hollow-roots` | below ground | R1 Root Fall, R2 the Bone Cellar (2 x 1), R3 the Drop Gate, D1 the Old Cellar (dark) |
| `weaver-hollow-boughs` | the upper floor | B1 the Bough Stair, B2 the Drawbridge (2 x 1), B3 the Mimic's Pantry, B4 the Nursery, B5 the Warden's Den, the Hoard (the Pearl room), B6 the Pillar, D2 the Dark Bough (dark) |
| `weaver-hollow-crown` | the top | C1 the Crown Stair, C2 the Crown (the Matron), C3 the Outer Bough, C4 the Spinning Loft |

**Built by a tool, not by hand.** `godot/tools/build_weaver_hollow.gd` writes the four scenes from
`godot/tools/weaver_hollow/hollow_floors.gd` (every room, door, object and enemy, by cell), with
`hollow_canvas.gd` (the painting) and `hollow_scene.gd` (the layers and nodes). Rebuilding
overwrites edits made in the editor: change `hollow_floors.gd`, build again
(`"<Godot console exe>" --headless --path godot -s res://tools/build_weaver_hollow.gd [-- --only=<floor>]`),
then bake (`tools/bake_elevation.gd -- --world=weaver-hollow-trunk,weaver-hollow-roots,weaver-hollow-boughs,weaver-hollow-crown`).
`tools/render_weaver_hollow.gd` renders the floors (`--rooms`, `--collision`, `--scene=<world>`) and
`tools/film_weaver_hollow.gd` films the main path in the game, shot by shot (`--only=<prefix>`;
`--only=check` walks over the lowered drawbridges and down the gallery's stair and prints where the
slime ends; `python scripts/maps/weaver-hollow-contact-sheet.py <film dir> <out.png>` lays the shots
out). Its
pieces: the webs ([WEBS.md](WEBS.md)), the bomb's cracked floor, cracked winch post and blast kegs
([BODY_SHAPES.md](BODY_SHAPES.md) "Goo Bomb") and the Matron ([specs/matron.md](specs/matron.md)
section 8). Tests: `godot/tests/test_weaver_hollow.gd`, `test_weaver_webs.gd`,
`test_weaver_bombs.gd`, `test_matron.gd`.

- **The paint:** each floor is a mass of rock at elevation level 2 (its top the oak's dark soil, its
  walls root rock on the `cliffs` layer) with the rooms carved out at level 0: every camera room
  (16 x 14 cells) keeps a one-cell rim of rock, so two rooms are parted by a two-cell band whose
  face is a wall of two courses. Doorways are two-cell gaps through the bands (an east or west one
  also clears the two rows its lintel hangs over). The hub's gallery is level 1 under two rows of
  rock (so the Crown Door's arch fits, as the kit's doors stand three rows down) and four rows deep
  (so the door shows from the top of the hub's floor), with a front flight of stairs at its east
  end; R1's ledge is level 1 with its own flight. The voids (B2, B6) are
  holes at level -2 floored with dark cavern stone. Rooms vary their floors (cobble, dry leaves,
  moss; C4 the interiors' wooden boards, `HollowCanvas.WOOD_FLOOR`, one tile) so they read apart from
  the rock's top. C1 has a one-row band of rock across it (row 21, its face over rows 22-23) whose
  one gap is the stair's straight way; the Hoard's stair is a well between two blocks of rock at the
  vault's south end. Floor webs are never painted under a wall's face (they would draw over it);
  `paint_webs(rect, 1)` webs a level-1 ledge (the gallery's west end).
- **Kit pieces used:** the Dungeon in each floor (resume at `dungeon-entrance` in T1; the other
  floors' `entrance_map_id` is the Trunk; the seal: `boss_id` `orb-weaver-matron`, `boss_name` "The
  Orb-Weaver Matron", `seal_color` violet `#9a5ad8`, `roar_sound` the spider hiss at 0.4,
  `dust_color` silk `#efe6d6`); two seals (`object.dungeon-seal`: `entrance-seal` in T1's south
  doorway, `wall` south, `glimpse`; `crown-east-seal` in C2's east doorway, `wall` east); three key
  doors of one keyhole (the hub's east door; the Warden's door in B2, `den-door`; C1's K3 door,
  `crown-k3-door`) and the boss door (the Crown Door on the gallery); dungeon chests for the map
  (T3a), small key 1 (R2's pocket), the Nursery's coins and potion (B4, `hidden`: the ambush's
  reward) and the dark rooms' prizes (D1, D2); the big chest with the big key (the Hoard); small key
  2 is the Cocoon Mimic's swallowed drop (`object.dungeon-key`, spat out when she is beaten), small
  key 3 lies in C4's silk parcel (its `contents` `dungeon-small-key`: freed, it drops as the kit's
  floor key); six shutters (the gallery stair's block, `starts_shut`, lowered by the gallery's winch;
  the Nursery's two; the Warden's; the Hoard's, `starts_shut`, the Warden fight's reward; the
  Crown's, shut and opened by the Matron's camp, `boss_engaged` / `boss_defeated`); two room fights
  (the Nursery, `once`; the Warden's Den, `boss_id` `weaver-hollow-brood-warden`, Pearl 2's guard);
  two drawbridges (B2's and B6's, each lowered by a cracked winch post's `trigger`); three void
  hazards (`draw_look` off); twelve pots that hide a refill and grow back (four on the gallery and
  four at C1's top, heart or energy; four in the den, random) and an energy flower (the gallery);
  prize glints in D1 and, for Pearl 2's glow, over its altar and at the Hoard's shutter in the den.
  Three small keys for three keyholes, so no key can be spent wrong. No falling slabs, no shadow
  path, no compass.
- **Pearl 2** (`object.pearl-two`, `boss_id` `weaver-hollow-brood-warden`, `take_radius` 90) on the
  brood's altar (`game/scenes/objects/weaver-hollow/brood-altar.tscn`: a mossy stone pillar bound in
  old silk, solid at its base) in the Hoard beside the big chest. It rises when the Warden's fight is
  won; its take grants the Silk skin and seals the Hollow (the kit's take, [The seal](#the-seal));
  T1's seal is on another floor, so the take plays the roar and the line, no camera cut. Its glow
  (two pale violet `object.prize-glint`s under a StoryVariant on `pearl.orb-weaver-matron`) twinkles
  until it is taken.

### The main path

1. **The forecourt** (`gloop-forest-f4`): the Watch Oak's bricked root gate, a cracked wall: a bomb
   blows it, and the hole is a door into T1.
2. **T1 Root Door:** floor webs (a walk slows, a Roll sticks); S3's web wall east (the Silk skin,
   on a later visit).
3. **T2 the Hollow Heart:** the hub. The Crown Door is seen on the gallery from the floor; the
   hatch in the floor is latched from below; the east door is locked.
4. **T3 the Larder:** two orb-weavers; two cracked walls in its north face: the west one into the
   map nook (T3a, the map), the east one into T4.
5. **T4 the Well Room:** the cracked floor; blown, it drops the slime one way into the Roots.
6. **R1 Root Fall:** the slime lands on a ledge (`roots-landing`) above the first egg sac.
7. **R2 the Bone Cellar:** the Watcher Eye among stone pillars (cover from its beam and the bones),
   two Bone Throwers at their posts; a cracked face in a block of rock hides small key 1's pocket.
8. **R3 the Drop Gate:** Fatty's Lair's old Thorn Guard drop gate (`object.drop-gate`) in a band
   of rock: pull its worm lever and Roll the web-free row before it drops; the gate winch
   (`object.gate-winch`) beyond holds it up for good; the cave ladder climbs to the hub's hatch,
   which opens for good (the loop back).
9. **T2's east door** (key 1) leads to **B1 the Bough Stair** (a Silk Lurker; D2's doorway north).
10. **B2 the Drawbridge:** the void across the room; a bomb thrown over it breaks the cracked winch
    post on the far rim, and the bridge drops west across the gap.
11. **B3 the Mimic's Pantry:** the Cocoon Mimic swallowed small key 2; S2's parcels behind the
    alcove's web wall.
12. **The Warden's door** (key 2, one keyhole) opens **B5 the Warden's Den:** the Brood Warden (the
    first half's last test: a blast plants it), the den's shutter shut behind the slime; Pearl 2's
    glow twinkles at the Hoard's shutter through the fight. Beaten, the Hoard's shutter sinks.
13. **The Hoard, the Pearl room:** the big chest with the big key and, on the brood's altar, Pearl 2,
    risen with the Warden's fall. **The take:** the Silk skin, worn; the Matron's roar from the
    Crown, silk dust, "The Orb-Weaver Matron roars! The way out slams shut."; the seals shut (T1's
    way out, C2's east doorway).
14. **The Hoard's stair** (the Silk skin's first lock, safe, right at the Pearl): a web wall across
    the well's mouth, passed at half speed or cut for good with the Spear. Down it, **T2's gallery**,
    the calm room (the pots, the flower; silk spills over its west end, seen from the hub's floor on
    the first visit); its winch lowers the block at the foot of the gallery's stair, the short way
    down to the hub's floor and the entrance after a faint.
15. **The Crown Door** (the big key) leads up to **C1 the Crown Stair** (the test): floor webs from
    wall to wall, which the Silk slime walks and Rolls at full speed; a band of rock across the stair
    whose one gap, the straight way up, a web wall chokes (wade it, or cut it for good and every climb
    after a faint is quick); at the top the K3 door and four pots, the calm spot before her. C1's
    south part leads east into **C4 the Spinning Loft** (the twist): two rows of web walls from wall
    to wall (seven each, `loft-web-<row>-<i>`, 104 tall) part the old store loft into three
    corridors; a Slime Spider in each corridor ahead lines up and shoots while the slime wades a row
    at half speed (its body shows above the silk, which fades while the slime stands behind it), or
    the Spear cuts a lane for good; small key 3 lies wrapped in a silk parcel at the north corridor's
    east end. Silk-hung rafters, a peg rail of silk hanks, a spool and a spinning wheel dress it.
16. **The K3 door** (key 3) opens **C2 the Crown:** the Matron (the boss shutter shut while she
    fights), enraged while sealed, the Silk skin's exam ([specs/matron.md](specs/matron.md) 8.2):
    round 1 as built (a blast on her shadow, then the Spear); round 2 a cage of web walls round her
    shadow (a thrown bomb stops in its silk and blows out of reach: cut in or wade in, then cast
    inside); round 3 her webbed floor and her brood (the Silk slime Rolls through). Her fall breaks
    the seals; her full heart and her thread.
17. **C3 the Outer Bough:** past the sunk seal, her web wall (pass or cut) and the drop back to the
    forecourt by S1.

**After a faint or a quit** (resumed at T1, inside the seal): T1, the hub, the stair block (once the
gallery's winch is turned), the gallery, the Crown Door, C1 (its web wall cut), the K3 door: four
rooms. Before the winch: T1, the hub, the east door, B1, B2, B5, the Hoard and its stair. S3 (T1's
web wall) and S2 (B3's parcels) open on any walk after the Pearl; S1 (the forecourt) after the seal
lifts, on the way out.

**Off the path:** B4 the Nursery and B6 the Pillar, an optional bomb wing (from B2's east doorway).
The Nursery's ambush (once: shutters close both doorways; three egg sacs in rings of webs and an
orb-weaver) brings a chest with 30 coins and a health potion. B6 (from B4): a bomb on the first
blast keg sets off the line along the broken parapet, and the last breaks the pillar's cracked post:
its bridge drops across the void to the rim, and the far shore's Goo Heart is the heart quarter's
stand-in. D1 the Old Cellar and D2 the
Dark Bough are dark (the Lantern): D1's chest (its glint seen from the doorway) is for a page of the
war journal; D2's three candles, all lit, light the room for good and bring its chest, for the
Silkspun Stew recipe. Neither is an item yet: D1 holds 40 coins, D2 a health potion and 20 coins.
Secrets behind web walls (the Silk skin): S1 in the forecourt
(50 coins and an energy potion), S2 in the pantry (a health potion, an energy potion, 40 coins), S3
off T1 (30 coins).

### Doors between the floors

`door.gd` doors (a north door pairs with a south one, east with west):

- `trunk-entrance` (T1, south) and the forecourt's blown root gate (`weaver-hollow-root-gate`);
- `trunk-east-stair` (T2, east, behind the key door) and `boughs-from-trunk` (B1, west);
- `trunk-gallery-stair` (the gallery, north) and `boughs-hoard-stair` (the Hoard, south);
- `trunk-crown-door` (the gallery, north, behind the Crown Door) and `crown-from-trunk` (C1, south);
- `trunk-hatch` (T2's floor, a ladder down in a `LatchedHatch`: a south door, pushed down onto) and
  `roots-ladder` (R3's cave ladder, a north door);
- one way: the Well Room's blown floor (`trunk-well-floor`, a fall) to the marker `roots-landing`
  in R1, and `crown-bough-drop` (C3, a fall) to the marker `weaver-hollow-silk-drop` in the
  forecourt.

While sealed, `trunk-entrance` and `crown-bough-drop` (to the forecourt) refuse with the seal's line;
the doors between the floors go on.

### The forecourt (`gloop-forest-f4`)

- **Gone from the open world:** the Matron's nest camp (`gloop-ch2-matron-nest`), its guarded
  chest, its silk Gulp spot and the Goo Heart that appeared there after her fall; the ring's
  decorative cocoons, egg sacs and ground webs (the clarity rule: inside, the egg sacs, the Mimic
  and the floor webs are real), and the trees and webs where the oak stands.
- **`weaver-hollow-forecourt`:** the Watch Oak (`watch-oak`: its picture
  `asset/MAPS/landmarks/watch-oak.webp` at 0.6, drawn at z -1 like a wall's face so the slime, the
  trees and the gate's decals draw over it; its upper trunk fades into the forest painted behind
  it; `Trunk` collision in bands round its silhouette); the root gate (`object.cracked-wall` on the
  bricked arch, `weaver-hollow.root-gate`; its `blocker` is the `ArchBricks` body; blown, a door to
  `trunk-entrance`); S1 (a web wall closing a nook in the forest's edge east of the gate, its parcel
  inside); the marker `weaver-hollow-silk-drop` where C3's drop lands.
- The forecourt has no elevation, so it needs no bake.

### The Hollow's own pieces

- `game/scripts/latched_hatch.gd` (`LatchedHatch`): the hub's hatch, latched from below ("Latched
  from below.") until the slime climbs up through it from R3 (its door's `arrived` signal); then
  open for good (`weaver-hollow.hatch-open`).
- `game/scripts/room_arenas.gd` (`RoomArenas`, a node in every floor): each placed enemy's arena is
  its camera room, so egg sacs hatch, the Watcher Eye drifts and enemies chase only in their room,
  also when the room is entered again.
- `RoomEntry` markers in B2 and B6, whose middles are void: `?room=B2-drawbridge` starts there.
- C4's dressing and the brood's altar (`game/scenes/objects/weaver-hollow/`: `loft-rafter`,
  `loft-peg-rail` hang on the north wall's face, `loft-spool`, `loft-spinning-wheel` stand solid in
  the corridors' corners, `brood-altar`): Magnific GPT 2.5 (`gpt-2-mini`, transparent, the Lili
  creation as style reference), 2026-10-17, two generations (200 credits), sources and prompts in
  `asset/Originals/weaver-hollow/loft/`, packed by `python scripts/art/pack-loft-art.py` into
  `godot/asset/MAPS/props/weaver-hollow/` (loaded through `sheet_sprite.gd` until the editor imports
  them).
- **F6 on the second half with the Silk skin:** F6 on a floor gives the Hollow's dev powers (the
  Spear, the Roll, the Heavy skin, the Goo Bomb: Silk is won mid-dungeon, from Pearl 2). F6 on
  `game/dev/weaver-hollow-second-half.tscn` (`game/dev/second_half_run.gd`; dev only) runs
  `weaver-hollow-crown` the same way and lends the Silk skin for the session, worn; on the web or a
  desktop launch `?map=weaver-hollow-crown&skins=silk` does the same, and `?sealed` takes Pearl 2
  quietly and seals.

### Limits

- Heart quarters are not built (roadmap 5.3): B6's prize is a Goo Heart (+10 max HP).
- Side doors now sit in the Hollow's root-rock wall pieces; the room outline hides the world beyond.
- The Hoard is a small vault in the east of a full-size camera room; the rest of its screen is rock.
- C4's rows of web walls hide the slime behind them only partly: an "across" web fades to 0.45 while
  the slime stands behind it (`web_wall.gd`); the corridors are three rows deep.
- A Slime Spider's web shot (`spider-web`, 50 before defence) is the Gloop Forest's, untuned for C4;
  web walls stop shots (they are solid on the world layer), so the spiders hit the slime while its
  body shows above a row it wades, or through a cut lane. Cut lanes let the spiders roam between the
  corridors.
- Not built: Mossy's tip at the ring's south gap, the Matron's three-way lash (8.7; if built it
  pulls but never traps a silk-skinned slime). Quest 6 ("The Matron's Nest", `quests-chapter-2.json`)
  still describes her old nest fight; it completes on her defeat in the Crown.
- Filmed (`tools/film_weaver_hollow.gd`, 41 shots, the forecourt to her fall and out) but not played
  through by the owner.

## Fatty's Lair (built)

Chapter 1's dungeon, built 2026-10-17 from [its design](../design/2026-10-16-dungeon-fattys-lair.md)
(its status lists what moved) and **reworked the same day for the Pearl inside the dungeon**
([the plan](../design/2026-10-17-pearl-mid-dungeon.md#fattys-lair-chapter-1-the-heavy-skin)): the
Thorn Guard's old fort that Gorge's worms took, Fatty One Eye's lair below it. The first half tests
what the slime brings (the Roll, the Spear, the Gulp's throw) and ends in the Larder, where the Big
Squint guards **Pearl 1**; its take grants the Heavy skin and seals the Lair ([The seal](#the-seal));
the second half teaches, tests and twists the Heavy skin, and Fatty's phase two is its exam.
**One world per room since 2026-10-18** (the owner's decision; [DUNGEON_ROOMS.md](DUNGEON_ROOMS.md#fattys-lair-one-world-per-room-2026-10-18)):
24 rooms in 22 worlds, each built when the slime walks in (R1 the Gatehouse is `world.fatty-lair`;
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
(below). **Edited in the editor** since 2026-10-18: its 22 room scenes
(`game/scenes/worlds/rooms/fatty-lair/`) are the source of truth (DUNGEON_ROOMS.md).
`tools/build_fattys_lair.gd`, which first built it, is retired and writes nothing. After painting
holes or stairs in a room, bake that room's world (`tools/bake_elevation.gd -- --world=fatty-lair-<room>`;
R1's is `fatty-lair`).
Its code is `godot/game/fattys_lair/` and the scene scripts `game/scripts/drop_gate.gd`,
`gate_winch.gd`, `eye_latch.gd`, `plank_barricade.gd`, `stair_hatch.gd`, `heavy_plate.gd`,
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
  chest in R9's alcove (hidden: R9's plate raises it); chests for the map (the nook), R1's store,
  the Armoury; five bolted doors (the hub to R1, R5 to R1, R7 to R2, R9 to R8,
  R11 to the ledge); two shutters (the Larder's, the arena's south one) and the Larder's room fight
  (`once`, `boss_id` `fatty-lair-big-squint`: the mini-boss, Pearl 1's guard); two seals
  (`object.dungeon-seal`: R1's south doorway, the take's glimpse, and R13's north doorway, the way
  out past Fatty); the hub's drawbridge; 24 falling slabs (R2, R7, R11) and R2's landing (a
  `hazard-deck`); a void hazard over every rectangle of hole cells (`draw_look` off; the Armoury's
  and the Burrow's with `Return` points at their doorways) and a spikes hazard over the pit; the
  shadow path and three prize glints (the Burrow's, the Armoury's, the Larder's altar); pots that
  grow back; an energy flower on the ledge. The arena's south shutter is driven by the boss camp
  through the Lair's director. No compass is placed (the director is the map's boss mark, group
  `dungeon_map_mark`; the Larder's fight, with its `boss_id`, is marked too until it is won).
- **The Heavy skin's locks** ([SKINS.md](SKINS.md#heavy)), all in the second half or after the
  Pearl: three plank barricades (the Larder's north doorway, R1's store, the bolt-hole), four heavy
  plates (the Weigh House's two, R10's, R9's; the hub's two drawbridge plates are not heavy since
  2026-10-19: two bodies, the slime and Burr), six armour statues that are
  heavy blocks (the Weigh House's, R10's, R9's four) and the Weigh House's loose prize. Nothing
  before the Pearl needs a plate or the skin.

### The rooms

Columns A to E (west to east), rows 2 to 6 (north to south), as the design names them.

| Room | Cell | What is there |
|---|---|---|
| R1 the Gatehouse | C6 | the entrance (south, to Fatty's Hollow), the gate's inner winch, the store behind planks |
| R2 the Slab Steps | D6 | an L of void: two slabs over its west arm; two over its north arm to a landing |
| R3 the Pit Hall | C5-D5 | the hub: the chasm round the north ledge, Burr's cell and the Inner Stair in the west gallery, the drawbridge, the boss door |
| R4 the Squint Den | B5 | two Squints; the map nook's crates in its west wall |
| R5 the Eye Hall | B6 | the north maze (2026-10-19): low dividers, three eye latches struck in order on a timer, three Squints on guard, three gates opening together; the alcove's timed pair, small key 1 |
| R6 the Pipe Gallery | E5 | two Pipe Worms (the Burrow's mouth walled 2026-10-19: the Burrow moved to D4) |
| R7 the Bell Bridge | E6 | the spike pit, the bell on its rock, the turning slab bridge, small key 2 |
| R8 the Guard Crypt | B3-B4 | the Inner Stair's foot (its ladder up), two Bone Marchers, the Thorn Guard's statues, door 3 (an open doorway into R11) |
| R9 the Watcher Hall | A3 | the Heavy skin's twist: the Watcher Eye among four armour statues, a plate in its sight that raises the big chest in the south alcove (**the big key**); its north stone door held by R10's plate; its east door bolted on its side |
| R10 the Dung Roller Run | A2-B2 | the Heavy skin's test: the Dung Roller's lane, a statue in the north niche, a plate before the corridor down to R9's stone door |
| R11 the Drop-gate Bridge | C4 | the inner drop gate, the slab bridge with its turn, a Pipe Worm |
| R12 the Larder | C3 | the Pearl room: Fatty's hoard, the Big Squint's ambush, the worms' altar with Pearl 1's glow, the north doorway nailed shut (the Heavy skin's first lock) |
| C2 the Weigh House | C2 | the Heavy skin's teach (no enemy): a plate before the east stone door, a statue and a plate that holds the west stone door only while it stands on it; scale pans and weights; a pouch in a scale pan on the east wall |
| R13 Fatty's Arena | D4 | Fatty One Eye, the Heavy skin's exam; the south shutter; the north doorway's seal; his full heart |
| R14 the Postern | D3 | after Fatty: the green-key chest, the bolt-hole's barricade |
| the bolt-hole | D2 | a tunnel up to daylight in level-1-d4 |
| the map nook | A5 | a small room behind R4's crates |

### The main path

1. **Fatty's Hollow** (`level-1-d5`'s hill, since 2026-10-17; [Outside](#outside-fattys-hollow-and-the-bolt-hole)):
   through the old fort's field maze and over its moat's slab bridge to the forecourt; pull the worm
   lever in front of the gate, then Roll north under the old gate before it drops (walking from the
   lever never makes it).
2. **R1:** turn the inner winch (the outer gate stays up for good). East into R2: a Roll over two
   slabs, then two more to the landing; north into the hub, where Burr calls from his cell.
3. **The west wing:** R4's Squints, then R5's **north maze** (owner, 2026-10-19; it replaced the
   single teach latch): the hall north of the inner door is a maze of low dividers (a row across
   with two gaps, a pocket each side, a gatehouse in the middle holding G1 and G2 above the inner
   door, G3). Three eye latches, I under the west pocket's divider, II under the east pocket's, III
   on the north wall (the old inner latch, `r5-latch-inner`, its records kept), must be thrust in
   that order (`order`), all within I's 20 s (its `open_ms`; a broken run opens the later ones too):
   out of order the run starts over. Three Squints guard the top corridor and the two lower lanes.
   Solved, the three gates sink together, for good (each latch its own `gate_id`; together, so a
   failed run never shuts the slime between two gates). Then the alcove's two eyes each stay shut
   3 s, and both shut at once open it: **small key 1**.
4. **The east wing:** R6's Pipe Worms, then R7: a thrown pot rings the bell, which opens the
   platform's door; two slabs to the rock, two to the platform: **small key 2**.
5. **Burr's cell:** two keys, two keyholes; he thanks the slime, winds the Inner Stair's hatch up and
   warns of the bones. Then (owner, 2026-10-19) **the drawbridge takes two**: its chains run to two
   plates on the hub's south walk, one body on each, at once; Burr walks to the west one and holds
   it ("That drawbridge takes two ... I'll hold this one. You take the other."). The slime sinks the
   east one: both down, the bridge comes down for good, the short way to the north ledge and the boss
   door. Burr says goodbye, wishes the slime luck and walks out (he waits by the bolt-hole after
   Fatty). Left before the bridge is down, he is back on his plate each time the hub is built.
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
   while the slime sinks it) raises the big chest in the south alcove: **the big key**. R9's bolt
   opens into R8, the ladder leads up to the hub.
10. **The hub:** the drawbridge is down since Burr's freeing (step 5): the short way from the entrance
   to the boss door; the north ledge (the calm spot: pots, an energy flower); the boss door with the
   big key.
11. **R13:** Fatty One Eye, enraged (below); his fall breaks the seals. Then **R14 the Postern:** the
   green key, and a Heavy Roll through the bolt-hole's barricade, up to daylight by the Verdant Gate,
   where Burr waits.

**The way back after a resume** (a faint or a quit wakes the slime at R1, inside the seal): R1, the
bolt to the hub, the drawbridge (down since Burr's freeing), the ledge, the boss door. Were it still
up (Burr not freed): the hub, the Inner Stair, R8, then door 3 and R11 to the Larder (or R9's bolt,
once opened from inside). Nothing the main path needs lies outside after the take.

Secrets: the map nook (the crates jammed in R4's west gap are light things: taken by the Gulp, the
gap's barrier goes with the secret jingle), R1's store (planks: the Heavy Roll, inside, after the
Pearl, on the walk back after a faint or at the end; 100 coins), the Weigh House's pouch (a Heavy
Roll into the east wall shakes the old scale pan's pouch down: 30 coins), the Old Armoury (its four sconces lit for good open its
stone door: the Lantern, Chapter 3; coins for now) and the Glow-moss Burrow (the shadow path: the
Lantern; a goo heart). *Changed 2026-10-19 (owner): the Lair caves in once Fatty falls, so its
come-back secrets move outside ([the plan](../design/2026-10-19-lair-secrets-outside.md)). The sally
port is now `slimeshire-sally-port` (`game/scenes/worlds/rooms/c4/slimeshire-sally-port.tscn`), under C4's
fenced pen below the town wall: the slime drops off the wall into the pen, a Goo Bomb breaks its
cracked ground (`SallyPort/sally-port-crack`, flag `level-1.sally-port-crack`) and it falls in; a
ladder climbs back to `sally-port-way-out` south of the pen. R5's crack is plain wall.* *Changed
again the same day: an open hole in the pen (no bomb), a winding room, the way out a hatch on the
town's east side ([Holes and hatches](#holes-and-hatches)).* *The Glow-moss Burrow (2026-10-19) is now
`slimeshire-glow-moss-burrow` (`game/scenes/worlds/rooms/d4/slimeshire-glow-moss-burrow.tscn`, its heart
`slimeshire-burrow-quarter`): in D4's south-west, a dark-forest maze (medium beeches and pines on the
forest layer, two spiders and a worm) on the road down to D5 hides a clearing at the end of its
longest dead end with an old dry trunk over a hole (`object.dry-trunk-hole`,
`Chapter1/burrow-trunk`): the Lantern burns it (`burnt.level-1.burrow-trunk`); burnt, it shows the
mossy hole with its ladder over the ash (the burnable's `reveal`), which the slime climbs down into
the Burrow, whose ladder climbs back beside the ash
(`burrow-way-out`). R6's tunnel to it is plain wall.* *The Old Armoury (2026-10-19) is now
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
green key waits.

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
- **The inner winch** (`object.gate-winch`, `gate_winch.gd`): in R1; used, it holds the outer gate
  (`fatty-lair-gate` in `level-1-d5`; the gate's and the winch's `map_id`) up for good, across the
  two worlds.
- **Eye latches** (`object.eye-latch`, `eye_latch.gd`) over **divider gates** (since 2026-10-19,
  FENCES.md "Dungeon dividers"; R9's in its doorway is still an `object.latch-door`, its slab the
  wall's shutter leaf): only a thrust (the `spear` tag) shuts the
  eye; a lone latch opens its doors for good; latches sharing a `group_id` (R5's alcove) each stay
  shut `open_ms` and solve their gate only while all are shut at once. With an `order` (1, 2, 3 ...;
  R5's north maze, 2026-10-19) they must be struck in it: struck while an earlier one is still open,
  a latch clinks (`order_text`) and the group's shut latches open again; a latch whose time runs out
  opens every later one of its group with it, so the first one's `open_ms` is the run's time. A timed
  latch's eye flickers in its last 1.5 s. Solved, each latch opens its own `gate_id`.
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
  The Weigh House's first plate is a plain one (its door stays open while it rises, 5 s). The
  counterweight's chain (`game/fattys_lair/counterweight_chain.gd`, presentation) hangs from the
  raised bridge to the slime's (east) plate, pulls taut as it sinks and goes once the bridge is down.
- **Heavy blocks reset with their room** (the guide's no-softlock rule): since the Lair is one world
  per room, each room is built afresh when it is entered, its statues where its scene puts them, as
  the room's enemies and pots come back (the director's own reset for a world of several rooms went
  on 2026-10-19: every Lair world has one room). A statue pushed into a corner never blocks the way;
  the plates are not saved, the drawbridge and the big chest are.
- **The Inner Stair** (`object.stair-hatch`, `stair_hatch.gd`; `object.stair-ladder` at its foot):
  shut until Burr winds it ("Its winch is behind the cell door."); open, walking into its well fades
  the slime down to R8, and walking north into the ladder at the crypt's south-west brings it back
  up (the second half's way back to the hub).
- **Burr** (`character.burr`, `game/fattys_lair/burr_actor.gd`) and **the Lair's director**
  (`game/fattys_lair/lair_director.gd`): his call the first time the slime comes into the hub
  (flag `fatty-lair.burr-called`), his freeing when his door opens (`fatty-lair.burr-freed`), the
  hatch, his walk to his plate (`burr_plate`) and his hold there while the drawbridge (`bridge`) is up,
  his goodbye and walk out once it is down; Fatty's phase two, the clods and the arena's shutter; the map nook's gap
  (kept open for good by `fatty-lair.nook-gap-open`); the heavy blocks' reset; the Larder's glow,
  which goes once Pearl 1 is taken. One world per room: a director stands in each room that needs
  one with that room's paths (the hub's: Burr, who stands in the hub's world behind his cell door;
  the arena's: Fatty, the compass's mark; the Larder's; R4's).
- **Fatty's phase two, the Heavy skin's exam** (`fatty.gd` `configure_phase_two`, its `phase_two_*`
  exports; [specs/boss.md](specs/boss.md) section 3.8): under half his health he leaps twice in a
  row; each landing drops light mud clods from the roots (after a shadow,
  `game/fattys_lair/clod_shadow.gd`; liftable `mud-ball`s, at most four, falling hazards), and the
  second sends a mud ripple over the floor (`game/fattys_lair/mud_ripple.gd`) that a Roll's i-frames
  carry through; his eye stays squinted shut and he braces (every hit clinks). **A Heavy Roll into
  him while he is on the floor** (the Roll's bonk tagged `heavy`) knocks him off balance for
  `phase_two_dizzy_ms` (1.6 s): "Off balance!", he rocks back `phase_two_topple_lean_rad` and
  wobbles, stars over him, his eye wide open, and the Spear lands then. A thrown clod only splats
  ("It splats. Fatty hardly notices.", `phase_two_thrown_text`); a plain Roll bonks off him. Phase
  one is as built (the Spear in his open eye after a leap). Enraged while the Lair is sealed (the
  kit's `EnragedLook`, the same numbers). Beaten: the dungeon records him, the seals break, the
  power he soaked up pours from him into the Pearl the slime carries (the director's sparkles, a
  flash of light on the slime) and his full heart shows (`object.full-heart`, `fatty-one-eye`: +20
  max HP and max energy, as every boss's; the Pearl plan's open point 12).
- **The Pearl** (`object.pearl`, `pearl.gd`, on `decoration-world-solid--pearl-altar`): Pearl 1 lies
  on the worms' altar in the Larder, its `boss_id` the Larder fight's (`fatty-lair-big-squint`): it
  rises once the Big Squint falls. A warm glow and a glint over the altar show from the door all
  through the fight. Walked into from any side of its altar, it plays its card, sets
  `pearl.fatty-one-eye`, grants and wears the Heavy skin (`skin_id`: SkinState.grant,
  [SKINS.md](SKINS.md)) and seals the Lair ([The seal](#the-seal): Fatty's roar, the picture of R1's
  seal).
- **The interaction's `usable` group** (`interaction_controller.gd` USABLE_GROUP): any node with
  `origin()`, `interact_radius`, `prompt`, `badge_rise`, `use()` and an optional `can_use()` is
  offered to the interact key (the lever, the inner winch, Burr outside).

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
- **Fatty's old camp left D4** with its guarded chest (the green key is in the shrine). The camp's
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
- Not built: the war journal page (the Armoury's chest holds coins), heart quarters (the Burrow's
  prize is a goo heart), the journal pointing home after Burr's talk (question 103, roadmap 5.17),
  the worm mural, Fatty's shrinking into a small calm slime (his built death clip plays), the
  drill hall's weights (the plan's other way for his exam).
- The clods' art is the liftable `mud-ball`; a generated clod picture was not used.


### Separate room scenes and integrated doorways (2026-10-17)

The three dungeons now have 60 editable room scenes assembled by a shared shell, retaining
their dungeon ids, puzzle paths and records. F6 on a room starts there. The camera covers
anything beyond the current outline with darkness; Burr's cell is separate from the
L-shaped Pit Hall. Doorways use the wall's own courses with two-cell arches (root arches
in the Hollow, timber in the Mine), and moving leaves/blocks sit inside them. See
[Dungeon room scenes](DUNGEON_ROOMS.md) for editing, builders, art packing and checks.

**Interior walls (2026-10-18, awaiting the owner's verdict):** the replacement for these cliff walls
and doorway frames is the InteriorWallLayer ([INTERIOR_WALLS.md](INTERIOR_WALLS.md)): a room scene
paints its rim two cells thick and the wall is Zelda's bevelled frame, four sloping faces mitred at the
corners, every opening cut into its face; the door objects take `frame_drawn_by_wall` and draw only their leaf or block. So
far only the box-room lab (`?map=box-room-lab`) uses it.
