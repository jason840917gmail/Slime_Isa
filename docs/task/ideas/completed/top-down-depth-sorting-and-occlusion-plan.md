# Top-down depth sorting and actor occlusion

Status: **Completed and verified**

The anchor-based depth, occlusion metadata, editor overlays, runtime reveal
behavior, diagnostics, and production content coverage are implemented.

This document is the implementation tracker for replacing fixed world depths
with ground-anchor Y-sorting and keeping actors readable behind tall scenery.

## Goals

- A player, enemy, friend, or projectile behind a tree or house renders behind it.
- The same entity renders in front after moving below the object's ground anchor.
- Visual offsets, animation frames, and sprite height never change the sort anchor.
- Hidden actors remain readable through an intentional silhouette.
- Tall-object occlusion regions are editable visual-template data in the map editor.
- Ground sorting, overhead artwork, effects, and UI have explicit non-overlapping
  depth bands.

## Current problem

World rendering currently uses unrelated fixed values:

- terrain: depth `1`;
- authored objects and legacy houses: depth `2`;
- enemies: depth `8`;
- friends: depth `9`;
- player: depth `10`;
- effects, labels, and UI use additional absolute values.

Consequently, characters paint over tall scenery regardless of their world
position. The existing stable foundations are:

- authored map objects already have an `objectAnchorX/objectAnchorY`;
- visual offsets are separate from object anchors and physics bodies;
- `AnimatedVisual` exposes `setDepth`;
- player and enemy visuals are attached to stable gameplay anchors.

## Architecture

### Shared depth policy

Add a small shared world-rendering module, owned by the presentation or visual
feature layer, with named bands:

1. ground terrain;
2. ground decals;
3. Y-sorted world entities;
4. overhead artwork;
5. reveal silhouettes and world effects;
6. screen UI.

The policy resolves a world depth from:

```text
bandBase
  + round(clamp(groundAnchorY, 0, 65_536) * 16) * 1_024
  + stableTieSlot * 16
  + attachmentSlot
```

- Band bases are separated by `2_000_000_000`, which exceeds the complete
  world-sort span for the supported `256 * 256px = 65_536px` map height.
- Sixteen Y quanta per pixel preserve sub-pixel movement.
- `stableTieSlot` is an integer from `0..31`.
- `attachmentSlot` is an integer from `-7..7`.
- Tie plus attachment values remain below half of one Y quantum, so they cannot
  invert entities in different Y quanta or cross a band boundary.
- The stable tie prevents flicker when two anchors share the same Y.
- Attachment bias keeps ears, name tags, health bars, or related visual parts
  ordered relative to their owner without assigning unrelated absolute depths.
- Visual/source offsets and airborne visual elevation do not affect the key.

Static scenery resolves depth when created or moved. Dynamic actors and
projectiles update depth only when their ground Y changes.

Every sorted owner receives a stable sort ID:

- authored map objects: persisted `instanceId`, passed into `ObjectFactory`;
- player: `player`;
- enemies: `enemy:<enemyId>`;
- friends and legacy houses: creation index assigned by their owning factory;
- pooled projectiles: `projectile:<owner>:<poolSlot>`.

The policy hashes the stable ID into the tie slot. Hash collisions retain
Phaser's stable display-list order and cannot oscillate between frames.

### Ground-anchor formulas

Do not use a sprite's `.y` indiscriminately:

- player, enemies, and friends: Arcade body bottom;
- every authored object, solid or decorative: persisted `objectAnchorY`; collider
  edits must never change render order;
- legacy houses and beds: an explicit base point owned by `House` (initially the
  door/base Y derived at construction), with their creation index as ID;
- projectiles: physics body center Y because they occupy a flight plane;
- attached visuals: owner's ground anchor and depth plus attachment slot.

These formulas become named resolver functions with unit tests. A future content
override may be added only when an asset cannot represent its ground point with
these contracts.

### Sorted and explicit modes

`ObjectFactory` and visual helpers accept an explicit depth mode:

- `world-sorted`: normal runtime and normal editor document objects;
- `explicit`: cursor ghosts, focused previews, drag lifts, selection markers,
  overlays, UI, and authored overhead parts.

`setObjectAnchor` recalculates depth only in `world-sorted` mode. Editor dragging
temporarily applies an explicit lift and restores the resolved sorted depth on
drop/cancel instead of restoring fixed depth `2`.

The policy defines editor-only bases above every gameplay band:

