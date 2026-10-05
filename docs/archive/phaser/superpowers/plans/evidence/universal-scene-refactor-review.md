# Universal Scene refactor — post-implementation review

Reviewed: `main` @ `a1d5036` (2026-09-26) against the last pre-refactor commit `ec0271e`.
Method: code reading old vs new, `pnpm typecheck` + scene/combat test suites, a script that replays the old layered-animation math for every weapon frame and diffs it against the generated scene tracks, and headless Chromium runs of the game and of Scene Studio.

**Status:** typecheck passes. `scene-content`, `scene-runtime`, `scene-integration`, `scene-studio` and `combat` all pass. `scene-conversion` fails 16 tests on a Linux checkout (see §6).

**Root theme:** the tests check structure (node counts, "moved more than 10px", contact signals fired by hand, hand-picked layer/mask values), not gameplay. The converters also re-implemented runtime math by hand instead of calling the shared functions the old runtime used. So every mismatch in that math went out silently, for every asset at once. The final report itself says gameplay testing was "Not performed".

---

## 1. Physics / collision — why you walk through trees, walls and houses

### 1.1 CRITICAL — collision layer/mask data plus a two-way acceptance rule make the player (and NPCs) ignore every solid

**Data** (produced by the converters):

| Body | Layer | Mask |
|---|---|---|
| Player | 1 | 3 |
| NPCs | 1 | 1 |
| Enemies | 2 | 5 |
| Every StaticBody2D (trees, houses, walls, rocks, chests), `TileMapLayer2DNode` wall tiles | 1 | 2 |

These come from `scripts/lib/scene-conversion/characters.mjs:88,119,156`, `objects.mjs:124,258,330`, `maps.mjs:385` and `TileMapLayer2DNode.ts:59-60`.

**Rule:** `PhaserNodeContext.ts:257-259` (pair colliders) and `:279-281` (static group) require **both** `A.mask & B.layer` **and** `B.mask & A.layer`.

- Player vs static: `3 & 1 = 1` ✓, but `2 & 1 = 0` ✗, so the pair is rejected and the player passes through.
- NPC vs static: rejected the same way.
- Enemies (layer 2) are accepted, which is why only enemies still collide with walls.
- `worm-arrow` projectile is layer 0 / mask 0, so it is never blocked. `ProjectileScript.ts:63` waits for a blocking contact that can never come, so arrows fly through walls and trees.

