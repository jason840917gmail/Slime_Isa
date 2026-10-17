extends "res://game/scripts/collectible.gd"
## A walk-over refill (docs/godot/DUNGEONS.md "Refills that grow back"): a goo heart (`heart`:
## `dungeon.refill.heartHp` health) or a few coins (`coins`: `dungeon.refill.potCoins`), what a pot
## leaves where it stood (pot_loot.gd). `spawn(kind, feet)` builds one on the world's entity layer
## (energy is the game's energy shard, game/combat/reactions/energy_shard.gd). A CollectibleScript:
## the slime's PickupArea finds it as it finds every pile; a heart is left lying while health is
## full. Not saved.
##
## Owner: dungeon kit.

const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const EnergyShard := preload("res://game/combat/reactions/energy_shard.gd")

const PICKUPS_ART := "res://asset/MAPS/objects/dungeon/pickups-2x2.webp"
## Cells of the pickups sheet: flower, bud, heart, coins.
const FRAME_OF := {"heart": 2, "coins": 3}
const PICKUP_LAYER := 7
const SEEKER_LAYER := 6
const DRAWN_PX := 26.0
const REASON_FULL := "health-full"
const REASON_INVALID := "invalid-collector"

## "heart" or "coins".
@export var kind: String = "heart"

var _taken := false


## Builds a `kind` pickup ("heart", "coins" or "energy") standing at `feet` (global). Null without a
## world.
static func spawn(pickup_kind: String, feet: Vector2) -> Node2D:
	var radius := DungeonState.number("refill.pickupRadiusPx", 22.0)
	if pickup_kind == "energy":
		return EnergyShard.spawn(feet, DungeonState.number("refill.potEnergy", 15.0), radius)
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null or not FRAME_OF.has(pickup_kind):
		return null
	var root := Node2D.new()
	root.name = "DungeonPickup"
	root.y_sort_enabled = true
	root.position = parent.to_local(feet)
	var visual := Sprite2D.new()
	visual.name = "Visual"
	var sheet := SheetSprite.load_picture(PICKUPS_ART)
	if sheet != null:
		visual.texture = sheet
		visual.hframes = 2
		visual.vframes = 2
		visual.frame = int(FRAME_OF[pickup_kind])
		var cell := sheet.get_size() / 2.0
		visual.scale = Vector2.ONE * DRAWN_PX / maxf(1.0, cell.x)
		visual.offset = Vector2(0.0, -cell.y * 0.5)
	root.add_child(visual)
	var area := Area2D.new()
	area.name = "PickupArea"
	area.collision_layer = 1 << (PICKUP_LAYER - 1)
	area.collision_mask = 1 << (SEEKER_LAYER - 1)
	area.monitoring = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	area.add_child(shape)
	root.add_child(area)
	var script_node: Node = (load("res://game/dungeon/dungeon_pickup.gd") as GDScript).new()
	script_node.name = "DungeonPickupScript"
	script_node.set(&"object_id", "collectible.dungeon-" + pickup_kind)
	script_node.set(&"pickup_area", area)
	script_node.set(&"kind", pickup_kind)
	script_node.set(&"bounce", true)
	root.add_child(script_node)
	parent.add_child.call_deferred(root)
	return root


func remaining() -> int:
	return 0 if _taken else 1


func request_pickup(collector: Area2D) -> Dictionary:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if _taken or player == null or collector == null or collector != player.call(&"get_pickup_area"):
		return _say({"status": "rejected", "moved": 0, "remaining": remaining(), "reason": REASON_INVALID})
	var feel := Services.feel()
	var at := pickup_area.global_position if pickup_area != null else Vector2.ZERO
	if kind == "heart":
		if int(player.call(&"get_hp")) >= int(player.call(&"get_max_hp")):
			return _say({"status": "rejected", "moved": 0, "remaining": remaining(), "reason": REASON_FULL})
		var healed := int(player.call(&"heal", int(DungeonState.number("refill.heartHp", 20.0))))
		if feel != null:
			feel.audio_cue(&"Heal")
			feel.floating_text(at - Vector2(0.0, TEXT_RISE), "+%d" % healed, &"green", false)
	else:
		var run := Services.run()
		var coins := int(DungeonState.number("refill.potCoins", 5.0))
		if run != null:
			run.add_coins(coins)
		if feel != null:
			feel.floating_text(at - Vector2(0.0, TEXT_RISE), "+%dc" % coins, &"yellow", false)
	_taken = true
	if feel != null:
		feel.particles(&"loot-sparkle", at - Vector2(0.0, 10.0))
	var result := _say({"status": "collected", "moved": 1, "remaining": 0})
	depleted.emit({"objectId": object_id, "x": at.x, "y": at.y})
	_free_owner()
	return result


func _say(result: Dictionary) -> Dictionary:
	pickup_resolved.emit(result)
	return result
