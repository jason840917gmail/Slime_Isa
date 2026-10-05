# Boss spec — Fatty One Eye and the level-1 boss camp

Source of truth: the Phaser code on `feat/godot-migration` (read 2026-10-05, commit b75e2b2).
Everything below is read from code; `file:line` references are to `src/game/...`. "Position" or
"centre" is the old Phaser body position (the CharacterBody2D node position); Godot roots sit at
the feet (conventions, *Feet origin*): `position = feet - depth_anchor * scale`. Fatty's
`depth_anchor` is `(0, 42)`, so its Phaser position is 42 px above its feet (the sprite's origin
point, not the middle of its body).

Godot targets: script `game.fatty` → `res://game/scripts/fatty.gd` (node `FattyScript`, a child
`Node` of the `FattyOneEye` CharacterBody2D; it extends `game/scripts/enemy.gd` as `FattyScript`
extends `EnemyScript` in Phaser); script `game.boss-camp` → `res://game/scripts/boss_camp.gd`
(node `BossCampScript` in the encounter `encounter.level-1-fatty-camp`); helpers in
`res://game/bosses/`; the bar in `res://game/ui/boss_health_bar.gd`. Read with the
[enemy spec](./enemy.md): Fatty runs the whole base enemy step first, and only the differences are
written here.

---

## 0. Scope

### IN
- The camp: activation, spawning the boss, arena perimeter, respawn timer and the "seen outside"
  rule, the reset when the player dies, the guard flag of the chest, removal on exit.
- Fatty: the phase machine (chase, return-to-center, contact-hop, small-hop, airborne, landing,
  recovery, dead), the contact hop on top of the base melee, the leap with its two telegraphs,
  landing damage and knockback, the ground-crack effect, the landing camera shake, damage
  immunity while hopping and airborne, no stun and no shove from hits, spear-only damage, the arena
  leash and full heal after `arenaRecoveryMs` outside, death.
- The boss health bar (name, bar, "Boss health hp / max"), shown while a boss lives.
- Defeat: `boss-burst` particles, "Fatty One Eye defeated!", the `Victory` cue, the
  `boss-defeated` feel preset, the camp's `boss_defeated` signal (the hook the quest system needs).
- SFX wiring already in the scene JSON (hurt, hop, leap, fall, land, recover, death, roar).

### OUT (exists in Phaser; later phases)
| Feature | Where | Notes |
|---|---|---|
| Writing the camp (`respawnReadyAtEpochMs`) and `defeatedBossIds` to disk | `features/progression/WorldProgress.ts:362-371, 519-533`, `infrastructure/persistence/SaveSchema.ts` | Godot keeps both in RunState (`map_record(map_id)["boss_camps"][campId] = {"respawn_ready_at_epoch_ms"}`, `world["defeated_boss_ids"]`), so they survive world travel; saving RunState is Phase 4 |
| Quests reacting to the defeat (`defeat-boss` objective of `chapter-one` "defeat-fatty") | `quests/QuestEventBridge.ts:18, 62`, `quests/matchers/ObjectiveMatchers.ts:84-85, 123`, `quests/QuestService.ts:399-401` | Godot emits the camp's `boss_defeated({campId, bossId})` where Phaser emits `gameEvents 'boss.defeated' {bossId}`; nothing listens yet |
| Boss music (`boss.engaged` / `boss.disengaged` → `MusicDirector.setBossFight`) | `features/world/UniversalSceneWorldController.ts:548-557, 765-771` | Godot emits the camp's `boss_engaged` / `boss_disengaged`; `MusicDirector` listens to them ([audio.md](./audio.md)) |
| The guarded chest (`isChestGuarded`, "Chest locked by Fatty One Eye", "Fatty One Eye is guarding this chest!") | `BossCampScript.ts:143-146`, `UniversalSceneWorldController.ts:899-915` | Chests are not ported; `is_chest_guarded()` and `guard_changed` are |
| Quest waypoint to the camp (`bossCampPosition`) | `UniversalSceneWorldController.ts:1145`, `features/quests/QuestWaypoint.ts` | |
| Occlusion silhouette of the boss | `UniversalSceneWorldController.ts:2008` | Dropped by plan |
| Dev overlays (`debugAttackAreas`, hurtbox overlay, `bossBattleAreas`) | `EnemyScript.ts:646-660`, `UniversalSceneWorldController.ts:849-881` | Debug only |
| `content/bosses/fatty-one-eye.json` / `BossCatalog.ts` | | Only map validation and the Studio preview read it; every runtime number comes from the scene JSON (§1). Its `landingRadius`, `crackFadeMs`, `contactHop.clipId/hitboxId`, `eye`, `body` are unused at run time |
| `ui/BossHealthBar.ts` | | Dead code (no importer); the bar is `ui.boss-health-bar` + `BossHealthSurfacePort` |
| Settings that scale the feel (screen-shake slider, reduce motion) | `features/feel/GameFeel.ts:82-99` | As for every feel event in the port |

