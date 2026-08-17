# Center-Following Confirmed-Hit Effects Implementation Plan

**Approved design:**
`docs/superpowers/specs/2026-08-17-center-following-hit-effects-design.md`

**Goal:** Spawn confirmed weapon-hit effects at the damaged target's `x`/`y`
anchor and follow only that position until the target is destroyed or the effect
finishes. Preserve spawn-time depth, direction, mirroring, animation transforms,
and lifetime.

**Scope:** The world-effect adapter and pool, confirmed-hit dispatch in
`CombatController`, focused lifecycle tests, architecture wording, and gameplay
verification. Collision detection, damage rules, effect content, schemas,
catalogs, and Weapon Studio behavior are excluded.

## Working-Tree Rule

Before every task, inspect `git status --short` and the relevant diffs. The
working tree already contains an uncommitted collision-body implementation:

- `src/game/combat/Hitbox.ts`
- `src/game/dev/WorldDebugRenderer.ts`
- `src/game/features/combat/CombatController.ts`
- `src/game/combat/CombatBodyGeometry.ts`
- `scripts/tests/combat/combat-body-geometry.test.mjs`

The following weapon/effect content edits are also present and outside this plan:

- `src/game/content/effects/basic-spear-impact/effect.json`
- `src/game/content/weapons/basic-spear/weapon.json`
- `src/game/content/weapons/slam-hammer/weapon.json`
- `src/game/content/effects/slam-hammer-impact/`

Preserve all of them. In particular, build the `CombatController` edit on top of
the collision-body work instead of restoring the committed version. Do not stage
or commit any protected content file. Because `CombatController.ts` overlaps the
collision work, create a feature commit only after the collision implementation
has been committed separately or after reviewing and staging exact hunks. If
that boundary is not safe, leave the runtime changes uncommitted and report it.

## Verification Commands

- `pnpm test:combat`
- `pnpm effects:check`
- `pnpm typecheck`
- `pnpm build`
- `pnpm check`
- `git diff --check`

`pnpm check` currently may stop at the known missing
`characters/authored/projectiles-64x64.png` asset. Reproduce and report that as a
baseline issue if it remains; do not weaken asset validation or create a fake
asset as part of this feature.

## Task 1: Add a Position-Only Effect Adapter Update

**Files**

- Modify: `src/game/features/effects/WorldEffectAdapter.ts`
- Create: `scripts/tests/combat/world-effect-adapter.test.mjs`

**Tests first**

1. Construct an adapter with known position, depth, and mirror values.
2. Call the new position-only method with a different `x` and `y`.
3. Assert `getAnimationHostTransform()` exposes the new coordinates while
   preserving base depth, zero rotation, `mirrorX`, and `mirrorY` exactly.
4. Reset the same adapter for pooled reuse and prove the new spawn-time depth and
   mirrors replace the previous instance's values.

**Implementation**

1. Add `setPosition(x: number, y: number): void` to `WorldEffectAdapter`.
2. Change only the private `x` and `y` fields in that method.
3. Keep `reset` as the complete spawn/reuse operation for position, depth, and
   both mirror axes.
4. Do not add target knowledge or event listeners to the adapter; it remains a
   domain-neutral `LayeredAnimationHost`.

**Verify**

```powershell
pnpm test:combat
pnpm typecheck
```

**Suggested commit:** `feat: update pooled effect positions`

## Task 2: Add an Explicit Target-Position Attachment Lifecycle

**Files**

- Create: `src/game/features/effects/WorldEffectPositionAttachment.ts`
- Modify: `src/game/features/effects/WorldEffectPool.ts`
- Create: `scripts/tests/combat/world-effect-position-attachment.test.mjs`

**Tests first**

Use a small fake event-emitting target and a real `WorldEffectAdapter` to cover:

1. Attaching immediately copies the target's finite `x` and `y`.
2. `update()` follows movement even when `target.active === false`.
3. Changing target depth, scale, rotation, active state, or visibility never
   changes the adapter's non-position transform.
4. A non-finite coordinate retains the adapter's last valid value for that axis
   while the other finite axis can still update.
5. A target `destroy` event performs one final finite position sync, removes the
   listener/reference, and leaves the adapter frozen there.
6. Explicit disposal removes the exact listener and is safe to call repeatedly.
7. Disposing an old attachment before reuse prevents later movement or destroy
   events from changing the reused adapter.
8. Two attachments backed by two targets update independently.

**Implementation**

1. Define and export the narrow structural `WorldEffectPositionTarget` contract:
   a Phaser game object with readable `x`/`y` and the normal `once`/`off`
   destruction-event lifecycle. Do not import `Enemy` or `TargetDummy`.
2. Encapsulate one target, one adapter, and the exact destroy callback in a small
   idempotent attachment object. The pool slot owns at most one such object.
3. Synchronize each finite axis independently so invalid target data cannot
   poison a previously valid render transform.
4. On target destruction, synchronize once, detach without canceling the effect,
   and make all later updates no-ops.
5. Extend `WorldEffectSpawnRequest` with optional
   `followPositionOf?: WorldEffectPositionTarget`; retain `x`/`y` for static
   callers and as the initial fallback.
6. Extend `EffectSlot` with its optional attachment. Before reusing a slot, clear
   its old timeout and dispose its old attachment before resetting the adapter.
7. When a follow target is supplied, create the attachment after adapter reset
   and before the animation starts.
8. In `WorldEffectPool.update`, update the attachment before advancing the clock
   and calling `visual.updateAnchor()`. This ensures the current frame uses the
   latest target coordinates.
9. Centralize slot attachment cleanup and call it from animation completion,
   safety-timeout release, reuse, explicit pool destruction, and scene shutdown.
10. Preserve fixed world-space behavior when `followPositionOf` is omitted.

