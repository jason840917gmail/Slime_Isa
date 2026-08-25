# Stone and Starter Tools Implementation Plan

## Status

Ready for implementation. This plan delivers Roadmap Section 2 as one safe,
save-compatible vertical slice. Stone content, the shared animation library,
and Map Studio object creation already have substantial implementations; they
need verification and close-out rather than replacement.

## Player outcome

A fresh save starts in Sunbell Meadow with only the innate slime attack. The
player collects loose wood and stone by hand, crafts starter tools and spears,
harvests trees and stone nodes with the correct tool, clears a one-time enemy
camp, claims one green key, and permanently unlocks the east exit to Gloop
Forest.

The complete proof is:

`collect -> craft -> harvest -> fight -> chest -> key -> exit -> reload`

## Current baseline

| Roadmap item | Current state | Plan treatment |
|---|---|---|
| 2.1 Stone nodes | Implemented in content/runtime; three nodes are placed and depletion/piles are persisted | Validate a fresh-save collect/reload pass, add loose starter stone, then close |
| 2.2 Starter recipes | Only three potion recipes exist; crafting consumes ingredients before proving output capacity | Replace the hard-coded list with one context-ready catalog and an atomic transaction |
| 2.3 Tool gates | Damage modifiers exist, but zero damage is only a silent rejection and does not model tool tier | Add explicit harvesting capability/tier checks and readable feedback |
| 2.4 Shared animation library | Catalog, packages, studios, runtime adapters, validators, and focused tests exist | Run close-out checks and update stale status text |
| 2.5 Map Studio object creation | The New object dialog, import path, save endpoint, and palette refresh exist | Run the documented floor/solid/import/reload acceptance pass and update the old plan status |
| 2.6 Guarded key | No reusable one-time camp, reward chest, green key, or keyed exit exists | Add authored progression fields, persistence, runtime controllers, and editor controls |

## Decisions and invariants

- Sunbell Meadow (`meadow-crossing`) is the starter level. Its east exit to
  `gloop-forest` is the first green-key gate.
- The existing `goo-gauntlet` ID becomes the temporary runtime identity for the
  innate slime strike. It is always available, is not granted as inventory
  loot, has no harvesting capability, and is the only attack on a new save.
  The later action-dashboard task may move it from the weapon row into a fixed
  ability slot without changing this milestone's progression.
- New production item IDs are `wooden-spear`, `stone-axe`, `stone-pickaxe`, and
  `stone-spear`. Existing `basic-spear`, `wooden-axe`, and `pickaxe` definitions
  remain readable for old saves and debug use during the migration. Do not
  silently rename a saved stable ID.
- Harvest eligibility and harvest damage are separate. Tool capability/tier
  decides whether a hit is legal; existing numeric damage modifiers decide how
  effective a legal hit is.
- Recipe definitions live in `src/game/content/`, while transaction logic stays
  in the crafting/inventory feature. The UI never owns recipe truth.
- Every crafting attempt validates ingredients and output capacity before
  changing inventory. A failed craft changes nothing and emits one clear reason.
- The camp, chest, and gate use authored stable IDs. Enemy kills, key rewards,
  and gate unlocks are never inferred from screen coordinates.
- The save records encounter completion, opened reward IDs, and unlocked gate
  IDs separately. Do not overload `completedDungeonIds` with unrelated state.
- Normal starter grants remain active until the replacement path passes the
  fresh-save and reload matrix. Debug grants remain available only behind an
  explicit development-only action or query flag.
- `asset/assets.json` remains media metadata only. Harvest rules, recipes,
  rewards, encounter behavior, and gates belong in TypeScript/authored map
  content.

## Work sequence

### 0. Close out the already-built Section 2 foundations

Run the existing animation, object, and map validators and focused package /
object-animation tests. Then perform the manual checks that automation cannot
prove:

1. break a stone node, partially collect its generated piles, save/reload, and
   confirm the same remaining amount;
2. create one floor decoration and one solid decoration in Map Studio, including
   one imported spritesheet case;
3. place both, save, reload Map Studio and runtime, and confirm frame, scale,
   collision, depth, and optional animation references;
4. open Weapon/Animation Studio and confirm migrated package previews and
   runtime fallback for a missing optional animation.

If these checks pass, mark 2.1, 2.4, and 2.5 complete. If one fails, fix only
that acceptance gap before starting the progression changes. Update
`2026-08-20-map-studio-new-object-authoring-implementation-plan.md` from
"Proposed" to its verified implementation state.

### 1. Establish stable starter content and save compatibility

Add the four production weapon/tool definitions under
`src/game/content/weapons/`. Reuse approved animation packages and artwork for
the first playable pass where new art is not yet available, but keep each new
stable ID and balance definition distinct. Register no duplicate media entries
when two definitions intentionally share one visual package.

Extend the weapon definition contract with an optional harvest capability map,
for example:

```ts
harvestCapabilities?: Readonly<Record<string, number>>;
```

The first definitions are:

- Stone Axe: `wood: 1`;
- Stone Pickaxe: `stone: 1`;
- Wooden Spear and Stone Spear: no harvest capability;
- innate slime strike and other combat weapons: no harvest capability.

