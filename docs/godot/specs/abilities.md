# Abilities, Gulp forms and ability puzzles: spec for the Godot port

Covers what [player.md](player.md) skipped as **[OUT]** (its §12): Jump, Stretch Lash, Squash Slam,
Teleport, the shared ability rules and energy, Eat/Gulp and the Gulp forms (Heavy, Sticky), the
passive Goo Trail, and the world scripts that react to abilities: `game.gulp-spot`,
`game.pressure-plate`, `game.cracked-ground`, `game.lash-bell`, `game.ability-lesson`,
`game.training-dummy`, `game.goo-heart`, `game.restoration-site` (plus what `game.spider-web` /
`game.web-patch` and `game.gate` need from this side).

Sources read (read-only): `src/game/features/player/{PlayerAbilityController,PlayerAbilityService,
PlayerAbilityDefinitions,PlayerAbilityPresentation,PlayerController,PlayerInputActions,PointerAim,
ControlLabels}.ts`, `src/game/infrastructure/scenes/compatibility/LegacyPlayerAbilityPresentation.ts`,
`src/game/features/combat/LineStrike.ts`, `src/game/features/world/UniversalSceneWorldController.ts`,
`src/game/scenes/WorldScene.ts`, `src/game/features/gulp/{GulpController,GulpHud,GulpWheel,
GulpWheelLayout}.ts`, `src/game/content/gulp/gulpForms.ts`, `src/game/content/abilities.ts`,
`src/game/features/scripts/{GulpSpot,PressurePlate,CrackedGround,LashBell,AbilityLesson,
TrainingDummy,GooHeart,RestorationSite,SpiderWeb,WebPatch,Gate,StoryFlag}Script.ts` and
`registrations.ts`, `src/game/features/ui/AbilityBarSurfacePort.ts`, `src/game/features/feel/{GameFeel,
SquashStretch,ParticlePresets,SlimeTrail}.ts`, `src/game/features/audio/AudioEventBridge.ts`,
`src/game/features/progression/StoryProgress.ts`, `src/game/core/{GameState,EventBus}.ts`,
`src/game/systems/PlayerStats.ts`, `src/game/runtime/scene/physics/SensorGeometry.ts`,
`src/game/infrastructure/scenes/PhaserNodeContext.ts`, the quest catalogue, the authored object and
world scenes, `asset/assets.json`; on the Godot side `godot/game/scripts/player.gd`,
`godot/game/player/*`, `godot/game/combat/*`, `godot/game/feel/*`, `godot/game/autoload/*`
(including `run_state.gd`), `godot/game/characters/player_slime.tscn`, `godot/project.godot`,
`godot/tests/**`, and the converted `godot/game/scenes/objects/*.tscn`.

Line numbers are `file:line` in the current `feat/godot-migration` tree. Paths without a folder are
under `src/game/`.

Legend: **[IN]** port now, **[OUT]** exists in Phaser, deferred (listed so later phases know),
**[QUIRK]** the Phaser build behaves differently from what its code/comments/descriptors say, or
oddly; a decision may be needed. **[CENTRE]** uses the Phaser body position = the old sprite centre
(Godot root = feet; use `get_centre()` / `FeetAnchor`, player spec §11).

## Port status (2026-10-05)