---

## 1. Data: where every number comes from

### 1.1 Fatty script properties (`characters/fatty-one-eye.scene.json`, node `script`, `scriptId: game.fatty`)
Inherited `game.enemy` exports (enemy spec 1.1) plus the Fatty ones. Fallbacks are the runtime
ones (`numberProperty(key, fallback)` in `FattyScript.ts`; every Fatty duration is used as
`max(1, value)`).
| JSON | Godot export | Value | Runtime fallback |
|---|---|---|---|
| `body` / `visual` / `animation` | same | `FattyOneEye` / `Visual` / `Animation` | |
| `damageArea` | `damage_area: Area2D` | `Eye` (the hurtbox is the eye) | |
| `attackArea` | `attack_area: Area2D` | `ContactAttack` | |
| `contactAttack` | `contact_attack: Area2D` | `ContactAttack` (same node) | |
| `landingZone` | `landing_zone: Area2D` | `LandingZone` | |
| `displayName` | `display_name` | `"Fatty One Eye"` | `""` |
| `faction` / `rank` | | `"hostile"` / `"boss"` | |
| `maxHealth` | `max_health` | 140 | 1 |
| `targetingRadius` | `targeting_radius` | 933 (aggro; chase gives up beyond 1399.5) | 0 |
| `attackRange` | `attack_range` | 64 (unused: the contact area decides reach, §3.3) | 0 |
| `movementSpeed` | `movement_speed` | 42 (chase and walk home) | 0 |
| `attackCooldownMs` | `attack_cooldown_ms` | 1000 | 0 |
| `attributes` | `attributes` | `attackWindupMs 250, attackRecoveryMs 50, contactDamage 18, knockbackStrength 180, effectImmunities ["knockback"], allowedWeaponIds [...]` (the last two are informational: the damage rule enforces both) | |
| `damageRule` | `damage_rule` | `{priority 100, damageMultiplier 1, acceptedSources [{allWeaponTags ["spear"]}], effectResponses {knockback {mode "immune"}}}` | |
| `rewards` | `rewards` | `{}` | |
| `arenaRecoveryMs` | `arena_recovery_ms` | 60000 | 0 |
| `contactHopCooldownMs` | `contact_hop_cooldown_ms` | 1000 | 1000 |
| `contactHopDurationMs` | `contact_hop_duration_ms` | 300 | 300 |
| `leapCadenceMs` | `leap_cadence_ms` | 5000 | 5000 |
| `smallHopCount` | `small_hop_count` | 3 | 3 |
| `smallHopDurationMs` | `small_hop_duration_ms` | 260 | 260 |
| `betweenHopsMs` | `between_hops_ms` | 100 | 100 |
| `airTimeMs` | `air_time_ms` | 1000 | 1000 |
| `recoveryMs` | `recovery_ms` | 700 | 700 |
| `landingDamage` | `landing_damage` | 32 | 32 |
| `landingKnockbackStrength` | `landing_knockback_strength` | 280 | 280 |
| `landingEffectId` | `landing_effect_id` | `"boss-ground-crack"` | `""` (none) |
| `landingShakeMs` | `landing_shake_ms` | 100 | 100 |
| `landingShakeIntensity` | `landing_shake_intensity` | 0.003 | 0.003 |

### 1.2 Camp script properties (`encounters/level-1-fatty-camp.scene.json`, `scriptId: game.boss-camp`)
| JSON | Godot export | Value | Runtime fallback (`BossCampScript.ts:55-61`) |
|---|---|---|---|
| `mapId` / `campId` / `bossId` | `map_id` / `camp_id` / `boss_id` | `level-1` / `level-1-fatty-one-eye-camp` / `fatty-one-eye` | `""` |
| `bossScene` | `boss_scene: String` (scene id) | `character.fatty-one-eye` | `""` |
| `activationArea` / `arenaArea` | `Area2D` | circles r 440 / r 420 at the camp origin | |
| `activeBosses` | `active_bosses: Node2D` | `ActiveBosses` | required (Phaser throws when missing) |
| `guardedChest` | `guarded_chest: Node` | `GuardedChest` (not read at run time) | |
| `guardedChestInstanceId` | `guarded_chest_instance_id` | `level-1-fatty-guarded-chest` | |
| `respawnMs` | `respawn_ms` | 180000 | 0 |
| `spawn` | `spawn: Vector2` | (0, 0) (offset from the camp origin) | (0, 0) |

