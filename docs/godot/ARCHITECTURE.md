# Godot game architecture

How the Godot port is put together: autoloads, the time and pause model, coordinates, data
shapes, the scene-script contract, bootstrap and the two damage flows. Written for the Phase 0
trial (level-1, player slime, worm swordsman, basic sword) and kept current as the port grows.
Read it with [CONVENTIONS.md](./CONVENTIONS.md) and the [migration plan](../GODOT_MIGRATION.md).
The exact Phaser behaviour each part ports is in [specs/](./specs/): when this file and a spec
disagree about structure (files, names, who calls whom) this file wins; about behaviour, the spec wins.

---

## 1. Architecture overview

```
project.godot [autoload]  (registered in this order; tree order = process order)
  GameConstants  res://game/autoload/game_constants.gd   data: generated/data/*.json
  SimClock       res://game/autoload/sim_clock.gd        gameplay ms clock (pausable, priority -1000)
  WorldService   res://game/autoload/world_service.gd    world/player/camera/areas/scene index/pause reasons
  DamageRouter   res://game/combat/damage_router.gd      receiver registry + activations + route()
  GameFeel       res://game/feel/game_feel.gd            hit-stop, shake, floating text, particles, audio cues (ALWAYS)

res://game/main.tscn (main.gd)                         bootstrap
  World (Node2D)      <- world.level-1 instanced here (converter root, y-sorted)
       ...converted props/NPCs (npc.gd), world areas (world_area.gd), exit (world_exit.gd stub)
       WorldBounds (StaticBody2D, built at runtime)
       PlayerSlime (character.player-slime)  <- spawned at runtime
           ... PlayerScript (player.gd), HurtSfx, DeathSfx
           PlayerCombat (player_combat.gd)          <- added by main.gd
           BasicSword (weapon.basic-sword)          <- mounted by PlayerCombat.equip(), last child, at (0,-27.56)
               ... WeaponScript (weapon.gd), SwingSfx
       WormSwordsman xN (character.worm-swordsman)  <- EnemyPopulation, EnemyScript (enemy.gd)
       effect holders (Node2D) > BasicSwordImpact (effect.gd)  <- EffectSpawner
  WorldCamera (world_camera.gd, ALWAYS, priority 100)
  Hud (CanvasLayer 10, hud.gd) > PlayerHealthBar (player_health_bar.gd)
  FpsReadout (CanvasLayer 100, fps_readout.gd)
  ArrivalFade (CanvasLayer 5, runtime)      EnemyPopulation (enemy_population.gd, runtime)
GameFeel children: FloatingTextLayer (CanvasLayer 8), ParticleFx (Node2D, high z)
```

Design rules:
- **Scene scripts** live in `game/scripts/` and only there. A file there is a converter-visible script id (`game.<kebab>` → `<snake>.gd`). The converter attaches the file and writes exactly the `@export`s it declares. Do not add or remove files in `game/scripts/` without the architect or integrator.
- **No inheritance between scene scripts.** The converter reads only the target file's `@export var` lines, so every export is declared in the file itself. `character.gd` is therefore deliberately absent. Shared character maths lives in static helpers (`shared/feet_anchor.gd`, `shared/directions.gd`).
- **Static helpers** are `extends RefCounted` files with static funcs: perimeter, directions, feet anchor, resolver, scaling, AI, wander policy, aim and bounds. Small stateful helpers are RefCounted instances: input buffer, squash, territory, attack lifecycle, combo and activations.
- **Autoloads are reached only through `res://game/shared/services.gd`**, as `Services.router()`, `Services.world()`, `Services.feel()`, `Services.constants()`, `Services.clock()` and `Services.now_ms()`. This was verified on 4.7.2: the headless `--check-only -s` does **not** know autoload names, so a bare `DamageRouter.route(...)` fails the check with "Identifier not found". The getters are typed, so calls are still statically checked.
- **Cross-file types**: `const X := preload("res://...")`, where X equals the file's `class_name`. Autoload scripts have no `class_name`, because a class_name equal to an autoload name is an error. Preload cycles (`player.gd` ↔ `player_combat.gd`, `services.gd` ↔ the autoloads) were tested and are fine.

