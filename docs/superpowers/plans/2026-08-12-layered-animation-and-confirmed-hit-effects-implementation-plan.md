# Layered Animation and Confirmed-Hit Effects Implementation Plan

**Approved design:** `docs/superpowers/specs/2026-08-12-layered-animation-and-confirmed-hit-effects-design.md`

**Goal:** Replace weapon-only single-sprite animation and automatic Impact playback with one reusable layered animation foundation, a shared layered Studio timeline, and reusable effects that spawn only after accepted damage at the target contact edge.

**Scope:** Weapon Studio and weapon runtime are the first complete consumers. Character, enemy, and projectile migration is intentionally deferred, but their future adapters must be able to use the shared contracts, clock, transform resolver, renderer, and editor without copying weapon code.

**Working-tree rule:** Before every task, inspect `git status --short` and the relevant diffs. The current edits to `player-slime/character.json` and `basic-sword/weapon.json` belong to the user. Never replace or revert them. The content-migration task must transform the current on-disk weapon values, including those edits.

## Verification commands introduced by this work

- `pnpm test:animation` — shared clock, layered resolution, transform, and compatibility tests.
- `pnpm test:weapon-studio` — existing and new Weapon Studio authoring/migration tests.
- `pnpm test:combat` — damage result, contact geometry, attack synchronization, and effect lifecycle tests.
- `pnpm effects:check` — effect package and Boot-bundle validation.
- `pnpm check` — final repository validation.

If `pnpm check` still encounters the pre-existing missing `enemy.projectile.generated-64` asset, record that as a baseline failure and do not weaken asset validation to hide it.

## Task 1: Add the shared layered document, resolver, and validator

**Files**

- Modify: `src/game/shared/animation/types.ts`
- Create: `src/game/shared/animation/layered.ts`
- Create: `src/game/shared/animation/layeredValidation.ts`
- Modify: `src/game/shared/animation/index.ts`
- Create: `scripts/tests/shared-animation/layered-document.test.mjs`
- Modify: `package.json`

**Implementation**

1. Add the approved domain-neutral contracts: `LayeredAnimationDocument`, `AnimationVisualLayerDocument`, `AnimationVisualBlockDocument`, `AnimationLayerTransformDocument`, `AnimationBlockTransformDocument`, and normalized equivalents.
2. Add pure helpers for integer timeline-frame count, active-block lookup, layer resolution, transparent gaps, layer ordering, and deterministic depth ordering.
3. Add a shared asset-lookup interface to validation instead of importing the game manifest into the shared module. Content validators will provide asset kind and frame count.
4. Validate FPS `1..240`, integral `durationSeconds * framesPerSecond` within `1e-6`, stable unique layer IDs, at least one layer/block for persisted variants, inclusive in-range block bounds, no overlap in a layer, valid source frames, finite transforms, positive scale, and spritesheet assets.
5. Keep draft-only empty-layer behavior outside persisted-document validation so runtime/content validation cannot accidentally accept it.
6. Export all new contracts and helpers from the shared animation index.
7. Add `test:animation` and the currently missing `test:weapon-studio` package scripts so every later verification command is runnable from a clean checkout.

**Tests first**

- A three-layer document resolves all layers against the same master frame.
- Leading, interior, and trailing gaps return no active block for that layer.
- Adjacent blocks are valid; overlapping blocks are rejected.
- Duplicate layer IDs, invalid frames, non-integral duration/FPS, and invalid scale are rejected.
- Layer order plus `depthOffset` has deterministic output.

**Verify**

```powershell
pnpm test:animation
pnpm typecheck
```

**Commit:** `feat: define shared layered animations`

## Task 2: Extract `AnimationClock` and retain single-layer compatibility

**Files**

- Create: `src/game/shared/animation/clock.ts`
- Modify: `src/game/shared/animation/player.ts`
- Modify: `src/game/shared/animation/types.ts`
- Modify: `src/game/shared/animation/index.ts`
- Create: `scripts/tests/shared-animation/animation-clock.test.mjs`
- Modify: `scripts/tests/weapon-studio/keyframe-targeting.test.mjs`

