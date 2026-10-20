# Godot game architecture

How the Godot port is put together: autoloads, the time and pause model, coordinates, data
shapes, the scene-script contract, bootstrap and the two damage flows. Written for the Phase 0
trial (level-1, player slime, worm swordsman, basic sword) and kept current as the port grows.
Read it with [CONVENTIONS.md](CONVENTIONS.md) and the [migration plan](../GODOT_MIGRATION.md).
The exact Phaser behaviour each part ports is in [specs/](specs): when this file and a spec
disagree about structure (files, names, who calls whom) this file wins; about behaviour, the spec wins.

---

## 1. Architecture overview

```
project.godot [autoload]  (registered in this order; tree order = process order)
  GameConstants  res://game/autoload/game_constants.gd   data: game/data/*.json
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
       ground (TileMapLayer, z -2, world_ground.gd: mounts these in the editor too) > TileCollision (rock walls, in 174), GroundSurface (ground_surface.gd), WaterSurface (water_surface.gd), TerrainEdges (terrain_edges.gd) > Level0..3  <- mounted by register_world
           Elevation (elevation.gd) > Patches, Shade, Sides, Ramps, RampFeet, Stairs, Occlusion, Collision > Level<n>, Stairs  <- mounted by register_world when the world has an elevation layer
           WaterWake (water_wake.gd)  <- mounted by register_world; puts the water wake sprites on every walker body (WaterWakeBack first, WaterWakeFront last)
       elevation (TileMapLayer, elevation_layer.gd)  <- painted levels and stairs; hidden in the game
       forest (TileMapLayer, forest_layer.gd) > Trees, Shadows, Collision  <- painted tree walls (FORESTS.md); builds its own trees
       walls (TileMapLayer, wall_layer.gd) > Walls, Collision  <- painted built walls (WALLS.md); draws its own pieces
       webs (TileMapLayer, web_layer.gd, z -1) > Webs  <- painted floor webs (WEBS.md): halve a walk, stick a Roll; draws its own webs
       cell-props, details, large-props, old-props (TileMapLayer, prop_layer.gd) > Props  <- painted scenery (PROPS.md); instances its own props
       Scenery (Node2D, y-sorted)  <- props placed as nodes from the Scenery dock (PROPS.md)
       Enemies (Node2D) > placed-enemy.tscn (placed_enemy.gd)  <- the world's enemies, placed by hand; draw only in the editor (specs/enemy.md §3.3)
       ...converted props/NPCs (npc.gd), world areas (world_area.gd), exits (world_exit.gd)
       WorldBounds (StaticBody2D, built at runtime)
       PlayerSlime (character.player-slime)  <- spawned at runtime
           ... PlayerScript (player.gd), HurtSfx, DeathSfx
           PlayerCombat (player_combat.gd)          <- added by main.gd
           BasicSword (weapon.basic-sword)          <- mounted by PlayerCombat.equip(), last child, at (0,-27.56)
               ... WeaponScript (weapon.gd), SwingSfx
       WormSwordsman xN (character.worm-swordsman)  <- EnemyPopulation, EnemyScript (enemy.gd)
           (archers, brawlers, spiders, orb weavers alike; line_up_ai.gd for the four-way shooters: archers and spiders)
       WormArrow / SpiderWeb (projectile.*)         <- EnemyProjectiles.fire, ProjectileScript (projectile.gd)
       fatty-camp (encounter.fatty-lair-boss, in world.fatty-lair) > BossCampScript (boss_camp.gd)
       FattyOneEye (character.fatty-one-eye)        <- spawned by the camp, FattyScript (fatty.gd)
       orb-weaver (character.orb-weaver-matron)     <- gloop-forest's camp, MatronScript (matron.gd)
       MatronWebPatch (effect) > WebPatchScript     <- the Matron's volley; spider-web (object) > SpiderWebScript
       AttackTelegraph (attack_telegraph.gd, z -1)  <- a boss's ground warning while it lasts
       effect holders (Node2D) > BasicSwordImpact (effect.gd)  <- EffectSpawner
       GooTrail (goo_trail.gd, y 0)                <- the player's Goo Trail passive (ground decal)
       RollFx (roll_fx.gd, y 0)                    <- the Roll's skid streaks and dust (ground decal; made by player_roll.gd)
       SlamArea / ability effects                  <- the player's abilities (game/player/abilities/)
  WorldCamera (world_camera.gd, ALWAYS, priority 100)
  Hud (CanvasLayer 10, hud.gd) > HudConsole (console/hud_console.gd: the bottom console, its orbs and menu buttons), PlayerHealthBar (player_health_bar.gd), BossHealthBar (boss_health_bar.gd), AbilityBar (ability_bar.gd, placed on the console)
      WeaponHotbar (weapon_hotbar.gd)         <- the weapon in hand and its carousel, placed on the console (crafting spec 8.6)
      MapUi (map_ui.gd, group map_ui) > Minimap (minimap.gd)   <- its WorldMap window lives under GameWindows
      QuestTracker (quest_tracker.tscn, group quest_tracker)   <- binds to Quests on its own
  FpsReadout (CanvasLayer 100, fps_readout.gd)
  ArrivalFade (CanvasLayer 5, runtime)      EnemyPopulation (enemy_population.gd, runtime)
  Interaction (interaction_controller.gd)   EnemyLoot (enemy_loot.gd)   ControlHints (CanvasLayer 10)   <- made once in _ready, kept across worlds
  FurniturePlacement (furniture_placement.gd, after World: the ghost draws over the world's z 0)
  GameWindows (CanvasLayer 40, game_windows.gd) > Root > the game windows (bag, crafting, dialogue, offer, map, journal, chest, ...)
      QuestJournal (quest_journal_window.gd, group quest_journal), ChestWindow (chest_window.gd, group chest_window)   <- added by main
      MenuWindows (menu_windows.gd, group menu_windows)  <- the menu key; makes InventoryScreen, CraftingScreen, MenuTabs under Root
  InventoryActions (inventory_actions.gd, group inventory_actions)  <- belt, consumables and craft glue; made once
      DialogueBox (dialogue_box.tscn), QuestOfferWindow (quest_offer_window.tscn)   <- mounted by Quests
  Quests (quest_service.gd, group quests)   QuestMarkers (npc_quest_markers.gd, z 1)   QuestWaypoint (quest_waypoint_view.gd, z 2)   <- made once, kept across worlds
GameFeel children: FloatingTextLayer (CanvasLayer 8), ParticleFx (Node2D, high z)
MusicDirector children: WorldMusic (the world's MusicPlayer, moved here), BossMusic (audio.global), FadingMusic
Shell children: ShellLayer (CanvasLayer 50) > Root > AreaTitleCard, PauseMenu, GameOver, SettingsMenu, CreditsMenu, ControlsMenu, EndCard, Fade
```

Design rules:
- **Scene scripts** live in `game/scripts/` and only there. A file there is a scene-script id (`game.<kebab>` → `<snake>.gd`), attached to the scenes in `game/scenes/` that use it (the converter attached them and wrote exactly the `@export`s each declared; since Phase 1 a new export gets its values in the editor). Do not add or remove files in `game/scripts/` without the architect or integrator.
- **Inheritance between scene scripts only where Phaser has it, or for a new enemy.** The converter merged the `@export`s along a script's `extends` chain, so a port may extend another scene script exactly when the Phaser script does: `fatty.gd` extends `enemy.gd` (FattyScript extends EnemyScript) and overrides its hooks (`_after_enemy_step`, `_attack_area_reach`, `_can_run_common_attack`, ...). An enemy made in Godot extends `enemy.gd` the same way (`clod_stomper.gd`, 2026-10-09). There is still no `character.gd`: shared character maths lives in static helpers (`shared/feet_anchor.gd`, `shared/directions.gd`).
- **Static helpers** are `extends RefCounted` files with static funcs: perimeter, directions, feet anchor, resolver, scaling, AI, wander policy, aim and bounds. Small stateful helpers are RefCounted instances: input buffer, squash, territory, attack lifecycle, combo and activations.
- **Autoloads are reached only through `res://game/shared/services.gd`**, as `Services.router()`, `Services.world()`, `Services.feel()`, `Services.constants()`, `Services.clock()`, `Services.run()`, `Services.music()`, `Services.shell()` and `Services.now_ms()`. This was verified on 4.7.2: the headless `--check-only -s` does **not** know autoload names, so a bare `DamageRouter.route(...)` fails the check with "Identifier not found". The getters are typed, so calls are still statically checked.
- **Cross-file types**: `const X := preload("res://...")`, where X equals the file's `class_name`. Autoload scripts have no `class_name`, because a class_name equal to an autoload name is an error. Preload cycles (`player.gd` ↔ `player_combat.gd`, `services.gd` ↔ the autoloads) were tested and are fine.

