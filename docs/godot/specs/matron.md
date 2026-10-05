# Matron spec — the Orb-Weaver Matron, her nest camp, web patches and web barriers

Source of truth: the Phaser code on `feat/godot-migration` (read 2026-10-05). Everything below is
read from code; `file:line` references are to `src/game/...`. "Position" or "centre" is the old
Phaser body position; Godot roots sit at the feet (conventions, *Feet origin*). The Matron's
`depth_anchor` is `(0, 30)`.

Godot targets: script `game.matron` → `res://game/scripts/matron.gd` (node `EnemyScript`, a child
`Node` of the Matron's CharacterBody2D; it extends `game/scripts/enemy.gd` as `MatronScript`
extends `EnemyScript` in Phaser); the camp is the ported `game.boss-camp`
(`res://game/scripts/boss_camp.gd`, [boss.md](./boss.md) §4) in `encounter.gloop-matron-nest`;
`game.web-patch` → `res://game/scripts/web_patch.gd`; `game.spider-web` →
`res://game/scripts/spider_web.gd`; the world side of webs (`world.spider-web` port, `catchInWeb`,
`applyWeb`) → `res://game/enemy/spider_web_port.gd`. Read with the [enemy spec](./enemy.md)
(part 2: projectiles §12, the slime-spider AI §14) and [boss.md](./boss.md): the Matron runs the
whole base enemy step first (arena leash included) and only the differences are written here.

---

## 0. Scope

### IN
- The Matron (`MatronScript.ts`): the base enemy with the slime-spider AI and web spit, the phase
  machine (fight, volley-telegraph, volley-rest, dead), the volley (marks, telegraph, landing hit,
  web patches, camera shake), the boss reaction to hits (feedback only), the common-attack gate,
  defeat and exit.
- Her camp `gloop-matron-nest` in gloop-forest: the Fatty camp code as it is (activation, spawn,
  arena leash and 60 s recovery heal, respawn timer and the "seen outside" rule, reset on the
  player's death, guard flag of the chest, RunState records, the boss bar, defeat burst / text /
  Victory cue / `boss-defeated` feel, `boss_defeated` signal).
- Web patches (`WebPatchScript.ts` in `effect.matron-web-patch`) and web barriers
  (`SpiderWebScript.ts` in `object.spider-web`): catching the slime, the Sticky form tearing them,
  the torn-barrier story flag.
- SFX wiring already in the scene JSON (hurt, death, alert, volley hiss, spit, roar, web splat,
  web tear).

### OUT (exists in Phaser; later phases)
| Feature | Where | Notes |
|---|---|---|
| The rooted `sticky` status on the player, its web cover following the slime | `scenes/WorldScene.ts:1758-1771`, `systems/StatusEffects.ts` | player.gd's (abilities spec 13.9 / 19.3; `is_rooted()` is false until status effects exist). Godot calls `player.apply_web(ms)` when it exists; until then a fallback stops and suppresses the slime for the duration and draws the cover where it stands (§5.3) |
| The Sticky Gulp form itself | `features/gulp/*` | player.gd's (abilities port); the webs read `player.crosses_webs()` (Phaser `crossesWebs`, `WorldScene.ts:2350`) |
| Quests reacting to the defeat (`chapter-two` "the-matrons-nest", reward squash-slam) | `quests/*` | the camp's `boss_defeated({campId, bossId})` is the hook |
| Boss music (`boss.engaged` / `boss.disengaged`) | `UniversalSceneWorldController.ts:548-557` | as for Fatty |
| The guarded chest's lock text | `UniversalSceneWorldController.ts:899-915` | chests belong to the world-objects port; `is_chest_guarded()` and `guard_changed` are there |
| Occlusion silhouette, dev overlays | | dropped / debug only |
| `docs/superpowers/specs/2026-10-01-orb-weaver-matron.md` | | design notes; every runtime number comes from the scene JSON (§1) |

---

## 1. Data

