# Wooden Axe Tool Design

**Status: approved design; implementation pending.**

## Goal

Add the generated wooden axe as a real equippable starter tool for the Wood
Gathering milestone. It uses the existing layered weapon catalog and hotbar,
but its authored damage modifiers make it a proper resource tool rather than a
combat weapon.

## Content

- Add `wooden-axe` under `src/game/content/weapons/`.
- Use asset `weapon.player.wooden-axe-tiles` for the axe artwork. Frame 0 is
  down-facing, frame 1 is the right-facing side pose, and frame 2 is up-facing;
  left resolves by mirroring the right attack.
- Add a short, readable chopping idle/attack animation with a resource hitbox
  active only during the contact frames.
- Author the version-2 directional package explicitly: `right` uses axe frame
  1, `down` uses frame 0, and `up` uses frame 2. Omit `left` so it inherits
  and mirrors `right`.
- Author direct damage modifiers in this order:
  - `{ "targetTag": "wood", "modifier": 1 }`
  - `{ "targetTag": "resource", "modifier": 0.1 }`
  - `{ "targetTag": "enemy", "modifier": 0.2 }`
- Add `wooden-axe-impact` under `src/game/content/effects/` using the default
  directional variant and asset `effect.resource.impact-tiles`. Store it on the
  weapon as `onResourceHitEffectId`, not the generic `onHitEffectId`, so wood
  chips never appear when the axe hits an enemy. The effect is independent of
  the axe visual and resolves at the confirmed resource impact position through
  the existing effect pool.
- Extend the authored/normalized weapon contract and schema with optional
  `onResourceHitEffectId`. Resource-hit effect spawning captures the resource
  image’s x/y/depth before damage is applied, then spawns the effect as a static
  world anchor after a positive resource hit; it must not follow the image when
  a tree becomes a wood pile.
- Import the new weapon/effect definitions into the virtual content catalogs.
- Add `wooden-axe` to the starter weapon IDs so a fresh game grants it and the
  existing five-slot hotbar can assign it automatically.

## Damage routing

The combat controller will resolve weapon modifiers against ordered target tags
for both resource nodes and enemies. Resource nodes keep their authored object
tags (with `wood` before broader tags); enemies receive the generic `enemy` tag
for this lookup. Targets without a matching modifier continue to use 1.0
damage.

## Acceptance checks

1. `weapons:check` and `effects:check` pass with the new definitions.
2. A fresh game owns and assigns the wooden axe without replacing the other
   starter weapons.
3. The axe uses the generated directional art and mirrors the side pose left.
4. Chopping a tree applies normal damage (`wood: 1`) and confirmed contact
   spawns `wooden-axe-impact` independently at the target.
5. Hitting an enemy applies 20% of the axe’s calculated damage and does not
   spawn the resource impact effect; resource and enemy modifier resolution does
   not change existing weapons’ behavior.
