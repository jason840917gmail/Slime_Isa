extends RefCounted
class_name ControlLabels
## The names players see for the controls, read from the InputMap so they never disagree with
## the bindings (Phaser `features/player/ControlLabels.ts`, `features/shell/ControlsSurfacePort.ts`).
## Keys use the keyboard layout's printed label (an AZERTY player sees "ZQSD"); mouse buttons and
## a few keys have names. Usable by any prompt ("Right-click: Open chest" via `control_verb`).
##
## Owner: shell.

## CODE_NAMES (ControlLabels.ts:4-24), by physical keycode. The arrow keys are arrows, as in Phaser
## (the theme's Source Sans 3 has ↑ ↓ ← →; docs/godot/UI_THEME.md, "Symbols").
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
## The potion belt's keys, slot order (project.godot: 1 to 4; game/inventory/potion_belt.gd).
const POTION_ACTIONS: Array[StringName] = [&"potion_1", &"potion_2", &"potion_3", &"potion_4"]
const POTION_KEYS_TEXT := "Drink one potion from that belt slot (belt slots are found; set a potion to one in your bag)"
const ReworkMode := preload("res://game/shapes/rework_mode.gd")


## `controlRows()` (ControlsSurfacePort.ts:9-27): [key label, what it does] per control, keys only (one
## combat, 2026-11-25: the mouse schemes are gone; everything aimed goes the way the slime faces). The
## body-shapes rework mode lists its own controls (`rework_rows`).
static func control_rows() -> Array[PackedStringArray]:
	if ReworkMode.is_on():
		return rework_rows()
	var rows: Array[PackedStringArray] = []
	rows.append(PackedStringArray([movement_label(), "Move"]))
	rows.append(PackedStringArray([control_label(&"attack"), "Attack, or chop and mine"]))
	rows.append(PackedStringArray([control_label(&"interact"), "Talk, open, sleep, craft at a bench; hold to pick up placed furniture"]))
	rows.append_array([
		PackedStringArray([control_label(&"dodge"), "Roll the way the slime faces: spin up, then dash straight on while held; bonk into walls (learned in the story)"]),
		PackedStringArray([control_label(&"stretch_lash"), "Stretch Lash the way the slime faces"]),
		PackedStringArray([control_label(&"squash_slam"), "Squash Slam"]),
		PackedStringArray([control_label(&"teleport"), "Teleport as far as it goes the way the slime faces"]),
		PackedStringArray([control_label(&"eat"), "Hold to suck in an essence or a light thing (a pot, a rock, a pumpkin...); press again to throw it"]),
		PackedStringArray([control_label(&"swallow"), "Swallow the essence you hold to take its form; with nothing held, spit the form out"]),
		PackedStringArray([potion_keys_label(), POTION_KEYS_TEXT]),
		PackedStringArray([control_labels(&"weapon_next"), "Switch between equipped weapons"]),
		PackedStringArray([control_label(&"menu"), "Bag, crafting, journal and map"]),
		PackedStringArray([control_label(&"journal"), "Journal"]),
		PackedStringArray([control_label(&"map"), "World map"]),
		PackedStringArray(["%s / %s" % [control_label(&"zoom_in"), control_label(&"zoom_out")], "Zoom in / out"]),
		PackedStringArray([control_label(&"pause"), "Pause menu, or close the open window"]),
	])
	# The old Swallow, Stretch Lash, Squash Slam and Teleport have no key since 2026-11-20 (1 to 4
	# are the potion belt's): a control without a key is not listed.
	var listed: Array[PackedStringArray] = []
	for row: PackedStringArray in rows:
		if not row[0].is_empty():
			listed.append(row)
	return listed


## "1–4": the potion belt's keys (`potion_1` .. `potion_4`) as one label; each key's own label
## joined with " / " when they are not the plain run 1 to 4 (another layout, a rebinding).
static func potion_keys_label() -> String:
	var labels := PackedStringArray()
	for action: StringName in POTION_ACTIONS:
		labels.append(control_label(action))
	if labels == PackedStringArray(["1", "2", "3", "4"]):
		return "1–4"
	return " / ".join(labels)


