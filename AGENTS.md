# Slime Isa — Agent Guide

## Dev Commands

- `pnpm dev` — start Vite on port 3000
- `pnpm typecheck` — run strict TypeScript validation
- `pnpm build` — typecheck and create the production build
- `pnpm check` — run the complete local verification sequence

## Stack

- Phaser 3, TypeScript, and Vite
- ES2022 with ESNext modules and Bundler module resolution
- pnpm is required by `packageManager`

## Project Structure

- Entry point: `src/main.ts` → `src/game/config.ts`
- Phaser scene composition: `src/game/scenes/`
- Feature orchestration: `src/game/features/`
- Immutable definitions and balancing: `src/game/content/`
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
- Feature controllers receive dependencies through context interfaces and must never import `WorldScene`.
- Global events, input bindings, DOM listeners, and controllers require explicit cleanup. Use `DisposableBag` for scene-owned callbacks.
- Use the shared `terrainNoise.ts` sampling functions. Do not duplicate terrain noise logic.
- `Friend` and `House` own their sprites and physics bodies and expose entity APIs.
- Procedural textures are generated in `infrastructure/assets/ProceduralAssetScene.ts`; `scenes/BootScene.ts` is a stable scene facade.

## Build Behavior

- `tsconfig.json` includes only `src/`
- Strict TypeScript also rejects unused locals, unused parameters, and switch fallthrough
- `vite.config.ts` must retain `base: './'` for deployed asset paths
- Build output is `dist/`
- Phaser is emitted as a separate vendor chunk; large source images still need future asset optimization

## Status

There are no automated gameplay tests or CI yet. Every change must at minimum pass `pnpm build` and receive a browser smoke test when it affects scene startup or runtime wiring.
