# Map editor: right-side object inspector

## Goal

Add a right-side inspector to the development-only map editor. It should let a level designer inspect a placed object, adjust its map placement, and tune the selected reusable visual's collider and visual alignment while seeing the result on the canvas.

The inspector must clearly separate:

- **Instance changes**: affect only the selected object in the open map and are saved by **Save map**.
- **Definition changes**: affect every use of the same `objectId + visualId` in every map and are saved by **Save definition**.

This distinction is essential. Collider and visual-alignment values belong to the reusable object definition under `src/game/content/objects/`; they must not be copied into map instances.

## Current constraints

- The editor currently has a 340 px left panel and a canvas, but no right panel.
- A map object stores `instanceId`, `objectId`, `visualId`, `x`, `y`, and optional `initialState`.
- Object colliders are frame-specific values in JSON object definitions:

  ```json
  {
    "width": 42,
    "height": 16,
    "offsetX": 28,
    "offsetY": 59
  }
  ```

- Solid object frames are required to have a collider. Decorative frames must not have one.
- `scripts/check-objects.mjs` already validates object files, asset/frame references, and collider bounds.
- Terrain definitions are different: `TileCatalog.ts` stores static physics as insets, not object-style collider bounds. Editing that TypeScript file safely is a separate task.
- The editor renders objects with physics disabled, so it needs an explicit collider overlay to preview definition changes.

## Product decisions

### Scope for the first version

The first version edits **placed object instances and object visual definitions only**.

Terrain inspector support is out of scope for this task. Do not add a browser endpoint that rewrites `TileCatalog.ts` as text. A later task can move editable terrain data to a validated serializable catalog or add a deliberate TypeScript-aware authoring mechanism.

### Selection behavior

- The inspector is populated when an object is selected with **Select / Move (`V`)**.
- With no object selected, show an empty state: “Select an object to inspect its placement and visual definition.”
- Changing tools may leave the object selected, but definition overlays are shown only while the Select tool is active.
- If the selected object is deleted, clear the inspector immediately.
- Palette selection alone does not open an editable definition. A placed instance must be selected so the canvas provides spatial context.

### Definition identity and impact

A definition edit targets one exact pair: `objectId + visualId`. The server resolves that pair to its owning JSON file and frame entry; the browser never sends a filesystem path.

The inspector must display a persistent warning above definition controls:

> Shared definition — changes affect every map using this visual.

Identifiers, asset ID, and frame index are read-only in this task. Renaming IDs or changing frames can invalidate authored maps and deserves a separate workflow.

## Inspector layout

On wide screens, use a three-column editor shell:

```text
340 px tools | flexible canvas | 300–340 px inspector
```

Keep the current industrial “Field Cartographer” visual language. The inspector should feel like a compact measuring instrument: dense numeric controls, clear units, high-contrast overlays, and restrained motion.

At narrow widths, the inspector becomes a canvas-side drawer rather than shrinking the canvas to an unusable size. It must be closable and reopenable from an **Inspector** button. The empty state should not reserve the full right-column width on narrow screens.

### Section 1 — Selection (read-only)

- Thumbnail
- Human-readable visual name
- `instanceId`
- `objectId`
- `visualId`
- Physics: `Static` or `None`
- Asset ID and frame index

Long IDs must wrap or truncate with their full value available via `title`; they must not overflow the panel.

### Section 2 — Placement (map instance)

- `x` in world pixels
- `y` in world pixels
- **Snap to cell anchor** action

Placement values update the selected map instance through `MapEditorState.mutate`, participate in map undo/redo, mark only the map as dirty, and refresh the canvas immediately. Use finite numeric values and constrain the anchor to the map's pixel bounds.

Do not expose `initialState` as arbitrary JSON in the first version. Behavior-specific state needs typed controls rather than an unsafe generic editor.

### Section 3 — Visual alignment (shared definition)

Add a frame-specific definition field:

```json
"visualOffset": { "x": 0, "y": 0 }
```

- `x`: horizontal render offset in pixels; positive moves the art right.
- `y`: vertical render offset in pixels; positive moves the art down.
- Default is `{ "x": 0, "y": 0 }` when omitted.
- Values are integers.
- Include **Reset to 0, 0**.

This is a **visual-only** offset. It moves the rendered art relative to the object's map anchor but must not move:

- the stored map `x`/`y`;
- the collision body in world space;
- selection/snap anchor semantics;
- depth ordering semantics.

The runtime and editor must use the same object-rendering implementation so their alignment matches. If the existing Phaser image/body coupling cannot preserve a fixed collider while moving only the art, introduce a small object view/body composition instead of silently turning this into a whole-object placement offset.

### Section 4 — Collider (shared definition)

Show this section only for an archetype whose `physics` is not `null`.

- `width`: integer, minimum 1
- `height`: integer, minimum 1
- `offsetX`: integer, minimum 0
- `offsetY`: integer, minimum 0
- **Reset changes** restores the last server-saved values

The collider is expressed in unscaled source-frame pixels. It must remain inside the source frame:

```text
offsetX + width  <= frame width
offsetY + height <= frame height
```

For decorative objects, show “This object has no physics” rather than controls. This task must not toggle an archetype between decorative and solid, because that is behavior-level content editing rather than frame tuning.

## Canvas feedback

While a selected object is being inspected, draw these overlays above the map content:

- Object anchor: small crosshair at the stored map `x`/`y`.
- Source-frame bounds: thin dashed outline around the rendered frame.
- Collider: translucent red/orange rectangle with a solid outline.
- Visual-offset guide: line from the object anchor to the offset art anchor when the offset is non-zero.

