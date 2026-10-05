# Player spec for the Godot Phase 0 trial

Sources read (all read-only): `src/game/features/scripts/PlayerScript.ts`, `CharacterScript.ts`,
`src/game/features/player/*` (`PlayerController`, `PlayerAbilityController/Service/Definitions/Presentation`,
`PlayerHealthController/Service`, `PlayerNodePorts`, `PlayerServicePorts`, `PlayerInputActions`, `PointerAim`, `WheelStepper`),
`src/game/scenes/WorldScene.ts` (the code that actually drives the player each step),
`src/game/features/world/UniversalSceneWorldController.ts` (mounting, clocks), `src/game/features/combat/{DamageRouter,DamageResolver,AttackActivation,CombatController}.ts`,
`src/game/systems/{PlayerStats,StatusEffects}.ts`, `src/game/core/GameState.ts`, `src/game/runtime/scene/input/*`,
`src/game/infrastructure/scenes/PhaserSceneTreeHost.ts`, `src/game/infrastructure/scenes/compatibility/LegacyPlayerAbilityPresentation.ts`,
`src/game/features/feel/{GameFeel,SquashStretch,ParticlePresets,sharedFeel}.ts`, `src/game/content/game-constants.json`,
`src/game/content/scenes/authored/characters/player-slime.scene.json`.

Line numbers are `file:line` in the current `feat/godot-migration` tree.

Legend: **[IN]** in trial scope, **[OUT]** exists in Phaser, not in the trial (listed so later phases know), **[CENTRE]** behaviour depends on the Phaser body position being the sprite centre (Godot root is the feet; see section 11), **[QUIRK]** the Phaser build behaves differently from what its code/comments intend; a decision is needed.

---

## 0. Ownership map in Phaser (who does what)

The player is split over several objects. The Godot port can collapse them (one `player.gd` on the `PlayerScript` node plus maybe a small health helper), but the behaviour below must be kept.

| Phaser object | Role |
|---|---|
| `PlayerScript` (ScriptNode `game.player`, node `PlayerScript` in the scene) | Input capture and buffer, its own simulation clock, roll/dodge/knockback timers, sets body velocity, plays clips through the AnimationPlayer, damage-receiver facade, emits the scene signals |
| `PlayerController` (created by `WorldScene`) | Per-step movement: speed choice (walk/sprint), facing vector, sprite flip, which walk clip; starts the dodge roll |
| `WorldScene.updateGameplay` | The per-step state machine (dead / asleep / suppressed / action-locked / actions / move); action dispatch order; animation priority gate; hit and death presentation |
| `PlayerAbilityController` + `PlayerAbilityService` | Dodge "ability" rules: learned, cooldown, busy, action-locked |
| `PlayerHealthController` + `PlayerHealthService` | HP pipeline: hit i-frames, defense mitigation, death, knockback request, respawn |
| `GameState` (`core/GameState.ts`) | Stores `hp`, `maxHp`; emits `player.damage`, `hp.changed`, `player.death`, `player.respawn` |
| `CombatController` | Turns an attack press into a weapon swing (direction, damage payload), locks actions during the swing |
| `GameFeel`, `SquashStretch`, `ParticlePresets` | Shake/hit-stop, jelly squash, particles |

---

## 1. Scene contract (`characters/player-slime.scene.json`) [IN]

Root `body` = `CharacterBody2D` named **`PlayerSlime`**.

| Node (name) | Type | Properties (JSON) | Notes for Godot |
|---|---|---|---|
| `PlayerSlime` | CharacterBody2D | `collisionLayer: 2` (bit 2 = layer 2 `player`), `collisionMask: 1157` (= 1+4+128+1024 → layers 1 `world`, 3 `enemy`, 8 `npc`, 11 `water`), `collideWorldBounds: true` (dropped by converter, see §5.6), `depthAnchor: [0, 27.560000000000002]` | Root re-anchored to the feet; `metadata/depth_anchor = Vector2(0, 27.56)` |
| `BodyShape` | CollisionShape2D | rect **30 × 26** (`player-slime.body-shape`), position `[0, 14.56]` | After re-anchoring: position `(0, -13)`; rect spans y −26..0 (bottom edge = feet) |
| `Visual` | Sprite2D | texture `character.player.slime` (sheet 2048², 8×8 frames of 256²), `frame 0`, `origin [0.5,0.5]`, `scale [0.28125, 0.28125]` (→ 72 px), `position [0,0]` | After re-anchoring: position `(0, -27.56)`; `offset (-128,-128)`, `centered=false`, NEAREST |
| `DamageArea` | Area2D | layer 8 (= layer 4 `hurtbox`), mask 16 (= layer 5 `hitbox`), `monitoring false`, `monitorable true` | The player's hurtbox |
| `DamageShape` | CollisionShape2D | same 30×26 rect at `[0,14.56]` | → `(0,-13)` |
| `PickupArea` | Area2D | layer 32 (`pickup-seeker`), mask 64 (`pickup`), monitoring+monitorable | **[OUT]** pickups; but see signals |
| `PickupShape` | CollisionShape2D | same rect | |
| `Animation` | AnimationPlayer | library `character.player.slime.animations`, `domain: physics`, `autoplay: "idle"` | `callback_mode_process = PHYSICS` |
| `PlayerScript` | ScriptNode `game.player` | `body→body`, `visual→visual`, `animation→animation`, `damageArea→damage-area`, `playerName: "bob"` | Converter target `res://game/scripts/player.gd`; exports `body: CharacterBody2D`, `visual: Sprite2D`, `animation: AnimationPlayer`, `damage_area: Area2D`, `player_name: String` |
| `HurtSfx` | AudioStreamPlayer | `sfx.player.hurt` (3 variants), `pitchRandomness 0.06`, `minIntervalMs 120` | |
| `DeathSfx` | AudioStreamPlayer | `sfx.player.death` | |

