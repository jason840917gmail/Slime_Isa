# DOWN-to-UP Directional Mirroring Implementation Plan

**Approved design:** `docs/superpowers/specs/2026-08-13-down-up-directional-mirroring-design.md`

**Goal:** Add DOWN-master/UP-mirror-or-custom behavior to weapon attacks and
confirmed-hit effects, using one shared directional resolver and one shared
layered transform path while preserving RIGHT-master/LEFT mirroring.

**Scope:** Shared directional resolution, layered `mirrorY` composition, weapon
and effect contracts, runtime adapters, Weapon Studio behavior, content defaults,
and regression coverage. Character/enemy animation libraries and diagonal
directions are excluded.

**Working-tree rule:** Before every task, inspect `git status --short` and relevant
diffs. The current edits to `src/game/content/weapons/basic-sword/weapon.json` and
`src/game/editor/character-studio.css` belong to the user. Preserve them and do
not stage, replace, or revert them as part of this plan.

## Verification commands

- `pnpm test:animation`
- `pnpm test:weapon-studio`
- `pnpm test:combat`
- `pnpm weapons:check`
- `pnpm effects:check`
- `pnpm typecheck`
- `pnpm build`

## Task 1: Add the shared directional inheritance resolver

**Files**

- Create: `src/game/shared/animation/directionalInheritance.ts`
- Modify: `src/game/shared/animation/index.ts`
- Create: `scripts/tests/shared-animation/directional-inheritance.test.mjs`

**Implementation**

1. Define domain-neutral direction, mirror-axis, inheritance-policy, and resolved
   variant contracts without importing weapon or effect types.
2. Implement pure exact-first resolution for RIGHT-to-LEFT and DOWN-to-UP, followed by
   an optional domain Default fallback.
3. Return requested direction, source direction, authored state, `mirrorX`, and
   `mirrorY` with the resolved value.
4. Require an actual master variant before applying a mirror rule; never mirror
   Default as a substitute master.
5. Export the resolver from the shared animation index.

**Tests first**

- Exact LEFT/UP wins over enabled inheritance.
- Missing LEFT resolves RIGHT with `mirrorX: true` only.
- Missing UP resolves DOWN with `mirrorY: true` only.
- Disabled/missing master falls through to unmirrored Default.
- Every exact/mirror-enabled/master-present/Default-present combination follows
  the design resolution table.
- Unresolvable input returns no result without mutating variants.

**Verify**

```powershell
pnpm test:animation
pnpm typecheck
```

**Commit:** `feat: resolve shared directional inheritance`

## Task 2: Extend shared layered transforms with vertical mirroring

**Files**

- Modify: `src/game/shared/animation/layeredTransform.ts`
- Create: `src/game/shared/animation/directionalMaterialization.ts`
- Modify: `scripts/tests/shared-animation/layered-transform.test.mjs`
- Modify host fixtures found by `rg -n "mirrorX" src scripts/tests`

**Implementation**

1. Add required `mirrorY` to `LayeredAnimationHostTransform` and every host
   construction site.
2. Negate composed local Y offset when `mirrorY` is active.
3. Include host `mirrorY` in `flipY` XOR composition.
4. Negate local rotation when exactly one host mirror axis is active; preserve it
   when neither or both are active.
5. Keep origin, positive scale magnitudes, depth, and host rotation ordering
   unchanged.
6. Add a pure materializer that bakes one resolved host reflection into a cloned
   layered document: reflect every layer/block offset, negate both rotation levels
   for odd mirror parity, and toggle the reflected flip axis once per layer.
7. Leave gameplay tracks outside the visual materializer.

**Tests first**

- Vertical mirror reflects Y but not X.
- Vertical mirror participates in authored `flipY` cancellation.
- One mirror axis negates local rotation; two preserve it.
- Existing horizontal-mirror expectations remain unchanged.
- Asymmetric origin plus independent layer/block offsets reflects around the
  authored pivot with exact matrix-derived coordinates.
- Materialized animation with no host mirror renders identically to inherited
  animation with a host mirror.

**Verify**

```powershell
pnpm test:animation
pnpm typecheck
```

**Commit:** `feat: mirror layered animations vertically`

## Task 3: Make DOWN the weapon master and UP an optional override

**Files**

- Modify: `src/game/content/weapons/types.ts`
- Modify: `src/game/content/weapons/normalize.ts`
- Modify: `src/game/content/weapons/validation.ts`
- Modify: `src/game/content/weapons/weapon.schema.json`
- Modify: `src/game/content/weapons/migrateLegacyWeapon.ts`
- Modify: `scripts/tests/weapon-studio/weapon-v2-migration.test.mjs`
- Modify: `scripts/check-weapons.mjs` if it duplicates direction requirements

**Implementation**

1. Change v2 authored weapon typing so RIGHT/DOWN are required and LEFT/UP are
   optional.
2. Normalize all directions through the shared resolver with both inheritance
   pairs enabled.
3. Extend normalized presentation/source metadata to represent DOWN-to-UP without
   losing existing `mirror-right` behavior.
