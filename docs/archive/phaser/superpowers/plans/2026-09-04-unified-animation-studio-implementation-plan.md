# Unified Animation Studio Implementation Plan

## Objective

Implement the approved [Unified Animation Studio design](../specs/2026-09-04-unified-animation-studio-design.md): add a first-class `ANIMATIONS` Studio destination that can edit player, enemy, NPC, shared layered, and weapon-owned layered animations through one shell while retaining each native document format, validator, revision, and persistence endpoint.

The implementation must expose character/NPC/enemy source sheets and source-sheet replacement, add adjacent keyframe duplication with deterministic timeline metadata remapping, preserve the existing shared layered package tools, and safely edit embedded weapon animations without moving gameplay or combat ownership into Animation Studio.

## Execution rules

- Preserve the approved three-adapter boundary: single-sheet character packages, shared layered packages, and weapon-owned layered subdocuments.
- Do not convert character clips to layered packages, add a new runtime animation format, or rewrite content merely by opening it.
- Work test-first at each boundary: add the failing focused test, make the smallest implementation change, run the focused command, then continue.
- Keep development-only editor imports behind `import.meta.env.DEV`; production gameplay must not eagerly import any Studio mount.
- Use the existing character package update, animation-library transaction, and weapon package save paths. Do not add a combined write endpoint.
- The worktree already contains substantial user-owned NPC, crafting, map, and HUD changes, including edits in `package.json`, `src/game/config.ts`, `CharacterDocumentState.ts`, `CharacterStudio.ts`, `characterContentModulesPlugin.ts`, and `character-studio.css`. Before each checkpoint, re-read `git status --short`, inspect overlapping hunks, stage only files belonging to that phase, and never discard unrelated changes.
- Do not touch `.animation-library-transaction-*`, `.character-studio-*`, `.superpowers/brainstorm/`, or `temp/` artifacts except through their owning tests and cleanup paths.
- Keep current Character Studio and Weapon Studio functional throughout the migration. Remove only the nested shared-animation routing after the new top-level route has focused coverage.
- Treat source-sheet replacement as a reference change, not a frame migration: preserve authored frame numbers and block invalid saves.

## Phase 0 — Record the baseline and protect overlapping work

**Read/verify**

- `git status --short`
- `package.json`
- `src/game/config.ts`
- `src/game/editor/CharacterStudio.ts`
- `src/game/editor/CharacterDocumentState.ts`
- `src/game/editor/AnimationStudio.ts`
- `src/game/editor/LayeredWeaponStudio.ts`
- `src/game/content/characters/characterContentModulesPlugin.ts`
- `src/game/content/animations/animationContentModulesPlugin.ts`
- `src/game/editor/character-studio.css`

**Steps**

1. Capture the current dirty-file list and note which relevant files already contain the uncommitted NPC work. Use hunk-level inspection before modifying those files.
2. Confirm the production NPC packages and sheets referenced by the acceptance test are present:
   - `src/game/content/characters/village-elder-plop/`
   - `src/game/content/characters/mossy-scout/`
   - `asset/characters/authored/npcs/village-elder-plop.png`
   - `asset/characters/authored/npcs/mossy-scout.png`
3. Run the focused baseline before changing implementation:

```text
pnpm test:character-studio
pnpm test:animation-packages
pnpm test:animation
pnpm test:weapon-studio
pnpm characters:check
pnpm animations:check
pnpm weapons:check
pnpm typecheck
```

4. Record pre-existing failures separately. Do not broaden this work to repair unrelated game UI, map, crafting, or NPC runtime failures.

No commit is expected for this phase.

## Phase 1 — Add the Animation Studio identity, route, and combined catalog contracts

**Create**

- `src/game/editor/AnimationStudioCatalog.ts`
- `src/game/editor/AnimationStudioRoute.ts`
- `scripts/tests/animation-studio/catalog-route.test.mjs`

**Modify**

- `package.json`

**Steps**

1. Add `test:animation-studio` as `node --test scripts/tests/animation-studio/*.test.mjs` and add it to `pnpm check` near the other Studio suites.
2. In `catalog-route.test.mjs`, use the existing esbuild/data-URL test pattern to add failing tests for:
   - prefixed keys that cannot collide across character, shared, and weapon-owned entries;
   - `player`, `enemy`, and `npc` single-sheet entries from `characterPackages`;
   - shared entries retaining `animationId`, `packagePath`, and revision;
   - one owned idle entry for an embedded idle animation without `idleAnimationId`;
   - one owned entry for each explicitly authored embedded attack direction without `animationId`;
   - missing `left` and `up` directions becoming aliases to the correct `right` and `down` masters;
   - referenced idle/attack slots becoming aliases to the matching shared entry instead of editable weapon-owned copies;
   - a missing shared target producing a disabled catalog diagnostic rather than falling back to hydrated embedded data;
   - version-1 weapons being excluded from the layered owned-entry set;
   - search text matching display name, stable ID, role, slot, direction, and package path.