### 1.1 Matron script properties (`characters/orb-weaver-matron.scene.json`, node `script` named `EnemyScript`, `scriptId: game.matron`)
Inherited `game.enemy` exports (enemy spec 1.1) plus the Matron ones. Runtime fallbacks are
`numberProperty(key, fallback)` / `stringProperty` in `MatronScript.ts`.
| JSON | Godot export | Value | Runtime rule / fallback |
|---|---|---|---|
| `displayName` | `display_name` | `"Orb-Weaver Matron"` | |
| `faction` / `rank` | | `hostile` / `boss` (never slowed, enemy spec 15) | |
| `maxHealth` | `max_health` | 300 | |
| `targetingRadius` | `targeting_radius` | 560 (gives up beyond 840) | |
| `attackRange` | `attack_range` | 300 | |
| `movementSpeed` | `movement_speed` | 58 (orbit, walk home) | |
| `attackCooldownMs` | `attack_cooldown_ms` | 2200 | |
| `attributes` | `attributes` | `wanderSpeed 24, attackWindupMs 700, attackRecoveryMs 400, contactDamage 30 (unused), knockbackStrength 220, effectImmunities ["knockback"] (informational), behavior "slime-spider", fleeRange 90, isRanged true, projectileSpeed 240` | |
| `damageRule` | `damage_rule` | `{priority 100, damageMultiplier 1, effectResponses {knockback {mode immune}}}` | every weapon hurts her |
| `projectile` | `projectile` | `{projectileId "spider-web", assetId "enemy.projectile.spider-web", damage 18, stickMs 900}` | |
| `rewards` | `rewards` | `{}` | |
| `arenaRecoveryMs` | `arena_recovery_ms` | 60000 | |
| `firstVolleyDelayMs` | `first_volley_delay_ms` | 3500 | `max(1, v)`, fallback 3500 |
| `volleyCadenceMs` | `volley_cadence_ms` | 6500 | `max(1, v)`, fallback 6500 |
| `volleyTelegraphMs` | `volley_telegraph_ms` | 900 | `max(500, v)`, fallback 900 |
| `volleyRestMs` | `volley_rest_ms` | 1300 | `max(1, v)`, fallback 1300 |
| `volleyPoints` | `volley_points` | 4 | `max(1, round(v))`, fallback 4 |
| `volleySpread` | `volley_spread` | 170 | `max(0, v)`, fallback 170 |
| `volleyRadius` | `volley_radius` | 56 | `max(8, v)`, fallback 56 |
| `volleyDamage` | `volley_damage` | 20 | fallback 20 |
| `volleyKnockbackStrength` | `volley_knockback_strength` | 120 | fallback 120 |
| `patchEffectId` | `patch_effect_id` | `"matron-web-patch"` | fallback `""` (no patches) |

### 1.2 Camp (`encounters/gloop-matron-nest.scene.json`, `scriptId: game.boss-camp`)
`mapId gloop-forest`, `campId gloop-matron-nest`, `bossId orb-weaver-matron`, `bossScene
character.orb-weaver-matron`, activation circle r **460**, arena circle r **320**, `activeBosses`,
`guardedChest` (`object.chest-wooden` at (80, −232): iron-bar ×3, hp-potion ×2),
`guardedChestInstanceId gloop-matron-guarded-chest`, `respawnMs` **300000**, `spawn (0, 0)`;
`RoarSfx` (spider-hiss, pitch 0.4, range 1600) ← `boss_spawn_requested`. Instanced in
`worlds/gloop-forest.scene.json` as `gloop-ch2-matron-nest` at **(3120, 940)** (under the
`matron-nest` Node2D at (0, 0)): activation = circle (3120, 940, r 460), arena = circle (3120, 940,
r 320), the Matron spawns at (3120, 940) (feet at (3120, 970)).

### 1.3 Code literals
| Name | Value | Source |
|---|---|---|
| volley angle step | `turn = (volley_sequence × 0.9) mod 2π` rad | `MatronScript.ts:69` |
| volley camera shake | 80 ms, intensity 0.002 (`boss-landing` feel: hit-stop 0) | `MatronScript.ts:96`, `UniversalSceneWorldController.ts:586` |
| boss target tags | `["enemy", "boss"]` | `UniversalSceneWorldController.ts:2199-2201` |
| boss damage number | `-N` at position − (0, 8) | `UniversalSceneWorldController.ts:2039-2045` (bosses are not ordinary enemies) |
| defeat burst / text | boss spec 1.3 | |

### 1.4 Derived numbers (player defense 3)
- Spit: the common ranged attack (enemy spec 12) — `spider-web` at 240 px/s, hits for
  max(1, 18 − 3) = **15**, knockback 220, web 900 ms; fired 700 ms after the attack starts; the
  sequence ends +min(2000, max(1100, 300) + 250) = **+1350 ms**; next spit ≥ 2200 ms later.
- Slime-spider AI: `preferred = max(1, 90) = 90`; spits between 90 and 300 px, backs off inside
  64.8 px (0.72 × 90) while holding, approaches spiralling beyond 300 px.
