# Timeline Right-Edge Drag Resizing

## Problem

Character Studio and Weapon Studio let authors change a keyframe tile's hold with one-frame decrease and increase buttons. Longer changes require repeated clicks even though the shared seconds-first timeline already displays each hold as a spatial block.

## Approved behavior

- Every editable keyframe tile has a draggable right-edge resize handle.
- Horizontal dragging changes that tile's hold in whole playback-frame steps.
- The tile width and its compact hold label preview the snapped result while dragging.
- Releasing the pointer commits one undoable hold change through the existing shared timeline resize operation.
- The minimum hold is one frame.
- Resizing a tile targets that tile and does not change the current selection.
- Starting a resize never starts tile reordering.
- `Escape` or pointer cancellation restores the original visual state and commits nothing.
- Locked or mirrored timelines expose no interactive resize handle.
- The existing decrease and increase controls remain available for precise one-frame changes.
- Character Studio and Weapon Studio use the same rendered handle and shared resize interaction controller.

## Architecture

The normalized animation clip remains the source of truth. `resizeKeyframeHold` continues to own timing mutation: it clamps the requested hold to at least one frame, shifts every later keyframe start by the hold delta, and recalculates clip duration from the resulting playback-frame count. Border dragging must not duplicate this timing logic.

The shared timeline renderer adds one right-edge handle to each editable tile. The handle identifies its keyframe with the same zero-based keyframe index used by the existing hold buttons. It is excluded for locked tiles. The handle is a focusable element with an accessible label that names the keyframe and current hold.

A shared pointer interaction controller owns transient drag state and exposes adapter callbacks instead of importing Character Studio or Weapon Studio state. Its input contract contains the pointer-down event, handle element, keyframe index, original hold, frame-column width, and a commit callback. Its output is either one committed integer hold or cancellation. Adapters only resolve their current clip and call their existing targeted hold mutation with the final delta.

The controller modifies only transient DOM presentation during pointer movement: tile grid span, the seconds/frame hold label, handle value text, and a resizing class. It does not mutate the document, add undo entries, or rerender the Studio before release. On commit, the adapter performs exactly one existing mutation and normal rendering replaces the transient DOM. On cancellation, the controller restores the original span and labels.

## Pointer and snapping rules

Pointer down on the right-edge handle takes precedence over tile selection and reorder handlers. It prevents the default native drag, stops propagation where needed, captures the pointer, and records the tile's original hold and horizontal coordinate.

Frame width comes from the rendered timeline grid, not a duplicated CSS constant: divide the keyframe lane's rendered width by the timeline playback-frame count. For pointer coordinate `x`, start coordinate `x0`, original hold `h`, and rendered frame width `w`, the preview hold is:

`max(1, h + round((x - x0) / w))`

The preview changes only when the snapped integer hold changes. Dragging left past the minimum keeps the preview at one frame. Dragging right may extend beyond the current clip end; later keyframes and total duration shift only when the final hold is committed. Horizontal scrolling does not affect the calculation because both pointer coordinates are viewport-relative and frame width is measured from the lane.

Only the right edge is resizable. Dragging the left edge has no timing meaning and keeps normal tile behavior. A resize handle must not be marked `draggable`; the parent tile's native reorder path ignores pointer starts originating inside a resize handle.

## Visual and accessibility behavior

The resize target occupies a narrow strip on the tile's right edge with an `ew-resize` cursor. A visible line/knob appears on hover, focus, selected tiles, and while resizing without obscuring the artwork or existing hold controls. The active handle uses the existing cyan/amber timeline palette.

The handle uses slider semantics with integer frame values: minimum one, current hold, and a readable value such as `4 frames, 0.17 seconds`. Left/Right arrow keys change the targeted hold by one frame through the same adapter callback; Home sets one frame. Existing `−/+` controls remain the primary compact buttons and preserve their current keyboard behavior.

During pointer resizing, the handle's accessible current value and the visible `seconds / frames` label reflect the snapped preview. Focus returns to the corresponding newly rendered handle after commit when practical. Reduced-motion preferences require no special animation because resizing uses direct geometry updates.

## Lifecycle and error handling

The shared controller permits only one active resize. A new valid pointer start cancels any stale transient resize first. Pointer up commits only when the snapped hold differs from the original; otherwise it restores the tile and performs no mutation. Pointer cancellation, `Escape`, Studio disposal, clip change, direction change, or rerender cancels the active resize.

Invalid indices, missing clips, nonpositive frame widths, detached handles, locked timelines, and non-primary pointer buttons are no-ops. Adapter mutation remains responsible for validating that the keyframe still exists when the pointer is released. If state changed during the gesture, no stale document mutation is applied.

## Verification

- Shared controller tests verify drag distances below half a frame do not change the hold, half-frame thresholds round to the next frame, negative dragging clamps at one, and multi-frame dragging returns the expected integer hold.
- Tests verify pointer move updates only transient span/labels and pointer up calls the commit callback once with the final hold; unchanged and cancelled gestures commit nothing.
- Tests verify a resize start does not trigger tile selection or reorder behavior.
- Character Studio and Weapon Studio adapter tests verify dragging an unselected tile resizes that tile without changing selection or preview targeting.
- Non-final resize tests verify earlier starts remain unchanged, later starts shift by the exact hold delta, untargeted holds remain unchanged, and duration matches the resulting playback-frame count divided by FPS.
- Final-keyframe resize tests verify duration changes without shifting keyframe starts.
- Locked/mirrored timeline tests verify handles are inert or absent.
- Keyboard tests verify Left/Right and Home operate in whole frames and respect the one-frame minimum.
- Run focused editor tests, `pnpm typecheck`, character and weapon validators, a production build, `git diff --check`, and a live browser check of both studios.

## Alternatives rejected

- Mutating the document on every pointer move would create excess rerenders and undo history entries.
- Free-time dragging followed by rounding on release would make the visible preview disagree with the discrete animation model.
- Left-edge resizing would change the boundary with the previous tile and introduce ambiguous ownership; only the right edge changes the targeted tile's hold.