3. Define `AnimationStudioEntry` as the exact discriminated union from the design. Keep idle and attack weapon branches distinct so TypeScript requires `direction` only for attacks.
4. Define editor-only alias and diagnostic node types separately from selectable entries. Aliases retain their visible weapon/slot path but resolve to an authoritative entry key.
5. Implement a pure `buildAnimationStudioCatalog(characterPackages, sharedCatalog, weapons)` function. It must not import the filesystem, Vite server APIs, Phaser, or DOM globals.
6. Resolve weapon direction inheritance using the existing right/left and down/up pairing rules. Opening an inherited alias must never add a missing directional document.
7. Add a pure helper that rebuilds all entries and aliases from complete source snapshots. The shell will call it after any catalog refresh instead of mutating individual rows and risking stale weapon revisions.
8. Define `AnimationStudioSelection` and pure route functions for these forms:
   - character plus optional clip;
   - shared animation ID;
   - weapon idle;
   - weapon attack plus direction.
9. Test route parsing, serialization, percent encoding, unknown parameters, invalid slot/direction combinations, and mixed-family parameters. Mixed selection families must normalize to no explicit selection; they must not receive precedence by accident.
10. Preserve unrelated query values such as `editor` when writing a valid selection and remove stale selection-family keys when switching adapters.

**Focused verification**

```text
pnpm test:animation-studio
pnpm typecheck
```

**Commit checkpoint:** `feat: define unified animation catalog and routes`

## Phase 2 — Replace free-cell character duplication with deterministic insertion remapping

**Modify**

- `src/game/editor/CharacterTimeline.ts`
- `src/game/editor/CharacterDocumentState.ts`
- `scripts/tests/character-studio/character-studio.test.mjs`
- `scripts/tests/animation-studio/single-sheet-timeline.test.mjs`

**Steps**

1. Add failing timeline tests around a clip with explicit `keyframeTimes`, unequal holds, events, and hitbox spans. Cover insert-before-selection and duplicate-after-selected-hold independently.
2. Replace the Character Timeline dependency on shared `duplicateKeyframe()` for this workflow with a focused insertion primitive that accepts one or more `{ sourceFrame, hold }` occurrences and an insertion boundary.
3. Have the primitive return the inserted keyframe index, insertion boundary, inserted duration, and next timeline frame count. Invalid clip/index/frame input must return a typed failure or throw the existing `AnimationTimelineError`; it must not silently consume an undo entry.
4. For insert-before-selection:
   - derive the boundary from the selected keyframe start;
   - insert selected source frames in selection order;
   - give each inserted occurrence a one-cell hold;
   - shift the selected occurrence and all later keyframe times by the inserted frame count.
5. For duplicate:
   - derive the selected start and hold from `normalizeAnimationClip()` and `holdLengthAtKeyframe()`;
   - insert one copy at `selectedStart + selectedHold`;
   - give the copy the same hold as the selected occurrence;
   - extend `durationSeconds` and shift later keyframe times by that hold.
6. Add one metadata remapper used by both operations:
   - events before the boundary stay unchanged;
   - events at or after it shift by the inserted duration;
   - spans entirely before stay unchanged;
   - spans at or after shift as a unit;
   - crossing spans split at the boundary, leaving the inserted cells inactive;
   - span canonicalization must preserve the intentional gap and must not merge the split parts.
7. Test exact-boundary events, a one-cell crossing span, a span ending just before the boundary, multiple hitbox IDs, insertion at index zero, insertion at clip end, duplicating the final keyframe, and nonuniform keyframe holds.
8. Refactor `CharacterDocumentState` history snapshots to include clip/timeline/source selection state in addition to package content. Undo and redo must restore a valid selection rather than leave an out-of-range index after an insertion is reversed.
9. Update `insertSelectedFrames()` and `duplicateSelectedFrame()` so selection moves to the first inserted occurrence or duplicate and `selectedSourceFrame` follows it. Each operation must create exactly one state-history entry.
10. Add direct state tests proving duplicate succeeds when all original timeline cells are occupied, undo restores the original document/selection, redo restores the duplicate/selection, and events/spans are not cloned onto the inserted cells.
11. Leave the generic shared `duplicateKeyframe()` utility unchanged for consumers outside Character Studio unless repository search proves it is now unused; do not alter layered block duplication semantics.