**Implementation**

1. Move step traversal, wrap, ping-pong, scrub, pause/resume, large-delta advancement, playback IDs, and completion into `AnimationClock`.
2. Give the clock ordered frame subscriptions with two explicit phases: visual subscribers first, track subscribers second. Dispatch authored events after track subscribers and completion last.
3. Return cleanup functions from subscriptions and make destruction idempotent.
4. Rebuild `AnimationPlayer` as a compatibility adapter over one clock. Preserve its public state and callbacks so Character Studio and current single-layer consumers do not change behavior.
5. Ensure non-looping completion emits the final visual and track frame before `onComplete`, and cancellation never emits completion.
6. Prevent a looped legacy attack from driving repeated combat later by exposing a one-shot normalized clock descriptor; weapon normalization will select it in Task 4.

**Tests first**

- Existing wrap, ping-pong, scrub, and large-delta behavior remains byte-for-byte equivalent at the state/callback boundary.
- Dispatch order is `visual -> track -> event -> completion` on the final frame.
- Restart increments playback ID; pause/resume does not.
- Destroy and cancel release subscribers and do not complete.

**Verify**

```powershell
pnpm test:animation
pnpm test:weapon-studio
pnpm typecheck
```

**Commit:** `refactor: extract shared animation clock`

## Task 3: Add shared transform composition and the reusable layered renderer

**Files**

- Create: `src/game/shared/animation/layeredTransform.ts`
- Create: `src/game/shared/animation/LayeredAnimationPlayer.ts`
- Modify: `src/game/shared/animation/index.ts`
- Create: `src/game/features/visuals/LayeredAnimationVisual.ts`
- Create: `src/game/features/visuals/LayeredAnimationHost.ts`
- Create: `scripts/tests/shared-animation/layered-transform.test.mjs`
- Create: `scripts/tests/shared-animation/layered-player.test.mjs`

**Implementation**

1. Implement the approved pure transform resolver once: layer plus block offset, component scale multiplication, host/layer/block XOR flips, mirrored local rotation, host rotation last, and layer-only origin.
2. Keep host position, base depth, rotation, and composition mirror behind `LayeredAnimationHost`; do not mention weapons in shared files.
3. Implement `LayeredAnimationPlayer` as the pure bridge from a layered document and clock frame to resolved visible-layer states.
4. Implement `LayeredAnimationVisual` as the Phaser renderer. Allocate at most one sprite per authored layer, reuse it, hide it during transparent gaps, and update texture/frame/transform/depth without per-frame object creation.
5. Runtime defensive handling may skip a malformed layer and emit a development diagnostic, but authoring validation remains all-or-nothing.
6. Make listener and scene-shutdown cleanup explicit and idempotent.

**Tests first**

- Exact transform equations for all four directions and mirrored Left.
- Layer and block flips use XOR, including double-flip cancellation.
- Layer sprites hide in gaps and reappear without recreation.
- Sibling layers continue when one runtime layer is invalid.
- Layer order and depth offset remain stable.

**Verify**

```powershell
pnpm test:animation
pnpm typecheck
```

**Commit:** `feat: render layered animations from one clock`

## Task 4: Add the v1/v2 weapon contract and lossless migration

**Files**

- Modify: `src/game/content/weapons/types.ts`
- Modify: `src/game/content/weapons/normalize.ts`
- Modify: `src/game/content/weapons/validation.ts`
- Modify: `src/game/content/weapons/weapon.schema.json`
- Create: `src/game/content/weapons/migrateLegacyWeapon.ts`
- Modify: `src/game/content/weapons/WeaponCatalog.ts`
- Modify: `scripts/check-weapons.mjs`
- Create: `scripts/tests/weapon-studio/weapon-v2-migration.test.mjs`

