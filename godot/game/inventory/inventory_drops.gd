extends RefCounted
## Dropping bag items on the ground (Phaser `features/collectibles/InventoryDropController.ts`
## `dropFromSlot`, `InventoryDropPlacement.ts`, `content/items/InventoryDropCatalog.ts`).
## Crafting spec 6.5.
##
## A drop takes up to the requested count from one bag slot, records it in the map's
## `inventory_drops` ("inventory-drop-<n>", RunState.create_inventory_drop) and launches one pile
## of the item's ground look from the player to the first free cell two or more cells ahead
## (ResourceDrops.spawn_pile with the drop id). The pile updates its record when picked up
## (collectible.gd -> EnemyLoot.on_pile_changed) and comes back settled on the next load
## (EnemyLoot.restore_world restores every drop record of the map). Weapons and items without a
## ground look (the workbench) cannot be dropped.
##
## Owner: crafting / inventory.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ResourceDrops := preload("res://game/world_objects/resource_drops.gd")
const CollectibleScript := preload("res://game/scripts/collectible.gd")
const Directions := preload("res://game/shared/directions.gd")

const OPEN := "open"
const BLOCKED := "blocked"
const COMPATIBLE_STACK := "compatible-stack"
## InventoryDropController.ts: the refusal text, white, big, 1800 ms, 42 px above the centre.
const NO_SPACE_TEXT := "No ground space available"
const SPAWN_FAILED_TEXT := "Could not drop item"
const TEXT_RISE := 42.0
const TEXT_MS := 1800.0
const COLLECTIBLE_GROUP := &"collectible"


## `resolveInventoryDropDefinition`: the item's `worldDrop` {objectId, visualId} when it is a plain
## item (not a weapon) whose pile scene exists and collects that same item; {} otherwise.
static func ground_look(item_id: String) -> Dictionary:
	var definition := ItemCatalog.base_definition(item_id)
	var look: Variant = definition.get("worldDrop")
	if not look is Dictionary or definition.has("equipment"):
		return {}
	var object_id := str((look as Dictionary).get("objectId", ""))
	var world := Services.world()
	if object_id.is_empty() or world == null or world.scene_path("object." + object_id.replace(".", "-")).is_empty():
		return {}
	return look


static func can_drop(item_id: String) -> bool:
	return not ground_look(item_id).is_empty()


## `findInventoryDropDestination` (InventoryDropPlacement.ts:17-67): from the source cell
## `(floor(x/ts), floor(y/ts) - 1)`, rings of Chebyshev radius 2, 3, ... (radius 1 is skipped so
## the pile is not picked up again at once); each ring's cells sorted by how far ahead they are
## (desc), how far aside (|side| asc, then side desc: the facing's left first), then row, then
## column. A same-item drop pile ahead is reused (its point); otherwise the first open cell of the
## nearest ring that has one. `facing` is a direction (snapped to a cardinal), `dims` =
## {"tile_size", "columns", "rows"}, `inspect` (cell -> {"kind": "open" | "blocked" |
## "compatible-stack", "x"?, "y"?}). Returns the landing point (Vector2) or null.
static func find_destination(source: Vector2, facing: Vector2, dims: Dictionary, inspect: Callable) -> Variant:
	var ts := int(dims.get("tile_size", 0))
	var columns := int(dims.get("columns", 0))
	var rows := int(dims.get("rows", 0))
	if ts <= 0 or columns <= 0 or rows <= 0:
		return null
	var origin := Vector2i(floori(source.x / ts), floori(source.y / ts) - 1)
	var forward := Directions.cardinal_vector(Directions.cardinal_name(facing))
	var left := Vector2(forward.y, -forward.x)
	for radius in range(2, maxi(columns, rows) + 1):
		var ring: Array[Dictionary] = []
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				if maxi(absi(x - origin.x), absi(y - origin.y)) != radius:
					continue
				if x < 0 or y < 0 or x >= columns or y >= rows:
					continue
				var offset := Vector2(x - origin.x, y - origin.y)
				ring.append({"cell": Vector2i(x, y), "ahead": offset.dot(forward), "side": offset.dot(left)})
		ring.sort_custom(_ring_order)
		var open: Variant = null
		for entry in ring:
			var cell: Vector2i = entry["cell"]
			var found: Variant = inspect.call(cell)
			var state: Dictionary = found if found is Dictionary else {"kind": BLOCKED}
			match str(state.get("kind", BLOCKED)):
				COMPATIBLE_STACK:
					return Vector2(float(state.get("x", 0.0)), float(state.get("y", 0.0)))
				OPEN:
					if open == null:
						open = cell
		if open != null:
			var chosen: Vector2i = open
			return Vector2(chosen.x * ts + ts / 2.0, (chosen.y + 1) * ts)
	return null