**Focused verification**

```text
pnpm test:character-studio
pnpm test:animation-studio
pnpm test:animation
pnpm typecheck
```

**Commit checkpoint:** `feat: duplicate character keyframes with timeline remapping`

## Phase 3 — Make source-sheet replacement valid, diagnosable, and saveable

**Create**

- `src/game/editor/CharacterSourceSheetCompatibility.ts`
- `scripts/tests/animation-studio/source-sheet-compatibility.test.mjs`

**Modify**

- `src/game/editor/CharacterDocumentState.ts`
- `src/game/content/characters/characterContentModulesPlugin.ts`
- `scripts/tests/character-studio/authoring-runtime.test.mjs`

**Steps**

1. Add a pure compatibility collector that receives a `VisualSetDocument` and populated frame count and returns typed occurrences for:
   - every invalid `clips[clipId].frames[keyframeIndex]`; and
   - every invalid numeric `frameVisuals` key, including unused overrides.
2. Test that the collector reports duplicate source-frame use once per clip occurrence, includes unused override keys, ignores valid boundary frame `count - 1`, rejects frame `count`, and keeps malformed keys visible through normal package validation.
3. Add `CharacterDocumentState.changeSourceSheet(assetId)` as one undoable mutation that changes only `visualSet.assetId`. It must preserve all clips, frames, keyframe times, duration, FPS, loop fields, animation tracks, events, spans, defaults, clip offsets, and `frameVisuals` objects byte-for-byte apart from the asset ID.
4. Add state tests for compatible replacement, incompatible replacement, undo/redo, and changing back to the original sheet. Do not add clamping, remapping, deletion, or default-frame substitution.
5. Update the character package update handler so these identity fields remain immutable:
   - character ID;
   - character kind;
   - runtime role;
   - character `visualSetId`;
   - visual-set `visualSetId`.
6. Remove only `visualSet.assetId` from the update identity comparison. Leave duplicate/create identity checks unchanged.
7. Keep `validatePackageAgainstRoot()` after the identity check. It remains the server authority for manifest membership, spritesheet populated count, clip frames, `frameVisuals`, character role, and package-root uniqueness.
8. Extend the fixture endpoint test to:
   - load an existing fixture package and revision;
   - update it to a second registered compatible spritesheet and verify the saved package/revision;
   - attempt an unknown asset and verify no disk change;
   - attempt a sheet with too few populated frames and assert diagnostics identify both a clip occurrence and unused `frameVisuals` key;
   - retry with the stale revision and confirm the conflict path still wins correctly.
9. Ensure failed writes leave the original character and visual-set files unchanged and do not leave transaction directories.

**Focused verification**

```text
pnpm test:animation-studio
pnpm test:character-studio
pnpm characters:check
pnpm assets:check
pnpm typecheck
```

**Commit checkpoint:** `feat: support validated character source sheet replacement`

## Phase 4 — Extract reusable single-sheet animation presentation from Character Studio

**Create**

- `src/game/editor/SingleSheetAnimationWorkbench.ts`
- `src/game/editor/SingleSheetAnimationAdapter.ts`

**Modify**

- `src/game/editor/CharacterStudio.ts`
- `src/game/editor/character-studio.css`
- `scripts/tests/animation-studio/single-sheet-adapter.test.mjs`
- `scripts/tests/character-studio/character-studio.test.mjs`

**Steps**

1. Add source-structure and pure-render tests for the common single-sheet surface before moving code. Assert it renders the current sheet thumbnail/metadata, full source grid, selected clip, timeline, duplicate/remove actions, playback controls, role-allowed event rows, and compatibility issues.
2. Extract only animation-focused rendering and event-neutral view models from `CharacterStudio.ts`:
   - frame sprite/tile rendering;
   - preview and alignment overlay;
   - clip tabs;
   - source-sheet metadata and frame grid;
   - timeline/keyframe rendering and hold controls;
   - animation-event/hitbox-span rows required to understand the track;
   - playback and animation transform inspector fields.
