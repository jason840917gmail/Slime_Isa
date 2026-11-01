extends StairHatchScript
class_name StairDoorScript
## Scene script `game.stair-door` (`object.stair-door`; Fatty's Lair's Inner Stair and the crypt's
## stair back up, the playground's pair): a door set into a wall that opens from behind onto the
## stair it connects to. The same logic as `stair_hatch.gd` (the well, the fade, the travel), with
## its own art: shut it shows the door; open (its flag, or `start_open`) it shows the stairs.
## `direction` "up" or "down" picks the arrow on the keystone and the stairs. Frames of
## `256x256-tile_4x1-stair-door.webp`, row-major: 0 closed up, 1 closed down, 2 stairs up, 3 stairs
## down.
##
## Going through, the slime walks into the doorway (`MOUTH_UP` above the threshold of the door's
## picture, which may be dragged off the node), then takes two steps of the stairs, each way its own:
## - **up:** it climbs `UP_CLIMB` px a step, up the flight at its normal size.
## - **down:** the first step climbs into the doorway; on the second it goes down the flight,
##   `DOWN_SINK` px lower, shrinking to `DOWN_SCALE` and fading to `DOWN_ALPHA` into the dark
##   stairwell.
## The walk in is `ENTER_MS`, each step `STEP_MS` with the open-world stairs' step sound. Then the fade
## and the travel run as in `stair_hatch.gd`. Only the slime's picture moves, on the player's effects
## channel (door.gd `effect_step`, as ladders and holes do); its body stays where it is. The picture
## is back at rest when the slime arrives behind the black (a stair in the same world), or at once
## when the travel is refused; a stair into another world builds the slime afresh there.
##
## Arriving, the stair it comes out of plays the way in backwards (`play_arrival`, 2026-10-31): down
## the flight or up out of the dark into the doorway's mouth, then out onto the floor, facing south
## with its walk clip (player.gd `walk_in`).
##
## Owner: dungeons (Fatty's Lair).

const Door := preload("res://game/scripts/door.gd")

const SHEET_UP := 0
const SHEET_DOWN := 1
const SHEET_OPEN := 2
## Walking into the doorway, then one step of the stairs walk (400 ms each in the open world).
const ENTER_MS := 350.0
const STEP_MS := 550.0
## The doorway's mouth, above the threshold of the door's picture, where the slime steps in.
const MOUTH_UP := -24.0
## Up: each step climbs the slime up the flight.
const UP_CLIMB := 16.0
## Down: the second step goes down the flight into the dark (the first climbs into the doorway).
const DOWN_SINK := 6.0
const DOWN_SCALE := 0.75
const DOWN_ALPHA := 0.3

## "up" or "down": the way the stair leads.
@export_enum("up", "down") var direction: String = "up"


func _show() -> void:
	if visual != null:
		visual.frame = (SHEET_UP if direction == "up" else SHEET_DOWN) + (SHEET_OPEN if is_open() else 0)


## The walk into the doorway, the steps down or up, then the parent's travel (the fade and move, or
## the travel to `target_world`).
func _travel(player: Node) -> void:
	var tween: Tween = player.call(&"effect_tween") if player.has_method(&"effect_tween") else null
	if tween == null:
		super._travel(player)
		return
	_travelling = true
	player.call(&"stop_movement")
	player.call(&"suppress_movement", ENTER_MS + STEP_MS * 2.0 + FADE_MS * 2.0 + HOLD_MS)
	var mouth := _threshold() + Vector2(0.0, MOUTH_UP) - (player.call(&"get_centre") as Vector2)
	var at: Dictionary = {"offset": mouth, "scale": 1.0, "alpha": 1.0}
	tween.tween_callback(_step_sound)
	Door.effect_step(tween, player, Door.EFFECT_REST, at, ENTER_MS)
	for step: Dictionary in _steps(mouth):
		tween.tween_callback(_step_sound)
		Door.effect_step(tween, player, at, step, STEP_MS).set_trans(Tween.TRANS_SINE)
		at = step
	tween.finished.connect(_after_steps.bind(player))


