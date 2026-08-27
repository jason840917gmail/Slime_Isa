# Central Gameplay Configuration Phased Implementation Plan

## Status

Implemented and locally verified across all four phases. This architectural
program was delivered as four independently verifiable changes:

1. configuration foundation and behavior-preserving centralization;
2. mutable, persisted inventory capacity;
3. table-driven level progression and save migration;
4. Character Studio authoring for gameplay configuration.

Each phase must pass its own acceptance gate before the next phase starts. Do
not combine phases 2-4 merely because they share `game-constants.json`.

## Player and author outcome

- One validated JSON document owns shared gameplay rules and new-run defaults.
- Runtime code imports only the typed `src/game/Constant.ts` gateway.
- Invalid production configuration stops startup with a readable error instead
  of allowing partial defaults.
- New runs copy initial inventory capacity and attributes; existing saves keep
  their mutable values.
- The initial maximum level is 10. Each level owns its XP-to-next requirement
  and the stats gained upon reaching it.
- Saves store `level` and current-level `currentXp`; derived combat stats are
  recalculated from the current table.
- Character Studio edits the same JSON source without rewriting
  TypeScript or duplicating values in the player character package.

## Pre-implementation baseline

| Concern | Current owner/behavior | Target |
|---|---|---|
| Inventory capacity | `MAX_SLOTS = 24` in `systems/Inventory.ts`; not saved | JSON seeds a mutable saved capacity |
| Base item stacks | `maxStack` duplicated in `items.json` | Exact item-ID map in gameplay configuration |
| Weapon stacks | Literal `1` during inventory registry creation | Configured global weapon stack rule |
| Player attributes | Primary character package plus fallback literals | JSON seeds saved attributes |
| Movement | Primary character package | Current JSON rules apply to every run |
| Movement cap / hit i-frames | Literals in `PlayerStats.ts` | Current JSON rules |
| XP curve | Formula `round(80 * level^1.5)` | Explicit per-level table |
| HP/energy gains | Persisted accumulated bonuses | Derived from saved level and current table |
| Attack/defense | Local bases plus per-level formula | Configured bases plus summed level gains |
| Studio | Edits player fields inside `character.json` | Edits `game-constants.json` separately |

The repository currently has unrelated weapon and Character Studio work in the
working tree. Implementers must preserve those edits, inspect the latest file
state before each patch, and never replace whole Studio/plugin files from this
plan's baseline assumptions.

## Normative initial level table

The first checked-in table preserves the current XP formula and uniform stat
growth through the newly explicit level-10 cap. The `200` and `500` values in
the design discussion were shape examples, not initial balance values.

| Current level | XP to next | Max HP gain on reaching level | Energy gain | Attack gain | Defense gain |
|---:|---:|---:|---:|---:|---:|
| 1 | 80 | 0 | 0 | 0 | 0 |
| 2 | 226 | 12 | 4 | 2 | 1 |
| 3 | 416 | 12 | 4 | 2 | 1 |
| 4 | 640 | 12 | 4 | 2 | 1 |
| 5 | 894 | 12 | 4 | 2 | 1 |
| 6 | 1176 | 12 | 4 | 2 | 1 |
| 7 | 1482 | 12 | 4 | 2 | 1 |
| 8 | 1810 | 12 | 4 | 2 | 1 |
| 9 | 2160 | 12 | 4 | 2 | 1 |
| 10 | `null` | 12 | 4 | 2 | 1 |

`xpToNextLevel` belongs to the current row. `gains` belongs to reaching that
row, so level 1 has zero gains and level 10 still has the final earned gain.

## Phase 1 - Configuration foundation and behavior parity

### 1. Add the versioned source, schema, and pure validator

Add:

- `src/game/content/game-constants.json`;
- `src/game/content/game-constants.schema.json`;
- `src/game/content/GameConstantsValidation.ts`;
- `src/game/Constant.ts`;
- `scripts/check-game-constants.mjs`;
- `scripts/tests/game-constants/game-constants.test.mjs`.

The JSON contains the complete inventory and player structure from the design,
including all ten normative level rows above. The schema uses
`additionalProperties: false` at every object boundary.

`GameConstantsValidation.ts` is Phaser-free and exports:

```ts
interface GameConstantsIssue {
  readonly path: string;
  readonly message: string;
}

function validateGameConstants(value: unknown): readonly GameConstantsIssue[];
function normalizeGameConstants(value: unknown): GameConstants;
```

Validation must cover structural types, finite/nonnegative values, integer
millisecond and stack values, movement ordering, contiguous ordered level rows,
level-1 zero gains, final `xpToNextLevel: null`, and every other invariant in
the design. `normalizeGameConstants` throws one `GameConstantsValidationError`
containing all issues; it never inserts fallback balance values.

`Constant.ts` imports the JSON, validates it immediately, recursively freezes
the normalized object with `Object.freeze`, and exports it as a compile-time
`DeepReadonly<GameConstants>`. This makes “deeply readonly” both a TypeScript
and runtime guarantee. Direct JSON imports outside the gateway are forbidden.

The game must fail before `BootScene` when validation fails. The thrown error
includes the JSON path and every issue, so a production build never starts with
a partially accepted configuration.

`check-game-constants.mjs` loads the same pure TypeScript validator with the
existing esbuild-to-memory pattern. It additionally reads `items.json` and
requires exact bidirectional parity between base item keys and
`inventory.maxStackByItem` keys. Do not duplicate the structural validator in
the script.

Add `constants:check` to `package.json` and place it before content/runtime
tests in `pnpm check`.

### 2. Migrate inventory rules without changing the save shape

Update:

- `src/game/content/items/items.json`;
- `src/game/content/items/ItemCatalog.ts`;
- `src/game/systems/Inventory.ts`;
- focused collectible/inventory tests.

Remove `maxStack` from base item JSON. `ItemCatalog` clones and normalizes every
base definition with the configured limit, rejects a missing/extra ID, and
still returns complete `ItemDef` values. Weapon registration reads
`weaponMaxStack`.

Replace the local `MAX_SLOTS` literal with
`GAME_CONSTANTS.inventory.initialMaxSlots`, but keep capacity fixed for this
phase. Do not change `GameSaveData.inventory` yet. This isolates centralization
from persistence migration.

Tests prove the configured initial capacity is 24, base item stacks remain
exactly 99/9 as today, weapon stacks remain 1, unknown items still fail, and
collectible partial-transfer behavior is unchanged.

### 3. Migrate non-progression player values without touching progression

Update:

- `src/game/content/player.ts`;
- `src/game/content/initial-state/InitialRun.ts`;
- `src/game/features/player/PlayerController.ts`;
- `src/game/systems/PlayerStats.ts`;
- `src/game/content/characters/player-slime/character.json`;
- `src/game/content/characters/types.ts`;
- `src/game/content/characters/character.schema.json`;
- `src/game/content/characters/validation.ts`;
- `src/vite-env.d.ts`;
- `src/game/editor/CharacterDocumentState.ts` and `CharacterStudio.ts`;
- character, combat, and player-stat tests.

`content/player.ts` remains the adapter for the authored name/body and combines
them with the central rules. Move initial attributes, movement speeds, dodge
protection, movement cap, and hit i-frames to the gateway. Remove those local
or package copies after their consumers migrate.

Do not migrate progression runtime behavior in this phase. The complete
progression table is present and validated in the JSON so its final contract is
known, but `GameState` continues using the current formula, package progression,
saved cumulative `xp`, `maxHpBonus`, and `maxEnergyBonus` until phase 3. This is
the only temporary duplicate ownership allowed by the plan, and phase 3 must
remove it atomically with the save migration.

The primary player package removes top-level player attributes and
`player.movement`, but temporarily retains `player.progression` as the active
runtime owner. Enemy-authored attributes remain legal. Character schema,
validator, virtual declarations, package creation, normalization, and Studio
rendering must make that player/enemy distinction explicit. Until phase 4,
Studio shows a short notice that primary-player attributes and movement live in
`game-constants.json`; it keeps the existing progression fields only until
phase 3 removes their runtime ownership.

Phase 3 changes the final player package to `player: { name }`, moves base
HP/energy/attack/defense and the level table into runtime use, and removes the
temporary progression editor fields.

