extends RefCounted
## The rework mode's input layer (docs/godot/BODY_SHAPES.md "Controls in the rework mode"; body-shapes
## plan section 6 "Input changes"). On: `swallow`, `stretch_lash`, `squash_slam` and `teleport` lose
## their number keys (Swallow is a Q hold; the others are Ability Box abilities used with
## `ability_use`, F), and `dodge` (the Roll) moves from 2 to Space. Off: each of them gets back
## exactly the events it had. main.gd applies it whenever it decides the mode (`apply`).
##
## The keys-only control scheme (game/player/mouse/key_bindings.gd) is a layer on top of this one:
## before this layer changes, the keys-only layer is taken off, and it is put back after, so each
## layer saves and restores only what lies under it and no event is lost, whichever of the two is
## applied first. (With the mode on, the keys-only layer also binds `ability_use` to S and `dodge` to
## D.)
##
## Owner: rework wiring (BODY_SHAPES.md "Mode, wiring, testbed").

const KeyBindings := preload("res://game/player/mouse/key_bindings.gd")

## Actions the rework mode leaves without any event.
const ERASED_ACTIONS: Array[StringName] = [&"swallow", &"stretch_lash", &"squash_slam", &"teleport"]
## Actions the rework mode rebinds: action -> the physical keys it has instead.
const REBOUND := {
	&"dodge": [KEY_SPACE],
}

## Action -> its events before this layer changed it; empty while the layer is off.
static var _saved: Dictionary = {}
static var _applied: bool = false


## Puts the rework layer on the InputMap (`on`) or takes it off. A call that changes nothing (on
## while on, off while off) leaves the InputMap alone.
static func apply(on: bool) -> void:
	if on == _applied:
		return
	var keys_only := KeyBindings.is_applied()
	if keys_only:
		KeyBindings.apply(false)
	if on:
		for action: StringName in ERASED_ACTIONS:
			if _save(action):
				InputMap.action_erase_events(action)
		for action: StringName in REBOUND:
			if not _save(action):
				continue
			InputMap.action_erase_events(action)
			for keycode: Key in REBOUND[action]:
				var event := InputEventKey.new()
				event.physical_keycode = keycode
				InputMap.action_add_event(action, event)
	else:
		for action: StringName in _saved:
			InputMap.action_erase_events(action)
			for event: InputEvent in _saved[action]:
				InputMap.action_add_event(action, event)
		_saved.clear()
	_applied = on
	if keys_only:
		KeyBindings.apply(true)


## True while the rework layer is on the InputMap.
static func is_applied() -> bool:
	return _applied


## Remembers `action`'s events once; false when the InputMap has no such action.
static func _save(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	if not _saved.has(action):
		_saved[action] = InputMap.action_get_events(action).duplicate()
	return true
