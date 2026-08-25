# Walk-over Collectibles and Editor Attributes Implementation Plan

## Status

Implemented and hardened on 2026-08-24 as Roadmap item 2.6. Loose wood, loose
stone, and berries use one walk-over collectible path; trees and stone nodes
remain damageable resources. Legacy pile progress migrates into map-scoped
collectible progress, including remaining quantities and deterministic generated
drop positions.

The follow-up hardening pass added catalog-backed item validation,
archetype-aware map-instance validation, exact drop-count placement when nearby
cells are full, dependency-injected collectible runtime services, independent
per-object gameplay drafts, granular **Use default** behavior, dirty/error tab
indicators, keyboard tab navigation, dependent drop-visual overrides, and total
yield previews.

Verified with TypeScript and production builds; asset, animation, object, map,
and visual validators; persistence, collectible-runtime, and Map Studio state
tests; plus a live Map Studio check of grouping, resource controls,
yield preview, keyboard tab navigation, draft preservation, and reset behavior.
The destructive/full-inventory runtime scenarios in the manual matrix remain
useful release acceptance checks rather than implementation blockers.

## Player and creator outcome

The player walks over loose wood, loose stone, berries, and future collectible
objects to collect them. Loose materials never show an `F` prompt and do not
consume the general interaction action. If inventory capacity prevents a full
pickup, the uncollected quantity remains in the world.

In Map Studio:

- the right inspector has at least two persistent tabs: **Visuals & Collision**
  and **Resource & Collectible Attributes**;
- loose wood and stone appear in **Collectibles**, not **Resource Nodes**;
- collectibles expose their material/item and default quantity;
- resource nodes expose life points, persistence, hit feedback, tool
  requirements, a **Dropped collectible** dropdown, and a **Pieces dropped**
  number field;
- a selected placed instance shows its resolved values and may override only
  the supported instance values, such as starting quantity, starting life,
  dropped collectible, and pieces dropped;
- shared archetype edits clearly state that they affect every instance using
  that object definition.

The complete proof is:

`place -> inspect attributes -> save -> reload editor -> walk over -> collect -> save -> reload game`

## Current baseline

| Area | Current state | Required correction |
|---|---|---|
| Loose wood and stone | `resource.wood-pile` and `resource.stone-pile` use `resourcePile` data and are collected with `F` within 96 pixels | Move them to collectible content and collect only on player overlap |
| Purple berry | Uses `behavior: collectible.purple-berry`, but its reward and quantity are hard-coded in `WorldScene` | Give it the same authored collectible payload and generic collection path |
| Resource nodes | Trees and stone nodes use `resourceNode` data and `ResourceNodeController` | Keep them as damageable resources; remove pile/pickup responsibility from the controller |
| Editor grouping | `objectGroup()` groups by object-ID prefix | Group by authored capability (`collectible`, `resourceNode`, etc.) so folders and names do not control behavior |
| Inspector | Shows IDs, art, physics, tags, and visual geometry/animations in one long panel | Split the right panel into Visuals & Collision and Resource & Collectible Attributes tabs, then add resolved gameplay values |
| Persistence | Node and pile state share `resources` stages (`node`, `pile`, `destroyed`, `depleted`) | Separate collectible remaining quantity from resource-node life/depletion, with migration for existing saves |

## Decisions and invariants

- A **resource node** is a damageable world object that must be harvested. Trees
  and stone nodes remain resource nodes even when they drop collectibles.
- A **collectible** is a non-solid world object with an inventory payload that
  is collected by player overlap. Loose wood and stone are collectibles.
- Use stable IDs `collectible.wood-pile` and `collectible.stone-pile`. Migrate all
  authored map references and resource-node drop references in the same
  change. Preserve map instance IDs so existing map-scoped save progress still
  identifies the same placed objects.
- Replace `resourcePile` with one generic authored payload named `collectible`:

  ```ts
  collectible: {
    itemId: string;
    quantity: number;
  }
  ```

  The item catalog owns material names, icons, stack limits, and inventory
  presentation. Object content owns only the world pickup and its quantity.
- `F` remains the general intentional-interaction key for houses, shops, and
  similar actions. It is removed only from collectible pickup handling.
- Collection is inventory-safe. A full inventory leaves the collectible
  untouched. A partial add reduces and persists the remaining world quantity.
- Player overlap may fire repeatedly, so collection must be idempotent per
  physics step and must never grant the same quantity twice.
- Resource nodes own life, damage, tool requirements, drop rules, and depletion.
  The collectible feature owns overlap, inventory transfer, remaining quantity,
  pickup feedback, and collectible persistence.
- A resource drop points to a collectible archetype and a number of collectible
  pieces, not directly to an inventory item. Each spawned piece uses the
  selected collectible's own `itemId` and `quantity`. For example, a stone node
  may drop `collectible.stone-pile` with `pieces: 3`; if that collectible grants
  10 stone, the editor previews a total yield of 30 stone.
