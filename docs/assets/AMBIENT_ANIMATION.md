# Ambient Object Animation

Things in the world that would move in real life should move in the game.
This is the standard for idle ("ambient") motion on world objects.

## Pick a tier

| Tier | When | How | Examples |
| --- | --- | --- | --- |
| 1. Frame sheet | The shape itself changes | 8-frame loop in a sprite sheet, played on the `Visual` sprite's `frame` | campfire flames, lantern flicker, stew bubbles, banner cloth, water shimmer; tree canopy sway is the same bend done in a shader (below) |
| 2. Motion only | The object moves but keeps its shape | `AnimationPlayer` tracks on the `Visual` sprite (`rotation`, `alpha`), no new art | a hanging sign swinging, a glow pulsing, tree webs swaying and victim cocoons struggling (`object.decoration-world-ambient.web-*`, origin at the thread so they swing from it) |
| 3. Static | Nothing would move | nothing | fences, tables, anvils, crates, statues |

Gates, doors and the grindstone get interaction clips (open, spin), not idle loops.

**Walk-over pickups bounce** (owner decision 2026-10-05): every collectible pile (wood, stone, ore,
charcoal, berries, keys, tonics, shards...) hops about 6 px every 1-2 s, so it catches the eye and
reads apart from the resource nodes it came from (trees, stone and iron nodes), which stay still.
It is code, not a clip: `game/scripts/collectible.gd` tweens the `Visual`'s offset and a small
landing squash relative to its own values (so instance overrides survive), each pile starting at a
random moment, and only once the pile can be picked up (a dropped pile lands first). A pickup that
should stay still sets `bounce = false` on its CollectibleScript.

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
`godot/asset/MAPS/decorations/128x128-tile_8x5-decorations-ambient.webp` (asset
`sheet.decorations.ambient.8x5`, one row per object) from the static
decoration sheet. It has two methods:

- **Video, fire pixels only** (campfire, cauldron fire). Render the static
  sprite 6x on `#FF00FF`, make a 5 s Seedance loop with the same image as start
  and end keyframe ([Magnific guide](magnific-mcp-guide.md)), extract 8 frames
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

Trees sway in a shader, not a sheet: the big trees of the region sets
(`godot/asset/MAPS/trees/sets/`, 2 px per world unit) are too large to bake 8
frames each. `godot/game/world/forest/tree_sway.gdshader` shifts each pixel row
sideways by an amount that is 0 where the canopy leaves the trunk and grows
toward the crown, one slow even swing (a travelling ripple made big canopies
wobble), so trunks and roots never move; the phase
comes from where the tree stands, so one shared material
(`tree_sway_material.tres`) serves every tree and they batch. It is a Tier 1
bend, not a rotation; tune it on the material ([forests](../godot/FORESTS.md)).
Rigid trees (cacti, crystal trees, cave mushrooms, bare gnarled and ash trees)
do not sway: their table entry says `"sway": false` and they get no material.
(The 2026-10 art replaced the baked sway sheets and the leaf-fall autumn tree.)

## Town loops

The West town's pictures (`godot/asset/MAPS/town/`) get their loops from
`scripts/art/pack-town-art.py`, all procedural, each an `ambient` kind in its sheet table: `goo`
(the jelly dome, the town hall's finial), `bath` (the bathhouse's goo and steam), `lamp` (the goo
lamp: its jar glows and swings from its hook), `laundry`, `bees`, `water` (the trough, the rain
barrel and the stream falling into it), `sway` (the scarecrow leans from its pole's foot) and
`fountain` (the goo fountain: rings spread over its pool, its bubbles bob, the blob on top squashes
and stretches, streaks run down the stem, a drop falls from each side drip; 12 frames).

**A loop must read at the game's size** (owner, 2026-11-12: the first fountain, a 10% brightness
shimmer, "is static"). The game draws these pictures at about half their pixels, so a part moves at
least 4 picture pixels, or its brightness changes by a fifth, or nobody sees it. Check a new loop in
a recording of the game (`godot/tools/render_door_walk.gd` films any spot), not in the sheet.

The houses (2026-11-12):