Update the weapon schema, normalizer, catalog checks, Weapon Studio form/round
trip, and focused weapon tests together so editor saves cannot erase the new
field.

Change loadout initialization into two explicit paths:

- production initialization: reconcile saved inventory/loadout and ensure only
  the innate slime strike fallback exists on a true new save;
- development grant: add the legacy test arsenal only after an explicit
  development-only command or `?starterGear=1` flag.

Existing saves keep owned legacy items. Empty or invalid equipped IDs normalize
to the innate fallback without deleting inventory or duplicating a weapon.

### 2. Build one future-compatible, atomic recipe path

Create `src/game/content/recipes/types.ts` and `RecipeCatalog.ts`. Move the
existing potion definitions into this catalog and add these portable recipes:

| Recipe ID | Output | Cost |
|---|---|---|
| `craft-wooden-spear` | `wooden-spear` | 20 wood |
| `craft-stone-axe` | `stone-axe` | 10 wood + 10 stone |
| `craft-stone-pickaxe` | `stone-pickaxe` | 10 wood + 10 stone |
| `craft-stone-spear` | `stone-spear` | 20 wood + 20 stone |

Define `context: 'portable' | 'workbench' | 'forge' | 'kitchen' | 'alchemy'`,
`tier`, and optional unlock metadata now, but implement only the portable
context in this milestone. This prevents a second recipe migration when the
station milestones begin.

Add an inventory transaction operation that simulates all removals and grants
on a copy of the slots, including slots freed by consumed ingredients, and
commits only when every operation succeeds. Emit `inventory.changed` once per
successful transaction and never on a rejected simulation.

Refactor `Crafting.ts` into a service returning a typed result such as
`crafted`, `missing-ingredients`, `inventory-full`, `already-owned`, `locked`,
or `wrong-context`. Weapon recipes are one-time ownership recipes: crafting a
second copy is rejected before ingredients are consumed. Update `CraftingUI.ts`
to render the catalog result and, after a weapon output succeeds, call the
existing `playerWeaponLoadout.ensureAssigned` path. If all six slots are
occupied, the crafted item remains safely in inventory and the UI explains that
assignment is still needed.

Add pure tests for catalog validation, exact recipe costs, output-capacity
failure, ingredients that free an output slot, single-event commit, wrong
context, and crafted-weapon assignment.

### 3. Author the no-softlock starter economy

Use the generic walk-over collectible path defined in the
[Walk-over Collectibles and Editor Attributes plan](./2026-08-24-walk-over-collectibles-and-editor-attributes-implementation-plan.md).
Do not keep or create an `F`-based loose-material pickup path. Author loose wood
and loose stone collectibles near the Meadow spawn with a guaranteed budget of
at least `40 wood + 20 stone`. This funds the
Wooden Spear, Stone Axe, and Stone Pickaxe in any order. The stronger Stone
Spear then requires the player to use those tools to gather the additional
`20 wood + 20 stone`, preserving the intended harvest step.

Because starter weapon/tool recipes reject duplicate ownership, this fixed
budget cannot be consumed by accidentally crafting a second copy. Do not add a
hidden material grant or a special respawn rule unless playtesting finds another
real loss path.

Update `meadow-crossing.map.json` through Map Studio where possible. Validate
that every source is reachable without crossing a collider, entering the
guarded camp, or owning a tool.

### 4. Enforce explicit harvesting requirements with feedback

Extend resource-node content with an optional authored requirement:

```ts
harvestRequirement?: {
  readonly targetTag: string;
  readonly minimumTier: number;
  readonly failureMessage: string;
};
```

Trees require `wood` tier 1 and stone nodes require `stone` tier 1. Resource
piles remain hand-collectible and have no requirement.

At the combat/resource boundary, resolve the equipped weapon's capability
before calculating damage. Return a typed `insufficient-tool` rejection with
the content-authored message. Show throttled floating/prompt feedback, but do
not play hit animation/effect, reduce health, knock the node, or persist a
change. Once eligible, apply the existing target-tag damage modifier normally.

Add tests covering no tool, wrong tool, correct tier, future higher tier,
zero-damage rejection, accepted hit feedback, and final-hit replacement.

### 5. Add reusable one-time camps to authored enemy areas

Extend `MapEnemySpawnArea` with an optional `spawnMode`, defaulting to
`ambient`; support `clear-once` for progression camps. Update map parsing,
validation, serialization, Map Studio's enemy-area dialog, and the map checker
in the same slice.

For `clear-once` areas, `EnemySpawner` must:

1. seed the authored population once when the player first activates the area;
2. never refill defeated enemies;
3. expose the stable spawn-area ID on death events;
4. emit one completion event when an initialized camp reaches zero living
   enemies;
5. skip seeding when that encounter ID is already persisted as complete.

Author a small `starter-green-key-camp` in Sunbell Meadow. Keep it outside the
hand-collection path and tune it for the Wooden Spear, with the Stone Spear as a
meaningful advantage rather than a hard requirement.