- Every resource node must choose its dropped collectible from catalog entries
  that actually declare a `collectible` payload. Free-text object IDs are not
  accepted by the normal editor workflow.
- Gameplay defaults are archetype data. Per-instance map state contains only
  intentional overrides and runtime state; it never copies the complete
  archetype definition into every map object.
- Attribute edits from Map Studio write to the owning object JSON through a
  validated development endpoint. The editor must not put shared gameplay
  rules into `asset/assets.json`.
- An instance override is blank by default and inherits the archetype value.
  The first supported overrides are collectible starting quantity and resource
  starting life points. Other resource rules remain shared defaults in this
  slice.
- `WorldScene` remains a composition root. Generic collection behavior belongs
  in a feature controller and is connected through dependency interfaces.

## Work sequence

### 1. Establish the collectible content contract

Add `collectible` to `ObjectArchetypeDefinition` and
`objects.schema.json` with required `itemId` and integer `quantity >= 1`.
Update `scripts/check-objects.mjs` so it validates the payload, verifies the
item ID exists, rejects contradictory definitions, and requires collectible
objects to be non-solid.

Contradictory combinations to reject in the first slice:

- both `collectible` and `resourceNode` on one archetype;
- `collectible` with static collision physics;
- a `collectible` tag without a collectible payload;
- a `resource`/resource-node classification without `resourceNode` data.

Move the loose material definitions to:

- `src/game/content/objects/collectibles/collectible-wood-pile.json` with
  `objectId: collectible.wood-pile`, `itemId: wood`, and `quantity: 10`;
- `src/game/content/objects/collectibles/collectible-stone-pile.json` with
  `objectId: collectible.stone-pile`, `itemId: stone`, and `quantity: 10`.

Give `collectible.purple-berry` an explicit payload rather than keeping its
material grant only in `WorldScene`. Keep any berry-specific animation, coin,
or quest side effect as a reaction to the generic collection event; do not make
a second pickup implementation.

Replace the resource node's direct `dropItem`, total-material `dropCount`, and
special `replacement` fields with one collectible drop definition:

```ts
drop: {
  objectId: string; // must resolve to an archetype with collectible data
  visualId: string; // must belong to that collectible archetype
  pieces: number;   // integer >= 1
}
```

Migrate the current balance without changing its total yield: a tree drops one
wood collectible containing 10 wood, while a stone node drops three stone
collectibles containing 10 stone each. Once the editor exists, changing
**Pieces dropped** from 3 to 4 makes that stone node spawn four collectible
objects and the yield preview changes from 30 to 40 stone.

Update `ObjectCatalog.ts`, every authored map reference, tree/stone drop
references, deterministic map tooling, and focused fixtures together. Do not
retain duplicate legacy palette entries.

### 2. Split collectible pickup from resource-node harvesting

Create a `CollectibleController` under `src/game/features/collectibles/`. It
receives the scene, map ID, player/inventory adapter, feedback adapter, and
world-progress adapter through a context interface. It registers both authored
and dynamically spawned collectible objects.

The controller must:

1. create or receive a physics-enabled overlap object for each active
   collectible without making it solid;
2. resolve its default quantity plus any authored instance override and saved
   remainder;
3. attempt the inventory add when the player body overlaps it;
4. leave the object unchanged and show throttled `Inventory full` feedback when
   zero items fit;
5. persist and display a partial remainder when only part of the quantity fits;
6. destroy/deactivate the visual and persist collection only when the remainder
   reaches zero;
7. emit one generic collection event containing map ID, instance ID, item ID,
   and collected quantity.

Remove prompt creation, nearest-pile lookup, `tryInteract()`, interaction-group
ownership, and pile inventory transfer from `ResourceNodeController`.
`WorldScene.handleActionInput()` must stop forwarding `F` to resource piles.

Resource depletion still decides where drops appear. Change its boundary to
resolve the resource's authored or instance-overridden `drop` definition and
request exactly `pieces` stable collectible spawns. The spawn callback carries
`objectId`, `visualId`, `instanceId`, source resource ID, position, and the
collectible's quantity. The collectible controller then owns each spawned drop
from registration through collection.

Use deterministic nearby placement for every drop count, not a stone-specific
three-pile branch. Search valid cells in a stable order; when there are fewer
open cells than pieces, place the remaining pieces at stable offsets around an
already valid drop point rather than silently reducing the authored count.

Replace the berry-specific overlap group and `collectPurple()` inventory grant
with the generic controller. Berry-only presentation or rewards may subscribe
to the generic event after the inventory transfer succeeds.

### 3. Separate and migrate persistence

Extend each map runtime state with collectible state keyed by stable instance
ID, for example:

```ts
collectibles: Record<string, {
  remaining: number;
  sourceResourceInstanceId?: string;
  cellX?: number;
  cellY?: number;
}>;
```

Keep resource-node state focused on node life/depletion and the deterministic
drop layout needed to reconstruct spawned collectibles. Bump the save schema
version and add a migration that converts old `pile`, `destroyed`, and
`depleted` resource-pile states without restoring already collected material.

Migration rules:

- preserve map ID and authored/source instance IDs;
- preserve partially collected wood and stone amounts;
- preserve generated stone pile IDs and cells;
- preserve depleted nodes as depleted;
- never grant inventory items during migration;
- make repeated loading/migration idempotent.

Add pure migration fixtures for an untouched node, partially damaged persistent
tree, replaced wood pile, partially collected authored pile, partially
collected generated stone piles, fully depleted source, and legacy berry state
where applicable.

### 4. Make Map Studio grouping capability-based

Replace the ID-prefix rules in `MapEditorPanel.objectGroup()` with an exported
classification derived from the archetype definition. The initial precedence
is:

1. `collectible` -> **Collectibles**;
2. `resourceNode` -> **Resource Nodes**;
3. explicit behavior families such as houses;
4. physics/tags for solid and floor decorations;
5. **Other Objects** as a visible fallback.

This ensures wood, stone, berries, and later drops appear together even if the
content folder or display name changes. Include item ID, quantity, life, and
tags in Object Content search text so creators can find entries by gameplay
meaning as well as artwork name.

Add focused tests proving that wood and stone appear only under Collectibles,
trees and stone nodes appear only under Resource Nodes, and no archetype is
silently omitted.

### 5. Build a tabbed right inspector and edit gameplay attributes

Refactor the Map Studio right panel into a tabbed inspector with at least these
two tabs:

1. **Visuals & Collision** contains the reusable visual identity and preview,
   display name, source asset/frame, scale and visual offset, collider shape and
   bounds, depth bounds, occlusion bounds, canvas-guide visibility, and shared
   idle/on-hit animation references. Existing visual-template behavior moves
   into this tab without losing any controls.
2. **Resource & Collectible Attributes** reads the selected archetype directly,
   not an expanded copy on `ObjectVisualChoice`. It contains the collectible
   material/quantity fields and the resource-node life, drop, tool, effect, and
   persistence fields described below.

Keep the object identity summary and the tab bar visible at the top of the
right panel. A non-resource decoration may still open the second tab, but it
shows a clear `This object has no resource or collectible attributes` empty
state instead of unrelated fields.

Tab behavior must be safe and predictable:

- remember the active tab while selecting other objects during the editor
  session;
- switching tabs never discards a draft or silently saves it;
- visual and gameplay dirty/error states are tracked independently and shown on
  their tab labels;
- selecting another object checks for unsaved changes from either tab;
- each tab has its own scoped Save/Reset actions so saving collision cannot
  overwrite resource data and saving resource data cannot overwrite visuals;
- the tab controls use normal keyboard navigation and expose selected/tabpanel
  state to assistive technology.

The **Resource & Collectible Attributes** tab renders the following contextual
fields.

For a collectible, show:

- classification: Collectible;
- item/material ID and resolved item name;
- default quantity;
- pickup method: Walk over;
- persistence: map instance and remaining quantity;
- selected-instance quantity override, when a placed instance is selected.

For a resource node, show:

- classification: Resource node;
- life points;
- **Dropped collectible**: a searchable dropdown containing only collectible
  archetypes, with thumbnail, display name, object ID, contained item, and
  quantity per piece;
- **Collectible visual**: a dependent visual dropdown when the chosen
  collectible has multiple visual templates;
- **Pieces dropped**: an integer number input controlling how many collectible
  objects spawn when the node reaches zero life;
- **Total material yield**: a read-only preview calculated as pieces multiplied
  by the selected collectible's quantity;
- persist partial life: yes/no;
- hit effect and depletion message;
- required material/tool tag and minimum tier;
- failure message;
- selected-instance overrides for starting life, dropped collectible/visual,
  and pieces dropped, when a placed instance is selected.

Shared values are editable with a clear **Applies to every instance** label.
Instance values are edited through `MapEditorState`, participate in undo/redo,
set the map dirty flag, and save in that object's `initialState`. Show both
default and resolved values whenever an override exists, plus a **Use default**
action that removes the override.

Changing the collectible dropdown automatically selects its valid default
visual and refreshes the yield preview. Saving is blocked if the selected
collectible or visual no longer exists. The dropdown is populated from the
current object catalog, so adding a future collectible makes it available to
resource nodes without adding editor-specific code.

Use a separate gameplay-attribute draft/state from visual geometry, wired to
the second tab, so saving a collider cannot accidentally erase behavior data
and vice versa. Extend the development save endpoint to patch only the selected,
schema-approved gameplay block, then re-run object validation before replacing
the source JSON.