## 2. Autoloads (API summary; full docs in the files)

| Autoload | Key API | Process mode |
|---|---|---|
| `GameConstants` | `value(path, fallback)`, `number(path)`, `integer(path)`, `dictionary(path)`, `data_file(name)`. Paths are the JSON's camelCase dotted paths (`character.player.movement.baseSpeed`). A missing path is a push_error, never a balance fallback | default |
| `SimClock` | `now_ms`, `step_count`, `last_step_ms`, `reset()`. Ticks first in every physics step | PAUSABLE, physics priority -1000 |
| `WorldService` | `scene_path`, `instantiate_scene`, `spawn_at_phaser_position(scene_id, phaser_point, parent=null)`, `register_world`, `entities_root`, `dimensions`, `world_rect`, `map_id`, `camera_mode`, `areas(kind)`, `safe_zones`, `npc_wander_area(instance_id)`, `is_solid_tile`, `is_bridged`, `player_spawn_marker`, `player_spawn_point`, `find_spawn_point`, `register_player`, `primary_target`, `line_of_sight(from,to,exclude)`, `register_camera`, `set_pause_reason(reason, active)`, `has_pause_reason`, `clear`. Vars: `world_root`, `definition`, `ground_layer`, `elevation` (cliffs and levels: `level_at`, `is_walkable`, `level_of`, `track`; null without an elevation layer), `player`, `player_body`, `camera`. Signals `world_registered`, `player_registered` | default |
| `DamageRouter` | `register_area(area, receiver, rule, tags=[])`, `unregister_area`, `receiver_for_area`, `tags_for_area`, `begin_activation(source, areas) -> int`, `end_activation`, `is_activation_active`, `route(request) -> result`. Signal `routed` | default |
| `GameFeel` | `play(event)`, `shake(ms, intensity)`, `hit_stop(ms)`, `is_frozen()`, `floating_text(world_pos, text, color_name, big, duration_ms=-1)`, `particles(preset, world_pos)`, `audio_cue(cue, payload)` | ALWAYS |
| `RunState` | Phaser's `GameSaveData` in one place (snake_case): vars `player`, `inventory`, `world`, `story`, `location`, `quests`; `new_run()` (sets `start_kit_pending`; `start_weapon_id` is a dev / test start weapon), `ensure_started()`, `max_hp()` (Goo Hearts and bosses' full hearts), `max_energy()` (with the bosses' raises), `add_goo_heart`/`add_full_heart`/`add_max_energy`, `capture_player(map_id, snapshot)`; coins (`add_coins`, `spend_coins`); the bag (`item_count`, `item_capacity`, `add_item` all or nothing, `remove_item`, `transact_items`, `remove_from_slot`, `slots`, `collect_world_item`, `unlock_gate`); the belt (`weapon_slots`, `set_weapon_slots`, `equipped_weapon_id`, `set_equipped_weapon`); story (`has_flag`/`set_flag`, `learn_ability`, `knows_recipe`/`learn_recipes` and the dev flag `debug_all_recipes_known`, `record_talk`/`has_talked_to`); quests (`quest_status`, `is_quest_active`, `notify_quests_changed`); `map_record(map_id)` (resources, collectibles, inventory drops, placed furniture, chests, gates, object_states, ...), `placed_furniture`/`place_furniture`/`remove_placed_furniture`, `inventory_drops`/`create_inventory_drop`/`set_inventory_drop_amount`, `object_state`/`set_object_state`, `respawn_point`, `request_navigation`/`consume_navigation`; saves (`save_slot`, `load_slot`, `read_slot`, `list_saves`, `delete_slot`, the recovery autosave in slot 0, `serialize`/`install`). Signals for every change (`inventory_changed`, `coins_changed`, `story_flag_changed`, `ability_learned`, `weapon_loadout_changed`, `weapon_equipped`, `recipes_learned`, `recipe_crafted`, `craft_failed`, `quests_changed`, `world_progress_changed`, `saved`, `loaded`); each schedules the autosave. Outlives worlds | ALWAYS |
| `MusicDirector` (after `RunState`) | `set_boss_fight(active, camp_id)`, `fade_out(ms)`, `set_menu_paused(paused)`, `advance(ms)`, `world_gain/boss_gain/duck()`, `world_track/boss_track()`, vars `audio_unlocked`, `play_arrival_cue`; static `apply_mix(master, effects, music, muted)`, `set_bus_volume_linear(bus, v)` for the shell. Claims the world's music-bus player on `world_registered` and listens to the `boss_camp` group ([specs/audio.md](specs/audio.md)) | ALWAYS |
| `Shell` (after `MusicDirector`) | `get_settings()` (GameSettings: `values()`, `update(change)`, `reset()`, `shake_scale()`, ... in user://settings.cfg), `open_pause()`, `can_open_pause()`, `open_settings/controls/credits()`, `handle_escape()`, `is_any_open()`, `show_area_title(text, colour)`, `show_defeat(info)`, `quit_to_title()`, `set_action(id, callable)` / `run_action(id)` for the windows other features own (`journal`, `inventory`, `map`, `save`, `load`, `wake`). Each open window holds the pause reason `shell:<surface id>`. Listens to `world_registered` (area card while a `world_main` node exists), `story_flag_changed` (end cards), `player_registered` ([specs/shell.md](specs/shell.md)) | ALWAYS |

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

**Area records** (`WorldService.areas(kind)`): `{id, kind, data (raw JSON, camelCase), perimeter}`, plus `stay_perimeter` for `enemy-spawn` (the playground and the dev worlds only) and `enemy-wander` (a camp's wander area that placed enemies name; its stay perimeter is its perimeter). Perimeters are `{"shape":"rectangle",x,y,w,h}` / `{"shape":"circle",x,y,radius}` (`shared/perimeter.gd`, complete). `safe_zones()` returns the rectangle perimeters.

**Primary target**: `{player, body, centre, hurtbox, active, hostile}`, or `{}`.

## 6. Scene scripts: export / signal / handler contract (checked against the scene JSON)

| Script id → file | Exports (snake_case of the JSON keys the scenes set; *italic* = extra, not in JSON) | Signals (1 Dictionary arg) | Handlers |
|---|---|---|---|
| `game.player` → `scripts/player.gd` | `body, visual, animation, damage_area, player_name`; *`dodge_learned`=true, `aim_rise_px`=28* | `health_changed, damaged, defeated, damage_feedback`; *`respawned`* | `on_pickup_area_entered(area)` (asks the pile's CollectibleScript) |
| `game.enemy` → `scripts/enemy.gd` (worm swordsman, archer, brawler, slime spider, orb weaver, prologue worm) | `body, visual, animation, damage_area, attack_area, faction, rank, max_health, targeting_radius, attack_range, movement_speed, attack_cooldown_ms, attributes, damage_rule, rewards, projectile, impact_effect`; *`display_name, arena_recovery_ms`* | `health_changed, damaged, defeated, alerted, attack_started, reward_requested, damage_feedback` | — |
| `game.weapon` → `scripts/weapon.gd` (13 weapon scenes) | `weapon_id, category, attack_area, animation, base_damage, cooldown_ms, knock_strength, damage_modifiers, harvest_capabilities, scaling, on_hit_effect_id, attack_plans` | `attack_started, attack_finished` | `on_area_entered(area)` |
| `game.effect` → `scripts/effect.gd` (all 9 `effects/*` scenes) | `effect_id, animation, lifetime_ms` | `finished` | — |
| `game.npc` → `scripts/npc.gd` (7 NPCs; Tom since 2026-10-09, idling in place) | `body, visual, animation, character_id, npc_definition_id, wander_speed, pause_min_ms, pause_max_ms` | `interaction_lock_changed` | — (`get_phaser_position()`, `get_instance_id_key()`, `acquire_interaction_lock()`: a conversation holds the NPC still until its release runs; the quest service reads `npc_definition_id`) |
| `game.world-definition` → `scripts/world_definition.gd` | `map_id, tile_size, columns, rows, metadata, camera_mode` | — | — |
| `game.world-area` → `scripts/world_area.gd` | `area_kind, area_id, area, data, shape, stay_shape` | — | — |
| `game.world-exit` → `scripts/world_exit.gd` | `map_id, exit_id, target_area_id, entry, entry_marker, area, gate`; *`arrival_grace_ms`=-1* | `navigation_resolved` | `on_body_entered(body)` |
| `game.fatty` → `scripts/fatty.gd` (extends `enemy.gd`; `character.fatty-one-eye`) | the `game.enemy` exports + `contact_attack, landing_zone, contact_hop_cooldown_ms, contact_hop_duration_ms, leap_cadence_ms, small_hop_count, small_hop_duration_ms, between_hops_ms, air_time_ms, recovery_ms, landing_damage, landing_knockback_strength, landing_effect_id, landing_shake_ms, landing_shake_intensity` | the enemy signals + `phase_changed` | — |
| `game.boss-camp` → `scripts/boss_camp.gd` (`encounter.fatty-lair-boss`, `encounter.gloop-matron-nest`, `encounter.weaver-hollow-matron`; `encounter.level-1-fatty-camp`, the old overworld camp, is the camp tests' fixture since 2026-10-17) | `map_id, camp_id, boss_id, boss_scene, activation_area, arena_area, active_bosses, guarded_chest, guarded_chest_instance_id, respawn_ms` (below 0: never returns), `spawn`, `boss_overrides` | `boss_spawn_requested, boss_defeated, guard_changed`; *`boss_engaged, boss_disengaged`* | — |
| `game.matron` → `scripts/matron.gd` (extends `enemy.gd`; `character.orb-weaver-matron`, node `EnemyScript`) | the `game.enemy` exports + `first_volley_delay_ms, volley_cadence_ms, volley_telegraph_ms, volley_rest_ms, volley_points, volley_spread, volley_radius, volley_damage, volley_knockback_strength, patch_effect_id` | the enemy signals + `phase_changed` | — |
| `game.clod-stomper` → `scripts/clod_stomper.gd` (extends `enemy.gd`; `character.clod-stomper`, 2026-10-09) | the `game.enemy` exports + `slam_zone, crouch_ms, air_ms, hop_px, recovery_ms, stomp_cooldown_ms, slam_damage, slam_knockback, crack_radius, landing_effect_id, landing_shake_ms, landing_shake_intensity` | the enemy signals + `phase_changed` | — (crouch, hop, slam in its ring, dazed; the slam breaks cracked ground near its feet) |
| `game.popworm`, `game.spitcap`, `game.hopper`, `game.bramble-boar`, `game.thorn-guard`, `game.rook-thief` → `scripts/popworm.gd`, `spitcap.gd`, `hopper.gd`, `bramble_boar.gd`, `thorn_guard.gd`, `rook_thief.gd` (extend `game/enemy/patterned_enemy.gd`, which extends `enemy.gd`; the bestiary's rows 5 to 10, 2026-10-16) | the `game.enemy` exports + `pose`, `defeated_frame` (the Thorn Guard: `guard_group`); their pattern numbers are their type's `pattern` block in `enemy-types.json` | the enemy signals + `phase_changed` | the Popworm `on_ground_shake(at, radius, heavy)`, the Rook Thief `on_arrow_hit(hit)` ([BESTIARY.md](BESTIARY.md)) |
| `game.squint` (also `character.big-squint`), `game.pipe-worm`, `game.dung-roller` → `scripts/squint.gd`, `pipe_worm.gd`, `dung_roller.gd` (extend `game/enemy/patterned_enemy.gd`; the bestiary's rows 11 to 14, Fatty's Lair, 2026-10-16); `game.mud-glob` → `scripts/mud_glob.gd` (extends `spore_seed.gd`, `projectile.mud-glob`) | the `game.enemy` exports + `pose`, `defeated_frame`; the Pipe Worm `aim_direction`, `hole`, `glint`; the Dung Roller `track` (points from its post), `beetle`, `beetle_shape`, `beetle_hurt_shape`, `ball_look`; their numbers are their type's `pattern` block in `enemy-types.json` | the enemy signals + `phase_changed` | the Pipe Worm `on_ground_shake(at, radius, heavy)` ([BESTIARY.md](BESTIARY.md)) |
| `game.silk-lurker`, `game.thornball`, `game.egg-sac`, `game.broodling`, `game.cocoon-mimic`, `game.brood-warden` → `scripts/silk_lurker.gd`, `thornball.gd`, `egg_sac.gd`, `broodling.gd`, `cocoon_mimic.gd`, `brood_warden.gd` (extend `game/enemy/patterned_enemy.gd`; the bestiary's rows 18 to 22, Chapter 2, 2026-10-16) | the `game.enemy` exports + `pose`, `defeated_frame`; their numbers are their type's `pattern` block in `enemy-types.json` | the enemy signals + `phase_changed` | the Silk Lurker `on_arrow_hit(hit)`; the egg sac spawns `character.broodling` with its arena ([BESTIARY.md](BESTIARY.md)) |
| `game.projectile` → `scripts/projectile.gd` (`projectile.worm-arrow`, `projectile.spider-web`) | `projectile_id, body, visual, animation, attack_area, default_speed, lifetime_ms, rotate_to_velocity` | `launched, expired` | `on_area_entered(area)` (`launch(direction, speed, payload)`, `expire()`) |
| `game.spore-seed` → `scripts/spore_seed.gd` (extends `projectile.gd`; `projectile.spore-seed`, 2026-10-16) | the `game.projectile` exports | `launched, expired` | the mouth's suckable contract: `origin()`, `can_take()`, `suck_info()`, `take()` ([BESTIARY.md](BESTIARY.md#hooks-for-the-powers)) |
| `game.web-patch` → `scripts/web_patch.gd` (`effect.matron-web-patch`) | `radius, visual` | `caught, torn` | — |
| `game.spider-web` → `scripts/spider_web.gd` (`object.spider-web`) | `width, depth, tears_when_crossed, visual` | `caught, torn` | — |

| `game.resource-node` → `scripts/resource_node.gd` (49 scenes: trees, stone, iron, amber ore; world-objects spec) | the `game.destructible` keys `map_id, instance_id, object_id, damage_area, max_health, initial_health, tags, damage_rule` + `drop, idle_animation_id, hit_effect_id, on_hit_animation_id, persist_health`=true, `depletion_message, harvest_requirement, animation` | `health_changed, damaged, damage_feedback, destroyed, resource_hit, harvest_blocked, drops_requested` | — (damage receiver API) |
| `game.collectible` → `scripts/collectible.gd` (16 scenes; spawned piles too) | `map_id, instance_id, object_id, item_id, quantity, source_resource_instance_id, source_inventory_drop_id, pickup_area` | `pickup_resolved, depleted` | — (`request_pickup(collector)`) |
| `game.story-flag` → `scripts/story_flag.gd` | `flag_id` | — | `on_set(payload)` (JSON handler `set`) |
| `game.story-variant` → `scripts/story_variant.gd` | `flag_id, when_set, when_unset` | `switched` | `on_set(payload)` |

| `game.door` → `scripts/door.gd` (10 doors; interaction spec §3.2; pushed into, no interact key) | `map_id, door_id, target_area_id, target_door_id, target_marker, kind, side, trigger_rect, walk_area, arrival_step, use_cue, house_art, door_rect, door_arch, hinge, double_leaf, leaf_art_path, open_cue, close_cue, fall_cue, gate` | — | — (`use()`, `arrival_point()`, `on_arrival()`, `lead_ms()`, group `door`) |
| `game.gate` → `scripts/gate.gd` (pushed open with the key, no interact key; `prompt`, `locked_prompt`, `interact_radius` unused) | `map_id, gate_id, required_item_id, consume_on_unlock, prompt, locked_prompt, locked_message, unlocked_message, interact_radius, badge_rise, closed_frame, open_frame, visual, doors` | `opened`, `closed`, `message_shown` | `open(payload)` (plates; not saved), `open_for_good(payload)` (bells, 2026-10-16: records the unlock in RunState, so the gate stays open) |
| `game.chest` → `scripts/chest.gd` | `map_id, instance_id, initial_contents` | `guard_blocked, open_requested, stack_transferred, closed` | — |
| `game.bed` → `scripts/bed.gd` | `prompt, interact_radius, badge_rise, sleep_point, wake_point` | — | — (`sleep_request()`) |
| `game.workbench` → `scripts/workbench.gd` | `prompt, recipe_context, tier, interact_radius, badge_rise` | — | — (`site()`) |

| `game.training-dummy` → `scripts/training_dummy.gd` (abilities spec) | `damage_area, visual` | `hit` | — (damage receiver API) |
| `game.essence` → `scripts/essence.gd` | `essence, fade_ms, interact_radius` | — | — (`origin()`, `suck_info()`, `can_take()`, `take()`, `pick_up()`; Q sucks it in, the interaction controller offers "Pick up"; `spawn()` drops one) |
| `game.liftable` → `scripts/liftable.gd` (`object.liftable`, `scenes/objects/liftable.tscn`: one scene for the 67 kinds of the catalog `game/data/liftables.json`; `object.liftable-rock`, `-puffball`, `-pinecone` preset the kind) | `kind, variant, heavy` | — | — (`origin()`, `suck_info()`, `can_take()`, `take()`; static `catalog()`, `kinds()`, `entry()`, `frames_of()`, `frame_of()`, `material_of()`, `display_name()`, `art_size()`; Q sucks it in; on `_ready` the Visual's frame and the body's footprint (70 % of the art's width × 12 px) follow `kind`; `variant` -1 picks one of two looks from the position for the kinds that have two) |
| `game.pressure-plate` → `scripts/pressure_plate.gd` | `plate_id, radius, sink_px, pressed_frame, gate_id, latch, visual` | `pressed, released` | — (`is_down()`; pressed by a heavy slime) |
| `game.cracked-ground` → `scripts/cracked_ground.gd` | `flag_id, radius, requires_impact` | `cracked` | — (`is_broken()`, `break_open()`, `receive_blast(hit)`, groups `cracked_ground` and `blast_targets`; a Goo Bomb blast, a Squash Slam (or a jump landing) in the Stone form, or a Clod Stomper's slam; `object.cracked-floor`'s root `cracked_floor.gd` sets it up with a one-way `fall` hole) |
| `game.lash-bell` → `scripts/lash_bell.gd` | `bell_id, gate_id, damage_area, visual` | `rung` | — (`ring()`, `on_arrow_hit(hit)` (group `bow_targets`), static `rings_to(request)`, damage receiver API: only a hit tagged `thrown` rings it, never the Spear or the Lash, 2026-10-16; its post is a Lash anchor, group `lash-bell`) |
| `game.barred-gate` → `scripts/barred_gate.gd` (`object.barred-gate`, 2026-10-16) | `map_id, gate_id, refusal_text, rise_ms, bars, bars_area, grate` | `opened`, `refused` | — (`open()`, `open_now()`, `is_open()`, `refuse()`, `record_map_id()`, static `is_spear(request)`; the bars' damage receiver: the Spear passes, anything else clinks; its `Lever` child, `game/world_objects/barred_gate_lever.gd`, takes only the Spear; [PROLOGUE.md](PROLOGUE.md#the-barred-gate)) |
| `game.ability-lesson` → `scripts/ability_lesson.gd` | `ability_ids, radius` | `taught` | — |
| `game.goo-heart` → `scripts/goo_heart.gd` | `heart_id, radius, bob_px, visual, hearts` (Goo Hearts it grants, 1-4: Fatty's boss heart is worth 2) | `collected` | — (`is_taken()`) |
| `game.restoration-site` → `scripts/restoration_site.gd` | `prompt, flag_id, object_id, quest_id, cost, locked_message, restored_message, interact_radius, badge_rise` | — | — (`origin()`, `cost_entries()`, `restore()`, `persistence_key()`; a restore sends `QuestEvents` `object.activated`) |
| `game.tom-web` → `scripts/tom_web.gd` (`object.tom-web`, 2026-10-09) | `damage_area, visual, hits_to_tear, quest_id, freed_flag, object_id` | `torn` | — (damage receiver API: weapon hits tear it while its quest is active, then flag `tom-freed` and `QuestEvents` `object.activated`; group `quest_object` for the quest arrow) |

`game.destructible` has no scenes: its logic is `game/world_objects/destructible_health.gd`, owned by `resource_node.gd` (which declares the destructible exports itself). `game.interaction` has no scenes and no service behind it in Phaser, so it is not ported. No scene is left on the converter's placeholder `unported_script.gd`, which was removed in clean-out wave 1 (2026-10-17).

Enemies fire projectiles through `game/enemy/enemy_projectiles.gd` (Phaser's world `spawnEnemyProjectile`): the projectile goes under the world root and hits only the player's hurtbox ([specs/enemy.md](specs/enemy.md) §12). Webs (`spider_web.gd`, `web_patch.gd`) reach the player through `game/enemy/spider_web_port.gd`, which calls player.gd's `crosses_webs()` and `teleport(centre)` and duck-types `apply_web(ms)` (a stop-and-suppress fallback until it exists) ([specs/matron.md](specs/matron.md) §5).

Boss camps ([specs/boss.md](specs/boss.md)) spawn their boss under the world root when the player centre enters the activation circle, hand it the arena (`EnemyScript.configure_arena`), keep their respawn timer and the defeated boss ids in RunState (`map_record(map_id)["boss_camps"]`, `world["defeated_boss_ids"]`), reset the fight when the player's `defeated` fires, and join the group `boss_camp`; the HUD's `BossHealthBar` binds itself to every camp in that group, and a later quest system listens to `boss_defeated` there.

## 7. Bootstrap (main.gd `_ready`, world spec 1.2)

1. `apply_viewport_scale()`: keep `root.content_scale_size` at the base size 1024 × 1024 (the 16 × 14 tile play area and the HUD console's 128-unit strip), and re-apply on `size_changed`; `setup_camera()` gives the WorldCamera the console's height as `bottom_inset`.
2. `RunState.ensure_started()`; the map is the pending travel handoff's (`RunState.consume_navigation()`), else `resolve_map_id()` (`"level-1"`). Steps 3-11 are `_build_world(map_id, handoff)`, which `travel_to` runs again for the next world.
3. `load_world()`: instance `world.level-1` under `$World`, then `WorldService.register_world(root)`.
4. `WorldBounds.build(world_root, world_rect)`.
5. `spawn_player(handoff)`: `spawn_at_phaser_position("character.player-slime", WorldService.player_spawn_point(), world_root)` (after a travel: `AreaTravel.arrival_point(handoff)`), then `register_player(PlayerScript node)` and `restore_run_state(RunState.player)` (HP). The feet land at (640, 731.56).
6. `equip_run_start()`: `PlayerCombat.new()` → child "PlayerCombat" of the player root → `setup(player)` → `player.set_combat(combat)`; a new run (`RunState.start_kit_pending`) starts empty-handed as in Phaser, unless the `weapon` launch option or `RunState.start_weapon_id` (the test runner sets "basic-sword") names a weapon, which `InventoryActions.grant_start_weapon` puts in the bag, on belt slot 1 and in hand; the playground gets every weapon (`grant_playground_weapons`) and, unless the test runner turns `playground_abilities` off, every ability learned quietly plus 10 of each Gulp material (`grant_playground_abilities`); then `InventoryActions.equip_run_weapon()`: `WeaponLoadout.reconcile()` and `PlayerCombat.equip(RunState.equipped_weapon_id())` (nothing for an empty hand). Travel and loads keep the hand.
7. `start_enemy_population()`: `EnemyPopulation.new()` → `setup(areas("enemy-spawn"), safe_zones(), entities_root())` (it finds the world's placed enemies and `enemy-wander` areas itself), `allowed_types` empty (every type the world's camps name; the trial allowed only `worm-swordsman`), `seed_initial()`: every placed enemy stands at once, once per build, so a beaten one is back only when the world is built again (roadmap 5.25, [specs/enemy.md](specs/enemy.md) §3.3); spawn areas (the playground, the dev worlds) seed and refill on their timers.
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

1. The starter camp's three worms stand from the moment the chunk is built: `EnemyPopulation.seed_initial` spawns each placed worm (`character.worm-swordsman`, its root on its node), then `configure_navigation(the camp's enemy-wander record, safe_zones)`. (A playground pen instead spawns while the player centre is inside its pursue rect, once `now > last + intervalMs` and fewer than `maxPopulation` are alive, at a stay-rect point outside the safe zones.)
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
| `game/world/world_camera.gd` | world | Also camera rooms (keeps to the `CameraRoom` the target stands in, slides between them, `fit_to_view`) and a scene's hold (`pan_to(point, ms, false)`, `set_zoom_level`) |
| `game/world/camera_room.gd` | world | `CameraRoom`: a rect of a world the camera keeps to while the slime is in it ([PROLOGUE.md](PROLOGUE.md#camera-rooms)) |
| `game/world/world_bounds.gd` | world | |
| `game/world/water_surface.gd`, `water_surface.gdshader`, `water_surface.gdshaderinc` | world | Animated water over the ground's water tiles ([specs/water.md](specs/water.md)); mounted by `WorldService.register_world`; the `.gdshaderinc` holds the water maths the shoreline edges share |
| `game/world/terrain_edges/terrain_edges.gd`, `terrain_materials.gd`, `terrain_edge.gdshader`, `terrain_edge_water.gdshader`, `art/` | world | Hand-made terrain edges on a dual grid over the ground, shores included ([TERRAIN_LAB.md](TERRAIN_LAB.md)); mounted by `WorldService.register_world` after the water |
| `game/world/ground_surface.gd`, `ground_surface.gdshader` | world | The ground at 128 px per cell where a ground has a 128 px sheet, drawn in world space over the ground tiles; mounted first by `WorldService.register_world` ([TERRAIN_LAB.md](TERRAIN_LAB.md#ground-at-128-px)) |
| `game/world/world_ground.gd` | world | The script on every world's `ground` layer (`@tool`): in the editor it mounts the water surface and the terrain edges, so a world looks as it does in the game; does nothing in the game ([TERRAIN_LAB.md](TERRAIN_LAB.md#how-it-works)) |
| `game/world/elevation/elevation.gd`, `elevation_grid.gd`, `elevation_stairs.gd`, `elevation_rims.gd`, `elevation_occlusion.gd`, `elevation_mesh.gd`, `elevation_layer.gd`, `elevation_tileset.tres`, `cliffs/`, `*.gdshader`, `art/` | world | Hills, holes, flights of stairs and ground levels from a world's painted `elevation` layer: the model and its 3D ground, the cliff and stairs drawing (each wall in the style painted on the `cliffs` layer or its ground's), cast shadows, per-level collision, body levels and hiding bodies behind higher ground; mounted by `WorldService.register_world` after the terrain edges ([ELEVATION.md](ELEVATION.md)) |
| `game/world/atlas/world_map_data.gd`, `world_atlas.gd`, `atlas_region.gd`, `atlas_world_survey.gd`, `map_note.gd`; `game/data/world-map.json`; `game/dev/world_atlas.tscn` | world | The world layout (regions on the 8 × 8 chunk grid, their worlds, openings), the editor atlas that shows every world on it and moves regions, MapNotes (sketch markers in placeholder worlds, editor only) ([WORLD_ATLAS.md](WORLD_ATLAS.md)) |
| `game/world/atlas/world_chunks.gd`; `game/data/world-chunks.json`; `game/scenes/worlds/chunks/` | world | Regions cut into chunk worlds (`tools/split_region_chunks.gd`): travel into a cut region goes to the chunk that holds the arrival marker; a chunk knows its region for the map ([WORLD_ATLAS.md](WORLD_ATLAS.md#chunk-worlds-a-test-2026-10-12)) |
| `game/world/forest/forest_layer.gd`, `big_trees.gd`, `forest_tileset.tres`, `tree_sway.gdshader` | world | Tree walls painted on a `ForestLayer`: the region sets' big trees, thinned with every wall gap filled, ground shade, canopy sway, trunk-line collision, "Absorb trees" for placed wall trees ([FORESTS.md](FORESTS.md)) |
| `game/world/webs/web_layer.gd`, `floor_webs.gd`, `web_tileset.tres` | world | Floor webs painted on a `webs` WebLayer (six flat webs, auto-picked per cell) and the webs' rule every floor web shares (FloorWebs: a walk halved and a Roll stuck without the Silk skin, `crosses_webs()`; the web walls' half-speed pass with it), read by player.gd's walk ([WEBS.md](WEBS.md)) |
| `game/world/walls/wall_layer.gd`, `wall_piece.gd`, `wall_tileset.tres` | world | Built walls painted on a `walls` WallLayer: each cell's shape from its painted neighbours, drawn from its style's sheet (16 shapes, 4 pattern parities), each shape's footprint solid; `WallPiece` shows one piece in the kept `wall-stone-solid` scenes ([WALLS.md](WALLS.md)) |
| `game/world/props/prop_layer.gd`, `props_cell_tileset.tres`, `props_detail_tileset.tres`, `walls_tileset.tres`, `props_tileset.tres`, `prop_palettes.json` | world | Scenery painted from a palette on PropLayers: `cell-props` (64 grid) and `details` (32), each prop a block of whole cells; `old-props` (8) for free placement (and what was painted before); the older `large-props` (64). Each painted cell instances its scene at the tile's anchor, size and mirror ([PROPS.md](PROPS.md)) |
| `game/world/water_wake.gd` | world | Splash and ripple sprites at the feet of every walker in shallow or deep water ([specs/water.md](specs/water.md#9-wading-godot-only)); mounted by `WorldService.register_world` after the elevation |
| `game/world/npc_wander_policy.gd` | world | |
| `game/scripts/world_definition.gd` | world | |
| `game/scripts/world_area.gd` | world | |
| `game/scripts/world_exit.gd` | world objects | Level-triggered after the arrival grace; asks `Main.request_exit` |
| `game/autoload/run_state.gd` | world objects | Autoload `RunState`; `saving_blocked_reason()` / `can_save()` refuse every save while the prologue runs and inside a dungeon (there a quit or a closed window writes the dungeon's resume save instead: [DUNGEONS.md](DUNGEONS.md#dungeon-state-no-saving-resume-at-the-entrance)) |
| `game/scripts/resource_node.gd`, `game/scripts/collectible.gd` | world objects | Spec world-objects.md |
| `game/scripts/story_flag.gd`, `game/scripts/story_variant.gd` | world objects | Flags in `RunState.story` |
| `game/world_objects/item_catalog.gd` | world objects | items.json + max stacks; weapons are items (names, icons, descriptions from `weapons.json`) |
| `game/crafting/recipe_catalog.gd`, `crafting_service.gd` | crafting | Recipes (`recipes.json`), stations and site lists; quotes, the status order and crafts on `RunState.transact_items` ([specs/crafting.md](specs/crafting.md) §1-2) |
| `game/inventory/weapon_catalog.gd`, `item_icons.gd` | crafting | Weapon names, descriptions, icons, stats (`weapons.json`); item icons as atlas frames (`item-icons.json`) |
| `game/inventory/inventory_drops.gd` | crafting | Dropping bag items on the ground: placement, records, pile launch (restore is `EnemyLoot.restore_world`) |
| `game/inventory/inventory_actions.gd` | crafting | Child "InventoryActions" of main (group `inventory_actions`): the belt glue (switch, equip, assign, hold), consumables, after-craft, harvest advice, the trial grant and `equip_run_weapon` |
| `game/player/weapon_loadout.gd`, `wheel_stepper.gd` | crafting | Belt rules on RunState (owned, assign, cycle, equip, reconcile, grant); mouse-wheel notches to single steps |
| `game/ui/screens/menu_windows.gd` | crafting | GameWindows' child "MenuWindows" (group `menu_windows`): the menu key, `open_bag` / `open_crafting` / `open_station`, the tab strip state and coach, `register_tab` for the journal and map windows, the pause menu's Inventory action |
| `game/ui/screens/game_window.gd`, `item_cell.gd` | crafting | Base of the bag and crafting windows (centred `WindowPanel`, push / pop, focus, click and select cues); the `SlotButton` list cell (icon, name, tag; drag and drop) |
| `game/ui/screens/inventory_screen.gd`, `inventory_model.gd`, `crafting_screen.gd`, `crafting_model.gd`, `menu_tabs.gd` | crafting | The bag window, the crafting window (built in code, models with the exact texts) and the menu tab strip |
| `game/ui/weapon_hotbar.gd` | crafting | The weapon in hand on the HUD console and the weapon carousel, built by `hud.gd` |
| `game/ui/console/` | UI | The HUD console (roadmap 4.12): `hud_console.gd` (layout, orbs, menu buttons, form badge), `goo_orb.gd` + `goo_orb.gdshader` (an orb), `console_style.gd` (the slot frame and key badges) |
| `game/interaction/interaction_controller.gd` | interaction | Child "Interaction" of main, kept across worlds: targets (gates, doors, workbenches, beds, chests, NPCs), choice, execute; NPC candidates and conversations come from the quest service; a chest opens the chest window |
| `game/interaction/interaction_prompt.gd`, `interaction_badge.gd` | interaction | "Right-click: <prompt>" (CanvasLayer 9) and the key badge (world, z 1) |
| `game/rest/sleep_controller.gd` | interaction | Sleeping in a bed, owned by player.gd |
| `game/scripts/door.gd`, `gate.gd`, `chest.gd`, `bed.gd`, `workbench.gd` | interaction | Spec interaction.md |
| `game/world_objects/destructible_health.gd` | world objects | HP, records, regrow timer (the `game.destructible` logic) |
| `game/world_objects/resource_respawn.gd` | world objects | Regrow rule on the wall clock (`epoch_override_ms` for tests) |
| `game/world_objects/resource_drops.gd` | world objects | Drop cells, scatter, pile launch, restore, pile bookkeeping |
| `game/world/area_travel.gd` | world objects | Arrival point (door, named marker, entry edge, spawn), travel fades, music fade-out (only ambience once `MusicDirector` holds the music); `Main.travel_to` / `request_exit` drive it |
| `game/world/chunk_scroll.gd` | world builder | The Zelda screen scroll between two chunks of a region (picture of the old view, camera slide, the slime walking in); `Main._scroll_travel` drives it |
| `game/scripts/npc.gd` | world | |
| `game/ui/hud.gd` | world | The HUD: the coin chip, the console and the pieces it places on it (weapon slot, ability bar, minimap) |
| `game/ui/hud_bar.gd` | world | One labelled HUD bar drawn from its theme variation (`HudBar`, `BossBar`) |
| `game/ui/player_health_bar.gd` | world | Styled by `FloatingHealthBar` |
| `game/ui/fps_readout.gd` | world | Styled by `DebugPanel` / `DebugLabel` |
| `game/scripts/player.gd` | player | Plays every clip in its version for the facing (`_directional_clip`, `_flip_for`); energy, effects channel, statuses, Gulp forms and abilities hang off it |
| `game/player/abilities/ability_definitions.gd`, `player_abilities.gd` | abilities | Ability table, energy costs and cooldowns on the sim clock, the dispatch order ([specs/abilities.md](specs/abilities.md)) |
| `game/player/abilities/jump_sequence.gd`, `slam_sequence.gd`, `teleport_sequence.gd`, `lash_sequence.gd` | abilities | One sequence per ability (tween steps chained with `parallel()`) |
| `game/player/abilities/ability_terrain.gd`, `ability_world.gd`, `ability_fx.gd` | abilities | Landing and line checks against the world, strike areas, lash probes, the shared effects |
| `game/player/gulp/gulp_forms.gd`, `gulp_controller.gd`, `gulp_hud.gd` | abilities | Gulp forms (2026-10-08: swallowed essences, no timer): skin, speed, the pop on a hit, spitting out, and the "[Q] Suck" / "[Q] Throw" hints |
| `game/player/gulp/mouth.gd`, `thrown_object.gd`, `break_burst.gd`, `held_look.gd`, `suction_fx.gd` | abilities | The mouth: hold Q to suck in an essence or a liftable (one of the 67 kinds: a pot, a rock, a pumpkin, ...; the suck also sweeps in every walk-over pickup in reach, picked up as if walked over, 2026-10-19), hold it (drawn inside, on the belly), throw it (it strikes for `gulp.throwDamage` × its material's multiplier and breaks by its material: `break_burst.gd` bursts a liftable into 3 × 3 chunks of its own picture, with the material's particles and cue); an essence is never thrown: Q spits it out whole 44 px ahead, where it stays (owner, 2026-10-09); a full slime walks at `gulp.holdingSpeedMultiplier` (70%); a hit that knocks a liftable out breaks it at the feet; `held_look.gd` shows each as its frame of the liftables or essences sheet (2026-10-09; the first `game/world_objects/pot_art.gd` and its pot were removed); the suction streaks are still a placeholder. `tools/render_gulp_art.gd` renders the Gulp art on one sheet |
| `game/player/roll/player_roll.gd`, `roll_fx.gd` | abilities | The Roll (2026-10-09, the `dodge` ability on key 2, a Pegasus-boots dash): spin-up, a straight launch in one of eight directions, hold to keep rolling, the bonk (shake, hit-stop, wobble, a hit on an enemy) and the bounce back, its cooldown; the skid streaks and dust ([specs/player.md](specs/player.md) §5) |
| `game/player/skins/` (`skin_state.gd`, `skin_look.gd`, `feral_climb.gd`, `feral_claws.gd`); `game/scripts/climb_wall.gd`, `loose_prize.gd`, `rubble_heap.gd`, `plank_barricade.gd`; `game/dev/corners/skins_corner.*`, `skin_pedestal.gd` | skins | The Pearls' skins (roadmap 7.8, 2026-10-17): Heavy, Silk and Feral, always on once won and stacking (`SkinState.is_on`, the record in RunState), the looks that show while each works and the bag's everyday look, the Heavy Roll's breakables and loose prizes, the Feral climb and the Spear's double tempo, the playground's Skins corner ([SKINS.md](SKINS.md)) |
| `game/player/gulp/player_swimming.gd` | abilities | Swimming in a form that swims (the Frog): the `water` bit off the body's mask, swim clips, waterline and sunk art in deep water ([specs/abilities.md](specs/abilities.md#117-swimming-the-frog-form-godot-addition-owner-2026-10-06-in)) |
| `game/player/status_effects.gd` | player | Burn, poison, slow, sticky, bouncy, frenzy, and the web root (`apply_web`) |
| `game/player/goo_trail.gd` | abilities | The Goo Trail passive: smears under the slime that slow enemies |
| `game/building/furniture_placement.gd`, `placed_furniture.gd` | world objects | Child "FurniturePlacement" of main: placing furniture (ghost, free test, records, quest event), picking it up, mounting placed benches on every world build ([specs/furniture.md](specs/furniture.md)) |
| `game/ui/glyphs.gd` | UI | The text symbols of the UI, Phaser's ✓ ▸ ✕ ★ ◆ ▶ ○, in one place (drawn by Source Sans 3 and its Noto Sans Symbols 2 fallback; UI_THEME.md "Symbols") |
| `game/ui/npc_name_tags.gd` | world | Child "NpcNameTags" of main: a "NameTag" (display name, 14 px, outlined) on every NPC body with a definition, sorted with the NPC |
| `game/hints/control_hints.gd` | interaction | Child "ControlHints" of main (CanvasLayer 10): first-time control hints, learned by use as `hint.<id>` story flags; the prologue's own order while it runs (`PROLOGUE_HINT_IDS`) |
| `game/ui/ability_bar.gd` | abilities | The HUD's ability bar (bottom centre): labels from `player.ability_status`, clicks run `activate_ability_from_ui` |
| `game/scripts/training_dummy.gd`, `essence.gd`, `liftable.gd`, `pressure_plate.gd`, `cracked_ground.gd`, `cracked_floor.gd`, `winch_post.gd`, `blast_keg.gd`, `lash_bell.gd`, `ability_lesson.gd`, `goo_heart.gd`, `restoration_site.gd` | abilities | The abilities' puzzle pieces (§6; the Goo Bomb's: BODY_SHAPES.md "The Goo Bomb") |
| `game/saves/save_slots_menu.gd`, `.tscn` | saves | The save slots window (three slots and the autosave) on the Shell's stack; RunState mounts it and registers the Shell's `save` / `load` actions |
| `game/world_objects/enemy_loot.gd` | world objects | Child "EnemyLoot" of main: enemy coins, loot piles scattered round the corpse, their records and restore |
| `game/ui/screens/game_windows.gd` | UI | Child "GameWindows" of main (CanvasLayer 40): the game windows' parent, the one `modal` pause owner, Escape for the top window |
| `game/ui/screens/quest_journal_window.gd`, `quest_journal_model.gd` | quests (UI) | The quest journal "Quest Book" on GameWindows (group `quest_journal`, surface `quest-journal`): the menu's Journal tab and the pause menu's Journal action, abandon (in-window confirm) and retry ([specs/journal-and-chest.md](specs/journal-and-chest.md)) |
| `game/ui/screens/chest_window.gd`, `chest_model.gd` | interaction (UI) | The chest window on GameWindows (group `chest_window`, surface `chest-inventory`, silent): `chest.gd` opens it with `open_chest` and closes it with `close_for`; Take Stack, right click ([specs/journal-and-chest.md](specs/journal-and-chest.md)) |
| `game/ui/screens/window_style.gd` | UI | Corner radii and line heights for windows built in code (journal, chest) |
| `game/ui/map/map_ui.gd`, `minimap.gd`, `map_terrain.gd`, `map_markers.gd`, `world_map_window.gd`, `.tscn` | map | The HUD minimap (a small map of the world's ground, owner decision; `terrain_alpha = 0` = Phaser's see-through; markers, view) and the world map window on GameWindows (the regions of `game/data/world-map.json`: discovered, current, the player's dot, the openings); the `map` key, the pause menu's Map action and the marker API ([specs/map.md](specs/map.md)) |
| `game/quests/quest_events.gd` | quests | `QuestEvents.emit(event, payload)` for world scripts and features |
| `game/quests/quest_service.gd` | quests | Child "Quests" of main (group `quests`), kept across worlds: the quest state machine over `RunState.quests`, commands, queries, NPC candidates and markers, load validation, the `quest` launch option; mounts the dialogue box and the offer window in GameWindows ([specs/quests.md](specs/quests.md)) |
| `game/quests/quest_catalog.gd`, `quest_objectives.gd` | quests | The 15 definitions (`game/data/quests-chapter-*.json`), recipe and NPC lookups, reward and objective texts; the objective matchers |
| `game/quests/quest_npc_talk.gd`, `quest_notifications.gd`, `quest_waypoint.gd` | quests | NPC conversations (offer, turn-in, reoffer, plain talk); toasts, chapter and ability banners (an active ability plays the ceremony instead while main's `ability_ceremonies` is on, and so does a permanent item's first arrival, RunState `permanent_item_gained`), quest cues; the waypoint target resolver (also quest objects, group `quest_object`) |
| `game/ui/ceremony/ability_ceremony.gd`, `ceremony_stage.gd` | UI | The ceremony (2026-10-09, roadmap 4.13): a CanvasLayer (95) made once under the tree's root by `AbilityCeremony.request(tree, id)` (an ability), `request_item(tree, item_id)` (a weapon, tool or key the first time, from RunState `permanent_item_gained`; RunState keeps `story.celebrated_item_ids` and its `quiet_items` grants count without one) or `request_heart(tree, bonus, icon)` (`goo_heart.gd`). It pauses the world (reason `ceremony`), dims around the slime, raises a goo bubble with the thing's icon (an ability's HUD console `ability-<id>.webp`, an item's bag icon) with light rays and sparkles (`ceremony_stage.gd`), shows the card (kicker, name, line, how-to: `AbilityDefinitions.CEREMONY`, an item's description, key labels from `control_labels.gd`) and waits for a key; requests queue and wait while a window is open (reason `modal`). main's `ability_ceremonies` (default on; the test runner turns it off) lets `quest_notifications.gd` request it. `tools/render_ceremony.gd` renders it in the running playground for tuning ([specs/quests.md](specs/quests.md#43-ability-banner-and-audio)) |
| `game/scripts/tom_web.gd` | quests | The web Tom is caught in (2026-10-09, roadmap 8.13; quest `tom-in-the-web`): weapon hits tear it, then flag `tom-freed` |
| `game/ui/screens/dialogue_box.tscn/.gd`, `quest_offer_window.tscn/.gd` | quests | The NPC dialogue box and the quest offer / turn-in window (Godot-owned copies of `ui.npc-dialogue`, `ui.quest-offer-modal`) on GameWindows |
| `game/ui/quest_tracker.tscn/.gd`, `npc_quest_markers.gd`, `quest_waypoint_view.gd` | quests | The HUD quest tracker (copy of `ui.quest-tracker`), the "!"/"?" markers over NPCs (main's "QuestMarkers", z 1) and the gold waypoint (main's "QuestWaypoint", z 2) |
| `game/characters/player_slime.tscn` | player | Godot-owned player scene (CONVENTIONS "Scenes Godot owns"); clips rebuilt by `tools/build_player_clips.gd` |
| `game/dev/playground.tscn` | world | `main.tscn` with `map_id = "playground"`; run with F6 |
| `tools/build_region_worlds.gd`, `tools/region_worlds/`, `tools/render_world_atlas.gd` | world | Builds the placeholder region worlds from the layout; renders the atlas ([WORLD_ATLAS.md](WORLD_ATLAS.md)) |
| `game/player/player_input_buffer.gd` | player | |
| `game/player/pointer_aim.gd` | player | |
| `game/player/mouse/control_scheme.gd`, `key_bindings.gd`, `click_orders.gd`, `click_path.gd`, `pointer_targets.gd`, `click_marker.gd` | player | The control schemes (experiment): click / right-click to walk, attack or use, face the pointer, or keys only (InputMap rebound); shortest routes over every ground level (any-angle A* queried from physics: narrow gaps, stairs, drops); hover targets and ground rings ([MOUSE_CONTROLS.md](MOUSE_CONTROLS.md)) |
| `game/player/squash_stretch.gd` | player | |
| `game/scripts/enemy.gd` | enemy | |
| `game/enemy/enemy_ai.gd` | enemy | |
| `game/enemy/camp_territory.gd` | enemy | |
| `game/enemy/attack_lifecycle.gd` | enemy | |
| `game/enemy/enemy_population.gd` | enemy | Placed enemies once per world build; the playground's and dev worlds' camps and legacy `metadata.spawns`; `slow_enemies_near` ([specs/enemy.md](specs/enemy.md) §3.3, §18, §15) |
| `game/enemy/placed_enemy.gd`, `game/scenes/encounters/placed-enemy.tscn` | enemy | A world enemy placed by hand under `Enemies`: type, wander area (a shared `enemy-wander` area or its own circle), overrides; its picture and outline in the editor ([specs/enemy.md](specs/enemy.md) §3.3) |
| `tools/lib/enemy_placement.gd` | enemy | Sets out a spawn table as placed enemies (counts by weight, an even layout, types mixed): the chunk tool and the 2026-10-16 conversion |
| `game/enemy/slime_spider_ai.gd` | enemy | `SlimeSpiderAI.ts` (enemy spec §14): the Matron's AI, the spiders' idle and wander |
| `game/enemy/line_up_ai.gd` | enemy | The four-way shooters' chase, flee and attack (2026-10-16, enemy spec §20): the Worm Archer (`behavior: "liner-up"`), the Slime Spider and the Orb-weaver run to the slime's row or column and shoot straight down it; their numbers are their type's `ai` block in `enemy-types.json` |
| `game/enemy/enemy_projectiles.gd` | enemy | The world's `spawnEnemyProjectile` (enemy spec §12.3) |
| `game/scripts/projectile.gd` | enemy | `game.projectile`: flight, lifetime, wall stop, one hit on the player |
| `game/scripts/clod_stomper.gd` | enemy | The Clod Stomper (2026-10-09, roadmap 8.12) on top of `enemy.gd`: a camp enemy that stomps instead of swinging (ring telegraph, hop, slam, dazed), breaks cracked ground near its feet and always drops a stone essence |
| `game/enemy/patterned_enemy.gd`, `ground_shadow.gd`, `ground_shake.gd`; `game/scripts/popworm.gd`, `spitcap.gd`, `hopper.gd`, `bramble_boar.gd`, `thorn_guard.gd`, `rook_thief.gd`, `spore_seed.gd`; `game/runtime/sheet_sprite.gd` | enemy | The bestiary's patterned enemies (2026-10-16): a phase machine per enemy on top of `enemy.gd`, shielded phases and kill hits, the heavy ground shake, the catchable spore seed, sheets loaded imported or from the file ([BESTIARY.md](BESTIARY.md)) |
| `game/scripts/squint.gd`, `pipe_worm.gd`, `dung_roller.gd`, `mud_glob.gd`; `game/enemy/eye_glint.gd` | enemy | Fatty's Lair's bestiary enemies (2026-10-16): the Squints' Spear-only opening, the Pipe Worm's catchable mud glob and its eyes glinting in the pipe, the Dung Roller's track ([BESTIARY.md](BESTIARY.md)) |
| `game/scripts/silk_lurker.gd`, `thornball.gd`, `egg_sac.gd`, `broodling.gd`, `cocoon_mimic.gd`, `brood_warden.gd` | enemy | Chapter 2's bestiary enemies (2026-10-16): the Lurker's thread and drop, the Thornball's bounces (and the Goo Bomb's blast flipping it), the egg sac's swarm, the mimic's hold on the slime, the Warden's telegraphed sweeps ([BESTIARY.md](BESTIARY.md)) |
| `game/dev/corners/bestiary_corner.tscn`, `bestiary_corner.gd`, `bestiary_pen.gd` | dev | The playground's Bestiary corner: one pen per bestiary enemy, signs, respawn, F4, the Goo Bomb pens' box ability ([BESTIARY.md](BESTIARY.md#the-bestiary-corner)) |
| `game/dev/corners/barred_gate_corner.tscn` | dev | The playground's Barred-gate corner (x 2752-3264, y 4288-4600): the barred gate in a walled yard, a chest behind it, pots outside ([PROLOGUE.md](PROLOGUE.md#the-barred-gate)) |
| `game/dungeon/` (`dungeon.gd`, `dungeon_state.gd`, `room_door.gd`, `room_travel.gd` (a dungeon of one world per room: its doors), `dungeon_layout.gd`, `layout_room.gd`, `layout_mark.gd` (its map's layout), `dungeon_items.gd`, `dungeon_hud.gd`, `dungeon_map_draw.gd`, `dungeon_minimap.gd`, `dungeon_map_page.gd`, `dungeon_door.gd`, `key_door.gd`, `bolted_door.gd`, `shutter.gd`, `room_fight.gd`, `winch.gd`, `drawbridge.gd`, `hazard.gd`, `hazard_watch.gd`, `hazard_deck.gd`, `falling_slab.gd`, `shadow_path.gd`, `prize_glint.gd`, `dungeon_chest.gd`, `dungeon_key_pickup.gd`, `dungeon_pickup.gd`, `pot_loot.gd`, `energy_flower.gd`, `item_pop.gd`, `push_probe.gd`, `dungeon_seal.gd`, `seal_moment.gd`); `game/bosses/enraged_look.gd`; `game/scenes/objects/dungeon/`; `game/scenes/worlds/dungeon-lab.tscn`, `tools/build_dungeon_lab.gd`, `tools/render_dungeon_seal.gd` | dungeon kit | The shared dungeon kit (2026-10-17): the Dungeon node (no saving, resume at the entrance, rooms that come back, the HUD key chip, the dungeon map), small keys and the big key, locked doors with one or two keyholes, the boss door, bolted doors, shutters and room fights, winches, drawbridges, the void, falling slabs and spike pits (one hazard watch), refills that grow back, the shadow path and prize glints, the seal (the Pearl's take seals the doors out until the boss falls; the roar, the glimpse and the boss's rage), and the dev lab ([DUNGEONS.md](DUNGEONS.md)) |
| `game/fattys_lair/` (`lair_director.gd`, `burr_actor.gd`, `burr_outside.gd`, `heavy_check.gd`, `mud_ripple.gd`, `clod_shadow.gd`, `void_shade.gd`); `game/scripts/drop_gate.gd`, `gate_winch.gd`, `eye_latch.gd`, `plank_barricade.gd`, `stair_hatch.gd`, `pearl.gd`; `game/world_objects/worm_lever.gd`, `sliding_slab.gd`; `game/scenes/worlds/rooms/fatty-lair/` (one world per room), `tools/build_fattys_lair.gd` (retired) | dungeons (Fatty's Lair) | Chapter 1's dungeon (2026-10-17): the drop gate and its worm lever, the inner winch, the eye latches and their stone doors, the plank barricade (the Heavy Roll's check, `heavy_check.gd`, now reading the Heavy skin: [SKINS.md](SKINS.md)), the Inner Stair, Burr (his cell, his lines, outside after Fatty), Fatty's phase two (its clods and mud ripple), the Pearl, the voids' shade; the world and its builder ([DUNGEONS.md "Fatty's Lair (built)"](DUNGEONS.md#fattys-lair-built)) |
| `game/prologue/prologue_state.gd`, `prologue_director.gd`, `town_edge_meeting.gd`, `prologue_scene.gd`, `yoi_actor.gd`, `birth_bubble.gd`, `cinema_bars.gd`, `soft_glow.gd`, `fireflies.gd`; `game/world_objects/barred_gate_lever.gd`; `game/scenes/characters/yoi.tscn` | prologue | The prologue (roadmap 5.18-5.24): its story flags and the no-save state, the director in `west-village-b4` (the birth, the blocked path, Yoi's fight, the rescue, the Spear, the gate), Plop's meeting in `level-1-c4`, the scene helpers, Yoi's actor, the birth's bubble, the letterbox bars, glows and fireflies ([PROLOGUE.md](PROLOGUE.md)) |
| `game/enemy/spider_web_port.gd` | enemy | The world's `world.spider-web` port, `catchInWeb`, `applyWeb` (duck-typed player hooks, [specs/matron.md](specs/matron.md) §5) |
| `game/scripts/fatty.gd` | boss | Fatty One Eye's phases on top of `enemy.gd` ([specs/boss.md](specs/boss.md)) |
| `game/scripts/matron.gd` | boss | The Orb-Weaver Matron's volleys on top of `enemy.gd` ([specs/matron.md](specs/matron.md)) |
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
| `game/feel/hit_flash.gdshader` | combat | Also hides the body behind higher ground (`elevation_occlusion.gdshaderinc`; inert without elevation) |
| `game/feel/floating_text_layer.gd` | combat | |
| `game/feel/particle_fx.gd` | combat | |
| `game/runtime/**` | converter | Helpers the converted scenes use (audio, animation, placeholders, UI) |
| `game/scenes/**`, `game/scenes/scene_index.json` | scenes | Every world, object, character, weapon, effect, projectile and encounter scene, Godot's since Phase 1 (CONVENTIONS "Scenes Godot owns"); checked by `tools/verify_scenes.gd` |
| `game/world/terrain_tileset.tres` | scenes | The terrain TileSet the world scenes' ground layers use |
| `game/audio/music_director.gd` | audio | Autoload `MusicDirector`: world and boss music, leave/arrival fades, menu duck, `AreaTransition` cue, the mix hook ([specs/audio.md](specs/audio.md)) |
| `game/shell/shell.gd` | shell | Autoload `Shell`: window stack, Escape and pause, area titles, game over, end cards, quit to title ([specs/shell.md](specs/shell.md)) |
| `game/shell/title.tscn`, `title.gd` | shell | The title screen (the main scene): launch-option skip, level-1 backdrop, New Game / Continue / Load / Settings / Credits |
| `game/shell/*_menu.tscn/.gd`, `game_over.*`, `end_card.*`, `area_title_card.*` | shell | The shell windows (Godot-owned copies of the `ui.*` scenes) on `shell_menu.gd` |
| `game/shell/game_settings.gd`, `control_labels.gd`, `area_titles.gd`, `launch_options.gd` | shell | Settings (user://settings.cfg, bus mix, GameFeel), InputMap key labels, area names / colours (region worlds named from `game/data/world-map.json`), launch options |
| `game/ui/theme/ui_tokens.gd`, `slime_theme.tres`, `icons/` | UI theme | Design tokens and the one UI Theme with its drawn icons, built by `tools/build_ui_theme.gd` ([UI_THEME.md](UI_THEME.md)) |

Only ported scene scripts live in `game/scripts/`: every file there is a scene-script id
(`game.<kebab-id>` → `<snake_id>.gd`), so add one only when porting that script.

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
| O1 | Moving vertically: the live look (`walk` in every direction) or the intended `hop`/`stretch`? (player spec 4.3) | **New art.** The slime sheet is side-view and has no real up/down walk, so the owner wants a new three-quarter top-down player sheet with idle and walk per direction (then attacks and abilities), built piece by piece. Page 1 (idle and walk per direction) and page 2 (rolls and the stretch lash) are in since 2026-10-05, with keyed sword swings and ability clips on page 1's art: the player scene is Godot-owned and `player.gd` plays `<clip>-down/-up/-side` (or `-left`) for its facing |
| O2 | Pointer aim origin. The player spec recommends the intended feet − 28; the combat spec says port as is (centre − 28 = feet − 55.56). The specs disagree | **Keep the live aim**: `aim_rise_px = 28` above the old centre (top of the head) |
| O3 | Combo off-by-one: every lone sword hit does 28, not 24 | **Fixed in the port**: the multiplier is the hit's own tier (×1.0, ×1.15, ×1.5), so a lone sword hit does 24 (crit 42); the Phaser game keeps its bug until it is retired |
| O4 | Standing still always un-flips the slime (faces left) | **Done with the new art** (2026-10-05): idle clips per direction keep the last facing |
| O5 | Trial setup: dodge learned, sword equipped, respawn at spawn after 1.4 s with no defeat screen, only the worm-swordsman camp active (the other three camps are skipped by `allowed_types`) | As listed. Since 2026-10-05 every camp spawns: archers, brawlers, slime spiders and orb weavers are ported (`allowed_types` is empty) |
| O6 | Godot bodies do not shove each other (Arcade did, slightly) | Accept for the trial |

### Converter and integration notes (resolved during the trial)

- Node-typed exports resolve only when listed in the node header (`node_paths=PackedStringArray(...)`); the converter wrote it, and the editor keeps it.
- Solid terrain tiles (`WorldService.SOLID_TILE_IDS`: deep water and rock wall; shallow water is walkable since 2026-10-06) carry a `tile_id` custom data layer, which `WorldService.is_solid_tile` reads. Deep water collides through a full-cell square on its tiles in `game/world/terrain_tileset.tres` (physics layer `water`), except on the cells under a bridge deck (`game/world/bridge_deck.gd`, which `world_ground.gd` opens through runtime tile data; [specs/water.md](specs/water.md) §10); rock wall through merged rectangle bodies under `ground/TileCollision` (Phaser's outer-edge inset).
- Re-anchored scenes placed in worlds (NPCs) get `depth_anchor` added to their position; instance roots carry `metadata/instance_id` and `metadata/persistence_key`.
- The ground layer is the TileMapLayer whose `tile_set` is `res://game/world/terrain_tileset.tres`.
- The water surface is the ground layer's child `WaterSurface` (z -2, drawn right after the tiles); underwater life (z -2) y-sorts after it. The terrain edges are the next child, `TerrainEdges`, drawn over the surface: at a shore they fill with the same water (shared `water_surface.gdshaderinc`, the surface's own mask) and the land's edge tile on top, so `smooth_water_ground` stays on ([TERRAIN_LAB.md](TERRAIN_LAB.md)).
- Physics interpolation is on; the camera blends its target between ticks itself.
- `*.gd.uid` files are committed.