- editor document sorting uses the normal world formula;
- cursor/focused preview band;
- drag-lift band;
- move-handle/selection-marker band;
- template geometry overlay band.

Existing editor depths `85`, `95`, `107`, `120`, and similar values are migrated
to these named bases. No old small explicit depth may remain beside billion-scale
world bands.

### Ownership

- `ObjectFactory` applies static object depth from the stored object anchor.
- Player, enemy, and friend owners update their own depth and attached visuals.
- `AnimatedVisual` mirrors the resolved depth of its gameplay anchor.
- Projectile pooling assigns a stable pool-slot ID on creation. `CombatController`
  calls `projectilePool.update(scene)` from its existing update loop; that method
  recalculates active projectile depths only when body-center Y changes.
  `clearScene` destroys registrations and cached sort state.
- Legacy `House` objects use an explicit base/door ground point until they are
  replaced by authored-map objects.
- World labels and health bars use owner-relative attachment depth.
- Melee arcs, projectile impacts, and death particles use a world-sort key at
  their spawn/impact ground Y with an effect attachment slot, so foreground
  scenery can still occlude them correctly.
- Floating damage, healing, XP, and interaction text use the reveal/world-effects
  band above foreground scenery for readability; they remain below screen UI.
- Screen-space UI remains outside world sorting.

Runtime migration of static scenery and dynamic actors is one atomic rollout.
The branch may introduce policy helpers and tests first, but must not ship or
commit a gameplay state where sorted objects coexist with fixed-depth actors.

### Elevation

Ground depth and visual elevation are separate concepts. A jump can move a
sprite visually upward while its shadow and sort key remain at the ground
anchor. A future true-elevation system may add height-aware collision, but it
must not overload Phaser depth.

## Occlusion silhouettes

### Authored occlusion region

Add optional visual-template data:

```json
{
  "occlusionBounds": {
    "width": 96,
    "height": 112,
    "offsetX": 16,
    "offsetY": 8
  }
}
```

The rectangle uses source-frame pixels, like collider bounds:

- it belongs to the individual visual template;
- absence means the template does not occlude actors;
- it is independent from collision geometry;
- it follows the rendered art rather than the collider;
- it must fit inside the source frame;
- duplicated templates copy the current occlusion draft independently.

Only tall foreground-capable objects should opt in. Floors, collectibles, and
small props default to no occlusion.

Spritesheet frame dimensions are authoritative for validation. Procedural assets
and animated object templates cannot enable occlusion in the first
implementation. Procedural assets lack authoritative source-frame dimensions
across validators, while animated occluders would require spatial-grid
reindexing whenever a frame transform changes. The editor disables the checkbox
for both, and the client/server/checker contract rejects authored bounds on
either. Animated actors can still receive silhouettes. Dynamic/animated
occluders are a tracked extension after static regions are proven.

### Source rectangle to world rectangle

Use one shared pure transform for runtime and editor previews. Given the current
render sprite, source frame dimensions, scale, origin, flip, and source-space
occlusion rectangle:

1. derive the rendered frame's world top-left from sprite position, absolute
   display scale, and current origin;
2. mirror source X/Y offsets inside the frame when flipped;
3. multiply bounds dimensions and mirrored offsets by absolute display scale;
4. add the result to the rendered frame top-left.

The sprite position already contains object `visualOffset`, so the transform
must not subtract it. This is
deliberately different from collider placement: colliders stay attached to the
gameplay anchor, while occlusion bounds follow the visible static art.

### Runtime detection

`WorldScene` owns an `OcclusionController` and passes narrow registration
interfaces into object/actor factories. Each registration returns a disposable
handle and also listens to owner destruction as a safety net. Explicit cleanup
remains required.

The controller registers:

- static occluders and their resolved world rectangles;
- the player;
- active/engaged enemies;
- any future actor type explicitly opting into reveal behavior.

An actor is occluded only when:

1. the occluder is in front according to the shared depth policy;
2. actor visual bounds intersect the occluder's `occlusionBounds`;
3. both belong to the active scene and camera-relevant world area.

Enemy reveal eligibility is a public read-only Enemy query, not raw Phaser
`active`: alive and in `chase`, `attack`, or `flee`, or currently executing an
attack sequence. Idle/wandering enemies are not revealed. Eligibility is
re-evaluated during the controller update and becomes false immediately on
death.

Registration cleanup rules:

