extends Node
## A lock of several crystal lenses (crystal_lens.gd; docs/godot/BODY_SHAPES.md "The Bow"): once
## every lens in `lenses` is struck, it opens what it is tied to, once and for good: every node in
## `targets` is set off through the kit's generic hookup (DungeonState.fire: a hidden chest rises), the
## story flag `flag_id` is set when one is given, and `opened` is emitted. One lens alone opens nothing.
##
## The lake camp's river (level-1-c5, `CampRiverLenses/camp-river-lens-lock`) is the first: the Bow's
## first lock, two lenses on the river's north bank by the road and a hidden chest by the camp across
## the water.
##
## Its record is the kit's object state (DungeonState.mark_done under `lock_id`), so it opens once: a
## world built again with every lens struck leaves its targets to their own records (a risen chest
## stays up). The lenses tell it when they are struck, and again when a world is built with them struck.
##
## Owner: dungeons (the Crystal Mine's lenses).

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

## Payload {"lockId": String}: every lens is struck and the lock opened (once).
signal opened(payload: Dictionary)

## Its id (the object state's key).
@export var lock_id: String = ""
## The crystal lenses (CrystalLens) that must all be struck.
@export var lenses: Array[NodePath] = []
## What it sets off once they are (DungeonState.fire: a hidden dungeon chest's `appear`).
@export var targets: Array[NodePath] = []
## A story flag set when it opens ("" = none).
@export var flag_id: String = ""


func _ready() -> void:
	for path in lenses:
		var lens := get_node_or_null(path)
		if lens != null and lens.has_signal(&"struck") and not lens.is_connected(&"struck", _on_struck):
			lens.connect(&"struck", _on_struck)


## True once it opened (every lens struck).
func is_open() -> bool:
	return DungeonState.is_done(get_tree(), _key())


## How many of its lenses are struck.
func struck_count() -> int:
	var count := 0
	for path in lenses:
		var lens := get_node_or_null(path)
		if lens != null and lens.has_method(&"is_struck") and bool(lens.call(&"is_struck")):
			count += 1
	return count


func _on_struck(_payload: Dictionary) -> void:
	if not is_inside_tree() or is_open() or lenses.is_empty() or struck_count() < lenses.size():
		return
	DungeonState.mark_done(get_tree(), _key())
	for path in targets:
		DungeonState.fire(get_node_or_null(path), {"lock_id": lock_id})
	var run := Services.run()
	if run != null and not flag_id.is_empty():
		run.set_flag(flag_id)
	opened.emit({"lockId": lock_id})


func _key() -> String:
	return DungeonState.object_key(self, "lens-lock:" + (lock_id if not lock_id.is_empty() else String(name)))
