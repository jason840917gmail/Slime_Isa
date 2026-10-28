@tool
extends Node2D
## The hub's counterweight chains (Fatty's Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"):
## presentation only. An iron chain hangs from the raised drawbridge's top down to each heavy plate
## in `plates`, so the first visit shows what the plates do. As a plate sinks its chain pulls taut;
## once the drawbridge (`bridge`) is down the chains are gone (the bridge lies on them).
##
## Editor (2026-10-27): it draws in the editor. Drag the top point (the Marker2D child named by
## `top_marker`, else `top`) and the plates where they stand; the chains follow.
##
## Owner: dungeons (Fatty's Lair).

const LINK_COLOR := Color(0.33, 0.3, 0.28, 1.0)
const LINK_LIGHT := Color(0.62, 0.58, 0.52, 1.0)
const LINK_DARK := Color(0.12, 0.1, 0.09, 0.9)
const SEGMENTS := 40
const SAG_TAUT := 0.15
const HANDLE_RADIUS := 6.0
const HANDLE_COLOR := Color(1.0, 0.8, 0.2, 0.95)

## The heavy plates the chains end on: one chain each, ending `plate_lift` above the plate's centre.
@export var plates: Array[NodePath] = []
## Where each chain hangs from (the raised bridge's top edge), one Marker2D child per plate, in the
## `plates` order (drag them in the editor); `top` for a plate with no marker.
@export var top_markers: Array[NodePath] = []
## Where the chains hang from when a plate has no marker, from this node.
@export var top: Vector2 = Vector2(0.0, -400.0)
@export var plate_lift: float = 6.0
@export var bridge: NodePath
## How far a slack chain sags below the straight line (world units); taut it sags SAG_TAUT of it.
@export var sag_px: float = 70.0
@export var link_px: float = 10.0

var _depths := PackedFloat32Array()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	var drawbridge := get_node_or_null(bridge)
	if drawbridge != null and drawbridge.has_method(&"is_lowered") and bool(drawbridge.call(&"is_lowered")):
		visible = false
		set_process(false)
		return
	var depths := _plate_depths()
	if depths != _depths:
		_depths = depths
		queue_redraw()


## The depth each plate is pressed to (0 up, 1 down), in `plates` order.
func _plate_depths() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for path: NodePath in plates:
		var weight := get_node_or_null(path)
		out.append(float(weight.call(&"depth")) if weight != null and weight.has_method(&"depth") else 0.0)
	return out


## The top point of the chain for plate `index`, from this node.
func top_point(index: int) -> Vector2:
	if index < top_markers.size():
		var marker := get_node_or_null(top_markers[index]) as Node2D
		if marker != null:
			return marker.position
	return top


## A point of a chain at `t` (0 at `from`, 1 at `to`): a sagging curve, taut at depth 1.
func point_at(t: float, from: Vector2, to: Vector2, depth: float) -> Vector2:
	var sag := sag_px * lerpf(1.0, SAG_TAUT, clampf(depth, 0.0, 1.0))
	var mid := (from + to) * 0.5 + Vector2(0.0, sag)
	var a := from.lerp(mid, t)
	var b := mid.lerp(to, t)
	return a.lerp(b, t)


func _draw() -> void:
	for index: int in plates.size():
		var plate := get_node_or_null(plates[index]) as Node2D
		if plate == null:
			continue
		var from := top_point(index)
		var to := to_local(plate.global_position) + Vector2(0.0, -plate_lift)
		var depth := _depths[index] if index < _depths.size() else 0.0
		_draw_chain(from, to, depth)
		# In the editor each chain shows two handles: its top (drag its marker) and its end (drag the plate).
		if Engine.is_editor_hint():
			_draw_handle(from)
			_draw_handle(to)


## A handle the editor shows at a chain's end (not drawn in the game).
func _draw_handle(at: Vector2) -> void:
	draw_circle(at, HANDLE_RADIUS + 1.5, Color(0.0, 0.0, 0.0, 0.7))
	draw_circle(at, HANDLE_RADIUS, HANDLE_COLOR)


func _draw_chain(from: Vector2, to: Vector2, depth: float) -> void:
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		points.append(point_at(float(i) / SEGMENTS, from, to, depth))
	draw_polyline(points, LINK_DARK, 4.0, true)
	var length := 0.0
	for i in SEGMENTS:
		length += points[i].distance_to(points[i + 1])
	var count := maxi(2, int(length / maxf(2.0, link_px)))
	for i in count:
		var t := (float(i) + 0.5) / count
		var at := point_at(t, from, to, depth)
		var along := (point_at(minf(1.0, t + 0.01), from, to, depth) - point_at(maxf(0.0, t - 0.01), from, to, depth)).normalized()
		var across := Vector2(-along.y, along.x)
		var half_long := link_px * 0.62
		var half_wide := 2.6 if i % 2 == 0 else 1.2
		var ring := PackedVector2Array()
		for k in 12:
			var angle := TAU * float(k) / 12.0
			ring.append(at + along * cos(angle) * half_long + across * sin(angle) * half_wide)
		ring.append(ring[0])
		draw_polyline(ring, LINK_DARK, 2.6, true)
		draw_polyline(ring, LINK_COLOR if i % 2 == 0 else LINK_LIGHT, 1.4, true)
