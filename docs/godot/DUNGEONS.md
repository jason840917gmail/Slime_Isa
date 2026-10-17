# The dungeon kit

> **Status:** built 2026-10-17 for the three Release 1 dungeons (Fatty's Lair, the Weaver Hollow,
> the Crystal Mine; their designs in `docs/design/2026-10-16-dungeon-*.md`). Every piece below is
> **usable**: it compiles, it is placed in the dungeon lab and its numbers are in
> `game-constants.json` `dungeon`. Code: `godot/game/dungeon/`; scenes:
> `godot/game/scenes/objects/dungeon/` (ids `object.<name>` in `scene_index.json`); tests:
> `godot/tests/test_dungeon_kit.gd`.

The shared pieces a dungeon is built from: the dungeon state (no saving, resume at the entrance),
keys and locked doors, chests, the dungeon map, doors that open one way or for good, shutters and
room fights, winches and drawbridges, the void with falling slabs and spike pits, refills that grow
back, and the dark rooms' shadow path and glints. Each dungeon's own pieces (its boss, its lock
looks, its enemies) are built by its own work on top of these.

## Placing pieces: the rules they share

- **Rooms are camera rooms** (`game/world/camera_room.gd`, [PROLOGUE.md](PROLOGUE.md#camera-rooms)):
  one per room, 1024 x 896 (16 x 14 cells) or bigger.
- **Walk into it to use it** (no interact key, as doors and gates: CONVENTIONS.md "Doors"): locked
  doors, bolts and winches are pushed (`game/dungeon/push_probe.gd`: the slime's body within
  `worldNavigation.gatePushReachPx` of the object's body, its movement pointing at it, for
  `worldNavigation.doorPushMs`; a winch for `dungeon.winch.turnMs`). Chests open with the interact
  key, as every chest.
- **Records:** what a piece did for good is kept by id in the dungeon's record (DungeonState
  `mark_done`, keys `"<map id>:<kind>:<id>"`); outside a dungeon in the map record's
  `object_states` (a winch or a drawbridge works in any world). Give every piece its id (`door_id`,
  `winch_id`, `bridge_id`, `shutter_id`, `fight_id`, `pickup_id`, a chest's `instance_id`), else
  the node's name is used: names must then be unique in the world.
- **The generic hookup** (`DungeonState.fire`): a winch's `targets`, a room fight's `reward` and
  anything connected to it set a node off through its `trigger(payload)`, else `appear`,
  `open_for_good`, `lower` or `open`; a node without one (a chest's root) passes it to its first
  child that has one. Every kit piece that something opens has `trigger`: Shutter, Drawbridge, the
  hidden chest; the game's gates (`gate.gd`) and the kit's doors answer `open_for_good`. Connect a
  bell's `rung`, a cracked post's `cracked`, a lens's hit or any signal to `trigger`.
- **Walls and doorways:** the kit draws no walls. A doorway two cells wide through a wall painted on
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
  that is won once keeps its enemies away for good.
- **Dev launch options** (once a session): `keys=<n>` (small keys), `bigkey`, `dmap` (the map and
  the compass), `room=<CameraRoom name>` (start in that room, at its `RoomEntry` child or its
  middle), with `map=<world>`: `?map=dungeon-lab&keys=2&room=B1`.

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
- **The dungeon map** (`dungeon_map_draw.gd`): the rooms are the Dungeon world's camera rooms. On the
  HUD minimap (`dungeon_minimap.gd`, under its player dot) and on the map screen (`M`; the world map
  window shows the dungeon's page, `dungeon_map_page.gd`, titled with `display_name`, keys and items
  on its summary line): a room the slime stood in is filled in parchment; with the map every other
  room shows dim (fog lifted); without it a room not visited is not drawn; the room the slime is in
  has a gold ring. With the compass, a red mark is on the boss's room (a room fight with a
  `boss_id` not beaten, or a node in group `dungeon_map_mark` with `mark = "boss"`) and a gold dot
  on every chest not opened yet.

## Chests

`object.dungeon-chest` (the wooden chest) and `object.dungeon-big-chest` (the big chest, for the big
key): `game/dungeon/dungeon_chest.gd` on the `ChestScript` child, which is the game's chest
(`chest.gd`: its record, the "Open chest" prompt, the chest window) plus:

- the dungeon items in `initial_contents` go straight to the dungeon when it opens; any loot beside
  them ("coins", potions...) opens the chest window as any chest;
- `hidden`: not there until set off (a room fight's `reward`, a winch target, any signal on
  `appear` or `trigger`): it rises with a puff and the secret jingle, and stays;
- `map_id` and `instance_id` may stay empty: the world's id and the chest root's name.

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
  draw over it at the same depth); leave an islet (ground in the hole) out of its rectangle, as the
  lab's A2 does with four hazards round its islet.
- **The slime is in a hazard** when its feet are inside it and no deck holds them, or when it walks
  on a lower level than `rim_level` (it dropped into the hole). `HazardWatch` (`hazard_watch.gd`, made
  by the world's first hazard or deck) watches it every step (not while it flies, is on stairs or
  is dead).
- **Void:** the slime spins and shrinks away (`dungeon.void.fallMs`, the `FallDown` cue), then is put
  back on the rim it fell from and loses `dungeon.void.damage` (true damage; `damage` per hazard): the
  last safe ground it stood on (its body clear of every hazard and every slab, or its feet on a safe
  deck: never half on the bridge, touching a slab that would give again), or, when the hazard has
  return points (`return_points`, else its children named `Return...`), the one nearest to that
  ground: the bridge's start, a path's mouth. A fall that faints it wakes it at the entrance.
- **Spikes / lava** (`kind` "spikes" or "lava"): a sunken pit (a hole `pit_depth` levels deep with a
  flight of stairs out). In it the slime is hurt (`dungeon.spikes.damage`, `lava.damage`) each time
  its invulnerability ends (the Roll's i-frames pass), until it walks out by the stair. A slab gone
  from under it drops it into the pit first (`dungeon.spikes.fallMs`).
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

  **The timing:** walking (200 units/s) a 64-unit slab takes 450 ms from the body's first touch to
  the feet leaving it, so it always falls under a walker; a Roll crosses one in under 270 ms (the
  classic Roll launches at 460 units/s; the rework's quick Roll covers 165 units in 330 ms, ending
  at 333 units/s). The slime cannot wait on a slab between two Rolls (the Roll's cooldown is longer
  than the delay), so **a bridge longer than one Roll needs a solid landing where each Roll ends**
  (a HazardDeck, as Fatty's Lair's R7 has): one quick Roll from the rim's edge crosses two slabs
  (128 + the body's 26 units = 154 of its 165), and holding the way on after the Roll walks the
  last few units off. On a landing the slime walks to its far edge, then Rolls on (from the middle
  of a one-cell landing a quick Roll falls short of the far rim by about 20 units); the classic
  Roll (about 185 units) has room to spare. The charged (held) Roll crosses any bridge.

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
- **Prize glint:** `object.prize-glint` (`prize_glint.gd`): a little star that twinkles over a
  prize, drawn above a dark room's darkness (z 46, as the Gloomling's eyes), so the slime sees from
  the doorway that something waits inside. `tint`, `phase`, `only_in_dark`, `lit_strength`.

## The dungeon lab

`game/scenes/worlds/dungeon-lab.tscn` (`world.dungeon-lab`; dev only: not in the release export).
Launch it with `?map=dungeon-lab` (web) or `-- --map=dungeon-lab` (desktop). Rebuild it with
`"<Godot console exe>" --headless --path godot -s res://tools/build_dungeon_lab.gd -- --force` (it
overwrites hand edits). Nine screens, masonry walls on the elevation layer (cobble ground), entered
at B3:

| Room | What it shows |
|---|---|
| B3 the entrance | the entrance marker (a faint resumes here), a small-key chest, the map chest, three pots hiding a heart, energy and coins, an energy flower; north: the small-key door; west: the back of the bolted door |
| C3 | an ambush (`once`): shutters on both doorways, two worms, a chest that rises with a small key |
| C2 | falling slabs: two over a narrow void (one Roll), two + a landing + two over a wide one; a small key on the far side |
| B2 the hub | the door with two keyholes (north) |
| B1 | the winch, the drawbridge over the void, the big chest (the big key), the boss door (north) |
| B0 | the boss room: a room fight with a boss (a Big Squint) behind its shutter |
| A2 dark | the shadow path over the void to an islet, a glinting chest with the compass |
| A3 | slabs and a landing over a spike pit with a stair out; the bolted door back into the entrance; a worm that is back each time the room is entered again |

Three small keys open three keyholes, in any order. The dark room's shadow path shows in the
slime's ember light once the Lantern is learned. The lab's Dungeon node writes no resume save
(`resume_saves` off): Continue never starts in the lab. `?keys=3&bigkey&dmap` skips the hunt.

## Numbers (`game-constants.json` `dungeon`)

| Key | Value | What |
|---|---|---|
| `door.keyholeMs`, `door.openMs`, `door.lineEveryMs` | 380, 650, 1500 | a padlock dropping; the shut door rising away; a refusal line at most this often |
| `bolt.slideMs` | 420 | the bolt sliding back before the door opens |
| `shutter.moveMs`, `shutter.insetPx`, `shutter.openDelayMs` | 260, 80, 600 | a shutter rising or sinking; how far inside the room (and from its shutters) a fight starts; the pause before they open |
| `winch.turnMs`, `winch.reachPx` | 900, 8 | how long to push a winch; its push reach |
| `drawbridge.lowerMs`, `shakeMs`, `shakeIntensity` | 650, 240, 0.006 | the bridge coming down and its thud |
| `void.damage`, `void.fallMs` | 10, 600 | a fall's cost and length |
| `spikes.damage`, `spikes.fallMs`; `lava.damage`, `lava.fallMs` | 8, 320; 12, 320 | a hit each time the invulnerability ends; the drop into the pit |
| `slab.fallDelayMs`, `dropMs`, `returnMs`, `riseMs`, `shakePx` | 300, 380, 10000, 450, 2.5 | the slab's timing (above) |
| `refill.flowerEnergy`, `flowerRegrowMs`, `flowerReachPx` | 25, 20000, 30 | the energy flower |
| `refill.heartHp`, `potEnergy`, `potCoins`, `pickupRadiusPx` | 20, 15, 5, 22 | what a pot hides; the pickups' reach (and the floor key's) |
| `shadowPath.fadePx` | 48 | the moss fading at a light's edge |
| `glint.periodMs`, `glint.sizePx` | 1700, 16 | the glint's twinkle |

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

## The Crystal Mine (built)

Chapter 3's dungeon, built 2026-10-17 from [its design](../design/2026-10-16-dungeon-crystal-caverns.md)
(as built, below; the design's [status](../design/2026-10-16-dungeon-crystal-caverns.md) lists what
moved). One world, `world.crystal-mine` (`game/scenes/worlds/crystal-mine.tscn`), 80 x 70 tiles: a
5 x 5 grid of screens, 14 camera rooms, 7 of them dark. **Built by a tool:**
`"<Godot console exe>" --headless --path godot -s res://tools/build_crystal_mine.gd [-- --dry]`
rebuilds the whole world (hand edits are lost), then bake its elevation
(`tools/bake_elevation.gd -- --world=crystal-mine`). Its code is `godot/game/crystal_mine/` and the
Colossus's `game/scripts/crystal_colossus.gd`; its art `scripts/art/pack-mine-art.py` (sources and
prompts in `asset/Originals/mine/`). Tests: `godot/tests/test_crystal_mine.gd` and
`test_mine_camp.gd`.

