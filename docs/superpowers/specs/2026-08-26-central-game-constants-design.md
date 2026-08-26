# Central Gameplay Constants Design

## Status

Approved design. Implementation is intentionally staged so the first change
does not turn every local rendering or animation literal into a global
dependency.

## Goal

Create `src/game/Constant.ts` as the authoritative edit point for tunable
runtime gameplay values. The first migration covers inventory capacity and
stack limits plus the primary player's movement and progression tuning. Later
domains can be migrated through the roadmap without changing the ownership
model again.

## Ownership decision

`Constant.ts` owns shared, tunable gameplay numbers used by runtime systems.
Content files continue to own identity and authored data that varies by item,
character, enemy, object, map instance, or visual package. In particular:

- `Constant.ts` owns the player's shared runtime defaults and inventory rules.
- Item JSON keeps IDs, names, categories, icons, and descriptions. Runtime
  `ItemDef.maxStack` is populated from `Constant.ts`.
- The primary player character package keeps its name, body geometry, visual
  references, and animation tracks. Its movement and progression values move
  to `Constant.ts`.
- Enemy-specific AI, combat, drop tables, resource quantities, map placement,
  animation timing, collision geometry, and UI/layout values remain in their
  current owning content or feature modules. They are not duplicated as
  global defaults merely because they are numeric.

The architecture documentation will replace the existing prohibition on a
global constants file with this narrower ownership rule.

## Constant shape

The module exports one readonly nested object so a developer can find values
by domain without maintaining several competing configuration modules:

```ts
export const GAME_CONSTANTS = {
  inventory: {
    maxSlots: 24,
    maxStackByItem: {
      wood: 99,
      stone: 99,
      'iron-ore': 99,
      charcoal: 99,
      'hp-potion': 9,
      'energy-potion': 9,
      'purple-berry-mat': 99,
      'silk-clump': 99,
      shard: 99,
    },
    weaponMaxStack: 1,
  },
  character: {
    player: {
      attributes: { strength: 10, vitality: 10, agility: 10, intellect: 10 },
      movement: {
        baseSpeed: 240,
        boostSpeed: 360,
        dodgeSpeed: 420,
        dodgeInvulnerabilityMs: 400,
      },
      progression: {
        baseMaxHp: 100,
        baseMaxEnergy: 100,
        hpPerLevel: 12,
        attackPerLevel: 2,
        defensePerLevel: 1,
        energyPerLevel: 4,
      },
      movementSpeedCap: 480,
      hitInvulnerabilityMs: 500,
    },
  },
} as const;
```

Item IDs remain the keys in `maxStackByItem`; this avoids a second translation
layer between content and runtime. The object is readonly at the TypeScript
boundary and consumers do not mutate it at runtime.

## Runtime integration

The first implementation will make these consumers read the central values:

1. `systems/Inventory.ts` uses `inventory.maxSlots` and the weapon stack
   default instead of a local slot constant.
2. `content/items/ItemCatalog.ts` normalizes base item definitions with the
   configured per-item stack limits. Missing configured IDs fail during the
   catalog boundary instead of silently falling back to a second value.
3. `content/player.ts` becomes a compatibility/composition adapter for the
   primary player's name and body while movement, progression, and default
   attributes come from `GAME_CONSTANTS`.
4. `features/player/PlayerController.ts`, `systems/PlayerStats.ts`,
   `core/GameState.ts`, and `content/initial-state/InitialRun.ts` consume the
   central player values.
5. The player character schema/types and Character Studio player gameplay
   fields stop treating movement/progression as editable package data. The
   package retains the player name and authored visual/physical data.

No save schema migration is required: inventory saves store item IDs and
counts, while the constants are runtime configuration rather than player
state. Existing saves continue to load using the current item IDs.

## Migration rules for future domains

- Move a number only when it is a tunable gameplay rule shared across runtime
  consumers or intentionally controlled from one central balance surface.
- Give each domain a nested section (`combat`, `abilities`, `resources`, or
  similar) and keep units explicit in names such as `CooldownMs`, `Speed`, or
  `MaxCount` where ambiguity is possible.
- Remove the old literal or local export after consumers migrate; do not keep
  fallback copies.
- Keep per-entity authored values in content. A global value may be a default
  only when the runtime contract explicitly defines a default and its owner.
- Do not move UI dimensions, colors, animation frame data, storage keys, map
  geometry, or editor-only limits into this gameplay module.

## Validation and tests

The first migration will verify:

- TypeScript compilation and production build remain green.
- Inventory tests cover configured slot capacity, stacking, unknown IDs, and
  weapon stack behavior.
- The existing collectible tests still cover full, partial, and exact
  remaining-quantity transfers while reading the configured inventory rules.
- Player stat and movement tests assert that changing the central values
  changes the resolved runtime values without changing save data shape.
- A constants/content validator or equivalent catalog assertion detects a base
  item without a configured stack limit and detects stale player gameplay
  fields that would create a duplicate source of truth.
- `pnpm check` includes the constants validation once that checker exists.

## Roadmap placement

Add a new **Cross-Cutting Gameplay Configuration** section after Cross-Cutting
Persistence in `docs/GAME_ROADMAP.md`:

### [ ] C.1 — Define central gameplay constants ownership

Document the `Constant.ts` contract, domain boundaries, naming/unit rules, and
the distinction between centralized runtime tuning and authored content.

### [ ] C.2 — Centralize inventory tuning

Move inventory capacity, item stack limits, and weapon stack behavior to the
inventory section; update catalog normalization, inventory consumers, tests,
and the collectible verification matrix.

### [ ] C.3 — Centralize player character tuning

Move primary-player attributes, movement speeds, dodge protection,
progression growth, movement cap, and hit invulnerability to the character
section; remove duplicate player gameplay ownership from the character
package/editor.

### [ ] C.4 — Migrate remaining shared gameplay defaults by domain

Move remaining cross-feature balance literals in focused slices, preserving
feature ownership and per-entity authored values.

### [ ] C.5 — Enforce central-tuning integrity

Add automated checks and documentation that prevent stale duplicate values,
validate configured IDs and units, and keep `pnpm check` green.

## Non-goals

- This is not a runtime settings menu or live balance editor.
- This does not centralize every numeric literal in the repository.
- This does not change gameplay values in the initial migration.
- This does not replace authored item, character, enemy, resource, map, or
  animation content with generated constants.