The encounter is instanced in `worlds/level-1.scene.json` as `level-1-fatty-one-eye-camp` at
**(2528, 1472)**, so activation = circle (2528, 1472, r 440), arena = circle (2528, 1472, r 420),
boss spawn = (2528, 1472) (Fatty's feet at (2528, 1514)). The chest sits at (2528, 1077).

### 1.3 Code literals
| Name | Value | Source |
|---|---|---|
| landing phase length | 360 ms (= the `landing` clip, 0.36 s) | `FattyScript.ts:107` |
| boss target tags | `["enemy", "boss"]` | `UniversalSceneWorldController.ts:2199-2201` (`managedTargetTags`) |
| defeat burst | `boss-burst` at position − (0, 30) | `UniversalSceneWorldController.ts:2025` |
| defeat text | `"<name> defeated!"`, yellow, big, at position − (0, 84) | `:2027-2033` |
| boss damage number | `-N` at position − (0, 8) (not the visual top: bosses are not in `ordinaryEnemies`) | `:2039-2045` |
| telegraph colours | fill `#ff7a3d` α 0.15; stroke 3 px `#ffc85a` α 0.85; shadow ellipse 96 × 34 `#07120e` α 0.38 | `features/effects/AttackTelegraphs.ts:11-16, 34` |
| `boss-landing` feel | shake from the scene (100 ms / 0.003), hit-stop 0 | `UniversalSceneWorldController.ts:586`, `features/feel/GameFeel.ts:44` |
| `boss-defeated` feel | shake 450 ms / 0.012, hit-stop 180 ms | `GameFeel.ts:46`, `UniversalSceneWorldController.ts:599` |
| `boss-burst` particles | `fx-sparkle`, 36, over, 900 ms, speed 120–320, scale 1.6→0, alpha 1→0, rotate 0–360, tint one of `#ffe89a #86f0c3 #ffffff` | `features/feel/ParticlePresets.ts:35-38`; texture `infrastructure/assets/ProceduralAssetScene.ts:103-111` |

### 1.4 Derived numbers
- Contact hop: impact at +250 ms → the player takes max(1, 18 − 3) = **15**, knockback 180;
  the hop phase ends at +300 ms, the attack sequence at +min(2000, max(250 + 50, 0) + 250) =
  **+550 ms** (Fatty has no `attack-*` clip, so the clip length is 0); next hop ≥ 1000 ms later.
- Leap: first one 5000 ms after spawn; small hops 3 × (260 + 100) = **1080 ms**; flight 1000 ms;
  landing 360 ms; recovery 700 ms; the next leap 5000 ms after recovery ends (a full cycle is at
  least 8140 ms). Landing hit: max(1, 32 − 3) = **29**, knockback 280.
- Spear only: the basic sword is rejected `source-blocked` (no flash, number or sound). A basic
  spear hit does 30 (combo tiers ×1, ×1.15, ×1.5; crit 5 %), so about five hits.

---

## 2. Scene structure

### 2.1 `characters/fatty-one-eye.scene.json`
Root `FattyOneEye` CharacterBody2D: layer 4 (enemy), mask 1027 (world + player + water),
`depthAnchor (0, 42)`, `collideWorldBounds`. Player and Fatty block each other.
| Node | Type | Phaser props | Godot after the feet re-anchor |
|---|---|---|---|
| BodyShape | CollisionShape2D | ellipse 44 × 42 radii at (1, −29) | rectangle 88 × 84 at (1, −71) (Arcade bodies are boxes) |
| Visual | Sprite2D | `boss.fatty-one-eye` 108 × 118, 37 frames, origin (0.5, 0.7627), scale 1.5 | (0, −42) |
| Eye | Area2D | layer 8 (hurtbox), mask 16 | (0, −42) |
| EyeShape | CollisionShape2D | circle r 23.5 at (−2, −33), moved by every clip | unchanged (child of Eye) |
| ContactAttack | Area2D | layer 16, mask 8, monitoring/monitorable off | (0, −42) |
| ContactShape | CollisionShape2D | ellipse 83.5 × 52 radii at (1, −25), disabled | 32-point polygon |
| LandingZone | Area2D | layer 16, mask 8, monitoring/monitorable off | (0, −42) |
| LandingShape | CollisionShape2D | ellipse 110.5 × 60.5 radii at (0, 0) | 32-point polygon |
| Animation | AnimationPlayer | autoplay `chase`, physics domain | |
| FattyScript | ScriptNode `game.fatty` | §1.1 | |
| HurtSfx | AudioStreamPlayer2D | fatty-hurt 1–2, pitch ±0.06, min interval 150 ms | ← `damaged` |
| HopSfx / LeapSfx / FallSfx / LandSfx / RecoverSfx / DeathSfx | AudioStreamPlayer2D | filters `phase=contact-hop\|small-hop` / `airborne` / `airborne` (vol 0.7) / `landing` (range 1400) / `recovery` (vol 0.7) / `dead` (detached, range 1400) | ← `phase_changed` |

There is no `defeated` connection: the death sound comes from `phase_changed {phase: dead}`.
Disabled shapes still count as reach (`EnemyScript.ts:621-632`): the contact and landing areas are
geometry only; nothing uses their physics overlaps.

### 2.2 Clips (frames of the 6 × 7 sheet)
| Clip | fps | length | loop | frames | also animates |
|---|---|---|---|---|---|
| chase | 7.69 | 0.78 s | yes | 6–11 | Eye (per frame), LandingShape (0, 0), ContactShape (1, −25) |
| small-hop | 15.38 | 0.26 s | yes | 12–15 | Eye |
| contact-hop | 20 | 0.30 s | no | 12, 13, 14 (at 3), 15 (at 5) | Eye; event `hitbox-activated {hitboxId: contact-hop-impact}` at 0.25 s |
| airborne | 6 | 1.0 s | no | 18–23 | Eye |
| landing | 11.1 | 0.36 s | no | 24–27 | Eye |
| recovery | 5.56 | 0.36 s | yes | 28–29 | Eye |
| death | 9.09 | 0.66 s | no | 30–35 | — |

The `contact-hop` event is not consumed by anything (as the worm's events, enemy spec 2.1): the
impact is the base attack's 250 ms windup timer. The base script's directional clips
(`idle-*`, `walk-*`, `attack-*`, `knockback-*`, `die-*`) do not exist here, so its `play_facing`
calls do nothing; Fatty plays its own clips. `mirrorsSideFacing()` is false: the sprite never flips.

### 2.3 `encounters/level-1-fatty-camp.scene.json`
Root `Level1FattyCamp` Node2D; `ActivationArea` / `ArenaArea` (Area2D layer 512, mask 4,
circle shapes at (0, 0)); `ActiveBosses` Node2D; `BossCampScript`; `GuardedChest`
(`object.chest-wooden` at (0, −395), contents `green-key`); `RoarSfx` (fatty-roar, range 1600)
← `boss_spawn_requested`. Phaser never reads the areas' physics overlaps: containment is computed
from their shapes (`BossCampScript.ts:79-104`).

### 2.4 `effects/boss-ground-crack.scene.json`
Root Node2D, `depthAnchor (0, 0)`; `Crack` Sprite2D (4 frames 96 × 96, scale 2, ground-decals
band = `z_index −1`); clip `right` 0.65 s: frames 0 / 1 (0.15 s) / 2 (0.3 s) / 3 (0.5 s), alpha
1 → 0; `EffectScript` (`game.effect`, `lifetimeMs 650`); `ImpactSfx` stone-crumble, autoplay,
detached. Spawned with direction `right` at a point (`UniversalSceneWorldController.ts:579-581`,
`spawnEffect :1599`).

### 2.5 `ui/boss-health-bar.scene.json` and its styling
Container anchored bottom-centre, offsets (−274, −264) to (274, −192) (548 × 72), z 20; label
`BossName` (top, 28 px tall, danger tone, 16 px bold); ProgressBar `Health` from y 34 to the
bottom, label "Boss health", `showValue` → text `"Boss health <ceil(hp)> / <ceil(max)>"`
(`infrastructure/phaser-nodes/ui/HtmlControlPresentationAdapter.ts:268`). CSS
(`src/styles.css:3396-3410`): border `#8b2f2f`, radius 12, padding 0 12 px, background gradient
`#261727` → `#101a31`, bar 16 px tall with radius 5. Bindings: `name`, `hp`, `maxHp`, `visible`.
In the live Phaser DOM a more specific `.scene-control--container.game-ui` rule and the inline
layout override that rule: the card shows the standard window border, no padding, and the bar
stretches 38 px to the card's bottom. The card sits 192-264 px above the screen bottom, above the
weapon hotbar (116-172 px) and the ability bar (12-84 px). Godot (`game/ui/boss_health_bar.gd`,
2026-10-05) follows the rule's intent: red border, 12 px padding, a 16 px bar, so the card is
548 × 58 with its bottom edge at Phaser's 192 px; on views shorter than 720 px it stays at least
96 px below the view centre (the player), and it is never wider than the screen − 24 px.

---

## 3. Fatty per physics step

### 3.1 State (`FattyScript.ts:10-15`)
```
phase := "chase"; phase_started_at := 0
next_contact_hop_at := 0
next_leap_at := now + max(1, leap_cadence_ms)     # _enter_tree, FattyScript.ts:45-48
leap_from := (0, 0); leap_target := (0, 0)
```
`transition_to(phase, now)` (`:222-226`): set phase and `phase_started_at = now`, then emit
`phase_changed({phase, time: now})`. `elapsed(now) = max(0, now − phase_started_at)`.
`set_body_collision(on)` (`:228-231`): Phaser `collisionEnabled` (`infrastructure/phaser-nodes/
PhysicsBody2DNode.ts:80-84`: the Arcade body is disabled, so it neither blocks nor is blocked).
Godot: collision layer and mask 0 when off, the authored ones (4 / 1027) when on.

### 3.2 Step order (`FattyScript.ts:50-115`)
The whole base enemy step runs first (enemy spec 4.2, with the boss differences in §3.3), then:
```
if defeated or phase == "dead": return
if phase == "chase":
    if returning_to_arena: begin_return(now); return
    if runtime_state == "attack":                     # a melee sequence runs, or the AI is in its
        if request_contact_hop(now): play("contact-hop")   # attack state (in reach, cooling down)
        return
    if now >= next_leap_at:
        cancel_attack(); begin_leap_telegraph(now); velocity = 0
    return
if phase == "return-to-center":
    if not returning_to_arena: resume_chase(now)
    return
velocity = 0                                          # every other phase holds still
contact-hop: elapsed >= max(1, contact_hop_duration_ms) (300) ->
    clear_telegraph(); spawn landing_effect_id at the position; resume_chase(now)
small-hop:   elapsed >= max(1, small_hop_duration_ms + between_hops_ms) * max(1, small_hop_count)
             (1080) -> begin_airborne(now)
airborne:    p = min(1, elapsed / max(1, air_time_ms)); position = leap_from + (leap_target - leap_from) * p
             if p >= 1: land(now)
landing:     elapsed >= 360 -> begin_recovery(now)
recovery:    elapsed >= max(1, recovery_ms) (700) -> next_leap_at = now + max(1, leap_cadence_ms); resume_chase(now)
```
Then the body moves with its velocity (Arcade; Godot `ArcadeMover.move`). While collision is off
the airborne teleport is not blocked by walls or the player.

Transitions (`:117-192`):
| Function | Guard | Effect |
|---|---|---|
| `request_contact_hop(now)` | not defeated, phase chase, `now >= next_contact_hop_at`, and the boss **position** inside the arena (when it has one) | phase contact-hop; `next_contact_hop_at = now + max(1, contact_hop_cooldown_ms)`; collision off; telegraph = the ContactAttack shapes where they are, shadow at the position |
| `begin_leap_telegraph(now)` | not defeated, phase chase | phase small-hop; play `small-hop` |
| `begin_airborne(now)` | phase small-hop | `leap_from` = position; target = the player centre (even a dead player's; the boss position when there is no player); `leap_target = clamp_to_arena(target)`; telegraph = the LandingZone shapes moved by `leap_target − leap_from`, shadow at `leap_target`; collision off; phase airborne; play `airborne` |
| `land(now)` | phase airborne | collision on; phase landing; play `landing`; clear the telegraph; if the player is active and its hurtbox overlaps the LandingZone shapes (now at the landing point): `route_immediate_attack(landing_damage, landing_knockback_strength, no impact effect)`; spawn `landing_effect_id` at the position; shake `landing_shake_ms` / `landing_shake_intensity` |
| `begin_recovery(now)` | phase landing | phase recovery; play `recovery` |
| `resume_chase(now)` | phase contact-hop, recovery or return-to-center | collision on; phase chase; play `chase` |
| `begin_return(now)` | not defeated, phase not dead | collision on; phase return-to-center; play `chase` |

`play(name)` is the base `playAnimation(name)` (restart only when the clip differs).

### 3.3 What the base step does differently for a boss
1. **Navigation** is `{arena}` only (`UniversalSceneWorldController.ts:2073-2079`): no spawn area
   (no territory, no regeneration, `may_engage = distance <= 933`), no safe zones.
2. **Arena leash** (`EnemyScript.ts:392-409`), after the "no target" check and before the
   territory: when the player **centre** is outside the arena perimeter (`bossPerimeterContains`,
   inclusive, squared distance for circles):
   ```
   if arena_left_at is unset: arena_left_at = now
   if arena_recovery_ms > 0 and now - arena_left_at >= arena_recovery_ms: restore_health(max)
   cancel_attack(); returning_to_arena = true; ai_state = runtime_state = "idle"
   velocity = toward the arena centre at movement_speed; when the centre is within
       max(1, movement_speed * delta) the body is put on the centre and velocity = 0
   update_facing(velocity); play_facing(walk/idle)      # no such clips on Fatty
   return
   ```
   Otherwise `returning_to_arena = false` and `arena_left_at` is cleared. The heal emits
   `health_changed` (the bar follows it). Not when the player is dead: the "no target" branch
   comes first.
3. **Attack reach** (`attackAreaReach`, `FattyScript.ts:214`; `EnemyAI.ts:271-273, 297, 309`):
   "in reach" is "the player's hurtbox overlaps the ContactAttack shapes", computed once per step.
   Chase → attack when in reach (instead of `distance <= attack_range`); attack → chase when not in
   reach (instead of `distance > attack_range × 1.3`); the impact lands only if still in reach
   (instead of `distance <= attack_range × 1.35`, `EnemyScript.ts:771-773`).
4. **Common attack gate** (`canRunCommonAttack`, `FattyScript.ts:212`; `EnemyScript.ts:467-469`):
   the AI's attack request starts the base melee only in phase chase.
5. **Melee** = the base sequence (enemy spec 5): windup 250, impact once at +250 (contact damage
   18, knockback 180, weapon `enemy-contact`, tags `contact, enemy`), finish +550, cooldown 1000.
   `attack_started {ranged: false, windupMs: 250}` has no listener on Fatty.
6. **Being hit** (`FattyScript.ts:19-43`):
   - `can_receive_damage`: phase airborne or contact-hop → `{accepted: false, reason: "state-blocked"}`
     (retryable); else the base rule (dead once defeated).
   - `react_to_damage`: always the hit feedback (flash `#ff6f88` 120 ms, number at position − (0, 8),
     yellow and big above 15). Never cancels the attack, never stuns, never changes the phase. Only
     in phase chase, with an applied knockback potency P > 0 and a non-zero knock vector, the
     velocity becomes `knock / |knock| × P` (no base 120, no resistance). Fatty is knockback
     immune, so P is always 0 in practice.
7. **Defeat** (`FattyScript.ts:203-210`): clear the telegraph; the base defeat (enemy spec 7:
   cancel, velocity 0, collision off, attack area off, `health_changed {hp: 0}`, `defeated`,
   `reward_requested {rewards: {}}`); collision off; play `death`; phase dead (→ DeathSfx).
8. **Exit**: clear the telegraph, then the base exit (cancel the attack, unregister the hurtbox).
9. The damage router registers the Eye with the authored rule and target tags `["enemy", "boss"]`.

### 3.4 `route_immediate_attack` (`EnemyScript.ts:675-699`)
```
needs attack_area, router, activations; the target active and hostile
origin = position; knock = unit(player centre − origin), or (0, 0) when they coincide
(optional range check: none for the landing)
activation = begin_activation(self, [attack_area])
route {activation, source self, attack_area, target_area = player hurtbox, weapon_id "enemy-contact",
       weapon_tags ["contact", "enemy"], damage_types ["physical"], base_damage,
       effects [{knockback, potency}] (omitted when potency <= 0), impact {position: origin, knock}}
hit = accepted and actual > 0; (impact effect: skipped for the landing); end_activation
```
A dodging player or one in i-frames rejects it `state-blocked`; nothing retries.

### 3.5 Shapes and overlaps (`EnemyScript.ts:626-643`, `runtime/scene/physics/SensorGeometry.ts`)
- `referencedAreaShapes(area)`: every CollisionShape2D child in world space, disabled or not.
- `targetOverlapsShapes(shapes, target)`: any shape intersects any shape of the player's hurtbox
  (`damageShapes`); with no hurtbox shapes, the player centre inside any shape.
- Telegraph translation (`FattyScript.ts:245-249`) moves each shape by the offset.
Godot: the shapes are the converted resources (ellipses are 32-point polygons) with their global
transforms; `Shape2D.collide` tests the overlap.

### 3.6 Telegraph (`features/effects/AttackTelegraphs.ts`)
One warning per attacker: `show` replaces the previous one; nothing is drawn when there are no
shapes and no shadow. Drawn on the ground-decal band, sorted at the shadow's y (the shapes'
average centre y without one): shadow ellipse first, then each shape filled and stroked (§1.3).
Static: it does not follow the boss. Shown by the contact hop (until the hop ends) and the leap
(from take-off to landing); cleared on landing, at the end of a contact hop, on defeat and on exit.

### 3.7 Camera shake and effects
`shakeCamera(ms, intensity)` (`EnemyScript.ts:714-716`) does nothing unless both are > 0, else
plays feel `boss-landing` with the scene's shake (`GameFeel.play(event, shake)`, hit-stop 0).
`spawnEffectAt(id, point)` (`:702-704`) does nothing for an empty id, else spawns `effect.<id>`
at the point (direction `right`). Both the contact-hop end and the landing spawn the crack at the
boss position (42 px above its feet).

---

## 4. The camp

### 4.1 Per fixed step, before the scripts (`UniversalSceneWorldController.ts:695, 1989-1996`)
For each camp: `inside = activation shapes contain the player position` (inclusive, ε 1e-6;
also while the player is dead) and `evaluate_activation(inside, Date.now())`
(`BossCampScript.ts:106-121`):
```
if suppress_spawn_until_outside:                 # resolveBossCampSpawnSuppression
    suppress_spawn_until_outside = inside; return false     # blocks this step either way
ready_at = respawn_ready_at (epoch ms or none)
if ready_at is set and not inside: observed_outside_after_defeat = true
eligible = not live_boss and inside and (ready_at is none or
           (observed_outside_after_defeat and epoch_now >= ready_at))     # bossCampSpawnEligible
if eligible: spawn(); return true
```
On entering the tree `observed_outside_after_defeat = (ready_at is none)` (`:64-75`).

### 4.2 spawn (`BossCampScript.ts:148-163`, `UniversalSceneWorldController.ts:1998-2012`)
```
active_bosses missing -> error
live_boss = true; observed_outside_after_defeat = false; respawn_ready_at = none
request = {sceneId, campId, bossId, parentRuntimeId (ActiveBosses), spawn: {x, y}}
spawner: remove any previous boss of this camp; mount `bossScene` at camp origin + spawn
    (the world's top level, not under ActiveBosses); its navigation is {arena}
status view: show the bar for this camp (gameEvents 'boss.engaged' {campId, bossId})
emit boss_spawn_requested(request)        # -> RoarSfx
emit guard_changed({instanceId: guardedChestInstanceId, guarded: true})
```
Godot: the boss root goes under `WorldService.entities_root()` (the y-sorted world root, as
Phaser's top level) with `spawn_at_phaser_position`, then `configure_arena(arena perimeter)`.

### 4.3 Arena and activation perimeters (`features/bosses/BossCampBehavior.ts`)
`bossPerimeterFromSensorShape` (`:5-9`): circle → `{circle, x, y (centre), radius}`; rectangle →
`{rectangle, x, y (top-left), w, h}`; other shapes none (the first convertible shape counts).
Not rounded (unlike world areas). `bossArenaCenter` (`:11-15`): circle centre or rectangle centre.
`clampToBossArena` (`:17-32`): rectangle → clamp each axis to [x, x + w] / [y, y + h]; circle →
unchanged inside (≤ r), else projected onto the circle. `bossPerimeterContains` (`:34-43`):
non-finite → false; rectangle inclusive; circle `dx² + dy² <= r²`.

### 4.4 Defeat (`UniversalSceneWorldController.ts:2021-2037`, after the fixed step)
```
particles boss-burst at position − (0, 30)
camp.on_boss_defeated(Date.now()):                               # BossCampScript.ts:123-132
    if not live_boss: return
    live_boss = false; observed_outside_after_defeat = false
    progress.markBossDefeated(bossId):  defeatedBossIds += bossId (Godot: RunState);
        gameEvents 'boss.defeated' {bossId}  (-> quests, AudioEventBridge 'Victory' cue);
        feel 'boss-defeated'
    respawn_ready_at = epoch_now + respawn_ms       # setBossCampRespawnReadyAt (Godot: RunState)
    status view: hide the bar (gameEvents 'boss.disengaged' {campId, defeated: true})
    emit boss_defeated({campId, bossId}); emit guard_changed({..., guarded: false})
floating text "<name> defeated!" yellow big at position − (0, 84)
dispose the boss mount (the same step)
```
`<name>` = `displayName`, else the boss id in title case (`bossDisplayName`, `:337-340`).
No coins, loot or XP (`onManagedEnemyDefeated` is only for ordinary enemies). Respawn: only after
the player has been outside the activation circle since the defeat, re-enters, and 180 s of wall
clock have passed.

**Godot deviation (requested):** Phaser disposes the boss in the step it dies, so its `death`
clip is never seen. The port keeps the dead body (collision off, hurtbox rejecting `dead`) until
the `death` clip has played (0.66 s on the gameplay clock), then frees it. Everything else in the
list above happens on the defeat step, as in Phaser.

### 4.5 Reset when the player dies (`scenes/WorldScene.ts:1920-1924` → `resetActiveFights`)
`reset_active_fight()` (`BossCampScript.ts:134-141`): if a boss lives: remove it, hide the bar
(not defeated), `live_boss = false`, `suppress_spawn_until_outside = true`, guard off. No respawn
timer: walking out of the activation circle and back in spawns a fresh boss at full health.
Godot: the camp listens to the player's `defeated` signal (emitted synchronously at death, like
`onPlayerDeath`).

### 4.6 Exit (`BossCampScript.ts:70-74`)
Remove the boss, hide the bar (not defeated), `live_boss = false`. In Godot this also happens on
world travel (main.gd frees the world root with the camp, its boss and any telegraph); the
respawn timer and the defeated ids stay in RunState.

---

## 5. Boss health bar (`features/ui/BossHealthSurfacePort.ts`)
`show_boss(campId, bossId)` stores `{name, hp(), maxHp()}` for the camp (a Map: re-showing keeps
the camp's place); `hide_boss(campId, defeated)` removes it. Every frame the bar shows the
**last** stored camp: `name`, `hp = max(0, hp())`, `maxHp = max(1, maxHp())`, `visible = any
stored`. So: shown on spawn, follows every hp change (hits, the arena heal), hidden on defeat,
on reset and when the camp leaves the tree. Godot: a Control on the HUD layer bound to every
camp's `boss_engaged` / `boss_disengaged`, polling the boss's damage state each frame.

---

## 6. Signals (Godot shape: one Dictionary, camelCase keys)
| Script | Signal | Payload | Emitted | Connected |
|---|---|---|---|---|
| fatty | `phase_changed` | `{phase, time}` | every transition | Hop/Leap/Fall/Land/Recover/Death SFX (filters) |
| fatty | base signals | enemy spec 8 | | `damaged` → HurtSfx |
| boss camp | `boss_spawn_requested` | `{sceneId, campId, bossId, parentRuntimeId, spawn: {x, y}}` | spawn | RoarSfx |
| boss camp | `boss_defeated` | `{campId, bossId}` | defeat | — (the quest hook; Phaser's `boss.defeated` carries `{bossId}`) |
| boss camp | `guard_changed` | `{instanceId, guarded}` | spawn, defeat, reset | — (chests OUT) |
| boss camp | *`boss_engaged`* | `{campId, bossId}` | spawn | the boss bar (Phaser `gameEvents 'boss.engaged'`) |
| boss camp | *`boss_disengaged`* | `{campId, defeated}` | defeat, reset, exit | the boss bar (`'boss.disengaged'`) |
Camps join the group `boss_camp`, so a later quest or music system finds them.

---

## 7. Centre vs feet
Every Fatty distance, arena test, leap point, telegraph shadow, crack position, damage number,
burst and defeat text uses the Phaser position `feet − (0, 42)`; the player side uses its centre
(`primary_target().centre`). The camp origin and the arena/activation circles have no depth
anchor (unchanged). Shapes (contact, landing, hurtboxes) are tested in global space as they are.

---

## 8. Porting checklist / pitfalls
- The base step must not move the body before Fatty's phase logic: Fatty zeroes the velocity in
  every phase but chase and teleports while airborne, then the body moves once.
- Fatty never stuns, so the base AI runs every step in every phase; only its velocity is
  overridden. The arena leash comes from the base step and is mirrored as the return phase.
- The contact hop is a side effect of the base melee: no melee start, no hop. The leap check is
  skipped while a melee sequence is active.
- Landing damage uses the player's hurtbox against the landing shape at the landing point, not a
  radius; the boss is only state-blocked while hopping or airborne.
- Floating point: phase ends compare `elapsed >= duration`, so with 60 Hz steps a phase can end
  one step later than the nominal time; tests allow one step.
- The camp clock for respawns is the wall clock (epoch ms), as Phaser's save-backed timer.