### 6. Formalize map validation for instance overrides

Replace unconstrained resource/collectible `initialState` usage with validation
based on the referenced archetype:

- collectible `remaining` must be an integer from `0` through the chosen
  starting quantity;
- resource-node `health` must be a finite number from `0` through its default
  life points;
- resource-node `dropObjectId` must resolve to an archetype with a collectible
  payload, `dropVisualId` must belong to it, and `dropPieces` must be an integer
  of at least 1;
- collectible overrides are rejected on resource nodes and resource overrides
  are rejected on collectibles;
- unsupported keys remain available only for their owning behavior family,
  rather than becoming a general gameplay escape hatch.

Keep the map format at v1 if these are validation rules for the existing
`initialState` object. Bump it only if the serialized field shape changes.

### 7. Verification and close-out

Automated verification:

- object schema/catalog validation accepts the new collectible definitions and
  rejects contradictory behavior combinations;
- all authored maps validate with the new collectible IDs;
- collectible transfer tests cover full, partial, zero-capacity, repeated
  overlap, and exact-once depletion;
- persistence migration tests cover authored and generated pickups;
- editor grouping/search tests cover both object groups and attribute keywords;
- right-panel tests cover tab switching, keyboard tab navigation, active-tab
  persistence, contextual empty states, independent dirty/error indicators,
  and protection against cross-tab data loss;
- editor state tests cover shared-draft separation, instance override
  undo/redo, dependent collectible/visual dropdowns, yield preview,
  **Use default**, save, and reload;
- `pnpm check` passes.

Manual runtime and editor proof:

1. open Map Studio and verify the right panel has **Visuals & Collision** and
   **Resource & Collectible Attributes** tabs;
2. verify wood, stone, and berry appear in Collectibles, while a tree and stone
   node appear in Resource Nodes;
3. switch between both inspector tabs and confirm visual/collision edits and
   gameplay edits retain independent unsaved state;
4. inspect and edit one collectible quantity and one resource life value;
   choose Stone from the resource's collectible dropdown and set 4 pieces;
   save, reload Map Studio, and confirm the resolved values and total-yield
   preview;
5. place loose wood and stone, start a fresh game, and collect both by walking
   over them without pressing `F`;
6. fill the inventory, walk over a pile, and confirm its remaining quantity is
   not lost; free capacity and collect the remainder;
7. break a tree and stone node, partially collect their drops, save/reload, and
   confirm the same nodes/drop layout and remaining quantities; repeat with 3
   and 4 pieces and confirm the exact authored number spawns;
8. press `F` near loose material and confirm it performs no pickup while other
   intentional interactions still use `F`;
9. verify collection feedback, inventory counts, quest/event reactions, and
   map transitions do not double-grant material.

## File ownership map

| Concern | Primary files |
|---|---|
| Collectible/resource content contracts | `src/game/content/objects/ObjectCatalog.ts`, `src/game/content/objects/objects.schema.json`, object JSON files |
| Object and map validation | `scripts/check-objects.mjs`, `scripts/check-maps.mjs`, `src/game/content/maps/mapFormat.ts` |
| Walk-over pickup runtime | `src/game/features/collectibles/CollectibleController.ts`, `src/game/scenes/WorldScene.ts` |
| Resource damage and drop spawning | `src/game/features/resources/ResourceNodeController.ts` |
| Save migration and map progress | `src/game/infrastructure/persistence/SaveSchema.ts`, `SaveRepository.ts`, `src/game/features/progression/WorldProgress.ts` |
| Editor grouping and search | `src/game/editor/MapEditorPanel.ts` |
| Shared/default and instance attributes | `src/game/editor/MapEditorInspector.ts`, a dedicated gameplay attribute editor state, `MapEditorState.ts`, `vite.config.ts` |
| Authored content migration | `src/game/content/maps/`, `scripts/lib/procedural-map-generator.mjs` |

## Done when

- loose wood and stone are collectible archetypes and appear only in the
  Collectibles group;
- all collectibles use the generic walk-over collection path and loose
  materials have no `F` prompt or `F` pickup route;
- trees and stone nodes remain damageable resources and appear in Resource
  Nodes;
- the inspector exposes collectible quantity/material and resource life/drop/
  tool attributes, including a catalog-backed dropped-collectible dropdown,
  visual choice, piece count, total-yield preview, safe shared edits, and
  supported instance overrides;
- the right inspector provides separate **Visuals & Collision** and **Resource
  & Collectible Attributes** tabs with independent drafts, validation, and save
  actions;
- existing authored maps and saves retain their resource and remaining pickup
  state through migration;
- automated checks pass and the manual fresh-save/reload matrix is verified in
  the running game and Map Studio.
