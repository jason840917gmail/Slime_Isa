@tool
extends Node2D
## Draws a Bone Marcher's route in the editor (the bestiary's row 32; docs/godot/BESTIARY.md "Bone
## Marcher"): the line through its points, the closing line of a loop, an arrow on each leg showing
## the way it walks, and each point's number. Edit the route in the Inspector and the line follows.
## Two places use it:
##
## - **The marcher's scene** (`RoutePreview` under the bone-marcher root): it reads its sibling
##   EnemyScript's `route` and `route_loop` (old centres from where it was placed, drawn from the
##   root's old centre, `metadata/depth_anchor` above the feet), so a marcher placed in a world shows
##   its route where it stands.
## - **A Bestiary pen** (a child of the pen node, game/dev/corners/bestiary_pen.gd): it reads the
##   pen's `enemy_properties` `route` and `route_loop`, drawn from the pen's first post.
##
## In the game it draws nothing. Presentation only.
##
## Owner: enemy builder.

const LINE := Color(0.95, 0.85, 0.45, 0.85)
const LOOP_LINE := Color(0.95, 0.85, 0.45, 0.55)
const POINT := Color(1.0, 0.55, 0.25, 0.95)
const TEXT := Color(1.0, 0.97, 0.9, 0.95)
const LINE_PX := 2.0
const POINT_PX := 4.0
const ARROW_PX := 7.0
const FONT_SIZE := 12
const SCRIPT_NODE := "EnemyScript"
const ROUTE_KEY := "route"
const LOOP_KEY := "route_loop"

var _drawn: Array = []


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false
		set_process(false)
		return
	z_index = 10


func _process(_delta: float) -> void:
	# The marcher's script is not a tool: watch its route for Inspector edits.
	var now := _source()
	if now != _drawn:
		_drawn = now
		queue_redraw()


## [origin, points, loop] of the route to draw, in this node's space; [] when there is none.
func _source() -> Array:
	var parent := get_parent()
	if parent == null:
		return []
	var properties: Variant = parent.get(&"enemy_properties")
	if properties is Dictionary:
		var posts: Variant = parent.get(&"posts")
		var origin: Vector2 = (posts as PackedVector2Array)[0] if posts is PackedVector2Array and not (posts as PackedVector2Array).is_empty() else Vector2.ZERO
		var pen_route: Variant = (properties as Dictionary).get(ROUTE_KEY)
		if pen_route is PackedVector2Array:
			return [origin, pen_route, bool((properties as Dictionary).get(LOOP_KEY, true))]
		return []
	var script_node := parent.get_node_or_null(NodePath(SCRIPT_NODE))
	if script_node == null:
		return []
	var route: Variant = script_node.get(&"route")
	if not route is PackedVector2Array:
		return []
	var anchor: Variant = parent.get_meta(&"depth_anchor", Vector2.ZERO)
	var origin := -(anchor as Vector2) if anchor is Vector2 else Vector2.ZERO
	var loop: Variant = script_node.get(&"route_loop")
	return [origin, route, loop if loop is bool else true]


func _draw() -> void:
	if _drawn.size() < 3:
		return
	var origin: Vector2 = _drawn[0]
	var route: PackedVector2Array = _drawn[1]
	var loop: bool = _drawn[2]
	if route.is_empty():
		return
	var points := PackedVector2Array()
	for point: Vector2 in route:
		points.append(origin + point)
	for index: int in points.size():
		var last := index == points.size() - 1
		if last and (not loop or points.size() < 3):
			break
		var from := points[index]
		var to := points[0] if last else points[index + 1]
		draw_line(from, to, LOOP_LINE if last else LINE, LINE_PX)
		_arrow(from, to)
	var font := ThemeDB.fallback_font
	for index: int in points.size():
		draw_circle(points[index], POINT_PX, POINT)
		if font != null:
			draw_string(font, points[index] + Vector2(6.0, -6.0), str(index), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				FONT_SIZE, TEXT)


func _arrow(from: Vector2, to: Vector2) -> void:
	var leg := to - from
	if leg.length() < ARROW_PX * 3.0:
		return
	var tip := from + leg * 0.5 + leg.normalized() * ARROW_PX * 0.5
	var back := leg.normalized() * ARROW_PX
	var side := back.orthogonal() * 0.6
	draw_colored_polygon(PackedVector2Array([tip, tip - back + side, tip - back - side]), LINE)
