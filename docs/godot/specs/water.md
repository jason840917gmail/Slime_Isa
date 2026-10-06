# Water spec — animated water surface and water life

Source of truth: the Phaser code on `feat/godot-migration` (commit 1aaf78b). Everything below is read
from code; file:line references are to `src/game/...` unless a path says otherwise. A GDScript engineer
should be able to port or change this without opening the TypeScript.

Godot targets: `res://game/world/water_surface.gd` (node `WaterSurface`, a child of the ground
TileMapLayer, mounted by `WorldService.register_world`) and `res://game/world/water_surface.gdshader`.
The water life stays converted: `res://game/scenes/objects/water-life--*.tscn`.

---

## 0. Scope

### IN
- The animated surface over `water` (shallow) and `deep-water` tiles: one shader quad per tile layer.
- The per-tile mask, the shader maths, uniforms, texture sampling and blending.
- Draw order between the ground, the surface, the underwater life and the surface decals.
- Water-life presentation (tint, alpha, depth) and how its clips run.

### OUT (exist in Phaser; ported elsewhere or later)
| Feature | Where | Notes |
|---|---|---|
| Terrain blending (baked transition chunks under the surface) | `features/world/TerrainTransitionLayer.ts`, `TerrainTransitionRenderer.ts` | Not ported: replaced by hand-made terrain edges drawn over the surface (section 6.2, [../TERRAIN_LAB.md](../TERRAIN_LAB.md)) |
| Water collision | `TileMapLayer2DNode.mountCollision` | Changed by the owner (2026-10-06): shallow `water` is walkable; `deep-water` blocks (unless the slime swims: the Frog Gulp form, [abilities.md](abilities.md) §11.7) through a full-cell collision square on its tiles in `game/world/terrain_tileset.tres`, physics layer `water`. The converted merged bodies under `ground/TileCollision` were removed. A shore collision traced from the edge art was tried and rejected: its uneven outline made the slime stick, since `ArcadeMover` cuts the speed at every contact |
| Canvas-renderer fallback | `WaterSurfaceLayer.ts:154` | Phaser draws no water on the Canvas renderer; Godot always runs Compatibility (GLES3 / WebGL 2) |
| Water ambience audio | world scene audio emitters | Converted with the worlds |
| Scene Studio preview | same `TileMapLayer2DNode` code | Godot's editor does not run the mount (runtime only) |

---

## 1. Where Phaser mounts the surface

- `TileMapLayer2DNode._enter_tree` calls `mountTerrainPresentation(columns, rows, cells, tiles,
  transform)` after the tiles and collision (`infrastructure/phaser-nodes/TileMapLayer2DNode.ts:193`).
- `mountTerrainPresentation` (`:252-289`) returns at once for a rotated or scaled layer (`:259`). It
  builds `grid[rows][columns]` of tile ids from the tile data, ignoring cells outside the grid
  (`:262-263`), and classifies a tile by its assets: `sheet.grounds.19x19.water` → shallow,
  `sheet.grounds.19x19.deep-water` → deep (`WATER_ASSETS`, `:18`, `:274-277`). It then calls
  `WaterSurfaceLayer.create({scene, grid, waterKind, tileSize, textures: {shallow, deep}})` with the
  texture keys of those two sheets (`:278-287`).
- `create` returns nothing when the renderer is not WebGL or no cell is water
  (`features/world/WaterSurfaceLayer.ts:153-157`).
- Every presentation sync moves the quad to the layer's global position and copies the layer's
  visibility (`TileMapLayer2DNode.ts:242-243`). The layer destroys it on exit (`:199-200`), and the
  scene shutdown destroys it too (`WaterSurfaceLayer.ts:210-214`).

Water tiles (`content/scenes/authored/resources/terrain/terrain.tile-set.resource.json`):

| Tile id | Kind | Asset | Physics | Transition |
|---|---|---|---|---|
| `water` | shallow | `sheet.grounds.19x19.water` (`godot/asset/MAPS/grounds/64x64-tile_19x19_water.webp`, 1216 px) | static, layer `water`, inset 10 | natural-ground, priority 5, noisy-feather 12 |
| `deep-water` | deep | `sheet.grounds.19x19.deep-water` (`..._deep-water.webp`, 1216 px) | static, layer `water`, inset 10 | natural-ground, priority 4, noisy-feather 12 |

