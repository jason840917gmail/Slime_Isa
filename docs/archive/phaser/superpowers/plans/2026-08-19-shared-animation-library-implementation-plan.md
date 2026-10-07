# Shared Animation Library and Weapon Studio Implementation Plan

## Status

Implemented following the approved shared animation library design. Object
Studio has been withdrawn. Its authoring route, UI, CSS, navigation, and Vite
endpoints are removed; migrated object and weapon content now resolves shared
animation packages by stable ID.

## Outcome

Build one reusable catalog of complete layered animation packages. Weapon
Studio is the first authoring surface. Weapon definitions and object templates
store stable animation IDs, while runtime adapters resolve those IDs through a
single catalog and use the existing shared animation clock, layered renderer,
and transforms.

The implementation must preserve static-object fallback, existing weapon
combat ownership, resource-owned `hitEffectId` feedback, authored map geometry,
and current Character Studio behavior while the migration is staged.

## Boundaries and invariants

- `src/game/shared/animation` owns timing, frame resolution, layered rendering,
  transforms, and playback lifecycle.
- `src/game/content/animations` owns package files, package metadata, stable IDs,
  and package-level validation.
- Weapon definitions own damage, actions, hitboxes, directional tracks, and
  references to animation IDs; they do not own reusable animation documents
  after migration.
- Object templates own optional `idleAnimationId` and `onHitAnimationId`.
  Resource `hitEffectId` remains a separate world-space material effect.
- Map Studio owns placement and geometry and receives a picker, not a second
  animation editor.
- Optional animation failures are static-image-first at runtime. No missing or
  malformed package may hide the required base visual.
- Package discovery is recursive and derived from files; no persisted index is
  introduced.
- Every save that changes package content or references validates the complete
  affected catalog before an atomic commit.

## Work sequence

### 1. Define the package contract and catalog

Add the package wrapper schema and TypeScript types:

- `src/game/content/animations/animation-package.schema.json`
- `src/game/content/animations/types.ts`
- `src/game/content/animations/validation.ts`
- `src/game/content/animations/AnimationCatalog.ts`
- `src/game/content/animations/virtual-animation-content.ts`
- package discovery/build integration alongside the existing virtual content
  plugins

The validator must enforce package version `1`, non-empty `displayName` and
`description`, the global animation-ID pattern, safe package/folder names,
exactly one `animation.json` per package directory, valid nested layered
documents, at least one non-empty runtime visual layer, and asset IDs present in
`asset/assets.json`. Duplicate IDs, malformed JSON, unsafe paths, unknown
assets, and invalid timelines fail the whole catalog with structured
diagnostics.

Add focused catalog tests for valid packages, duplicate IDs, malformed
packages, unknown assets, invalid empty layers, recursive discovery, and
relative `$schema` rewriting when a package moves between folder depths.

### 2. Build a deterministic migration preflight

Create a staged migration tool and audit record:

- `scripts/migrate-animation-packages.mjs`
- `scripts/migrations/animation-id-map.json`
- focused migration tests under `scripts/tests/animation-packages/`

For each weapon, extract idle and authored directional attacks to
`weapon.<slug>.idle` and `weapon.<slug>.attack.<direction>`. For object visual
set/clip pairs, use the specified tree special case and general
`object.<object>.<visual>.<clip>` IDs. Sanitize IDs with the prescribed
`slugSegment` algorithm and abort on empty slugs or differing destination
collisions.

The tool must write to a staging directory, validate every generated package
and rewritten reference against the complete catalog, then atomically replace
the staged files. Any failure removes only the staging directory and leaves
legacy files untouched. The mapping records source path, source field,
destination path, destination ID, and canonical reuse/collision decisions.

Keep the temporary legacy reader until the migrated catalog and all references
are confirmed.

### 3. Extract current content and migrate references

Generate packages for current weapon documents and tree idle content, then
rewrite weapon/object references:

- weapon `animations.idle` → `idleAnimationId`
- directional attack `animation` → `animationId`
- object visual-set/clip references → object template animation IDs

Do not move combat tracks, hitboxes, character actions, resource fields, or
effect ownership into the package. Add compatibility normalization only for
the migration window, then remove the legacy reader after the read pass.

Verify existing weapon previews, runtime visuals, attack timing, and direction
inheritance before deleting embedded animation fields.

### 4. Extract standalone animation editor state

Create a shared editor state boundary from the current layered Weapon Studio
implementation:

- `src/game/editor/SharedAnimationDocumentState.ts`
- reusable package metadata/form state and package save helpers
- reusable animation picker/tree model
- existing timeline, block inspector, source picker, preview, and validation
  components remain the shared visual/editor primitives

The state must edit a package without manufacturing a weapon definition. Then
extend Weapon Studio’s left library into expandable `WEAPONS` and
`ANIMATIONS` roots with search across display name, ID, description, and path.

Implement package operations in staged transactions: create folder/package,
edit metadata, duplicate with a new ID, move with `$schema` rewrite, and delete
only when no weapon/object field references the package. ID editing is disabled
in the first slice. Reference warnings must list every referencing field.

Add editor tests for nested discovery, collapsed-folder search visibility,
metadata-only rename, duplicate/new-ID rules, move behavior, delete blocking,
and invalid package save diagnostics.

### 5. Add Map Studio object animation references and picker

Extend object-template content types, schema, validator, virtual content, and
Map Studio inspector with:

```ts
idleAnimationId?: string;
onHitAnimationId?: string;
```

Add a reusable picker dialog that supports folder tree, global search,
description, preview, None, and validation state. The picker writes only to the
parent Map Studio draft; template save remains the single persistence action.

At save time, validate that IDs exist and that idle packages loop while on-hit
packages do not. Report stable diagnostics including package path, animation ID,
and the object-template field. Keep stale legacy references readable at runtime
with static fallback while authored saves block invalid new references.

### 6. Add object runtime adapters and damage dispatch

Implement shared resolver and object adapter contracts in the object feature:

- `AnimationDefinitionResolver`
- `ObjectAnimationAdapter`
- `AcceptedObjectDamageEvent`

`ObjectFactory` creates the static image/physics anchor first. If idle resolves,
the adapter owns layered sprites and hides the static image only after setup
succeeds. `animateOnHit` restarts at frame zero, plays once, and returns to
idle/static on completion. Calls after disposal are ignored; all generated
sprites and clocks are cleaned up on replacement and scene shutdown.

Update `ObjectFactory.update(deltaMs)` and the world/map editor update loops to
advance live adapters. `ResourceNodeController` must snapshot both object
`onHitAnimationId` and resource `hitEffectId` before depletion removes the
record. `CombatController` dispatches object on-hit animation and separate
world effect only for accepted positive damage. Zero-damage collisions remain
silent.

For final resource hits, commit depletion and disable interaction immediately,
defer replacement until valid on-hit completion, and finalize exactly once on
missing/invalid animation, adapter disposal, or scene destruction.

Add focused runtime tests for idle fallback, valid looping idle, invalid idle +
valid on-hit, missing on-hit, repeated positive hits, zero damage, final-hit
replacement, adapter disposal, and scene shutdown.

### 7. Remove the compatibility boundary and update documentation

After migration and the compatibility read pass:

- remove the temporary legacy animation reader and migration-only branches;
- remove obsolete visual-set object animation references from object content;
- update architecture, studio contract, roadmap, and content-check docs;
- keep `resourceNode.hitEffectId`, material effect packages, map geometry, and
  unrelated Character/Weapon Studio workflows intact.

The withdrawn Object Studio remains absent: no route, tab, link, CSS, endpoint,
or status note is reintroduced.

## Verification gates

Run the narrowest relevant gate after each slice, then the full sequence:

1. package/catalog and migration tests;
2. `pnpm assets:check`;
3. `pnpm maps:check`;
4. `pnpm test:animation` plus weapon, combat, and new package/object tests;
5. `pnpm typecheck`;
6. `pnpm build`;
7. `pnpm check` before handoff.

The final acceptance pass must confirm that Object Studio is not discoverable,
current static objects render unchanged, migrated weapons preserve visuals and
combat tracks, Map Studio saves only valid animation IDs, and object animation
failures never leave hidden anchors or orphaned layered sprites.

## Current cleanup completed

- Deleted `src/game/editor/ObjectStudio.ts` and
  `src/game/editor/object-studio.css`.
- Removed `/__object-studio/catalog` and `/__object-studio/save` from
  `vite.config.ts`.
- Removed Map Studio’s Object Studio navigation and edit link.
- Removed the superseded Object Studio spec/status documentation.
- Removed obsolete object visual-set animation fields and the migrated tree
  visual-set package; resource hit-effect fields remain separate.