## 2. Autoloads (API summary; full docs in the files)

| Autoload | Key API | Process mode |
|---|---|---|
| `GameConstants` | `value(path, fallback)`, `number(path)`, `integer(path)`, `dictionary(path)`, `data_file(name)`. Paths are the JSON's camelCase dotted paths (`character.player.movement.baseSpeed`). A missing path is a push_error, never a balance fallback | default |
| `SimClock` | `now_ms`, `step_count`, `last_step_ms`, `reset()`. Ticks first in every physics step | PAUSABLE, physics priority -1000 |
| `WorldService` | `scene_path`, `instantiate_scene`, `spawn_at_phaser_position(scene_id, phaser_point, parent=null)`, `register_world`, `entities_root`, `dimensions`, `world_rect`, `map_id`, `camera_mode`, `areas(kind)`, `safe_zones`, `npc_wander_area(instance_id)`, `is_solid_tile`, `player_spawn_marker`, `player_spawn_point`, `find_spawn_point`, `register_player`, `primary_target`, `line_of_sight(from,to,exclude)`, `register_camera`, `set_pause_reason(reason, active)`, `has_pause_reason`, `clear`. Vars: `world_root`, `definition`, `ground_layer`, `player`, `player_body`, `camera`. Signals `world_registered`, `player_registered` | default |
| `DamageRouter` | `register_area(area, receiver, rule, tags=[])`, `unregister_area`, `receiver_for_area`, `tags_for_area`, `begin_activation(source, areas) -> int`, `end_activation`, `is_activation_active`, `route(request) -> result`. Signal `routed` | default |
| `GameFeel` | `play(event)`, `shake(ms, intensity)`, `hit_stop(ms)`, `is_frozen()`, `floating_text(world_pos, text, color_name, big, duration_ms=-1)`, `particles(preset, world_pos)`, `audio_cue(cue, payload)` | ALWAYS |

## 3. Time, pause and process model

- **One gameplay clock**: `Services.now_ms()` (SimClock). It is used for every gameplay timer: roll, i-frames, knockback, dodge cooldown, input buffer, weapon windows and cooldown, combo window, enemy stun, enemy flash, attack timing, search, sight throttle, despawn, spawn intervals and router `simulation_time`. Do not keep separate per-script accumulators, and do not use `Time.get_ticks_msec()` for gameplay.
- **Real time** (`Time.get_ticks_msec()`) is only for what Phaser ran on scene time: the player's 120 ms hit flash, the 1400 ms defeat→respawn delay, floating text, health-bar visibility, camera damping and shake, and the end of a hit-stop.
- **Hit-stop = tree pause.** `GameFeel.hit_stop(ms)` calls `WorldService.set_pause_reason(&"hit-stop", true)`. The tree is paused while any reason is active, so a hit-stop ending never unpauses a menu. While paused, physics, SimClock, AnimationPlayers, tweens and every pausable script stop. These keep running with `PROCESS_MODE_ALWAYS`: GameFeel and its text/particles, WorldCamera, Hud, FpsReadout, and **PlayerScript**.
- **PlayerScript is ALWAYS** so `_unhandled_input` keeps buffering presses, stamped with the frozen SimClock time. Its `_physics_process` must `return` at the top while `get_tree().paused`. Its `_process` drives the real-time flash and the respawn delay. `Engine.time_scale` is never used.
- **One mover call per body.** `player.gd` moves the player, `enemy.gd` moves each enemy (every path except defeated), and `npc.gd` moves each NPC, always with `ArcadeMover.move(body, delta)` (`game/shared/arcade_mover.gd`), never `move_and_slide()`: in floating mode that slides along walls at full speed (about 41 % faster on a diagonal than Arcade), stops dead near head-on and never cuts `velocity`. Velocity persists between steps: read it back after the move (the blocked component is zeroed, as in Arcade) and never reset it blindly.
- **Step order** inside one physics tick follows tree order: SimClock (priority -1000), then the autoloads, then Main → World children. Within the player that is PlayerScript (state machine, attack start), then PlayerCombat, then WeaponScript (overlap resolve, windows). This matches Phaser: player state machine → node scripts → physics → contacts. EnemyPopulation runs after the world nodes (one step later than Phaser; acceptable per the enemy spec).
- The weapon resolves `attack_area.get_overlapping_areas()` at the **start** of its step. That keeps Phaser's one-step hit latency.

