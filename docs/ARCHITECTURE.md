# Slime Isa Architecture

The Phaser game uses a feature-first architecture. A feature owns its runtime behavior and configuration; scenes only compose features and coordinate engine lifecycle.

## Dependency direction

```text
scenes -> features -> content/shared
   |          |
   +------> presentation
   +------> infrastructure
```

- `content/` contains immutable gameplay definitions and balancing values.
- `features/` contains gameplay controllers and use cases.
- `infrastructure/` owns browser storage, asset generation, and other external concerns.
- `presentation/` owns shared visual tokens and UI presentation code.
- `shared/` contains small engine-independent utilities used by multiple features.
- `scenes/` are Phaser composition roots. They create controllers, connect callbacks, forward updates, and dispose owned resources.
- Existing `systems/`, `combat/`, `enemies/`, and `ui/` folders contain reusable runtime components. New feature orchestration belongs in `features/`.

## Ownership rules

1. A gameplay rule has exactly one source of truth. Shared balancing values live in `content/`, next to the definition they configure.
2. Do not create a global `constants.ts`. Local drawing and tween values stay local; cross-feature gameplay values receive a named owner.
3. Only `infrastructure/persistence` may access `localStorage` or define storage keys.
4. Scenes must not contain storage parsing, content registries, or complete feature implementations.
5. Feature controllers receive dependencies through a context interface. They do not import `WorldScene`.
6. Every global event, keyboard handler, DOM listener, and controller must have an explicit cleanup path.
7. Persistent data is saved through the schema-versioned `SaveSystem`; migrations belong in the persistence layer.
8. UI may display state and invoke provided actions. It must not reach into unrelated scene internals.
9. Prefer typed identifiers and readonly definitions for content registries.
10. `pnpm build` must pass before changes are considered complete.

## Current composition

`WorldScene` delegates major responsibilities to:

- `PlayerController` and `PlayerFactory`
- `CombatController`
- `CrystalTrialController`
- `MapBuilder` and `MapRepository`
- `HousePlacement`
- `AreaNavigation`
- `WorldDebugRenderer`
- `SaveSystem`, `SaveRepository`, and `WorldProgress`

The remaining scene code is the migration boundary for UI composition, friend spawning, collectibles, and Phaser collision wiring. When one of those areas grows, extract its orchestration into the matching feature folder rather than adding another subsystem directly to the scene.

## Persistence

Save schema version 3 stores player state, inventory, quests, and world progress in one envelope. Player equipment now includes the active weapon ID and five persistent weapon hotbar slots. The repository reads older envelopes and split keys; missing loadout fields normalize to the starter loadout. Autosave is driven by typed domain events and is debounced.

Weapon ownership is inventory-backed. Weapon definitions are registered as unique equipment items, `WeaponLoadout` validates ownership and slot assignment, and `CombatController` replaces the active weapon gameplay/visual pair only after the loadout authorizes a switch. Plain number keys 1–5 select the five loadout slots; development cheats use Shift+1–Shift+8.

## World dimensions

`WorldDimensions` is the single geometry value for a loaded map: tile size, columns, rows, pixel width, and pixel height. `WorldScene` passes it through feature contexts to world building, physics, navigation, spawning, houses, abilities, camera, minimap, and debug rendering. Do not introduce global world-width or tile-count constants. Production dimensions always come from `dimensionsFromMap(map)`.

## Authored production maps

Every area references a required JSON map in `src/game/content/maps/`. `MapRepository` validates and lazy-loads it before `WorldScene`; `MapBuilder` creates terrain, reusable objects, behavior groups, entries, and exits. Missing production maps fail visibly instead of falling back to runtime generation.

The deterministic generator in `scripts/lib/procedural-map-generator.mjs` is tooling only. `pnpm maps:bake` can recreate the initial three production maps, but gameplay never imports the generator. Once a generated map is manually edited, do not rebake it unless replacing those edits is intentional.

## Phaser and Godot

`src/` is the Phaser/Vite application. `MobileVersion/` is an independent Godot application. They may share design documents and source art, but they must not share engine-specific runtime code.