## The world's cell test for dropping `item_id` (InventoryDropController.ts:68-76,
## WorldScene.ts:1673-1688): a drop record of the map on that cell -> "compatible-stack" for the
## same item, else "blocked"; outside the world, a solid tile, an authored root or a live pile ->
## "blocked"; else "open".
static func world_inspector(map_id: String, item_id: String) -> Callable:
	var world := Services.world()
	var run := Services.run()
	var ts := int(world.dimensions().get("tile_size", 64)) if world != null else 64
	var drops: Array = run.inventory_drops(map_id) if run != null else []
	var occupied := ResourceDrops.occupied_cells("", ts)
	var piles := {}
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for node: Node in tree.get_nodes_in_group(COLLECTIBLE_GROUP):
			var pile := node as CollectibleScript
			if pile == null:
				continue
			var root := pile.get_parent() as Node2D
			if root == null or root.is_queued_for_deletion() or pile.remaining() <= 0:
				continue
			piles[Vector2i(floori(root.global_position.x / ts), floori((root.global_position.y - 1.0) / ts))] = true
	return func(cell: Vector2i) -> Dictionary:
		for record: Dictionary in drops:
			var x := float(record.get("x", 0.0))
			var y := float(record.get("y", 0.0))
			if Vector2i(floori(x / ts), floori(y / ts) - 1) == cell:
				if str(record.get("item_id", "")) == item_id:
					return {"kind": COMPATIBLE_STACK, "x": x, "y": y}
				return {"kind": BLOCKED}
		if world == null or world.is_solid_tile(cell.x, cell.y) or occupied.has(cell) or piles.has(cell):
			return {"kind": BLOCKED}
		return {"kind": OPEN}


## `dropFromSlot(slotIndex, requested)`: drops min(requested, slot count) of bag slot `index` in
## front of the player. False (and the bag untouched) when nothing can be dropped there.
static func drop_from_slot(index: int, requested: int) -> bool:
	var run := Services.run()
	var world := Services.world()
	var player: Node = world.player if world != null else null
	var slots: Array = run.slots() if run != null else []
	if player == null or not is_instance_valid(player) or index < 0 or index >= slots.size() or requested <= 0:
		return false
	var slot: Dictionary = slots[index]
	var item_id := str(slot.get("item_id", ""))
	var look := ground_look(item_id)
	if look.is_empty():
		return false
	var quantity := mini(int(slot.get("count", 0)), requested)
	var map_id := world.map_id()
	var source: Vector2 = player.call(&"get_centre")
	var facing: Vector2 = player.call(&"get_facing")
	var destination: Variant = find_destination(source, facing, world.dimensions(), world_inspector(map_id, item_id))
	if not destination is Vector2:
		_text(source - Vector2(0.0, TEXT_RISE), NO_SPACE_TEXT)
		return false
	var removed := run.remove_from_slot(index, quantity)
	if removed != quantity:
		if removed > 0:
			run.add_item(item_id, removed)
		return false
	var landing: Vector2 = destination
	var record := run.create_inventory_drop(map_id, {"item_id": item_id, "amount": quantity,
		"object_id": str(look.get("objectId", "")), "visual_id": str(look.get("visualId", "")),
		"x": landing.x, "y": landing.y})
	var drop_id := str(record["id"])
	var pile := ResourceDrops.spawn_pile(str(look.get("objectId", "")), drop_id, map_id, quantity, "", landing, source, 0, drop_id)
	if pile == null:
		run.set_inventory_drop_amount(map_id, drop_id, 0)
		run.add_item(item_id, quantity)
		_text(source - Vector2(0.0, TEXT_RISE), SPAWN_FAILED_TEXT)
		return false
	return true


static func _ring_order(a: Dictionary, b: Dictionary) -> bool:
	if float(a["ahead"]) != float(b["ahead"]):
		return float(a["ahead"]) > float(b["ahead"])
	if absf(float(a["side"])) != absf(float(b["side"])):
		return absf(float(a["side"])) < absf(float(b["side"]))
	if float(a["side"]) != float(b["side"]):
		return float(a["side"]) > float(b["side"])
	var cell_a: Vector2i = a["cell"]
	var cell_b: Vector2i = b["cell"]
	if cell_a.y != cell_b.y:
		return cell_a.y < cell_b.y
	return cell_a.x < cell_b.x


static func _text(at: Vector2, text: String) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(at, text, &"white", true, TEXT_MS)