## 4. Coordinates (feet vs centre)

Converted character roots sit at the feet and carry `metadata/depth_anchor`. Use `res://game/shared/feet_anchor.gd`:
- `FeetAnchor.phaser_position(root)` gives the old Phaser root position: the centre for the player and the enemies, the sprite bottom for NPCs.
- `FeetAnchor.place_at_phaser_position(root, p)` / `WorldService.spawn_at_phaser_position(...)` place a root at `p + depth_anchor * scale`.
- `FeetAnchor.local_phaser_origin(root)` = `-depth_anchor` gives the weapon mount and the camera aim offset.
- The player's `get_centre()` and the enemy's `get_centre()` wrap this.

Do every AI distance, aim, knock direction, perimeter test, spawn point, floating-text anchor and camera target in that old space (player spec 11, enemy spec 9, combat spec 14, world spec 0). Hurtbox/hitbox shapes and depth sorting need no script work. A hurtbox `Area2D.global_position` *is* the old centre (combat F3).

## 5. Data shapes

**Scene signal payloads** (signals declared in scene JSON connections) are one Dictionary in **Phaser's camelCase keys**: `health_changed {"hp","maxHp"}`, `defeated {"receiverNodeId"}`, `alerted {"state"}`, `attack_started {"ranged","windupMs"}` (enemy) / `{"weaponId","direction"}` (weapon), `finished {"effectId"}`. Converted `payloadFilter`s reference these keys. `receiverNodeId` = `str(body.get_path())`.

**Internal dictionaries use snake_case** (full definitions in the `damage_router.gd` header):
- request `{activation_id, source, attack_area, target_area, weapon_id, weapon_tags, damage_types, base_damage, effects:[{effect_id, potency}], impact:{position (old centre), knock}}`
- input `{scaled_damage, request, rule, state, simulation_time}`
- result `{status, reason, retryable, actual_damage, defeated, applied_effects, rejected_effects}`
- commit `{request, rule, result, simulation_time, receiver}` (this is also the `damaged` / `damage_feedback` payload)
- damage state `{hp, max_hp, dead}`; can-receive `{accepted, reason}`

**Receiver rules** are the authored `damageRule` Dictionary with camelCase keys (`{"priority":0,"damageMultiplier":1}`). The player uses the same shape as a const.

**Weapon → combat-port target**: `{area, receiver, position (target centre), attack_direction, tags}`. Swing payload: `{damage:int, knockback_strength, cooldown_ms, weapon_tags, damage_types}`.

**Area records** (`WorldService.areas(kind)`): `{id, kind, data (raw JSON, camelCase), perimeter}`, plus `stay_perimeter` for `enemy-spawn`. Perimeters are `{"shape":"rectangle",x,y,w,h}` / `{"shape":"circle",x,y,radius}` (`shared/perimeter.gd`, complete). `safe_zones()` returns the rectangle perimeters.

**Primary target**: `{player, body, centre, hurtbox, active, hostile}`, or `{}`.

## 6. Scene scripts: export / signal / handler contract (checked against the scene JSON)

