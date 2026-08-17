# Center-Following Confirmed-Hit Effects Design

**Date:** 2026-08-17  
**Status:** Approved for implementation planning

## Context

Confirmed weapon hits currently capture the target's combat-body geometry before
damage, derive a point on the body's incoming edge, and spawn a scene-owned effect
at that fixed world-space point. The effect therefore stays behind when knockback
or ordinary movement moves the enemy during the effect animation.

The desired presentation is simpler: a confirmed-hit effect appears at the
target object's center and follows that center for the rest of the animation.
Only position follows. The effect's direction, mirroring, depth, scale, rotation,
animation state, and lifetime remain the values established when it spawns.

This design supersedes only the fixed contact-edge placement and non-following
statements in
`2026-08-12-layered-animation-and-confirmed-hit-effects-design.md`. Its damage
confirmation, directional variant resolution, pooling, and scene ownership
contracts remain unchanged.

## Goals

- Spawn every accepted, positive-damage weapon effect at the damaged target's
  current `x` and `y` anchor.
- Follow the target's `x` and `y` while that target object exists, including
  movement caused by knockback.
- Keep all presentation values except target-relative position/depth fixed at spawn
  time.
- Let the effect finish independently after the target is destroyed by freezing
  it at the target's last valid position.
- Ensure pooled slots never retain a target or destruction listener across
  release, reuse, pool destruction, or scene shutdown.
- Preserve fixed world-position spawning for future or existing callers that do
  not request target following.

## Non-Goals

- Contact-edge, collision-body-center, visual-bounds-center, or visual-bounds
  offset calculations for effect placement.
- Following target rotation, scale, visibility, active state, animation, or
  facing.
- Parenting effect sprites to an enemy display object or container.
- Changing damage acceptance, hit suppression, collision detection, attack
  direction, effect content documents, asset metadata, or editor schemas.
- Canceling an effect when its originating attack, weapon, or target ends.

## Placement and Attachment Contract

The target object's Phaser transform anchor is the authoritative center for this
presentation behavior. `CombatController` passes the confirmed target itself and
uses `target.x` and `target.y` as the initial spawn coordinates. Combat-body
geometry remains authoritative for deciding whether an attack overlaps a target,
but is not consulted when placing the visual effect.

`WorldEffectSpawnRequest` retains its static `x`, `y`, and `depth` values and adds
an optional position-follow target. This keeps `WorldEffectPool` useful for static
world effects while allowing confirmed-hit callers to request attachment without
introducing a combat dependency into the effects feature. The follow target must
provide finite `x` and `y` coordinates plus Phaser's destruction-event lifecycle.

Conceptually:

```ts
interface WorldEffectPositionTarget extends Phaser.GameObjects.GameObject {
  readonly x: number;
  readonly y: number;
  readonly depth: number;
}

interface WorldEffectSpawnRequest {
  readonly effectId: string;
  readonly direction: EffectDirection;
  readonly x: number;
  readonly y: number;
  readonly depth: number;
  readonly followPositionOf?: WorldEffectPositionTarget;
  readonly followDepthOffset?: number;
}
```

The exact exported type may use the narrowest Phaser type accepted by both
`Enemy` and `TargetDummy`; it must not expose combat-specific classes from the
effects module.

For a confirmed hit, `CombatController` supplies:

- `x: hitTarget.x` and `y: hitTarget.y`;
- `depth: hitTarget.depth + 0.2`, refreshed from target depth each pool update;
- the already captured cardinal attack direction; and
- `followPositionOf: hitTarget`.

It no longer resolves a target edge or captures body geometry solely for effect
placement. Removing this caller does not require deleting the generic
`ContactPoint` utility or its tests if other code or public contracts still use
them.

## Pool Ownership and Update Flow

Each `WorldEffectPool` slot owns at most one optional attachment record. The
record contains the current target and the exact destruction callback registered
for it. A slot is the sole owner of that callback.

On spawn:

1. Clear any timeout and attachment left by the slot's previous use.
2. Reset the adapter with the request's spawn-time position, depth, and mirrors.
3. If a follow target exists, validate and copy its current finite `x`, `y`, and
   target-relative depth into the adapter, store the target, and register a
   one-shot destroy listener.
4. Start the effect animation and safety timeout as today.

On every active-pool update:

1. If the slot remains attached, copy the target's current finite `x`, `y`, and
   target-relative depth into the adapter.
2. Advance the effect clock.
3. Ask the layered visual to update its anchor.

Position/depth synchronization happens before the visual anchor update so the
rendered sprites observe the target's latest coordinates and sort depth in that
frame. `WorldEffectAdapter` therefore gains position/depth mutators such as
`setPosition(x, y)` and `setDepth(baseDepth)`. These methods must not modify
mirrors or animation state.

An inactive target is still an existing target: `active === false` alone does not
detach or stop following. This permits death or disable sequences that move or
animate an object before its actual destruction. Actual Phaser destruction is
the lifecycle boundary.

