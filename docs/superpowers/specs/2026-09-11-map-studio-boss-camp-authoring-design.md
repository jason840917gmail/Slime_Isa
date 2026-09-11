# Map Studio Boss Camp Authoring Design

**Date:** 2026-09-11  
**Status:** Approved for implementation  
**Related:** [Fatty One Eye guarded chest design](./2026-09-11-fatty-one-eye-guarded-chest-design.md), [Level 1 milestone 2 verification checklist](../../task/ideas/open/level-1-milestone-2-verification-checklist.md)

## Problem

Authored maps can contain `bossCamps`, and the runtime can spawn Fatty One Eye
from them, but Map Studio only preserves those records. It does not render the
boss, expose the camp as a selectable concept, or provide controls for editing
its spawn, circles, timer, or optional guarded chest. Opening Level 1 therefore
shows the chest but hides the encounter that owns it.

## Goals

1. Make every authored boss visible in Map Studio at its spawn point.
2. Add a dedicated **Boss Camp** tool for creating, selecting, moving, editing,
   and deleting boss camps.
3. Represent both activation and combat areas as independently editable circles
   centered on the boss spawn.
4. Expose the complete boss-camp record in the right inspector.
5. Keep the guarded chest optional and leave it untouched when a camp is deleted.
6. Preserve undo/redo, map resizing, validation, and save/reload behavior.

## Non-goals

- Running boss AI or combat inside Map Studio.
- Editing boss balance, attacks, animation frames, or effect immunities. Those
  remain owned by the boss definition.
- Treating bosses as ordinary map objects.
- Automatically creating or deleting a chest with a camp.
- Changing ordinary enemy-area or NPC-area workflows.

## Product direction

Map Studio is used by a creator arranging an authored encounter who needs to
understand its spatial relationships without reading JSON. The editor should
feel like a cartographer's encounter overlay rather than a generic form.

- **Domain concepts:** authored maps, boss lairs, spawn anchors, activation
  boundaries, combat arenas, guarded loot links, respawn rules.
- **Color world:** translucent slime green for the boss identity, cool cyan for
  activation, warm amber for the combat arena, chest gold for guarded-loot
  links, and the existing dark map-overlay ink for contrast.
- **Signature:** the visible boss sprite at the shared center of two labeled,
  concentric encounter rings, with an optional line to the guarded chest.
- **Defaults rejected:** an invisible data-only record is replaced by an in-map
  sprite; a generic modal is replaced by the established right inspector; one
  undifferentiated boundary is replaced by two purpose-labeled rings.

The implementation reuses the editor's established border-led, low-clutter
visual language, spacing, and typography. No unrelated design system is added.

## Chosen approach

Add a first-class boss-camp editing path alongside the existing enemy-area and
NPC-area paths. Boss camps remain top-level map records because they combine a
boss definition reference, spatial areas, respawn policy, and an optional chest
relationship. The boss sprite is an editor preview, not an ordinary object.

Alternatives rejected:

1. **Encode the boss as an object.** This would make the sprite easy to select,
   but would split one encounter across object and camp records and undermine
   the current map format.
2. **Fold bosses into Enemy Area.** This would reuse more UI, but ordinary camps
   have weighted populations and refill intervals while bosses have one spawn,
   two areas, a defeat timer, and guarded loot. Combining them would make both
   concepts harder to author.

## Map contract

The existing `MapBossCamp` record remains authoritative, with one contract
change: `guardedChestInstanceId` becomes optional.

```ts
interface MapBossCamp {
  id: string;
  bossId: string;
  activationPerimeter: CirclePerimeter;
  arenaPerimeter: CirclePerimeter;
  spawn: MapPoint;
  respawnMs: number;
  guardedChestInstanceId?: string;
}
```

Both perimeters must be circles for this authoring slice. They share the boss
spawn as their center. The arena radius must not exceed the activation radius.
The runtime continues to read the same records; an absent guarded chest simply
means no chest is locked by that camp.

Map schema, runtime parsing, reference validation, repository checking, and
browser-side reference resolution must accept the optional chest and enforce
the circular, co-centered area rules. Level 1's current rectangular bounds are
replaced deterministically with a 416 px activation radius and a 320 px arena
radius, both centered on Fatty's existing spawn at (2528, 1472).

Map resizing follows the editor's existing coordinate semantics:

- changing tile size uniformly scales boss spawn coordinates and both radii by
  the tile-size ratio;
- changing only row or column counts leaves boss coordinates and radii intact;
- combined dimension and tile-size changes perform the uniform tile-size scale
  first; and
- any resize that would leave the spawn or either full circle outside the new
  map is rejected rather than silently clamped or repositioned.

## Creation and selection

The toolbar gains **Boss Camp**. Activating it changes the status copy to explain
that one click places a boss spawn. Clicking a valid map position:

1. creates a unique camp ID;
2. selects the first catalog boss, currently Fatty One Eye;
3. uses the clicked tile center as the spawn and both circle centers;
4. creates a 416 px activation radius and a 320 px arena radius;
5. sets a 180-second respawn;
6. leaves the guarded chest unset; and
7. selects the new camp and opens its inspector state.

