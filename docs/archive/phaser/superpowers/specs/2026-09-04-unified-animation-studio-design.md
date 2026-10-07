# Unified Animation Studio Design

## Status

Approved by spec review and by the user on 2026-09-04.

## Objective

Create one top-level Animation Studio for every authored animation workflow. It must make character and NPC spritesheets visible and replaceable, expose keyframe duplication, and retain the existing layered weapon/shared-animation tools without converting either content family to a different runtime format.

The unified Studio is an authoring shell with format-specific adapters. It is not a new animation data format.

## Current problem

The repository already contains two partially shared animation experiences:

- Character Studio edits single-spritesheet clips stored in `character.json` and `visual-set.json`. Its state layer already implements selected-keyframe duplication, but the UI does not expose that action. Its current asset shelf creates packages and does not let an existing character change its spritesheet.
- `AnimationStudio.ts` edits layered `animation.json` packages and is mounted from Weapon Studio. It is not represented as a first-class navigation destination, so users reasonably perceive it as part of Weapon Studio. Its source-sheet selector is scoped to an existing visual layer and is not useful for character/NPC clips.

This split hides capabilities and makes the same timeline concept feel like unrelated editors.

## Approved approach

Use one shell with three native persistence adapters and two editing surfaces:

1. A single-sheet adapter for character and NPC clip packages.
2. A shared-package adapter for reusable layered `animation.json` packages.
3. A weapon-owned adapter for layered idle and directional-attack animation subdocuments embedded in a weapon package.

The shared-package and weapon-owned adapters reuse the same layered timeline, preview, source-sheet, and block-inspector components. They remain separate adapters because package identity, revision ownership, validation, and save transactions differ.

The shell owns navigation, combined catalog search, selection, preview placement, save status, undo/redo presentation, and validation presentation. Each adapter owns its native document state, timeline controls, source-sheet rules, and persistence endpoint.

The alternative of converting character clips to layered packages is rejected because it would require content, runtime, schema, and save migration without improving the immediate editing workflow. Keeping separate editors and adding only links is also rejected because it would preserve the current ambiguity.

## Navigation and package identity

Add `ANIMATIONS` as a first-class Studio tab and support `?studio=animations`.

The route accepts exactly one of these stable selection forms:

- `?studio=animations&character=<characterId>&clip=<clipId>`;
- `?studio=animations&animation=<animationId>`;
- `?studio=animations&weapon=<weaponId>&slot=idle`; or
- `?studio=animations&weapon=<weaponId>&slot=attack&direction=<right|left|up|down>`.

When parameters from multiple selection families are present, the shell treats the route as stale, removes the conflicting selection parameters, and selects the first available entry. It does not guess which family the user intended.

Characters, Projectiles, Weapons, Animations, and Map Studio remain separate top-level destinations. Character Studio and Weapon Studio link to Animation Studio with the relevant package preselected. Existing `?studio=characters` and `?studio=weapons` entry points remain valid. Existing weapon URLs that include a shared animation selection may redirect or normalize to the new top-level Animation Studio URL without changing the referenced package.

The combined library displays native packages in one searchable tree with explicit badges:

- `PLAYER`
- `ENEMY`
- `NPC`
- `WEAPON`
- `SHARED`

Stable package IDs, file ownership, and references remain unchanged. The UI label does not become persisted data.

## Catalog boundary

The browser composes the combined library from three existing authorities:

- `characterPackages` from `virtual-character-content` for character/NPC package metadata;
- `/__animation-library/catalog` for shared layered packages and their revisions; and
- `/__character-studio/weapons` for version-2 weapon documents and weapon revisions.

`/__character-studio/assets` remains the source-sheet picker catalog; it is not an animation identity catalog. A normalized editor-only union describes selectable entries:

```ts
type AnimationStudioEntry =
  | {
      kind: 'single-sheet';
      role: 'player' | 'enemy' | 'npc';
      characterId: string;
      displayName: string;
      visualSetId: string;
      clipIds: readonly string[];
    }
  | {
      kind: 'shared-package';
      role: 'shared';
      animationId: string;
      displayName: string;
      packagePath: string;
      revision: string;
    }
  | {
      kind: 'weapon-owned';
      role: 'weapon';
      weaponId: string;
      displayName: string;
      revision: string;
      slot: 'idle';
    }
  | {
      kind: 'weapon-owned';
      role: 'weapon';
      weaponId: string;
      displayName: string;
      revision: string;
      slot: 'attack';
      direction: 'right' | 'left' | 'up' | 'down';
    };
```

The browser normalization joins the weapon and shared-package catalogs by `idleAnimationId` and directional `animationId`. It emits one selectable entry per editable owned animation slot, not one ambiguous entry per weapon. `idle` has no direction. `attack` entries always include a direction. An attack direction inherited from its paired master is rendered as an alias to the owning master slot; it is not silently materialized by merely opening Animation Studio.

If an idle or attack slot references a shared `animationId`, its weapon-folder row is an alias to the matching shared-package entry and edits that authoritative package. A missing shared target is a catalog diagnostic, not a weapon-owned fallback. The shell must not expose a hydrated compatibility copy as weapon-owned content. The `WEAPON` badge is reserved for animation subdocuments whose authoritative storage is the weapon package.

After a weapon-owned save, the shell refetches `/__character-studio/weapons`, replaces the authoritative weapon document/revision, and rebuilds every owned entry and alias sharing that `weaponId`. This prevents the other idle/directional rows for the same full-document save from retaining a stale revision or stale inheritance/reference state.

This union is presentation metadata only. It must not make Character Studio depend on the layered animation schema or make the shared animation library depend on the virtual character-content module.

The initial implementation should reuse the existing endpoints and normalize their responses in the browser. A new combined persistence endpoint is out of scope.

## Shared shell responsibilities

The shell provides:

- a single library/search surface;
- route-to-selection synchronization;
- package type and role badges;
- a consistent preview frame and preview controls;
- a consistent timeline location;
- visible save, dirty, undo, redo, and validation states;
- adapter mounting and cleanup;
- protection against losing unsaved changes when switching packages or package families.

The shell calls the active adapter through a narrow lifecycle contract. The exact names may vary, but the contract must cover render/mount, current identity, dirty state, validation issues, undo, redo, save, and dispose. Adapter cleanup must remove listeners, timers, pointer capture, and pending UI state before another adapter mounts.

## Single-sheet character and NPC adapter

The adapter uses the existing `CharacterDocumentState`, character timeline helpers, package validation, and character package save endpoint. It edits one selected clip at a time while preserving the complete package document.

Its layout exposes:

- the selected character or NPC identity and clip tabs;
- the current spritesheet thumbnail;
- the current asset ID;
- grid columns, rows, cell dimensions, and populated frame count;
- a visible `CHANGE SOURCE SHEET` control;
- the complete source-frame grid for the selected sheet;
- append and insert-before-selection controls;
- the keyframe timeline with selection, drag reorder, hold resize, timing labels, and event markers;
- `DUPLICATE KEYFRAME` and `REMOVE KEYFRAME` actions;
- FPS, duration, loop, and loop-mode controls;
- character/NPC animation events and the existing role restrictions;
- frame, clip, and default visual alignment controls relevant to animation presentation.

Gameplay attributes, AI values, body geometry, hitbox definitions, and other non-animation Character Studio fields remain in Character Studio. The Animation Studio may display hitbox/event timeline rows required to author an animation track, but it must not become a general character gameplay editor.

### Duplicate-keyframe behavior

Duplicating a selected single-sheet keyframe:

- copies its source-frame ID;
- copies its occurrence-level visual/timing meaning, not the package-global source-frame override object;
- inserts the new keyframe immediately after the selected keyframe;
- preserves the selected keyframe's authored hold duration by extending the timeline at the end of that hold and shifting later authored content;
- selects the newly inserted keyframe;
- creates one undoable mutation;
- does not duplicate hitbox spans or one-frame events automatically.

Single-sheet insertion and duplication use one timeline-position remapper:

- `INSERT BEFORE SELECTION` inserts each selected source frame as a one-timeline-cell keyframe immediately before the selected occurrence. It shifts that occurrence and all later keyframes by the number of inserted cells.
- `DUPLICATE KEYFRAME` inserts one occurrence at the end boundary of the selected occurrence and gives it the same hold length as the selected occurrence. It shifts every later keyframe by that hold length.
- Events at or after the insertion boundary shift by the inserted duration so they remain attached to their original authored content. No event is cloned onto inserted or duplicated cells.
- A hitbox span entirely at or after the boundary shifts as a unit. A span entirely before the boundary is unchanged. A span crossing the boundary is split into a pre-insertion segment and a shifted post-insertion segment, leaving the newly inserted cells inactive. Canonicalization must not merge the two segments across that intentional gap.
- Selection moves to the first inserted occurrence for insert, and to the duplicated occurrence for duplicate.

This policy replaces the current free-cell duplication behavior, which may place a copy inside an unrelated longest hold and may fail when no free cell exists. It is implemented as one shared timeline mutation helper so clips, events, spans, undo, and validation cannot diverge.

The action is disabled only when there is no selected keyframe. It must not silently fail because every existing keyframe currently occupies a timeline cell; the operation extends duration as needed.

### Source-sheet replacement behavior

Changing the character/NPC source sheet updates `visualSet.assetId` only. It preserves:

- every clip ID;
- every source-frame number;
- keyframe times and holds;
- events and hitbox spans;
- default, clip, and frame visual transforms.

The source-frame grid, metadata, and preview switch immediately to the newly selected asset.

If any authored source-frame number is outside the new sheet's populated frame range, the adapter blocks save and reports every invalid reference in two groups:

- each clip/keyframe occurrence whose source-frame number is invalid; and
- each key in `visualSet.frameVisuals` whose numeric source-frame number is invalid, including keys not currently used by a clip.

The adapter highlights invalid source frames where practical. It does not clamp, remap, delete, or replace frames automatically. Re-authoring every invalid occurrence/override or changing back to a compatible sheet clears the error.

Only registered spritesheet assets are offered. Asset registration/import remains an asset/package creation concern and is not duplicated inside this first Animation Studio slice.

The existing character update endpoint must be relaxed narrowly for this operation: `characterId`, character kind, runtime role, character `visualSetId`, and visual-set `visualSetId` remain immutable, but `visualSet.assetId` is no longer an identity field on update. The endpoint still performs revision checking and validates the complete submitted package against the asset manifest, spritesheet frame count, role policy, and package root before writing. Duplicate/create identity rules are unchanged. Therefore a compatible registered replacement can save, while unknown assets and any out-of-range clip frame or `frameVisuals` key are rejected server-side even if a client bypasses the UI guard.

## Shared layered-package adapter

The shared-package adapter reuses `SharedAnimationDocumentState`, the layered timeline views, preview components, block inspector, and animation-library transaction endpoint already used by `AnimationStudio.ts`.

It continues to expose:

- animation package metadata;
- layers and per-layer spritesheet selection;
- the source-frame picker for the selected layer;
- tile/block placement at the playhead;
- drag movement and hold resize;
- `DUPLICATE TILE` for the selected block;
- per-layer and per-block transform controls;
- duration, FPS, loop, loop mode, preview playback, undo/redo, and save.

Duplicating a layered block retains the current behavior: it copies source frame, transform, and hold immediately after the selected block only when that range is free and inside the authored duration. If it cannot fit, the Studio reports the reason instead of failing without feedback.

## Weapon-owned layered adapter

The weapon-owned adapter reuses the same layered editing components but has a distinct document contract:

- identity is `weaponId + slot + optional direction`, with the weapon catalog revision;
- load retains the complete `LayeredWeaponDefinition` draft so all non-animation fields survive save unchanged;
- direct UI edits may mutate only the selected owned animation subtree; attack timing changes additionally reconcile that direction's dependent `attackTrack` in the same mutation as described below;
- idle edits target `weapon.animations.idle` only when `idleAnimationId` is absent;
- attack edits target the explicitly authored `weapon.directionalAttacks[direction].animation` only when that attack has no shared `animationId`;
- inherited directions are read-only redirects to their owning master direction and are not materialized in this Studio;
- validation runs the complete weapon validator plus asset validation before save;
- save uses the existing weapon package endpoint, weapon revision, and conflict handling, and sends no effect mutation;
- after a successful save, the adapter installs the returned weapon revision, refetches the weapon catalog, and rebuilds every entry/alias for that weapon without losing selection.