**Implementation**

1. Split authored input into `LegacyWeaponDefinition` version 1 and `LayeredWeaponDefinition` version 2, with a normalized runtime definition independent of either storage shape.
2. Require v2 Idle plus Right/Up/Down directional attack packages; allow Left to mirror Right. Keep each directional package's animation, character action, hitboxes, and attack track together.
3. Add optional `onHitEffectId` and `presentation.facingMode`. Forbid v2 root `assetId`, `visual`, root attack/impact clips, root hitboxes, and root attack track.
4. Implement pure legacy-clip migration to a `base` layer. Preserve expanded source-frame output, duration, Idle loop mode, per-occurrence transforms, `visual.origin`, `visual.scale`, `visual.sourceOffset`, selected animation offsets, and frame offsets.
5. Coerce migrated attacks to `loop: false` while preserving one traversal. Keep v1 loading read-only; only explicit Studio save emits v2.
6. Strip `weapon.impact` events only from the migrated v2 output, not from the in-memory legacy source before the user confirms saving.
7. Update schema, runtime validation, and CLI validation to accept v1/v2 inputs but validate new saves against the strict v2 shape.

**Tests first**

- Legacy expanded frames and transforms equal migrated base-layer output at every master frame.
- Horizontal mirror and directional animation offsets retain preview parity.
- Migrated attack loops become one-shot; Idle loop behavior remains unchanged.
- V2 rejects root legacy visual/combat animation fields and missing required directions.
- Loading a v1 document does not modify its source object or disk.

**Verify**

```powershell
pnpm test:animation
pnpm test:weapon-studio
pnpm weapons:check
pnpm typecheck
```

**Commit:** `feat: normalize layered weapon packages`

## Task 5: Evolve the shared timeline into a layered authoring component

**Files**

- Create: `src/game/editor/LayeredAnimationDocumentState.ts`
- Create: `src/game/editor/LayeredAnimationTimelineView.ts`
- Create: `src/game/editor/LayeredAnimationTimelinePanel.ts`
- Create: `src/game/editor/LayeredAnimationTimelineInteraction.ts`
- Modify: `src/game/editor/AnimationTimelineResize.ts`
- Modify: `src/game/editor/AnimationTimelinePanel.ts`
- Modify: `src/styles.css`
- Create: `scripts/tests/weapon-studio/layered-timeline.test.mjs`

**Implementation**

1. Put all mutations in `LayeredAnimationDocumentState`: add/rename/reorder/delete layers, select a layer/block, insert tiles, move blocks, resize the clicked block, delete while preserving gaps, edit transforms, change FPS, and guarded duration changes.
2. Render one seconds ruler/playhead and ordered visual lanes. Accept optional host-provided rows beneath the lanes so weapons can supply hitbox and event tracks without entering the shared component.
3. Scope the asset shelf and Add Tiles picker to the selected layer asset. Insert selected source frames consecutively at the playhead; reject overlap and overflow without shifting existing blocks.
4. Keep plus/minus and right-edge drag controls keyed by both `layerId` and block identity. Reuse pointer capture and commit-on-release semantics from the current resize interaction.
5. Preserve frame indices on FPS change and recompute seconds. Snap Duration to a whole frame and reject a reduction that would clip visual blocks or host-supplied track extents.
6. Keep preview mute/solo state outside the persisted document.
7. Leave the existing single-layer Character Studio wrapper operational; it may continue using the compatibility panel until its later adapter migration.

**Tests first**

- Every control targets its clicked lane/block even when another block is selected.
- Add Tiles targets the selected layer and rejects overlap/overflow atomically.
- Body drag snaps to frames; right-edge resize changes only `through`.
- Delete creates a transparent gap.
- Reorder/depth/preview visibility are deterministic; preview flags are not serialized.
- Duration guards include host hitbox spans and events.

**Verify**

```powershell
pnpm test:weapon-studio
pnpm test:character-studio
pnpm typecheck
```

