# Stone Gathering and Pickaxe Design

**Status: approved design; implementation pending.**

## Goal

Extend the verified Wood Gathering loop with a stone resource node and a test
Pickaxe. A large stone pile can be attacked, then becomes three collectible
small stone piles distributed around its original map cell.

## Player-facing rules

- The large stone node uses the resource sheet visual at row `0`, column `1`.
- Its authored replacement is a separate `resource.stone-pile` archetype using
  row `1`, column `1` (`stone-pile`), `resourcePile.itemId: "stone"`,
  `resourcePile.amount: 10`, and collectible `resource`/`stone` tags. It must
  not reuse the wood-pile archetype because the replacement contract owns both
  the visual and the collected item.
- It is an authored map object with a static collision body and `40` health.
- The node tags are ordered `stone`, `resource`, `solid`, so the combat
  resolver’s target-tag precedence selects the specific stone modifier before
  the generic resource modifier.
- The Pickaxe is immediately available as a starter/testing tool.
- It is owned and assigned to the new sixth hotbar slot on a fresh game; the
  existing default equipped weapon remains unchanged so adding the tool does
  not alter the current opening combat state.
- The Pickaxe uses the established tool package conventions and generated
  directional art. Its combat profile is:
  - base damage `12`;
  - `{ "targetTag": "stone", "modifier": 1 }`;
  - `{ "targetTag": "resource", "modifier": 0 }`;
  - `{ "targetTag": "enemy", "modifier": 0.2 }`;
  - all other resource tags use modifier `0`.
- Existing weapons can contact the node but deal `0` damage. Add an explicit
  `{ "targetTag": "stone", "modifier": 0 }` entry to each existing weapon so
  the specific stone rule wins before the broader `resource: 0.1` fallback.
  These hits do not show an additional “needs Pickaxe” message.
- A resolved modifier of `0` is a valid no-damage result. The combat pipeline
  must not clamp it to `1`, save resource health, show damage text, or spawn a
  confirmed resource-hit effect.
- When the node reaches zero health, it is removed and yields `30 stone` as
  three small piles. Each normal pile contains `10 stone` and uses the resource
  sheet visual at row `1`, column `1`.
- Piles use the existing `F` collect prompt, inventory stacking, floating reward
  text, depletion, and saved state behavior used by wood piles.

## Drop placement

- The first placement candidates are the eight cells surrounding the node’s
  original map cell, including diagonals.
- A candidate is free only when it is inside the map and does not conflict with
  authored collision/object occupancy or another spawned pile.
- If an adjacent candidate is blocked, search outward for the nearest free map
  cell until the three piles have positions.
- If fewer than three free positions exist, merge the total yield into the
  available piles. For example, one free position becomes a single `30 stone`
  pile; two positions become `10` and `20` piles.
- Amounts are assigned by deterministic pile index: allocate `10` to each
  selected position in candidate order, then add any remainder to the last
  selected pile. Thus two positions are always `10` then `20`, and one position
  is `30`.
- Spawned piles receive deterministic IDs derived from the source instance ID
  and their stable drop index, allowing their individual remaining amounts to
  persist without adding them to authored map JSON.
- Candidate order is deterministic: increasing Chebyshev distance from the
  source cell, then ascending row (`y`), then ascending column (`x`). The
  source cell is the final fallback after the large node is removed, so a
  destroyed node never loses its yield even when no neighboring cell is free.
- Cell occupancy is provided to the controller through a narrow callback that
  accounts for map collision terrain, authored solid-object footprints, and
  already-reserved dynamic pile cells. The callback also receives map bounds
  and tile size so the controller does not depend on `WorldScene`. The source
  node’s cell is explicitly ignored by this occupancy callback after the node
  is removed, allowing it to serve as the final fallback.
- Convert a persisted cell back to an object anchor using the map editor’s
  convention: `x = cellX * tileSize + tileSize / 2`,
  `y = (cellY + 1) * tileSize`.

## Persistence

