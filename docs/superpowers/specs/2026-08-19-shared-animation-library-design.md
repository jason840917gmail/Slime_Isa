# Shared Animation Library and Weapon Studio Browser

**Status: approved design; implementation has not started.** This document
supersedes the Object Studio animation direction in
`2026-08-19-object-studio-animations-design.md`. Object Studio will be
removed rather than extended.

## Goal

Create one reusable library of complete layered animations. Weapon Studio is
the first authoring surface for that library, while weapons and map objects
reference animations by stable ID. Map-authored objects can therefore use the
same animation runtime as weapons without embedding animation documents or
depending on filesystem paths.

## Ownership and boundaries

- **Animation library** owns complete layered animation packages: timing,
  looping, visual layers, source assets, transforms, validation, and stable
  IDs.
- **Weapon Studio** owns authoring and browsing both weapon definitions and
  shared animation packages. It does not make shared animations weapon-only.
- **Weapon definitions** own combat values, character action IDs, directional
  hitboxes/tracks, and references to animation IDs.
- **Object templates** own the optional `idleAnimationId` and
  `onHitAnimationId` references. These values are shared by every instance of
  the same object visual.
- **Map Studio** owns placement and object-template geometry. It provides a
  searchable animation picker but does not contain a second animation editor.
- **Runtime adapters** resolve IDs through the shared catalog and provide
  world anchors. The shared animation clock, layered renderer, and transforms
  remain in `src/game/shared/animation`.
- **Resource effects** remain a separate concern. An object's
  `onHitAnimationId` animates the object itself; a resource `hitEffectId`
  remains a reusable world-space feedback effect.

## Content model

Each animation package is a real directory containing `animation.json`:

```text
src/game/content/animations/
  objects/resources/tree-idle/animation.json
  objects/resources/tree-hit/animation.json
  weapons/wooden-axe/idle/animation.json
  weapons/wooden-axe/attack-right/animation.json
```

The package wrapper adds searchable metadata to the existing layered document:

```json
{
  "$schema": "../../../animation-package.schema.json",
  "version": 1,
  "animationId": "object.tree.idle",
  "displayName": "Tree Idle",
  "description": "Subtle movement for pine trees.",
  "animation": {
    "version": 2,
    "durationSeconds": 1,
    "framesPerSecond": 8,
    "loop": true,
    "loopMode": "wrap",
    "layers": [
      {
        "layerId": "canopy",
        "displayName": "Canopy",
        "assetId": "sheet.trees.8x6",
        "depthOffset": 0,
        "blocks": [{ "from": 0, "through": 7, "sourceFrame": 24 }]
      }
    ]
  }
}
```

`src/game/content/animations/animation-package.schema.json` owns the package
wrapper and embeds the layered-animation shape; there is no second path or
schema interpretation for a package. The nested `animation` value is
validated with the existing layered animation validator and asset catalog.
Runtime packages require at least one valid visual layer and one block in that
layer; an empty-layer draft is permitted only in the editor and cannot be
saved. Package `version` is exactly `1`; unknown versions fail validation
instead of being guessed or silently migrated.
The package schema requires non-empty `displayName` and `description` strings;
those fields are not optional presentation hints.

`animationId` is globally unique and must match
`^[a-z0-9]+(?:[.-][a-z0-9]+(?:-[a-z0-9]+)*)+$`. Package and folder names on
disk must match `[a-z0-9][a-z0-9-]*`. A directory is an animation package only when it
contains exactly one `animation.json`; ordinary folders cannot contain an
`animation.json` child alongside another package with the same discovered ID.
Folder location is discovered from the real path and is not duplicated in
runtime data. Because the local `$schema` value is relative to the package
file, a folder move rewrites that value for the destination depth in the same
atomic operation; package content is never left pointing at a stale schema.
Animation layer `assetId` values always reference the global `asset/assets.json`
catalog; animation packages do not carry package-local image files in this
slice. Asset registration remains the existing Weapon Studio workflow, and a
package with an unknown global asset is invalid.

