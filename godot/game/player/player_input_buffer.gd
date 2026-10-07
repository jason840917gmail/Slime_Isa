extends RefCounted
class_name PlayerInputBuffer
## Held keys + buffered presses for the player (Phaser `PlayerScript._unhandled_input`,
## `consumeActionPress`, `getMovementInput`). Player spec section 7.
##
## Press timestamps are simulation time (SimClock), so presses made during hit-stop do not age.
## Older presses than the buffer window are dropped, never fired late.
##
## Owner: player builder.

## Actions the player captures (snake_case of PlayerInputActions.ts): movement, sprint, the
## actions and the abilities, and `interact` (right click, interaction spec 2.7).
const ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right",
	&"attack", &"sprint", &"dodge", &"interact", &"jump", &"stretch_lash", &"squash_slam",
	&"teleport", &"eat"]

var _held: Dictionary = {}
var _pressed_at: Dictionary = {}


## On a non-echo press of a captured action: if not already held, `pressed_at[action] = now_ms`
## (key repeat does not refresh); mark held. On release: unmark held. Returns true when the event
## matched a captured action (the caller then marks it handled).
func capture(event: InputEvent, now_ms: float) -> bool:
	var matched := false
	for action: StringName in ACTIONS:
		if not event.is_action(action):
			continue
		matched = true
		if event.is_action_pressed(action):
			if not _held.has(action):
				_pressed_at[action] = now_ms
			_held[action] = true
		elif event.is_action_released(action):
			_held.erase(action)
	return matched


## Records a press of `action` at `now_ms` without a held state: the mouse wheel's weapon steps
## (`weapon_next` / `weapon_previous`, game/player/wheel_stepper.gd), which are not in ACTIONS.
func mark_pressed(action: StringName, now_ms: float) -> void:
	_pressed_at[action] = now_ms


## True while `action` is held (sprint, movement).
func is_held(action: StringName) -> bool:
	return _held.has(action)


## `consumeActionPress` (PlayerScript.ts:170-176): false if no pending press; else remove it and
## return `now_ms - pressed_at <= buffer_ms` (game-constants `input.bufferMs`, 150).
func consume(action: StringName, now_ms: float, buffer_ms: float) -> bool:
	if not _pressed_at.has(action):
		return false
	var pressed_at: float = _pressed_at[action]
	_pressed_at.erase(action)
	return now_ms - pressed_at <= buffer_ms


## `getMovementInput`: Vector2(held(right) - held(left), held(down) - held(up)); not normalized.
func movement_vector() -> Vector2:
	return Vector2(
		float(int(_held.has(&"move_right")) - int(_held.has(&"move_left"))),
		float(int(_held.has(&"move_down")) - int(_held.has(&"move_up"))))


## Empties held keys and pending presses (pause, scene exit, death is NOT a clear).
func clear() -> void:
	_held.clear()
	_pressed_at.clear()