## The two steps of the stair after the doorway's mouth (`mouth`: the picture's offset there), for
## this door's direction (door.gd `effect_step` states).
func _steps(mouth: Vector2) -> Array[Dictionary]:
	var first := {"offset": mouth + Vector2(0.0, -UP_CLIMB), "scale": 1.0, "alpha": 1.0}
	if direction == "down":
		return [first, {"offset": mouth + Vector2(0.0, -UP_CLIMB + DOWN_SINK), "scale": DOWN_SCALE, "alpha": DOWN_ALPHA}]
	return [first, {"offset": mouth + Vector2(0.0, -UP_CLIMB * 2.0), "scale": 1.0, "alpha": 1.0}]


## Arriving by this stair (main.gd `_start_arrival` from another world, `_arrive` in this one): the
## way in played backwards, from the far end of its two steps out to where the slime stands, after
## `delay_ms` behind the black. A stair up (the slime came down it): down two steps from the top of
## the flight into the doorway's mouth; a stair down (it came up): up out of the dark, small and
## faint, to full size, then down into the mouth. Then it walks out of the doorway to its spot. Each
## step `worldNavigation.stairArrivalStepMs` with the step sound, the walk `stairArrivalWalkMs`.
## Returns the ms the slime is held from now.
func play_arrival(player: Node, delay_ms: float) -> float:
	if player == null or not player.has_method(&"effect_tween"):
		return 0.0
	var mouth := _threshold() + Vector2(0.0, MOUTH_UP) - (player.call(&"get_centre") as Vector2)
	var at_mouth: Dictionary = {"offset": mouth, "scale": 1.0, "alpha": 1.0}
	var path: Array[Dictionary] = _steps(mouth)
	path.reverse()
	path.append(at_mouth)
	var at: Dictionary = path.pop_front()
	var tween := Door.arrival_tween(player, at, delay_ms)
	if tween == null:
		return 0.0
	var step_ms := _number("stairArrivalStepMs", STEP_MS)
	var walk_ms := _number("stairArrivalWalkMs", ENTER_MS)
	for step: Dictionary in path:
		tween.tween_callback(_step_sound)
		Door.effect_step(tween, player, at, step, step_ms).set_trans(Tween.TRANS_SINE)
		at = step
	Door.effect_step(tween, player, at, Door.EFFECT_REST, walk_ms)
	var total := delay_ms + step_ms * path.size() + walk_ms
	# Out of the stair facing into the room, its walk clip playing: `face` alone keeps the clip's
	# row, so the slime would come out showing its back from walking up into the stair. The input
	# held to go in is dropped too.
	if player.has_method(&"walk_in"):
		player.call(&"walk_in", inward(), total)
	return total


## `worldNavigation.<key>` from game-constants, else `fallback`.
func _number(key: String, fallback: float) -> float:
	var constants := Services.constants()
	return constants.number("worldNavigation." + key) if constants != null else fallback


## The threshold of the door's picture (global): its bottom middle; the node without a picture.
func _threshold() -> Vector2:
	if visual == null:
		return global_position
	var rect := visual.get_rect()
	return visual.to_global(Vector2(rect.get_center().x, rect.end.y))


func _step_sound() -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_STEP)


## The steps above already sound; the travel's own step would double them.
func _travel_cue() -> void:
	pass


func _after_steps(player: Node) -> void:
	_travelling = false
	if not is_instance_valid(player):
		return
	super._travel(player)
	# Refused (another travel under way, no way there): the picture comes back at once, and the
	# walk starts from rest if the slime walks in again.
	if not _travelling:
		_rest_picture(player)


## Behind the black (a stair in the same world): the picture is back at rest where the slime arrives.
func _arrive(player: Node, marker: Node2D, holder: Array[CanvasLayer]) -> void:
	_rest_picture(player)
	await super(player, marker, holder)


func _rest_picture(player: Node) -> void:
	if is_instance_valid(player) and player.has_method(&"reset_effects"):
		player.call(&"reset_effects")