### 6. Add authored reward chests and keyed exits

Add a reusable reward-chest object archetype with closed/open visuals and an
interaction point. Add authored map reward data that references the chest's
stable `instanceId`, its required encounter ID, and item grants. Validate every
cross-reference and expose the fields in the selected chest's Map Studio
inspector; do not store reward contents in `asset/assets.json`.

Register `green-key` as a non-stackable key item. The starter chest remains
locked until `starter-green-key-camp` is complete. Opening it performs an atomic
inventory grant; if inventory is full, it remains unopened and claimable. Only
after the grant succeeds does it persist the reward ID and switch to its open
visual. Repeated interaction and reload produce no duplicate key.

Extend `MapExit` with an optional gate:

```ts
gate?: {
  readonly id: string;
  readonly requiredItemId: string;
  readonly consumeOnUnlock: boolean;
  readonly lockedMessage: string;
};
```

Add gate controls beside each Map Studio connection. Author
`meadow-east-green-gate` on the existing east exit to Gloop Forest. On overlap,
an unavailable gate blocks transition and shows throttled feedback. With the
green key, consume it exactly once, persist the gate ID, and transition. An
already-unlocked gate never requires or consumes another key.

### 7. Add progression persistence and migration

Add normalized, default-empty world progress collections for completed enemy
encounters, opened reward IDs, and unlocked gate IDs. Bump the save schema and
normalize older saves instead of casting them directly. Keep existing dungeon,
boss, resource, inventory, and loadout data unchanged.

Add focused save tests for:

- loading the previous schema with all new collections empty;
- encounter completion surviving reload and preventing respawn;
- full-inventory chest failure leaving reward state unopened;
- successful chest grant occurring once;
- gate key consumption and permanent unlock;
- loading an unlocked gate with no key still permitting transition.

### 8. Remove normal grants only after the replacement loop passes

Run the entire milestone with a truly fresh save while normal starter grants
are still behind a temporary compatibility switch. Verify the resource budget,
crafting errors, assignment, combat difficulty, chest capacity, transition, and
reload behavior. Then make production initialization the default and retain the
old arsenal only through the explicit development grant.

Do not delete legacy weapon definitions in this milestone. Their cleanup needs
a separate save-usage audit after released saves have migrated.

## File ownership map

| Concern | Primary files/directories |
|---|---|
| Recipe authority | `src/game/content/recipes/`, `src/game/crafting/Crafting.ts` |
| Atomic inventory | `src/game/systems/Inventory.ts` |
| Tool definitions/capabilities | `src/game/content/weapons/`, weapon schema/normalizer/checks |
| Loadout migration/debug grant | `src/game/systems/WeaponLoadout.ts`, `src/game/scenes/WorldScene.ts` |
| Resource requirements | `src/game/content/objects/`, `ResourceNodeController.ts`, `CombatController.ts` |
| One-time camps | `mapFormat.ts`, `EnemySpawner.ts`, `EventBus.ts`, Map Studio enemy-area controls |
| Chest/key/gate | object content, progression feature controllers, Map Studio object/connection controls |
| Persistence | `SaveSchema.ts`, `SaveRepository.ts`, `WorldProgress.ts` |
| Starter content | `src/game/content/maps/meadow-crossing.map.json` |
| Automated coverage | focused suites under `scripts/tests/crafting/`, `progression/`, `combat/`, and `map-editor/` |

Keep orchestration in feature controllers. `WorldScene` may construct and wire
them, but must not absorb the complete crafting, encounter, reward, or gate
implementation.

## Verification gates

Run the narrow checks after each slice and the full check before handoff:

1. weapon/object/map validators after each content-contract change;
2. focused crafting, inventory, harvest-gate, encounter, chest, gate, save, and
   Map Studio tests;
3. `pnpm typecheck`;
4. `pnpm build`;
5. `pnpm check`;
6. fresh-save manual playtest at default zoom and one overview zoom;
7. save/reload after partial gathering, camp completion, chest opening, and gate
   unlocking;
8. Map Studio reload check for the camp, chest, and gated connection.

## Milestone acceptance matrix

| Scenario | Required result |
|---|---|
| Fresh save | Only innate slime attack is available; no production test arsenal |
| Hand collection | Enough reachable loose wood/stone exists to avoid a permanent softlock |
| Failed craft | No ingredient is consumed and the reason is visible |
| Successful craft | Item appears once and is assigned when a slot is available |
| Wrong harvesting tool | Node state is unchanged and a clear requirement is shown |
| Correct harvesting tool | Tree/stone damage and persistent drops behave normally |
| Camp clear | Enemies stop spawning and completion survives reload |
| Full chest claim | Key is not lost; chest remains closed and claimable |
| Successful chest claim | Exactly one green key is granted and the chest stays open |
| Locked exit | No transition occurs without the key |
| Gate unlock | One key unlocks the east exit permanently |
| Reload after unlock | Gloop Forest remains reachable without another key |
| Editor round trip | Camp mode, chest reward, and exit gate survive save/reload and validation |

Roadmap Section 2 is complete only when every row passes without debug commands
or automatic production gear grants.