| Script id → file | Exports (snake_case of the JSON keys the scenes set; *italic* = extra, not in JSON) | Signals (1 Dictionary arg) | Handlers |
|---|---|---|---|
| `game.player` → `scripts/player.gd` | `body, visual, animation, damage_area, player_name`; *`dodge_learned`=true, `aim_rise_px`=28* | `health_changed, damaged, defeated, damage_feedback`; *`respawned`* | `on_pickup_area_entered(area)` (stub) |
| `game.enemy` → `scripts/enemy.gd` (worm swordsman, archer, brawler, slime spider, orb weaver) | `body, visual, animation, damage_area, attack_area, faction, rank, max_health, targeting_radius, attack_range, movement_speed, attack_cooldown_ms, attributes, damage_rule, rewards, projectile, impact_effect`; *`display_name, arena_recovery_ms`* | `health_changed, damaged, defeated, alerted, attack_started, reward_requested, damage_feedback` | — |
| `game.weapon` → `scripts/weapon.gd` (13 weapon scenes) | `weapon_id, category, attack_area, animation, base_damage, cooldown_ms, knock_strength, damage_modifiers, harvest_capabilities, scaling, on_hit_effect_id, attack_plans` | `attack_started, attack_finished` | `on_area_entered(area)` |
| `game.effect` → `scripts/effect.gd` (all 9 `effects/*` scenes) | `effect_id, animation, lifetime_ms` | `finished` | — |
| `game.npc` → `scripts/npc.gd` (6 NPCs) | `body, visual, animation, character_id, npc_definition_id, wander_speed, pause_min_ms, pause_max_ms` | `interaction_lock_changed` | — |
| `game.world-definition` → `scripts/world_definition.gd` | `map_id, tile_size, columns, rows, metadata, camera_mode` | — | — |
| `game.world-area` → `scripts/world_area.gd` | `area_kind, area_id, area, data, shape, stay_shape` | — | — |
| `game.world-exit` → `scripts/world_exit.gd` (stub) | `map_id, exit_id, target_area_id, entry, area, gate`; *`arrival_grace_ms`=-1* | `navigation_resolved` | `on_body_entered(body)` |

Every other script id stays on the converter's `unported_script.gd`. In level-1 that covers `game.door`, `game.story-variant`, the encounter's `game.boss-camp`, collectibles and resource nodes. `game.matron` and `game.fatty` are separate ids. `game.web-patch` and `game.projectile` are not ported.

## 7. Bootstrap (main.gd `_ready`, world spec 1.2)

1. `apply_viewport_scale()`: set `root.content_scale_size` so 1 game px = 1 CSS px, and re-apply on `size_changed`.
2. `resolve_map_id()` returns `"level-1"`.
3. `load_world()`: instance `world.level-1` under `$World`, then `WorldService.register_world(root)`.
4. `WorldBounds.build(world_root, world_rect)`.
5. `spawn_player()`: `spawn_at_phaser_position("character.player-slime", WorldService.player_spawn_point(), world_root)`, then `register_player(PlayerScript node)`. The feet land at (640, 731.56).
6. `equip_trial_weapon()`: `PlayerCombat.new()` → child "PlayerCombat" of the player root → `setup(player)` → `player.set_combat(combat)` → `equip("basic-sword")`.
7. `start_enemy_population()`: `EnemyPopulation.new()` → `setup(areas("enemy-spawn"), safe_zones(), entities_root())`, `allowed_types = ["worm-swordsman"]`, `seed_initial()`.
8. `configure_npcs()`: for each node in group `"npc"`, call `configure_wander(npc_wander_area(npc.get_instance_id_key()).get("perimeter", {}))`.
9. `setup_camera()`: `$WorldCamera.setup(world_rect, camera_mode)`, `start_follow(player_root)`, `register_camera`, and connect `player.respawned` → `pan_to`.
10. `start_arrival_fade()`: 400 ms, `#0b1020`.
11. `setup_ui()`: `$Hud.bind_player(player)`, `$FpsReadout.bind_camera($WorldCamera)`.

## 8. Data flow: a sword hit on a worm

