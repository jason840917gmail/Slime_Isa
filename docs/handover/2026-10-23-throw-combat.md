# Handover: the throw-combat branch (2026-10-23)

For the next agent working in this folder. The owner is opening a workspace here so all work on the
experiment happens in one place.

## Where things are

| | Folder | Branch | State |
|---|---|---|---|
| **This workspace** | `D:/projects/Slime isa-throw` (a git worktree) | `exp/throw-combat` | HEAD `8d557e25` when this was written (2026-10-30: `64259c9d`, eight commits on, among them the world move below), **not pushed** |
| The main checkout | `D:/projects/Slime isa` | `main` | `c3325139`, clean, 3 commits ahead of `origin/main` (not pushed) |

- The owner's Godot editor has **this** folder open (`--path "D:/projects/Slime isa-throw/godot"`).
  Before editing a scene on disk, ask him to close it in the editor (a save there writes its own copy
  back). After you change files, tell him to reload.
- `main` is already merged into this branch (last merge `8d557e25`); nothing on `main` is missing here.
- Godot console: `C:/Users/User/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`.
  This worktree has its own import cache (`godot/.godot`, copied and re-imported on 2026-10-20), so a
  headless `--import` here does not touch the main checkout's.

## What the branch is

The throw-combat experiment: the Gulp is the whole fight. Read
[docs/godot/THROW_COMBAT.md](../godot/THROW_COMBAT.md) first; it has the owner's decisions, the data
(`gulp.throwCombat` in game-constants.json), the code map (`godot/game/throw/`), the playground's throw
yard (F6 Gulp level, Shift+F6 aim help) and the open points.

Commits on the branch, oldest first:

- `7f5d62df` the experiment itself (weights and Gulp levels 1-3, material effects freeze / sleep /
  stick / shatter / pierce, shapes as Ability Box powers, no attack key, missed arrows and the
  Brawler's rocks as ammo, aim help behind a switch, the throw yard, `tests/test_throw_combat.gd`).
- `6197823d`, `ffe696ae` two freed-instance errors the owner hit in the playground.
- `e69bbd4c` keys-only scheme in this mode: **A** Gulp, **S** Roll, **D** box ability, attack has no
  key (`KeyBindings.THROW_LAYOUT`; main.gd reapplies it when the mode changes). Changed after this
  commit (2026-10-23): **Q** Gulp, **S** Roll, **A** box ability.
- `a82dfb0e` Fatty's Lair: all 28 medium and heavy liftables made light, 35 pots and rocks added so
  every enemy has two within 170 px (each room's `Throwables` node); Squint and Big Squint take
  thrown hits in the open eye; the owner's armoury fix (one divider gate with the candles' gate id,
  the chest's settings back).
- `e0e730cd` Glint Bats are awake while their dark room is not fully lit and sleep for good once
  every candle burns (the Lantern's job); bats belong only in rooms with a `DarkRoom`, so the two in
  the Lair's lit rooms (c2, r7) were removed.
- From `main`: `8d899923` (is_instance_valid before `is` in 34 checks across the game) and
  `c3325139` (the 10 rooms entered from a chunk moved into `rooms/<chunk>/`: `rooms/c4`, `d4`,
  `d5`, `c5`, `rooms/gloop-forest-e4`, `e5`; rule in docs/godot/CONVENTIONS.md).

Nothing has been played by hand by an agent; headless checks only. The suite was not run.

## The task in progress (done: `84ee5d69`, 2026-10-23)

*Updated 2026-10-30: this move is done and committed (`84ee5d69` "move the playground caves and dev
worlds out of worlds/"); the steps below are kept as the record of how.*

The owner asked (2026-10-23): move **the two playground caves into `rooms/playground/`** and **the
labs and test worlds into a dev folder**, and **leave his scratch worlds where they are** (`174`,
`236`, `cole`, `girls`, `jk`, `tiktok`, `emberleef`, `hot`, `icege`, `meadow-crossing`).

Do it **here, on `exp/throw-combat`** (the owner now works only in this folder). Suggested targets,
all under `godot/game/scenes/worlds/`:

| World | To |
|---|---|
| `playground-cavern.tscn`, `playground-bomb-cave.tscn` | `rooms/playground/` |
| `cliff-manual-tiles-lab`, `cliff-shapes-lab`, `cliff-sides-lab`, `dungeon-lab`, `fence-park`, `depth-occlusion-test`, `test-rectangle` | `dev/` |

How the last move was done (and what to fix with every move):

1. `git mv` the scene. Its **elevation cache** follows the path: `Elevation.cache_path` names it after
   the scene's path under `worlds/` with `/` turned into `__` (`rooms/playground/playground-cavern.tscn`
   -> `elevation_cache/rooms__playground__playground-cavern.res`; `dev/fence-park.tscn` ->
   `elevation_cache/dev__fence-park.res`). The cache key is the painting, not the path, so renaming
   is enough. Check which of these have a cache file first (`ls godot/game/scenes/worlds/elevation_cache`).
2. Rewrite every literal path (`scenes/worlds/<name>.tscn`, `elevation_cache/<name>.res`) in text
   files, skipping `.godot`, `.git`, `node_modules`, `export`, `output` and `docs/archive`. The script
   used last time is easy to adapt: it walks the repo and replaces exact substrings
   (`scenes/worlds/x.tscn` -> `scenes/worlds/rooms/c4/x.tscn`). Files that name these worlds today:
   - `godot/game/scenes/scene_index.json` (the paths the game loads)
   - `godot/export_presets.cfg`: the web preset's `exclude_filter` lists each dev world and its cache
     by path; after the move `game/scenes/worlds/dev/*` and `game/scenes/worlds/elevation_cache/dev__*`
     can replace the single entries (keep the scratch worlds' entries as they are)
   - `godot/game/scenes/worlds/playground.tscn`, `godot/game/dev/corners/bomb_corner.gd` and `.tscn`
   - tools that write or read them: `build_cliff_manual_prototype.gd`, `build_cliff_shapes_lab.gd`,
     `build_cliff_sides_lab.gd`, `render_cliff_sides_lab.gd`, `build_dungeon_lab.gd`,
     `render_dungeon_seal.gd`, `render_fence_park.gd`, `scripts/maps/build-fence-park.py`; check each
     for paths built from an id (`WORLDS_DIR + id + ".tscn"`, `"res://game/scenes/worlds/%s.tscn"`),
     which a text replace does not catch
   - tests: `test_weaver_bombs.gd`, `test_dungeon_kit.gd`, `test_dungeon_seal.gd`, `test_fences.gd`
   - docs: CONVENTIONS, DUNGEONS, ELEVATION, FENCES, BODY_SHAPES, ARCHITECTURE, CLIFF-MANUAL-PROTOTYPE,
     TOOLING, GAME_ROADMAP, specs/abilities, interaction, water, world-objects
   - `game-constants.json` names `dungeon-lab` by world id (`dungeon.devPowers`), which does not change
3. Load each moved world from its `scene_index.json` path headless (a throwaway `-s` script that
   `load()`s and instantiates each one) and grep again for the old paths.
4. Add the rule to docs/godot/CONVENTIONS.md next to the chunk-rooms rule (the paragraph on F6 on a
   world scene), and commit.

## Owner rules and lessons from this branch

- **Tests only when he asks** (not the suite, not filtered tests, not verify_scenes). `--check-only`
  compiles are fine; so are throwaway headless check scripts (delete them after).
- **Compile every script you edit** with `--check-only`. A constant that a parent class already has
  (`THROWN_TAG` in `PatternedEnemyScript`) breaks the subclass, and the error only shows when the
  file itself is compiled or loaded.
- **`is_instance_valid(x)` before `x is Type`**: `is` on a freed instance is a runtime error.
- **Editable Children**: switching it off on an instance drops every override of its children (the
  armoury's gate lost its `gate_id`, its chest its contents and save id). Overrides of an instance's
  child are `[node name="GateScript" parent="Objects/<gate>" index="4"]` blocks plus an
  `[editable path="Objects/<gate>"]` line at the end of the scene.
- **Windows shell**: heredocs collapse backslashes (line continuations got joined, `\n` became real
  newlines in strings). Write Python helpers to a file in the scratchpad and run them, or use the
  Edit tool.
- **Editor re-saves**: after an editor session many `.tres` files show as modified with only line
  endings changed (harmless). Check `slime_theme.tres` keeps its icons before committing it.
- Commit only what was asked; mention the owner's own uncommitted edits instead of sweeping them in.
- Reply in Spanish if he writes in Spanish (he mixes both).
