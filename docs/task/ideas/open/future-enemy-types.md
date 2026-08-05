# Future Enemy Types

These enemies were removed from the active roster because they only had temporary procedural textures. They are design ideas, not valid map enemy IDs. Reintroduce one only after it has an authored spritesheet, a `visual-set.json`, an entry in `enemy-types.json`, and complete idle, walk, attack, and death behavior.

## Status

Open — future content concepts. Keep these entries out of runtime catalogs until
the art, behavior, balance, and validation package for a concept is complete.

## Completion checklist for a reintroduction

1. Commission and register the authored spritesheet and effects.
2. Add a visual set with idle, walk, attack, and death clips in every required direction.
3. Add the enemy definition, AI behavior, drops, and projectile or impact assets.
4. Add validator coverage and a focused combat/browser smoke scenario.
5. Add the stable enemy ID to maps and editor choices only after all checks pass.

## Archived concepts

| Concept | Intended role | Previous tuning and drops | Art/behavior needed |
| --- | --- | --- | --- |
| Blob | Slow introductory melee enemy | 40 HP; 60 chase speed; 8 damage; 20 XP; 3 coins | Directional idle/walk/attack/death |
| Spike Slime | Moderate-health retaliator | 70 HP; 70 chase speed; 14 damage; 30% knockback resistance; 35 XP; 6 coins; possible silk | Directional set plus a readable spike retaliation |
| Bouncer | Fast leaping melee enemy | 55 HP; 140 chase speed; 16 damage; 40 XP; 8 coins | Directional set plus leap windup, airborne, and impact frames |
| Caster Slime | Fragile ranged enemy that keeps distance | 35 HP; 220 attack range; 180 projectile speed; 6 damage; 45 XP; 10 coins; possible shard | Directional set, cast effect, and authored projectile |
| Swarmer | Small, fast pack enemy | 20 HP; 160 chase speed; 6 damage; 12 XP; 2 coins | Compact directional set and pack-spawn rules |
| Armored Slime | Slow tank with high knockback resistance | 120 HP; 50 chase speed; 18 damage; 70% knockback resistance; 60 XP; 15 coins; possible shard | Directional set with armor-readable hit and death frames |
| Mimic | Stationary collectible disguise and ambusher | 80 HP; 100 chase speed after reveal; 20 damage; 50 XP; 30 coins | Closed disguise, reveal transition, directional combat, and death |
| Sticky Spider-Slime | Ranged controller that applies slow | 50 HP; 200 attack range; 140 projectile speed; 10 damage; 40 XP; 8 coins; possible silk | Directional set, web projectile, impact effect, and slow status |
| The Blobfather | Gloop Forest boss; heavy leaping melee enemy | 360 HP; 82 chase speed; 24 damage; 82% knockback resistance; boss reward of 220 XP and 180 coins | Large directional boss set, leap sequence, boss phases, arena integration, and boss UI |

## Reintroduction rule

The three entries in `src/game/content/enemies/enemy-types.json` are the source of truth for real enemies. A future concept must not be added to a map, generator, or editor choice until its complete visual package and runtime definition are added there and pass `pnpm enemies:check`.