Connections (must resolve or Godot logs errors):

| Source.signal | Target.handler | Godot |
|---|---|---|
| `PickupArea.area_entered` | `PlayerScript.on_pickup_area_entered` | built-in signal → `func on_pickup_area_entered(area: Node) -> void` must exist (stub in the trial, **[OUT]** pickups) |
| `PlayerScript.damaged` | `HurtSfx.play` | `signal damaged(commit: Dictionary)` → `play_cue` |
| `PlayerScript.defeated` | `DeathSfx.play` | `signal defeated(payload: Dictionary)` → `play_cue` |

Other `PlayerScript` signals emitted in Phaser but not connected in the scene: `health_changed {hp, maxHp}` and `damage_feedback (commit)`. Declare them too (one Dictionary argument each).

### 1.1 Animation clips (all keyed on `../Visual` `frame`, discrete)

| Clip | fps | duration s | loop | frames | Used in trial? |
|---|---|---|---|---|---|
| `idle` | 6 | 1.1667 | yes | 0,2,1,4,1,4,2 | **IN** (standing still, after swing, respawn) |
| `walk` | 10 | 0.8 | yes | 9,10,11,12,13,14,13,12 | **IN** (moving) |
| `hop` | 11 | 0.8182 | yes | 17..23,22,21 | intended for moving down, see [QUIRK] §4.3 |
| `stretch` | 12 | 0.6667 | yes | 32..39 | intended for moving up, see [QUIRK] §4.3 |
| `roll` | 14 | 0.1429 | yes | 43,44 | **IN** dodge roll |
| `attack-1` | 12 | 0.42 | no (`loopMode: wrap`) | 48 (single frame) | **IN** basic sword swing (weapon's `characterActionId` is `attack-1` for every direction) |
| `knockback` | 8 | 0.125 | no | 24 | **IN** when knocked back |
| `die` | 8 | 1.0 | no | 26..31,31,31 | **IN** death |
| `squash` 12fps 0.667 loop, `trick` 0.8, `teleport` 0.667, `eat` 0.167, `attack-2` 0.5, `attack-3` 0.5, `hurt` 0.214 (never played by player code), `charge` 0.667 loop, `cast` 0.333, `doze` 1.0, `sleep` 2.0 loop | | | | | **OUT** |

Phaser's play rule (`PlayerNodePorts.ts:212-216`): `play(id, force)` returns false if the clip does not exist; otherwise restarts only when `force` or the current clip differs. Godot `AnimationPlayer.play()` already ignores a repeated call for the playing clip; for `force` use `stop(); play(id)` (or `play(id); seek(0, true)`).

Non-looping clips hold their last frame when they end (same in Godot).

---

## 2. Values and where they come from

| Value | Number | Source |
|---|---|---|
| Walk speed | 200 px/s | `game-constants.json` `character.player.movement.baseSpeed` |
| Sprint speed | 300 px/s (+ `gameState.boostBonus`, 0 in a new run, **[OUT]** boost items) | `movement.boostSpeed` |
| Speed cap | 480 px/s | `movement.movementSpeedCap` |
| Dodge speed | 380 px/s | `movement.dodgeSpeed` |
| Dodge roll duration | 500 ms | `movement.dodgeDurationMs` |
| Dodge i-frames | 400 ms (first part of the roll) | `movement.dodgeInvulnerabilityMs` |
| Dodge cooldown after roll | 250 ms → ability cooldown = 500 + 250 = **750 ms from roll start** | `movement.dodgeCooldownMs`; sum in `PlayerAbilityDefinitions.ts:214` |
| Hit i-frames | 500 ms | `character.player.hitInvulnerabilityMs` |
| Max HP | 100 (+10 per Goo Heart, **[OUT]**) | `character.player.stats.maxHp`, `gooHeart.maxHpBonus` |
| Defense | 3 | `stats.defense` |
| Damage-taken multiplier | 1 | literal `PlayerStats.ts:71` |
| Attack stat | 12 (swing damage × 12/10) | `stats.attack` |
| Crit chance / multiplier | 0.05 / 1.75 | `stats.critChance`, `stats.critMultiplier` |
| Input buffer | 150 ms | `input.bufferMs` |
| Wheel step lock | 150 ms | `input.weaponWheelStepLockMs` (**[OUT]** weapon wheel) |
| Player knockback duration | **160 ms** | literal `PlayerHealthController.ts:134` (and :172) |
| Fallback knockback strength (direct `applyDamage` path only) | 220 px/s | literal `PlayerHealthController.ts:171` |
| Knockback strength from an enemy hit | the `knockback` effect potency of the enemy's damage request (enemy scene `attributes.knockbackStrength`; worm swordsman `enemy-types.json` `ai.knockbackStrength = 260`) | enemy spec |
| Pointer dead zone | 16 px | literal `PointerAim.ts:2` (`POINTER_DEAD_ZONE_PX`) |
| Aim origin rise | 28 px | literal `WorldScene.ts:149` (`SLIME_CENTER_RISE_PX`) [CENTRE][QUIRK] |
| Hit flash | colour `0xff6f88`, 120 ms | literal `WorldScene.ts:1912-1913` |
| Death → defeat screen/respawn delay | 1400 ms | literal `WorldScene.ts:1932` |
| Move-start squash idle threshold | 150 ms | literal `WorldScene.ts:908` |
| Fixed step | 1/60 s, max 5 catch-up steps per frame | `PhaserSceneTreeHost.ts:3-4` |
| Feel presets (shake/hit-stop) | §8 | `GameFeel.ts:35-51` (presentation literals, deliberately not in constants) |
| Squash presets | §8 | `SquashStretch.ts:122-133` |
| Default attack aim | `pointer` | `GameSettingsStore.ts:34` (settings `attackAim`, dev panel can switch to `facing`) |

`resolveMovementSpeed(base, flat=0, mult=1) = min(480, max(0, (base + flat) * max(0, mult)))` (`PlayerStats.ts:53-56`).

---

## 3. Clocks and step order [IN]

- Gameplay time is a **simulation clock in ms advanced only by fixed physics steps** (`PlayerScript.ts:93-95`, `UniversalSceneWorldController.ts:692-694`). It stands still while paused and during hit-stop. Every timer below (roll, i-frames, knockback, cooldowns, input buffer, action-animation unlock) uses it. In Godot: accumulate `delta * 1000.0` in `_physics_process` into one `sim_time_ms` (Phaser has two copies one step apart, `PlayerScript.simulationTimeMs` and the world's; the difference is not meaningful). Do **not** use `Time.get_ticks_msec()` for these.
- Per fixed step (`PhaserSceneTreeHost.ts:96-111`): 1) world clock += dt; `WorldScene.updateGameplay` (the player state machine, §4) 2) physics-domain animations advance 3) nodes' `_physics_process` (PlayerScript clock += dt) 4) velocities pushed to Arcade, physics step, positions/velocities read back 5) attacks/contacts resolved (damage to the player arrives here, §6). Godot equivalent: do the state machine at the top of `_physics_process`, then `ArcadeMover.move(body, delta)`.
- Input events are queued and dispatched once per rendered frame **before** the fixed steps (`drainInput`, `PhaserSceneTreeHost.ts:157-163`), sorted by timestamp.
- Rendering interpolates physics positions between steps (`presentation/PhysicsPresentation.ts`). Godot: enable 2D physics interpolation (`physics/common/physics_interpolation = true`) to get the same smoothness on >60 Hz screens.