4. Preserve the complete DOWN package for inherited UP: animation, action,
   hitboxes, track spans, events, and multipliers.
5. Update schema and validators to require RIGHT/DOWN and validate optional
   LEFT/UP only when present.
6. Keep legacy migration lossless: explicit legacy UP data remains explicit.
7. Ensure normalization and migration do not mutate input documents.

**Tests first**

- A v2 weapon with RIGHT/DOWN only validates and resolves four directions.
- Inherited UP reports DOWN source and vertical mirror.
- Exact UP remains authored and unmirrored.
- Missing DOWN is rejected with an exact validation path.
- Inherited UP shares DOWN action, animation, hitboxes, and track values.
- Existing LEFT mirror and legacy migration assertions still pass.
- Legacy root-only, RIGHT-only, DOWN-only, explicit-UP, and all-direction inputs
  produce the documented explicit migration output.

**Verify**

```powershell
pnpm test:weapon-studio
pnpm weapons:check
pnpm typecheck
```

**Commit:** `feat: inherit weapon up attacks from down`

## Task 4: Add DOWN-to-UP inheritance to effects

**Files**

- Modify: `src/game/content/effects/types.ts`
- Modify: `src/game/content/effects/normalize.ts`
- Modify: `src/game/content/effects/validation.ts`
- Modify: `src/game/content/effects/effect.schema.json`
- Modify: `scripts/check-effects.mjs`
- Modify: `scripts/tests/weapon-studio/effect-content.test.mjs`

**Implementation**

1. Add `mirrorUpFromDown?: boolean` to authored effect documents and schema.
2. Replace the normalized single `mirrored` boolean with explicit mirror axes and
   source/authored metadata from the shared resolver.
3. Resolve exact, mirror pairs, then unmirrored Default in the approved order.
4. Validate the new flag type and require an authored DOWN master when the flag is
   active (enabled and exact UP is absent).
5. Preserve behavior of existing effects that omit the flag.
6. Encode the complete exact/flag/master/Default resolution matrix as table-driven
   tests so validation and normalization cannot interpret it differently.
7. Resolve all four requested directions independently; reject the whole effect if
   any direction is unresolved or an active mirror flag lacks its master. Treat an
   enabled flag as dormant while its exact child exists.

**Tests first**

- Enabled missing UP resolves DOWN with vertical mirror.
- Exact UP overrides the mirror flag.
- Missing DOWN with the flag enabled and no exact UP fails validation.
- Default fallback remains unmirrored.
- Disabled UP mirror plus missing UP uses Default when available and fails when it
  is absent.
- Enabled UP mirror plus missing DOWN is rejected when exact UP is absent, even
  when Default exists.
- Exact UP plus an enabled mirror flag and missing DOWN remains valid because the
  flag is dormant.
- Existing LEFT mirror behavior remains unchanged.

**Verify**

```powershell
pnpm test:weapon-studio
pnpm effects:check
pnpm typecheck
```

**Commit:** `feat: inherit effect up variants from down`

## Task 5: Feed both mirror axes through runtime weapon and effect adapters

**Files**

- Modify: `src/game/features/combat/WeaponVisual.ts`
- Modify: `src/game/features/effects/WorldEffectAdapter.ts`
- Modify: `src/game/features/effects/WorldEffectPool.ts`
- Modify: `src/game/combat/Weapon.ts` only if source-direction metadata leaks into
  hitbox selection
- Modify/create focused tests under `scripts/tests/combat/`

**Implementation**

1. Have `WeaponVisual` consume normalized mirror axes rather than infer only
   `mirror-right` locally.
2. Extend `WorldEffectAdapter.reset` and construction with `mirrorX` and `mirrorY`.
3. Pass normalized effect mirror axes through pooled effect reuse.
4. Keep attack direction UP when combat creates the attack snapshot, even when
   visual/combat package data comes from DOWN.
5. Confirm directional hitbox offset and sector-angle helpers receive requested
   UP and therefore produce upward collision geometry.
6. Share fixture expectations with Studio preview tests: UP center is
   `(offsetY, -offsetX)` and sector angle is `-Math.PI / 2`.

**Tests first**

- Weapon host transform reports only `mirrorY` for inherited UP.
- Reused effect slots reset both mirror axes between directions.
- Inherited UP rectangle/ellipse offsets resolve in UP coordinates.
- Inherited UP sectors aim upward while retaining DOWN-authored radii/spans.
- Confirmed-hit effect still spawns at the enemy contact edge.
- Runtime and Studio geometry fixtures produce identical centers and angles for
  asymmetric hitboxes in all four directions.

**Verify**

```powershell
pnpm test:animation
pnpm test:combat
pnpm typecheck
```

**Commit:** `feat: render vertical directional mirrors at runtime`

## Task 6: Extract pair-neutral Studio direction mode behavior

**Files**

- Create: `src/game/editor/DirectionalInheritanceView.ts`
- Create: `src/game/editor/DirectionalInheritanceState.ts`
- Modify: `src/game/editor/LayeredWeaponStudio.ts`
- Modify: `src/game/editor/WeaponStudio.ts`
- Modify: `src/game/editor/character-studio.css`
- Create/modify tests under `scripts/tests/weapon-studio/`

