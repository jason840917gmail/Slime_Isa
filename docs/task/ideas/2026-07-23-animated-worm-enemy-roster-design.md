# Animated worm enemy roster migration

## Status

Approved for implementation.

## Goal

Make the three authored worm enemies the only active enemy roster:

- `worm-archer`
- `worm-swordsman`
- `worm-brawler`

Every enemy exposed to maps, the map editor, and runtime spawning must have file-backed artwork plus directional idle, walk, attack, and death animation clips. The procedural Blobfather encounter is disabled under the same rule.

The removed enemy concepts and their current gameplay definitions must remain documented in `docs/task/ideas/future-enemy-types.md` for later art and implementation.

## Source assets

The ready runtime art is under `asset/MAPS/enemies/`:

| Stable asset ID | Asset | Geometry | Purpose |
| --- | --- | --- | --- |
| `enemy.worm.archer` | `64x64-8x6-worm-archer.png` | 8 columns × 6 rows, 64×64 frames | Archer character |
| `enemy.worm.swordsman` | `64x64-4x10-worm-swordsman.png` | 4 columns × 10 rows, 64×64 frames | Swordsman character |
| `enemy.worm.brawler` | `64x64-8x6-worm-brawler.png` | 8 columns × 6 rows, 64×64 frames | Brawler character |
| `enemy.projectile.worm-arrow` | `16x10-1x1-worm-arrow.png` | 16×10 image | Archer projectile |
| `effect.enemy.worm-brawler-hit` | `16x20-1x3-worm-brawler_hits.png` | 1 column × 3 rows, 16×20 frames | Brawler impact effect |

These assets use transparency and must be cataloged in `asset/assets.json` with stable IDs. Character sheets, the arrow, and the hit effect belong to the boot bundle.

## Chosen approach

Use a hard active-roster replacement.

Old enemy IDs will not remain as hidden runtime aliases and will not be silently mapped to worm enemies. This keeps authored maps, editor choices, analytics events, and future balancing semantically correct.

Alternative approaches were rejected:

- Filtering old definitions only at spawn time leaves incomplete enemies selectable elsewhere.
- Reusing old IDs for worms avoids map edits but gives misleading names and permanent migration debt.

## Active enemy definitions

Active definitions move to `src/game/content/enemies/enemy-types.json`, with a matching schema and a typed loader in `EnemyTypes.ts`. Its top-level shape is:

```json
{
  "$schema": "./enemy-types.schema.json",
  "types": {
    "worm-archer": {},
    "worm-swordsman": {},
    "worm-brawler": {}
  }
}
```

The object key must equal each record's `id`. This JSON is the single source used by runtime code, repository checks, authored-map validation, and the map editor.

The final runtime contract is:

```ts
interface EnemyConfig {
  id: 'worm-archer' | 'worm-swordsman' | 'worm-brawler';
  visualSetId: EnemyVisualSetId;
  body: {
    width: number;
    height: number;
    centerOffsetX: number;
    centerOffsetY: number;
  };
  maxHp: number;
  ai: EnemyAIConfig;
  drop: EnemyDrop;
  projectile?: {
    assetId: 'enemy.projectile.worm-arrow';
    damage: number;
  };
  impactEffect?: {
    visualSetId: 'effect.enemy.worm-brawler-hit';
    clipId: 'hit';
    distance: number;
  };
}
```

`textureKey`, `defaultClip`, `scale`, and `tint` are removed from active regular-enemy definitions. Visual scale and origin belong to the visual set. The enemy ID replaces `textureKey` in `enemy.died` analytics/event payloads.

`Enemy` remains an Arcade Sprite for compatibility but uses an invisible `__WHITE` render anchor at scale `1`. Body width, height, and center offsets are stable world-unit geometry and do not depend on source-frame dimensions.

The three roles are:

### Worm archer

- Ranged behavior.
- Maintains distance from the player.
- Fires the authored worm-arrow image.
- Lower contact damage than the melee enemies.

### Worm swordsman

