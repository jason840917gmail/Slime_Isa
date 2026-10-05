# Enemy spec — worm swordsman, camp spawning (Phase 0 trial)

Source of truth: the Phaser code at `feat/godot-migration` (commit 41904a0). Everything below is read
from code; file:line references are to `src/game/...`. A GDScript engineer should be able to port this
without opening the TypeScript.

Godot targets (from the conventions): script `game.enemy` → `res://game/scripts/enemy.gd` (node name
`EnemyScript`, a child `Node` of the `CharacterBody2D` root); scene `character.worm-swordsman` →
`res://generated/scenes/characters/worm-swordsman.tscn`; world areas `game.world-area` →
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
| Ranged / projectile enemies | `EnemyScript.ts:754-770`, `900-908`, `UniversalSceneWorldController.spawnEnemyProjectile` | `projectile` property, `projectileSpeed`, `stickMs` (spider web). Worm archer, slime spider. |
| `fleeRange` keep-distance behaviour | `EnemyAI.ts:284-286`, `317-335`; `EnemyScript.ts:441-442` | Archers/spiders. Worm has no `fleeRange` (but see safe-zone flee, which IS in scope). |
| Slime spider AI | `enemies/ai/SlimeSpiderAI.ts` | `attributes.behavior == "slime-spider"`: orbit/approach, keep distance, retreat, fire. |
| Fatty / Matron bosses, boss arena leash, `arenaRecoveryMs`, telegraphs, camera shake, `routeImmediateAttack`, `attackAreaReach` overrides | `FattyScript.ts`, `MatronScript.ts`, `EnemyScript.ts:392-409, 598-610, 619, 675-716`, `features/effects/AttackTelegraphs.ts` | Ground telegraphs are **only** used by bosses; the worm has no telegraph besides its windup clip + SFX. |
| `impactEffect` spawn on hit | `EnemyScript.ts:797-806` | Worm brawler only (`effect.enemy.worm-brawler-hit`). Worm swordsman has none. |
| Slow (goo trail) | `EnemyScript.ts:205-209, 425-426, 449, 486-487, 934-944` | `applySlow(multiplier, durationMs)`; treat slow factor as 1 in the trial. |
| Effect immunities / `damageRule.effectResponses`, `acceptedSources`, `blockedWeaponTags` | `combat/DamageResolver.ts` | Worm rule is `{priority:0, damageMultiplier:1}` only. |
| Elevation routing, `DamageRouter` reach gate | docs/ELEVATION.md | Not ported (elevation rejected; this router has no gate). |
| Occlusion silhouette for enemies | `UniversalSceneWorldController.registerCharacterOcclusion` | Dropped by plan. |
| Dev overlay attack areas | `EnemyScript.debugAttackAreas` | Debug only. |
| Legacy player-relative spawning, `despawnRadius` | `AuthoredEnemyPopulationController.ts:96-98, 115-121, 140-143, 216-224` | Only when a world has no spawn areas but has `metadata.spawns`; level-1 has spawn areas and no `spawns`. |
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
4. Instantiate scene `character.<type>` (via `res://generated/scene_index.json`) at the point
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
