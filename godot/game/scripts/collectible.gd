extends Node
class_name CollectibleScript
## Scene script `game.collectible` (Phaser `features/scripts/CollectibleScript.ts` +
## `features/collectibles/CollectibleController.ts`). World-objects spec 7. Child
## "CollectibleScript" of the pile's Node2D root.
##
## Walk-over pickup: the player's PickupArea entering this pile's PickupArea calls
## `request_pickup` once (edge-triggered: after a partial or full-bag pickup the player steps off
## and on again). As much as fits moves into the bag (RunState.collect_world_item); the rest stays.
## An emptied pile is freed; an authored pile already taken frees itself when the world loads.
##
## The pickup bounce (owner decision 2026-10-05, not in Phaser): every walk-over pickup hops a few
## pixels now and then, so it catches the eye and reads apart from resource nodes (stone, iron,
## trees), which never move. A tween on the Visual relative to its own offset and scale (worlds
## override both per instance), starting at a random moment so neighbouring piles never hop
## together, and only while the pile can be picked up (a dropped pile's flight owns the Visual until
## it lands). `bounce = false` turns it off for a pickup.
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ResourceDrops := preload("res://game/world_objects/resource_drops.gd")
const EnemyLoot := preload("res://game/world_objects/enemy_loot.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")

## JSON `mapId`.
@export var map_id: String = ""
## JSON `instanceId` (authored instance id, or "<node>-drop-<n>" for a resource pile).
@export var instance_id: String = ""
## JSON `objectId` (e.g. "collectible.wood-pile").
@export var object_id: String = ""
## JSON `itemId` (items.json id).
@export var item_id: String = ""
## JSON `quantity` (`max(1, floor(quantity))`).
@export var quantity: int = 1
## JSON `sourceResourceInstanceId`: the node that dropped this pile ("" = authored).
@export var source_resource_instance_id: String = ""
## JSON `sourceInventoryDropId`: the bag drop this pile is ("" = none; bag drops are OUT).
@export var source_inventory_drop_id: String = ""
## JSON `pickupArea`: the Area2D (layer 64, monitorable) the player's PickupArea overlaps.
@export var pickup_area: Area2D
## The pickup bounce (see the file comment).
@export var bounce: bool = true

## Every pickup request. Payload: {"status": "collected"|"partial", "moved", "remaining"} or
## {"status": "rejected", "moved": 0, "remaining", "reason"}.
signal pickup_resolved(payload: Dictionary)
## The pile was emptied. Payload: the pickup request (camelCase keys, spec 1.5).
signal depleted(payload: Dictionary)

## CollectibleController.ts:77-91 and WorldScene.ts:435 (literals).
const TEXT_RISE := 34.0
const INVENTORY_HINT_MS := 1000.0
const SPARKLE_RISE := 24.0
const PURPLE_BERRY := "purple-berry-mat"
## CollectibleReactionController.ts:33.
const BERRY_COINS := 5
const GROUP := &"collectible"
## The bounce: the hop's height in world px, its rise and fall, the squash on landing, and the rest
## between hops (a random time in the range).
const BOUNCE_HEIGHT := 6.0
const BOUNCE_UP_S := 0.16
const BOUNCE_DOWN_S := 0.13
const BOUNCE_SQUASH := Vector2(1.1, 0.9)
const BOUNCE_SQUASH_S := 0.1
const BOUNCE_REST_S := Vector2(1.1, 1.9)
## The first hop comes this long after the pile appears (random in the range).
const BOUNCE_FIRST_S := Vector2(0.2, 1.6)

## One "Inventory full" hint per second for every pile (Phaser: one per world controller).
static var _inventory_hint_ready_at_ms: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	if pickup_area == null:
		push_error("CollectibleScript '%s' requires its pickup_area reference" % instance_id)
	if remaining() <= 0:
		# Authored and already taken (mountAuthoredWorld frees it).
		_free_owner()
		return
	if bounce:
		_queue_bounce(randf_range(BOUNCE_FIRST_S.x, BOUNCE_FIRST_S.y))


## The saved record's remaining, else the authored or spawned quantity.
func remaining() -> int:
	var run := Services.run()
	var record := run.collectible_record(map_id, instance_id) if run != null else {}
	return int(record["remaining"]) if record.has("remaining") else maxi(1, quantity)


## `requestPickup` (CollectibleScript.ts:76-102); `collector` is the player's PickupArea.
func request_pickup(collector: Area2D) -> Dictionary:
	var pos := pickup_area.global_position if pickup_area != null else Vector2.ZERO
	var request := {"mapId": map_id, "instanceId": instance_id, "objectId": object_id,
		"itemId": item_id, "requested": remaining(),
		"collectorAreaNodeId": str(collector.get_path()) if collector != null and collector.is_inside_tree() else "",
		"x": pos.x, "y": pos.y}
	if not source_resource_instance_id.is_empty():
		request["sourceResourceInstanceId"] = source_resource_instance_id
	if not source_inventory_drop_id.is_empty():
		request["sourceInventoryDropId"] = source_inventory_drop_id
	var result := _pickup(request, collector, pos)
	pickup_resolved.emit(result)
	if str(result["status"]) != "rejected" and int(result["remaining"]) == 0:
		depleted.emit(request)
		_free_owner()
	return result