For an owned attack, any mutation that changes `framesPerSecond` or total timeline-frame count atomically runs the existing `reconcileWeaponAttackTrack(previousAnimation, nextAnimation)` policy. It time-projects events and hitbox bounds when FPS changes, removes events that fall outside a shortened timeline, and clamps or removes spans that no longer fit. The animation change and reconciled sibling track form one undo entry and one full-weapon save. The user cannot directly edit combat markers from Animation Studio, but structural timing edits cannot leave them invalid.

The adapter never uses the shared-animation transaction for an owned subtree. Conversely, a slot carrying a shared animation reference opens the shared-package adapter, so `stripSharedAnimationCopies` is not part of the unified editor's save path.

Weapon combat tracks, hitboxes, targeting, damage, equipment data, and on-hit effect documents remain in Weapon Studio. Reusable on-hit effects are explicitly outside the first unified Studio slice because they have their own effect identity, revision, direction inheritance, and two-document save transaction; their layered visual components may be migrated later behind a fourth adapter without changing this shell contract.

Shared attack animations cannot safely reconcile every referencing weapon in the animation-library transaction. Therefore timing fields are locked when a shared package is referenced by any weapon attack whose `attackTrack` contains an event or hitbox span. The shell derives this lock and lists the affected weapon slots from the loaded weapon catalog. The animation-library transaction independently enforces the same rule by comparing the existing and submitted shared package: if FPS or total timeline-frame count changes while such a dependent track exists, it rejects the write with consumer-specific diagnostics. Other visual edits remain available, and timing edits remain available for unreferenced packages, idle-only references, and attack references with no dependent track markers.

## Persistence and unsaved-change behavior

Each adapter saves through its existing authoritative path:

- single-sheet changes use character package validation and save;
- shared-package changes use the animation-library transaction and package revision checks;
- weapon-owned changes validate and save the complete weapon draft through the existing weapon package endpoint with `expectedWeaponRevision`, while limiting edits to the selected animation plus any required attack-track reconciliation.

The shell never serializes one package kind through the other endpoint.

Switching packages, changing Studio tabs, or following a Character/Weapon link while the active adapter is dirty prompts before discarding changes. A rejected save preserves the draft and current selection. Revision conflicts use the existing conflict messages and do not overwrite disk.

## Error handling

The shell distinguishes catalog/loading failures from adapter validation failures.

- Catalog failure: keep navigation visible and show a retry action.
- Missing selected package: clear the stale route identity and select the first available compatible entry.
- Incompatible source sheet: keep the selection and draft visible, block save, and list invalid frame references.
- Adapter mount failure: dispose partial listeners/timers and show a recoverable error instead of leaving two editors active.
- Duplicate failure: explain the timing/range conflict and preserve the original selection.
- Save conflict or server failure: preserve the dirty draft and display the authoritative message.

## Migration and compatibility

Implementation proceeds without deleting either current editor path immediately.

1. Extract the current `AnimationStudio.ts` layered editing surface and wrap its existing document state as the shared-package adapter.
2. Reuse that layered surface behind a weapon-owned adapter with weapon identity, revision, validation, and persistence.
3. Extract the animation-focused parts of Character Studio behind the single-sheet adapter while keeping Character Studio functional.
4. Narrowly allow `visualSet.assetId` replacement in the character update endpoint while retaining all other identity and manifest/frame validation.
5. Add the server-side shared-animation timing guard for weapon attack-track consumers.
6. Add the top-level Animation Studio route and navigation tab.
7. Route animation-focused links from Character Studio and Weapon Studio into the unified shell.
8. Keep compatibility entry points until automated and manual coverage confirms the new route restores all three adapter identities.