Both use `selection: sheet-wrap`: tile (x, y) shows sheet tile (x mod 19, y mod 19), so a water
tile's ground pixel at layer position `px` is the sheet texel at `px mod 1216`.

Worlds with water (tile counts shallow / deep): level-1 204 / 58 (56 × 56), emberleef 110 / 0,
jk 57 / 0, playground 12 / 0, test-rectangle 2 / 0, 174 0 / 100, crystal-caverns 0 / 120,
gloop-forest 0 / 181, hot 0 / 25.

---

## 2. The mask (`WaterSurfaceLayer.ts:165-184`)

- A canvas of `columns × rows` pixels, one per tile. Texel (x, y) = (255, 0, 0, 255) for shallow,
  (0, 255, 0, 255) for deep, (0, 0, 0, 255) for anything else.
- Sampler `iChannel0`, `clamp_to_edge` on both axes (`:203-205`). Filtering is LINEAR for min and mag
  with no mipmaps: Phaser's `Shader.initSampler2D` defaults
  (`node_modules/phaser/src/gameobjects/shader/Shader.js:957-958`), and the game runs with
  `pixelArt: false` (`game/config.ts:170`).
- Sampled at `uv = (px / uTile) / uGrid`. Texel centres fall on tile centres, so the value is
  bilinear between neighbouring tile centres: 1 at a water tile's centre, 0.5 on a water/land edge,
  0 at a land tile's centre. This soft field is what gives the shore its shape.

---

## 3. Shader

### 3.1 Quad, uniforms, textures, blending
- One quad covers the whole layer: `scene.add.shader(base, 0, 0, columns * tileSize, rows * tileSize)
  .setOrigin(0).setDepth(WATER_SURFACE_DEPTH)` (`WaterSurfaceLayer.ts:202`).
- `px` is the pixel position inside the quad, y down (the vertex program `:112-125` flips y into
  `fragCoord`, and the fragment program flips it back, `:64`). With the quad at the layer origin, `px`
  is the layer-local pixel position.

| Uniform | Value | Source |
|---|---|---|
| `time` | seconds since the game booted, ms resolution (`game.loop.getDuration()`) | `Shader.js:1112`, `TimeStep.js:828-831`; it keeps running while the scene tree is paused |
| `resolution` | quad size | Phaser default |
| `iChannel0` | the mask, clamp | `:205` |
| `iChannel1` | shallow sheet, repeat (falls back to deep, then the mask) | `:206` |
| `iChannel2` | deep sheet, repeat (falls back to shallow, then the mask) | `:207` |
| `uGrid` | (columns, rows) | `:197` |
| `uTile` | tile size, 64 | `:198` |
| `uPeriod` | 1216 (`TEXTURE_PERIOD`, one repeat of the 19 × 19 sheet) | `:36`, `:199` |

- WebGL 1 repeats only power-of-two textures, so `repeatableCopy` redraws each 1216 px sheet into a
  1024 × 1024 canvas (`imageSmoothingQuality = "high"`) and samples that, LINEAR and REPEAT
  (`:37`, `:131-144`). One texture period is still 1216 world px (`uv = px / uPeriod`).
- Output is premultiplied: `gl_FragColor = vec4(color * alpha, alpha)`, drawn with Phaser's NORMAL
  blend (ONE, ONE_MINUS_SRC_ALPHA), i.e. `color · alpha + dst · (1 − alpha)`.

### 3.2 Fragment maths (`WaterSurfaceLayer.ts:55-108`, verbatim)

