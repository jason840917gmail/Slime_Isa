# Layered Animation and Confirmed-Hit Effects Design

## Summary

Slime Isa will replace the weapon-only `Impact` clip with two distinct concepts:

1. **Layered visual animation** for artwork that always accompanies an animation,
   such as a sword, swing trail, glow, or lightning arc.
2. **Confirmed-hit effects** for artwork that appears only after combat actually
   damages a target.

All visual layers share one animation clock but may use different source assets,
frames, transforms, depth offsets, and visible time ranges. Confirmed-hit effects
are reusable content packages using the same layered animation model. A weapon
references one effect package, and the runtime spawns one effect at the target
contact point for every successful damage application.

The shared layered model, clock, renderer, and editor component must not be
weapon-specific. Weapon Studio and weapon runtime are the first consumers.
Character, enemy, and projectile adapters may adopt the same foundation without
introducing another timeline implementation.

## Goals

- Author multiple synchronized visual layers inside one animation.
- Allow every layer to select a different manifest asset.
- Support transparent gaps before, between, and after layer blocks.
- Keep hitbox and event tracks synchronized with the same master timeline.
- Replace automatic timeline-driven weapon impacts with effects triggered by
  confirmed damage.
- Support Default, Right, Left, Up, and Down effect presentation with explicit
  fallback and mirroring.
- Spawn a separate effect at each target contact point when multiple targets are
  damaged.
- Preserve existing animation timing and transforms during migration.
- Keep the new timeline editor reusable across Studio screens.

## Non-Goals

- A general Godot-style graph containing arbitrary audio, callback, property,
  shader, or scene-spawn tracks.
- A particle-system or shader-effect editor.
- Attaching a confirmed-hit burst to a moving target after it has spawned. The
  contact point is captured in world space at hit time.
- Migrating every character, enemy, and projectile document in this delivery.
  Their future adapters must consume the shared foundation defined here.
- Changing hitbox geometry, damage balance, or attack-track activation semantics.

## Current Problem

Weapon Studio exposes `Idle`, `Attack`, and `Impact` clips. The runtime starts
`Impact` only when an authored `weapon.impact` timeline event fires. Basic Sword's
directional attack tracks contain no such event, so its populated Impact tab
never appears in gameplay.

Even when the event exists, `WeaponVisual` switches its single sprite from the
attack clip to the impact clip. This replaces the sword artwork rather than
overlaying an effect and fires whether or not an enemy was hit. It cannot express
a sword and trail playing together, and it cannot place impact artwork at an
enemy contact point.

## Architecture

### Shared animation clock

Timing traversal must have one owner. Extract the frame-advance, loop,
ping-pong, scrub, event-dispatch, and completion behavior currently embedded in
`AnimationPlayer` into a shared animation clock.

- `AnimationClock` advances a master timeline described by duration, FPS, loop,
  and loop mode.
- The existing single-layer `AnimationPlayer` becomes a compatibility adapter
  over that clock.
- `LayeredAnimationPlayer` resolves every visual layer at the clock's current
  timeline frame.
- Hitbox and event runners consume the same timeline-frame updates rather than
  running independent timers.

There must never be one timer per visual layer. This prevents drift and makes
Studio preview match runtime playback.

### Shared layered document

The authored layered format is independent of weapons and asset types:

```ts
interface LayeredAnimationDocument {
  readonly version: 2;
  readonly durationSeconds: number;
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: 'wrap' | 'ping-pong';
  readonly layers: readonly AnimationVisualLayerDocument[];
}

interface AnimationVisualLayerDocument {
  readonly layerId: string;
  readonly displayName: string;
  readonly assetId: string;
  readonly depthOffset: number;
  readonly transform?: AnimationLayerTransformDocument;
  readonly blocks: readonly AnimationVisualBlockDocument[];
}

interface AnimationVisualBlockDocument {
  readonly from: number;
  readonly through: number;
  readonly sourceFrame: number;
  readonly transform?: AnimationBlockTransformDocument;
}

interface AnimationBlockTransformDocument {
  readonly offset?: readonly [number, number];
  readonly scale?: readonly [number, number];
  readonly rotationDeg?: number;
  readonly flipX?: boolean;
  readonly flipY?: boolean;
}

interface AnimationLayerTransformDocument extends AnimationBlockTransformDocument {
  readonly origin?: readonly [number, number];
}
```

`from` and `through` are inclusive master timeline-frame indices. A layer is
transparent when no block covers the current frame. Blocks in the same layer
must not overlap. Adjacent blocks are allowed even when they use the same source
frame because each block may have a different transform.