- Deliberate close-range behavior.
- Moderate-to-high health and knockback resistance.
- Slower attack cadence with stronger contact damage.

### Worm brawler

- Fast close-range behavior.
- Lower health than the swordsman.
- Uses the authored three-frame impact effect when its melee attack connects.

The new IDs and values below are authoritative initial balance.

The initial concrete records use these values:

| Field | Archer | Swordsman | Brawler |
| --- | ---: | ---: | ---: |
| `visualSetId` | `enemy.worm.archer` | `enemy.worm.swordsman` | `enemy.worm.brawler` |
| `maxHp` | 40 | 90 | 55 |
| Body `width × height` | 36 × 24 | 36 × 26 | 34 × 24 |
| Body center offset | `[0, 10]` | `[0, 9]` | `[0, 10]` |
| `aggroRange` | 280 | 220 | 240 |
| `attackRange` | 220 | 38 | 34 |
| `fleeRange` | 120 | omitted | omitted |
| `wanderSpeed` | 30 | 28 | 50 |
| `chaseSpeed` | 80 | 75 | 130 |
| `attackCooldownMs` | 2200 | 1500 | 1100 |
| `attackWindupMs` | 600 | 400 | 250 |
| `attackRecoveryMs` | 350 | 400 | 250 |
| `contactDamage` | 6 | 16 | 12 |
| `isRanged` | true | false | false |
| `projectileSpeed` | 180 | omitted | omitted |
| `knockbackResist` | 0 | 0.45 | 0.1 |

Drops:

- Archer: 45 XP, 10 coins, 15% chance of one shard.
- Swordsman: 50 XP, 10 coins, 20% chance of one shard.
- Brawler: 40 XP and 8 coins.

Archer projectile damage is `12`. Brawler impact distance is `22` world units. `attackRecoveryMs` becomes a required AI value for all active enemies.

## Visual-set organization

Create one colocated visual definition per enemy:

```text
src/game/content/visuals/
├── enemy-worm-archer/visual-set.json
├── enemy-worm-swordsman/visual-set.json
└── enemy-worm-brawler/visual-set.json
```

Each visual set defines these clip IDs:

- `idle-side`, `idle-up`, `idle-down`
- `walk-side`, `walk-up`, `walk-down`
- `attack-side`, `attack-up`, `attack-down`
- `die-side`, `die-up`, `die-down`

Side clips face right in source art. Runtime uses horizontal flipping for left.

The sheets contain contiguous populated frames but use different layouts and frame counts. Initial frame lists will be inferred by visual inspection. The JSON files are the correction point if an inferred boundary is wrong; no frame ranges are hardcoded inside `Enemy`.

The initial inferred frame lists are:

| Clip | Archer | Swordsman | Brawler |
| --- | --- | --- | --- |
| `idle-side` | 0–3 | 8–11 | 0–3 |
| `walk-side` | 4–7 | 20–23 | 4–7 |
| `attack-side` | 8–10 | 30–33 | 8–10 |
| `die-side` | 11–13 | 34–37 | 11–13 |
| `idle-up` | 14–17 | 4–7 | 14–17 |
| `walk-up` | 18–20 | 16–19 | 18–21 |
| `attack-up` | 21–24 | 27–29 | 22–24 |
| `die-up` | 25–27 | 34–37 shared | 25–27 |
| `idle-down` | 28–31 | 0–3 | 28–31 |
| `walk-down` | 28–31 shared | 12–15 | 32–34 |
| `attack-down` | 32–34 | 24–26 | 35–38 |
| `die-down` | 35 | 34–37 shared | 39–42 |

Ranges are inclusive. These lists are deliberately data-only and may be corrected later without changing enemy code.

`VisualCatalog.ts` explicitly imports all three enemy visual-set JSON files and the brawler-effect visual set. Literal visual-set IDs are `enemy.worm.archer`, `enemy.worm.swordsman`, `enemy.worm.brawler`, and `effect.enemy.worm-brawler-hit`; `VisualSetId` is extended with those values. Visual sets are not assumed to be auto-discovered at runtime.

