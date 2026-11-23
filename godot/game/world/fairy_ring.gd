@tool
extends Node2D
## A fairy ring (Gloop Forest's River Roads, 2026-11-21; docs/design/2026-11-21-gloop-river-roads.md):
## a ring of glowing mushrooms in a secret glade. While the slime's feet are within `radius` of its
## middle, it heals `heal_amount` HP every `every_ms` of the gameplay clock (Services.now_ms()), as
## quiet rest (player.gd `heal`); stepping out stops it. The ring's picture is a child scene (the
## mushroom decor's fairy-ring-glow); this node is its middle. The editor draws the radius.
##
## Owner: world.

const Services := preload("res://game/shared/services.gd")

## How far from the middle the slime's feet heal (units).
@export var radius: float = 110.0:
	set(value):
		radius = value
		queue_redraw()
## HP a heal gives, and how often (gameplay ms) while the slime stands in the ring.
@export var heal_amount: int = 2
@export var every_ms: float = 700.0

var _next_ms: float = -1.0


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	var body := player.get(&"body") as Node2D if player != null and is_instance_valid(player) else null
	if body == null or body.global_position.distance_to(global_position) > radius:
		_next_ms = -1.0
		return
	var now := Services.now_ms()
	if _next_ms < 0.0:
		_next_ms = now + every_ms
	elif now >= _next_ms:
		player.call(&"heal", heal_amount)
		_next_ms = now + every_ms


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.5, 0.9, 0.8), 2.0)
