# Slime Isa Architecture

The Phaser game uses a feature-first architecture on top of a Godot-style scene tree. A feature owns its runtime behavior and configuration; Phaser scenes only compose features and coordinate engine lifecycle.

## Dependency direction

```text
scenes -> features -> content/shared
   |          |
   +------> presentation
   +------> infrastructure
```

Folders under `src/game/`:

- `content/` — immutable definitions and balancing: `game-constants.json`, authored scene documents (`content/scenes/authored/`), map conversion inputs (`content/maps/`), item/weapon/character/effect/object catalogs, quests, recipes, terrain.
- `features/` — gameplay controllers and use cases, including every ScriptNode behavior in `features/scripts/`.
- `runtime/scene/` — engine-independent Node, SceneTree, ScriptNode, signals, animation, and scene-instantiation contracts.
- `infrastructure/` — Phaser node implementations (`phaser-nodes/`), the scene host and loaders (`scenes/`), map loading, audio, asset loading/procedural textures, and browser persistence.
- `presentation/` — shared visual tokens, depth, camera, and UI skin.
- `shared/` — small engine-independent utilities (`animation/`, `lifecycle/`, collision shapes).
- `scenes/` — Phaser composition roots: `BootScene` (facade for `infrastructure/assets/ProceduralAssetScene`), `MapLoadScene`, `WorldScene`.
- `editor/` — dev-only Scene Studio (`editor/scene-studio/`).
- Older reusable-component folders still in use: `core/` (EventBus, GameState, SaveSystem), `systems/` (inventory, stats, loadout), `combat/`, `enemies/`, `ui/`, `world/` (Area, Biome, WorldDimensions), `quests/`, `crafting/`, `dev/` (debug renderers). New feature orchestration belongs in `features/`.

## Ownership rules

1. A gameplay rule has exactly one source of truth. Shared balancing values live in `content/`, next to the definition they configure.
2. `content/game-constants.json` is the only authored source of cross-feature gameplay values and new-run defaults (see below). Local drawing and tween values stay local.
3. Only `infrastructure/persistence` may access `localStorage` or define storage keys.
4. Scenes must not contain storage parsing, content registries, or complete feature implementations.
5. Feature controllers receive dependencies through a context interface. They do not import `WorldScene`.
6. Every global event, keyboard handler, DOM listener, and controller must have an explicit cleanup path.
7. Persistent data is saved through the schema-versioned `SaveSystem`; migrations belong in the persistence layer.
8. UI may display state and invoke provided actions. It must not reach into unrelated scene internals.
9. Prefer typed identifiers and readonly definitions for content registries.
10. Verify a change with `pnpm typecheck` plus the targeted checks/tests for the area changed (for example `pnpm scenes:check`, `pnpm maps:check`, or the matching `pnpm test:*` suite). Run the full `pnpm build` / `pnpm check` only when asked, or before a release or a commit of broad changes.

## Gameplay configuration

`content/game-constants.json` owns inventory capacity and stack rules, initial player attributes, movement speeds and cap, dodge and hit protection, the player's base stats and Goo Heart bonus, world-navigation timing, sleep regeneration, the Gulp form duration, and the ordered `resources.tags` harvesting catalog. `game-constants.schema.json` owns the structural contract and generates both TypeScript types and a standalone validator; `GameConstantsValidation.ts` adds only cross-field invariants. Runtime code imports the validated, deeply readonly `GAME_CONSTANTS` and its types through `src/game/Constant.ts`; direct runtime JSON imports, duplicate hand-written interfaces, and fallback balance literals are forbidden.

After a schema edit run `pnpm constants:generate`; `pnpm constants:check` rejects stale generated code. In development Vite stays available when the document is invalid so it can be repaired (a dev endpoint, `/__game-constants`, serves and saves it), while gameplay fails before `BootScene`. Production builds reject invalid constants.

Harvest capability and requirement fields persist stable IDs from the closed `resources.tags` catalog. Damage-modifier tags are a separate open domain. Character packages own identity, body, and visuals, not player attributes or stats; enemy packages may own their own stats.

## Scene tree and Scene Studio

`UniversalSceneWorldController` mounts world, entity, UI, and audio SceneTrees. A ScriptNode stores a registered script ID and data only; behavior is registered in `features/scripts/registrations.ts` and reaches domain services through typed ports. The Phaser host performs one Arcade step for scene-owned bodies and areas; authored circles, capsules, and polygons are approximated with Arcade-compatible shapes, not pixel-perfect collision. Persistent world populations come only from authored world scenes; Phaser scenes must not add hidden NPCs, houses, puzzles, or props.

Scene Studio (`?studio=scenes`, dev server only) creates and edits authored scene documents and resources with a shared inspector, undo/redo, and hash-checked saves written through the dev-only `/__scene-studio/content` Vite endpoint. Legacy editor URLs (`?studio=characters|weapons|projectiles|animations`, `?editor=<map>`) redirect into it. `scripts/check-scene-ownership.mjs` rejects retired editor and construction paths.

Resources follow Godot's sub-resource convention: a collision shape, sprite sheet, animation library, or tile layer used by one scene lives in that scene's `subresources`. Only data shared by several scenes is a standalone `*.resource.json` (the UI theme and the project terrain TileSet `terrain.tiles`). Images and audio stay in `asset/assets.json`.

