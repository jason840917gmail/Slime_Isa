# Weapon Timed-Keyframe Animation Editor

## Status

Approved by the user on 2026-08-10.

## Goal

Improve Weapon Studio's animation authoring model and interaction flow so weapon
tiles behave like a Godot-style timed animation track. A clip has an explicit
total duration and FPS, source tiles are authored as keyframes on that timeline,
and each tile remains visible until the next keyframe. The editor must also stop
resetting the workbench scroll position when a field or attack-track control is
changed.

## User-facing outcome

- The main Weapon Studio workbench no longer shows a permanent SOURCE TILES bank.
- The animation section has an `ADD TILES` button that opens a source-tile picker.
- The picker supports selecting multiple source tiles and appending them to the
  current animation.
- Each animation clip exposes total duration in seconds and FPS.
- The animation tile track displays blocks positioned on a numbered frame ruler.
  Block width represents the time until the next keyframe, including the final
  hold through the end of the clip.
- Newly added tile sets are distributed evenly across the clip. Keyframes can
  then be moved manually to create holds and custom timing.
- Hitbox spans and events remain separate tracks aligned to the same timeline.
- Full editor rerenders preserve workbench scroll, inspector scroll, browser
  scroll, and the active field where practical.

## Design

### Timed animation data

Extend `WeaponAnimationDocument` with an optional timing pair:

```ts
interface WeaponAnimationDocument {
  readonly frames: readonly number[];
  readonly keyframeTimes?: readonly number[];
  readonly durationSeconds?: number;
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: 'wrap' | 'ping-pong';
  readonly frameTransforms?: Readonly<Record<string, WeaponFrameTransformDocument>>;
}
```

`durationSeconds` and `keyframeTimes` are an all-or-none authored pair. A document
with only one of them is invalid in the authored validator and is normalized as a
legacy clip only at a catalog boundary that explicitly records a diagnostic.
Normalized animation data always contains both values, including for fallback
root and directional attack packages.

`frames` remains the ordered source-tile list and `frameTransforms` remains keyed
by authored tile occurrence. `keyframeTimes[i]` is the integer timeline frame at
which `frames[i]` becomes visible. The computed timeline frame count is:

```text
max(1, round(durationSeconds * framesPerSecond))
```

Timeline cells use the half-open range `[0, N)`. The first keyframe must be at
frame `0`, and valid times satisfy:

```text
0 = keyframeTimes[0] < ... < keyframeTimes[K - 1] < N
```

For each keyframe, the displayed span runs from its start time through one frame
before the next keyframe, or through frame `N - 1` for the last tile. Its hold
length is therefore `nextTime - startTime`, or `N - lastTime` for the final tile.
The effective playback duration is `N / framesPerSecond`; rounding the requested
seconds to `N` is deliberate and must be displayed by the editor when it differs
from the requested value.

Even distribution uses the deterministic formula:

```text
keyframeTimes[i] = floor(i * N / K), for i in [0, K)
```

It is valid only when `K <= N`. Manual dragging snaps to an integer timeline
frame and clamps between the previous keyframe plus one and the next keyframe
minus one. A move that cannot fit without collision is rejected with an inline
message.

If both timing fields are absent, normalization preserves the existing behavior:

- `durationSeconds = frames.length / framesPerSecond`;
- `keyframeTimes = [0, 1, 2, ...]`;
- every tile occupies exactly one timeline frame.

This makes old weapon JSON readable without rewriting the authored files.

Timing is resolved per animation package. Explicit directional attack timing
overrides the directional fallback; absent RIGHT/UP/DOWN timing falls back to the
normalized root attack timing, and an absent LEFT package inherits RIGHT timing
through the existing mirror relationship. Idle and impact use their root clips.

### Shared timing helpers

Add a focused weapon timeline module that owns:

- legacy timing normalization;
- timeline frame-count calculation;
- even keyframe distribution;
- keyframe lookup for a timeline frame;
- expansion from timed keyframes to per-frame playback data;
- rescaling keyframe times when duration or FPS changes;
- remapping keyframe timing and transforms during visual reorder, duplicate, and
  delete;
- deterministic even distribution and collision checks.

Visual keyframe edits do not silently move hitbox spans or events: those tracks
are independent absolute timeline tracks. A visual reorder moves the source tile,
its occurrence transform, and its keyframe time together; hitbox/event positions
stay on their existing timeline frames. Deleting a visual keyframe leaves valid
track positions untouched, with the previous/next visual tile filling the time.
Duplicating a visual keyframe copies its source tile and transform, inserts it at
the next available visual position, and runs the explicit distribution command
only when the user requests it. Track edits themselves preserve their absolute
frame positions.

Runtime, Weapon Studio, validation, and deterministic checks must use these
helpers rather than implementing separate timing math.

### Runtime playback

The timeline helper returns an expanded structure:

```ts
interface ExpandedWeaponAnimation {
  readonly sourceFrames: readonly number[];
  readonly occurrenceIndices: readonly number[];
  readonly timelineFrameCount: number;
  readonly effectiveDurationMs: number;
}
```

