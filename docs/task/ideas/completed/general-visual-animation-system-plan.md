# General visual animation system implementation plan

Status: completed and verified.

## Phase 1: Content model and validation

1. Add `src/game/content/visuals/visual-set.schema.json`.
2. Define the serializable visual-set TypeScript types in `VisualCatalog.ts`.
3. Add player, blob enemy, and tree visual-set JSON files.
4. Resolve each visual set through a stable asset manifest ID.
5. Validate visual-set IDs, asset compatibility, source-frame ranges, transforms, clip timing, and runtime-key uniqueness.
6. Add procedural enemy texture entries to the asset manifest so editor-facing content never depends on anonymous Phaser texture keys.
7. Add a `visuals:check` script and include it in `pnpm check`.

## Phase 2: Generic animation registration

1. Add an infrastructure helper that registers every clip in a visual set with Phaser.
2. Derive Phaser texture keys from manifest asset IDs.
3. Keep registration idempotent with `scene.anims.exists(runtimeKey)`.
4. Preserve current player runtime keys to avoid changing combat and ability callers in the first migration.
5. Provide lookups by `visualSetId`, clip ID, runtime key, and source-frame transform.

## Phase 3: Stable anchor and rendered visual

1. Add an `AnimatedVisual` class owned by a physics/entity anchor.
2. Create a non-physics Phaser sprite for rendering.
3. Follow the anchor position every update.
4. Apply default origin, source offset, and scale.
5. Listen for animation-frame changes and merge the matching frame override.
6. Apply flipping, tint, alpha, depth, and temporary scale multipliers to the render sprite.
7. Destroy listeners and the render sprite explicitly.
8. Confirm frame transforms never resize or relocate the physics body.

## Phase 4: Player migration

1. Move `SLIME_ANIMS` into `player-slime/visual-set.json`.
2. Remove the hardcoded `slime` texture from `WorldScene.makeAnimation()`.
3. Register the player visual set before player creation.
4. Update `PlayerEntity` to expose the stable physics sprite and its `AnimatedVisual`.
5. Route `PlayerController` animation and horizontal flip through `AnimatedVisual`.
6. Route one-shot animation handling in `WorldScene` through the visual.
7. Replace direct player visual scale manipulation in `AbilitySystem` with a temporary visual scale multiplier.
8. Keep player collision dimensions, position, velocity, and world-bound behavior on the physics anchor.
9. Remove `src/game/slimeAnimations.ts` after all imports are migrated.

## Phase 5: Enemy proof

1. Add a stable manifest entry for the procedural blob texture.
2. Add `enemy-blob/visual-set.json` with a one-frame looping idle clip.
3. Extend `EnemyConfig` with an optional `visualSetId` and default clip.
4. Give `Enemy` an `AnimatedVisual` when configured.
5. Route enemy tint, hit flash, telegraph color, alpha, and death scaling to the rendered visual.
6. Keep AI, velocity, contact distance, and collision on the enemy physics anchor.
7. Ensure enemies without visual sets continue using the existing sprite-rendering path during migration.

## Phase 6: Tree proof

1. Add an optional visual-set/clip reference to the relevant object visual definition.
2. Extend the object schema and catalog validation.
3. Update `ObjectFactory` to create a stable static physics anchor plus `AnimatedVisual` only for opted-in objects.
4. Add a one-frame looping tree clip referencing the authored tree's selected source frame.
5. Preserve authored origin, visual offset, collider offset, and stable map anchor.
6. Keep all non-animated objects on the existing image path.
7. Ensure editor selection and object movement continue to use the stable object anchor.

## Phase 7: Documentation and editor hook

1. Update the character-sprite knowledge guide with the visual-set pipeline.
2. Document source-offset units, mirroring, and transform precedence.
3. Document how maps and object archetypes reference visual sets.
4. Add the visual-set editor panel with frame preview and JSON persistence.

## Phase 8: Verification

1. Run `pnpm assets:check`.
2. Run `pnpm visuals:check`.
3. Run `pnpm objects:check`.
4. Run `pnpm maps:check`.
5. Run `pnpm typecheck`.
6. Run `pnpm build`.
7. Smoke-test scene startup, player movement, idle/walk/ability animations, blob spawning/hit/death effects, tree rendering/collision, area transitions, and scene cleanup.
8. Enable Arcade physics debug temporarily to verify that frame offsets and scales do not move collision bodies.
