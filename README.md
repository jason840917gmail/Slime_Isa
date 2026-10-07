# Slime Isa

A top-down open-world slime adventure built with [Godot 4.7](https://godotengine.org/) (GDScript),
released first as a web build. Still early in development.

## Run it

1. Install Godot **4.7.2** (the standard GDScript build).
2. Open the `godot/` folder in Godot and press **F5**: the title screen starts.
3. To try mechanics, open `godot/game/dev/playground.tscn` and press **F6** (every weapon and ability).

Web build: export the "Web" preset (`--headless --path godot --export-release "Web" export/web/index.html`)
and serve `godot/export/web/`.

## Development

- `pnpm install` once, then `pnpm test:godot` runs the headless integration tests (`GODOT` points at
  the Godot 4.7.2 console executable when it is not in the default place).
- Scenes (`godot/game/scenes/`), game data (`godot/game/data/`) and art (`godot/asset/`) are edited
  in the Godot project; source art lives in `asset/Originals/`, and the art tools in `scripts/` turn
  it into runtime sheets ([docs/TOOLING.md](docs/TOOLING.md)).

See [AGENTS.md](AGENTS.md) for commands, structure and rules, [docs/godot/](docs/godot/CONVENTIONS.md)
for how the game is built, and [docs/assets/README.md](docs/assets/README.md) for making art.

## History

The game began as a Phaser 3 + TypeScript + Vite app with its own scene editor (Scene Studio). It
moved to Godot in October 2026 ([docs/GODOT_MIGRATION.md](docs/GODOT_MIGRATION.md)); the Phaser app
was removed at the cutover, and its docs are kept in [docs/archive/phaser/](docs/archive/phaser/).
Android will be an export preset of the Godot project after Release 1.

## Status

Work in progress. Playable today: the Slimeshire Meadow level-1 world and several other areas, combat
with a weapon belt, enemies and bosses, harvesting, crafting, quests and NPCs, house interiors, named
saves, music and sound effects. Gameplay tuning and visual polish are ongoing, and there is no CI.