3. Keep body, gameplay attributes, AI, projectile configuration, hitbox-definition creation, game constants, package creation/duplication, and general character inspector sections in Character Studio.
4. Make Character Studio consume the extracted render helpers so the existing editor does not fork into a second implementation. Preserve its current package, gameplay, constants, drag, resize, and modal behavior.
5. Add a visible `DUPLICATE KEYFRAME` action beside `REMOVE KEYFRAME` in the common timeline controls. Wire Character Studio to `duplicateSelectedFrame()` as a regression benefit; this must not wait for the top-level shell.
6. Rename all `INSERT AT PLAYHEAD` copy for single-sheet clips to `INSERT BEFORE SELECTION`, matching the actual selected-keyframe model.
7. Implement `SingleSheetAnimationAdapter` around `CharacterDocumentState`. It loads `/__character-studio/package/:characterId`, opens the requested clip or the first clip, and loads `/__character-studio/assets` for replacement choices and frame metadata.
8. The adapter renders only animation-related workbench/inspector content. It may show existing hitbox spans and events and permit the same role-valid animation event/span mutations already supported by state, but it does not render or mutate gameplay, body, AI, attributes, or hitbox definitions.
9. Add `CHANGE SOURCE SHEET` as an existing-package action distinct from the package-creation asset shelf. Offer only catalog entries with `kind === 'spritesheet'`, show the current selection, and apply `changeSourceSheet()` immediately to the draft after confirmation.
10. Use `CharacterSourceSheetCompatibility` with the chosen asset's populated count. Render every invalid clip/keyframe and unused override, highlight invalid frame numbers in the source/timeline where possible, and expose the diagnostics through adapter status so the shell disables save.
11. Save the complete character package to `/__character-studio/package/update` with the package revision. On success, call `markSaved()` with the returned package/revision. On conflict/failure, preserve the draft, selection, sheet picker state, and diagnostic list.
12. Implement the adapter lifecycle contract needed by the shell: stable identity, status subscription, dirty/saving/canUndo/canRedo, save, undo, redo, mount, and dispose. Disposal must stop playback, cancel drags, unsubscribe state listeners, remove DOM/window listeners, and close picker/modal state.
13. Add tests with player, enemy, Village Elder Plop, and Mossy Scout fixtures. Confirm NPC role restrictions remain enforced at the state boundary and both NPC sheets expose all authored clips.

**Focused verification**

```text
pnpm test:animation-studio
pnpm test:character-studio
pnpm characters:check
pnpm typecheck
```

**Manual checkpoint:** Open current Character Studio and confirm its preview, timeline, drag/resize, event/span tools, and gameplay inspector still behave as before after the extraction.

**Commit checkpoint:** `refactor: share the single sheet animation workbench`

## Phase 5 — Extract the shared layered adapter and common layered workbench

**Create**

- `src/game/editor/LayeredAnimationWorkbench.ts`
- `src/game/editor/SharedAnimationStudioAdapter.ts`

**Modify**

- `src/game/editor/AnimationStudio.ts`
- `src/game/editor/SharedAnimationDocumentState.ts`
- `src/game/editor/LayeredAnimationDocumentState.ts`
- `src/game/editor/LayeredAnimationPreviewPanel.ts`
- `src/game/editor/LayeredAnimationTimelinePanel.ts`
- `src/game/editor/LayeredAnimationBlockInspector.ts`
- `src/game/editor/character-studio.css`
- `scripts/tests/weapon-studio/shared-workbench-integration.test.mjs`
- `scripts/tests/animation-studio/shared-adapter.test.mjs`

**Steps**

1. Add failing tests that describe the layered workbench as a document-agnostic visual editor: render layers, source selector, source-frame picker, playhead, block movement/resize, `DUPLICATE TILE`, transforms, preview, FPS/duration/loop controls, undo/redo hooks, and a caller-supplied timing-lock reason.
2. Move the current shared-package workbench rendering and DOM interaction machinery out of `AnimationStudio.ts` into `LayeredAnimationWorkbench.ts`. Reuse the existing timeline/preview/block-inspector modules rather than creating parallel versions.
3. Give the workbench a narrow host contract:
   - read the current layered animation and selection;
   - invoke typed visual/timing mutations;
   - receive spritesheet catalog metadata;
   - expose timing editability and a reason;
   - notify the adapter of selection/status changes;
   - dispose playback timers, split/resize drags, pointer capture, and listeners.
