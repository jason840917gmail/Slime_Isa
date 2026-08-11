# Timeline Right-Edge Drag Resizing

## Problem

Character Studio and Weapon Studio let authors change a keyframe tile's hold with one-frame decrease and increase buttons. Longer changes require repeated clicks even though the shared seconds-first timeline already displays each hold as a spatial block.

## Approved behavior

- Every editable keyframe tile has a draggable right-edge resize handle.
- Horizontal dragging changes that tile's hold in whole playback-frame steps.
- The tile width and compact hold label preview the snapped result while dragging.
- Releasing the pointer commits one undoable hold change through the existing shared timeline resize operation.
- The minimum hold is one frame.
- Resizing targets that tile and does not change the current selection.
- Starting a resize never starts tile reordering.
- `Escape` or pointer cancellation restores the original visual state and commits nothing.
- Locked and mirrored timelines omit the resize handle.
- Existing decrease and increase controls remain available for precise one-frame changes.
- Character Studio and Weapon Studio use the same rendered handle and shared resize interaction controller.

## Architecture

The normalized animation clip remains the source of truth. `resizeKeyframeHold` continues to own timing mutation: it clamps the requested hold to at least one frame, shifts every later keyframe start by the hold delta, and recalculates clip duration from the resulting playback-frame count. Border dragging must not duplicate this timing logic.

The shared timeline renderer adds one right-edge handle to each editable tile. The handle identifies its keyframe with the same zero-based keyframe index used by the existing hold buttons. Locked and mirrored tiles omit the handle entirely. The handle is focusable and has an accessible label that names the keyframe and current hold.

A shared `TimelineHoldResizeController` owns transient drag state and exposes adapter callbacks instead of importing Character Studio or Weapon Studio state. Each Studio creates one controller and forwards its container pointer/key events to `pointerDown`, `pointerMove`, `pointerUp`, `pointerCancel`, and `keyDown`. `cancel` restores an active preview, and `dispose` cancels and makes the controller inert.

On handle pointer down, the controller asks the adapter to `resolveContext(keyframeIndex)`. The returned context contains the keyframe index, source frame, start frame, original hold, FPS, original timeline-frame count, a validation token for the current clip/direction/revision, the timeline root, the keyframe lane, and the target tile. The shared renderer guarantees that a tile contains `.timeline-frame-hold`, a handle contains `data-timeline-resize-handle` and `data-keyframe-index`, and every tile has `data-timeline-index`; these are the complete DOM selectors used by the controller.

The commit interface uses an absolute hold consistently: `commitHold({ keyframeIndex, sourceFrame, startFrame, originalHold, requestedHold, validationToken }): boolean`. The adapter accepts the commit only when the same clip/direction/revision is active and the indexed keyframe still has the original source frame, start frame, and hold. It then calls `resizeKeyframeHold(normalizedClip, keyframeIndex, requestedHold)` once and returns true. A rejected commit returns false and causes the controller to restore the preview without changing selection, history, or document state.

The controller receives the existing shared seconds formatter. It modifies only transient DOM presentation during pointer movement: the target span, later tile starts, total preview-frame count, visible hold label, handle label, and resizing classes. It does not mutate the document, add undo entries, or rerender the Studio before release. On an accepted commit, normal adapter rendering replaces the transient DOM. On cancellation or rejection, the controller restores all cached inline styles, labels, attributes, and classes.

## Pointer and snapping rules

Pointer down on the right-edge handle takes precedence over tile selection and reorder handlers. It prevents the default native drag, stops propagation where needed, captures the pointer, and records the tile's original hold and horizontal coordinate.

Frame width comes from the rendered timeline grid, not a duplicated CSS constant: divide the keyframe lane's rendered width by the original timeline playback-frame count. The controller records the timeline scroll position at pointer down. For pointer coordinate `x`, start coordinate `x0`, current and initial timeline scroll positions `s` and `s0`, original hold `h`, and rendered frame width `w`, the content-space drag distance is `d = (x - x0) + (s - s0)`.

Frame delta rounds symmetrically to the nearest whole frame, with exact half-frame ties away from zero: `d >= 0 ? floor(d / w + 0.5) : ceil(d / w - 0.5)`. Therefore `+0.5w` produces `+1`, `-0.5w` produces `-1`, and movement strictly inside either half-frame threshold produces zero. The preview hold is `max(1, h + frameDelta)`.

The preview changes only when the snapped integer hold changes. Dragging left past the minimum keeps the preview at one frame. For preview delta `p = previewHold - originalHold`, the target tile uses `previewHold` columns, every later tile's start column shifts by `p`, and the temporary timeline-frame count becomes `originalTimelineFrames + p`. This prevents overlap and previews the same downstream shift that will be committed.

