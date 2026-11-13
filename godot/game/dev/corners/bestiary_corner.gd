extends Node2D
## The playground's Bestiary corner (docs/godot/BESTIARY.md "The Bestiary corner"; the bestiary:
## docs/design/2026-10-16-bestiary.md). Instanced once into game/scenes/worlds/playground.tscn at
## the world's origin, so its children stand at world positions east of the old east edge (x 3392
## to 6592, y 384 to 4736): one pen per bestiary enemy (game/dev/corners/bestiary_pen.gd), 33 in the
## bestiary's order (the seventh row: every dungeon's skeletons and the Watcher Eye), five to a row,
## each with a sign giving its enemy's name, kind and right tool. Pen 34 (beside 33) is an extra:
## Gloomlings in a dark pen with a burning brazier (`pen-34-brazier`), to try their hunt.
## The built enemies stand in their pens; the rest are "coming next".
##
## RESPAWN_KEY (F4, the shapes testbed's pen key) brings every pen's enemies back at once. It is read
## in `_input` and not marked handled, so the same press still respawns the shapes testbed's pen.
##
## It is a rework-mode testbed: with the mode off (the classic game, the test runner's playground)
## it takes itself out, so nothing of it is in the classic world.
##
## Owner: enemy builder.

const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const BestiaryPen := preload("res://game/dev/corners/bestiary_pen.gd")

const RESPAWN_KEY := KEY_F4


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not ReworkMode.is_on():
		queue_free()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != RESPAWN_KEY:
		return
	if get_tree().paused or not ReworkMode.is_on():
		return
	respawn_all()


## Every pen's enemies anew.
func respawn_all() -> void:
	for pen: BestiaryPen in pens():
		pen.respawn()


## The pens, in the bestiary's order.
func pens() -> Array[BestiaryPen]:
	var found: Array[BestiaryPen] = []
	for child: Node in get_children():
		if child is BestiaryPen:
			found.append(child as BestiaryPen)
	found.sort_custom(func(a: BestiaryPen, b: BestiaryPen) -> bool: return a.number < b.number)
	return found


## The pen of bestiary row `number`, or null.
func pen(number: int) -> BestiaryPen:
	for found: BestiaryPen in pens():
		if found.number == number:
			return found
	return null