1. LMB → `PlayerScript._unhandled_input` → `PlayerInputBuffer.capture(event, now)`.
2. Physics step: SimClock ticks. `PlayerScript._physics_process` checks: not paused, not dead, not suppressed, not locked. Then `_handle_action_input()`: the dodge press goes first; the attack press (≤ `input.bufferMs`) → `_attack()`. That faces `Directions.snap_to_cardinal(pointer aim)` and calls `PlayerCombat.try_attack()`.
3. `PlayerCombat.try_attack()` runs the gates and sets `dir = Directions.cardinal_name(facing)`. The payload is damage `round(20 × 12/10)` = 24 (crit 5 % → 42), knockback 140, cooldown 1200. Then `WeaponScript.try_begin_attack(dir, payload)`, and on a crit `GameFeel.play(&"critical-hit")`.
4. `WeaponScript.try_begin_attack()`: `ready_at = now + 1200` → `PlayerCombat.on_attack_started()` (player `set_action_locked(true)`, `stop_movement()`, `play_animation("attack-1")`) → weapon clip `attack-<dir>` → emit `attack_started` → SwingSfx `play_cue`.
5. Later steps, `WeaponScript._physics_process`: resolve overlaps (none yet), then `frame = floor(elapsed/1000·fps)`. When the window opens: `DamageRouter.begin_activation(weapon, [attack_area])` and enable `<dir>--primary`.
6. The next step reads `attack_area.get_overlapping_areas()` and finds the worm's DamageArea → `_resolve_contact(area)`. It looks up `receiver = router.receiver_for_area(area)` (EnemyScript, not the wielder) and marks it tried for this window. Target = `{area, receiver, position = area.global_position (worm centre), attack_direction, tags = ["enemy"]}`. `damage = PlayerCombat.transform_damage(24, target)` = round(24 × 1 × combo 1.15) = **28**. Request: knockback effect 140, impact at the worm centre, `knock = Directions.cardinal_vector(dir)`. Then `router.route(request)`.
7. `DamageRouter.route` validates the request and activation, then checks source and duplicates. `DamageResolver.resolve(enemy, …, now)` gives scaled 28 → actual 28 → accepted (not defeated). The activation records it. Then `EnemyScript.commit_damage(commit)` and `publish_damage_feedback(commit)`.
8. `EnemyScript.commit_damage`: HP 90 → 62, `health_changed`, `damaged` → HurtSfx, hurt flag set. Hit feedback: `HitFlash.flash` until now+120, then `GameFeel.floating_text(-28, yellow, big)` at (centre.x, visual top − 8). It then calls `cancel_attack()`, sets velocity = knock × (140+120)·(1−0.45) = 143, stun 370 ms, and plays `knockback-<facing>` (restart).
9. Back in the weapon, `PlayerCombat.on_outcome(result, target)` runs. A crit plays `GameFeel.audio_cue(&"Crit")`. Then `GameFeel.play(&"hit")` → `hit_stop(65)`, which pauses the tree. It also emits `GameFeel.particles(&"hit-spark", centre − (0,12))` and `EffectSpawner.spawn_in_front("basic-sword-impact", dir, centre, feet)`.
10. `GameFeel._process` (real time) unpauses after 65 ms. The worm's enemy-clock flash therefore lasts 65 + 120 ms, as in Phaser.
11. When elapsed reaches the duration, `_finish_attack()`: shapes off, `end_activation`, weapon `idle`, `PlayerCombat.on_attack_finished` (unlock, `idle` unless knockback has priority), and `attack_finished`. The next swing is allowed 1200 ms after the start.

## 9. Data flow: a worm hit on the player

1. `EnemyPopulation._physics_process` runs only while the player centre is inside the pursue rect. Once `now > last + 2500` and fewer than 3 are alive, it spawns at a stay-rect point outside the safe zones: `spawn_at_phaser_position("character.worm-swordsman", point)`, then `configure_navigation(area, safe_zones)`.
2. `EnemyScript._physics_process` runs the territory (engaged), then the AI chase. At centre distance ≤ 38 it enters `attack`, and `EnemyAI.run` returns `attack_requested`. `_begin_attack(dir)` then runs:
   - lifecycle `try_begin(now, 1500)`;
   - `router.begin_activation(self, [attack_area])`;
   - impact at +400 ms, finish at +1050 ms;
   - attack area on, `attack-<facing>`;
   - `attack_started` → WindupSfx.
