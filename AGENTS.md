# Slime Isa — OpenCode Agent Guide

## Dev Commands
- `pnpm dev` — start Vite dev server (port 3000)
- `pnpm build` — typecheck + production build

## Stack
- Phaser 3 + TypeScript + Vite
- Strict TypeScript (`strict: true` in tsconfig)
- ES2022, ESNext modules, Bundler module resolution
- pnpm required (enforced via `packageManager` in package.json)

## Project Structure
- Entry point: `src/main.ts` → `src/game/config.ts`
- Game scenes: `src/game/scenes/`
- Shared systems extracted into `src/game/` root: `Minimap.ts`, `HUD.ts`, `ShopUI.ts`, `terrainNoise.ts`
- `tools/` is a standalone utility, unrelated to the game build

## Architecture Notes
- `WorldScene` is the main scene (~887 lines). Major systems (minimap, HUD, shop) are extracted but still have references through scene callbacks. For large scale-up, extract `HouseUI` and `EnterPrompt` similarly.
- `terrainNoise.ts` — single shared `sample()` function used by both `worldTiles.ts` and `WorldScene`. **Do not duplicate** — use this module.
- `Friend` and `House` are entity classes in `src/game/`. They hold their own sprites/physics bodies and expose clean APIs.
- All game textures (terrain, props, NPC parts) are generated procedurally in `BootScene.createTerrainTextures()`. No external asset loading for base tiles.

## Build Behavior
- `tsconfig.json` includes only `src/` — no type checking outside it
- `vite.config.ts` sets `base: './'` (important for asset paths in deployed builds)
- Build output to `dist/`
- Asset chunk is large (2.7 MB PNG); code-splitting will be needed as more art is added

## Status
No tests, no linting, no CI. The `build` script runs `tsc --noEmit` as the typecheck step.