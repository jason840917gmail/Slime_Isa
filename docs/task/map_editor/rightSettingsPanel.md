# Map editor: right-side object template inspector

> **Status: Completed for v1.** The reusable template inspector, grouped Object Content palette, independent draft state, live previews, responsive layout, and atomic update persistence are implemented and verified. Duplicate visual templates and cloned object definitions remain explicitly tracked as follow-up creation workflows.

## Goal

Add a right-side template inspector to the development-only map editor. It lets a level designer select a reusable object template from **Object Content**, preview its geometry on the canvas, and edit the template's visual alignment and collider.

The inspector does not edit placed map instances. Every saved template change affects all existing and future map instances that reference the same `objectId + visualId`.

The workflow must support two different creation operations:

- **Duplicate visual template**: create another `visualId` under the same object archetype. The new template may reuse the same artwork while owning an independent display name, collider, and visual offset.
- **Clone object definition**: create a new object archetype and JSON file when physics, behavior, destructibility, tags, or the available visuals may need to diverge later.

These operations must remain distinct. A collider variation should not require a new gameplay archetype.

## Implementation resume

The completed v1 implementation now provides:

- Template-only editing selected from **Object Content**; placed map instances remain map-editing concerns.
- Artwork grouping by `assetId + frame`, with sibling display names, visual IDs, and collider summaries.
- A compact right inspector with read-only identity metadata, display-name editing, visual offset controls, collider controls for solid objects, shared-impact warning, reset, save, and responsive close/reopen behavior.
- Independent template draft state and navigation protection, separate from map undo/redo and map save state. Invalid numeric drafts remain visible in the field while the canvas keeps the last valid geometry.
- Shared runtime/editor rendering with fixed map anchors, offset artwork, preserved collider world position, matching-instance overlays, and a focused fallback preview when no instance is visible.
- Optional `displayName` and `visualOffset` schema/model support, server-side validation, and the development-only `/__map-editor/object-template/update` endpoint with atomic JSON replacement.
- Browser smoke coverage for wide and narrow layouts, inspector drawer behavior, grouped sibling selection, invalid draft handling, solid collider editing/reset, and valid/invalid persistence responses.

Validation completed with `pnpm check`, which passed asset, object, map, type, and production-build checks.

The remaining creation workflows are not part of the completed v1 slice: duplicate visual template, clone object definition, dynamic object catalog discovery, shared Node validation extraction, and their expanded browser coverage remain follow-up work.

## Definition ownership

Object definitions under `src/game/content/objects/` are the source of truth for reusable object behavior and presentation.

Definition fields have three ownership levels:

| Owner | Fields | Purpose |
| --- | --- | --- |
| Object archetype | `objectId`, `physics`, `behavior`, `destructible`, `tags` | Gameplay properties shared by every template in the definition |
| Variant group | `assetId` | Media source shared by its frame templates |
| Visual template | `visualId`, `displayName`, `frame`, `visualOffset`, `collider` | Reusable appearance and geometry selected by maps |

The stable template identity is `objectId + visualId`. Maps continue to store that identity with instance placement and optional typed state. Template properties must never be copied into map instances.

`asset/assets.json` remains responsible for media-loading metadata such as paths, dimensions, texture keys, and default render origin. Object-specific visual alignment belongs in the object definition because it describes how a reusable game object uses that media.

## Current constraints

- The editor has a 328 px left panel, a flexible canvas, and a compact 180 px inspector rail on wide screens; narrow screens use a 240 px closable drawer.
- A map object stores `instanceId`, `objectId`, `visualId`, `x`, `y`, and optional `initialState`.
- Object colliders are frame-specific values in JSON object definitions.
- Solid object templates require a collider. Decorative templates must not have one.
- `scripts/check-objects.mjs` validates object files, asset/frame references, and collider bounds.
- The editor renders objects with physics disabled, so it needs an explicit collider overlay for template previews.
- Terrain definitions use a different model in `TileCatalog.ts` and are outside this task.

## Template data model

Extend each object frame template with optional `displayName` and `visualOffset` fields:

```json
{
  "visualId": "wood-fence-narrow",
  "displayName": "Narrow Passage",
  "frame": 0,
  "visualOffset": { "x": -4, "y": 2 },
  "collider": {
    "width": 72,
    "height": 20,
    "offsetX": 28,
    "offsetY": 72
  }
}
```

### Display name

