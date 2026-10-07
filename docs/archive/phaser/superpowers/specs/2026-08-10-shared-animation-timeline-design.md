# Shared Animation Timeline for Characters, Enemies, and Weapons

## Status

Architecture direction approved by the user on 2026-08-10. This document
supersedes the weapon-only boundary in
`2026-08-10-weapon-timed-keyframe-editor-design.md`; the weapon behavior remains
part of the shared design as one consumer.

## Goal

Create one Godot-like animation foundation for characters, enemies, and weapons.
The foundation owns clip timing, keyframes, playback, looping, scrubbing,
timeline editing, and generic animation events. Entity types provide adapters
for their own visuals and gameplay tracks.

The result should make it possible to author a timed animation using the same
schema, editor, and player for a character, enemy, or weapon host without
maintaining three different animation models or three different timeline
implementations. Raw frame references remain local to the owning asset package:
the first pass does not promise that a character's source tile can be assigned
directly to a weapon or enemy. Cross-asset retargeting would require a separate
explicit frame-mapping feature.

## Recommendation

Use composition as the source of truth:

```text
AnimationClipDocument
        |
AnimationPlayer / timeline helpers
        |
AnimationHostAdapter
   /        |        \
Character  Enemy    Weapon
```

The shared animation system is the source of truth. A future thin
`AnimatedEntity` base class may expose convenience methods such as `play`,
`stop`, and `scrub`, but it must delegate to the shared player and must not own
entity-specific combat or rendering rules.

Do not make the animation model inherit from `WeaponAnimationDocument`,
`CharacterAnimationDocument`, or `EnemyAnimationDocument`. The common model
must remain neutral.

## User-facing outcome

- Character Studio, Enemy Studio, and Weapon Studio use the same timeline
  behavior and visual language.
- Every clip has a total duration and FPS. The editor shows the effective
  timeline frame count after duration/FPS rounding.
- Source tiles are authored as timed keyframes. A keyframe holds its tile until
  the next keyframe, so a tile does not need to be duplicated for every frame.
- The visual track, event tracks, and domain-specific gameplay tracks share one
  ruler and one timeline coordinate system.
- The source-tile bank is not permanently visible in the main editor. Each
  studio opens its asset-specific source picker from the animation track's
  `ADD TILES` control.
- Changing controls or selecting attack/event-track items preserves workbench,
  inspector, browser, window scroll, and field focus.
- Existing legacy clips remain loadable and behave as one-frame-per-tile clips
  until edited or saved.

## Shared animation data model

The common authored contract is:

```ts
interface AnimationClipDocument {
  readonly frames: readonly number[];
  readonly keyframeTimes?: readonly number[];
  readonly durationSeconds?: number;
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: 'wrap' | 'ping-pong';
}

interface NormalizedAnimationClipDocument extends AnimationClipDocument {
  readonly keyframeTimes: readonly number[];
  readonly durationSeconds: number;
}
```

`frames[i]` is the source-frame reference for authored keyframe occurrence
`i`. `keyframeTimes[i]` is the integer timeline cell where that occurrence
becomes visible. The normalized type is the only type accepted by shared
runtime and editor consumers.

Timing fields are an all-or-none pair. A document with only one timing field is
invalid. A document with neither field is legacy and normalizes as:

```text
durationSeconds = frames.length / framesPerSecond
keyframeTimes = [0, 1, 2, ...]
```

The shared model owns animation timing only. Existing domain metadata remains
with its owning package:

- Character clips keep sprite-sheet placement metadata such as `sourceOffset`.
- Weapon clips keep occurrence-based transforms and weapon presentation data.
- Enemy clips keep enemy-specific visual and presentation metadata.

Those metadata structures must use the shared keyframe occurrence index when
they need to follow a tile through a drag, duplicate, reorder, or delete.

New draft clips may temporarily contain zero source frames while the editor is
waiting for the author to use `ADD TILES`. Empty draft clips cannot play,
preview, or save. The editor shows an actionable validation message and keeps
the draft editable. Every normalized runtime clip and every successfully saved
clip must contain at least one source frame and a keyframe at timeline cell `0`.

### Timeline semantics

For a normalized clip:

```text
N = max(1, round(durationSeconds * framesPerSecond))
timeline cells = [0, N)
```

The valid keyframe invariant is:

```text
0 = keyframeTimes[0] < ... < keyframeTimes[K - 1] < N
```

Each keyframe holds from its start cell through the cell before the next
keyframe, or through `N - 1` for the final keyframe. Its hold length is the
next start minus the current start, or `N - lastStart` for the final keyframe.
The effective playback duration is `N / framesPerSecond`.

Even distribution uses:

```text
keyframeTimes[i] = floor(i * N / K), for i in [0, K)
```

It is valid only when `K <= N`. Duration/FPS changes rescale old keyframe
positions with `round(oldTime * newN / oldN)` followed by the deterministic
forward pass used by the weapon design. The edit is rejected transactionally if
the new timeline cannot fit every keyframe or if an existing absolute track
position would fall outside the new range.