- **Banners and signs** are in the same script: `HOUSE_CLOTH` waves a house's banners from their top
  row (the gatekeeper's two, the town hall's two, the game booth's side banner), `HOUSE_SIGNS`
  swings a hanging sign from its beam (the inn's mug, the store's potion), 8 frames at 6 fps; a
  house with nothing else moving has the kind `still`. `HOUSE_PAD` adds empty columns to a picture
  whose sign swings past its edge (the inn, the store: their `Visual` offset is 10 px further left).
- **Chimney smoke** is not art: `godot/game/scenes/effects/chimney-smoke.tscn` (a `CPUParticles2D`
  whose puff is a gradient; tune it there). A house scene has, per chimney, a `Smoke` Node2D one
  unit in front of its foot (so the smoke sorts with its house) and under it a `Puffs` instance at
  the chimney's opening. The pumpkin, snail shell and gatekeeper's houses have no chimney; the
  bathhouse's steam is in its picture.

Still pictures on purpose: benches, barrels, crates, stalls, the signpost, the statue, fences,
hedges, the garden beds.

## Interior loops

The interior pieces that burn, glow, bubble or steam (2026-11-12; owner: "take a look at interior
decoration, like candles and caldarium") get their loop from
`scripts/art/build-ambient-strips.py`: the lit lantern, the three candles, the two stew cauldrons,
the baking clay oven, the potion cauldron, the lit root hearth, the alchemy workbench, the tall
potion shelf (its bottles pulse, each at its own moment) and the water of the tub, the bucket and
the stone basin (one wide glint drifting over it: still water, so no stripes). Each is
one tile of an interior sheet; the script makes 8 frames of it from the tile's own pixels (flames
lean and stretch, fire and lamp light flickers unevenly, light bands run over a liquid, the
potion's bubbles bob one by one, steam leans, glowing mushrooms and bottles pulse) and writes them
to `godot/asset/MAPS/interiors/ambient/<scene name>.webp`. The piece's scene shows that strip
through `game/runtime/sheet_sprite.gd` and plays it with an `AmbientAnimation` player; the script
rewires a scene once and afterwards only rebuilds its strip. To animate another piece, add it to
the script's `PIECES` table (its sheet tile and its effects' boxes; `--preview=<dir> --boxes` draws
them on the picture) and run it.

**Every interior piece with fire, light or liquid** has a loop since 2026-11-12 (owner: "i still
see not animated candles and fires inside interiors of chunck c4"): 59 pieces. Besides the ones
above: the single candle, the candlestick, the four sconces, the candle cluster, the toadstool
candle, the nightstand's candle and the dining table's two (flames measured by hand: a candle flame
is too pale to find by colour); the four fire pits, the four lit hearths, the lit clay oven and the
lit forge (`("auto", "fire")`: the script finds the flames by colour); the acorn lantern and the
fence post's lantern; the stew, soup and water cauldrons; every tub, trough, bucket and basin with
water; every glow mushroom, the fairy ring, the crystal window, the crystal ball, the glowing puddle,
the firefly jar and the potion bottles (a slow pulse). The level-1 forge building's fire flickers
too (`house-world-solid--forge-red`).

Still on purpose indoors: banners (no wind), plants, herb bundles, the small wall potion shelf (its
bottles are plain clay and glass, nothing glows), the wash basin with soap (no water shows) and
every unlit piece. **Not animated:** the lamps painted into a room's wall art (the mushroom home's
shell: its teal and orange lanterns). The shell is one picture cut into cells, each a prop with its
own random start: a lamp across two cells would flicker out of step. It needs its own way.

## Dungeon loops and the town well

The same script (2026-11-12; owner: "take a look a the town well, and the dungeons art") covers any
object scene: a piece's strip is written beside its sheet, in `<the sheet's folder>/ambient/`.

- **Town well** (`decoration-world-solid--village-well`): a glint over its water, the bucket bobs.
- **Lit brazier** (`brazier-lit`, also the lit look of the gameplay `brazier`): its flames ripple
  upward in long waves and the light flickers.
- **Candelabra** and the **guard table**'s candle: flames lean, the light flickers.
- **Worm head statue**: its eyes pulse.
- **War banner**: its cloth waves from the crossbar (effect `cloth`; the pole and the mushrooms on
  its chain stay).
- **Crystal pillar, ore heap, rock stump**: a shine travels over the crystals.

Still on purpose: barrels, bones, crates, pillars, benches, racks, the sarcophagus, chains, the
hanging cage (a swing would run past its picture's edge) and the prize cocoon (the game draws its
own glint on it).

## Wiring

Each animated decoration scene has an ambient `AnimationPlayer` (clip `idle`, random start) on its
`Visual` sprite; tree scenes have none (their `Visual` carries the sway material). The players were
wired in the Phaser scene JSON
by a script and converted with the scenes; a new animated object gets its player in the Godot editor
(copy one from a similar scene in `godot/game/scenes/objects/`).

## Water

Water itself animates in a shader (`godot/game/world/water_surface.gdshader`;
shores: [terrain edges](../godot/TERRAIN_LAB.md)). Wildlife sits on top as
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
  `godot/asset/MAPS/water/` from `asset/Originals/water/generated/`.
- The object scenes (`godot/game/scenes/objects/water-life--*.tscn`) and their placement under each
  world's `water-life` node (level-1, emberleef, jk, 174, crystal-caverns, gloop-forest and hot:
  fish only where their whole path stays over water, a big shadow only where its path is deep,
  nothing near bridges) were generated by Phaser-era scripts and converted; new water life is
  placed in the Godot editor.
