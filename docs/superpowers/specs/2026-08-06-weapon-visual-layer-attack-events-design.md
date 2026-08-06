# Weapon Visual Layer and Attack-Event Authoring Design

## Status

Approved by the user on 2026-08-06.

## Summary

Upgrade the weapon system so equipped weapons render as a separate visual layer attached to the player’s existing gameplay anchor. Character action clips remain reusable and are selected by the weapon through `animKey`; weapon source sheets author the weapon’s idle, attack, and impact frames. Weapon attack timing becomes event-driven: named weapon hitboxes activate on authored attack-frame spans, and optional frame events support impact effects and other presentation hooks.

Both Character Studio and Weapon Studio must support the complete authoring loop. A shared composite preview starts the character and weapon clips together, preserves each clip’s own frame rate, exposes live attachment alignment, and displays all named hitboxes, active spans, and events while scrubbing.

## Goals

- Keep one character compatible with many weapons without baking weapons into character sheets.
- Support authored weapon attack frames rather than requiring static weapon tiles.
- Reuse existing character actions such as `slime-trick`, `slime-cast`, or `idle` while weapon art owns weapon-specific motion.
- Synchronize gameplay hitbox activation with weapon attack-frame spans.
- Support multiple named weapon hitboxes and multiple active windows per hitbox.
- Expose attachment alignment and complete combined playback in both studios.
- Preserve existing weapons through a normalization/fallback path during migration.
- Keep gameplay ownership outside `WorldScene`; controllers receive narrow context interfaces.

## Non-goals

- Creating a skeletal/bone animation system.
- Baking character-plus-weapon combinations into new character sheets.
- Replacing the existing character animation track editor.
- Reworking ranged projectile gameplay in this slice beyond providing generic weapon events.
- Making editor-only preview character selection part of the saved runtime weapon definition.

## Current state and constraints

- `Weapon.attack()` currently owns damage calculation, hitbox spawning, cooldown, character animation triggering, and procedural slash VFX.
- `CombatController` constructs the equipped `Weapon` and provides the player, facing, targets, hit handler, and animation callback.
- The player is an invisible Arcade physics sprite with an `AnimatedVisual` render layer attached to it.
- `WeaponDefinition` already contains optional `assetId`, weapon animation clips, and `visual.sourceOffset`, but live runtime code does not consume them yet.
- Character Studio already authors source frames, clips, named hitboxes, hitbox spans, and frame events.
- Weapon Studio already has source-sheet selection, animation tabs, visual offset fields, and frame-list editing, but does not yet render the runtime weapon layer or author weapon hitbox tracks.
- Existing weapon fields (`hitboxWidth`, `hitboxHeight`, `hitboxOffset`, and `hitboxDurationMs`) are currently singleton combat values and must remain readable during migration.

## Architecture

### Stable anchor and render layers

The existing player physics sprite remains the stable gameplay anchor. The runtime composition is:

```text
Player physics anchor
├── Character AnimatedVisual
└── WeaponVisual
```

`WeaponVisual` is a render-only layer that follows the same anchor rather than becoming a physics body or requiring a Phaser `Container`. It owns its sprite, animation registration, source-frame transform, facing behavior, depth slot, and cleanup listeners. It must not resize or move the player’s Arcade body.

`PlayerFactory` continues to own construction of the player anchor and character `AnimatedVisual`. `CombatController` owns the equipped weapon runtime: the normalized `Weapon`, its `WeaponVisual`, and its weapon attack track runner. `CombatController.update()` advances the runner and visual after player movement has updated the anchor. Equipping or replacing a weapon destroys the previous visual and runner before creating the new pair. `CombatController.destroy()` destroys the current weapon visual/runner and unregisters all timers and scene listeners. `WorldScene` only passes the player anchor, depth resolver, asset resolver, and combat callbacks through the controller context.

Attack lifecycle is explicit. `CombatController` receives `setActionLocked(locked)` in its context. On a successful attack it sets the lock, stops player velocity, and starts the character/weapon clips. Runner completion or cancellation closes every hitbox, destroys the attack timers, clears the lock, and requests normal idle presentation. This replaces the current independent delayed `onAttackEnd` path and prevents normal movement input from overwriting the attack animation.

The attachment transform is resolved from the weapon definition using this precedence:

```text
weapon.visual.sourceOffset
→ weapon.visual.animationOffsets[animationId]
→ weapon.visual.frameOffsets[frame]
```

More-specific values override less-specific values. Origin, scale, and facing mode follow the same explicit contract. Runtime depth is derived from the player world-depth resolver and an attachment slot; authoring does not directly write world depth values.

### Character and weapon playback

`characterActionId` is the stable character action relationship. At attack start:

1. CombatController asks the weapon to begin its attack.
2. WeaponVisual starts the weapon attack clip.
3. The context plays the character action clip from `characterActionId`.
4. A weapon attack track runner advances against elapsed attack time.
5. Track transitions activate/deactivate named hitboxes and dispatch optional events.
6. When the weapon attack completes, the weapon visual returns to idle and the character returns to its normal idle/movement presentation.

Character and weapon clips keep independent FPS and frame sequences. The runtime starts them together but does not force them to share frame indices. The weapon attack timeline is authoritative for weapon hit timing.

The existing `animKey` field remains a legacy alias. Normalization strips the old `slime-` runtime prefix when present. Runtime code resolves the normalized action ID through a context callback such as `playCharacterAction(actionId)`, which converts the character document clip ID into the correct visual runtime key. Weapon content does not store a Phaser runtime animation key and does not hardcode the player visual set.

### Attack track runner

Add a weapon-specific track runner following the behavior of `CharacterAnimationTrackRunner` without coupling weapon definitions to `CharacterDocument`. It must:

- start, cancel, pause, resume, and update an attack clip;
- expose current clip, position, elapsed time, and active hitbox IDs;
- activate and deactivate spans when the frame position changes;
- support multiple non-overlapping spans for the same hitbox ID;
- issue a unique activation ID for every span activation;
- dispatch one-frame events exactly once per playback position;
- disable all active spans on completion, cancellation, destruction, or scene shutdown.

Weapon hitbox activation must not be implemented as a button-press-only delayed call. Legacy fallback may use the old immediate behavior only when an old weapon has no authored attack track.

## Runtime data model

Extend `WeaponDefinition` with weapon-owned visual and attack-track data. The exact names should follow existing character conventions where possible.

```ts
interface WeaponHitboxDocument {
  readonly shape: 'rectangle' | 'circle' | 'ellipse' | 'sector';
  readonly width: number;
  readonly height: number;
  readonly radius?: number;
  readonly radiusX?: number;
  readonly radiusY?: number;
  readonly offsetX: number;
  readonly offsetY: number;
  readonly innerRadius?: number;
  readonly outerRadius?: number;
  readonly arcWidthRad?: number;
  readonly damageMultiplier?: number;
  readonly knockbackMultiplier?: number;
}

interface WeaponAttackTrackDocument {
  readonly hitboxSpans: readonly WeaponHitboxSpanDocument[];
  readonly events?: readonly WeaponEventDocument[];
}

interface WeaponHitboxSpanDocument {
  readonly hitboxId: string;
  readonly from: number;
  readonly through: number;
}

interface WeaponEventDocument {
  readonly at: number;
  readonly eventId: string;
  readonly payload?: JsonValue;
}
```

The weapon definition adds:

```ts
readonly characterActionId?: string;
readonly hitboxes?: Readonly<Record<string, WeaponHitboxDocument>>;
readonly attackTrack?: WeaponAttackTrackDocument;
readonly visual?: {
  readonly sourceOffset: readonly [number, number];
  readonly animationOffsets?: Readonly<Record<string, readonly [number, number]>>;
  readonly frameOffsets?: Readonly<Record<string, readonly [number, number]>>;
  readonly origin?: readonly [number, number];
  readonly scale?: readonly [number, number];
  readonly facingMode?: 'vector' | 'horizontal-flip';
};
```

For legacy definitions without `hitboxes`, normalize the old singleton values into a `primary` hitbox. For legacy definitions without `attackTrack`, normalize a fallback span matching the previous immediate-hit behavior. New Studio-created definitions should save the explicit named-hitbox and attack-track form.

Weapon hitbox geometry should be converted into the existing `HitboxConfig` at activation time. Sector geometry retains the current player-facing arc behavior; rectangle/circle/ellipse geometry must be resolved consistently with the authored offsets and current facing. Each activation receives its own hit-once target set so repeated spans can hit again intentionally.

### Coordinate and facing contract

- Weapon visual offsets, frame offsets, origin, and source-sheet alignment are authored in source pixels, then multiplied by the resolved visual scale.
- Weapon hitbox dimensions and offsets are authored in world units, independent of source pixels and sprite scale.
- The default `vector` facing mode assumes the source frame points right. The local +X axis and local offsets rotate to `atan2(facing.y, facing.x)`.
- `horizontal-flip` leaves the weapon unrotated and mirrors only for left-facing horizontal presentation; it is intended for flat or character-specific art.
- Hitbox local offsets rotate with the facing vector. Sector hitboxes use the captured attack angle; rectangle/circle/ellipse geometry uses the rotated local center and shape dimensions.
- Origin is normalized 0–1 and scale is a positive multiplier. Source offsets do not change the player body or gameplay anchor.