Numeric edits preview immediately without saving. Invalid drafts retain the last valid canvas preview and show an inline field error. Overlay geometry must remain correct when the camera pans or zooms.

As a follow-up enhancement, collider edges may become draggable handles. Numeric fields plus the live overlay are sufficient for this task; do not make drag handles a hidden completion requirement.

## Editing and save model

Maintain two independent draft/dirty states:

| Change | Owner | Undo/redo | Save action |
| --- | --- | --- | --- |
| Instance `x`/`y` | Open map | Existing map history | Save map |
| Collider | Object visual definition | Definition draft reset in v1 | Save definition |
| Visual offset | Object visual definition | Definition draft reset in v1 | Save definition |

- **Save map** must never write object catalog files.
- **Save definition** must never write the open map.
- `Ctrl+S` continues to mean **Save map**. Do not overload it based on focus.
- An unsaved definition draft gets its own dirty badge.
- Switching selection with an unsaved definition draft requires a confirmation: discard the draft or remain on the current selection.
- Browser navigation warnings must trigger when either the map or definition draft is dirty.
- After a successful definition save, re-render all visible instances using the affected `objectId + visualId`, not only the selected one.
- A failed save keeps the draft and displays the server error.

Definition edits do not join the existing map undo stack. Mixing globally persisted content changes into a snapshot of one map would make undo semantics misleading. A **Reset changes** action is enough for v1.

## Development-only definition API

Extend the Vite development plugin with a dedicated endpoint such as:

```text
POST /__map-editor/object-definition
```

The request contains stable IDs and editable values only:

```json
{
  "objectId": "rock.amber-ore.mineable",
  "visualId": "amber-ore",
  "collider": { "width": 42, "height": 16, "offsetX": 28, "offsetY": 59 },
  "visualOffset": { "x": 0, "y": -4 }
}
```

Server requirements:

1. Reject non-`POST` requests and oversized bodies.
2. Validate `objectId` and `visualId` against the loaded catalog.
3. Resolve the owning file from a server-owned allowlist derived from object definitions; never accept a client path.
4. Read the current JSON file and update only the matching frame's `collider` and `visualOffset`.
5. Enforce integer/range/frame-bound rules server-side. Client validation is not sufficient.
6. Preserve all unrelated JSON properties and frame entries.
7. Validate the complete updated object definition with the same rules used by `objects:check`.
8. Write to a temporary file and atomically rename it over the target.
9. Return the normalized saved definition, including resolved frame dimensions.

The endpoint exists only in the Vite development server and must not be included in the production build.

Avoid duplicating validator logic between the script and endpoint. Extract reusable object validation into `scripts/lib/` or another Node-only module that both can call.

## Required data-model changes

Update all owners of the object definition format:

- `ObjectFrameVariant` in `ObjectCatalog.ts`
- `objects.schema.json`
- `scripts/check-objects.mjs` or its extracted shared validator
- `ObjectFactory` resolution/rendering
- Editor preview and definition DTO types

`visualOffset` belongs on `ObjectFrameVariant`, beside `collider`, because alignment can differ per frame within one spritesheet. It does not belong in `asset/assets.json`: the asset manifest owns media metadata, and this setting is object-visual placement behavior.

## Suggested implementation slices

1. Add and validate `visualOffset` in the object definition model; preserve zero-offset runtime behavior.
2. Make `ObjectFactory` apply the offset without moving the world collider.
3. Add a read model that resolves inspector metadata for an `objectId + visualId`.
4. Add independent definition draft state and the dev-only atomic save endpoint.
5. Add the right-side inspector and responsive drawer behavior.
6. Add canvas overlays and live draft previews.
7. Update `docs/MAP_EDITOR.md` with the global-impact/save distinction.

Keep DOM rendering and event cleanup in the editor UI layer. Keep map mutations in `MapEditorState`. Do not put filesystem concerns in `MapEditorScene` or reusable runtime factories.

## Acceptance criteria

- Selecting a placed object opens the inspector with the correct instance and visual metadata.
- Editing instance `x`/`y` moves only that instance, supports map undo/redo, and marks the map dirty.
- Collider and visual-offset edits preview immediately and mark a separate definition draft dirty.
- Saving a definition updates only the matching `objectId + visualId` JSON frame.
- Saving a definition visibly updates every matching instance currently on the canvas.
- Reloading the editor and launching the map show the saved visual alignment and collider behavior consistently.
- A visual offset does not change the object's stored map coordinates or its collider's world-space rectangle.
- Invalid collider dimensions or out-of-frame bounds cannot be saved and produce a useful inline/server error.
- Decorative objects never receive collider controls or collider data.
- `Save map`, `Ctrl+S`, and map undo/redo retain their current behavior.
- Unsaved map changes and unsaved definition changes are independently visible and protected on navigation/selection changes.
- The editor is usable at wide and narrow desktop viewport sizes without covering required save/status controls.
- All DOM/global listeners added for the inspector have explicit cleanup.
- `pnpm objects:check`, `pnpm maps:check`, `pnpm typecheck`, and `pnpm build` pass.
- A browser smoke test covers selecting an object, editing both scopes, rejecting invalid bounds, saving, reloading, and playing the map.

## Explicitly out of scope

- Editing `TileCatalog.ts` or terrain physics
- Renaming `objectId` or `visualId`
- Changing asset IDs or spritesheet frame indices
- Toggling object physics, behavior, destructibility, or tags
- Arbitrary `initialState` JSON editing
- Per-map collider or visual-offset overrides
- Production/server content authoring
