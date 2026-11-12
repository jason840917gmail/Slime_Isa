@tool
extends "res://game/dungeon/hazard.gd"
class_name SkyFall
## The void under a sky floor (docs/godot/SKY_FLOOR.md "Falls"): the dungeon kit's void hazard
## (hazard.gd, HazardWatch does the falling), pinned to its SkyFloor instead of the paint. It covers
## exactly the sky cells of the SkyFloor's area (painted at its `sky_level` or lower), and its rim is
## `sky_level` + 1: a slime that drops into the sky falls and is put back where it fell from, while an
## ordinary hole on an island (a pond, a pit, a lower terrace at -1) and the world's other holes stay
## what they are. (A plain Hazard reads its floor and rim from the paint: sky beside level-0 islands
## would make every hole on them a fall.)
##
## The SkyFloor makes one in the game (`falls`). To send falls to fixed spots, add one as its child
## yourself, as any hazard: `return_points` (or children named "Return...") or `fixed_return`.
##
## Owner: world (sky).

## The SkyFloor it belongs to (its parent when unset).
var sky: Node2D


func _init() -> void:
	kind = "void"
	draw_look = false


func _sky() -> Node2D:
	if sky == null or not is_instance_valid(sky):
		sky = get_parent() as Node2D
	return sky if sky != null and sky.has_method(&"area_rect") else null


## Its rectangle is its SkyFloor's area (HazardWatch reads it for the body-over check), wherever and
## however big it was placed.
func rect() -> Rect2:
	var floor_node := _sky()
	return Rect2(floor_node.call(&"area_rect")) if floor_node != null else super()


func covers(point: Vector2) -> bool:
	var floor_node := _sky()
	return floor_node != null and bool(floor_node.call(&"is_sky_at", point))


func floor_level() -> int:
	var floor_node := _sky()
	return int(floor_node.get(&"sky_level")) if floor_node != null else rim_level - 1


func rim() -> int:
	return floor_level() + 1
