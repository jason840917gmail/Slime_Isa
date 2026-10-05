# Character Studio bugs

## Reported issues

- [x] **Source and animation thumbnails show black boxes**
  - Area: Source sheet and Animation timeline.
  - Reproduction: Open Character Studio and inspect the registered source frames and clip frames.
  - Expected: Each tile shows the actual cropped sprite frame, including frames from the middle of a sheet.
  - Acceptance: Source and timeline tiles render the correct frame image with a missing-image fallback instead of a blank/black tile.
  - Resolution: Replaced CSS-only sheet crops with real cropped `<img>` elements and removed invalid nested timeline buttons.

- [x] **Play Clip cannot be stopped**
  - Area: Animation timeline playback.
  - Reproduction: Press `PLAY CLIP`, then press the same button again.
  - Expected: The button toggles between play and stop. Looping remains available through the `LOOP` setting, but playback can always be stopped.
  - Acceptance: A second press stops the interval immediately, updates the label, and changing clips/packages does not leave stale playback running.
  - Resolution: Playback now uses an explicit interval toggle, changes the button to `STOP CLIP`, and stops when the author changes clips, frames, packages, or playback settings.

- [x] **Hitbox span and event controls are clearer**
  - Area: Animation timeline controls.
  - Reproduction: Press `+ HITBOX SPAN` or `+ EVENT` and inspect the timeline.
  - Expected: The editor explains what each annotation affects and clearly shows the selected frame's active hitboxes/events.
  - Acceptance: Hitbox spans are described as inclusive active-frame ranges used by runtime collision callbacks; events are described as one-frame runtime callback markers that do not change the sprite by themselves.
  - Resolution: Added inline explanations, selected-frame summaries, named hitbox rows, visible event labels, and bounded span prompts.

## Resolution notes

The implementation passes the Character Studio dependency-graph typecheck, character content validation, browser smoke verification, and diff whitespace validation. The local dependency directory was repaired with `pnpm install --ignore-scripts`; the remaining project verification commands are tracked separately below.

## Follow-up usability issues — 2026-07-27

- [x] **Native browser prompts are disruptive**
  - Area: Character Studio data entry and popup messages.
  - Reproduction: Create, rename, duplicate, import a sheet, or add an annotation.
  - Expected: A styled in-studio dialog with clear context, validation, cancel behavior, and keyboard support.
  - Resolution: Added a reusable Character Studio modal layer for alerts, confirmations, and single- or multi-field forms. Escape and backdrop dismissal cancel safely, and focus moves to the first field.

- [x] **Editing an existing animation asks for a new name**
  - Area: Animation clip tabs and clip actions.
  - Reproduction: Select an existing clip and use the animation editing controls.
  - Expected: The selected clip is edited in place; naming is requested only for creating, renaming, or duplicating.
  - Resolution: Existing clip tabs now clearly open the selected clip for direct editing. The pencil and duplicate controls are explicitly labeled as rename and duplicate actions, while the timeline header identifies the clip being edited.

- [x] **Clicking a selected source frame should deselect it**
  - Area: Source sheet frame selection.
  - Reproduction: Click the same source frame twice.
  - Expected: The second click clears that frame from the selection.
  - Resolution: Source frame selection is now toggle-based and supports multiple selected frames for append/insert operations.

- [x] **Timeline frames cannot be reordered by dragging**
  - Area: Animation timeline.
  - Reproduction: Drag one timeline frame over another frame.
  - Expected: The frame moves to the drop position and the selected frame stays synchronized.
  - Resolution: Timeline tiles are draggable with native drag/drop plus pointer fallback, visible drag/drop states, and deterministic document-state reordering.

- [x] **Saving an existing character says Character ID is required**
  - Area: Character Studio save action.
  - Reproduction: Change an existing package and press `SAVE DRAFT`.
  - Expected: The open package ID is used automatically.
  - Resolution: The update endpoint now reads the active package ID from the update payload, and the editor derives it from the loaded character document before falling back to the route state.
