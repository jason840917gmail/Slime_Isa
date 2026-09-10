# Inventory World Drops Design

**Status:** Approved for implementation on 2026-09-10.

## Goal

Let the player move stackable non-equipment items from inventory into the
current map without destroying them. Inventory drops use the shared world-drop
arc and landing behavior, become collectible only after settling, and survive
save/load. Permanent Remove actions remain available.

Weapon and equipment dropping is deferred until each weapon has an authored
ground presentation and its equipped/loadout behavior is defined.

## Player behavior

- The quantity selector controls both Remove and Drop actions.
- Non-equipment details offer `Drop N` and `Drop All` in addition to the
  existing permanent removal actions.
- Dropping closes the inventory, removes the chosen quantity, and launches one
  physical pickup from the player to a nearby valid ground position.
- The pickup contains the full selected quantity and cannot be collected until
  it lands.
- Walking over it afterward returns as much as inventory capacity allows.
- A partial pickup leaves the remainder on the ground.
- Player-created drops remain on their owning map across reloads and map visits.

## Content ownership

Each droppable item explicitly declares a ground presentation containing an
object archetype ID and visual ID. Existing wood, stone, iron, charcoal, and
purple-berry collectible definitions are reused. Potions, silk, and crystal
shards receive collectible object definitions backed by their existing
procedural textures. Equipment has no ground presentation in this slice, so
the UI does not offer Drop for it.

Explicit item metadata avoids ambiguous inference: multiple object archetypes
may collect into the same item ID, while inventory dropping needs one stable
appearance.

## Runtime architecture

`InventoryDropController` owns player-created drop placement, inventory/world
state coordination, reconstruction, and collection-linked cleanup. It receives
narrow dependencies for player position/facing, blocked-cell checks, inventory
removal/restoration, and `WorldDropSpawner.spawn()`.

The controller chooses the first valid nearby tile in deterministic facing-
first order. It stores the final anchor and presentation in map-scoped world
progress before submitting a launch request. Restored records use settled mode.

`InventoryUI` remains presentation-only. It calculates the selected amount and
calls an injected drop callback. A successful request updates selection and
closes the modal so the unpaused world displays the launch.

## Persistence and IDs

Each map runtime state adds:

- `inventoryDrops`, a record of active player-created drops; and
- `nextInventoryDropSequence`, a monotonic map-local sequence.

Each record stores stable ID, item ID, quantity, object/visual IDs, and final
anchor. Existing saves migrate by defaulting both fields to empty/one without
changing authored maps.

Collection state changes identify an inventory-drop source ID. The controller
updates the record after partial collection and deletes it after full
collection. The sequence never moves backward, so a collected instance ID is
not reused and cannot collide with stale collectible progress.

## Transaction and failure behavior

Before changing inventory, validate quantity, content mapping, placement, and
spawn request data. Then remove inventory, persist the drop record/sequence,
and spawn in one synchronous operation before recovery autosave can run. If
persistence or spawning throws, delete the pending record and restore the exact
quantity to inventory. A failed request reports a visible message and keeps the
inventory open.

If no nearby valid ground position exists, nothing changes. Scene teardown
cancels active presentation through the shared spawner; the persisted record
restores settled on the next visit.

## Verification

- Drop N and Drop All remove exactly the requested amount without invoking
  permanent Remove behavior.
- Every current non-equipment item resolves to a valid collectible ground
  presentation; equipment does not.
- New drops launch from the player and activate pickup only after settling.
- Full and partial recollection update both inventory and persisted drop data.
- Reload and map re-entry reconstruct active drops settled at exact anchors.
- IDs remain unique after collection, reload, and another drop.
- Invalid quantity, missing presentation, blocked placement, and spawn failure
  leave inventory and world progress unchanged.
- Persistence, collectible, UI, content, typecheck, and production build checks
  pass.
