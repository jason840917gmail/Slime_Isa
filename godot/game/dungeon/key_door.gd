@tool
extends "res://game/dungeon/dungeon_door.gd"
class_name KeyDoor
## A locked dungeon door (docs/godot/DUNGEONS.md "Keys and locked doors"): `object.key-door` (small
## keys, one or two keyholes) and `object.boss-door` (`lock` "big": the big key). Walk into it with a
## key: a small-key door spends one small key per keyhole (DungeonState.spend_small_key), the
## keyhole's padlock springs open and drops (`dungeon.door.keyholeMs`), and with every keyhole open
## the door opens for good (its keyholes and its opening are in the dungeon's record). Two keyholes
## take two keys, one per push or one after the other while the slime keeps pushing; the record
## keeps a keyhole opened, so the second key can come later. The boss door opens with the big key,
## which stays held. Without a key it says `locked_text`. It opens from either side.
##
## Its padlocks are the Sprite2D children of `locks` (as many as `keyholes`; extra ones hide).
##
## Owner: dungeon kit.

const CUE_KEY := &"GateUnlock"
const SPARKLE := &"loot-sparkle"
const LOCK_FALL_PX := 22.0
## Two padlocks stand this far apart on the leaf (world px).
const LOCK_SPACING_PX := 44.0

## A keyhole opened. Payload: {"doorId", "open": keyholes open now, "keyholes"}.
signal keyhole_opened(payload: Dictionary)

## "small" (small keys, a keyhole each) or "big" (the big key: the boss door).
@export_enum("small", "big") var lock: String = "small"
## Keyholes of a small-key door (1 or 2; how much the lock needs shows on the door).
@export_range(1, 2) var keyholes: int = 1:
	set(value):
		keyholes = clampi(value, 1, 2)
		_show_locks()
## The line without a key ("" = the default for its lock and keyholes).
@export var locked_text: String = ""
## The padlocks' parent (their Sprite2D children, left to right).
@export var locks: Node2D



func _ready() -> void:
	super()
	_show_locks()


func _show_locks() -> void:
	if locks == null:
		return
	var sprites := _lock_sprites()
	for i in sprites.size():
		sprites[i].visible = lock == "small" and i < keyholes
		sprites[i].position.x = (float(i) - float(keyholes - 1) * 0.5) * LOCK_SPACING_PX


func _lock_sprites() -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	if locks != null:
		for child: Node in locks.get_children():
			if child is Sprite2D:
				out.append(child as Sprite2D)
	return out


## Keyholes open (from the record).
func open_keyholes() -> int:
	var run := Services.run()
	var id := DungeonState.current_id(get_tree())
	return DungeonState.keyholes_open(run, id, record_key()) if run != null and not id.is_empty() else 0


func default_text() -> String:
	if lock == "big":
		return "A great lock. It wants the big key."
	if keyholes > 1:
		return "Two locks. Each wants a small key."
	return "Locked. A small key opens it."


func _restore() -> void:
	super()
	if is_open():
		return
	var open := open_keyholes()
	var sprites := _lock_sprites()
	for i in mini(open, sprites.size()):
		sprites[i].visible = false


func _wants_retry() -> bool:
	var run := Services.run()
	var id := DungeonState.current_id(get_tree())
	if run == null or id.is_empty() or is_open():
		return false
	if lock == "big":
		return DungeonState.has_item(run, id, DungeonState.BIG_KEY)
	return DungeonState.small_keys(run, id) > 0 and DungeonState.keyholes_open(run, id, record_key()) < keyholes


func _on_push(_from_face: bool) -> void:
	var run := Services.run()
	var id := DungeonState.current_id(get_tree())
	if run == null or id.is_empty():
		say(locked_text if not locked_text.is_empty() else default_text())
		return
	if lock == "big":
		if DungeonState.has_item(run, id, DungeonState.BIG_KEY):
			_unlock_cue()
			open_for_good()
		else:
			say(locked_text if not locked_text.is_empty() else default_text())
		return
	var open := DungeonState.keyholes_open(run, id, record_key())
	if open >= keyholes:
		open_for_good()
		return
	if not DungeonState.spend_small_key(run, id):
		say(locked_text if not locked_text.is_empty() else default_text())
		return
	open = DungeonState.open_keyhole(run, id, record_key())
	_unlock_cue()
	_drop_lock(open - 1)
	keyhole_opened.emit({"doorId": door_id, "open": open, "keyholes": keyholes})
	if open >= keyholes:
		_open_after_locks.call_deferred()
	else:
		push_again_after(DungeonState.number("door.keyholeMs", 380.0))


func _open_after_locks() -> void:
	var wait := DungeonState.number("door.keyholeMs", 380.0) / 1000.0
	if is_inside_tree() and wait > 0.0:
		await get_tree().create_timer(wait, false).timeout
	if is_inside_tree():
		open_for_good()


func _unlock_cue() -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_KEY)
		feel.particles(SPARKLE, global_position - Vector2(0.0, 60.0))


## The padlock `index` springs open, then drops and fades (presentation, real time).
func _drop_lock(index: int) -> void:
	var sprites := _lock_sprites()
	if index < 0 or index >= sprites.size():
		return
	var padlock := sprites[index]
	if padlock.hframes > 1:
		padlock.frame = 1
	var tween := padlock.create_tween()
	var ms := DungeonState.number("door.keyholeMs", 380.0) / 1000.0
	tween.tween_interval(ms * 0.4)
	tween.set_parallel(true)
	tween.tween_property(padlock, "position:y", padlock.position.y + LOCK_FALL_PX, ms * 0.6).set_ease(Tween.EASE_IN)
	tween.tween_property(padlock, "modulate:a", 0.0, ms * 0.6)
	tween.chain().tween_callback(padlock.hide)
