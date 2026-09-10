# Shared World Drop Spawner Implementation Plan

**Design:** `docs/superpowers/specs/2026-09-10-shared-world-drop-spawner-design.md`

**Status:** Implemented on 2026-09-10. Focused collectible tests,
TypeScript validation, and the production build pass. The complete project
check reaches an unrelated pre-existing NPC area assertion failure in
`scripts/tests/npcs/npc-inclusion.test.mjs`.

## Objective

Introduce one reusable physical-drop lifecycle for current resource piles and
future world-drop producers. Newly created drops use the approved staggered
arc and landing settle, remain uncollectible during motion, and activate at the
exact persisted destination. Restored drops appear settled immediately.

## Work sequence

### 1. Add deterministic motion primitives

Create `src/game/features/collectibles/WorldDropMotion.ts` with the approved
timing constants and a pure trajectory function. Use Euclidean distance,
`clamp(distance * 0.45, 28, 56)`, linear horizontal interpolation, and
parabolic vertical lift. Keep Phaser and scene state out of this module so the
trajectory and zero-distance behavior are directly testable.

### 2. Add the shared world-drop lifecycle

Create `src/game/features/collectibles/WorldDropSpawner.ts` with:

- the discriminated `launch`/`settled` request contract;
- narrow injected adapters for object creation, anchor/depth updates, and
  collectible registration;
- synchronous validation of anchors, zero-based launch indexes, visual IDs,
  and collectible archetypes before object creation;
- immediate body disable and withheld collectible registration for launches;
- a delayed 280 ms trajectory, 40 ms rebound, and 60 ms settle;
- exact final anchor, scale, depth mode, body enable, and one-time registration;
- immediate settled creation for restored drops;
- presentation-failure fallback and idempotent teardown of delayed/active
  launch tweens and unregistered images.

Use the object's landing depth while airborne, then restore ordinary
world-sorted depth after settling. Preserve authored nonuniform scale.

### 3. Route resource drops through the shared API

Replace `ResourceNodeController`'s direct object-creation and collectible-
registration dependencies with a `spawnWorldDrop` dependency.

For newly depleted resources:

1. choose deterministic pile cells and build pile records;
2. save the complete destroyed-source state;
3. submit launch requests in zero-based pile order using the resource anchor;
4. show the existing depletion feedback.

For restored pile records, submit settled requests so load never replays the
motion. Keep quantities, instance IDs, placements, and save schemas unchanged.

### 4. Compose and clean up in WorldScene

Construct one `WorldDropSpawner` after the object factory and collectible
controller are available. Adapt the existing `MapBuilder.createDynamicObject`,
`setObjectAnchor`, `setObjectDepthMode`, and
`CollectibleController.register` boundaries.

Inject the spawner into `ResourceNodeController`. During area reset, destroy
resource nodes first, then the world-drop spawner, then collectibles. This lets
pending depletion persist while preventing late launch callbacks.

### 5. Verify behavior and contracts

Extend `scripts/tests/collectibles/` to cover:

- trajectory start, apex, destination, clamping, and zero-distance hops;
- settled-mode immediate registration;
- launch-mode disabled pickup until all phases complete;
- stagger delay and exact scale/anchor restoration;
- validation before object creation, including non-collectible archetypes;
- tween setup fallback, duplicate completion protection, cleanup during delay,
  and rejection after disposal.

Run `pnpm test:collectibles`, `pnpm typecheck`, and `pnpm check`. Manually verify
tree and stone drops in the running game if browser startup is available.

## Expected file ownership

| Concern | Files |
|---|---|
| Pure drop trajectory | `src/game/features/collectibles/WorldDropMotion.ts` |
| Shared lifecycle/API | `src/game/features/collectibles/WorldDropSpawner.ts` |
| Resource producer integration | `src/game/features/resources/ResourceNodeController.ts` |
| Scene composition and teardown | `src/game/scenes/WorldScene.ts` |
| Focused automated coverage | `scripts/tests/collectibles/*.test.mjs` |

## Completion criteria

- Wood and stone piles visibly launch and settle at existing deterministic
  destinations.
- No pile can be collected before its own landing settle completes.
- Restored piles do not animate.
- Future physical-drop producers can use the same request contract without
  importing resource types.
- Persistence remains authoritative before presentation begins.
- Focused and full project verification pass without changing unrelated user
  edits.
