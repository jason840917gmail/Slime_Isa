# Villagers and animals (the West town, 2026-11-01)

The West town's people and animals: slime villagers who stand in their shops, keep their posts or
walk about, a family of five, and animals that wander, follow their mothers or owners, fly about and
react to the slime. Who they are, their lines and the owner's picks:
[design/2026-11-01-west-town-villagers.md](../design/2026-11-01-west-town-villagers.md).

**Status (2026-11-02):** all 27 villagers and 20 animals are built (art, scenes, lines) and placed in
the town's four chunks (below); a room stands behind every house door (26 doors since 2026-11-12:
a building with no door in its art has no room, below). The wanderers walk in `npc-wander` areas drawn in the chunks (dragged and
sized in the editor like the old NPCs'), and Gavy and Dan climb fences and walls (filmed in
west-village-a4). No tests run, not played in the game with the slime.

## Where they are

| Chunk | Villagers | Animals | Room doors |
|---|---|---|---|
| `west-village-b4` (Market Hill) | Plum at her stall, Dot and Dab at the fountain benches, Fizz and Tad, Tansy on the upper market street, Wick (route along the main street's lamps), Young Burr by the gatehouse, Sprig at the vegetable garden | three doves on the plaza, three butterflies, robin, bluebird, squirrel | shop (general store), inn, town hall, bathhouse, bakery (pumpkin house), herbalist (jelly dome), townhouse, gatehouse |
| `west-village-a4` (West Hill) | Penny (route past the mailboxes), Old Sedge (route down the main road), Isa, Dany, Gavy, Dan | Biscuit after Old Sedge, the cat at the family's cottage, pig and two piglets in the pen, hen and two chicks, duck and two ducklings on the pond, hedgehog and snail at the allotments, robin, goldfinch, swallow, two butterflies, squirrel | tailor (two flats, the outside stair), family home (blue cottage), and the twelve homes of A4 |
| `west-village-a5` | Gramps Reel on the lake's east bank | duck and two ducklings on the lake, two sheep, dove, bluebird, butterfly, squirrel, hedgehog | both farmhouses |
| `west-village-b5` | Zing at the game booth, Bram at the south gate | duck and a duckling on the duck pond, robin, goldfinch, two butterflies, dove, snail, swallow | thatch cottage, snail house, townhouse |

In each chunk they are under `NPCs` and `Animals`; the wanderers' areas are `npc-wander` areas
under `Areas` (`<node name>-wander`, below); the walkers' routes are Path2D nodes under
`Routes` (`<id>-route`, named by their `route`), dragged in the editor like any path; the rooms'
doors are `<room>-door` nodes at the buildings' feet (no leaf art set: the door's sounds play, its
leaf does not swing).

## The cast

| Who | Scene | How they live |
|---|---|---|
| Dollop, Burble, Crumb, Mayor Wobbleton, Bobbin, Auntie Suds, Dune, Granny Thistle, May | `characters/villagers/<id>.tscn` | stand in their room (below) |
| Sprig, Dot, Dab, Bram, Zing, Plum, Gramps Reel, Young Burr | same | stand at their post outside |
| Penny, Old Sedge, Wick | same | walk a route (`Route`) |
| Tansy, Fizz, Tad, Isa, Gavy | same | wander their `npc-wander` area (Isa's and Gavy's wide; Gavy fast, climbing fences and walls) |
| Dany, Dan | same | follow: Dany after Isa, Dan after Gavy (set `follow` where they are placed); Dan climbs after her |
| pig, piglet, sheep | `objects/animals/<id>.tscn` | wander; pigs snuffle and nap, sheep graze and lie down |
| Biscuit (the pup), hen, chick, duckling | same | follow: the pup Old Sedge, chicks the hen, ducklings the duck (`follow`) |
| cat, squirrel | same | wander, nap or nibble; run off when the slime comes near |
| hedgehog, snail | same | curl into a ball / hide in the shell when the slime comes near |
| duck | same | swims its `Route` round the pond |
| robin, dove, bluebird, goldfinch | same | hop and peck; take off and fly about now and then; fly off when the slime comes near |
| swallow, three butterflies | same | always in the air, flying from spot to spot of their circle |

Scene ids (`scene_index.json`): `character.villager.<id>`, `object.animal.<id>`. Rooms:
`world.west-village-<room>`.

## Villagers

A villager is an NPC: a CharacterBody2D (layer `npc`, mask world, player, water) with a `Shadow`, a
`BodyShape` at its feet, the `Visual` sprite (`game/runtime/sheet_sprite.gd`: the sheet loads from
its file before Godot imports it) and its `Animation` player; its root runs
`game/world/villagers/villager_script.gd` (VillagerScript, which extends `game/scripts/npc.gd`), so
every setting below is on the placed instance itself, in the Inspector, and kept when the world is
saved (on a child node, as the old NPCs have it, an instance's settings are hidden without Editable
Children and dropped on save). Its id is its definition in `game/data/npc-definitions.json` (name
tag, "Talk to ...", three lines). The scene root is its feet.

