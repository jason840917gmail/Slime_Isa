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
- `runtime/scene/` owns the common Node, SceneTree, ScriptNode, and scene-instantiation contracts. `infrastructure/scenes/` connects that tree to Phaser; authored scene documents and resources live under `content/scenes/authored/`.
- Existing `systems/`, `combat/`, `enemies/`, and `ui/` folders contain reusable runtime components. New feature orchestration belongs in `features/`.

## Ownership rules

1. A gameplay rule has exactly one source of truth. Shared balancing values live in `content/`, next to the definition they configure.
2. `content/game-constants.json` is the only authored source of cross-feature gameplay values and new-run defaults. `game-constants.schema.json` owns their structural contract and generates both TypeScript types and a standalone validator; `GameConstantsValidation.ts` adds only cross-field invariants. Runtime code imports the validated, deeply readonly `GAME_CONSTANTS` value and its re-exported types through `game/Constant.ts`; direct runtime JSON imports, hand-written duplicate property interfaces, and fallback balance literals are forbidden. Local drawing and tween values stay local.
3. Only `infrastructure/persistence` may access `localStorage` or define storage keys.
4. Scenes must not contain storage parsing, content registries, or complete feature implementations.
5. Feature controllers receive dependencies through a context interface. They do not import `WorldScene`.
6. Every global event, keyboard handler, DOM listener, and controller must have an explicit cleanup path.
7. Persistent data is saved through the schema-versioned `SaveSystem`; migrations belong in the persistence layer.
8. UI may display state and invoke provided actions. It must not reach into unrelated scene internals.
9. Prefer typed identifiers and readonly definitions for content registries.
10. `pnpm build` must pass before changes are considered complete.

## Gameplay configuration

The versioned gameplay constants document currently owns inventory capacity and stack rules, initial player attributes, movement speeds and cap, dodge protection, hit protection, world-navigation timing, and the ordered `resources.tags` harvesting catalog. Changing an authored value requires changing only that JSON document. Adding a structurally independent property requires adding it to the JSON and schema, while TypeScript validation changes only when the property participates in a cross-field invariant. Harvest capability and requirement fields persist stable string IDs from that closed catalog; editors, save endpoints, and repository checks reject unknown values. Damage-modifier tags remain an independent open domain because they also classify enemies and other combat targets. New runs copy initial attributes, while movement and protection remain current global rules. Base item definitions omit stack limits and are normalized against the exact configured item-ID map; weapon items use the configured global weapon stack limit.

After a schema edit, run `pnpm constants:generate`; `constants:check` rejects stale generated types or validation code. Development keeps Vite available when the document is invalid so it can be repaired, while gameplay still fails before `BootScene`. Production builds reject invalid constants.

The primary character package owns authored identity, body, and visuals. It must not contain primary-player attributes, movement, or progression rules. Gameplay constants own the primary-player progression table; runtime XP uses that table, saves persist level plus current XP, and legacy cumulative XP is migrated without granting synthetic rewards. Enemy packages may continue to own their attributes and per-entity gameplay values.

## Shared animation ownership

`shared/animation` owns timeline timing, layered visual documents, frame resolution, and playback order. Domain adapters for characters, enemies, weapons, projectiles, and effects may select content and provide a world anchor, but must not copy the clock, renderer, transform composition, or layered timeline editor. Every visual layer and combat/event track for one animation consumes the same master frame. Shared animation packages are authored external resources in Scene Studio. Their original packages remain frozen conversion inputs for hash and identity checks.

Weapon definitions version 2 store Idle and directional Attack animations as layered documents. Hitbox activation remains a weapon-owned directional track on that same clock. Reusable contact visuals live in `content/effects`; enemy feedback uses weapon `onHitEffectId`, while resource nodes own material `hitEffectId` feedback dispatched only after positive damage. Confirmed effects start at the damaged object's `x`/`y` anchor, follow its world-sort depth with a fixed front offset while it remains active, and freeze at the last valid position if the target is destroyed. Timeline events must never synthesize weapon impact effects or bypass confirmed damage. Authored weapon scenes now own the mounted combat composition; old packages remain checked conversion inputs until their consumers and writers are retired.