3. At `now ≥ impact`, `_resolve_attack` (once per swing): it re-checks centre distance ≤ 51.3. Request: `weapon_id "enemy-contact"`, tags `["contact","enemy"]`, base 37, knockback effect 260, impact at the worm centre, `knock = normalized(player centre − worm centre)`. Then `router.route()`.
4. `DamageResolver.resolve(player…)`. `PlayerScript.can_receive_damage` rejects with `"state-blocked"` (retryable) while dodging or inside i-frames; the worm does not retry. Otherwise `mitigate_damage` gives max(1, 37 − 3) = 34, and the hit is accepted.
5. `PlayerScript.commit_damage`: HP 100 → 66, i-frames until `commit.simulation_time + 500`, `health_changed` (the HUD and the floating health bar listen), `damaged` → HurtSfx. At HP 0 the death sequence runs synchronously: `die`, stop, `player-defeated` feel, `DEFEATED`, then a respawn after 1400 ms of real time. After that comes `defeated` → DeathSfx.
6. `PlayerScript.publish_damage_feedback`:
   - emits `damage_feedback`;
   - `GameFeel.play(&"player-hurt")`: shake 110 ms / 0.005 via `WorldService.camera.shake`, plus hit-stop 70;
   - squash `hit`, `slime-splash` at the centre, and red `-34` at centre − 30;
   - a 120 ms real-time HitFlash;
   - `apply_knockback(knock, 260, 160)`, skipped when defeated.
7. At +1050 ms the worm finishes its swing and returns to `chase`. Its next swing is allowed 1500 ms after this one started.

## 10. File map by area

The trial was built in four areas; files keep these areas so related code stays together.

| File | Area | Notes |
|---|---|---|
| `godot/project.godot` `[autoload]` | — | Autoload registrations |
| `game/main.tscn` | world | Replaces the placeholder |
| `game/main.gd` | world | |
| `game/autoload/game_constants.gd` | world | |
| `game/autoload/sim_clock.gd` | world | |
| `game/autoload/world_service.gd` | world | |
| `game/shared/services.gd` | world | **Complete**; change only to add an autoload |
| `game/shared/feet_anchor.gd` | world | **Complete** |
| `game/shared/directions.gd` | world | **Complete** |
| `game/shared/perimeter.gd` | world | **Complete** |
| `game/shared/arcade_mover.gd` | shared | The one way bodies move (Arcade-style slide; never `move_and_slide()`) |
| `godot/tests/**` | tests | Headless integration tests, `pnpm test:godot` |
| `game/world/world_camera.gd` | world | |
| `game/world/world_bounds.gd` | world | |
| `game/world/npc_wander_policy.gd` | world | |
| `game/scripts/world_definition.gd` | world | |
| `game/scripts/world_area.gd` | world | |
| `game/scripts/world_exit.gd` | world | Stub stays inert |
| `game/scripts/npc.gd` | world | |
| `game/ui/hud.gd` | world | |
| `game/ui/player_health_bar.gd` | world | |
| `game/ui/fps_readout.gd` | world | |
| `game/scripts/player.gd` | player | Picks directional clips (`_directional_clip`, `_flip_for`) |
| `game/characters/player_slime.tscn` | player | Godot-owned player scene (CONVENTIONS "Scenes Godot owns"); clips rebuilt by `tools/build_player_clips.gd` |
| `game/dev/playground.tscn` | world | `main.tscn` with `map_id = "playground"`; run with F6 |
| `game/player/player_input_buffer.gd` | player | |
| `game/player/pointer_aim.gd` | player | |
| `game/player/squash_stretch.gd` | player | |
| `game/scripts/enemy.gd` | enemy | |
| `game/enemy/enemy_ai.gd` | enemy | |
| `game/enemy/camp_territory.gd` | enemy | |
| `game/enemy/attack_lifecycle.gd` | enemy | |
| `game/enemy/enemy_population.gd` | enemy | |
| `game/combat/damage_router.gd` | combat | Autoload |
| `game/combat/damage_resolver.gd` | combat | |
| `game/combat/attack_activations.gd` | combat | |
| `game/combat/combat_scaling.gd` | combat | |
| `game/combat/combo_counter.gd` | combat | |
| `game/combat/player_combat.gd` | combat | |
| `game/combat/effect_spawner.gd` | combat | |
| `game/scripts/weapon.gd` | combat | Shown only while swinging (`show_when_idle` off, owner decision 2026-10-05) |
| `game/scripts/effect.gd` | combat | |
| `game/feel/game_feel.gd` | combat | Autoload |
| `game/feel/hit_flash.gd` | combat | |
| `game/feel/hit_flash.gdshader` | combat | Already functional |
| `game/feel/floating_text_layer.gd` | combat | |
| `game/feel/particle_fx.gd` | combat | |
| `game/runtime/**` | converter | Helpers the converter attaches (audio, animation, placeholders, UI) |

