# Dark Rooms, Candles and Burnables

Built 2026-10-14 for the Lantern on branch `exp/body-shapes` (design:
[bomb-lantern-and-secrets](../design/2026-10-14-bomb-lantern-and-secrets.md) section 2; the ability
itself: [BODY_SHAPES.md "The Lantern"](BODY_SHAPES.md#the-lantern-2026-10-14)). Every number is in
`game-constants.json` `abilities.lantern`.

## Two contracts (`game/world/fire/fire_targets.gd`)

- **Fire targets**: a node in group `fire_targets` with `receive_fire(hit: Dictionary) -> bool`.
  True means the flame is used up and stops there; false lets it fly on (a candle already lit). The
  flame touches a target where its `fire_rect() -> Rect2` (global) says, or else within its
  `fire_radius` property (24 px without one) of its global position. Candles and burnables are
  fire targets; the Goo Bomb's bombs are not (owner, 2026-10-15: a bomb blows only on its fuse).
- **Light sources**: a node in group `light_sources` with `light_circle() -> Vector3` (global x,
  global y, radius; a radius of 0 or less is off). The slime with the Lantern (in a dark room), lit
  candles, burning burnables, flames, and the Goo Bomb's bombs and blasts are light sources.
  `FireTargets.flicker(radius, phase, share)` gives a radius a real-time flicker.

## Dark rooms (`game/world/darkness/dark_room.gd`)

*Since 2026-11-21:*
- **`darkness_override`** (0 to 1; below 0, the constant) makes a room dim rather than black: Gloop
  Forest's outdoor glow grove uses 0.72.
- **Glow-moss** (`game/world/darkness/glow_moss.gd`) is a light source that never goes out. It cuts
  a small soft hole (`radius` 44) and draws a few glowing specks over the dark, so a dim place
  shows its way.

A `DarkRoom` node (`@tool`, drawn as a purple outline in the editor) placed in a world scene
darkens the rectangle `size` from its position.

- The darkness is **one** ColorRect with `dark_room.gdshader` over the room (z 45: above every
  world sprite, below the ability effects, the particles and the HUD). There are no 2D Light nodes:
  they are too slow on WebGL 2 with the Compatibility renderer.
- Every frame it hands the shader the light sources that reach the room, the
  `darkness.maxLights` (16) nearest to the slime, in its local pixels. The shader cuts a soft hole
  (`softPx` 40 inside the radius, with a faint warm rim) around each one, and the dark is `alpha`
  1.0, pure black, elsewhere (0.92 until 2026-10-19, then 0.98: the owner wanted it "totally dark,
  black with no light"), softened over 24 px at the rectangle's edge. Size a dark room over its walls
  and 48 px past the room's edge, or the walls and the soft edge show.
- **Its candles** (below, "A share of the room per candle"): every candle, sconce or brazier standing
  inside its rectangle and every one listed in `candles` (NodePaths: one outside it). With `lit` of
  `n` burning the dark lifts by (lit / n) ^ `darkness.candleShareCurve` (0.5); while all of them burn,
  the room fades to lit over `litFadeMs` (1500 ms). When one goes out, it fades darker again. A room
  with no candle never lifts. `lifts_by_candles` off: only the listed ones count, and only all
  together (the Colossus's arena, Bestiary pen 34: a brazier's circle there is a ring that matters).
- `lit_for_good_when_all_lit` (off by default): once all its candles burn, the room stays lit for
  good and keeps them lit. This sets the story flag `lit_flag` (default
  `dark-room-lit.<persistence key or path>`), and the overlay is removed.
- The slime's ember and its 160 px light show only while the Lantern is the Ability Box's chosen
  ability (owner, 2026-10-19) and only inside a room that is still dark
  (`DarkRoom.is_dark_at`). A dark room makes the player's ember node when the slime is around
  (`LanternGlow.ensure`).

## Candles (`game/world/fire/candle.gd`)

A Node2D with the script shows one of two existing interior props, `unlit_scene` or `lit_scene`.
The candle, the candlestick, the sconces and the toadstool candles in
`game/scenes/objects/interiors/` have lit and unlit scenes. The script makes both looks as children
(the hidden one's collision is off), and in the editor it shows the one `lit_at_start` asks for.
The **brazier** (`object.brazier`, `game/scenes/objects/brazier.tscn`, 2026-10-16) is a ready-made
one: the script on an iron brazier's two looks (`brazier-unlit.tscn`, `brazier-lit.tscn`, from
`asset/MAPS/props/caverns/256x256-tile_2x1-brazier.webp`), `light_kind` "brazier", `burn_ms` 20000;
the Bestiary's Shardback pen has two, and the Crystal Mine has its braziers
([DUNGEONS.md "The Crystal Mine (built)"](DUNGEONS.md#the-crystal-mine-built)).

- A flame lights it. Lit, it is a light source at `flame_offset`, with a warm additive glow on its
  flame: its `light_radius`, else by `light_kind` a candle's or sconce's `candle.lightRadiusPx` (300
  units; 110 until 2026-11-25) or a brazier's `candle.brazierLightRadiusPx` (380; 120). The
  Colossus's braziers set their own 150: that circle is his brittle ring (`light_radius_px`).
- `burn_ms` (60000 by default): it goes out after that much gameplay time. In its last
  `candle.gutterMs` (5000) it gutters: the flame flickers harder, dims and its light shrinks.
  Nothing is saved. With `burn_ms` 0 it stays lit for good (story flag `candle-lit.<key>`). With
  `burn_ms` below 0 (2026-10-17, the Colossus's braziers) it burns until something puts it out;
  nothing is saved either.
- `group` + `gate_id`: when every candle of the group burns at once, every gate with that
  `gate_id` opens (`GateScript.open`, as a pressure plate does; the Crystal Mine's lantern gate
  opens for good).
- **Putting out** (2026-10-17): `put_out()` puts a lit candle out now (smoke, the SlamImpact cue),
  unless it burns for good. `CandleScript.put_out_near(tree, centre, half, nearest_only)` puts out
  every lit candle with `stomp_puts_out` whose foot lies in the ellipse of half size `half` round
  `centre`, or only the nearest one: the Shardback's slam ring (its `slamRx` x `slamRy` times
  `slamPutsOutScale` 1.8) and the Crystal Colossus's stomp (the nearest of his four). A candle
  without `stomp_puts_out` (the default) never goes out that way.
- **Smothered** (2026-10-17): while a node of the group `candle_smotherers` says it `smothers(point)`
  the candle's foot (the Gloomling, within 40 units of it), the candle refuses a flame (the flame is
  spent; "The shadow smothers the wick.", the GulpWearOff cue): drive the shadow off with light,
  then light it.

## Burnables (`game/world/fire/burnable.gd`)

The script sits under a burnable's root body, following the pattern of `tom_web.gd`. Today there
is one: `game/scenes/objects/deadthorn-hedge.tscn`, a 160 x 88 hedge from
`asset/abilities/lantern/deadthorn-2x1.webp` (hedge | burnt) with a 144 x 34 blocking body.

- A flame sets it on fire. It burns for `burnable.burnMs` (600 ms): flames run out from its middle
  to both ends, and it lights the dark around it. Halfway through, it shows its burnt look and sets
  fire to every burnable its fire box (grown by `spreadPx` 24) touches. At the end it smokes and
  stops colliding.
- It stays burnt: the story flag `burnt.<persistence key or path>`.
- Weapons, throws and slams are refused (`immune`, a clink) with "Too dry and hard. Fire would take
  it."

## Effects (`game/world/fire/fire_fx.gd`)

These are code-drawn and run on real time: `embers(at, count, back)`, `smoke(at)`, and the shared
soft glow texture (`glow_texture()`, used with `additive()`).

## The playground's Lantern corner

`game/dev/corners/lantern_corner.tscn` is instanced in `game/scenes/worlds/playground.tscn`, which
was widened east from 40 to 52 columns for it: new grass, and a cavern floor under the room. The
layout is in [BODY_SHAPES.md "The Lantern"](BODY_SHAPES.md#the-lantern-2026-10-14).

## Enemies that answer to light

The Bestiary's pens 23, 24, 28 and 34 each hold a `DarkRoom` the size of the pen: 23, 24 and 28 have
no candles, so they stay dark; 34's brazier lights only its own circle (`lifts_by_candles` off), so the
pen stays dark round it. Three enemies there read the light sources (they only read them:
`game/enemy/light_sense.gd`, [BESTIARY.md](BESTIARY.md#what-the-patterned-enemies-share)): the
Gloomling flees any light and the Glint Bat is awake while the room is dark (it sleeps once every
candle burns) (and a Gloomling sitting on a candle smothers
it, above); the Shardback's shell turns brittle in fire light (every source but the slime's own
ember), and its slam puts out the braziers in its ring.

**Full darkness** (2026-11-13): where no light source reaches the slime in a dark room that is still
dark (`light_sense.gd` `dark_at`), the Gloomlings of the room come for it and bite on contact
([BESTIARY.md "23. Gloomling"](BESTIARY.md#23-gloomling-shadow)). A light is the slime's shelter: its
ember (the Lantern chosen), a burning candle or brazier, a Goo Bomb while it glows. Pen 34 shows it:
three Gloomlings round a brazier that burns, the Goo Bomb on the box.

## The Crystal Mine's dark-room pieces

The mine ([DUNGEONS.md](DUNGEONS.md#the-crystal-mine-built)) adds three that read the fire:
the **crystal veil** (`game/crystal_mine/crystal_veil.gd`: open while one of its braziers burns,
grows back when the last goes out; since 2026-10-17 across the mouth of M10's doorway off M11, the
optional Lantern wing's lock, a brazier on each side), the **lantern gate** (`lantern_gate.gd`: its candles open it
for good; open, its lamp cups are a light source) and the Colossus's four braziers (`burn_ms` -1,
`stomp_puts_out`; the one-scene Mine's arena, retired on 2026-11-25, listed them;
the rebuilt Mine's M15, the Colossus lab's world, lists none and has `lifts_by_candles` off: each
brazier lights only its 150-unit circle, his brittle ring). Their eyes show in the dark through
`game/enemy/dark_eyes.gd` (drawn over the overlay, only while the room is dark).

## A share of the room per candle (2026-11-25)

The owner, on the walk's pictures: "candles dont light up the room ... definitly a lot more that what
is iluminate today", and both remedies. Before, a candle lit 110 units (about 3 % of a one-screen
room), a brazier 120, and each *listed* candle lifted a quarter of the dark: one lamp of three left the
room at 0.75 black, and a room listing none (the Dark Maze) never lifted. Now:

- **A bigger light:** a candle or sconce 300 units (`abilities.lantern.candle.lightRadiusPx`), a
  brazier 380 (`candle.brazierLightRadiusPx`, the brazier scene's `light_kind`); a node's own
  `light_radius` still wins (the Colossus's 150).
- **A share of the room per candle:** every candle standing inside a dark room's rectangle counts,
  listed or not; `lit` of `n` burning lifts (lit / n) ^ 0.5 of the dark
  (`darkness.candleShareCurve`; a straight share left one of three at two thirds black): one of three
  lifts 58 %, one of four half, two of four 71 %. All burning, the room is lit while they burn; lit for
  good only where the room already says so (`lit_for_good_when_all_lit`).
- **Rooms without a candle stay dark** (the Tally Room's lesson).
- Pictures, before and after, as the game shows them: `output/dungeon-rework/mine/candles/`
  (`m2-lamp-tunnel-before-after.png`: none, one, two, three lamps; `m8-dark-maze-before-after.png`: none,
  one, two, four candles; `hollow-d2-dark-bough-before-after.png`: none, one, three).

Every dark room in the game (`tools/list_dark_rooms.gd` lists a scene's rooms with their candles):

| Room | Candles | What changes |
|---|---|---|
| Crystal Mine M2 the Lamp Tunnel | 3 lamps, listed, lit for good | each lamp lifts its share (58 %, 82 %, then lit for good) |
| Crystal Mine M5 the Tally Room | none | nothing: dark for good (its lesson) |
| Crystal Mine M6 the Bat Gallery | 2 lamps, listed, lit for good | one lamp lifts 71 %; its bats sleep once both burn, as before |
| Crystal Mine M8 the Dark Maze | 4 candles, none listed (burn 90 s) | each now lifts its share while it burns (half the maze's dark with the first): the maze reads once a candle burns, and the four candles' run (best order 128 cells, about 50 s of the 90) gets easier, not harder; the gate, the Gloomling on the north-west candle and the timing are unchanged |
| Crystal Mine M11 the Crystal Veil | the veil's brazier (20 s) | lit while it burns (its two Glint Bats sleep then); dark again when it goes out |
| Crystal Mine M13 the Shardback's Den | 2 braziers (20 s) | each lifts 71 %, both light it; the Shardback's brittle ring is the bigger 380 light (the rails under either brazier) |
| Crystal Mine M15 the Colossus's Arena, the Colossus lab | 4 braziers, `light_radius` 150 | nothing: `lifts_by_candles` off, his rings as they were |
| Crystal Caverns G4's dark nook, H4's under-line tunnel | 2 braziers each, listed, lit for good | one brazier lifts 71 % |
| Weaver Hollow D1 the Old Cellar | none | nothing |
| Weaver Hollow D2 the Dark Bough | 3 candles, listed, lit for good | each lifts its share |
| Slimeshire's Old Armoury (D4) | 4 sconces, listed, lit for good | each lifts its share |
| Slimeshire's Glow-moss Burrow (D4) | none | nothing |
| Gloop Forest E5's glow grove | none (dim, 0.72) | nothing |
| The playground's lantern corner | 4 candles, listed | each lifts its share |
| The playground's cave corner nook, the dungeon lab's A2 | none | nothing |
| Bestiary pens 23, 24, 28 | none | nothing |
| Bestiary pen 34 | its brazier | `lifts_by_candles` off: the brazier is a shelter in full dark |

**The light-shy enemies** read the same circles (`light_sense.gd`): a Gloomling flees from farther
(300 units round a candle), a Glint Bat wakes from farther and sleeps in a lit room, the Shardback's
shell is brittle anywhere in a brazier's 380. No fight broke in the walk (M6's bats, M8's Gloomlings,
the Den); none of their numbers changed.