```glsl
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) { /* value noise: smoothstep-weighted bilinear mix of hash() at the 4 cell corners */ }
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec4 m = texture2D(iChannel0, (px / uTile) / uGrid);
float wet = m.r + m.g;
float edge = noise(px * 0.035) * 0.22 + noise(px * 0.09) * 0.1 - 0.16;   // in [-0.16, 0.16]
float body = wet + edge;
if (body < 0.3) discard;
float deep = smoothstep(0.25, 0.85, m.g / max(wet, 0.001));
vec2 uv = px / uPeriod;
vec2 wobble1 = vec2(sin(px.y * 0.034 + t * 1.25), cos(px.x * 0.029 + t * 1.05)) * 0.0055;
vec2 wobble2 = vec2(sin((px.x + px.y) * 0.019 - t * 0.85), cos((px.x - px.y) * 0.017 + t * 0.7)) * 0.0045;
// shallow: two copies of the sheet drift across each other; their common bright parts are caustics
vec3 s1 = texture2D(iChannel1, uv + vec2(t * 0.011, t * 0.006) + wobble1).rgb;
vec3 s2 = texture2D(iChannel1, uv * 0.87 + vec2(-t * 0.008, t * 0.010) + wobble2 + 0.37).rgb;
float caustic = max(0.0, min(luma(s1), luma(s2)) - 0.42) * 2.4;
vec3 shallow = mix(s1, s2, 0.5) * 0.92 + vec3(0.75, 0.95, 1.0) * caustic;
// deep: slower, larger scale, broad swells
vec3 d1 = texture2D(iChannel2, uv * 0.72 + vec2(t * 0.004, t * 0.0025) + wobble1 * 0.7).rgb;
vec3 d2 = texture2D(iChannel2, uv * 0.58 + vec2(-t * 0.003, t * 0.0045) + wobble2 * 0.7 + 0.61).rgb;
float swell = sin(px.x * 0.0045 + px.y * 0.0031 - t * 0.55) * 0.5 + 0.5;
vec3 deepColor = (d1 + d2) * 0.5 + vec3(0.02, 0.05, 0.09) * swell;
vec3 color = mix(shallow, deepColor, deep);
// sun glints: one 9 px cell in ~67 (hash >= 0.985) twinkles a soft four-point star
vec2 cell = floor(px / 9.0); float h = hash(cell);
vec2 centre = (cell + 0.25 + 0.5 * vec2(hash(cell + 7.1), hash(cell + 3.7))) * 9.0;
vec2 d = abs(px - centre);
float star = max(0.0, 1.0 - length(d) / 2.2) + max(0.0, 1.0 - (d.x * 3.0 + d.y) / 4.5) * 0.5
           + max(0.0, 1.0 - (d.y * 3.0 + d.x) / 4.5) * 0.5;
float twinkle = pow(max(0.0, sin(t * 2.1 + h * 60.0)), 10.0);
color += vec3(1.0, 0.98, 0.9) * step(0.985, h) * twinkle * star * (1.0 - deep * 0.75) * 0.85;
// foam lapping where the body is thin (the shore)
float shore = 1.0 - smoothstep(0.5, 0.95, body);
float lap = sin(t * 1.4 + noise(px * 0.02) * 6.2832) * 0.5 + 0.5;
float foam = shore * smoothstep(0.55, 0.85, noise(px * 0.09 + vec2(t * 0.5, -t * 0.35)) * 0.7 + lap * 0.45);
color = mix(color, vec3(0.93, 0.98, 1.0), foam * 0.6);
float alpha = smoothstep(0.3, 0.62, body) * mix(0.82, 0.9, deep);   // never opaque: 0.82 shallow, 0.9 deep
```

Consequences worth knowing:
- The surface is never opaque (alpha 0.82 shallow, 0.9 deep), so 10–18 % of the ground under it
  shows through.
- A pixel draws when `wet + edge ≥ 0.3`. On a land tile beside water, `wet` falls from 0.5 at the
  edge to 0 at the tile centre, so the water reaches at most 0.36 tile (23 px) past a water tile,
  typically about 0.2 tile (13 px). Inside a water tile next to land, `body` can stay below 0.62, so
  the surface thins out and the ground shows more strongly there (rounded corners).
- Deep vs shallow changes over the middle of a tile pair: `deep` goes from 1 to 0 between 15 % and
  75 % of the way from a deep tile centre to a shallow one (about 38 px).

---

## 4. Draw order

Phaser depths (`presentation/WorldDepth.ts`, band spacing 2 000 000 000; world-sorted depth = band +
round(y · 16) · 1024 + tie · 16 + attachment, so any sorted sprite at y ≥ 1 is above band + 16 000):

| What | Depth | Source |
|---|---|---|
| Tile images | `ground-terrain` (0) | `TileMapLayer2DNode.ts:139` |
| Baked terrain blend chunks | `ground-decals` + 0.2 | `TerrainTransitionLayer.ts:147` |
| Water surface | `ground-decals` + 0.5 (`WATER_SURFACE_DEPTH`) | `WaterSurfaceLayer.ts:33` |
| Deep fish shadows | explicit `ground-decals` + 0.55 | `scripts/props/generate-water-life-scenes.mjs:87` |
| Waterweed, kelp | explicit `ground-decals` + 0.6 (`UNDERWATER_DEPTH`) | `:88`, `WaterSurfaceLayer.ts:34` |
| Fish | explicit `ground-decals` + 0.65 | `:89` |
| Lily pads, frog on a pad, bubbles | world-sorted `ground-decals` | `:90` |
| Reeds (and the player, props) | world-sorted `world-entities` | `:91` |

