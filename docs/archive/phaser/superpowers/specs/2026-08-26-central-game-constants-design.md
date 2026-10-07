# Central Gameplay Constants Design

## Status

Approved design. Implementation is intentionally staged so the first change
does not turn every local rendering or animation literal into a global
dependency.

## Goal

Create `src/game/content/game-constants.json` as the authoritative, Studio-
editable source for shared gameplay rules and new-run defaults. Create
`src/game/Constant.ts` as the typed runtime gateway that validates the JSON and
exports it as `GAME_CONSTANTS`.

The first migration covers inventory defaults and stack rules plus the primary
player's attributes, movement, progression, level cap, and per-level XP and
stat growth. Later domains can move through the roadmap without changing the
ownership or save-precedence model again.

## Ownership decision

The JSON owns shared gameplay rules and initial values. `Constant.ts` owns the
runtime contract, not a second copy of those values. Content files continue to
own identity and authored data that varies by item, character, enemy, object,
map instance, or visual package.

In particular:

- `inventory.initialMaxSlots` seeds a new run. The run's current inventory
  capacity is mutable player state and is saved thereafter.
- Inventory stack limits remain global item rules. Item JSON keeps IDs, names,
  categories, icons, descriptions, and item-specific effects; runtime
  `ItemDef.maxStack` is populated from the configured stack rules.
- `character.player.initialAttributes` seeds a new run. Saved attributes take
  precedence after creation because gameplay can change them.
- Player movement, protection, base combat values, the level cap, XP
  requirements, and the stat gain assigned to each level are global rules.
- The primary player character package keeps its name, body geometry, visual
  references, and animation tracks. It does not duplicate attributes,
  movement, progression, or other centrally owned player gameplay fields.
- Enemy-specific AI, combat, drop tables, resource quantities, map placement,
  animation timing, collision geometry, and UI/layout values remain in their
  current owning content or feature modules. They are not moved merely because
  they are numeric.

The architecture documentation will replace the prohibition on a global
constants file with this narrower rule and document the two-file boundary:
JSON is the editable data source, while `Constant.ts` is its only runtime
gateway.

## Configuration shape

The JSON is versioned, has a strict schema, and groups values by domain. This
abridged example shows the contract; the production `levels` array contains
all entries from level 1 through level 10:

```jsonc
{
  "$schema": "./game-constants.schema.json",
  "version": 1,
  "inventory": {
    "initialMaxSlots": 24,
    "maxStackByItem": {
      "wood": 99,
      "stone": 99,
      "iron-ore": 99,
      "charcoal": 99,
      "hp-potion": 9,
      "energy-potion": 9,
      "purple-berry-mat": 99,
      "silk-clump": 99,
      "shard": 99
    },
    "weaponMaxStack": 1
  },
  "character": {
    "player": {
      "initialAttributes": {
        "strength": 10,
        "vitality": 10,
        "agility": 10,
        "intellect": 10
      },
      "movement": {
        "baseSpeed": 240,
        "boostSpeed": 360,
        "dodgeSpeed": 420,
        "dodgeInvulnerabilityMs": 400,
        "movementSpeedCap": 480
      },
      "hitInvulnerabilityMs": 500,
      "progression": {
        "maxLevel": 10,
        "baseMaxHp": 100,
        "baseMaxEnergy": 100,
        "baseAttack": 10,
        "baseDefense": 2,
        "levels": [
          {
            "level": 1,
            "xpToNextLevel": 200,
            "gains": { "maxHp": 0, "maxEnergy": 0, "attack": 0, "defense": 0 }
          },
          {
            "level": 2,
            "xpToNextLevel": 500,
            "gains": { "maxHp": 12, "maxEnergy": 4, "attack": 2, "defense": 1 }
          },
          // Entries 3 through 9 use their individually authored requirements
          // and gains.
          {
            "level": 10,
            "xpToNextLevel": null,
            "gains": { "maxHp": 12, "maxEnergy": 4, "attack": 2, "defense": 1 }
          }
        ]
      }
    }
  }
}
```

`xpToNextLevel` belongs to the current level. For example, the level-1 value is
the XP needed to reach level 2, and the level-2 value is the XP needed to reach
level 3. The final level must use `null` because no higher level exists.

`gains` describes the stats gained upon reaching that entry's level. Level 1
must contain zero gains because its stats come from the base values. Every
later level through the configured maximum may define different gains. Derived
max HP, max energy, attack, and defense are the base values plus the sum of
gains from level 2 through the player's current level.

`Constant.ts` imports the JSON, validates it at the runtime boundary, and
exports a deeply readonly `GAME_CONSTANTS`. It contains no fallback literals.
Consumers import the gateway rather than importing the JSON directly.

## Default, rule, and save precedence

The design distinguishes initial values from global rules and mutable run
state:

| Value | New run | Existing save |
| --- | --- | --- |
| Inventory capacity | Copy `initialMaxSlots` into inventory state | Saved capacity wins |
| Player attributes | Copy `initialAttributes` into player state | Saved attributes win |
| Current HP and energy | Initialize from resolved level-1 maxima | Saved values load, then clamp to recalculated maxima |
| Player level | Start at 1 | Saved `level` wins when it is within the configured range |
| Current XP | Start at 0 | Saved `currentXp` wins, subject to the current level's requirement |
| Movement and protection | Read current global rules | Current global rules apply |
| Base combat values and level gains | Resolve from the current table | Recalculate from saved level using the current table |
| Item and weapon stack limits | Read current global rules | Current global rules apply to new stacking operations |

Changing base values or any level gain therefore recalculates the derived stats
of an existing character without rewriting its saved level or current XP.
Changing initial attributes or initial inventory capacity affects new runs
only.

The initial configured level range is exactly 1 through 10. `maxLevel` is an
editable balance value rather than a hard-coded schema maximum; changing it
also requires a complete matching levels table. A player at the currently
configured maximum cannot gain another level or emit another level-up reward.
A save containing a level outside the configured range is incompatible:
loading fails visibly and does not overwrite the stored save.

If a stack limit is reduced below a count already present in a save, that slot
is grandfathered so loading never destroys items. New additions do not add to
an over-limit slot, and all newly created stacks obey the current limit.
Removing items naturally brings the grandfathered slot back under the current
rule.

## Save schema and migration

Inventory capacity must become persistent because it can increase during a
run. Replace the saved inventory array with an inventory-owned structure:

```ts
interface InventorySaveData {
  readonly maxSlots: number;
  readonly slots: readonly InventorySlot[];
}
```

The save migration wraps legacy inventory arrays as `slots`. It initializes
`maxSlots` to the greater of `inventory.initialMaxSlots` and the number of
occupied legacy slots, so migration never discards items or creates an
over-capacity inventory. New saves always serialize both fields, and saved
capacity must be a positive integer no smaller than the occupied slot count.

Inventory exposes an `increaseMaxSlots(amount)` operation for progression
rewards. It accepts only a positive integer, never reduces capacity, and emits
`inventory.changed` after a successful increase so the existing autosave path
persists it.

Progression remains directly on `GameStateData`. The existing `level` field is
retained, while cumulative `xp` is replaced by current-level `currentXp`:

```ts
interface GameStateData {
  level: number;
  /** XP already earned within `level` toward the next level. */
  currentXp: number;
}
```

`currentXp` is not lifetime cumulative XP. For a non-final level it is in the
range `0 <= currentXp < xpToNextLevel`. When XP crosses the requirement, the
requirement is subtracted, the level increases, the remainder carries into the
new level, and the process repeats until the remainder is below the next
requirement or the configured maximum is reached. At the configured maximum,
`currentXp` is always zero.

Legacy cumulative XP is converted to `currentXp` during migration without
changing the legacy saved level. The migration subtracts the legacy cumulative
threshold for that level and normalizes the remainder against the new current-
level requirement. If a changed requirement makes saved progress too large,
`currentXp` is clamped to one less than the new requirement so loading a
configuration edit does not synthesize a level-up or skill-point reward.

Previously persisted `maxHpBonus` and `maxEnergyBonus` are no longer used to
resolve stats. All four derived combat stats are recalculated from the saved
level and current table. Saved HP and energy remain the player's current
resources and clamp only when their recalculated maxima decrease.

The public `xp` getter is replaced by `currentXp`. The existing `xp.changed`
event name remains, but its payload becomes
`{ currentXp, xpToNextLevel, level, delta }`, where `xpToNextLevel` is
`number | null`. At the configured maximum it is `null`, and the UI presents
the player as max level instead of rendering another XP target. All UI and
persistence consumers move to those explicit current-level semantics.

This is a versioned save-schema migration. The original save remains untouched
if parsing or migration fails.

## Runtime integration

The first implementation will make these consumers use the new boundary:

1. `systems/Inventory.ts` owns mutable `maxSlots`, seeds it from
   `inventory.initialMaxSlots`, serializes it, and uses the configured weapon
   stack rule instead of local literals.
2. `content/items/ItemCatalog.ts` normalizes base item definitions with the
   configured per-item stack limits. Missing or extra configured IDs fail at
   the catalog boundary instead of silently falling back.
3. `content/player.ts` remains a compatibility/composition adapter for the
   primary player's name and body while reading central gameplay rules.
4. `features/player/PlayerController.ts`, `systems/PlayerStats.ts`,
   `core/GameState.ts`, and `content/initial-state/InitialRun.ts` consume the
   central player values.
5. `core/GameState.ts` replaces cumulative XP and the formula XP curve with
   saved `level`/`currentXp` progression and table-driven requirements. It
   replaces local base attack/defense literals and recalculates all derived
   stats from the current table.
6. The player character schema, TypeScript types, validators, virtual-content
   declarations, creation defaults, tests, and Character Studio package state
   stop storing primary-player attributes, movement, and progression fields.
7. Persistence migrates inventory capacity and progression as described above.