Only ported scene scripts live in `game/scripts/`: every file there is a script id the converter
attaches (`game.<kebab-id>` → `<snake_id>.gd`), so add one only when porting that script.

## 11. Call map between areas (who depends on whom)

- **player →** combat (`Services.router().register_area/unregister_area`, `PlayerCombat.try_attack`, `HitFlash.*`, `GameFeel.play/floating_text/particles/audio_cue`); world (`Services.world().player_spawn_point()`, `Services.constants()`, `Services.now_ms()`).
- **enemy →** combat (router `register_area/unregister_area/begin_activation/end_activation/route`, `HitFlash.*`, `GameFeel.floating_text`); world (`primary_target`, `line_of_sight`, `spawn_at_phaser_position`, `Perimeter.*`, `FeetAnchor.*`); player (via `primary_target`: `hurtbox`, `active`).
- **combat →** player (`get_facing`, `is_dead`, `is_action_locked`, `set_action_locked`, `stop_movement`, `play_animation`, `get_damage_area`; PlayerScript is the wielder receiver); world (`instantiate_scene`, `entities_root`, `set_pause_reason`, `camera.shake`, `constants`).
- **world →** player (`get_centre`, `is_dead`, `get_hud_snapshot`, `health_changed`, `respawned`, `set_combat`, `RESPAWN_PAN_MS`); combat (`PlayerCombat.new/setup/equip`); enemy (`EnemyPopulation.setup/allowed_types/seed_initial`).

## 12. Open questions

### Owner decisions (answered 2026-10-05 unless noted)

| # | Question | Decision |
|---|---|---|
| O1 | Moving vertically: the live look (`walk` in every direction) or the intended `hop`/`stretch`? (player spec 4.3) | **New art.** The slime sheet is side-view and has no real up/down walk, so the owner wants a new three-quarter top-down player sheet with idle and walk per direction (then attacks and abilities), built piece by piece. Page 1 (idle and walk per direction) is in since 2026-10-05: the player scene is Godot-owned and `player.gd` picks `<clip>-down/-up/-side` for its facing |
| O2 | Pointer aim origin. The player spec recommends the intended feet − 28; the combat spec says port as is (centre − 28 = feet − 55.56). The specs disagree | **Keep the live aim**: `aim_rise_px = 28` above the old centre (top of the head) |
| O3 | Combo off-by-one: every lone sword hit does 28, not 24 | **Fixed in the port**: the multiplier is the hit's own tier (×1.0, ×1.15, ×1.5), so a lone sword hit does 24 (crit 42); the Phaser game keeps its bug until it is retired |
| O4 | Standing still always un-flips the slime (faces left) | **Done with the new art** (2026-10-05): idle clips per direction keep the last facing |
| O5 | Trial setup: dodge learned, sword equipped, respawn at spawn after 1.4 s with no defeat screen, only the worm-swordsman camp active (the other three camps are skipped by `allowed_types`) | As listed |
| O6 | Godot bodies do not shove each other (Arcade did, slightly) | Accept for the trial |

### Converter and integration notes (resolved during the trial)

- Node-typed exports resolve only when listed in the node header (`node_paths=PackedStringArray(...)`); the converter writes it.
- Solid terrain tiles carry a `tile_id` custom data layer; their collision is merged rectangle bodies under `ground/TileCollision` (Phaser's outer-edge inset), which `WorldService.is_solid_tile` reads.
- Re-anchored scenes placed in worlds (NPCs) get `depth_anchor` added to their position; instance roots carry `metadata/instance_id` and `metadata/persistence_key`.
- The ground layer is the TileMapLayer whose `tile_set` is `res://generated/resources/terrain_tileset.tres`.
- Physics interpolation is on; the camera blends its target between ticks itself.
- `*.gd.uid` files are committed.