**Commit:** `feat: add shared layered timeline editor`

## Task 6: Add reusable effect packages, catalog, and validation

**Files**

- Create: `src/game/content/effects/types.ts`
- Create: `src/game/content/effects/normalize.ts`
- Create: `src/game/content/effects/validation.ts`
- Create: `src/game/content/effects/EffectCatalog.ts`
- Create: `src/game/content/effects/effect.schema.json`
- Create: `src/game/content/effects/virtual-effect-content.ts`
- Modify: `src/game/content/characters/characterContentModulesPlugin.ts`
- Modify: `src/vite-env.d.ts`
- Modify: `tsconfig.json`
- Create: `scripts/check-effects.mjs`
- Modify: `package.json`
- Create: `scripts/tests/weapon-studio/effect-content.test.mjs`

**Implementation**

1. Add effect package v1, cardinal direction types, exact/Left-mirror/Default resolver, and normalized non-looping variants.
2. Validate that every saved package resolves all four directions to at least one valid layer/block and that all referenced assets are Boot-bundle spritesheets with valid frame indices.
3. Extend the existing Vite content plugin with an effect root, `virtual-effect-content`, catalog revision, package revisions, and GET/create/update endpoints using the same optimistic-concurrency response shape as weapons.
4. Extend asset registration used by effect imports to add the registered spritesheet to `bundles.boot` exactly once. Keep media metadata in `asset/assets.json`; never place effect behavior there.
5. Add `effects:check` before `weapons:check` in `pnpm check`, and make weapon validation reject an unknown `onHitEffectId` once both catalogs are available.
6. Deduplicate missing/invalid effect diagnostics by effect ID and keep them development-only.

**Tests first**

- Exact direction wins, mirrored Left is second, Default is final fallback.
- All four directions must resolve; empty variants do not count.
- Effects reject loops, missing/non-spritesheet assets, out-of-range frames, and non-Boot assets.
- Catalog and package revisions change only when canonical content changes.
- Duplicate Boot insertion is idempotent.

**Verify**

```powershell
pnpm test:weapon-studio
pnpm effects:check
pnpm weapons:check
pnpm typecheck
```

**Commit:** `feat: add reusable confirmed-hit effects`

## Task 7: Move Weapon Studio to layered Idle/Attack editing and an On Hit surface

**Files**

- Modify: `src/game/editor/WeaponStudio.ts`
- Create: `src/game/editor/WeaponStudioDocumentState.ts`
- Create: `src/game/editor/WeaponStudioOnHitPanel.ts`
- Create: `src/game/editor/WeaponStudioMigration.ts`
- Modify: `src/game/editor/WeaponHitboxPreview.ts`
- Modify: `src/game/content/characters/characterContentModulesPlugin.ts`
- Create: `src/game/content/weapons/weaponEffectTransaction.ts`
- Modify: `src/styles.css`
- Create: `scripts/tests/weapon-studio/weapon-layered-authoring.test.mjs`
- Create: `scripts/tests/weapon-studio/weapon-effect-transaction.test.mjs`

**Implementation**

1. Replace the current `idle | attack | impact` selection with layered Idle and directional Attack editing plus a separate On Hit surface.
2. Use `LayeredAnimationTimelinePanel` for all weapon visual lanes and pass the selected direction's hitbox/event rows as host tracks under the same ruler.
3. Preview every active layer and current hitbox from one playhead. Keep current scroll/focus preservation and ensure every button uses `type="button"` so clicks do not jump the page.
4. Add effect selection/clear/create/edit for Default/Right/Left/Up/Down, Left mirroring, and a clear shared-content warning. Maintain independent weapon dirty/revision/saving state and effect dirty/revision/saving state.
5. Add explicit v1 migration UI. Loading only creates a draft; saving writes v2. If a legacy Impact is a usable effect, offer a proposed stable effect ID without silently creating it.
6. Implement the dual-document migration endpoint in `weaponEffectTransaction.ts`: validate both expected revisions, write both temporary files, rename effect first then weapon, compensate effect on weapon failure, remove a newly created empty effect directory, clean all temporary files in `finally`, and return `manual-recovery-required` with exact paths if compensation fails.
7. Keep ordinary independent weapon/effect create/update endpoints for non-migration edits.
8. Split pure state/transaction logic out of the large mount file; do not refactor unrelated Character Studio code.