At drag start, the controller freezes the measured frame width in a resize-only CSS custom property. While the timeline has its resizing class, the ruler, keyframe lane, and optional track rows use that fixed pixel width for every explicit or newly added preview column. Updating the temporary frame count can therefore extend the lane beyond the original clip without changing the snap width. Existing ruler labels remain at their original frame starts during the gesture; the committed rerender adds or removes labels for the new duration.

Only the right edge is resizable. Dragging the left edge has no timing meaning and keeps normal tile behavior. A resize handle is not `draggable`; the parent tile's native reorder path ignores pointer starts originating inside a resize handle.

## Visual and accessibility behavior

The resize target occupies a narrow strip on the tile's right edge with an `ew-resize` cursor. A visible line or knob appears on hover, focus, selected tiles, and while resizing without obscuring the artwork or existing hold controls. The active handle uses the existing cyan/amber timeline palette.

The handle uses button semantics because the hold has no arbitrary maximum. Its accessible label includes the current value, such as `Resize keyframe 2 hold: 4 frames, 0.17 seconds`. Left/Right arrow keys commit a one-frame decrease or increase through the same absolute-hold callback; Home commits a hold of one frame. Existing minus/plus controls remain the primary compact buttons and preserve their current keyboard behavior.

During pointer resizing, the handle's accessible label and the visible `seconds / frames` label reflect the snapped preview. Focus returns to the corresponding newly rendered handle after an accepted keyboard or pointer commit when practical. Reduced-motion preferences require no special animation because resizing uses direct geometry updates.

## Lifecycle and error handling

The shared controller permits only one active resize. A new valid pointer start cancels any stale transient resize first. Pointer up commits only when the snapped hold differs from the original; otherwise it restores the tile and performs no mutation. `pointerCancel`, `Escape`, or `dispose` invokes `cancel`. Each adapter invokes `cancel` before a rerender, clip change, direction change, or state replacement that was not caused by an accepted resize commit.

Invalid indices, missing clips, nonpositive frame widths, detached handles, locked timelines, and non-primary pointer buttons are no-ops. The adapter validates the gesture token and original keyframe identity before mutation. If state changed during the gesture, no stale document mutation is applied.

| State | Entry | Exit and result |
| --- | --- | --- |
| Idle | No active context | Valid handle pointer down enters Dragging; keyboard commands may commit directly |
| Dragging | Context and original DOM snapshot captured | Pointer movement previews snapped holds; pointer up enters Committed or Rejected; cancel conditions enter Cancelled |
| Committed | Adapter accepts one absolute hold | Adapter rerenders, controller clears transient state, then returns to Idle |
| Rejected | Adapter rejects a stale or invalid token | Controller restores the DOM snapshot and returns to Idle |
| Cancelled | Escape, pointer cancellation, mode change, or explicit cancel | Controller restores the DOM snapshot and returns to Idle without a callback |
| Disposed | Studio cleanup calls `dispose` | Any preview is restored; future controller calls are no-ops |

## Verification

- Shared controller tests verify drag distances below half a frame do not change the hold, exact positive and negative half-frame thresholds round away from zero, scroll delta contributes to content-space movement, negative dragging clamps at one, and multi-frame dragging returns the expected integer hold.
- Tests verify pointer move updates only transient target span, later starts, timeline-frame count, labels, and classes. Pointer up calls the absolute-hold callback once with the final hold; unchanged, cancelled, rejected, and disposed gestures commit nothing and restore the DOM snapshot.
- Tests verify a resize start does not trigger tile selection or reorder behavior.
- Character Studio and Weapon Studio adapter tests verify dragging an unselected tile resizes that tile without changing selection or preview targeting.
- Non-final resize tests verify earlier starts remain unchanged, later starts shift by the exact hold delta, untargeted holds remain unchanged, and duration matches the resulting playback-frame count divided by FPS.
- Final-keyframe resize tests verify duration changes without shifting keyframe starts.
- Locked and mirrored timeline tests verify resize handles are absent.
- Keyboard tests verify Left/Right and Home operate in whole frames and respect the one-frame minimum.
- Run `node --test scripts/tests/character-studio/*.test.mjs scripts/tests/weapon-studio/*.test.mjs`, `pnpm typecheck`, `pnpm characters:check`, `pnpm weapons:check`, `pnpm build`, `git diff --check`, and a live browser check of both studios.

## Alternatives rejected

- Mutating the document on every pointer move would create excess rerenders and undo history entries.
- Free-time dragging followed by rounding on release would make the visible preview disagree with the discrete animation model.
- Left-edge resizing would change the boundary with the previous tile and introduce ambiguous ownership; only the right edge changes the targeted tile's hold.
