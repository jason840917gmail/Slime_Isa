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

| Asset | Geometry | Purpose |
| --- | --- | --- |
| `64x64-8x6-worm-archer.png` | 8 columns × 6 rows, 64×64 frames | Archer character |
| `64x64-4x10-worm-swordsman.png` | 4 columns × 10 rows, 64×64 frames | Swordsman character |
| `64x64-8x6-worm-brawler.png` | 8 columns × 6 rows, 64×64 frames | Brawler character |
| `16x10-1x1-worm-arrow.png` | 16×10 image | Archer projectile |
| `16x20-1x3-worm-brawler_hits.png` | 1 column × 3 rows, 16×20 frames | Brawler impact effect |

These assets use transparency and must be cataloged in `asset/assets.json` with stable IDs. Character sheets, the arrow, and the hit effect belong to the boot bundle.

## Chosen approach

Use a hard active-roster replacement.

Old enemy IDs will not remain as hidden runtime aliases and will not be silently mapped to worm enemies. This keeps authored maps, editor choices, analytics events, and future balancing semantically correct.

Alternative approaches were rejected:

- Filtering old definitions only at spawn time leaves incomplete enemies selectable elsewhere.
- Reusing old IDs for worms avoids map edits but gives misleading names and permanent migration debt.

## Active enemy definitions

`EnemyConfig` gains a stable enemy ID and requires a visual set. Regular enemies no longer use a procedural `textureKey` as their identity or render source.

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

Existing balance values may be reused by role where sensible, but the new IDs are authoritative.

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

The brawler impact effect may use a separate effect visual definition because it is not anchored character state. The arrow remains a static projectile image.

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
| Attack | `attack-<direction>` |
| Dead | `die-<direction>` |

Clip playback changes only when the resolved clip or flip changes. Attack and death clips are not restarted each update.

Death disables physics/gameplay immediately, plays the directional death clip once, then fades or destroys the enemy. A short timeout remains as a defensive fallback if animation completion does not fire.

## Attack visuals

The projectile API receives the firing enemy's projectile texture key or asset-derived configuration. The archer uses the authored arrow image and rotates it to its travel vector.

The brawler hit animation is spawned as a short-lived effect at the attack/contact point. Its animation and object are explicitly destroyed after completion or scene shutdown.

Swordsman attacks use the character sheet's attack animation and do not require a separate effect asset.

## Map and editor migration

Only the three worm IDs remain in `ENEMY_CONFIGS`, so the map editor automatically exposes only complete enemies.

Every authored map spawn entry is rewritten to one of the three new IDs. Existing weights are aggregated by role:

- Ranged old types → `worm-archer`
- Durable or weapon-like old types → `worm-swordsman`
- Fast, swarm, leap, or contact old types → `worm-brawler`

Weights are normalized per map, duplicate entries are merged, and existing `maxAlive` limits are preserved conservatively. Maps that previously exposed one incomplete special enemy receive one suitable worm type rather than retaining an invalid ID.

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

Procedural enemy texture generation and the procedural enemy projectile are removed when no active consumer remains. Generic boss UI or progression infrastructure may stay if it has no active boss-specific wiring.

## Validation

Repository validation must enforce:

- every active enemy has a unique stable ID;
- every active enemy references a known visual set;
- every enemy visual set references a ready manifest spritesheet;
- all twelve required directional clips exist;
- every clip frame is within sheet bounds and points to a populated authored frame;
- ranged enemies reference a ready projectile asset;
- no authored map references a removed enemy ID;
- no removed enemy appears in the editor roster or runtime spawn tables.

## Verification

Run:

- `pnpm assets:check`
- `pnpm visuals:check`
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
