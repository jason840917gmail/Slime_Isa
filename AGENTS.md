# Slime Isa — Agent Guide

## Dev Commands

- `pnpm dev` — start Vite on port 3000
- `pnpm typecheck` — run strict TypeScript validation
- `pnpm assets:check` — validate `asset/assets.json` against disk truth (paths, dimensions, orphans)
- `pnpm maps:check` — validate authored maps in `src/game/content/maps/` (structure, legends, instance IDs)
- `pnpm maps:bake` — regenerate the three production maps from the deterministic seed tool (overwrites those map files)
- `pnpm build` — typecheck and create the production build
- `pnpm check` — run the complete local verification sequence

## Stack

- Phaser 3, TypeScript, and Vite
- ES2022 with ESNext modules and Bundler module resolution
- pnpm is required by `packageManager`

## Project Structure

- Entry point: `src/main.ts` → `src/game/config.ts`
- Asset manifest: `asset/assets.json` (+ `assets.schema.json`) catalogs runtime/loadable media with stable IDs; source art (`asset/Originals/`) and experiments stay unmapped via `ignore` patterns
- Phaser scene composition: `src/game/scenes/`
- Feature orchestration: `src/game/features/`
- Immutable definitions and balancing: `src/game/content/`
- Authored maps: `src/game/content/maps/` (format v1 in `mapFormat.ts`; maps persist stable IDs only — terrain tile IDs, archetype IDs, enemy keys, area IDs)
- Storage and procedural assets: `src/game/infrastructure/`
- Shared UI tokens: `src/game/presentation/`
- Small cross-feature utilities: `src/game/shared/`
- Architecture rules: `docs/ARCHITECTURE.md`
- `MobileVersion/` is an independent Godot application
- `tools/` is unrelated to the game build

## Architecture Rules

- `WorldScene` is a Phaser composition root. Keep complete feature implementations out of it.
- Browser persistence belongs exclusively in `src/game/infrastructure/persistence/`; use `SaveSystem` and the versioned repository.
- Gameplay balancing values have one owner in `content/` or their owning feature. Do not create a global constants file.
- `asset/assets.json` owns media-loading metadata only (paths, frames, texture keys, editor placement hints). Collision/solidity, animations, AI, stats, and biome rules stay in TypeScript.
- Feature controllers receive dependencies through context interfaces and must never import `WorldScene`.
- Global events, input bindings, DOM listeners, and controllers require explicit cleanup. Use `DisposableBag` for scene-owned callbacks.
- Production gameplay requires authored maps and must not invoke procedural world generation. The deterministic bake source lives in `scripts/lib/procedural-map-generator.mjs` for editor/tooling use only.
- `Friend` and `House` own their sprites and physics bodies and expose entity APIs.
- Procedural textures are generated in `infrastructure/assets/ProceduralAssetScene.ts`; `scenes/BootScene.ts` is a stable scene facade.

## Build Behavior

- `tsconfig.json` includes only `src/`
- Strict TypeScript also rejects unused locals, unused parameters, and switch fallthrough
- `vite.config.ts` must retain `base: './'` for deployed asset paths
- Build output is `dist/`
- Phaser is emitted as a separate vendor chunk; large source images still need future asset optimization

## Status

There are no automated gameplay tests or CI yet.