---

## 4. Movement, facing, sprint, animation [IN]

### 4.1 Per-step state machine (`WorldScene.updateGameplay`, `WorldScene.ts:814-886`)

Runs once per fixed step unless the world is paused (modal) — when paused, velocity is zeroed (`stopMovingBodies`) and held input is cleared (`setPaused → playerScript.clearInput()`, `UniversalSceneWorldController.ts:789-793`).

```
now = sim_time
finishExpiredActionAnimation(now)               # [OUT] eat; unlocks action lock of playActionAnimation
(… status effects tick, energy regen [OUT], etc.)
if dead:            stop velocity; return        # no input is consumed while dead
if asleep:          [OUT] sleep; return
direction = movement keys (§4.2)
if movementSuppressed (knockback OR rolling):  return   # velocity is NOT touched: the roll/knockback velocity persists; presses stay buffered
if actionLocked (weapon swing / ability sequence): velocity = 0; return   # presses stay buffered
if eat-hold wheel open: [OUT]; velocity = 0; return
if handleActionInput() consumed an action: return       # this step does NOT call move(): velocity keeps last step's value for one step
squashOnMoveStart(direction)
playerController.move(direction)
```

`isMovementSuppressed()` = `sim < movementSuppressedUntilMs || sim < rollUntilMs` (`PlayerScript.ts:135-137`).

### 4.2 Movement input

`getMovementInput()` (`PlayerScript.ts:155-160`): `x = held(move_right) − held(move_left)`, `y = held(move_down) − held(move_up)` — 8 directions, opposite keys cancel. Godot: `Input.get_vector` is **not** equivalent unless deadzone/analog are irrelevant; use `Vector2(int(right)-int(left), int(down)-int(up))` from the script's own held set (see §7) so pause clears it.

### 4.3 `PlayerController.move(direction)` (`PlayerController.ts:57-101`)

```
if movementSuppressed: return
sprint = held(sprint)
base   = sprint ? boostSpeed(300) + boostBonus(0) : resolveMovementSpeed(baseSpeed 200)
speed  = resolveMovementSpeed(base, 0, statusSpeedMultiplier) * gulpFormSpeedMultiplier   # status mult = product of active statuses; 1 in the trial; Gulp form [OUT] = 1
if rooted (status 'sticky'):  velocity = 0; play 'idle'; return      # [OUT] spider web
velocity = normalize(direction) * speed   (zero when direction is zero)   # diagonals are not faster
if direction == 0:
    Visual.flip_h = false          # NOTE: standing still always faces the art's default (left)
    play 'idle'
    return
facing = normalize(direction)      # 8-way facing vector, initial (0,1)
Visual.flip_h = |x| >= |y| and x > 0
clip: if |y| > |x|: (y < 0 ? 'stretch' : 'hop') else 'walk'      # see QUIRK below
```

Sprint: hold Shift; no energy cost, no stamina, no animation change (same walk clips, faster). Works in any direction. Sprint has no effect on the dodge.

**[QUIRK] vertical clips are effectively never shown.** Two paths play clips each step: `PlayerScript.move()` plays `walk`/`idle` directly on the AnimationPlayer (`PlayerScript.ts:139-145`), then `PlayerController` asks `WorldScene.playAnimation('slime-hop'|'slime-stretch'|'slime-walk'|'slime-idle')`, which returns early when its own cached key is unchanged (`WorldScene.ts:1696-1698`). Result per step while moving vertically: step N plays `hop` (cache changes), step N+1 `PlayerScript.move` switches back to `walk` and the cached `slime-hop` is ignored. So the live game shows **`walk` for every moving direction** (with a one-step flash of `hop`/`stretch` when the direction class changes) and `idle` when still. Recommendation: port the live look (`walk` always) behind a bool `use_vertical_walk_clips := false`, and ask the owner; the intended rule is the one in the pseudo-code.

