extends Node2D
## The warm glow of a hot throw (the rebound prototype, game/throw/throw_feel.gd: a sturdy thing the
## mouth caught in the air hits harder on its next throw): a soft pulsing halo behind the thing while
## the slime holds it and while it flies. Code-drawn, additive, behind its parent (the thing's look),
## in real time. `attach(look, px)` adds it; it goes with the look.
##
## Owner: throw combat (the sender).

const COLOR := Color(1.0, 0.72, 0.28)
const RINGS := 7
const RING_ALPHA := 0.11
const PULSE_SHARE := 0.1
const PULSE_PER_S := 9.0
const NODE_NAME := "ThrowGlow"

var _radius: float = 0.0
var _age: float = 0.0


## A glow `px` across (world px) behind `look`, whatever the look's own scale and turn.
static func attach(look: Node2D, px: float) -> void:
	if look == null or px <= 0.0 or look.has_node(NODE_NAME):
		return
	var node := new()
	node.name = NODE_NAME
	node._radius = px * 0.5 / maxf(0.001, absf(look.scale.x))
	node.show_behind_parent = true
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	node.material = blend
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	look.add_child(node)


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


func _draw() -> void:
	var size := _radius * (1.0 + PULSE_SHARE * sin(_age * PULSE_PER_S))
	for i in RINGS:
		draw_circle(Vector2.ZERO, size * (1.0 - float(i) / float(RINGS)), Color(COLOR, RING_ALPHA))
