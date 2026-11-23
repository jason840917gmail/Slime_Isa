@tool
extends Node2D
## A critter freed from the silk, at home in Mossy's camp (Gloop Forest's River Roads, 2026-11-21;
## docs/design/2026-11-21-gloop-river-roads.md "Critters in silk"): where it lives once a
## SilkCritter (silk_critter.gd) with the same story flag `flag_id` has been torn open. Until the
## flag is set it holds nothing; once it is (when the world is built, or while it stands), it puts
## its `critter` (a town animal's scene: it wanders its own circle, villagers' rules, critter.gd)
## here. In the editor it draws a small ring with the flag, to place it by.
##
## Owner: webs (the Gloop Forest).

const Services := preload("res://game/shared/services.gd")
const EDITOR_RING := Color(1.0, 0.85, 0.3, 0.85)

## The story flag of the SilkCritter that frees it.
@export var flag_id: String = ""
## The animal (a town animal's scene, the same as its SilkCritter's).
@export var critter: PackedScene:
	set(value):
		critter = value
		queue_redraw()

var _animal: Node2D


func _ready() -> void:
	y_sort_enabled = true
	if Engine.is_editor_hint():
		queue_redraw()
		return
	var run := Services.run()
	if run == null:
		return
	if not flag_id.is_empty() and run.has_flag(flag_id):
		_come_home()
	else:
		run.story_flag_changed.connect(_on_flag)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var run := Services.run()
	if run != null and run.story_flag_changed.is_connected(_on_flag):
		run.story_flag_changed.disconnect(_on_flag)


func _on_flag(payload: Dictionary) -> void:
	if str(payload.get("flag", "")) == flag_id and bool(payload.get("set", false)):
		_come_home.call_deferred()


## True once its critter is home.
func is_home() -> bool:
	return _animal != null


func _come_home() -> void:
	if _animal != null or critter == null or not is_inside_tree():
		return
	_animal = critter.instantiate() as Node2D
	add_child(_animal)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 20, EDITOR_RING, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(-40.0, -24.0), flag_id.get_slice(".", 1), HORIZONTAL_ALIGNMENT_CENTER, 80.0, 11, EDITOR_RING)