Other rules:
- `WorldScene.playAnimation(key, force)` gate (`WorldScene.ts:1690-1703`), applies to every clip request except those `PlayerScript` plays directly (`walk`/`idle` in move, `roll` in beginDodge): while dead only `die` passes; while `sim < playerKnockbackUntil` only `die` and a forced `knockback` pass; otherwise skip if same key and not forced. Key `slime-<clip>` → clip `<clip>`.
- `player.rotation` is forced to 0 everywhere (no-op in Godot).

### 4.4 Facing

- `facing: Vector2`, initial `(0, 1)` (down) (`PlayerController.ts:28`); restored from the save's cardinal `facing` ([OUT] saves).
- Updated by: moving (8-way, normalized), `face(dir)` (attack in pointer mode, dodge; `PlayerController.ts:104-108`: ignores zero, sets facing + flip with the same rule). Not updated by standing still, knockback, or the roll's motion.
- Consumers: attack direction (§9), dodge fallback direction (§5), save (cardinal: `|x| > |y|` → left/right, else up/down — note strict `>` here vs `>=` elsewhere).
- Flip rule everywhere: `flip_h = abs(x) >= abs(y) and x > 0` (exact tie such as (1,1) normalized → flips right).

### 4.5 Move-start squash (`WorldScene.ts:905-911`)

Only on the normal move path: if moving now, was not moving last step, and has been still for ≥150 ms (scene real time) → `squash.play('move-start')` (§8). When movement stops, `stillSince = now`.

---

## 5. Dodge roll [IN] (learned-gated; see trial note)

### 5.1 Input → rules

`handleActionInput` (`WorldScene.ts:1773-1829`) checks abilities in fixed order `jump, dodge, stretch-lash, squash-slam, teleport`, then `attack`, then `eat`; the **first consumed press wins and ends the step** (others stay buffered). Dodge = action `dodge` (key `1`).

`useAbility('dodge', stuck)` (`WorldScene.ts:1717-1735`):
```
aim    = pointerAim()                     # §9.1; undefined if pointer never seen or within 16 px
toward = aim ?? facing
if stuck (rooted): nothing (press is consumed, no feedback)       # [OUT] web
abilities.tryDodge(() => playerController.tryDodge(snapToCardinal(toward)))
```
**The dodge direction comes from the mouse pointer, snapped to 4 directions — not from the movement keys.** `snapToCardinal` (`PointerAim.ts:29-32`): `|x| >= |y|` → `(sign x, 0)` (x == 0 → +1), else `(0, sign y)`.

`tryDodge` rules (`PlayerAbilityController.ts:133-140`, `PlayerAbilityService.ts:324-340`), checked in this order:
1. `busy` — an ability sequence (jump/teleport/slam/lash, [OUT]) is running → rejected silently.
2. `locked` — `storyProgress.knowsAbility('dodge')` is false → "Not learned yet" red floating text at (centre.x, centre.y − 30) [CENTRE] + `player.action {anim:'ability-denied'}` → global `AbilityDenied` cue.
3. `cooldown` — `sim < cooldownUntil.dodge` → rejected **silently** (no cue, no text).
4. `action-locked` — weapon swing / action animation → denied cue.
5. `energy` — cost 0, never.
On success `cooldownUntil.dodge = sim + 750` (set before the roll itself; if the roll then fails the cooldown still runs — cannot happen through the key path because a suppressed player never reaches `handleActionInput`).

Trial note: dodge is taught by a Chapter 1 quest ([OUT] story). For the trial treat it as learned (e.g. `@export var dodge_learned := true`), otherwise key 1 only shows "Not learned yet".

### 5.2 Roll (`PlayerController.tryDodge`, `PlayerController.ts:111-133`; `PlayerScript.beginDodge`, `PlayerScript.ts:193-201`)

```
dir = given (cardinal) ; if zero → facing ; if zero → (1,0) ; normalize
speed = resolveMovementSpeed(380) = 380        # not affected by sprint or statuses
if movementSuppressed or duration<=0 or iframes<0: fail
dodgeUntilMs = max(dodgeUntilMs, sim + min(400, 500))   # i-frames
rollUntilMs  = max(rollUntilMs,  sim + 500)
velocity = dir * 380                          # set ONCE; persists for the whole roll
play 'roll' (direct, loops)
face(dir)                                     # facing + flip
WorldScene.playAnimation('slime-roll')        # cache sync only
emit player.action {anim:'dodge'}             # → global audio cue 'Dodge'
particle 'dodge-dust' at (centre.x, feet.y)   # Phaser resolveBodyBottom == feet → Godot global_position
floating text 'DODGE' cyan at (centre.x, centre.y − 30)   [CENTRE]
control hint 'dodge' learned                  # [OUT] hints UI
```
Distance on open ground: 380 × 0.5 = **190 px**. During the roll:
- Movement keys are ignored and the velocity is never rewritten (§4.1); action presses are buffered but expire (roll 500 ms > buffer 150 ms, so only presses made in the last 150 ms of the roll fire when it ends).
- Hitting a wall: Arcade zeroes the blocked axis and the read-back velocity keeps it zero for the rest of the roll. Godot: keep the persistent `velocity` and move with `ArcadeMover.move(body, delta)` (`game/shared/arcade_mover.gd`), which zeroes the blocked component the same way. (`move_and_slide()` in floating mode does not: it keeps the velocity and slides at full speed.)
- i-frames: `isDodging() = sim < dodgeUntilMs` → `canReceiveDamage` returns `state-blocked` (`PlayerScript.ts:218-221`). From 400 to 500 ms the slime is still rolling but can be hit; a hit then sets the knockback velocity (overrides the roll) and extends suppression.
- When the roll ends the next normal step's `move()` restores walk/idle.
- No squash, no trail, no tint during the roll.

