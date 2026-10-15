extends RefCounted
## The keys-only control scheme's bindings (game/player/mouse/control_scheme.gd, `keys`): while it is
## on, the InputMap is rebound so every action, prompt, hint and the Controls list follow at once
## (they read the InputMap): the arrows walk, A attacks, W interacts, E alone cycles the weapons
## (the weapon scroll, the mouse wheel's job; no key goes back: owner, 2026-10-08), and no mouse
## button or wheel does anything in play. The other keys are project.godot's (B the bag, J the
## journal, M the map). Switching to another scheme puts every action's events back exactly as
## project.godot has them.
## GameSettings applies it (`apply_to_input`) at start-up and on every change.
## In the body-shapes rework mode (game/shapes/rework_mode.gd, docs/godot/BODY_SHAPES.md) it also
## puts the chosen box ability (`ability_use`) on S and the Roll (`dodge`) on D (REWORK_LAYOUT); it
## sits on top of the rework's own input layer (game/shapes/rework_input.gd), which takes this one
## off and puts it back around every change of its own, so each restores only what it changed.
##
## Owner: player builder.

const ReworkMode := preload("res://game/shapes/rework_mode.gd")

## Action -> the physical keys it has in the keys-only scheme (nothing else).
const LAYOUT := {
	&"move_up": [KEY_UP],
	&"move_down": [KEY_DOWN],
	&"move_left": [KEY_LEFT],
	&"move_right": [KEY_RIGHT],
	&"attack": [KEY_A],
	&"interact": [KEY_W],
	&"weapon_previous": [],
	&"weapon_next": [KEY_E],
}
## The rework mode's keys-only extras (body-shapes plan section 6 "Keys only"): the chosen box
## ability on S, the Roll on D. Only while ReworkMode is on; the classic layout stays as above.
const REWORK_LAYOUT := {
	&"ability_use": [KEY_S],
	&"dodge": [KEY_D],
}

## Action -> its events before the keys-only scheme rebound it; empty while it is off.
static var _saved: Dictionary = {}


## Rebinds the InputMap for the keys-only scheme (`keys_only`), or restores it.
static func apply(keys_only: bool) -> void:
	if keys_only:
		for action: StringName in LAYOUT:
			if not InputMap.has_action(action):
				continue
			if not _saved.has(action):
				_saved[action] = InputMap.action_get_events(action).duplicate()
			InputMap.action_erase_events(action)
			for keycode: Key in LAYOUT[action]:
				var event := InputEventKey.new()
				event.physical_keycode = keycode
				InputMap.action_add_event(action, event)
		if ReworkMode.is_on():
			for action: StringName in REWORK_LAYOUT:
				if not InputMap.has_action(action):
					continue
				if not _saved.has(action):
					_saved[action] = InputMap.action_get_events(action).duplicate()
				InputMap.action_erase_events(action)
				for keycode: Key in REWORK_LAYOUT[action]:
					var event := InputEventKey.new()
					event.physical_keycode = keycode
					InputMap.action_add_event(action, event)
		return
	for action: StringName in _saved:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved[action]:
			InputMap.action_add_event(action, event)
	_saved.clear()


## True while the keys-only bindings are on.
static func is_applied() -> bool:
	return not _saved.is_empty()