- `displayName` is the human-readable template name shown beneath an artwork thumbnail.
- It is optional for backward compatibility.
- When omitted, the editor derives a title from `visualId`.
- `visualId` remains the unique stable identifier used by maps and runtime resolution.
- Duplicating a template requires a new display name and a unique `visualId`. The editor generates a slug from the name and lets the user adjust it before creation.

### Visual offset

- `visualOffset.x`: horizontal art offset in unscaled source-frame pixels; positive moves the art right.
- `visualOffset.y`: vertical art offset in unscaled source-frame pixels; positive moves the art down.
- The default is `{ "x": 0, "y": 0 }` when omitted.
- Both values must be integers.
- The offset is applied after resolving the asset's render origin.

This is a visual-only offset. It must not change:

- stored map `x` or `y`;
- the map anchor or snapping semantics;
- the collider's world-space rectangle;
- depth-ordering semantics.

The runtime and editor must use the same object-rendering implementation. If a single Phaser image cannot keep the anchor and body fixed while moving only the art, introduce a small body/visual composition with the image as an offset child.

### Collider

The collider remains expressed in unscaled source-frame pixels:

```json
{
  "width": 42,
  "height": 16,
  "offsetX": 28,
  "offsetY": 59
}
```

It must satisfy:

```text
width >= 1
height >= 1
offsetX >= 0
offsetY >= 0
offsetX + width <= frame width
offsetY + height <= frame height
```

## Product decisions

### Scope for the first version

The first version edits visual-template geometry only:

- optional display name;
- visual offset;
- collider.

Object-level physics, behavior, destructibility, and tags are visible but read-only. Asset ID and frame index are also read-only when editing an existing template.

The first version does not edit map placement, `instanceId`, `initialState`, terrain definitions, or arbitrary object-level gameplay properties.

### Selection behavior

- Selecting an artwork or template in **Object Content** opens the template inspector. A placed map object is not required.
- Selecting a placed object with **Select / Move (`V`)** continues to support map manipulation but does not open or change the template inspector.
- Clicking an artwork thumbnail selects its default template. Clicking one of its named siblings selects that exact `visualId`.
- If no palette template is selected, show: “Select an object template from Object Content to edit its shared definition.”
- Changing map tools may leave the palette template selected.
- Template overlays remain visible while the inspector is open, regardless of the active map tool, but must not intercept canvas input.
- Switching templates with an unsaved draft requires confirmation to discard the draft or remain on the current template.

### Global impact

Show a persistent notice above editable controls:

> Shared template — saved changes affect every existing and future map object using this template.

During preview and after save, update every visible instance matching the selected `objectId + visualId`, not only one instance.

## Grouped object palette

Templates that share `assetId + frame` are artwork siblings and must appear under one thumbnail. Do not repeat identical thumbnails for sibling templates.

Example:

```text
[Wood Fence thumbnail] Wood Fence
  Standard             Collider 100 x 24
  Narrow Passage       Collider 72 x 20
  Shifted Left         Collider 90 x 24
  + New template
```

Each sibling row shows:

- display name, falling back to a title derived from `visualId`;
- collider dimensions for solid objects, or `No physics` for decorative objects;
- a dirty indicator when it owns the active unsaved draft;
- the full `visualId` in a tooltip or secondary metadata treatment.

The inspector reports how many templates share the artwork, for example: “Shares artwork with 2 other templates.” Sibling membership is derived from `assetId + frame`; no parent-template pointer is required. Duplicated templates are independent and do not inherit later changes from their source.

## Inspector layout

On wide screens, use the implemented three-column editor shell:

```text
328 px tools | flexible canvas | 180 px template inspector
```

Keep the industrial “Field Cartographer” visual language. The inspector should feel like a compact measuring instrument: dense numeric controls, clear pixel units, high-contrast overlays, and restrained motion.

At narrow widths, the inspector becomes a closable canvas-side drawer up to 240 px wide. An **Inspector** button reopens it. A closed or empty inspector must not reserve the full right-column width.

### Section 1 — Template identity

- Artwork thumbnail
- Template display name
- `objectId`
- `visualId`
- Asset ID and frame index
- Artwork-sibling count
- Physics: `Static` or `None`
- Read-only behavior, destructibility, and tags

Long IDs must wrap or truncate with their complete value available through `title`. They must not overflow the panel.

### Section 2 — Visual alignment

- Integer `x` and `y` controls in source-frame pixels
- **Reset to 0, 0** action
- A concise reminder that the art moves while the anchor and collider remain fixed

