extends RefCounted
## Resource drops (Phaser `features/resources/ResourceNodeController.ts`,
## `ResourceDropPlacement.ts`, `UniversalSceneWorldController.spawnWorldDrop/animateWorldDrop`,
## `collectibles/WorldDropMotion.ts`). World-objects spec 5.
##
## A broken node drops `pieces` piles of its drop scene, each holding the scene's authored
## quantity. They land on the free cells nearest the node, by Chebyshev distance then row then
## column, starting from the cell above the node's anchor; a boxed-in node stacks the extra piles
## on that cell with golden-angle offsets. Phaser sorts the whole grid against every authored
## root for each break; this walks rings outward over a precomputed occupied set (same order).
## The piles fly out in a 280 ms arc and can be picked up once they settle. Their records keep the
## node "destroyed" until every pile is collected, then "depleted" (which can regrow).
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const CollectibleScript := preload("res://game/scripts/collectible.gd")

## WorldDropMotion.ts:6-13.
const FLIGHT_MS := 280.0
const STAGGER_MS := 60.0
const REBOUND_MS := 40.0
const SETTLE_MS := 60.0
const REBOUND_HEIGHT := 4.0
## Arc height `clamp(0.45 × distance, 28, 56)` (WorldDropMotion.ts:15-22).
const ARC_FACTOR := 0.45
const ARC_MIN := 28.0
const ARC_MAX := 56.0
## ResourceDropPlacement.ts:11-19.
const GOLDEN_ANGLE := 2.399963229728653
## Depletion text: yellow, big, 46 px above the node (ResourceNodeController.ts:110).
const DEPLETION_TEXT_RISE := 46.0
const DEFAULT_DEPLETION_MESSAGE := "Resource depleted"
const OBJECT_SCENE_PREFIX := "object."

## object id -> authored pile quantity (read once per scene).
static var _quantities: Dictionary = {}


## The source cell of a node anchored at `anchor` (cellForAnchor): one row above its tile.
static func source_cell(anchor: Vector2, ts: int) -> Vector2i:
	return Vector2i(floori(anchor.x / ts), floori(anchor.y / ts) - 1)


## Cells held by authored roots of the registered world other than `source_instance_id`
## (isAuthoredCellOccupied): every instance root placed directly in the world scene (owner =
## world root, `metadata/instance_id`), at `(floor(x/ts), floor((y-1)/ts))` of its old Phaser
## root position. Runtime piles, the player and enemies never block.
static func occupied_cells(source_instance_id: String, ts: int) -> Dictionary:
	var cells := {}
	var world := Services.world()
	if world == null or not is_instance_valid(world.world_root):
		return cells
	var world_root := world.world_root
	for node: Node in world_root.find_children("*", "Node2D", true, false):
		if node.owner != world_root or not node.has_meta(&"instance_id") or node.is_queued_for_deletion():
			continue
		if str(node.get_meta(&"instance_id")) == source_instance_id:
			continue
		var point := FeetAnchor.phaser_position(node as Node2D)
		cells[Vector2i(floori(point.x / ts), floori((point.y - 1.0) / ts))] = true
	return cells


## Cells of the piles still lying in `map_id` (amount > 0 in "destroyed" records).
static func reserved_cells(map_id: String) -> Dictionary:
	var cells := {}
	var run := Services.run()
	if run == null:
		return cells
	var resources: Dictionary = run.map_record(map_id)["resources"]
	for key: String in resources:
		var record: Dictionary = resources[key]
		if str(record.get("stage", "")) != "destroyed":
			continue
		for pile: Dictionary in record.get("piles", []):
			if int(pile.get("amount", 0)) > 0:
				cells[Vector2i(int(pile.get("cell_x", 0)), int(pile.get("cell_y", 0)))] = true
	return cells