4. Preserve existing `LayeredAnimationDocumentState` semantics for layer/block placement, movement, hold resize, transforms, visibility/solo state, duplicate fit checks, FPS reprojection, and duration validation.
5. Make duplicate failure return/display the existing no-space reason. Do not silently no-op when a duplicate is outside duration or overlaps another block.
6. Implement `SharedAnimationStudioAdapter` around `SharedAnimationDocumentState`, including package metadata, create/duplicate/move/delete actions, selected path, catalog revision, entry revision, validation, dirty history, and `/__animation-library/transaction` persistence.
7. After save, replace the adapter's authoritative package/catalog snapshot with the returned transaction catalog, retain the selected `animationId`, and clear dirty history without a reload.
8. Keep the adapter responsible for shared package identity and CRUD; keep the layered workbench responsible only for animation presentation/mutations.
9. Reduce `AnimationStudio.ts` to the eventual shell entry point or a temporary forwarding mount during this phase. Do not leave two exported `mountAnimationStudio` implementations.
10. Update the existing shared-workbench tests to target the extracted module and assert both shared and weapon adapters will depend on it rather than copying its markup/actions.

**Focused verification**

```text
pnpm test:animation-studio
pnpm test:animation
pnpm test:animation-packages
pnpm test:weapon-studio
pnpm typecheck
```

**Manual checkpoint:** Open the current shared package path through its compatibility URL and verify package CRUD, tile picker, duplicate, transforms, split resize, zoom, playback, undo/redo, save, and reload.

**Commit checkpoint:** `refactor: extract the shared layered animation adapter`

## Phase 6 — Protect shared timing when weapon attack tracks depend on it

**Modify**

- `src/game/content/animations/types.ts`
- `src/game/content/animations/animationContentModulesPlugin.ts`
- `src/game/editor/AnimationStudioCatalog.ts`
- `src/game/editor/SharedAnimationStudioAdapter.ts`
- `scripts/tests/animation-packages/package-validation.test.mjs`
- `scripts/tests/animation-studio/shared-timing-lock.test.mjs`

**Steps**

1. Extend `AnimationPackageReference` with explicit timing-dependency metadata for weapon attack references. Do not infer timing dependency from loop mode or owner kind in the UI.
2. In `readAnimationReferences()`, mark a directional weapon reference as timing-dependent only when its `attackTrack` contains at least one event or hitbox span. Idle references, object references, and marker-free attack references remain unlocked.
3. Add a dedicated diagnostic code such as `animation-timing-consumer-conflict` to the animation package diagnostic union.
4. Before staging any transaction write, compare the existing and submitted package's `framesPerSecond` and total `layeredTimelineFrameCount()`. If either changes and a timing-dependent weapon reference exists, reject the transaction with diagnostics naming every affected weapon and field.
5. Perform this check after ID/reference resolution but before any temporary write or replacement. A rejected batch must leave every package unchanged, even if another write in the batch is otherwise valid.
6. Add transaction tests for:
   - FPS change blocked by a referenced attack event;
   - total frame-count change blocked by a referenced hitbox span;
   - unchanged timing with visual block/source-sheet edits allowed;
   - marker-free attack reference allowed;
   - idle-only reference allowed;
   - multiple consumers enumerated;
   - batch atomicity on timing rejection.
7. Derive the same lock in `AnimationStudioCatalog` from the loaded weapon documents. Feed it to `SharedAnimationStudioAdapter` and the layered workbench.
8. Disable only FPS and duration controls when locked. Keep layer, source sheet, source frame, block positioning inside the existing duration, transforms, metadata, playback, and save available.
9. Render a concise lock explanation listing affected weapon slots. If a stale client bypasses the disabled control, surface the authoritative transaction diagnostic and retain its draft.
10. Confirm reference JSON responses remain backward compatible for clients that ignore the new optional metadata.

**Focused verification**

```text
pnpm test:animation-packages
pnpm test:animation-studio
pnpm animations:check
pnpm weapons:check
pnpm typecheck
```

**Commit checkpoint:** `feat: guard shared animation timing dependencies`

## Phase 7 — Add the weapon-owned document state and adapter

**Create**

- `src/game/editor/WeaponAnimationTrackReconciliation.ts`
- `src/game/editor/WeaponOwnedAnimationDocumentState.ts`
- `src/game/editor/WeaponAnimationStudioAdapter.ts`
- `scripts/tests/animation-studio/weapon-owned-state.test.mjs`
- `scripts/tests/animation-studio/weapon-adapter.test.mjs`

**Modify**

- `src/game/editor/LayeredWeaponStudio.ts`
- `src/game/editor/LayeredWeaponStudioMutation.ts`
- `scripts/tests/weapon-studio/layered-timeline.test.mjs`
- `scripts/tests/weapon-studio/shared-workbench-integration.test.mjs`

