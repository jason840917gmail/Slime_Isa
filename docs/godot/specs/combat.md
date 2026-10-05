# Combat spec — Phase 0 trial (basic sword vs worm swordsman)

Source of truth: the Phaser app on `feat/godot-migration` (read 2026-10-04). All
paths are under `src/game/` unless they start with `src/`. Line numbers are
`file:line` in the current tree. "Centre" = the old Phaser body position (the
CharacterBody2D node position); "feet" = the Godot root after re-anchoring
(conventions, *Feet origin*): `centre = feet - depth_anchor * scale`.

Binding inputs: `docs/GODOT_MIGRATION.md`, the shared `docs/godot/CONVENTIONS.md`.

---

## 0. Scope

### IN (trial)

| Feature | Where it lives in Phaser |
|---|---|
| Equipping the basic sword and mounting its scene on the player | `features/world/UniversalSceneWorldController.ts:1637` `mountWeapon`, `features/combat/CombatController.ts:110` |
| Swing input, aim (pointer / facing), 4-way direction | `scenes/WorldScene.ts:1749` `attack()`, `CombatController.ts:63,148` |
| Swing damage payload (attack stat, attribute scaling, crit) | `CombatController.ts:148-176`, `combat/CombatScaling.ts` |
| Swing timeline: cooldown, hit windows (frame spans), sector hitboxes, animations, swing SFX | `features/scripts/WeaponScript.ts`, `content/scenes/authored/weapons/basic-sword.scene.json` |
| Hit detection (Area2D contact, level-triggered), one hit per receiver per window | `WeaponScript.ts:142-157, 283-345` |
| Damage resolution pipeline (router, resolver, activation dedupe) | `features/combat/DamageRouter.ts`, `DamageResolver.ts`, `AttackActivation.ts`, `DamageReceiver.ts` |
| Enemy damage reaction: HP, knockback, hit-stun, hit flash, damage number, defeat | `features/scripts/EnemyScript.ts:255-316, 361-378, 515-533, 863-867` |
| Enemy melee vs player: windup, impact, reach, damage, knockback | `EnemyScript.ts:724-795`, `enemies/enemyCombatLifecycle.ts` |
| Player damage pipeline: dodge block, i-frames, defense, commit, knockback, flash, number | `features/scripts/PlayerScript.ts:214-238`, `features/player/PlayerHealthController.ts`, `PlayerHealthService.ts`, `WorldScene.ts:339-353, 1892-1918` |
| Hit-stop and camera shake (GameFeel presets) | `features/feel/GameFeel.ts`, `WorldScene.ts:735-748, 792-799` |
| Impact effect `effect.basic-sword-impact` | `CombatController.ts:223-234`, `features/scripts/EffectScript.ts`, `content/scenes/authored/effects/basic-sword-impact.scene.json` |
| Floating damage numbers | `features/ui/FloatingTextSurfacePort.ts` (active path), `ui/FloatingText.ts` (fallback) |
| Hit particles `hit-spark` (enemy hit), `slime-splash` (player hurt) | `features/feel/ParticlePresets.ts` |
| Combo damage multiplier (only because it changes damage when one swing hits 2+ enemies; see 9.4) | `combat/ComboSystem.ts` |

### OUT (exists in Phaser; later phases)

- Harvesting trees/rocks/resources (`targetTags` `resource`/`stone`, `harvestCapabilities`, `HarvestAdvice.ts`, `DestructibleScript`, `ResourceNodeScript`), harvest messages.
- Every other weapon (spear, axe, pickaxe, hammer, gauntlet), weapon belt/hotbar/wheel switching (`systems/WeaponLoadout.ts`, `core/WeaponSlots.ts`), `equipWeapon` swaps, weapon icons.
- Projectiles (`ProjectileScript`, enemy `projectile` property, worm archer), `LineStrike.ts` (Stretch Lash probe, Squash Slam `strikeArea`), legacy pooled `combat/Hitbox.ts` (abilities + dev overlay only), `combat/TargetDummy.ts`, `TrainingDummyScript`, `LashBellScript`.
- Status effects other than knockback: `web` (spider web stick), goo-trail `slow`, `sticky`/rooted, Gulp forms (`knockbackImmune`, form tints/skins).
- Combo UI (the "Nx COMBO" text, "3x FINISHER!" text) — the multiplier itself is IN (9.4).
- Bosses (`rank: boss`, arena leash, immune message "This weapon cannot hurt it!", `source-blocked` handling, boss bars), camps/territory regen, enemy AI and spawning (owned by the ENEMY spec; only the attack lifecycle is here).
- Enemy rewards: coins (`+10c` text), item loot drops (`dropEnemyLoot`), `enemy.died` quest events.
- Player death flow beyond "mark dead + play `die`": game-over shell, respawn at bed, `DEFEATED` text is cheap and may be kept.
- HUD: health bar flash (`flashPlayerHealthBar`), player health UI.
- Dodge roll itself (player spec); this spec only says dodging blocks damage.
- Dev overlay (`debugSwing`, `debugAttackAreas`), `WeaponHitRequest.ts`, `ConfirmedHitEffect.ts`, `DamageableTarget.ts`, `CombatBodyGeometry.ts` (legacy/overlay geometry).
- Elevation reach gate: **not present on this branch** (`DamageRouter.ts` has no reach gate); the port ignores levels (GODOT_MIGRATION: elevation redesigned later).
- Squash-and-stretch "hit" on the slime and the `slime-splash` particles are presentation nice-to-haves (described, low priority).

---

## 1. Object map and data sources

| Phaser object | Godot node (converted) | Data |
|---|---|---|
| `weapon.basic-sword` scene (`BasicSword` Node2D root, no `depthAnchor`) | `res://generated/scenes/weapons/basic-sword.tscn` | root children: `Base1`, `Layer22` (Sprite2D), `AttackArea` (Area2D, layer 16 / mask 8, monitoring false) with 4 CollisionShape2D (`right--primary`, `left--primary`, `up--primary`, `down--primary`, all `disabled`), `Animation` (AnimationPlayer, physics domain, autoplay `idle`), `WeaponScript` (Node, `res://game/scripts/weapon.gd`), `SwingSfx` (AudioStreamPlayer, `sfx.weapon.swing-blade` + 2 variants, pitchRandomness 0.06) |
| `character.player-slime` (root `PlayerSlime` CharacterBody2D, `depthAnchor [0, 27.56]`) | `.../characters/player-slime.tscn`, root at feet, `metadata/depth_anchor = (0, 27.56)` | `DamageArea` Area2D layer 8 (hurtbox) / mask 16, monitoring false, monitorable true; shape rect 30×26 at centre+(0,14.56) = feet+(0,−13). `PlayerScript` → `player.gd`. `HurtSfx` (`damaged` → play, minInterval 120 ms), `DeathSfx` (`defeated` → play) |
| `character.worm-swordsman` (root CharacterBody2D layer 4 / mask 1027, `depthAnchor [0, 22]`) | `.../characters/worm-swordsman.tscn` | `DamageArea` layer 8 / mask 16, monitoring+monitorable true, rect 36×26 at centre+(0,9) = feet+(0,−13). `AttackArea` layer 16 / mask 8, monitoring false, circle r 51.3 (disabled; **inert**, see 7.3). `EnemyScript` → `enemy.gd`. SFX: `HurtSfx` (`damaged`), `DeathSfx` (`defeated`, detached), `AlertSfx` (`alerted`), `WindupSfx` (`attack_started`) |
| `effect.basic-sword-impact` (root Node2D, `depthAnchor [0,0]` → no shift) | `.../effects/basic-sword-impact.tscn` | `Base1` Sprite2D (`effect.weapon.hit-tiles`, 126×126, scale 0.3), `Animation` clips `right/left/up/down`, `EffectScript` (`effect_id`, `lifetime_ms` 1000), `ImpactSfx` (AudioStreamPlayer2D, autoplay, detached, `sfx.weapon.hit-slash` + 1 variant, pitchRandomness 0.07) |

Value sources used below:

| Value | Number | Source |
|---|---|---|
| sword base damage | 20 | `basic-sword.scene.json` WeaponScript `baseDamage` (= `content/weapons/basic-sword/weapon.json` `baseDamage`; Phaser reads the weapon.json copy via `WeaponCatalog`, identical) |
| sword cooldown | 1200 ms | scene `cooldownMs` (= weapon.json) |
| sword knock strength | 140 | scene `knockStrength` (= weapon.json `knockStrength`) |
| sword scaling | `damage {strength: 2}`, `cooldown {agility: 0.25}`, `knockback {strength: 0.25}` | scene `scaling` (= weapon.json) |
| sword damage modifiers | `stone ×0`, `resource ×0.1` | scene `damageModifiers` (no effect on enemies, tag `enemy`) |
| sword on-hit effect | `basic-sword-impact` | scene `onHitEffectId` |
| player action clip on swing | `attack-1` (all 4 directions) | **weapon.json only** (`directionalAttacks.*.characterActionId`); not in the scene JSON → literal `"attack-1"` in the port, or ask the converter owner to carry it |
| player attack stat | 12 | `game-constants.json` `character.player.stats.attack` |
| crit chance / multiplier | 0.05 / 1.75 | `character.player.stats.critChance` / `critMultiplier` |
| player defense | 3 | `character.player.stats.defense` |
| player max HP | 100 | `character.player.stats.maxHp` |
| player i-frames after a hit | 500 ms | `character.player.hitInvulnerabilityMs` |
| attributes (strength, vitality, agility, intellect) | 10 each at a new run | `character.player.initialAttributes` |
| input buffer | 150 ms | `input.bufferMs` |
| player damage-taken multiplier | 1 | literal in `systems/PlayerStats.ts:50` |
| worm HP | 90 | worm scene EnemyScript `maxHealth` (= `enemy-types.json` `maxHp`) |
| worm attack range / aggro | 38 / 220 | scene `attackRange` / `targetingRadius` |
| worm attack cooldown | 1500 ms | scene `attackCooldownMs` |
| worm windup / recovery | 400 / 400 ms | scene `attributes.attackWindupMs` / `attackRecoveryMs` |
| worm contact damage | 37 | scene `attributes.contactDamage` |
| worm knockback strength (on player) | 260 | scene `attributes.knockbackStrength` |
| worm knockback resist | 0.45 | scene `attributes.knockbackResist` |
| worm damage rule | priority 0, multiplier 1 | scene `damageRule` |
| enemy-type numbers | same values | `enemy-types.json` `types.worm-swordsman.ai` (Phaser uses the **scene** values for combat; `enemy-types.json` only feeds `drop` and the spawner) |
| enemy hit constants | see 7.2 | literals `EnemyScript.ts:102-116` |
| player knockback duration | 160 ms | literal `PlayerHealthController.ts:134` |
| hit flash colour / duration | `#ff6f88` / 120 ms | literals `EnemyScript.ts:110-111`, `WorldScene.ts:1912-1913` |
| feel presets | see §10 | literals `GameFeel.ts:35-51` ("presentation, owned here rather than in game-constants.json") |
| combo | window 600 ms, multipliers 1.0/1.15/1.5 | literals `ComboSystem.ts:9-11` |

The literals are existing code constants, not new balance values: port them as
named `const`s in the script that owns them, each with a comment naming the
Phaser file. (If the architect prefers, they can move to `game-constants.json`
in Phase 2; the trial must not edit `src/`.)

---

## 2. Event flow overview (one swing that hits a worm)

```
input "attack" (fixed step, before scripts)          WorldScene.handleActionInput :1816
  └─ attack(): face pointer (snap 4-way)              WorldScene.ts:1749
       └─ CombatController.tryAttack()                CombatController.ts:148
            ├─ gate: weapon equipped, !attacking, canAttack(), weapon.canBeginAttack()
            ├─ direction = 4-way(facing); payload {damage, knockbackStrength, cooldownMs, weaponTags, damageTypes}
            └─ WeaponScript.tryBeginAttack(direction, payload)       WeaponScript.ts:172
                 ├─ readyAt = now + cooldownMs
                 ├─ combat.onAttackStarted → actionLocked=true, player velocity 0, player plays "attack-1"
                 ├─ weapon AnimationPlayer.play("attack-<dir>")
                 └─ emit attack_started → SwingSfx.play
            (crit rolled: gameFeel.play("critical-hit") immediately)
each fixed step (WeaponScript._physics_process)
  1. resolve contacts of the AttackArea (shapes enabled last step)   → per new receiver: route damage
  2. elapsed >= durationMs → finishAttack (shapes off, weapon "idle", player "idle", unlock)
  3. frame = floor(elapsed/1000*fps); open/close hit windows; enable only "<dir>--<hitboxId>" shapes
route damage (per receiver per window)
  CombatController.transformManagedWeaponDamage (modifier × combo)  → DamageRouter.routeStep
     → resolveDamage (source match, dead check, multipliers, rounding, clamp)
     → EnemyScript.commitDamage: hp -= dmg; signals health_changed, damaged(→HurtSfx);
        reactToDamage: flash, damage number, cancel attack, knockback velocity, stun, "knockback-<facing>"
        or defeat(): stop, collision off, "die-<facing>", defeated(→DeathSfx)
     → CombatController.onManagedWeaponOutcome: gameFeel "hit" (hit-stop 65 ms), hit-spark,
        spawn effect.basic-sword-impact at target centre (front of target), crit sting once
```

---

## 3. Equipping and mounting the sword

Phaser: `CombatController` constructor reads `gameState.equippedWeaponId`; if set,
`mountManagedWeapon(id)` (`CombatController.ts:110-115`). A new run has **no**
weapon (`content/initial-state/InitialRun.ts:21-23`, `weaponId: null`); the
sword normally comes from story/quests. **Trial: equip `basic-sword` at start.**

`mountWeapon` (`UniversalSceneWorldController.ts:1637-1660`):
1. instance `weapon.basic-sword`;
2. find its WeaponScript, check `weaponId` matches;
3. reparent the weapon root under the **player body node**, then set its local position to `(0, 0)` — i.e. the weapon root sits on the player's **centre**;
4. dispose any previous weapon mount.

**Feet origin (F1):** in Godot the player root is at the feet. Add the weapon
instance as a child of the player root at local `position = -depth_anchor`
= `(0, -27.56)` (read `player.get_meta("depth_anchor")`; player scale is 1).
Every sword sprite key position and every hitbox position below is relative to
that point. Add it as the **last child** so it draws over `Visual` (Phaser:
`Base1` depthOffset 0.01 and `Layer22` 1.011 are always in front of the slime;
the player root is not y-sorted internally, so tree order does it).

The weapon AnimationPlayer autoplays `idle`: `Base1` frame 0, alpha 1, pos (0,0),
scale 0.5 — the sword sprite is visible over the slime's centre while idle.
`Layer22` (the slash smear) alpha 0 in idle.

---

## 4. Starting a swing

### 4.1 Input gate (WorldScene)

- `attack` press is buffered: `PlayerScript.consumeActionPress('attack')` returns
  true only if the press is ≤ `input.bufferMs` (150 ms) old in simulation time
  (`PlayerScript.ts:170-176`). A press made during knockback / action lock / death
  waits in the buffer; if consumed later than 150 ms it is dropped.
- `handleActionInput` is only reached when: not dead, not sleeping, **not
  movement-suppressed (knockback)**, **not `actionLocked`** (`WorldScene.ts:839-868`).
- `attack()` (`WorldScene.ts:1749-1757`): if setting `attackAim == 'pointer'`
  (default, `GameSettingsStore.ts:34`) and the pointer gives an aim, the slime
  first faces it, snapped to 4 directions (`PointerAim.ts:29-32`: `|x| >= |y|` →
  ±x, ties go sideways). Aim origin: `(centre.x, centre.y - 28)`
  (`SLIME_CENTER_RISE_PX`, `WorldScene.ts:149,1740`); dead zone 16 px
  (`POINTER_DEAD_ZONE_PX`) → no aim → keeps current facing.
  **F2:** aim origin in Godot = `feet - (0, 27.56 + 28)`. (The 28 px rise looks
  stale — the sprite centre already is the body position — but port it as is
  and flag it to the owner; it only matters when the pointer is near the slime.)
