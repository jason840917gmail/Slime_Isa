extends RefCounted
## The keys-only control scheme's bindings, the game's one scheme since the one combat (piece 5,
## 2026-11-25: the four mouse schemes and the F2 switch are gone): the InputMap is rebound so every
## action, prompt, hint and the Controls list follow at once (they read the InputMap). One layout (one combat, owner, 2026-11-25: "S will stay as roll and D will
## be ability. Q suck and W interact"): the arrows walk, A attacks with the current weapon (a tap for
## its combo, a hold for its charge), S rolls, D uses the ability chosen in the bag, Q is the Gulp
## (suck, throw, swallow, spit), W interacts, E alone switches the weapon (no key goes back: owner,
## 2026-10-08), and no mouse button or wheel does anything in play. The other keys are project.godot's
## (B the bag, J the journal, M the map). `apply(false)` puts every action's events back exactly as
## project.godot has them (the rework layer does that around its own changes, then applies it again).
## GameSettings applies it (`apply_to_input`) at start-up and on every change. It sits on top of the
## rework's own input layer (game/shapes/rework_input.gd), which takes this one off and puts it back
## around every change of its own, so each restores only what it changed.
##
## Owner: player builder.

## Action -> the physical keys it has (nothing else).
const LAYOUT := {
	&"move_up": [KEY_UP],
	&"move_down": [KEY_DOWN],
	&"move_left": [KEY_LEFT],
	&"move_right": [KEY_RIGHT],
	&"attack": [KEY_A],
	&"dodge": [KEY_S],
	&"ability_use": [KEY_D],
	&"eat": [KEY_Q],
	&"interact": [KEY_W],
	&"weapon_previous": [],
	&"weapon_next": [KEY_E],
}

## Action -> its events before the keys-only scheme rebound it; empty while it is off.
static var _saved: Dictionary = {}


## Rebinds the InputMap for the keys-only scheme (`keys_only`), or restores it.
static func apply(keys_only: bool) -> void:
	if keys_only:
		_rebind(LAYOUT)
		return
	for action: StringName in _saved:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved[action]:
			InputMap.action_add_event(action, event)
	_saved.clear()


## Gives every action of `layout` exactly its keys there, remembering its events first (once).
static func _rebind(layout: Dictionary) -> void:
	for action: StringName in layout:
		if not InputMap.has_action(action):
			continue
		if not _saved.has(action):
			_saved[action] = InputMap.action_get_events(action).duplicate()
		InputMap.action_erase_events(action)
		for keycode: Key in layout[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)


## True while the keys-only bindings are on.
static func is_applied() -> bool:
	return not _saved.is_empty()