**Implementation guardrails**

- Do not detach merely because `active`, `visible`, or the Arcade body is false.
- Do not copy target depth or any visual transform other than `x`/`y`.
- Do not parent effect sprites to the target.
- Do not let a target-destroy callback release or cancel the effect.
- Do not expose mutable pool-slot state solely for tests; test the attachment
  seam directly and verify pool wiring through public behavior/manual smoke.

**Verify**

```powershell
pnpm test:combat
pnpm effects:check
pnpm typecheck
```

**Suggested commit:** `feat: follow hit effect target positions`

## Task 3: Dispatch Confirmed Effects from the Target Center

**Files**

- Modify: `src/game/features/combat/CombatController.ts`
- Modify: `scripts/tests/combat/combat-body-geometry.test.mjs`
- Modify only if needed for placement assertions:
  `scripts/tests/combat/confirmed-hit-effects.test.mjs`

**Tests first**

1. Keep the existing confirmation-gate assertions: missing effect ID, rejected
   damage, and zero actual damage spawn nothing.
2. Remove or rewrite the collision test named around a fatal body snapshot
   producing a confirmed-hit effect. Body geometry no longer places effects.
   Retain collision-focused assertions that disabled bodies do not participate in
   later activations.
3. Rely on the attachment tests for initial center placement, motion, inactive
   targets, destruction freeze, independent targets, and stale-listener reuse.
4. Do not delete `ContactPoint.ts` or its focused tests; they remain a generic
   utility unless a separate cleanup proves them fully unused and is approved.

**Implementation**

1. In the weapon hit callback, continue applying combo-scaled damage and
   life-steal exactly as today.
2. Keep the existing `shouldSpawnConfirmedHitEffect` gate unchanged.
3. For every accepted positive-damage `Enemy` or `TargetDummy`, call
   `WorldEffectPool.spawn` with:

   - `x: hitTarget.x`;
   - `y: hitTarget.y`;
   - `depth: hitTarget.depth + 0.2` captured at spawn;
   - the attack snapshot's existing cardinal direction; and
   - `followPositionOf: hitTarget`.

4. Remove the contact-edge calculation and imports used only for effect
   placement.
5. Remove `attackVector` from the callback destructuring if it becomes unused;
   strict TypeScript rejects unused bindings.
6. Remove the pre-damage body snapshot from this callback when it is no longer
   used. Do not change `Hitbox` collision-body resolution or debug overlay logic.
7. Confirm fatal enemies remain attachable through their death animation even
   after the Arcade body is disabled, and that target dummies remain followable
   while inactive. Actual object destruction is the only detach event.

**Verify**

```powershell
pnpm test:combat
pnpm typecheck
```

**Suggested commit:** `feat: center confirmed hit effects on targets`

## Task 4: Update the Runtime Contract and Run Full Verification

**Files**

- Modify: `docs/ARCHITECTURE.md`
- Do not modify the approved historical specs; the 2026-08-17 design explicitly
  supersedes their fixed-edge/non-following statements.

**Documentation**

1. Replace the architecture statement that positions the effect at the target
   contact edge.
2. State that accepted positive damage spawns at the damaged object's `x`/`y`
   center and follows only position until effect completion or target
   destruction.
3. Preserve the rule that timeline events cannot synthesize hit effects or
   bypass damage confirmation.
4. Keep content/editor/schema ownership unchanged. The Weapon Studio help-copy
   reference to contact-edge presentation is outside the approved runtime/editor
   scope; report it as a copy-only follow-up rather than silently broadening this
   implementation.

**Automated verification**

```powershell
pnpm test:combat
pnpm effects:check
pnpm typecheck
pnpm build
pnpm check
git diff --check
git status --short
```

If `pnpm check` stops at the previously missing projectile asset, record the
exact failure and show that the focused combat suite, effect validation,
typecheck, and build pass independently.

**Gameplay smoke check**

1. Start the development build and use a weapon with a visible on-hit effect.
2. Miss an enemy and confirm no effect appears.
3. Hit the outer red collision area without touching the small visual-anchor
   square; confirm damage still occurs and the effect appears at target center.
4. Hit from all four cardinal directions; confirm the effect direction/mirroring
   remains correct while placement stays centered.
5. Knock an enemy back during a longer effect and confirm only the effect's
   position follows. Watch for depth changes, animation restarts, or transform
   jumps.
6. Land a fatal hit; confirm the effect follows during the existing death object
   lifetime and freezes cleanly if the target is destroyed before it completes.
7. Hit a target dummy through its inactive/death state and confirm position
   following continues until the object actually disappears or the effect ends.
8. Hit multiple enemies in one attack and confirm each effect follows only its
   own target.
9. Let effects complete, trigger pool reuse, and verify an old target cannot move
   a new effect.
10. Exit or reload the scene and confirm no effect or target listener survives
    shutdown.

**Suggested commit:** `docs: document center-following hit effects`

## Completion Gate

Implementation is complete only when:

- A confirmed positive-damage weapon hit spawns exactly at `target.x`/`target.y`.
- The effect follows only `x`/`y` while the target exists, including knockback
  and inactive-but-not-destroyed states.
- Depth, direction, mirrors, rotation, scale, authored offsets, animation
  progress, and lifetime remain fixed from spawn.
- Target destruction freezes the effect at the final valid center without
  canceling it.
- Completion, timeout, reuse, pool destruction, and scene shutdown remove all
  attachment references/listeners.
- Static pool callers that omit a target still work.
- Collision-body combat remains authoritative, and decorative/ground objects
  without collision bodies remain non-collidable.
- Focused tests, strict TypeScript, and production build pass; any unrelated
  repository-wide asset failure is reproduced and reported separately.
- Protected working-tree content edits are neither staged, reverted, nor
  overwritten.