### Shared edit rules

The shared timeline module owns the deterministic rules for:

- adding and evenly distributing source tiles;
- moving a keyframe to the nearest legal free cell, with lower-cell tie breaks;
- reordering the keyframe, source frame, and occurrence metadata together;
- duplicating into the midpoint of the longest available hold;
- deleting one or more keyframes while preserving the minimum-one-keyframe
  invariant;
- rebasing remaining keyframe times when the first keyframe is deleted;
- explicitly distributing all visual keyframes evenly;
- looking up the active keyframe and hold length for a timeline cell;
- expanding timed keyframes into per-timeline-frame playback data.

Visual keyframe edits do not silently move event or gameplay-track positions.
Those tracks use absolute timeline cells and are validated after every
transaction.

## Shared runtime

Add a reusable `AnimationPlayer` that accepts a normalized clip and emits a
neutral playback state:

```ts
interface AnimationPlaybackState {
  readonly timelineFrame: number;
  readonly keyframeIndex: number;
  readonly sourceFrame: number;
  readonly occurrenceIndex: number;
  readonly finished: boolean;
}
```

The player owns:

- play, pause, stop, and scrub;
- FPS and effective-duration calculations;
- wrap and ping-pong looping;
- one-shot completion;
- keyframe lookup and held-frame expansion;
- deterministic event dispatch positions.

The player must not know about Phaser sprites, weapon hitboxes, character
hurtboxes, enemy AI, or combat effects.

Each entity provides an `AnimationHostAdapter` with responsibilities such as:

```ts
interface AnimationPlaybackContext {
  readonly previousTimelineFrame: number | null;
  readonly timelineFrame: number;
  readonly direction: 1 | -1;
  readonly cycle: number;
  readonly isScrub: boolean;
}

interface AnimationHostAdapter {
  applyAnimationFrame(
    state: AnimationPlaybackState,
    context: AnimationPlaybackContext,
  ): void;
  dispatchAnimationEvent(
    event: AnimationEventDocument,
    context: AnimationPlaybackContext,
  ): void;
  resetDomainTracks(context: AnimationPlaybackContext): void;
}
```

Character, enemy, and weapon adapters can then update their own visuals and
domain tracks without duplicating timeline math. Playback dispatch is
deterministic: starting a clip applies cell `0` and emits events authored at
cell `0` once; advancing across multiple cells emits every crossed event in
playback order; skipped render updates do not skip events; and a loop crossing
processes the end segment before the beginning segment. Ping-pong reports its
direction through the context and does not emit the same boundary event twice
merely because the playhead reverses. Scrubbing applies the visual frame and
calls `resetDomainTracks`, but does not emit gameplay events. Studios may opt
into an explicit non-gameplay event-preview mode.

Attack tracks remain one-shot even when malformed legacy data says loop. Idle
and impact clips retain their configured wrap or ping-pong behavior. Ping-pong
operates on the expanded held-frame sequence so transforms and source-frame
occurrences stay attached correctly.

## Shared tracks and domain tracks

Generic animation events use the same absolute timeline coordinate system for
all entity types:

```ts
interface AnimationEventDocument {
  readonly at: number;
  readonly eventId: string;
  readonly payload?: JsonValue;
}
```

The canonical package-level track shape is:

```ts
interface AnimationTrackDocument {
  readonly events?: readonly AnimationEventDocument[];
}

interface AnimationTrackBundle {
  readonly animationTracks: Readonly<Record<string, AnimationTrackDocument>>;
}
```

The `animationTracks[clipId]` entry is the shared home for generic events.
Domain packages extend the corresponding entry with their own track data or
keep a domain-owned parallel track keyed by the same `clipId`; they do not
invent alternate timeline coordinates. Character `animationTracks` and the
weapon attack-track event data converge on this contract during migration.

The shared editor can render and edit generic event rows. Event consumers remain
domain-owned:

- characters may trigger footsteps, effects, or state changes;
- enemies may trigger attacks, sounds, or AI callbacks;
- weapons may trigger hitbox windows, trails, or impact effects.

Hitbox geometry, hurtboxes, attack windows, weapon trails, and attachment rules
are not forced into one universal schema. Each domain registers a track adapter
that uses the shared ruler and validation boundaries.

## Shared editor architecture

Create one reusable timeline editor/view model with host-provided adapters:

```ts
interface AnimationTimelineHost {
  getSourceTiles(): readonly SourceTile[];
  getClip(): NormalizedAnimationClipDocument;
  getTracks(): readonly AnimationTrackViewModel[];
  applyEdit(edit: AnimationTimelineEdit): void;
}
```

The shared editor owns:

- the clip tab and timing controls;
- the ruler and duration-block visual track;
- keyframe selection, drag, reorder, duplicate, and delete;
- `ADD TILES` picker lifecycle and multi-selection;
- playhead and scrub behavior;
- event-row rendering;
- scroll/focus capture and restoration around DOM rerenders.