### Weapon hitbox lifecycle

`HitboxPool.spawn()` must return an activation handle with `deactivate()` and `isActive`. Active hitboxes remain registered until the track runner closes their span or the handle duration expires. `HitboxPool.update(scene)` performs overlap checks for every active handle each frame, so targets can enter an active hitbox after the initial frame. Every handle retains its own hit-once set. `HitboxPool.clearScene()` deactivates all handles before destroying pooled zones and graphics.

The combat update path calls the pool update once per frame. Track span close events explicitly deactivate their handle; legacy fallback may still use a timed handle. Circle and ellipse weapon hitboxes require explicit intersection helpers in `HitboxPool`; they must not be silently coerced to rectangles. Their broad-phase Arcade zone may remain rectangular, but the final overlap test uses the authored geometry against target bounds.

### Playback, events, and damage snapshots

Weapon attack clips are non-looping. Frame position follows the shared animation contract: `step = floor(elapsedMs / (1000 / framesPerSecond))`, with spans inclusive of both `from` and `through`. The runner processes every crossed step in order, so skipped render frames cannot skip hitbox transitions or events. A non-looping attack completes after its authored frame sequence; active spans are closed before completion callbacks run. Idle clips loop; impact clips are non-looping. A span is active from the time its `from` frame is entered until the next position after `through` is entered.

Built-in event IDs are resolved through an explicit weapon event registry/context. `weapon.impact` plays the impact clip; repeated `weapon.impact` events may restart it. Unknown event IDs do not mutate gameplay and produce a diagnostic/editor warning. Event payloads remain JSON values and are passed to the context for future VFX, sound, projectile, or status-effect consumers.

Damage, critical-roll result, knockback scaling, and other attack stats are snapshotted once at attack start. Each activated hitbox applies its own `damageMultiplier` and `knockbackMultiplier` to that snapshot. Repeated spans receive new activation IDs and can hit the same target again by design. Combo registration remains per accepted target hit, as in the current combat controller.

## Studio workflow

### Shared composite preview

Create a shared preview controller/view-model used by both studios. It owns:

- selected character package and action clip;
- selected weapon definition;
- combined elapsed playback time;
- character and weapon frame resolution using independent FPS;
- weapon attachment transform resolution;
- active weapon hitboxes and frame events;
- play, pause, previous-frame, next-frame, scrub, and reset controls.

The preview must show the character and weapon together while authoring. Scrubbing changes both visual layers and the hitbox/event overlay at the same elapsed time. If one clip ends before the other, its last frame is held until the preview attack duration completes. Changing source asset, clip, frame, offset, hitbox, span, or event must update the composite preview immediately.

### Character Studio responsibilities

Character Studio continues to own the character package, character visual set, character clips, character hitboxes, and character animation tracks. Add a weapon-preview integration that:

- exposes the character’s available action clips to the weapon workflow;
- lets the author select a weapon from the catalog for preview only;
- plays the selected character clip with the selected weapon attack clip;
- displays the weapon attachment and all weapon hitbox/event overlays;
- keeps character hitbox and event editing available for character-owned combat;
- warns when a selected weapon references an action clip missing from the current character.

Preview selection must not add a runtime weapon dependency to a character package.

### Weapon Studio responsibilities

Weapon Studio becomes the complete weapon authoring surface:

- identity, category, combat profile, scaling, source asset, and character action clip;
- weapon attachment offset, origin, scale, facing mode, and optional animation/frame offsets;
- idle, attack, and impact source-frame timelines;
- named weapon hitbox creation, editing, removal, and geometry preview;
- attack timeline rows for every named hitbox;
- multiple active spans per hitbox;
- one-frame weapon events and payload editing;
- selected preview character/action and combined playback;
- validation status and save blocking for invalid hitbox or track data.

The weapon timeline should use the same frame-strip and row interaction language as Character Studio: selected frame, hitbox span cells, event markers, add/remove controls, frame insertion/removal/reordering, playback controls, and live preview.

## Validation and error handling

Weapon validation must check:

- if `assetId` is present, the source asset exists and is tagged `weapon`;
- if `assetId` is present, the source asset is available through the runtime asset manifest/loading bundle when the weapon is used in gameplay;
- every animation frame is inside the source frame count;
- idle, attack, and impact clips contain at least one frame;
- hitbox IDs are valid and unique;
- every span references an existing hitbox;
- span frame indexes are integers, ordered, and inside the attack clip;
- event frame indexes are inside the attack clip;
- shape-specific dimensions and radii are valid finite non-negative values;
- attachment offsets, origin, and scale are valid finite values;
- at least one of authored `characterActionId` or legacy `animKey` is present and non-empty;
- new Studio-created weapons use `characterActionId` and do not require a Phaser runtime key;
- preview-character clip availability is editor validation only and is not a saved weapon dependency.

