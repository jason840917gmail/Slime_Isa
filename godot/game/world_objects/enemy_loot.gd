extends Node
## Enemy rewards (Phaser `CombatController.awardEnemyDefeat` + `InventoryDropController.dropLoot`
## / `restore` + `LootDropPlacement.ts`). A child of main that hears every enemy's
## `reward_requested` (it connects to each enemy as it enters the tree): the coins are paid at
## once ("+10c", yellow, 20 px above the corpse), and each loot item that wins its chance roll
## falls as a pile scattered around the corpse (golden-angle rings of 0.45 / 0.6 / 0.75 tiles,
## squashed 0.7 vertically, skipping blocked cells; on the corpse when all are blocked). Each pile
## is recorded in its map's `inventory_drops` before it flies, so it is back on the next load until
## it is picked up; an item with no ground look goes straight into the bag.
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")
const ResourceDrops := preload("res://game/world_objects/resource_drops.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")

const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))
const LOOT_RINGS: Array[float] = [0.45, 0.6, 0.75]
const LOOT_VERTICAL_SCALE := 0.7
const LOOT_TURNS := 8
const COIN_TEXT_RISE := 20.0
const ORIGIN_LOOT := "loot"
## EnemyScript.RANK_BOSS: Fatty and the Matron.
const RANK_BOSS := "boss"

## An enemy died and its rewards were paid. Payload: {"enemyId", "kind", "x", "y"} (quests).
signal enemy_died(payload: Dictionary)


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node.has_signal(&"reward_requested") and node.has_method(&"get_centre"):
		var callback := _on_reward.bind(node)
		if not node.is_connected(&"reward_requested", callback):
			node.connect(&"reward_requested", callback)


