# Enemy spec — worm swordsman, camp spawning (Phase 0 trial)

Source of truth: the Phaser code at `feat/godot-migration` (commit 41904a0). Everything below is read
from code; file:line references are to `src/game/...`. A GDScript engineer should be able to port this
without opening the TypeScript.

Godot targets (from the conventions): script `game.enemy` → `res://game/scripts/enemy.gd` (node name
`EnemyScript`, a child `Node` of the `CharacterBody2D` root); scene `character.worm-swordsman` →
`res://game/scenes/characters/worm-swordsman.tscn`; world areas `game.world-area` →
`res://game/scripts/world_area.gd`.

---

## 0. Scope

### IN trial scope
- Camp spawning from `enemy-spawn` world areas (counts, interval, respawn, spawn point, safe-zone rejection).
- One enemy script (`game.enemy`, the base `EnemyScript`) with its states: idle, wander, chase, attack,
  knockback (hit-stun), die; the camp **territory** layer (home / engaged / searching / returning, leash,
  regen, full heal); safe-zone avoidance (`flee` push-out).
- Attack: cooldown, windup, impact timing, reach check, damage request to the player, attack-area toggle.
- Sight: range + line of sight against world-layer blockers, throttled. **Elevation ignored.**
- Hit reaction: hit flash, damage number, knockback impulse, stun, knockback clip.
- Death: die clip, collision off, signals, despawn after 800 ms.
- Signals → SFX wiring (hurt, death, alert, windup) already in the scene JSON connections.

### OUT of trial scope (exist in Phaser; later phases must port them)
| Feature | Where | Notes |
|---|---|---|
| Loot drops & coins | `features/combat/CombatController.ts:281-301` (`awardEnemyDefeat`) | +`drop.coins` (worm: 10) via `enemy-types.json`, floating `+10c` text, items rolled by `chance` (worm: shard 20 %) dropped on the ground; emits `gameEvents 'enemy.died' {enemyId, areaId, kind}` used by **quest kill objectives** (`quests/matchers/ObjectiveMatchers.ts:55`). The scene `rewards` property and `reward_requested` signal are emitted but **nobody listens** (dead data). |
| Ranged / projectile enemies | `EnemyScript.ts:754-770`, `900-908`, `UniversalSceneWorldController.spawnEnemyProjectile` | **Ported 2026-10-05, §12.** `projectile` property, `projectileSpeed`, `stickMs` (spider web). Worm archer, slime spider, orb weaver. |
| `fleeRange` keep-distance behaviour | `EnemyAI.ts:284-286`, `317-335`; `EnemyScript.ts:441-442` | **Ported, §13.** Archers/spiders. Worm has no `fleeRange` (but see safe-zone flee, which IS in scope). |
| Slime spider AI | `enemies/ai/SlimeSpiderAI.ts` | **Ported 2026-10-05, §14.** `attributes.behavior == "slime-spider"`: orbit/approach, keep distance, retreat, fire. |
| Fatty / Matron bosses, boss arena leash, `arenaRecoveryMs`, telegraphs, camera shake, `routeImmediateAttack`, `attackAreaReach` overrides | `FattyScript.ts`, `MatronScript.ts`, `EnemyScript.ts:392-409, 598-610, 619, 675-716`, `features/effects/AttackTelegraphs.ts` | Ground telegraphs are **only** used by bosses; the worm has no telegraph besides its windup clip + SFX. Fatty and the arena leash are ported since 2026-10-05 ([boss.md](./boss.md)), the Matron too ([matron.md](./matron.md)) |
| `impactEffect` spawn on hit | `EnemyScript.ts:797-806` | **Ported 2026-10-05, §16.** Worm brawler only (`effect.enemy-worm-brawler-hit`). Worm swordsman has none. |
| Slow (goo trail) | `EnemyScript.ts:205-209, 425-426, 449, 486-487, 934-944` | **Ported 2026-10-05 (enemy side), §15.** `applySlow(multiplier, durationMs)`; the goo trail that calls it is the player's (abilities spec 12, OUT). |
| Effect immunities / `damageRule.effectResponses`, `acceptedSources`, `blockedWeaponTags` | `combat/DamageResolver.ts` | **Ported, §17** (the resolver had them since the Fatty port). Worm rule is `{priority:0, damageMultiplier:1}` only. |
| Elevation routing, `DamageRouter` reach gate | docs/ELEVATION.md | Not ported (elevation rejected; this router has no gate). |
| Occlusion silhouette for enemies | `UniversalSceneWorldController.registerCharacterOcclusion` | Dropped by plan. |
| Dev overlay attack areas | `EnemyScript.debugAttackAreas` | Debug only. |
| Legacy player-relative spawning, `despawnRadius` | `AuthoredEnemyPopulationController.ts:96-98, 115-121, 140-143, 216-224` | **Ported 2026-10-05, §18.** Only when a world has no spawn areas but has `metadata.spawns` (crystal-caverns, icege); level-1 has spawn areas and no `spawns`. |
| `enforceSpawnArea` (pursue-perimeter guard in the AI) | `EnemyAI.ts:142-206` | **Dead in practice**: `EnemyScript.ts:472` passes `spawnArea` to the AI only when there is no territory, and a territory exists exactly when there is a spawn area. Do not port. |
| `hit_reaction`, `damage_feedback` signals | `EnemyScript.ts:303, 315` | `hit_reaction` is not even a declared signal (no-op); `damage_feedback` has no listener. Optional. |

---

## 1. Data: where every number comes from

All enemy AI/combat numbers come from the **scene JSON script properties** of
`characters/worm-swordsman.scene.json` (node `script`, `scriptId: game.enemy`). `enemy-types.json`
duplicates the same `ai` values but the runtime only uses it for: the type id → scene id
(`character.<type>`, `UniversalSceneWorldController.ts:332`), identity for `maxAlive` counting, and
`drop` (out of scope). **No enemy value lives in `game-constants.json`.** Everything else is a code literal.

### 1.1 Worm swordsman script properties (scene JSON → Godot export, snake_case)
| JSON | Godot export | Value |
|---|---|---|
| `body` | `body: CharacterBody2D` | root `WormSwordsman` |
| `visual` | `visual: Sprite2D` | `Visual` |
| `animation` | `animation: AnimationPlayer` | `Animation` |
| `damageArea` | `damage_area: Area2D` | `DamageArea` (hurtbox) |
| `attackArea` | `attack_area: Area2D` | `AttackArea` (hitbox) |
| `faction` | `faction: String` | `"hostile"` |
| `rank` | `rank: String` | `"ordinary"` |
| `maxHealth` | `max_health: float` | 90 (clamped `max(1, v)`) |
| `targetingRadius` | `targeting_radius: float` | 220 (= aggro range) |
| `attackRange` | `attack_range: float` | 38 |
| `movementSpeed` | `movement_speed: float` | 75 (= chase speed) |
| `attackCooldownMs` | `attack_cooldown_ms: float` | 1500 |
| `attributes` | `attributes: Dictionary` (camelCase keys) | `wanderSpeed 28, attackWindupMs 400, attackRecoveryMs 400, contactDamage 37, knockbackStrength 260, knockbackResist 0.45` |
| `damageRule` | `damage_rule: Dictionary` | `{priority:0, damageMultiplier:1}` |
| `rewards` | `rewards: Dictionary` | `{coins:10, items:[{itemId:"shard",chance:0.2}]}` (unused) |
Declare also (absent on the worm, defaults): `display_name ""`, `arena_recovery_ms 0`, `projectile {}`, `impact_effect {}`.
Attribute readers (`EnemyScript.ts:869-927`): a missing/non-finite number → fallback (0 unless stated);
`fleeRange`, `leashRange`, `projectileSpeed` are "optional" (absent = null).