`UNDERWATER_DEPTH` is not read at runtime: the scene generator copies its value into the scene JSON.
Underwater things draw above the surface (below it they would vanish under the 82–90 % alpha) and
read as underwater through their tint and alpha (section 5).

Godot (converter: `scripts/godot/lib/tiles.mjs:140`, `scripts/godot/lib/sprite.mjs:7-17, 59-65`):

| What | Godot |
|---|---|
| Ground TileMapLayer | `z_index` −2; one item at y = 0 in the world's y-sort |
| `WaterSurface` | child of the ground layer, `z_index` 0 relative (−2), drawn right after the layer's tiles |
| Underwater life (explicit `ground-decals` depth) | Visual `z_index` −2 (explicit depth in band b → Z(b) − 1), y-sorted with the world. Every instance has y > 0, so it draws after the ground layer (y 0) and its surface |
| Lily pads, frog, bubbles | −1 |
| Reeds | 0 |

### 4.1 Mounting in Godot
`WorldService.register_world` calls `WaterSurface.mount(ground_layer)` once it has picked the ground
layer. `mount` does nothing on a dry world or on a rotated or scaled layer. A second call returns
the existing node. On travel, `main.gd` frees the world root, which also frees the surface (a child
of the ground layer), and `register_world` mounts a new one for the next world.

`mount` reads each used cell's `tile_id` custom data (`water` → shallow, `deep-water` → deep;
cached per atlas source), writes the RGBA8 mask, takes the two sheets from the atlas sources of
those tiles, and sets the uniforms `water_mask`, `shallow_texture`, `deep_texture`, `grid_size`,
`tile_size`, `texture_period`. Sampler hints carry Phaser's filtering: `filter_linear` everywhere,
`repeat_disable` on the mask and `repeat_enable` on the sheets.

---

## 5. Water life

### 5.1 Catalog (`scripts/props/generate-water-life-scenes.mjs:94-117`, scenes `content/scenes/authored/objects/water-life--*.scene.json`)

| Scenes | Sheet | Scale | Alpha | Tint | Depth | Clip `object.water-life.idle` |
|---|---|---|---|---|---|---|
| `fish-{koi,carp,minnow,perch}-{lane,oval}` | fish 128×64, 8×5 | 0.42 | 0.72 | `#b9dcef` | explicit +0.65 | 8–12 s loop at 10 fps: Visual `position` path, `flipX` at the turns, tail frames |
| `deep-fish-shadow-{lane,oval}` | fish (row 4) | 1.1 / 1.25 | 0.75 | — | explicit +0.55 | 20 / 22 s at 8 fps: position, flipX, frames |
| `waterweed-{eelgrass,bushy}` | plants | 0.55 | 0.6 | `#a9d2e3` | explicit +0.6 | 2 s at 4 fps, frames |
| `kelp-{olive,teal}` | plants | 0.9 | 0.5 | `#7ea4bf` | explicit +0.6 | 2.67 s at 3 fps, frames |
| `lilypad-{pink,white,single,small}` | lilypads | 0.52 | 1 | — | world-sorted ground-decals | 2.67 s at 3 fps, frames |
| `frog-lilypad` | frog | 0.46 | 1 | — | world-sorted ground-decals | 8.5 s at 10 fps, 9 keys (holds a frame up to 2.8 s between blinks and croaks) |
| `bubbles` | plants (row 4) | 0.7 | 0.9 | — | world-sorted ground-decals | 1.33 s at 6 fps, frames |
| `reeds-{cattails,reeds,rushes,sedge}` | reeds | 0.62 | 1 | — | world-sorted world-entities | 2 s at 4 fps, frames |

Fish paths: lane `(rx·sin 2πt, ry·sin(4πt + 0.6))`, oval `(rx·cos 2πt, ry·sin 2πt)` (`:40-42`).
Fish and shadows have origin (0.5, 0.5); the rest (0.5, 1). None of them collide.

