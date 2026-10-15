# Dark Rooms, Candles and Burnables

Built 2026-10-14 for the Lantern on branch `exp/body-shapes` (design:
[bomb-lantern-and-secrets](../design/2026-10-14-bomb-lantern-and-secrets.md) section 2; the ability
itself: [BODY_SHAPES.md "The Lantern"](BODY_SHAPES.md#the-lantern-2026-10-14)). Every number is in
`game-constants.json` `abilities.lantern`.

## Two contracts (`game/world/fire/fire_targets.gd`)

- **Fire targets**: a node in group `fire_targets` with `receive_fire(hit: Dictionary) -> bool`.
  True means the flame is used up and stops there; false lets it fly on (a candle already lit). The
  flame touches a target where its `fire_rect() -> Rect2` (global) says, or else within its
  `fire_radius` property (24 px without one) of its global position. Candles, burnables and the Goo
  Bomb's bombs are fire targets.
- **Light sources**: a node in group `light_sources` with `light_circle() -> Vector3` (global x,
  global y, radius; a radius of 0 or less is off). The slime with the Lantern (in a dark room), lit
  candles, burning burnables, flames, and the Goo Bomb's bombs and blasts are light sources.
  `FireTargets.flicker(radius, phase, share)` gives a radius a real-time flicker.

## Dark rooms (`game/world/darkness/dark_room.gd`)

A `DarkRoom` node (`@tool`, drawn as a purple outline in the editor) placed in a world scene
darkens the rectangle `size` from its position.

- The darkness is **one** ColorRect with `dark_room.gdshader` over the room (z 45: above every
  world sprite, below the ability effects, the particles and the HUD). There are no 2D Light nodes:
  they are too slow on WebGL 2 with the Compatibility renderer.
- Every frame it hands the shader the light sources that reach the room, the
  `darkness.maxLights` (16) nearest to the slime, in its local pixels. The shader cuts a soft hole
  (`softPx` 40 inside the radius, with a faint warm rim) around each one, and the dark is `alpha`
  0.92 elsewhere, softened over 24 px at the rectangle's edge.
- `candles` (NodePaths): while all of them burn, the room fades to lit over `litFadeMs` (1500 ms).
  When one goes out, it fades dark again.
- `lit_for_good_when_all_lit` (off by default): once all its candles burn, the room stays lit for
  good and keeps them lit. This sets the story flag `lit_flag` (default
  `dark-room-lit.<persistence key or path>`), and the overlay is removed.
- The slime's ember and its 160 px light show only inside a room that is still dark
  (`DarkRoom.is_dark_at`). A dark room makes the player's ember node when the slime is around
  (`LanternGlow.ensure`).

## Candles (`game/world/fire/candle.gd`)

A Node2D with the script shows one of two existing interior props, `unlit_scene` or `lit_scene`.
The candle, the candlestick, the sconces and the toadstool candles in
`game/scenes/objects/interiors/` have lit and unlit scenes. The script makes both looks as children
(the hidden one's collision is off), and in the editor it shows the one `lit_at_start` asks for.

- A flame lights it. Lit, it is a light source of `candle.lightRadiusPx` (110 px) at
  `flame_offset`, with a warm additive glow on its flame.
- `burn_ms` (60000 by default): it goes out after that much gameplay time. In its last
  `candle.gutterMs` (5000) it gutters: the flame flickers harder, dims and its light shrinks.
  Nothing is saved. With `burn_ms` 0 it stays lit for good (story flag `candle-lit.<key>`).
- `group` + `gate_id`: when every candle of the group burns at once, every gate with that
  `gate_id` opens (`GateScript.open`, as a pressure plate does).

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