A saved layered animation must contain at least one layer, and every saved layer
must contain at least one block. The Studio may temporarily hold an empty draft
layer while the author chooses tiles, but save remains disabled until every layer
is usable. Deleting the final block or layer is allowed only in draft state.

Layer transforms provide stable placement for an entire source asset. Block
transforms are composed afterward and support occurrence-specific edits.
Transforms do not alter hitbox geometry.

Layered animations always persist `version: 2` and use `layers`; legacy
single-layer clips have no animation-level version and use `frames`. This
structural discriminator is unambiguous because v2 forbids `frames`,
`keyframeTimes`, and `frameTransforms` at the animation root. Legacy weapon
documents use package `version: 1`; newly saved layered weapons use package
`version: 2`. Input normalization accepts the v1/v2 union, while the Studio only
writes v2 after migration. A migrated weapon saves `animations.idle` and every
directional `animation` as layered v2, adds optional `onHitEffectId` and
`presentation.facingMode`, and omits root
`animations.attack`, root `animations.impact`, root `assetId`, `visual`,
`attackTrack`, and `hitboxes` after all directional packages have migrated.
Normalization continues reading those root fields for legacy weapons only.

The v2 weapon contract requires `animations.idle`, directional Right, Up, and
Down packages, and permits an optional Left package that otherwise mirrors
Right. Each directional package owns its layered animation, character action,
hitboxes, and attack track. `presentation.facingMode` controls Idle orientation;
directional packages retain the existing authored/mirrored presentation rules.

The layered master clock requires an integer `framesPerSecond` from `1` through
`240` and a positive finite duration whose product with FPS is within `1e-6` of
an integer. The normalized timeline frame count is that integer. Attack clips
must be non-looping. A legacy weapon attack authored with `loop: true` remains
readable but normalization coerces it to one-shot playback; migration writes
`loop: false` while preserving its source-frame sequence for one traversal. Idle
clips preserve wrap/ping-pong looping. Confirmed-hit effects are coerced to
non-looping during legacy conversion and must validate as non-looping once saved.
Hitbox spans and events therefore run once per attack and never repeat
independently of the visuals.

### Layered visual renderer

`LayeredAnimationVisual` owns a small reusable sprite set, one sprite per authored
layer. It depends on:

- a normalized layered animation;
- an anchor adapter that supplies world position, base depth, direction, and
  presentation mirroring;
- the shared animation clock; and
- the asset manifest for texture/frame resolution.

At each clock frame, it hides layers with no active block and updates active
sprites with the resolved source frame and composed transform. Draw order begins
with authored layer order and then applies `depthOffset` inside the anchor's
attachment depth band. Directional mirroring applies to the complete visual
composition; block-level flips apply afterward.

The renderer must pool or reuse sprites during playback. It must not create and
destroy Phaser sprites on every frame.

Transform composition is explicit and does not use matrix inheritance between
layer and block transforms:

- Sprite origin is the layer `origin`, defaulting to `[0.5, 0.5]`; blocks cannot
  override origin.
- Local position is `layer.offset + block.offset`. Composition mirroring negates
  its X component, then host facing rotation rotates the complete local offset
  before adding the world anchor.
- Scale is component-wise `layer.scale × block.scale`, with missing values equal
  to `[1, 1]`. Authored scale values stay positive; flips are separate booleans.
- Effective X flip is `hostMirror XOR layer.flipX XOR block.flipX`; effective Y
  flip is `layer.flipY XOR block.flipY`.
- Local rotation is `layer.rotationDeg + block.rotationDeg`. Composition
  mirroring negates local rotation; host rotation is added last.

Layer origin is a normalized Phaser sprite origin and is not numerically
mirrored; the effective X flip reflects artwork around that authored pivot. These
rules are the single transform resolver used by Studio and runtime. Legacy weapon
migration creates the `base` layer with the old `assetId`; maps `visual.origin`,
`visual.scale`, and `visual.sourceOffset` into its layer transform; folds the selected
`visual.animationOffsets` value into the layer offset for each migrated clip;
and folds `visual.frameOffsets` plus `frameTransforms` into each block transform.
This mapping must be covered by parity tests before legacy fields are omitted.

### Host adapters

Adapters connect shared animation to domain owners:

- `WeaponAnimationAdapter` anchors layers to the player and applies weapon
  direction inheritance.