**Fundamental fix:**
1. **Named layers defined once**, in project data (a Godot-style "layer names" table, e.g. `world=1, player=2, enemy=4, npc=8, hurtbox=16, hitbox=32, pickup=64…`). Converters and the editor reference the names; nobody writes raw numbers.
2. **Godot semantics:** a moving body is blocked when *its own* mask contains the other's layer. A static body's mask is irrelevant. For two moving bodies, use OR (either side detecting is enough for Arcade's symmetric separation) or resolve per side.
3. **Validation in `scenes:check`:** every `CharacterBody2D` whose role moves in the world must include the `world` layer in its mask. Also warn about any authored body pair that can never interact.
4. **Behaviour test in the browser suite:** load real production scenes (player, NPC, enemy, projectile), push each into a house, a tree, a wall tile and a map edge, and assert it is blocked. The current `physics-contacts.spec.ts` uses hand-picked 1/2 vs 2/1 values that don't match production data.

### 1.2 HIGH — Arcade's per-step body reset never runs (confirmed in browser)

`PhaserNodeContext.startManualStepping` disables Phaser's update and `stepPhysics` calls `world.step()` directly (`PhaserNodeContext.ts:203`). In Phaser 3.90, `World.step` does **not** call `Body.preUpdate`, so `resetFlags()` (touching/blocked/embedded) and the `prev`/`prevFrame` refresh never run.

- **Measured:** the player touched an NPC; `touching.right` stayed `true` after walking about 350px away.
- **Effect:** contact normals (`PhaserNodeContext.ts:296`) read stale flags. Arcade's separation code (`ProcessX/ProcessY BlockCheck`) reads `blocked.*`, so once the layers are fixed you can expect sticky or one-sided walls and pushes that spread to other bodies (suspected).
- **Fix:** own the full step contract in `stepPhysics`:
  1. For each enabled dynamic body, run the `preUpdate` work: `resetFlags()`, copy `position` into `prev`/`prevFrame`, and **do not** call `updateFromGameObject`, because the backend object sits at the node anchor, not the body centre.
  2. Then `world.step(dt)`.
  3. Add a test that the flags clear after two bodies separate.

### 1.3 HIGH — world bounds removed (confirmed)

The old player, enemies and boss used `setCollideWorldBounds(true)` (old `PlayerFactory.ts:20`). Nothing in the new `src` sets it except `TargetDummy`. **Measured:** walking left on level-1 reached x = −307.

**Fix:** add a `collideWorldBounds` body property (default true for CharacterBody2D). Apply it in `PhysicsBody2DNode`, with bounds taken from the world scene's size, not a constant.

### 1.4 MEDIUM — related correctness gaps
- **Authored inset collision size is ignored.** `updateFromGameObject`/`refreshBody` resets static tile bodies to 64×64 instead of the authored inset (e.g. 48×52). This was true before the refactor too, but the new node system should honour the shape resource. Set size/offset *after* the refresh, or compute it from the `CollisionShape2D`.
- **One body, one shape.** `PhysicsBody2DNode.enabledShape()` throws unless there is exactly one enabled shape, and rejects sector shapes. It is fine as a documented limit, but it should be a `scenes:check` rule rather than a runtime throw.
- **Pair colliders grow with the square of the body count.** `createBlockingCollider` makes one collider per pair of dynamic bodies. Group dynamic bodies by layer and create one collider per interacting layer pair.
- **Water.** Water/deep-water have no physics before or after the refactor. If they should block, that is a tile-set data change (a collision shape on those tiles), not code.

---

## 2. Weapons, combat and animation alignment

Most of the misalignment has one source: `scripts/lib/scene-conversion/combat-entities.mjs` flattened the old layered animation system incorrectly, and the runtime lost two capabilities it needs (mirroring and parent-relative depth).

### 2.1 CRITICAL — layer transforms are *replaced*, not *composed* (confirmed by replaying every frame)
- **Old:** `src/game/shared/animation/layeredTransform.ts:36-60` added layer offset and block offset, multiplied the scales, added the rotations and XOR'd the flips.
- **New:** `combat-entities.mjs:72-84` does `{ ...base, ...block.transform }`. Any key the block sets overwrites the layer's value, and `flipX/flipY` are dropped.
- **Effect:**
  - Most weapon layers have scale 0.5–0.62 and blocks say 1.0, so weapons draw at 1.6–2× size. Scale is wrong in 31/40 frames for basic-sword, 58/58 for slam-hammer and 32/32 for wooden-axe.
  - basic-sword's slash layer (offset `[60,0]`) loses its offset in the up-attack.
- **Fix:** the converter must not re-implement the math. Sample each frame through the same `resolveLayeredAnimationFrame` + `composeAnimationVisualTransform` from `shared/animation` that the old runtime used. Add a **parity test** that, for every weapon, character and effect, compares old-math output with generated tracks frame by frame.

### 2.2 CRITICAL — inherited directions are never mirrored (left from right, up from down)
- **Old:** `normalize.ts` resolved inheritance, and `WeaponVisual.getAnimationHostTransform` (old `WeaponVisual.ts:78-90`) mirrored offsets, rotation and flip.
- **New:**
  - `combat-entities.mjs:150` reuses the right-facing animation unchanged for `attack-left` (and for `attack-up` on pickaxe, stone-axe, stone-pickaxe, stone-spear, wooden-spear).
  - The `mirrored` flag written at `:173` is read by nothing.
  - Effects have the same bug (`:263-267`).
- **The runtime can't express a mirror:**
  - `Node2D` rejects negative scale (`runtime/scene/Node2D.ts:52,73`).
  - `flipX/flipY` are not animatable (`propertyDescriptors.ts:263`).
- **Effect:** attacking left swings the weapon visual on the right side while the hitbox is correctly at −x, so the visual and the damage zone disagree.
- **Fix:**
  1. Add mirroring to the transform model: allow negative scale, or add a `mirror` flag on `Node2D` that composes into children.
  2. Make `flipX/flipY` animatable step properties.
  3. Have the converter call the existing `materializeDirectionalAnimation(anim, { mirrorX, mirrorY })` before sampling.

### 2.3 HIGH — weapon and effect draw order lost
- **Old:** weapon depth was `player.depth + 0.01` (old `CombatController.ts:346`) plus `layerIndex*0.001 + depthOffset` per layer (`layered.ts:117`).
- **New:**
  - Every weapon/effect `Sprite2D` is `depthMode:'world-sorted'` (`combat-entities.mjs:118`), so its depth comes from its own Y (`Sprite2DNode.ts:193-203`).
  - `depthOffset` and layer order are discarded.
  - `spawnEffect` ignores `request.depth` (`UniversalSceneWorldController.ts:777-782`).
- **Effect:** the sword draws behind the slime for frames 0–5 and then pops in front; slash and blade layers can swap; impacts draw under enemies.
- **Fix:** add a parent-relative depth mode (`depthMode:'relative'` + depth-anchor node + offset). The converter writes it from source `depthOffset`/layer order, and effect spawns honour the requested depth.

### 2.4 HIGH — the +20px correction for up-attacks inherited from down is dropped
- **Old:** the hitbox and the visual both got `resolveWeaponPresentationOffsetY(mirrorY)` (+20) (old `Weapon.ts:158,271`, `WeaponVisual.ts:84`).
- **New:** `orientedPosition` (`combat-entities.mjs:139-144`) only rotates.
- **Effect:** the up-hitbox is 20px too high for 5 weapons, so they miss targets directly above.
- **Fix:** use the weapon normalizer's `directionalAttacks[d].presentationOffsetY` instead of re-deriving directions.

### 2.5 HIGH — enemies no longer react to hits
- **Old `Enemy.applyDamage`:** cancelled the windup, applied knockback of (strength + 120) × (1 − resist) and 320–600 ms of stun with velocity decay.
- **New:** `EnemyScript.commitDamage` (`EnemyScript.ts:153`) only lowers HP and stores effects in `activeEffects`, which nothing reads. Enemies can't be staggered or interrupted, which makes combat feel broken.
- **Also lost:**
  - After an attack the old AI fled when inside `fleeRange`; `finishAttack` (`:238`) now always chases.
  - The attack now ends at `windup + recovery` (`:382`) instead of `max(windup+recovery, clipDuration)+250`, so the clip is cut off mid-swing.
  - Ranged enemies no longer re-check range after the windup.
- **Fix:** a data-driven hit-reaction state in `EnemyScript` that consumes knockback/stun from the damage commit, using the enemy's attributes. End attacks on `animation_finished` or read the clip length from the AnimationPlayer library.

### 2.6 HIGH — multi-hitbox attacks can hit a target only once
- **Old:** each hitbox window had its own hit list (old `Hitbox.ts:151`, `Weapon.ts:229`), e.g. goo-gauntlet punch + impact.
- **New:** dedupe per attack (`WeaponScript.ts:226,239`, `AttackActivation.ts:60`), and hits rely on edge-triggered "entered". A target already inside the area when the next window opens is never hit.
- **Fix:** dedupe on (hitbox window, receiver), and query current overlaps when a window activates.

### 2.7 MEDIUM
- **Enemies never face left.** `EnemyScript.playDirectional` (`:459-461`) maps left and right to `*-side` and never flips; the old code did `setFlipX(vector.x < 0)`. This needs the mirror capability from 2.2.
- **Hardcoded or dropped animation data** in the converters:
  - `animations.mjs:49` keeps `loopMode` only for NPCs, so the spider's ping-pong idle now wraps.
  - `:50-51` hardcodes gameplay events (`attack-side` at frame 1, `contact-hop`) instead of reading `animationTracks`.
  - `:54-60` uses magic FPS/frame numbers for the boss.
  - `characters.mjs:158` hardcodes enemy `origin:[0.5,0.5], scale:[1,1]` and ignores `visual-set.json defaults` (the NPC/player builders already read them).
  - Player `frameVisuals` and projectile `frameOffsets` are not converted, and projectile `sourceOffset` no longer rotates with velocity (old `Projectile.ts:296-304`).
- **Two clocks for weapon timing.** `CombatController.ts:140` passes `scene.time.now` into `WeaponScript`, which gates hitbox windows on it while the AnimationPlayer runs on simulation time; they can drift after pauses. Drive hitbox enable/disable from AnimationPlayer events.

### 2.8 Depth sorting and occlusion (MEDIUM, confirmed)
- **Sort point:** characters now sort by the sprite origin (`Sprite2DNode.ts:202`), not body bottom (player ≈ 27px off).
- **Two depths disagree:** occlusion reads the hidden physics sprite's depth (`WorldScene.ts:686`) while rendering uses the visual sprite.
- **Enemies lost occlusion silhouettes:** they are no longer registered for them (old `Enemy.ts:141`).
- **Fix:** an authored `depthAnchor` (feet point, derived from the body shape) on each character scene, used by both render and occlusion. Every scene that has one registers for occlusion through the scene, not by hand-wiring.

---

## 3. Editor — why Scene Studio shows nothing (reproduced in Chromium)

### 3.1 CRITICAL — `fetch` called unbound
`SceneStudioRepository.ts:52`: `private readonly request: Fetch = fetch`, later called as `this.request(...)`. The browser throws **"Failed to execute 'fetch' on 'Window': Illegal invocation"**. `SceneStudio.ts` catches it into the status bar, so the list stays at "Scenes 0". Every legacy URL (`?editor=level-1`, `?studio=characters`, …) redirects correctly and then lands on this same empty page. Tests never saw it because they always inject a fake fetch.

**Fix:** `request: Fetch = (input, init) => globalThis.fetch(input, init)`, plus one browser test that uses the real default constructor. Verified: scenes load after this change.

### 3.2 HIGH — the layout grows with the list
`scene-studio.css:9-12` uses `grid-template: 72px 1fr 30px` with `min-height:100%`. With 355 explorer rows the middle row grows to about 17,800px. `body` has `overflow:hidden`, and the viewport centres the origin at `top:50%`, so everything, including the status bar, sits about 8,900px off-screen.

**Fix:** `height:100%; grid-template-rows: 72px minmax(0,1fr) 30px;` and scroll inside the explorer.

### 3.3 HIGH — the viewport never renders real content
- `SceneStudio.ts:409-477` draws diamonds, "GR" text buttons for tiles and outline boxes. There are no textures, no Phaser and no asset manifest.
- `ScenePreview.ts` is an interface with **no implementation**. `ResourceBrowser`, `ShapeEditor`, `ViewportSelection`, `SceneClipboard` and `contexts/{Animation,Audio,Signal,Debug}Context` are imported by nothing.
- **Also missing:**
  - Wheel/drag pan and zoom are not bound (`SceneViewport.ts:23-25` has them, `SceneStudio.bind()` never wires them), so objects at world coordinates (x ≈ 1400–3500) can't be reached.
  - Child positions ignore their parents (`SceneViewport.ts:53-56`).
  - Instanced scenes (25 in level-1, 414 in meadow-crossing) are never drawn or expandable (no resolver passed, `SceneStudio.ts:395,403`).
- **Fix:**
  1. Implement `ScenePreviewFactory` as an embedded Phaser game that mounts the scene through the **same** `PhaserSceneTreeHost` and node registry as the game, in a paused/editor mode. That way the editor can never drift from runtime rendering.
  2. Compose global transforms through the tree.
  3. Resolve instances.
  4. Add pan, zoom and frame-all.

### 3.4 Regressions vs the old editors (capabilities that no longer exist)
- **Map editor:** rendered world, drag-painting, object search/place/drag, enemy/NPC areas, new map / resize, map connections.
- **Character Studio:** sheet preview, timeline, directional inheritance editor.
- **Animation Studio:** block timeline, playback, layered inspector. Libraries are now raw JSON textareas.
- **Weapon Studio:** hitbox editor and guides, targeting editor.
- **Projectile Studio:** no dedicated preview or editor.
- **Other:** on-canvas shape handles, explorer search filter.
- The 29 old editor modules still in `src/game/editor/*.ts` are unreachable. The plan said to reuse them, and they weren't connected.

---

## 4. World runtime and performance

- **p95 frame time +107% on large maps.** Measured on gloop-forest: 11.9 of 17.1 ms is `tree.process`.
  - About 110 HTML UI controls re-sync every frame. `ControlPresentationAdapter.ts:36-38` reads `clientWidth/Height`, forcing layout, and `HtmlControlPresentationAdapter.ts:130` rewrites class, styles and `img.src` data URLs unconditionally. One TextureRect alone costs about 7.9 ms.
  - Every wall tile is repositioned and re-inserted into the static tree every frame (`TileMapLayer2DNode.ts:108-126`).
  - **Fix:** dirty flags / transform revision, never touch static tiles unless the layer moves, batch DOM reads before writes, set `src` only on change.
- **Frame-loop timing mix (suspected).** Gameplay input/abilities run in `beforeFixedStep` (0–5× per frame), and some timers use wall-clock time (`this.time.now`, `delayedCall`) that keeps running while modals pause the simulation, so action locks and knockback can expire during a pause. Use simulation time for all gameplay timers.
- **Exits fire only on "entered".** Standing in a locked gate after getting the key, or spawning inside an exit, doesn't trigger it (the old code checked overlap every frame). Low severity.
- **Hardcoded values left in the runtime:**
  - `UniversalSceneWorldController.ts`: `MANAGED_ENEMY_SCENES` (227), scene-name prefix checks (234), chest radius 112 and "Fatty One Eye" strings (599–609, 1047).
  - `config.ts`: a hand-maintained scene list.
  - `WorldScene`: "The Verdant Gate unlocks!", level-up text, respawn to `'level-1'`.
- **Leftover compatibility code:**
  - `WorldSceneLoader` rebuilds the legacy map format from a `metadata` blob.
  - Tile physics is defined in both the global `TileCatalog` and the per-map tile sets, which can drift apart.
  - `LegacyPlayerAbilityPresentation.ts` (364 lines) is still live.
  - `WorldScene.collisionTiles` is an empty static group still passed to combat and debug.
  - `WorldScene` is still 1,363 lines.

---

## 5. Plan completeness

| WP | Status |
|---|---|
| 0–8 foundations (documents, tree, resolver, Phaser host, bodies, animation, studio state) | Mostly in place. The physics contract (§1.1, §1.2) is semantically wrong and untested against production data. |
| 8 Scene Studio UI | **Incomplete.** No preview implementation, several modules unwired (§3). |
| 9–11 conversion of enemies, player, NPCs, weapons, effects | **Converted structurally, not behaviourally.** Transform composition, mirroring, depth and hit reaction were lost (§2). |
| 12–14 world, UI and audio cutover | Works, but with performance regressions (§4) and compatibility code left in. |
| 15 acceptance | **Not met.** Gameplay acceptance is "pending user checklist", and the p95 exception is unapproved. |

## 6. Tooling: `test:scene-conversion` fails on any machine but yours
`ConversionRunner.mjs:58` and `ui.mjs:73` hash raw file bytes. The ledger was hashed on Windows, where some files were CRLF (git checkout conversion) and some LF (tool-written).

| Ledger rows with a hash | Count |
|---|---|
| Match LF | 58 |
| Match only CRLF | 99 |
| Match neither | 93 |

Of the 93 that match neither, 12 are checked conversions (the icege map and 11 UI `.ts` files) that were hashed from uncommitted local edits.

**Fix:**
- Hash normalised text (strip BOM, CRLF → LF) or use the git blob hash.
- Add `.gitattributes` with `* text=auto eol=lf`.
- Regenerate the ledger.

---

## Recommended fix order
1. **Collision contract** (§1.1 named layers + Godot rule + validation, §1.2 step reset, §1.3 world bounds) with a production-data browser test.
2. **Editor unblock** (§3.1 fetch, §3.2 layout). These are one-line fixes, and after them you can see and select your content.
3. **Animation parity:**
   - Runtime: add mirror and relative depth to the runtime (§2.2, §2.3).
   - Converter: re-run it through the shared animation functions (§2.1, §2.4).
   - Parity test: old math vs generated tracks, for every asset.
4. **Combat feel:** enemy hit reaction, attack length, multi-hitbox dedupe, facing (§2.5–2.7).
5. **Depth anchor and occlusion** (§2.8).
6. **Real editor preview** through the shared Phaser host (§3.3), then port the timeline, hitbox and shape tools.
7. **Performance dirty-flags** (§4) and removal of the compatibility code.
8. **Replace structure-only tests with behaviour tests:** blocked-by-wall, facing-left visual matches hitbox, enemy staggers on hit, editor loads with the real fetch.