### 1.2 Code literals
| Name | Value | Source |
|---|---|---|
| `ENEMY_SIGHT_CHECK_MS` | 150 | `features/scripts/EnemyScript.ts:100` |
| `ENEMY_HIT_KNOCKBACK_BASE` | 120 | `EnemyScript.ts:103` |
| `ENEMY_HIT_STUN_BASE_MS` | 320 | `:105` |
| `ENEMY_HIT_STUN_MAX_BONUS_MS` | 280 | `:106` |
| `ENEMY_HIT_STUN_PER_STRENGTH_MS` | 0.35 | `:107` |
| `ENEMY_HIT_STUN_VELOCITY_DECAY` | 0.94 per 60 Hz step | `:109` |
| `ENEMY_HIT_FLASH_MS` | 120 | `:110` |
| `ENEMY_HIT_FLASH_COLOR` | `0xff6f88` | `:111` |
| `ENEMY_ATTACK_SEQUENCE_PADDING_MS` | 250 | `:113` |
| `ENEMY_ATTACK_SEQUENCE_MAX_MS` | 2000 | `:114` |
| `ENEMY_MELEE_REACH_MULTIPLIER` | 1.35 | `:116` |
| walk/idle clip threshold | speed > 2 px/s → walk | `:405, 428, 490` |
| territory `leashRange` | `leashRange attr ?? max(520, aggro*2)` → worm **520** | `enemies/ai/Territory.ts:42-53` |
| territory `searchMs` | 3000 | `Territory.ts:44` |
| territory `loseSightMultiplier` | 1.5 | `:45` |
| territory `returnSpeedMultiplier` | 1.3 → worm 97.5 px/s | `:46` |
| territory `regenPerSecond` | 0.35 × maxHealth → worm 31.5 hp/s | `:47` |
| territory `ARRIVED` | 18 px | `Territory.ts:112` |
| chase give-up | distance > aggro × 1.5 (330) → wander | `enemies/EnemyAI.ts:279` |
| attack keep-reach | distance > attackRange × 1.3 (49.4) → chase | `EnemyAI.ts:308` |
| idle → wander chance | `random() < 0.01` per AI call | `EnemyAI.ts:245` |
| wander re-pick direction | `random() < 0.02` per AI call, uniform angle × wanderSpeed | `EnemyAI.ts:259-262` |
| wander → idle chance | `random() < 0.005` per AI call | `EnemyAI.ts:264` |
| safe-zone push speed | chaseSpeed × 1.25 (93.75) | `EnemyAI.ts:228` |
| defeated → dispose | 800 ms (enemy's simulation time) | `features/world/UniversalSceneWorldController.ts:2052` |
| spawn point attempts | 32 | `enemies/AuthoredEnemyPopulationController.ts:206` |
| initial seed count | `min(8, spawns?.maxPopulation ?? 8)` = 8, then `min(8, area.maxPopulation)` per area | `CombatController.ts:137`, `AuthoredEnemyPopulationController.ts:92` |
| sight blocker min size | bodies < 20 px on **both** sides never block | `infrastructure/scenes/PhaserNodeContext.ts:95` |
| damage number "important" | amount > 15 → yellow + emphasised, else white | `UniversalSceneWorldController.ts:2043` |

The per-call random chances assume one AI call per 60 Hz physics step (they are frame-rate dependent
and the AI may be called up to 3× in one step, see §4.4). Keep Godot physics at 60 Hz and port them as is.

### 1.3 Derived worm numbers
- Aggro 220; lose sight beyond 330; chase speed 75; wander 28; return/search walk 97.5.
- Melee: enters attack at ≤ 38; leaves attack state at > 49.4; impact lands if ≤ **51.3** (= 38 × 1.35,
  which is exactly the authored `worm-swordsman.attack-shape` circle radius 51.3).
- Attack sequence: impact at +400 ms, finish at +min(2000, max(400+400, clipMs) + 250) = **+1050 ms**
  (clip 444 ms side / 333 ms up-down, both < 800). Cooldown: next attack ≥ 1500 ms after the previous start.
- Hit: strength = (P + 120) × (1 − 0.45) where P = summed `knockback` effect potency of the hit.
  Example basic sword (knockStrength 140, unscaled): 143 px/s, stun 320 + min(280, 50.05) = 370 ms.

---

## 2. Scene structure (worm-swordsman.scene.json)

Root `WormSwordsman` CharacterBody2D: `collisionLayer 4` (bit 3 = enemy), `collisionMask 1027`
(world 1 + player 2 + water 1024), `depthAnchor [0,22]`, `collideWorldBounds true`.
Enemies do **not** collide with each other (enemy bit not in mask). The player's mask (1157) includes
enemy, so player and worm block each other. Use `motion_mode = MOTION_MODE_FLOATING` (top-down).

| Node | Type | Phaser props | After feet re-anchor (Godot) |
|---|---|---|---|
| BodyShape | CollisionShape2D | rect 36×26 at (0,9) | (0,−13) |
| Visual | Sprite2D | sheet `enemy.worm.swordsman` 64×64, 38 frames, origin 0.5 | position (0,−22) |
| DamageArea | Area2D | layer 8 (hurtbox), mask 16, monitoring/monitorable true | — |
| DamageShape | CollisionShape2D | rect 36×26 at (0,9) | (0,−13) |
| AttackArea | Area2D | layer 16 (hitbox), mask 8, **monitoring false, monitorable false** | — |
| AttackShape | CollisionShape2D | circle r 51.3 at (0,0), **disabled true** | (0,−22) |
| Animation | AnimationPlayer | `domain: physics`, `autoplay: idle-side` | |
| EnemyScript | ScriptNode `game.enemy` | §1.1 | |
| HurtSfx | AudioStreamPlayer2D | worm-hurt 1-3, pitchRandomness 0.06, minIntervalMs 90 | |
| DeathSfx | AudioStreamPlayer2D | worm-death 1-2, pitchRandomness 0.06, **detached** | |
| AlertSfx | AudioStreamPlayer2D | worm-alert, volume 0.7 | |
| WindupSfx | AudioStreamPlayer2D | worm-windup, volume 0.8 | |

Connections (all `handler: play` → `play_cue(payload)` in Godot):
`EnemyScript.damaged → HurtSfx`, `defeated → DeathSfx`, `alerted → AlertSfx`, `attack_started → WindupSfx`.

### 2.1 Animation clips (all track `../Visual:frame`, discrete)
Facing suffix is `side | up | down`; side clips are mirrored with `flip_h` when facing left.
| Clip | fps | length s | loop | frames |
|---|---|---|---|---|
| idle-down / idle-up / idle-side | 5 | 0.8 | yes | 0-3 / 4-7 / 8-11 |
| walk-down / walk-up / walk-side | 8 | 0.5 | yes | 12-15 / 16-19 / 20-23 |
| attack-down / attack-up | 9 | 0.333 | no | 24-26 / 27-29 |
| attack-side | 9 | 0.444 | no | 30-33; **events** `hitbox-activated {hitboxId:"sword",spanIndex:0}` at frame 1 (0.111 s) and `hitbox-deactivated` at frame 3 (0.333 s), `gameplay:true` |
| knockback-down / -up / -side | 8 | 0.125 | no | single frame 0 / 4 / 8 (the first idle frame) |
| die-down / -up / -side | 7 | 0.571 | no | 34-37 (same frames for all facings) |

**The attack-side animation events are NOT consumed by anything in Phaser** (only
`AnimationPlayerNode.ts:71` emits them; there is no listener or connection). Damage timing is a
**timer** (`attackWindupMs`), not the events, and the up/down clips have no events at all. For parity,
the Godot port must ignore `animation_event` for the worm and use the timer (§5). Switching to
event-driven hitboxes would break up/down attacks and change timing (0.111 s vs 0.4 s) — a design
change for later, not part of the port.

Non-looping clips hold their last frame when finished, and `currentAnimation` becomes empty
(`AnimationPlayerNode.ts:72-78`). Godot behaves the same (`current_animation == ""` after a
non-looping clip ends), so the `play_animation` rule below ports directly.

---

## 3. Spawning (camp areas)

### 3.1 World-area data (level-1)
Built by `infrastructure/scenes/WorldSceneLoader.ts:192-237` (`worldAreaData`) from every
`game.world-area` ScriptNode: `areaKind`, `areaId`, `data` (Dictionary), node refs `shape` (outer) and
`stayShape` (enemy-spawn only). Perimeters come from the referenced CollisionShape2D's resource and
**global** position (`content/scenes/worldAreaGeometry.ts:32-52`):
- rectangle: `left = round(x − w/2)`, `top = round(y − h/2)`, `right = max(left+1, round(x + w/2))`,
  `bottom = max(top+1, round(y + h/2))` → `{shape:"rectangle", x:left, y:top, w:right−left, h:bottom−top}`
  (rotation not allowed; scale multiplies w/h).
- circle: `{shape:"circle", x:round(x), y:round(y), radius:max(1, round(r·scale))}`.
- `enemy-spawn` → `{...data, id, stayPerimeter: stay, pursuePerimeter: outer}`; validated: same shape kind,
  stay fully inside pursue.
- `enemy-safe-zone` → rect only → `{x, y, w, h}`.
World areas have no `depthAnchor`, so their positions are unchanged in Godot.

level-1 (`worlds/level-1.scene.json`):
| areaId | kind | node position | shapes | computed perimeters | data |
|---|---|---|---|---|---|
| `level-1-starter-camp` | enemy-spawn | (1132, 1509.5) | pursue rect 1288.5×880.5 at (0,0); stay rect 280×181 at (−2, 4.5) | pursue `x488 y1069 w1288 h881`; stay `x990 y1424 w280 h181` | `enemies:[{type:"worm-swordsman", weight:1, maxAlive:3}], intervalMs:2500, maxPopulation:3` |
| `enemy-safe-1` | enemy-safe-zone | (896, 640) | rect 1536×1024 | `x128 y128 w1536 h1024` | — |
| `level-1-webwood`, `-autumn-grove`, `-south-meadow` | enemy-spawn | | | | spiders/archers/brawlers — **out of trial scope** (skip these areas, or spawn only types that have a ported scene) |

Player spawn marker is (640, 704) — inside the safe zone and **outside** the starter camp's pursue rect,
so on a fresh load nothing is seeded; worms appear once the player walks into the pursue rect.
Note the safe zone (y ≤ 1152) overlaps the top of the pursue rect (y ≥ 1069).

### 3.2 Population controller (`enemies/AuthoredEnemyPopulationController.ts`)
Owned by `CombatController` (`features/combat/CombatController.ts:117-138`), updated every fixed step
with `time = world simulation time in ms` (starts at 0 at world load, `WorldScene.ts:1880`,
`UniversalSceneWorldController.ts:693`).

State: `enemies: Array[member]`, `area_by_enemy: {member → area}`, `area_last_spawn_at: {areaId → ms}` (default 0).

**seed(8)** at construction (`:87-99`): for each area whose **pursue** perimeter contains the player
position: spawn `min(8, area.maxPopulation)` = 3 immediately. (Does NOT set `area_last_spawn_at`.)

**update(time)** each fixed step (`:101-138`):
1. Drop list entries: a member whose node is gone (`!active && !dead`) → destroy & drop; a member that is
   `dead` → drop (its node is still on screen; it is freed by the death timer, §7). Camp members are never
   despawned by distance (`:115`).
2. For each area with the player inside its **pursue** perimeter
   (`enemySpawnAreaContainsPlayer` = `perimeterContains(pursue, player.x, player.y)`, inclusive edges):
   `count = alive members of this area`; if `time > area_last_spawn_at + intervalMs` **and**
   `count < maxPopulation` → `spawn_one(area)` and set `area_last_spawn_at = time` (set even if the spawn
   returned null).
   - The interval timer only advances while the player is inside the pursue rect; with the player outside,
     nothing spawns and nothing despawns.
   - **Edge case (faithful):** the interval is measured from the last *spawn*, not the last death. If the
     camp was full for > 2.5 s, killing a worm causes a replacement to spawn on the very next step
     (while the corpse is still visible for 800 ms).
   - First worm appears at the first step where `time > 2500` and the player is inside; then one every
     2.5 s up to 3.

**spawn_one(area)** (`:146-197`):
1. Candidate types: `area.enemies` entries; drop entries whose `maxAlive` is reached (alive members with the
   same type and the same area id). None → return null.
2. Weighted pick: `roll = randf() * total_weight`; iterate entries `roll -= weight`; first with `roll <= 0`.
3. Spawn point (`:203-214`): up to 32 tries of `random_point_in_perimeter(stay)`; reject a point inside
   any safe zone (inclusive rect test against `enemySafeZones`); none found → return null.
   Rectangle: `(x + randf()*w, y + randf()*h)`; circle: `angle = randf()*TAU, d = sqrt(randf())*r`
   (`content/maps/agentAreaGeometry.ts:35-38`). No collision check: a worm may spawn overlapping a tree.
4. Instantiate scene `character.<type>` (via `res://game/scenes/scene_index.json`) at the point
   (`UniversalSceneWorldController.ts:1444-1468`) and hand the enemy its navigation: the spawn area record
   and the world's safe-zone list (`:2073-2085`).
   **Feet origin:** the point is the Phaser body *centre*; place the Godot root at
   `point + depth_anchor * scale` = `point + (0, 22)`.

---

## 4. Per-step behaviour (`EnemyScript._physics_process`, `EnemyScript.ts:361-491`)

### 4.1 Script state
```
sim_ms := 0.0                 # own simulation clock, += delta*1000 each physics step
hp := max_health; defeated := false; reward_published := false
attack_state := {active:false, ready_at:0, sequence_id:0}       # enemyCombatLifecycle.ts
active_sequence_id := null; active_activation_id := null
attack_impact_at := 0; attack_finish_at := 0; attack_resolved := false
attack_direction := Vector2(0, 1)
ai_state := "idle"; runtime_state := "idle"
facing := "down"; facing_flipped := false
hit_stun_until := 0; hit_flash_until := 0
territory := {mode:"home", last_seen:null, search_until:0}; hurt_since_territory_step := false
sight_checked_at := -INF; sight_cached := false
```
`_enter_tree`: register the hurtbox (`damage_area`) with the damage router using `damage_rule`
(priority 0, multiplier 1); error if `damage_area` / `attack_area` missing. `_exit_tree`: `cancel_attack()`,
unregister.

### 4.2 Step order (exact)
```
sim_ms += delta * 1000
update_hit_flash()                                  # §6.2
if defeated: velocity = 0; runtime_state = "dead"; return
if sim_ms < hit_stun_until:                         # knockback / stun
    velocity *= pow(0.94, delta * 60); return       # no AI, no territory, no attack, no anim change
target = primary target (the player)
if target missing or target dead (or not hostile):
    cancel_attack(); ai_state = runtime_state = "idle"; velocity = 0; play_facing("idle"); return
origin = enemy CENTRE; player = player CENTRE        # see §9
dir = normalized(player - origin) or attack_direction if zero length
distance = |player - origin|
territory = step_camp_territory(...) if this enemy has a spawn area else null   # §4.3
if territory and (territory.move_to or territory.hold):
    cancel_attack()
    ai_state = "idle" if hold else "wander"; runtime_state = ai_state
    speed = movement_speed * 1.3
    step = move_to ? normalized(move_to - origin) * speed : 0
    velocity = step
    update_facing(step); play_facing("walk" if |step| > 2 else "idle"); return
if territory and territory.mode == "engaged" and ai_state in ["idle", "wander"]:
    emit alerted({state:"chase"}); ai_state = "chase"
if active_sequence_id != null:                      # attack in flight, §5
    if not attack_resolved and sim_ms >= attack_impact_at: resolve_attack(target, origin)
    if active_sequence_id != null and sim_ms >= attack_finish_at:
        finish_attack(active_sequence_id); ai_state = "chase"   # ("flee" if fleeRange set & distance < fleeRange — out of scope)
run the AI loop (§4.4) starting from ai_state, with velocity = current body velocity
if old ai_state in [idle, wander] and new state in [chase, flee]: emit alerted({state: new})
ai_state = new state
runtime_state = "attack" if active_sequence_id != null else ai_state
body.velocity = velocity
if active_sequence_id != null: return               # facing/anim frozen while attacking
update_facing(velocity); play_facing("walk" if |velocity| > 2 else "idle")
```
Then the body moves: Phaser Arcade integrates `velocity` after scripts. In Godot call
`ArcadeMover.move(body, delta)` (`game/shared/arcade_mover.gd`) at the end of **every** path above except `defeated` (the stun path must move
too, it is the knockback slide). The AI reads back `body.velocity` the next step, so keep using the
post-move velocity (the mover zeroes the blocked component on collision, as Arcade does; `move_and_slide()` would not).

### 4.3 Territory (`enemies/ai/Territory.ts:115-169`, called from `EnemyScript.ts:548-571`)
Inputs: `now = sim_ms`, `enemy = origin`, `player = player centre`, `home = area.stayPerimeter`,
`aggro = targeting_radius (220)`, `attack_reach = attack_range (38)`, `sees_player = sees_target()`,
`hurt = hurt_since_territory_step` (then reset to false). Rules: §1.2.

Helpers:
- `home_distance(home, p)`: circle → `max(0, |p − c| − r)`; rect → `hypot(max(x−p.x, 0, p.x−(x+w)), max(y−p.y, 0, p.y−(y+h)))` (0 inside).
- `home_center(home)`: circle centre or rect centre (`x + w/2, y + h/2`) — stay `990,1424,280,181` → (1130, 1514.5).
- `within_leash = from_home + max(0, distance − attack_reach) <= leash (520)`.

Per step: `from_home = home_distance(home, enemy)`; `reachable = player && within_leash`;
`in_sight = player && sees_player && distance <= aggro`.
Actions: **engage** → mode engaged, `last_seen = player`, `{mode:engaged, may_engage:true}`.
**go_home** → mode returning, `{move_to: home_center, regenerate:true}`.
**search** → if mode was not searching: `search_until = now + 3000`; mode searching; if `last_seen` exists
and `|last_seen − enemy| > 18` and `home_distance(home, last_seen) <= 520` → `{move_to: last_seen}` else `{hold:true}`.

| mode | rule (first match) |
|---|---|
| home | `(in_sight or hurt) and reachable` → engage; `from_home > 18` → go_home; else `{mode:home}` (AI runs, may_engage false) |
| engaged | `!player or !reachable` → go_home; `lost = !sees_player or distance > aggro*1.5`; `lost and !hurt` → search; else engage |
| searching | `(in_sight or hurt) and reachable` → engage; `now >= search_until` → go_home; else search |
| returning | `hurt and reachable` → engage (sight alone does not); `from_home <= 0` → mode home, `last_seen = null`, `{mode:home, regenerate:true, restore_health:true}`; else go_home |

After the decision (`EnemyScript.ts:568-569`): `restore_health` → `restore_health(max_health)`; else
`regenerate` → `restore_health(hp + max_health * 0.35 * delta)`.
`restore_health(v)`: `next = min(max, max(hp, v))`; if unchanged or defeated → nothing; else set and emit
`health_changed({hp, maxHp})`.

Consequences worth knowing:
- `may_engage` is false in every mode except engaged, so idle/wandering worms only start chasing via the
  "engaged → alerted, chase" line in §4.2.
- A wandering worm that drifts > 18 px outside the stay rect walks back to the stay centre at 97.5 px/s,
  regenerating, and heals to full when it re-enters (`from_home <= 0`, i.e. at the edge, not the centre).
  It then continues in `ai_state = "wander"` **with the return velocity still on the body** until the
  wander RNG picks a new direction (faithful quirk).
- While hit-stunned the territory does not step, so `hurt` stays true until the stun ends, then engages.
- When the player dies the early "no target" branch runs; territory memory stays as it was.

**Sight** (`EnemyScript.ts:574-580`): if `distance > targeting_radius * 1.5` → false (no cache update).
Else if `sim_ms − sight_checked_at < 150` → `sight_cached`. Else `sight_checked_at = sim_ms`,
`sight_cached = line_of_sight(origin, player)`. Phaser `lineOfSight` = no static body on the **world**
collision layer (bit 1) whose AABB intersects the segment, ignoring bodies smaller than 20 px in both
width and height (`PhaserNodeContext.ts:95-106`); water does not block. Godot: `intersect_ray` from
centre to centre with `collision_mask = 1`, excluding the enemy and player bodies; the < 20 px exception
is an acceptable approximation to skip for the trial (or check the hit collider's shape size). Elevation is
ignored. No target service → `true`.

### 4.4 Combat AI loop (`EnemyScript.ts:449-487` + `enemies/EnemyAI.ts`)
```
velocity = body.velocity        # (divided by last slow factor; 1 in trial)
state = ai_state
for i in 3:
    before = velocity
    result = run_state(state, ctx)            # may write velocity
    if result == "continue": break
    state = result
    if velocity != 0 and velocity != before: break
```
`run_state` first applies **safe zones** (every state except dead, `EnemyAI.ts:208-234`): for the first
safe-zone rect containing the enemy centre (inclusive), compute distances to the 4 edges
(left `ex−x`, right `x+w−ex`, top `ey−y`, bottom `y+h−ey`), pick the smallest (ties: first in that
order), set velocity = that outward axis × chaseSpeed × 1.25, return `"flee"`. Then (spawnArea guard —
dead, skip) then the state function. `ctx`: `distance`, `dir`, config (aggro 220, attackRange 38,
wanderSpeed 28, chaseSpeed 75, fleeRange null), `in_attack_reach = null` (base script → distance rule),
`may_engage = territory.may_engage` when a territory exists, else `distance <= aggro`.

| state | behaviour (`EnemyAI.ts`) |
|---|---|
| idle (236-247) | velocity = 0; `noticesPlayer` (`may_engage`) → "chase"; `randf() < 0.01` → "wander"; else continue |
| wander (249-269) | noticesPlayer → velocity 0, "chase"; `randf() < 0.02` → velocity = (cos a, sin a) × 28 with `a = randf()*TAU`; then `randf() < 0.005` → velocity 0, "idle"; else continue (velocity kept) |
| chase (275-301) | `distance > aggro*1.5` (330) → "wander"; (fleeRange — n/a); `distance <= 38` → velocity 0, "attack"; else velocity = dir × 75, continue |
| attack (303-315) | `distance > 38*1.3` (49.4) → "chase"; else velocity 0, `request_attack(dir)`, continue |
| flee (317-335) | (fleeRange n/a); `distance > aggro*1.5` → "wander"; else velocity = −dir × 75 (runs **away** from the player), continue |
| dead | continue |

Safe-zone edge case (in scope, faithful): after being pushed out of a safe zone the worm is in `flee`, and
plain `flee` without `fleeRange` runs away from the player until > 330 px (then wander) — unless the
territory takes over first (search/return). With level-1's layout a worm chasing north toward the village
can reach the safe-zone edge (stay top y 1424 → safe-zone bottom y 1152 is 272 px, inside the 520 leash).

`request_attack(dir)` → `begin_attack(dir)` (§5). It is called every step while in `attack` state; it is a
no-op while an attack is active or the cooldown is running.

### 4.5 Facing and clips (`EnemyScript.ts:826-845, 665-668`)
`update_facing(v)`: ignore if `|v| < 1e-6`; if `|v.x| > |v.y|` → facing "side", `flipped = v.x < 0`; else
facing "up" if `v.y < 0` else "down", `flipped = false`. Then `visual.flip_h = flipped`
(`mirrorsSideFacing` true for the base script).
`play_facing(action, restart=false)` → `play_animation(action + "-" + facing, restart)`;
`play_animation(name, restart)`: play only if `(restart or current_animation != name) and has_animation(name)`.
Initial facing "down" → first idle is `idle-down` (the scene's autoplay `idle-side` shows for one step).

---

## 5. Attack (timer driven)

### 5.1 Cooldown lifecycle (`enemies/enemyCombatLifecycle.ts`)
- `try_begin(time, cooldown)`: if `active` or `time < ready_at` → fail; else `sequence_id += 1`,
  `active = true`, `ready_at = time + cooldown`, return sequence id.
- `finish(seq)`: if `active and sequence_id == seq` → `active = false`.
- `cancel()`: `active = false`, `sequence_id += 1` (`ready_at` unchanged: a cancelled swing still costs its cooldown).

### 5.2 begin_attack(direction) (`EnemyScript.ts:724-746`)
```
seq = try_begin(sim_ms, attack_cooldown_ms (1500)); if fail: return
attack_direction = normalized(direction) (keep old if zero)
active_sequence_id = seq
active_activation_id = activations.begin(self, [attack_area])   # one-hit-per-target token
windup = max(0, attributes.attackWindupMs)   # 400
recovery = max(0, attributes.attackRecoveryMs) # 400
update_facing(attack_direction)
clip_ms = length of "attack-" + facing        # 444 side / 333 up-down
attack_impact_at = sim_ms + windup                                   # +400
attack_finish_at = sim_ms + min(2000, max(windup + recovery, clip_ms) + 250)   # +1050
attack_resolved = false
set_attack_area_active(true)
play_facing("attack", restart=true)
emit attack_started({ranged:false, windupMs:windup})   # → WindupSfx
```
`set_attack_area_active(on)`: `attack_area.monitoring = on`; every CollisionShape2D child
`disabled = !on` (`EnemyScript.ts:816-823`). In Godot use `set_deferred` for both (physics-callback safe).
The area toggle is **cosmetic for the worm**: damage does not come from the physics overlap (see 5.3).

During the sequence the AI loop keeps running (§4.2): in `attack` state it holds still; if the player
steps beyond 49.4 px it switches to `chase` and **slides toward the player while the swing plays out**
(facing/clip frozen). The attack clip ends at 333/444 ms and holds its last frame until +1050 ms.

### 5.3 resolve_attack at `sim_ms >= attack_impact_at` (`EnemyScript.ts:748-795`)
```
attack_resolved = true                            # only ONE impact check per swing
if activation/area/router missing or target dead: return
distance = |player centre − enemy centre|
if distance > attack_range * 1.35 (51.3): return  # whiff
knock = normalized(player − origin) or attack_direction if zero
route damage request to the player's hurtbox:
  activation_id, source = self, attack_area, target_area = player damage area,
  weapon_id "enemy-contact", weapon_tags ["contact","enemy"] (sorted), damage_types ["physical"],
  base_damage = attributes.contactDamage (37),
  effects = [{effect_id:"knockback", potency: attributes.knockbackStrength (260)}] (omitted if potency <= 0),
  impact = {x: origin.x, y: origin.y, knock_x: knock.x, knock_y: knock.y}
(if accepted with damage > 0 and impactEffect set → spawn effect; worm has none)
```
The player's handling (mitigation, i-frames, knockback 260 along knock dir) belongs to the player/combat
spec. If the player is in i-frames the router returns a *retryable* rejection, but the worm never retries
(`attack_resolved` is already true) — the swing simply misses.

### 5.4 Ending
At `sim_ms >= attack_finish_at`: `finish_attack(seq)` → `end_attack()`; `ai_state = "chase"`.
`end_attack()` (`:808-814`): `activations.end(activation_id)`, clear `active_activation_id`,
`active_sequence_id = null`, `attack_resolved = false`, `set_attack_area_active(false)`.
`cancel_attack()` = lifecycle cancel + `end_attack()`; called on: hit (non-lethal), death, target
lost/dead, territory move/hold, `_exit_tree`.

---

## 6. Being hit

### 6.1 Damage receive (`EnemyScript.ts:255-304`, `features/combat/DamageResolver.ts`, `DamageRouter.ts`)
The player's weapon routes a request at the worm's `DamageArea`. Resolver order: validate → source
matches rule (worm: accepts everything) → if receiver state dead/hp ≤ 0 reject `dead` →
`scaled = base_damage × 1 (multiplier) × per-type multipliers (none)` → `can_receive_damage`: rejects
with `dead` once defeated → `rounded = max(0, round(scaled))`, `actual = min(hp, rounded)` → effects
(knockback potency × responses: none) → if `actual == 0` and no applied effects → reject `immune` →
accept `{actual_damage, defeated: actual >= hp, applied_effects, rejected_effects}`.
One accepted hit per receiver per weapon activation (AttackActivation).

`commit_damage(commit)`:
```
if defeated: return
hp = max(0, hp − actual)
emit health_changed({hp, maxHp}); emit damaged(commit)      # damaged → HurtSfx (also on the killing blow)
is_dead = commit.defeated or hp <= 0
hurt_since_territory_step = true
react_to_damage(commit, is_dead)
if is_dead: defeat()
```

### 6.2 react_to_damage (`EnemyScript.ts:282-312`)
```
show_hit_feedback(commit):
    hit_flash_until = sim_ms + 120
    visual tint-fill 0xff6f88 (solid colour silhouette, see below)
    damage number at (enemy centre x, top of Visual bounds − 8), text "-<amount>",
        yellow & emphasised if amount > 15 else white            (UniversalSceneWorldController.ts:2039-2045)
if is_dead: return
cancel_attack()
immune = rejected_effects has {knockback, reason "immune"}
P = sum of applied "knockback" potencies
resist = clamp(attributes.knockbackResist, 0, 1)      # 0.45
strength = 0 if immune else (P + 120) * (1 − resist)
k = (impact.knock_x, impact.knock_y); if strength > 0 and |k| > 0: body.velocity = k / |k| * strength
stun_ms = 320 + min(280, strength * 0.35)
hit_stun_until = max(hit_stun_until, sim_ms + stun_ms)
play_facing("knockback", restart=true)                  # 0.125 s, holds the first idle frame
```
Note the base 120 is added even when the weapon carries no knockback effect (P = 0 → 66 px/s for the worm).
During the stun the body slides with `velocity *= 0.94^(delta*60)` per step and nothing else runs
(§4.2). Facing does not change on a hit.

`update_hit_flash()` (start of every step, also while dead): if `hit_flash_until > 0` and
`sim_ms >= hit_flash_until` → `hit_flash_until = 0`, clear the tint.
Godot: Phaser `setTintFill` replaces every opaque pixel with the colour; `modulate` (multiplicative)
cannot do that. Use a small `canvas_item` shader on `Visual` (`uniform vec4 flash_color; uniform float
flash;` → `COLOR.rgb = mix(tex.rgb, flash_color.rgb, flash)`), keep `self_modulate` for authored tint
and `modulate` free, per conventions.

---

## 7. Death and despawn

`defeat()` (`EnemyScript.ts:515-533`), once:
```
defeated = true; hp = 0
cancel_attack(); runtime_state = "dead"
velocity = 0; body collision disabled  (Phaser `collisionEnabled = false`; Godot: set_deferred
    BodyShape.disabled = true, or zero collision_layer/mask, so the player walks through the corpse)
set_attack_area_active(false)
play_facing("die", restart=true)                 # die-<facing>, 0.571 s, holds frame 37
emit health_changed({hp:0, maxHp}); emit defeated({receiverNodeId})   # → DeathSfx (detached)
emit reward_requested({receiverNodeId, rewards}) once      # no listener
```
The hurtbox stays registered; further hits are rejected `dead` (no flash, no SFX).
Each later step only zeroes velocity (and clears the flash when due).

World side (`UniversalSceneWorldController.ts:2047-2071`, after each fixed step): on first seeing
`defeated`: `dispose_at = enemy.sim_ms + 800` and notify `on_enemy_defeated({enemyId, config, x, y})`
(enemy centre; → coins/loot/`enemy.died`, out of scope); when `enemy.sim_ms >= dispose_at` →
`queue_free()` the enemy root. No fade or tween: the last die frame shows until removal.
The population controller already dropped the member the step it died (§3.2).
`DeathSfx` is `detached`, so its sound must survive the 800 ms free (sfx_player_2d handles it).

---

## 8. Signals and services (Godot shape)

Enemy script signals (one Dictionary payload each, per conventions):
| signal | payload | emitted | connected in scene |
|---|---|---|---|
| `health_changed` | `{hp, maxHp}` | damage, regen, full heal, death | — |
| `damaged` | commit Dictionary | every accepted hit (incl. lethal) | HurtSfx `play_cue` |
| `defeated` | `{receiverNodeId}` | death | DeathSfx `play_cue` |
| `alerted` | `{state: "chase"|"flee"}` | idle/wander → chase/flee | AlertSfx `play_cue` |
| `attack_started` | `{ranged:false, windupMs:400}` | swing start | WindupSfx `play_cue` |
| `reward_requested` | `{receiverNodeId, rewards}` | death, once | — |
| `damage_feedback` | commit | after commit | — (optional) |

Services the enemy needs from the world (Phaser `ENEMY_TARGET_SERVICE`, `UniversalSceneWorldController.ts:575-589`):
- `get_primary_target()` → player: centre position, hurtbox id/node, `active = !player.dead`, `hostile = true`.
- navigation for this enemy: `safe_zones` (world list) and `spawn_area` (the area record it spawned from; null
  for an enemy placed without a camp → no territory, then `may_engage = distance <= aggro`).
- `line_of_sight(from, to)` (§4.3).
- `show_damage_number(...)`.
- Damage router + attack activations shared with the player and weapon (one per world).
Suggested Godot wiring: the spawner sets `enemy_script.spawn_area` / `safe_zones` right after instancing,
and the enemy finds the player and router through an autoload/world service (architect's call).

Fixed-step order in Phaser: world sim clock += dt → population update → scripts `_physics_process`
(enemy) → Arcade physics moves bodies → defeated-enemy cleanup. Godot: spawner in its own
`_physics_process` (or the world's), enemy script moves its body itself (`ArcadeMover.move`); order differences
of one step are acceptable.

---

## 9. Centre vs feet (every place that assumes the Phaser body position is the centre)

Phaser body position = sprite centre; the worm's feet are centre + (0, 22), the player's are centre +
(0, 27.56). In Godot both roots are at the feet. Define
`centre(n) = n.global_position − n.get_meta("depth_anchor") * n.scale` and **do all enemy AI maths in
centre space** to keep parity (feet-to-feet distances would differ by up to 5.56 px vertically and tilt
every direction):
1. Spawn point (`randomPointInPerimeter(stay)`) is a centre → root at `point + (0, 22)` (§3.2).
2. Safe-zone rejection of spawn points tests the centre.
3. Seeding/spawning test the **player centre** against the pursue perimeter.
4. `origin` for distance, `dir`, `distance <= 38 / 49.4 / 51.3 / 220 / 330`: centre (enemy) to centre (player).
5. Territory `home_distance(stay, enemy centre)`, `ARRIVED 18`, `last_seen = player centre`, `move_to`
   targets (stay centre, last seen) are centre positions.
6. Safe-zone containment / push-out in the AI uses the enemy centre.
7. Line-of-sight ray: centre → centre.
8. Attack `impact.x/y` = enemy centre; knock direction centre → centre.
9. AttackShape circle r 51.3 is centred on the body centre (Godot (0, −22)); hurtbox rect 36×26 at centre+(0,9).
10. Damage number x = enemy centre x; defeat notification x/y (loot position) = centre.
11. Facing is chosen from velocity only (origin-independent) — no change needed.

---

## 10. Porting checklist / pitfalls
- Script order inside `_physics_process` matters (flash update before the dead check; stun before AI;
  territory before attack resolution; facing/anim skipped while attacking).
- Use the enemy's own `sim_ms`, not engine time, for every timer (stun, flash, cooldown, impact, search,
  sight throttle, 800 ms despawn).
- `velocity` persists between steps (wander keeps its direction; after returning home the return
  velocity carries over) — read it back from the body, do not reset each step.
- `alerted` has two emit points: the territory "engaged" line (sets `ai_state = "chase"` right after
  emitting, so the AI-loop check below it cannot fire again that step) and the AI-loop line (idle/wander →
  chase/flee, e.g. a safe-zone push-out `flee`). Keep both, in that order.
- Ignore the `hitbox-activated`/`hitbox-deactivated` animation events for now (§2.1).
- Godot `CharacterBody2D` does not push other bodies; Arcade separated dynamic bodies (player and worm
  shove each other slightly). Acceptable trial difference; mention to the owner if contact feels sticky.
- Random: use `randf()` for every `Math.random()`; keep one call per check (do not pre-roll).

---

# Part 2 — ranged enemies, spiders, slow, impact effects, legacy spawning (ported 2026-10-05)

Read from the Phaser code on `feat/godot-migration` (2026-10-05). Same conventions as part 1:
`file:line` refs are to `src/game/...`, "centre" is the old Phaser body position, every distance is
centre to centre. Godot targets: `game.enemy` stays `res://game/scripts/enemy.gd`; `game.projectile`
→ `res://game/scripts/projectile.gd` (node `ProjectileScript`); helpers in `res://game/enemy/`:
`enemy_projectiles.gd` (the world's `spawnEnemyProjectile`), `slime_spider_ai.gd`,
`spider_web_port.gd` (the world's `world.spider-web` port and `applyWeb`, see
[matron.md](./matron.md) §5) and `enemy_population.gd` (legacy spawning, `slowEnemiesNear`).

## 11. Enemy types the worlds spawn

Every `enemy-spawn` world area and every legacy `metadata.spawns` table (read from
`content/scenes/authored/worlds/*.scene.json`):

| World | Spawner | Types |
|---|---|---|
| level-1 | areas `level-1-starter-camp`, `-webwood`, `-autumn-grove`, `-south-meadow` | worm-swordsman (3); slime-spider (3); worm-archer (2) + worm-brawler (2); worm-brawler (2) + slime-spider (1) |
| gloop-forest | areas `gloop-orb-weavers-north-east`, `-south-west`, `-south` (2 each, every 6000 ms) | orb-weaver |
| crystal-caverns | legacy `metadata.spawns` (§18): radius 200–500, every 1500 ms, max 16 | worm-brawler 30, worm-swordsman 40, worm-archer 30 |
| playground (dev) | area `playground-enemy-pen` (every 4000 ms, max 6) | worm-brawler (3), worm-archer (1), slime-spider (1), orb-weaver (2) |
| meadow-crossing, cole, girls, tiktok (dev) | areas | slime-spider, worm-archer, worm-brawler, worm-swordsman |
| icege (dev) | legacy `metadata.spawns` | worm-swordsman |

gloop-forest also has `metadata.spawns`, unused because it has spawn areas
(`AuthoredEnemyPopulationController.ts:88, 127`). So five types: **worm-swordsman** (part 1),
**worm-archer**, **worm-brawler**, **slime-spider**, **orb-weaver**, all `game.enemy` with these
script properties (`characters/<type>.scene.json`, node `script`; `projectileSpeed`, `fleeRange`,
`behavior` and `isRanged` live in `attributes`):

| | archer | brawler | slime spider | orb weaver |
|---|---|---|---|---|
| maxHealth | 40 | 55 | 40 | 70 |
| targetingRadius (aggro) | 280 | 240 | 280 | 300 |
| attackRange | 220 | 34 | 220 | 240 |
| movementSpeed | 80 | 130 | 80 | 72 |
| attackCooldownMs | 2200 | 1100 | 2200 | 2000 |
| wanderSpeed | 30 | 50 | 30 | 28 |
| attackWindupMs / RecoveryMs | 600 / 350 | 250 / 250 | 600 / 350 | 650 / 350 |
| contactDamage | 22 (unused, ranged) | 52 | 22 (unused) | 26 (unused) |
| knockbackStrength / Resist | 180 / 0 | 340 / 0.1 | 180 / 0 | 200 / 0.3 |
| fleeRange | 120 | — | 120 | 140 |
| behavior | standard | standard | `slime-spider` | `slime-spider` |
| projectileSpeed | 180 | — | 180 | 200 |
| projectile | `worm-arrow`, damage 22 | — | `spider-web`, damage 50, stickMs 1000 | `spider-web`, damage 30, stickMs 1300 |
| impactEffect | — | `enemy-worm-brawler-hit`, distance 22 | — | — |
| depthAnchor | (0, 22) | (0, 22) | (0, 12) | (0, 15) |
| damageRule | priority 0, ×1 | same | same | same |

Their SFX wiring is the worm's (`damaged` → HurtSfx, `defeated` → DeathSfx, `alerted` → AlertSfx,
`attack_started` → WindupSfx: archer bow-draw, brawler worm-windup; the spiders have no WindupSfx).
`rewards` stay unused (loot is OUT, part 1 §0).

## 12. Ranged attack and enemy projectiles

### 12.1 Projectile configuration (`EnemyScript.ts:900-908`)
`projectile` counts only when it is a Dictionary with a numeric `damage` and at least one of a
string `projectileId` / `assetId`; `stickMs` counts only when it is a number > 0. Otherwise the enemy
is melee. `attack_started` carries `ranged = (that configuration exists)` (`:745`).

### 12.2 Firing (`EnemyScript.ts:748-770`)
The ranged attack is the common attack of part 1 §5 (same cooldown, windup, finish
`min(2000, max(windup + recovery, clip) + 250)`, attack area toggle, cancel rules). At the impact
moment (`now >= attack_impact_at`, once) `resolve_attack` does, in order:
```
attack_resolved = true
if no activation, attack area or router: return
if target not active or not hostile: return
if projectile configuration:
    fire {position: enemy centre now, direction: attack_direction (set at begin_attack, unit),
          speed: attributes.projectileSpeed (fallback 200), damage: projectile.damage,
          knockback_strength: attributes.knockbackStrength (fallback 0),
          projectile_id, asset_id, stick_ms (when > 0)}
    return                                  # no reach check: the flight decides
(melee as part 1 §5.3)
```
The aim is where the player was when the attack **started** (`begin_attack` stores the unit
direction); the origin is where the enemy stands at the impact moment.

### 12.3 Spawning the projectile (`UniversalSceneWorldController.spawnEnemyProjectile`, `:2087-2114`)
```
projectile_id missing -> error (Phaser throws)
mount scene "projectile.<projectile_id>" with its root at `position` (projectile roots have no depth anchor)
script = its ProjectileScript (missing -> error)
script.launch(direction, speed, {
    source: the shooter, damage, knockback_strength,
    weapon_id: projectile_id, weapon_tags: ["enemy", "projectile"], damage_types: ["physical"],
    target_areas: [the player's hurtbox],
    effects: [{effect_id: "web", potency: stick_ms}] when stick_ms > 0 })
```
The world disposes a projectile once it is no longer `launched` or its root is gone
(`finishExpiredProjectiles`, `:2116-2122`); the script frees its own root on expiry (§12.4), so
nothing else is needed in Godot.

### 12.4 `game.projectile` (`features/scripts/ProjectileScript.ts`)
Properties (`projectiles/*.scene.json`, node `ProjectileScript`): `projectileId` (fallback
`"unknown-projectile"`), `body` (CharacterBody2D root), `visual`, `animation`, `attackArea`,
`defaultSpeed` (`max(0, v)`, fallback 0), `lifetimeMs` (`max(0, v)`, fallback 0),
`rotateToVelocity` (true only when `=== true`). Signals `launched {projectileId}`, `expired
{projectileId}`; handler `on_area_entered` ← `AttackArea.area_entered`.

State: `age_ms = 0`, `launched = false`, the damage payload, `activation_id`.

- `launch(direction, speed = default_speed, damage = null)` (`:80-98`): error unless the speed is
  finite and ≥ 0 and the direction non-zero. `body.velocity = unit(direction) × speed`; with
  `rotate_to_velocity` the **Visual** (not the body) gets `rotation = atan2(vy, vx)`; `age = 0`,
  `launched = true`, store the payload; with a payload begin an attack activation for
  `(payload source, [attack_area])`; emit `launched` (→ ReleaseSfx / SpitSfx).
- `_physics_process` (`:63-71`, scripts run before Arcade moves the body): not launched → nothing;
  `age += delta`; the body touched a blocker in the last physics step (`blockingContacts`) →
  `expire()`; else `age >= lifetime_ms` → `expire()`. Arcade then moves the body by its velocity
  against its collision mask.
- `on_area_entered(area)` (`:108-133`): ignore unless launched with a payload, an activation, a
  router and an attack area; ignore areas not in `target_areas` (enemy hurtboxes, the shooter's
  own included, are skipped and the projectile flies on). Route one request:
  `{activation, source, attack_area, target_area: area, weapon_id (payload, else projectile_id),
  weapon_tags (payload, else ["projectile"]), damage_types (payload, else ["physical"]),
  base_damage: payload damage, effects: [knockback, potency knockback_strength, when > 0] + payload
  effects, impact: {position (0, 0), knock: unit(body velocity) (length 1 when zero)}}`, then
  `expire()` **whatever the result** (a dodged or i-framed hit still consumes the projectile).
- `expire()` (`:100-106`): only when launched: `launched = false`, end the activation, emit
  `expired` (→ the arrow's detached ThunkSfx), free the root.
- `_exit_tree` (`:73-78`): `launched = false`, end the activation, drop the payload.
The scenes' `impact` clip is never played.

### 12.5 Projectile scenes
| | `projectile.worm-arrow` | `projectile.spider-web` |
|---|---|---|
| root | CharacterBody2D `WormArrow`, layer 256 (projectile), mask 1 (world), `collideWorldBounds` false | `SpiderWeb`, same |
| body / attack shape | rectangle 16 × 10 | circle r 7 |
| AttackArea | layer 16 (hitbox), mask 8 (hurtbox), monitoring on | same |
| clips | `move` (autoplay, loop), `impact` | `move` 6 fps ping-pong frames 0 → 4 → 6, `impact` |
| script | defaultSpeed 180, lifetimeMs 3000, rotateToVelocity | defaultSpeed 170, lifetimeMs 3000, rotateToVelocity |
| SFX | ReleaseSfx ← `launched`; ThunkSfx (detached) ← `expired` | SpitSfx ← `launched` |

Water (layer 1024) is not in the mask: projectiles fly over water; walls, trees, houses, rocks and
stakes (layer 1) stop them. The speed always comes from the shooter (`projectileSpeed`), never from
`defaultSpeed`.

### 12.6 The web effect on the player (player side)
`PlayerHealthController.publishDamageFeedback` (`features/player/PlayerHealthController.ts:117-135`):
after the hit presentation and unless the hit was lethal, an applied `web` effect with potency > 0
calls `applyWeb(potency)` **before** the knockback. `WorldScene.applyWeb(ms)`
(`scenes/WorldScene.ts:1758-1771`) applies the `sticky` status for `ms` (rooted: no walking, no
jump/dodge/teleport; attacks and the lash still work; `systems/StatusEffects.ts:98`,
`features/player/PlayerController.ts:72-77`) and, unless already stuck, spawns
`effect.spider-web-cover` following the player. The knockback still plays first (movement
suppression wins over the root, `PlayerController.ts:57-60`). This is `player.gd`'s job (abilities
spec 13.9 / 19.3); the enemy side only routes the effect. Godot fallback until the player has
`apply_web(ms)`: `spider_web_port.gd` shows the web cover at the player for an accepted web hit and
skips the root.

### 12.7 Derived numbers (player defense 3)
- Archer: an arrow hits for max(1, 22 − 3) = **19**, knockback 180; fired 600 ms after the attack
  starts; the sequence ends at +min(2000, max(950, 375) + 250) = **+1200 ms** (side clip 375 ms, up
  500 ms); the next shot ≥ 2200 ms after the previous start. Speed 180 for 3000 ms = 540 px of flight.
- Slime spider: a web hits for **47**, knockback 180, web 1000 ms. Orb weaver: **27**, knockback 200,
  web 1300 ms, speed 200, windup 650 → finish +1250 ms.
- Brawler: melee 52 → **49**, knockback 340; impact at +250, finish +min(2000, max(500, clip) + 250).

## 13. `fleeRange` with the standard AI (`EnemyAI.ts:275-335`, `EnemyScript.ts:439-443`)
Ported with the trial's AI (dormant for the worm). With `fleeRange` > 0 (archer 120):
- chase: beyond aggro × 1.5 → wander; **then** `distance < fleeRange` → flee (velocity kept); then in
  reach (`distance <= attackRange`) → velocity 0, attack; else run at the player.
- flee: `distance >= fleeRange` → velocity 0, **attack**; beyond aggro × 1.5 → wander; else run
  straight away from the player at `movementSpeed`.
- attack: beyond attackRange × 1.3 (archer 286) → chase; else hold and request the attack. The
  attack state never flees by itself.
- When a sequence finishes, the AI state becomes flee when `fleeRange > 0` and `distance <
  fleeRange`, else chase.
So an archer keeps 120–286 px from the player and shoots whenever the cooldown allows.

## 14. Slime-spider AI (`enemies/ai/SlimeSpiderAI.ts`)
Used when `attributes.behavior == "slime-spider"` (slime spider, orb weaver, the Matron): after the
safe-zone push (part 1 §4.4, unchanged) `runState` hands every state to `runSlimeSpiderState`
(`EnemyAI.ts:116-123`). `preferred = max(1, fleeRange ?? attackRange × 0.55)` (`:33-35`: an absent
`fleeRange` uses 0.55 × range, a present 0 gives 1). `notices` = `may_engage` (part 1 §4.4).

| state | behaviour |
|---|---|
| idle (`:37-43`) | velocity 0; notices → chase; `randf() < 0.008` → wander; else continue |
| wander (`:45-63`) | notices → velocity 0, chase; `randf() < 0.02` → velocity = (cos a, sin a) × wanderSpeed with `a = randf() × TAU`; `randf() < 0.004` → velocity 0, idle; else continue |
| chase (`:65-78`) | beyond aggro × 1.5 → wander; `distance <= attackRange`: `distance < preferred` → flee (velocity kept), else velocity 0, attack; otherwise orbit (0.86, 0.52, movementSpeed), continue |
| flee (`:80-91`) | beyond aggro × 1.5 → wander; `distance >= preferred` → attack when `distance <= attackRange`, else chase (velocity kept); otherwise orbit (−0.92, 0.44, movementSpeed × 1.08), continue |
| attack (`:93-100`) | beyond attackRange × 1.3 → chase; `distance < preferred × 0.72` → flee; else velocity 0, request the attack, continue |
| dead | continue |

**Orbit** (`:102-120`): `d` = unit direction to the player (the attack direction when the distance
is 0); `sign = 1 if sin(centre.x × 0.017 + centre.y × 0.013) >= 0 else −1`; `tangent = (−d.y × sign,
d.x × sign)`; `v = d × radial + tangent × lateral`; velocity = `unit(v) × speed` (length 1 when 0).
A spider spirals in toward the player, stops to spit between `preferred` and `attackRange`, and backs
off spiralling when the player comes closer than `preferred` (closer than 0.72 × preferred while it
holds to spit). After a sequence finishes the base rule of §13 applies (flee when closer than
`fleeRange`, else chase).

## 15. Slow (`EnemyScript.ts:205-209, 365-367, 425-426, 449, 486-487, 934-944`)
`apply_slow(multiplier, duration_ms)`: ignored for `rank == "boss"`, a defeated enemy, a multiplier
outside (0, 1) or a duration ≤ 0. Else `until = now + duration`; the multiplier is replaced when the
old slow has run out (`now >= slowed_until`) or the new one is stronger (`multiplier <=
slow_multiplier`); `slowed_until = max(slowed_until, until)`. `is_slowed() = now < slowed_until`.
Per step: `slow_written = applied_slow; applied_slow = 1` first thing (the defeated, stun, no-target
and arena paths write unslowed velocities). The territory walk writes `walk × applied_slow` with
`applied_slow = slow multiplier while slowed, else 1` (facing and clip use the unslowed walk). The AI
path reads the body velocity back divided by `slow_written` (the AI sees its own unslowed speed),
runs, then writes `velocity × applied_slow` (same rule); facing and clip use the unslowed velocity.
Caller: the goo trail (`WorldScene.ts:901` → `slowEnemiesNear(points, 26, 0.55, 400)`,
`UniversalSceneWorldController.ts:1236-1249`: every live **ordinary** enemy whose centre is within
the radius of any point; returns the count). Godot: `EnemyPopulation.slow_enemies_near(points,
radius, multiplier, duration_ms)`; the trail itself is the player's (abilities spec 12, OUT).

## 16. Impact effect (`EnemyScript.ts:792-806, 696`)
`impactEffect = {effectId, distance}` (worm brawler: `enemy-worm-brawler-hit`, 22). After a melee
impact whose route was **accepted with damage > 0**, and after an immediate attack that hit unless
the caller passed `impactEffect: false` (Fatty's landing, the Matron's volley): spawn
`effect.<effectId>` (direction `right`) with its root at `centre + attack_direction × distance`
(`distance` 0 when not a finite number; a missing or non-string `effectId` spawns nothing). The
brawler's effect: 3 frames at 12 fps (0.25 s), `hit-punch` sound.

## 17. Effect immunities and damage rules
Every enemy's `damageRule` goes to the router as authored (part 1 §6.1); the resolver
(`combat/DamageResolver.ts`; Godot `damage_resolver.gd`, complete since the Fatty port) handles
`acceptedSources`, `blockedWeaponTags`, `damageTypeMultipliers` and `effectResponses` (`immune` →
the effect is rejected with reason `immune`; `multiplier`). The base reaction (part 1 §6.2) then uses
strength 0 for an immune knockback (no shove, stun 320 ms only). The world's ordinary types have no
immunities; the bosses do (Fatty, the Matron: `knockback` immune). `attributes.effectImmunities` is
informational only (nothing reads it at run time).

## 18. Legacy player-relative spawning (`AuthoredEnemyPopulationController.ts`, `features/combat/CombatController.ts:117-138, 269-274`)
Only when the world has **no** enemy-spawn areas and has `metadata.spawns` (world definition
`metadata`): `{enemies: [{type, weight, maxAlive?}], radius: {min, max}, intervalMs, maxPopulation,
safeZones?}`. Spawn-point safe zones = the enemy-safe-zone areas + `spawns.safeZones`; enemy
navigation keeps the area safe zones (`scenes/WorldScene.ts:1352, 2327`).
- seed: `min(8, spawns.maxPopulation ?? 8)` spawns at once (with areas that count caps each area,
  part 1 §3.2).
- update, each fixed step: drop gone and dead members; a member **without** an area farther than
  `despawnRadius = radius.max + 300` from the player centre is removed (freed); then when `now >
  last_spawn_at + intervalMs` and fewer than `maxPopulation` live members: spawn one, `last_spawn_at
  = now` (also when the spawn failed).
- spawn one: candidates = table entries under their `maxAlive` (live members of that type without an
  area), weighted pick as in part 1; spawn point: up to 32 tries of `angle = randf() × TAU`, `dist =
  min + randf() × (max − min)`, `(clamp(player.x + cos × dist, 40, W − 40), clamp(player.y + sin ×
  dist, 40, H − 40))`, rejected inside a safe zone; the enemy gets no spawn area (no territory,
  `may_engage = distance <= aggro`) and the area safe zones.

crystal-caverns: 8 enemies around the spawn at load, then one every 1.5 s up to 16, removed beyond
800 px from the player.

## 19. Godot notes and deviations
- **Projectile source.** Phaser's request source is the shooter's id string, still valid after the
  shooter died; the Godot router needs a live Object, so the projectile script itself is the
  activation and request source (it lives exactly as long as it can hit). The payload keeps
  `source_node_id`.
- **Projectile step order.** `projectile.gd` reads its age from SimClock (`now − launched_at`),
  expires on a blocking contact recorded by its last move (`ArcadeMover.move` returned true) or at
  the lifetime, else moves. `area_entered` arrives at the start of the next physics tick (Godot
  flushes area queries before the scripts): a hit lands at most one step later than in Phaser. A
  projectile spawned during a step first moves in the next one (±1 step of flight).
- **World bounds.** `collideWorldBounds` false: the projectile ignores the runtime `WorldBounds`
  body (a collision exception) and leaves the world until its lifetime ends.
- **Warm-up.** An enemy warms its projectile scene and impact effect in `_ready`; the population
  warms `character.<type>` for every type it may spawn when it seeds (Phaser loads all media
  before the world starts).
- **Spawn timers.** Phaser's world simulation time starts at 0 when a world loads; SimClock keeps
  running across travel, so `EnemyPopulation` measures `last_spawn_at` (camps and legacy) from its
  `setup` time instead of 0.
- **Trial filter.** `main.gd` sets `EnemyPopulation.allowed_types = ["worm-swordsman"]` (the world
  session's file); emptied, every type above spawns. The tests clear it.
