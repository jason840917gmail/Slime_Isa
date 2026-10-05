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
  RunState       res://game/autoload/run_state.gd        the run: player stats, inventory, world records, story, travel handoff
  MusicDirector  res://game/audio/music_director.gd      world/boss music, fades, menu duck, arrival cue (ALWAYS)
  Shell          res://game/shell/shell.gd               pause/settings/controls/credits windows, area titles, game over, end cards, settings (ALWAYS)

res://game/shell/title.tscn (title.gd)                 title screen, the main scene (level-1 drifts behind; launch options skip it)

res://game/main.tscn (main.gd)                         bootstrap
  World (Node2D)      <- world.level-1 instanced here (converter root, y-sorted)
       ground (TileMapLayer, z -2) > TileCollision, WaterSurface (water_surface.gd)  <- mounted by register_world
       ...converted props/NPCs (npc.gd), world areas (world_area.gd), exits (world_exit.gd)
       WorldBounds (StaticBody2D, built at runtime)
       PlayerSlime (character.player-slime)  <- spawned at runtime
           ... PlayerScript (player.gd), HurtSfx, DeathSfx
           PlayerCombat (player_combat.gd)          <- added by main.gd
           BasicSword (weapon.basic-sword)          <- mounted by PlayerCombat.equip(), last child, at (0,-27.56)
               ... WeaponScript (weapon.gd), SwingSfx
       WormSwordsman xN (character.worm-swordsman)  <- EnemyPopulation, EnemyScript (enemy.gd)
           (archers, brawlers, spiders, orb weavers alike; slime_spider_ai.gd for the spiders)
       WormArrow / SpiderWeb (projectile.*)         <- EnemyProjectiles.fire, ProjectileScript (projectile.gd)
       level-1-fatty-one-eye-camp (encounter) > BossCampScript (boss_camp.gd)
       FattyOneEye (character.fatty-one-eye)        <- spawned by the camp, FattyScript (fatty.gd)
       orb-weaver (character.orb-weaver-matron)     <- gloop-forest's camp, MatronScript (matron.gd)
       MatronWebPatch (effect) > WebPatchScript     <- the Matron's volley; spider-web (object) > SpiderWebScript
       AttackTelegraph (attack_telegraph.gd, z -1)  <- a boss's ground warning while it lasts
       effect holders (Node2D) > BasicSwordImpact (effect.gd)  <- EffectSpawner
       GooTrail (goo_trail.gd, y 0)                <- the player's Goo Trail passive (ground decal)
       SlamArea / ability effects                  <- the player's abilities (game/player/abilities/)
  WorldCamera (world_camera.gd, ALWAYS, priority 100)
  Hud (CanvasLayer 10, hud.gd) > PlayerHealthBar (player_health_bar.gd), BossHealthBar (boss_health_bar.gd), AbilityBar (ability_bar.gd)
      WeaponHotbar (weapon_hotbar.gd)         <- the belt's 4 slots above the ability bar (crafting spec 8.6)
      MapUi (map_ui.gd, group map_ui) > Minimap (minimap.gd)   <- its WorldMap window lives under GameWindows
      QuestTracker (quest_tracker.tscn, group quest_tracker)   <- binds to Quests on its own
  FpsReadout (CanvasLayer 100, fps_readout.gd)
  ArrivalFade (CanvasLayer 5, runtime)      EnemyPopulation (enemy_population.gd, runtime)
  Interaction (interaction_controller.gd)   EnemyLoot (enemy_loot.gd)   ControlHints (CanvasLayer 10)   <- made once in _ready, kept across worlds
  FurniturePlacement (furniture_placement.gd, after World: the ghost draws over the world's z 0)
  GameWindows (CanvasLayer 40, game_windows.gd) > Root > the game windows (bag, crafting, dialogue, offer, map, ...)
      MenuWindows (menu_windows.gd, group menu_windows)  <- the menu key; makes InventoryScreen, CraftingScreen, MenuTabs under Root
  InventoryActions (inventory_actions.gd, group inventory_actions)  <- belt, consumables and craft glue; made once
      DialogueBox (dialogue_box.tscn), QuestOfferWindow (quest_offer_window.tscn)   <- mounted by Quests
  Quests (quest_service.gd, group quests)   QuestMarkers (npc_quest_markers.gd, z 1)   QuestWaypoint (quest_waypoint_view.gd, z 2)   <- made once, kept across worlds
GameFeel children: FloatingTextLayer (CanvasLayer 8), ParticleFx (Node2D, high z)
MusicDirector children: WorldMusic (the world's MusicPlayer, moved here), BossMusic (audio.global), FadingMusic
Shell children: ShellLayer (CanvasLayer 50) > Root > AreaTitleCard, PauseMenu, GameOver, SettingsMenu, CreditsMenu, ControlsMenu, EndCard, Fade
```

Design rules:
- **Scene scripts** live in `game/scripts/` and only there. A file there is a converter-visible script id (`game.<kebab>` → `<snake>.gd`). The converter attaches the file and writes exactly the `@export`s it declares. Do not add or remove files in `game/scripts/` without the architect or integrator.
- **Inheritance between scene scripts only where Phaser has it.** The converter merges the `@export`s along a script's `extends` chain, so a port may extend another scene script exactly when the Phaser script does: `fatty.gd` extends `enemy.gd` (FattyScript extends EnemyScript) and overrides its hooks (`_after_enemy_step`, `_attack_area_reach`, `_can_run_common_attack`, ...). There is still no `character.gd`: shared character maths lives in static helpers (`shared/feet_anchor.gd`, `shared/directions.gd`).
- **Static helpers** are `extends RefCounted` files with static funcs: perimeter, directions, feet anchor, resolver, scaling, AI, wander policy, aim and bounds. Small stateful helpers are RefCounted instances: input buffer, squash, territory, attack lifecycle, combo and activations.
- **Autoloads are reached only through `res://game/shared/services.gd`**, as `Services.router()`, `Services.world()`, `Services.feel()`, `Services.constants()`, `Services.clock()`, `Services.run()`, `Services.music()`, `Services.shell()` and `Services.now_ms()`. This was verified on 4.7.2: the headless `--check-only -s` does **not** know autoload names, so a bare `DamageRouter.route(...)` fails the check with "Identifier not found". The getters are typed, so calls are still statically checked.
- **Cross-file types**: `const X := preload("res://...")`, where X equals the file's `class_name`. Autoload scripts have no `class_name`, because a class_name equal to an autoload name is an error. Preload cycles (`player.gd` ↔ `player_combat.gd`, `services.gd` ↔ the autoloads) were tested and are fine.

## 2. Autoloads (API summary; full docs in the files)

| Autoload | Key API | Process mode |
|---|---|---|
| `GameConstants` | `value(path, fallback)`, `number(path)`, `integer(path)`, `dictionary(path)`, `data_file(name)`. Paths are the JSON's camelCase dotted paths (`character.player.movement.baseSpeed`). A missing path is a push_error, never a balance fallback | default |
| `SimClock` | `now_ms`, `step_count`, `last_step_ms`, `reset()`. Ticks first in every physics step | PAUSABLE, physics priority -1000 |
| `WorldService` | `scene_path`, `instantiate_scene`, `spawn_at_phaser_position(scene_id, phaser_point, parent=null)`, `register_world`, `entities_root`, `dimensions`, `world_rect`, `map_id`, `camera_mode`, `areas(kind)`, `safe_zones`, `npc_wander_area(instance_id)`, `is_solid_tile`, `player_spawn_marker`, `player_spawn_point`, `find_spawn_point`, `register_player`, `primary_target`, `line_of_sight(from,to,exclude)`, `register_camera`, `set_pause_reason(reason, active)`, `has_pause_reason`, `clear`. Vars: `world_root`, `definition`, `ground_layer`, `player`, `player_body`, `camera`. Signals `world_registered`, `player_registered` | default |
| `DamageRouter` | `register_area(area, receiver, rule, tags=[])`, `unregister_area`, `receiver_for_area`, `tags_for_area`, `begin_activation(source, areas) -> int`, `end_activation`, `is_activation_active`, `route(request) -> result`. Signal `routed` | default |
| `GameFeel` | `play(event)`, `shake(ms, intensity)`, `hit_stop(ms)`, `is_frozen()`, `floating_text(world_pos, text, color_name, big, duration_ms=-1)`, `particles(preset, world_pos)`, `audio_cue(cue, payload)` | ALWAYS |
| `RunState` | Phaser's `GameSaveData` in one place (snake_case): vars `player`, `inventory`, `world`, `story`, `location`, `quests`; `new_run()` (sets `trial_weapon_pending` for main's trial weapon), `ensure_started()`, `max_hp()`, `capture_player(map_id, snapshot)`; coins (`add_coins`, `spend_coins`); the bag (`item_count`, `item_capacity`, `add_item` all or nothing, `remove_item`, `transact_items`, `remove_from_slot`, `slots`, `collect_world_item`, `unlock_gate`); the belt (`weapon_slots`, `set_weapon_slots`, `equipped_weapon_id`, `set_equipped_weapon`); story (`has_flag`/`set_flag`, `learn_ability`, `knows_recipe`/`learn_recipes` and the dev flag `debug_all_recipes_known`, `record_talk`/`has_talked_to`); quests (`quest_status`, `is_quest_active`, `notify_quests_changed`); `map_record(map_id)` (resources, collectibles, inventory drops, placed furniture, chests, gates, object_states, ...), `placed_furniture`/`place_furniture`/`remove_placed_furniture`, `inventory_drops`/`create_inventory_drop`/`set_inventory_drop_amount`, `object_state`/`set_object_state`, `respawn_point`, `request_navigation`/`consume_navigation`; saves (`save_slot`, `load_slot`, `read_slot`, `list_saves`, `delete_slot`, the recovery autosave in slot 0, `serialize`/`install`). Signals for every change (`inventory_changed`, `coins_changed`, `story_flag_changed`, `ability_learned`, `weapon_loadout_changed`, `weapon_equipped`, `recipes_learned`, `recipe_crafted`, `craft_failed`, `quests_changed`, `world_progress_changed`, `saved`, `loaded`); each schedules the autosave. Outlives worlds | ALWAYS |
| `MusicDirector` (after `RunState`) | `set_boss_fight(active, camp_id)`, `fade_out(ms)`, `set_menu_paused(paused)`, `advance(ms)`, `world_gain/boss_gain/duck()`, `world_track/boss_track()`, vars `audio_unlocked`, `play_arrival_cue`; static `apply_mix(master, effects, music, muted)`, `set_bus_volume_linear(bus, v)` for the shell. Claims the world's music-bus player on `world_registered` and listens to the `boss_camp` group ([specs/audio.md](./specs/audio.md)) | ALWAYS |
| `Shell` (after `MusicDirector`) | `get_settings()` (GameSettings: `values()`, `update(change)`, `reset()`, `shake_scale()`, ... in user://settings.cfg), `open_pause()`, `can_open_pause()`, `open_settings/controls/credits()`, `handle_escape()`, `is_any_open()`, `show_area_title(text, colour)`, `show_defeat(info)`, `quit_to_title()`, `set_action(id, callable)` / `run_action(id)` for the windows other features own (`journal`, `inventory`, `map`, `save`, `load`, `wake`). Each open window holds the pause reason `shell:<surface id>`. Listens to `world_registered` (area card while a `world_main` node exists), `story_flag_changed` (end cards), `player_registered` ([specs/shell.md](./specs/shell.md)) | ALWAYS |

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
| `game.player` → `scripts/player.gd` | `body, visual, animation, damage_area, player_name`; *`dodge_learned`=true, `aim_rise_px`=28* | `health_changed, damaged, defeated, damage_feedback`; *`respawned`* | `on_pickup_area_entered(area)` (asks the pile's CollectibleScript) |
| `game.enemy` → `scripts/enemy.gd` (worm swordsman, archer, brawler, slime spider, orb weaver) | `body, visual, animation, damage_area, attack_area, faction, rank, max_health, targeting_radius, attack_range, movement_speed, attack_cooldown_ms, attributes, damage_rule, rewards, projectile, impact_effect`; *`display_name, arena_recovery_ms`* | `health_changed, damaged, defeated, alerted, attack_started, reward_requested, damage_feedback` | — |
| `game.weapon` → `scripts/weapon.gd` (13 weapon scenes) | `weapon_id, category, attack_area, animation, base_damage, cooldown_ms, knock_strength, damage_modifiers, harvest_capabilities, scaling, on_hit_effect_id, attack_plans` | `attack_started, attack_finished` | `on_area_entered(area)` |
| `game.effect` → `scripts/effect.gd` (all 9 `effects/*` scenes) | `effect_id, animation, lifetime_ms` | `finished` | — |
| `game.npc` → `scripts/npc.gd` (6 NPCs) | `body, visual, animation, character_id, npc_definition_id, wander_speed, pause_min_ms, pause_max_ms` | `interaction_lock_changed` | — (`get_phaser_position()`, `get_instance_id_key()`, `acquire_interaction_lock()`: a conversation holds the NPC still until its release runs; the quest service reads `npc_definition_id`) |
| `game.world-definition` → `scripts/world_definition.gd` | `map_id, tile_size, columns, rows, metadata, camera_mode` | — | — |
| `game.world-area` → `scripts/world_area.gd` | `area_kind, area_id, area, data, shape, stay_shape` | — | — |
| `game.world-exit` → `scripts/world_exit.gd` | `map_id, exit_id, target_area_id, entry, area, gate`; *`arrival_grace_ms`=-1* | `navigation_resolved` | `on_body_entered(body)` |
| `game.fatty` → `scripts/fatty.gd` (extends `enemy.gd`; `character.fatty-one-eye`) | the `game.enemy` exports + `contact_attack, landing_zone, contact_hop_cooldown_ms, contact_hop_duration_ms, leap_cadence_ms, small_hop_count, small_hop_duration_ms, between_hops_ms, air_time_ms, recovery_ms, landing_damage, landing_knockback_strength, landing_effect_id, landing_shake_ms, landing_shake_intensity` | the enemy signals + `phase_changed` | — |
| `game.boss-camp` → `scripts/boss_camp.gd` (`encounter.level-1-fatty-camp`, `encounter.gloop-matron-nest`) | `map_id, camp_id, boss_id, boss_scene, activation_area, arena_area, active_bosses, guarded_chest, guarded_chest_instance_id, respawn_ms, spawn` | `boss_spawn_requested, boss_defeated, guard_changed`; *`boss_engaged, boss_disengaged`* | — |
| `game.matron` → `scripts/matron.gd` (extends `enemy.gd`; `character.orb-weaver-matron`, node `EnemyScript`) | the `game.enemy` exports + `first_volley_delay_ms, volley_cadence_ms, volley_telegraph_ms, volley_rest_ms, volley_points, volley_spread, volley_radius, volley_damage, volley_knockback_strength, patch_effect_id` | the enemy signals + `phase_changed` | — |
| `game.projectile` → `scripts/projectile.gd` (`projectile.worm-arrow`, `projectile.spider-web`) | `projectile_id, body, visual, animation, attack_area, default_speed, lifetime_ms, rotate_to_velocity` | `launched, expired` | `on_area_entered(area)` (`launch(direction, speed, payload)`, `expire()`) |
| `game.web-patch` → `scripts/web_patch.gd` (`effect.matron-web-patch`) | `radius, visual` | `caught, torn` | — |
| `game.spider-web` → `scripts/spider_web.gd` (`object.spider-web`) | `width, depth, tears_when_crossed, visual` | `caught, torn` | — |

| `game.resource-node` → `scripts/resource_node.gd` (49 scenes: trees, stone, iron, amber ore; world-objects spec) | the `game.destructible` keys `map_id, instance_id, object_id, damage_area, max_health, initial_health, tags, damage_rule` + `drop, idle_animation_id, hit_effect_id, on_hit_animation_id, persist_health`=true, `depletion_message, harvest_requirement, animation` | `health_changed, damaged, damage_feedback, destroyed, resource_hit, harvest_blocked, drops_requested` | — (damage receiver API) |
| `game.collectible` → `scripts/collectible.gd` (16 scenes; spawned piles too) | `map_id, instance_id, object_id, item_id, quantity, source_resource_instance_id, source_inventory_drop_id, pickup_area` | `pickup_resolved, depleted` | — (`request_pickup(collector)`) |
| `game.story-flag` → `scripts/story_flag.gd` | `flag_id` | — | `on_set(payload)` (JSON handler `set`) |
| `game.story-variant` → `scripts/story_variant.gd` | `flag_id, when_set, when_unset` | `switched` | `on_set(payload)` |

| `game.door` → `scripts/door.gd` (10 doors; interaction spec) | `map_id, door_id, target_area_id, target_door_id, prompt, interact_radius, badge_rise` | — | — (`use()`, `arrival_point()`, group `door`) |
| `game.gate` → `scripts/gate.gd` | `map_id, gate_id, required_item_id, consume_on_unlock, prompt, locked_prompt, locked_message, unlocked_message, interact_radius, badge_rise, closed_frame, open_frame, visual, doors` | `opened` | `open(payload)` (plates, bells; not saved) |
| `game.chest` → `scripts/chest.gd` | `map_id, instance_id, initial_contents` | `guard_blocked, open_requested, stack_transferred, closed` | — |
| `game.bed` → `scripts/bed.gd` | `prompt, interact_radius, badge_rise, sleep_point, wake_point` | — | — (`sleep_request()`) |
| `game.workbench` → `scripts/workbench.gd` | `prompt, recipe_context, tier, interact_radius, badge_rise` | — | — (`site()`) |

| `game.training-dummy` → `scripts/training_dummy.gd` (abilities spec) | `damage_area, visual` | `hit` | — (damage receiver API) |
| `game.gulp-spot` → `scripts/gulp_spot.gd` | `material_item_id, radius, badge_rise` | — | — (`origin()`; the interaction controller offers "Eat") |
| `game.pressure-plate` → `scripts/pressure_plate.gd` | `plate_id, radius, sink_px, pressed_frame, gate_id, latch, visual` | `pressed, released` | — (`is_down()`; pressed by a heavy slime) |
| `game.cracked-ground` → `scripts/cracked_ground.gd` | `flag_id, radius, requires_landing` | `cracked` | — (`is_broken()`; a squash slam or a heavy landing) |
| `game.lash-bell` → `scripts/lash_bell.gd` | `bell_id, gate_id, lash_only, damage_area, visual` | `rung` | — (`ring()`, damage receiver API) |
| `game.ability-lesson` → `scripts/ability_lesson.gd` | `ability_ids, radius` | `taught` | — |
| `game.goo-heart` → `scripts/goo_heart.gd` | `heart_id, radius, bob_px, visual` | `collected` | — (`is_taken()`) |
| `game.restoration-site` → `scripts/restoration_site.gd` | `prompt, flag_id, object_id, quest_id, cost, locked_message, restored_message, interact_radius, badge_rise` | — | — (`origin()`, `cost_entries()`, `restore()`, `persistence_key()`; a restore sends `QuestEvents` `object.activated`) |

`game.destructible` has no scenes: its logic is `game/world_objects/destructible_health.gd`, owned by `resource_node.gd` (which declares the destructible exports itself). `game.interaction` has no scenes and no service behind it in Phaser, so it is not ported. Every other script id stays on the converter's `unported_script.gd`.

Enemies fire projectiles through `game/enemy/enemy_projectiles.gd` (Phaser's world `spawnEnemyProjectile`): the projectile goes under the world root and hits only the player's hurtbox ([specs/enemy.md](./specs/enemy.md) §12). Webs (`spider_web.gd`, `web_patch.gd`) reach the player through `game/enemy/spider_web_port.gd`, which calls player.gd's `crosses_webs()` and `teleport(centre)` and duck-types `apply_web(ms)` (a stop-and-suppress fallback until it exists) ([specs/matron.md](./specs/matron.md) §5).

Boss camps ([specs/boss.md](./specs/boss.md)) spawn their boss under the world root when the player centre enters the activation circle, hand it the arena (`EnemyScript.configure_arena`), keep their respawn timer and the defeated boss ids in RunState (`map_record(map_id)["boss_camps"]`, `world["defeated_boss_ids"]`), reset the fight when the player's `defeated` fires, and join the group `boss_camp`; the HUD's `BossHealthBar` binds itself to every camp in that group, and a later quest system listens to `boss_defeated` there.

## 7. Bootstrap (main.gd `_ready`, world spec 1.2)

1. `apply_viewport_scale()`: set `root.content_scale_size` so 1 game px = 1 CSS px, and re-apply on `size_changed`.
2. `RunState.ensure_started()`; the map is the pending travel handoff's (`RunState.consume_navigation()`), else `resolve_map_id()` (`"level-1"`). Steps 3-11 are `_build_world(map_id, handoff)`, which `travel_to` runs again for the next world.
3. `load_world()`: instance `world.level-1` under `$World`, then `WorldService.register_world(root)`.
4. `WorldBounds.build(world_root, world_rect)`.
5. `spawn_player(handoff)`: `spawn_at_phaser_position("character.player-slime", WorldService.player_spawn_point(), world_root)` (after a travel: `AreaTravel.arrival_point(handoff)`), then `register_player(PlayerScript node)` and `restore_run_state(RunState.player)` (HP). The feet land at (640, 731.56).
6. `equip_trial_weapon()`: `PlayerCombat.new()` → child "PlayerCombat" of the player root → `setup(player)` → `player.set_combat(combat)`; at a new run (`RunState.trial_weapon_pending`) `InventoryActions.grant_trial_weapon("basic-sword"` or the `weapon` launch option`)` puts it in the bag, on belt slot 1 and in hand (crafting owner decision C3); then `InventoryActions.equip_run_weapon()`: `WeaponLoadout.reconcile()` and `PlayerCombat.equip(RunState.equipped_weapon_id())` (nothing for an empty hand). Travel and loads keep the hand.
7. `start_enemy_population()`: `EnemyPopulation.new()` → `setup(areas("enemy-spawn"), safe_zones(), entities_root())`, `allowed_types` empty (every type the world's camps name; the trial allowed only `worm-swordsman`), `seed_initial()`.
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
| `game/world/water_surface.gd`, `water_surface.gdshader` | world | Animated water over the ground's water tiles ([specs/water.md](./specs/water.md)); mounted by `WorldService.register_world` |
| `game/world/npc_wander_policy.gd` | world | |
| `game/scripts/world_definition.gd` | world | |
| `game/scripts/world_area.gd` | world | |
| `game/scripts/world_exit.gd` | world objects | Level-triggered after the arrival grace; asks `Main.request_exit` |
| `game/autoload/run_state.gd` | world objects | Autoload `RunState` |
| `game/scripts/resource_node.gd`, `game/scripts/collectible.gd` | world objects | Spec world-objects.md |
| `game/scripts/story_flag.gd`, `game/scripts/story_variant.gd` | world objects | Flags in `RunState.story` |
| `game/world_objects/item_catalog.gd` | world objects | items.json + max stacks; weapons are items (names, icons, descriptions from `weapons.json`) |
| `game/crafting/recipe_catalog.gd`, `crafting_service.gd` | crafting | Recipes (`recipes.json`), stations and site lists; quotes, the status order and crafts on `RunState.transact_items` ([specs/crafting.md](./specs/crafting.md) §1-2) |
| `game/inventory/weapon_catalog.gd`, `item_icons.gd` | crafting | Weapon names, descriptions, icons, stats (`weapons.json`); item icons as atlas frames (`item-icons.json`) |
| `game/inventory/inventory_drops.gd` | crafting | Dropping bag items on the ground: placement, records, pile launch (restore is `EnemyLoot.restore_world`) |
| `game/inventory/inventory_actions.gd` | crafting | Child "InventoryActions" of main (group `inventory_actions`): the belt glue (switch, equip, assign, hold), consumables, after-craft, harvest advice, the trial grant and `equip_run_weapon` |
| `game/player/weapon_loadout.gd`, `wheel_stepper.gd` | crafting | Belt rules on RunState (owned, assign, cycle, equip, reconcile, grant); mouse-wheel notches to single steps |
| `game/ui/screens/menu_windows.gd` | crafting | GameWindows' child "MenuWindows" (group `menu_windows`): the menu key, `open_bag` / `open_crafting` / `open_station`, the tab strip state and coach, `register_tab` for the journal and map windows, the pause menu's Inventory action |
| `game/ui/screens/game_window.gd`, `item_cell.gd` | crafting | Base of the bag and crafting windows (centred `WindowPanel`, push / pop, focus, click and select cues); the `SlotButton` list cell (icon, name, tag; drag and drop) |
| `game/ui/screens/inventory_screen.gd`, `inventory_model.gd`, `crafting_screen.gd`, `crafting_model.gd`, `menu_tabs.gd` | crafting | The bag window, the crafting window (built in code, models with the exact texts) and the menu tab strip |
| `game/ui/weapon_hotbar.gd` | crafting | The HUD weapon belt (bottom centre, above the ability bar), built by `hud.gd` |
| `game/interaction/interaction_controller.gd` | interaction | Child "Interaction" of main, kept across worlds: targets (gates, doors, workbenches, beds, chests, NPCs), choice, execute; NPC candidates and conversations come from the quest service; the chest stand-in |
| `game/interaction/interaction_prompt.gd`, `interaction_badge.gd` | interaction | "Right-click: <prompt>" (CanvasLayer 9) and the key badge (world, z 1) |
| `game/rest/sleep_controller.gd` | interaction | Sleeping in a bed, owned by player.gd |
| `game/scripts/door.gd`, `gate.gd`, `chest.gd`, `bed.gd`, `workbench.gd` | interaction | Spec interaction.md |
| `game/world_objects/destructible_health.gd` | world objects | HP, records, regrow timer (the `game.destructible` logic) |
| `game/world_objects/resource_respawn.gd` | world objects | Regrow rule on the wall clock (`epoch_override_ms` for tests) |
| `game/world_objects/resource_drops.gd` | world objects | Drop cells, scatter, pile launch, restore, pile bookkeeping |
| `game/world/area_travel.gd` | world objects | Arrival point (door, entry edge, spawn), travel fades, music fade-out (only ambience once `MusicDirector` holds the music); `Main.travel_to` / `request_exit` drive it |
| `game/scripts/npc.gd` | world | |
| `game/ui/hud.gd` | world | Coins label and bars styled by the UI theme (`HudLabel`, `HudBar`) |
| `game/ui/hud_bar.gd` | world | One labelled HUD bar drawn from its theme variation (`HudBar`, `BossBar`) |
| `game/ui/player_health_bar.gd` | world | Styled by `FloatingHealthBar` |
| `game/ui/fps_readout.gd` | world | Styled by `DebugPanel` / `DebugLabel` |
| `game/scripts/player.gd` | player | Plays every clip in its version for the facing (`_directional_clip`, `_flip_for`); energy, effects channel, statuses, Gulp forms and abilities hang off it |
| `game/player/abilities/ability_definitions.gd`, `player_abilities.gd` | abilities | Ability table, energy costs and cooldowns on the sim clock, the dispatch order ([specs/abilities.md](./specs/abilities.md)) |
| `game/player/abilities/jump_sequence.gd`, `slam_sequence.gd`, `teleport_sequence.gd`, `lash_sequence.gd` | abilities | One sequence per ability (tween steps chained with `parallel()`) |
| `game/player/abilities/ability_terrain.gd`, `ability_world.gd`, `ability_fx.gd` | abilities | Landing and line checks against the world, strike areas, lash probes, the shared effects |
| `game/player/gulp/gulp_forms.gd`, `gulp_controller.gd`, `gulp_hud.gd` | abilities | Gulp forms (eating materials): timers, tint, speed and the form HUD |
| `game/player/status_effects.gd` | player | Burn, poison, slow, sticky, bouncy, frenzy, and the web root (`apply_web`) |
| `game/player/goo_trail.gd` | abilities | The Goo Trail passive: smears under the slime that slow enemies |
| `game/building/furniture_placement.gd`, `placed_furniture.gd` | world objects | Child "FurniturePlacement" of main: placing furniture (ghost, free test, records, quest event), picking it up, mounting placed benches on every world build ([specs/furniture.md](./specs/furniture.md)) |
| `game/hints/control_hints.gd` | interaction | Child "ControlHints" of main (CanvasLayer 10): first-time control hints, learned by use as `hint.<id>` story flags |
| `game/ui/ability_bar.gd` | abilities | The HUD's ability bar (bottom centre): labels from `player.ability_status`, clicks run `activate_ability_from_ui` |
| `game/scripts/training_dummy.gd`, `gulp_spot.gd`, `pressure_plate.gd`, `cracked_ground.gd`, `lash_bell.gd`, `ability_lesson.gd`, `goo_heart.gd`, `restoration_site.gd` | abilities | The abilities' puzzle pieces (§6) |
| `game/saves/save_slots_menu.gd`, `.tscn` | saves | The save slots window (three slots and the autosave) on the Shell's stack; RunState mounts it and registers the Shell's `save` / `load` actions |
| `game/world_objects/enemy_loot.gd` | world objects | Child "EnemyLoot" of main: enemy coins, loot piles scattered round the corpse, their records and restore |
| `game/ui/screens/game_windows.gd` | UI | Child "GameWindows" of main (CanvasLayer 40): the game windows' parent, the one `modal` pause owner, Escape for the top window |
| `game/ui/map/map_ui.gd`, `minimap.gd`, `map_terrain.gd`, `map_markers.gd`, `world_map_window.gd`, `.tscn` | map | The HUD minimap (see-through as in Phaser; `terrain_alpha` bakes the world's ground instead; markers, view) and the world map window on GameWindows; the `map` key, the pause menu's Map action and the marker API ([specs/map.md](./specs/map.md)) |
| `game/quests/quest_events.gd` | quests | `QuestEvents.emit(event, payload)` for world scripts and features |
| `game/quests/quest_service.gd` | quests | Child "Quests" of main (group `quests`), kept across worlds: the quest state machine over `RunState.quests`, commands, queries, NPC candidates and markers, load validation, the `quest` launch option; mounts the dialogue box and the offer window in GameWindows ([specs/quests.md](./specs/quests.md)) |
| `game/quests/quest_catalog.gd`, `quest_objectives.gd` | quests | The 14 definitions (`generated/data/quests-chapter-*.json`), recipe and NPC lookups, reward and objective texts; the objective matchers |
| `game/quests/quest_npc_talk.gd`, `quest_notifications.gd`, `quest_waypoint.gd` | quests | NPC conversations (offer, turn-in, reoffer, plain talk); toasts, chapter and ability banners, quest cues; the waypoint target resolver |
| `game/ui/screens/dialogue_box.tscn/.gd`, `quest_offer_window.tscn/.gd` | quests | The NPC dialogue box and the quest offer / turn-in window (Godot-owned copies of `ui.npc-dialogue`, `ui.quest-offer-modal`) on GameWindows |
| `game/ui/quest_tracker.tscn/.gd`, `npc_quest_markers.gd`, `quest_waypoint_view.gd` | quests | The HUD quest tracker (copy of `ui.quest-tracker`), the "!"/"?" markers over NPCs (main's "QuestMarkers", z 1) and the gold waypoint (main's "QuestWaypoint", z 2) |
| `game/characters/player_slime.tscn` | player | Godot-owned player scene (CONVENTIONS "Scenes Godot owns"); clips rebuilt by `tools/build_player_clips.gd` |
| `game/dev/playground.tscn` | world | `main.tscn` with `map_id = "playground"`; run with F6 |
| `game/player/player_input_buffer.gd` | player | |
| `game/player/pointer_aim.gd` | player | |
| `game/player/squash_stretch.gd` | player | |
| `game/scripts/enemy.gd` | enemy | |
| `game/enemy/enemy_ai.gd` | enemy | |
| `game/enemy/camp_territory.gd` | enemy | |
| `game/enemy/attack_lifecycle.gd` | enemy | |
| `game/enemy/enemy_population.gd` | enemy | Camps and legacy `metadata.spawns`, `slow_enemies_near` ([specs/enemy.md](./specs/enemy.md) §18, §15) |
| `game/enemy/slime_spider_ai.gd` | enemy | `SlimeSpiderAI.ts` (enemy spec §14) |
| `game/enemy/enemy_projectiles.gd` | enemy | The world's `spawnEnemyProjectile` (enemy spec §12.3) |
| `game/scripts/projectile.gd` | enemy | `game.projectile`: flight, lifetime, wall stop, one hit on the player |
| `game/enemy/spider_web_port.gd` | enemy | The world's `world.spider-web` port, `catchInWeb`, `applyWeb` (duck-typed player hooks, [specs/matron.md](./specs/matron.md) §5) |
| `game/scripts/fatty.gd` | boss | Fatty One Eye's phases on top of `enemy.gd` ([specs/boss.md](./specs/boss.md)) |
| `game/scripts/matron.gd` | boss | The Orb-Weaver Matron's volleys on top of `enemy.gd` ([specs/matron.md](./specs/matron.md)) |
| `game/scripts/web_patch.gd`, `game/scripts/spider_web.gd` | boss | Web patches and web barriers (matron spec §5) |
| `game/scripts/boss_camp.gd` | boss | Activation, spawn, defeat, respawn and reset of a boss camp |
| `game/bosses/boss_arena.gd` | boss | `BossCampBehavior.ts`: perimeters, clamp, containment, spawn eligibility |
| `game/bosses/area_shapes.gd` | boss | World-space shapes of an Area2D and their overlap tests (attack areas vs the player's hurtbox) |
| `game/bosses/attack_telegraph.gd` | boss | Ground warnings (`AttackTelegraphs.ts`), one per attacker |
| `game/ui/boss_health_bar.gd` | boss | The boss bar on the HUD layer (`BossHealthSurfacePort.ts`) |
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
| `game/audio/music_director.gd` | audio | Autoload `MusicDirector`: world and boss music, leave/arrival fades, menu duck, `AreaTransition` cue, the mix hook ([specs/audio.md](./specs/audio.md)) |
| `game/shell/shell.gd` | shell | Autoload `Shell`: window stack, Escape and pause, area titles, game over, end cards, quit to title ([specs/shell.md](./specs/shell.md)) |
| `game/shell/title.tscn`, `title.gd` | shell | The title screen (the main scene): launch-option skip, level-1 backdrop, New Game / Continue / Load / Settings / Credits |
| `game/shell/*_menu.tscn/.gd`, `game_over.*`, `end_card.*`, `area_title_card.*` | shell | The shell windows (Godot-owned copies of the `ui.*` scenes) on `shell_menu.gd` |
| `game/shell/game_settings.gd`, `control_labels.gd`, `area_titles.gd`, `launch_options.gd` | shell | Settings (user://settings.cfg, bus mix, GameFeel), InputMap key labels, area names / colours, launch options |
| `game/ui/theme/ui_tokens.gd`, `slime_theme.tres` | UI theme | Design tokens and the one UI Theme, built by `tools/build_ui_theme.gd` ([UI_THEME.md](./UI_THEME.md)) |

Only ported scene scripts live in `game/scripts/`: every file there is a script id the converter
attaches (`game.<kebab-id>` → `<snake_id>.gd`), so add one only when porting that script.

## 11. Call map between areas (who depends on whom)

- **player →** combat (`Services.router().register_area/unregister_area`, `PlayerCombat.try_attack`, `HitFlash.*`, `GameFeel.play/floating_text/particles/audio_cue`); world (`Services.world().player_spawn_point()`, `Services.constants()`, `Services.now_ms()`).
- **enemy →** combat (router `register_area/unregister_area/begin_activation/end_activation/route`, `HitFlash.*`, `GameFeel.floating_text`); world (`primary_target`, `line_of_sight`, `spawn_at_phaser_position`, `packed_scene`, `Perimeter.*`, `FeetAnchor.*`); player (via `primary_target`: `hurtbox`, `active`; webs through `spider_web_port.gd`: `get_centre`, `is_dead`, `crosses_webs`, `teleport`, optional `apply_web`, fallback `stop_movement`/`suppress_movement`).
- **boss →** enemy (`fatty.gd` and `matron.gd` extend `enemy.gd`; the camp calls `configure_arena`); combat (router `begin_activation/route/end_activation` through `_route_immediate_attack`); world (`spawn_at_phaser_position`, `entities_root`, `primary_target`, `player_registered`, `Services.run()` records); feel (`shake`, `particles`, `floating_text`, `audio_cue`, `play`); player (its `defeated` signal resets the fight). The HUD's `BossHealthBar` reads the camps (group `boss_camp`) and the boss's `get_damage_state`.
- **combat →** player (`get_facing`, `is_dead`, `is_action_locked`, `set_action_locked`, `stop_movement`, `play_animation`, `get_damage_area`; PlayerScript is the wielder receiver); world (`instantiate_scene`, `entities_root`, `set_pause_reason`, `camera.shake`, `constants`).
- **world →** player (`get_centre`, `is_dead`, `get_hud_snapshot`, `health_changed`, `respawned`, `set_combat`, `RESPAWN_PAN_MS`); combat (`PlayerCombat.new/setup/equip`); enemy (`EnemyPopulation.setup/allowed_types/seed_initial`); quests (`Quests.on_world_built(map_id)` after each build, `close_conversations()` on teardown).
- **crafting / bag / belt →** RunState (bag, belt, recipes, drop records); PlayerCombat (`equip`, `unequip`, `get_weapon`, `is_attacking`); player (`get_centre`, `get_facing`, `heal`, `restore_energy`, `play_animation`, `is_action_locked`); GameWindows (`add_window`, `push`/`pop`); Shell (`set_action(&"inventory")`, `is_any_open`); ResourceDrops (`spawn_pile`, `occupied_cells`); feel (`floating_text`, `audio_cue`); quests through `QuestEvents` (`craft.completed`, `control.used {weapon-switch}`). The player's wheel and resource nodes' blocked text reach `InventoryActions` by group; the interaction controller calls `MenuWindows.open_station`.
- **quests →** RunState (`quests` records, facts, rewards: `transact_items`, `learn_recipes`, `learn_ability`, `set_flag`, `add_coins`); GameWindows (`add_window`, `push`/`pop`, `window_opened`); Shell (`menu_opened`, `show_area_title`); NPCs (`acquire_interaction_lock`, `get_phaser_position`); boss camps (`boss_defeated`); feel (`floating_text`, `audio_cue`). World scripts reach quests only through `QuestEvents.emit` (collectible pickups, ordinary enemy deaths in `enemy_loot.gd`, restorations, crafting); the interaction controller asks `npc_candidate` / `talk_to` (group `quests`).

## 12. Open questions

### Owner decisions (answered 2026-10-05 unless noted)

| # | Question | Decision |
|---|---|---|
| O1 | Moving vertically: the live look (`walk` in every direction) or the intended `hop`/`stretch`? (player spec 4.3) | **New art.** The slime sheet is side-view and has no real up/down walk, so the owner wants a new three-quarter top-down player sheet with idle and walk per direction (then attacks and abilities), built piece by piece. Page 1 (idle and walk per direction) and page 2 (rolls) are in since 2026-10-05, with keyed sword swings on page 1's art: the player scene is Godot-owned and `player.gd` plays `<clip>-down/-up/-side` (or `-left`) for its facing |
| O2 | Pointer aim origin. The player spec recommends the intended feet − 28; the combat spec says port as is (centre − 28 = feet − 55.56). The specs disagree | **Keep the live aim**: `aim_rise_px = 28` above the old centre (top of the head) |
| O3 | Combo off-by-one: every lone sword hit does 28, not 24 | **Fixed in the port**: the multiplier is the hit's own tier (×1.0, ×1.15, ×1.5), so a lone sword hit does 24 (crit 42); the Phaser game keeps its bug until it is retired |
| O4 | Standing still always un-flips the slime (faces left) | **Done with the new art** (2026-10-05): idle clips per direction keep the last facing |
| O5 | Trial setup: dodge learned, sword equipped, respawn at spawn after 1.4 s with no defeat screen, only the worm-swordsman camp active (the other three camps are skipped by `allowed_types`) | As listed. Since 2026-10-05 every camp spawns: archers, brawlers, slime spiders and orb weavers are ported (`allowed_types` is empty) |
| O6 | Godot bodies do not shove each other (Arcade did, slightly) | Accept for the trial |

### Converter and integration notes (resolved during the trial)

- Node-typed exports resolve only when listed in the node header (`node_paths=PackedStringArray(...)`); the converter writes it.
- Solid terrain tiles carry a `tile_id` custom data layer; their collision is merged rectangle bodies under `ground/TileCollision` (Phaser's outer-edge inset), which `WorldService.is_solid_tile` reads.
- Re-anchored scenes placed in worlds (NPCs) get `depth_anchor` added to their position; instance roots carry `metadata/instance_id` and `metadata/persistence_key`.
- The ground layer is the TileMapLayer whose `tile_set` is `res://generated/resources/terrain_tileset.tres`.
- The water surface is the ground layer's child `WaterSurface` (z -2, drawn right after the tiles); underwater life (z -2) y-sorts after it. When terrain blending is ported it must draw between the tiles and the surface, and the shader's interim `smooth_water_ground` goes off (water spec 6.1).
- Physics interpolation is on; the camera blends its target between ticks itself.
- `*.gd.uid` files are committed.