## Destruction and Cleanup

When the followed target emits `DESTROY`, the slot copies the target's final
finite `x`, `y`, and target-relative depth, removes its attachment record, and
continues playing at those fixed values. If a coordinate or depth is non-finite,
the adapter retains its most recent valid value for that component. The effect is
not canceled.

All attachment cleanup is idempotent and centralized. It must unregister the
exact listener when the target has not already destroyed itself, then clear both
the callback and target reference. Cleanup runs:

- before an inactive slot is reused;
- whenever a slot is released by completion or safety timeout;
- when the pool is destroyed; and
- during scene shutdown through the pool's existing destruction path.

The target-destroy callback must tolerate racing with effect completion or scene
shutdown. After attachment cleanup, later target movement or destruction cannot
mutate the released or reused slot.

## Confirmed-Damage Flow

The damage gate remains unchanged. A visual spawns only when
`shouldSpawnConfirmedHitEffect` accepts a damage result, meaning the target
accepted the application and actually lost positive health.

For each qualifying target:

1. Apply damage through the existing target-specific adapter.
2. Read the hit target's current `x`, `y`, and depth.
3. Spawn one effect with the target as its optional position-follow source.
4. During subsequent pool updates, copy target `x`, `y`, and target-relative
   depth until target destruction or effect release.
5. If target destruction occurs first, freeze at the final valid center and let
   the scene-owned animation finish.

A miss, rejected hit, dead or invulnerable result, and zero actual damage still
spawn no effect. A multi-target attack creates one independently attached slot
per damaged target. A deliberately multi-hit attack creates one independently
attached slot per accepted damage application, subject to the existing hitbox
activation suppression rules.

## Presentation Invariants

Once an effect spawns, all values except `x`, `y`, and target-relative base depth
are immutable for that instance:

- effect definition and animation variant;
- cardinal direction and derived mirroring;
- target-relative base-depth offset and per-layer depth offsets;
- block/layer position offsets;
- scale and rotation; and
- clock state and completion lifetime.

Layer-authored offsets remain relative to the moving target anchor. Following a
target never re-resolves the effect definition or restarts the animation.

## Architecture and Documentation Changes

- `CombatController` continues to own damage confirmation and requests the
  target-following effect.
- `WorldEffectPool` owns optional attachment state and all related listener
  cleanup because the effect lifetime is scene-owned.
- `WorldEffectAdapter` remains the small bridge between pooled placement and the
  shared layered renderer; it accepts position/depth updates.
- `LayeredAnimationVisual` remains unchanged and reads the adapter transform
  through its existing anchor update.
- `docs/ARCHITECTURE.md` must describe confirmed-hit effects as centered on and
  position-following the damaged target, replacing its contact-edge statement.

No content JSON, schema, catalog, asset manifest, or Weapon Studio change is
required.

## Validation Strategy

Focused automated coverage should prove:

- a followed effect initially uses target `x` and `y`, not collision-body or
  visual-bounds edges;
- movement and knockback update effect `x` and `y` on the next pool update;
- depth, direction, mirrors, rotation, scale, authored offsets, and animation
  progress do not change when target properties change;
- an inactive but existing target remains followed;
- target destruction snapshots the final valid center, detaches, and allows the
  animation to complete at that position;
- completion and safety-timeout release remove the destruction listener;
- pooled reuse cannot inherit the prior target or be moved by its later events;
- two targets damaged by one attack move their effect instances independently;
- misses, rejected applications, and zero actual damage remain effect-free; and
- pool destruction and scene shutdown remove all outstanding attachments.

The implementation must also pass strict TypeScript validation, the focused
combat/effect tests, and a production build. A gameplay smoke check should verify
that a visible impact stays centered during enemy knockback and does not jump or
outlive its normal animation duration.

## Acceptance Criteria

- A successful weapon hit renders its effect at the damaged object's `x`/`y`
  center.
- The effect follows that center for its animation while the object exists.
- Only world position follows; every other presentation value remains fixed from
  spawn.
- Destroying the target freezes the effect at its last valid center instead of
  canceling it or producing an error.
- Pool reuse, completion, shutdown, and destruction leave no stale target
  references or listeners.
- Collision and damage behavior remain unchanged, and decorative objects without
  collision bodies remain non-collidable.

## Amendment: Target-Relative World Depth

The implementation revealed one required sorting invariant: a fixed effect depth
can fall behind its target when the target moves downward through the Y-sorted
world. The confirmed-hit effect therefore also follows the target's current
world-sort `depth` with the spawn request's fixed front offset (`+0.2` for weapon
hits). Position and this target-relative depth freeze together at the target's
last valid values on destruction. Direction, mirroring, scale, rotation,
animation state, authored offsets, and lifetime remain fixed. This amendment
supersedes only the earlier "only position follows" and fixed-depth statements;
all damage, pooling, and cleanup contracts remain unchanged.
