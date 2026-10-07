# Map editor inspector template and overlay fixes

## Problems

1. The template inspector can overwrite a shared template but cannot preserve it
   while saving the current draft as a new template.
2. Editing visual or collider offsets rerenders the inspector and jumps its
   scroll container to the top.
3. Selecting a template draws visual-frame and collider boxes for every matching
   map instance, creating excessive canvas clutter.

## Approved behavior

### Save actions

- **Save template** updates the selected `objectId + visualId`.
- **Save as new template** asks for a unique stable `visualId` and display name.
  It inserts a sibling in the same object definition, reuses the selected
  template's asset and frame, and applies the current draft offset and collider.
- The original template remains unchanged.
- Creating a separate gameplay object definition is out of scope.

The development server owns path resolution, validates IDs and geometry, rejects
duplicates, preserves unrelated JSON fields, and atomically replaces the owning
object-definition file.

The new `visualId` must be unique across every variant group in the selected
`objectId`. The new frame is appended to the exact variant group containing the
source. The server copies all source-frame metadata, including animation fields,
then replaces `visualId`, `displayName`, `visualOffset`, and `collider` with the
new identity and current validated draft.

Saving a new template is allowed even when the template draft itself is
unchanged. The dialog defaults its display name from the current draft and keeps
both fields editable. Canceling changes nothing. Validation or server errors
remain inline in the open dialog so the user can retry.

Because changing an imported object JSON file causes Vite to reload the editor,
**Save as new template** is disabled while the open map has unsaved changes and
explains that the map must be saved first. After successful creation, the clean
editor reloads with query parameters identifying the new `objectId + visualId`,
so the new sibling is loaded by the existing catalog and selected automatically.
Map-reference validation used by the development server must read current object
definitions from disk rather than the config module's startup-time catalog, so
maps can immediately save references to newly created visual IDs.

### Stable inspector editing

Inspector rerenders preserve the scroll container's `scrollTop` and restore focus
using the stable `data-template-field` identity. Text selection is restored only
for input types that support selection ranges; numeric inputs restore focus
without calling unsupported selection APIs. If a rerender removes the focused
field, only the scroll position is restored. Numeric offset and collider edits
therefore keep the user's viewport and editing position stable.

### Geometry overlay control

The inspector provides a **Show boxes for all matching instances** checkbox.
`ObjectTemplateEditorState` owns this editor-session flag, exposes it in
`ObjectTemplateViewState`, and emits changes to both the inspector renderer and
the scene's existing template-state subscription. It defaults to false whenever
a new editor scene is created and is never saved into map or object JSON.

- Off + selected placed instance matches the inspected template: draw the
  source-frame visual box and collider box only for that instance.
- Off + no matching placed instance selected: draw only the centered focused
  template preview, even when matching instances exist elsewhere in the map.
- On: draw both boxes for every rendered instance in the open map matching the
  selected `objectId + visualId`; the currently selected map instance does not
  change this set.
- On + zero matching instances: draw the centered focused template preview.

"Rendered instance" means an object instantiated from the open map. Camera
clipping naturally determines which overlay geometry is currently onscreen.

## Verification

- Updating a template changes only the selected template.
- Saving as new creates a selectable sibling with the current draft and leaves
  the source unchanged.
- Save as new is blocked while the map is dirty and reloads/selects the new
  sibling only after a clean successful write.
- Invalid or duplicate IDs keep the dialog and draft open with an error.
- The server accepts immediate map references to the new visual ID from disk
  truth without requiring a Vite restart.
- Offset and collider edits preserve inspector scroll and focus.
- The overlay checkbox starts off and toggles selected-only versus all-matching
  visual and collider boxes.
- Object/map validators, strict TypeScript, production build, and browser editor
  smoke tests pass.