func _pickup(request: Dictionary, collector: Area2D, pos: Vector2) -> Dictionary:
	var world := Services.world()
	var player = world.player if world != null else null
	if player == null or collector == null or collector != player.get_pickup_area():
		return _rejected(remaining(), "invalid-collector")
	var left := remaining()
	if left <= 0:
		return _rejected(0, "depleted")
	# Read before the pickup: an emptied drop's record goes with it.
	var recovered := EnemyLoot.is_recovered(map_id, source_inventory_drop_id)
	var run := Services.run()
	var moved := run.collect_world_item(map_id, instance_id, item_id, left, int(request["requested"]),
			source_resource_instance_id, source_inventory_drop_id)
	var feel := Services.feel()
	if moved <= 0:
		var now := float(Time.get_ticks_msec())
		if now >= _inventory_hint_ready_at_ms and feel != null:
			_inventory_hint_ready_at_ms = now + INVENTORY_HINT_MS
			feel.floating_text(pos - Vector2(0.0, TEXT_RISE), "Inventory full", &"white", true)
		return _rejected(left, "inventory-full")
	var next := run.collectible_record(map_id, instance_id)
	var rest := int(next.get("remaining", left - moved))
	var source := str(next.get("source_resource_instance_id", source_resource_instance_id))
	if not source.is_empty():
		ResourceDrops.on_pile_changed(map_id, source, instance_id, rest)
	if not source_inventory_drop_id.is_empty():
		EnemyLoot.on_pile_changed(map_id, source_inventory_drop_id, rest)
	if feel != null:
		feel.floating_text(pos - Vector2(0.0, TEXT_RISE), "+%d %s" % [moved, ItemCatalog.item_name(item_id)], &"yellow", false)
	_on_collected(player, moved, recovered)
	return {"status": "collected" if rest == 0 else "partial", "moved": moved, "remaining": rest}


## `collectible.collected` listeners: the loot sparkle over the slime (WorldScene.ts:435-437) and
## the purple berry reaction (eat clip, +5 coins per berry; CollectibleReactionController.ts).
## `recovered`: the pile was the player's own bag drop (no coins again).
func _on_collected(player: Node, moved: int, recovered: bool) -> void:
	var feel := Services.feel()
	if feel != null and player.has_method(&"get_centre"):
		feel.particles(&"loot-sparkle", player.get_centre() - Vector2(0.0, SPARKLE_RISE))
	if item_id == PURPLE_BERRY and not recovered:
		if player.has_method(&"play_action_clip"):
			player.play_action_clip("eat")
		Services.run().add_coins(BERRY_COINS * moved)
	# Quests (CollectibleController.ts:92-99): loot piles count, the player's own bag drop does not.
	var event := {"mapId": map_id, "instanceId": instance_id, "objectId": object_id, "itemId": item_id, "quantity": moved}
	if recovered:
		event["recovered"] = true
	QuestEvents.emit(QuestEvents.COLLECTIBLE_COLLECTED, event)


## The pile's art: the first Sprite2D under its root (the `Visual`).
func _visual() -> Sprite2D:
	var root := get_parent()
	if root == null:
		return null
	var visual := root.get_node_or_null(^"Visual") as Sprite2D
	if visual != null:
		return visual
	var sprites := root.find_children("*", "Sprite2D", true, false)
	return sprites[0] as Sprite2D if not sprites.is_empty() else null


## The next hop after `delay_s` (the tween lives on the Visual, so it pauses with the tree and ends
## with the pile).
func _queue_bounce(delay_s: float) -> void:
	var visual := _visual()
	if visual == null or not visual.is_inside_tree():
		return
	var wait := visual.create_tween()
	wait.tween_interval(delay_s)
	wait.tween_callback(_bounce_once)


## One hop: up, down, a squash on landing, back to rest; then the next one. A pile that cannot be
## picked up yet (still flying) waits.
func _bounce_once() -> void:
	var visual := _visual()
	if visual == null or not is_inside_tree():
		return
	if pickup_area != null and not pickup_area.monitorable:
		_queue_bounce(0.3)
		return
	var base_offset := visual.offset
	var base_scale := visual.scale
	var lift := Vector2(0.0, BOUNCE_HEIGHT / maxf(absf(base_scale.y), 0.001))
	var hop := visual.create_tween()
	hop.tween_property(visual, ^"offset", base_offset - lift, BOUNCE_UP_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(visual, ^"offset", base_offset, BOUNCE_DOWN_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hop.tween_property(visual, ^"scale", base_scale * BOUNCE_SQUASH, BOUNCE_SQUASH_S * 0.4)
	hop.tween_property(visual, ^"scale", base_scale, BOUNCE_SQUASH_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hop.tween_interval(randf_range(BOUNCE_REST_S.x, BOUNCE_REST_S.y))
	hop.tween_callback(_bounce_once)


func _rejected(left: int, reason: String) -> Dictionary:
	return {"status": "rejected", "moved": 0, "remaining": left, "reason": reason}


func _free_owner() -> void:
	if pickup_area != null:
		pickup_area.set_deferred(&"monitorable", false)
	var owner_root := get_parent()
	if owner_root != null and not owner_root.is_queued_for_deletion():
		owner_root.queue_free()