- object destruction unregisters its occluder;
- actor destruction/death unregisters or disables its reveal;
- enemy despawn and scene transition dispose registrations;
- editor `renderDocument` destroys editor-only preview registrations before
  rebuilding, although the gameplay silhouette controller is not created in the
  editor scene;
- scene shutdown destroys all reveal sprites, owner listeners, indices, and
  handles;
- projectile-pool scene cleanup clears depth state (projectiles are sorted but
  are not silhouette reveal actors).

### Performance contract

Use a uniform static grid with `256px` cells:

- insert/remove static occlusion rectangles during registration cleanup;
- query only cells touched by an actor's visual bounds plus a `32px` margin;
- skip actors whose expanded bounds do not intersect the camera world view plus
  `128px`;
- update once per scene update after actors and animations have updated;
- expose development counters for registered occluders, queried cells,
  candidates, intersections, and update milliseconds.

The automated large-map fixture contains at least 1,000 occluders and 50 actors.
The controller must avoid a 50,000-pair full scan, average fewer than 50
candidates per onscreen actor in the fixture, and report under `1ms` average
occlusion-update time across 600 frames on the documented development machine.

### Silhouette rendering

The reveal visual:

- mirrors the actor's current texture frame, animation frame, origin, scale,
  source offset, flip, and temporary visual transform;
- renders in a dedicated reveal band above foreground scenery;
- uses a readable player color and a distinct enemy color;
- is visible only while at least one valid occluder hides the actor;
- never changes physics, targeting, damage, or AI.

The player is always eligible. Enemies are eligible only while active/engaged so
the system does not reveal otherwise-undetected threats.

Rectangular full-actor silhouettes are phase one. Polygon masks and silhouettes
clipped to only the hidden pixels are future refinements.

## Map-editor support

Add an **Occlusion** section to the reusable template inspector:

- `Occludes actors` checkbox, default off when no bounds exist;
- width, height, offset X, and offset Y numeric fields;
- source-frame validation shared with the development server;
- a distinct translucent canvas rectangle;
- inclusion in Reset, Save template, and Save as new template;
- visual/collider/occlusion overlays remain independently identifiable.

The object schema, `ObjectCatalog`, object validator, object factory, template
draft state, update endpoint, and duplicate endpoint must agree on the field.

## Verification contract

Introduce reproducible checks rather than relying only on visual judgment:

- Add Vitest as a development dependency and `pnpm test:depth`.
- Pure tests cover depth-band separation, anchor formulas, tie stability,
  attachments, source-rectangle transforms for every flip/origin combination,
  overlap eligibility, and registration disposal.
- Add `src/game/content/maps/depth-occlusion-test.map.json` as a small authored
  fixture with repeated trees/houses, equal-Y actors, and front/behind paths.
- Add `pnpm smoke:depth-editor` using Playwright. It launches Vite against a
  dedicated checked-in test object and map, saves the fixture object's exact
  original bytes, edits/saves/resets/duplicates occlusion bounds, asserts
  diagnostics exposed in DOM text, and restores the exact bytes in `finally`.
  Each run starts from the same visual IDs, leaves `git diff` empty for the
  fixtures, and remains repeatable after failure.
- Add `pnpm smoke:depth-game` using Playwright. A development-only deterministic
  fixture scene moves the player and an engaged enemy through known anchor and
  occlusion positions, while a read-only diagnostics panel reports resolved
  depths, occluder IDs, candidate counts, and silhouette visibility for
  assertions.
- `pnpm check` includes pure tests and existing validators. Browser smoke
  commands remain explicit until CI is introduced.

Manual browser review still checks visual quality in at least one tree-heavy and
one house-heavy production map, but completion does not depend on manual review
for mathematical ordering or lifecycle correctness.

## Phased implementation tracker

### Phase 1 — Depth policy and diagnostics

- [x] Add named depth bands and one depth-resolution function.
- [x] Define stable tie and attachment biases.
- [x] Add development diagnostics showing anchor Y and resolved depth.
- [x] Document that visual offset and elevation do not alter sorting.
- [x] Add `pnpm test:depth` coverage for ordering, anchor formulas, equal-Y
      ties, attachments, and band separation.

### Phase 2 — Atomic world-sorting migration

