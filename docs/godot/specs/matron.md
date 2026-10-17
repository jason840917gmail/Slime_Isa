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
  the Silk skin's stand-in, the full heart, the max-energy raise, her thread). The open-world nest
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
  longer roots either). The Silk skin is not built (roadmap 7.8): today its stand-ins are the story
  flag `skin.silk`, which Pearl 2 sets (section 8.5; `player.gd` `SILK_SKIN_FLAG`), and the Silk
  Gulp form (Sticky).
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
and `game/scripts/boss_camp.gd` (`respawn_ms` below 0, `boss_overrides`).

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
- **Beaten:** her egg sacs and the Broodlings of her arena burst; the cocoon unravels and its thread
  draws up into the web; she shrinks into an ordinary big orb-weaver (the orb-weaver's sheet, from
  behind) and scuttles `retreat_px` up through her web, fading at the end (the body frees itself
  after 2 s, as in section 4). The camp's defeat bookkeeping is section 4's.
- Not built: the three-way Stretch Lash that pulls and traps (roadmap 8.7's plan of 2026-10-02):
  she keeps the web spit (1.4).

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

### 8.4 The Weaver Hollow's camp (`encounter.weaver-hollow-matron`)
`game/scenes/encounters/weaver-hollow-matron.tscn`, for the Crown room C2 (world rect (0, 0) to (1024,
896), floor x 64 to 1024, y 192 to 896): its origin goes at the floor centre (512, 544).
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
  south doorway (at (512, 832), `wall` south), so the slime cannot leave while she fights. A slime
  that faints resumes at the dungeon's entrance in the Trunk (the kit's Dungeon node).
- Children: `RoarSfx`, and her rewards (8.5 to 8.7), which wait hidden until
  `orb-weaver-matron` is in RunState `defeated_boss_ids`: `Pearl` (`object.pearl-two`) at (0, −114)
  (her shadow: "Pearl 2 lies in the silk at the web's heart"), `FullHeart` (`object.full-heart`) at
  (112, −96), `MatronThread` (`object.matron-thread`) at (−256, −296), its spool hanging in her web by
  the top wall. Move them in the world scene (editable children).

### 8.5 Pearl 2 and the Silk skin (`object.pearl-two`)
`game/scenes/objects/pearl-two.tscn`: `game/scripts/pearl.gd` (Fatty's Lair's Pearl script) with
`pearl_id` "orb-weaver-matron", `boss_id` "orb-weaver-matron", `number` 2, `skin_flag` "skin.silk",
its card ("Silk skin": webs no longer catch or stick; floor webs at full speed, web walls slowly, the
Spear cuts silk) and the picture `256x256-pearl-silk.webp` at 0.28. Walking into it (40 px) takes it:
the ceremony's card (while main's `ability_ceremonies` is on), the flags `pearl.orb-weaver-matron`
and `skin.silk`. **The Silk skin's stand-in:** `player.crosses_webs()` is true once the run has
`skin.silk` (as for the Silk Gulp form), so every web rule that reads it (5.5, WEBS.md) treats the
slime as silk-skinned. The interact key does not take it (pearl.gd takes by walking in).

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
brood bursting), Pearl 2 → `crosses_webs()`, the full heart +20 once (and through a save), the thread
only with the Silk skin. `tools/render_matron.gd` renders the fight's moments in the Crown for the
look (run windowed).