How it moves, the first that applies:

1. an `npc-wander` world area naming it (as the old NPCs; [specs/world.md](specs/world.md) 5.3):
   an Area2D under the world's `Areas` with a `collision-shape` (a rectangle or a circle: drag and
   size it in the editor) and a `world-area-script` (`area_kind` `npc-wander`, `data`
   `{"npcInstanceId": "<its instance_id>"}`); to give another villager or animal one, duplicate an
   area and set its `npcInstanceId` to that node's `instance_id` metadata (`<chunk>-<node name>`);
2. `follow`: a node to stay near (another villager); it wanders within `follow_radius` of its feet;
3. a route: the points of the Path2D in `route`, or of its child `Route` (route walkers have one;
   turn on **Editable Children** on the instance to drag the points), walked in order with a pause
   (`pause_min_ms` to `pause_max_ms`) at each, round and round, or there and back with `route_loop`
   off;
4. its own circle of `wander_radius` around where it stands (the editor draws it, light blue);
5. else it stays where it is placed (shopkeepers, villagers at their posts).

Its walking speed and pauses are `wander_speed`, `pause_min_ms` and `pause_max_ms` on its root.
Standing still it keeps facing its last way (`idle-left`, `idle-right`,
`idle-up`: a walk's first frame); while the slime talks to it, it plays `talk` (npc.gd). Its name
tag floats `name_tag_rise` over its feet (kids lower).

**Climbers** (`climbs_over`; owner, 2026-11-01: Gavy climbs walls and fences, and her father after
her): Gavy and Dan hop over a fence (the `fences` layer) or a wall (a `walls` WallLayer: stone,
hedges) that stops their walk about head on (`climb_head_on`, 0..1). It looks for a free spot past
it, `climb_step` by `climb_step` up to `climb_reach` px, inside the world and touching nothing, and
crosses to it at `climb_speed` with no collision, its picture rising `climb_height` px in an arc
(its shadow stays on the ground). After landing it rests `climb_rest_ms` before it may climb again
and picks a fresh spot; a follower (Dan) climbs only when its leader is out of `follow_radius`, so
it climbs to catch up, never back and forth. Houses, cliffs, water and props are never climbed.

Clips: `idle` (the first pose, a blink every 4 s, a soft jelly breath on the Visual's scale),
`talk` (talking and laughing poses), and for walkers `walk-left/-right/-down/-up` (4 steps; the side
row is mirrored for left) and the three facing idles. The clips write the Visual's `scale`, so
scale a villager by its root node, never its Visual.

## Animals

An animal is a CharacterBody2D with `game/world/villagers/critter.gd` (Critter) on its root, its
`Shadow`, `BodyShape`, `Visual` and `Animation`. Big ones (pig, sheep) stand on the `npc` layer and
block the slime; small ones are on no layer and let it through. Land animals stop at walls and
water; the duck, the ducklings, the swallow and the butterflies collide with nothing.

Where it goes follows the villagers' rules: an `npc-wander` area naming it (read from the world on
its first step; a flier also flies about within it), else `follow` (within `follow_radius`,
hurrying at `catch_up_speed` when far behind), else a `Route`, else its `wander_radius` circle, else
it stays put. Pausing, it sometimes plays one of its `rest_clips` (`rest_clip_chance`).

When the slime comes within `notice_px` it reacts (`reaction`):

| Reaction | What it does | Values |
|---|---|---|
| `none` | takes no notice | |
| `flee` | runs straight away, then wanders back | `flee_speed`, `flee_ms` |
| `fly` | flies off (its picture rises and drifts away, fading), stays away, then flies back in somewhere in its circle and lands | `fly_px`, `fly_ms`, `gone_ms` |
| `curl`, `hide` | plays that clip while the slime is near, and a while after | `calm_ms` |

**Flying about** (owner: "the bird need to fly as well"): when a pause would start, a bird takes off
with `flight_chance`: its picture rises `flight_height` over `fly_ms`, it flies at `flight_speed` to a
random spot of its circle with no collision (over roofs and walls), its shadow staying on the
ground and shrinking, and comes down there. `always_flying` (the swallow, the butterflies) never
lands.

Every number is a property of the animal's scene, tuned in the Inspector. Gameplay time is
`Services.now_ms()`; it moves only through `ArcadeMover.move`.

## Placing them

The Scenery dock's **Villagers** and **Animals** categories list them by picture; a drag places the
scene at its own size under the world's `NPCs` or `Animals` node (both y-sorted, made when missing).
Give it an `npc-wander` area under `Areas` (above), or set its wander circle, route or `follow` in
the Inspector. The editor draws each one's wander circle and a line to the node it follows
(`game/world/villagers/wander_guide.gd`, editor only); the areas show as their collision shapes.

## Rooms

A room behind every house door (owner: "a room behind each door, we can improve the rooms later"):
`game/scenes/worlds/rooms/west-village/west-village-<room>.tscn`, listed as the region's
`interiors` in `world-map.json`. Each is level-1's slime-home shell (14 x 11 cells, the timber floor
and walls; its furniture left out), furniture as nodes under `Furniture`, villagers under `NPCs`
(animals under `Animals`), a `south` way out (`house-door`, leaves from `interior-timber-door.webp`)
to the door `<room id>-door` in its chunk, and the house ambience and music.

