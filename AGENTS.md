# Slime Isa — Agent Guide

Top-down open-world slime game in **Godot 4.7.2** with statically typed GDScript, Compatibility
renderer (WebGL 2), exported to the web first. The project is `godot/`. pnpm runs the test runner and
a few art tools; Python tools need Pillow (several also numpy).

The game was ported from a Phaser 3 + TypeScript app, which was removed on 2026-10-05 (the cutover in
[docs/GODOT_MIGRATION.md](docs/GODOT_MIGRATION.md)); its docs are in `docs/archive/phaser/` and
its code is in git history.

## Working Rules

- Work on the current branch. Do not create new branches unless the user asks for one.
- Do not run tests after every change — it wastes compute and time. Run `pnpm test:godot`,
  `tools/verify_scenes.gd` or a web export only when the user asks, or once after a really big,
  breaking change. A `--check-only` compile of an edited script is fine.
- Scenes, data and art are edited in the Godot project. An open Godot editor holds its own copy of
  every open scene: a "save all" there writes it back over files changed on disk, so reload changed
  scenes in the editor (or close them) before saving.
- Avoid headless `--import` runs while someone has the editor open (they share the import cache).
- Commit the `*.import` and `*.gd.uid` files Godot creates next to assets and scripts.
- Keep docs truthful: when you change behavior, paths, or commands, update the doc that describes
  them in the same change.

## Commands

- Godot editor: open `godot/` in Godot 4.7.2. F5 runs the title screen; `game/dev/playground.tscn`
  with F6 runs the playground testbed (every weapon and ability); F6 on a world scene runs the game
  in that world.
- Launch options: `?map=<world id>`, `?spawn=<x>,<y>`, `?weapon=<id>`, `?quest=<id>[:<stage>]`,
  `?recipes`, `?arsenal` on the web; `-- --map=<id> ...` on desktop
  ([docs/godot/CONVENTIONS.md](docs/godot/CONVENTIONS.md#running-a-world)).
- `pnpm test:godot [-- --filter=<text>]` — the headless integration tests in `godot/tests/`
  (about ten minutes for the full suite).
- `"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/verify_scenes.gd` — loads every
  scene in `godot/game/scenes/scene_index.json` and plays level-1.
- Web build: `"<Godot console exe>" --headless --path godot --export-release "Web" export/web/index.html`
  (the "Web (dev)" preset keeps the dev worlds); `.claude/launch.json` "godot-web" serves it on port 3200.
- Art tools (`pnpm items:pack`, `grounds:pack`, `props:pack`, `audio:bake` and the Python scripts in
  `scripts/`) turn sources in `asset/Originals/` into runtime sheets in `godot/asset/`:
  [docs/TOOLING.md](docs/TOOLING.md).

## Project Map

- `godot/project.godot` — settings, input map, physics layer names, autoloads.
- `godot/game/main.tscn` — the world bootstrap; `game/shell/title.tscn` is the main scene.
- `godot/game/autoload/` — `WorldService`, `RunState` (the run and saves), `GameConstants` (data)
  and `SimClock`; the other autoloads (`DamageRouter`, `GameFeel`, `MusicDirector`, `Shell`) live
  with their areas. Reach every autoload through `res://game/shared/services.gd`.
- `godot/game/scenes/` — every world, object, character, weapon, effect, projectile and encounter
  scene, with `scene_index.json` (scene id → path; add a line for a scene the game loads by id).
- `godot/game/data/` — game constants, items, enemy types, recipes, quests, NPC definitions,
  weapons and item icons (JSON read through `GameConstants`).
- `godot/game/scripts/` — scene scripts (`game.<id>` → `<snake_id>.gd`); the rest of `godot/game/`
  holds gameplay, UI, shell, audio and world systems by area.
- `godot/asset/` — runtime art and audio (`res://asset/...`); `asset/Originals/` (sources and
  concepts) and `asset/project/` (sprite-sheet projects) stay outside the Godot project.
- `godot/tools/` — headless tools (scene verifier, clip and theme builders, labs);
  `godot/tests/` — the test suite; `godot/addons/godot_ai/` — the editor plugin (MCP bridge).
- `scripts/` — art and audio tools and the test runner; `tools/` is unrelated to the game build.

## Architecture Rules

How the game is built: [docs/godot/ARCHITECTURE.md](docs/godot/ARCHITECTURE.md); project rules:
[docs/godot/CONVENTIONS.md](docs/godot/CONVENTIONS.md); the exact behaviour each area reproduces:
[docs/godot/specs/](docs/godot/specs/).

- Static typing everywhere, tabs, snake_case, one class per file; reference scripts with `preload`.
- Autoloads only through `Services` (`Services.world()`, `.run()`, `.constants()`, `.now_ms()`, ...).
- One gameplay clock: `Services.now_ms()`; real time only for presentation.
- Bodies move only through their own scene script with `ArcadeMover.move(body, delta)`, never
  `move_and_slide()`.
- Gameplay values come from `godot/game/data/game-constants.json` or scene properties, never new
  literals.
- Worlds are scenes: NPCs, houses, props, walls, gates and interactions are instances in the world
  scene; the player and enemies are spawned by code.
- Terrain is ground only; transitions between grounds are hand-made edge tiles
  ([docs/godot/TERRAIN_LAB.md](docs/godot/TERRAIN_LAB.md)); walls are placed object instances.
- Hills, holes and stairs are painted on a world's `elevation` layer; cliffs, their lips and feet
  and each level's collision follow ([docs/godot/ELEVATION.md](docs/godot/ELEVATION.md)).
- Saves go through `RunState` to `user://saves/`.

## Status

No CI. Automated coverage is `pnpm test:godot` and `tools/verify_scenes.gd`; interactive feel
(movement, combat, visuals) still needs a manual playthrough.
