# Physics-Body Combat Collision Design

**Date:** 2026-08-17  
**Status:** Approved for implementation planning

## Problem

Weapon hit detection currently verifies that a target has an Arcade body but
then intersects the weapon against `GameObject.getBounds()`. Enemies use an
invisible 4-by-4 `__WHITE` sprite as their runtime anchor while their authored
body is much larger. Consequently, the tiny render bounds accept damage and the
authored collision body shown by the red world-debug overlay does not.

Confirmed-hit effect placement uses the same render bounds, so effects are also
anchored to the wrong target area.

## Collision Contract

An active, enabled Arcade body is the sole authority for combat collision. A
combat target without an enabled body is non-collidable and cannot receive a
weapon hit. Visual bounds never substitute for missing collision geometry.
This keeps decorative and ground objects without collision bodies non-solid and
non-damageable by construction.

The collision contract applies to every physics combat target, including
enemies and training dummies. It does not change authored weapon geometry,
animation timing, damage, knockback, combo behavior, or hit-once suppression.

## Runtime Design

A small, pure combat geometry helper will snapshot an active target's enabled
Arcade body into plain world-space geometry. Rectangular bodies remain exact
axis-aligned rectangles. Native Arcade circle bodies remain exact circles with
their authored center and radius. Inactive targets and disabled, missing,
non-finite, or non-positive body geometry resolve to no target.

`HitboxPool` will resolve this body geometry once per target check and pass it
to every weapon-shape intersection path:

- rectangle attacks use rectangle-to-rectangle or rectangle-to-circle tests;
- circle and ellipse attacks use exact axis-aligned ellipse-to-rectangle tests
  or a deterministic closest-point-on-ellipse calculation for circle bodies;
- sector attacks preserve rectangular targets by testing containment plus the
  sector's radial segments and circular arcs against the rectangle edges;
- sector attacks preserve circle targets by comparing the circle radius with
  the exact shortest distance from its center to the annular sector.

No path replaces a rectangular body with a circumscribed circle or replaces a
circle body with its axis-aligned bounding box during collision decisions. The
helper handles degenerate zero-width sectors as radial segments and treats arc
widths of a full turn or more as annuli. This is a target-geometry correction,
not a change to authored weapon dimensions or placement.

After a target accepts positive damage, `CombatController` will calculate the
confirmed-hit contact point from the same body rectangle. The body bounds are
captured before damage because a fatal hit may disable the body immediately.
Since weapon hits require an enabled body, no visual fallback is needed.

## Debug Behavior

The red world-debug outline displays only active, enabled Arcade bodies and
therefore matches the area that can accept weapon hits. Disabled bodies are not
drawn during enemy death animations, and inactive training dummies are also
omitted. The blue visual-bounds overlay may still show the small invisible
anchor for enemies; it remains a render-debug measurement and no longer
influences combat.

## Error Handling

Inactive targets and targets with a missing, disabled, malformed, or zero-sized
body are skipped. The hit handler, combo counter, damage pipeline, and impact
effects are not invoked for them. Pool lifecycle and per-activation hit
bookkeeping remain unchanged. A fatal accepted hit may disable the body, but
its pre-damage geometry snapshot remains available solely to place that hit's
confirmed effect; later activations cannot hit the disabled target.

## Verification

Focused automated coverage will reproduce the regression with a target whose
visual bounds are a tiny square inside a larger physics body:

- a weapon overlapping only the outer portion of the body registers a hit;
- a weapon outside the body does not register a hit;
- a target without an enabled body does not register a hit;
- an inactive training dummy with a still-enabled body does not register a hit;
- a rectangle attack misses the corners of a native circle body's bounding box;
- ellipse and sector attacks do not gain false-positive padding around a long,
  thin rectangular body;
- confirmed-hit contact points use the pre-damage body edge even when a fatal
  hit disables the body;
- a later activation cannot hit that disabled target;
- rectangle, circle/ellipse, and sector paths consume exact physics geometry;
- one target is still reported at most once per activation.

Final verification runs the focused combat tests followed by `pnpm check`.

## Completion Criteria

The fix is complete when every combat target receives weapon damage throughout
its red collision body, never through render-only bounds, and targets without
an enabled collision body cannot collide or take weapon damage.
