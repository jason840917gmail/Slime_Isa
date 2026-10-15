@tool
class_name StrikeDirection
extends Resource
## One direction of a strike (side, down or up): the hit's reach and centre, the arm, the attachment points and
## the timeline. Shown live above the strike's fields in the Inspector.

const KeyScript := preload("res://game/shapes/strike_key.gd")

## The hit's reach in this direction (game px): the Axe's arc radius, the Hammer's circle offset, the Spear's
## line. The chain step hits with this number; it is the only place that reach is set.
@export var hit_reach: float = 0.0
## Where the hit is measured from (drag the cross in the preview).
@export var hit_center: Vector2 = Vector2.ZERO
## How far the weapon reaches out from the body (game px); negative pulls it in.
@export var arm_px: float = 0.0
## Moves where the weapon leaves the body (game px) on body frames 1 to 6, added to the art's own point.
@export var socket_nudge: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2.ZERO]
## Shows the strip mirrored (the Axe backswing's down and up).
@export var flip_h: bool = false
## The Spear only (game px): its hidden end behind the socket, the neck's fade past the socket, the shaft's width.
@export var spear_inside: float = 0.0
@export var spear_fade: float = 0.0
@export var spear_shaft: float = 5.0
## The timeline, in time order.
@export var keys: Array[KeyScript] = []
