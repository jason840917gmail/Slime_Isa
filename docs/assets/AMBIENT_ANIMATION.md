# Ambient Object Animation

Things in the world that would move in real life should move in the game.
This is the standard for idle ("ambient") motion on world objects.

## Pick a tier

| Tier | When | How | Examples |
| --- | --- | --- | --- |
| 1. Frame sheet | The shape itself changes | 8-frame loop in a sprite sheet, played on the `Visual` sprite's `frame` | campfire flames, lantern flicker, stew bubbles, banner cloth, water shimmer, tree canopy sway, the animated autumn tree |
| 2. Motion only | The object moves but keeps its shape | `AnimationPlayer` tracks on the `Visual` sprite (`rotation`, `alpha`), no new art | a hanging sign swinging, a glow pulsing, tree webs swaying and victim cocoons struggling (`object.decoration-world-ambient.web-*`, origin at the thread so they swing from it) |
| 3. Static | Nothing would move | nothing | fences, tables, anvils, crates, statues |

Gates, doors and the grindstone get interaction clips (open, spin), not idle loops.

## Rules

- **Never in sync.** Every ambient `AnimationPlayer` autoplays with
  `randomizeStart: true`, so each placed copy starts its loop at a random frame.
- **Don't fight instance overrides.** Worlds override the `Visual`'s `scale`,
  `visualOffset` and `flipX` per instance for variety. An animation track
  writes absolute values, so ambient tracks on a shared object scene must not
  touch those properties. Use `frame` for sheets, or `rotation` for a whole
  object that swings.
- **Move only what would move.** A tree bends at the canopy and its trunk stays
  put; a banner's cloth waves on a fixed stand. Rotating a whole sprite makes
  rooted things look like they rock, so bake the bend into frames instead.
- **Subtle.** Canopy sway tops out around 2.4 px per 128 px of tree at 4 fps.
  Other frame loops run 6 to 10 fps.
- **One loop per object.** Keep hit or interaction clips in the same library as
  the idle (as `ResourceNodeScript` does with `onHitAnimationId`), so only one
  player writes the `Visual`.

## Making a Tier 1 sheet

`scripts/art/build-ambient-decoration-sheets.py` builds
`asset/MAPS/decorations/128x128-tile_8x5-decorations-ambient.webp` (asset
`sheet.decorations.ambient.8x5`, one row per object) from the static
decoration sheet. It has two methods:

- **Video, fire pixels only** (campfire, cauldron fire). Render the static
  sprite 6x on `#FF00FF`, make a 5 s Seedance loop with the same image as start
  and end keyframe ([Magnific guide](./magnific-mcp-guide.md)), extract 8 frames
  and keep them in `asset/Originals/decorations/ambient/<name>/`. The script
  copies only the moving fire pixels into the original sprite. Video output
  adds light rays, cast shadows, smoke build-up and camera drift, so never pack
  whole video frames.
- **Procedural** (lantern flicker, banner wave, water shimmer, stew bubbles).
  The frames are derived from the original sprite, so there is no generation
  noise and the silhouette never shifts. Only the part that should move is
  moved: the banner wave shifts the cloth and its trim, and the pole, crossbar
  and base stay the original pixels in every frame. A video pass was tried for
  the banner, but Seedance changed its perspective and added a cast shadow,
  so the cloth would not line up with the fixed stand.

Trees use `scripts/art/build-tree-sway-sheets.py`, which bakes 8 canopy-sway
frames per tree into `asset/MAPS/trees/128x170-tile_16x22-trees-sway.webp`
(`sheet.trees.sway.16x22`) and `256x256-tile_8x3-trees-sway.webp`
(`sheet.trees.3x1.sway.8x3`); source frame `f` becomes frames `f*8 .. f*8+7`.
Rows shift sideways by an amount that is 0 where the canopy leaves the trunk
and grows toward the crown, so trunks and roots never move. Leafless trees
(frames 0-8 of the 128x170 sheet: dead pines, twisted bare trees, the frosted
tree) have no canopy, so they stay on the static sheet with no animation; the
list lives in both the sheet builder and the wiring script.

After changing the sheet, re-run
`python scripts/art/despill-magenta-fringe.py` on it if it came from a chroma
key.

## Wiring

`node scripts/props/wire-ambient-animations.mjs [--write]` adds the ambient
player and library (`<prefix>.ambient-animations`, clip `object.ambient.idle`)
to the decoration scenes that have a sheet row. Tree scenes on the static tree
sheets are switched to the sway sheets and play their 8 frames. Trees with
their own authored frame animation (the autumn tree) keep it and only get
`randomizeStart`.
It is idempotent. Re-run it after anything that regenerates object scenes,
such as `python scripts/props/generate-wall-prop-scenes.py`.

## Water

Water itself animates in a shader (`features/world/WaterSurfaceLayer.ts`, see
[Terrain Transitions](../TERRAIN_TRANSITIONS.md)). Wildlife sits on top as
ordinary object scenes, `object.water-life.*`:

| Where | What | Depth |
| --- | --- | --- |
| Shore (shallow tile next to land) | reeds, cattails, rushes, sedge swaying from the base | `world-entities`, sorted |
| Shallow surface | lily pads bobbing (pink or white flower, single, small cluster), a frog on a pad that blinks and croaks | `ground-decals`, sorted |
| Shallow, under the surface | koi, carp, minnow and perch swimming a lane or an oval with a tail wiggle; eelgrass and waterweed swaying | explicit, just above the water surface, blue-tinted and see-through |
| Deep | a big dark fish shadow cruising slowly, dark kelp, rising bubbles | explicit (shadow lowest), bubbles on the surface |

Underwater things draw just above the animated surface with a blue tint and
partial transparency; under the nearly opaque surface they would vanish.
Swimming is authored animation (a looping path on the `Visual` position,
`flipX` at the turns, tail-wiggle frames), so no script runs per fish. None of
these objects collide, so they never catch the Stretch Lash hook or block a
teleport.

- `python scripts/art/build-water-life-sheets.py` packs the five sheets in
  `asset/MAPS/water/` from `asset/Originals/water/generated/`.
- `node scripts/props/generate-water-life-scenes.mjs [--write]` writes the
  object scenes (paths, timing, tint and depth live in its catalog).
- `node scripts/maps/scatter-water-life.mjs <world-id>... [--write]` places them
  under a `water-life` node: fish only where their whole path stays over water,
  a big shadow only where its path is deep, and nothing near bridges. Re-running
  replaces the previous water life. It currently runs on level-1, emberleef, jk,
  174, crystal-caverns, gloop-forest and hot (not the playground). Afterwards run
  `pnpm audio:wire` and `pnpm assets:worlds`.
