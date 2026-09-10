# Shared World Drop Spawner Design

**Status: implemented on 2026-09-10.**

## Goal

Replace the instant appearance of resource piles with a shared world-drop
pipeline. A newly created physical drop launches from its source, follows a
short arc to its predetermined landing position, performs a small landing
bounce, and becomes collectible only after it settles.

The pipeline must be reusable by future resource nodes, enemies, chests,
quests, and other producers of physical world drops. Existing rewards that go
directly into inventory remain unchanged until their owning feature elects to
create physical drops through this pipeline.

## Player-facing behavior

- Use the approved `arc + tiny bounce` motion.
- A flight lasts `280` ms, followed by a `100` ms landing
  settle. Exact values may be tuned during visual verification without adding
  content-specific timing.
- Multiple pieces launch in deterministic pile order with a `60` ms stagger.
- Horizontal motion travels directly from the source anchor to the final
  landing anchor. Vertical motion uses a parabolic lift above that line.
- Arc height is derived from travel distance and clamped to a modest range so
  nearby drops still read clearly and farther placements do not leave the
  visible play area unnecessarily.
- The landing response briefly squashes and rebounds the existing drop image.
  It does not require new sprite frames.
- A drop cannot be collected while launching or bouncing. It becomes
  collectible only at its final resting position after the landing settle.
- Each piece activates independently when its own motion completes.
- Drops reconstructed from saved state appear already settled and collectible;
  loading a map never replays the launch.

## Architecture

Add a focused `WorldDropSpawner` under the collectible feature. It owns the
creation-to-activation lifecycle of physical collectible drops, but it does
not own drop tables, placement selection, inventory rewards, or persistence.

The public request is a discriminated union. `launchIndex` is explicitly
zero-based, and restored drops cannot accidentally supply launch-only data:

```ts
interface WorldDropDefinition {
  readonly objectId: ObjectArchetypeId;
  readonly visualId: string;
  readonly instanceId: string;
  readonly initialState?: Readonly<Record<string, unknown>>;
}

type WorldDropRequest =
  | {
      readonly mode: 'launch';
      readonly source: { readonly x: number; readonly y: number };
      readonly destination: { readonly x: number; readonly y: number };
      readonly launchIndex: number; // zero-based non-negative integer
      readonly drop: WorldDropDefinition;
    }
  | {
      readonly mode: 'settled';
      readonly destination: { readonly x: number; readonly y: number };
      readonly drop: WorldDropDefinition;
    };
```

`spawn(request)` validates synchronously, creates the object, and returns its
`Phaser.GameObjects.Image`. Invalid request data or a non-collectible object ID
throws before object creation. Once creation succeeds, presentation setup
failures fall back to immediate settled registration rather than throwing and
stranding a saved reward.

The spawner receives narrow dependencies for object creation and collectible
registration. It must not import `WorldScene`, `MapBuilder`,
`ResourceNodeController`, or a concrete persistence repository.
The injected object-creation contract guarantees that a validated
`collectible.walk-over` archetype is returned with its static pickup body.
`WorldDropSpawner` owns disabling that body before flight and re-enabling it at
settled completion; the registration dependency only adds the now-active image
to `CollectibleController`'s records.

`ResourceNodeController` remains responsible for choosing valid landing cells,
building stable pile records, and saving resource progress. It delegates each
new pile to `WorldDropSpawner` instead of directly creating and registering the
collectible. Its restore path delegates with animation disabled.

Future systems receive the same spawner dependency. They gain the same motion
when they intentionally submit a physical world drop; merely adding a new item
definition does not create a drop or change an inventory-direct reward.

`initialState` is deliberately opaque to the spawner. For today's resource
drops it contains `remaining` and `sourceResourceInstanceId`, which preserve
the existing `CollectibleController` callback to `ResourceNodeController`.
This design does not invent a generic source-owner callback. A future producer
that needs collection-linked persistence must define that ownership integration
when it adopts physical drops; it can still reuse the same creation and motion
pipeline.

## Drop lifecycle