The editor/server validation path uses the shared character asset catalog and manifest metadata rather than assuming that a source file exists only because a JSON field is present. Runtime loading must preload registered weapon sheets through the existing asset-loading path before WorldScene creates a weapon visual. The current missing generated `weapons-64x64.png` entry must either be supplied as a real registered asset or removed from the ready runtime manifest before enabling that weapon.

For this implementation, absent `assetId` is allowed only for legacy/procedural fallback weapons. Any weapon with an `assetId` must be manifest-registered, weapon-tagged, loadable by the boot asset path, and backed by a real file. The stale `weapon.player.generated-64` manifest entry should be removed until a real sheet is supplied; future Studio imports register real files through the existing asset workflow.

Editor save controls must remain disabled or show actionable validation errors. Runtime must fail safely: an invalid optional weapon visual cannot move the player body, and an interrupted attack must deactivate all active hitboxes before returning to normal presentation.

## Migration

- Keep legacy singleton weapon fields readable during the transition.
- Introduce separate authored and normalized types. The authored type accepts the legacy `animKey` alias or the new `characterActionId`; `NormalizedWeaponDefinition` always contains a resolved `characterActionId`, resolved hitboxes, resolved visual defaults, and explicit attack-track mode. Apply `normalizeWeaponDefinition()` at the catalog boundary, editor load/save boundary, and runtime weapon-construction boundary so every consumer sees the canonical form.
- Normalize old fields to a `primary` weapon hitbox at load time.
- Normalize missing attack tracks to a marked legacy immediate-hit fallback; new definitions and Studio saves use explicit tracks.
- Migrate Goo Gauntlet to an explicit attack frame sequence, named `primary` hitbox, and at least one authored active span while keeping its missing-asset/procedural-VFX fallback until a real sheet is registered.
- Keep the existing procedural slash effect as a fallback/secondary presentation until weapon impact visuals are fully authored.
- Register weapon source sheets through the existing asset manifest workflow; do not create a second asset registry.

Legacy `animKey` values normalize to `characterActionId` by removing the `slime-` prefix when present. New Studio saves write `characterActionId`; the legacy field is retained only where required for compatibility.

For each `hitboxId`, overlapping spans are invalid and must be rejected by validation. Adjacent spans may be canonicalized into one continuous span; separated spans are allowed and create separate activation IDs. The runtime active map is therefore keyed by hitbox ID for the currently active non-overlapping span, while activation IDs distinguish repeated windows over the lifetime of one attack.

## Verification plan

Add focused deterministic coverage for:

1. Track activation/deactivation across two separated spans for one hitbox.
2. Two hitboxes active on different frames and the same frame.
3. Unique activation IDs and hit-once reset between repeated spans.
4. Track cancellation and completion cleanup.
5. Independent character/weapon FPS resolution at shared elapsed times.
6. Legacy normalization of singleton hitbox fields.
7. Validation failures for missing IDs, out-of-range frames, invalid shapes, and missing assets.
8. Persistent hitbox overlap checks while a span remains active and explicit handle cancellation at span close.
9. Character action ID resolution to a visual runtime key without saving a preview-character dependency.

Run the project checks proportionally after implementation:

```text
pnpm typecheck
pnpm weapons:check
pnpm assets:check
pnpm build
pnpm check
```

Manual Studio acceptance:

- Create a weapon from a source sheet.
- Define idle, attack, and impact frames.
- Add two named hitboxes.
- Add two separated spans for one hitbox and one span for the other.
- Add an impact event.
- Preview the character and weapon together while scrubbing.
- Confirm hitbox overlays match the authored rows.
- Change attachment offsets and confirm only weapon artwork moves.
- Save, reload, and confirm all frames, hitboxes, spans, events, and attachment settings persist.

## Expected implementation boundaries

Likely production changes are expected in:

- `src/game/content/weapons/types.ts`, schema, validation, and normalization;
- `src/game/combat/Weapon.ts` and a new weapon attack track/visual runtime module;
- `src/game/features/combat/CombatController.ts` and player composition context;
- shared timeline/preview/editor helpers;
- `src/game/editor/CharacterStudio.ts` and `CharacterDocumentState.ts`;
- `src/game/editor/WeaponStudio.ts`;
- weapon content and asset manifest entries;
- weapon validation/check scripts;
- focused tests or deterministic verification helpers;
- `docs/STUDIO_TABS.md` and architecture documentation as needed.

No implementation should move gameplay ownership into `WorldScene`; it should continue acting as a composition root and pass explicit dependencies into feature controllers.