## Up to `limit` free cells around `source`, nearest first (Chebyshev rings, each in row then
## column order), skipping the source, cells outside the grid and cells `blocked` rejects.
static func find_drop_cells(source: Vector2i, limit: int, blocked: Callable, columns: int, rows: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	if limit <= 0:
		return found
	var max_ring := maxi(columns, rows)
	for ring in range(1, max_ring + 1):
		for y in range(source.y - ring, source.y + ring + 1):
			var edge_row := absi(y - source.y) == ring
			var xs: Array = range(source.x - ring, source.x + ring + 1) if edge_row else [source.x - ring, source.x + ring]
			for x: int in xs:
				if x < 0 or y < 0 or x >= columns or y >= rows:
					continue
				var cell := Vector2i(x, y)
				if blocked.is_valid() and bool(blocked.call(cell)):
					continue
				found.append(cell)
				if found.size() >= limit:
					return found
	return found


## Scatter of the `occurrence`-th pile sharing a cell (stableOffset): (0, 0) for the first, then
## golden-angle steps of radius `min(0.42·ts, 0.1·ts·√k)`, rounded.
static func stable_offset(ts: int, occurrence: int) -> Vector2i:
	if occurrence <= 0:
		return Vector2i.ZERO
	var angle := occurrence * GOLDEN_ANGLE
	var radius := minf(0.42 * ts, 0.1 * ts * sqrt(float(occurrence)))
	return Vector2i(roundi(cos(angle) * radius), roundi(sin(angle) * radius))


## `completeDropPlacements`: the free cells padded with `fallback` up to `pieces`, each with the
## offset for how many earlier entries share its cell. [{"cell": Vector2i, "offset": Vector2i}].
static func complete_placements(cells: Array[Vector2i], fallback: Vector2i, pieces: int, ts: int) -> Array[Dictionary]:
	var chosen: Array[Vector2i] = []
	for index in mini(cells.size(), pieces):
		chosen.append(cells[index])
	while chosen.size() < pieces:
		chosen.append(fallback)
	var seen := {}
	var placements: Array[Dictionary] = []
	for cell in chosen:
		var occurrence: int = seen.get(cell, 0)
		seen[cell] = occurrence + 1
		placements.append({"cell": cell, "offset": stable_offset(ts, occurrence)})
	return placements


## A pile's world position: the bottom-centre of its cell plus its offset.
static func pile_position(cell: Vector2i, offset: Vector2i, ts: int) -> Vector2:
	return Vector2(cell.x * ts + ts / 2.0 + offset.x, (cell.y + 1) * ts + offset.y)


## Spec 5.1 (`spawnManagedResourceDrops`): records the node as "destroyed" with its piles, launches
## them from the node and shows the depletion text. `request` is the `drops_requested` payload
## (camelCase keys).
static func spawn_for(request: Dictionary) -> void:
	var world := Services.world()
	var run := Services.run()
	if world == null or run == null or world.dimensions().is_empty():
		return
	var dims := world.dimensions()
	var ts := int(dims["tile_size"])
	var map_id := str(request.get("mapId", ""))
	var instance_id := str(request.get("instanceId", ""))
	var drop_object_id := str(request.get("dropObjectId", ""))
	var origin := Vector2(float(request.get("x", 0.0)), float(request.get("y", 0.0)))
	var pieces := maxi(1, int(request.get("pieces", 1)))
	var amount := authored_quantity(drop_object_id)
	if amount <= 0:
		return
	var source := source_cell(origin, ts)
	var occupied := occupied_cells(instance_id, ts)
	var reserved := reserved_cells(map_id)
	var blocked := func(cell: Vector2i) -> bool:
		return world.is_solid_tile(cell.x, cell.y) or occupied.has(cell) or reserved.has(cell)
	var cells := find_drop_cells(source, pieces, blocked, int(dims["columns"]), int(dims["rows"]))
	var placements := complete_placements(cells, source, pieces, ts)
	var piles: Array = []
	for index in placements.size():
		var placement: Dictionary = placements[index]
		var cell: Vector2i = placement["cell"]
		var offset: Vector2i = placement["offset"]
		var pile := {"id": "%s-drop-%d" % [instance_id, index + 1], "cell_x": cell.x, "cell_y": cell.y,
			"amount": amount, "object_id": drop_object_id, "visual_id": str(request.get("dropVisualId", ""))}
		if offset.x != 0:
			pile["offset_x"] = offset.x
		if offset.y != 0:
			pile["offset_y"] = offset.y
		piles.append(pile)
	run.set_resource_record(map_id, instance_id, {"stage": "destroyed", "value": float(amount * piles.size()), "piles": piles})
	for index in piles.size():
		var pile: Dictionary = piles[index]
		var destination := pile_position(Vector2i(pile["cell_x"], pile["cell_y"]),
				Vector2i(int(pile.get("offset_x", 0)), int(pile.get("offset_y", 0))), ts)
		spawn_pile(drop_object_id, str(pile["id"]), map_id, amount, instance_id, destination, origin, index)
	var feel := Services.feel()
	if feel != null:
		var message := str(request.get("depletionMessage", DEFAULT_DEPLETION_MESSAGE))
		feel.floating_text(origin - Vector2(0.0, DEPLETION_TEXT_RISE), message, &"yellow", true)


## Spec 5.5 (`restoreDynamicDrops`): a "destroyed" node's uncollected piles come back settled at
## their saved cells; none left -> the record becomes "depleted" (its timer kept).
static func restore(map_id: String, source_id: String, record: Dictionary, drop_definition: Dictionary) -> void:
	var world := Services.world()
	var run := Services.run()
	if world == null or run == null or world.dimensions().is_empty():
		return
	var ts := int(world.dimensions()["tile_size"])
	var active: Array = []
	for pile: Dictionary in record.get("piles", []):
		if int(pile.get("amount", 0)) > 0:
			active.append(pile)
	if active.is_empty():
		run.set_resource_record(map_id, source_id, {"stage": "depleted", "value": 0.0})
		return
	for pile: Dictionary in active:
		var object_id := str(pile.get("object_id", drop_definition.get("objectId", "")))
		var destination := pile_position(Vector2i(int(pile.get("cell_x", 0)), int(pile.get("cell_y", 0))),
				Vector2i(int(pile.get("offset_x", 0)), int(pile.get("offset_y", 0))), ts)
		spawn_pile(object_id, str(pile.get("id", "")), map_id, int(pile["amount"]), source_id, destination, null, 0)


## Spec 5.6 (`onCollectibleStateChanged`): after a pickup from pile `pile_id` of node `source_id`.
static func on_pile_changed(map_id: String, source_id: String, pile_id: String, remaining: int) -> void:
	var run := Services.run()
	if run == null or source_id.is_empty():
		return
	var record := run.resource_record(map_id, source_id)
	if record.is_empty() or str(record.get("stage", "")) != "destroyed" or not record.has("piles"):
		return
	var piles: Array = []
	var total := 0
	for pile: Dictionary in record["piles"]:
		var copy := pile.duplicate()
		if str(copy.get("id", "")) == pile_id:
			copy["amount"] = remaining
		if int(copy.get("amount", 0)) > 0:
			piles.append(copy)
			total += int(copy["amount"])
	if piles.is_empty():
		run.set_resource_record(map_id, source_id, {"stage": "depleted", "value": 0.0})
	else:
		run.set_resource_record(map_id, source_id, {"stage": "destroyed", "value": float(total), "piles": piles})


## Mounts a pile (`spawnWorldDrop`): `object.<object id with "." -> "-">` under the world's
## entities root with its collectible overrides set before it enters the tree. `launch_from` (a
## Vector2) flies it there from the node, pickable only once it settles; null places it settled.
## `source_id` names the resource node that dropped it, `inventory_drop_id` the loot or bag drop.
static func spawn_pile(object_id: String, pile_id: String, map_id: String, amount: int, source_id: String,
		destination: Vector2, launch_from: Variant, launch_index: int, inventory_drop_id: String = "") -> Node2D:
	var world := Services.world()
	if world == null:
		return null
	var parent := world.entities_root()
	var instance := world.instantiate_scene(OBJECT_SCENE_PREFIX + object_id.replace(".", "-"))
	var root := instance as Node2D
	if root == null or parent == null:
		if instance != null:
			instance.free()
		push_error("ResourceDrops: cannot spawn pile scene for '%s'" % object_id)
		return null
	var script := _collectible_of(root)
	if script == null or script.object_id != object_id or script.pickup_area == null:
		push_error("ResourceDrops: '%s' has no matching CollectibleScript with a pickup area" % object_id)
		root.free()
		return null
	script.map_id = map_id
	script.instance_id = pile_id
	script.quantity = amount
	script.source_resource_instance_id = source_id
	script.source_inventory_drop_id = inventory_drop_id
	var start: Vector2 = launch_from if launch_from is Vector2 else destination
	root.position = _local_point(parent, start)
	if launch_from is Vector2:
		script.pickup_area.monitorable = false
	parent.add_child(root)
	root.reset_physics_interpolation()
	if launch_from is Vector2:
		_launch(root, script.pickup_area, parent, start, destination, launch_index)
	return root


## The authored `quantity` of a pile scene (CollectibleScript of `object.<id>`), cached.
static func authored_quantity(object_id: String) -> int:
	if _quantities.has(object_id):
		return _quantities[object_id]
	var world := Services.world()
	if world == null:
		return 0
	var instance := world.instantiate_scene(OBJECT_SCENE_PREFIX + object_id.replace(".", "-"))
	if instance == null:
		return 0
	var script := _collectible_of(instance)
	var quantity := script.quantity if script != null else 0
	instance.free()
	if quantity <= 0:
		push_error("ResourceDrops: pile scene '%s' needs a positive quantity" % object_id)
		return 0
	_quantities[object_id] = quantity
	return quantity


static func _collectible_of(root: Node) -> CollectibleScript:
	for child: Node in root.get_children():
		if child is CollectibleScript:
			return child
	return null


static func _local_point(parent: Node, global_point: Vector2) -> Vector2:
	var item := parent as CanvasItem
	if item != null and item.is_inside_tree():
		return item.get_global_transform().affine_inverse() * global_point
	return global_point


## The flight (spec 5.4): a stagger, a 280 ms linear arc, a squash on landing, a 40 ms rebound and
## a 60 ms settle; then the pile can be picked up. Tweens on the pile pause with the tree
## (hit-stop, menus), like Phaser's scene tweens.
static func _launch(root: Node2D, area: Area2D, parent: Node, from: Vector2, to: Vector2, launch_index: int) -> void:
	var visual: Sprite2D = null
	var sprites := root.find_children("*", "Sprite2D", true, false)
	if not sprites.is_empty():
		visual = sprites[0]
	var base_scale := visual.scale if visual != null else Vector2.ONE
	var height := clampf(ARC_FACTOR * from.distance_to(to), ARC_MIN, ARC_MAX)
	var place := func(point: Vector2) -> void:
		if is_instance_valid(root):
			root.position = _local_point(parent, point)
	var squash := func(scale: Vector2) -> void:
		if visual != null and is_instance_valid(visual):
			visual.scale = base_scale * scale
	var tween := root.create_tween()
	tween.tween_interval(launch_index * STAGGER_MS / 1000.0)
	tween.tween_method(func(t: float) -> void:
		place.call(from + (to - from) * t - Vector2(0.0, 4.0 * height * t * (1.0 - t))), 0.0, 1.0, FLIGHT_MS / 1000.0)
	tween.tween_callback(func() -> void:
		place.call(to)
		squash.call(Vector2(1.12, 0.82)))
	tween.tween_method(func(p: float) -> void:
		place.call(to - Vector2(0.0, REBOUND_HEIGHT * p))
		squash.call(Vector2(1.12 - 0.16 * p, 0.82 + 0.22 * p)), 0.0, 1.0, REBOUND_MS / 1000.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(p: float) -> void:
		place.call(to - Vector2(0.0, REBOUND_HEIGHT * (1.0 - p)))
		squash.call(Vector2(0.96 + 0.04 * p, 1.04 - 0.04 * p)), 0.0, 1.0, SETTLE_MS / 1000.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		place.call(to)
		squash.call(Vector2.ONE)
		if is_instance_valid(area):
			area.set_deferred(&"monitorable", true))