---

## 6. Taking damage, health, knockback, death [IN]

### 6.1 Receiver registration
`PlayerScript._enter_tree` registers its `DamageArea` with the damage router (`priority 0`, `damageMultiplier 1`, no accepted-source filter, no immunities) and joins groups `player` and `damage-target` (`PlayerScript.ts:73-91`). Godot: `add_to_group("player")`, `add_to_group("damage-target")`; the combat spec owns the router; the player exposes the receiver API below.

### 6.2 Resolution order for one hit (`DamageResolver.ts:140-187`, `DamageRouter.ts:123-135`)
```
state = {hp, maxHp, dead}
if dead or hp <= 0                       → rejected 'dead' (not retryable)
scaled = baseDamage * area.damageMultiplier(1) * Π damageTypeMultipliers (none)
canReceiveDamage:
   if isDodging()                        → rejected 'state-blocked'  (RETRYABLE)
   if sim < iFrameUntil                  → rejected 'state-blocked'  (RETRYABLE)
mitigated = scaled == 0 ? 0 : (trueDamage ? scaled : max(1, scaled − defense 3)) * damageTakenMult 1
rounded   = max(0, round(mitigated))     # JS Math.round: .5 rounds up
actual    = min(hp, rounded)
effects   = request effects (e.g. knockback potency) — player has no effect immunities
if actual == 0 and no effects            → rejected 'immune'
accepted {actualDamage: actual, defeated: actual >= hp, appliedEffects}
→ commitDamage(commit) then publishDamageFeedback(commit)
```
**Retryable** means the attack activation does not remember the rejection: the same enemy swing can still hit once the dodge/hit i-frames end while its hitbox overlaps (`AttackActivation.ts:79`). Accepted hits are remembered per activation (one hit per swing per receiver).