- **The paint:** every cell is rock at level 2 (its top crystal floor, so its walls are crystal rock
  and it never reads as a room's floor; masonry and cobble round the old fort's hall); each room is
  carved out to level 0 with cavern floor and a one-cell rock border; doorways are two-cell gaps (an
  east or west one also clears the two rows its lintel hangs over). Holes: M2's two void pits (-2),
  the Dark Maze's void (-2), the Chasm (-3), the Great Shaft's floor with the boss door's way (-2)
  and the Colossus's arena (-2); the S5 shelf in M1 (1), the maze's inner walls (1), the shaft's
  spire (0). The gallery's rim is fenced (`fences` layer) but for the spire plank's foot.
- **Kit pieces used:** the Dungeon (`crystal-mine`, "The Crystal Mine", resume at
  `dungeon-entrance` in M1), a floor key (K1), seven chests (K2, K3, the map, S1, S4, S5) and the
  big chest (hidden, the Den's reward), the Foreman's Gate (`key-door`, two keyholes), the Den door
  (one), the boss door, three shutters (M1's iron shutter `starts_shut`, the Den's fight shutter and
  its ledge `starts_shut`), the Den's room fight (`once`), the crank (`winch` in M7, M1's shutter),
  two drawbridges (the Chasm's, the spire plank), four void hazards (`draw_look` off, `Return...`
  points), the shadow path, seven pots that grow back, an energy flower and three prize glints.
  `KitMarkers` keeps a marker for what nothing builds yet: the war journal's pages and S1's heart
  quarter (S1 and S5 hold coins until then).