The host supplies source-tile resolution, metadata inspectors, and domain
tracks. This lets Character Studio, Enemy Studio, and Weapon Studio present
their own inspector fields while using identical timeline behavior.

The picker is a modal selection surface backed by the active entity's existing
spritesheet metadata. It is not persisted as part of the animation definition.

## Entity integration

### Characters

Character clips migrate from `frames + framesPerSecond` to the shared normalized
clip at the content boundary. `CharacterAnimationTrackRunner` becomes a thin
adapter around `AnimationPlayer`. Character hitbox spans and events keep their
existing domain meaning but use the shared timeline frame count.

`CharacterTimeline` and `CharacterDocumentState` delegate all visual timing
mutations to the shared timeline module. Character-specific source offsets and
hitbox editing stay in the character feature. The current behavior that shifts
character events and hitbox spans when visual frames are inserted or removed is
replaced by the shared rule: visual edits leave absolute domain-track positions
unchanged, then validate them against the new timeline. A transaction that
would leave a track outside the clip is rejected with an actionable message;
there is no silent compatibility shift after migration.

### Enemies

Enemies use the same normalized clip, player, editor, and event semantics as
characters. In the current codebase an enemy is represented by
`CharacterDocument.kind === 'enemy'`; the first migration keeps that ownership
inside Character Studio and does not create a separate Enemy Studio or a second
enemy animation package. Enemy-specific attack, hurtbox, AI, and effect tracks
are adapters, not alternate animation implementations. Existing enemy
animation data is normalized through the same legacy boundary.

### Weapons

Weapon clips migrate from the weapon-only timing helpers to the shared module.
`WeaponVisual` consumes neutral playback state plus weapon occurrence transforms.
`WeaponAttackTrackRunner` becomes a host adapter and uses the shared timeline
frame count for completion, events, and bounds. Weapon Studio uses the shared
editor and provides weapon-specific transform and attack-track inspectors.

The weapon-specific rules already approved in the weapon timed-keyframe design
remain normative under the shared model: occurrence transforms move with their
authored keyframe; legacy clips normalize to one frame per tile; duration/FPS
rescaling uses the specified raw-time and forward-pass formula; absent LEFT
continues to mirror RIGHT; absent vertical packages continue to fall back to
root; custom directional packages own their timing; and dirty saves materialize
explicit timing only for authored packages already present in the draft.

`WeaponAnimationDocument` becomes a domain extension of
`AnimationClipDocument`, and its normalized form combines
`NormalizedAnimationClipDocument` with weapon occurrence transforms. It is not
a second timing model.

## Save and migration policy

- Legacy clips remain readable without timing fields.
- Opening a legacy clip materializes normalized timing in the in-memory draft.
- A successful dirty save writes explicit timing for authored clips already
  present in that entity's draft.
- Normalization does not create missing directional or fallback packages.
- Existing fallback and mirror relationships remain data relationships owned by
  the entity package, while the resolved clip presented to runtime always has
  explicit timing.
- The migration must not silently rewrite absolute event or gameplay-track
  positions when visual keyframes change.

The shared validator checks positive finite duration, positive integer FPS,
all-or-none timing fields, matching frame/timing lengths, first-frame zero,
strict timing order, timeline bounds, capacity, and track positions.

## Implementation sequence

1. Add shared animation content types, normalization, validation, timeline edit
   helpers, keyframe lookup, expansion, and playback state.
2. Add deterministic checks for legacy normalization, distribution, holds,
   expansion, looping, rescaling, edits, validation, and event positions.
3. Adapt the character runtime and editor to the shared model while preserving
   existing character behavior.
4. Adapt the weapon runtime and editor, including the source picker, duration
   blocks, attack tracks, and scroll/focus preservation.
5. Add the enemy adapter through the existing `CharacterDocument.kind ===
   'enemy'` path using the same contracts; do not create an enemy-specific
   timeline implementation or studio unless a later product decision requires
   a separate authoring surface.
6. Extract the shared timeline view and picker so all three studios render the
   same interaction model.
7. Remove duplicated timing math and update validators/check commands.

## Non-goals

- A universal hitbox, hurtbox, or combat schema.
- Moving all animation assets into a new external library in the first pass.
- Making every animated object inherit from a Phaser display-object base.
- Rewriting unrelated map, asset, or gameplay systems.

## Verification

Run deterministic coverage for:

1. Legacy character, enemy, and weapon clips normalizing identically.
2. Duration/FPS frame-count rounding and even distribution.
3. Held keyframes, occurrence metadata, transforms, and ping-pong playback.
4. Drag, reorder, duplicate, delete, and rescale behavior across all hosts.
5. Generic event positions and domain-track bounds.
6. Directional fallback and mirror resolution for weapons and characters.
7. Character, enemy, and weapon runtime completion using expanded timeline length.
8. Shared editor picker, duration blocks, ruler alignment, and scroll/focus
   preservation.

Run:

```text
pnpm typecheck
pnpm weapons:check
pnpm assets:check
pnpm build
```

Any existing unrelated asset-check failure remains separately tracked.