Example: worm swordsman `contactDamage 37` (if that is the request's base damage — enemy spec) → 37 − 3 = 34 HP.

### 6.3 Commit (`PlayerScript.commitDamage`, `PlayerScript.ts:227-233`; `PlayerHealthService.commitDamage`, `:271-288`)
```
hp -= actual (GameState.damage: clamps at 0; emits 'player.damage' {amount, source} and 'hp.changed';
              if hp hits 0 emits 'player.death' SYNCHRONOUSLY → markDead → onPlayerDeath (§6.6) runs NOW)
if defeated: markDead (idempotent)
elif actual > 0: iFrameUntil = commit.simulationTime + 500
emit health_changed {hp, maxHp}
emit damaged (commit)            → HurtSfx.play_cue (also fires for an effect-only 0-damage hit)
if dead: emit defeated {receiverNodeId}  → DeathSfx.play_cue
```

### 6.4 Feedback (`PlayerScript.publishDamageFeedback` → `PlayerHealthController.publishDamageFeedback`, `PlayerHealthController.ts:119-135`)
```
emit damage_feedback (commit)
if actual > 0: onPlayerHit(actual)            # §6.5 — runs on the killing blow too
if defeated: return                            # no knockback on death
web effect [OUT]
strength = potency of effect 'knockback' (0 if absent) ; if strength <= 0 return
dir = (impact.knockX, impact.knockY) ; if zero length → no knockback ; else normalize
applyKnockback(dir, strength, 160 ms)
```
`applyKnockback` (`WorldScene.ts:341-350`, `PlayerScript.ts:208-212`):
```
if gulp form knockbackImmune [OUT]: return
playerKnockbackUntil      = max(old, sim + 160)    # animation-priority window
movementSuppressedUntilMs = max(old, sim + 160)    # movement/actions wait
velocity = dir * strength                          # constant for 160 ms, no friction/decay
play 'knockback' FORCED (restart)
```
Distance: strength × 0.16 s (worm swordsman 260 → ~42 px). The knockback direction is computed by the attacker (enemy/combat spec) from positions [CENTRE] — see §11.

### 6.5 Hit presentation (`WorldScene.onPlayerHit`, `WorldScene.ts:1892-1918`) — only when `actualHpLost > 0`
- wake from sleep [OUT]
- `gameFeel.play('player-hurt')` (shake 110 ms / 0.005, hit-stop 70 ms)
- `squash.play('hit')` (skipped while an ability sequence is busy)
- particle `slime-splash` at the body position [CENTRE] (9 goo drops, lifespan 420 ms, speed 50–140, angle 200–340°, gravityY 420, scale 0.8→0.3, alpha 1→0, ground layer)
- HUD health bar flash ([OUT] HUD, a later phase)
- floating text `-N` red, important, at (centre.x, centre.y − 30) [CENTRE]
- red flash: if not already flashing: Visual tint-fill `#ff6f88` (whole silhouette becomes that colour) for 120 ms of **scene time** (not simulation, so it runs through hit-stop), then restore tint (Gulp skin/tint [OUT] → clear). Godot: a small canvas_item shader on `Visual` (`flash_color`, `flash_amount`) — `modulate` can only darken/multiply. Keep `self_modulate` for authored tint (converter contract).
There is no blinking during the 500 ms i-frames.

### 6.6 Death (`WorldScene.onPlayerDeath`, `WorldScene.ts:1920-1940`)
Triggered synchronously from the HP reaching 0 (inside the commit), i.e. **before** the `damaged`/`defeated` signals and before the hit feedback of §6.5.
```
wake [OUT]; gulp.clear() [OUT]
playerKnockbackUntil = 0
universalWorld.resetActiveFights()        # enemies disengage — enemy spec
play 'die' FORCED
velocity = 0
gameFeel.play('player-defeated')          # shake 400 ms / 0.012, hit-stop 150 ms
floating text 'DEFEATED' red important at (centre.x, centre.y − 40) [CENTRE]
after 1400 ms (scene time): defeat screen (shell.showDefeat [OUT]) → its "wake" calls respawnPlayer
```
Then §6.5 still runs for the killing blow (`player-hurt` shake is ignored by Phaser because a shake is already running — `Camera.shake` without `force`; hit-stop takes the max, 150 ms), the red flash plays over the `die` clip.

While dead: the state machine stops the body every step and consumes no input; every damage is rejected `dead`; `heal` returns 0; clip requests other than `die` are dropped; energy regen stops [OUT].

### 6.7 Respawn (`WorldScene.respawnPlayer`, `WorldScene.ts:1942-1983`)
Trial version (no shell, no beds): after the 1400 ms delay call respawn directly — exactly what Phaser does when `this.shell` is absent (`WorldScene.ts:1933`).
```
hp = maxHp, energy = maxEnergy ; emit 'player.respawn' (→ global 'Respawn' cue)
dead = false ; iFrameUntil = 0
status effects cleared [OUT]
teleport to findSpawnPoint(level spawn)   [CENTRE] (§11)
playerKnockbackUntil = 0
play 'idle' FORCED ; clear tint ; alpha 1
camera: pan to spawn 350 ms 'Power2' then follow again
floating text 'Respawned' green important at (spawn.x, spawn.y − 40)
```
Bed respawn / other-area respawn [OUT].

### 6.8 Health state rules (`GameState.ts:182-223`)
`hp` is clamped to `[0, maxHp]`; `damage(amount)` ignores `amount <= 0` or already-dead; `heal` ignores when dead; `maxHp = 100 + gooHearts × 10`. New run starts at full HP (`InitialRun.ts`).

---

## 7. Input capture and buffering [IN]

### 7.1 Bindings (`PlayerInputActions.ts:18-34`; already in `project.godot` as snake_case)
`move_up W/↑, move_down S/↓, move_left A/←, move_right D/→, attack LMB, sprint Shift (L/R), dodge 1`. [OUT] in the trial: `interact RMB, jump Space, stretch_lash 2, squash_slam 3, teleport 4, eat Q, weapon_next/previous wheel`, shell actions `menu E, map M, zoom ±, pause Esc`.

Mouse buttons and the wheel count only when pressed over the game canvas, not over HUD/windows; a release always counts (`InputEvent.ts:52-55`). Godot: handle in `_unhandled_input` (GUI controls with `mouse_filter = STOP` already swallow clicks).

### 7.2 Capture (`PlayerScript._unhandled_input`, `PlayerScript.ts:97-111`)
```
held: Set[action]            pressed: Dict[action → sim_time_ms of the press]
on press of action:  if action not in held: pressed[action] = sim_time   # key-repeat does not refresh
                     held.add(action)
on release:          held.erase(action)
event handled
```
Godot: `if event.is_action_pressed(a) and not event.is_echo()` / `event.is_action_released(a)`; mark handled with `get_viewport().set_input_as_handled()`. A second press before consumption overwrites the timestamp.

### 7.3 Consumption (`consumeActionPress`, `PlayerScript.ts:170-176`)
```
if action not in pressed: return false
t = pressed[action]; pressed.erase(action)
return sim_time − t <= 150          # older presses are DROPPED, not fired late
```
- `isActionPressed(action)` = held (used for sprint).
- `clearInput()` empties held, pressed and the wheel stepper: on pause (any modal), on scene exit.
- Because the simulation clock freezes during hit-stop, a press made during a hit-stop does not age.
- Buffering emerges from the state machine (§4.1): while rolling, knocked back or swing-locked, presses are not consumed; when the lock ends the first step consumes them if ≤150 ms old. This is how a click made late in a swing queues the next swing.
- Edge: if dodge and attack are both pending, dodge wins this step; the attack press then ages during the 500 ms roll and is dropped.

### 7.4 Wheel stepper [OUT] (weapon switch)
`WheelStepper.ts`: wheel deltas accumulate per direction until 50 px = one step; after a step, more scrolling within 150 ms (`weaponWheelStepLockMs`) resets the lock and the accumulator.

---

## 8. Game feel used by the player [IN]

`GameFeel.play(event)` (`GameFeel.ts:83-100`): `shake(ms, intensity × screenShake setting)` (none when reduce-motion; setting default 1) and `hitStop(ms)`: `frozenUntil = max(frozenUntil, now + ms)` (scene real time; overlapping stops do not add). While frozen (`WorldScene.ts:735-748, 792-799`) the world advances by **0 s** (no fixed steps: simulation clock, physics, physics animations, tweens, sprite animations all hold); rendering, camera shake, particles continue; input is still queued.

| Event | shake ms | intensity | hit-stop ms |
|---|---|---|---|
| `player-hurt` | 110 | 0.005 | 70 |
| `player-defeated` | 400 | 0.012 | 150 |
| `hit` (sword lands on a creature — weapon spec) | 0 | 0 | 65 |
| `critical-hit` (crit swing begins — `CombatController.ts:173`) | 80 | 0.006 | 95 |

Phaser shake (3.90 `Shake.js:244-245`): each frame camera offset = `U(−1,1) × intensity × viewport_width` (x) and `× viewport_height` (y), times zoom; a new shake while one runs is ignored. Godot: `Camera2D.offset = Vector2(randf_range(-1,1)*i*vw, randf_range(-1,1)*i*vh) * zoom` per frame. The offset is in world units and the camera zooms it again, so the on-screen shift is `× zoom²`, which is what Phaser's scroll offset does (`world_camera.gd` `_advance_shake`; corrected by the 2026-10-04 review, which found the earlier formula missing the `× zoom`).
Godot hit-stop suggestion: `Engine.time_scale = 0.0` and restore with `get_tree().create_timer(ms/1000.0, true, false, true)` (ignore_time_scale = true); make shake/particles/flash use unscaled time.

Squash and stretch (`SquashStretch.ts:122-185`): the event snaps the Visual's extra scale to the preset, then tweens back to 1; a new event replaces the running one; skipped while an ability sequence is busy (unless forced). Reduce motion keeps 35 %: `start = 1 + (preset − 1) × 0.35`. Effective scale = authored 0.28125 × effect scale.

| Event | scaleX | scaleY | ms | ease (Godot) |
|---|---|---|---|---|
| `move-start` | 0.9 | 1.12 | 170 | Back.Out → `TRANS_BACK, EASE_OUT` |
| `hit` | 1.22 | 0.8 | 190 | Back.Out |
| `jump`/`land`/`gulp` | | | | [OUT] |

Pivot: Phaser scales around the sprite origin (0.5,0.5) = the Visual node position = old body centre [CENTRE]. In Godot the `Visual` node sits at `(0,-27.56)` with `centered=false` and a pixel offset, so scaling `Visual.scale` pivots at the same point — same look. (A feet pivot would look better for a jelly; that is a design change, ask first.)

`dodge-dust` particle (`ParticlePresets.ts:27-30`): texture `dust-puff` (procedural), 9 particles, lifespan 460 ms, speed 30–95 all directions, gravityY −30, scale 0.9→0.25, alpha 0.8→0, rotation 0–360, ground layer.

Audio: `player.action {anim}` → global cues (`AudioEventBridge.ts:31-42`): `dodge → Dodge`, `ability-denied → AbilityDenied`; `player.respawn → Respawn`. These live in `audio/global.scene.json` (audio spec).

---

## 9. Attack input → equipped weapon [IN]

### 9.1 Aim source
`attack()` (`WorldScene.ts:1748-1756`):
```
if settings.attackAim == 'pointer' (default):
    aim = pointerAim()
    if aim: face(snapToCardinal(aim))     # facing & flip change even if the swing is then refused
combatController.tryAttack()
```
`pointerAim()` (`WorldScene.ts:1738-1741`, `PointerAim.ts:11-21`): undefined if the pointer has never been over the game (`pointerSeen`); origin = `(body.x, body.y − 28)`; `d = pointer_world − origin`; undefined if `|d| < 16`; else unit vector + distance. **[CENTRE][QUIRK]**: Phaser `body.y` is the sprite centre, so the origin is 28 px above the centre (above the slime's head: frame 0 art spans y −18..+35 around the centre). The constant was written as "the slime's middle sits 28 px above its origin" (commit 23aba52), i.e. assuming the origin was the feet. Recommended Godot origin: `global_position + Vector2(0, -28)` (feet − 28 ≈ old centre − 0.4), which is what was intended; the literal Phaser value would be `global_position + Vector2(0, -55.56)`. Only matters near diagonals (4-way snap).
With `attackAim == 'facing'` (dev panel), the last facing is used.

### 9.2 Swing request (`CombatController.tryAttack`, `CombatController.ts:148-176`)
```
refuse if: no weapon equipped (new run has weaponId null — the trial must equip 'basic-sword'),
           already attacking, actionLocked, paused, dead, or weapon.canBeginAttack() false (weapon cooldown — weapon spec)
dir4 = facing (or (1,0) if zero) → |x| >= |y| ? (x<0 ? 'left':'right') : (y<0 ? 'up':'down')      (CombatController.ts:63-66)
damage = round(resolveScaledValue(weapon.baseDamage × attack/10 (=1.2), weapon.scaling.damage, attributes))
crit   = random() < 0.05 → damage = round(damage × 1.75)
weapon.tryBeginAttack(dir4, {damage, knockbackStrength, cooldownMs, weaponTags, damageTypes:['physical']})
if accepted and crit: gameFeel 'critical-hit'
```
### 9.3 Swing lifetime callbacks (`CombatController.ts:254-267`)
- weapon `onAttackStarted(weaponId, dir)`: `attacking = true`, `actionLocked = true`, velocity 0, play `slime-<weapon.directionalAttacks[dir].characterActionId>` → basic sword: `attack-1`.
- weapon `onAttackFinished`: `attacking = false`, `actionLocked = false`, play `idle`.
- While `actionLocked`, the state machine zeroes velocity every step and consumes no input (presses buffer, §7.3). A knockback during a swing overrides: suppression is checked first, so the knockback velocity runs its 160 ms, then the lock zeroes velocity again; the `knockback` clip has priority and the swing's final `idle` request is dropped if still inside the knockback window.
- The weapon scene is mounted as a child of the player body at local `(0,0)` = old centre (`UniversalSceneWorldController.ts:1652-1654`) [CENTRE] → in Godot add it under `PlayerSlime` at `-depth_anchor = (0,-27.56)` unless the weapon scene is itself re-anchored (weapon spec must confirm).

---

## 10. Status effects (`systems/StatusEffects.ts`) — mostly [OUT]

Only the hook matters for the trial: movement speed × product of active statuses' `speedMult`, and `rooted` (= `sticky`) blocks walking and the dodge. The worm swordsman applies none. Definitions for later: `burn` 6 dps 3000 ms, `poison` 4 dps 5000 ms (ticks every 500 ms via `gameState.damage`, bypassing i-frames, no hit feedback), `slow` ×0.55 2500 ms, `sticky` ×0 1200 ms, `bouncy` 1500 ms, `frenzy` ×1.4 speed and ×1.4 attack 4000 ms; re-applying keeps the longer remaining time.

---

## 11. Centre vs feet — every place Phaser uses the body position as the centre

Phaser `player.x/y` = `PlayerScript.getPosition()` = CharacterBody2D node origin = **sprite centre**; the feet (`depthAnchor`, `resolveBodyBottom`) are `+27.56` below. In Godot `global_position` = feet, so `old_centre = global_position − Vector2(0, 27.56)` (scale 1).

| Use | Phaser | Godot |
|---|---|---|
| Spawn / respawn / teleport position (`mountScene position`, `findSpawnPoint`, `queue_teleport`) | node origin = centre | `global_position = P + (0, 27.56)` (converter rule for spawning re-anchored scenes) |
| Saved location x,y and its tile validity check [OUT saves] | centre | convert on load/save |
| Pointer aim origin | centre − 28 | feet − 28 recommended (§9.1) |
| Weapon mount | child at (0,0) = centre | child at (0, −27.56) |
| Enemy targeting (`primaryEnemyTarget().position = script.getPosition()`), aggro/attack ranges, knock direction of enemy hits | centre | enemy spec: measure to `old_centre` to keep ranges identical |
| Direct-damage impact position (`applyDamage`) | centre | `old_centre` |
| Floating texts: `DODGE`/`-N`/`Not learned yet` at −30, `DEFEATED`/`Respawned` at −40 | centre − k | feet − 27.56 − k |
| Name tag (`playerName` "bob", 14 px, stroke 4) | interpolated centre − 56 | feet − 83.56 [OUT/optional in trial] |
| `slime-splash` particles | centre | `old_centre` |
| `dodge-dust` particles | body bottom = feet | `global_position` |
| Squash pivot | sprite centre | Visual node position (automatic) |
| Camera follow (`startFollow(player)`) | centre | Camera2D on player with `offset`/position `(0,−27.56)` to keep the same framing |
| Depth sorting | feet | Y-sort by feet (automatic) |
| Hurtbox/pickup/body shapes | offset +14.56 from centre | offset −13 from feet (converter) |
| [OUT] Gulp wheel (−28), jump/teleport/lash ability targets (`player.x/y`), goo trail (`bodyBottom − 3`), `isOccupied` probe | centre-based | convert when ported |

---

## 12. Out of scope (exists in Phaser; later phases)

Jump (Space, 700 ms cd, 168 px, 420 ms, arc 54 px), Stretch Lash (2, 2000 ms cd, 20 energy, 180 px, goo hook), Squash Slam (3, 2500 ms cd, 30 energy, r 90, dmg 30, knockback 320), Teleport (4, 1800 ms cd, 35 energy, ≤240 px, min 32 px, pointer reach), ability-sequence `busy`/action-lock and its presentation leases (`PlayerAbilityPresentation`, `LegacyPlayerAbilityPresentation`), energy (max 100, regen 8/s, costs), Eat/Gulp forms (Q tap/hold wheel, `eat` clip, form speed multiplier, knockback immunity, skins/tints), goo trail (passive), pickups (`PickupArea`, `on_pickup_area_entered` → `CollectibleScript.requestPickup`), interact (RMB, hold for secondary), weapon switching (wheel + hotbar), furniture placement mode, sleep/doze/beds, status effects (§10), web (`applyWeb`, `spider-web-cover` effect), control hints, ability bar UI activation (`activateAbilityFromUi`), defeat screen and bed respawn, saves (location + facing), HUD health bar, boost bonus items, Goo Hearts, dev cheats.

---

## 13. Suggested Godot shape (non-binding; architect decides)

- `res://game/scripts/player.gd` on the `PlayerScript` Node: exports per §1, signals `health_changed`, `damaged`, `defeated`, `damage_feedback` (one Dictionary each), `on_pickup_area_entered(area)` stub. Holds `sim_time_ms`, held/pressed input, `facing`, timers (`dodge_until`, `roll_until`, `suppressed_until`, `knockback_anim_until`, `iframe_until`, `dodge_cooldown_until`), `action_locked`, `dead`, `current_clip_key`.
- `_physics_process(delta)`: advance clock → state machine §4.1 → `ArcadeMover.move(body, delta)` (the body itself has no script from the converter; the player script drives it). World-bounds clamp after moving (converter drops `collideWorldBounds`).
- Receiver API for the combat router: `get_damage_state()`, `can_receive_damage(input)`, `mitigate_damage(input)`, `commit_damage(commit)`, `publish_damage_feedback(commit)`, plus `apply_knockback(dir, strength, ms)`.
- Values from the constants autoload (`character.player.*`, `input.bufferMs`); the literals in §2 marked "literal" may stay as named `const`s in the script with a comment pointing to the Phaser source (they are not in `game-constants.json`).

## 14. Open questions for the owner / integrator

1. Vertical walk clips (`hop`/`stretch`): port the live look (always `walk`) or the intended one? (§4.3)
2. Pointer aim origin: intended feet − 28 or literal centre − 28? (§9.1)
3. Trial: dodge learned from the start, sword equipped from the start, respawn at the level spawn after 1.4 s without a defeat screen — confirm.
4. Idle always un-flips the sprite (faces left when still, even after walking right). Keep? (§4.3)
