extends Node2D
## Scene script `game.loose-prize` (`object.loose-prize`, game/scenes/objects/loose-prize.tscn;
## docs/godot/SKINS.md "Heavy"): a prize caught up high (a coin pouch snagged in a tree, a parcel on
## a ledge) that a Heavy Roll shakes loose (Direction "The skins": a Heavy Roll that hits a wall, a
## tree and so on shakes things loose, so objects fall; the lock-and-key table's "a tree bonk that
## shakes a prize loose"). Place its root where it lands, at the foot of the tree or the wall it is
## caught on; its picture (`Visual`) hangs `hang_height` above.
##
## - **A Heavy Roll's bonk** within reach (game/enemy/ground_shake.gd: a heavy shake whose radius
##   holds the root; the Heavy Roll's reaches `skins.heavy.looseRadiusPx`) shakes it loose: it falls,
##   bounces once, pays `coins` and spills `contents` ({item_id: count}) as loot piles, and the story
##   flag `flag_id` keeps it taken (read at load: gone for good).
## - A plain bonk's shake only makes it sway, saying `hint_text` (the clarity rule), at most every
##   HINT_EVERY_MS.
##
## Owner: skins.

const Services := preload("res://game/shared/services.gd")
const GroundShake := preload("res://game/enemy/ground_shake.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")

const MAIN_GROUP := &"world_main"
const FALL_S := 0.45
const BOUNCE_PX := 14.0
const BOUNCE_S := 0.22
const SWAY_RAD := 0.18
const SWAY_S := 0.7
const HINT_EVERY_MS := 2500.0
const HINT_RISE := 40.0
const COIN_RISE := 30.0
const CUE_FALL := &"DropPop"
const CUE_LAND := &"DropLand"
const CUE_COIN := &"Coin"

## Shaken loose. Payload: {"flagId", "coins", "contents"}.
signal shaken_loose(payload: Dictionary)

## Story flag set once it fell ("" = it comes back with the world).
@export var flag_id: String = ""
@export var coins: int = 0
## Items spilled where it lands ({item_id: count}).
@export var contents: Dictionary = {}
## How high it hangs above its root (world units).
@export var hang_height: float = 120.0
@export var hint_text: String = "Something up there wobbles... a heavier bump would shake it loose."

var _fallen := false
var _next_hint_ms := 0.0
var _visual: Node2D


func _enter_tree() -> void:
	add_to_group(GroundShake.GROUP)
	var run := Services.run()
	_fallen = not flag_id.is_empty() and run != null and run.has_flag(flag_id)


func _ready() -> void:
	_visual = get_node_or_null(^"Visual") as Node2D
	if _fallen:
		visible = false
		return
	if _visual != null:
		_visual.position.y = -hang_height


func is_fallen() -> bool:
	return _fallen


## GroundShake: a heavy shake reaching it shakes it loose; a light one makes it sway.
func on_ground_shake(at: Vector2, radius: float, heavy: bool) -> void:
	if _fallen or not is_visible_in_tree() or at.distance_to(global_position) > radius:
		return
	if heavy:
		shake_loose()
		return
	_sway()
	var now := float(Time.get_ticks_msec())
	if now >= _next_hint_ms:
		_next_hint_ms = now + HINT_EVERY_MS
		var feel := Services.feel()
		if feel != null and not hint_text.is_empty():
			feel.floating_text(global_position - Vector2(0.0, hang_height + HINT_RISE), hint_text, &"white", false, 2400.0)


## It falls, lands, pays out and is gone (a script may call it).
func shake_loose() -> void:
	if _fallen:
		return
	_fallen = true
	var run := Services.run()
	if run != null and not flag_id.is_empty():
		run.set_flag(flag_id)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_FALL)
	var world := Services.world()
	SkinState.show(world.player if world != null else null, SkinState.HEAVY)
	if _visual == null:
		_land()
		return
	var tween := create_tween()
	tween.tween_property(_visual, "position:y", 0.0, FALL_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		if feel != null:
			feel.audio_cue(CUE_LAND)
			feel.particles(&"dodge-dust", global_position))
	tween.tween_property(_visual, "position:y", -BOUNCE_PX, BOUNCE_S * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "position:y", 0.0, BOUNCE_S * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_land)


func _land() -> void:
	var run := Services.run()
	var feel := Services.feel()
	if coins > 0 and run != null:
		run.add_coins(coins)
		if feel != null:
			feel.audio_cue(CUE_COIN)
			feel.floating_text(global_position - Vector2(0.0, COIN_RISE), "+%dc" % coins, &"yellow", false)
	if not contents.is_empty():
		_drop(contents, global_position)
	shaken_loose.emit({"flagId": flag_id, "coins": coins, "contents": contents.duplicate()})
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.3)
	fade.tween_callback(func() -> void: visible = false)


func _sway() -> void:
	if _visual == null:
		return
	var tween := _visual.create_tween()
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(_visual):
			_visual.rotation = SWAY_RAD * (1.0 - t) * sin(t * TAU * 3.0), 0.0, 1.0, SWAY_S)


## The items as loot piles around `at` (main's EnemyLoot), else straight into the bag.
func _drop(items: Dictionary, at: Vector2) -> void:
	var run := Services.run()
	var world := Services.world()
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	var loot: Node = main.get(&"loot") as Node if main != null else null
	if loot != null and loot.has_method(&"drop_loot") and world != null:
		var list: Array = []
		for item_id: Variant in items:
			list.append({"item_id": str(item_id), "count": int(items[item_id])})
		loot.call(&"drop_loot", world.map_id(), at, list)
		return
	if run != null:
		for item_id: Variant in items:
			run.add_item(str(item_id), int(items[item_id]))