## The body-shapes rework mode's rows (docs/godot/BODY_SHAPES.md "Controls in the rework mode";
## body-shapes plan sections 5 and 6; one combat, 2026-11-25): keys only; the attack is the current
## weapon's (tap to chain, hold to charge, free), E the next weapon, Q the whole mouth with the throw
## rules, `ability_use` the box ability chosen in the bag; no Swallow, Lash, Slam or Teleport keys.
static func rework_rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var charge := "taps in rhythm chain a combo (each strikes as you let go); hold until the ring fills, then let go to charge"
	rows.append(PackedStringArray([movement_label(), "Move"]))
	rows.append(PackedStringArray([control_label(&"attack"), "Attack with your weapon; %s" % charge]))
	rows.append(PackedStringArray([control_label(&"interact"), "Talk, open, sleep, craft at a bench; hold to pick up placed furniture"]))
	rows.append_array([
		PackedStringArray([control_label(&"dodge"), "Roll the way the slime faces as you let go: a tap rolls a short way; with the charged-roll upgrade, hold to spin up, then dash straight on while held; bonk into walls (learned in the story)"]),
		PackedStringArray([control_label(&"ability_use"), "Use the ability chosen in the bag (the way the slime faces)"]),
		PackedStringArray([control_label(&"eat"), "Gulp: press to suck for a second; tap to throw what you hold (its weight sets the blow) or spit an essence out; hold until the ring fills to swallow an essence, or with an empty mouth to spit your form out"]),
		PackedStringArray([control_labels(&"weapon_next"), "Next weapon (Spear, War Axe, Hammer: the ones you have)"]),
		PackedStringArray([potion_keys_label(), POTION_KEYS_TEXT]),
		PackedStringArray([control_label(&"menu"), "Bag: your weapons, abilities and skins on top (choose here); crafting, journal and map"]),
		PackedStringArray([control_label(&"journal"), "Journal"]),
		PackedStringArray([control_label(&"map"), "World map"]),
		PackedStringArray(["%s / %s" % [control_label(&"zoom_in"), control_label(&"zoom_out")], "Zoom in / out"]),
		PackedStringArray([control_label(&"pause"), "Pause menu, or close the open window"]),
	])
	return rows


## The label of an action's main (first) binding, e.g. "Space" for `dodge` (the Roll); "" when unbound.
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


## "Right click" -> "Right-click", for prompts that read as a verb; a key reads "Press A" (the keys-only
## scheme, the default since 2026-11-25: "A to attack" did not read).
static func control_verb(action: StringName) -> String:
	var label := control_label(action)
	if label.ends_with(" click"):
		return label.trim_suffix(" click") + "-click"
	return "Press %s" % label if not label.is_empty() else label


## How a text names `action`'s main binding inside a sentence: "the mouse wheel" for a mouse binding (in
## lower case), the key itself ("E") for a key.
static func control_in_sentence(action: StringName) -> String:
	var label := control_label(action)
	return "the " + label.to_lower() if label.contains(" ") else label


## `text` with each `{<action>}` replaced by that action's main key, so a text kept as data follows
## the bindings: "holding {interact}" reads "holding W" in the keys-only scheme and "holding right
## click" with the mouse (a mouse button in lower case, inside a sentence). An unbound or unknown
## action reads "the <action> key".
static func with_keys(text: String) -> String:
	var out := text
	var start := out.find("{")
	while start >= 0:
		var end := out.find("}", start)
		if end < 0:
			break
		var action := out.substr(start + 1, end - start - 1)
		var label := control_label(StringName(action))
		if label.is_empty():
			label = "the %s key" % action.replace("_", " ")
		elif label.ends_with(" click"):
			label = label.to_lower()
		out = out.substr(0, start) + label + out.substr(end + 1)
		start = out.find("{", start + label.length())
	return out


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
	# The layout's own label (an AZERTY "A" on the physical Q) where the display server has one;
	# headless and the web display server do not (on the web the call only logs an error), so
	# there the physical key names the key, as Phaser's `event.code` labels do.
	if key.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		var layout_key := DisplayServer.keyboard_get_label_from_physical(code)
		if layout_key != KEY_NONE:
			printed = layout_key
	return OS.get_keycode_string(printed).to_upper()