- Partial stone-node health is runtime-only and resets to `40` after reload.
- Once a node is destroyed, its state is stored as a source record keyed by map
  ID and source instance ID:
  `{ stage: "destroyed", piles: [{ id, cellX, cellY, amount }] }`.
  Each pile’s cell and amount are restored exactly; placement is never
  re-simulated during reload. When all amounts reach zero, the source becomes
  `{ stage: "depleted", value: 0 }`.
- Existing wood `node`/`pile`/`depleted` records remain valid. Add the new
  destroyed-pile shape as an optional versioned union and migrate unknown or
  malformed pile entries by ignoring them rather than breaking old saves.
- Add an authored resource-node persistence policy. Wood keeps its current
  partial-health persistence; stone sets `persistHealth: false`, so `node`
  health records are ignored and reset on reload while destroyed records still
  restore their piles.
- Collecting a spawned pile saves its remaining amount; an emptied pile remains
  depleted after reload.

## Content and runtime architecture

- Add a stone resource-node archetype that references the existing resource
  sheet and authored collider/depth geometry.
- Give the node an authored destruction message (for example, `Stone broken`)
  instead of reusing the wood-specific `Tree felled` announcement.
- Keep the existing `ResourceNodeController` as the owner of node and pile
  behavior. Extend its replacement path to create multiple dynamic pile
  records through a narrow object-creation dependency rather than importing a
  scene or map-builder implementation. The dependency accepts an object ID,
  visual ID, world anchor, stable sort/instance ID, and initial state, and
  returns the created image plus its occlusion-registration disposer.
- Dynamic piles use the same catalog visual/application path as authored wood
  piles so scale, origin, depth, and interaction behavior remain consistent.
- Resource target registration must add the large node to combat target routing;
  dynamic piles must be removed from target/collision groups and added to the
  interaction group only.
- Saved resource progress must distinguish a live authored stone node from a
  destroyed source with a list of spawned pile records and remaining amounts.
- Add the Pickaxe weapon definition, its three-direction sprite asset, and an
  independent stone-chip impact effect asset/content definition. Use IDs
  `weapon.player.pickaxe-tiles`, `stone-impact`, and
  `effect.resource.stone-impact-tiles`; register the assets in
  `asset/assets.json` and boot content, and import the definitions into
  `virtual-weapon-content.ts` and `virtual-effect-content.ts`. Use the standard
  frame mapping (down `0`, side-right `1`, up `2`, left mirrored from right),
  and store the effect as the stone node's resource-owned `hitEffectId`, never
  on the Pickaxe or generic enemy-hit definition. The effect is resource-only
  and anchored at the confirmed hit position, not attached to the Pickaxe
  visual.
- Expand the hotbar to six slots for testing so the Pickaxe is immediately
  owned and assigned while all existing starter tools remain available.
- Add stone to the item registry and inventory icon mapping using the existing
  resource sheet’s matching thumbnail convention.
- Add authored stone-node visual variants to Level 1 for testing.

## Acceptance checks

1. `objects:check`, structural `maps:check`, `weapons:check`, `effects:check`,
   and `assets:check` validate the new node, map content, Pickaxe, and stone
   impact effect; runtime map/catalog loading validates the object references.
2. A fresh game grants and assigns the Pickaxe to the sixth hotbar slot for
   testing without removing the existing starter tools; selecting that slot
   equips it through the normal loadout flow.
3. The large stone node collides with the player and accepts only Pickaxe
   damage; existing weapons visibly contact it but leave its health unchanged,
   without fake minimum damage or resource-hit feedback.
4. Destroying a node removes its collision and creates three adjacent small
   piles with a total of `30 stone`, using diagonal positions when available.
5. Blocked positions trigger nearest-free search; insufficient space merges
   pile amounts without losing any stone.
6. `F` collection, inventory thumbnails/counts, save/reload, and depletion work
   for every spawned pile.
7. Partial node damage resets after reload, while destroyed sources and their
   pile states persist.
8. The Pickaxe’s stone-chip effect appears independently at the node hit point;
   it does not follow the tool or appear on enemies.