Character and layered content files are not rewritten merely by opening the new Studio.

## Testing

Focused automated coverage must prove:

- the combined catalog includes character, NPC, weapon, and shared entries without ID collisions;
- weapon entries have stable slot identities, inherited slots redirect without materialization, and shared-reference slots resolve to the shared package;
- all entries and aliases for a saved weapon refresh to the returned authoritative revision and structure;
- route parsing and normalization restore all three adapter identities and reject mixed-family parameters;
- adapter switches dispose the previous adapter and protect dirty drafts;
- Character and Weapon Studio links include the correct stable selection;
- duplicate character keyframe inserts immediately after the selected hold, copies its hold, extends duration, shifts later content, selects the duplicate, and forms one undo step;
- insert-before-selection uses one-cell keyframes and selects the first insertion;
- insert and duplicate shift later events, shift later spans, split crossing spans around an inactive gap, and do not clone events or activate hitboxes on inserted cells;
- layered duplicate retains source frame, transforms, and hold and reports no-space failures;
- changing a character/NPC spritesheet preserves every authored frame/timing/event value;
- out-of-range references block save and enumerate affected clip occurrences and unused `frameVisuals` keys;
- the character update endpoint accepts a compatible registered `assetId` replacement, preserves all stable package identity fields, and rejects unknown or frame-incompatible replacements;
- changing back to a compatible sheet clears the error;
- layered source-sheet changes remain per-layer;
- weapon-owned edits preserve all non-animation weapon fields, use the weapon revision, and report conflicts without overwriting disk;
- owned attack timing edits reconcile the dependent track atomically and remain one undo entry;
- shared-reference weapon slots save only through the shared-package transaction;
- shared animation timing controls lock for weapon attack-track consumers, and the transaction rejects an equivalent bypass attempt with consumer diagnostics;
- existing character, NPC, shared-animation, weapon, and runtime validation stays green;
- the production build does not include development-only Studio mounts.

Manual verification must cover:

1. Open Animation Studio directly from the top-level tab.
2. Select Village Elder Plop and Mossy Scout and confirm their full spritesheets and five clips are visible.
3. Duplicate a keyframe, undo, redo, save, reload, and verify persistence.
4. Switch to an incompatible sheet, confirm frames are preserved and save is blocked, then switch back.
5. Select a weapon-owned animation and a shared animation, change each selected layer's sheet, duplicate a tile, save, and reload.
6. Open an inherited weapon direction and confirm it redirects without creating a new directional document.
7. Open a weapon slot backed by a shared animation and confirm saving changes only the shared package.
8. Confirm a shared package with weapon attack markers allows visual edits but locks FPS/duration changes.
9. Navigate to and from Character and Weapon Studio without losing stable selection.

## Non-goals

- Converting character clips to layered animation packages.
- Moving character gameplay, enemy AI, body, or equipment ownership into Animation Studio.
- Moving weapon combat timing or damage ownership into Animation Studio.
- Editing weapon on-hit effect documents in the first unified Studio slice.
- Automatically remapping frames when a sheet changes.
- Creating a new asset import pipeline.
- Removing current compatibility entry points in the first slice.
- Changing production runtime animation formats or save-game data.

## Acceptance criteria

The work is complete when:

- `ANIMATIONS` is a visible top-level Studio destination;
- a user can find and open character, NPC, weapon, and shared animation content from one library;
- Village Elder Plop and Mossy Scout show their source sheets and can change to another registered sheet;
- source-sheet replacement preserves authored frame numbers and blocks invalid saves;
- a selected character/NPC keyframe has a visible, working duplicate action;
- layered packages retain visible source-sheet selection and tile duplication;
- each native package saves through its existing authoritative validator, identity, revision, and endpoint;
- weapon-owned animation saves preserve every unrelated weapon field, while shared-reference weapon slots edit only their shared package;
- owned attack timing changes reconcile dependent tracks, and unsafe shared timing changes are blocked in both UI and persistence;
- dirty-switch protection, undo/redo, validation, and cleanup work across adapter changes;
- existing content and runtime behavior remain compatible.