Update `docs/ARCHITECTURE.md` with the JSON/gateway ownership rule and add the
new configuration roadmap section without marking later phases complete.

### Phase 1 acceptance gate

- `pnpm constants:check`
- `pnpm characters:check`
- `pnpm test:characters`
- `pnpm test:combat`
- `pnpm test:collectibles`
- `pnpm typecheck`
- `pnpm build`
- `pnpm check`

No save schema, serialized field, XP, level-cap, or progression behavior changes
are allowed in phase 1. A current save must round-trip byte-equivalent gameplay
state at every currently reachable level.

## Phase 2 - Mutable persisted inventory capacity

### 4. Give inventory capacity one mutable runtime owner

Update `Inventory.ts` so each instance owns a positive integer `maxSlotsValue`
seeded from `initialMaxSlots`. Keep `maxSlots()` as the read API and add:

```ts
increaseMaxSlots(amount: number): boolean;
serialize(): InventorySaveData;
load(data: InventorySaveData): void;
```

`increaseMaxSlots` accepts only a positive integer, emits exactly one
`inventory.changed` event when capacity changes, and has no reward caller in
this phase. This phase provides persistence capability; a future reward feature
decides when to grant slots.

Existing slots whose count exceeds a newly lowered global stack limit are
grandfathered. `add` and `transact` do not add to an over-limit stack; newly
created stacks obey the current limit; removal naturally restores compliance.

### 5. Version and migrate inventory persistence

Update:

- `src/game/infrastructure/persistence/SaveSchema.ts`;
- `src/game/infrastructure/persistence/SaveRepository.ts`;
- `src/game/core/SaveSystem.ts`;
- `src/game/content/initial-state/InitialRun.ts`;
- `scripts/tests/persistence/save-schema.test.mjs`;
- `scripts/tests/persistence/save-repository.test.mjs`;
- collectible tests that construct inventory saves.

Change `GameSaveData.inventory` to:

```ts
interface InventorySaveData {
  readonly maxSlots: number;
  readonly slots: readonly InventorySlot[];
}
```

Bump the current envelope schema version once. If another in-progress feature
has advanced version 5 before this phase begins, use the next available version
and preserve every intervening migration.

Legacy arrays migrate to:

```ts
{
  maxSlots: Math.max(GAME_CONSTANTS.inventory.initialMaxSlots, slots.length),
  slots,
}
```

Reject a new-format save when `maxSlots` is not a positive integer or is less
than its occupied slot count. Migration never drops or merges items. SaveSystem
captures and installs the inventory-owned structure transactionally.

### Phase 2 acceptance gate

- new run begins with 24 slots;
- an increased capacity survives recovery and named-save round trips;
- a legacy save with more than 24 occupied slots migrates with capacity equal
  to its occupied count and loses no items;
- over-limit legacy stacks remain removable and accept no additional items;
- an invalid capacity rejects the snapshot without changing the active run;
- `pnpm test:persistence`, `pnpm test:collectibles`, `pnpm typecheck`,
  `pnpm build`, and `pnpm check` pass.

## Phase 3 - Table-driven level progression

### 6. Extract pure progression resolution

Add `src/game/systems/PlayerProgression.ts`, free of Phaser and mutable global
state. It reads a supplied progression table and exports pure operations:

```ts
function levelEntry(progression: PlayerProgressionDefinition, level: number): PlayerLevelDefinition;
function resolveLevelStats(progression: PlayerProgressionDefinition, level: number): ResolvedLevelStats;
function applyExperience(
  progression: PlayerProgressionDefinition,
  level: number,
  currentXp: number,
  amount: number,
): ExperienceResult;
```

`resolveLevelStats` adds configured base values to gains from levels 2 through
the supplied level. It returns pre-perk max HP, max energy, attack, and defense.
`PlayerStats` and `GameState` apply existing perks afterward in their current
order.

`applyExperience` requires finite, nonnegative XP, subtracts each current
level's `xpToNextLevel`, carries the remainder through multiple levels, emits
one result entry per earned level, and stops at `maxLevel`. At the configured
maximum it returns `currentXp: 0` and discards further XP without issuing
additional rewards.

### 7. Change runtime state to saved level plus current-level XP

Update:

- `src/game/core/GameState.ts`;
- `src/game/core/EventBus.ts`;
- `src/game/HUD.ts`;
- every `xp.changed` consumer;
- `src/game/content/initial-state/InitialRun.ts`;
- player-stat and progression tests.

Replace cumulative `xp`, `maxHpBonus`, and `maxEnergyBonus` with `currentXp`.
Keep `level` and saved current HP/energy. `addXp` delegates to the pure resolver,
grants one skill point and emits one `level.up` event for each crossed level,
then refills HP and energy to the final post-perk maxima. At max level the HUD
shows `MAX`.

Keep the event name `xp.changed`, but change its typed payload to:

```ts
{
  currentXp: number;
  xpToNextLevel: number | null;
  level: number;
  delta: number;
}
```

Replace the public `xp` getter with `currentXp`. Remove formula helpers and old
exports only after all consumers migrate.

### 8. Add explicit progression save migration

Add a pure migration helper under
`src/game/infrastructure/persistence/PlayerProgressionMigration.ts` and bump
both the player-state version and the outer save-envelope version once.

Before removing `maxHpBonus` and `maxEnergyBonus`, run a repository-wide audit
and retain a regression assertion that their only production writer was the
old level-up path. If another writer exists at implementation time, stop and
separate that bonus into a new saved field rather than discarding it.

Legacy migration rules are exact:

1. require saved `level` to be an integer within the configured range;
2. require legacy cumulative `xp` to be finite and nonnegative;
3. compute the old cumulative threshold with the removed formula for the saved
   level;
4. calculate `rawRemainder = legacyXp - legacyThreshold`;
5. normalize a negative remainder to `0`;
6. at max level store `currentXp: 0`;
7. otherwise clamp the remainder to
   `0..currentLevel.xpToNextLevel - 1`.

Saved level always wins during migration. Even when the raw remainder spans
one or more new table requirements, migration clamps it and never synthesizes
levels, skill points, perk choices, or refill events. A level outside the
configured table is an incompatible save error; the repository leaves the
stored snapshot and active session untouched.

On load, recalculate maxima from the saved level and current table. Clamp saved
HP/energy down only when they exceed the new maxima; do not refill during load.

Add `scripts/tests/progression/player-progression.test.mjs`, a
`test:progression` package script, and include it in `pnpm check`.

### Phase 3 acceptance gate

- every normative XP row and gain resolves exactly;
- one XP grant can cross multiple levels with the correct remainder and one
  reward per level;
- level 10 stores zero current XP and cannot reward level 11;
- changing a level gain recalculates an existing save's derived stats without
  changing its saved level/current XP;
- inconsistent legacy XP below/above its saved-level range follows the exact
  clamp rules;
- removed bonus fields are proven level-only before deletion;
- current HP/energy clamp on load and fully refill only on a real level-up;
- `pnpm test:progression`, `pnpm test:persistence`, `pnpm test:combat`,
  `pnpm typecheck`, `pnpm build`, and `pnpm check` pass.

## Phase 4 - Character Studio configuration authoring

### 9. Add a dedicated development-only content endpoint

Add `src/game/content/gameConstantsContentPlugin.ts` instead of expanding the
already large character package plugin. Register it in `vite.config.ts` next to
the existing content plugins.

Expose fixed-path GET and POST endpoints for `game-constants.json`. GET returns
the validated document plus a revision hash. POST requires the expected
revision, validates the complete submitted document with the shared validator,
returns `409` on revision conflict, writes a sibling temporary file, and
atomically renames it over the fixed target. Never accept a client-provided
filesystem path.

On validation or write failure, preserve the original file and return
field-addressable issues. Invalidate the loaded constants module after a
successful write so a development reload sees the new data. This endpoint is
available only through the Vite development plugin and is absent from the
production bundle.

### 10. Give gameplay configuration independent Studio state

Add `src/game/editor/GameConstantsStudioState.ts` with its own draft, saved
snapshot, revision, dirty flag, validation issues, conflict state, undo/redo,
and save lifecycle. Do not add configuration mutations to
`CharacterDocumentState`.

Update `CharacterStudio.ts` so the primary-player inspector loads this state
and exposes:

- initial strength, vitality, agility, and intellect;
- movement, dodge, cap, and hit-protection values;
- base HP, energy, attack, and defense;
- editable `maxLevel`;
- an ordered row per level containing XP-to-next and four gains.

Level 1 gains are read-only zero. The final row's XP is read-only `null`.
Increasing max level appends an invalid/incomplete row that blocks save until
all fields are authored. Decreasing max level shows an explicit confirmation
before deleting rows. Do not inspect browser saves or silently rewrite them.

Package Save and Gameplay Defaults Save remain separate buttons and separate
dirty/error states. A failure or conflict in one does not alter the other.
Update `src/game/editor/character-studio.css` narrowly and preserve unrelated
working-tree styling changes.

### 11. Verify Studio persistence and production isolation

Add `scripts/tests/character-studio/game-constants-authoring.test.mjs` covering:

- validated GET and deterministic POST round-trip;
- invalid document rejection without file mutation;
- stale revision conflict;
- atomic-write failure preservation;
- independent package/configuration dirty states;
- undo/redo for scalar and level-row edits;
- max-level increase/decrease behavior;
- production build contains no writable endpoint.

### Phase 4 acceptance gate

- Character Studio can edit, save, reload, and display all central player
  values;
- package JSON never regains centrally owned player fields;
- invalid configuration remains unsaved and produces readable field errors;
- runtime reload sees a successful edit and still fails fast on invalid disk
  content;
- `pnpm test:character-studio`, `pnpm constants:check`, `pnpm typecheck`,
  `pnpm build`, and `pnpm check` pass;
- manually change one level gain, reload the game, load a save at that level,
  and confirm derived stats recalculate without changing level/current XP.

## File ownership map

| Concern | Primary files |
|---|---|
| Authored gameplay values | `src/game/content/game-constants.json` and schema |
| Runtime validation/gateway | `GameConstantsValidation.ts`, `src/game/Constant.ts` |
| Repository validation | `scripts/check-game-constants.mjs` |
| Item normalization | `content/items/ItemCatalog.ts`, `systems/Inventory.ts` |
| Initial player composition | `content/player.ts`, `content/initial-state/InitialRun.ts` |
| Derived progression | `systems/PlayerProgression.ts`, `core/GameState.ts`, `systems/PlayerStats.ts` |
| Save contracts/migrations | `infrastructure/persistence/SaveSchema.ts`, `SaveRepository.ts`, `PlayerProgressionMigration.ts` |
| XP events/presentation | `core/EventBus.ts`, `HUD.ts` |
| Studio API | `content/gameConstantsContentPlugin.ts`, `vite.config.ts` |
| Studio state/UI | `editor/GameConstantsStudioState.ts`, `CharacterStudio.ts`, `character-studio.css` |
| Verification | `scripts/tests/game-constants/`, `scripts/tests/progression/`, persistence and Character Studio suites |

## Program completion matrix

| Scenario | Required result |
|---|---|
| Invalid constants in development | Checker and runtime gateway list exact paths and fail |
| Invalid constants in production | Application fails before Boot; no fallback values run |
| New run | Capacity 24, configured initial attributes, level 1/current XP 0 |
| Existing attributes | Saved values override changed initial defaults |
| Existing capacity | Saved value overrides changed initial capacity |
| Legacy inventory overflow | Capacity expands to occupied count; no item loss |
| Changed stack limit | Existing over-limit stack survives but cannot grow |
| Levels 1-9 | Exact normative XP and gain rows apply |
| Level 10 | Final gain applies, XP becomes 0, HUD shows MAX, no further reward |
| Changed gain table | Existing saved level resolves new derived stats |
| Legacy inconsistent XP | Saved level preserved; current XP follows clamp rules |
| Lowered maxima | Current HP/energy clamp without a load-time refill |
| Real level-up | HP/energy refill to final post-perk maxima |
| Studio invalid edit | Save blocked; source file and runtime revision unchanged |
| Studio conflict | Stale draft gets 409 and never overwrites newer data |

The program is complete only when all four phase gates and every matrix row
pass. Phase 1 is the safest first implementation slice and must be reviewable
without the persistence, progression, or Studio migrations from later phases.