**Steps**

1. Extract `reconcileWeaponAttackTrack()` from `LayeredWeaponStudio.ts` into a pure module and keep Layered Weapon Studio using it. Add direct tests for unchanged FPS, FPS projection, duration growth, duration shrink, exact boundaries, removed out-of-range events, clamped/removed spans, and deterministic sorting/merging.
2. Implement `WeaponOwnedAnimationDocumentState` with:
   - the complete original and draft `LayeredWeaponDefinition`;
   - weapon revision;
   - an exact owned slot identity (`idle` or authored attack direction);
   - layered selection state;
   - full-document undo/redo snapshots;
   - dirty/validation/save state.
3. Reject construction or editing when:
   - the weapon is not version 2;
   - idle has `idleAnimationId`;
   - an attack direction is inherited rather than authored;
   - an authored attack has `animationId`;
   - the selected embedded animation is missing.
   These cases resolve through catalog aliases before adapter creation and must remain defensive failures if called directly.
4. Route visual workbench mutations only to the selected embedded animation. Do not expose setters for identity, combat, targeting, hitboxes, character action, icon, equipment, effect, or other direction data.
5. When FPS or total timeline-frame count changes for an owned attack, compare previous/next animation and reconcile only that direction's `attackTrack` in the same history mutation. Idle timing needs no sibling reconciliation.
6. Prove by deep-equality tests that every unrelated weapon field and every unselected animation direction remains unchanged after layer, block, source-sheet, FPS, duration, undo, and redo operations.
7. Validate the full weapon draft with `validateWeaponDefinitionForStudioSave()` and current asset/icon catalog checks before saving.
8. Implement `WeaponAnimationStudioAdapter` using the shared `LayeredAnimationWorkbench`. It displays weapon/slot/direction identity but no combat inspector or effect controls.
9. Save through `/__character-studio/weapon/save-package` with:
   - the complete weapon draft;
   - `weaponOperation: 'update'`;
   - `expectedWeaponRevision`;
   - no effect document or effect mutation fields.
10. Do not call `stripSharedAnimationCopies()` or `saveSharedAnimationEdits()` in this adapter; catalog resolution guarantees it only receives authoritative embedded animations.
11. On success, install the returned weapon revision, refetch `/__character-studio/weapons`, rebuild all catalog entries/aliases for that weapon, and retain the selected owned slot when still valid. If the saved structure changed its ownership unexpectedly, resolve through the rebuilt catalog instead of retaining a stale adapter.
12. On validation, revision conflict, or server error, keep the complete draft, workbench selection, undo/redo stacks, and current route unchanged.
13. Test an inherited direction route redirects to its master without materializing `left`/`up`, and a shared-reference slot opens the shared adapter without modifying the weapon document.

**Focused verification**

```text
pnpm test:animation-studio
pnpm test:weapon-studio
pnpm weapons:check
pnpm animations:check
pnpm typecheck
```

**Manual checkpoint:** Edit and save one embedded idle and one embedded attack animation, reload both, then verify Weapon Studio still shows all original combat, targeting, icon, and on-hit values.

**Commit checkpoint:** `feat: edit weapon owned animations in Animation Studio`

## Phase 8 — Build the unified shell, dirty-switch controller, and combined library

**Create**

- `src/game/editor/AnimationStudioAdapter.ts`
- `src/game/editor/AnimationStudioController.ts`
- `src/game/editor/AnimationStudioLibrary.ts`
- `scripts/tests/animation-studio/adapter-switching.test.mjs`
- `scripts/tests/animation-studio/library-rendering.test.mjs`

**Modify**

- `src/game/editor/AnimationStudio.ts`
- `src/game/editor/character-studio.css`

**Steps**

1. Define one lifecycle/status contract implemented by all three adapters. It must expose identity, dirty/saving state, validation issues, canUndo/canRedo, status message, save/undo/redo, status subscription, mount, and dispose.
2. Put adapter-switch orchestration in a DOM-independent controller. Inject adapter creation, discard confirmation, and route writing so fake adapters can prove behavior without adding a DOM test dependency.
3. Add failing controller tests for:
   - initial route selection;
   - clean adapter switch disposes exactly once;
   - dirty switch accepted disposes and mounts the next adapter;
   - dirty switch rejected keeps adapter and URL unchanged;
   - adapter creation failure disposes partial state and yields a recoverable shell error;
   - repeated selection does not remount;
   - shell disposal disposes the active adapter once;
   - save/undo/redo dispatch only to the active adapter.
