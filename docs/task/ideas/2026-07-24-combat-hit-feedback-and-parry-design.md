# Combat Hit Feedback and Future Parry Design

## Goals

Make enemy attacks readable and dangerous, ensure damage feedback always reports the real HP loss, and define a future hitbox-based parry system that can later be authored through an enemy/character editor.

## Immediate implementation scope

### Enemy feedback

- Enemies flash red only when they receive damage.
- Starting an attack does not tint or flash an enemy red.
- Authored attack animation frames provide the enemy attack warning.

### Player damage pipeline

`HealthSystem` remains the single owner of player damage mitigation and accepted-hit invulnerability. Every damage request returns a discriminated result:

- `{ status: "accepted", requestedDamage, mitigatedDamage, actualHpLost }`; or
- `{ status: "rejected", reason, requestedDamage, mitigatedDamage: 0, actualHpLost: 0 }`.

Rejection reasons are `dead`, `invulnerable`, and `invalid`. Dodge immunity remains an earlier combat gate: while dodging, combat does not submit a `DamageRequest`.

Combat feedback must consume this result. It must not independently read remaining player HP or repeat mitigation calculations.

When a hit is accepted:

1. Apply the mitigated damage.
2. Display the actual HP removed.
3. Flash the player visual red.
4. Knock the player in the normalized incoming-impact direction and suppress movement input for 160 milliseconds so the bounce is visible.
5. Start 500 milliseconds of hit invulnerability.

Requests received during hit invulnerability produce no damage, floating number, flash, or additional knockback. Dead, invalid, invulnerable, and dodge-blocked hits are collectively “blocked hits” for feedback purposes. Dodge invulnerability remains a separate input/combat rule.

### Initial damage tuning

Damage is fixed rather than percentage-based so player defense and defensive perks make progression visible. Raw enemy damage values are tuned so a level-one player with default defense loses approximately:

| Enemy | Raw damage | Exact default level-one HP loss | Knockback speed |
| --- | ---: | ---: | ---: |
| Worm Archer arrow | 22 | 20 | 180 world units/second |
| Worm Swordsman attack | 37 | 35 | 260 world units/second |
| Worm Brawler attack | 52 | 50 | 340 world units/second |

The displayed number is always the actual HP removed. For example, a 50-point calculated hit against a player with 12 HP displays 12.

For melee, the incoming-impact direction is the normalized vector from the enemy anchor to the player anchor at impact. For a projectile, it is the normalized projectile velocity immediately before recycling. A zero-length vector applies no knockback.

### Player attack direction

Movement determines the player’s facing direction. Keyboard attack and mouse click both trigger an attack in that current facing direction. Cursor position does not aim, rotate, or redirect the attack. The direction is locked for that attack sequence.

## Future parry and authored attack-hitbox design

Parrying is documented here but is not part of the immediate implementation.

### Attack hitboxes

Player and melee enemy attacks will eventually expose explicit, temporary attack hitboxes. A melee parry occurs only when two active attack hitboxes overlap. Entity bodies, facing comparison, distance checks, and relative character positions do not independently create a parry.

On melee parry:

- cancel both attack sequences;
- apply no damage to either entity;
- apply no hit invulnerability to either entity;
- knock both entities away from the hitbox clash point;
- play a dedicated clash effect and sound rather than a red damage flash.

Attack-hitbox clashes resolve before attack hitboxes can damage opposing hurtboxes in the same physics step. A resolved clash immediately disables both attack hitboxes before cancelling their attack sequences. This precedence guarantees that a parried attack cannot also apply damage.

Player attack hitboxes still originate in the player’s locked facing direction. The overlap rule itself does not impose an additional facing test.

### Projectile parry possibilities

The recommended progression is:

1. Interception phase: an active player attack hitbox intercepts and destroys an enemy arrow.
2. Reflection phase: a narrower perfect-parry timing window reflects the arrow toward enemies.
3. In the reflection phase, reflected projectiles retain authored projectile identity but switch ownership and receive separately balanced reflected damage.

### Future editor support

The current map editor selects real enemy IDs and edits spawn enablement, weights, maximum-alive values, spawn radii, interval, maximum population, and safe zones. It also supports shared object visual-offset and collider editing. It cannot create or edit character/enemy definitions, animation clips, attack timing, or attack hitboxes.

A future character/enemy editor should make attack hitboxes first-class authored data:

- shape and size;
- directional offset from the stable physics anchor;
- active animation frames or normalized timing window;
- attack sequence association;
- knockback strength;
- debug overlay preview;
- clash/parry eligibility.

Enemy attack hitboxes should live in the real enemy definition. Player attack hitboxes should live in the corresponding player weapon/ability definition. Both should use stable IDs and editor-safe JSON, while visual sets continue to own only render transforms and animation clips. The runtime remains responsible for collision execution, damage rules, and parry resolution.

## Data flow

Immediate damage flow:

```text
enemy attack or projectile
  -> CombatController builds DamageRequest with amount and impact vector
  -> HealthSystem checks invulnerability and calculates final damage
  -> GameState removes HP and returns actual HP lost
  -> HealthSystem returns DamageResult
  -> WorldScene renders the accepted-hit feedback
```

Future melee-parry flow:

```text
player attack hitbox overlaps enemy attack hitbox
  -> clash resolver cancels both attacks
  -> resolver applies opposing knockback
  -> resolver emits clash feedback
  -> no HealthSystem damage request is created
```

## Validation

Immediate implementation must verify:

- attack animations do not tint enemies red;
- damaging enemies still produces their red hit flash;
- an isolated level-one player with 100 HP, 2 defense, no perks, and no prior invulnerability loses exactly 20 HP from one archer arrow, 35 HP from one swordsman strike, and 50 HP from one brawler strike;
- displayed damage equals the HP delta;
- archer, swordsman, and brawler accepted hits set player velocity to the specified 180, 260, and 340 world-units/second in the defined incoming direction, suppress movement input for 160 ms, and produce 500 ms of invulnerability;
- blocked hits produce no secondary feedback;
- click attacks use current facing rather than cursor direction;
- asset, visual, enemy, object, map, TypeScript, and production-build checks pass;
- browser smoke tests cover melee and projectile hits without console errors.

Future melee-parry tests must cover attack-hitbox overlap precedence, immediate hitbox disablement, attack cancellation, opposing knockback, zero damage, and zero granted invulnerability. Interception-phase tests cover arrow destruction. Reflection-phase tests separately cover perfect-window timing and reflected projectile ownership.
