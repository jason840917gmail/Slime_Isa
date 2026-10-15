> **Archived 2026-10-14** from the branch `feat/elevation-levels` (the Phaser-era ground-levels
> attempt of 2026-10-04, rejected and never merged; the branch is deleted). Kept as a reference
> for the level rules the Godot elevation has not built yet (enemies, projectiles, sight and
> spawns by level), not as a plan: the Godot design is [docs/godot/ELEVATION.md](../../godot/ELEVATION.md).

# Ground Levels (Elevation)

> **Status: foundation system, built and playable in the playground's
> Elevation Park (roadmap milestone [H](./GAME_ROADMAP.md#h-ground-levels-elevation)).**
> Ground levels touch walking, collision, rendering, depth, gravity, jumps,
> abilities, combat, projectiles, sight, enemy AI, spawning, interactions,
> loot and saves. **Every new feature must answer the
> [elevation checklist](#the-elevation-checklist-for-every-new-feature)
> before it is planned and again before it is marked done.**

## The idea in one paragraph

The world is not flat. Every map cell has a whole-number **level** (…, -2,
-1, 0, 1, 2, … as many as a map needs). A raised block of ground shows a
**cliff face** on its south side, one tile row tall per level it rises, and
**walls** on its east, west and north edges, the way *A Link to the Past*
draws its plateaus. Stairs, ramps, ladders and vines join levels. Walking off
a rim drops the slime to the ground below; tall falls hurt; bottomless pits
send it back to safe ground. Bodies only touch, hit and push bodies at their
own height. Projectiles fly in 3D: they plunge from high ground, clear a cliff
only near its rim, and stop against the face. A cliff hides what stands back
from its rim.

## What we take from other games

| Game | What it does with height | What Slime Isa keeps |
|---|---|---|
| *Zelda: A Link to the Past*, *Minish Cap* | Plateaus with tall front faces and thick side walls; stairs cut into faces; ledges you hop down but not up; pits that return you to the edge with damage | The look (faces, side and back walls), stairs in faces, one-way drops, pits |
| *CrossCode* | True height for every entity; auto-jump off any edge; projectiles and jumps in 3D; high ground for ranged fights | Projectile flight and sight in 3D; walking off any rim drops you |
| *Hyper Light Drifter* | Falls into the void cost health and respawn you on the last safe tile | Pit rule |
| *Pokémon* | One-way ledges | Drops are one-way: climbing needs stairs, a ladder, vines or a Jump |
| *Stardew Valley*, *Eastward* | Terraced cliffs as layout and decoration | Terraces that guide exploration |
| RTS games (*StarCraft*, *Warcraft III*) | Low ground cannot see high ground | Cover: stand back from the rim and archers below cannot see or hit you |

## The model

### Levels, faces and walls

- The map is authored **as the camera sees it** (screen space). An
  **elevation layer** stores one level per cell; unpainted cells are level 0.
- **One level is exactly one tile row of cliff face (64 px).** A level-L
  block standing above level-M ground uses the bottom `L − M` rows of its
  painted area as its **face**. Face cells are never walkable; they are the
  wall seen from the front. So a block needs at least `L − M + 1` rows to
  have walkable ground on top.
- The north edge of a block is its **back wall** and its east and west edges
  are **side walls**: thick bands drawn where the block meets lower ground,
  thicker for taller drops, wrapping down past the ends of the south face.
  Both the high and the low level are kept off the wall by thin colliders
  where it is drawn (`features/elevation/ElevationWalls.ts`).
- Walls are traced as continuous outlines and **turn with 45° corners**, outer
  and inner, like *A Link to the Past* (`features/elevation/WallContours.ts`):
  each 90° turn is cut back by up to 40 px along both walls; the small corner
  triangle changes sides (outer corners show low ground, inner corners high
  ground) and a collider square keeps the right level off the diagonal.
- **Lighting:** light comes from the upper left. A darker, scalloped band of
  low ground hugs every wall so the join is seamless: widest behind a block
  (its north edge), narrower on its east side, narrowest on its lit west side.
  The foot of every face casts the strongest shadow. Walls facing east are
  darker, walls facing west are lit, back walls sit in between.
- Connector cells join levels; their two levels come from the cells on
  either side, their height is interpolated across them. The run climbs
  along the axis whose two ends are each one level (a floor at the top, a
  floor at the bottom); a side that mixes levels is a wall beside the run, so
  stairs cut along a wall still climb between the floors at their ends:

| Painted tile | Who can use it | Notes |
|---|---|---|
| `stairs` | everyone | Stone or wooden steps. In a south face: as many rows as the levels they climb. Sideways stairs (east/west) work too |
| `ramp` | everyone | A slope paved with the ground it climbs to |
| `ladder` | the player only | Enemies cannot climb ladders |
| `vines` | the **Sticky** Gulp form only | A climbing wall; a silk Gulp spot belongs beside it |
| `pit` | nobody | Bottomless. Falling in costs `pitDamage` and returns the slime to the last safe ground |

- Painting **water** in a face's rows makes a **waterfall** (animated curtain,
  foam at the rim, splash at the foot). The water stays solid like any water.
- Negative levels make canyons, quarries and sunken caves: their north wall
  is a face of the level-0 ground above them.

### Depth (the projected frame)

Everything that needs real depth works in the **projected frame**: a point
drawn at screen `y` at elevation `E` (in levels) has the depth coordinate
`y + E × 64`, which stays constant while something moves straight up or down.

- A body's **feet** (bottom centre of its collider) say which cell it stands
  in; its **level** comes from that cell (the rounded height on a connector).
  Only a falling body carries a stored level and a height above the ground.
- `ElevationField.physicalSurface(x, depth)` answers how high the ground is at
  a depth coordinate. Falls, projectiles and sight use it, so a south drop
  falls straight down the face, an arrow hits the face where it meets it, and
  a cliff hides what stands behind its rim.
- **Draw order is unchanged:** sprites still sort by their feet (ground anchor),
  and a fall or jump only moves the picture (`visual.effects.offsetY`), never
  the sort key (`presentation/WorldDepth.ts`). A body standing at the foot of a
  face draws in front of it; a body on top draws behind anything south of it.

## The rules (gameplay contract)

All tunable numbers are in `content/game-constants.json` → `elevation`.

| Topic | Rule |
|---|---|
| Walking | Bodies walk only on cells of their own level and on connectors that include it. Faces, walls, pits and other levels block. |
| Stairs and ramps | Walking across them changes the level smoothly; anyone may use them. |
| Ladders, vines | Ladders: player only. Vines: Sticky form only. Everyone else is blocked. |
| Dropping | Pushing against a rim for `dropPushMs` hops the slime down: south and side drops fall straight down the face, north drops hop to the visible ground. Drops taller than `maxVoluntaryDropLevels` stay solid ("Too high to jump down"). |
| Falling | Gravity `gravityPxPerSecondSquared`; input waits until landing. Falls of `safeDropLevels` or fewer are free; each extra level costs `fallDamagePerLevel` (half in the Heavy form). |
| Stomp | Landing from one level or more deals `stompDamagePerLevel` × levels to enemies within `stompRadiusPx` (double in the Heavy form). Heavy landings also break cracked ground. |
| Pits | Walking into a pit drops the slime in; it loses `pitDamage` and returns to the last safe ground away from the pit. Enemies never fall into pits. |
| Knockback | Knockback that carries a body into a rim pushes it off (enemies and the slime). |
| Jump | Flies over lower ground and gaps, mantles ledges up to `jumpClimbLevels` higher, stops before taller faces, and lands on the last standable spot. A Jump that comes down a cliff costs fall damage like a drop. |
| Teleport | Lands only on the slime's own level. |
| Stretch Lash | A heavy catch on higher ground (a post on a plateau) pulls the slime up onto that ground. |
| Melee, contact, area hits | Reach only bodies within `meleeReachLevels` of the attack's height (`DamageRouter` reach gate). |
| Projectiles | Fly in a straight 3D line from the shooter's centre toward the target's centre (`bodyCentreLevels` above the feet): plunging from high ground, rising from low ground. They hit a body when within `projectileReachLevels` of its centre, pass over (or under) bodies at other heights, fly over props lower than them (`propHeightLevels`), and stop where they meet the ground (a cliff face). |
| Sight | Enemies see the slime only along a clear 3D line over the ground: standing back from a rim hides it from below; standing at the rim exposes it. Elevation colliders never block 2D sight; heights decide. |
| Enemy movement | Enemies take stairs and ramps to reach the slime (`ElevationNavigator`), never use ladders or vines, never drop on purpose, and do not swing melee at a target on another level. Ranged enemies need sight. |
| Spawning | Camp enemies spawn only on the level of their camp's home area, never on a face. |
| Interactions, Gulp spots | Only targets on the slime's own level are in reach (a chest on the cliff above is not). |
| Loot and saves | Drops never land on faces or pits; a saved position inside a face or pit is replaced by a spawn point. |

## Authoring

### In Scene Studio

1. Open the world (`?studio=scenes&scene=world.<id>`), press **+ Layer** and
   set the new layer's tile set to **`elevation.tiles`** (the layer's tile
   data must use that tile set; a world has at most one elevation layer).
2. Paint `level-N` (`level-n2` is level −2), `stairs`, `ramp`, `ladder`,
   `vines` and `pit`. Studio shows the painted cells as numbered, coloured
   squares over the cliffs; the game hides them (dev panel → *Show ground
   levels* brings them back).
3. Leave a face: a block that rises D levels needs its bottom D rows for the
   face. Put stairs, ramps, ladders and vines **in those face rows**, as many
   rows as levels.
4. The cliff style comes from the ground tile painted under the face
   (`terrain.tiles` → `elevation.cliffStyle`): meadow, forest, autumn, desert,
   snow, cave, crystal, town, volcanic, castle, dungeon. Paint water in face
   rows for a waterfall.
5. Run `pnpm scenes:check` and `pnpm assets:worlds`.

### By script

`scripts/maps/build-playground-elevation.mjs` builds Elevation Park and is
the worked example: `level(x0, y0, x1, y1, n)`, `mark(…, 'stairs')`,
`paint(…, terrainTile)` and enemy camps placed on their level.

### Interiors: castles, dungeons and caves

Inside, walls are raised ground too, never wall objects: every cell that is
not floor is masonry or rock a few levels above the floor beside it, so the
same faces, side walls, 45° corners, shadows, colliders and drops apply.

- **North walls** are tall faces (a band as many rows deep as the wall is
  high, plus a row of wall top). **Side walls** show their thick side walls.
  **South walls** show only their top and back-wall rim, as in Link to the Past.
- Paint wall tops with a dark wall-top ground so solid masonry reads apart
  from walkable floor: `castle-wall-top`, `dungeon-wall-top`, `cave-rock-top`
  (the face art, darkened). Floors: `castle-floor`, `castle-carpet`,
  `dungeon-floor`, `cavern-floor`, `crystal-floor`. Each picks its cliff style
  (castle, dungeon, cave, crystal), so a raised dais or gallery on castle
  floor gets castle walls.
- Raised platforms (a throne dais, galleries for archers, a ledge a Jump up),
  sunken rooms, pits with one-cell bridges, ladders, vines and waterfalls all
  work indoors as outdoors. A solid pillar is a small raised block with a
  wall-top ground (2 × 3 cells at level 2: one row of top, two of face).
- Doors: an unmarked doorway is a gap in the south wall with an inline
  `game.door` node; `object.cave-ladder` climbs back out of an underground
  room. From outside, `object.castle-gate` and `object.dungeon-entrance`
  (`game.door`) stand against a face like the cave doors.
- Furnishings: `object.interior.<name>` (wall torch, brazier, banner, throne,
  armor stand, candle table, weapon rack, candelabra, cell bars, wall chains,
  barrel, crates, broken pots, treasure pile, cobweb, orb pedestal). Torches,
  braziers and candles flicker; wall pieces, cobwebs and shards are
  walk-through. Hang wall torches on a north face by placing their foot in
  the face rows.

`scripts/maps/build-playground-interiors.mjs` builds the three interior
testbeds (`playground-castle`, `playground-dungeon`,
`playground-cave-depths`, described in
[AUTHORED_MAPS.md](./AUTHORED_MAPS.md#dev-only-worlds)) from rooms and
chambers: `floor(…, level, tile)` opens floor, `level`/`mark` raise blocks and
place connectors, and `walls(tile, { level } | { above })` closes every other
cell (`above` puts a wall that many levels over its nearest floor).

### Layout tips

- Give stairs two or three columns: they read better and enemies path through them.
- A one-level step with no stairs is a Jump puzzle; two levels need stairs, a ladder or vines.
- A tall cliff with a ladder and a Gulp spot beside vines makes a gated shortcut.
- Put archers on high ground, brawlers below and a ramp between them: the fight changes as the slime climbs.
- Keep at least one row of walkable ground in front of every face.

## Art

| Asset | File | Made by |
|---|---|---|
| Cliff face per style (wraps both ways) | `asset/MAPS/elevation/256x256-tile_4x3-cliff-faces.webp` (`sheet.elevation.cliff-faces`) | Magnific GPT-2, `scripts/elevation/pack-cliff-art.py` |
| Rim overhang per style (grass, moss, leaves, sand, snow, rock, crystals, capstones, basalt) | `asset/MAPS/elevation/512x64-tile_1x12-cliff-lips.webp` (`sheet.elevation.cliff-lips`) | same |
| Waterfall curtain and foam | `256x256-waterfall-curtain.webp`, `512x64-waterfall-foam.webp` | same |
| Editor tiles (numbers and icons) | `64x64-tile_8x4-elevation-editor.webp` | `scripts/elevation/build-elevation-editor-tiles.py` |
| Volcanic ash ground (for the volcanic style) | `asset/MAPS/grounds/64x64-tile_19x19_black-ashlands.webp` | `pnpm grounds:pack` |
| Cave entrances (meadow, forest, desert, snow, crystal, volcanic) | `192x192-tile_3x2-cave-entrances.webp` → scenes `object.cave-entrance.<style>` (solid) and `object.cave-door.<style>` (`game.door`) | Magnific GPT-2, `pack-cliff-art.py props`, `scripts/elevation/generate-elevation-prop-scenes.mjs` |
| Cliff dressing (16: boulders, mossy rock, mushrooms, roots, autumn rocks, thornbush, sandstone rubble, skull, snowdrift, ice chunks, icicles, frosted rock, slate rubble, crystals, fallen blocks, basalt rubble) | `128x128-tile_4x4-cliff-decor.webp` → scenes `object.cliff-decor.<name>` | same |
| Interior floors: castle flagstones, dungeon cobbles, royal carpet | `asset/MAPS/grounds/64x64-tile_19x19_{castle-floor,dungeon-floor,royal-carpet}.webp` | Magnific GPT-2, `pnpm grounds:pack` |
| Interior wall tops (castle, dungeon, cave) | `asset/MAPS/grounds/64x64-tile_19x19_{castle-wall-top,dungeon-wall-top,cave-rock-top}.webp` | the face art darkened, `pnpm grounds:pack` |
| Castle gate and dungeon entrance | `256x256-tile_2x1-interior-entrances.webp` → scenes `object.castle-gate`, `object.dungeon-entrance` (`game.door`) | Magnific GPT-2, `pack-cliff-art.py props`, `generate-elevation-prop-scenes.mjs` |
| Interior furnishings (16) | `128x128-tile_4x4-interior-props.webp` → scenes `object.interior.<name>` | same |
| Flame flicker for the torch, brazier, candle table and candelabra (8 frames each) | `128x128-tile_8x4-interior-flames.webp` | derived from the props by `pack-cliff-art.py props` |

The look target every cliff generation attached as its style reference is
`asset/Originals/elevation/concepts/terraced-meadow-concept.png`.

Bridge art (rope and stone decks, posts, an arch) is generated and waiting in
`asset/Originals/elevation/props/bridges-a.png` for task H.11. Sources live in
`asset/Originals/elevation/`.
Set a cave at the foot of a face (its mound covers the face behind it); a
`cave-door` instance needs `mapId`, `doorId`, `targetAreaId` and
`targetDoorId` overrides like any door.
`node scripts/elevation/register-elevation-assets.mjs` owns their manifest
entries.

**Adding a cliff style:** generate a seamless face texture and a rim strip with
the [Magnific guide](./assets/magnific-mcp-guide.md) (prompts in the pack
script's sources), add the style to `STYLES` in
`scripts/elevation/pack-cliff-art.py` and to `content/elevation/cliffStyles.ts`
(same index), pack, and set `elevation.cliffStyle` on the terrain tiles that use it.

## Code map

| File | Owns |
|---|---|
| `features/elevation/ElevationField.ts` | The pure model: tile ids, derived faces and connectors, walkability, surface height, the projected frame, 3D segment tests, drop plans |
| `features/elevation/ElevationWalls.ts` | Where side and back walls are and how thick (shared by art and colliders) |
| `features/elevation/WallContours.ts` | Walls traced into outlines with 45° corners, mitered bands, corner fills and corner colliders |
| `features/elevation/ElevationRules.ts` | Reach, sight, aiming and fall damage rules |
| `features/elevation/ElevationNavigator.ts` | Breadth-first routes between levels for walking enemies |
| `features/elevation/ElevationController.ts` | Runtime: per-level colliders and the blocking filter, falls, drops, pits, stomps, the damage reach gate, queries for scripts and abilities |
| `features/elevation/ElevationPorts.ts` | `ElevationScriptPort` (script service `world.elevation`) and its flat fallback |
| `features/elevation/ElevationOverlay.ts` | Whether painted levels show (Studio, dev panel) |
| `features/world/elevation/CliffPlan.ts`, `CliffLayer.ts`, `WaterfallLayer.ts` | Drawing: faces, walls, rims, shadows, stairs, ramps, ladders, vines, pits, waterfalls |
| `content/elevation/cliffStyles.ts` | Cliff styles and their colours |
| `infrastructure/phaser-nodes/TileMapLayer2DNode.ts` | Mounts the cliff and waterfall layers for an elevation layer (game and Studio alike) |
| `infrastructure/scenes/WorldSceneLoader.ts` | Keeps elevation layers out of the terrain grid; builds `LoadedWorldMap.elevation` |
| `infrastructure/scenes/PhaserNodeContext.ts` | `setBlockingFilter`, `sightTransparent` |
| `features/combat/DamageRouter.ts` | `setReachGate`, rejection reason `out-of-reach`; `DamageRequest.elevation` |

## The elevation checklist for every new feature

Answer each line in the feature's plan, and check it in the playground before
the feature is done. "Not applicable" is a valid answer; silence is not.

1. **Where can it stand?** Which levels, and can it use stairs, ramps, ladders, vines?
2. **Can it leave its level?** Does it drop off rims, get knocked off, fly, climb, fall into pits?
3. **What can it reach?** Melee, area and contact attacks: same level only? Does anything reach across levels on purpose (and why)?
4. **What does it fire?** Projectiles must fly through `ProjectileScript.flyAt` (or an equivalent 3D flight) and stop at cliff faces.
5. **What can it see?** Sight across levels uses `ElevationScriptPort.sight`.
6. **How does it move toward things?** Walking AI uses routes (`ElevationScriptPort.route`), never a straight line through a cliff.
7. **Where does it spawn, drop, land or teleport?** Never inside a face or pit; on the intended level.
8. **How is it drawn?** Sorted by its feet; height only as a visual offset; a shadow when airborne.
9. **Interactions:** is it usable only from its own level?
10. **Tests:** a Node test for the rule and a spot in Elevation Park that shows it.

## Testing

- `pnpm test:elevation` — the field, rules, walls and navigator.
- Elevation Park (`pnpm dev`, `http://localhost:3000/?map=playground`, then
  walk south from the spawn): zones A–H are described in
  [AUTHORED_MAPS.md](./AUTHORED_MAPS.md#dev-only-worlds). The dev panel's
  *Show ground levels* paints every cell's level.
- Interiors: the castle gate (Town Terraces), the dungeon entrance (archery
  range) and the meadow cave (Meadow Terraces) lead into `playground-castle`,
  `playground-dungeon` and `playground-cave-depths`; `?map=<id>` opens them
  directly.
- Headless playtests (Playwright + Brave, see the agent memory notes) can teleport
  the slime with `scene.teleportPlayer`, read `scene.elevation.playerLevel()`,
  and hold WASD.

## Known limits and next steps

- **Bridges** (a deck over lower ground that bodies walk on while others pass
  underneath) need two standing levels in one cell; planned in milestone H.
- **Flying enemies** (bats, birds) should ignore levels; no enemy flies yet.
- **The player has no ranged weapon yet.** When the Bouncy Bow arrives it must
  use the same 3D flight as enemy projectiles.
- Prop heights are one value (`propHeightLevels`); tall trees and low fences
  should get their own height property.
- Enemies take no fall damage and never drop on purpose; a "leaper" enemy
  that hops down cliffs is a good future type.
- Terrain blending (`TERRAIN_TRANSITIONS.md`) still blends materials across a
  rim; walls cover most of it.
- The minimap does not shade levels yet.
- Interiors have no light or darkness: torches and braziers are decoration.
  A dark-room mechanic (a light radius, torches to light) would be its own feature.
- Cliff chunks are baked canvases like the terrain blend: fine for the
  playground's 80 × 72 tiles; very large maps should be measured (milestone 10.4).