### 5.2 How it animates in Phaser
- No script runs per fish. Each scene has an `AmbientAnimation` AnimationPlayer: autoplay
  `object.water-life.idle`, `randomizeStart: true`, `domain: render`, looping.
- `AnimationPlayerNode._ready` plays the autoplay clip and, when `randomizeStart` and the clip loops,
  seeks to a random whole frame (`runtime/scene/animation/AnimationPlayerNode.ts:105-111`), so copies
  never move in lockstep.
- Render-domain clips advance once per rendered frame by its delta, even while the scene tree is
  paused (`infrastructure/scenes/PhaserSceneTreeHost.ts:121-124`).
- `tint` is Phaser's multiplicative tint (`Sprite2DNode.ts:202, 280`) and `alpha` the sprite alpha.

### 5.3 Godot
- The converted scenes already match: Visual `self_modulate` = tint with the alpha, `z_index` as in
  section 4, and `AmbientAnimation` runs `runtime/animation_player.gd`, whose `_ready` plays the
  autoplay clip through `play_clip` and seeks a random whole frame (`animation_player.gd:45-54`).
  Render domain → `callback_mode_process` IDLE.
- `test_water.gd` checks this on level-1: all 65 instances play, their playheads advance and their
  frames or positions change. No runtime fix was needed. The "no water animation" report came from
  the missing surface: the static water tiles under moving fish read as still water.
- Instances per world: level-1 65 (under its `Water Life` node), emberleef 49, gloop-forest 39,
  crystal-caverns 26, 174 22, hot 8, jk 8.

---

## 6. Differences from Phaser

### 6.1 Smooth water ground
Under the 10–18 % transparent surface, Phaser shows its blended terrain. Godot shows the raw tiles,
which have a hard edge between a `water` and a `deep-water` tile, so tile steps appeared along
every deep/shallow border. The shader's `smooth_water_ground` uniform (default on) handles this: on
a pixel whose own tile is water (`texelFetch` of the mask), it composites the two sheets at `uv`
(exactly the texel that tile shows, see section 1), mixed by `deep`, under the surface and draws
opaque. Away from deep/shallow borders this equals what the tile shows, so nothing else changes.
It stays on with the terrain edges: Godot does not port Phaser's blend (below).

### 6.2 Shores: hand-made terrain edges instead of the blend
Phaser's shores look round because its baked terrain blend rounds the ground under the surface
(chunks at +0.2, surface at +0.5). Godot replaces the blend with hand-made edge tiles drawn **over**
the surface ([../TERRAIN_LAB.md](../TERRAIN_LAB.md), 2026-10-05): at a corner where land meets water
the edge layer first fills the tile with water, using the same maths (`water_surface.gdshaderinc`,
shared with `water_surface.gdshader`), the surface's own mask and sheets and the same opaque water
ground, so it is pixel-identical to the surface next to it, then draws the land's edge tile with its
painted rim on top. The shore foam therefore shows only on the water side of the land's rim. Water
and deep water still blend inside the surface (its deep factor), not with tiles.

### 6.3 Order inside the underwater band
Phaser orders shadows (+0.55) < plants (+0.6) < fish (+0.65). The converter maps all three to
z −2, so Godot y-sorts them: a fish can pass under a kelp or waterweed whose base is lower on the
screen (both are see-through, so this shows only as a slightly different overlap). A fix needs the
converter, e.g. distinct z values for the three with the ground layer moved below them.

### 6.4 Time
The shader uses Godot's `TIME`: engine seconds that keep running through pauses, like Phaser's
`time`. It wraps every hour (`rendering/limits/time/time_rollover_secs`, default 3600), which gives
one jump in the pattern per hour.

### 6.5 Textures
Godot samples the original 1216 px sheets (GLES3 / WebGL 2 repeat non-power-of-two textures) instead
of a 1024 px resampled copy. The period and colours are the same; the detail is slightly sharper.

### 6.6 Drawn rectangle
The quad covers the water's bounding box plus one tile (`DRAW_MARGIN_TILES`), not the whole layer.
Every pixel Phaser could draw is inside it (section 3.2), so the image is identical and fewer pixels
run the shader.

### 6.7 Ambient clips and pauses
Phaser's render-domain clips keep running through a hit-stop (65–100 ms) or a modal pause. The
converter gives render-domain AnimationPlayers `PROCESS_MODE_ALWAYS`
(`scripts/godot/lib/animation.mjs`, 2026-10-05), so water life does too; physics-domain players
(characters) still pause with the tree.

