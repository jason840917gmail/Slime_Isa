# Godot project conventions

Rules for working in `godot/` during the migration. The plan and phases are in
[GODOT_MIGRATION.md](../GODOT_MIGRATION.md); the game's structure (autoloads,
data flow, file map) is in [ARCHITECTURE.md](./ARCHITECTURE.md); exact Phaser
behaviour per area is in [specs/](./specs/).

## Layout

| Path | Made by | Content |
|---|---|---|
| `godot/project.godot` | hand (Godot editor) | settings, input map, physics layer names, autoloads |
| `godot/asset/` | `pnpm godot:sync`, git-ignored | copies of every file `asset/assets.json` maps, at `res://asset/<source.path>` |
| `godot/generated/` | `pnpm godot:convert`, git-ignored | converted scenes (`scenes/<path under content/scenes/authored>.tscn`), `resources/terrain_tileset.tres`, `resources/ui_theme.tres`, `scene_index.json` (scene id → path), `data/` copies of `game-constants.json`, `enemy-types.json`, `items.json`, `collision-layers.json`, and `conversion_report.json` |
| `godot/game/runtime/` | hand, owned with the converter | helper scripts the converter attaches: `sfx_player(_2d).gd`, `animation_player.gd`, `unported_script.gd`, `modal_root.gd`, `scene_item_list.gd`, `audio_cue_rules.gd` |
| `godot/game/scripts/` | hand | one file per ported scene-script id (`game.world-area` → `world_area.gd`); the converter attaches it and writes the exports it declares |
| `godot/game/characters/` | hand (Godot editor) | scenes Godot owns (below), e.g. `player_slime.tscn` |
| `godot/game/dev/` | hand | development scenes, e.g. `playground.tscn` (below) and the [terrain lab](./TERRAIN_LAB.md) |
| `godot/game/**` (rest) | hand | autoloads, gameplay, UI, bootstrap (`main.tscn`) |
| `godot/tools/` | hand | headless tools such as `verify_generated.gd`, `build_player_clips.gd` and `build_terrain_lab.gd`; excluded from exports |
| `godot/tests/` | hand | headless integration tests: `run_tests.gd` runs every `func test_*` in `test_*.gd` against a fresh `main.tscn` (helpers in `lib/test_context.gd`; game bugs not fixed yet go in a file's `KNOWN_FAILURES`); excluded from exports |
| `godot/addons/godot_ai/` | the Godot AI plugin (4.3.0, MIT), committed | the editor plugin (MCP bridge) that lets Claude drive the open editor, plus its `_mcp_game_helper` autoload for running-game inspection; disabled by itself in headless runs and excluded from exports. Update it from its dock, then commit |

Until Phase 1 of the migration ends, scene JSON is the source of truth: change
content there and re-run the converter. Never hand-edit `godot/generated/`.

## Scenes Godot owns

Phase 1 moves scenes to Godot one at a time. To take one over, copy its converted
`.tscn` from `godot/generated/scenes/` into `godot/game/` (characters go in
`game/characters/`) and add its scene id to `OWNED_SCENES` in
`game/autoload/world_service.gd`; `WorldService.scene_path` then returns the owned copy
instead of the generated one. From then on edit it in the Godot editor (or with a tool in
`godot/tools/`); the converter keeps writing the old generated copy, which nothing loads.

| Scene id | Owned scene | Since |
|---|---|---|
| `character.player-slime` | `res://game/characters/player_slime.tscn` | 2026-10-05: the three-quarter top-down slime sheet (directional idle, walk, roll and sword-swing clips, built by `tools/build_player_clips.gd`) |
| `ui.title-screen`, `ui.pause-menu`, `ui.settings`, `ui.controls`, `ui.credits`, `ui.game-over`, `ui.end-card`, `ui.area-title-card` | `res://game/shell/title.tscn`, `pause_menu.tscn`, `settings_menu.tscn`, `controls_menu.tscn`, `credits_menu.tscn`, `game_over.tscn`, `end_card.tscn`, `area_title_card.tscn` | 2026-10-05: the game shell on the UI theme ([specs/shell.md](./specs/shell.md)). Loaded by path from the Shell and the title, so they are not in `OWNED_SCENES` |
| `ui.save-slots` | `res://game/saves/save_slots_menu.tscn` | 2026-10-05: the save slots window, mounted on the Shell by `RunState` (`Shell.mount_menu`); loaded by path |

## Running a world

F5 runs the title screen (`game/shell/title.tscn`, the main scene); New Game and Continue start
`game/main.tscn`, which loads level-1, and a `map` launch option skips the title. To test in the playground (the testbed
where new mechanics are tried first), open `game/dev/playground.tscn` and press F6 (Run
Current Scene); it inherits `main.tscn` with `map_id = "playground"`. Any other world:
set `map_id` on a scene like it, or launch with `?map=<id>` (web) / `-- --map=<id>`
(desktop). `?spawn=<x>,<y>` / `-- --spawn=<x>,<y>` places the player at an old Phaser
position.

## Input and physics

- Input actions are the snake_case of `src/game/features/player/PlayerInputActions.ts`:
  `move_up/down/left/right`, `attack` (LMB), `interact` (RMB), `sprint`, `jump`, `dodge`,
  `stretch_lash`, `squash_slam`, `teleport`, `eat`, `weapon_next/previous` (wheel),
  `menu`, `map`, `zoom_in/out`, `pause`.
- Physics layers keep the bits and names of `src/game/content/physics/collision-layers.json`.
  60 physics ticks per second (enemy AI rolls per step depend on it); physics
  interpolation is on.
- Audio buses: Master, Effects, Music, Ambience.

## Scene conversion facts scripts rely on

- **Feet origin.** A converted scene root that had a `depthAnchor` (characters,
  projectiles, effects) now sits at its feet and carries `metadata/depth_anchor`.
  The old Phaser position (the body centre for characters) is
  `global_position - depth_anchor * scale`; use `shared/feet_anchor.gd`
  (`FeetAnchor.phaser_position`, `place_at_phaser_position`) or the scripts'
  `get_centre()`. Spawn with `WorldService.spawn_at_phaser_position`.
- **Script exports.** JSON `camelCase` properties become `snake_case` exports. The
  converter writes only exports the target script declares; typed Node exports are
  listed in the node's `node_paths` header so they resolve on instantiate.
  Dictionary values keep their JSON camelCase keys.
- **Signals and handlers.** A script declares its JSON signals by name and emits one
  Dictionary payload (camelCase keys, as in Phaser). Handlers keep the JSON handler id
  and take one argument; Godot's own signals pass Godot's arguments.
- **Audio and animation helpers.** Call `play_cue(payload)` / `stop_cue(payload)` on
  audio players, and `play_clip` / `stop_clip` on converted AnimationPlayers (their
  `animation_event(event: Dictionary)` signal carries `event_id`, `payload`,
  `gameplay`, `animation`, `at`). Clips live in the default library, so names are
  plain (`idle`, `attack-side`).

## GDScript rules

- Godot 4.7, static typing everywhere, tabs, snake_case, one class per file.
- Reach autoloads only through `res://game/shared/services.gd`
  (`Services.world()`, `.router()`, `.feel()`, `.constants()`, `.clock()`,
  `.now_ms()`): the headless check does not know autoload names.
- Reference other scripts with `const Foo := preload("res://game/....gd")`.
- One gameplay clock: `Services.now_ms()`. Real time only for presentation
  (flashes, floating text, camera). Hit-stop pauses the tree; scripts that must keep
  running (input buffering, camera, HUD) use `PROCESS_MODE_ALWAYS`.
- Each body is moved only by its own scene script, with `ArcadeMover.move(body, delta)` (`game/shared/arcade_mover.gd`); never `move_and_slide()`, whose floating-mode slide differs from Phaser's Arcade.
- Gameplay values come from `generated/data/game-constants.json` (through
  `Services.constants()`) or from scene properties, never new literals.
- Commit the `*.gd.uid` files Godot creates next to scripts.

## Checking your work

```bash
pnpm godot:sync && pnpm godot:convert
"<Godot 4.7.2 console exe>" --headless --path godot --import
"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/verify_generated.gd
"<Godot 4.7.2 console exe>" --headless --path godot --check-only -s res://game/<file>.gd
"<Godot 4.7.2 console exe>" --headless --path godot --quit-after 600
pnpm test:godot    # = --headless --path godot -s res://tests/run_tests.gd; Godot from $GODOT
```

`pnpm test:godot` (about a minute) checks the trial's numbers from [specs/](./specs/): walk,
sprint and dodge, sword and worm damage, i-frames, knockback, worm death, the starter camp's
spawning, respawn, the camera follow, level-1's tiles, the water mask, draw order and water-life
clips, the Fatty One Eye fight (camp spawn and reset, hop and leap timings, landing damage, arena
leash, health bar, defeat), the ranged enemies (`test_enemy_ranged.gd`: archer arrows, projectile
lifetime, walls and hurtboxes, flee range, the spider AI and webs, the brawler's impact effect,
slow, knockback immunity, every world enemy type, crystal-caverns' legacy spawning), the
Orb-Weaver Matron (`test_matron.gd`: nest camp and bar, spit, volley marks, landing and web
patches, no stagger, arena leash, defeat records, reset, the web barrier and its torn flag,
gloop-forest's orb weavers), and a 600-frame run without engine errors. Add `--filter=<text>` to run some tests,
`--strict` to fail on known failures too.

The `--check-only` pass reports one error per run and does **not** catch calls to
methods that do not exist on autoloads, so always also boot the game headless.
Do not run headless `--import` while the Godot editor has the project open: they
share the import cache.