- `face(dir)` (`PlayerController.ts:104-108`) also sets `Visual.flip_h = (|x|>=|y| && x > 0)` (slime art faces left).

### 4.2 `CombatController.tryAttack` (`CombatController.ts:148-176`)

Gates, in order: weapon equipped; `!attacking`; `canAttack()` =
`!actionLocked && !paused && !dead` (`WorldScene.ts:2243`);
`weapon.canBeginAttack()` = `simTime >= readyAt && no active plan`
(`WeaponScript.ts:133-135`). Any failure → return false, nothing happens.

Direction (`CombatController.ts:63-66`): `facing` (unit vector; zero → `(1,0)`):
`|x| >= |y|` → `x < 0 ? left : right`, else `y < 0 ? up : down`.

Damage payload (all with attributes at 10 → every scaling term is 0):

```
scaling(coefs) = Σ over attributes ((attr - 10) / 10) * coef                CombatScaling.ts:11-21
scaled(base, coefs, min=0) = max(min, base * max(0, 1 + scaling))           CombatScaling.ts:23-32
scaledDamage = round(scaled(baseDamage * (attack / 10), scaling.damage))     = round(20 * 1.2) = 24
critical = randf() < critChance (0.05)
damage = critical ? round(scaledDamage * critMultiplier) : scaledDamage      = 24, crit 42
knockbackStrength = scaled(knockStrength, scaling.knockback)                 = 140   (not rounded)
cooldownMs = scaled(cooldownMs, scaling.cooldown, min 1)                     = 1200  (not rounded)
weaponTags = [weaponId contains "spear" ? "spear" : "weapon"] + ["harvest:<tag>:<tier>" ...]  = ["weapon"]
damageTypes = ["physical"]
```

Note the cooldown scaling sign: positive agility *raises* the cooldown
(`cooldown {agility: 0.25}` multiplies by `1 + 0.25*(agi-10)/10`). Port as is.

If the weapon accepted the swing and it is a crit: `gameFeel.play('critical-hit')`
**at swing start, before anything is hit** (`CombatController.ts:173`), and
`criticalAttack = true` (cleared on the first creature hit, 9.3).

### 4.3 `WeaponScript.beginAttack` (`WeaponScript.ts:182-197`)

1. `plan = attackPlans[direction]` (missing → return false).
2. `activeDirection = direction`, `activePlan = plan`, `activeSince = simTime`.
3. `readyAt = simTime + payload.cooldownMs` (cooldown counts from swing **start**; swing ≥ 292 ms, cooldown 1200 ms → one swing per 1.2 s).
4. bind services (router, activations, combat port).
5. `combat.onAttackStarted(weaponId, direction)` → `CombatController.ts:254-260`: `attacking = true`, `actionLocked = true`, player velocity `(0,0)`, player plays `attack-1` (via `playAnimation('slime-attack-1')`, ignored while knockback has priority — `WorldScene.ts:1690-1694`).
6. weapon AnimationPlayer `play(plan.animationId)` (`attack-right|left|up|down`).
7. emit `attack_started {weaponId, direction}` → `SwingSfx.play_cue(payload)`.

While `actionLocked`, `updateGameplay` stops the player each step
(`WorldScene.ts:864-868`) — the slime cannot move during a swing; knockback still
moves it (the knockback branch runs first, `WorldScene.ts:858-862`).

---

## 5. Swing timeline: plans, windows, shapes

### 5.1 Attack plans (`basic-sword.scene.json` WeaponScript `attackPlans`)

| dir | animationId | durationMs | fps | hitbox span (frames) | open while elapsed ∈ | Base1 mirrored |
|---|---|---|---|---|---|---|
| right | `attack-right` | 416.667 | 24 | `primary` 4..8 | [166.7, 375.0) ms | no |
| left | `attack-left` | 416.667 | 24 | `primary` 4..8 | [166.7, 375.0) ms | `flipX` keys true |
| up | `attack-up` | 333.333 | 12 | `primary` 1..3 | [83.3, 333.3) ms (ends with swing) | no |
| down | `attack-down` | 291.667 | 24 | `primary` 1..5 | [41.7, 250.0) ms | no |

`damageMultiplier` and `knockbackMultiplier` are 1 for every span (defaults 1
when absent, `WeaponScript.ts:220-221`). `events: []`, `mirrored` is unused by
the runtime.

### 5.2 Per-step state machine (`WeaponScript._physics_process`, `WeaponScript.ts:142-157`)

States: `Idle` (no plan) → `Swinging` → `Idle`.