Maps and definitions store only IDs. Moving a package between folders does not
change a reference; changing an ID is an explicit migration operation. The
runtime virtual content module and the Vite authoring catalog both discover
every package recursively. They are authoritative over the same sorted file
set and reject duplicate IDs, malformed packages, unknown assets, invalid
layered timelines, and unsafe paths. A malformed package fails the whole
catalog/build with a structured package-path and animation-ID diagnostic; it
is never silently omitted from a partial catalog. The authoring endpoint may
return that diagnostic without writing anything, while production content
cannot build until the package is corrected.

## Weapon references and migration

The layered weapon shape is migrated without moving combat ownership:

- `animations.idle` becomes `animations.idleAnimationId`.
- Each directional attack's embedded `animation` becomes `animationId`.
- Directional `characterActionId`, hitboxes, and attack tracks remain on the
  weapon because they describe combat behavior, not reusable artwork.
- The same animation ID may be referenced by multiple directions or weapons.
- Existing embedded layered documents are extracted into packages with stable
  IDs before the weapon definitions are rewritten.

The deterministic migration algorithm is:

1. For each weapon ID, extract idle as `weapon.<weapon-id>.idle` and each
   authored direction as `weapon.<weapon-id>.attack.<direction>`.
2. Sanitize each weapon ID with `slugSegment`: lowercase it, replace every
   run of non-alphanumeric characters with one hyphen, trim leading/trailing
   hyphens, and abort if the result is empty. Use the exact IDs
   `weapon.<slug>.idle` and `weapon.<slug>.attack.<direction>`; preserve a
   checked mapping file containing source weapon path, source field,
   destination package path, and destination ID.
3. Do not deduplicate documents automatically. If a destination ID already
   exists with identical canonical JSON, reuse it; if it differs, abort the
   migration with a collision diagnostic.
4. Convert object visual-set/clip references with this complete mapping:
   `object.tree.world + snow-pine-idle` becomes
   `object.tree.idle` at `objects/tree/idle/animation.json`; every other
   object pair becomes
   `object.<slug-object-id>.<slug-visual-id>.<slug-clip-id>` at
   `objects/<slug-object-id>/<slug-visual-id>-<slug-clip-id>/animation.json`.
   A pair with an invalid or empty slug aborts the migration. Character package
   visual sets remain on their existing Character Studio path.
5. Validate every rewritten weapon/object reference against the generated
   catalog before replacing any source file. Write all package and definition
   changes through a staged transaction; a failure removes the stage and
   leaves the legacy files untouched.

The migration fixture records every old field and new ID so it can be audited
or rolled back before the legacy reader is removed.

Weapon runtime resolution fails closed for optional visual packages: a missing
animation produces a development diagnostic and keeps the static/base visual
visible. Required combat fields remain validation errors.

## Weapon Studio experience

The left panel becomes a file-explorer library with two expandable roots:

```text
Search weapons and animations…   [All | Weapons | Animations]

WEAPONS
  starter/
    wooden axe
    pickaxe

ANIMATIONS
  weapons/
    wooden-axe/
      idle
      attack-right
```

Folders are expandable/collapsible and animation files display their name,
stable ID, description, and type badge. Search matches display name, ID,
description, and path; matching files remain discoverable even when their
parent folder was previously collapsed. Selecting a weapon opens the existing
weapon editor. Selecting an animation opens the shared layered timeline
editor.

The first authoring slice supports creating folders, creating animations,
editing metadata, duplicating, moving, and deleting with reference warnings.
It reuses the existing layered timeline, layer inspector, source-asset picker,
preview, and validation components rather than cloning them. A shared
animation-editor state boundary is extracted from `LayeredWeaponStudio` so a
standalone package does not need a fake weapon wrapper.

Moving a package changes only its on-disk folder and leaves its ID and all
references unchanged. Metadata rename does not change the ID. Duplicate
creates a new package and requires a new ID. ID editing is intentionally
disabled in the first slice. Deleting a referenced package is blocked and
lists every referencing weapon/object field; there is no force-delete path.
Each operation stages the package and any rewritten `$schema` value and commits
by atomic rename; the catalog has no persisted index. It is always derived by
recursive discovery, so an interrupted operation leaves the previous package
intact.

## Map Studio picker and object fields

The shared object-template inspector adds two optional fields:

```ts
idleAnimationId?: string;
onHitAnimationId?: string;
```

