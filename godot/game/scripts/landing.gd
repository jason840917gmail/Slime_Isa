@tool
extends Node2D
class_name LandingScript
## Scene script `game.landing` (`object.landing`, 2026-10-31; docs/design/
## 2026-10-31-crossings-and-arrivals.md D3): where a one-way fall comes down in another world. A
## hole the slime falls through (door.gd kind "fall", a cracked floor broken open, a silk drop)
## names it in `target_door_id`, as a door names its pair; arriving, the slime drops in from
## `worldNavigation.landingDropPx` above its spot over `landingDropMs`, lands with `DropLand` and a
## squash over `landingSquashMs` (Zelda's fall into the room below). Nothing leads back through it:
## it is an end of a crossing for arriving only (the `door` group, `door_id`; area_travel.gd finds
## it). Drag it where the slime should land; the editor draws it.
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")
const AreaTravel := preload("res://game/world/area_travel.gd")
const Door := preload("res://game/scripts/door.gd")

const CUE_LAND := &"DropLand"
## The squash on landing: wide and flat, then back to its own shape.
const SQUASH := Vector2(1.3, 0.7)
const EDITOR_COLOR := Color(0.35, 0.75, 0.95, 0.9)

## Its id: the fall that lands here names it in `target_door_id`.
@export var door_id: String = "":
	set(value):
		door_id = value
		queue_redraw()


func _enter_tree() -> void:
	add_to_group(AreaTravel.DOOR_GROUP)


## Where the slime lands: this node, rounded.
func arrival_point() -> Vector2:
	return Vector2(floorf(global_position.x + 0.5), floorf(global_position.y + 0.5))


## The slime lands exactly here, not on a tile centre.
func exact_arrival() -> bool:
	return true


func has_side() -> bool:
	return false


## No facing of its own: the slime keeps the one it fell with.
func inward() -> Vector2:
	return Vector2.ZERO


func on_arrival() -> void:
	pass


## main.gd `_start_arrival`: the drop from above after `delay_ms` (behind the black), then the
## landing's sound and squash. Returns the ms the slime is held from now.
func play_arrival(player: Node, delay_ms: float) -> float:
	if player == null or not player.has_method(&"effect_tween"):
		return 0.0
	var drop_ms := _number("landingDropMs", 420.0)
	var squash_ms := _number("landingSquashMs", 180.0)
	var above := {"offset": Vector2(0.0, -_number("landingDropPx", 320.0)), "scale": 1.0, "alpha": 1.0}
	var tween := Door.arrival_tween(player, above, delay_ms)
	if tween == null:
		return 0.0
	Door.effect_step(tween, player, above, Door.EFFECT_REST, drop_ms).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_land.bind(player))
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(player):
			player.call(&"set_effect_scale", SQUASH.lerp(Vector2.ONE, t)), 0.0, 1.0, maxf(squash_ms, 1.0) / 1000.0) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return delay_ms + drop_ms + squash_ms


## The moment it touches the ground: the sound and a puff of dust.
func _land(player: Node) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	feel.audio_cue(CUE_LAND)
	if is_instance_valid(player):
		feel.particles(&"dodge-dust", player.call(&"get_centre"))


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, 10.0, EDITOR_COLOR)
	draw_line(Vector2(0.0, -90.0), Vector2(0.0, -14.0), EDITOR_COLOR, 3.0)
	draw_line(Vector2(0.0, -14.0), Vector2(-10.0, -28.0), EDITOR_COLOR, 3.0)
	draw_line(Vector2(0.0, -14.0), Vector2(10.0, -28.0), EDITOR_COLOR, 3.0)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(16.0, 6.0), "landing %s" % (door_id if not door_id.is_empty() else "?"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, EDITOR_COLOR)


## `worldNavigation.<key>` from game-constants, else `fallback`.
func _number(key: String, fallback: float) -> float:
	var constants := Services.constants()
	return constants.number("worldNavigation." + key) if constants != null else fallback