- Volley: first one 3500 ms after the spawn (when free: not spitting, not walking home, player
  alive); marks for 900 ms; landing hit max(1, 20 − 3) = **17**, knockback 120 (knock from her
  centre toward the player); 4 web patches; rest 1300 ms; next volley 6500 ms after the rest ends
  (a cycle is at least 8700 ms).
- 300 hp: a basic sword (24 per hit) needs 13 hits; she takes knockback-free hits and never
  staggers.

---

## 2. Scenes

### 2.1 `characters/orb-weaver-matron.scene.json`
Root CharacterBody2D (named `orb-weaver`), layer 4, mask 1027, `depthAnchor (0, 30)`,
`collideWorldBounds`. BodyShape and DamageShape: ellipse 40 × 30 radii (Godot: a rectangle 80 × 60
for the body, a 32-point polygon for the hurtbox). Visual: `orb-weaver-matron.sprite` (the orb weaver
sheet 64 × 64, 8 × 10), scale 2.6, tint `#b98cff`. AttackArea (layer 16, mask 8, off) > AttackShape
circle r 340 (only the attack activation uses the area). Animation: the orb weaver's directional
clips `idle-*`, `walk-*`, `attack-*` (0.3 s), `knockback-*`, `die-*` (0.286 s), autoplay
`idle-side`. SFX: HurtSfx (spider-hurt, pitch 0.6, min interval 150) ← `damaged`; DeathSfx
(spider-death, pitch 0.55, detached, range 1400) ← `defeated`; AlertSfx (spider-hiss, pitch 0.6)
← `alerted`; VolleySfx (spider-hiss, pitch 0.45, range 1400, filter `phase=volley-telegraph`) ←
`phase_changed`; SpitSfx (web-spit, pitch 0.7, filter `phase=volley-rest`) ← `phase_changed`.
There is no WindupSfx: the projectile's own SpitSfx plays on launch.

### 2.2 `effects/matron-web-patch.scene.json`
Root Node2D `MatronWebPatch`, `depthAnchor (0, 0)`; `Web` Sprite2D (the `spider-web-cover` sheet,
4 frames 64 × 64, scale 1.8, alpha 0.4, `ground-decals` band → z −1); clip `right` (autoplay, 6 s):
frames 0–3 at 10 fps, alpha 0.4 → 0.95 (0.3 s) → 0.95 (5.2 s) → 0 (6.0 s); `EffectScript`
(`game.effect`, `lifetimeMs 6000`); `WebPatchScript` (`game.web-patch`, `radius 50`, `visual Web`);
`SplatSfx` (web-splat, autoplay, detached); `TearSfx` (silk pickup) ← `WebPatchScript.torn`.

### 2.3 `objects/spider-web.scene.json`
Root Node2D `spider-web` (no depth anchor); `Visual` (`sheet.props.gulp.8x1` frame 4, origin
(0.5, 1), scale 0.56); `StakeLeft` / `StakeRight` StaticBody2D (layer 1) at (−62, −8) / (62, −8)
with 18 × 18 boxes (the web itself has no collision); `SpiderWebScript` (`game.spider-web`,
`width 112`, `depth 56`, `visual Visual`). No connections. Placed in gloop-forest
(`gloop-ch2-nook-web` at (800, 1280), persistence key `gloop-forest.gloop-ch2-nook-web`) and the
playground (`playground-nook-web` at (384, 1760)).

---

## 3. The Matron per physics step

### 3.1 State (`MatronScript.ts:24-28`)
```
phase := "fight"; phase_started_at := 0
next_volley_at := now + max(1, first_volley_delay_ms)      # _enter_tree (:32-35)
volley := []  (points, old Phaser positions); volley_sequence := 0
```
`transition_to(phase, now)` (`:130-134`): phase, `phase_started_at = now`, emit
`phase_changed({phase, time: now})`.

### 3.2 Step order (`MatronScript.ts:37-60`)
The whole base enemy step runs first (enemy spec 4.2 with the slime-spider AI and the ranged
attack; the arena leash, boss spec 3.3; navigation `{arena}` only: no territory, no safe zones),
then:
```
if defeated or phase == "dead": return
if phase == "fight":
    if returning_to_arena or now < next_volley_at or attacking: return   # never mid-spit
    target = primary target; if not active or not hostile: return
    begin_volley(now, target centre); return
velocity = 0                                         # both volley phases hold still
volley-telegraph: now - phase_started_at >= max(500, volley_telegraph_ms) -> land_volley(now)
volley-rest:      now - phase_started_at >= max(1, volley_rest_ms) ->
                  next_volley_at = now + max(1, volley_cadence_ms); transition_to("fight")
```
Then the body moves (Godot `ArcadeMover.move`). The base AI keeps running in the volley phases (it
can still flee or chase in its own state), but the Matron's velocity is zeroed and the common
attack is gated (§3.5), so she stands still. The arena leash still runs in every phase: when the
player leaves the arena during a volley she stays put (velocity 0) but is "returning", and the
next fight phase waits for her to come back.

