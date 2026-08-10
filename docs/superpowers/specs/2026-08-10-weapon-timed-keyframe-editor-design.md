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

Extend `WeaponAnimationDocument` with optional timing fields:

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

`frames` remains the ordered source-tile list and `frameTransforms` remains keyed
by authored tile occurrence. `keyframeTimes[i]` is the integer timeline frame at
which `frames[i]` becomes visible. The computed timeline frame count is:

```text
max(1, round(durationSeconds * framesPerSecond))
```

For each keyframe, the displayed span runs from its start time through one frame
before the next keyframe, or through the final timeline frame for the last tile.
Keyframe times must be strictly increasing and within the computed timeline.

If timing fields are absent, normalization preserves the existing behavior:

- `durationSeconds = frames.length / framesPerSecond`;
- `keyframeTimes = [0, 1, 2, ...]`;
- every tile occupies exactly one timeline frame.

This makes old weapon JSON readable without rewriting the authored files.

### Shared timing helpers

Add a focused weapon timeline module that owns:

- legacy timing normalization;
- timeline frame-count calculation;
- even keyframe distribution;
- keyframe lookup for a timeline frame;
- expansion from timed keyframes to per-frame playback data;
- remapping timing, transforms, tracks, and events during reorder/delete.

Runtime, Weapon Studio, validation, and deterministic checks must use these
helpers rather than implementing separate timing math.

### Runtime playback

The runtime expands each timed animation into a per-timeline-frame sequence for
Phaser playback. The expanded entry includes both the source tile ID and its
authored occurrence index, allowing `WeaponVisual` to:

- render the correct source tile for every held frame;
- apply one occurrence's transform throughout its whole hold;
- preserve directional and mirrored presentation behavior.

`WeaponAttackTrackRunner` receives the expanded timeline length. Existing hitbox
spans and events continue to use integer frame positions, but those positions now
refer to the actual timed timeline rather than the number of source tiles.

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

When duration changes, existing keyframes are rescaled to the new timeline while
remaining ordered and clamped. If the new timeline cannot fit every keyframe at a
unique frame, the editor shows an actionable validation message rather than
silently dropping tiles.

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
- The JSON schema and TypeScript validator check positive finite duration,
  positive integer FPS, matching keyframe/frame lengths, strictly increasing
  times, and in-range times.
- Attack spans and events are validated against the computed timeline frame count.
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
8. Manual Weapon Studio smoke checks for Add Tiles, multi-select, duration
   blocks, frame ruler alignment, and scroll preservation.

Run:

```text
pnpm typecheck
pnpm weapons:check
pnpm assets:check
pnpm build
```

The existing unrelated asset-check failure for the missing generated projectile
sheet remains separately tracked and must not be conflated with this work.