- `WorldEffectAdapter` anchors a non-looping effect to a captured world point.
- Future character, enemy, and projectile adapters provide their own anchors and
  depth policies while reusing the same player and renderer.

Domain adapters may select clips and anchor behavior, but may not implement
their own frame timing or layer resolution.

The domain owner creates and owns one clock for the active clip, starts it before
the first frame is rendered, advances it once during the owner's normal update,
and receives its single completion callback. Weapon combat subscribes its
hitbox/event runner to that clock; `WeaponVisual` subscribes the layered renderer.
On completion, the weapon combat owner ends the attack and returns the visual to
Idle. The scene never updates a second attack timer.

Clock frame dispatch order is fixed: update visual-layer state, apply hitbox span
open/close transitions, dispatch authored events, and finally dispatch completion.
`CombatController.update` advances the weapon clock before `hitboxPool.update`,
so collision and visible layers observe the same master frame.

## Confirmed-Hit Effect Packages

Reusable effects live in `src/game/content/effects/<effect-id>/effect.json` and
are loaded through an effect catalog. Media metadata remains in
`asset/assets.json`; effect documents own animation and presentation behavior.

```ts
interface EffectDefinition {
  readonly version: 1;
  readonly effectId: string;
  readonly displayName: string;
  readonly default?: LayeredAnimationDocument;
  readonly directions?: Partial<Readonly<Record<
    'right' | 'left' | 'up' | 'down',
    LayeredAnimationDocument
  >>>;
  readonly mirrorLeftFromRight?: boolean;
}
```

Every confirmed-hit effect must normalize to a finite, non-looping clip. Variant
resolution is deterministic:

1. Use the exact authored direction when present.
2. For Left only, use mirrored Right when `mirrorLeftFromRight` is enabled.
3. Use `default` when present.
4. If no variant resolves, the package is invalid and is rejected by validation.

Every valid package must resolve all four cardinal directions through exact,
mirrored, or Default variants. A missing package reference at runtime skips the
visual and emits a development diagnostic; it never cancels damage or interrupts
an attack.

A resolved effect variant is usable only when it contains at least one validated
layer with at least one validated block. Empty variants do not satisfy
directional coverage. Effect Studio may hold an empty draft while authoring, but
cannot save it or assign it to a weapon.

A weapon references an optional `onHitEffectId`. One package contains its own
directional variants, so the weapon does not need four effect properties.

The effect catalog is generated from `src/game/content/effects/**/effect.json`
using the same virtual-module pattern as weapons. Each package has a revision
hash and optimistic-concurrency API. Effect layer asset pickers accept manifest
spritesheets that are members of the existing Boot bundle. The import flow adds
newly registered effect spritesheets to that bundle. Boot preloads and asserts
those textures before gameplay, and weapon/effect checks fail when a referenced
asset is absent from the bundle.

## Confirmed Damage Flow

The generic hitbox pool remains responsible only for overlap detection and
per-activation hit suppression. It does not spawn effects.

The weapon wraps its pooled hit handler with immutable attack metadata:

- weapon ID;
- authored hitbox ID;
- attack direction and normalized attack vector; and
- attack/playback ID.

The combat owner captures contact bounds before applying damage, then calls a
shared `DamageableTarget.applyDamage(request): DamageApplicationResult` adapter.
Enemy and Target Dummy wrappers implement the contract without forcing all game
entities to inherit a common class:

```ts
interface DamageApplicationResult {
  readonly status: 'accepted' | 'rejected';
  readonly actualDamage: number;
  readonly defeated: boolean;
  readonly reason?: 'dead' | 'invulnerable' | 'invalid';
}
```

`actualDamage` is capped HP actually removed, so overkill reports remaining HP,
not requested damage. The adapter catches no exceptions: an unexpected target
exception remains a programming error, while normal rejection is represented by
the result. An effect is confirmed only for `accepted` with `actualDamage > 0`. A
miss, rejected hit, dead target, invulnerable target, or zero-damage result does
not spawn an effect.

For every confirmed damage result:

1. Resolve the target's active physics-body bounds, falling back to visual bounds.
2. Resolve the cardinal attack vector captured by the weapon attack snapshot:
   Right `(1, 0)`, Left `(-1, 0)`, Up `(0, -1)`, or Down `(0, 1)`. Raw facing,
   knockback, and attacker-to-target vectors never select the effect direction.
3. Starting at the target center, trace opposite the incoming vector to the edge
   of the axis-aligned target bounds. This near edge is the contact point.