### The rooms

Screens by column (0 to 4, west to east) and row (0 to 4, north to south); the main path in order.

| Room | Screen | What is there |
|---|---|---|
| M1 Mine Mouth | (1, 4) | the entrance from the camp (south doorway), the resume marker, the empty cart station ("The cart is at the far end of the line."), the iron shutter in the east wall (lifted by M7's crank), the root wall up to the S5 shelf (Feral) and its chest, pots |
| M2 Lamp Tunnel | (1, 3), dark 1 | rails north, two void pits west of them (a fall: back at the south door), three sconces (60 s) that light it for good, a pot that grows back |
| M5 Tally Room | (0, 3), dark 2 | west of M2: the desk, four crystal pillars, a Gloomling on K1 (a floor key); the cracked wall in its north wall (the Goo Bomb, S2) opens the way to M3 |
| M3 Survey Office | (0, 2), lit | optional: the map chest on the surveyor's table, a Crystal Crawler round its pillar |
| M4 The Great Shaft | (1-2, 2), lit | the hub: the gallery (two braziers burning for good) round the shaft (-2), the ore lift's two landings, the spire with its lens (the Bow) and the S1 chest; north the Foreman's Gate (two keyholes); M14, the shaft floor: pots (two hearts), an energy flower, the boss door east |
| M6 Bat Gallery | (2-3, 3), dark 3 | three Glint Bats over the rails, two sconces, the rotten timbers in the south-east doorway (a Heavy Roll), the S3 nook in the east wall behind a web wall (the Silk skin) with a silk parcel |
| M7 Ore Store | (2-3, 4), lit | east half: the Pick Mole behind its crates, K2 in the chest behind it; west half, past the divider: the Bone Leaper alone, and the crank that lifts M1's shutter |
| M8 The Dark Maze | (0-1, 0-1), dark 4 | four corner candles (60 s, group `dark-maze`): all four at once open the exit gate (the mine's lantern gate) for good; the goal brazier burning beyond it; the void across the middle with the shadow path over it; two Gloomlings (one smothering the north-west candle, one on S4's chest), three Glint Bats, a pot |
| M9 The Chasm | (2, 0), dim | the cart station (the cart starts here), the chasm (-3) with the raised drawbridge on the far rim and the lens beside it (an arrow lowers it, rows 8 and 9), the Bone Thrower on the far ledge, crystal vein glows |
| M10 Prism Gallery | (3, 0), lit | the Prism Eye, the iron-banded ore crate (a heavy block) |
| M11 Crystal Veil | (3, 1), dark 5 | the veil across the room, the brazier by it (20 s) and one on the far side, two Glint Bats in its light; the Den door (one keyhole) west, the way to M12 east, a pot |
| M12 The Fort Hall | (4, 1), lit | cobble and masonry; K3's chest on the dais, the Bone Marcher's loop round it, five armour statues (heavy blocks), the Watcher Eye, two watch-fires |
| M13 Shardback's Den | (2, 1), dark 6 | two braziers (20 s, `stomp_puts_out`), the Shardback; the room fight shuts the east shutter, and won: the big chest rises (the big key) and the ledge's shutter sinks for good (a drop onto the shaft floor) |
| M15 The Colossus's Arena | (3, 2), dark | four braziers (until put out), the Colossus, the root wall he climbs (the way out, Feral), Pearl 3 and his full heart |

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
- **Crystal veil** (`crystal_veil.gd`, `object.crystal-veil`): smoky black crystal across a room,
  `size` wide; open while any of its `braziers` burns, it grows back from both ends over `grow_ms`
  when the last goes out and pushes a slime standing in it to the nearer side; every hit clinks
  ("Cold, dark crystal. It shrinks from fire.").
- **Lantern gate** (`lantern_gate.gd`, `lantern-gate.tscn`): the mine's timber gate with two lamp
  cups, in the group `gate`: candles whose `gate_id` is its own open it for good (the Dark Maze's
  four, the camp's brazier); open, its cups burn and light the dark.
- **Rotten timbers** (`rotten-timbers.tscn`): Fatty's Lair's plank barricade (`plank_barricade.gd`)
  in the mine's look: only a Heavy Roll (the Stone form's bonk, or any Roll with the Heavy skin)
  smashes it; flag `crystal-mine.rotten-timbers`.
- **Heavy ore crate** (`heavy-ore-crate.tscn`): `heavy_block.gd` with the iron-banded crate.
- **Climbable wall** (`climb_wall.gd`, `climb-wall.tscn`): thick living roots and rocky handholds
  (the Feral skin's lock, question 132). With the story flag `skin.feral` (Pearl 3 sets it) the
  interact key climbs it to `top` in three pulls over `climb_ms` (collision off on the way, the level
  taken at the top), then travels on when it has an `exit_area_id` (the arena's: to
  `crystal-caverns-h4`, `arrive-from-crystal-mine`). Without the skin, pushing up at it: "Too steep
  to climb." **The Feral skin itself is not built:** this flag is its stand-in hook.
- **The rails** (`mine_rails.gd`): drawn rails along `points` (the leading line), no collision.
- **The world script** (`crystal_mine.gd`, node `CrystalMine`): keeps each placed enemy to the
  camera room it stands in (its arena), so bats, eyes and Gloomlings fight in their own room.

### The Crystal Colossus (roadmap 12.4)

`character.crystal-colossus` (`game/scenes/characters/crystal-colossus.tscn`,
`game/scripts/crystal_colossus.gd`, a patterned enemy; 240 health; his numbers in
`enemy-types.json` `crystal-colossus.pattern`; eight poses in
`godot/asset/MAPS/enemies/384x384-tile_8x1-crystal-colossus.webp`). His arena is
`colossus_arena.gd` (node `ColossusArena` in M15), a boss camp for the HUD's boss bar and the boss
music, and the compass's boss mark (`dungeon_map_mark`) until he falls.

- **The start:** the slime's centre in `arena_rect`: crystal grows over the way in behind it
  (`seal_cells`, the BreakGlass cue and a shake), the four braziers go cold, he stands at `post` and
  wakes after `wake_ms` (1200) with a roar.
- **The braziers** (candle.gd, `burn_ms` -1: they burn until put out, `stomp_puts_out`): while all
  four burn his weak spot is open (`set_exposed`): a plate of his armour cracks open on a side picked
  at random (front, back, left or right), glowing; he reels for `reelMs` (1800) when it opens.
- **Hits:** every hit clinks off his crystal except the Spear's (tag `spear`) on the open weak spot
  from its side (the hit's source within `weakSideDot` 0.45 of that side's direction); none lands
  while he is on the wall or in the air.
- **His stomp** (the tell: a foot raised for `raiseMs` 650 over a darkening ring `stompRx` x
  `stompRy` 116 x 78; within `stompRangePx` 120 of the slime or every `stompEveryMs` 2600): 24
  damage in the ring, and it puts out the lit `stomp_puts_out` brazier nearest to him
  (`stompPutsOut` 1; `CandleScript.put_out_near` nearest only), so the weak spot shuts.
- **His climb:** after `stompsPerClimb` (3) stomps he leaps onto the north wall at the climb spot
  nearest to the slime (`climb_spots`), out of reach, and clings for `climbMs` (5200), throwing a
  Crystal Mite down every `throwEveryMs` (1300; `mitesPerClimb` 2, at most `maxMites` 4 alive); then
  he leaps down at the slime (a landing ring, `landPutsOut` 1 brazier). In the rework mode a killed
  mite can drop an energy shard (the generic `combat.energyShard` roll); the arena holds no other
  refill. Below `enragedShare` (half health): quicker stomps, more mites, and a landing puts out
  two braziers.
- **Fainting** or leaving the arena while he stands starts it over (he goes, the mites go, the
  braziers go out, the crystal over the way in goes).
- **His fall:** he joins `defeated_boss_ids` and the dungeon's beaten bosses; the four braziers
  burn for good (the cavern is lit); **Pearl 3** (`pearl-three.tscn`, `game/scripts/pearl.gd`) rises
  where he fell and grants the story flag `skin.feral` (the Feral skin's card); his **full heart**
  (`object.full-heart`, `crystal-colossus`, +20 max HP and max energy) rises beside it; the way in
  stays shut, so the way out is the climb up the root wall he climbed, to the Lookout (H4).

### Darkness and fire in the mine

[DARKNESS.md](DARKNESS.md) has the pieces: candles that burn until put out (`burn_ms` < 0), `put_out`
and `put_out_near` (the Shardback's slam ring puts out the Den's braziers, the Colossus's stomp the
nearest of his four), and candles a Gloomling smothers (the Dark Maze's north-west candle refuses a
flame while one sits on it: "The shadow smothers the wick."). The dark rooms: M2 and M6 light for
good once their sconces burn; M5, M8, M11, M13 stay dark; M15 lights while its four braziers burn,
and for good once he falls.

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
  `arrive-from-crystal-mine` in front of it (the mine's south doorway leads there). The smith, Pip's
  dad (`game/scenes/characters/smith.tscn`, `smith_actor.gd`: four poses, he works his anvil), talks
  through the camp's director (`mine_camp.gd`, node `MineCamp`): the first talk gives the
  **Lantern** (`learn_ability("lantern")`, its ceremony; flag `mine-camp.lantern-given`) and says
  "The lamp by the gate. Give it a flame."; while the gate is shut he says it again; once it is open
  he sends the slime to Burr (once, flag `mine-camp.sent-to-burr`), then gives tips. When the gate
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

- The **Feral skin** is not built: the root walls climb on its story flag (`skin.feral`, set by
  Pearl 3) as a scripted climb, not the skin's hold-and-claw climb.
- The **Bow** is not built: the two lenses take its arrow's hook (`on_arrow_hit`) and nothing else
  strikes them, so the Chasm cannot be crossed in play until it is.
- **Heart quarters** and the **war journal's pages** are not built: S1 and S5 hold coins until then
  (their `KitMarkers` say what goes there).
- The spire plank (S1) lands across the spire's own wall face; its walk across is untested.
- Tests are written, not run yet: `test_crystal_mine.gd` (15), `test_mine_camp.gd` (5).

## The Weaver Hollow (built)

Chapter 2's dungeon, built 2026-10-17 from [its design](../design/2026-10-16-dungeon-weaver-hollow.md)
(its status lists what moved in the build): the Thorn Guard's old watch fort inside the Watch Oak,
climbed from its roots to the Matron's web at its top. Four worlds are one dungeon (`weaver-hollow`,
"Weaver Hollow"); its forecourt is the open world's `gloop-forest-f4`.

| World | Floor | Camera rooms |
|---|---|---|
| `weaver-hollow-trunk` | the ground floor, the entrance | T1 Root Door, T2 the Hollow Heart (the hub, 2 x 2, its gallery along the north), T3 the Larder, T4 the Well Room (the map nook T3a sealed in its west), S3's nook |
| `weaver-hollow-roots` | below ground | R1 Root Fall, R2 the Bone Cellar (2 x 1), R3 the Drop Gate, D1 the Old Cellar (dark) |
| `weaver-hollow-boughs` | the upper floor | B1 the Bough Stair, B2 the Drawbridge (2 x 1), B3 the Mimic's Pantry, B4 the Nursery, B5 the Warden's Den, the Hoard, B6 the Pillar, D2 the Dark Bough (dark) |
| `weaver-hollow-crown` | the top | C1 the Crown Stair, C2 the Crown (the Matron), C3 the Outer Bough |

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
  moss) so they read apart from the rock's top.
- **Kit pieces used:** the Dungeon in each floor (resume at `dungeon-entrance` in T1; the other
  floors' `entrance_map_id` is the Trunk); two key doors (the hub's east door, one keyhole; the
  Warden's double door in B2, two) and the boss door (the Crown Door on the gallery); dungeon
  chests for the map (T3a), small key 1 (R2's pocket), small key 3 (B4, `hidden`: the ambush's
  reward) and the dark rooms' prizes (D1, D2); the big chest with the big
  key (the Hoard); small key 2 is the Cocoon Mimic's swallowed drop (`object.dungeon-key`, spat out
  when she is beaten); six shutters (the gallery stair's block, `starts_shut`, lowered by the
  gallery's winch; the Nursery's two; the Warden's; the Hoard's, `starts_shut`, the Warden fight's
  reward; the Crown's, shut and opened by the Matron's camp, `boss_engaged` / `boss_defeated`); two
  room fights (the Nursery, `once`; the Warden's Den, `boss_id` `weaver-hollow-brood-warden`); two
  drawbridges (B2's and B6's, each lowered by a cracked winch post's `trigger`); three void hazards
  (`draw_look` off); eight pots that hide a refill and grow back (four on the gallery, heart or energy; four in the
  den, random) and an energy flower (the gallery); a prize glint in D1. Three small keys for three
  keyholes, so no key can be spent wrong. No falling slabs, no shadow path, no compass.

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
12. **B4 the Nursery:** an ambush, once: shutters close both doorways; three egg sacs in rings of
    webs and an orb-weaver; won, a chest rises with small key 3. B6 lies north.
13. **The double door** (keys 2 and 3) opens **B5 the Warden's Den:** the Brood Warden, the den's
    shutter shut behind the slime; beaten, the Hoard's shutter sinks: the big chest, the big key.
14. **The Hoard's stair** leads down to **T2's gallery**, the calm room before the boss (the pots,
    the flower); its winch lowers the block at the foot of the gallery's stair, the shortcut down to
    the hub's floor and the entrance.
15. **The Crown Door** (the big key) leads up to **C1 the Crown Stair** and **C2 the Crown:** the
    Matron (the boss shutter shut while she fights); then Pearl 2 (the Silk skin), her full heart
    and her thread.
16. **C3 the Outer Bough:** her web wall, passed with the Silk skin, and the drop back to the
    forecourt by S1.

**Off the path:** B6 the Pillar (from B4): a bomb on the first blast keg sets off the line along the
broken parapet, and the last breaks the pillar's cracked post: its bridge drops across the void to
the rim, and the far shore's Goo Heart is the heart quarter's stand-in. D1 the Old Cellar and D2 the
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

### Limits

- Heart quarters are not built (roadmap 5.3): B6's prize is a Goo Heart (+10 max HP).
- The hub's east key door is in an east wall at the world's edge, so it shows as the kit's turned
  front art, a sliver at the room's edge.
- The Hoard is a small vault in the east of a full-size camera room; the rest of its screen is rock.
- Not built: Mossy's tip at the ring's south gap, the Matron's three-way lash (8.7). Quest 6 ("The
  Matron's Nest", `quests-chapter-2.json`) still describes her old nest fight; it completes on her
  defeat in the Crown.

## Fatty's Lair (built)

Chapter 1's dungeon, built 2026-10-17 from [its design](../design/2026-10-16-dungeon-fattys-lair.md)
(its status lists what moved): the Thorn Guard's old fort that Gorge's worms took, Fatty One Eye's
lair below it. One world, `world.fatty-lair` (`game/scenes/worlds/fatty-lair.tscn`), 80 x 70 cells:
a 5 x 5 grid of screens, 19 camera rooms, two of them dark. Its way in and out are in
`level-1-d4` (below). **Built by a tool:**
`"<Godot console exe>" --headless --path godot -s res://tools/build_fattys_lair.gd` rewrites the
whole world (hand edits are lost), then bake it (`tools/bake_elevation.gd -- --world=fatty-lair`).
Its code is `godot/game/fattys_lair/` and the scene scripts `game/scripts/drop_gate.gd`,
`gate_winch.gd`, `eye_latch.gd`, `plank_barricade.gd`, `stair_hatch.gd`, `pearl.gd` and Fatty's
phase two in `fatty.gd`; its art `python scripts/art/pack-fattys-lair-art.py` (sources in
`asset/Originals/fattys-lair/generated/`) into `godot/asset/MAPS/objects/fattys-lair/` and Burr's
sheet `godot/asset/characters/authored/npcs/burr.webp`. Tests: `godot/tests/test_fattys_lair.gd`.

- **The paint:** rock at level 2 (its top forest floor) with the rooms carved out at level 0, every
  camera room keeping a one-cell rim (two-cell bands between rooms; an east or west doorway also
  clears the two rows its lintel hangs over). Walls on the `cliffs` layer: masonry for the upper
  fort, cave rock for the Deep (R8 to R12, the Armoury), root rock where the worms dug (the arena,
  the Burrow, the bolt-hole). Floors: cobble, the Deep's earth (the amberleaf sheet) in R10, the
  Armoury, the Burrow and the bolt-hole. The voids are holes at -3 floored with dark cavern stone,
  darkened a little more by `VoidShade` (`game/fattys_lair/void_shade.gd`, presentation only); R7's
  spike pit is a hole at -1 with a flight of stairs out. Built walls (`walls` layer) make R1's
  store, R5's inner wall and alcove, Burr's cell, R7's platform gate, R11's low wall and the
  Armoury's closet.
- **Kit pieces used:** the Dungeon (`fatty-lair`, "Fatty's Lair", resume at `dungeon-entrance` in
  R1), a `RoomEntry` in every camera room (`?room=<name>`); small keys 1 and 2 on the floor (R5, R7)
  and key 3 in R10's chest, for Burr's door (two keyholes) and door 3 (one); the boss door; the big
  chest (hidden: the Larder fight's reward); chests for the map (the nook), R1's store, the
  Armoury and the sally port; five bolted doors (the hub to R1, R5 to R1, R7 to R2, R10 to R8, R11
  to the ledge); three shutters (the Larder's, the arena's two) and the Larder's room fight
  (`once`); the hub's winch and drawbridge; 24 falling slabs (R2, R7, R11) and R2's landing (a
  `hazard-deck`); a void hazard over every rectangle of hole cells (`draw_look` off; the Armoury's
  and the Burrow's with `Return` points at their doorways) and a spikes hazard over the pit; the
  shadow path and two prize glints; pots that grow back; an energy flower on the ledge. The arena's
  shutters are driven by the boss camp through the Lair's director. No compass is placed (the
  director is the map's boss mark, group `dungeon_map_mark`).

### The rooms

Columns A to E (west to east), rows 2 to 6 (north to south), as the design names them.

| Room | Cell | What is there |
|---|---|---|
| R1 the Gatehouse | C6 | the entrance (south, to Fatty's Hollow), the gate's inner winch, the store behind planks |
| R2 the Slab Steps | D6 | an L of void: two slabs over its west arm; two over its north arm to a landing |
| R3 the Pit Hall | C5-D5 | the hub: the chasm round the north ledge, Burr's cell and the Inner Stair in the west gallery, the drawbridge, the boss door |
| R4 the Squint Den | B5 | two Squints; the map nook's crates in its west wall |
| R5 the Eye Hall | B6 | the first eye latch, the alcove's timed pair, small key 1, the sally port's crack |
| R6 the Pipe Gallery | E5 | two Pipe Worms; the Burrow's mouth in its north wall |
| R7 the Bell Bridge | E6 | the spike pit, the bell on its rock, the turning slab bridge, small key 2 |
| R8 the Guard Crypt | B3-B4 | the Inner Stair's foot, two Bone Marchers, the Thorn Guard's statues, door 3 |
| R9 the Watcher Hall | A3 | the Watcher Eye among four statues; the latch of the north door |
| R10 the Dung Roller Run | A2-B2 | the Dung Roller's lane, small key 3 in a chest |
| R11 the Drop-gate Bridge | C4 | the inner drop gate, the slab bridge with its turn, a Pipe Worm |
| R12 the Larder | C3 | the Big Squint's ambush, the big chest |
| R13 Fatty's Arena | D4 | Fatty One Eye; the shutters; the boss heart (two hearts) |
| R14 the Pearl Shrine | D3 | the altar and Pearl 1, the green-key chest, the bolt-hole's barricade |
| the bolt-hole | D2 | a tunnel up to daylight in level-1-d4 |
| the Old Armoury (dark) | A4 | two holes in its floor, four cold sconces, its chest behind a stone door |
| the Glow-moss Burrow (dark) | E4 | the shadow path over the void to an islet's goo heart |
| the map nook, the sally port | A5, A6 | small rooms behind R4's crates and R5's crack |

### The main path

1. **Fatty's Hollow** (`level-1-d4`): pull the worm lever, then Roll under the old gate before it
   drops (walking from the lever never makes it).
2. **R1:** turn the inner winch (the outer gate stays up for good). East into R2: a Roll over two
   slabs, then two more to the landing; north into the hub, where Burr calls from his cell.
3. **The west wing:** R4's Squints, then R5: a thrust shuts the eye over the inner wall's door (for
   good); the alcove's two eyes each stay shut 3 s, and both shut at once open it: **small key 1**.
4. **The east wing:** R6's Pipe Worms, then R7: a thrown pot rings the bell, which opens the
   platform's door; two slabs to the rock, two to the platform: **small key 2**.
5. **Burr's cell:** two keys, two keyholes; he thanks the slime, winds the Inner Stair's hatch up,
   warns of the bones and walks out.
6. **The Deep:** down the Inner Stair into R8's crypt (Bone Marchers); R9, where the latch under the
   Watcher Eye opens the north door; R10's lane and its chest: **small key 3**; door 3 into R11.
7. **R11:** its lever lifts the inner gate for 500 ms (a Roll north makes it); two slabs north, two
   east; north into **R12**, where the shutter shuts behind the slime until the Big Squint falls and
   the big chest rises: **the big key**.
8. **The north ledge:** R11's bolt opens onto it (the calm spot: pots, an energy flower); its winch
   lowers the drawbridge for good, the short way from the entrance to the boss door.
9. **R13:** the boss door; Fatty One Eye (below); then **R14:** Pearl 1 and the Heavy skin, the green
   key, and the Heavy Roll through the bolt-hole's barricade, up to daylight by the Verdant Gate,
   where Burr waits.

Secrets: the map nook (the crates jammed in R4's west gap are light things: taken by the Gulp, the
gap's barrier goes with the secret jingle), R1's store (planks: the Heavy Roll, after the Pearl;
100 coins), the sally port (R5's crack: the Goo Bomb, Chapter 2; potions), the Old Armoury (its four
sconces lit for good open its stone door: the Lantern, Chapter 3; coins for now) and the
Glow-moss Burrow (the shadow path: the Lantern; a goo heart).

### The Lair's own pieces

- **Drop gate and worm lever** (`object.drop-gate`, `drop_gate.gd`, `game/world_objects/worm_lever.gd`):
  the old oak gate in its rock mound; the lever (interact key, the interaction's `usable` group)
  raises it over `rise_ms` (220), it stays up `open_ms` (700 outside, 500 in R11) and drops in
  `drop_ms` (140), shoving out a slime caught under it; a push on the shut gate says its line.
  `hold_open_for_good()` keeps it up (recorded as the gate unlocked).
- **The inner winch** (`object.gate-winch`, `gate_winch.gd`): in R1; used, it holds the outer gate
  (`fatty-lair-gate` in `level-1-d4`) up for good, across the two worlds.
- **Eye latches** (`object.eye-latch`, `eye_latch.gd`) over **stone doors** (`object.latch-door`:
  `gate.gd` with `game/world_objects/sliding_slab.gd`): only a thrust (the `spear` tag) shuts the
  eye; a lone latch opens its doors for good; latches sharing a `group_id` (R5's alcove) each stay
  shut `open_ms` and solve their gate only while all are shut at once.
- **The plank barricade** (`object.plank-barricade`, `plank_barricade.gd`): only the Heavy Roll smashes
  it (`game/fattys_lair/heavy_check.gd`: a roll with the `heavy` tag, the Stone form's, or any roll
  once the Heavy skin's flag `skin.heavy` is set, until roadmap 7.8 builds the skins); anything else
  bonks with its line. Kept smashed by `flag_id`.
- **The Inner Stair** (`object.stair-hatch`, `stair_hatch.gd`; `object.stair-ladder` at its foot):
  shut until Burr winds it ("Its winch is behind the cell door."); open, walking into its well fades
  the slime down to R8, and the ladder brings it back.
- **Burr** (`character.burr`, `game/fattys_lair/burr_actor.gd`) and **the Lair's director**
  (`game/fattys_lair/lair_director.gd`): his call the first time the slime comes into the hub
  (flag `fatty-lair.burr-called`), his freeing when his door opens (`fatty-lair.burr-freed`), the
  hatch, his walk out; Fatty's phase two, the clods and the arena's shutters; the map nook's gap.
- **Fatty's phase two** (`fatty.gd` `configure_phase_two`, its `phase_two_*` exports): under half
  his health he leaps twice in a row; each landing drops light mud clods from the roots (after a
  shadow, `game/fattys_lair/clod_shadow.gd`; liftable `mud-ball`s, at most four), and the second
  sends a mud ripple over the floor (`game/fattys_lair/mud_ripple.gd`) that a Roll's i-frames carry
  through; his eye stays shut (every hit clinks) until a thrown thing dizzies him, and the Spear
  lands then. Beaten: the dungeon records him, the boss heart shows (`goo_heart.gd` `hearts` 2) and
  the Pearl rises.
- **The Pearl** (`object.pearl`, `pearl.gd`, on `decoration-world-solid--pearl-altar`): shown once
  its boss is beaten; walked into from any side of its altar, it plays its card and sets
  `pearl.fatty-one-eye` and `skin.heavy`. The Weaver Hollow's and the Mine's Pearls use it too.
- **The interaction's `usable` group** (`interaction_controller.gd` USABLE_GROUP): any node with
  `origin()`, `interact_radius`, `prompt`, `badge_rise`, `use()` and an optional `can_use()` is
  offered to the interact key (the lever, the inner winch, Burr outside).

### Outside: Fatty's Hollow and the bolt-hole (`level-1-d4`)

- **The way in** (`object.fatty-lair-mouth`, `game/scenes/objects/fatty-lair-mouth.tscn`, at
  (192, 1012) in D4, the old camp clearing's north-west edge): the drop gate (`fatty-lair-gate`,
  its lever four cells east), a closed mound round the passage behind it, and the north door
  `fatty-lair-mouth` into R1; coming out, the slime walks out of the gate's doorway even when the
  leaf is down. The node is in group `boss_way_in` (metadata `boss_id`), so the tracked quest's
  "Defeat Fatty One Eye" points at it in D4 (`game/quests/quest_waypoint.gd`).
- **Fatty's old camp left D4** with its guarded chest (the green key is in the shrine). The camp's
  scene, `encounter.level-1-fatty-camp`, stays as the boss-camp tests' fixture
  (`godot/tests/lib/fatty_camp_fixture.gd` puts it back in the clearing for `test_boss.gd`,
  `test_audio.gd`, `test_chest_window.gd`, `test_interaction.gd`).
- **The bolt-hole's mouth** (`object.fatty-lair-bolt-hole-mouth`, at (1408, 960), south-west of the
  Verdant Gate): an open hatch, an arrival-only south door (nothing leads back down).
- **Burr outside** (`character.burr-outside`, `game/fattys_lair/burr_outside.gd`, beside it): there
  once he is freed and Fatty is beaten; talked to, he says the town must see the Pearl and walks off
  home (flag `fatty-lair.burr-outside`).

### Limits

- R2's landing shows the kit's flat deck floor; doors in side walls show the kit's turned front art.
- Not built: the war journal page (the Armoury's chest holds coins), heart quarters (the Burrow's
  prize is a goo heart), the journal pointing home after Burr's talk (question 103, roadmap 5.17),
  the Heavy skin itself (roadmap 7.8: the flag stands in), the worm mural.
- The clods' art is the liftable `mud-ball`; a generated clod picture was not used.