4. Rebuild `AnimationStudio.ts` as the top-level shell. It loads in parallel:
   - `characterPackages` from `virtual-character-content`;
   - `/__animation-library/catalog`;
   - `/__character-studio/weapons`;
   - `/__character-studio/assets`.
5. Keep the shell/navigation visible if any catalog load fails. Show which authority failed and a retry action; do not mount an adapter using a half-resolved identity.
6. Render one searchable library tree with role badges `PLAYER`, `ENEMY`, `NPC`, `WEAPON`, and `SHARED`. Group single-sheet packages by role, shared packages by folder path, and weapon slot/alias rows under each weapon.
7. Render inherited and shared-reference weapon rows as aliases. Give disabled missing-reference rows an actionable diagnostic. Selection highlighting must follow the authoritative entry while preserving the visible alias context.
8. On an invalid/missing route selection, remove stale selection keys and choose the first available compatible entry. On mixed-family route parameters, clear them before fallback as defined in Phase 1.
9. Shell-owned topbar controls display adapter status and provide save, undo, and redo. The adapter owns only its workbench, inspector, and modal/picker surface.
10. Preserve search text and expanded folders when switching adapter families. Keep package-local selection such as clip, layer, block, and playhead inside the adapter.
11. Guard internal package/alias switches with the controller's dirty confirmation. Add a `beforeunload` handler while the active adapter is dirty so browser reload and top-level navigation receive native protection; remove it when clean or disposed.
12. Preserve `editor=<mapId>` in every Studio link and route update. Use `history.replaceState` for package/clip selection so normal editing does not fill browser history with every click.
13. Add shell cleanup for catalog retry callbacks, subscriptions, beforeunload, delegated events, and the active adapter. No listener, timer, picker, drag, or DOM from a prior adapter may remain after a switch.
14. Add render tests for role badges, stable keys, search, selected aliases, diagnostics, count, topbar state, and the five top-level Studio destinations.

**Focused verification**

```text
pnpm test:animation-studio
pnpm test:character-studio
pnpm test:weapon-studio
pnpm typecheck
```

**Manual checkpoint:** Switch repeatedly among an NPC clip, enemy clip, shared package, and embedded weapon attack while using preview playback and source pickers; confirm no duplicate timers, event responses, or stale selection remains.

**Commit checkpoint:** `feat: add the unified animation studio shell`

## Phase 9 — Promote Animation Studio to first-class navigation and add contextual links

**Modify**

- `src/game/config.ts`
- `src/game/editor/StudioModeTabs.ts`
- `src/game/editor/CharacterStudio.ts`
- `src/game/editor/LayeredWeaponStudio.ts`
- `src/game/editor/WeaponStudio.ts`
- `src/game/editor/AnimationStudio.ts`
- `src/game/editor/character-studio.css`
- `scripts/tests/animation-studio/navigation.test.mjs`
- `scripts/tests/weapon-studio/studio-library-tree.test.mjs`
- `scripts/tests/weapon-studio/shared-workbench-integration.test.mjs`

**Steps**

1. Extend `StudioMode` and the top navigation with `animations`. Order the destinations as Characters, Projectiles, Weapons, Animations, Map Studio and set `aria-current` only on the active route.
2. In `createGame()`, parse the `studio` value once and add a dedicated development-only animation branch with title `Animation Studio — Field Cartographer` and dynamic import of `mountAnimationStudio`.
3. Stop treating `studio=animations` as Weapon Studio. Keep the Weapon branch and `mountWeaponStudio()` focused on weapons.
4. Preserve compatibility for old `?studio=weapons&animation=<id>` URLs by normalizing them to `?studio=animations&animation=<id>` before mounting the unified shell. Retain `editor` and unrelated safe query parameters.
5. Remove the nested shared-animation mount and import from `WeaponStudio.ts` only after the compatibility test passes. `mountWeaponStudio()` should mount the layered weapon editor directly and continue honoring `weapon=<id>`.
6. Add an `OPEN IN ANIMATION STUDIO` link in Character Studio using the selected character and clip route.
7. Add contextual Animation Studio links in Layered Weapon Studio:
   - embedded idle -> weapon idle route;
   - embedded authored attack -> weapon attack/direction route;
   - shared-reference idle/attack -> shared animation route;
   - inherited attack -> owning master route.