Boss sprites remain visible in every editor tool so authored encounters never
disappear from the map. Clicking a boss sprite first applies the existing
unsaved object-template guard used when changing ordinary object selection. If
the creator cancels that template discard, selection does not change. Otherwise
the active object template context is cleared, while
`GameplayAttributeEditorState.workingDrafts` remains untouched exactly as it
does across ordinary object selection changes. Map Studio then switches to
**Boss Camp** mode and selects the camp. Dragging the selected sprite moves the
spawn and both circle centers together. Movement is one undoable command.

Delete or Backspace removes only the selected camp after the editor's existing
selection rules. Any formerly guarded chest remains an ordinary map object.
Undo restores the camp and its chest reference.

## Canvas overlays

The boss/content boundary exposes a catalog-driven preview descriptor:

```ts
interface BossEditorPreview {
  assetId: AssetId;
  textureKey: string;
  frame: number;
  origin: readonly [number, number];
  scale: number;
}
```

Each boss definition owns its preview asset ID and front-facing idle frame.
The catalog combines those fields with the manifest-owned runtime texture key
and origin plus the definition-owned visual scale. Both the runtime boss and
Map Studio consume that descriptor, removing Fatty-specific asset lookup from
editor rendering. The preview remains editor-only and is not placed in
`map.objects`.

Camp overlays appear only while **Boss Camp** is active:

- activation circle: cyan, low-opacity fill, labeled “Activation” and its radius;
- combat arena: amber, slightly stronger fill, labeled “Arena” and its radius;
- boss spawn: selected gold anchor treatment around the preview sprite;
- guarded chest: a restrained gold connector from the boss center to the chest,
  shown only when a valid chest is assigned; and
- resize handles: distinct handles on each circle, shown for the selected camp.

The two circles remain centered on the boss. Dragging an activation handle edits
only activation radius. Dragging an arena handle edits only arena radius. Exact
values can also be entered in the inspector. The arena can never be enlarged
beyond activation; invalid pointer or numeric edits are rejected with clear
status feedback.

## Right inspector

Selecting a boss camp makes `MapEditorInspector`, the existing right-hand
inspector surface, authoritative for:

- stable camp ID, displayed read-only after creation;
- boss type, selected from the boss catalog;
- spawn X and Y;
- activation radius;
- arena radius;
- respawn time in seconds, persisted as milliseconds;
- optional guarded chest, selected from chest instances on the current map; and
- delete camp.

Changing spawn X or Y moves both circle centers. The guarded-chest control has a
clear **None** option. A chest already assigned to another camp is unavailable
or disabled. Missing referenced content is shown as an error and cannot be
silently saved.

Boss-definition properties such as HP, attack timings, weak-point geometry, and
immunities are summarized only if useful for recognition; they are not editable
from Map Studio.

Boss-camp selection and object-template selection are mutually exclusive.
`MapEditorInspector` renders either the current boss-camp form or its existing
object template/gameplay content, never both. A pending object draft must be
explicitly discarded through the existing confirmation guard before a boss can
replace that inspector context. Dirty gameplay-attribute drafts are preserved
in their existing per-object working-draft store; boss selection neither
prompts for nor discards them, so returning to that object restores its draft.

## State and architecture

`MapEditorState` gains first-class boss-camp selection and mutations:

- select a camp;
- create a camp from a spawn point;
- update boss, spawn, radii, respawn, or chest;
- move a camp while preserving relative ownership;
- delete a camp without deleting objects; and
- normalize boss camps after load and uniformly scale them only when tile size
  changes.

Every mutation uses the existing serialized undo/redo mechanism. Switching away
from **Boss Camp** clears only boss-camp selection. Object, exit, enemy-area,
safe-zone, and NPC-area selections keep their existing mutual-exclusion rules.

`MapEditorScene` owns preview sprites, hit testing, drag gestures, circle
overlays, and resize handles. `MapEditorPanel`, the left control surface, owns
only the **Boss Camp** tool button and compact camp count/status. The existing
right-side `MapEditorInspector` owns exact property inputs and camp deletion.
Boss preview lookup stays in the boss/content boundary rather than being
hard-coded to Fatty inside editor rendering.

## Validation and error handling

A boss camp is invalid when:

- its ID is missing or duplicated;
- its boss ID is not in the boss catalog;
- its spawn or circle extends outside the authored map;
- either perimeter is not a positive-radius circle;
- a circle center differs from the spawn;
- arena radius exceeds activation radius;
- respawn time is not a positive integer;
- its optional chest does not exist or is not a chest; or
- its optional chest is already guarded by another camp.

Creation or editing that would produce invalid geometry is rejected before map
mutation. External malformed JSON still reports field-specific errors through
the map parser and repository checker.

## Testing and acceptance

Focused Map Studio tests cover:

1. loading Level 1 renders a selectable Fatty preview;
2. one-click creation uses the approved circular defaults;
3. boss selection does not masquerade as object selection;
4. dragging the boss moves spawn and both circle centers;
5. activation and arena radii edit independently;
6. arena radius cannot exceed activation radius;
7. inspector changes are undoable and survive redo;
8. guarded chest is optional and only current-map chests can be selected;
9. deleting a camp preserves its chest;
10. map resizing scales spawn and both radii;
11. save/reload preserves the complete camp record; and
12. existing object, enemy-area, NPC-area, and chest tests remain green.

Repository acceptance requires `pnpm maps:check`, focused Map Studio tests,
`pnpm typecheck`, and `pnpm build`. Manual acceptance opens Level 1, confirms
Fatty is visible, selects and moves him, edits both radii separately, clears and
restores the chest assignment, saves, reloads, and observes the same map data.