The runtime passes this structure, or its `timelineFrameCount`, into the weapon
visual and attack-track runner rather than allowing consumers to infer timing
from `clip.frames.length`. The expanded sequence is used for Phaser playback;
the occurrence index maps each displayed frame back to the authored tile
occurrence, allowing `WeaponVisual` to:

- render the correct source tile for every held frame;
- apply one occurrence's transform throughout its whole hold;
- preserve directional and mirrored presentation behavior.

`WeaponAttackTrackRunner` receives the expanded timeline length. Its completion,
position, event dispatch, and bounds all use that length. Attack tracks remain
one-shot even if a malformed/legacy attack clip says `loop: true`; idle and impact
visual playback use the expanded sequence with the existing wrap/ping-pong
semantics. Ping-pong reverses the expanded displayed sequence, including its
occurrence indices, so held transforms remain attached to the correct occurrence.
Existing hitbox spans and events continue to use integer frame positions, but
those positions now refer to the actual timed timeline rather than the number of
source tiles.

### Weapon Studio interaction

The animation panel contains:

1. Clip tabs and directional controls.
2. Clip timing controls: duration in seconds and FPS.
3. A duration-block animation track with a frame ruler.
4. An `ADD TILES` button that opens a modal source-tile picker.
5. Tile selection, reorder, duplicate, delete, and manual keyframe movement.
6. A selected-keyframe inspector showing source tile, start frame, derived hold
   length, and transform controls.
7. Aligned hitbox and event tracks for attack clips.

The source picker uses the selected weapon asset's existing spritesheet metadata.
It is a temporary modal selection surface, not saved as part of the weapon
definition. Adding selected tiles appends them and evenly distributes the current
keyframe set across the clip. Manual movement afterward writes explicit
`keyframeTimes`.

When duration or FPS changes, the old timeline count `N` and new count `N'` are
used to rescale each keyframe with `round(oldTime * N' / N)`, then the result is
clamped monotonically to preserve `0 = t0 < ... < tK-1 < N'`. The same operation
does not alter absolute hitbox/event positions; positions outside the new range
are surfaced as validation errors for the author to correct. If the new timeline
cannot fit every keyframe at a unique frame, the editor shows an actionable
validation message rather than silently dropping tiles.

Legacy clips materialize explicit timing in the in-memory draft when the author
opens a clip. Saving writes the timing pair. Changing a legacy clip's duration or
adding a tile uses even distribution; simply opening and saving without a timing
edit may retain the compact legacy form if no explicit timing was needed.

### Scroll and focus preservation

Before `WeaponStudio` replaces its rendered DOM, capture:

- `.studio-workbench` scrollTop/scrollLeft;
- `.studio-inspector-scroll` scrollTop/scrollLeft;
- window scroll offsets;
- the active editor field's identifying data attribute when available.

After rendering, restore those values synchronously and on the next animation
frame. Restore focus to the matching field when it still exists. Modal opening and
closing use the same path so users can continue authoring at the same location.

## Migration and validation

- Existing weapon documents remain valid without timing fields.
- Newly edited or created clips write explicit `durationSeconds` and
  `keyframeTimes`.
- The JSON schema includes both timing fields and enforces their array/number
  structure. The TypeScript validator checks positive finite duration, positive
  integer FPS, all-or-none timing, matching keyframe/frame lengths, first-frame
  zero, strict ordering, the `[0, N)` boundary, and timeline capacity.
- Attack spans and events are validated against the computed timeline frame count.
- Root, directional, and mirror-resolved tracks are each validated against the
  computed timeline count; root attack validation uses the resolved root attack
  animation rather than an unrelated animation length.
- The standalone weapon check uses the shared-compatible rules and validates all
  reusable weapon definitions.
- Mirror-linked LEFT packages inherit RIGHT timing; custom LEFT owns its timing.

## Verification

Add deterministic coverage for:

1. Legacy clips normalizing to one-frame-per-tile timing.
2. Two-second, 12 FPS clips producing 24 timeline frames.
3. Even distribution of one, several, and boundary-sized tile sets.
4. Expansion of held keyframes to playback frames and occurrence indices.
5. Reordering, duplication, deletion, and duration rescaling preserving timing,
   transforms, hitbox spans, and events.
6. Validation failures for duplicate, out-of-range, or mismatched keyframes.
 7. Attack-track runner completion and event positions on expanded timelines.
 8. Partial timing fields, duration rounding, FPS changes, first/last-frame
    events, mirror/custom-LEFT inheritance, and ping-pong playback.
 9. Occurrence transforms remaining correct during held frames.
10. Manual Weapon Studio smoke checks for Add Tiles, multi-select, duration
    blocks, frame ruler alignment, and all workbench/inspector/window scroll and
    focus targets.

Run:

```text
pnpm typecheck
pnpm weapons:check
pnpm assets:check
pnpm build
```

The existing unrelated asset-check failure for the missing generated projectile
sheet remains separately tracked and must not be conflated with this work.