**Implementation**

1. Define the two Studio pairs once: RIGHT master/LEFT child/horizontal mirror and
   DOWN master/UP child/vertical mirror.
2. Centralize authored/inherited status, source direction, locked state, labels,
   action names, and mode-card text.
3. Render SIDE and VERTICAL groups with master/custom status and the approved
   labels.
4. Lock timeline, tile, layer, action, hitbox, and attack-track edits for either
   inherited child.
5. Make custom by deep-cloning the complete resolved master package in one state
   mutation. Materialize the visual reflection from Task 2 so the new exact child
   initially looks identical with no host mirror; copy gameplay data unchanged.
6. Restore inheritance by removing only the child package, resetting selection,
   and showing a clear unsaved notice.
7. Replace scattered LEFT-only source-direction branches in the active layered
   Studio with the pair-neutral helper.
8. Keep the compatibility Weapon Studio on the same helper until it is removed,
   so both screens cannot disagree.

**Tests first**

- DOWN displays MASTER and missing UP displays MIRROR DOWN.
- Inherited UP controls are disabled and name DOWN as owner.
- MAKE CUSTOM UP deep-clones every nested package field.
- MAKE CUSTOM UP preserves the inherited visual output without double mirroring.
- Editing custom UP never mutates DOWN.
- Editing DOWN after custom conversion no longer changes custom UP.
- RESTORE DOWN MIRROR removes only UP and immediately resolves later DOWN edits.
- Existing LEFT controls and labels retain behavior.

**Verify**

```powershell
pnpm test:weapon-studio
pnpm typecheck
```

**Commit:** `feat: author vertical mirrors in weapon studio`

## Task 7: Mirror DOWN correctly in Studio previews and effect editing

**Files**

- Modify: `src/game/editor/LayeredWeaponStudio.ts`
- Modify: `src/game/editor/WeaponStudio.ts`
- Modify shared preview helpers under `src/game/editor/` as identified by
  `rg -n "mirrorX|MIRROR RIGHT|direction === 'left'" src/game/editor`
- Modify: `scripts/tests/weapon-studio/keyframe-targeting.test.mjs`
- Modify: `scripts/tests/weapon-studio/effect-content.test.mjs`

**Implementation**

1. Resolve preview animation and package ownership through the shared directional
   result for both attack and effect scopes.
2. Apply vertical reflection to every active preview layer, including composed Y
   offsets, rotations, and flip state.
3. Preview inherited UP hitboxes using requested UP geometry and inherited DOWN
   activation spans.
4. Add the same make-custom/restore mode card and lock semantics to on-hit effect
   editing.
5. Ensure preview playback, tile selection, active-layer count, and playhead stay
   aligned while switching between DOWN and inherited/custom UP.

**Tests first**

- Preview markup/style differs by the exact expected vertical reflection.
- Non-centered origins and separate layer/block transforms match shared matrix
  results exactly.
- Hitbox preview points upward and tracks the inherited active window.
- Effect preview exposes MIRROR DOWN and becomes independently editable after
  custom conversion.
- Switching directions does not mutate or duplicate source data.

**Verify**

```powershell
pnpm test:weapon-studio
pnpm typecheck
```

**Commit:** `fix: preview vertical directional inheritance`

## Task 8: Update draft defaults, preserve existing content, and run full validation

**Files**

- Modify new-weapon/effect draft factories in `src/game/editor/LayeredWeaponStudio.ts`
- Modify: `scripts/migrate-weapon-content.mjs` if it authors new effect defaults
- Modify authored content only when explicitly required by validation; do not
  convert existing custom UP variants automatically
- Modify documentation comments and test fixtures that still state UP/DOWN are
  always independent

**Implementation**

1. Create new weapons with RIGHT/DOWN only; LEFT/UP begin inherited.
2. Create new effects with RIGHT/DOWN, `mirrorLeftFromRight: true`, and
   `mirrorUpFromDown: true`.
3. Keep current authored UP weapon/effect content unchanged and therefore custom.
4. Search for stale assumptions using:
   `rg -n "independent authored views|right.*up.*down|mirrorLeftFromRight|mirror-right" src scripts docs`.
5. Run focused suites, content checks, typecheck, and production build.
6. Inspect final diffs to ensure the user's pre-existing weapon JSON and CSS edits
   remain intact and unstaged unless the user separately requests them.

**Acceptance verification**

- New and existing content validates.
- Inherited UP weapon attacks and effects render vertically mirrored in runtime
  and Studio.
- Custom UP remains byte-for-byte stable unless edited.
- RIGHT-to-LEFT tests remain green.
- No implementation introduces duplicated child JSON for inherited directions.

**Verify**

```powershell
pnpm test:animation
pnpm test:weapon-studio
pnpm test:combat
pnpm weapons:check
pnpm effects:check
pnpm typecheck
pnpm build
```

**Commit:** `test: verify directional mirror pairs`