### Section 3 — Collider

Show controls only when the archetype's `physics` is not `null`:

- `width`: integer, minimum 1
- `height`: integer, minimum 1
- `offsetX`: integer, minimum 0
- `offsetY`: integer, minimum 0

For decorative templates, show “This object has no physics” instead. This task must not toggle physics.

### Section 4 — Actions

- **Reset changes**: restore the last server-saved display name, visual offset, and collider.
- **Save template**: update the selected `objectId + visualId` only.
- **Duplicate visual template**: open a dialog for the new display name and unique `visualId`, then add an independent sibling using the same `assetId + frame` and the current draft geometry.
- **Clone object definition**: open a dialog for a new unique `objectId`, then create a new validated object JSON file containing the complete archetype.

The two creation actions must use distinct labels and explanatory text so users understand whether they are creating geometry for the same gameplay object or a new gameplay archetype.

## Canvas feedback

When a template is selected, draw a non-interactive preview overlay for all visible matching instances:

- fixed object anchor: small crosshair at each stored map `x`/`y`;
- source-frame bounds: thin dashed outline around the offset rendered frame;
- collider: translucent red/orange rectangle with a solid outline;
- visual-offset guide: line from the fixed object anchor to the offset art anchor when the offset is non-zero.

The inspector should also provide a focused preview when the selected template has no visible instance on the current map. This preview uses the same renderer and overlay geometry as map objects rather than a separate approximation.

Numeric edits preview immediately without saving. Invalid drafts retain the last valid canvas preview and show an inline field error. Geometry must remain correct while the camera pans or zooms.

Collider drag handles are a possible follow-up. Numeric controls plus live overlays are sufficient for this task.

## Editing and save model

Map and template edits have independent state:

| Change | Owner | Undo/redo | Save action |
| --- | --- | --- | --- |
| Map instances and map content | Open map | Existing map history | Save map |
| Display name | Object visual template | Reset draft in v1 | Save template |
| Collider | Object visual template | Reset draft in v1 | Save template |
| Visual offset | Object visual template | Reset draft in v1 | Save template |

- **Save map** must never write object definition files.
- **Save template** must never write the open map.
- `Ctrl+S` continues to mean **Save map** regardless of focus.
- The template draft has its own dirty badge.
- Browser navigation warnings trigger when either map state or template state is dirty.
- A failed save keeps the draft and displays the server error.
- Successful saves and creation operations refresh the object catalog, grouped palette, focused preview, and all matching visible instances.
- Template edits do not join map undo/redo because they are global content changes rather than one map's history.

## Development-only definition API

Use explicit operations rather than one ambiguous write endpoint:

```text
POST /__map-editor/object-template/update
POST /__map-editor/object-template/duplicate
POST /__map-editor/object-definition/clone
```

### Update template

The request contains stable IDs and editable values only:

```json
{
  "objectId": "decoration.world.solid",
  "visualId": "wood-fence",
  "displayName": "Standard",
  "collider": { "width": 100, "height": 24, "offsetX": 14, "offsetY": 68 },
  "visualOffset": { "x": 0, "y": -4 }
}
```

The server updates only the matching frame template's editable fields.

### Duplicate visual template

The request identifies the source and new template without providing a path:

```json
{
  "objectId": "decoration.world.solid",
  "sourceVisualId": "wood-fence",
  "visualId": "wood-fence-narrow",
  "displayName": "Narrow Passage",
  "collider": { "width": 72, "height": 20, "offsetX": 28, "offsetY": 72 },
  "visualOffset": { "x": -4, "y": 2 }
}
```

The server inserts a sibling under the source template's variant group, reusing its `assetId + frame`.

### Clone object definition

The request contains the source and new stable IDs:

```json
{
  "sourceObjectId": "decoration.world.solid",
  "objectId": "decoration.village.solid"
}
```

The server clones the complete definition, updates `objectId`, derives an allowed destination under `src/game/content/objects/`, validates it, and registers it with the server-owned catalog mechanism. It must never accept a client filesystem path.

The current `ObjectCatalog.ts` uses a hard-coded import table. Clone support therefore requires replacing that table with build-time discovery of validated object JSON modules, such as a typed `import.meta.glob` catalog. A newly cloned file must become available after Vite reloads the affected module; the endpoint must not rewrite TypeScript source or append imports as text.

### Server requirements

