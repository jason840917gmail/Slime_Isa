extends Node
class_name ChestScript
## Scene script `game.chest` (Phaser `features/scripts/ChestScript.ts`; interaction spec 3.4, 6.3).
## Persistent contents in `RunState.map_record(map_id).chests` (created from `initial_contents`
## on first sight); a live boss camp may guard the chest. Opening emits `open_requested` and hands
## the chest to the chest window (`CHEST_VIEW_SERVICE`: the first node of group `chest_window`,
## game/ui/screens/chest_window.gd, `open_chest`); each stack moved into the bag emits
## `stack_transferred`; closing tells the window (`close_for`) and emits `closed`. Leaving the tree
## while open closes the window without `closed` (Phaser's entry disposable, owner decision K4).
##
## A heart quarter inside (`goo_heart_id`; owner, 2026-10-17: most hearts are hidden in chests,
## found by curiosity; a quarter since 2026-10-26): opening the chest the first time lifts the
## quarter out of it (it rises over the chest, as Zelda's heart piece) and grants it as the pickup
## does (goo_heart.gd `grant`: the flag "goo-heart.<id>", one quarter; the fourth completes a heart),
## once; when it has risen (HEART_RISE_MS of gameplay time) the chest shows "Heart quarter 2 of 4"
## (or "Heart complete!") and asks for the ceremony (goo_heart.gd `celebrate`). The flag is the record:
## the chest counts as holding something until it is set, and is empty (open) after, in every save.
## With only the heart inside, no chest window opens; with other things too, the window shows them
## after the heart has risen and its ceremony has played (Zelda's order: the window pauses the world,
## which would freeze the rise). A load or a travel during the rise frees the chest and skips both.
##
## Owner: interaction.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const GooHeart := preload("res://game/scripts/goo_heart.gd")
const ItemPop := preload("res://game/dungeon/item_pop.gd")
const AbilityCeremony := preload("res://game/ui/ceremony/ability_ceremony.gd")

const GROUP := &"chest"
const BOSS_CAMP_GROUP := &"boss_camp"
const VIEW_GROUP := &"chest_window"
## The heart rising out of the chest: from this far above the chest's feet, this much higher, this
## big, over this long (the picture on real time, the text, the ceremony and the window after it on
## the gameplay clock).
const HEART_FROM_PX := 34.0
const HEART_RISE_PX := 46.0
const HEART_SIZE_PX := 40.0
const HEART_RISE_MS := 1500.0
const HEART_SPARKLE := &"loot-sparkle"

## JSON `mapId`.
@export var map_id: String = ""
## JSON `instanceId`.
@export var instance_id: String = ""
## JSON `initialContents`: {item_id: positive count}.
@export var initial_contents: Dictionary = {}
## A Goo Heart inside: its heart id (unique across maps, as an `object.goo-heart`'s); empty: none.
@export var goo_heart_id: String = ""

## The chest is guarded by a live boss. Payload: {"instanceId"}.
signal guard_blocked(payload: Dictionary)
## The chest opened. Payload: {"mapId", "instanceId", "contents"}.
signal open_requested(payload: Dictionary)
## A stack moved into the bag. Payload: {"itemId", "moved"}.
signal stack_transferred(payload: Dictionary)
## The chest closed. Payload: {"instanceId"}.
signal closed(payload: Dictionary)

var _open: bool = false
## The gameplay time its given heart has risen (-1: no heart rising); then its text and ceremony
## (`_heart_celebrated`), then the window on what else it holds.
var _heart_risen_ms: float = -1.0
var _heart_celebrated: bool = false
var _heart_at: Vector2 = Vector2.ZERO
var _heart_icon: Texture2D


func _enter_tree() -> void:
	add_to_group(GROUP)
	var run := Services.run()
	if run != null:
		run.ensure_chest(map_id, instance_id, positive_counts(initial_contents))


func _ready() -> void:
	set_physics_process(false)


func _exit_tree() -> void:
	# Gone during the rise (a load, a travel): no text, ceremony or window after it.
	_heart_risen_ms = -1.0
	set_physics_process(false)
	if _open:
		_open = false
		var view := _view()
		if view != null:
			view.call(&"close_for", instance_id)


## Old Phaser position of the chest (its parent).
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return FeetAnchor.phaser_position(parent) if parent != null else Vector2.ZERO


## A copy of what is left inside.
func remaining() -> Dictionary:
	var run := Services.run()
	return run.chest_remaining(map_id, instance_id) if run != null else {}


func is_empty() -> bool:
	return remaining().is_empty() and not holds_heart()


## True while its Goo Heart is still inside (it has one and its flag is not set).
func holds_heart() -> bool:
	return not goo_heart_id.is_empty() and not GooHeart.is_heart_taken(goo_heart_id)


## A live boss camp guards this chest (BossCampScript.isChestGuarded).
func is_guarded() -> bool:
	for camp: Node in get_tree().get_nodes_in_group(BOSS_CAMP_GROUP):
		if camp.has_method(&"is_chest_guarded") and bool(camp.call(&"is_chest_guarded", instance_id)):
			return true
	return false


