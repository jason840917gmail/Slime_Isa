# Matron spec — the Orb-Weaver Matron, her nest camp, web patches and web barriers

Source of truth: the Phaser code on `feat/godot-migration` (read 2026-10-05). Everything below is
read from code; `file:line` references are to `src/game/...`. "Position" or "centre" is the old
Phaser body position; Godot roots sit at the feet (conventions, *Feet origin*). The Matron's
`depth_anchor` is `(0, 30)`.

Godot targets: script `game.matron` → `res://game/scripts/matron.gd` (node `EnemyScript`, a child
`Node` of the Matron's CharacterBody2D; it extends `game/scripts/enemy.gd` as `MatronScript`
extends `EnemyScript` in Phaser); the camp is the ported `game.boss-camp`
(`res://game/scripts/boss_camp.gd`, [boss.md](boss.md) §4) in `encounter.gloop-matron-nest`;
`game.web-patch` → `res://game/scripts/web_patch.gd`; `game.spider-web` →
`res://game/scripts/spider_web.gd`; the world side of webs (`world.spider-web` port, `catchInWeb`,
`applyWeb`) → `res://game/enemy/spider_web_port.gd`. Read with the [enemy spec](enemy.md)
(part 2: projectiles §12, the slime-spider AI §14) and [boss.md](boss.md): the Matron runs the
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
- **Godot only (2026-10-17): the Weaver Hollow's fight** (section 8): her cocoon, its three rounds,
  her camp `encounter.weaver-hollow-matron` at the top of the Hollow, and her rewards (Pearl 2 and
  the Silk skin, the full heart, the max-energy raise, her thread). The open-world nest
  above keeps the Phaser fight until it is removed.

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
| `attributes` | `attributes` | `wanderSpeed 24, attackWindupMs 700, attackRecoveryMs 400, contactDamage 20 (unused), knockbackStrength 220, effectImmunities ["knockback"] (informational), behavior "slime-spider", fleeRange 90, isRanged true, projectileSpeed 240` | |
| `damageRule` | `damage_rule` | `{priority 100, damageMultiplier 1, effectResponses {knockback {mode immune}}}` | every weapon hurts her |
| `projectile` | `projectile` | `{projectileId "spider-web", assetId "enemy.projectile.spider-web", damage 20, stickMs 900}` | |
| `rewards` | `rewards` | `{}` | |
| `arenaRecoveryMs` | `arena_recovery_ms` | 60000 | |
| `firstVolleyDelayMs` | `first_volley_delay_ms` | 3500 | `max(1, v)`, fallback 3500 |
| `volleyCadenceMs` | `volley_cadence_ms` | 6500 | `max(1, v)`, fallback 6500 |
| `volleyTelegraphMs` | `volley_telegraph_ms` | 900 | `max(500, v)`, fallback 900 |
| `volleyRestMs` | `volley_rest_ms` | 1300 | `max(1, v)`, fallback 1300 |
| `volleyPoints` | `volley_points` | 4 | `max(1, round(v))`, fallback 4 |
| `volleySpread` | `volley_spread` | 170 | `max(0, v)`, fallback 170 |
| `volleyRadius` | `volley_radius` | 56 | `max(8, v)`, fallback 56 |
| `volleyDamage` | `volley_damage` | 40 (20 in Phaser) | fallback 40 |
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
r 320), the Matron spawns at (3120, 940) (feet at (3120, 970)). Since 2026-10-12 gloop-forest is
cut into chunk worlds: the nest is in `gloop-forest-f4` (origin (2048, 0)), at **(1072, 940)**
there, its camp's `mapId` `gloop-forest-f4` ([WORLD_ATLAS.md](../WORLD_ATLAS.md#chunk-worlds-2026-10-12)).
**Since 2026-10-17 no world places it:** the Matron lives in the Weaver Hollow's Crown (section 8.4)
and `gloop-forest-f4` is the Hollow's forecourt (the Watch Oak's root gate,
[DUNGEONS.md](../DUNGEONS.md#the-weaver-hollow-built)). The scene stays, and `test_matron.gd` mounts
it at (1072, 940) in F4 for the tests of her own fight (sections 3 to 5).

### 1.3 Code literals
| Name | Value | Source |
|---|---|---|
| volley angle step | `turn = (volley_sequence × 0.9) mod 2π` rad | `MatronScript.ts:69` |
| volley camera shake | 80 ms, intensity 0.002 (`boss-landing` feel: hit-stop 0) | `MatronScript.ts:96`, `UniversalSceneWorldController.ts:586` |
| boss target tags | `["enemy", "boss"]` | `UniversalSceneWorldController.ts:2199-2201` |
| boss damage number | `-N` at position − (0, 8) | `UniversalSceneWorldController.ts:2039-2045` (bosses are not ordinary enemies) |
| defeat burst / text | boss spec 1.3 | |

### 1.4 Derived numbers (no player defence since 2026-11-24)
- Spit: the common ranged attack (enemy spec 12) — `spider-web` at 240 px/s, hits for
  **20** (Phaser: max(1, 18 − 3) = 15), knockback 220, web 900 ms; fired 700 ms after the attack starts; the
  sequence ends +min(2000, max(1100, 300) + 250) = **+1350 ms**; next spit ≥ 2200 ms later.
- Slime-spider AI: `preferred = max(1, 90) = 90`; spits between 90 and 300 px, backs off inside
  64.8 px (0.72 × 90) while holding, approaches spiralling beyond 300 px.
- Volley: first one 3500 ms after the spawn (when free: not spitting, not walking home, player
  alive); marks for 900 ms; landing hit **40** (Phaser: max(1, 20 − 3) = 17), knockback 120 (knock from her
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
port keeps the dead body (collision off, hurtbox rejecting `dead`) for 2 s on the gameplay clock
(owner decision 2026-10-05): its `die-<facing>` clip (0.286 s), then the last frame, fading out
over the last 0.3 s; then frees it.

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
The patch lives as long as its effect (6000 ms) and is never remembered. **Godot since 2026-10-17
(5.5):** the patch is a floor web; the last line is gone: a rolling slime sticks
(`FloorWebs.stick_roll`, emit `caught`), and a walking one walks at half speed while its centre is
on the patch (the patch is in group `web_slows`), with no catch and no set-back.

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
- `player_crosses_webs()`: the Gulp form's `crossesWebs` (Sticky) → Godot `player.crosses_webs()`
  (the Silk skin's hook, 5.5).
- `catch_player(zone)`: `from_above = player.y < zone.y`; teleport the player (stop, place, reset)
  to `(player.x, zone.y − halfHeight − 26)` when from above, else `(player.x, zone.y + halfHeight +
  30)`; `applyWeb(900)`; at most every 2500 ms (scene time) the white big text "Caught in the web!
  (something sticky could cross)" at the (new) player centre − (0, 56) for 2200 ms. Godot since
  2026-10-17: "Thick silk. It will not give." (the old line named the Sticky form; the web walls'
  line, docs/godot/WEBS.md). Only the web barrier (5.2) catches since then.
- `web_torn(zone)`: `gameEvents 'web.torn'` (→ global cue `WebTear`), `loot-sparkle` particles at
  the zone, cyan big text "The web tears open!" at zone − (0, 40) for 1800 ms.
- `applyWeb(ms)`: player side (enemy spec 12.6).
Godot (`spider_web_port.gd`): `player.crosses_webs()`, `player.is_rolling()` /
`player.stop_movement()` (a rolling slime's roll ends first, 5.5) and `player.teleport(centre)`
(stop and place) directly; `player.apply_web(ms)` when it exists, else the fallback `stop_movement` +
`suppress_movement(ms)` (no walking, but unlike Phaser's root also no attacks or abilities) and the
web cover (`effect.spider-web-cover`, drawn in front of the slime at its centre, not following it)
unless the slime was already held. The message throttle is kept per world (metadata on the world
root).

### 5.4 Godot notes
- The web scripts check in `_physics_process` (Phaser `_process`, once per rendered frame): the
  player position only changes in physics steps, and teleporting in a physics step keeps the
  body's interpolation consistent.
- A jump or teleport that skips over a zone is the abilities port's concern (abilities spec 5.x).

### 5.5 The Roll and the Silk skin (owner, 2026-10-16, question 131)
- **A volley patch is a floor web** (since 2026-10-17, roadmap 7.9: "a Matron volley patch behaves
  like a web"; the rule in `game/world/webs/floor_webs.gd`, docs/godot/WEBS.md). Without the Silk
  skin a slime whose centre is on the patch walks at `webs.floorSlowMultiplier` (0.5) of its speed,
  and nothing catches or sets it back; a Roll that enters it **sticks where it is**:
  `FloorWebs.stick_roll` ends the roll (`player.stop_movement()`: no bonk, no bounce, no rolling on,
  its i-frames gone) and roots the slime `webs.rollStickMs` (900) with the web cover (`apply_web`);
  the patch emits `caught`. A Roll never crosses or tears a patch (`tests/test_matron.gd`
  `test_web_patch_slows_a_walk_sticks_a_roll_and_tears_for_the_sticky_one`,
  `tests/test_player_movement.gd` `test_a_roll_sticks_in_a_floor_web`). Painted floor webs (the
  `webs` WebLayer) follow the same rule (`tests/test_weaver_webs.gd`).
- **The web barrier (5.2) still catches:** a walk or a roll into it is set back on the side it came
  from (`catch_player`, the roll ended first), so it blocks until the slime crosses webs. The
  Weaver Hollow's web walls are `object.web-wall` (solid without the Silk skin, passed at half speed
  with it, cut for good by a shape's hit with it; WEBS.md).
- **The Silk skin's hook** is `player.crosses_webs()`: with it webs neither slow, catch nor stick
  (the patch and the barrier tear instead, and `player.apply_web(ms)` does nothing, so a spit web no
  longer roots either). Since roadmap 7.8 it is the Silk skin itself (SkinState, won from Pearl 2,
  section 8.5; [SKINS.md](../SKINS.md#silk)); the Silk Gulp form (Sticky) no longer counts.
- Not built yet (roadmap 7.9): the Orb-weaver's laid webs and the webs of Tom's maze.

---

## 6. Signals
| Script | Signal | Payload | Connected |
|---|---|---|---|
| matron | `phase_changed` | `{phase, time}` | VolleySfx (`phase=volley-telegraph`), SpitSfx (`phase=volley-rest`) |
| matron | `shell_changed` (cocoon fight, section 8) | `{shell: "cocooned" \| "torn" \| "respin", round, time}` | — (cues are global, 8.3) |
| matron | base enemy signals | enemy spec 8 | HurtSfx, DeathSfx, AlertSfx |
| web patch | `caught`, `torn` | zone `{x, y, halfWidth, halfHeight}` | `torn` → TearSfx |
| spider web | `caught`, `torn` | zone | — |
| camp | boss spec 6 | | RoarSfx ← `boss_spawn_requested` |

## 7. Centre vs feet
Every Matron distance, arena test, volley point, telegraph, damage number, burst and text uses her
old Phaser position (`feet − (0, 30)`); the player side uses its centre. Web zones are world
positions of roots without a depth anchor (unchanged). The patch effect spawns with its root at
the volley point.

---

## 8. The Weaver Hollow's fight: the cocoon (Godot only, built 2026-10-17, not yet played by the owner)

The design: [the Weaver Hollow](../../design/2026-10-16-dungeon-weaver-hollow.md#the-matrons-room),
question 133 ([decisions](../../story/07-decisions-archive.md)), roadmap 8.7. Her fight needs the
Goo Bomb: she shields herself in a web cocoon that only a blast tears open, then the Spear. Built in
`game/scripts/matron.gd` (the cocoon's state machine), `game/bosses/matron_cocoon_look.gd` (its look)
and `game/scripts/boss_camp.gd` (`respawn_ms` below 0, `boss_overrides`). **Since the Pearl moved
inside the dungeon** (2026-10-17, [the plan](../../design/2026-10-17-pearl-mid-dungeon.md#the-matrons-exam))
the slime meets her with the Silk skin, and her fight is its exam: with the skin round 2 is a cage of
web walls and round 3 a webbed floor (8.2); without it (a dev run) the rounds below play as built.
Pearl 2 lies in the Hoard, guarded by the Brood Warden, not in her camp.

### 8.1 Switch and numbers
The cocoon is on while the Matron's `cocoon_enabled` is (off in `character.orb-weaver-matron`, so the
open-world nest keeps sections 1 to 7; the Hollow's camp turns it on through its `boss_overrides`).
Every number is an export on her scene (group "Cocoon (Weaver Hollow)"), the volley's beside them:

| Export | Value | What |
|---|---|---|
| `open_ms` | 4000 | torn: how long she lies open on the floor |
| `drop_ms` | 260 | her fall out of the cocoon (part of the window) |
| `respin_ms` | 1500 | her climb and the new cocoon (the tell: threads whirl) |
| `round_two_below_hp` / `round_three_below_hp` | 200 / 100 | the rounds' health floors (of 300) |
| `round_hang_px` | 60, 130, 130 | the cocoon's bottom over its shadow in rounds 1 to 3 |
| `ring_patches`, `ring_radius`, `ring_reweb_ms` | 8, 130, 5000 | round 2's ring of floor webs (`patch_effect_id`) round her shadow, webbed again while she is cocooned |
| `egg_sac_scene`, `egg_sac_offsets` | `character.egg-sac`, (±72, 36) | round 3's two egg sacs by her shadow (old centres), dropped once |
| `breath_ms` | 2600 | one breath of the cocoon (the Cocoon Mimic's tell) |
| `clink_text` | "Woven too thick. It would take a blast." | the cocoon's refusal line |
| `silk_exam` | on | the Silk skin's exam: round 2's cage and round 3's webbed floor when the slime has the skin (`silk_exam_on()`) |
| `cage_walls_per_side`, `cage_thickness_px`, `cage_height_px` | 2, 24, 100 | round 2's cage: web walls on each side of the square of half side `ring_radius`, their solid's depth, the back and front ones' height |
| `cage_text` | "A thrown bomb sticks in the silk." | said (BlastBarrier, at most every 1.5 s) when a bomb comes to rest against the cage from outside |
| `floor_web_radius_px`, `floor_web_share` | 352, 0.8 | round 3's webbed floor: the cells within this of her shadow, about this share of them |
| `pose_scale` | 0.5 | her own poses in the fight |
| `retreat_px`, `retreat_scale` | 260, 0.62 | beaten: how far she scuttles off, and how small (an ordinary orb-weaver is 0.46) |

Game-wide (`game-constants.json`): `character.player.fullHeart.maxHpBonus` 20,
`character.player.maxEnergyUpgrade.bossBonus` 20, `inventory.maxStackByItem.matron-thread` 1.

### 8.2 Per step
- **First step:** she joins group `blast_targets`, takes her own pose sprite (8.3) in place of the
  old sheet's `Visual`, and is cocooned in the round her health is in.
- **Cocooned** (`get_shell()` "cocooned"): the whole base step runs (the slime-spider AI, the spit,
  the leash), then the volley machine (3.2), but her velocity is zeroed: she hangs from her thread
  and never walks. Her body is not solid (the slime walks under the cocoon). Every hit is refused
  "immune" (a clink) with `clink_text` (BlastBarrier.refuse: at most every 1.5 s, orange, over the
  cocoon), old-style and rework hits alike, and the Goo Bomb blast's hurtbox strike skips her (she
  is a blast target), so no hit and no blast hurts her. Round 2 webs its ring again every
  `ring_reweb_ms`.
- **Torn:** a Goo Bomb blast whose ellipse (176 × 120, `abilities.gooBomb.ellipse`) holds her shadow
  (`blast_point()`: her feet) calls `receive_blast`: the spit and a volley in hand are dropped (its
  telegraph cleared, phase back to "fight"), she drops to the floor (`drop_ms`; a small camera shake
  and `DropLand` on landing), solid, and lies dazed for `open_ms` (her legs twitch between two poses,
  she shivers; a hit shows her flinch for 260 ms). No AI, no spit, no volley, no leash. Every weapon
  hurts her, but a hit takes her no lower than her round's floor (`round_floor()`: 200, 100, 0);
  reaching it ends the window at once. The tear: "The cocoon tears open!", `WebTear`, silk tatters.
- **Respin:** after `open_ms`, or at the round's floor: she climbs her thread (the climbing pose
  rises and fades over 60 % of `respin_ms`), threads whirl round the husk and the new silk closes
  (`MimicWrap`). Hits clink; a blast now tears the half-spun cocoon again. When it closes she is
  cocooned in the round her health is in, and her next volley comes `first_volley_delay_ms` later.
- **Rounds:** 1 above 200 (hangs low, the floor clear); 2 above 100 (hangs higher; its ring of 8
  floor webs round the shadow: a bomb thrown over them, a Roll sticks); 3 (two egg sacs drop by her
  shadow with her arena; their Broodlings swarm and, in the rework mode, drop energy shards as every
  kill does; a blast that holds a sac bursts it). Three blasts at least: she cannot be beaten
  without the Goo Bomb.
- **The Silk skin's exam** (the slime has the Silk skin, `SkinState.is_on`, and `silk_exam` is on;
  in the Hollow it always has, since Pearl 2 comes first):
  - **Round 1** as built; her volleys' floor webs neither slow the slime nor stick its Roll, and her
    spit no longer roots it (`apply_web` does nothing with the skin).
  - **Round 2: the web-wall cage** in place of the ring. `cage_slots()`: a square of half side
    `ring_radius` (130) round her shadow, `cage_walls_per_side` (2) `object.web-wall`s a side (the
    back and front ones "across", the sides "side", meeting at the corners), spawned under the
    world's entities in `MatronCage`, `remembered` off (a cut sets no flag), faded in. Every
    `ring_reweb_ms` while she is cocooned each slot whose wall is cut is spun again (`MimicWrap`),
    never one the slime's feet stand in. A throw ends at the first hurtbox (`thrown_object.gd`), so a
    thrown bomb stops in the cage's silk and blows there, out of reach of her shadow (its ellipse is
    88 × 60 from its middle); a spat bomb's hop stops short of it too. A bomb come to rest within 30
    px of a wall from outside gets `cage_text` once. The slime cuts a gap with the Spear (the web
    wall's cut) or wades a wall at half speed, and casts inside the ring.
  - **Round 3: the webbed floor.** The cage goes (its silk falls as tatters) and `object.floor-web`s
    (one a 64-unit cell, its web and turn picked by the cell) cover about `floor_web_share` of the
    cells within `floor_web_radius_px` of her shadow inside her arena (`MatronFloorWebs`), faded in,
    with the egg sacs as built. The Silk slime walks them at full speed and Rolls through them to
    dodge the swarm and to set one blast on a sac and her shadow together.
  - Both go with her: her fall (the cage's tatters; the webbed floor stops holding at once and fades
    over 0.7 s) and a reset (her body freed: `_exit_tree`).
  - Without the skin the built rounds play (a dev run on the Crown alone: the ring, no webbed floor).
- **Beaten:** her egg sacs and the Broodlings of her arena burst; the cocoon unravels and its thread
  draws up into the web; she shrinks into an ordinary big orb-weaver (the orb-weaver's sheet, from
  behind) and scuttles `retreat_px` up through her web, fading at the end (the body frees itself
  after 2 s, as in section 4). The camp's defeat bookkeeping is section 4's; her fall breaks the
  Hollow's seals ([DUNGEONS.md "The seal"](../DUNGEONS.md#the-seal)).
- While the Hollow is sealed (the Pearl taken) she shows her rage at her fight's start (the kit's
  `EnragedLook`: her silk darkens to violet; presentation only).
- Not built: the three-way Stretch Lash that pulls and traps (roadmap 8.7's plan of 2026-10-02):
  she keeps the web spit (1.4). If it is built, it pulls but never traps a silk-skinned slime.

### 8.3 The look (`game/bosses/matron_cocoon_look.gd`, node `CocoonLook` under the body)
Presentation only; matron.gd sets its `state` ("cocooned", "torn", "respin", "gone", "off"),
`progress`, `hang_px` and `breath` each step. The shadow (an ellipse that shrinks and pales as the
cocoon hangs higher), the thread up to `thread_top_px` (420) over the shadow, the cocoon
(`256x416-tile_2x1-matron-cocoon.webp` frame 0, at 0.5, swelling with the breath by `breath_swell`
0.06) with an additive red glow over its eyes (`eye_glow_*`), the torn husk (frame 1), the respin's
whirling threads, the unravelling. `@tool`: `preview_state` shows a state in the editor, for tuning
the hang, the thread and the glow on the scene. Her poses: `384x384-tile_4x1-matron.webp` (dazed A,
dazed B, flinch, climbing), drawn at `pose_scale` with their feet at hers; the hit flash and the
reactions' hit motion follow it (`visual`).

### 8.4 The Weaver Hollow's camp (today's Crown: `weaver-hollow-matron-old.tscn`)
Since the switch-over of 2026-11-25 this camp is `game/scenes/encounters/weaver-hollow-matron-old.tscn`,
a copy of the encounter as it was, instanced only by today's Crown (no longer entered; it goes at step
5); `encounter.weaver-hollow-matron` itself is the ram fight's camp (section 9). For the Crown room C2
(world rect (0, 0) to (1024, 896), floor x 64 to 1024, y 192 to 896): its origin goes at the floor
centre (512, 544).
- `BossCampScript`: `map_id` "weaver-hollow-crown", `camp_id` "weaver-hollow-matron", `boss_id`
  "orb-weaver-matron", `boss_scene` `character.orb-weaver-matron`, `spawn` (0, −144) (her shadow at
  (512, 430), in the web's middle), `respawn_ms` −1 (once beaten she never comes back: no timer is
  stored, and `is_boss_defeated()` keeps the camp from spawning her again, in a camp built again
  too), `boss_overrides` {`cocoon_enabled`: true, `arena_recovery_ms`: 0} (no heal after a while
  outside the arena), no guarded chest.
- Activation: a rectangle 960 × 608 centred at (32, −48) (the floor from the top wall down to 96 px
  above the bottom wall: she spawns once the slime is in). Arena: a rectangle 960 × 704 centred at
  (32, 0) (the whole floor, so she never walks home and her volleys clamp into the room).
- The shutters' hook (the dungeon kit's): the camp's `boss_engaged {campId, bossId}` on her spawn and
  `boss_defeated {campId, bossId}` (with `boss_disengaged {campId, defeated: true}`) on her fall; a
  slime that dies resets the fight (section 4.5), and she spawns again when it comes back in.
- **Placed** (2026-10-17) in `weaver-hollow-crown` as `Objects/matron-camp` at (512, 544), built by
  `tools/build_weaver_hollow.gd` (an editable instance): its `boss_engaged` is connected to the
  `shut` and its `boss_defeated` to the `open` of `Objects/crown-shutter`, the kit's shutter in C2's
  south doorway (at (512, 832), `wall` south), so the slime cannot leave while she fights. The way
  out east (C2's east doorway, to C3's drop) holds the Hollow's seal (`Objects/crown-east-seal`,
  `object.dungeon-seal`, `wall` east, at (960, 512)) from Pearl 2's take until her fall, so her web
  wall in C3 cannot let a silk-skinned slime out first. A slime that faints resumes at the dungeon's
  entrance in the Trunk (the kit's Dungeon node).
- Children: `RoarSfx`, and her rewards (8.6, 8.7), which wait hidden until `orb-weaver-matron` is
  in RunState `defeated_boss_ids`: `FullHeart` (`object.full-heart`) at (112, −96), `MatronThread`
  (`object.matron-thread`) at (−256, −296), its spool hanging in her web by the top wall. Move them
  in the world scene (editable children). Pearl 2 is no longer one of them (8.5).

### 8.5 Pearl 2 and the Silk skin (`object.pearl-two`)
**Since 2026-10-17 it lies in the Weaver Hollow's Hoard** (the boughs' `Objects/pearl-two`, on the
brood's altar beside the big chest, `take_radius` 90), guarded by the Brood Warden's room fight: it
rises when that fight is won, and its take seals the Hollow until the Matron falls
([DUNGEONS.md "The Weaver Hollow (built)"](../DUNGEONS.md#the-weaver-hollow-built)).
`game/scenes/objects/pearl-two.tscn`: `game/scripts/pearl.gd` (Fatty's Lair's Pearl script) with
`pearl_id` "orb-weaver-matron", `boss_id` "weaver-hollow-brood-warden", `number` 2, `skin_id` "silk",
its card ("Silk skin": webs no longer catch or stick; floor webs at full speed, web walls slowly, the
Spear cuts silk) and the picture `256x256-pearl-silk.webp` at 0.28. Walking into it (40 px) takes it:
the ceremony's card (while main's `ability_ceremonies` is on), the flag `pearl.orb-weaver-matron`,
and the Silk skin (SkinState.grant: won, its ceremony line the first time when no card shows; the everyday look stays as
it was, the skin shows only while it works;
[SKINS.md](../SKINS.md)). `player.crosses_webs()` is true from then on, so every web rule that reads
it (5.5, WEBS.md) treats the slime as silk-skinned. The interact key does not take it (pearl.gd takes by walking in).

### 8.6 The full heart and the max-energy raise (`object.full-heart`)
`game/scenes/objects/full-heart.tscn` (`game/scripts/full_heart.gd`; the goo heart's picture at
0.62), set in the camp to `heart_id` and `boss_id` "orb-weaver-matron", `raises_max_energy` on.
Walking into it (40 px) once she is beaten: `player.grant_full_heart()` (RunState
`add_full_heart`: `player.full_hearts` + 1; `max_hp()` = `stats.maxHp` + goo hearts × 10 + full
hearts × 20; HP fills), then `player.grant_max_energy(20)` (RunState `add_max_energy`:
`player.max_energy_bonus` + 20; `max_energy()` = `stats.maxEnergy` + the bonus; energy fills; the
player reads it in `restore_run_state`), "+20 max HP, +20 max energy", `Heal`, and the ceremony's
"Full Heart" card. The flag `full-heart.orb-weaver-matron` keeps it taken: once per run, saved with
the run's `player` record. The HUD's life orb shows a whole heart pip per full heart too.

### 8.7 Her thread (`object.matron-thread`, question 106)
`game/scenes/objects/matron-thread.tscn` (`game/scripts/matron_thread.gd`): the spool
(`128x128-matron-spool.webp` at 0.42) hangs `hang_px` (90) over its root on a strand rising
`strand_top_px` (200) into her web. Its hurtbox (tags `barrier`, `web`) refuses every hit with a
clink while she lives; after her fall, without the Silk skin, a clink and "Sticky silk holds it fast.
You need a way with webs." (it never names the skin); with it (`crosses_webs()`), a weapon's hit (tags
`weapon` or `spear`: the Spear) cuts the strand: "The strand parts!", `WebTear`, the spool drops
(`drop_ms` 320). Walking into the dropped spool (34 px) puts the story item `matron-thread` (items.json,
category "story", icon `items-matron-thread`) in the bag with its ceremony card and sets the flag
`matron-thread.taken`: taken once, for good, saved. The cut alone is not saved. A full bag leaves it
on the floor ("Your bag is full."). The interact key does nothing to it.

### 8.8 Tests
`tests/test_matron.gd` mounts the Hollow's camp where the nest was (the nest's camp freed first):
the cocoon and its clinks, a blast on her shadow and one that misses it, the 4 s window and the 1.5 s
respin, the three rounds (one big hit takes 100, round 2's ring, round 3's sacs), no respawn (and the
brood bursting), her camp holding no Pearl, the Silk skin's exam
(`test_with_the_silk_skin_round_two_cages_her_and_round_three_webs_the_floor`: the cage's eight
walls, a bomb stuck against it, the Silk slime wading in, a cut wall spun again without a flag,
round 3's webbed floor, gone with her), the full heart +20 once (and through a save), the thread
only with the Silk skin. Pearl 2 in the Hoard: `tests/test_weaver_hollow.gd`.
`tools/render_matron.gd` renders the fight's moments in the Crown for the look (run windowed);
`tools/film_weaver_hollow.gd` films her three rounds (`--only=matron`).

## 9. The ram fight (the rework, built 2026-11-24 in a lab, not yet in the Hollow)

Step 2 of the [dungeons 2 and 3 rework](../../design/2026-11-23-dungeons-2-3-rework.md#the-orb-weaver-matron),
with the owner's changes of 2026-11-24 (his drawing of the room: five rams along the north wall,
their targets roped across the room; "the rams can't be there only to damage the boss, they are
demolition tools ... now he can use them as well to damage us"; her cocoon over one ram's lane, at
random; "one of her attacks also activate rams to try to hurt you"; "make matron's projectiles and
webs bigger to match her size"). Her own scene, `character.orb-weaver-matron-rework`
(`game/scenes/characters/orb-weaver-matron-rework.tscn`: the Matron's scene with the script
`game/bosses/matron_ram.gd`, `MatronRamScript extends MatronScript`, the cocoon fight on and her
volley's radius 84). `world.matron-lab` places her, and since 2026-11-25 the rebuilt Hollow's Crown
(`world.weaver-hollow-c2-crown`), which the game enters since the switch-over of the same day:
`encounter.weaver-hollow-matron`'s own values are hers (`boss_scene` this scene, `map_id`
`weaver-hollow-c2-crown`, `spawn` (0, −30), the lab's wake and arena shapes, her heart and thread where
the lab has them), the lab's arena carried into the room at the lab's coordinates, nothing of hers
changed ([DUNGEONS.md "The Crown"](../DUNGEONS.md#the-crown-step-3s-third-piece-2026-11-25), [the
switch-over](../DUNGEONS.md#the-switch-over-2026-11-25); its films: `tools/film_crown.gd`). Today's
Crown keeps section 8's fight through a copy of the encounter. matron.gd changed only by the hook
`_runs_ai()` (the base step runs from inside the cocoon; her subclass adds hanging free).

### 9.1 The fight
- **The rams are both sides' tools.** The slime trips a ram (a throw at its knock target) at her;
  she trips one at the slime: **her ram call** (`_step_ram_call`): while she can attack (in her
  cocoon or hanging free), the slime stands in a ready ram's lane (`lane_margin_px` 8) whose target
  is armed, and `ram_call_every_ms` (4500) has passed (the first `ram_call_first_ms` 3500 after her
  fight starts), she spits a glob of web at that target (`game/bosses/web_glob.gd`: an arc of
  `ram_call_flight_ms` 450, `MatronHiss`; it knocks the target with its `strike()`); never the ram
  whose lane her own cocoon hangs over. The slime sees the glob fly and the ram shudder (0.35 s) and
  steps off the lane. **She calls one from the floor too** (round 2, after a dive; the owner,
  2026-11-24: "she can trigger the tramp even from the ground after jumping at you, that way the
  player can trick her to make her hit her self"): once per landing, `ground_call_after_ms` (600)
  after she lands, whenever the slime stands in a ready ram's lane, **her own lane too**, whatever
  `ram_call_every_ms` says (it restarts from this call). She spits from where she lies (the spit
  frames on the floor) and then stays down at least `ground_call_stay_ms` (1000) after the glob
  lands, past the ram's shudder, swing and hold (`dungeon.ram` 350 + 420 + 150), so a log she
  trips down her own lane always reaches her: a slime that waits in her lane and steps out when she
  spits makes her fling herself (the ram's catch below).
- **Every cocoon hangs over one ram's lane**, the middle of it, picked at random (`get_rams`, the
  mechanisms with a lane in her arena; `_pick_home`), never the lane she just hung over: at her first
  step she moves there; at each respin, when the new lane's middle is more than a few units away,
  she climbs to the cocoon's hang (`climb_ms`, less when she is already up) and crawls along her web
  to it (`relocate_speed` 320, shell "relocating": out of reach like hanging, no attacks), and only
  then spins it there (the whole respin is the spin): a cocoon always closes over its lane, wherever
  she lay (from the far west lane to the far east one about 4 s). Up on her web (hanging, climbing,
  crawling, spinning, in her cocoon, diving) her body collides with nothing, so the slime or a
  target's post on the floor never holds her; down on the floor (landed, flung, open, her cocoon
  knocked down) it collides with the world, the slime and water again (`_set_shell`). Each ram's
  target stands straight below its lane, its rope running up the lane to the ram (the owner,
  2026-11-24: "they should align vertically with the ram ... player can't even see where the
  trigger connects since the scene is too big").
- **Round 1** (above `round_two_below_hp` 200): the low cocoon (`ram_hang_px[0]` 60) breathes and
  volleys as built; a Goo Bomb on its shadow tears it (8.2), and its lane's ram **knocks it down
  whole** (below). Open, she lies dazed `open_ms` (4000).
- **Round 2** (above 25 in the ram fight's scene): no cocoon. At round 1's floor she climbs up (`climb_ms` 1100) and
  **hangs free** (`ram_hang_px[1]` 200 over her shadow), out of reach (hits clink, `high_text` "Out of
  reach up there."). She crawls along her web over the slime (`reposition_speed` 150), spits (the
  base attack, from her mouth up there) and every `dive_every_ms` (3600; the first `first_dive_ms`
  1800 after she reaches the hang) **dives** where her shadow lies: `dive_ms` 900 (her shadow grows as
  she falls), `dive_damage` 40 to a slime within `dive_radius_px` 64, `MatronImpact`; she lies
  `landed_ms` 4000 (the owner, 2026-11-24: "she stay fo 4 secodns so you have time to trigger the
  tramp"; 900 before), catchable by a ram the whole time but glancing every hit off (each with `landed_text` "Her shell
  turns it. A ram would crack her.", at most every 1.5 s; diving and flung stay silent), calls a ram
  from the floor (above), and climbs back. She **rings every knock target in her arena** with web walls
  (`object.web-wall`, a square of half side `target_ring_radius` 70, spun again every `ring_reweb_ms`
  5000 where cut, never where the slime stands): a throw from outside stops in the silk; the slime
  wades in (the Silk skin) or cuts a window (the Spear). **A ram that catches her** (`on_mechanism_hit`
  kind `ram`, from `dive_catch_from` 0.3 of the dive, or landed) flings her along its lane
  (`fling_speed` 1100, until a wall or the arena's edge stops her, at most `fling_max_ms` 650,
  `MatronShriek`): she crashes on her back (`ram_blow_damage` 20, a big number, a shake) and is open
  `open_ms`; then she climbs back up, or at the round's floor spins a new cocoon.
- **Round 3: her last hit** (the owner, 2026-11-24: "phase 3 is only when she have a hit left"):
  the ram fight's scene (`orb-weaver-matron-rework.tscn`) starts it at `round_three_below_hp` **25**
  (the built fight's 100 stays on matron.gd), and open in it the first hit that lands takes all she
  has left (`mitigate_damage`), whatever it is. The cocoon hangs high (`ram_hang_px[2]` 170) over a
  lane: a blast cannot reach it (`blast_reach_px` 100; `high_cocoon_text` "Too high for a blast.
  Knock it down first."). The floor webbed (the Silk skin) and the two egg sacs, as built (a ram on
  its lane hits the sacs too). **No volley in round 3** (the owner, the same day: "in phase 3 mattron
  not longer use if frist grounf web attack , is too many attacks"; `volley_in_round_three` off):
  she keeps to her spit, her ram call and her brood; each time a volley comes due it is put off a
  `volley_cadence_ms`.
- **A cocoon knocked down** (any round, its lane's ram, `_knock_down`): it falls (`downed_fall_ms`
  260) and is knocked `knock_down_px` 70 along the lane, `MatronShriek`, then lies whole on the floor,
  straining, solid, for `downed_ms` (9000; a bomb's fuse takes 3 s, with no cast since 2026-11-24); a blast on it (its
  middle within the blast's ellipse: lay the bomb beside it) tears it and she spills out dazed, open
  as in round 1. Else she cuts herself free and spins again over another lane; the husk stays where
  it lay and fades.
- **Thrown things** hurt her for `thrown_damage_share` 0.5 of a Spear hit (`shapes.spear.baseDamage`)
  whenever she is open, as Fatty's eye.
- **Her missed webs are ammo** (the owner, 2026-11-24: "the webs that she miss should be throwables
  in case we ran out of pot", as Fatty's mud balls): every mark of a volley that missed the slime
  (`_land_volley`) and every spit that missed it (it ended on a wall or at its range:
  `ProjectileScript.did_hit_target()`) leaves a **web ball** where it landed: a liftable of kind
  `web_ball_kind` ("web-ball", `game/data/liftables.json`, material soft, `kindEffects` stick as the
  mud ball), sucked in and thrown like a pot (a knock target, her when open), leaving nothing where it
  lay. It pops in, never lands within 48 of the slime, stays inside her arena; at most
  `max_web_balls` (6) lie at once, the oldest unravelling (flattens and fades, no longer suckable).
  `get_web_balls()` lists them. A volley's mark that hit the slime leaves only its patch.
- **Her size** (the owner): her spit's projectile is `spit_scale` 2 times its scene (picture and
  hitbox), her volley's web patches `patch_scale` 1.6 times (picture and slowing circle, with her
  volley's marks at radius 84), her glob `glob_scale` 2.

### 9.2 Her look and sounds
`game/bosses/matron_ram_look.gd` (`MatronRamLook`, made at her first step under her body): her shadow
(shrinking and paling with her height), her thread from her top to the web, her pose and the fallen
cocoon, drawn by `game/bosses/boss_sheet_sprite.gd` from her packed frames
(`res://asset/MAPS/enemies/bosses/matron/`, `frames.json`; `python scripts/art/boss_frames.py pack
matron`; sources and prompts `asset/Originals/dungeon-kit/bosses/matron/`): hanging (a loop), the
spit (her ram call shows it too, hanging or from the floor), the dive (let go, falling, legs wide, landed), rammed (struck,
flung, tumbling, crashed), on her back kicking (a loop), climbing (a loop), spinning her cocoon,
the cocoon on the floor (knocked down, straining, torn), dazed (dropping out, two dazed, a flinch).
The hanging whole cocoon is still matron_cocoon_look.gd's (its breath in code). Sounds: Sound Picker
round 16 ([audio spec](audio.md#18-round-16-the-two-bosses)): `MatronHiss`, `MatronShriek`,
`MatronImpact`.

### 9.3 The lab and its films
`game/dev/bosses/matron-lab.tscn` (`world.matron-lab`; `?map=matron-lab`, `-- --map=matron-lab`, or F6
on it; `dungeon.devPowers.matron-lab` lends the Spear, the Roll, the Heavy and Silk skins and the
Goo Bomb), built by `tools/build_matron_lab.gd -- --force`: one root-rock room, its floor 20 x 16
cells; five rams along the north wall swinging south (lanes 9 cells long), each ram's target straight
below its lane by the south wall (2026-11-24; first built where the owner drew them, spread round the
room with the ropes crossing, too hard to follow in a room this big), its rope up the lane; her camp
in the middle (`respawn_ms` 4000 so she comes back for another try), her full heart rising in the
middle of the floor when she falls (the owner, 2026-11-24; it stood by the south wall before);
twelve pots between the lanes and between the targets.
`bash scripts/godot/film-matron.sh <name> --film=<film>` films it frame by frame into
`output/boss-rework/matron-films/<name>/` (`tools/film_matron.gd`, one game window at a time):
`bombs` (the Goo Bomb with no cast: a press inside its 1 s cooldown refused, three bombs lying at
once), `crush` (the Heavy Roll through three Broodlings made by the tool: each popped, no bonk;
docs/godot/SKINS.md "The Heavy Roll"), `quiet3` (round 3 left to play: no volley), `round1`, `dive` (the slime in a gap between two lanes;
`landed_for_ms` notes her time down),
`ram-catch`, `ground-call` (she dives on the slime in the second lane; it steps down the lane and
waits; she spits at that lane's target from the floor, the slime steps out of the lane and her own
log flings her: on her back, the Spear and a pot), `ring`, `round3` (with `--lie=south` or `--lie=west` she lies by the
south wall or on the far west lane and her new cocoon's lane is staged as the farthest; `--lie=slime`
puts the slime on that lane's middle, `--lie=post` sends her line through a target's post; the notes
give her x at the close against the lane's middle), `ram-call`, `web-balls` (the pots taken away: her
volley misses, the slime throws a web ball at her lane's target and the ram knocks the cocoon down;
then one more ball drops and `web_balls_after_throw` counts the list, the sucked ball being freed),
`look`. The films stage her health where they start past round 1, keep the slime topped up, and hold
her attacks (and burst her brood) while the slime casts a bomb or picks up a pot; each notes what it
staged. They draw the liftables from the sheet's file (`_fresh_sheet`), so a sheet repacked since the
editor last imported it shows.

### 9.4 Not yet
Played only by the films, never with a keyboard; no tests written for it (`tests/test_matron.gd`
covers section 8, and its Hollow tests build `encounter.weaver-hollow-matron`, which is this fight
since the switch-over: they fail until step 5 rewrites them). The rebuilt Crown (C2) places her, and
the game enters it since the switch-over (2026-11-25).
