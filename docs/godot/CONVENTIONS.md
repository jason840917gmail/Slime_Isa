# Godot project conventions

Rules for working in `godot/` during the migration. The plan and phases are in
[GODOT_MIGRATION.md](../GODOT_MIGRATION.md); the game's structure (autoloads,
data flow, file map) is in [ARCHITECTURE.md](ARCHITECTURE.md); exact Phaser
behaviour per area is in [specs/](specs).

## Layout

| Path | Made by | Content |
|---|---|---|
| `godot/project.godot` | hand (Godot editor) | settings, input map, physics layer names, autoloads |
| `godot/asset/` | art tools in `scripts/` (or by hand), committed with their `.import` files | the runtime art and audio, at `res://asset/...` (moved from the repository's `asset/` at the cutover; sources stay in `asset/Originals/`) |
| `godot/game/data/` | hand, from the Phaser content on 2026-10-05 | the game data: `game-constants.json`, `enemy-types.json`, `items.json`, `collision-layers.json`, `npc-definitions.json`, `recipes.json`, `quests-chapter-1.json` / `-2.json`, `weapons.json` (names, icons, stats) and `item-icons.json` (texture key → sheet, frame size, grid), read through `GameConstants` (`Services.constants()`) |
| `godot/game/scenes/` | hand (Godot editor), from the converter on 2026-10-05 | every world, object, character, weapon, effect, projectile and encounter scene (`<kind>s/<path>.tscn`, the scene JSON's layout) and `scene_index.json` (scene id → path); see "Scenes Godot owns" |
| `godot/game/world/terrain_tileset.tres` | hand, from the converter | the terrain TileSet (one atlas source per tile id, `tile_id` custom data) |
| `godot/game/runtime/` | hand | helper scripts the converted scenes use: `sfx_player(_2d).gd`, `animation_player.gd`, `unported_script.gd`, `modal_root.gd`, `scene_item_list.gd`, `audio_cue_rules.gd` |
| `godot/game/scripts/` | hand | one file per ported scene-script id (`game.world-area` → `world_area.gd`), attached to the scenes that use it; a new `@export` gets its value in the editor |
| `godot/game/characters/` | hand (Godot editor) | scenes Godot owns (below), e.g. `player_slime.tscn` |
| `godot/game/dev/` | hand | development scenes, e.g. `playground.tscn` (below) and the [terrain lab](TERRAIN_LAB.md) |
| `godot/game/**` (rest) | hand | autoloads, gameplay, UI, bootstrap (`main.tscn`) |
| `godot/tools/` | hand | headless tools such as `verify_scenes.gd`, `build_player_clips.gd` and `build_terrain_lab.gd`; excluded from exports |
| `godot/tests/` | hand | headless integration tests: `run_tests.gd` runs every `func test_*` in `test_*.gd` against a fresh `main.tscn` (helpers in `lib/test_context.gd`; game bugs not fixed yet go in a file's `KNOWN_FAILURES`); excluded from exports |
| `godot/addons/godot_ai/` | the Godot AI plugin (4.3.0, MIT), committed | the editor plugin (MCP bridge) that lets Claude drive the open editor, plus its `_mcp_game_helper` autoload for running-game inspection; disabled by itself in headless runs and excluded from exports. Update it from its dock, then commit |

Scenes, game data and art are Godot's: edit scenes in the Godot editor (or with a tool in
`godot/tools/`), items, quests, recipes and constants in `godot/game/data/`, and art through the tools
in `scripts/` ([TOOLING.md](../TOOLING.md)). The Phaser app they came from was removed at the cutover
(2026-10-05).

## Scenes Godot owns

Every scene is Godot's since Phase 1 of the migration (2026-10-05). The converter's last output
was copied into `godot/game/scenes/` with the scene JSON's folder layout (`worlds/level-1.tscn`,
`objects/interiors/beds/...`), and `game/scenes/scene_index.json` maps every scene id to its file;
`WorldService.scene_path(id)` reads it. The converter's UI scenes were not kept: Godot-owned
windows built on the theme replace them (table below).

- Edit a scene in the Godot editor. A scene file that moves or is renamed must be updated in
  `scene_index.json` (and in the scenes that instance it; the editor's move does both for `.tscn`
  references, not for the JSON).
- A new scene the game loads by id (`object.<name>`, `character.<name>`, `world.<id>`, ...) needs a
  line in `scene_index.json`; a new world also needs a world exit that leads to it.
- `res://tools/verify_scenes.gd` loads and instantiates every indexed scene and plays level-1
  ("Checking your work").

Scenes that differ from the converter's copy or replace it:

| Scene id | Owned scene | Since |
|---|---|---|
| `character.player-slime` | `res://game/characters/player_slime.tscn` | 2026-10-05: the three-quarter top-down slime sheet (directional idle, walk, roll, sword-swing and ability clips, plus doze, sleep and defeat facing down, built by `tools/build_player_clips.gd`; no old side-view clip is left) |
| `ui.title-screen`, `ui.pause-menu`, `ui.settings`, `ui.controls`, `ui.credits`, `ui.game-over`, `ui.end-card`, `ui.area-title-card` | `res://game/shell/title.tscn`, `pause_menu.tscn`, `settings_menu.tscn`, `controls_menu.tscn`, `credits_menu.tscn`, `game_over.tscn`, `end_card.tscn`, `area_title_card.tscn` | 2026-10-05: the game shell on the UI theme ([specs/shell.md](specs/shell.md)). Loaded by path from the Shell and the title, not through the scene index |
| `ui.save-slots` | `res://game/saves/save_slots_menu.tscn` | 2026-10-05: the save slots window, mounted on the Shell by `RunState` (`Shell.mount_menu`); loaded by path |
| `ui.minimap`, `ui.world-map-ui` | `res://game/ui/map/minimap.gd` (built in code), `world_map_window.tscn` | 2026-10-05: the minimap and the world map ([specs/map.md](specs/map.md)), made by `MapUi` under the HUD; loaded by path |
| `ui.inventory-ui`, `ui.crafting-ui`, `ui.menu-tabs`, `ui.weapon-hotbar` | `res://game/ui/screens/inventory_screen.gd`, `crafting_screen.gd`, `menu_tabs.gd` (built in code; made by `menu_windows.gd` on GameWindows), `res://game/ui/weapon_hotbar.gd` (built in code under the HUD) | 2026-10-05: the bag, the crafting window, the menu tab strip and the HUD weapon belt ([specs/crafting.md](specs/crafting.md)); the converted copies stay unused |
| `ui.npc-dialogue`, `ui.quest-offer-modal`, `ui.quest-tracker` | `res://game/ui/screens/dialogue_box.tscn`, `quest_offer_window.tscn`, `res://game/ui/quest_tracker.tscn` | 2026-10-05: the NPC dialogue box, the quest offer / turn-in window and the HUD quest tracker on the UI theme ([specs/quests.md](specs/quests.md)); the quest service mounts the first two on GameWindows, the HUD the tracker; loaded by path |
| `ui.quest-journal`, `ui.chest-inventory-panel` | `res://game/ui/screens/quest_journal_window.gd`, `chest_window.gd` (built in code; main adds them to GameWindows) | 2026-10-05: the quest journal and the chest window ([specs/journal-and-chest.md](specs/journal-and-chest.md)); the converted copies stay unused |

## Running a world

F5 runs the title screen (`game/shell/title.tscn`, the main scene); New Game and Continue start
`game/main.tscn`, which loads level-1, and a `map` launch option skips the title. To test in the playground (the testbed
where new mechanics are tried first), open `game/dev/playground.tscn` and press F6 (Run
Current Scene); it inherits `main.tscn` with `map_id = "playground"`. F6 on a world scene
itself (`game/scenes/worlds/<id>.tscn`) works too: run on its own, a world has no player, camera
or HUD, so its `world_definition.gd` swaps it for `main.tscn` with its map id (the playground keeps
its testbed kit). Or launch with `?map=<id>` (web) / `-- --map=<id>` (desktop). `?spawn=<x>,<y>` / `-- --spawn=<x>,<y>` places the player at an old Phaser
position. `?quest=<id>[:<stage>]` / `-- --quest=<id>[:<stage>]` makes a quest active at that stage
(default the first) when the first world is built (`QuestService.debug_activate`: earlier stages
done, no rewards), to reach quest steps whose systems are not ported yet; it does not skip the
title by itself (add `map` or `skip-title`). A new run starts empty-handed (Phaser); the playground
hands out every weapon and every ability. `?weapon=<id>` / `-- --weapon=<id>` gives a new run that weapon (bag, belt
slot 1, hand); `?recipes` / `-- --recipes` makes every
recipe known (until quests teach them); `?arsenal` / `-- --arsenal` adds the six development weapons
at a new run ([specs/crafting.md](specs/crafting.md) C2, C3, 8.2).

## Input and physics

- Input actions are the snake_case of Phaser's `PlayerInputActions.ts` (removed at the cutover):
  `move_up/down/left/right`, `attack` (LMB), `interact` (RMB), `sprint`, `jump`, `dodge`,
  `stretch_lash`, `squash_slam`, `teleport`, `eat`, `weapon_next/previous` (wheel),
  `menu`, `map`, `zoom_in/out`, `pause`.
- Physics layers keep the bits and names of `game/data/collision-layers.json` (Phaser's layers).
  Layers 12-18 (`level -3` … `level 3`) are the walls of each elevation level: a walking body
  collides with its own level's layer only ([ELEVATION.md](ELEVATION.md)).
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
- Gameplay values come from `game/data/game-constants.json` (through
  `Services.constants()`) or from scene properties, never new literals.
- Commit the `*.gd.uid` files Godot creates next to scripts.

## Checking your work

```bash
"<Godot 4.7.2 console exe>" --headless --path godot --import    # not while an editor has the project open
"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/verify_scenes.gd
"<Godot 4.7.2 console exe>" --headless --path godot --check-only -s res://game/<file>.gd
"<Godot 4.7.2 console exe>" --headless --path godot --quit-after 600
pnpm test:godot    # = --headless --path godot -s res://tests/run_tests.gd; Godot from $GODOT
```

Run the tests only when the user asks or after a really big, breaking change ([AGENTS.md](../../AGENTS.md)). `pnpm test:godot` (about ten minutes for the full suite; `--filter=<text>` runs one file) checks the trial's numbers from [specs/](specs): walk,
sprint and dodge, sword and worm damage, i-frames, knockback, worm death, the starter camp's
spawning, respawn, the camera follow, level-1's tiles, the water mask, draw order and water-life
clips, the Fatty One Eye fight (camp spawn and reset, hop and leap timings, landing damage, arena
leash, health bar, defeat), the ranged enemies (`test_enemy_ranged.gd`: archer arrows, projectile
lifetime, walls and hurtboxes, flee range, the spider AI and webs, the brawler's impact effect,
slow, knockback immunity, every world enemy type, crystal-caverns' legacy spawning), the
Orb-Weaver Matron (`test_matron.gd`: nest camp and bar, spit, volley marks, landing and web
patches, no stagger, arena leash, defeat records, reset, the web barrier and its torn flag,
gloop-forest's orb weavers), the quests (`test_quests.gd`, `test_quests_gloop.gd`: new-run
records, offer / turn-in conversations, the dialogue reveal and keys, rewards, known facts, the
tracker, markers, toasts, waypoint targets, saves), crafting, the bag and the belt (`test_crafting.gd`,
`test_inventory.gd`, `test_loadout.gd`: quotes and the status order, the crafting window, the menu
key and tabs, consumables, drops, the wheel, the hotbar, the trial sword), the quest journal and the chest window
(`test_journal.gd`, `test_chest_window.gd`), and a 600-frame run without engine errors. Add `--filter=<text>` to run some tests
(`--filter=a|b` runs either; quote it in the shell), `--strict` to fail on known failures too. Sound
checks ask `TestContext.played(player)` (cues started since `TestContext.silence(player)`), not
`playing`: a short cue can already have ended when a starved headless mixer catches up.

The `--check-only` pass reports one error per run and does **not** catch calls to
methods that do not exist on autoloads, so always also boot the game headless.
Do not run headless `--import` while the Godot editor has the project open: they
share the import cache.