1. Reject non-`POST` requests and oversized bodies.
2. Validate object and visual IDs against catalog rules.
3. Resolve owning and destination files from server-owned rules; never accept client paths.
4. Enforce unique `objectId` and `visualId` values for creation operations.
5. Enforce display-name, integer, range, frame-bound, and physics/collider rules server-side.
6. Preserve unrelated JSON properties, variant groups, and frame templates during updates and duplication.
7. Validate the complete resulting object definition using the same rules as `objects:check`.
8. Write to a temporary file and atomically rename it over the destination.
9. Return normalized saved data, including source-frame dimensions and refreshed sibling metadata.
10. Keep all endpoints development-only and out of the production build.

Avoid duplicating validation logic. Extract reusable object validation into a Node-only module shared by `scripts/check-objects.mjs` and the Vite development plugin.

## Required data-model changes

Update all owners of the object definition format:

- `ObjectFrameVariant` in `ObjectCatalog.ts`;
- `objects.schema.json`;
- `scripts/check-objects.mjs` or its extracted validator;
- `ObjectFactory` resolution and body/visual rendering;
- object-definition discovery in `ObjectCatalog.ts`, replacing the hard-coded import table so cloned definitions are loadable without generated TypeScript edits;
- grouped object-palette read models;
- editor preview and definition DTO types;
- development-only Vite authoring endpoints.

`displayName` and `visualOffset` belong on `ObjectFrameVariant` beside `collider` because they can differ between templates that reuse the same artwork.

## Suggested implementation slices

1. Add and validate optional `displayName` and `visualOffset`, preserving generated names and zero-offset behavior for existing definitions.
2. Make `ObjectFactory` apply visual offset without moving the world anchor or collider.
3. Replace the hard-coded object import table with typed build-time JSON discovery, preserving the `ObjectArchetypeId` and validation guarantees used by maps and runtime code.
4. Group palette choices by `assetId + frame` and expose named sibling templates.
5. Add a template read model and independent draft state.
6. Add shared Node validation and atomic update, duplicate, and clone endpoints.
7. Add the right-side inspector and responsive drawer.
8. Add canvas overlays and live preview for every matching visible instance plus a focused fallback preview.
9. Update `docs/MAP_EDITOR.md` with template ownership, global impact, and separate save behavior.

Keep DOM rendering and event cleanup in the editor UI layer. Keep map mutations in `MapEditorState`. Do not put filesystem concerns in `MapEditorScene` or runtime factories.

## Acceptance criteria

- Selecting an Object Content palette entry opens the correct reusable template without requiring a placed object.
- Selecting or moving a placed map object does not change the template inspector or expose placement controls there.
- Templates sharing `assetId + frame` appear under one thumbnail with distinct names, IDs, and geometry summaries.
- Collider and visual-offset edits preview immediately and mark only the template draft dirty.
- Every visible instance using the selected `objectId + visualId` updates during preview and after save.
- A focused preview remains available when the current map has no matching instance.
- Saving updates only the matching frame template and never writes the open map.
- Reloading the editor and launching the map use the saved visual alignment and collider consistently.
- Visual offset does not change stored map coordinates, anchor behavior, depth semantics, or collider world position.
- Invalid collider dimensions and out-of-frame bounds cannot be saved and produce useful inline and server errors.
- Decorative templates never receive collider controls or collider data.
- Duplicate visual template creates a unique sibling under the same artwork thumbnail without changing the source.
- Clone object definition creates a unique validated object archetype without changing the source.
- The grouped palette refreshes after duplication or cloning.
- `Save map`, `Ctrl+S`, and map undo/redo retain their current behavior.
- Unsaved map and template changes are independently visible and protected during navigation and template switching.
- The editor remains usable at wide and narrow desktop viewport sizes without covering required save/status controls.
- All DOM and global listeners added for the inspector have explicit cleanup.
- `pnpm objects:check`, `pnpm maps:check`, `pnpm typecheck`, and `pnpm build` pass.
- A browser smoke test covers grouped sibling selection, offset preview, collider validation, update/save/reload, duplicate template, clone definition, and map play.

## Explicitly out of scope

- Editing placed map coordinates or arbitrary `initialState` in the template inspector
- Editing `TileCatalog.ts` or terrain physics
- Renaming an existing `objectId` or `visualId`
- Changing an existing template's asset ID or frame index
- Editing physics, behavior, destructibility, or tags in the inspector
- Per-map collider or visual-offset overrides
- Collider drag handles
- Production/server content authoring