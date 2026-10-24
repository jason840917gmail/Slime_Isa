# Godot project conventions

Rules for working in `godot/` during the migration. The plan and phases are in
[GODOT_MIGRATION.md](../GODOT_MIGRATION.md); the game's structure (autoloads,
data flow, file map) is in [ARCHITECTURE.md](ARCHITECTURE.md); exact Phaser
behaviour per area is in [specs/](specs).

## Layout

| Path | Made by | Content |
|---|---|---|
| `godot/project.godot` | hand (Godot editor) | settings, input map, physics layer names, autoloads |
| `godot/asset/` | art tools in `scripts/` (or by hand), committed with their `.import` files | the runtime art and audio, at `res://asset/...` (moved from the repository's `asset/` at the cutover; sources stay in `asset/Originals/`, and so do the art tools' own inputs: everything under `godot/asset/` ships in the web build, which is why the cliff kits moved to `asset/Originals/elevation/cliff-kit/` on 2026-10-17) |
| `godot/game/data/` | hand, from the Phaser content on 2026-10-05 | the game data: `game-constants.json`, `enemy-types.json`, `items.json`, `npc-definitions.json`, `recipes.json`, `quests-chapter-1.json` / `-2.json`, `weapons.json` (names, icons, stats), `item-icons.json` (texture key → sheet, frame size, grid) and `liftables.json` (the 67 liftable kinds: name, material, frames, art size; written by `scripts/props/pack-gulp-art.py` since 2026-10-09, so edit the kinds there), read through `GameConstants` (`Services.constants()`) |
| `godot/game/scenes/` | hand (Godot editor), from the converter on 2026-10-05 | every world, object, character, weapon, effect, projectile and encounter scene (`<kind>s/<path>.tscn`, the scene JSON's layout) and `scene_index.json` (scene id → path); see "Scenes Godot owns" |
| `godot/game/world/terrain_tileset.tres` | hand, from the converter | the terrain TileSet (one atlas source per tile id, `tile_id` custom data) |
| `godot/game/runtime/` | hand | helper scripts the converted scenes use: `sfx_player(_2d).gd`, `animation_player.gd`, `audio_cue_rules.gd`; and `sheet_sprite.gd`, the bestiary's sheet sprite (the converter's `unported_script.gd`, `modal_root.gd` and `scene_item_list.gd`, which no scene used, were removed in clean-out wave 1, 2026-10-17) |
| `godot/game/scripts/` | hand | one file per ported scene-script id (`game.world-area` → `world_area.gd`), attached to the scenes that use it; a new `@export` gets its value in the editor |
| `godot/game/characters/` | hand (Godot editor) | scenes Godot owns (below), e.g. `player_slime.tscn` |
| `godot/game/dev/` | hand | development scenes, e.g. `playground.tscn` (below), the [terrain lab](TERRAIN_LAB.md) and the [world atlas](WORLD_ATLAS.md) (`world_atlas.tscn`) |
| `godot/game/**` (rest) | hand | autoloads, gameplay, UI, bootstrap (`main.tscn`) |
| `godot/tools/` | hand | headless tools such as `verify_scenes.gd`, `build_player_clips.gd`, `build_terrain_lab.gd` and `build_region_worlds.gd` (with `region_worlds/`; [WORLD_ATLAS.md](WORLD_ATLAS.md)); excluded from exports |
| `godot/tests/` | hand | headless integration tests: `run_tests.gd` runs every `func test_*` in `test_*.gd` against a fresh `main.tscn` (helpers in `lib/test_context.gd`; game bugs not fixed yet go in a file's `KNOWN_FAILURES`); excluded from exports |
| `godot/addons/scenery_dock/` | hand | the Scenery dock: every scenery prop by picture, dragged into the 2D view as a node under the world's `Scenery` node (its Enemies category: every enemy type, dragged in as a placed enemy under `Enemies`, [specs/enemy.md](specs/enemy.md) §3.3), and the export step that leaves the paint layers' palette pictures out of exported games ([PROPS.md](PROPS.md)); editor only, the game never loads it |
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
  line in `scene_index.json`; a new world also needs a world exit that leads to it, and its
  `ground` layer needs the script `res://game/world/world_ground.gd` (so the editor shows its water
  and terrain edges; [TERRAIN_LAB.md](TERRAIN_LAB.md#how-it-works)).
- `res://tools/verify_scenes.gd` loads and instantiates every indexed scene and plays level-1
  ("Checking your work").
- World sizes follow the chunk grid in [docs/story/03-world.md](../story/03-world.md#world-size-and-screen):
  64 px tiles, a screen of 16 × 14 tiles (the 1024 × 896 play area; with the HUD console's 128-unit
  strip under it, the 1024 × 1024 base view in `project.godot`), overworld
  maps in whole chunks of 32 × 32 tiles (level-1 is 64 × 64), interiors no bigger than one screen.
- Where the worlds sit is the layout `godot/game/data/world-map.json` ([WORLD_ATLAS.md](WORLD_ATLAS.md)):
  each region names its overworld scene (`world`) and interiors. Touching regions connect only at
  designated openings (one per stretch of shared border, its exit on both sides, `entry_marker`
  naming the arrival marker; an opening into a hand-made world is one-way until that world gets
  its own exit and `arrive-from-<world>-1` marker there: the atlas shows which). See and rearrange the whole world in `game/dev/world_atlas.tscn`;
  rebuild the placeholder regions with `tools/build_region_worlds.gd` after a layout change; a
  region you start building by hand: set its `placeholder` to false (or drop the scene root's
  `world_map_placeholder` metadata) so the tool leaves it alone.

Scenes that differ from the converter's copy or replace it:

| Scene id | Owned scene | Since |
|---|---|---|
| `character.player-slime` | `res://game/characters/player_slime.tscn` | 2026-10-05: the three-quarter top-down slime sheet (directional idle, walk, roll, sword-swing and ability clips, plus doze, sleep and defeat facing down, built by `tools/build_player_clips.gd`; no old side-view clip is left). 2026-10-12, body-shapes prototype ([BODY_SHAPES.md](BODY_SHAPES.md)): the same tool builds the War Axe's Spin pose clips (`shape-axe-<pose>-<direction>`, page 6), which only the rework mode plays; the shapes' strike animations are built at run time (StrikeLibrary), not stored in the scene; the `StrikeRig`, `StrikeRigFront` and `StrikeRigNeck` nodes under the Visual draw their weapons |
| `ui.title-screen`, `ui.pause-menu`, `ui.settings`, `ui.controls`, `ui.credits`, `ui.game-over`, `ui.end-card`, `ui.area-title-card` | `res://game/shell/title.tscn`, `pause_menu.tscn`, `settings_menu.tscn`, `controls_menu.tscn`, `credits_menu.tscn`, `game_over.tscn`, `end_card.tscn`, `area_title_card.tscn` | 2026-10-05: the game shell on the UI theme ([specs/shell.md](specs/shell.md)). Loaded by path from the Shell and the title, not through the scene index |
| `ui.save-slots` | `res://game/saves/save_slots_menu.tscn` | 2026-10-05: the save slots window, mounted on the Shell by `RunState` (`Shell.mount_menu`); loaded by path |
| `ui.minimap`, `ui.world-map-ui` | `res://game/ui/map/minimap.gd` (built in code), `world_map_window.tscn` | 2026-10-05: the minimap and the world map ([specs/map.md](specs/map.md)), made by `MapUi` under the HUD; loaded by path |
| `ui.inventory-ui`, `ui.crafting-ui`, `ui.menu-tabs`, `ui.weapon-hotbar` | `res://game/ui/screens/inventory_screen.gd`, `crafting_screen.gd`, `menu_tabs.gd` (built in code; made by `menu_windows.gd` on GameWindows), `res://game/ui/weapon_hotbar.gd` (built in code under the HUD) | 2026-10-05: the bag, the crafting window, the menu tab strip and the HUD weapon belt ([specs/crafting.md](specs/crafting.md)); the converted copies stay unused |
| `ui.npc-dialogue`, `ui.quest-offer-modal`, `ui.quest-tracker` | `res://game/ui/screens/dialogue_box.tscn`, `quest_offer_window.tscn`, `res://game/ui/quest_tracker.tscn` | 2026-10-05: the NPC dialogue box, the quest offer / turn-in window and the HUD quest tracker on the UI theme ([specs/quests.md](specs/quests.md)); the quest service mounts the first two on GameWindows, the HUD the tracker; loaded by path |
| `ui.quest-journal`, `ui.chest-inventory-panel` | `res://game/ui/screens/quest_journal_window.gd`, `chest_window.gd` (built in code; main adds them to GameWindows) | 2026-10-05: the quest journal and the chest window ([specs/journal-and-chest.md](specs/journal-and-chest.md)); the converted copies stay unused |

## Running a world

F5 runs the title screen (`game/shell/title.tscn`, the main scene); New Game starts
`game/main.tscn` in the prologue (the birth at the Wellspring, `west-village-b4`;
[PROLOGUE.md](PROLOGUE.md)), Continue in the saved world, and a `map` launch option skips the title
(main.tscn on its own loads level-1). To test in the playground (the testbed
where new mechanics are tried first), open `game/dev/playground.tscn` and press F6 (Run
Current Scene); it inherits `main.tscn` with `map_id = "playground"`. F6 on a world scene
itself (`game/scenes/worlds/<id>.tscn`; a room you enter from a chunk lives in that chunk's folder,
`game/scenes/worlds/rooms/<chunk>/<id>.tscn`: Slimeshire's by the short chunk name, `rooms/c4/`,
`rooms/d4/`, other regions' by the full one, `rooms/gloop-forest-e4/`; a dungeon keeps its own
`rooms/<dungeon>/`; owner, 2026-10-22) works too: run on its own, a world has no player, camera
or HUD, so its `world_definition.gd` swaps it for `main.tscn` with its map id (the playground keeps
its testbed kit). The dev worlds (the labs and test worlds) live in `game/scenes/worlds/dev/`, and the playground's two caves in `game/scenes/worlds/rooms/playground/`; the web export leaves out `dev/` and `elevation_cache/dev__*` by glob (`godot/export_presets.cfg`), so a new lab or test world goes in `dev/`, and a new playground cave in `rooms/playground/`. A dungeon's world run this way (listed in `dungeon.devPowers` in
game-constants.json: Fatty's Lair and its hill outside, `level-1-d5`, the Weaver Hollow's four
floors, the Crystal Mine, the dungeon lab) plays in the body-shapes mode with the powers the slime has by then: the Spear and the Roll,
then the Heavy skin and the Goo Bomb, then the Silk skin and the Lantern. They are lent for the
session (abilities through `learn_session_ability`, the `skin.<name>` entries as lent skins:
`SkinState.lend`, [SKINS.md](SKINS.md)) and
the autosave is off (owner, 2026-10-17; `main.gd` `dev_powers_for`). Fatty's Lair also lends the Heavy skin (owner, 2026-10-18: to test the second half without taking Pearl 1 first). Fatty's Lair is one world per room (2026-10-18, [DUNGEON_ROOMS.md](DUNGEON_ROOMS.md#fattys-lair-one-world-per-room-2026-10-18)): **F6 on one of its room scenes** (`game/scenes/worlds/rooms/fatty-lair/<room>.tscn`) runs that room's world (`fatty-lair` for R1, `fatty-lair-<room>` for the others) with the Lair's powers, its `world-definition` doing the swap (`room_scene.gd` leaves it to it); `?map=fatty-lair-<room>` does the same from the web. D5 starts at its upper-west path marker (384, 384), clear of the cliff. F6 on
`game/dev/weaver-hollow-second-half.tscn` runs the Weaver Hollow's Crown that way with the Silk
skin lent too (won mid-dungeon from Pearl 2; [DUNGEONS.md](DUNGEONS.md#the-weaver-hollow-built)). Or launch with `?map=<id>` (web) / `-- --map=<id>` (desktop). `?spawn=<x>,<y>` / `-- --spawn=<x>,<y>` places the player at an old Phaser
position. `?quest=<id>[:<stage>]` / `-- --quest=<id>[:<stage>]` makes a quest active at that stage
(default the first) when the first world is built (`QuestService.debug_activate`: earlier stages
done, no rewards), to reach quest steps whose systems are not ported yet; it does not skip the
title by itself (add `map` or `skip-title`). A new run starts empty-handed (Phaser); the playground
hands out every weapon and every ability, and it never writes the autosave, so the title's Continue
never starts there (manual saves still work). `?weapon=<id>` / `-- --weapon=<id>` gives a new run that weapon (bag, belt
slot 1, hand); `?recipes` / `-- --recipes` makes every
recipe known (until quests teach them); `?arsenal` / `-- --arsenal` adds the six development weapons
at a new run ([specs/crafting.md](specs/crafting.md) C2, C3, 8.2). `?audition` / `-- --audition`
lets F8 and F7 switch the open Sound Picker round's options in the game
([specs/audio.md](specs/audio.md) §10.3). The body-shapes rework (branch `exp/body-shapes`,
[BODY_SHAPES.md](BODY_SHAPES.md)) runs **in every world and every run** (2026-10-24; the classic
game is gone from this branch), and `?shapes` / `-- --shapes` lends its shapes in any world (it and
the playground skip the title). `?prologue` / `-- --prologue`
starts a new run in the prologue, as New Game does, and skips the title. `?skins=heavy,silk,feral`
/ `-- --skins=...` lends those skins for the session in any world ([SKINS.md](SKINS.md)). In a dungeon world,
`keys=<n>`, `bigkey`, `dmap` (the map and the compass) and `room=<camera room>` (in Fatty's Lair a
room of another world: it travels there) set the dungeon up
(with `map`; [DUNGEONS.md](DUNGEONS.md#dungeon-state-no-saving-resume-at-the-entrance)), and
`sealed` starts it with its Pearl taken and its seal shut ([DUNGEONS.md](DUNGEONS.md#the-seal));
the kit's lab is `?map=dungeon-lab`.

## Doors

**No keys for transitions** (owner, 2026-10-14): the slime goes through a door, a cave mouth, a
ladder or a hole by walking or pushing into it, as through a map edge in Zelda. Nothing that
changes scene is offered to the interact key.

**A north door leads to the next scene's south door** (and back), an east door to a west door.
A door (`game/scripts/door.gd`: a Node2D in the world with a `DoorScript` child, or the hole of a
blown cracked wall) has a `side` in the Inspector: the wall it is in, which is the way the slime
pushes to go through it (`north` = walking up into it), and a `kind`:

| `kind` | What it is | Going through |
|---|---|---|
| `door` | a real door: house front doors, interior exits | the leaf swings open (`doorOpenMs` 250, `DoorOpen`), then the iris; arriving through it the leaf stands open while the slime walks out, then closes (`doorCloseMs` 250, `DoorClose`) |
| `opening` | a gap, a cave mouth, a hole in a wall | the iris at once (`use_cue`) |
| `ladder_down` | a hole with a ladder (the sinkholes) | the slime sinks and shrinks into the hole (`ladderClimbMs` 450), then the iris |
| `ladder_up` | a ladder's foot (`cave-ladder`, side north) | the slime climbs a little and fades (`ladderClimbMs`), then the iris |
| `fall` | a hole without a ladder into another scene | the slime spins and shrinks into the hole (`holeFallMs` 550, `FallDown`), then the iris. Plain pits painted on the elevation are not doors and keep their falls |

**Push to enter:** the player body's collision rect must touch the door's trigger (`walk_area`, an
Area2D, else `trigger_rect` around the door node: default (-16, -20, 32, 40)) while the movement
input points into the door for `worldNavigation.doorPushMs` (200) of simulation time: the side
within `doorPushAlignment` (0.7), or for a door without a side toward the trigger's middle
(`holePushAlignment` 0.35); in a hole any walking counts once the slime's centre is over it. Size
the trigger so the slime touches it where it stops against the wall (the level-1 mushroom door's is
taller, the house stands on a hill). A click order in the mouse schemes leans into the door the same
way (MOUSE_CONTROLS.md). **Locked doors:** fill `gate` (`id`, `requiredItemId`, `consumeOnUnlock`,
`lockedMessage`, optional `unlockedMessage`, as a world exit's lock). Without the key the push
shows the locked line once per push; with it the push unlocks the door (the key is spent,
`GateUnlock`), opens it and goes through.

**Gates are pushed too** (owner, 2026-10-15; `game/scripts/gate.gd`): no interact key. The body
within `worldNavigation.gatePushReachPx` (6) of the gate's `doors` body, the input pointing at it
(within `doorPushAlignment`) for `doorPushMs`: with the key (or its record unlocked) the gate opens
and says `unlocked_message`; without it, `locked_message` once per push. Gates opened by plates
(`open()`, this visit only) are unchanged; a bell's gate opens for good (`open_for_good()`, its
record unlocked as a key's push leaves it; owner, 2026-10-16, question 136).

**Real doors' look:** the door is painted into the house sprite. Set `house_art` (the house's
Sprite2D), `door_rect` (the painted door, relative to the door node, world units), `door_arch` (the
arch's height) and `hinge` (or `double_leaf`: two leaves hinged on the outer edges); door.gd then
builds `game/world/door_leaf.gd` under the sprite: a dark doorway over the rect and the leaf cut
from the house's own pixels, squashed toward the hinge and shaded as it swings in. A separate leaf
picture in `leaf_art_path` is drawn over the rect, closed too: the level-1 mushroom house's door
(`res://asset/MAPS/Houses/doors/mushroom-door-leaf.png`, Magnific 2026-10-14, made for the forge
and moved here; it matches the painted door's planks, straps and ring). Not imported yet, that
picture is read from the file; missing, only the dark doorway opens. The level-1 forge (the slime
home) has no door (owner, 2026-10-15): `home-door` is an `opening`, its painted fire arch shows.

**Interior ways out:** the bottom wall's door is its own picture, a Sprite2D `house-door-art` in
the room set as the door's `house_art` (the leaves are cut from it): `interior-timber-door.webp`
(two plank leaves on a sill between the door posts; slime-home, gloop-hut, `double_leaf`) and
`interior-mushroom-door.webp` (a root frame with a round-topped door; mushroom-home), packed by
`scripts/art/pack-door-art.py` (it prints the leaf rect for the scene). The sprite's position is the
picture's top edge, so the slime always draws in front of it (the door is seen from inside, like a
top-wall door in Zelda); its feet are the room's bottom edge.

When you build the scene behind a door:

- Put the paired door on the opposite wall: a cave behind a hole in a north-facing cliff gets its
  entrance as a `south` door at the bottom edge; a house you enter by walking up into its front
  door has a `north` door outside and a `south` way out at the bottom of the room.
- Point the two doors at each other: `target_area_id` = the other world's map id,
  `target_door_id` = the other door's `door_id`.
- **One-way ways in** (2026-10-17): a door with no `target_door_id` and a `target_marker` arrives at
  the Node2D of that name in the target world (any depth, snapped to its tile centre, the slime's
  facing kept), so nothing there has to lead back: the Weaver Hollow's blown Well Room floor
  (`object.cracked-floor`, a `fall` hole) drops onto a marker on a ledge in `weaver-hollow-roots`.
  A door with no `target_area_id` is an arrival point only: pushing into it never travels.
- Put the door node in the doorway: on the threshold, its feet where the opening is in the wall or
  building. Arriving there, the slime appears in the doorway facing into the room and **walks
  out** (`game/player/door_walk_out.gd`, owner 2026-10-14): it waits out the iris's black hold,
  then walks while the iris opens, at `worldNavigation.doorWalkOutSpeedShare` (1) of its walking
  speed with the walk clip and its input locked, and stops on its own once its collision rect,
  widened sideways to `doorWalkOutProbeWidthPx` (200, so the posts or walls beside an opening
  count), no longer touches the shapes it touched in the doorway, plus `doorWalkOutMarginPx` (6).
  It never walks into anything else (it stops early), and gives up after `doorWalkOutMaxPx` (160;
  0 turns the walk off). Input comes back when it stops. This holds for every door with a side, in
  both directions, the cave ladder too (the slime steps down off it).
- Leave out the `arrival` child: with the walk off, the slime arrives `arrival_step` inside the
  door (default `worldNavigation.doorArrivalStep`, 48 world units, from the door node, away from
  its wall), facing into the room; an `arrival` child, where an old door has one, still sets that
  spot; keep it on the room's ground (the level-1 mushroom house door uses `arrival_step` 20 to
  stay on its hill). With the walk on, the slime takes the elevation level of the doorway.
- A door does not travel while the slime walks out of a door, nor for
  `worldNavigation.edgeTransitionGraceMs` after it enters the tree.
- Doors travel with the Zelda iris (`game/world/iris_transition.gd`; durations
  `worldNavigation.irisCloseMs`, `irisHoldMs`, `irisOpenMs`) after their lead-in; walking off a map
  edge (world exits) keeps the fade. A sided door whose target door has another side than the
  opposite one logs a warning on arrival (doors without a side are not checked).

Example: the playground's Bomb corner hole (`game/dev/corners/bomb_corner.tscn`, `door_side`
north, kind opening, its trigger the wall's `passage`) and `playground-bomb-cave`'s `south-door`
(side south, with a `walk_area`). The house doors: level-1 `home-door` (the forge's archway) is a
`north` opening; `mushroom-home-door` (with the leaf picture) and gloop-forest `hut-door` are
`north` real doors; the slime-home, mushroom-home and gloop-hut `house-door`s are `south` real
doors with the room's door picture. The gloop and
playground sinkholes are `ladder_down` (no side, arrival child) and their cave ladders `ladder_up`
(side north).

## Input and physics

- Input actions are the snake_case of Phaser's `PlayerInputActions.ts` (removed at the cutover):
  `move_up/down/left/right`, `attack` (LMB), `interact` (RMB), `sprint` (no key since 2026-10-08:
  no sprint from the start), `jump` (no key since the jump was hidden, 2026-10-08), `dodge` (key 2: the Roll since
  2026-10-09),
  `stretch_lash`, `squash_slam`, `teleport`, `eat`, `weapon_next/previous` (wheel),
  `menu`, `map`, `zoom_in/out`, `pause`; `ability_use` (F) is captured only in the body-shapes
  rework mode, which also clears the number keys and moves the Roll to Space
  ([BODY_SHAPES.md](BODY_SHAPES.md#controls-in-the-rework-mode)).
- Physics layers keep Phaser's bits and names; the names are set in `project.godot`
  (`[layer_names]`), the only place code and scenes take them from. Layer N is bit 2^(N-1).
  (Until clean-out wave 1, 2026-10-17, `game/data/collision-layers.json` held this list too, but no
  code read it.)

  | Layer | Name | What is on it |
  |---|---|---|
  | 1 | `world` | Solid world geometry: wall tiles and StaticBody2D props (trees, houses, rocks, chests); every CharacterBody2D masks it |
  | 2 | `player` | The player CharacterBody2D |
  | 3 | `enemy` | Hostile CharacterBody2D bodies, bosses included |
  | 4 | `hurtbox` | Area2Ds that can receive damage |
  | 5 | `hitbox` | Area2Ds that deal damage |
  | 6 | `pickup-seeker` | The Area2D that collects pickups (the player's pickup radius) |
  | 7 | `pickup` | A collectible's Area2D |
  | 8 | `npc` | Friendly NPC CharacterBody2D bodies |
  | 9 | `projectile` | Projectile CharacterBody2D bodies |
  | 10 | `trigger` | World trigger Area2Ds (exits, navigation and encounter areas) |
  | 11 | `water` | Water tiles: walking bodies (player, enemies, NPCs) mask it, projectiles fly over it |
  | 12-18 | `level -3` … `level 3` | The walls of each elevation level: a walking body collides with its own level's layer only ([ELEVATION.md](ELEVATION.md)) |
  | 19 | `stairs` | The steps of every flight of stairs: every walking body but the player collides with it, so enemies and NPCs stay off stairs ([Stairs walk](ELEVATION.md#stairs-walk)) |

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
- Find a scene's node by its class (`child is LevelCollisionLayer`), never by a name: names are typed by hand in the editor and drift (a room's painted layer was named `LevelCollisionLayer` and was silently ignored). A name stays only for a node the code creates and names itself.
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
sprint and the roll (a roll sticks in a floor web), sword and worm damage, i-frames, knockback, worm death, the starter camp's
placed worms (standing at once, beaten ones back only when the chunk is built again) and the
playground pen's timed spawning (`test_camp.gd`, `test_enemy_pen.gd`), respawn, the camera follow, level-1's tiles, the water mask, draw order and water-life
clips, the Fatty One Eye fight (camp spawn and reset, hop and leap timings, landing damage, arena
leash, health bar, defeat; on the old overworld camp, put back in D4 for the tests), Fatty's Lair
(`test_fattys_lair.gd`), the ranged enemies (`test_enemy_ranged.gd`: archer arrows, projectile
lifetime, walls and hurtboxes, flee range, the four-way line-up (the archer, the line-up AI, the
spider's line-up and webs, the Spitcap's and the Pipe Worm's lines), the brawler's impact effect,
slow, knockback immunity, every world enemy type and level-1's placed camps, crystal-caverns' placed
enemies, icege's legacy spawning), the
Orb-Weaver Matron (`test_matron.gd`: nest camp and bar, spit, volley marks, landing and web
patches, no stagger, arena leash, defeat records, reset, the web barrier and its torn flag,
gloop-forest's placed camps; the Weaver Hollow's cocoon fight: clinks, the blast that tears it, the
window and the respin, three rounds, no respawn, Pearl 2's Silk skin, the full heart, her thread),
the Weaver Hollow's webs (`test_weaver_webs.gd`: floor webs halve a
walk and stick a Roll, enemies unslowed, web walls block and let the Silk slime through at half
speed, cut for good, silk parcels; [WEBS.md](WEBS.md)), the quests (`test_quests.gd`, `test_quests_gloop.gd`: new-run
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
