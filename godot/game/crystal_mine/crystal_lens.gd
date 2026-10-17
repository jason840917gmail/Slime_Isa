extends Node2D
class_name CrystalLens
## The Bow's lock (docs/godot/DUNGEONS.md "The Crystal Mine (built)"; decisions archive question 127:
## "the Bow's target is a crystal lens on a post", never an eye): a round faceted lens in a brass ring
## on a wooden post, set across a gap in a straight line from where the slime stands. An arrow in it
## (the Bow, roadmap 12.6: `on_arrow_hit`, the group `bow_targets` every far target joins) strikes it
## for good: the lens glows gold and what it is tied to opens: every gate (group `gate`) whose
## `gate_id` is one of `opens` is opened for good (`open_for_good`, else `open`), every node in
## `targets` is set off through the kit's generic hookup (DungeonState.fire: a drawbridge's
## `trigger`), and `struck` is emitted for anything else listening.
##
## The Chasm's lens lowers its bridge (the main path's one Bow lock, question 102); the Great Shaft's
## spire lens (secret S1) swings the plank to the spire's heart quarter. Nothing else strikes it: a
## thrown pot falls short of a lens across a gap, and the Spear never reaches one.
##
## Struck for good is the kit's object state (DungeonState.mark_done), so it lasts.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const BOW_TARGETS := &"bow_targets"
const GATE_GROUP := &"gate"
const GROUP := &"crystal_lenses"
const FRAME_PLAIN := 0
const FRAME_STRUCK := 1
const CUE_STRIKE := &"Crit"
const TEXT_RISE := 120.0

## Payload {"lens_id": String}: the lens was struck (once, or again at load when it was).
signal struck(payload: Dictionary)

## Its id (the object state's key; the drawbridge it lowers names it).
@export var lens_id: String = ""
## The gate ids it opens when struck.
@export var opens: PackedStringArray = PackedStringArray()
## The kit pieces it sets off when struck (DungeonState.fire: a Drawbridge lowers for good).
@export var targets: Array[NodePath] = []
@export var visual: Sprite2D

var _struck: bool = false


func _enter_tree() -> void:
	add_to_group(BOW_TARGETS)
	add_to_group(GROUP)


func _ready() -> void:
	_struck = DungeonState.is_done(get_tree(), _key())
	_show()
	if _struck:
		_open_ties.call_deferred(true)


func is_struck() -> bool:
	return _struck


## The Bow's hook: an arrow hit the lens. True: the arrow is spent here.
func on_arrow_hit(_hit: Dictionary = {}) -> bool:
	if _struck:
		return true
	strike()
	return true


## Strikes it for good (an arrow; the tests and the film).
func strike() -> void:
	if _struck:
		return
	_struck = true
	DungeonState.mark_done(get_tree(), _key())
	_show()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_STRIKE)
		feel.particles(&"hit-spark", global_position - Vector2(0.0, TEXT_RISE * 0.6))
	_open_ties()


func _open_ties(at_load: bool = false) -> void:
	for node: Node in get_tree().get_nodes_in_group(GATE_GROUP):
		if str(node.get(&"gate_id")) in opens:
			if node.has_method(&"open_for_good"):
				node.call(&"open_for_good")
			elif node.has_method(&"open"):
				node.call(&"open")
	# At load the kit pieces keep their own records (a drawbridge stays down).
	if not at_load:
		for path in targets:
			DungeonState.fire(get_node_or_null(path), {"lens_id": lens_id})
	struck.emit({"lens_id": lens_id})


func _show() -> void:
	if visual != null:
		visual.frame = FRAME_STRUCK if _struck else FRAME_PLAIN


func _key() -> String:
	return DungeonState.object_key(self, "lens:" + (lens_id if not lens_id.is_empty() else name))
