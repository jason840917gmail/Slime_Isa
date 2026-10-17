extends Node2D
## The hub's counterweight chain (Fatty's Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"):
## presentation only. An iron chain hangs from the raised drawbridge's top (`top`, from this node,
## which stands on the counterweight plate) down to the plate (`plate`, an object.heavy-plate), so
## the first visit shows what the plate does. As the plate sinks the chain pulls taut; once the
## drawbridge (`bridge`) is down it is gone (the bridge lies on its chains).
##
## Owner: dungeons (Fatty's Lair).

const LINK_COLOR := Color(0.33, 0.3, 0.28, 1.0)
const LINK_LIGHT := Color(0.62, 0.58, 0.52, 1.0)
const LINK_DARK := Color(0.12, 0.1, 0.09, 0.9)
const SEGMENTS := 40

## Where the chain hangs from (the raised bridge's top), from this node.
@export var top: Vector2 = Vector2(0.0, -400.0)
## Where it ends, on the plate, from this node.
@export var bottom: Vector2 = Vector2(0.0, -6.0)
@export var bridge: NodePath
@export var plate: NodePath
## How far the slack chain sags below the straight line (world units); taut it sags SAG_TAUT of it.
@export var sag_px: float = 70.0
@export var link_px: float = 10.0

const SAG_TAUT := 0.15

var _depth: float = -1.0


func _process(_delta: float) -> void:
	var drawbridge := get_node_or_null(bridge)
	if drawbridge != null and drawbridge.has_method(&"is_lowered") and bool(drawbridge.call(&"is_lowered")):
		visible = false
		set_process(false)
		return
	var weight := get_node_or_null(plate)
	var depth := float(weight.call(&"depth")) if weight != null and weight.has_method(&"depth") else 0.0
	if not is_equal_approx(depth, _depth):
		_depth = depth
		queue_redraw()


## A point of the chain at `t` (0 at the top, 1 at the plate): a sagging curve.
func point_at(t: float) -> Vector2:
	var sag := sag_px * lerpf(1.0, SAG_TAUT, clampf(_depth, 0.0, 1.0))
	var mid := (top + bottom) * 0.5 + Vector2(0.0, sag)
	var a := top.lerp(mid, t)
	var b := mid.lerp(bottom, t)
	return a.lerp(b, t)


func _draw() -> void:
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		points.append(point_at(float(i) / SEGMENTS))
	draw_polyline(points, LINK_DARK, 4.0, true)
	var length := 0.0
	for i in SEGMENTS:
		length += points[i].distance_to(points[i + 1])
	var count := maxi(2, int(length / maxf(2.0, link_px)))
	for i in count:
		var t := (float(i) + 0.5) / count
		var at := point_at(t)
		var along := (point_at(minf(1.0, t + 0.01)) - point_at(maxf(0.0, t - 0.01))).normalized()
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