## `awardEnemyDefeat`: coins, then the loot rolls.
func _on_reward(payload: Dictionary, enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	var at: Vector2 = enemy.call(&"get_centre")
	var rewards: Dictionary = payload.get("rewards", {}) if payload.get("rewards") is Dictionary else {}
	var run := Services.run()
	var world := Services.world()
	# The enemy's kind is its character scene ("worm-swordsman"), as Phaser's `config.id`.
	var root := enemy.get_parent()
	var kind := root.scene_file_path.get_file().get_basename() if root != null else ""
	enemy_died.emit({"enemyId": str(enemy.get_instance_id()), "kind": kind, "x": at.x, "y": at.y})
	# Quests: `enemy.died` for ordinary enemies only (bosses, rank "boss", report through their camp).
	if str(enemy.get(&"rank")) != RANK_BOSS:
		QuestEvents.emit(QuestEvents.ENEMY_DIED, {"enemyId": enemy.get_instance_id(),
			"areaId": world.map_id() if world != null else "", "kind": kind})
	var coins := int(rewards.get("coins", 0))
	if coins > 0 and run != null:
		run.add_coins(coins)
		var feel := Services.feel()
		if feel != null:
			feel.floating_text(at - Vector2(0.0, COIN_TEXT_RISE), "+%dc" % coins, &"yellow", false)
	var items: Array = []
	for entry: Variant in rewards.get("items", []):
		if not entry is Dictionary:
			continue
		if randf() < float(entry.get("chance", 0.0)):
			items.append({"item_id": str(entry.get("itemId", "")), "count": int(entry.get("count", 1))})
	if not items.is_empty() and world != null:
		drop_loot(world.map_id(), at, items)


## `dropLoot`: one pile per item around `at` (old centre of the corpse).
func drop_loot(map_id: String, at: Vector2, items: Array) -> void:
	var run := Services.run()
	var world := Services.world()
	if run == null or world == null or world.dimensions().is_empty():
		return
	var ts := int(world.dimensions()["tile_size"])
	var destinations := scatter(at, items.size(), ts, _blocked_test(ts))
	for index in items.size():
		var item: Dictionary = items[index]
		var count := int(item["count"])
		if count <= 0:
			continue
		var item_id := str(item["item_id"])
		var definition := _ground_look(item_id)
		if definition.is_empty():
			run.add_item(item_id, count)
			continue
		var record := create_drop(map_id, {"item_id": item_id, "amount": count, "object_id": definition["objectId"],
			"visual_id": definition["visualId"], "x": destinations[index].x, "y": destinations[index].y, "origin": ORIGIN_LOOT})
		ResourceDrops.spawn_pile(str(definition["objectId"]), str(record["id"]), map_id, count, "", destinations[index], at, index, str(record["id"]))


## `restore`: the map's uncollected drops come back settled.
func restore_world() -> void:
	var run := Services.run()
	var world := Services.world()
	if run == null or world == null:
		return
	var map_id := world.map_id()
	var drops: Dictionary = run.map_record(map_id)["inventory_drops"]
	for id: String in drops:
		var record: Dictionary = drops[id]
		var definition := _ground_look(str(record.get("item_id", "")))
		if definition.is_empty() or int(record.get("amount", 0)) <= 0 or str(definition["objectId"]) != str(record.get("object_id", "")):
			continue
		ResourceDrops.spawn_pile(str(record["object_id"]), id, map_id, int(record["amount"]), "",
			Vector2(float(record.get("x", 0.0)), float(record.get("y", 0.0))), null, 0, id)


## A new drop record "inventory-drop-<n>" in `map_id` (WorldProgress.createInventoryDrop).
static func create_drop(map_id: String, drop: Dictionary) -> Dictionary:
	return Services.run().create_inventory_drop(map_id, drop)


## After a pickup from drop pile `drop_id` (InventoryDropController.onCollectibleStateChanged):
## the record keeps what is left and goes at 0.
static func on_pile_changed(map_id: String, drop_id: String, remaining: int) -> void:
	var run := Services.run()
	if run != null:
		run.set_inventory_drop_amount(map_id, drop_id, remaining)


## True when the drop is the player's own bag drop rather than enemy loot (it does not count as
## newly collected).
static func is_recovered(map_id: String, drop_id: String) -> bool:
	if drop_id.is_empty():
		return false
	var run := Services.run()
	var record: Variant = (run.map_record(map_id)["inventory_drops"] as Dictionary).get(drop_id) if run != null else null
	return record is Dictionary and str(record.get("origin", "")) != ORIGIN_LOOT


## `scatterLootDestinations`: where each of `count` pieces lands around `source`.
static func scatter(source: Vector2, count: int, ts: int, blocked: Callable) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for index in maxi(0, count):
		var radius := ts * LOOT_RINGS[index % LOOT_RINGS.size()]
		var chosen := Vector2(roundf(source.x), roundf(source.y))
		for turn in LOOT_TURNS:
			var angle := index * GOLDEN_ANGLE + turn * TAU / LOOT_TURNS
			var point := Vector2(roundf(source.x + cos(angle) * radius), roundf(source.y + sin(angle) * radius * LOOT_VERTICAL_SCALE))
			if not bool(blocked.call(point)):
				chosen = point
				break
		points.append(chosen)
	return points


## `isLootPointBlocked`: the cell under (x, y - 1) is solid or holds an authored root.
static func _blocked_test(ts: int) -> Callable:
	var occupied := ResourceDrops.occupied_cells("", ts)
	return func(point: Vector2) -> bool:
		var cell := Vector2i(floori(point.x / ts), floori((point.y - 1.0) / ts))
		var world := Services.world()
		return world == null or world.is_solid_tile(cell.x, cell.y) or occupied.has(cell)


## `resolveInventoryDropDefinition`: items.json `worldDrop` {objectId, visualId} for a plain item
## (not a weapon) whose pile scene exists; {} otherwise.
static func _ground_look(item_id: String) -> Dictionary:
	var definition := ItemCatalog.definition(item_id)
	var look: Variant = definition.get("worldDrop")
	if not look is Dictionary or definition.has("equipment"):
		return {}
	var world := Services.world()
	var object_id := str((look as Dictionary).get("objectId", ""))
	if object_id.is_empty() or world == null or world.scene_path("object." + object_id.replace(".", "-")).is_empty():
		return {}
	return look
