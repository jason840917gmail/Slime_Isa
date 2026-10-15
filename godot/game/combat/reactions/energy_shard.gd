extends "res://game/scripts/collectible.gd"
## The energy shard pickup (owner, 2026-10-11: no energy back from hits, but an enemy may drop an
## energy shard when it dies; combat-feel plan section 4 "Energy"; BODY_SHAPES.md "Data"
## `combat.energyShard`). EnemyReactions.on_defeated rolls `dropChance` in the rework mode (never for
## training dummies) and calls `spawn`, which builds the pile in code: a Node2D root on the world's
## entity layer with the look (energy_shard_look.gd, the painted crystal that bobs and glows), a
## PickupArea on the pickup layer (radius `pickupRadiusPx`) and this script node.
##
## It is a CollectibleScript, so the slime finds it the way it finds every walk-over pickup: its
## PickupArea entering this one calls `player.on_pickup_area_entered`, which asks the first
## CollectibleScript sibling to `request_pickup` (the Stretch Lash's pickup reaches it too). The
## pickup restores `amount` energy through `player.restore_energy` and frees the shard; a slime with
## full energy leaves it lying (stepping off and on again retries, as for a full bag). It is not
## saved and goes after `combat.energyShard.fadeMs` when that is set (blinking for its last
## FADE_BLINK_MS), else it stays until picked up or the world is left.
##
## Owner: reactions.

const ShardLook := preload("res://game/combat/reactions/energy_shard_look.gd")
const Self := preload("res://game/combat/reactions/energy_shard.gd")

const ROOT_NAME := "EnergyShard"
const SCRIPT_NODE_NAME := "EnergyShardScript"
const OBJECT_ID := "collectible.energy-shard"
## collision-layers.json: "pickup" (layer 7) is what the slime's "pickup-seeker" (layer 6) monitors.
const PICKUP_LAYER := 7
const SEEKER_LAYER := 6
const CUE_PICKUP := &"EnergyRestore"
const TEXT_COLOR := &"cyan"
const SPARKLE := &"loot-sparkle"
const FADE_BLINK_MS := 1500.0
const REASON_INVALID := "invalid-collector"
const REASON_FULL := "energy-full"
const STATUS_COLLECTED := "collected"

## Energy restored on pickup (`combat.energyShard.amount`).
@export var amount: float = 0.0
## Simulation ms after which it goes (0 = never).
@export var lifetime_ms: float = 0.0

var _taken: bool = false
var _fade_at_ms: float = -1.0
var _look: Node2D


## Builds a shard at `feet` (global position, on the ground) on the world's entity layer, with
## `amount` energy and a pickup circle of `radius_px`; `lifetime_ms` > 0 makes it fade. Added
## deferred (the death that drops it may happen inside a physics callback). Null without a world.
static func spawn(feet: Vector2, energy: float, radius_px: float, lifetime: float = 0.0) -> Node2D:
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null:
		return null
	var root := Node2D.new()
	root.name = ROOT_NAME
	root.y_sort_enabled = true
	root.position = parent.to_local(feet)
	var look := ShardLook.new()
	look.name = "Visual"
	root.add_child(look)
	var area := Area2D.new()
	area.name = "PickupArea"
	area.collision_layer = 1 << (PICKUP_LAYER - 1)
	area.collision_mask = 1 << (SEEKER_LAYER - 1)
	area.monitoring = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = maxf(1.0, radius_px)
	shape.shape = circle
	area.add_child(shape)
	root.add_child(area)
	var script_node: Node = Self.new()
	script_node.name = SCRIPT_NODE_NAME
	script_node.set(&"object_id", OBJECT_ID)
	script_node.set(&"pickup_area", area)
	script_node.set(&"amount", energy)
	script_node.set(&"lifetime_ms", lifetime)
	script_node.set(&"bounce", false)
	root.add_child(script_node)
	parent.add_child.call_deferred(root)
	return root


func _ready() -> void:
	super()
	_look = get_parent().get_node_or_null(^"Visual") as Node2D if get_parent() != null else null
	if lifetime_ms > 0.0:
		_fade_at_ms = Services.now_ms() + lifetime_ms


func _physics_process(_delta: float) -> void:
	if _fade_at_ms < 0.0 or _taken:
		return
	var left := _fade_at_ms - Services.now_ms()
	if left <= 0.0:
		_taken = true
		_free_owner()
	elif _look != null:
		_look.set(&"blink", left < FADE_BLINK_MS)


## One until it is taken (CollectibleScript: a pile with nothing left frees itself).
func remaining() -> int:
	return 0 if _taken else 1


## The slime's PickupArea (`collector`) touched it: the energy, a sparkle, the cue and "+N" in cyan,
## then it goes. Rejected for another collector, or while the slime's energy is full.
func request_pickup(collector: Area2D) -> Dictionary:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if _taken or player == null or collector == null or not player.has_method(&"get_pickup_area") \
			or collector != player.call(&"get_pickup_area"):
		return _answer({"status": "rejected", "moved": 0, "remaining": remaining(), "reason": REASON_INVALID})
	if player.has_method(&"get_energy") and player.has_method(&"get_max_energy") \
			and float(player.call(&"get_energy")) >= float(player.call(&"get_max_energy")):
		return _answer({"status": "rejected", "moved": 0, "remaining": remaining(), "reason": REASON_FULL})
	var gained := float(player.call(&"restore_energy", amount)) if player.has_method(&"restore_energy") else 0.0
	_taken = true
	var feel := Services.feel()
	var at := pickup_area.global_position if pickup_area != null else Vector2.ZERO
	if feel != null:
		feel.audio_cue(CUE_PICKUP)
		feel.particles(SPARKLE, at - Vector2(0.0, SPARKLE_RISE))
		if gained > 0.0:
			feel.floating_text(at - Vector2(0.0, TEXT_RISE), "+%d" % roundi(gained), TEXT_COLOR, false)
	var result := _answer({"status": STATUS_COLLECTED, "moved": 1, "remaining": 0})
	depleted.emit({"objectId": OBJECT_ID, "x": at.x, "y": at.y})
	_free_owner()
	return result


func _answer(result: Dictionary) -> Dictionary:
	pickup_resolved.emit(result)
	return result