Each field shows the selected package name/ID and has Browse and Clear actions.
Browse opens a reusable animation-picker dialog containing the same folder
tree, global search, description, preview, None option, and validation state
used by Weapon Studio. A native `<select>` is intentionally not used because
it cannot represent nested folders, descriptions, previews, or a growing
library without becoming unwieldy.

The parent Map Studio inspector owns template saving. Selecting **None** clears
the optional field; selecting a package writes its stable ID. A non-empty
stale or invalid ID is a save-blocking content error in Map Studio, while
runtime fallback remains available for already-authored legacy data. The
picker never writes map or object files by itself.

Slot compatibility is validated at save time: an idle selection must reference
a looping package, while an on-hit selection must reference a non-looping
package. This prevents a valid package with the wrong playback contract from
silently trapping an object in its hit state.

The fields are edited on the shared object template, not on individual map
instances. Saving changes all existing and future instances that use that
object visual after the normal authored-content reload.

## Runtime object behavior

`ObjectFactory` creates a stable static image/physics anchor first, then
optionally attaches an object animation adapter. The adapter receives an
`AnimationDefinitionResolver`, the static image anchor, and an
`AnimationClock` that it owns. `ObjectFactory.update(deltaMs)` advances every
live adapter; `WorldScene` and `MapEditorScene` call that update from their
scene update loop. The adapter passes the object's anchor position, authored
scale/origin, and current world depth to `LayeredAnimationVisual`.

The shared resolver and damage notification contracts are:

```ts
interface AnimationDefinitionResolver {
  get(animationId: string):
    | { readonly ok: true; readonly animation: NormalizedLayeredAnimationDocument }
    | { readonly ok: false; readonly diagnostic: {
        readonly code: 'animation-reference-missing' | 'animation-package-invalid';
        readonly animationId: string;
        readonly message: string;
      } };
}

interface AcceptedObjectDamageEvent {
  readonly target: Phaser.GameObjects.Image;
  readonly acceptedDamage: number;
  readonly onHitAnimationId?: string;
  /** Snapshot of the resource content field named `hitEffectId`. */
  readonly resourceHitEffectId?: string;
  readonly depleted: boolean;
}
```

`ResourceNodeController` returns this event data after it has accepted damage,
snapshotting both animation/effect IDs before a depleted node is removed.
The runtime event uses `resourceHitEffectId` to distinguish that snapshot from
the object's `onHitAnimationId`; the authored resource field remains
`resourceNode.hitEffectId`. Non-resource damageable objects emit the same
event with that field omitted.
`CombatController` dispatches the object adapter callback and the separate
world hit effect from that same result, before destruction is finalized. Other
damageable objects use the same `AcceptedObjectDamageEvent` shape. The event
is the only path that may call `animateOnHit`, and callers ignore events whose
`acceptedDamage` is zero or whose target adapter has already been disposed.

The adapter exposes:

```ts
animateIdle(animationId: string | undefined): void;
animateOnHit(animationId: string | undefined, onComplete?: () => void): boolean;
dispose(): void;
```

`AnimationDefinitionResolver.get(animationId)` returns a normalized package or
an undefined result plus a diagnostic. The adapter ignores calls after
`dispose()`, and object destruction disposes the adapter before its anchor is
removed. The positive-damage resource result is the authoritative event gate:
only `acceptedDamage > 0` may call `animateOnHit`.

Behavior:

1. If an idle ID resolves, it loops continuously. If it is absent or invalid,
   the static visual remains visible. When a valid layered animation is active,
   the static image is hidden and the layered sprites own presentation; the
   static image is restored whenever the adapter returns to fallback mode.
2. A resource/object hit calls `animateOnHit` only after positive damage has
   been accepted by the resource damage system.
3. On-hit playback restarts from frame zero for every successful hit. It is
   non-looping and returns to the resolved idle animation, or the static image
   when no idle exists, after completion.
4. Zero-damage collisions do not play the on-hit animation.
5. A missing or invalid on-hit package never destroys the object or hides its
   static visual. Development builds report the object ID and animation ID.
6. Replacing or destroying an object disposes its adapter and all generated
   animation sprites, preventing orphaned layers.

For a successful final resource hit, depletion state and drops are committed
immediately and the resource collider/interactions are disabled. Replacement
of the depleted object is deferred until the non-looping on-hit animation
calls `onComplete`; if no valid on-hit package can start, replacement happens
immediately. If the scene or object is destroyed first, the adapter disposes
and the pending replacement finalizes once. This prevents extra hits while
preserving final-hit feedback.