**Tests first**

- Impact tab and `weapon.impact` help text no longer render.
- Each visual lane can choose a different asset and uses the same seconds ruler as hitboxes/events.
- Preview selection, add/resize/drag, direction switching, and hitbox selection remain synchronized.
- Weapon and effect save buttons operate independently.
- Migration is explicit and creates no disk writes on load.
- Transaction tests cover create, update, revision conflict, second rename failure, successful compensation, temporary cleanup, and compensation failure response.

**Verify**

```powershell
pnpm test:weapon-studio
pnpm test:character-studio
pnpm typecheck
pnpm build
```

**Manual check**

1. Open Weapon Studio and migrate a copied fixture, not the user's current Basic Sword file.
2. Author sword/trail/glow lanes with distinct assets and gaps.
3. Scrub and play; confirm layers, hitbox activation, events, seconds ruler, and preview stay in phase.
4. Confirm page scroll does not jump while using timeline controls.

**Commit:** `feat: author layered weapons and on-hit effects`

## Task 8: Introduce accepted-damage results and contact-point resolution

**Files**

- Create: `src/game/combat/DamageableTarget.ts`
- Create: `src/game/combat/ContactPoint.ts`
- Modify: `src/game/enemies/Enemy.ts`
- Modify: `src/game/combat/TargetDummy.ts`
- Modify: `src/game/features/combat/CombatController.ts`
- Create: `scripts/tests/combat/damage-application.test.mjs`
- Create: `scripts/tests/combat/contact-point.test.mjs`
- Modify: `package.json`

**Implementation**

1. Add `DamageApplicationRequest`, `DamageApplicationResult`, and a structural `DamageableTarget` adapter contract; do not introduce an inheritance base class.
2. Update Enemy and Target Dummy to return accepted/rejected results. Cap `actualDamage` to HP removed, report fatal overkill correctly, and represent dead/invulnerable/invalid rejections without exceptions.
3. Existing callers such as Ability System may ignore the return value, but weapon combat must consume it.
4. Add pure dominant-axis quantization and cardinal vectors. Weapon attacks always supply their immutable cardinal snapshot.
5. Capture valid physics bounds first, then visual bounds, before damage. Resolve the contact point at the target's near edge opposite the incoming vector; use the captured center on invalid bounds.
6. Keep overlap suppression in `HitboxPool`; a rejected result remains consumed for the current activation.

**Tests first**

- Normal damage, overkill, dead, invulnerable, invalid, and zero-damage results.
- Right/Left/Up/Down edge positions for varied target bounds.
- Invalid bounds center fallback and dominant-axis fallback for future non-weapon adapters.
- Bounds are captured before a fatal hit disables the body.

**Verify**

```powershell
pnpm test:combat
pnpm typecheck
```

**Commit:** `refactor: report confirmed damage applications`

## Task 9: Drive weapon visuals and combat tracks from one clock

**Files**

- Modify: `src/game/combat/WeaponAttackTrackRunner.ts`
- Modify: `src/game/combat/Weapon.ts`
- Modify: `src/game/features/combat/WeaponVisual.ts`
- Create: `src/game/features/combat/WeaponAnimationAdapter.ts`
- Modify: `src/game/features/combat/CombatController.ts`
- Create: `scripts/tests/combat/weapon-animation-sync.test.mjs`

**Implementation**