The configured base values plus summed level gains produce the player's
pre-perk max HP, max energy, attack, and defense. Existing perk modifiers remain
layered on those resolved values in their current order; the migration does not
move perk balance into this document. After each successful level-up, current
HP and energy refill to their newly resolved, post-perk maxima, preserving the
existing gameplay behavior.

## Character Studio integration

Character Studio retains player-default and progression controls, but those
controls no longer mutate the character package. They edit
`game-constants.json` through a dedicated development-only endpoint.

The player gameplay panel exposes:

- initial attributes;
- movement speeds, movement cap, dodge protection, and hit protection;
- base max HP, max energy, attack, and defense;
- the editable max level, initially 10;
- one ordered row for each level with XP-to-next and four stat gains.

Changing `maxLevel` resizes the levels table. Increasing it appends rows with
explicit values that must be completed before save. Decreasing it requires a
confirmation because it deletes authored level rows and can make higher-level
saves incompatible.

The endpoint validates the entire submitted document, serializes it
deterministically, writes a temporary file, and atomically replaces the JSON.
Invalid submissions leave the existing file unchanged and return field-level
issues. Character-package saving and gameplay-constants saving are separate
operations with separate dirty and error states so one cannot partially
commit the other.

## Validation and tests

The first migration includes `game-constants.schema.json` and a mandatory
constants checker wired into `pnpm check`. The checker verifies:

- the document version and exact allowed keys;
- positive integer initial slot and stack limits;
- exact bidirectional parity between base item IDs and `maxStackByItem` keys;
- finite, nonnegative attributes, speeds, stats, and gains;
- integer, nonnegative millisecond values;
- `baseSpeed <= boostSpeed <= movementSpeedCap` and
  `dodgeSpeed <= movementSpeedCap`;
- `maxLevel` is a positive integer;
- the levels array contains each integer level from 1 through `maxLevel`
  exactly once, in ascending order;
- level 1 has zero gains, levels below the cap have positive integer
  `xpToNextLevel`, and the final level has `xpToNextLevel: null`;
- no centrally owned primary-player fields remain in character package data.

Tests cover:

- configured initial capacity, saved capacity precedence, capacity upgrades,
  stacking, grandfathered over-limit stacks, unknown IDs, and weapon behavior;
- full, partial, and exact collectible transfers under the configured
  inventory rules;
- new-run attribute defaults and saved attribute precedence;
- different XP requirements and gains at different levels;
- XP remainder carrying across multiple levels and normalization at the
  configured maximum;
- persistence of `level` and `currentXp` across save/load;
- the renamed current-XP getter and `xp.changed` payload;
- recalculation of all four derived stats after the constants table changes;
- stopping at the configured maximum without duplicate rewards;
- full HP and energy refill after a level-up, including perk modifiers;
- current HP and energy clamping after derived maxima decrease;
- legacy inventory and XP migration plus incompatible out-of-range saves;
- Character Studio load, validation, dirty state, atomic save, and error
  reporting for gameplay constants;
- TypeScript compilation and the production build.

## Migration rules for future domains

- Classify each value as an initial value, global rule, or mutable saved value
  before moving it.
- Move a number only when it is a shared gameplay rule or intentionally
  controlled from the central Studio balance surface.
- Give each domain a nested section and keep units explicit in names such as
  `CooldownMs`, `Speed`, or `MaxCount` where ambiguity is possible.
- Remove old literals and exports after consumers migrate; do not keep fallback
  copies.
- Keep per-entity authored values in content. A global value may be a default
  only when the runtime contract explicitly defines how it seeds saved state.
- Do not move UI dimensions, colors, animation frame data, storage keys, map
  geometry, or editor-only limits into this gameplay document.

## Roadmap placement

Add a new **Cross-Cutting Gameplay Configuration** section after Cross-Cutting
Persistence in `docs/GAME_ROADMAP.md`:

### [ ] C.1 - Define central gameplay configuration ownership

Document the JSON/TypeScript gateway, domain boundaries, units, and the
distinction among initial values, global rules, and saved state.

### [ ] C.2 - Centralize inventory tuning

Move initial capacity, item stack limits, and weapon stack behavior; persist
mutable capacity and migrate legacy inventory saves.

### [ ] C.3 - Centralize player character tuning

Move initial attributes, movement, protection, base combat values, level cap,
per-level XP, and per-level gains; remove duplicate package ownership and
replace formula-based progression.

### [ ] C.4 - Add Character Studio constants authoring

Add the validated player-default and level-table editor backed by atomic JSON
persistence.

### [ ] C.5 - Migrate remaining shared gameplay defaults by domain

Move remaining cross-feature balance literals in focused slices while
preserving feature ownership and per-entity authored values.

### [ ] C.6 - Enforce central-tuning integrity

Keep automated configuration, content-parity, save-migration, and stale-field
checks in `pnpm check`.

## Non-goals

- This is not an in-game settings menu or live production balance editor.
- This does not centralize every numeric literal in the repository.
- Character Studio edits source configuration for future builds and local
  development; it does not mutate a running player's saved attributes or
  inventory capacity.
- This does not replace authored item, character, enemy, resource, map, or
  animation identity and per-entity content with generated constants.