## Current composition

`WorldScene` delegates major responsibilities to:

- `PlayerController` and `UniversalSceneWorldController`
- `CombatController`
- `MapRepository`, `TileFactory`, and the authored world SceneTree
- `AreaNavigation`
- `WorldDebugRenderer`
- `SaveSystem`, `SaveRepository`, and `WorldProgress`

`UniversalSceneWorldController` mounts world, entity, UI, and audio SceneTrees. A ScriptNode contains feature behavior registered through `features/scripts/registrations.ts`; it obtains domain services through typed ports instead of importing `WorldScene`. The Phaser host performs one Arcade step for scene-owned bodies and areas. Blocking bodies and overlap sensors are distinct; area shape approximation follows the documented Phaser geometry limits. Persistent world populations come only from authored map JSON; scenes must not add hidden NPCs, houses, puzzles, or props. `WorldScene` still owns terrain rendering, camera/input coordination, domain services, and the host boundary.

Scene Studio (`?studio=scenes`) creates and edits authored scene documents and external resources with common property descriptors, undo/redo, hash-checked saves, and preview isolation. Select a scene or resource in the project explorer, edit its properties, and save; legacy category URLs redirect to the corresponding Scene Studio context. Runtime instances carry source provenance and reversible local overrides, so editing one instance does not mutate its packed source. ScriptNode documents store a registered script ID and data only; executable behavior lives in `features/scripts/`. Keep source-hash-audited conversion inputs and frozen fixtures for repeatability. `scripts/check-scene-ownership.mjs` rejects retired editor and construction paths. The object catalog remains a read-only map/save compatibility validator; NPC identity and placement definitions remain project data. Neither is an alternate writable editor.

Scene-owned collisions use Phaser Arcade bodies and area sensors. The host approximates authored circles, capsules, and polygons with Arcade-compatible shapes where needed; authored geometry is not a promise of pixel-perfect narrow-phase collision. Static blockers are grouped, and the managed tree owns explicit teardown of bodies, timers, subscriptions, and Phaser objects.

Only user gameplay acceptance can close the interactive movement, combat, interaction, and visual-quality checklist. Deterministic editor contracts and browser fixtures verify specific behavior, but cannot substitute for that playthrough.

## Persistence

Save schema version 4 stores player state, inventory, quests, and world progress in one envelope. Player equipment includes the active weapon ID and six persistent weapon hotbar slots. The repository reads older envelopes and split keys, drops retired population fields, and normalizes missing loadout fields to the starter loadout. Autosave is driven by typed domain events and is debounced.

Weapon ownership is inventory-backed. Weapon definitions are registered as unique equipment items, `WeaponLoadout` validates ownership and slot assignment, and `CombatController` replaces the active weapon gameplay/visual pair only after the loadout authorizes a switch. Plain number keys 1–6 select the six loadout slots; development cheats use Shift+1–Shift+8.

## World dimensions

`WorldDimensions` is the single geometry value for a loaded map: tile size, columns, rows, pixel width, and pixel height. `WorldScene` passes it through feature contexts to world building, physics, navigation, spawning, abilities, camera, minimap, and debug rendering. Do not introduce global world-width or tile-count constants. Production dimensions always come from `dimensionsFromMap(map)`.

## Authored production maps

Every area references a required JSON map in `src/game/content/maps/`. `MapRepository` validates and lazy-loads it before `WorldScene`; the authored world SceneTree creates reusable objects, populations, and interactions while `TileFactory` renders the terrain layer. Missing production maps fail visibly instead of falling back to runtime generation.

The deterministic generator in `scripts/lib/procedural-map-generator.mjs` is tooling only. `pnpm maps:bake` can recreate the initial three production maps, but gameplay never imports the generator. Once a generated map is manually edited, do not rebake it unless replacing those edits is intentional.

## Phaser and Godot

`src/` is the Phaser/Vite application. `MobileVersion/` is an independent Godot application. They may share design documents and source art, but they must not share engine-specific runtime code.