- [x] Apply anchor-based depth in `ObjectFactory`.
- [x] Recalculate depth when `setObjectAnchor` moves an editor object.
- [x] Add sorted versus explicit/editor depth modes.
- [x] Migrate legacy `House` and bed depth to explicit ground anchors.
- [x] Migrate player anchor and `AnimatedVisual`.
- [x] Migrate all three worm enemies.
- [x] Migrate friends and attached ears.
- [x] Migrate enemy health bars and player/friend name labels.
- [x] Migrate pooled enemy and future player projectiles.
- [x] Migrate combat effects to spawn/impact-Y sorting and floating text to the
      reveal/world-effects band.
- [x] Verify knockback, death, respawn, and pooled reuse preserve correct depth.
- [x] Verify trees, houses, walls, rocks, and small props against all actors.
- [x] Remove replaced fixed world depth values.
- [x] Merge this phase atomically; do not leave mixed fixed/sorted gameplay.

### Phase 3 — Occlusion data contract

- [x] Add `occlusionBounds` to object TypeScript types and JSON schema.
- [x] Validate positive integer dimensions and non-negative offsets.
- [x] Validate bounds against spritesheet frame dimensions.
- [x] Resolve world occlusion rectangles from object anchors and visual data.
- [x] Reject occlusion bounds for procedural and animated object templates in
      the first implementation.
- [x] Ensure Save As copies current occlusion data without changing the source.
- [x] Extend `pnpm objects:check` coverage.
- [x] Add transform tests covering origin, scale, flip, visual offset, and
      animated source offset.

### Phase 4 — Map-editor authoring

- [x] Add the Occludes actors checkbox and numeric fields.
- [x] Preserve inspector scroll/focus while editing occlusion fields.
- [x] Render a distinct occlusion overlay in the template preview.
- [x] Persist/reset/update/duplicate occlusion data.
- [x] Keep occlusion UI absent or disabled for unsupported procedural frames
      until valid source dimensions are available.
- [x] Add `pnpm smoke:depth-editor` for enable, edit, validation, reset, save,
      duplicate, and cleanup.

### Phase 5 — Runtime silhouettes

- [x] Add a scene-owned occlusion controller with explicit cleanup.
- [x] Register authored static occluders.
- [x] Register player and active/engaged enemies as reveal actors.
- [x] Add the `256px` spatial grid, camera margins, diagnostics, and performance
      fixture.
- [x] Mirror animated frame transforms into reveal silhouettes.
- [x] Support overlapping occluders without silhouette flicker.
- [x] Verify actor activation, death, pooling, scene transitions, and cleanup.
- [x] Add `pnpm smoke:depth-game` deterministic depth/visibility assertions.

### Phase 6 — Content authoring and gameplay verification

- [x] Author occlusion bounds for tree templates.
- [x] Author occlusion bounds for house templates.
- [x] Author bounds for tall walls and selected large rocks.
- [x] Leave floors, collectibles, and small props without bounds.
- [x] Smoke-test behind/in-front movement in every production biome.
- [x] Check silhouettes at camera edges, during attacks, knockback, and death.
- [x] Run object, map, asset, visual, enemy, typecheck, and production build checks.

### Phase 7 — Split foreground artwork

- [x] Extend visual templates with optional base and overhead visual parts.
- [x] Keep the base in the Y-sorted band and canopy/roof in the overhead band.
- [x] Allow the editor to preview both parts with one stable ground anchor.
- [x] Evaluate fading roofs, clipped silhouettes, and polygon occlusion masks.

## Important files

- `src/game/features/objects/ObjectFactory.ts`
- `src/game/features/visuals/AnimatedVisual.ts`
- `src/game/features/player/PlayerFactory.ts`
- `src/game/enemies/Enemy.ts`
- `src/game/enemies/Projectile.ts`
- `src/game/Friend.ts`
- `src/game/House.ts`
- `src/game/content/objects/ObjectCatalog.ts`
- `src/game/content/objects/objects.schema.json`
- `src/game/editor/ObjectTemplateEditorState.ts`
- `src/game/editor/MapEditorInspector.ts`
- `src/game/editor/MapEditorScene.ts`
- `scripts/check-objects.mjs`
- `vite.config.ts`

## Completion criteria

- No production world entity relies on a category-wide fixed depth for normal
  top-down ordering.
- Crossing an object's ground anchor changes front/behind order correctly.
- Visual offsets and animation frame transforms never cause depth jitter.
- Player and active-enemy silhouettes appear only under valid occlusion.
- Occlusion bounds can be authored, reset, saved, and duplicated in the editor.
- No scene transition, respawn, pooling cycle, or editor reload leaks reveal
  sprites, listeners, or depth registrations.
- All local validation and browser gameplay/editor smoke tests pass.
