# Slime Isa — Agent Guide

Top-down open-world slime game: Phaser 3 + TypeScript + Vite (ES2022, ESNext modules, Bundler resolution). pnpm is required.

## Working Rules

- Work on the current branch. Do not create new branches unless the user asks for one.
- Do not run tests after every change — it wastes compute and time. Run tests (`pnpm test:*`, `pnpm test:godot`, Playwright), `pnpm build` and `pnpm check` only when the user asks, or once after a really big, breaking change. A quick `pnpm typecheck` after TypeScript edits is fine.
- Never run `pnpm scenes:regenerate`, `pnpm maps:bake`, or a `--write` map script unless the task calls for it: they overwrite authored content.
- While `pnpm dev` is running, Scene Studio saves into `src/game/content/scenes/authored/` through a dev endpoint (and `/__game-constants` can write `game-constants.json`); an open Studio tab can overwrite files you edit by hand.
- Editing a conversion input (`asset/assets.json`, `items.json`, `enemy-types.json`, `NpcDefinitions.ts`, `RecipeCatalog.ts`, `game-constants.json`) invalidates the scene conversion ledger; re-hash it, and sync its rows after adding or removing content units, as described in [docs/TOOLING.md](docs/TOOLING.md#scene-conversion).
- Keep docs truthful: when you change behavior, paths, or commands, update the doc that describes them in the same change.

## Commands

- `pnpm dev` — Vite on port 3000. Game: `http://localhost:3000`; Scene Studio (dev only): `?studio=scenes[&scene=<sceneId>]`; world preview: `?map=<id>` (including dev-only worlds such as the `playground` testbed, listed in `src/game/content/scenes/devOnlyWorlds.ts` and left out of production builds)
- `pnpm typecheck` — strict `tsc` over `src/`, `vite.config.ts`, and the Playwright specs
- Targeted checks: `scenes:check` (scene JSON), `assets:check` (`asset/assets.json`), `constants:check`, `audio:check`, `quests:check`, `scene-ownership:check`, and per-domain `visuals|characters|weapons|projectiles|effects|enemies|objects:check`
- Targeted tests: `pnpm test:<suite>` (Node `--test` suites in `scripts/tests/`, e.g. `test:combat`, `test:quests`, `test:scene-runtime`, `test:persistence`); `test:scene-browser` runs Playwright
- `pnpm build` — typecheck + production build to `dist/`
- `pnpm check` — every check, every test suite, build and Playwright; slow

Content/art/audio generators (map builders, sheet packers, audio bake, interior scenes) are documented in [docs/TOOLING.md](docs/TOOLING.md).

## Project Map

- Entry: `src/main.ts` → `src/game/config.ts`; Phaser scenes `BootScene`, `MapLoadScene`, `WorldScene` in `src/game/scenes/`
- `src/game/content/` — immutable definitions and balancing; `content/scenes/authored/` holds every authored scene (worlds, characters, objects, encounters, weapons, effects, UI, audio) edited by Scene Studio
- `src/game/features/` — feature controllers; ScriptNode behavior is registered in `features/scripts/registrations.ts`
- `src/game/runtime/scene/` — Node/SceneTree/ScriptNode contracts; `infrastructure/scenes/` and `infrastructure/phaser-nodes/` host them in Phaser
- `src/game/infrastructure/` — persistence, procedural textures, audio, map loading
- `src/game/presentation/` (UI tokens), `src/game/shared/` (small cross-feature utilities)
- `src/game/editor/scene-studio/` — Scene Studio
- Older runtime folders still in use: `core`, `systems`, `combat`, `enemies`, `ui`, `world`, `quests`, `crafting`, `dev`. New orchestration goes in `features/`
- `asset/assets.json` (+ `assets.schema.json`) — runtime media catalog with stable IDs; source art in `asset/Originals/` stays unmapped
- `scripts/` — checks, tests, generators; `tools/` is unrelated to the game build
- The game is being migrated to Godot 4.7 (milestone G): plan and phases in [docs/GODOT_MIGRATION.md](docs/GODOT_MIGRATION.md). The Godot project is `godot/` (rules: [docs/godot/CONVENTIONS.md](docs/godot/CONVENTIONS.md)); `pnpm godot:sync` copies assets into it and `pnpm godot:convert` regenerates `godot/generated/` from the scene JSON. Use Godot 4.7.2 and never hand-edit `godot/generated/`

## Architecture Rules

Full rules and rationale: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

- `WorldScene` is a composition root; keep feature implementations out of it. Feature controllers get dependencies through context interfaces and never import `WorldScene`.
- Worlds are scenes: the game loads `content/scenes/authored/worlds/<id>.scene.json` (`world.<id>`). NPCs, houses, props, walls, gates and interactions are instances in that scene JSON — never injected by code. `content/maps/*.map.json` are legacy conversion inputs (still used for new-run spawn and save validation). See [docs/AUTHORED_MAPS.md](docs/AUTHORED_MAPS.md).
- Production gameplay never invokes procedural world generation; `scripts/lib/procedural-map-generator.mjs` is tooling only.
- Cross-feature gameplay values live only in `content/game-constants.json` (+ schema; run `pnpm constants:generate` after a schema edit) and are read through `src/game/Constant.ts`. Don't add other global constants files or fallback balance literals.
- Browser storage belongs exclusively to `infrastructure/persistence/`; save through `SaveSystem` and the versioned repository.
- `assets.json` owns media-loading metadata only. Collision, animation, AI, stats and biome rules stay in TypeScript or scene JSON.
- Global events, input bindings, DOM listeners and controllers need explicit cleanup; use `DisposableBag` for scene-owned callbacks.
- Terrain is ground only and blending never changes physics; walls are placed object instances (`object.crystal-cluster-wall.*`, `object.tree-forest-wall.*`). Details: [docs/TERRAIN_TRANSITIONS.md](docs/TERRAIN_TRANSITIONS.md).

## Build Gotchas

- `tsconfig.json` includes only `src/`; strict mode also rejects unused locals/parameters and switch fallthrough.
- `vite.config.ts` must keep `base: './'` for deployed asset paths. Phaser ships as a separate vendor chunk.
- Python tools need Pillow (several also numpy).

## Status

No CI. Automated coverage is the Node test suites and Playwright specs above; interactive feel (movement, combat, visuals) still needs a manual playthrough.
