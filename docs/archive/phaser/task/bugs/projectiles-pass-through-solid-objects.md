# Projectiles pass through solid objects

## Problem

Pooled projectiles only overlap their damage targets. They are not connected to
the world's `collisionTiles` group, so arrows pass through solid terrain,
trees, houses, and walls.

## Approved fix

`CombatController` will register one Arcade collider for each shared projectile
group—enemy and player—against `collisionTiles`. On contact, the callback will
recycle the projectile immediately. The existing collision group remains the
single source of truth for which world objects are solid.

This applies to current enemy arrows and future player projectiles. Projectile
contact with world geometry causes no damage and no impact effect.

`CombatController` owns both collider handles and destroys them during its own
cleanup, preventing duplicate callbacks if a controller is reconstructed.
World colliders are registered before projectile damage overlaps, and damage
callbacks ignore inactive projectiles, so solid-world contact wins when geometry
and a damage target are reached during the same physics step.

## Verification

- Enemy arrows disappear when they touch trees, houses, walls, or solid terrain.
- Arrows can still hit and damage the player before being recycled.
- Recycled arrows still collide after being fired again.
- A player-owned pooled projectile is fired into `collisionTiles`, confirmed
  recycled, fired again from the same pool slot, and confirmed recycled again.
- TypeScript validation, production build, and a browser smoke test pass.