8. Keep the shared animation rows visible in Weapon Studio's library if they remain useful as navigation, but make them normal links to the top-level Animation Studio rather than replacing the Weapon Studio mount in place.
9. Update current tests that explicitly assert no `studio=animations` links. Replace that old expectation with first-class navigation and compatibility-route assertions.
10. Add source-structure coverage proving the Animation Studio dynamic import remains guarded by `import.meta.env.DEV` and production game initialization does not mount it.
11. Confirm dirty protection works when following contextual links from inside Animation Studio and that Character/Weapon Studio retain their own existing dirty prompts.

**Focused verification**

```text
pnpm test:animation-studio
pnpm test:character-studio
pnpm test:weapon-studio
pnpm typecheck
pnpm build
```

**Manual checkpoint:** Open every top-level tab, use both contextual links, and paste each supported/compatibility URL directly into the browser.

**Commit checkpoint:** `feat: promote Animation Studio to top level navigation`

## Phase 10 — Acceptance hardening and regression cleanup

**Modify only as failures require**

- files already named by Phases 1–9
- focused test fixtures under `scripts/tests/animation-studio/`
- `docs/superpowers/specs/2026-09-04-unified-animation-studio-design.md` only if implementation reveals a genuinely incorrect design statement; obtain user approval before changing scope

**Steps**

1. Run the entire new suite and verify each acceptance path has an automated assertion.
2. Search for stale labels and routing:

```text
rg -n "INSERT AT PLAYHEAD|WEAPON STUDIO|studio=animations|mountAnimationStudio|duplicateSelectedFrame|visualSet\.assetId" src scripts/tests
```

3. Confirm remaining `INSERT AT PLAYHEAD` text belongs only to true layered playhead insertion.
4. Confirm no Animation Studio screen identifies itself as Weapon Studio and no `studio=animations` request enters `mountWeaponStudio()`.
5. Confirm every adapter reports validation and save errors through shell status without throwing away its draft.
6. Confirm all lifecycle cleanup paths remove listeners, playback timers, pointer drags/capture, state subscriptions, modals, and dirty navigation guards.
7. Confirm opening and closing the Studio without edits changes no character, animation, weapon, asset, map, or runtime content file.
8. Perform the design's manual acceptance sequence:
   - open Animation Studio from its top-level tab;
   - open Village Elder Plop and Mossy Scout and inspect every clip/source frame;
   - duplicate, undo, redo, save, reload;
   - select an incompatible sheet, confirm preserved frame numbers and blocked save, then restore a compatible sheet;
   - edit and save a shared layered package;
   - edit and save a weapon-owned idle and attack;
   - follow inherited and shared-reference aliases;
   - confirm shared timing lock when a weapon track has markers;
   - navigate between Character, Weapon, Animation, and Map Studio with stable selection and dirty prompts.
9. Run the complete project verification. If unrelated dirty work causes a failure, report it separately with evidence; do not modify unrelated files to force green.

## Final verification

```text
pnpm test:animation-studio
pnpm test:character-studio
pnpm test:animation-packages
pnpm test:animation
pnpm test:weapon-studio
pnpm characters:check
pnpm animations:check
pnpm weapons:check
pnpm assets:check
pnpm typecheck
pnpm build
pnpm check
```

## Completion criteria

- `ANIMATIONS` is a first-class top-level Studio destination with the correct title and development-only mount.
- The combined searchable library contains player, enemy, NPC, shared, weapon-owned, inherited-alias, and shared-reference-alias rows with collision-proof identities.
- Character/NPC/enemy source sheets are visible and replaceable; replacement changes only `visualSet.assetId`, preserves every frame/timing/track/transform value, and blocks invalid saves in UI and server validation.
- Character keyframe duplication is visible, adjacent, deterministic, succeeds without a free cell, preserves hold duration, remaps later metadata, and forms one undo step.
- Shared packages retain their current layered source-sheet, tile, timeline, preview, transform, CRUD, undo/redo, and transaction behavior.
- Shared FPS/duration changes are blocked in both UI and persistence when weapon attack markers depend on the timeline.
- Weapon-owned layered animations save through the weapon revision/validator while preserving unrelated weapon data and reconciling the selected attack track atomically.
- Inherited directions are never materialized by opening the editor, and shared-reference slots never edit hydrated weapon copies.
- Dirty-switch protection and full adapter cleanup work across all package families.
- Character Studio, Weapon Studio, runtime content, and existing validation remain compatible.

**Final commit checkpoint:** `feat: complete unified animation studio`