1. Make `WeaponAttackTrackRunner` a track-phase consumer of an external `AnimationClock`; remove its private timer/player.
2. Have the weapon runtime own one active clock. `WeaponAnimationAdapter` selects Idle or a directional Attack layered document, configures host direction/mirroring, and connects the clock to `WeaponVisual` plus the attack track.
3. Replace `WeaponVisual`'s single sprite/player with `LayeredAnimationVisual`. Its per-game-frame update may refresh anchor position/depth only; it must not advance another timer.
4. Start the visual selection before `clock.start` so frame zero renders before frame-zero hitboxes/events. On attack completion, close hitboxes, unlock the character, and switch the same clock back to Idle.
5. Change the weapon hit callback to pass immutable weapon ID, authored hitbox ID, attack direction/vector, and playback ID with the damage request.
6. Remove special handling that plays legacy Impact for `weapon.impact`. Generic authored events may still be forwarded to domain callbacks.
7. Keep `CombatController.update` order: advance weapon clock, refresh visual anchor if needed, update `hitboxPool`, then projectiles.

**Tests first**

- Three visual layers and hitbox spans observe identical frame sequences.
- Frame-zero and final-frame order matches the approved dispatch sequence.
- Right/Up/Down and mirrored Left apply the shared transform resolver.
- Looping legacy attacks execute once after normalization.
- Cancel/equip/destroy removes hitboxes and listeners without completing twice.
- No runtime path starts an Impact clip or a second attack timer.

**Verify**

```powershell
pnpm test:animation
pnpm test:combat
pnpm typecheck
```

**Commit:** `refactor: synchronize weapon animation and combat tracks`

## Task 10: Spawn pooled world effects only for confirmed hits

**Files**

- Create: `src/game/features/effects/WorldEffectAdapter.ts`
- Create: `src/game/features/effects/WorldEffectPool.ts`
- Modify: `src/game/features/combat/CombatController.ts`
- Modify: `src/game/combat/Weapon.ts`
- Modify: `src/game/scenes/WorldScene.ts`
- Create: `scripts/tests/combat/confirmed-hit-effects.test.mjs`
- Create: `scripts/tests/combat/world-effect-pool.test.mjs`

**Implementation**

1. Add a scene-owned pool whose instances contain a world-point host adapter, one clock, and one reusable layered visual.
2. In CombatController's weapon hit path, capture target bounds, apply combo-scaled damage, keep life-steal based on `actualDamage`, and spawn only when `status === 'accepted' && actualDamage > 0` and the weapon has `onHitEffectId`.
3. Resolve the effect using the weapon snapshot direction, then spawn one instance at the captured near-edge point for each successfully damaged target.
4. Missing or invalid effect content emits one development diagnostic and never affects damage or attack completion.
5. Return instances to the pool on animation completion or a duration-derived safety timeout. Release all instances/listeners at scene shutdown.
6. Make the pool scene-owned so attack cancellation, weapon replacement, or player destruction does not kill an already confirmed effect.
7. Do not show hitbox debug geometry in normal gameplay; development hitbox overlays remain controlled by existing development tools only.

**Tests first**

- Miss, rejected, dead, invulnerable, and zero-damage outcomes spawn nothing.
- One accepted hit spawns once at the correct contact edge and direction.
- One swing hitting multiple targets spawns independently for each target.
- Intentional later activation can hit again, while overlap ticks in one activation cannot.
- Exact, mirrored Left, and Default resolution all render.
- Completion, timeout, cancellation, equip, and scene shutdown lifecycle rules hold.

**Verify**

```powershell
pnpm test:combat
pnpm effects:check
pnpm typecheck
```

**Commit:** `feat: play effects on confirmed weapon hits`

## Task 11: Migrate repository weapon content and retire legacy Impact data

**Files**