### 3.3 `begin_volley(now, at)` (`:63-81`)
```
if defeated or phase != "fight": return false
cancel_attack()
count = max(1, round(volley_points)); spread = max(0, volley_spread)
turn = fmod(volley_sequence * 0.9, TAU)
points = [at]
for i in 1 .. count-1:
    angle = turn + ((i - 1) / max(1, count - 1)) * TAU
    points.append(at + (cos angle, sin angle) * spread)
volley = [clamp_to_arena(p) for p in points]          # BossArena.clamp_point when she has an arena
volley_sequence += 1
telegraph(volley circles, shadow at `at`)             # boss spec 3.6
play_animation("attack-side", restart)
transition_to("volley-telegraph", now)                # -> VolleySfx
```
With 4 points: the player's centre plus three marks 170 px away at `turn`, `turn + 120°`,
`turn + 240°` (`turn` 0, 0.9, 1.8, … rad for successive volleys).

### 3.4 `land_volley(now)` (`:83-98`)
```
clear the telegraph
shapes = volley circles (radius max(8, volley_radius) at each point)
if the target is active and its hurtbox overlaps any circle:
    route_immediate_attack(volley_damage, volley_knockback_strength, impact effect off)   # boss spec 3.4
for each point: spawn effect `patch_effect_id` at the point (direction right; "" spawns nothing)
shake_camera(80, 0.002)
transition_to("volley-rest", now)                     # -> SpitSfx
```

### 3.5 Base differences
1. **Common attack gate** (`canRunCommonAttack`, `:116`): the AI's attack request starts a spit only
   in phase `fight`.
2. **Reaction** (`reactToDamage`, `:112-114`): only the hit feedback (flash `#ff6f88` 120 ms, number
   at position − (0, 8), yellow and big above 15): no cancel, no stun, no shove. Knockback is
   immune in the rule anyway.
3. **Defeat** (`:118-123`): clear the telegraph; the base defeat (cancel, velocity 0, collision off,
   attack area off, `die-<facing>`, `health_changed {hp: 0}`, `defeated` → DeathSfx,
   `reward_requested {rewards: {}}`); phase `dead`.
4. **Exit** (`:125-128`): clear the telegraph, then the base exit.
5. Hurtbox target tags `["enemy", "boss"]`; damage number at the position (boss spec 1.3).
6. `apply_slow` is ignored (`rank boss`).

### 3.6 Telegraph
The ported `AttackTelegraph` (boss spec 3.6): one warning per attacker; the volley's four circles
(filled `#ff7a3d` α 0.15, stroked 3 px `#ffc85a` α 0.85) plus the shadow ellipse at the player's
position when the volley began; static; cleared on landing, defeat and exit.

---

## 4. The camp, the bar and the defeat
Exactly boss spec §4–§6 with §1.2's data. The camp spawns the Matron under the world root at
(3120, 940) when the player centre enters the activation circle (r 460), hands her the arena
(r 320); the bar shows "Orb-Weaver Matron" with her hp (300); leaving the arena makes her walk back
to its centre and, after 60 s outside, heal to full; the player's death resets the fight (spawn
again only after leaving the activation circle); the defeat bursts `boss-burst` at position −
(0, 30), records `orb-weaver-matron` in RunState `defeated_boss_ids` and the 300 s respawn time in
`map_record("gloop-forest")["boss_camps"]["gloop-matron-nest"]`, plays `Victory` and
`boss-defeated`, emits `boss_defeated {campId: gloop-matron-nest, bossId: orb-weaver-matron}`,
shows "Orb-Weaver Matron defeated!" at position − (0, 84) and lifts the chest guard.

**Godot deviation (as for Fatty, boss spec 4.4):** Phaser disposes the boss the step it dies; the
port keeps the dead body (collision off, hurtbox rejecting `dead`) for its `die-<facing>` clip
(0.286 s on the gameplay clock), then frees it.

---

## 5. Webs

