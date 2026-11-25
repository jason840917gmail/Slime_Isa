# Health and damage: the 2026-11-24 rebalance

*Status: applied 2026-11-24 (uncommitted, not played, tests not run). Every number below is the one in
the data or scene it names.*

## The owner's words (2026-11-24)

> "we are going to keep the orbs and avoid the hearts, but will start with 80, then fix the swordsman
> health, balance enemies damages to match 5 10 20 40 damages and more if need it and remove the armor
> so we get real damage, scale healing items to match, we need to take into account that as we
> progress in the game the enemies need to be stronger to pose a threat"

and before that: "the swordsman need to be kill by 2 light hits".

## The rules

1. The slime starts with **80** health (`character.player.stats.maxHp`). The health orb stays the HUD:
   no hearts.
2. **No armour:** `character.player.stats.defense` is 0, so nothing subtracts a flat amount and the
   number on an attack is the number the slime loses. (`player.gd` `mitigate_damage` still floors a
   hit at 1 and still skips the defence for a `true_damage` request; with 0 the two paths agree.)
3. Every damage to the slime is on the grid **5, 10, 20, 40** (60 or 80 kept for a rare finishing
   blow; nothing uses them yet).
4. **Enemies grow with the game.** Each enemy has a tier by where the slime first meets it (its first
   placement in a world; the design chapter for the four that are placed nowhere yet):

   | Tier | Where | Quick or ranged poke | Slow, telegraphed blow |
   |---|---|---|---|
   | 1 | The prologue, Slimeshire Meadow (chapter 1) and Fatty's Lair | 5 | 10 |
   | Boss 1 | Fatty One Eye | 10 | 20 |
   | 2 | Gloop Forest and the Weaver Hollow (chapter 2) | 10 | 20 |
   | Boss 2 | The Orb-Weaver Matron | 20 | 40 |
   | 3 | The Crystal Caverns, the Crystal Mine and the climbing walls (chapter 3) | 20 | 40 |
   | Boss 3 | The Crystal Colossus | 20 | 40 (see [Unsure](#numbers-i-was-unsure-of)) |

   Two kinds sit one step under their tier: a **swarm** (the Broodling, the Crystal Mite), because
   several bite at once, and a **repeated tick** (the Cocoon Mimic's chew while it holds the slime).
   A mini-boss takes its tier's high number.
5. **Healing** keeps its share of the slime's health: the new amount is the old share of 100 taken
   of 80, rounded to the nearest grid number.
6. The **Worm Swordsman** dies to two light throws (a light throw is `gulp.throwCombat.throwDamage`
   25): **40** health, in `worm-swordsman.tscn` and in `enemy-types.json`.
7. Left alone: the slime's own damage, enemy health (but the swordsman's), energy, and the Goo
   Heart's +20 (four quarters of 5).

The slime's health through Release 1 (what this curve is set against): 80 at the start; about 100
at Fatty (four of chapter 1's five heart quarters) and 120 after his full heart; about 140 at the
Matron and 160 after her; 160 to 180 in chapter 3 (one Caverns quarter is placed so far).

## Hits to die

| | Before (100 health, defence 3) | After (80 health, no defence) |
|---|---|---|
| Prologue worm | 7 a hit: 15 hits | 5: 16 hits |
| Chapter 1, ordinary (Worm Archer's arrow) | 19: 6 hits | 5: 16 hits |
| Chapter 1, heavy (Worm Swordsman, Worm Brawler) | 34 and 49: 3 hits | 10: 8 hits |
| Fatty's landing | 29: 4 hits | 20: 4 hits (5 at his fight's ~100) |
| Chapter 2, ordinary (Orb-weaver's web, Popworm) | 27 and 15: 4 and 7 hits | 10: 8 hits (12 at ~120) |
| Chapter 2, heavy (Thornball, Clod Stomper) | 19 and 23: 6 and 5 hits | 20: 4 hits (6 at ~120) |
| The Matron's volley | 17: 6 hits | 40: 2 hits (4 at her fight's ~140) |
| Chapter 3, ordinary (Glint Bat, Pick Mole) | 9 and 11: 12 and 10 hits | 20: 4 hits (8 at ~160) |
| Chapter 3, heavy (Shardback) | 23: 5 hits | 40: 2 hits (4 at ~160) |
| The Colossus's stomp | 21: 5 hits | 40: 2 hits (5 at his fight's ~180) |

Before, chapter 1 was the hardest part of the game (a swordsman took a third of the slime) and the
later chapters the easiest; now each chapter takes about as many hits at the health the slime has
when it gets there, and a boss about half as many.

## The table

"Data" is `godot/game/data/enemy-types.json` (`ai`, `pattern` and `projectile` blocks), "constants"
`godot/game/data/game-constants.json`, "scene" `godot/game/scenes/characters/<type>.tscn`
(`attributes`, `projectile` and the script's exports). Where both hold a number, both changed and
agree. A script's fallback (`pattern("key", fallback)` or an export's default) changed with its data
so a missing key never brings an old number back.

### The slime

| Source | Where | Old | New | Why |
|---|---|---|---|---|
| Max health | constants `character.player.stats.maxHp` | 100 | 80 | rule 1 |
| Defence | constants `character.player.stats.defense` | 3 | 0 | rule 2 |

### Enemies

| Enemy | Attack | Where | Old | New | Tier | Why |
|---|---|---|---|---|---|---|
| Prologue worm | contact | data `ai.contactDamage`, scene | 10 | 5 | 1 | the prologue's poke |
| Worm Swordsman | slash | data `ai.contactDamage`, scene | 37 | 10 | 1 | its one wound-up blow (400 ms) |
| Worm Swordsman | health | data `maxHp` / scene `max_health` | 90 / 8 | 40 / 40 | — | rule 6 |
| Worm Archer | arrow | data `projectile.damage`, scene | 22 | 5 | 1 | ranged poke |
| Worm Archer | contact (unused: it shoots) | data `ai.contactDamage`, scene | 22 | 5 | 1 | kept on the grid |
| Worm Brawler | lunge | data `ai.contactDamage`, scene | 52 | 10 | 1 | the army's heaviest blow, after a crouch |
| Slime Spider | web | data `projectile.damage`, scene | 50 | 5 | 1 (Slimeshire C5, D4) | ranged poke; the web's root is its real cost |
| Slime Spider | contact (unused) | data `ai.contactDamage`, scene | 22 | 5 | 1 | kept on the grid |
| Spitcap | spore seed | data `projectile.damage`, scene | 16 | 5 | 1 (design; not placed) | ranged poke |
| Hopper | landing | scene `attributes.contactDamage` | 20 | 10 | 1 (design; not placed) | a telegraphed jump |
| Bramble Boar | charge | data `pattern.chargeDamage` | 30 | 10 | 1 (design; not placed) | a telegraphed charge |
| Thorn Guard Statue | contact | scene `attributes.contactDamage` | 24 | 10 | 1 (design; not placed) | marching stone |
| Rook Thief | — | — | — | — | — | steals coins, never hurts |
| Squint | slam | data `pattern.slamDamage` | 12 | 5 | 1 (Lair) | a small slam (52 px ring); the Big Squint keeps the 10 |
| Big Squint | slam | data `pattern.slamDamage` | 18 | 10 | 1 (Lair), mini-boss | high number |
| Pipe Worm | mud glob | data `projectile.damage`, scene | 14 | 5 | 1 (Lair) | ranged poke |
| Dung Roller | ball | data `pattern.ballDamage` | 20 | 10 | 1 (Lair) | the ball is the heavy hit |
| Dung Roller | fury charge | data `pattern.chargeDamage` | 15 | 5 | 1 (Lair) | kept under the ball, as before |
| Worm Bulwark | charge | data `pattern.chargeDamage` | 30 | 10 | 1 (Lair R3) | telegraphed charge |
| Carnivore Plant | chew (one a bite) | data `pattern.chewDamage` | 33 | 20 | 1 (Lair R10), owner's exception | the owner, 2026-11-24: "put plants back to 40 damage at least", then "Make it 20 + 20": a bite costs 40 (chew + spit) |
| Carnivore Plant | spit | data `pattern.spitDamage` | 21 | 20 | 1 (Lair R10), owner's exception | as above |
| Bone Leaper | landing | data `pattern.landDamage` | 24 | 10 | 1 (Lair R8) | a big telegraphed leap |
| Bone Marcher | contact | scene `attributes.contactDamage` | 20 | 5 | 1 (Lair R8) | a patroller's touch |
| Watcher Eye | beam | data `pattern.beamDamage` | 24 | 10 | 1 (Lair) | its one blow, after the gaze and flash |
| Prism Eye | beam | data `pattern.beamDamage` | 22 | 10 | 1 (Lair C2, first) | as the Watcher Eye |
| **Fatty One Eye** | contact hop | scene `attributes.contactDamage` | 18 | 10 | Boss 1 | poke |
| Fatty One Eye | landing | scene `landing_damage`, `fatty.gd` default | 32 | 20 | Boss 1 | his telegraphed leap |
| Fatty One Eye | mud ripple (phase two) | `fatty.gd` `phase_two_ripple_damage` default and fallback | 18 | 10 | Boss 1 | a ring to hop over |
| Fatty One Eye | falling clod | `lair_director.gd` `clod_damage` default | 12 | 10 | Boss 1 | shadow-telegraphed, but many fall |
| Popworm | bite | data `pattern.biteDamage` | 18 | 10 | 2 (Gloop E3, first) | a quick bite after the tail's tell |
| Orb-weaver | web | scene `projectile.damage` | 30 | 10 | 2 | ranged poke |
| Orb-weaver | contact (unused) | scene `attributes.contactDamage` | 26 | 10 | 2 | kept on the grid |
| Clod Stomper | slam | `clod_stomper.gd` `slam_damage` default | 26 | 20 | 2 | behind a ring telegraph |
| Silk Lurker | drop | data `pattern.dropDamage` | 18 | 20 | 2 | the shadow-telegraphed drop |
| Silk Lurker | sway | data `pattern.swayDamage` | 8 | 10 | 2 | a touch while it hangs |
| Thornball | roll | data `pattern.rollDamage` | 22 | 20 | 2 | a telegraphed curl and roll |
| Broodling | bite | data `pattern.biteDamage` | 6 | 5 | 2, swarm | one step under: up to six bite |
| Cocoon Mimic | chew (every second while held) | data `pattern.chewDamage` | 6 | 5 | 2, repeated tick | the hold's cost is mostly the energy drain |
| Cocoon Mimic | spit | data `pattern.spitDamage` | 10 | 10 | 2 | already on the grid |
| Brood Warden | sweep | data `pattern.sweepDamage` | 20 | 20 | 2, mini-boss | already on the grid |
| Bone Thrower | bone | data `projectile.damage`, scene | 16 | 10 | 2 (Weaver Hollow Roots, first) | ranged poke |
| Jelly Bouncer | zap | data `pattern.zapDamage` | 20 | 20 | 2 (not placed; see Unsure) | a random, telegraphed zap |
| Jelly Bouncer | a throw bounced back | data `pattern.bounceDamageLight` / `Medium` / `Heavy` | 12 / 18 / 26 | 10 / 20 / 20 | 2 | the slime's own throw, back |
| **Orb-Weaver Matron** | volley | scene `volley_damage`, `matron.gd` default | 20 | 40 | Boss 2 | 900 ms telegraph, every 6.5 s |
| Orb-Weaver Matron | web spit | scene `projectile.damage` | 18 | 20 | Boss 2 | poke |
| Orb-Weaver Matron | contact (unused) | scene `attributes.contactDamage` | 30 | 20 | Boss 2 | kept on the grid |
| Gloomling | bite | data `pattern.contactDamage` | 12 | 20 | 3 | a bite after the hunt's tell |
| Glint Bat | swoop bite | data `pattern.biteDamage` | 12 | 20 | 3 | poke |
| Crystal Crawler | spikes | scene `attributes.contactDamage` | 14 | 20 | 3 | touch |
| Pick Mole | pickaxe | data `pattern.pickDamage` | 14 | 20 | 3 | lobbed, three in a row |
| Shardback | slam | data `pattern.slamDamage` | 26 | 40 | 3, mini-boss | high number |
| Crystal Mite | landing | data `pattern.landDamage` | 10 | 10 | 3, swarm | one step under |
| Crystal Mite | contact | scene `attributes.contactDamage` | 8 | 10 | 3, swarm | one step under |
| Rock Chucker | boulder | data `pattern.rockDamage` | 14 | 20 | 3 (the climbing walls) | thrown from the rim |
| Spiny Caterpillar | spikes | scene `attributes.contactDamage` | 12 | 20 | 3 | touch |
| Ledge Raven | flight | scene `attributes.contactDamage` | 10 | 20 | 3 | touch |
| **Crystal Colossus** | contact | data `pattern.contactDamage` | 14 | 20 | Boss 3 | touch |
| Crystal Colossus | stomp | data `pattern.stompDamage` | 24 | 40 | Boss 3 | see Unsure |

Every other enemy number (`zapEnemyDamage`, `bowling.damage`, `rollDamage` in a `reactions` block, the
`...DamageTaken` multipliers) is damage to enemies and is unchanged.

### Hazards, mechanisms and the slime's own blast

These meet the slime in every chapter with one number each, so they keep their share of its health.

| Source | Where | Old | New | Why |
|---|---|---|---|---|
| Void (a hole, the sky floor) | constants `dungeon.void.damage` | 10 | 10 | 10 % of 80 = 8 → 10 |
| Spikes | constants `dungeon.spikes.damage` | 8 | 10 | 6.4 → 5 is too light for a pit of spikes; 10 |
| Lava | constants `dungeon.lava.damage` | 12 | 10 | 9.6 → 10 (none placed in Release 1) |
| Deep water | constants `dungeon.water.damage` | 10 | 10 | 8 → 10 |
| Burr's yard ditch, Fatty's moat (Slimeshire C4, D5) | the hazards' own `damage` in `level-1-c4.tscn`, `level-1-d5.tscn` | 5 | 5 | already on the grid |
| The ram (Weaver Hollow) | constants `dungeon.ram.slimeDamage` | 12 | 20 | tier 2's heavy blow |
| The runaway cart (Crystal Mine) | constants `dungeon.ramCart.slimeDamage` | 15 | 20 | tier 3's low number: the slime's own tool, on rails it can see |
| Goo Bomb's blast on the slime | constants `abilities.gooBomb.selfDamage` | 18 | 10 | 14.4 → 10 |
| Goo Bomb in the mouth | constants `abilities.gooBomb.mouthDamage` | 28 | 20 | 22.4 → 20 |
| Burn, poison | `game/player/status_effects.gd` | 3 and 2 a tick | unchanged | nothing applies them (Phaser leftovers); off the grid |

### Healing

| Source | Where | Old | New | Why |
|---|---|---|---|---|
| Slime Tonic (`hp-potion`) | `items.json` `use.healHp` | 40 | 40 | 40 % of 80 = 32 → 40 (see Unsure) |
| Berry Basket | `items.json` `use.healHp` | 20 | 20 | 20 % of 80 = 16 → 20 |
| A dungeon pot's heart | constants `dungeon.refill.heartHp` | 20 | 20 | 16 → 20 |
| Fairy ring (Gloop E4) | `fairy_ring.gd` `heal_amount` / `every_ms` | 2 a 700 ms | unchanged | a quiet rate, no number shown |
| Sleep, the bath | constants `rest.sleepHpRegenPerSec`, `bathHpRegenPerSec` | 2 a second | unchanged | rates |
| A heart, a full heart, a respawn | `goo_heart.gd`, `full_heart.gd`, `player.gd` | fill in full | unchanged | |

## What grants defence

Nothing else in the build. The search covered the skins (Heavy: plates and blocks, no damage change;
Silk: webs; Feral: climbing, a fall costs nothing), the items, recipes and abilities, and
`combat_scaling.gd` (the attributes scale the slime's own hits only). What keeps the slime from a hit
is time, not a reduction: the 500 ms after a hit (`hitInvulnerabilityMs`), the Roll's untouchable
window and the improved Slam's air time. Planned only: "Thick Jelly, 25 % less damage" (Frostpeak's
Pearl in [the power curve](2026-10-11-world-power-curve.md), after Release 1).

## Enemy health: scene against data

Every type with both agrees but the Worm Swordsman (scene 8 since an editor re-save on 2026-10-06,
commit 88499375; data 90), now 40 in both. Four types have no `maxHp` in the data and keep their
scene's: the Orb-weaver 70, the Clod Stomper 90, Fatty One Eye 140, the Matron 300.

## Numbers I was unsure of

- **The cross-chapter enemies keep their first tier.** The Slime Spider, the Worm Swordsman, the
  Dung Roller (Gloop Forest), the Watcher Eye, the Prism Eye and the Bone Leaper and Marcher (the
  Weaver Hollow and the Mine) are first met in chapter 1, so they hit 5 or 10 in chapters 2 and 3 too.
  One number per type cannot grow by region; a per-region damage scale would need code (not done).
  The Prism Eye is the odd one: a Caverns enemy whose first placement is one room of Fatty's Lair
  (C2, the Weigh House).
- **The Colossus's stomp is 40, not one step above his chapter (60).** The grid keeps 60 for a rare
  finishing blow, and the stomp is his ordinary attack, every 2.6 s; at 40 it takes about five at his
  fight. 60 if the owner wants him deadlier.
- **The Carnivore Plant** cost 48 a bite (the owner, 2026-11-21: "the chew alone makes 30 damage");
  first set to 20, then back up on the owner's word (2026-11-24: "put plants back to 40 damage at
  least", then "Make it 20 + 20"): a chew of 20 and a spit of 20, 40 a bite, the one tier-1 enemy
  above its tier.
- **The Jelly Bouncer** is placed nowhere yet; tier 2 because the Goo Bomb (chapter 2) is the first
  thing that kills him. His bounced-back medium and heavy throws are both 20.
- **The Slime Tonic and the Berry Basket did not change**: rounded to the nearest grid number, 32 and
  16 come back to 40 and 20. The other reading (heals only 5, 10, 20) makes the Tonic 20 and the
  Basket 10.
- **The Popworm** is a chapter 1 enemy in the [bestiary](2026-10-16-bestiary.md) but is placed only
  in Gloop Forest, so it is tier 2 (10). The four tier-1 enemies placed nowhere (Spitcap, Hopper,
  Bramble Boar, Thorn Guard Statue) took their design chapter.
