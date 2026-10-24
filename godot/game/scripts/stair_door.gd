extends StairHatchScript
class_name StairDoorScript
## Scene script `game.stair-door` (`object.stair-door`; Fatty's Lair): a door set into a wall that
## opens from behind onto the stair it connects to. The same logic as `stair_hatch.gd` (the well, the
## fade, the travel), with its own art: shut it shows the door; open (its flag, or `start_open`) it
## shows the stairs. `direction` "up" or "down" picks the arrow on the keystone and the stairs.
## Frames of `256x256-tile_4x1-stair-door.webp`, row-major: 0 closed up, 1 closed down, 2 stairs up,
## 3 stairs down.
##
## Going through, the slime walks into the doorway, then takes the stairs, each way its own:
## - **down:** it sinks, shrinking and darkening, step by step into the stair's pit.
## - **up:** it climbs, one step at a time, rising up the flight at its normal size.
## Each step is `STEP_MS` with the open-world stairs' step sound. Then the fade and the travel run as
## in `stair_hatch.gd`. Only the slime's picture moves; its body stays where it is.
##
## Owner: dungeons (Fatty's Lair).

const SHEET_UP := 0
const SHEET_DOWN := 1
const SHEET_OPEN := 2
## Walking into the doorway, then one step of the stairs walk (400 ms each in the open world).
const ENTER_MS := 350.0
const STEP_MS := 550.0
## The doorway's mouth, above the door's threshold (node origin), where the slime steps in.
const MOUTH_UP := -24.0
## Down: the slime walks on into the doorway as far as the climb goes, at full size and colour; then
## it sinks `DOWN_SINK` px a step and darkens, into the stair. The sink only starts once it is inside.
const DOWN_SINK := 0
const DOWN_TINT := Color(0.45, 0.4, 0.5, 1.0)
## Up: each step climbs the slime up the flight.
const UP_CLIMB := 16.0

## "up" or "down": the way the stair leads.
@export_enum("up", "down") var direction: String = "up"


func _show() -> void:
	if visual != null:
		visual.frame = (SHEET_UP if direction == "up" else SHEET_DOWN) + (SHEET_OPEN if is_open() else 0)


## The walk into the doorway, the steps down or up, then the parent's travel (the fade and move, or
## the travel to `target_world`).
func _travel(player: Node) -> void:
	var sprite := player.get(&"visual") as Sprite2D
	if sprite == null:
		super._travel(player)
		return
	_travelling = true
	player.call(&"stop_movement")
	var step_ms := STEP_MS
	player.call(&"suppress_movement", ENTER_MS + step_ms * 2.0 + FADE_MS * 2.0 + HOLD_MS)
	var base_pos := sprite.position
	var base_scale := sprite.scale
	var base_tint := sprite.modulate
	var mouth := global_position + Vector2(0.0, MOUTH_UP)
	var tween := create_tween()
	tween.tween_callback(_step_sound)
	tween.tween_property(sprite, "global_position", mouth, ENTER_MS / 1000.0)
	for step: Dictionary in _steps(mouth, base_scale):
		tween.tween_callback(_step_sound)
		tween.tween_property(sprite, "global_position", step["pos"], step_ms / 1000.0).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(sprite, "scale", step["scale"], step_ms / 1000.0)
		tween.parallel().tween_property(sprite, "modulate", step["tint"], step_ms / 1000.0)
	tween.finished.connect(_after_steps.bind(player, sprite, base_pos, base_scale, base_tint))


## The two steps of the stair, for this door's direction.
func _steps(mouth: Vector2, base_scale: Vector2) -> Array[Dictionary]:
	if direction == "down":
		return [
			{"pos": mouth + Vector2(0.0, -UP_CLIMB), "scale": base_scale, "tint": Color.WHITE},
			{"pos": mouth + Vector2(0.0, -UP_CLIMB + DOWN_SINK), "scale": base_scale, "tint": DOWN_TINT},
		]
	return [
		{"pos": mouth + Vector2(0.0, -UP_CLIMB), "scale": base_scale, "tint": Color.WHITE},
		{"pos": mouth + Vector2(0.0, -UP_CLIMB * 2.0), "scale": base_scale, "tint": Color.WHITE},
	]


func _step_sound() -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_STEP)


## The steps above already sound; the travel's own step would double them.
func _travel_cue() -> void:
	pass


func _after_steps(player: Node, sprite: Sprite2D, base_pos: Vector2, base_scale: Vector2, base_tint: Color) -> void:
	_travelling = false
	super._travel(player)
	# The travel covers the sprite in black, so it is put back once the fade is over. Bound to the
	# sprite, not this node, so it still runs after a world change frees this door.
	var restore := func() -> void:
		if is_instance_valid(sprite):
			sprite.position = base_pos
			sprite.scale = base_scale
			sprite.modulate = base_tint
	get_tree().create_timer((FADE_MS * 2.0 + HOLD_MS) / 1000.0, true, false, true).timeout.connect(restore)
