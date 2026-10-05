extends RefCounted
class_name ControlLabels
## The names players see for the controls, read from the InputMap so they never disagree with
## the bindings (Phaser `features/player/ControlLabels.ts`, `features/shell/ControlsSurfacePort.ts`).
## Keys use the keyboard layout's printed label (an AZERTY player sees "ZQSD"); mouse buttons and
## a few keys have names. Usable by any prompt ("Right-click: Open chest" via `control_verb`).
##
## Owner: shell.

## CODE_NAMES (ControlLabels.ts:4-24), by physical keycode.
const KEY_NAMES := {
	KEY_SPACE: "Space",
	KEY_SHIFT: "Shift",
	KEY_ESCAPE: "Esc",
	KEY_ENTER: "Enter",
	KEY_TAB: "Tab",
	KEY_UP: "↑",
	KEY_DOWN: "↓",
	KEY_LEFT: "←",
	KEY_RIGHT: "→",
	KEY_EQUAL: "+",
	KEY_MINUS: "−",
	KEY_KP_ADD: "+",
	KEY_KP_SUBTRACT: "−",
}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Left click",
	MOUSE_BUTTON_MIDDLE: "Middle click",
	MOUSE_BUTTON_RIGHT: "Right click",
	MOUSE_BUTTON_WHEEL_UP: "Mouse wheel",
	MOUSE_BUTTON_WHEEL_DOWN: "Mouse wheel",
}
const MOVEMENT_ACTIONS: Array[StringName] = [&"move_up", &"move_left", &"move_down", &"move_right"]


## `controlRows()` (ControlsSurfacePort.ts:9-27): [key label, what it does] per control.
static func control_rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = [
		PackedStringArray([movement_label(), "Move"]),
		PackedStringArray([control_label(&"attack"), "Attack, or chop and mine"]),
		PackedStringArray([control_label(&"interact"), "Talk, open, sleep, craft at a bench; hold to pick up placed furniture"]),
		PackedStringArray([control_label(&"sprint"), "Hold to run"]),
		PackedStringArray([control_label(&"jump"), "Jump (learned in the story)"]),
		PackedStringArray([control_label(&"dodge"), "Dodge roll toward the pointer (learned in the story)"]),
		PackedStringArray([control_label(&"stretch_lash"), "Stretch Lash toward the pointer"]),
		PackedStringArray([control_label(&"squash_slam"), "Squash Slam"]),
		PackedStringArray([control_label(&"teleport"), "Teleport to the pointer"]),
		PackedStringArray([control_label(&"eat"), "Gulp: tap to eat at a Gulp spot or burp a form; hold for the quick wheel"]),
		PackedStringArray([control_label(&"weapon_next"), "Switch between equipped weapons"]),
		PackedStringArray([control_label(&"menu"), "Bag, crafting, journal and map"]),
		PackedStringArray([control_label(&"map"), "World map"]),
		PackedStringArray(["%s / %s" % [control_label(&"zoom_in"), control_label(&"zoom_out")], "Zoom in / out"]),
		PackedStringArray([control_label(&"pause"), "Pause menu, or close the open window"]),
	]
	return rows


## The label of an action's main (first) binding, e.g. "Space" for `jump`; "" when unbound.
static func control_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		var label := event_label(event)
		if not label.is_empty():
			return label
	return ""


## Every distinct label of an action's bindings joined with " / " ("+ / −").
static func control_labels(action: StringName) -> String:
	var labels := PackedStringArray()
	if InputMap.has_action(action):
		for event: InputEvent in InputMap.action_get_events(action):
			var label := event_label(event)
			if not label.is_empty() and not labels.has(label):
				labels.append(label)
	return " / ".join(labels)


## The four movement keys as one label: "WASD" (or "ZQSD" on AZERTY).
static func movement_label() -> String:
	var label := ""
	for action: StringName in MOVEMENT_ACTIONS:
		label += control_label(action)
	return label


## "Right click" -> "Right-click", for prompts that read as a verb.
static func control_verb(action: StringName) -> String:
	var label := control_label(action)
	return label.trim_suffix(" click") + "-click" if label.ends_with(" click") else label


## `codeLabel` for one InputEvent ("W", "1", "Space", "Right click"); "" for other devices.
static func event_label(event: InputEvent) -> String:
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return str(MOUSE_NAMES.get(mouse.button_index, "Mouse %d" % mouse.button_index))
	var key := event as InputEventKey
	if key == null:
		return ""
	var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if KEY_NAMES.has(code):
		return str(KEY_NAMES[code])
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return "Num %d" % (code - KEY_KP_0)
	var printed := code
	if key.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
		var layout_key := DisplayServer.keyboard_get_label_from_physical(code)
		if layout_key != KEY_NONE:
			printed = layout_key
	return OS.get_keycode_string(printed).to_upper()
