extends "res://game/scripts/chest.gd"
## A dungeon chest (docs/godot/DUNGEONS.md "Chests"; `object.dungeon-chest`, `object.dungeon-big-chest`):
## the game's chest (chest.gd: its record, the interaction prompt, the chest window) that can hold
## the dungeon's items. Put them in `initial_contents` as "dungeon-small-key", "dungeon-big-key",
## "dungeon-map" or "dungeon-compass" (count 1), beside any loot ("coins", potions...). Opened, the
## dungeon items go straight to the dungeon (DungeonItems.give: the counter, never the bag) with
## their ceremony or pop; what else it holds opens the chest window as any chest. Its record is the
## map's chest record, so an opened chest stays open (empty) after a faint, a quit or a load.
##
## `goo_heart_id` (chest.gd): a Goo Heart inside, lifted out and granted as it opens.
##
## `hidden`: it is not there until `appear()` (a room fight cleared, game/dungeon/room_fight.gd's
## `reward`; or any signal connected to `appear`): then it rises with a puff and the secret jingle,
## and stays (its appearance is recorded under `instance_id`).
##
## `map_id` may stay empty: the world's id is used; `instance_id` too: the chest root's name is used
## (give every chest of a world its own name).
##
## Owner: dungeon kit.

const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DungeonItems := preload("res://game/dungeon/dungeon_items.gd")

const CUE_APPEAR := &"SecretFound"
const PUFF := &"dodge-dust"
const SPARKLE := &"loot-sparkle"
const RISE_PX := 18.0
const RISE_S := 0.45

## The chest rose (`appear`). Payload: {"instanceId"}.
signal appeared(payload: Dictionary)

## Starts hidden until `appear()`.
@export var hidden: bool = false

var _shown := true


func _enter_tree() -> void:
	if map_id.is_empty():
		map_id = DungeonState.world_map_id(self)
	# Its record's id: `instance_id`, else the chest's own name (name every chest of a world apart).
	if instance_id.is_empty() and get_parent() != null:
		instance_id = String(get_parent().name)
	super()
	if hidden and _shown:
		# Hidden until its record says it rose (read once the Dungeon node is in the tree too).
		_set_shown(false)
		_show_if_recorded.call_deferred()


func _show_if_recorded() -> void:
	if is_inside_tree() and not _shown and DungeonState.is_done(get_tree(), _appear_key()):
		_set_shown(true)


## True once it stands in the room (not hidden).
func is_shown() -> bool:
	return _shown


## Rises into view (for good). Also takes any signal's payload, so a signal can be connected to it.
func appear(_payload: Variant = null) -> void:
	if _shown:
		return
	DungeonState.mark_done(get_tree(), _appear_key())
	_set_shown(true)
	var root := get_parent() as Node2D
	var feel := Services.feel()
	if feel != null and root != null:
		feel.audio_cue(CUE_APPEAR)
		feel.particles(PUFF, root.global_position)
		feel.particles(SPARKLE, root.global_position - Vector2(0.0, 30.0))
	var visual := _visual()
	if visual != null:
		var rest := visual.position
		visual.position = rest + Vector2(0.0, RISE_PX)
		visual.modulate.a = 0.0
		var tween := visual.create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "position", rest, RISE_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "modulate:a", 1.0, RISE_S * 0.6)
	appeared.emit({"instanceId": instance_id})


## Same as `appear` (the kit's generic hookup name).
func trigger(payload: Variant = null) -> void:
	appear(payload)


## Opening: the dungeon items go to the dungeon, the rest to the chest window (`chest.gd`), which
## opens once (one `open_requested`), after the heart's rise when a Goo Heart rises with them.
func request_open() -> String:
	if not _shown:
		return "hidden"
	var run := Services.run()
	var contents := remaining()
	var given := false
	if run != null and not is_heart_rising() and not DungeonState.current_id(get_tree()).is_empty():
		var kept := {}
		for content: String in contents:
			var item := DungeonState.item_of(content)
			if item.is_empty():
				kept[content] = contents[content]
				continue
			for _i in int(contents[content]):
				DungeonItems.give(get_tree(), item)
			given = true
		if given:
			run.set_chest_remaining(map_id, instance_id, kept)
			# A Goo Heart beside the dungeon items rises with them.
			_opened_giving(contents, give_heart())
			return "opened"
	return super()


## Its opening sound (chest.gd: on opening with a gift).
func _cue_open() -> void:
	var sfx := get_parent().get_node_or_null(^"OpenSfx") if get_parent() != null else null
	if sfx != null and sfx.has_method(&"play_cue"):
		sfx.call(&"play_cue", null)


func _appear_key() -> String:
	return DungeonState.object_key(self, "chest-appeared:" + instance_id)


func _set_shown(shown: bool) -> void:
	_shown = shown
	var root := get_parent() as CollisionObject2D
	if shown:
		add_to_group(GROUP)
	else:
		remove_from_group(GROUP)
	if root != null:
		root.visible = shown
		for shape: Node in root.find_children("*", "CollisionShape2D", false, false):
			(shape as CollisionShape2D).set_deferred(&"disabled", not shown)


func _visual() -> Node2D:
	var root := get_parent()
	return root.get_node_or_null(^"Visual") as Node2D if root != null else null