Idle and walk clips use `repeat: -1`. Attack and death clips use `repeat: 0`. The brawler impact clip uses frames `[0, 1, 2]`, `repeat: 0`, and a visually reviewed frame rate.

The arrow remains a static projectile image.

## Runtime animation state

`Enemy` owns a visual direction:

```text
side | up | down
```

Direction selection uses the dominant movement or target vector:

- Horizontal magnitude greater than vertical selects `side`; negative X flips the visual.
- Negative Y selects `up`.
- Positive Y selects `down`.
- Idle preserves the last meaningful direction.
- Attack locks direction toward the player for that attack.
- Death locks the last direction.

Animation selection is derived from AI state:

| AI/runtime condition | Visual clip |
| --- | --- |
| Idle or stationary | `idle-<direction>` |
| Wander, chase, or flee with velocity | `walk-<direction>` |
| Active attack sequence | `attack-<direction>` |
| Dead | `die-<direction>` |

Clip playback changes only when the resolved clip or flip changes. Attack and death clips are not restarted each update.

The long-lived AI `attack` state does not select an attack clip by itself. While it is waiting for cooldown and has no active sequence, velocity determines walk versus idle normally; a stationary cooldown wait displays `idle-<direction>`.

Death disables physics/gameplay immediately, plays the directional death clip once, then fades or destroys the enemy. A short timeout remains as a defensive fallback if animation completion does not fire.

## Attack sequence and damage

The current long-lived `attack` AI state is not treated as one animation. A typed attack sequence coordinates gameplay and visuals:

1. When attack range and cooldown allow, `Enemy` starts one sequence, stores a monotonically increasing sequence ID, locks direction toward the player, stops movement, starts the one-shot attack clip, and starts the telegraph.
2. `attackWindupMs` marks the impact/fire moment. The delayed callback captures the sequence ID and does nothing if the enemy died, was interrupted, left the scene, or started another sequence.
3. At impact, the archer fires once. A melee enemy checks range once, applies `contactDamage` once, and the brawler spawns one hit effect only when that geometric hit succeeds.
4. The sequence remains active through `attackWindupMs + attackRecoveryMs` and until animation completion, whichever is later. It then returns the AI to `chase`, or `flee` for a ranged enemy inside its flee range.
5. Cooldown begins when the sequence starts. A new sequence cannot begin while another is active.

The untyped `_lastAttackAt` property is replaced by explicit `Enemy` fields. Continuous per-update proximity damage is removed; `contactDamage` becomes melee attack damage delivered only at the impact point.

Taking damage during windup cancels the pending timer and sequence, enters hit stun, and returns to chase afterward. Death and scene shutdown cancel every pending attack timer.

Animation completion has a bounded defensive fallback. Attack completion is forced after
`max(attackWindupMs + attackRecoveryMs, clipDurationMs) + 250ms`, capped at `2000ms`.
Death cleanup is forced after `clipDurationMs + 250ms`, capped at `1500ms`.

## Projectile and impact visuals

The archer projectile contract is concrete:

- manifest asset ID: `enemy.projectile.worm-arrow`;
- source: `asset/MAPS/enemies/16x10-1x1-worm-arrow.png`;
- render origin: `[0.5, 0.5]`;
- rotation: `atan2(dy, dx)` on every activation;
- speed: `ai.projectileSpeed`;
- damage: `config.projectile.damage`;
- physics body: reset to the authored image dimensions on every activation.

`ProjectilePool.fire` resolves the texture key before activation and resets texture, origin, body size, rotation, scale, alpha, tint, velocity, damage, and lifetime timer. The overlap handler reads the pooled projectile's damage and recycles it through one public pool method instead of manually hiding the sprite. Scene cleanup destroys every pooled sprite and timer.

The brawler effect contract is concrete:

- manifest asset ID: `effect.enemy.worm-brawler-hit`;
- visual-set ID: `effect.enemy.worm-brawler-hit`;
- clip ID: `hit`;
- frames: `[0, 1, 2]`;
- placement: enemy position plus the locked attack direction multiplied by `impactEffect.distance`;
- rotation: follows attack direction;
- lifecycle: destroy on animation completion, defensive timeout, or scene shutdown.