Resource hit presentation is decided before this lifecycle begins. A
non-lethal accepted hit may play the object's authored on-hit animation. A
lethal accepted hit must skip that animation, complete depletion immediately,
remove the source object, and start the drop lifecycle in the same combat
resolution. The ordinary impact effect may still spawn at the source's
captured impact anchor after removal.

For a newly produced drop:

1. The owning feature determines the item, quantity, stable ID, and final
   placement.
2. The owner persists the final state before calling `spawn()`. A quit during
   flight or an object-creation error therefore cannot lose or relocate the
   item.
3. `WorldDropSpawner` validates that the request has finite anchors, a
   zero-based non-negative integer launch index for launch mode, and an
   archetype whose catalog definition has `collectible` behavior. Validation
   occurs before object creation.
4. The spawner creates the normal collectible object through the shared object
   factory.
5. It immediately keeps the object's pickup body inactive and withholds
   registration from `CollectibleController`.
6. It places the image at the source anchor and runs the deterministic flight
   and landing motion toward the final anchor.
7. After the image reaches its final resting transform, the spawner restores
   its ordinary world-sorted depth, enables its pickup body, and registers it
   with `CollectibleController`.

Creation may place the object in the collectible behavior group before the
spawner receives it. The spawner must disable the body synchronously before the
next physics step, and the object must remain absent from the collectible
controller's records until landing. Both guards prevent airborne pickup.
The injected registration dependency keeps its existing `void` return because
catalog validation makes refusal impossible for a valid request; registration
is called exactly once through an internal completion guard.

For a restored drop, the spawner creates it at the saved final anchor and
registers it immediately. No timer, tween, source anchor, or stagger is used.

## Motion implementation

The launch is runtime transform motion, not an Animation Studio clip. Studio
animations describe reusable frame/layer timelines, while a drop's source and
destination are different for every occurrence. Encoding this motion in Studio
would still require runtime movement and pickup gating.

Use a small pure trajectory function to compute the anchor from normalized
progress `t`, driven linearly from `0` through `1` over `280` ms:

- `x` linearly interpolates from source to destination;
- `y` linearly interpolates between anchors and subtracts a parabolic lift;
- lift is `4 * height * t * (1 - t)`, so it is zero at progress `0` and `1`
  and maximal at `0.5`;
- distance is Euclidean distance between the two anchors;
- `height = clamp(distance * 0.45, 28, 56)` pixels; and
- identical source and destination anchors intentionally produce a `28` pixel
  hop in place.

Drive that function from one Phaser tween or counter per active drop. Update
the object through the existing object-anchor helper so visual offsets remain
correct. Keep the pickup body disabled during these updates. During flight,
use a stable transient depth based on the final landing anchor; after settling,
restore normal world-sorted depth at the exact final anchor.

At flight completion, place the image exactly at the destination and set scale
to `1.12 × baseScaleX` and `0.82 × baseScaleY`. Rebound for `40` ms with
`Sine.Out` to `destination.y - 4`, `0.96 × baseScaleX`, and
`1.04 × baseScaleY`; then settle for `60` ms with `Sine.In` to the exact
destination and exact authored base scale. The full motion is `380` ms after
its delay. The delay is `launchIndex * 60` ms. Pickup activates only after the
final `60` ms settle completes. Do not bake these values into each collectible
object definition in this first version.

## Persistence and ownership

- Final placement and quantity are authoritative; animation progress is not
  persisted.
- Resource pile save data remains unchanged.
- `ResourceNodeController` saves its destroyed-source pile list before asking
  the spawner to animate the new images.
- Collecting a landed pile continues through `CollectibleController` and the
  existing resource-state callback.
- If a scene closes during flight, the owner already has enough state to
  restore the drop at its final location on the next load.
- Other future producers remain responsible for their own save records and for
  deciding whether a direct reward should instead become a physical drop.

## Cleanup and failure behavior

- `WorldDropSpawner` tracks stagger timers, tweens, and in-flight images and
  exposes idempotent `destroy()` cleanup.