Each physics step while `Swinging`, in this order:
1. `simTime += delta*1000` (the weapon's own clock; frozen by hit-stop).
2. **Resolve current overlaps** of the AttackArea for every *open* window
   (`resolveCurrentOverlaps`, `:283-287`). These contacts were computed by the
   physics step after the previous `_physics_process`, i.e. against the shapes
   enabled last step.
3. `elapsed = simTime - activeSince`; if `elapsed >= durationMs` → `finishAttack()` and return.
4. `frame = floor(elapsed / 1000 * fps)`; `updateWindows(plan, frame)` (`:256-272`):
   for each span *i*: `open = from <= frame <= through`.
   - open and no window *i* → create window *i* `{span, activationId = activations.begin(weapon, [attackArea]), resolvedReceivers = {}}`.
   - not open and window *i* exists → close it (`activations.end`).
   - then `setAttackAreaActive(windows non-empty, set of open hitboxIds)`.
5. `setAttackAreaActive(active, ids)` (`:361-372`): `AttackArea.monitoring = active`;
   for each CollisionShape2D child named `<dir>--<hitboxId>`:
   `disabled = !active || dir != activeDirection || hitboxId not in ids`.

`finishAttack()` (`:227-239`): all shapes disabled + monitoring off, close all
windows, release services, clear plan/direction, weapon AnimationPlayer
`play('idle')`, `combat.onAttackFinished` → `CombatController.ts:262-267`
(`attacking = false`, `actionLocked = false`, player plays `idle` — skipped while
knockback has priority), emit `attack_finished {weaponId, direction}`.

`cancelAttack()` = `finishAttack()` if active; called when the weapon leaves the
tree (`_exit_tree`). `playAttack` (force restart) is not used by the sword path.

Timing at 60 Hz (elapsed after the k-th step is k·16.667 ms): right/left shapes
on at step ≈10, off at step 23, swing ends step 25. A target already inside the
sector is hit **in the step the window opens**: Phaser resolves new contacts in
the same fixed step (`collectManagedContacts` → `area_entered`,
`PhaserSceneTreeHost.ts:101-107`); `currentContacts` only keeps contact going
across window changes. (Corrected by the 2026-10-04 review; an earlier version of
this spec claimed a one-step latency.) Godot reproduces it with a deferred
`intersect_shape` pass at the end of the weapon's step (see 6.2). Floating-point frame boundaries (e.g. 166.666…) may land on
either step; do not special-case.

### 5.3 Hitbox shapes (`AttackArea` children; positions relative to the weapon root = player centre)

All four are sectors: `innerRadius 0`, `outerRadius 57`, `arcWidthRad 2.2165681500327987`
(127.0°, half-width 63.5°). A point is inside if `dist <= 57` and
`|wrap(atan2(dy,dx) - angleRad)| <= arcWidth/2` (`runtime/scene/physics/SensorGeometry.ts:103-110`).
The converter emits polygon approximations (convex — arc < 180°, apex included).

| shape node | position (centre-relative) | angleRad | position relative to player **feet** (Godot, via weapon at (0,−27.56)) |
|---|---|---|---|
| `right--primary` | (14, 15) | 0 | (14, −12.56) |
| `left--primary` | (−14, 15) | π | (−14, −12.56) |
| `up--primary` | (0, 0) | −π/2 | (0, −27.56) |
| `down--primary` | (0, 15) | π/2 | (0, −12.56) |

Shape-node rotation is ignored (sector angle comes from the resource).
(weapon.json lists `down` as offsetX 15/offsetY 0 — that is the forward-axis
form; the scene JSON position `(0,15)` is the runtime truth.)

### 5.4 Sword animation clips (weapon AnimationPlayer, physics domain)

Converted by the converter; listed so the engineer can check the port. Keys at
frame `at` (seconds = `at / fps`). `Base1` scale 0.5 throughout; `Layer22` scale 1.

| clip | Base1 frame keys | Base1 position keys (centre-relative) | Layer22 (frame 16) visible |
|---|---|---|---|
| `idle` (0.125 s, loop) | 0 | (0,0) | alpha 0 |
| `attack-right` | 0,0,0,0,1,2,3,4,5,6 | (20,−12.56)×4,(25,−8),(30,−0.66),(36,12),(36,18),(36,28),(30,38) | alpha 1 at frames 6–8, pos (60,0) |
| `attack-left` | same frames, `flip_h` true | x mirrored | frames 6–8, pos (−60,0), flip |
| `attack-up` (12 fps) | 1,0,15,14 | (20,−10),(10,−12),(0,−14),(−16,−8) | frame 3, pos (0,−26), rot 3.8397 |
| `attack-down` | 7,7,8,9,10,11,11 | (20,40),(20,40),(12.25,42.75),(1.32,45),(−15,40),(−22,32),(−22,32) | frames 5–6, pos (0,50), rot 0.6981 |

These are children of the weapon root, so they are **not** shifted by the
player's re-anchoring; placing the weapon root at (0,−27.56) (§3) keeps them right.

---

## 6. Finding a hit

### 6.1 Phaser model (contact, not distance)

- The sword uses **Area2D contact**: AttackArea (layer 16 hitbox, mask 8 hurtbox)
  overlaps hurtbox Areas (`DamageArea`, layer 8, monitorable). Two inputs feed
  `resolveContact(contact)` (`WeaponScript.ts:294-345`):
  - the `area_entered` signal (scene connection `attack-area.area_entered → script.on_area_entered`), and
  - **level-triggered** polling of `AttackArea.currentContacts` at the start of every step (5.2 step 2) — so a target already inside when a window opens, or standing still inside, is still hit.
- Only `contact.otherKind == 'area'`.
- `receiver = router.receiverNodeIdForArea(otherArea)`; none (unregistered area) → ignore; `receiver == wielder` (the player's own DamageArea) → ignore (`:301-302`).
- `touching` = hitbox ids of the observer shapes in the contact whose name prefix is the active direction; if the contact names no known shape, all windows qualify (`:347-359`).
- For each open window: skip if no activation or `receiver ∈ window.resolvedReceivers`, or if `touching` excludes the window's hitbox. Otherwise **add receiver to `resolvedReceivers` first** (so every receiver is attempted at most once per window, whatever the result), then route (6.3).
- After each route: `if this.damage !== damage: return` — routing can end the swing (e.g. a defeat handler); stop using stale state (`:342-343`).

### 6.2 Godot recommendation

- Keep the converted AttackArea and shapes. Set `monitoring = true` for the
  whole time the weapon is mounted (equivalent: no enabled shape ⇒ no overlaps)
  and only toggle each CollisionShape2D's `disabled` in `_physics_process`
  (avoids "can't change monitoring during flush" errors; use `set_deferred` if
  ever toggled from a signal callback).
- At the start of each `_physics_process` while swinging, iterate
  `attack_area.get_overlapping_areas()` — Phaser's level-triggered
  `currentContacts` — and, after opening windows, queue a deferred
  `PhysicsDirectSpaceState2D.intersect_shape` pass over the enabled shapes so a
  target inside a window is hit in the step it opens (as `weapon.gd` does). Do not also connect
  `area_entered` (the converted connection to `on_area_entered(area)` may stay;
  make the handler call the same resolve function — the per-window set dedupes).
- Shape identity: for the sword only the current direction's single `primary`
  shape is ever enabled, so any overlap belongs to that window. If multi-hitbox
  weapons are ported later, use `area_shape_entered` / shape indices.
- Receiver lookup: a `DamageRouter` registry keyed by the hurtbox `Area2D`
  (instance id), filled by `enemy.gd` / `player.gd` in `_enter_tree`/`_ready`
  and cleared in `_exit_tree`.
- Alternative (one step earlier, deterministic): `PhysicsDirectSpaceState2D.intersect_shape`
  with the open shape, `collide_with_areas = true`, `collide_with_bodies = false`,
  mask 8. Only use if the owner finds the 16 ms latency noticeable.

### 6.3 Building the weapon damage request (`WeaponScript.ts:308-335`)

```
target = { areaNodeId, receiverNodeId,
           x, y = otherArea.global_position,            # F3: DamageArea is at the enemy CENTRE
           attackDirection = activeDirection, depth }
routed = CombatController.transformManagedWeaponDamage(payload.damage * span.damageMultiplier, target)
       = max(0, round(damage * modifier(targetTags) * combo.registerHit()))   CombatController.ts:196-199
request = {
  activationId: window.activationId, sourceNodeId: weapon, attackAreaNodeId: AttackArea,
  targetAreaNodeId: otherArea, weaponId: "basic-sword",
  weaponTags: payload.weaponTags ?? [...], damageTypes: payload.damageTypes ?? ["physical"],
  baseDamage: max(0, routed),
  effects: knockbackStrength > 0 ? [{effectId: "knockback", potency: knockbackStrength * span.knockbackMultiplier}] : [],
  impact: { x: target.x, y: target.y, knockX, knockY = attackVector(direction) }
}
attackVector: right (1,0), left (−1,0), up (0,−1), down (0,1)                 WeaponScript.ts:396-401
```

`modifier(targetTags)`: first tag (in the target's tag order) that has an entry
in `damageModifiers` wins, else 1 (`combat/DamageModifiers.ts`). Ordinary enemies
have tags `["enemy"]` (`UniversalSceneWorldController.ts:2195-2206`) → 1.

**F3:** in Godot the enemy's `DamageArea` is a direct child of the re-anchored
root, so it was shifted by −anchor: `damage_area.global_position` **is** the old
centre. Use the area's position (not the enemy root) for `target.x/y`.

The combo `registerHit()` runs **per routed target**, even if the hit is later
rejected (it is called before routing). See 9.4.

Then `outcome = router.route(request)`; `combat.onOutcome(outcome, target)` (§9).

---

## 7. Damage resolution

### 7.1 Router + resolver (generic; used by both directions)

`DamageRouter.routeStep` (`DamageRouter.ts:74-141`) with one request:
1. normalise/validate the request (finite non-negative damage, non-empty ids, unique tags) → else `rejected('invalid')`.
2. `activations.validate`: the activation must be active, from the same source, and include this attack area → else `rejected('inactive-attack')`.
3. look up the target area → receiver; missing → `rejected('invalid')`.
4. `damageSourceMatches(rule, request)` (`DamageResolver.ts:62-76`): `blockedWeaponTags` hit → no match; `acceptedSources` undefined → match. (Worm and player rules have neither → always match.)
5. `activations.beforeAttempt(activation, receiver, areaSignature)`: receiver already **accepted** in this activation → `rejected('duplicate')`; same area set terminally rejected before → `rejected('duplicate')`.
6. `resolveDamage(receiver, request, rule, simTime)` (`DamageResolver.ts:140-187`):
   ```
   if !sourceMatches → rejected('source-blocked')
   state = receiver.getDamageState()          # {hp, maxHp, dead}
   if state.dead or hp <= 0 → rejected('dead')
   scaled = baseDamage * rule.damageMultiplier * Π damageTypeMultipliers[type] (default 1)
   decision = receiver.canReceiveDamage?(input) → if !accepted → rejected(reason ?? 'state-blocked'); retryable iff reason == 'state-blocked'
   mitigated = receiver.mitigateDamage?(input) ?? scaled
   rounded = max(0, round(mitigated))
   actual = min(state.hp, rounded)
   effects: for each request effect: rule.effectResponses[id] 'immune' → rejectedEffects(immune);
            potency *= multiplier (if any); potency == 0 → rejectedEffects(zero-potency) else appliedEffects
   if actual == 0 and no appliedEffects → rejected('immune')
   accepted { actualDamage: actual, defeated: actual >= state.hp, appliedEffects, rejectedEffects }
   ```
   Rounding: JS `Math.round` rounds .5 **up** (toward +∞); GDScript `round()` rounds half away from zero — identical for non-negative values. Use `int(round(x))` / `roundi(x)` everywhere a "round" appears in this spec.
7. `activations.record`: accepted → receiver marked accepted; non-retryable rejection → signature marked terminal; retryable → nothing.
8. If accepted: `receiver.commitDamage(commit)` then `receiver.publishDamageFeedback(commit)` where `commit = {request, area: rule, result, simulationTime}`.

Godot simplification that keeps behaviour for the trial: one `DamageRouter`
(autoload suggested) with `register_area(area, receiver, rule)`,
`unregister_area(area)`, `receiver_for_area(area)`, `begin_activation(source, attack_area) -> String`,
`end_activation(id)`, and `route(request: Dictionary) -> Dictionary`
implementing steps 1–8 (activation sets: `accepted_receivers`,
`terminal_rejections[receiver] -> Set[area signature]`). Resolver as static
functions in a separate file. Results as Dictionaries:
`{status: "accepted"|"rejected", actual_damage, defeated, applied_effects, rejected_effects, reason, retryable}`.
The router clock is the world simulation time (`UniversalSceneWorldController.ts:389`,
`simulationClock` overrides the caller's time) — use one global sim clock that
stops during hit-stop and modal pause.

### 7.2 Enemy as receiver (`EnemyScript.ts`)

Registration (`_enter_tree`, `:346-359`): register `damageArea` with rule
`{priority 0, damageMultiplier 1}` from the scene `damageRule` (`:501-513`).
Requires `attackArea` reference too.

- `getDamageState` = `{hp, maxHp: maxHealth, dead: defeated}` (`:255-257`). `hp` starts at `maxHealth` (90).
- `canReceiveDamage` → `dead` when defeated, else accepted. No `mitigateDamage` (enemies take raw scaled damage).
- `commitDamage(commit)` (`:265-275`): if defeated return; `hp = max(0, hp - actual)`; store each applied effect potency; emit `health_changed {hp, maxHp}`, `damaged(commit)` (→ `HurtSfx`, min interval 90 ms); `defeated = result.defeated or hp <= 0`; `reactToDamage(commit, defeated)`; if defeated `defeat()`.
- `reactToDamage` (`:282-304`), ordinary enemies:
  ```
  showHitFeedback(commit)                      # always, also on the killing hit
  if defeated: return
  cancelAttack()                               # interrupts a windup: no impact this time (readyAt unchanged)
  immune = rejectedEffects has knockback 'immune'
  potency = Σ applied knockback potencies      # sword: 140
  resist = clamp(attributes.knockbackResist, 0, 1)      # worm: 0.45
  strength = immune ? 0 : (potency + 120) * (1 - resist)            # 120 = ENEMY_HIT_KNOCKBACK_BASE → worm: 143
  dir = normalize(impact.knockX, impact.knockY)         # sword: the cardinal swing vector
  if strength > 0 and |dir| > 0: body.velocity = dir * strength     # px/s, replaces velocity
  stunMs = 320 + min(280, strength * 0.35)              # worm: 370.05 ms
  hitStunUntil = max(hitStunUntil, simTime + stunMs)
  play "knockback-<facing>" (restart)                   # facing NOT changed by the hit
  emit hit_reaction {durationMs: stunMs, strength}      # no listeners in the worm scene
  ```
- Hit-stun in `_physics_process` (`:374-378`): while `simTime < hitStunUntil`:
  `velocity *= 0.94 ^ (delta*60)` and **return** (no AI, no attack). Worm drift ≈ 143/60 · (1−0.94²²)/(1−0.94) ≈ 30 px over 22 steps. Bodies collide with the world/player normally (move with `ArcadeMover.move`).
- `showHitFeedback` (`:307-312`): `hitFlashUntil = simTime + 120`; Visual `setTintFill(0xff6f88)` (solid fill, §11); damage number request `{x, y = body position (centre), amount: actualDamage}` (§12). `updateHitFlash` (`:863-867`, first thing in `_physics_process`) clears the tint when `simTime >= hitFlashUntil`. Enemy sim time stops in hit-stop → the flash lasts 65 ms (frozen) + 120 ms.
- `defeat()` (`:515-533`): `defeated = true`, `hp = 0`, `cancelAttack()`, state `dead`, velocity 0 and **body collision disabled**, attack area off, play `die-<facing>` (restart), emit `health_changed {0, maxHp}`, `defeated {receiverNodeId}` (→ `DeathSfx`, detached so it survives the free), `reward_requested` once (OUT). Every later `_physics_process` keeps velocity 0. The DamageArea stays registered; further hits are rejected `dead` (no feedback).
- Removal (`UniversalSceneWorldController.ts:2050-2063`, after each fixed step): first time `defeated` is seen → notify (rewards, OUT) and `disposeAt = enemySimTime + 800`; free the enemy when its sim time reaches that (`die-*` clips last 0.571 s).
- `_exit_tree`: `cancelAttack()`, unregister the area.

Animation names on the worm (clip = `<action>-<facing>`, facing `side|up|down`,
`side` mirrored by `Visual.flip_h = x < 0` — worm art faces right) (`:826-845`):
`idle-*`, `walk-*` (AI), `attack-*` (attack start, restart), `knockback-*`
(hit, restart; 0.125 s, 1 frame), `die-*` (defeat, restart). Facing rule:
`|x| > |y|` → side (flip if x<0), else `y<0 ? up : down`; vectors shorter than
1e-6 keep the old facing. `playAnimation(name, restart)` only calls `play` when
`restart` or the clip differs.

### 7.3 Enemy melee vs the player (`EnemyScript.ts:724-795`, lifecycle `enemies/enemyCombatLifecycle.ts`)

Trigger (AI, owned by the ENEMY spec; summary only): chase until
`distance(centre, playerCentre) <= attackRange (38)` → state `attack`: velocity 0
and `requestAttack(dirToPlayer)` **every step**; leaves `attack` for `chase` when
distance > 38 × 1.3 = 49.4 (`enemies/EnemyAI.ts:288-314`). `canRunCommonAttack()` is true.

Lifecycle state `{active, readyAt, sequenceId}`:
- `tryBegin(time, cooldown)`: if `active` or `time < readyAt` → no; else `sequenceId += 1`, `active = true`, `readyAt = time + attackCooldownMs (1500)`.
- `finish(seq)`: if active and seq matches → `active = false`.
- `cancel()`: `active = false`, `sequenceId += 1` (readyAt kept → an interrupted worm still waits 1500 ms from its last start).

`beginRuntimeAttack(direction)` (`:724-746`):
```
seq = tryBegin(simTime) else return
attackDirection = normalize(direction)
activeActivationId = activations.begin(enemy, [attackArea])
windup = 400, recovery = 400
updateFacing(attackDirection)
clipMs = length of "attack-<facing>" (side 444 ms, up/down 333 ms)
impactAt = simTime + windup                                   # +400 ms
finishAt = simTime + min(2000, max(windup + recovery, clipMs) + 250)   # +1050 ms for the worm
attackResolved = false
setAttackAreaActive(true)       # monitoring + shape on; nothing listens (inert)
play "attack-<facing>" (restart)
emit attack_started {ranged: false, windupMs: 400}   → WindupSfx
```
Each step while attacking (`:437-444`, after the hit-stun early return):
- `!attackResolved && simTime >= impactAt` → `resolveRuntimeAttack(target, origin)`.
- `simTime >= finishAt` → `finishAttack(seq)` (area off), AI state → `chase` (no flee range).
- AI keeps running during the swing; facing/animation are not updated while attacking (`:488`).

`resolveRuntimeAttack` (`:748-795`), melee branch:
```
attackResolved = true
if target not active (player dead) or not hostile → return
reach = attackAreaReach(target) → undefined for the base EnemyScript
if distance(enemyCentre, playerCentre) > attackRange * 1.35 (= 51.3) → miss (return)   # F4
knock = normalize(playerCentre - enemyCentre)   (zero length → attackDirection)          # F5
route { activationId, source: enemy, attackArea, targetArea: player DamageArea,
        weaponId: "enemy-contact", weaponTags: ["enemy","contact"], damageTypes: ["physical"],
        baseDamage: contactDamage (37),
        effects: knockbackStrength > 0 ? [{knockback, 260}] : [],
        impact: { x, y: enemyCentre, knockX, knockY: knock } }
if accepted with actualDamage > 0 → spawnImpactEffect(origin): only if the scene has an
   `impactEffect` property — the worm swordsman has none → nothing
```
The worm's `AttackArea` circle (r 51.3 = 38 × 1.35) is presentation for the dev
overlay only; the reach is the **distance rule**, not a contact. The worm attack
clip's `hitbox-activated`/`hitbox-deactivated` gameplay events have **no
listener** in Phaser — leave them unconnected.

One attempt per attack: the impact runs once; a rejection (player dodging or
in i-frames) is not retried.

### 7.4 Player as receiver

Registration (`PlayerScript.ts:73-91`): `damageArea` with rule `{priority 0, multiplier 1}`;
groups `player`, `damage-target`. The health logic is a service
(`PlayerHealthController` → `PlayerHealthService`), state in `gameState` (hp, maxHp).

```
getDamageState = {hp, maxHp, dead: deadFlag or hp <= 0}
canReceiveDamage:                                                      PlayerScript.ts:218-221
   if dodging (simTime < dodgeUntil)          → rejected 'state-blocked' (retryable)
   if simTime < iFrameUntil                   → rejected 'state-blocked'  PlayerHealthService.ts:42-46
   else accepted
mitigateDamage (PlayerHealthService.ts:18-22):
   scaled == 0 → 0
   afterDefense = trueDamage ? scaled : max(1, scaled - defense(3))
   return afterDefense * damageTakenMult(1)                            # worm: max(1, 37-3) = 34
commitDamage:
   gameState.damage(actual) → hp -= actual; emits player.damage / hp events; hp <= 0 → player.death → markDead
   if defeated → markDead (onDeath once)
   else if actual > 0 → iFrameUntil = commit.simulationTime + 500
   PlayerScript then emits health_changed {hp, maxHp}, damaged(commit) (→ HurtSfx, min 120 ms), and defeated if dead (→ DeathSfx)
publishDamageFeedback (PlayerHealthController.ts:119-135):
   if actual > 0 → onHit(result)                      # §8
   if defeated → return
   (web effect OUT)
   strength = applied knockback potency (260); if > 0:
      dir = normalize(impact.knockX, impact.knockY); if |dir| > 0 → applyKnockback(dir, 260, 160 ms)
```

`applyKnockback` (`WorldScene.ts:341-349` → `PlayerScript.ts:208-212` → `PlayerNodePorts.ts:60-62`):
`playerKnockbackUntil = max(.., now + 160)`; `movementSuppressedUntil = max(.., simTime + 160)`;
`velocity = dir * 260` (constant, no decay; ≈ 42 px); force-play `knockback`
(1 frame, 0.125 s). While suppressed: movement input ignored, attacks and other
actions not processed, and every other `playAnimation` call is ignored
(`WorldScene.ts:1690-1694`, only `die` and a forced `knockback` pass). After
160 ms normal movement writes velocity again (no input → velocity 0, `idle`).
(Gulp `knockbackImmune` OUT.)

Death (`WorldScene.ts:1920-1945`; flow beyond this OUT): `play('die', forced)`,
stop motion, `gameFeel.play('player-defeated')`, floating `DEFEATED` (red, big)
at centre − (0,40); after 1400 ms the defeat screen/respawn (OUT). While dead:
no input, `canAttack` false, enemies see `target.active = false` (cancel attack, idle).

---

## 8. Player hurt feedback (`WorldScene.onPlayerHit`, `:1892-1918`)

On every accepted hit with `actualHpLost > 0` (called from `publishDamageFeedback`):
1. `gameFeel.play('player-hurt')` → shake 110 ms @ 0.005, hit-stop 70 ms.
2. Squash `hit` on the slime visual: scale (1.22, 0.80) → (1,1) over 190 ms, `Back.Out` (`SquashStretch.ts:24`; skip while an ability animates the body). Multiply into the authored Visual scale (0.28125). *Nice-to-have.*
3. Particles `slime-splash` at the player centre (§13). *Nice-to-have.*
4. Health bar flash (OUT).
5. Floating text `-<actualHpLost>` red `#ff6f88`, big, at `(centre.x, centre.y - 30)` (**F6**: feet − (0, 57.56)).
6. Hit flash: if no flash is running: Visual solid fill `#ff6f88`; after **120 ms of real time** (`scene.time.delayedCall`, keeps running during hit-stop) restore the normal look. A second hit during a running flash does not extend it.

Also `HurtSfx` via the `damaged` signal (7.4).

---

## 9. Attacker-side feedback for the sword (`CombatController.onManagedWeaponOutcome`, `:201-235`)

Called after every routed weapon request, accepted or not:
1. Rejected → return (boss "immune" message OUT). No feel, no effect.
2. Target tags include `resource` → return (OUT).
3. **Crit sting**: if this swing was a crit and `actualDamage > 0` → clear the flag, emit global `weapon.critical-hit` (audio cue `Crit` in `audio.global`, `features/audio/AudioEventBridge.ts:93`). Once per swing.
4. `actualDamage > 0` → `gameFeel.play('hit')` (hit-stop 65 ms, no shake) and particles `hit-spark` at `(target.x, target.y - 12)` (**F7**: enemy centre − 12).
5. `onHitEffectId` set and `actualDamage > 0` → spawn the impact effect (9.1).

### 9.1 Impact effect

Request: `{effectId: "basic-sword-impact", direction: target.attackDirection, x, y: target (enemy centre), depth: target depth + MAX_ATTACHMENT_SLOT + 1}` — i.e. drawn **in front of the struck enemy**.

`spawnEffect` (`UniversalSceneWorldController.ts:1599-1635`): instance
`effect.<id>` with its root at (x, y); `EffectScript._enter_tree` plays `right`,
then the spawner calls `play(direction)` (restarts age).
`EffectScript` (`features/scripts/EffectScript.ts`): `play(variant)` plays the
clip if present, `age = 0`, `playing = true`; each physics step `age += dt`;
`age >= lifetimeMs (1000)` → `finish()`: emit `finished {effectId}`, free the
effect root. Clips: `right/left/up/down` show `Base1` frame 0, alpha 1, scale 0.3
for the whole second (`left` sets `flip_h`). `ImpactSfx` autoplays on spawn
(detached → keep playing after the free; pitch randomness 0.07).

**Godot draw order (F8):** the effect root at the enemy centre would y-sort
*behind* the enemy (its feet are 22 px lower). Spawn a plain Node2D holder at
`(enemy_feet.x, enemy_feet.y + 1)` in the enemy's y-sorted parent and add the
effect instance as its child at local `(target.x - feet.x, target.y - feet.y - 1)`
(= `(0, -23)` for the worm). Do not edit the generated effect scene.

### 9.2 Damage number for the enemy (`showEnemyDamageNumber`, `UniversalSceneWorldController.ts:2039-2045`)

`x = enemy centre.x`, `y = enemy Visual's on-screen top − 8` (falls back to the
centre y); text `-<amount>`; `amount > 15` → yellow `#ffdf8a` big, else white small.
Worm Visual: 64×64, origin 0.5, scale 1 → top = centre − 32 → text at centre − 40
= **feet − 62 (F9)**. In Godot compute from the Visual's global rect
(`visual.get_global_transform() * visual.get_rect()`), not from a constant.

### 9.3 Crit handling summary

Roll at swing start (`randf() < 0.05`); the crit damage applies to every target
of that swing; `critical-hit` feel (shake 80 ms @ 0.006, hit-stop 95 ms) at swing
start even on a miss; the `Crit` sound on the first creature actually damaged.

### 9.4 Combo multiplier (minimal port)

`ComboSystem` (`combat/ComboSystem.ts`), clock = sim time:
```
registerHit():                       # called once per routed target (6.3), before routing
  if now - lastHitAt > 600: combo = 0
  combo = min(combo + 1, 3); lastHitAt = now
  mult = [1.0, 1.15, 1.5][min(combo, 2)]     # indexed by the NEW combo value (see below)
  if combo >= 3: (finisher: text + gameFeel 'combo-finisher') ; combo = 0
  return mult
update() each step: combo > 0 and now - lastHitAt > 600 → combo = 0 (hides the combo text)
```
Careful: `damageMultiplier` reads `DAMAGE_MULT[min(combo, 2)]` **after** the
increment, so the first hit returns `DAMAGE_MULT[1] = 1.15`, the second `[2] = 1.5`,
the third `[2] = 1.5` + finisher (`ComboSystem.ts:36-38, 45-63`). With the sword's
1200 ms cooldown > 600 ms window, every single-target swing is a "first hit":
**every sword hit is ×1.15** → 24 → round(27.6) = **28** (crit: round(42×1.15) = 48).
Hitting two worms in one swing: 28 then round(24×1.5) = 36; a third target in the
same swing: 36 and the finisher (`gameFeel.play('combo-finisher')`: shake 120 ms
@ 0.008, hit-stop 100 ms; text OUT). Port these exact semantics (it is the live
Phaser damage); flag the off-by-one to the owner as a probable Phaser bug.

---

## 10. Game feel: hit-stop and shake (`features/feel/GameFeel.ts`)

| event | shake ms | intensity | hit-stop ms | fired by |
|---|---|---|---|---|
| `hit` | 0 | 0 | 65 | sword lands on a creature (actual > 0), per target |
| `critical-hit` | 80 | 0.006 | 95 | crit swing start |
| `combo-finisher` | 120 | 0.008 | 100 | 3rd combo hit |
| `player-hurt` | 110 | 0.005 | 70 | player loses HP |
| `player-defeated` | 400 | 0.012 | 150 | player death |

`play(event)`: `shake(ms, intensity)` then `hitStop(ms)`.
- `shake`: skipped if no stage, `ms <= 0`, `intensity <= 0`, or `shakeScale <= 0`; else camera shake with `intensity * shakeScale`. `shakeScale` = setting `screenShake` (0..1, default 1) or 0 under Reduce motion. Phaser `camera.shake` **does not replace a running shake** (force = false). Phaser offset each frame: `x = rand(−1,1) · intensity · viewportWidth · zoom`, `y = rand(−1,1) · intensity · viewportHeight · zoom`, constant amplitude, reset at the end (`node_modules/phaser/src/cameras/2d/effects/Shake.js:236-246`). Godot: a shake script on the Camera2D setting `offset` per frame, in world units `rand · intensity · viewport · zoom`, so the on-screen shift is `· zoom²` as in Phaser (`world_camera.gd` `_advance_shake`).
- `hitStop(ms)`: skipped under Reduce motion; `frozenUntil = max(frozenUntil, realNow + ms)` — overlapping stops do not add. Clock: **real time** (`scene.time.now`).
- While frozen (`WorldScene.ts:792-799, 735-748`): the world advances with delta 0 — no fixed steps (no sim time, no scripts, no physics), physics paused, tweens time-scale 0, sprite animations paused. Rendering, camera shake, particles, the floating text (real-time clock) and the player's real-time flash timer keep going.

Godot implementation suggestion (`GameFeel` autoload, `process_mode = ALWAYS`):
`hit_stop(ms)` sets `get_tree().paused = true` and remembers `frozen_until_ms`
(`Time.get_ticks_msec()`); `_process` unpauses when the time passes (only if it
was the one that paused — coordinate with the integrator's menu pause, e.g. a
pause-reason set). Give `PROCESS_MODE_ALWAYS` to: the camera shake, hit
particles, floating texts, the player's flash timer, and the player input reader
(so presses during a stop are buffered; the buffer uses sim time, which is frozen).
AnimationPlayers in the world stay pausable (Phaser freezes them).
Do not use `Engine.time_scale = 0`: it would also freeze particles/shake.

---

## 11. Hit flash (`setTintFill`)

Phaser `setTintFill(0xff6f88)` paints every opaque pixel solid `#ff6f88`
(alpha kept); `clearTint()` restores. Godot: a shared `canvas_item` shader
(`res://game/...hit_flash.gdshader`) with `uniform vec4 flash_color` and
`uniform float flash_amount`; `COLOR.rgb = mix(tex.rgb * COLOR.rgb, flash_color.rgb, flash_amount)`,
alpha untouched. Apply a per-instance `ShaderMaterial` (or `instance uniform`)
to the character's `Visual` when spawned. Works in the Compatibility renderer.
`modulate`/`self_modulate` cannot produce a fill (multiplicative).

| who | duration clock | duration | re-trigger |
|---|---|---|---|
| enemy | enemy sim time (stops in hit-stop) | 120 ms | each hit restarts the 120 ms |
| player | real time | 120 ms | ignored while a flash is running |

---

## 12. Floating damage numbers (`features/ui/FloatingTextSurfacePort.ts`, active path)

`spawn(x, y, text, color, big, durationMs?)` in **world** coordinates; drawn as a
screen-space UI element projected from the world point every frame.
- Pool 24; reuse the first expired entry; pool full → drop the request.
- Duration: big 900 ms, small 700 ms; clock = real time.
- Progress `p = clamp(elapsed / duration, 0, 1)` (linear): position = `(x, y − rise·p)` with rise 48 (big) / 34 (small); opacity `1 − p`; scale `1.1 + 0.2p` (big) / `0.9 + 0.1p` (small); font size 22 / 15 px.
- Colours: white `#ffffff`, yellow `#ffdf8a`, red `#ff6f88` (also orange, green, cyan, blue exist).
- Styling (font, outline) comes from the UI scene `content/scenes/authored/ui/floating-text.scene.json` (UI spec); the fallback pool in `ui/FloatingText.ts` uses `Trebuchet MS`, stroke `#0b1020` 4 px.

Godot: a `Label` (with outline) under a world-space `Node2D` with high `z_index`,
or a CanvasLayer label positioned via `get_viewport().get_canvas_transform()`;
either is fine for the trial.

---

## 13. Particles (`features/feel/ParticlePresets.ts`)

| preset | count | lifespan | speed | angle | gravity | scale | alpha | blend | texture | layer |
|---|---|---|---|---|---|---|---|---|---|---|
| `hit-spark` | 7 | 220 ms | 90–220 | all | 0 | 0.9→0 | 1→0 | additive | `fx-spark` 16×16: circle r7 `#fff2b8` α0.55 + core r3.5 white | above everything |
| `slime-splash` | 9 | 420 ms | 50–140 | 200°–340° (upward fan, y down) | +420 | 0.8→0.3 | 1→0 | normal | `fx-goo-drop` 16×16: circle r6 `#2f8f3a` at (8,9), r5 `#7be08a` at (8,8), highlight r1.6 white α0.8 at (6,6) | sorted at y+2 |

Textures are procedural (`infrastructure/assets/ProceduralAssetScene.ts:87-101`);
draw them once into an `ImageTexture` at startup or with `_draw`. Godot:
pooled `CPUParticles2D` (`one_shot`, `explosiveness = 1`, `emitting` restart),
`process_mode = ALWAYS` (they run through hit-stop).

---

## 14. Feet-origin dependencies (every place Phaser assumed the centre)

| # | Where | Phaser | Godot |
|---|---|---|---|
| F1 | weapon mount | weapon root at player body (0,0) = centre | weapon child at `-depth_anchor` = (0,−27.56) |
| F2 | pointer aim origin | `(centre.x, centre.y − 28)` | `feet − (0, 55.56)` |
| F3 | weapon target point (impact effect, spark, impact.x/y) | `DamageArea` global pos = enemy centre | `damage_area.global_position` (already the centre after re-anchoring) |
| F4 | enemy melee reach (≤ 51.3), AI distances (38, 49.4, 220) | centre ↔ centre | `centre = global_position − depth_anchor*scale` for both bodies (worm 22, player 27.56); using feet would shift y by 5.56 px |
| F5 | knockback direction on the player | `normalize(playerCentre − enemyCentre)` | same, with centres |
| F6 | player damage number / `DEFEATED` / splash | centre − 30 / centre − 40 / centre | feet − 57.56 / feet − 67.56 / feet − 27.56 |
| F7 | `hit-spark` | enemy centre − 12 | `damage_area.global_position − (0,12)` |
| F8 | impact effect draw order | explicit depth in front of target | holder at enemy feet + 1, effect offset up (9.1) |
| F9 | enemy damage number | (centre.x, visualTop − 8) | from the Visual's global rect |
| F10 | enemy `impactEffect` distance (not used by the worm) | `centre + attackDirection·distance` | centre-based |
| F11 | hurtboxes | rect centred at centre+(0,14.56) player / +(0,9) worm | converted; both end up at feet+(0,−13) — no script work |
| F12 | enemy spawn requests, loot/coin text (OUT) | centre | `P + depth_anchor` when spawning at an old position |

---

## 15. Expected trial numbers (acceptance checks)

| check | value |
|---|---|
| sword hit on a worm (no crit, single target) | 28 (24 × 1.15 combo, see 9.4); crit 48 |
| worm hits to kill (90 HP) | 4 (28, 56, 84, then 6) |
| worm knockback from a sword hit | 143 px/s along the swing direction, stun 370 ms, ≈ 30 px drift, `knockback-<facing>` |
| sword cadence | one swing per 1200 ms; swing locks movement 417 / 333 / 292 ms (side / up / down) |
| hit-stop on a sword hit | 65 ms, no shake |
| worm attack | windup 400 ms (WindupSfx at start), impact if centre distance ≤ 51.3, attack ends +1050 ms, next attack ≥ 1500 ms after the previous start |
| damage to the player | 34 (37 − 3); i-frames 500 ms; knockback 260 px/s for 160 ms (≈ 42 px); hurt feel shake 110 ms + hit-stop 70 ms |
| player deaths | 100 HP → 3 worm hits (34, 34, 32) |
| sword hit interrupts the worm | hit during the 400 ms windup cancels that attack (no damage) |

---

## 16. Edge cases

- Weapon never hits its wielder (receiver == player's receiver is skipped).
- A receiver is attempted once per hit window; with one span per direction → once per swing, even if it stays inside.
- Targets already overlapping when a window opens are hit (level-triggered).
- The swing continues if the player is knocked back mid-swing; the action lock holds until the swing ends; `idle` at the end is suppressed if knockback still has priority.
- Death mid-swing: swing finishes normally (weapon is not cancelled); no new swing (`canAttack` false).
- Hitting a defeated enemy (during its 800 ms death) → rejected `dead`, no feel/effect/number.
- Killing hit: flash + number shown, no knockback/stun; `die-<facing>`, collision off.
- Accepted with 0 damage (only possible with a ×0 modifier and knockback): enemy still flashes, shows `-0`, plays HurtSfx and is knocked back; no hit-stop/effect (CombatController needs `actualDamage > 0`). Not reachable with sword vs worm.
- Player dodging or in i-frames: worm impact rejected (`state-blocked`), not retried.
- Player dead: worms cancel attacks and idle (`target.active` false); impact checks `target.active` again.
- Enemy impact at distance > 51.3 → miss even if the AI was in attack state.
- Multiple worms: each resolves independently; i-frames (500 ms) block hits from others.
- Multiple targets in one swing: hit-stop does not stack (max), combo escalates per target (9.4), crit sting once.
- Hit-stop does not freeze real-time timers: player flash, floating text, particles, camera shake.
- Router `routeStep` dedupe: if two requests in the same activation hit the same receiver, only one is accepted (`duplicate`).
- Modal pause (OUT for trial) also freezes the sim; hit-stop must not unpause a modal pause.

---

## 17. Suggested GDScript layout (for the architect; names are proposals)

| file | role |
|---|---|
| `res://game/scripts/weapon.gd` (`game.weapon`) | WeaponScript port: exports `weapon_id, category, attack_area: Area2D, animation: AnimationPlayer, base_damage, cooldown_ms, knock_strength, damage_modifiers: Array, harvest_capabilities: Dictionary, scaling: Dictionary, on_hit_effect_id, attack_plans: Dictionary` (inner keys camelCase: `animationId, durationMs, framesPerSecond, hitboxSpans[{hitboxId, from, through, damageMultiplier, knockbackMultiplier}]`); signals `attack_started(payload)`, `attack_finished(payload)`; handler `on_area_entered(area)`; API `can_begin_attack()`, `try_begin_attack(direction: String, payload: Dictionary) -> bool`, `cancel_attack()` |
| `res://game/scripts/effect.gd` (`game.effect`) | EffectScript port: exports `effect_id, animation, lifetime_ms`; signal `finished(payload)`; `play(variant)`, `finish()` frees the scene root |
| `res://game/scripts/enemy.gd` (`game.enemy`) | owned by the ENEMY area; must implement the receiver API below plus §7.2/7.3 |
| `res://game/scripts/player.gd` (`game.player`) | owned by the PLAYER area; receiver API + dodge block + knockback (§7.4) |
| `res://game/combat/damage_router.gd` (autoload `DamageRouter`) | registry + activations + route (§7.1) |
| `res://game/combat/damage_resolver.gd` | static `resolve(receiver, request, rule, sim_time) -> Dictionary`, `source_matches(rule, request)` |
| `res://game/combat/player_combat.gd` | CombatController port: swing gate, payload (§4.2), `transform_damage`, `on_outcome` (§9), combo (§9.4), start/finish hooks (lock, player clips) |
| `res://game/feel/game_feel.gd` (autoload `GameFeel`) | presets, `play(event)`, shake, hit-stop (§10) |
| `res://game/feel/hit_flash.gdshader` | §11 |
| `res://game/feel/particle_fx.gd` | `play(event, pos)` pooled CPUParticles2D (§13) |
| `res://game/ui/floating_text.gd` | `spawn(pos, text, color, big)` (§12) |

Receiver API (duck-typed, called by the router):
`get_damage_state() -> {hp, max_hp, dead}`, optional `can_receive_damage(input) -> {accepted, reason}`,
optional `mitigate_damage(input) -> float`, `commit_damage(commit)`, optional
`publish_damage_feedback(commit)`. `input = {scaled_damage, request, area, state, simulation_time}`.

Combat port the weapon calls (Phaser `PLAYER_WEAPON_COMBAT_SERVICE`):
`on_attack_started(weapon_id, direction)`, `on_attack_finished(weapon_id, direction)`,
`transform_damage(damage, target) -> int`, `on_outcome(outcome, target)`,
`wielder_receiver() -> Node`.

Shared simulation clock: Phaser keeps per-script `simulationTimeMs` accumulators
(all fed by the same fixed step) plus the world clock used by the router. One
global sim clock in ms, advanced in `_physics_process` and frozen by hit-stop and
pause, is equivalent.

Cross-area needs:
- PLAYER: `player.gd` must expose facing (unit vector), `consume_action_press`, dodge flag, `apply_knockback(dir, strength, ms)`, movement suppression, `play_animation(name, force)` with knockback priority, the Visual for flash/squash, `depth_anchor`.
- ENEMY: `enemy.gd` must use centres for all distances (F4), call the router for its melee, and expose the Visual for flash and number placement.
- CONVERTER: confirm `weapon.gd` exports receive `attackPlans` as a Dictionary with camelCase inner keys; optionally carry `characterActionId` (`attack-1`) into the weapon scene.
- INTEGRATOR: register `DamageRouter` and `GameFeel` autoloads; give hit-stop a pause reason distinct from menus.
