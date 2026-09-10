# Collectible Quantity Badges Design

**Status:** Approved by standing implementation instruction on 2026-09-10.

## Goal

Show the stored quantity on every active ground collectible so resource piles
and stacked drops can be understood at a glance.

## Presentation

`CollectibleController` owns one world-space text badge per registered
collectible. The badge displays `×N` above the sprite using bold warm-white
text, a dark four-pixel outline, and a translucent dark background. It uses the
world reveal-effect depth band so it remains legible across light and dark
biomes while still moving with the camera.

Launched items do not register as collectible until settling, so their badge
appears only on landing. This avoids a detached number following the arc.

## Lifecycle

Create the badge when registration succeeds. Synchronize it whenever remaining
quantity changes through stacking or partial collection. Destroy it when the
pile depletes, is merged into another pile, or the controller tears down.

The badge is presentation-only. Saved quantity remains owned by existing
collectible/resource/inventory-drop persistence.

## Verification

- Registration creates a visible badge with the initial quantity.
- Stacking updates the surviving pile's badge.
- Partial collection updates the badge.
- Depletion and teardown destroy badges without affecting pickup behavior.
- Collectible tests, typecheck, and production build pass.
