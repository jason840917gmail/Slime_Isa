extends Node2D
class_name HeapHatch
## A hatch in the ground under a heap of light things (`object.heap-hatch`; docs/godot/specs/
## world-objects.md "The heap hatch"; first placed over Yoi's home in Lili's west yard, level-1-c4,
## owner 2026-10-16, questions 99 and 128). Like the prologue's blocked path
## (game/prologue/prologue_director.gd `path_blocked`), the slime clears it with the Gulp:
##
## - **Shut** while any liftable (group `liftable`: a LiftableScript whose root is not on its way
##   out) lies on it, its root inside `cover_rect` (relative to this node): the lid shows shut
##   (`visual`'s frame FRAME_SHUT) and its door (`door`, a door.gd of kind `ladder_down`) leads
##   nowhere (its trigger is off).
## - **Opens** the moment the last one is gulped away (or thrown off: anything that takes it off the
##   cover): the lid swings up (FRAME_OPEN) with a puff of dust and the door sound, the secret jingle
##   plays (`SecretFound`, as the prologue's cleared path) when something had lain on it since the
##   world was built, `opened` fires, and the story flag `flag_id` keeps it open for good.
## - **Open for good** (the flag set): built again, the heap (every liftable lying on the cover, and
##   any left in its old "Heap" child) is taken out before the slime sees it, and the hatch lies open.
##
## Place the heap's things as children of the hatch's own node (or anywhere over the cover), never
## inside its "Heap" child: Godot drops nodes added inside an instanced scene on any save of the world
## while that instance is not marked editable, which lost Yoi's crates more than once (2026-11-21).
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")

const FRAME_SHUT := 0
const FRAME_OPEN := 1
const CUE_SECRET := &"SecretFound"
const CUE_OPEN := &"DoorUse"
const DUST := &"dodge-dust"
## The dust puffs this far over the node (the lid's middle).
const DUST_RISE_PX := 30.0

## The hatch opened. Payload: {"flagId"}.
signal opened(payload: Dictionary)

## Story flag that keeps it open for good ("" = it opens again each visit once cleared).
@export var flag_id: String = ""
## The lid's picture: a two-frame sheet, shut then open.
@export var visual: Sprite2D
## Its door down (door.gd, kind `ladder_down`): off while shut.
@export var door: Node
## The old holder of the heap's liftables (anything left in it is taken out with the heap); the heap
## is now whatever liftables lie on the cover.
@export var heap: Node2D
## Where a liftable lying on it keeps it shut (relative to this node).
@export var cover_rect: Rect2 = Rect2(-60.0, -80.0, 120.0, 90.0)

var _open := false
var _trigger := Rect2()
## Something lay on it since the world was built (only then does the jingle play).
var _covered := false


func _ready() -> void:
	if door != null:
		_trigger = door.get(&"trigger_rect")
	var run := Services.run()
	_open = not flag_id.is_empty() and run != null and run.has_flag(flag_id)
	if _open:
		_take_out_heap()
	_apply()


func is_open() -> bool:
	return _open


## How many liftables lie on it now.
func lying_on() -> int:
	return heap_on_it().size()


## The liftables lying on it now (their roots inside `cover_rect`).
func heap_on_it() -> Array[Node2D]:
	var cover := Rect2(global_position + cover_rect.position, cover_rect.size)
	var found: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group(LiftableScript.GROUP):
		var root := node.get_parent() as Node2D
		if root == null or root.is_queued_for_deletion() or not root.is_inside_tree():
			continue
		if cover.has_point(root.global_position):
			found.append(root)
	return found


func _physics_process(_delta: float) -> void:
	if _open:
		set_physics_process(false)
		return
	if lying_on() > 0:
		_covered = true
		return
	open_for_good(_covered)


## Opens the hatch for good: the lid, the dust, the sounds (the jingle when `jingle`), the flag.
func open_for_good(jingle: bool = true) -> void:
	if _open:
		return
	_open = true
	var run := Services.run()
	if run != null and not flag_id.is_empty():
		run.set_flag(flag_id)
	_apply()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_OPEN)
		feel.particles(DUST, global_position - Vector2(0.0, DUST_RISE_PX))
		if jingle:
			feel.audio_cue(CUE_SECRET)
	opened.emit({"flagId": flag_id})


func _apply() -> void:
	if visual != null and visual.hframes * visual.vframes > FRAME_OPEN:
		visual.frame = FRAME_OPEN if _open else FRAME_SHUT
	if door != null:
		door.set(&"trigger_rect", _trigger if _open else Rect2())


## The heap's liftables leave before the slime sees them (the hatch is open for good): every one
## lying on the cover (the whole world is in the tree when this is ready), and any in `heap`.
func _take_out_heap() -> void:
	var gone: Array[Node] = []
	gone.append_array(heap_on_it())
	if heap != null:
		for child: Node in heap.get_children():
			if child.get_node_or_null(^"LiftableScript") is LiftableScript and not child in gone:
				gone.append(child)
	for node in gone:
		node.get_parent().remove_child(node)
		node.queue_free()
