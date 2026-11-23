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
- `candles` (NodePaths): each one that burns lifts `darkness.candleShare` (0.25) of the dark
  (owner, 2026-10-19); while all of them burn, the room fades to lit over `litFadeMs` (1500 ms).
  When one goes out, it fades darker again.
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
`asset/MAPS/props/caverns/256x256-tile_2x1-brazier.webp`), `light_radius` 120, `burn_ms` 20000;
the Bestiary's Shardback pen has two, and the Crystal Mine has its braziers
([DUNGEONS.md "The Crystal Mine (built)"](DUNGEONS.md#the-crystal-mine-built)).

- A flame lights it. Lit, it is a light source of `candle.lightRadiusPx` (110 px) at
  `flame_offset`, with a warm additive glow on its flame.
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

The Bestiary's pens 23, 24, 28 and 34 each hold a `DarkRoom` the size of the pen, with no candles, so
they stay dark. Three enemies there read the light sources (they only read them:
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
`stomp_puts_out`; his arena's DarkRoom lists them, so it is lit only while all four burn). Their eyes show in the dark through
`game/enemy/dark_eyes.gd` (drawn over the overlay, only while the room is dark).