Ported: the shared rules and energy (`game/player/abilities/player_abilities.gd`,
`ability_definitions.gd`; player.gd `energy_changed`, regen, respawn refill), Jump, Squash Slam,
Teleport and Stretch Lash (`*_sequence.gd`, `ability_terrain.gd`, `ability_world.gd`,
`ability_fx.gd`; the lash's light catch pulls piles now that collectibles exist), the dodge on the
shared rules, Eat and the Heavy / Sticky forms (`game/player/gulp/`: speed, knockback immunity,
plates and cracked ground, the tint fallback, the timer and `[Q] Gulp` hint), and the eight world
scripts of section 13 (gulp spot, pressure plate, cracked ground, lash bell, ability lesson,
training dummy, Goo Heart, restoration site; the last two use the interaction controller).
Later the same day: the status effects with the web root (`game/player/status_effects.gd`), the Goo
Trail passive (`game/player/goo_trail.gd`), the ability bar on the HUD (`game/ui/ability_bar.gd`,
§2.6), the Gulp quick wheel (`game/player/gulp/gulp_wheel.gd`, §11.6; the hold runs on the
simulation clock and a window closes it) and the form badge on the Gulp timer.
Tests: `test_abilities.gd`, `test_gulp.gd`, `test_world_puzzles.gd` (the last two run in the
playground through the runner's per-file `MAP_ID`), `test_status.gd`, `test_goo_trail.gd`,
`test_ability_bar.gd`.

Differences from this spec's Phaser behaviour, until decided otherwise:
- Sequence milestones run on the simulation clock (O-A4), so hit-stop and menus pause them.
- Restoration quests: `RunState.is_quest_active` is false until the quest phase, so the two
  level-1 ruins show their locked message (tests list the quest in
  `RunState.debug_active_quests`).
- The hop, squash (slam), teleport, eat and knockback clips are keyed on page 1's top-down
  frames, per direction (`tools/build_player_clips.gd`, `ACTIONS` and `POSES`; owner decision
  2026-10-05: keys from the new art). They only choose frames (crouch, spring, brace, open
  mouth...); the sequences' tweens still squash, stretch, lift and fade the art. The lash is
  filmed (Seedance): `stretch-down`, `-up`, `-side` and `-left` are page 2's rows 3-5, a 270 ms
  reach and pull back (the slime's own short jelly arm; the up lash stretches its sprout). The
  lash and the teleport turn the slime toward their direction (§3.2). The lash tendril was drawn
  unplaced at the world origin for every lash but a pull until 2026-10-05 (fixed; tested). The
  Heavy and Sticky skins are painted by a shader over the new frames
  (`game/player/gulp/form_skin.gdshader`: grey cobbles, cream silk; owner decision 2026-10-05)
  instead of Phaser's redrawn side-view sheets.

---

## 0. Ownership map in Phaser

| Phaser object | Role |
|---|---|
| `PlayerAbilityDefinitions.ts` | The ability table (literals, not game constants) |
| `PlayerAbilityService.ts` | Rules: busy / learned / cooldown / action-locked / energy; cooldown clocks; sequence ids; jump trace; teleport safe landing |
| `PlayerAbilityController.ts` | Facade created by `WorldScene` (`WorldScene.ts:374-395`): wires the service to `storyProgress`, `gameState` energy, the terrain grid and Arcade `overlapRect`; `status()` for the ability bar; `tryDodge` |
| `PlayerAbilityPresentation.ts` | Owns one presentation "lease" at a time; `complete` vs `dispose` |
| `LegacyPlayerAbilityPresentation.ts` | The actual sequences (tweens, timers, effects) of Jump, Teleport, Squash Slam, Stretch Lash; rejection feedback |
| `UniversalSceneWorldController.ts` (`lashProbe`, `lashRing`, `lashPull`, `strikeArea`, `lineReach`) + `WorldScene.lashLanding` | The world side of the lash and the slam (`AbilityWorldPort`, `LineStrike.ts:32-42`) |
| `WorldScene.updateGameplay` / `handleActionInput` / `useAbility` / `updateEatHold` | Input dispatch order, aim, energy regen, eat tap/hold |
| `GulpController.ts`, `gulpForms.ts`, `GulpHud.ts`, `GulpWheel.ts` | Gulp forms, eating, timer and hint, quick wheel |
| `WorldScene` closures (`plateWeights`, `groundCrack`, `gooHearts`, `abilityLessons`, `lashBells`, `trainingDummies`, `spiderWebs`, `restoreSite`; `WorldScene.ts:2336-2377`) | The services the world scripts read (`UniversalSceneWorldController.ts:657-662`) |
| Scene scripts in `features/scripts/` | The puzzle objects (§13) |

Godot has today: `player.gd` (movement, dodge roll with its own learned/cooldown checks, health,
knockback; `_action_locked` shared with `PlayerCombat`), `PlayerInputBuffer` (captures only
move/attack/sprint/dodge), `PointerAim` (unit vector only, no distance), `SquashStretch` (presets
`move-start`, `hit` only), `GameFeel` (presets include `slam`, `ground-crack`,
`building-restored` already), `ParticleFx` (`hit-spark`, `slime-splash`, `dodge-dust`, and in the
working tree `boss-burst`), `DamageRouter` (no "list all areas" call), `RunState` autoload
(story flags, learned abilities, inventory count/remove, `max_hp()` with Goo Hearts,
`story_flag_changed` / `ability_learned` signals), `story_flag.gd` / `story_variant.gd` (world
objects, in progress). The input map already has `jump` (Space), `stretch_lash` (2),
`squash_slam` (3), `teleport` (4), `eat` (Q), `interact` (RMB) (`project.godot`).

---

## 1. The ability table [IN]

`PlayerAbilityDefinitions.ts:39-46` (literals; the comment at `:31-38` says they stay in the player
feature "until promoted into game constants"). Only the dodge reads `game-constants.json`.

| id | title | action (key) | earnedBy (ability bar) | cooldownMs | energyCost | distance | durationMs | radius | damage |
|---|---|---|---|---|---|---|---|---|---|
| `jump` | Jump | `jump` (Space) | Quest | 700 | 0 | 168 | 420 | — | — |
| `dodge` | Dodge | `dodge` (1) | Quest | `dodgeDurationMs + dodgeCooldownMs` = 500 + 250 = **750** | 0 | — | 500 | — | — |
| `teleport` | Teleport | `teleport` (4) | Later | 1800 | 35 | 240 | — | — | — |
| `squash-slam` | Squash Slam | `squash-slam` (3) | Boss | 2500 | 30 | — | — | 90 | 30 |
| `stretch-lash` | Stretch Lash | `stretch-lash` (2) | Quest | 2000 | 20 | 180 | — | — | — (no damage, `:44`) |

Passive (`PlayerAbilityDefinitions.ts:58-60`): `goo-trail` "Goo Trail", learned text
"Goo Trail learned: enemies on your goo slow down". No key, no bar slot.

Ability ids, in key order: `PLAYER_ABILITY_IDS = ['jump','dodge','teleport','squash-slam','stretch-lash']`
(`content/abilities.ts:8`); the dispatch order (§3.1) and the ability bar order (§2.6) differ.

Bindings (`PlayerInputActions.ts:18-23`): `jump` Space, `dodge` Digit1, `stretch-lash` Digit2,
`squash-slam` Digit3, `teleport` Digit4, `eat` KeyQ (all physical codes). Godot actions:
`jump`, `dodge`, `stretch_lash`, `squash_slam`, `teleport`, `eat` (already in `project.godot`
as physical keycodes 32, 49, 50, 51, 52, 81).

### 1.1 How abilities are learned [IN data, OUT quests]

- `storyProgress.knowsAbility(id)` (`StoryProgress.ts:35`) is the only "unlocked" test
  (`PlayerAbilityController.ts:53`). There are no levels.
- A new run knows nothing. Teachers: quest rewards (`QuestService.ts:105` →
  `storyProgress.learnAbilities`): Chapter 1 quest `stone-tools` "Stone Tools" → `dodge`
  (`content/quests/quests/chapterOne.ts:145`), `worm-trouble` "Worm Trouble" → `jump`
  (`chapterOne.ts:194`); Chapter 2 `beyond-the-verdant-gate` → `stretch-lash` (`chapterTwo.ts:49`),
  `the-matrons-nest` (boss reward) → `squash-slam` (`chapterTwo.ts:267`). **Nothing teaches `teleport` or
  `goo-trail`** (dev panel only, `devTools.ts:372-385`). Quests are **[OUT]**.
- `game.ability-lesson` teaches on proximity (§13.5; the playground's lash yard).
- `learnAbilities(ids)` (`StoryProgress.ts:42-46`) adds only new ids and emits
  `ability.learned {abilityId}` per new id → audio cue `AbilityLearned`
  (`AudioEventBridge.ts:79`) and the area-title banner (`WorldScene.ts:483-491`):
  player ability → `"<title> learned: press <key label>"` (e.g. "Stretch Lash learned: press 2"),
  passive → its `learnedText`; colour `#9ff0c8` (`ABILITY_LEARNED_COLOR`, `WorldScene.ts:153`).
  Banner UI **[OUT]** (world spec §6.4); the cue is **[IN]**.
- Godot: read and write through `RunState` (`has_learned_ability`, `learn_ability`, signal
  `ability_learned {"ability_id"}`; `run_state.gd`). Keep `player.gd`'s `dodge_learned` export as
  the trial override (`is_learned(&"dodge")` = RunState or `dodge_learned`).

---

## 2. Ability rules (`PlayerAbilityService`) [IN]

### 2.1 Rejection order (`PlayerAbilityService.ts:93-100`)

```
rejection(id):
  if active_sequence_id != none            -> "busy"
  if not learned(id)                       -> "locked"
  if sim_now < cooldown_until[id]          -> "cooldown"      # strict: allowed again AT cooldown_until
  if action_locked                         -> "action-locked" # weapon swing, eat clip, any ability sequence
  if energy < definition.energy_cost       -> "energy"
  -> none
```

`cooldown_until` starts at 0 for every id and is per `PlayerAbilityService` instance, i.e. per
world: a map change resets every cooldown (new `WorldScene` → new controller). Godot: keep them
on the player instance (a travel respawns the player → same reset).

### 2.2 Sequenced abilities: `tryBegin` (`:102-141`) — jump, teleport, squash-slam, stretch-lash

```
try_begin(id, request{position (old centre), direction, facing, reach?}):
  r = rejection(id); if r: return rejected(r)
  dir = normalize(direction) if |direction| > 0 else normalize(facing)
        fallback when both zero: (1,0) for stretch-lash, (0,-1) otherwise          # :108, :196-200
  moving = |request.direction| > 0
  target = position
  if id == jump and moving:   target = trace(position, dir, 168, ensure_jump_movement=true)   # §5.2
  elif id == teleport:
      range = 240
      reach = range if request.reach is null/inf else min(range, max(0, reach))
      target = safe_landing(position, dir, reach); if none: return rejected("blocked")      # §7.2
  if energy_cost > 0 and not spend_energy(energy_cost): return rejected("energy")            # :120
  seq = next_sequence_id++ ; cooldown_until[id] = now + cooldown_ms ; active = seq
  set_action_locked(true)
  return accepted(intent{id, seq, direction: dir, start: position, target, definition, cooldown_until})
```

Note the jump direction is the movement keys, **not** the facing: with no key held the jump is
in place (`target = start`) even though `dir` falls back to the facing.

`complete(seq)` (`:143-148`): only for the active seq → `active = none`, `set_action_locked(false)`.
The controller then plays `slime-idle` (`PlayerAbilityController.ts:164`, through the
`WorldScene.playAnimation` gate: dropped while dead or inside the knockback window).
`cancel()` (`:150-154`): same without the idle (only on controller destroy or a thrown error).

The presentation (`PlayerAbilityPresentation.ts:36-51`) refuses a second presentation while one
is active (unreachable: `busy` rejects first). If `present` returns false the service is cancelled
but the cooldown and energy are **already spent** (`PlayerAbilityController.ts:170`) [QUIRK,
unreachable through the key path].

Lease semantics (`LegacyPlayerAbilityPresentation.ts:54-96`): natural completion keeps residual
effects alive (dust, the shadow's last tween, the squash spring); `dispose()` (scene shutdown
only) kills every tween/timer/object the sequence created and resets the visual effects
(offset 0, scale 1, alpha 1; `:105-108`). **Nothing cancels a sequence on hit or death** (§10).

### 2.3 Instant ability: `tryInstant` (`:84-91`) — the dodge only

Same `rejection()`, then spend energy (0), then `cooldown_until.dodge = now + 750`; the caller
then rolls (`PlayerAbilityController.ts:133-140`). A rejection other than `cooldown` goes to
`notifyRejected` (so a dodge on cooldown is silent; `busy` is silent too, §2.4).

### 2.4 Rejection feedback (`LegacyPlayerAbilityPresentation.ts:119-129`) [IN]

| reason | cue `AbilityDenied` | floating text at (centre.x, centre.y − 30) [CENTRE] |
|---|---|---|
| `busy` | no | — |
| `locked` | yes | "Not learned yet", red, not big |
| `cooldown` | yes for jump/lash/slam/teleport; **no for dodge** (`tryDodge` skips it) [QUIRK] | — |
| `action-locked` | yes | — |
| `energy` | yes | "Low energy", orange |
| `blocked` (teleport) | yes | "No safe spot there", orange |

The cue is `player.action {anim:'ability-denied'}` → `AbilityDenied` (`AudioEventBridge.ts:41`).

### 2.5 Status for the UI (`PlayerAbilityController.ts:95-110`) [IN data]

```
status(id) = {
  unlocked: learned(id),
  earnedBy: definition.earnedBy,
  cooldownRemainingMs: max(0, cooldown_until[id] - sim_now),
  busy: active_sequence_id != none,
  actionLocked: action_locked,
  insufficientEnergy: energy < energy_cost,
  canActivate: unlocked and cooldownRemainingMs == 0 and not busy and not actionLocked and not insufficientEnergy,
}
```

### 2.6 Ability bar data contract (`features/ui/AbilityBarSurfacePort.ts`) — screen [OUT], data [IN]

The `ui.ability-bar` surface (`content/scenes/authored/ui/ability-bar.scene.json`: five Buttons
Jump/Dodge/Lash/Slam/Teleport, bottom-centre, offsets −180..180 × −84..−12) reads a model every
frame:

- Slot order (`:8-14`): jump "Jump" (`jumpLabel`/`jumpDisabled`), dodge "Dodge", stretch-lash
  "Lash" (`lash*`), squash-slam "Slam" (`slam*`), teleport "Teleport".
- Label (`:37-45`), first match:
  locked → `"<earnedBy>\n<name>"`;
  cooldown > 0 → `"<s>s\n<name>"` with `s = (ceil(ms/100)/10).toFixed(1)` (e.g. 1234 ms → "1.3s");
  insufficient energy → `"Need <cost>E\n<name>"`;
  busy or action-locked → `"Busy\n<name>"`;
  else `"<key label>\n<name>"` (e.g. "Space\nJump", "2\nLash").
- Disabled (`:46`) = `not interactive or not canActivate`, `interactive = !paused && !dead`
  (`WorldScene.ts:2382`).
- Click (`:55-61`, handlers `on_jump_action` … mapped by the surface's `actions` property to the
  ability id) → only if interactive and `canActivate` → `WorldScene.activateAbilityFromUi(id)`
  (`:1705-1709`): returns if paused, dead, no system, or movement suppressed (roll/knockback);
  else `useAbility(id, rooted)` (§3.2).
- The authored button texts ("Lv 2\nJump", "Lv 4\nLash" …) are stale level-era placeholders,
  always overwritten by the model [QUIRK]. `src/game/ui/AbilityBar.ts` is dead code (never
  imported; it still says abilities are earned by levels).

Godot: expose `player.ability_status(id) -> Dictionary` (keys above, camelCase) and
`player.activate_ability_from_ui(id)`; the bar itself is **[OUT]**.

---

## 3. Input dispatch [IN]

### 3.1 Per-step order (`WorldScene.updateGameplay`, `WorldScene.ts:814-886`)

Additions to player spec §4.1 (in this order inside one fixed step):

```
finish_expired_action_animation(now)   # :819, the eat clip lock (§11.4)
gulp.update()                          # :826, form expiry on the sim clock
gulp_hud.update(...)                   # :827
energy regen if not dead               # :833-837, §4
if dead: close eat hold; stop; return
if sleeping: [OUT]
direction = movement keys
if movement suppressed (roll/knockback): move(direction) (no-op) ; return
if action_locked (swing, eat clip, ANY ability sequence): velocity = 0 ; return
if update_eat_hold(direction): stop ; return    # :871-876, true only while the quick wheel is open
if handle_action_input(): return                # §3.2
squash_on_move_start ; move(direction)
```

### 3.2 `handleActionInput` (`WorldScene.ts:1773-1829`)

```
(furniture placement mode [OUT] eats every ability press)
weapon-next / weapon-previous [OUT combat]
interact hold / interact press [interaction.md] -> returns true (the step is consumed) even with no candidate
for id in [jump, dodge, stretch-lash, squash-slam, teleport]:     # :1810, fixed order
    if consume_action_press(action(id)): use_ability(id, rooted); return true
if consume_action_press(attack): attack(); return true
if consume_action_press(eat): eat_hold = {since: scene_now, last_seen: scene_now, open: false, empty: false, entries: []}; return true
return false
```

`useAbility(id, stuck)` (`:1717-1735`), `stuck` = status `sticky` (rooted; spider web, status
effects **[OUT]**, keep the hook):

```
aim    = pointer_aim()        # unit vector + distance from (centre.x, centre.y - 28); undefined if pointer unseen or < 16 px  [CENTRE]
toward = aim ?? facing        # NOT snapped (only the dodge snaps)
jump:          if not stuck: try_jump(movement_direction)          # movement keys, not the pointer
dodge:         if not stuck and try_dodge(roll(snap_to_cardinal(toward))): hints.learn('dodge') [OUT]
stretch-lash:  try_stretch_lash(toward)                             # works while stuck [QUIRK: the pull then moves a rooted slime]
squash-slam:   try_squash_slam()                                    # works while stuck
teleport:      if not stuck: try_teleport(toward, aim?.distance)
```

A stuck press of jump/dodge/teleport is consumed with no feedback. No ability changes the facing
(only the dodge's `face()`). **Godot deviation (2026-10-05):** the lash and the teleport also
`face()` their direction, because their top-down clips are directional: a lash aimed down while
facing left would otherwise reach left while its tendril goes down.

Godot `PlayerInputBuffer.ACTIONS` must add `jump`, `stretch_lash`, `squash_slam`, `teleport`,
`eat` (and `interact` with the interaction spec). `PointerAim` must also return the distance
(`aimToward`, `PointerAim.ts:13-23`: `{x, y, distance}`).

---

## 4. Energy [IN]

| Value | Number | Source |
|---|---|---|
| Max energy | 100 | `character.player.stats.maxEnergy` |
| Regen | 8 per second of simulation | `character.player.stats.energyRegenPerSecond` (`PlayerStats.ts:49`) |
| New run | full (100) | `InitialRun` / `RunState.new_run` |

- Regen (`WorldScene.ts:833-837`): every fixed step while not dead, `regen(8 * delta_ms / 1000)`
  (`GameState.regenEnergy`, `GameState.ts:244-250`: clamps at max, emits `energy.changed
  {energy, maxEnergy, delta}`). It runs before the dead check of the state machine, so it also runs
  during swings, rolls, knockback, ability sequences and sleep; not while paused or in hit-stop
  (no fixed steps). Energy is a float (fractional regen).
- Spend (`GameState.useEnergy`, `:237-242`): false and nothing taken when `energy < amount`.
- Respawn (`GameState.revive`, `:216-222`): energy = max and `energy.changed` with
  `delta = maxEnergy` (100) → the `EnergyRestore` cue (threshold `delta >= 20`,
  `AudioEventBridge.ts:57, 77`) plays on every respawn next to `Respawn` [QUIRK].
- Saved in the run (`GameStateData.energy`); Godot `RunState.player.energy` exists.
- Godot today: `player.gd` reports `energy = maxEnergy` in `get_hud_snapshot()` (energy was OUT);
  the HUD refreshes only on `health_changed`. Needs `energy_changed` (§19.3).

---

## 5. Jump [IN]

### 5.1 Request

`tryJump(direction)` with `direction = playerController.readDirection()` (raw keys, e.g. (1,−1)),
from the old centre [CENTRE]. Energy 0, cooldown 700 ms from the press, duration 420 ms.

### 5.2 Target: `trace` (`PlayerAbilityService.ts:176-190`)

```
trace(start, dir, 168, ensure=true):
  steps = ceil(168 / 8) = 21
  last_valid = start
  for step in 1..21:
      d = step / 21 * 168          # = 8 * step
      p = start + dir * d
      if is_blocked(p): break      # TILES ONLY (below)
      last_valid = p
  if ensure and |last_valid - start| < 8: return start + dir * 12      # even into a blocked tile [QUIRK]
  return last_valid
```

`is_blocked(x, y)` (`PlayerAbilityController.ts:60-67`): tile `(floor(x/64), floor(y/64))` outside
the grid → true; else `isTileCollidable(tileId)` (water, deep-water, rock-wall). Godot:
`Services.world().is_solid_tile(floori(x / tile_size), floori(y / tile_size))` is the same test.

**[QUIRK] the jump ignores every object.** Walls, gates, houses, trees and rocks are placed
objects, not tiles (AGENTS.md "walls are placed object instances"), so a 168 px jump crosses any
wall thinner than that (the playground's stone-wall shapes are 54–70 px thick and a gate's doors
30 px, so the heavy gate's pen and the lash pen can be jumped into) and can land inside a solid
object. Teleport checks objects
(`isOccupied`), the jump does not. Also the centre-point test lets the landing body overlap a
blocked tile by up to 15 px (half the 30 px body). Phaser does not push a teleported body out
(Arcade separation needs motion); Godot's `ArcadeMover.move` depenetrates an overlapping body
on the next step (`arcade_mover.gd`, "a body that overlaps something … is pushed out even at
rest"). Owner question O-A1 (§18).

### 5.3 Sequence (`LegacyPlayerAbilityPresentation.ts:131-204`), times from the accepted press

| t (ms) | What |
|---|---|
| 0 | `player.action {anim:'ability-jump'}` → cue `Jump` (`:109`). Clip `hop` (loop, 11 fps, 0.818 s) via the playAnimation gate. Stop the body (velocity 0). Reset visual effects. Shadow ellipse 40×16, black, alpha 0.35 at **start (the old centre, not the feet)**, behind the slime (attachment slot −6) [CENTRE][QUIRK: it never moves with the jump]. |
| 0–210 | Effects offset → `(mid − start)` with `mid = (start + target)/2 − (0, 54)` (`JUMP_ARC_HEIGHT = 54`, `:23`), Quad.Out. Effects scale → jump stretch `(0.82, 1.35)` (reduce motion: `1 + (v−1)·0.35` = (0.937, 1.1225)), Quad.Out. Shadow alpha → 0.12, scale → 0.7, then yoyo back by 420 and destroyed. |
| 210–420 | Effects offset → `(target − start)`, Quad.In. Effects scale → `(1.18, 0.70)`, Quad.In. |
| 420 | Teleport the body to `target` (`WorldScene.teleportPlayer`, `:1584-1588`: stop, reset body). Effects offset 0, scale 1. `player.action {anim:'jump-land'}` → cue `Land`; `WorldScene` (`:446-452`) plays squash `land` **forced** (1.32, 0.72 → 1 in 220 ms Back.Out) and, if the Gulp form `pressesPlates` (Heavy), records `heavyLanding = {x, y (centre after the teleport), id: previous id + 1}`. 8 `goo-dust` particles at target (centre) [CENTRE]: lifespan 320, speed 20–60 any angle, scale 0.3→0, alpha 0.6→0, destroyed after 400 ms. `complete()` → unlock, `idle`. |

Path: the visual peaks 54 px above the straight line at t = 210; a jump in place goes straight up
54 px and back. The **body stays at the start for the whole 420 ms** (action-locked, velocity 0):
its hurtbox, the camera target, the plate weight point, web checks and enemy targeting all stay at
the start until the landing teleport [QUIRK, worth knowing for tests]. No i-frames. Facing is
unchanged.

Next jump: allowed at t = 700 (280 ms after landing). Energy 0.

Godot clip: `hop-down`, `-up` and `-side` (420 ms, once) key page 1's frames: a crouch, a spring
up, the rest pose at the top of the arc and a brace for the landing (`tools/build_player_clips.gd`,
owner decision 2026-10-05); the tweens above carry the arc and the squash and stretch.

---

## 6. Squash Slam [IN]

### 6.1 Sequence (`LegacyPlayerAbilityPresentation.ts:236-310`)

| t (ms) | What |
|---|---|
| 0 | cue `SlamWindup` (`ability-squash-slam`). Clip `squash` (loop 12 fps 0.667 s). Stop. Effects scaleY → 1.36 over 200 ms Quad.Out (scaleX untouched). |
| 200 | scaleY → 0.64 over 120 ms Quad.In. |
| 320 | **Impact** at the player's current centre [CENTRE]: ring circle r 10, `#86f0c3` alpha 0.5, tween scale → 9 (= radius/10, i.e. r 90) and alpha → 0 over 300 ms (linear), "reveal-effects" band (drawn over entities). `gameFeel.play('slam')` (shake 150 ms × 0.01, hit-stop 90 ms, `GameFeel.ts:41`). cue `SlamImpact` (`slam-impact`). `strikeArea` (§6.2). Legacy `hitboxPool` hit for the old `TargetDummy` class (dev cheat "dummy" only) **[OUT]**. Then scaleY → 1 over 150 ms Back.Out. |
| 470 (+ hit-stop) | `complete()`. |

Cooldown 2500 ms, energy 30. The hit-stop freezes the tweens (`WorldScene.ts:735-748`), so the
recovery ends 90 ms of real time later; on the sim clock it is still 470.

### 6.2 `strikeArea` (`UniversalSceneWorldController.ts:1391-1442`)

```
strike_area({ability_id: 'squash-slam', center, radius: 90, damage: 30, knockback: 320, weapon_tags: ['slam']}):
  source = 'ability.squash-slam' ; attack area token 'ability.squash-slam.area' = circle(center, 90)
  activation = activations.begin(source, [area])
  for each registered damage area (router):
      receiver = router.receiver(area)
      skip if receiver is the player, or the receiver's managed tags include 'resource' (trees, rocks; `managedTargetTags`, :2195-2206)
      skip unless one of the area's shapes intersects the circle (rect/circle exact test)
      at = area global position (enemies: the old centre; dummies/bells: their root)
      d  = |at - center| or 1 when 0
      request: weapon_id 'squash-slam', weapon_tags ['slam'], damage_types ['physical'], base_damage 30,
               effects [{knockback, 320}], impact {at, knock: (at - center)/d}      # zero vector when at == center
  route all requests in one router step; for each accepted with actual > 0: 'hit-spark' at (at.x, at.y - 12)
  activations.end(activation)
  if any accepted: gameFeel.play('hit')        # 65 ms; the 90 ms slam stop already runs (max wins)
```

- Not scaled by the attack stat, no crit, no combo (unlike the sword).
- Receivers: enemies, bosses (their rules may refuse: source/tag filters), training dummies,
  lash bells registered with `lashOnly: false` (none in content), destructibles. Not: the player,
  resources, lash-only bells (not registered).
- Example: worm swordsman 90 HP, no mitigation (`enemy.gd`): 90 → 60; knockback velocity
  `(320 + 120) × (1 − 0.45)` = **242 px/s**, stun `320 + min(280, 320 × 0.35)` = **432 ms**
  (enemy spec; same formula as the sword example in ARCHITECTURE §8).

Godot: `DamageRouter` has no "all areas" listing. Either add `registered_areas()` (combat
builder) or query physics: `PhysicsShapeQueryParameters2D` with a `CircleShape2D` r 90 at the old
centre, `collide_with_areas = true`, `collide_with_bodies = false`, mask = hurtbox layer
(value 8), `max_results` ≥ 64, then keep areas with `router.receiver_for_area(a) != null`,
receiver ≠ player, `"resource" not in router.tags_for_area(a)`. The router needs a real
`attack_area`: give the player a `SlamArea` Area2D (layer 0, mask 0, monitoring and monitorable
off, `CircleShape2D` r 90 at local `(0, −27.56)`) and use it with
`router.begin_activation(abilities_node, [slam_area])`, one `route()` per target, then
`end_activation`.

---

## 7. Teleport [IN]

### 7.1 Request

`tryTeleport(toward, aim?.distance)`: direction = pointer aim (unsnapped) or facing; `reach` =
the pointer's distance from the aim origin `(centre.x, centre.y − 28)` [CENTRE]. The landing is
measured from the **centre**, so with the pointer in range the slime's centre lands 28 px below
the pointer (`landing = centre + dir·d = pointer + (0, 28)`) [QUIRK, follows from decision O2's
aim origin]. No pointer (never seen, or within 16 px) → facing, reach 240.

### 7.2 `safeLanding` (`PlayerAbilityService.ts:166-174`)

```
for d = reach; d >= 32; d -= 8:            # MIN_TELEPORT_PX = 32 (:194)
    p = start + dir * d
    if is_blocked(p) or is_occupied(p): continue
    return p
return none -> "blocked"  ("No safe spot there", orange; no energy spent, no cooldown)
```

What lies between start and landing (water, a wall) does not matter. A reach < 32 (pointer 16–32
px away) always fails.

`is_occupied(x, y)` (`PlayerAbilityController.ts:68-77`): the player's Arcade body rect moved so
the centre is at (x, y): rect 30 × 26 centred on `(x, y + 14.56)`, tested with
`physics.overlapRect(..., includeDynamic=false, includeStatic=true)`; any enabled static body
counts (walls, houses, trees, rocks, gulp spots, dummies, bell posts, closed gate doors). Tiles
are not bodies in Phaser (handled by `is_blocked`), nor are the world bounds.

Godot: `intersect_shape` with a `RectangleShape2D(30, 26)` at `(x, y + 14.56)` (= the feet-anchored
`BodyShape` at `(0, −13)` for feet `(x, y + 27.56)`), mask 1, bodies only, excluding the player
body, and ignoring results under `ground/TileCollision`, the ground TileMapLayer (deep water's tile collision) and the runtime `WorldBounds` body
(parity: Phaser never counts them).

### 7.3 Sequence (`LegacyPlayerAbilityPresentation.ts:206-234`)

| t (ms) | What |
|---|---|
| 0 | Flash at start: circle r 10, `#72d8ff`, alpha 0.9 → scale 6 (r 60), alpha 0 over 260 ms Quad.Out (`spawnFlash`, `:426-440`). cue `TeleportOut`. Clip `teleport` (one-shot 12 fps 0.667 s). Stop. Effects alpha → 0, scale → 0.36 over 120 ms Quad.In. |
| 120 | Teleport the body to the landing. cue `TeleportIn` (`teleport-in`). Flash at the landing `#a3f0c0`. Effects alpha → 1, scale → 1 over 180 ms Back.Out. |
| 300 | `complete()`. |

Cooldown 1800, energy 35 (spent at the press, after the landing was found). No i-frames: the
hurtbox stays at the start for the first 120 ms.

---

## 8. Stretch Lash [IN] (light catch needs collectibles: **[OUT]** until they are ported)

A goo hook, not a weapon: no damage (`PlayerAbilityDefinitions.ts:44`). Direction = pointer aim
(unsnapped) or facing; fallback (1,0). From = the old centre [CENTRE]. Range 180, half width 16.

### 8.1 `lashProbe(from, to = from + dir·180, 16)` (`UniversalSceneWorldController.ts:1271-1300`)

```
reach   = line_reach(from, to)                    # first world-layer (1) static body along the line
blocked = reach != to
bell = first_bell_along(from, reach, 16)          # a bell post catches anywhere on its DamageArea
if bell: reach = bell.at; blocked = true
light = the collectible (remaining > 0) whose circle r 18 (LASH_PICKUP_RADIUS) touches the segment from->reach
        with half width 16, smallest projection along the line                                    # :1284-1296
if light:  return {kind: light, at: collectible root, pickup_id}
if bell:   return {kind: heavy, at: reach, anchor: bell post root}
return {kind: heavy, at: reach} if blocked else {kind: none, at: reach}
```

- `line_reach` (`:1252-1264`): `sightBlocked(from, to, layer 1)`; if blocked, 7 bisection steps
  over the fraction t ∈ [0, 1] and returns the last **open** fraction, i.e. up to 180/128 ≈ 1.4 px
  short of the hit. `sightBlocked` (`PhaserNodeContext.ts:95-106`) checks only static bodies on
  layer 1 (walls, trees, houses, rocks, posts, gulp spots, dummies); **tiles never block** (water,
  cliffs), and bodies smaller than 20 px in both width and height are ignored. Godot: ray query
  mask 1, bodies only, exclude the player; skip colliders under `ground/TileCollision` and the
  ground TileMapLayer (deep water's tile collision is on layer 1024 anyway, rock-wall tiles may be on 1) and shapes < 20×20; use the exact
  hit point or replicate the bisection (≤ 1.4 px difference).
- `first_bell_along` (`:1307-1329`): for each `LashBellScript` (lash-only or not): skip unless a
  shape of its `damageArea` touches the whole segment (half width 16); then walk `along = 0, 4, 8,
  …, length` and take the first point whose distance to the shape is ≤ 16; accept it only if
  `along >= 24` (`LASH_NEAR_PX`, `:356`: a bell right next to the slime is skipped so the hook can
  be thrown away from it). Keep the nearest such bell. `anchor` = the bell post root (its foot).
- Shape–segment test (`SensorGeometry.ts:194-230`): sample the segment every `max(4, halfWidth)`
  = 16 px (inclusive ends) and accept when a sample is within `halfWidth` of the shape (rect:
  distance to the closest point; circle: within `radius + halfWidth`). A bounding-box pre-check
  first.

### 8.2 Timeline (`LegacyPlayerAbilityPresentation.ts:319-424`)

| t (ms) | All kinds |
|---|---|
| 0 | cue `Lash` (`ability-stretch-lash`). Clip `stretch` (loop 12 fps 0.667 s; Godot: the filmed `stretch-<direction>`, once, 270 ms, after `face(dir)`). Stop. Lean: effects offset → dir·8, scale → (1.14, 0.88) over 110 ms Quad.Out, yoyo (back at 220). Tendril sprite frame 0 at `from`. |
| 40 / 80 | Tendril frames 1 / 2. |
| 120 | Act on the catch: |

- **none**: frame 3; +50 (170) frame 6; +100 (220) frame 7; +150 (**270**) destroy tendril, `complete()`.
- **light** (pickup): frame 4; `lashPull(pickup_id, player centre now)` (`:1350-1384`): the pickup
  root flies to that point in 220 ms (`LASH_PULL_MS`) Quad.In, then `requestPickup` with the
  player's pickup area (collectible spec); +60 frame 6; +120 frame 7; +170 (**290**) finish.
- **heavy**: frame 4; `lashRing(from, catch.at, 16)` (§8.3); `landing = lash_landing(from,
  anchor ?? at)` (§8.4); `travel = |landing − from|`.
  - `travel < 8`: +60 frame 6, +110 frame 7, +160 (**280**) finish.
  - else: at +50 (170) a flight of `D = max(120, travel / 0.9)` ms (`STRETCH_LASH_PULL_SPEED` 0.9 px/ms,
    `:39`) Quad.In; every update the body is teleported to `from + (landing − from)·progress` (no
    collision; it crosses water) and the tendril (frame 3) is drawn from there to `catch.at`. On
    complete: destroy the tendril, effects scale (1.2, 0.82) over 90 ms Quad.Out yoyo → `complete()`
    at **170 + D + 180**.

Tendril (`STRETCH_LASH_SHEET`, `:30-37`; asset `effect.player.stretch-lash`,
`MAPS/effects/384x96-tile_4x2-stretch-lash.webp`, frames 384×96: 0–3 reach out, 4–5 splat, 6–7
pull back): positioned at `from` (or the flying position), origin (0, 52/96), rotation
`atan2(dir)`, scale `(max(48, length)/384, 0.5)` where `length` = the catch distance from the
start for frames 0–7 (the tendril is full length from frame 0; the frames do the reaching), sorted
just behind the slime (`attachmentSlot −2` at the start y). Missing texture → no tendril, same
timing.

Cooldown 2000, energy 20.

### 8.3 `lashRing(from, caught, 16)` (`:1332-1347`)

`dir = normalize(caught − from)`; tip segment `caught − dir·6` → `caught + dir·24`
(`LASH_RING_DEPTH`); every `LashBellScript` whose damage-area shape touches the tip segment
(half width 16) rings (`bell.ring()`, §13.4). Called on every heavy catch, so a wall hook right
next to a bell rings it too. Returns the count (unused).

### 8.4 `lashLanding(from, caught)` (`WorldScene.ts:1647-1666`)

```
L = |caught - from| ; if L <= 30 (LASH_STANDOFF_PX, :132): return from
for d = L - 30; d > 0; d -= 8:
    p = from + dir * d
    if tile(p) inside the world and not solid: return p      # tiles only; objects ignored
return from
```

### 8.5 Interactions

- Rings bells (lash-only or not), opens their gates (§13.4).
- Pulls the slime across water and gaps; the playground lash yard is built for it (§14.2).
- During the flight the body is teleported each frame: knockback is overridden, a web zone on the
  path can catch the slime mid-flight (spider-web owner).
- A rooted (web) slime can still lash and be pulled [QUIRK].

---

## 9. Dodge: how it fits [IN, already ported]

Already in `player.gd` (player spec §5). Changes for the shared rules:
- Route the rule check through the shared ability rules: `try_instant(&"dodge")` (busy → silent;
  locked → "Not learned yet" + cue; cooldown → silent; action-locked → cue; energy cost 0).
  Today `player.gd._try_dodge` has no `busy` check (abilities did not exist).
- Dispatch order becomes jump, dodge, stretch-lash, squash-slam, teleport (§3.2): a jump press
  and a dodge press in the same step → the jump wins and the dodge press ages (it fires after the
  jump only if ≤ 150 ms old at the landing step, which a press made in the last 150 ms of the jump
  is).
- Dodge speed is not affected by Gulp forms (`PlayerController.ts:119-122`): a Heavy slime still
  rolls 380 px/s × 500 ms = 190 px.

---

## 10. Abilities and the rest of the game

| Situation | Phaser behaviour |
|---|---|
| Hit during a sequence | Damage and i-frames as usual. Knockback (not Heavy): suppression 160 ms and the knockback velocity move the body; the `knockback` clip is forced (interrupts `hop`/`squash`/…); the `hit` squash is skipped while busy (`SquashStretch` `busy()`); the sequence continues: the jump still lands at its precomputed target, the lash flight keeps teleporting along its line, the slam strikes at the body's position at t = 320. |
| Death during a sequence | Not cancelled (`onPlayerDeath`, `WorldScene.ts:1920-1940`, only clears the Gulp form). The jump still teleports the dead slime to its target; the final `idle` is refused (dead). Respawn is 1400 ms later, after every sequence ended. |
| Hit-stop | Tweens and physics freeze (`holdForHitStop`), `scene.time` timers do **not**: the lash's 40/80/120/… ms steps keep running through a hit-stop while its flight tween freezes [QUIRK]. |
| Modal pause (menus) | Sequences run on scene time and keep going while the simulation is paused (the inventory refuses to open while action-locked, `WorldScene.ts:2077`; other modals do not check) [QUIRK]. Godot's tree pause freezes them (better). |
| Map change | `PlayerAbilityController.destroy()` → lease `dispose()`; cooldowns reset with the new controller; energy persists (run state). |
| Weapon swing | Swing and abilities share `actionLocked`: neither can start during the other. |
| Squash/stretch | Skipped while busy unless forced (the landing). |
| Goo trail | No marks while busy (§12). |
| Plates / webs / hearts / lessons | They read the body position, which a jump or teleport changes only at its landing step (a jump never presses or leaves a plate mid-air; a jump or a teleport "skips" a web zone). |

---

## 11. Eat and the Gulp forms [IN; quick wheel OUT]

### 11.1 Forms (`content/gulp/gulpForms.ts:35-60`)

| id | name | material item (items.json name) | skin texture (asset id) | tint fallback | speed × | knockback immune | presses plates (and cracks ground) | crosses webs | swims | badge frame |
|---|---|---|---|---|---|---|---|---|---|---|
| `heavy` | Heavy | `stone` ("Stone") | `slime-form-heavy` (`character.player.slime.heavy`, `characters/slime-form-heavy.webp`, 8×8 of 256²) | `#9aa3ad` | 0.6 | yes | yes | no | no | 0 |
| `sticky` | Sticky | `silk-clump` ("Sticky Silk") | `slime-form-sticky` (`character.player.slime.sticky`) | `#f1ecff` | 0.9 | no | no | yes | no | 1 |
| `frog` | Frog | `frog` (Gulp spot only, §11.7) | none: skin 3 of `form_skin.gdshader` | `#8fd14f` | 1.0 | no | no | no | yes | 2 |

Duration `gulp.formDurationMs` = **60000** ms of simulation time, for every form. The Frog is a
Godot addition (owner, 2026-10-06; §11.7); the Godot table is `game/player/gulp/gulp_forms.gd`.
`gulpFormForMaterial(itemId)` (`:62-64`): the form whose material it is.

### 11.2 `GulpController` (`features/gulp/GulpController.ts`)

State: `form` (or none), `ends_at`, `last_material_item_id` (initially `stone`, the first form's).

```
eat():                                                     # one tap of Q (or RMB on a spot)   :67-83
  spot = nearest_spot()
  if spot:
      form = form_for(spot.material); if not form: return 'nothing'
      become(form); return 'spot'                          # free, spots never run out
  if form: end('burp'); return 'burp'
  show_message(carried_material()
      ? "No Gulp spot here. Hold Q to eat what you carry"  # key label from the binding table
      : "Nothing to gulp here")                            # white, not big, at (centre.x, centre.y - 56)
  return 'nothing'

eat_material(item_id):                                     # quick wheel release   :89-94
  form = form_for(item_id); if not form or count(item_id) < 1 or not consume(item_id, 1): return 'nothing'
  become(form); return 'inventory'

become(form):                                              # :133-140
  previous = self.form
  if previous and previous.id != form.id: on_form_changed(none, 'switched')
  self.form = form ; ends_at = now + 60000 ; last_material = form.material
  on_form_changed(form, 'refreshed' if previous and previous.id == form.id else 'started')

end(reason):  form = none ; ends_at = 0 ; on_form_changed(none, reason)       # :142-146
update():     if form and now >= ends_at: end('expired')    # every fixed step   :109-111
clear():      if form: end('cleared')                       # death (WorldScene.ts:1922)  :114-116
nearest_spot(): spots with |spot - player_centre| <= spot.radius, the nearest     # :119-131  [CENTRE]
remaining_ms(): max(0, ends_at - now) if form else 0
wheel_entries(): [{item, form, count}] for forms in table order with count > 0     # :97-101
preferred_material: last_material if carried, else the first carried in table order # :149-152
```

`on_form_changed` (`WorldScene.ts:1093-1100`):
1. `restorePlayerTint()` (`:1191-1197`): skin texture if it exists, else the tint (multiply);
   no form → own texture, no tint.
2. `gulp.changed {formId | null, reason}` → `started`/`refreshed`: squash `gulp` (1.24, 0.86 → 1
   in 320 ms Elastic.Out; skipped while an ability is busy) (`:453`). No audio cue for
   `gulp.changed` (the eat clip's `Eat` cue sounds).
3. Floating text at (centre.x, centre.y − 56), big: started → `"HEAVY!"` / `"STICKY!"` cyan;
   refreshed → `"Heavy refreshed"` cyan; burp → `"Burp!"` white; expired → `"The form wore off"`
   white; switched / cleared → none.

A form is lost silently on a map change (the controller is per world) and on death
(`cleared`). Not saved.

### 11.3 Form effects

- **Speed** (`PlayerController.ts:69-70`): `speed = resolve_movement_speed(base, 0, status_mult) ×
  form.speed_multiplier` (the cap applies before the form). Walk 200 → Heavy **120**, Sticky
  **180**; sprint 300 → Heavy **180**, Sticky **270**. Dodge unchanged (380). Jump/teleport/lash
  distances unchanged.
- **Knockback immunity** (Heavy; `WorldScene.ts:341-350`): `applyKnockback` returns before
  anything: no knockback velocity, no 160 ms movement suppression, no `knockback` clip, no
  knockback-priority window. Damage, i-frames, hit flash, squash, `-N` text still happen.
- **Plates and cracked ground** (Heavy): the plate-weight port returns `[player centre]` only
  while the form `pressesPlates` (`WorldScene.ts:2336`); a jump landing in Heavy form records
  `heavyLanding` (`:449-451`). §13.2, §13.3.
- **Webs** (Sticky): `spiderWebs.playerCrossesWebs()` = form `crossesWebs` (`:2350`); used by
  `game.spider-web` and `game.web-patch` (another engineer; §13.9).
- **Look**: in Phaser the skin sheets exist, so the whole slime is drawn from the re-textured
  sheet (same frame layout as the **old side-view** `character.player.slime` sheet); the tint is
  the fallback. Reapplied after the hit flash (`WorldScene.ts:1914`).
  **[QUIRK]/owner item O-G1**: the Godot player draws from the new three-quarter top-down sheet,
  which has no Heavy/Sticky skins. Decided 2026-10-05: a shader paints the form over the slime's
  own frames (`game/player/gulp/form_skin.gdshader`: grey cobbles for Heavy, cream silk for
  Sticky, green with dark spots and a pale belly for the Frog; only the green body changes). The tint (`visual.self_modulate`) stays as the fallback
  when the Visual has no skin material.

### 11.4 The eat press, tap and hold (`WorldScene.ts:913-969, 1821-1826, 1855-1877`)

```
handle_action_input: eat press (lowest priority, §3.2) -> eat_hold = {since: now, last_seen: now, open: false, empty: false}
                     # this step is consumed (velocity keeps last step's value once)

each later step, after the action-lock check (§3.1):
update_eat_hold(direction):
  if no hold: return false
  if now - last_seen > 600: close hold; return false      # steps were skipped (menu, a long swing): drop the press
  last_seen = now
  if eat not held:                                          # released
      if open: entry = entries[selected]; if entry and eat_material(entry.item) != 'nothing': play_action_animation('eat')
      elif not empty and eat() != 'nothing': play_action_animation('eat')
      close hold; return false                              # handle_action_input still runs this step
  if not open and not empty and now - since >= 250 (GULP_WHEEL_HOLD_MS, GulpWheelLayout.ts:2):
      entries = wheel_entries()
      if entries empty: empty = true; text "No Gulp materials carried" white not big at (centre.x, centre.y - 56)
      else: open = true; selected = index of preferred_material (or 0); pointer_start = pointer; wheel.open(entries)
  if not open: return false                                 # the slime keeps walking and acting while Q is held
  pick = slot for the movement direction (arrows/WASD)      # pickGulpWheelSlot, nearest slot angle
  if none and pointer moved > 10 px from pointer_start: pick = slot for (pointer - (centre.x, centre.y - 28))
  if pick: selected = pick
  wheel.update(centre, selected); return true               # the slime stands still while the wheel is open
```

`now` here is **scene time** (`this.time.now`), not the simulation clock. The hold is also closed
when paused, dead or asleep.

- Tap (release < 250 ms): `eat()` on the step after the release. Near a spot → that form (free);
  in a form away from spots → burp; else the message.
- [QUIRK] Hold ≥ 250 ms near a spot: with materials carried the wheel opens and the release eats
  from the **inventory** (costs one) instead of the free spot; with nothing carried `empty` is set
  and the release does **nothing** at all, even next to a spot.
- `play_action_animation('eat')` (`:1855-1870`): refused while dead or inside the knockback window;
  else `player.action {anim:'eat'}` → cue `Eat`, `action_locked = true`, stop, play `eat`
  (12 fps, frames 47, 40, **167 ms**, one-shot), `action_animation_until = now + 167` (sim). At the
  top of a later step `finish_expired_action_animation` unlocks and plays `idle` (`:1872-1877`).
  The form effects start immediately (before the clip).
- Also via interact (RMB): the interaction router candidate `gulp-spots` (`WorldScene.ts:1111-1128`):
  present when `nearest_spot()` exists; id `gulp-spots:<round x>:<round y>`, prompt
  `"Gulp the <item name>"` ("Gulp the Stone", "Gulp the Sticky Silk"), priority 60, no badge,
  origin = the spot; execute = `eat()` + eat clip. **[interaction.md]**.
- Descriptor and comments say "W" (`registrations.ts:533`, `WorldScene.ts:914`, `GulpWheel.ts:51`);
  the binding is **Q** (`PlayerInputActions.ts:23`; W is move-up) [QUIRK: stale text]. Godot `eat`
  is Q already.

Godot: run the hold on the simulation clock (difference only during hit-stop; modal pauses close
the hold anyway). Tap path [IN]; wheel [OUT] (it needs the inventory and the wheel drawing) but
keep `eat_material()` for it.

### 11.5 Gulp HUD (`GulpHud.ts`) [IN, simple labels]

Updated every fixed step (`WorldScene.ts:827`), drawn above everything:
- In a form: text `m:ss` with `seconds = ceil(remaining_ms / 1000)` (60000 → "1:00"), 14 px,
  stroke 4; with the badge texture (`ui.icons.gulp-forms.2x1`, frame = `iconFrame`, 36 px) the
  pair is centred over the slime: `width = text_width + 40`, `left = centre.x − width/2`, badge
  bottom-right at `(left + 36, centre.y − 70)`, text bottom-left at `(left + 40, centre.y − 76)`;
  without the badge the text is `"HEAVY 1:00"`.
- Hint `"[Q] Gulp"` (`#ffe89a`, origin bottom-centre) at `(spot.x, spot.y − badgeRise)` for the
  nearest spot in reach.

### 11.6 Quick wheel (`GulpWheel.ts`, `GulpWheelLayout.ts`) [OUT]

Ring of radius 72 around the slime centre, slots r 25, icons 46 px (form badge, else the item
icon), count text at slot + (14, 12), title = chosen form name upper-case (or "GULP") at y
+115 (72 + 25 + 18); slot `i` of `n` at angle `−90 + i·360/n` degrees (first at the top, clockwise); a direction
picks the nearest slot angle. Drawn in the world; nothing pauses.

### 11.7 Swimming: the Frog form (Godot addition, owner 2026-10-06) [IN]

Deep water blocks the slime ([water.md](water.md) §1: its tiles collide on the `water` physics
layer, 1024) until a form that `swims` lets it in. The only one is the **Frog**, gulped from a frog
Gulp spot (`object.gulp-spot-frog`, `game/scenes/objects/gulp-spot-frog.tscn`: a frog on a lily
pad, `material_item_id` `frog`, prompt "Gulp the Frog" from its `display_name`; no `frog` item
exists, so the wheel never offers it). `game/player/gulp/player_swimming.gd`, run by `player.gd`
every step after the Gulp controller:

- **Mask**: while the form swims, the water bit is cleared from the body's `collision_mask`;
  otherwise it is set again.
- **Swimming** = the form swims and the cell 2 px above the feet is `deep-water` (shallow water is
  wading, [water.md](water.md) §9). On the change:
  - the `swim-down`/`-up`/`-side` clips (page 3 of the slime sheet, loops) replace idle and walk;
  - `form_skin.gdshader`'s `waterline` = 30 px of the 256 px cell: everything lower is cut, with a
    thin foam line, and the art is lowered by as much (`set_swim_offset`, 30 × the Visual's scale),
    so the waterline sits on the feet, where the water wake draws its swim ripple;
  - nothing else changes: same speed, same body, same hurtbox.
- **No attacks or abilities while swimming** (the dodge included): `player.gd` consumes those
  presses before the ability loop; eat and interact still work.
- **The form holds over deep water** (`gulp_controller.gd`): while it swims and any corner of the
  body rectangle (inset 1 px) is over deep water, it does not expire, a tap of eat away from spots
  shows "Swim back to the shallows first" instead of a burp, and a spot or wheel form that does not
  swim is refused with the same message. Once out, an expired form ends at the next step, and deep
  water blocks the slime again.
- The update runs every step, dead or alive: when the form ends (a death clears it, §11.2) the
  next step drops the swim look.

---

## 12. Goo Trail (passive) [OUT]

`WorldScene.updateSlimeTrail` (`:892-902`) + `features/feel/SlimeTrail.ts`: once `goo-trail` is
learned, while alive, awake, not travelling and not busy, a mark is dropped every 30 px of
movement at `(centre.x, feet.y − 3)`; pool 28, lifetime 5000 ms, alpha 0.5 fading; every 100 ms
ordinary enemies within 26 px of a mark younger than 2500 ms get the `slow` status (×0.55) for
400 ms (`slowEnemiesNear`, `UniversalSceneWorldController.ts:1237-1249`). Nothing teaches it in
the story; it needs enemy status effects.

---

## 13. World scripts

All script roots below are **not** re-anchored (no `depthAnchor` in their scenes), so a Godot
root's `global_position` equals the Phaser position. Every distance test compares the **player's
old centre** with the script's **parent root** (`get_parent().global_position`) [CENTRE].
Converted scenes already exist in `godot/game/scenes/objects/` with the placeholder
`unported_script.gd` (e.g. `pressure-plate.tscn`: `Visual` offset `(−128, −207)` = visualOffset
(0, 49) − origin·frame, `hframes 8`, `frame 6`).

The Phaser scripts poll in `_process` (once per rendered frame, after the fixed steps; with delta
0 during hit-stop). Godot: gameplay checks in `_physics_process` (deterministic; one step of
latency because the world's nodes run before the player in tree order), presentation (bob,
wobble, ring frames) in `_process`.

Export defaults = the Phaser script fallbacks, which equal the descriptor defaults
(`registrations.ts:530-751`); the converter only writes what the JSON sets.

### 13.1 `game.gulp-spot` → `scripts/gulp_spot.gd` [IN]

Descriptor `registrations.ts:530-542`; script `GulpSpotScript.ts:17-32`. No signals, no handlers.

| Property (export) | Descriptor default | Script fallback | Scenes |
|---|---|---|---|
| `materialItemId` (`material_item_id: String`) | required string | `''` (a spot without one is skipped, `UniversalSceneWorldController.ts:1221`) | stone: `"stone"`, silk: `"silk-clump"` |
| `radius` (`float`) | 96 | 96 unless finite > 0 | 100 / 100 |
| `badgeRise` (`badge_rise: float`) | 80 | 80 unless finite | stone 112, silk 118 |

Scenes: `object.gulp-spot-stone` (StaticBody2D layer 1, shape 84×30 at (0, −16), sprite
`sheet.rocks.8x3` frame 20, scale 1.15, origin (0.5, 1)); `object.gulp-spot-silk` (StaticBody2D
layer 1, shape 70×28 at (0, −14), sprite `sheet.props.gulp.8x1` frame 3, scale 0.72). The root is
the bottom-centre of the art. Spots never run out.

Godot: join group `&"gulp-spot"`; expose `origin() -> Vector2` (parent `global_position`); the
player's Gulp controller iterates the group.

### 13.2 `game.pressure-plate` → `scripts/pressure_plate.gd` [IN]

Descriptor `:544-562`; script `PressurePlateScript.ts:38-139`.

| Property | Descriptor default | Script fallback | `object.pressure-plate` scene | Instance overrides |
|---|---|---|---|---|
| `plateId` (`plate_id`) | required | `''` | `"plate"` | always overridden (below) |
| `radius` | 40 | 40 unless finite ≥ 0 | **44** | — |
| `sinkPx` (`sink_px`) | 4 | 4 unless finite ≥ 0 | **0** | — |
| `pressedFrame` (`pressed_frame: int`) | −1 | −1 unless an integer | **7** | — |
| `gateId` (`gate_id`) | `''` | `''` | — | see below |
| `latch` (`bool`) | false | `=== true` | **true** | — |
| `visual` (`Sprite2D`, optional) | — | — | `../Visual` (frame 6, plate up; frame 7 = down) | — |

Signals: `pressed {plateId}`, `released {plateId}`. Behaviour (`:78-86`):

```
_process:
  if down and latch: return                                   # a latched plate never rises again (while the node lives)
  loaded = any weight with |weight - root| <= radius          # weights = [player centre] only in Heavy form
  if loaded == down: return
  down = loaded
  show_sunk(loaded):  visual offset y = rest.y + (sink_px if loaded else 0)     # rest captured at the first change
                      if pressed_frame >= 0: frame = pressed_frame if loaded else rest frame
  if loaded: open every game.gate in the whole tree whose gateId == gate_id (if gate_id != '')   # :88-98
  emit pressed/released {plateId}
```

- `released` never closes a gate. Gate openings by plates (and bells) are **not persisted**
  (`GateScript.open()` only sets the frame/collision; only key unlocks write the gate record,
  `UniversalSceneWorldController.ts:985-994`); a latched plate's state is not saved either. After
  a reload or a revisit the plate is up and the gate closed again [QUIRK].
- Scene defaults make every placed plate a latching plate with no sink and the frame swap.
- Godot: `visualOffset` is folded into `Sprite2D.offset` by the converter, so sink =
  `offset.y = rest_offset.y + sink_px`.

Listeners: `worlds/playground`: `playground-end-card-plate` `pressed` → `end-card-flag`
(`game.story-flag`, flag `playground-end-card-test`) handler `set` (converter → `on_set`,
`story_flag.gd`); the flag shows a test end card (`content/story/endCards.ts:23`, UI **[OUT]**).

### 13.3 `game.cracked-ground` → `scripts/cracked_ground.gd` [IN]

Descriptor `:654-667`; script `CrackedGroundScript.ts:40-115`.

| Property | Descriptor default | Script fallback | `object.cracked-ground` scene |
|---|---|---|---|
| `flagId` (`flag_id`) | required | `''` (does nothing) | `"cracked.unassigned"` (instances override) |
| `radius` | 48 | 48 unless finite > 0 | **52** |
| `requiresLanding` (`requires_landing`) | true | `!== false` | (unset → true) |

Signal: `cracked {flagId}`. The scene also holds a `game.story-variant` on the same flag (`Intact`
sprite frame 0 / `Broken` sprite frame 1 + a `game.door` "Climb down" with an `arrival` child at
(0, 96)); sprites `sheet.props.gulp.8x1`, scale 0.62, visualOffset (0, 62), ground-decal band.

```
_enter_tree: broken = flag_id != '' and has_flag(flag_id); seen_landing = last_heavy_landing()?.id     # :65-72
_process:                                                                                            # :80-96
  if broken or flag_id == '': return
  within(p) = |p - root| <= radius
  if requires_landing:
      landing = last_heavy_landing()                       # {x, y (player centre after the landing), id}
      if landing and landing.id != seen_landing:
          seen_landing = landing.id
          if within(landing): crack(); return
      if any weight within: ground_creaks(root)            # Heavy standing on it: hint only
      return
  if any weight within: crack()
crack():  broken = true; set_flags([flag_id]); ground_cracked(root); emit cracked {flagId}           # :98-103
```

- A landing counts only if the slime was **Heavy at the landing moment** (§5.3) and its centre
  lands within 52 px of the root. A landing older than the node (loaded later) never counts.
- `ground_cracked(at)` (`WorldScene.ts:2083-2087`): `gameFeel.play('ground-crack')` (shake
  260 ms × 0.012, no hit-stop), `ground.cracked` → cue `GroundCrack`, text "The ground gives
  way!" yellow big 1800 ms at (at.x, at.y − 60).
- `ground_creaks(at)` (`:2341-2346`): at most once per 4000 ms of scene time **for all cracked
  grounds together**: "It creaks under you... jump on it! (Space)" yellow big 2200 ms at
  (at.x, at.y − 50). ("Space" is a literal, not the binding label.)
- The flag makes the story variant swap to the hole and its door (`story_variant.gd`, world
  objects); the door leads to the cavern (`game.door`, interaction spec).

Godot: the player keeps `heavy_landing = {}` / `{"x","y","id"}` (ids from 1, per player
instance); expose `last_heavy_landing()`; the ground takes `seen` lazily on its first physics
step that sees a player (in Godot the world loads before the player spawns). Flags through
`RunState.set_flag`.

### 13.4 `game.lash-bell` → `scripts/lash_bell.gd` [IN]

Descriptor `:564-583`; script `LashBellScript.ts:40-127`.

| Property | Descriptor default | Script fallback | `object.lash-bell-post` scene |
|---|---|---|---|
| `bellId` (`bell_id`) | required | `''` | `"bell"` (instance overrides) |
| `gateId` (`gate_id`) | `''` | `''` | `''` |
| `lashOnly` (`lash_only`) | true | `!== false` | true |
| `damageArea` (`damage_area: Area2D`, required) | — | throws without it | `../DamageArea` (layer 8, mask 16, monitoring off; shape 84×104 at (−6, −44)) |
| `visual` (`Sprite2D`, optional) | — | — | `../Visual` (`object.lash-bell-post`, 3 frames of 256², scale 0.45; 0 rest, 1/2 swung) |

Root: StaticBody2D layer 1, shape 30×20 at (0, −10). Signal: `rung {bellId}`.

```
_enter_tree: if not lash_only: router.register_area(damage_area, self, {priority 0, damageMultiplier 1})   # :70-79
get_damage_state = {hp 1, max_hp 1, dead false}        # every accepted hit is "defeated: true", ignored [QUIRK]
commit_damage(_) -> ring()
ring():                                                 # :100-109
  ring_step = 0; elapsed = 0; frame = 1
  open every game.gate in the tree with gateId == gate_id (if set)
  lash_bells.rung(root): event lash-bell.rung -> cue BellRing; 'loot-sparkle' particles at (root.x, root.y - 70)
  emit rung {bellId}
_process(delta):                                        # :85-97
  if ring_step < 0: return
  elapsed += delta; if elapsed < 0.09: return
  elapsed = 0; ring_step += 1                           # reset, not subtract: slightly frame-rate dependent
  if ring_step >= 6: ring_step = -1; frame = 0; return
  frame = [1, 2, 1, 2, 1, 0][ring_step]
```

Rings from the lash (§8.3) and, when not lash-only, from weapon hits and the slam. It never
breaks; ringing again restarts the swing and re-opens (no-op) the gates.
`loot-sparkle` (`ParticlePresets.ts:31-34`): `fx-sparkle`, 6, lifespan 520, speed 20–60, angle
220–320, scale 0.9→0, alpha 1→0, rotate 0–180, drawn over everything; not in Godot's
`particle_fx.gd` yet.

Godot: group `&"lash-bell"`; the lash code reads `damage_area`'s shapes in world space.

### 13.5 `game.ability-lesson` → `scripts/ability_lesson.gd` [IN]

Descriptor `:585-598`; script `AbilityLessonScript.ts:24-62`.

| Property | Default | Script fallback | Scene `object.ability-lesson` (Node2D root only) | Playground instance |
|---|---|---|---|---|
| `abilityIds` (`ability_ids: Array`) | `[]` | non-empty strings only | `[]` | `["stretch-lash"]` |
| `radius` | 96 | 96 unless a number > 0 | 96 | **140** |

Signal: `taught {abilityIds: fresh}`.

```
_process:                                                       # :48-61
  if done or ability_ids empty: return
  p = player centre (none while dead); if none: return
  if |p - root| > radius: return
  done = true                                                   # even when nothing is new
  fresh = ids not yet learned; if fresh empty: return
  learn(fresh) -> storyProgress.learnAbilities -> per id: cue AbilityLearned + banner (§1.1)
  emit taught {abilityIds: fresh}
```

`done` lives with the node (a revisit re-checks, but known ids are filtered). Godot:
`RunState.learn_ability(id)` per id.

### 13.6 `game.training-dummy` → `scripts/training_dummy.gd` [IN]

Descriptor `:600-616`; script `TrainingDummyScript.ts:36-88`.

| Property | Notes |
|---|---|
| `damageArea` (`damage_area: Area2D`, required) | `../DamageArea` (layer 8, mask 16; shape 78×96 at (0, −46)) |
| `visual` (`Sprite2D`, optional) | `../Visual` (`object.training-dummy`, scale 0.42, origin (0.5, 1)) |

Root StaticBody2D layer 1, shape 34×20 at (0, −10). Signal `hit {damage}`.

```
_enter_tree: router.register_area(damage_area, self, {priority 0, damageMultiplier 1})   # no tags
get_damage_state = {hp 9999, max_hp 9999, dead false}       # never breaks; no can_receive/mitigate
commit_damage(commit):                                       # :55-63
  hits += 1; wobble_age = 0; side = -1 if commit.request.impact.knockX < 0 else 1
  training_dummies.show_hit(root, actual): text "<actual>" orange big at (root.x, root.y - 96)
  emit hit {damage: actual}
_process(delta):                                             # :79-87
  if wobble_age < 0: return
  wobble_age += delta
  amp  = 0.22 * exp(-4.5 * wobble_age)
  lean = 0 if amp < 0.004 else side * amp * cos(wobble_age * 9 * 2π / 3)     # = cos(6π t)
  visual.rotation = lean ; if lean == 0: wobble_age = -1      # ends after ln(55)/4.5 ≈ 0.89 s
```

Rotation pivots at the sprite origin (bottom centre) in Phaser; the converted Sprite2D (`centered
= false`, offset = −origin·frame) rotates about its node position, which is that origin. The
attacker's usual feedback applies (no `enemy`/`resource` tags: `PlayerCombat.on_outcome` plays
`hit` hit-stop, sparks at (root.x, root.y − 12) and the weapon impact effect). Sword: 24 per lone
hit in the port (owner decision O3), 42 on a crit. Slam: 30 each.

### 13.7 `game.goo-heart` → `scripts/goo_heart.gd` [IN]

Descriptor `:618-633`; script `GooHeartScript.ts:39-123`.

| Property | Default | Script fallback | Scene `object.goo-heart` |
|---|---|---|---|
| `heartId` (`heart_id`) | required | `''` | `"unassigned"` (`UNASSIGNED_HEART_ID`, `:9`) |
| `radius` | 36 | 36 unless finite ≥ 0 | 36 |
| `bobPx` (`bob_px`) | 4 | 4 unless finite ≥ 0 | 4 |
| `visual` (`Sprite2D`, optional) | — | — | `../Visual` (`sheet.props.gulp.8x1` frame 5, scale 0.46, visualOffset (0, −4)) |

Signal `collected {heartId}`.

```
_enter_tree:                                                   # :61-71
  if heart_id == '' or 'unassigned': warn "has no heartId; it cannot be collected"; taken = true; return   # visible, never bobs
  if has_flag("goo-heart." + heart_id): vanish()              # hidden for the rest of the run
_process(delta):                                               # :77-88
  if taken: return
  elapsed += delta ; visual offset y = rest.y + round(sin(elapsed * 3) * bob_px)     # ±4 px, period 2.09 s
  p = player centre (none while dead); if p and |p - root| <= radius:
      vanish(); collect(heart_id, root); emit collected {heartId}
collect (WorldScene.collectGooHeart, :2145-2154):
  if has_flag(flag): return ; set_flags(["goo-heart." + id])
  gameState.addGooHeart(): goo_hearts += 1; hp = new max_hp (full heal); hp.changed     # GameState.ts:138-143
  event goo-heart.collected {heartId, maxHp} -> cue Heal (placeholder)
  banner "Goo Heart! Max HP <maxHp>" #ff9fb4 [OUT banner]
  text "+10 max HP" green big 2000 ms at (root.x, root.y - 40)
```

`max_hp = 100 + goo_hearts × 10` (`character.player.gooHeart.maxHpBonus`). Heart ids are unique
across maps (5 placed, §14.1) → max HP up to 150. Godot: flag through `RunState`, count in
`RunState.player.goo_hearts`, the live player must take the new maximum and heal
(`player.grant_goo_heart()`, §19.3; `restore_run_state` already reads `RunState.max_hp()`).

### 13.8 `game.restoration-site` → `scripts/restoration_site.gd` [IN, quest gate stubbed; needs interaction + inventory]

Descriptor `:733-751`; script `RestorationSiteScript.ts:41-78`. No signals or handlers; it is an
interaction candidate (`UniversalSceneWorldController.ts:1038-1071`).

| Property | Default | Script fallback | Forge (`object.forge`) | Workshop (`object.workshop`) |
|---|---|---|---|---|
| `prompt` | required | `"Restore"` if empty | "Restore the Forge (40 stone, 20 wood, 6 iron ore)" | "Restore the Workshop (60 wood, 40 stone)" |
| `flagId` (`flag_id`) | required | `''` | `forge.restored` | `workshop.restored` |
| `objectId` (`object_id`) | required | `''` | `forge` | `workshop` |
| `questId` (`quest_id`) | `''` | `''` | `rekindle-the-forge` | `the-old-workshop` |
| `cost` (`Dictionary`) | `{}` | positive safe integers, authored order | `{"stone":40,"wood":20,"iron-ore":6}` | `{"wood":60,"stone":40}` |
| `lockedMessage` | required | "It is in ruins." | "The Forge has gone cold. Pip, the smith's son, wants it lit again." | "The old Workshop has caved in. Rebuilding it will take iron from a working Forge." |
| `restoredMessage` | required | "Restored!" | "The Forge burns again!" | "The Workshop is restored!" |
| `interactRadius` | 150 | 150 unless > 0 | 130 | 150 |
| `badgeRise` | 200 | 200 unless > 0 | 130 | 150 |

Both buildings: root StaticBody2D; `game.story-variant` on the flag swaps `ruined` ↔ `restored`
(the restored one holds the `game.workbench` station); the site script sits under
`ruined/site` (position (0,0)), so it leaves the tree once restored.

Candidate (`:1038-1071`): nearest in-tree site with `|player centre − site root| <=
interact_radius`; id `world-restorations:<id>`, prompt, priority 89, badge at (root.x, root.y −
badge_rise), pointer origin (root.x, root.y − 24). Execute → `restoreSite` (`WorldScene.ts:2094-2130`):

```
if paused or travelling or flag_id == '' or has_flag(flag_id): return false
label = (at.x, at.y - 36)
if quest_id != '' and quest(quest_id).status != 'active':
    text locked_message white big 2400 at label; event building.restore-refused {objectId, reason 'locked'} (no sound); return true
missing = [cost.count - have for each cost if > 0]
if missing: text "Missing: 12 Stone, 3 Wood" (item names, cost order) red big 2400; event refused 'missing-materials' -> cue CraftFail; return true
remove every cost from the inventory ; set_flags([flag_id])
event object.activated {objectId, instanceId (persistence key), areaId}       # quests [OUT]
event building.restored {...} -> cue BuildingRestored ; gameFeel 'building-restored' (shake 320 ms x 0.006)
60 'dust-puff' particles at (at.x, at.y - 70) from a random rect (-140, -90, 280, 120): lifespan 700-1200, speed 30-130,
    angle 180-360, scale 2.2 -> 0.6, alpha 0.95 -> 0; destroyed after 1300 ms
text restored_message green big 2600 at label ; return true
```

Quests are **[OUT]**: with a quest id the Phaser game refuses unless that quest is active. Port the
check behind a quest port that returns "not active" until the quest phase (parity with a run that
has not taken the quest) and let a test/dev flag override it (owner item O-R1). Inventory:
`RunState.item_count` / `remove_item` exist; item names from `items.json`
(`GameConstants.data_file("items.json")`). The interaction router is `interaction.md`.

### 13.9 What `game.spider-web` / `game.web-patch` need from this side (not ported here)

`SpiderWebScript.ts:18-26, 88-101`, `WebPatchScript.ts:43-63` read the `world.spider-web` port:
- `player_position()` = player centre, none while dead or travelling [CENTRE];
- `player_crosses_webs()` = the current Gulp form's `crossesWebs` (Sticky) → Godot
  `player.crosses_webs() -> bool`;
- `catch_player(zone)` (`WorldScene.catchInWeb`, `:2133-2142`: teleport outside the zone, root
  for 900 ms via `applyWeb`, throttled message) and `web_torn(zone)` live on the player/world side
  too; the rooted (`sticky`) status they set must block jump/dodge/teleport (§3.2,
  `player.is_rooted()`).
Interplay: a jump or a teleport crosses a web without touching its zone; the lash flight can be
caught mid-path (§10).

### 13.10 What plates and bells need from `game.gate` (world-objects spec)

`GateScript.open()` (`GateScript.ts:89-93`): no-op when open; else open frame, door body collision
off, emit `opened {gateId}`. Plates and bells call it on **every** gate in the tree whose `gateId`
matches (not just one map's). Godot proposal: `gate.gd` joins group `&"gate"`, exports `gate_id`,
has `open()` (also the converted handler `open`) and `is_open()`.

---

## 14. Instances per world

### 14.1 Counts (`content/scenes/authored/worlds/*.scene.json`)

| Object | playground | gloop-forest | gloop-cavern | level-1 | others |
|---|---|---|---|---|---|
| `object.gulp-spot-stone` | 1 | 2 | — | — | — |
| `object.gulp-spot-silk` | 1 | 2 | — | — | — |
| `object.pressure-plate` | 2 | 1 | — | — | — |
| `object.cracked-ground` | 1 | 1 | — | — | — |
| `object.lash-bell-post` | 1 | — | — | — | — |
| `object.ability-lesson` | 1 | — | — | — | — |
| `object.training-dummy` | 3 | — | — | — | — |
| `object.goo-heart` | — | 2 | 1 | 2 | — |
| `object.forge` / `object.workshop` (restoration) | — | — | — | 1 / 1 | — |
| `object.spider-web` (other engineer) | 1 | 1 | — | — | — |
| `object.gate-verdant` (`game.gate`) | 2 | 1 | — | 1 | — |

Positions and overrides (all parents at (0,0), so these are world positions; the Gulp spots,
bell, dummies and buildings override `body.position`, the others `root.position`):

| World | Instance | Position | Overrides |
|---|---|---|---|
| playground | `playground-stone-gulp-spot` | (1120, 800) | — |
| playground | `playground-silk-gulp-spot` | (680, 1660) | — |
| playground | `playground-heavy-plate` | (1344, 780) | plateId `playground-heavy-plate`, gateId `playground-heavy-gate` |
| playground | `playground-end-card-plate` | (1210, 380) | plateId `playground-end-card-plate` (no gate; `pressed` → story flag `playground-end-card-test`) |
| playground | `playground-heavy-gate` (gate) | (1344, 576) | gateId `playground-heavy-gate`, "Something heavy must press the plate." |
| playground | `playground-cracked-ground` | (1600, 1040) | flag `cracked.playground-sinkhole`; door `playground-sinkhole` → `playground-cavern` / `playground-cavern-ladder` |
| playground | `playground-lash-lesson` | (1904, 1520) | abilityIds `["stretch-lash"]`, radius 140 |
| playground | `playground-lash-bell` | (2490, 1470) | bellId `playground-lash-bell`, gateId `playground-lash-gate` |
| playground | `playground-lash-gate` (gate) | (1984, 1408) | gateId `playground-lash-gate`, "Ring the bell across the water with the Stretch Lash." |
| playground | `playground-training-dummy-1/2/3` | (1480, 1400), (1580, 1400), (1680, 1400) | — |
| playground | `playground-nook-web` (web) | (384, 1760) | — |
| gloop-forest | `gloop-ch2-hollow-stone-gulp-spot` | (2640, 3036) | — |
| gloop-forest | `gloop-ch2-clearing-stone-gulp-spot` | (1568, 2304) | — |
| gloop-forest | `gloop-ch2-nook-silk-gulp-spot` | (1060, 1400) | — |
| gloop-forest | `gloop-ch2-nest-silk-gulp-spot` | (2872, 1000) | — |
| gloop-forest | `gloop-ch2-hollow-plate` | (2880, 3016) | plateId `gloop-iron-hollow-plate`, gateId `gloop-iron-hollow-gate` (gate at (2880, 2816)) |
| gloop-forest | `gloop-ch2-cracked-ground` | (1344, 2368) | flag `cracked.gloop-sinkhole`; door → `gloop-cavern` / `gloop-cavern-ladder` |
| gloop-forest | `gloop-ch2-nook-goo-heart` | (800, 1176) | heartId `gloop-silk-nook` |
| gloop-forest | `gloop-ch2-matron-goo-heart` | (3120, 800) | heartId `gloop-matron-nest` (inside the `matron-heart` subtree shown by the story variant on `chapter-2-complete`) |
| gloop-cavern | `gloop-cavern-goo-heart` | (1216, 420) | heartId `gloop-cavern` |
| level-1 | `level-1-goo-heart-meadow-lakeside` | (176, 3040) | heartId `meadow-lakeside` |
| level-1 | `level-1-goo-heart-meadow-autumn-thicket` | (3300, 3190) | heartId `meadow-autumn-thicket` |
| level-1 | `level-1-workshop` / `level-1-forge` | (640, 392) / (1190, 1068) | — |

### 14.2 The playground testbed (`worlds/playground.scene.json`)

40 × 28 tiles of 64 px (2560 × 1792), spawn marker (1280, 1536). Ground: grass, a town-cobble
block (cols 16–25, rows 3–13), a forest-floor block (cols 29–38, rows 3–16) and a **water moat**:
column 37 rows 19–26 plus columns 38–39 on rows 19 and 26 (x 2368–2560, y 1216–1728), an island
for the bell. Areas: `playground-spawn-safe` (enemy-safe-zone rect 1024×640 at (1280, 1440)),
`playground-enemy-pen` (enemy-spawn at (2144, 640): worm-brawler, worm-archer, slime-spider, …).

Puzzle groups (all at offset 0):
- **heavy-puzzle**: stone spot (1120, 800) → Heavy → plate (1344, 780) opens the heavy gate
  (1344, 576) in the bottom wall of a stone-wall pen (walls x 1152–1536, y 256–576) holding the
  reward chest (1344, 420) and the end-card plate (1210, 380).
- **gulp-secrets**: cracked ground (1600, 1040): Heavy + jump landing → sinkhole door to
  `playground-cavern`.
- **web-puzzle**: silk spot (680, 1660) → Sticky → the web (384, 1760) in the bottom wall of a pen
  (x 224–544, y 1504–1760) with a chest (384, 1624).
- **lash-yard**: lesson (1904, 1520, r 140) teaches the lash; the bell (2490, 1470) stands on the
  moat island; ringing it opens the lash gate (1984, 1408) in the bottom wall of a pen (x
  1792–2176, y 1152–1408) holding a chest (1984, 1270). Loot on the island: wood pile (2470, 1296),
  stone pile (2470, 1600) (light catches). An armor statue `playground-lash-anchor` (2306, 1400)
  on the shore is the heavy catch that pulls the slime back off the island.
- **feel-yard**: three training dummies.

Nothing in the playground teaches jump, slam or teleport; tests teach them through `RunState`.

---

## 15. Game constants used (`content/game-constants.json`)

| Path | Value | Use |
|---|---|---|
| `gulp.formDurationMs` | 60000 | Form length (§11) |
| `character.player.stats.maxEnergy` | 100 | Energy cap, respawn refill |
| `character.player.stats.energyRegenPerSecond` | 8 | Regen (§4) |
| `character.player.stats.maxHp` | 100 | Base max HP (Goo Hearts add) |
| `character.player.gooHeart.maxHpBonus` | 10 | Per heart (§13.7) |
| `character.player.movement.dodgeDurationMs` / `dodgeCooldownMs` | 500 / 250 | Dodge cooldown 750 (§1) |
| `character.player.movement.baseSpeed` / `boostSpeed` / `movementSpeedCap` | 200 / 300 / 480 | Speeds the form multiplies (§11.3) |
| `input.bufferMs` | 150 | Every ability and eat press (player spec §7.3) |

Godot reads them with `Services.constants().number(path)` (`game_constants.gd`). Everything else
in this spec is a Phaser code literal (ability table, lash/teleport/jump geometry, sequence
timings, feel); keep them as named consts with their source lines, as `player.gd` does. Promoting
the ability table to game constants is a Phaser-side content change (conversion ledger) and out of
scope.

---

## 16. Feel, audio, texts and effects catalogue

Audio cues (all exist in `audio/global.scene.json`, pitch randomness 0.06, min interval 60 ms;
`GameFeel.audio_cue(name)`):

| Trigger | Cue |
|---|---|
| Jump start / landing | `Jump` / `Land` |
| Teleport out / in | `TeleportOut` / `TeleportIn` |
| Slam start / impact | `SlamWindup` / `SlamImpact` |
| Lash start | `Lash` |
| Any rejection but `busy` (dodge: not `cooldown`) | `AbilityDenied` |
| Eat clip | `Eat` |
| Ability learned | `AbilityLearned` |
| Ground cracked | `GroundCrack` |
| Bell rung | `BellRing` |
| Goo Heart | `Heal` (placeholder) |
| Building restored / refused for materials | `BuildingRestored` / `CraftFail` |
| Respawn energy refill | `EnergyRestore` [QUIRK §4] |

Feel presets (`GameFeel.ts:35-51`, already in `game_feel.gd`): `slam` 150 ms × 0.01 + 90 ms
hit-stop; `hit` 65 ms hit-stop (slam with hits); `ground-crack` 260 ms × 0.012;
`building-restored` 320 ms × 0.006.

Squash presets (`SquashStretch.ts:16-27`; Godot `squash_stretch.gd` has only `move-start`, `hit`):
`jump` (0.82, 1.35, 200 ms, Quad.Out; used as the jump's stretch target), `land` (1.32, 0.72,
220 ms, Back.Out; forced), `gulp` (1.24, 0.86, 320 ms, Elastic.Out). Reduce motion keeps 35 %.
Godot eases: Quad.Out → `TRANS_QUAD/EASE_OUT`, Quad.In → `TRANS_QUAD/EASE_IN`, Back.Out →
`TRANS_BACK/EASE_OUT`, Elastic.Out → `TRANS_ELASTIC/EASE_OUT`, Phaser default (Power0) →
`TRANS_LINEAR`. `SquashStretch` needs a `busy` callable (skip unless forced).

Visual "effects channel" (`Sprite2DNode.ts:70, 225-230, 311-321`): offset in world px added to the
sprite position, scale multiplied into the authored scale, alpha multiplied. Godot: offset →
`visual.position = rest_position + offset` (rest `(0, −27.56)`; **not** `visual.offset`, which the
attack clips key and `_play_clip` resets), scale → `visual.scale = base_scale × s` (pivot = the
old centre, same as Phaser), alpha → `visual.modulate.a`.

Floating texts (Godot `GameFeel.floating_text(pos, text, colour, big, duration_ms)`):

| Text | Colour | Big | ms | Position |
|---|---|---|---|---|
| Not learned yet | red | no | default | centre − 30 |
| Low energy / No safe spot there | orange | no | default | centre − 30 |
| HEAVY! / STICKY! / Heavy refreshed | cyan | yes | default | centre − 56 |
| Burp! / The form wore off | white | yes | default | centre − 56 |
| No Gulp spot here. Hold Q to eat what you carry / Nothing to gulp here / No Gulp materials carried | white | no | default | centre − 56 |
| The ground gives way! | yellow | yes | 1800 | ground root − 60 |
| It creaks under you... jump on it! (Space) | yellow | yes | 2200 | ground root − 50 |
| `<damage>` (dummy) | orange | yes | default | dummy root − 96 |
| +10 max HP | green | yes | 2000 | heart root − 40 |
| locked message / Missing: … / restored message | white / red / green | yes | 2400 / 2400 / 2600 | site root − 36 |

Particles and one-off effects to add in Godot: `goo-dust` burst (jump landing; texture
`ProceduralAssetScene.ts:66-73`: circles r 7 `#1a3a24`, r 5 `#7be08a`, r 2 white 0.85 at (7,7),
16×16), `loot-sparkle` preset (bell), `dust-puff` burst for restoration (60 particles,
§13.8), circle flashes (teleport 2 colours, slam ring), the jump shadow ellipse, the lash tendril
sprite (asset `effect.player.stretch-lash`, synced by `pnpm godot:sync`).

---

## 17. Centre vs feet (additions to player spec §11)

| Use | Phaser | Godot |
|---|---|---|
| Ability start, jump target, teleport landing, lash `from`, lash landing, slam centre | old centre | `get_centre()`; move with `FeetAnchor.place_at_phaser_position(body, p)` + `reset_physics_interpolation()` (not per step during the lash flight) |
| Aim origin (lash/teleport direction, teleport reach) | centre − 28 | `get_centre() − (0, aim_rise_px)` (decision O2) |
| Jump/teleport tile tests | centre point | same point |
| Teleport occupancy rect | 30×26 centred at centre + (0, 14.56) | same rect (= `BodyShape` at the feet-anchored position) |
| Jump shadow, landing dust, slam ring, teleport flashes | centre | centre (parity; owner may prefer the feet) |
| Gulp spot reach, plate weight, cracked-ground landing/weight, lesson, heart, restoration reach | centre to object root | `get_centre()` to `get_parent().global_position` |
| Gulp timer / wheel | centre − 76 / centre (pointer pick from centre − 28) | same |

---

## 18. Quirks and owner questions

| # | Item | Recommendation |
|---|---|---|
| O-A1 | The jump checks tiles only: it crosses walls/gates/houses and can land inside objects (§5.2); the 12 px "ensure movement" can land in a blocked tile | Port as is (parity) behind `jump_checks_objects := false`; ask the owner (the playground's heavy/lash pens and gloop-forest's gates can be bypassed once Jump is learned) |
| O-A2 | The jump's body stays at the start for 420 ms (hurtbox, camera, plates, webs); the shadow stays at the start centre | Parity |
| O-A3 | Teleport lands the centre 28 px below the pointer (§7.1) | Parity (follows O2) |
| O-A4 | Ability sequences run on scene time in Phaser (continue under menus; lash timers ignore hit-stop) | Godot: drive milestones on SimClock; everything pauses with the tree |
| O-A5 | Dodge on cooldown is silent; other abilities on cooldown play `AbilityDenied` | Parity |
| O-A6 | A rooted slime can lash and be pulled | Parity |
| O-A7 | `EnergyRestore` cue on every respawn | Parity (cheap) or drop; ask |
| O-G1 | Gulp skins re-texture the old side-view sheet; the Godot player uses new top-down art | Decided 2026-10-05: a shader skin over the new frames (`form_skin.gdshader`); the tint is the fallback |
| O-G2 | Holding Q near a spot eats from the inventory, or nothing when nothing is carried | Parity |
| O-G3 | "W" in descriptor/comments, binding is Q | Use the binding; fix the Phaser text separately (not in this port) |
| O-P1 | Plate/bell gate openings and latched plates are not saved | Parity now; a persistence decision belongs to world objects |
| O-B1 | A non-lash-only bell takes "defeated" hits (hp 1) | Parity (no content uses it) |
| O-R1 | Restoration needs an active quest; quests are OUT | Quest port returns "not active" (shows the locked message); a dev/test override |
| O-L1 | `AbilityBar.ts` and the ability-bar scene's "Lv N" texts are stale | Ignore in the port |

---

## 19. Godot port plan

### 19.1 Files

| File | Kind | Content |
|---|---|---|
| `game/player/abilities/ability_definitions.gd` | static `RefCounted` | The §1 table as consts (dodge cooldown from constants at runtime), rejection texts/colours, `title(id)`, `action(id)` |
| `game/player/abilities/player_abilities.gd` | `RefCounted` owned by `player.gd` | §2 rules: `cooldown_until`, `active_sequence`, `try_instant(id)`, `try_begin(id, request) -> Dictionary`, `complete(seq)`, `cancel()`, `status(id)`, `is_busy()`; `advance(now_ms)` drives the running sequence's milestones |
| `game/player/abilities/ability_terrain.gd` | static | `is_blocked(p)` (tiles), `is_occupied(space, p, exclude)` (§7.2), `trace()` (§5.2), `safe_landing()` (§7.2), `lash_landing()` (§8.4) |
| `game/player/abilities/ability_world.gd` | static | `line_reach()`, `first_bell_along()`, `lash_probe()`, `lash_ring()`, `strike_area()`, `shape_touches_segment()` (§8.1, §6.2) |
| `game/player/abilities/jump_sequence.gd`, `teleport_sequence.gd`, `slam_sequence.gd`, `lash_sequence.gd` | `RefCounted` | One per ability: `begin(intent)`, `advance(elapsed_ms) -> bool done`, `cancel()`; gameplay milestones on the sim clock (landing at 420, teleport at 120, impact at 320, catch at 120, flight progress), visuals with Tweens created on the Visual (they pause with the tree) |
| `game/player/abilities/ability_fx.gd` | `Node2D` helpers | Circle flash/ring (`_draw` + tween), shadow ellipse, tendril sprite, `goo-dust` burst |
| `game/player/gulp/gulp_forms.gd` | static | §11.1 table |
| `game/player/gulp/gulp_controller.gd` | `RefCounted` | §11.2 with an injected `now` Callable (unit-testable) |
| `game/player/gulp/gulp_hud.gd` | `Node2D` (high z) | Timer + badge and the `[Q] Gulp` hint (§11.5) |
| `game/scripts/gulp_spot.gd`, `pressure_plate.gd`, `cracked_ground.gd`, `lash_bell.gd`, `ability_lesson.gd`, `training_dummy.gd`, `goo_heart.gd`, `restoration_site.gd` | scene scripts | §13; exports = snake_case of the JSON keys with the §13 defaults; signals with camelCase payloads. Adding files to `game/scripts/` needs the architect/integrator (ARCHITECTURE §1); update ARCHITECTURE §6 and §10 in the same change |

Changes elsewhere: `player_input_buffer.gd` (actions), `pointer_aim.gd` (distance),
`squash_stretch.gd` (`jump`/`land`/`gulp` presets, `busy` callable, `force`), `particle_fx.gd`
(`loot-sparkle`, `goo-dust`, `dust-puff` presets; feel owner), `damage_router.gd` (optional
`registered_areas()`; combat owner), `hud.gd` (energy from `energy_changed`; world owner),
`run_state.gd` (`player.energy` round-trip; `add_goo_heart()`; world-objects owner).

### 19.2 `player.gd` step order (after the paused return)

```
now = Services.now_ms()
_finish_expired_action_clip(now)             # eat lock (§11.4)
_abilities.advance(now)                      # sequence milestones; completion unlocks + idle
_gulp.update()                               # expiry
if not _dead: _regen_energy(delta)           # §4
dead -> stop (and close eat hold) ; else:
  direction = movement keys
  if suppressed: pass
  elif _action_locked: velocity = 0
  elif _update_eat_hold(direction): velocity = 0
  elif _handle_action_input(): pass          # jump, dodge, stretch_lash, squash_slam, teleport, attack, eat
  else: squash-on-move-start; _move(direction)          # speed x form multiplier
if not _abilities.owns_body(): ArcadeMover.move(body, delta)     # the lash flight sets position directly
```

`apply_knockback`: return at once when the form is knockback-immune. `_die`: clear the form
(`cleared`), close the eat hold. `respawn`: energy full + `energy_changed`. `_exit_tree`:
`_abilities.cancel()` (frees transients, resets the visual).

### 19.3 API between `player.gd` and the world scripts

| Call | Returns / does | Used by |
|---|---|---|
| `get_centre() -> Vector2` | exists | everything |
| `is_dead() -> bool` | exists | lesson, heart, webs |
| `is_learned(id: StringName) -> bool` | RunState (+ `dodge_learned`) | rules, UI |
| `ability_status(id) -> Dictionary` / `activate_ability_from_ui(id)` | §2.5 / §2.6 | ability bar [OUT] |
| `is_ability_busy() -> bool` | §2.1 | squash, trail |
| `get_energy() -> float`, `get_max_energy() -> float`, `spend_energy(a) -> bool`; signal `energy_changed {"energy","maxEnergy","delta"}` | §4 | rules, HUD |
| `current_form() -> Dictionary` (`{}` or the §11.1 row), `current_form_id() -> StringName`, `form_remaining_ms() -> float` | §11 | HUD, tests |
| `presses_plates() -> bool` | Heavy | `pressure_plate.gd`, `cracked_ground.gd` |
| `crosses_webs() -> bool` | Sticky | spider-web / web-patch owner |
| `last_heavy_landing() -> Dictionary` (`{}` or `{"x","y","id"}`); signal `jump_landed {"x","y","heavy","id"}` | §5.3 | `cracked_ground.gd` |
| `eat() -> String` (`spot`/`burp`/`nothing`), `eat_material(item_id) -> String` | §11.2 (+ eat clip) | interaction candidate, wheel [OUT] |
| `nearest_gulp_spot() -> Node` | §11.2 | interaction candidate, HUD |
| `teleport_to(centre: Vector2)` | stop + place + reset interpolation | webs |
| `grant_goo_heart()` | RunState hearts + 1, `_max_hp = run.max_hp()`, `_hp = _max_hp`, `health_changed` | `goo_heart.gd` |
| `is_rooted() -> bool` | false until status effects are ported | §3.2 |

World side the abilities read: groups `&"gulp-spot"`, `&"lash-bell"` (with `damage_area` and
`ring()`), `&"gate"` (`gate_id`, `open()`); `Services.world().is_solid_tile`, `dimensions()`,
`world_root.get_world_2d().direct_space_state`; `Services.router()`; collectibles (light catch)
when ported. Story flags and learned abilities through `Services.run()`.

### 19.4 Order of implementation

1. Input actions, energy (+ HUD hook), `player_abilities.gd` rules and status; move the dodge
   onto them (existing dodge tests must stay green).
2. Jump (trace, sequence, landing record, squash `land`), `goo-dust`.
3. `training_dummy.gd`, then Squash Slam (`strike_area`, `SlamArea`, ring) — the dummy is the
   cheapest receiver to test against.
4. Teleport (`safe_landing`, occupancy query, flashes).
5. Gulp: forms, controller, eat tap, eat clip lock, `gulp_spot.gd`, HUD labels, speed multiplier,
   knockback immunity, tint.
6. `pressure_plate.gd` and `cracked_ground.gd` (need `gate.gd` and `story_variant.gd` from world
   objects for the visible result; the signals and flags are testable without them).
7. Stretch Lash (probe, ring, landing, flight, tendril), `lash_bell.gd`, `ability_lesson.gd`;
   light catch after collectibles.
8. `goo_heart.gd`.
9. `restoration_site.gd` (after the interaction router and inventory writes).
Deferred: quick wheel, ability bar screen, banners, Goo Trail, control hints, quests, status
effects (rooted), form skins, saving plate/bell gate state.

### 19.5 Tests (`godot/tests/`)

Harness: tests run in level-1 today (`run_tests.gd._setup` instances `main.tscn`). Add a per-file
`const MAP_ID := "playground"` that the runner sets on `main.map_id` before `add_child` (tests
owner); fallback: `await` `t.main.travel_to("playground")`. Set up with `t.teleport_player(centre)`,
`t.player().face(dir)` (no pointer in headless runs → aim = facing),
`Services.run().learn_ability("jump")`, and taps. Expected values (sim ms from the step that
consumes the press, tolerance one step = 16.7 ms unless noted):

`test_abilities.gd` (level-1 unless noted)
- Not learned: tap `jump` → no sequence, `AbilityDenied` cue, text "Not learned yet";
  `ability_status(&"jump")` = `{unlocked false, earnedBy "Quest", canActivate false}`.
- Jump in place: learned, no keys → centre unchanged, action-locked until +420, `jump_landed`
  at +420 with `heavy false`; `status.cooldownRemainingMs` 700 at the press; a second tap at
  +500 → rejected `cooldown` (cue); at +700 accepted.
- Jump right: hold `move_right` then tap `jump` → the sequence's `target − start` = (168, 0);
  centre x unchanged until +420, then = target.x (± 0.5).
- Jump stop at water (playground): centre (2200, 1450), hold right, tap jump → target
  (2360, 1450) (samples 8 px apart; the 2368 sample is in column 37); the landed centre may be
  pushed left to ≥ 2350 by `ArcadeMover` depenetration.
- Slam vs worm: passive worm at centre offset (60, 0); learn `squash-slam`; tap → worm HP 90 at
  +300, **60** at +320; worm velocity ≈ (242, 0) right after the impact; tree paused for ~90 ms
  real time; energy 70 (+ 8/s regen: ≈ 72.6 at +320); unlocked at +470; a worm at offset (200, 0)
  keeps 90 HP; second tap at +1000 → `cooldown`; accepted at +2500.
- Slam vs dummies (playground): centre (1480, 1440) → dummy 1 (rect y ≤ 1402, distance 38) and
  dummy 2 (closest point (1541, 1402), distance 71.9) emit `hit {damage: 30}`, dummy 3 (161 px)
  does not.
- Teleport (playground): centre (1280, 1536), face right, learn `teleport`, tap → centre
  (1280, 1536) until +120, then **(1520, 1536)**; energy 65; complete at +300; tap at +1000 →
  `cooldown`; accepted at +1800.
- Teleport blocked: centre (20, 1536), face left → every candidate is outside the world →
  "No safe spot there", energy 100, no cooldown.
- Energy: low-energy rejection (set energy 10, tap lash → "Low energy", nothing spent); regen
  10 → 18 after 1000 ms of sim time.
- Busy: tap `dodge` at +100 of a jump → no roll (the action lock keeps the press waiting and it
  is 320 ms old, so dropped, at the landing step); a tap at +300 rolls on the landing step (120 ms
  old). `ability_status(&"dodge").busy` is true during the jump (the `busy` rejection itself is
  reachable only from the ability bar).

`test_gulp.gd` (playground)
- Eat at the stone spot: centre (1120, 860) (60 px from the root), tap `eat` → form `heavy`,
  `form_remaining_ms` 60000 (± 17), text "HEAVY!", `Eat` cue, action-locked 167 ms.
- Heavy speeds: walk velocity (120, 0), sprint (180, 0); dodge still 380 px/s.
- Heavy knockback immunity: a worm hit lands (HP 100 → 66) but velocity stays 0 and
  `is_movement_suppressed()` false.
- Plate: Heavy at centre (1344, 800) → within 2 steps `pressed {plateId:"playground-heavy-plate"}`,
  Visual frame 7, gate `playground-heavy-gate` open (when `gate.gd` exists); walk away → no
  `released` (latch). Not Heavy at the same spot → nothing.
- End-card plate: Heavy at (1210, 400) → flag `playground-end-card-test` set (through the scene
  connection to `story_flag.gd`).
- Cracked ground: learn `jump`, Heavy, centre (1600, 1060), tap jump → at +420 flag
  `cracked.playground-sinkhole` set, `cracked` emitted, `ground-crack` shake; not Heavy → no
  crack; Heavy standing without a jump → creak text once, no crack.
- Burp: Heavy, centre far from spots, tap `eat` → form none, "Burp!", eat clip.
- Switch: Heavy, then eat at the silk spot (centre (680, 1720)) → `switched` then `started`
  sticky; walk speed 180; `crosses_webs()` true.
- Nothing: no form, away from spots, nothing carried → "Nothing to gulp here", no clip.
- `GulpController` unit test with a fake clock: expiry exactly at `ends_at` (60000), refresh
  resets to now + 60000, `remaining_ms` ceil formatting ("1:00", "0:01" at 1 ms).

`test_frog_form.gd` (level-1's lake, row 46: shallow x 3-5, deep x 6-11; §11.7)
- A frog spot placed at the slime, tap `eat` → form `frog`, skin 3, the body's mask without the
  `water` bit.
- Frog in deep water → swimming, waterline 30, a `swim-` clip while moving, the wake's swim row;
  back in shallow water → not swimming, waterline 0.
- Frog walking right from the shallows for 700 ms → past the middle of the first deep cell,
  swimming (fails while the tiles' physics layer is also on the world layer, 1025).
- Expired over deep water → still a frog, `eat()` = "nothing" (no burp); in the shallows → the
  form ends and the mask has the `water` bit again.
- Jump learned, tap `jump` while swimming → not airborne, no ability busy.

`test_world_puzzles.gd` (playground unless noted)
- Lesson: centre (1904, 1600) (80 px) → `stretch-lash` learned, `taught
  {abilityIds:["stretch-lash"]}`, `AbilityLearned` cue; at (1904, 1700) (180 px) nothing.
- Lash bell: lash learned, centre (2340, 1465), face right, tap `stretch_lash` → at +120 bell
  `rung {bellId:"playground-lash-bell"}` and gate `playground-lash-gate` open; catch at
  (2428, 1465), anchor (2490, 1470); landing ≈ (2460.0, 1469.0) (± 1); flight 120.08 / 0.9 =
  133.4 ms from +170; centre reaches the landing at ≈ +303; unlocked at ≈ +483; energy 80.
- Lash none: centre (1280, 1536), face right (no layer-1 body or pickup within 180 px) → no
  movement, unlock at +270, cooldown 2000, energy 80.
- Dummy sword hit: centre (1480, 1440), face up, tap `attack` → dummy 1 `hit {damage}` with 24
  (or 42 on a crit), orange text at (1480, 1304), wobble rotation ≠ 0 then 0 after ~0.89 s.
- Goo heart (level-1): centre within 20 px of (176, 3040) on dry ground → `collected
  {heartId:"meadow-lakeside"}`, flag `goo-heart.meadow-lakeside`, max HP 110, HP 110,
  `health_changed {hp:110, maxHp:110}`; travel away and back → the heart stays hidden.

### 19.6 Dependencies on other specs

- **world-objects.md** (in progress): `gate.gd` (`open()`, `gate_id`, group), `story_variant.gd`
  and `story_flag.gd` (in the working tree), `RunState` inventory writes (`add_item` for tests,
  `remove_item` exists), item names, collectibles (lash light catch, `requestPickup`), spider web
  and web patch (consume `crosses_webs()`, `is_rooted()`, `teleport_to()`), gate persistence.
- **interaction.md**: the interaction router (RMB), the `gulp-spots` candidate (priority 60) and
  the restoration candidate (priority 89); `interact` dispatch precedes the abilities (§3.2).
- **combat** (`combat.md`): router listing (optional), `PlayerCombat` shares `_action_locked`.
- **Quests [OUT]**: ability rewards, restoration `questId`, `object.activated`.
- **Art**: done (keyed ability clips, the filmed stretch lash, the shader form skins O-G1); the
  player's doze, sleep and defeat are filmed too, so no player clip uses the old sheet.
