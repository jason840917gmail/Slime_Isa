# Unified Animation Studio Design

## Status

Approved in conversation on 2026-09-04.

## Objective

Create one top-level Animation Studio for every authored animation workflow. It must make character and NPC spritesheets visible and replaceable, expose keyframe duplication, and retain the existing layered weapon/shared-animation tools without converting either content family to a different runtime format.

The unified Studio is an authoring shell with format-specific adapters. It is not a new animation data format.

## Current problem

The repository already contains two partially shared animation experiences:

- Character Studio edits single-spritesheet clips stored in `character.json` and `visual-set.json`. Its state layer already implements selected-keyframe duplication, but the UI does not expose that action. Its current asset shelf creates packages and does not let an existing character change its spritesheet.
- `AnimationStudio.ts` edits layered `animation.json` packages and is mounted from Weapon Studio. It is not represented as a first-class navigation destination, so users reasonably perceive it as part of Weapon Studio. Its source-sheet selector is scoped to an existing visual layer and is not useful for character/NPC clips.

This split hides capabilities and makes the same timeline concept feel like unrelated editors.

## Approved approach

Use one shell with two native adapters:

1. A single-sheet adapter for character and NPC clip packages.
2. A layered adapter for weapon-owned and reusable shared animation packages.

The shell owns navigation, combined catalog search, selection, preview placement, save status, undo/redo presentation, and validation presentation. Each adapter owns its native document state, timeline controls, source-sheet rules, and persistence endpoint.

The alternative of converting character clips to layered packages is rejected because it would require content, runtime, schema, and save migration without improving the immediate editing workflow. Keeping separate editors and adding only links is also rejected because it would preserve the current ambiguity.

## Navigation and package identity

Add `ANIMATIONS` as a first-class Studio tab and support `?studio=animations`.

The route accepts enough stable identity to restore a selection:

- a character package and optional clip ID; or
- a layered animation package ID.

Characters, Projectiles, Weapons, Animations, and Map Studio remain separate top-level destinations. Character Studio and Weapon Studio link to Animation Studio with the relevant package preselected. Existing `?studio=characters` and `?studio=weapons` entry points remain valid. Existing weapon URLs that include a shared animation selection may redirect or normalize to the new top-level Animation Studio URL without changing the referenced package.

The combined library displays native packages in one searchable tree with explicit badges:

- `CHARACTER`
- `NPC`
- `WEAPON`
- `SHARED`

Stable package IDs, file ownership, and references remain unchanged. The UI label does not become persisted data.

## Catalog boundary

The browser composes the combined library from the existing character-package and animation-library catalogs. A normalized editor-only union describes entries:

```ts
type AnimationStudioEntry =
  | {
      kind: 'single-sheet';
      role: 'character' | 'npc';
      characterId: string;
      displayName: string;
      visualSetId: string;
      clipIds: readonly string[];
    }
  | {
      kind: 'layered';
      role: 'weapon' | 'shared';
      animationId: string;
      displayName: string;
      packagePath: string;
    };
```

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
- append and insert-at-playhead controls;
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
- preserves the selected keyframe's authored hold duration by extending the timeline and shifting later keyframe start times;
- selects the newly inserted keyframe;
- creates one undoable mutation;
- does not duplicate hitbox spans or one-frame events automatically.

Events and spans remain attached to timeline positions. Shifting later keyframes must use the established timeline mutation policy so their positions remain internally valid.

The action is disabled only when there is no selected keyframe. It must not silently fail because every existing keyframe currently occupies a timeline cell; the operation extends duration as needed.

### Source-sheet replacement behavior

Changing the character/NPC source sheet updates `visualSet.assetId` only. It preserves:

- every clip ID;
- every source-frame number;
- keyframe times and holds;
- events and hitbox spans;
- default, clip, and frame visual transforms.

The source-frame grid, metadata, and preview switch immediately to the newly selected asset.

If any authored source-frame number is outside the new sheet's populated frame range, the adapter lists every affected clip/keyframe, highlights invalid source frames where practical, and blocks save. It does not clamp, remap, delete, or replace frames automatically. Selecting valid frames or changing back to a compatible sheet clears the error.

Only registered spritesheet assets are offered. Asset registration/import remains an asset/package creation concern and is not duplicated inside this first Animation Studio slice.

## Layered animation adapter

The layered adapter reuses `SharedAnimationDocumentState`, the layered timeline views, preview components, block inspector, and animation-library transaction endpoint already used by `AnimationStudio.ts`.

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

Weapon-specific combat tracks and weapon identity remain owned by Weapon Studio. Animation Studio edits the visual animation package or weapon-owned visual document selected by the adapter; it does not move damage, targeting, equipment, or hit-resolution logic.

## Persistence and unsaved-change behavior

Each adapter saves through its existing authoritative path:

- single-sheet changes use character package validation and save;
- layered changes use the animation-library transaction and package revision checks.

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

1. Extract or wrap the current layered `AnimationStudio.ts` implementation as the layered adapter.
2. Extract the animation-focused parts of Character Studio behind the single-sheet adapter while keeping Character Studio functional.
3. Add the top-level Animation Studio route and navigation tab.
4. Route animation-focused links from Character Studio and Weapon Studio into the unified shell.
5. Keep compatibility entry points until automated and manual coverage confirms the new route restores both package types.

Character and layered content files are not rewritten merely by opening the new Studio.

## Testing

Focused automated coverage must prove:

- the combined catalog includes character, NPC, weapon, and shared entries without ID collisions;
- route parsing and normalization restore both package families;
- adapter switches dispose the previous adapter and protect dirty drafts;
- Character and Weapon Studio links include the correct stable selection;
- duplicate character keyframe inserts immediately after selection, extends duration, shifts later keyframes, selects the duplicate, and forms one undo step;
- duplicate does not clone events or hitbox spans;
- layered duplicate retains source frame, transforms, and hold and reports no-space failures;
- changing a character/NPC spritesheet preserves every authored frame/timing/event value;
- out-of-range references block save and enumerate affected clips;
- changing back to a compatible sheet clears the error;
- layered source-sheet changes remain per-layer;
- existing character, NPC, shared-animation, weapon, and runtime validation stays green;
- the production build does not include development-only Studio mounts.

Manual verification must cover:

1. Open Animation Studio directly from the top-level tab.
2. Select Village Elder Plop and Mossy Scout and confirm their full spritesheets and five clips are visible.
3. Duplicate a keyframe, undo, redo, save, reload, and verify persistence.
4. Switch to an incompatible sheet, confirm frames are preserved and save is blocked, then switch back.
5. Select a layered weapon/shared animation, change the selected layer's sheet, and duplicate a tile.
6. Navigate to and from Character and Weapon Studio without losing stable selection.

## Non-goals

- Converting character clips to layered animation packages.
- Moving character gameplay, enemy AI, body, or equipment ownership into Animation Studio.
- Moving weapon combat timing or damage ownership into Animation Studio.
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
- each native package saves through its existing authoritative validator and endpoint;
- dirty-switch protection, undo/redo, validation, and cleanup work across adapter changes;
- existing content and runtime behavior remain compatible.