- With villagers: `shop` (Dollop), `inn` (Burble, Dune), `bakery` (Crumb), `town-hall` (the mayor),
  `tailor` (Bobbin), `bathhouse` (Auntie Suds), `herbalist` (Granny Thistle), `family-home` (May).
- **No door in the art, no room** (owner, 2026-11-12): the general store and the game booth are
  open stalls, so they have no door node and no room. The shop's room moved to B4's timber
  townhouse by the town hall (its door is `west-village-shop-door` now); that townhouse's own
  empty home, `west-village-b4-townhouse`, is left without a door (the scene is kept, unused). The
  bathhouse's way in is a curtain: its door is an `opening` (the slime walks up to it, nothing
  swings).
- Homes, empty for now and furnished by kind (cottage, flat, mushroom, farm, townhouse): A4's
  `a4-flat` (two-flats' ground floor), `a4-duplex-1`/`-2`, `a4-triplex-1`/`-2`/`-3`,
  `a4-twin-mushroom-1`/`-2`, `a4-thatch-cottage`, `a4-snail-house`, `a4-stump-house`, `a4-barn` (a
  sheep and a hen inside); B4's `b4-townhouse` and `b4-gatehouse` (Burr's: armour, helmets, a bow
  rack); A5's `a5-mushroom-farmhouse` and `a5-pumpkin-farmhouse`; B5's `b5-thatch-cottage`,
  `b5-snail-house` and `b5-townhouse` (room ids are `west-village-<name>`).

The outside doors stand at the buildings' door feet, under each painted door: on the `door-N`
markers of the buildings with several doors, else at the foot of the picture, nudged sideways where
the painted door is off-centre (the family cottage, the inn, both townhouses, the gatehouse). The
painted door itself is the house scene's **door frame** (`DoorFrame`, one per painted door:
[CONVENTIONS.md](CONVENTIONS.md#doors) "Door frames"): the door node takes the nearest one, its
leaf swings there and the slime walks up to its sill (the inn's porch, the tailor's stair).

## Art

Generated with Magnific GPT 2.5 on a transparent background (the owner's rule), one character per
prompt with its rough (or its own pose sheet) as the reference: a pose sheet (2 x 2: idle, blink,
talking, laughing; an animal: idle, two rest poses, a blink; birds and small animals one 3 x 2 sheet)
and, for walkers, three walk sheets (2 x 2, four steps: side in strict profile facing right, toward
the viewer, away). Sources and prompts: `asset/Originals/town/villagers/` (README).

- `python scripts/characters/pack-villagers.py [ids]` cuts each sheet along its emptiest rows and
  columns and draws every frame of one character at one scale (its first frame at its height, 2 px
  per world unit; a walk matched by its first, standing frame, times its `match` for a sitting
  animal), each frame on its cell's floor and centred on its mass, into
  `godot/asset/characters/villagers/<cell>x<cell>-tile_<cols>x<rows>-<id>.webp` (one row per sheet);
  the layouts go to `asset/Originals/town/villagers/packed.json`.
- `python scripts/characters/build-villager-scenes.py [--force] [ids]` writes the scenes from those
  layouts (clips, body, shadow, the numbers from its `CAST` table). It never touches a scene that
  exists unless `--force` names it: tune a scene in Godot after.
- `python scripts/interiors/build-town-rooms.py [--force] [rooms]` writes the rooms, the same way.
- `"<Godot console exe>" --path godot -s res://tools/capture_villagers.gd -- --out=<dir>` (a window,
  not `--headless`) puts every villager and animal on grass, lets them live a few seconds and saves
  the frames (`--villagers`, `--animals`, `--only=`, `--seconds=`, `--every=`, `--zoom=`,
  `--per-row=`); with `--scene=<world> --center=<x>,<y>` it films a world instead (a room, a town
  chunk), its areas registered as the game does (the `npc-wander` areas count).