- `destroy()` first marks the spawner disposed, cancels every stagger timer and
  tween, destroys each still-unregistered in-flight image, and clears its
  tracking records. Completion callbacks check the disposed flag and their
  per-drop completion guard before doing work.
- `spawn()` called after disposal throws a programmer-error exception before
  creating an object.
- If timer or tween setup throws after object creation, the spawner cancels any
  partial motion, places the valid image at the exact destination and authored
  scale, enables its body, and registers it once as an immediate settled drop.
- A missing body during flight setup is safe because registration is withheld.
  A missing body violates the injected object-creation contract. In that case
  the spawner destroys the unregistered image and reports the integration
  error; the owner's prior persistence restores the drop on reload after the
  integration is corrected. If the image itself has already been destroyed,
  completion exits without registration.
- Invalid request values, unknown catalog IDs, and valid but non-collectible
  archetypes throw before object creation. The spawner never substitutes an
  item or leaves a visible permanently uncollectible object.
- Completion sets the exact final anchor, authored base scale, body state, and
  collectible registration once, even if a callback is invoked more than once.

## Integration and teardown order

`WorldScene` constructs one shared `WorldDropSpawner` and injects it into
`ResourceNodeController`. The scene continues to own concrete object creation
and collectible registration callbacks.

On teardown, destroy `ResourceNodeController` before `WorldDropSpawner`.
`ResourceNodeController.destroy()` may finalize a pending depletion and save
its pile records while the spawner is still callable. The scene then destroys
the spawner, which cancels and destroys any presentation objects those final
requests created. The already-saved piles restore settled on the next load.
After the spawner is disposed, no controller may submit another request.

## Scope boundaries

- Do not add or modify Animation Studio content for this motion.
- Do not change resource placement rules, pile quantities, stable IDs, or save
  schemas.
- Do not convert current enemy XP, coins, or direct-inventory item rewards into
  physical drops as part of this change.
- Do not add physics simulation, random trajectories, collision against terrain
  during flight, magnetism, or item rarity effects.
- Do not move the feature into `WorldScene`; the scene only composes and injects
  the shared spawner.

## Verification

1. Destroying a tree launches its wood pile from the tree anchor to the
   existing selected landing anchor, then enables collection after settling.
   The lethal strike does not play or wait for the tree's on-hit animation.
2. Destroying a stone node launches three piles with `60` ms staggered starts;
   every pile lands at its precomputed deterministic cell.
3. Walking through an airborne or bouncing pile does not collect it. Walking
   through it after settling uses the existing collection and inventory flow.
4. Final anchors, visual scale, world depth, and pickup bodies match ordinary
   restored collectibles after all motion completes.
5. Saving or leaving during launch and reloading restores every outstanding
   pile settled at its persisted destination with the correct amount.
6. Re-entering a map with previously saved piles does not replay launch motion.
7. Scene shutdown during one or more active launches produces no late callback,
   stale tween, or destroyed-object error.
8. Pure trajectory tests cover start, apex, destination, Euclidean distance,
   clamped heights, and an identical source/destination hop.
9. Lifecycle tests cover cleanup during stagger delay, cleanup during flight,
   duplicate completion, tween/timer setup failure, and a launch submitted
   after disposal.
10. Validation tests prove invalid anchors, invalid launch indexes, unknown IDs,
    and valid non-collectible archetypes fail before the object-creation callback.
11. An ordering test proves resource persistence is updated before the first
    object-creation callback.
12. A small test caller outside the resource feature can submit a physical drop
    through the same API without importing resource-specific types.
13. Automated cases live under `scripts/tests/collectibles/` and pass through
    `pnpm test:collectibles`. Manual browser verification covers the visual arc,
    stagger, landing settle, depth, and pickup timing for wood and stone.
14. `pnpm typecheck`, `pnpm test:collectibles`, and `pnpm check` pass.
15. Combat sequencing tests prove that a non-lethal resource hit invokes the
    on-hit animation while a lethal resource hit completes depletion directly
    without invoking the animation adapter.