---

## 7. Performance

- One node and one draw call per world. No per-frame script: the shader reads `TIME`. The level-1
  mask is 56 × 56 RGBA8 (12.5 KB). Mounting is one pass over the used cells at world load.
- Per fragment inside the rectangle: one mask fetch and two value noises (8 `sin`). Land pixels
  are discarded there. Water pixels add 4 sheet fetches (plus 2 and a `texelFetch` for 6.1), two
  more noises, 3 hashes, about 10 `sin`/`cos` and a `pow`. Phaser ran the same program over the whole
  layer quad.
- Cost scales with the screen area under the water's bounding box: about 0.9 M fragments at
  1280 × 720 when the lake fills the screen, about 4× that on a 2× display. On the RTX 5090
  development machine, a windowed frame with level-1's lake on screen took 0.14 ms GPU on average
  (Movie Maker stats). The reference-laptop web measurement is still open, as for the whole trial.

---

## 8. Tests (`godot/tests/test_water.gd`)

- `test_mask_marks_shallow_and_deep_tiles`: a 5 × 4 layer built from the terrain TileSet. Checks
  every mask texel, the counts, the drawn rectangle (bounding box + 1 tile, clamped), the uniforms and
  sheets, that a second mount reuses the node, and that a dry layer gets no surface.
- `test_level1_surface_covers_the_water_tiles_in_draw_order`: level-1 has 204 shallow and 58 deep
  tiles. Every mask texel matches the ground's `tile_id`, and the rectangle covers every water tile.
  The surface has the ground's z (−2), each underwater Visual has the same z at y > 0, and the other
  water life is above it.
- `test_level1_water_life_plays_with_phaser_presentation`: 65 instances, each playing
  `object.water-life.idle` with the Phaser tint, alpha and z. Each advances, and each except the
  frog changes frame or position within about 1.2 s.
- `test_travel_rebuilds_the_surface_for_the_next_world`: travelling to gloop-forest frees level-1's
  surface and mounts one with 181 deep tiles, with the deep sheet in both slots.

## 9. Wading (Godot only)

Owner request (2026-10-06), after the classic top-down adventure games: anyone walking in shallow
water shows water at its feet, and a swimmer (the slime in the Frog Gulp form) shows calm rings.
`res://game/world/water_wake.gd` (`WaterWake.mount(ground)`, node `WaterWake`, a child of the ground
mounted by `WorldService.register_world` after the elevation) follows every walker body: a
`CharacterBody2D` on the player, enemy or NPC layer, placed in the world or spawned later.

- Each body gets two sprites from `godot/asset/MAPS/water/224x128-tile_4x2-water-wake.webp`: the
  ring's back half as its first child (drawn behind its art) and its front half as its last child
  (drawn in front), so it stands inside the ring.
- Every physics tick the cell under the body's feet (2 units up, inside the body) decides the row:
  `water` shows the wading splash (row 0: rising, highest, falling, settled), animating at 10 fps
  while the body moves and 4 fps while it stands; `deep-water` shows the swim ripple (row 1, 6 fps).
  Anything else, or a body in the air (a script child's `is_airborne()`, the player's jump), shows
  nothing.
- The ring is drawn for the player slime's 30-unit body (60 units across when wading, 70 when
  swimming); other bodies scale it by their collision shape's width (0.6 to 3 times).
- Presentation only: speed, collision and footsteps do not change.

The art is two Magnific GPT 2.5 sheets (`asset/Originals/water/generated/wade-splash.png`,
`swim-ripple.png`, transparent 2 x 2 grids, the water texture as colour reference), packed by
`python scripts/art/build-water-wake-sheet.py`, which aligns every frame on its ring. Tests:
`godot/tests/test_water_wake.gd` (shallow only, the frames animate, none in the air, enemies too)
and `test_water_collision.gd` (shallow water walkable, deep water blocks).

Swimming itself is the Frog Gulp form ([abilities.md](abilities.md) §11.7,
`game/player/gulp/player_swimming.gd`): its body ignores the `water` layer, and in deep water the
slime plays the swim clips (`swim-down`, `-up`, `-side`, page 3 of the slime sheet), which show the
whole body treading water, so a waterline 30 px above the feet of the 256 px cell hides its lower
part and the art sinks by as much onto the swim ripple. Tests: `godot/tests/test_frog_form.gd`.