### 5.1 `game.web-patch` (`features/scripts/WebPatchScript.ts`)
Properties: `radius` (> 0, else 48; authored 50), `visual` (the `Web` sprite). Signals `caught`,
`torn` (payload: the zone). Per frame (`_process`, `:50-65`):
```
player = port.player_position()          # null while dead or travelling
if no player or torn: return
zone = {x, y: the patch root's position, halfWidth: radius, halfHeight: radius}
if |player - (x, y)| > radius: return
if port.player_crosses_webs():           # Sticky
    torn = true; visual hidden; emit torn(zone)   # -> TearSfx; no message, no flag
    return
port.catch_player(zone); emit caught(zone)
```
The patch lives as long as its effect (6000 ms) and is never remembered.

### 5.2 `game.spider-web` (`features/scripts/SpiderWebScript.ts`)
Properties: `width` (> 0, else 200; authored 112), `depth` (> 0, else 48; authored 56),
`tearsWhenCrossed` (true unless `false`), `visual`. Signals `caught`, `torn`. Torn flag:
`web-torn.<placement persistence key>` (else the authored instance id, else the node id; `:117-123`).
- `_ready` (`:78-81`): when the story flag is set, show it torn (visual hidden, torn).
- Per frame (`:88-101`): `zone = {x: root.x, y: root.y − depth / 2, halfWidth: width / 2,
  halfHeight: depth / 2}` (the strands hang just above the root); the player centre inside the box
  (`|dx| <= halfWidth and |dy| <= halfHeight`) → Sticky: tear when `tearsWhenCrossed` (visual
  hidden, story flag set, `port.web_torn(zone)`, emit `torn`), else nothing; not Sticky:
  `port.catch_player(zone)`, emit `caught`.
- gloop-forest's nook web: box centre (800, 1252), half extents 56 × 28.

### 5.3 The port (`scenes/WorldScene.ts:2347-2357, 2132-2142, 1758-1771, 1584-1588`)
- `player_position()`: the player centre while alive and no area transition runs.
- `player_crosses_webs()`: the Gulp form's `crossesWebs` (Sticky) → Godot `player.crosses_webs()`.
- `catch_player(zone)`: `from_above = player.y < zone.y`; teleport the player (stop, place, reset)
  to `(player.x, zone.y − halfHeight − 26)` when from above, else `(player.x, zone.y + halfHeight +
  30)`; `applyWeb(900)`; at most every 2500 ms (scene time) the white big text "Caught in the web!
  (something sticky could cross)" at the (new) player centre − (0, 56) for 2200 ms.
- `web_torn(zone)`: `gameEvents 'web.torn'` (→ global cue `WebTear`), `loot-sparkle` particles at
  the zone, cyan big text "The web tears open!" at zone − (0, 40) for 1800 ms.
- `applyWeb(ms)`: player side (enemy spec 12.6).
Godot (`spider_web_port.gd`): `player.crosses_webs()` and `player.teleport(centre)` (stop and
place) directly; `player.apply_web(ms)` when it exists, else the fallback `stop_movement` +
`suppress_movement(ms)` (no walking, but unlike Phaser's root also no attacks or abilities) and the
web cover (`effect.spider-web-cover`, drawn in front of the slime at its centre, not following it)
unless the slime was already held. The message throttle is kept per world (metadata on the world
root).

### 5.4 Godot notes
- The web scripts check in `_physics_process` (Phaser `_process`, once per rendered frame): the
  player position only changes in physics steps, and teleporting in a physics step keeps the
  body's interpolation consistent.
- A jump or teleport that skips over a zone is the abilities port's concern (abilities spec 5.x).

---

## 6. Signals
| Script | Signal | Payload | Connected |
|---|---|---|---|
| matron | `phase_changed` | `{phase, time}` | VolleySfx (`phase=volley-telegraph`), SpitSfx (`phase=volley-rest`) |
| matron | base enemy signals | enemy spec 8 | HurtSfx, DeathSfx, AlertSfx |
| web patch | `caught`, `torn` | zone `{x, y, halfWidth, halfHeight}` | `torn` → TearSfx |
| spider web | `caught`, `torn` | zone | — |
| camp | boss spec 6 | | RoarSfx ← `boss_spawn_requested` |

## 7. Centre vs feet
Every Matron distance, arena test, volley point, telegraph, damage number, burst and text uses her
old Phaser position (`feet − (0, 30)`); the player side uses its centre. Web zones are world
positions of roots without a depth anchor (unchanged). The patch effect spawns with its root at
the volley point.