An invalid idle plus valid on-hit combination therefore renders the static
image until a successful hit, plays the valid on-hit package, and returns to
the static image. An invalid on-hit package never hides the static image.

The resource-owned world hit effect remains dispatched separately from the
positive-damage result and does not replace the object's own on-hit animation.

## Reverting Object Studio

Before the new authoring flow is enabled, remove only the Object Studio slice:

- the `?studio=objects` route and `ObjectStudio` UI/CSS;
- Object Studio navigation links and studio-tab entry;
- `/__object-studio/catalog` and `/__object-studio/save` endpoints;
- Object Studio-specific docs and status notes.

Preserve unrelated stone gathering, pickaxe, resource damage, material hit
effect, map geometry, and existing Weapon/Character Studio changes. Existing
object visual-set/clip references are migrated to animation IDs as part of the
shared package extraction rather than silently discarded.

## Error handling and persistence

- Authoring catalogs return structured errors for unreadable directories,
  malformed JSON, duplicate IDs, invalid assets, and invalid animation docs.
- Diagnostics use stable codes (`animation-package-invalid`,
  `animation-id-duplicate`, `animation-asset-invalid`,
  `animation-reference-missing`, `animation-slot-loop-mismatch`, and
  `animation-reference-in-use`) and include the package path, animation ID,
  and reference field whenever those values exist.
- Save operations validate the complete package and all changed references
  before atomically replacing files. Failed saves leave the previous content
  untouched.
- The picker disables Save for an invalid selection and identifies the exact
  package/field causing the error.
- Runtime fallback is static-image-first for optional animation failures.
- Browser listeners, playback clocks, dialogs, and preview sprites are
  disposed when a studio or scene closes.

## Implementation slices

1. Define the package schema, content types, recursive catalog, virtual module,
   validators, and focused package checks while the legacy references still
   load.
2. Run the deterministic extraction/migration preflight for current weapon
   and object packages, validate every rewritten reference, and keep the
   temporary legacy reader until the migrated catalog is confirmed. The
   migration mapping is stored at
   `scripts/migrations/animation-id-map.json` and is the rollback/audit record.
3. Extract current weapon layered documents and tree idle content into shared
   animation packages; migrate weapon/object references and runtime resolution.
4. Extract a standalone layered animation editor state from Weapon Studio and
   add the two-section file explorer, folder operations, search, and package
   save flow.
5. Add the reusable animation picker to Map Studio and add template-level
   object animation IDs.
6. Add the object animation adapter, positive-damage on-hit dispatch, idle
   fallback, completion return, replacement cleanup, and map preview support.
7. Remove Object Studio route, UI, CSS, links, endpoints, and superseded
   implementation notes only after the migration and compatibility read pass.
8. Update architecture/docs and add focused tests for package validation,
   references, picker behavior, runtime fallback, repeated successful hits,
   and zero-damage silence.

## Acceptance criteria

- Object Studio is no longer a route or navigation option.
- Weapon Studio can browse weapons and shared animations in real nested
  folders, search by name/ID/description, create a package, and edit its full
  layered timeline.
- Existing weapons preserve their idle/attack visuals and combat tracks after
  migration to animation IDs.
- Map Studio can assign, clear, search, preview, and save object idle/on-hit
  animation IDs at the shared-template level.
- Objects with no animation render their static image exactly as before.
- Objects with valid idle packages loop; valid on-hit packages play once only
  after positive damage and return to idle/static.
- Missing packages, malformed references, zero-damage hits, object replacement,
  and scene shutdown are handled without hidden sprites or uncaught errors.
- A final positive resource hit disables further interaction, completes its
  on-hit animation when valid, and then replaces the depleted object exactly
  once; invalid/missing on-hit content falls back to immediate replacement.
- Animation packages resolve only global manifest assets; an unknown asset is
  rejected by content validation and covered by a focused catalog test.
- Moving a package across folder depths rewrites its relative `$schema` path
  and leaves its ID/references unchanged; unsupported weapon/object IDs abort
  migration with an audit diagnostic.
- TypeScript, build, content validators, map checks, animation tests, weapon
  tests, and combat tests pass.