Swordsman attacks use the character sheet's attack animation and do not require a separate effect asset.

## Map and editor migration

Only the three worm IDs remain in `ENEMY_CONFIGS`, so the map editor automatically exposes only complete enemies.

Every authored map spawn entry uses this deterministic mapping:

| Removed ID | Replacement |
| --- | --- |
| `blob` | `worm-brawler` |
| `spike` | `worm-swordsman` |
| `bouncer` | `worm-brawler` |
| `caster` | `worm-archer` |
| `swarmer` | `worm-brawler` |
| `armored` | `worm-swordsman` |
| `mimic` | `worm-swordsman` |
| `spider` | `worm-archer` |

Duplicate replacement entries are merged by summing weights. Weights are not rescaled because only their ratios matter. If every merged source entry has `maxAlive`, the replacement cap is their sum; if any source entry is uncapped, the replacement is uncapped.

This produces the following production-map tables:

| Map | Spawn table |
| --- | --- |
| `meadow-crossing` | brawler 80, swordsman 20 |
| `gloop-forest` | brawler 65, swordsman 20, archer 15 |
| `crystal-caverns` | brawler 30, swordsman 40, archer 30 |
| `icege` | swordsman 10 |

Map-editor defaults become brawler 50, swordsman 30, and archer 20.

The same production tables are updated in `scripts/lib/procedural-map-generator.mjs`; running `pnpm maps:bake` must not restore removed IDs.

## Removed concepts

Remove these definitions from active runtime content:

- Blob
- Spike Slime
- Bouncer
- Caster Slime
- Swarmer
- Armored Slime
- Mimic
- Sticky Spider-Slime
- Blobfather

Before removal, preserve for each concept:

- stable proposed future ID;
- gameplay role and behavior notes;
- current stats and AI values;
- drops and boss rewards;
- missing art/animation requirements.

The future idea document is not imported by runtime code.

Blobfather-specific imports, spawning, rewards, and health-bar wiring are removed from `CombatController`. Generic boss UI or progression infrastructure may stay if it has no active boss-specific wiring. Procedural enemy texture generation and the procedural enemy projectile are removed when no active consumer remains.

## Validation

Add `scripts/check-enemies.mjs`, include it as `enemies:check` in `pnpm check`, and make it read `enemy-types.json`, all visual-set JSON files, and `asset/assets.json`. It enforces:

- every active enemy has a unique stable ID;
- every active enemy references a known visual set;
- every enemy visual set references a ready manifest spritesheet;
- all twelve required directional clips exist;
- every clip frame is within sheet bounds and points to a populated authored frame;
- ranged enemies reference a ready projectile asset;
- no authored map references a removed enemy ID;
- no removed enemy appears in the editor roster or runtime spawn tables.

`scripts/check-maps.mjs` also reads `enemy-types.json` and rejects unknown `spawns.enemies[*].type` values. This moves enemy-reference checking into repository validation while runtime map loading retains its defensive assertion.

Spritesheet manifest frame geometry gains optional `count`, meaning the number of populated contiguous source frames. It must be greater than zero and no larger than `cols × rows`. The new character assets declare:

- archer: `count: 36`;
- swordsman: `count: 38`;
- brawler: `count: 43`.

`visuals:check` validates clip and frame-visual indices against `count` when present, otherwise against full grid capacity. This prevents clips from silently selecting transparent padding cells.

## Verification

Run:

- `pnpm assets:check`
- `pnpm visuals:check`
- `pnpm enemies:check`
- `pnpm maps:check`
- `pnpm typecheck`
- `pnpm build`

Browser smoke tests must verify:

- all three worm types spawn;
- idle/walk direction and side flipping;
- archer attack and arrow orientation;
- swordsman attack;
- brawler attack and impact effect;
- directional death playback and cleanup;
- scene transitions do not leave visuals, effects, projectiles, listeners, or tweens behind;
- Blobfather and all removed enemy types never appear.