## Animation ownership

`shared/animation` owns timeline timing, layered visual documents, frame resolution, and playback order; domain adapters select content and a world anchor but do not copy the clock or renderer. Each character, weapon, effect, and animated object embeds its animation library in its own `AnimationPlayer` node (`runtime/scene/animation/`). Scene Studio's animation dock (`editor/scene-studio/animation/`) is the only animation editor; it keeps a weapon script's `attackPlans` in step with the clips they name. Three frozen tree clips used by the object converter remain under `scripts/migrations/frozen-sources/animations/`.

Weapon hitbox activation is a weapon-owned track on the same clock. Contact visuals live in `content/effects`; enemy feedback uses weapon `onHitEffectId`, resource nodes use material `hitEffectId`, and both fire only after confirmed positive damage. Weapon packages in `content/weapons/` are still read at runtime by the item registry and loadout alongside the authored weapon scenes.

## Current composition

`WorldScene` delegates to `PlayerController`, `UniversalSceneWorldController`, `CombatController`, `ResourceNodeController`, collectible/occlusion/interaction controllers, `WorldDebugRenderer`, and the `saveSystem`/`worldProgress` singletons. `MapLoadScene` resolves the destination through `AreaNavigation` and `WorldSceneLoader` before `WorldScene` starts. Terrain is drawn by `TileMapLayer2D` nodes in the world scene. `WorldScene` still owns camera/input coordination, domain services, and the host boundary.

## Worlds and maps

Each world is an authored scene `content/scenes/authored/worlds/<map-id>.scene.json` (scene ID `world.<map-id>`) containing a `game.world-definition` script and its tile layers. `WorldSceneLoader` resolves it before the active scene changes; a missing world fails visibly. `content/maps/<map-id>.map.json` (format v1, `mapFormat.ts`) are the conversion inputs the world scenes were produced from; `MapRepository` still validates them (e.g. a saved location's map on load) and `maps:check` checks them.

`scripts/lib/procedural-map-generator.mjs` is tooling only; gameplay never imports it. `pnpm maps:bake` rewrites only `gloop-forest.map.json` and `crystal-caverns.map.json`.

## World dimensions

`WorldDimensions` (`world/WorldDimensions.ts`) is the single geometry value for a loaded map: tile size, columns, rows, pixel width, and pixel height, always built by `dimensionsFromMap(map)`. It is passed through feature contexts; do not introduce global world-size constants.

## Persistence

Save schema version 10 (`infrastructure/persistence/SaveSchema.ts`) stores player state, inventory, quests, location, world progress, story, and play time in one envelope, with multiple named saves plus a debounced recovery autosave driven by typed domain events. `SaveRepository` migrates older envelopes and legacy split keys. Players see the named saves as three slots ("Slot 1"–"Slot 3") and the autosave as Continue; the Load window (title, pause menu, defeat screen) lists the autosave first, then the slots, and a slot whose save cannot be read shows why instead of "Empty". Quest states from an older build are fitted to the current catalog before they load (`infrastructure/persistence/quests/QuestStateRepair.ts`), a save that still cannot be installed returns to the title with the reason, and the autosave never records a defeated slime.

Per-device preferences (sound mix, screen shake, reduce motion) are not part of a run: `features/settings/GameSettingsService` (`gameSettings`) loads them through `infrastructure/persistence/GameSettingsStore` and is the one place gameplay reads them. Screen shake and hit-stop go through `features/feel/` (`gameFeel`, named presets scaled by those settings); never call `cameras.main.shake` directly. Squash and stretch, pooled particle presets (`particleFx`) and the goo trail live there too.

## Game shell

`features/shell/` owns the frame around play: the title screen (the first world of a page load runs in title mode: paused, no player or HUD, nothing autosaved), the pause menu (Esc), settings and controls, save slots, game over, credits, and end cards. Each menu is a `MenuSurface` presented by one authored `ui.*` scene; `GameShell` composes them and `WorldScene` supplies the actions. First-time control hints live in `features/hints/`.

Weapon ownership is inventory-backed: `WeaponLoadout` validates ownership and the four persistent belt slots (`WEAPON_HOTBAR_SLOT_COUNT`; older six- and three-slot saves are fitted by `core/WeaponSlots.ts`), and `CombatController` swaps the active weapon only after the loadout authorizes it. The mouse wheel cycles the filled slots, a click on a slot holds it, and the bag's belt row takes weapons dragged from the bag (`ItemList` `dropTarget` and its `item_dropped` signal). The weapon in hand always swings, at trees and rocks too (playtest 2026-10-01); a node it cannot harvest says where the right tool is (`features/combat/HarvestAdvice.ts`). Every player control is bound in one table, `features/player/PlayerInputActions.ts`, and every key label comes from `ControlLabels.ts`; development cheats are buttons on the dev panel (`dev.cheat`), never keys.

## Verification scope

Deterministic checks and browser fixtures verify specific contracts, but only a user playthrough can accept movement, combat, interaction, and visual quality.

## Phaser and Godot

`src/` is the Phaser/Vite application. `MobileVersion/` is an independent Godot application. They may share design documents and source art, but not engine-specific runtime code.
