extends Node2D
## The Feral skin's claws (docs/godot/SKINS.md "Feral"; Direction: "claws show" as the slime
## climbs). A child "FeralClaws" of the player's body, made by game/player/skins/feral_climb.gd the
## first time it climbs: two hands of three curved claws gripping the face on either side of the
## slime, drawn over it, popping in as it grabs and out as it lets go (real time, presentation
## only). The slime faces the wall the whole climb (its back to the camera), so the hands grip above
## its middle.
##
## Owner: skins.

const FILL := Color("#f2e8d2")
const SHADE := Color("#c9b48f")
const LINE := Color("#3b2a1b")
## Each hand from the body's root (the slime's feet), world px.
const HANDS: Array[Vector2] = [Vector2(-21.0, -34.0), Vector2(21.0, -34.0)]
const CLAW_LENGTH := 18.0
const CLAW_WIDTH := 6.5
const CLAW_GAP := 8.0
const POP_S := 0.12

var _shown := false
var _grip := 0.0


func _ready() -> void:
	z_index = 2
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


## Shows (or hides) the claws.
func set_shown(on: bool) -> void:
	if on == _shown:
		return
	_shown = on
	if on:
		visible = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE if on else Vector2(0.4, 0.4), POP_S).from(Vector2(0.4, 0.4) if on else Vector2.ONE)
	if not on:
		tween.tween_callback(func() -> void: visible = false)
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	# A small flex as it pulls, so the claws read as gripping.
	_grip = fmod(_grip + delta * 3.0, TAU)
	queue_redraw()


func _draw() -> void:
	for index in HANDS.size():
		var side := -1.0 if index == 0 else 1.0
		var hand := HANDS[index]
		var flex := sin(_grip + index * PI) * 1.2
		for claw in 3:
			var base := hand + Vector2(side * (claw - 1) * CLAW_GAP * 0.55, (claw - 1) * 1.5 + flex)
			_draw_claw(base, side, claw)


## One claw: a tapered hook from `base`, curling outward (`side`) and down over the rock.
func _draw_claw(base: Vector2, side: float, claw: int) -> void:
	var bend := 0.35 + 0.12 * float(claw)
	var tip := base + Vector2(side * CLAW_LENGTH * 0.45, -CLAW_LENGTH * (0.95 - 0.08 * float(claw)))
	var mid := base.lerp(tip, 0.5) + Vector2(side * CLAW_LENGTH * bend, 0.0)
	var points := PackedVector2Array()
	var count := 7
	for i in count:
		var t := float(i) / float(count - 1)
		points.append(_bezier(base + Vector2(-side * CLAW_WIDTH * 0.5, 0.0), mid, tip, t))
	for i in count:
		var t := 1.0 - float(i) / float(count - 1)
		var width := CLAW_WIDTH * (1.0 - t) * 0.0
		points.append(_bezier(base + Vector2(side * CLAW_WIDTH * 0.5, 0.0), mid + Vector2(side * 1.5, 1.0), tip, t) + Vector2(width, 0.0))
	draw_colored_polygon(points, FILL)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, LINE, 1.4, true)
	draw_line(base.lerp(tip, 0.25), base.lerp(tip, 0.7) + Vector2(side * 1.0, 0.0), SHADE, 1.0, true)


static func _bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + b * 2.0 * u * t + c * t * t
