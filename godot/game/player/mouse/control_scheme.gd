extends RefCounted
## The control scheme: how the mouse drives the slime (experiment, branch exp/mouse-controls).
##
## | scheme | walk | left click | right click |
## |---|---|---|---|
## | keyboard | WASD | swing toward the pointer | use the target in reach |
## | click (Diablo) | click the ground (hold to follow the pointer) | order: walk / attack / use | use: what is under the pointer (walking there), else the target in reach |
## | moba | right-click the ground (hold to follow) | swing in place toward the pointer | order: walk / attack / use |
## | pointer | W (or ↑) walks toward the pointer; the slime always faces it | swing toward the pointer | use the target in reach |
## | keys | the arrows; no mouse at all (A swings where the slime faces, W uses, S / D switch weapons) | nothing | nothing |
##
## An order (game/player/mouse/click_orders.gd) is what the button was pressed on: an enemy or a
## resource -> walk into weapon reach and swing (hold to keep swinging); something usable (a door,
## a chest, an NPC, a bed, a bench, a Gulp spot) -> walk to it and use it; the ground -> walk there
## (game/player/mouse/click_path.gd). In the click scheme Shift + left click swings in place.
## In the click and moba schemes WASD and every key keep working; a movement key cancels an order.
## In the pointer scheme only W walks (A, S and D do not, nor any click), and the slime turns to the
## pointer whenever it is free to (not rolling, swinging, knocked back or busy with an ability).
## In the keys scheme the InputMap is rebound (game/player/mouse/key_bindings.gd), the pointer
## aims nothing (`uses_mouse`): the swing, the dodge, the lash and the teleport go where the slime
## faces, the interact button picks without it, and placed furniture goes in front of the slime.
## Placing furniture keeps the keyboard scheme's buttons (left places, right cancels).
##
## Stored in GameSettings (`control_scheme`); the Settings window and F2 (`control_scheme_next`)
## change it.
##
## Owner: player builder.

const Services := preload("res://game/shared/services.gd")
const GameSettings := preload("res://game/shell/game_settings.gd")

const KEYBOARD := "keyboard"
const CLICK := "click"
const MOBA := "moba"
const POINTER := "pointer"
const KEYS := "keys"
## What the Settings window and the F2 message call each scheme.
const NAMES := {
	KEYBOARD: "Keyboard (WASD)",
	CLICK: "Click to move (Diablo)",
	MOBA: "Right-click to move (MOBA)",
	POINTER: "Face the pointer, W walks",
	KEYS: "Keys only (arrows, A attacks, W uses)",
}


## The player's scheme (the Shell's settings); the keyboard scheme without them.
static func current() -> String:
	var shell := Services.shell()
	var settings: GameSettings = shell.get_settings() if shell != null else null
	return parse(settings.value("control_scheme")) if settings != null else KEYBOARD


## `value` when it names a scheme, else the keyboard scheme.
static func parse(value: Variant) -> String:
	var scheme := str(value)
	return scheme if GameSettings.CONTROL_SCHEMES.has(scheme) else KEYBOARD


## The scheme after `scheme` (F2 and the Settings button cycle keyboard -> click -> moba ->
## pointer -> keys).
static func next(scheme: String) -> String:
	var index := GameSettings.CONTROL_SCHEMES.find(parse(scheme))
	return GameSettings.CONTROL_SCHEMES[(index + 1) % GameSettings.CONTROL_SCHEMES.size()]


## Saves `scheme` in the Shell's settings. False without them.
static func store(scheme: String) -> bool:
	var shell := Services.shell()
	var settings: GameSettings = shell.get_settings() if shell != null else null
	if settings == null:
		return false
	settings.update({"control_scheme": parse(scheme)})
	return true


static func display_name(scheme: String) -> String:
	return str(NAMES[parse(scheme)])


## True when a mouse button gives orders (the click and moba schemes).
static func uses_orders(scheme: String) -> bool:
	var parsed := parse(scheme)
	return parsed == CLICK or parsed == MOBA


## False in the keys scheme: the pointer aims nothing and picks nothing there.
static func uses_mouse(scheme: String) -> bool:
	return parse(scheme) != KEYS


## True when the slime faces the pointer and W walks toward it (the pointer scheme).
static func faces_pointer(scheme: String) -> bool:
	return parse(scheme) == POINTER


## The button that walks, attacks and uses; MOUSE_BUTTON_NONE without orders.
static func order_button(scheme: String) -> MouseButton:
	match parse(scheme):
		CLICK:
			return MOUSE_BUTTON_LEFT
		MOBA:
			return MOUSE_BUTTON_RIGHT
	return MOUSE_BUTTON_NONE


## The button that swings in place toward the pointer in an order scheme: the moba scheme's left
## button. MOUSE_BUTTON_NONE elsewhere (the click scheme swings with Shift + left click; the
## keyboard and pointer schemes with their `attack` binding).
static func swing_button(scheme: String) -> MouseButton:
	return MOUSE_BUTTON_LEFT if parse(scheme) == MOBA else MOUSE_BUTTON_NONE


## The button that uses things in an order scheme: the click scheme's right button (what is under
## the pointer, walking there, else the target in reach). MOUSE_BUTTON_NONE elsewhere.
static func use_button(scheme: String) -> MouseButton:
	return MOUSE_BUTTON_RIGHT if parse(scheme) == CLICK else MOUSE_BUTTON_NONE


## The order button as a verb for prompts ("Click: Open chest"); "" without orders.
static func order_verb(scheme: String) -> String:
	match parse(scheme):
		CLICK:
			return "Click"
		MOBA:
			return "Right-click"
	return ""


## How to swing in place, as a verb ("Shift + click"); "" without orders.
static func swing_verb(scheme: String) -> String:
	match parse(scheme):
		CLICK:
			return "Shift + click"
		MOBA:
			return "Left-click"
	return ""