- Create: `scripts/migrate-weapon-content.mjs`
- Modify: `src/game/content/weapons/goo-gauntlet/weapon.json`
- Modify: `src/game/content/weapons/basic-sword/weapon.json`
- Modify: `src/game/content/weapons/slam-hammer/weapon.json`
- Create as eligible: `src/game/content/effects/basic-sword-impact/effect.json`
- Modify: `src/game/content/weapons/virtual-weapon-content.ts`
- Modify: `src/game/content/effects/virtual-effect-content.ts`
- Modify if an imported effect asset is added: `asset/assets.json`

**Implementation**

1. Implement the migration command as a thin caller of the tested TypeScript migration rules; support a read-only preview/check mode and an explicit write mode.
2. Run preview against the current working tree and inspect every proposed diff before writing. Preserve the user's Basic Sword animation/hitbox edits and never regenerate `player-slime/character.json`.
3. Migrate all current weapon Idle and directional Attack clips to v2 base layers, preserve direction packages, remove migrated root visual/hitbox/track fields, and remove obsolete Impact clips/events.
4. Convert Basic Sword's intentionally authored usable Impact artwork into `basic-sword-impact` and assign `onHitEffectId`. Do not auto-create effect packages for other legacy Impact clips unless the eligibility rules identify actual effect artwork; leave them unassigned with a migration diagnostic otherwise.
5. Regenerate/update virtual content fallbacks so production and tests see the same packages as the development plugin.
6. Verify no saved v2 weapon contains `weapon.impact`, root Impact, or other forbidden legacy animation fields.

**Verify**

```powershell
node scripts/migrate-weapon-content.mjs --check
pnpm effects:check
pnpm weapons:check
pnpm assets:check
pnpm test:weapon-studio
pnpm test:combat
```

**Manual check**

1. Attack air in all four directions: no contact effect appears.
2. Hit one enemy in every direction: the directional/fallback effect appears at the enemy-facing contact edge.
3. Hit two enemies with one swing: each receives one effect.
4. Confirm no old cone/Impact replacement appears and development hitboxes show only when the debug tool enables them.

**Commit:** `content: migrate weapons to layered animations`

## Task 12: Final parity, lifecycle, and repository verification

**Files**

- Modify as failures require: files touched by Tasks 1–11 only
- Modify: `docs/ARCHITECTURE.md`
- Modify: `AGENTS.md` only if the new verification commands should become permanent contributor guidance

**Implementation**

1. Document the shared animation ownership rule: domain adapters select content/anchors, but may not own frame timing or copy the renderer/editor.
2. Document effect content ownership, confirmed-damage spawning, and the prohibition on timeline-driven weapon Impact playback.
3. Search for stale runtime/Studio references to `WeaponPlaybackAnimationId` Impact, `weapon.impact`, Impact tabs, root v2 `assetId`/`visual`, and duplicate animation timers. Keep legacy strings only inside migration/compatibility tests and v1 readers.
4. Run focused suites, then the full repository check. Fix only regressions caused by this work; report unrelated baseline failures separately.
5. Manually verify Weapon Studio scroll stability, layered preview parity, effect save separation, gameplay misses/hits/multi-target hits, effect cleanup, and production-hidden diagnostics.

**Verify**

```powershell
pnpm test:animation
pnpm test:weapon-studio
pnpm test:character-studio
pnpm test:combat
pnpm effects:check
pnpm weapons:check
pnpm check
git diff --check
git status --short
```

**Commit:** `docs: document shared layered animation runtime`

## Completion gate

Implementation is complete only when:

- Weapon Studio authors multiple asset-backed visual lanes on one seconds ruler.
- Weapon visuals, hitboxes, events, and completion consume one clock in the required order.
- A miss or rejected damage never spawns an On Hit effect.
- Every accepted multi-target damage result can spawn its own directional/fallback world effect at the captured contact edge.
- Effects survive attack cancellation and return to their scene pool on completion/timeout/shutdown.
- Newly saved weapon content is v2 and contains no automatic Impact animation/event path.
- Character Studio remains functional through the single-layer compatibility adapter.
- The full checks pass, apart from any clearly recorded pre-existing asset failure that was reproduced before implementation.