4. Fall back to the pre-damage target center if bounds are invalid. A weapon
   snapshot cannot contain a zero/diagonal vector; non-weapon future adapters
   must quantize their source vector with the same dominant-axis rule, defaulting
   to Right only when both components are invalid or zero.
5. Resolve the weapon's `onHitEffectId` and directional effect variant.
6. Spawn one pooled effect instance at the captured world-space point.

Because bounds are captured before damage, a fatal hit can still resolve the
contact edge after the target disables its body. The contact effect does not
follow the target after spawning. A multi-target
attack creates one independent effect per target that actually receives damage.
A deliberately multi-hit attack creates an effect for each successful damage
application, while each hitbox activation's existing hit set prevents effects on
every overlap tick.

A rejected damage result is still consumed by that activation's existing hit
set; the same continuously overlapping hitbox does not retry later or spawn a
delayed effect after invulnerability changes.

Damageable development targets use the same confirmed-damage path so effects can
be tested against target dummies.

## Weapon Studio Design

### Animation tabs

The weapon-level `Impact` animation tab is removed. `Idle` and each directional
`Attack` use the shared layered timeline editor.

The former Impact area becomes `On Hit`:

- select or clear a reusable effect package;
- create a package from a legacy Impact clip when it satisfies the migration
  rules below;
- edit Default, Right, Left, Up, and Down variants;
- enable or disable Left mirroring from Right; and
- clearly label the effect as shared content because editing it may affect other
  weapons that reference the same ID.

Weapon and effect documents have separate dirty states and save operations.
Saving an effect does not silently save a weapon, and saving a weapon does not
silently overwrite shared effect content.

### Layered timeline component

The existing shared animation timeline panel evolves into a reusable layered
component. Weapon Studio configures it with weapon-specific hitbox and event rows;
the visual lane behavior itself remains domain-neutral.

The panel contains:

- one shared seconds ruler and playhead;
- ordered visual lanes;
- hitbox and event rows beneath visual lanes when supplied by the host;
- `Add Layer`, playback, duration, FPS, and loop controls; and
- selected-layer controls for source asset, depth offset, visibility isolation,
  display name, ordering, and deletion.

Layer visibility and solo/mute controls affect only the Studio preview and are not
saved. Runtime layers are visible whenever they have an active block.

### Editing behavior

- Selecting a lane scopes the asset shelf, Add Tiles dialog, and transform
  controls to that layer.
- `Add Tiles` shows frames from the selected layer's asset only.
- Chosen tiles are inserted consecutively from the playhead. If the proposed
  cells overlap an existing block or exceed the master duration, insertion is
  rejected without shifting other blocks.
- Clicking a block selects that block and moves the playhead to its first frame.
- Dragging a block body moves it horizontally, snapped to frame cells.
- Dragging its right edge adjusts `through`, using the same pointer-capture and
  commit-on-release lifecycle as the current hold resize control.
- The existing plus/minus controls edit the clicked block, never merely the
  previously selected block.
- Deleting a block leaves transparent time rather than closing the gap.
- Up/Down controls reorder layers. `depthOffset` handles exceptional ordering.
- Duration reduction is rejected when any visual block, hitbox span, or event
  would fall outside the shortened timeline.
- FPS changes preserve timeline frame indices and may therefore change wall-clock
  duration. The Studio immediately recomputes `durationSeconds` as
  `timelineFrameCount / newFPS`; it never resamples or shifts blocks, hitboxes, or
  events. A separate Duration edit changes timeline frame count and uses the
  out-of-range guard above.
- Duration input snaps to the nearest whole master frame and displays the
  effective snapped seconds. Saved `durationSeconds × framesPerSecond` must remain
  an integer within the normalization tolerance.
- Preview, selection summary, ruler, layers, hitboxes, and events use the same
  master frame and cannot advance independently.

## Migration and Compatibility

### Legacy single-layer clips

Legacy animation clips remain accepted as input. Normalization converts each to
one `base` visual layer using the owning package's current asset ID:

- legacy keyframe start times become block `from` values;
- the next keyframe start minus one becomes `through`;
- the last block ends at the final master timeline frame; and
- legacy frame transforms become block transforms.

This conversion must preserve expanded frame output, duration, Idle looping, and
occurrence transforms. Legacy attack and Impact clips are the explicit exception:
they migrate to one-shot playback as defined above. The migrated Studio writes
the layered representation on the next explicit save; merely loading a document
does not mutate disk.

Before migration:

```json
{
  "version": 1,
  "assetId": "weapon.player.sword-tiles",
  "animations": {
    "idle": { "frames": [0], "framesPerSecond": 8, "loop": true },
    "impact": { "frames": [16], "framesPerSecond": 12, "loop": false }
  },
  "directionalAttacks": {
    "right": {
      "animation": { "frames": [0, 3], "keyframeTimes": [0, 3], "durationSeconds": 0.25, "framesPerSecond": 24, "loop": false }
    }
  }
}
```

After migration (unrelated combat fields omitted):

```json
{
  "version": 2,
  "onHitEffectId": "basic-sword-impact",
  "presentation": { "facingMode": "vector" },
  "animations": {
    "idle": {
      "version": 2, "durationSeconds": 0.125, "framesPerSecond": 8,
      "loop": true, "layers": [{
        "layerId": "base", "displayName": "Sword",
        "assetId": "weapon.player.sword-tiles", "depthOffset": 0,
        "blocks": [{ "from": 0, "through": 0, "sourceFrame": 0 }]
      }]
    }
  },
  "directionalAttacks": {
    "right": {
      "animation": {
        "version": 2, "durationSeconds": 0.25, "framesPerSecond": 24,
        "loop": false, "layers": [{
          "layerId": "base", "displayName": "Sword",
          "assetId": "weapon.player.sword-tiles", "depthOffset": 0,
          "blocks": [
            { "from": 0, "through": 2, "sourceFrame": 0 },
            { "from": 3, "through": 5, "sourceFrame": 3 }
          ]
        }]
      }
    }
  }
}
```

### Legacy weapon Impact clips

Weapon `Impact` clips and `weapon.impact` events are not kept as automatic attack
visuals. Migration follows these rules:

- When the legacy Impact clip contains usable frames and an asset ID, Weapon
  Studio creates a draft reusable effect package with a `default` variant and
  assigns its ID to `onHitEffectId`.
- Existing event payload effect IDs are offered as the new package ID when they
  are valid stable IDs.
- Conversion is one transactional development-server operation containing the
  expected weapon revision, proposed effect ID, effect draft, and migrated weapon.
  The server validates both documents and revisions, rejects an existing effect
  ID unless its exact expected revision is supplied, writes both temporary files,
  renames the effect first and weapon second, and rolls the effect back from its
  pre-write bytes if the weapon rename fails. For a newly created effect,
  rollback removes the renamed `effect.json` and its package directory when
  empty. A `finally` path removes both temporary files on every outcome. If
  compensation itself fails, the API returns a distinct
  `manual-recovery-required` 500 response with the exact affected package paths
  and does not report either document as saved. The response returns both saved
  revisions only after both renames succeed. No weapon may reference an effect
  package that failed to save.
- After conversion, obsolete `weapon.impact` events and the weapon Impact clip
  are removed from newly saved weapon data.
- If automatic conversion would only reproduce weapon artwork and cannot be
  confidently treated as an effect, the Studio shows a migration warning and
  leaves assignment to the author rather than generating misleading content.

Old documents continue to load until migrated, but the gameplay runtime must not
play legacy Impact clips automatically.

Example effect package:

```json
{
  "version": 1,
  "effectId": "basic-sword-impact",
  "displayName": "Basic Sword Impact",
  "mirrorLeftFromRight": true,
  "default": {
    "version": 2, "durationSeconds": 0.125, "framesPerSecond": 24,
    "loop": false, "layers": [{
      "layerId": "spark", "displayName": "Spark",
      "assetId": "weapon.player.sword-tiles", "depthOffset": 0,
      "blocks": [{ "from": 0, "through": 2, "sourceFrame": 16 }]
    }]
  },
  "directions": {
    "right": {
      "version": 2, "durationSeconds": 0.125, "framesPerSecond": 24,
      "loop": false, "layers": [{
        "layerId": "spark", "displayName": "Spark Right",
        "assetId": "weapon.player.sword-tiles", "depthOffset": 0,
        "blocks": [{ "from": 0, "through": 2, "sourceFrame": 16 }]
      }]
    }
  }
}
```

Browser SaveSystem migration is unnecessary because persisted player state stores
stable weapon IDs, not weapon or effect documents.

## Validation and Diagnostics

Authoring/catalog validation rejects an entire animation variant when any layer
is malformed; it never saves a partially valid variant. Runtime defense is more
permissive only for stale or externally modified content: it skips the invalid
layer, continues valid sibling layers, and emits a diagnostic. If no valid layers
remain, the visual variant is skipped. Shared authoring validation rejects:

- non-positive or non-finite duration/FPS;
- duplicate or invalid stable layer IDs;
- missing/non-spritesheet layer assets;
- source frames outside the selected asset;
- blocks with invalid or out-of-range inclusive bounds;
- overlapping blocks within one layer;
- non-finite transforms or non-positive scale values; and
- loops on confirmed-hit effect variants.

Effect validation rejects duplicate effect IDs, definitions that cannot resolve
all four directions, invalid directional keys, and Left mirroring without a Right
variant or Default fallback.

Runtime diagnostics are development-only and deduplicated per content ID. A bad
visual layer or effect is skipped. Combat and scene update continue.

## Performance and Lifecycle

- One clock drives every layer of an active animation.
- Layer sprites are reused for the life of an entity visual.
- Contact effects use a scene-owned pool and return to it on clip completion.
- Effect instances have a safety timeout derived from normalized duration so a
  malformed completion callback cannot leak sprites.
- Scene shutdown explicitly releases every active effect. Once confirmed and
  spawned, a world contact effect is scene-owned and finishes normally even if
  the originating attack is canceled, its weapon is replaced, or its owner is
  destroyed. Those owner lifecycles release only their clocks, entity-layer
  sprites, and listeners.
- Studio preview timers and DOM listeners follow the existing explicit cleanup
  lifecycle.

## Testing

### Shared animation tests

- legacy single-layer normalization preserves expanded playback;
- multiple layers resolve against one master frame without drift;
- leading, interior, and trailing transparent gaps hide the layer;
- block transforms compose after layer transforms;
- layer order and depth offsets resolve deterministically;
- wrap, ping-pong, scrub, large delta, completion, and cancellation semantics;
- invalid overlapping and out-of-range blocks are rejected.

### Studio tests

- add, select, rename, reorder, preview-hide, and delete layers;
- select different assets per layer;
- Add Tiles targets the selected lane and rejects overlaps/overflow;
- clicked plus/minus controls and right-edge drag resize the clicked block;
- block dragging snaps to master frames and preserves gaps;
- duration reduction guards visual blocks, hitbox spans, and events;
- preview stays synchronized across all lanes and combat tracks;
- weapon/effect dirty states and saves remain independent;
- legacy clip and Impact migration require explicit save.

### Runtime and combat tests

- weapon, trail, and effect layers remain synchronized in all directions;
- mirrored Left presentation affects the complete composition correctly;
- attack misses create no confirmed-hit effect;
- invulnerable, dead, rejected, and zero-damage targets create no effect;
- one successful hit creates one effect at the near contact edge;
- one swing damaging several targets creates one effect at each contact point;
- intentional multi-hit damage creates one effect per successful damage result;
- exact direction, mirrored Right-to-Left, Default fallback, and missing-effect
  diagnostics;
- effect pooling, completion, safety timeout, and scene shutdown cleanup, plus
  confirmation that attack cancellation and weapon replacement do not terminate
  already spawned scene-owned effects;
- production mode does not expose development diagnostics or authoring overlays.

## Delivery Sequence

1. Add shared layered types, normalization, validation, clock, player, renderer,
   and compatibility adapter with focused tests.
2. Evolve the shared timeline editor into visual lanes and migrate Weapon Studio
   attack/idle authoring to it.
3. Add the reusable effect catalog, directional resolver, editor surface, and
   content validation.
4. Refactor weapon hit results and combat confirmation, add contact-point
   resolution, pooling, and runtime effect playback.
5. Migrate current weapon documents and remove automatic `weapon.impact`
   playback and the legacy Impact tab.
6. Verify Studio/runtime parity and run the full repository checks.

Future character, enemy, and projectile adoption begins only after this shared
foundation is stable; those consumers must use adapters rather than copy the
timeline or renderer.

## Acceptance Criteria

- An authored attack can render a sword, trail, and lightning layer from three
  different assets on one synchronized timeline.
- Layers can contain transparent gaps and independent block transforms.
- The same shared model/player/editor component, not a weapon-only clone, powers
  layered authoring and playback.
- A miss never displays an On Hit effect.
- For a weapon configured with `onHitEffectId`, every target that receives damage
  gets an effect at its contact point using the correct directional variant or
  documented fallback.
- The old weapon Impact tab and automatic `weapon.impact` playback no longer
  exist in newly saved content or gameplay.
- Legacy clips load with visual parity and migrate only on explicit save.
- Missing visual content cannot prevent damage or leave runtime objects behind.