## "guarded" (emits `guard_blocked`) or "opened" (emits `open_requested`, then the chest window
## shows this chest; an empty chest opens too). A chest giving its heart opens the window on the
## rest once the heart has risen (`_opened_giving`); asked again meanwhile, it waits.
func request_open() -> String:
	if is_guarded():
		guard_blocked.emit({"instanceId": instance_id})
		return "guarded"
	if is_heart_rising():
		return "opened"
	var contents := remaining()
	if give_heart():
		_opened_giving(contents, true)
		return "opened"
	return _open_window()


## True from the moment it gives its heart until the window on what else it holds opens.
func is_heart_rising() -> bool:
	return _heart_risen_ms >= 0.0


## The chest window shows it (emits `open_requested`).
func _open_window() -> String:
	open_requested.emit({"mapId": map_id, "instanceId": instance_id, "contents": remaining()})
	_show_window()
	return "opened"


func _show_window() -> void:
	_open = true
	var view := _view()
	if view != null:
		view.call(&"open_chest", self)


## The chest opened giving things away (its heart when `heart`; a dungeon chest's items): its
## opening sound and one `open_requested` (`contents`: what it held besides the heart) now, then
## the window on what is left, if anything: at once, or after the heart's rise and ceremony.
func _opened_giving(contents: Dictionary, heart: bool) -> void:
	sync_frame()
	_cue_open()
	open_requested.emit({"mapId": map_id, "instanceId": instance_id, "contents": contents})
	if heart:
		_heart_risen_ms = Services.now_ms() + HEART_RISE_MS
		_heart_celebrated = false
		set_physics_process(true)
	elif not remaining().is_empty():
		_show_window()


## Its given heart: once it has risen, the text and the ceremony; once no ceremony plays or waits,
## the window on what else it holds.
func _physics_process(_delta: float) -> void:
	if not is_heart_rising() or Services.now_ms() < _heart_risen_ms:
		return
	if not _heart_celebrated:
		_heart_celebrated = true
		GooHeart.celebrate(get_tree(), 1, _heart_at, _heart_icon)
	var ceremony := get_tree().root.get_node_or_null(AbilityCeremony.NODE_NAME)
	if ceremony != null and (bool(ceremony.call(&"is_playing")) or int(ceremony.call(&"waiting")) > 0):
		return
	_heart_risen_ms = -1.0
	set_physics_process(false)
	if not remaining().is_empty():
		_show_window()


## Lifts its Goo Heart out and grants it (goo_heart.gd `grant`; its text and ceremony follow the
## rise: `_physics_process`); false when it holds none.
func give_heart() -> bool:
	if not holds_heart():
		return false
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return false
	var root := get_parent() as Node2D
	var at := root.global_position if root != null else origin()
	var icon := GooHeart.default_icon()
	if not GooHeart.grant(get_tree(), player, goo_heart_id, 1, at, icon, false):
		return false
	_heart_at = at
	_heart_icon = icon
	ItemPop.spawn(icon, at - Vector2(0.0, HEART_FROM_PX), HEART_RISE_PX, HEART_SIZE_PX, HEART_RISE_MS)
	var feel := Services.feel()
	if feel != null:
		feel.particles(HEART_SPARKLE, at - Vector2(0.0, HEART_FROM_PX + HEART_RISE_PX))
	return true


## The opening sound of a chest that gave something away as it opened: a world chest's scene plays
## it on `open_requested`; the dungeon chest plays its own.
func _cue_open() -> void:
	pass


## Moves what fits into the bag, or coins into the pouch; emits `stack_transferred` on a take.
func transfer_stack(item_id: String) -> int:
	var run := Services.run()
	var moved := 0
	if run != null and item_id == "coins":
		var contents := remaining()
		moved = int(contents.get("coins", 0))
		if moved > 0:
			contents.erase("coins")
			run.set_chest_remaining(map_id, instance_id, contents)
			run.add_coins(moved)
	elif run != null:
		moved = run.transfer_chest_stack(map_id, instance_id, item_id)
	if moved > 0:
		stack_transferred.emit({"itemId": item_id, "moved": moved})
	return moved


## `ChestScript.close`: the window lets go of this chest (a no-op when it closed itself first),
## then `closed`.
func close() -> void:
	_open = false
	var view := _view()
	if view != null:
		view.call(&"close_for", instance_id)
	closed.emit({"instanceId": instance_id})


## The chest window (group `chest_window`), or null.
func _view() -> Node:
	return get_tree().get_first_node_in_group(VIEW_GROUP) if is_inside_tree() else null


## `syncChestFrame`: the first Sprite2D under the chest root shows frame 1 when empty, else 0.
func sync_frame() -> void:
	var root := get_parent()
	if root == null:
		return
	var sprites := root.find_children("*", "Sprite2D", true, false)
	if sprites.is_empty():
		return
	var visual := sprites[0] as Sprite2D
	var frame := 1 if is_empty() else 0
	if visual.frame != frame and visual.hframes * visual.vframes > frame:
		visual.frame = frame


## `recordOfPositiveIntegers`: entries whose count is a whole number > 0.
static func positive_counts(contents: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in contents:
		var value: Variant = contents[key]
		if (value is int or value is float) and float(value) == roundf(float(value)) and float(value) > 0.0:
			out[str(key)] = int(value)
	return out
