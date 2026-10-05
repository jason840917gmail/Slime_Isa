# Slime Isa

An open-world game built with Phaser 3, TypeScript, and Vite. Still early in development.

## Stack

- [Phaser 3](https://phaser.io/) — game engine
- TypeScript + Vite — build tooling

## Run locally

```bash
pnpm install
pnpm dev
```

Then open `http://localhost:3000`.

## Development

- `pnpm dev` starts Vite on port 3000.
- `pnpm typecheck` runs strict TypeScript validation (game, Vite config, and browser-test configs).
- Targeted checks and tests: `pnpm scenes:check`, `pnpm maps:check`, `pnpm assets:check`, `pnpm test:<suite>` (see `package.json`).
- `pnpm build` type-checks and creates the production build in `dist/`.
- `pnpm check` runs every check, all Node test suites, the build, and the Playwright browser tests (slow; use before releases or broad commits).

See [AGENTS.md](AGENTS.md) for the full command list and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for dependency rules, ownership, and persistence. Asset authors start with [docs/assets/README.md](docs/assets/README.md).

Open `http://localhost:3000/?studio=scenes` (dev server only) for Scene Studio, the editor for every authored scene: worlds, characters, weapons, objects, effects, UI, and audio, plus shared resources. It provides a scene tree, inspector, animation timeline, tile painting, undo/redo, and saves straight to `src/game/content/scenes/authored/`. Old editor URLs (including `?editor=<map>`) redirect to it. In development, `http://localhost:3000/?map=<map-id>` starts directly in a world.

## Godot Migration

The game is moving from Phaser to Godot 4.7 (GDScript). The plan, decisions and phases are in [docs/GODOT_MIGRATION.md](docs/GODOT_MIGRATION.md). The old Android prototype in `MobileVersion/` was removed on 2026-10-04; Android will be an export preset of the Godot project after Release 1.

## Status

Work in progress. Playable today: the Slimeshire Meadow level-1 world and several other areas, combat with a six-slot weapon hotbar, enemies and bosses, harvesting, crafting, quests and NPCs, house interiors, named saves, and sound effects. Gameplay tuning and visual polish are ongoing, and there is no CI.
