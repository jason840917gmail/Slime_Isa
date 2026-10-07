extends "res://game/shell/shell_menu.gd"
## A chapter's end card (Phaser `features/shell/EndCardSurfacePort.ts`, `content/story/endCards.ts`,
## `ui/end-card.scene.json`): shown the moment its story flag is first set during play, never for a
## flag the run already had when the world loaded. "Return to title" saves and goes to the title.
## Escape never closes it. The Shell watches `RunState.story_flag_changed` and calls `check_flags`.
##
## Owner: shell.

## "return-to-title".
signal action_requested(action_id: StringName)

## END_CARDS (content/story/endCards.ts): {flag_id, title, subtitle, body}.
const CARDS: Array[Dictionary] = [
	{
		"flag_id": "chapter-2-complete",
		"title": "End of Chapter 2",
		"subtitle": "Gloop Forest",
		"body": "The Matron's web is broken, the Forge burns again, and Slimeshire has iron. The Crystal Caverns wait beyond the forest: Chapter 3 is still to come. Your run is saved when you return to the title.",
	},
	{
		"flag_id": "playground-end-card-test",
		"title": "The End (test)",
		"subtitle": "Playground",
		"body": "This card is what finishing a chapter will look like. Your run is saved when you return to the title.",
	},
]

## Flags whose card was shown (or was already set when the world loaded).
var _shown_flags: Dictionary = {}
var _card: Dictionary = {}

@onready var title_label: Label = $Panel/Margin/Rows/Title
@onready var subtitle_label: Label = $Panel/Margin/Rows/Subtitle
@onready var body_label: Label = $Panel/Margin/Rows/Body
@onready var return_button: Button = $Panel/Margin/Rows/Return


func _ready() -> void:
	super()
	return_button.pressed.connect(_on_return)


## Marks every card whose flag `has_flag` already reports as shown (a newly loaded world).
func mark_existing(has_flag: Callable) -> void:
	for card: Dictionary in CARDS:
		if bool(has_flag.call(str(card["flag_id"]))):
			_shown_flags[card["flag_id"]] = true


## `EndCardSurfacePort.checkFlags`: opens the first card whose flag is newly set. True if one opened.
func check_flags(has_flag: Callable) -> bool:
	for card: Dictionary in CARDS:
		var flag := str(card["flag_id"])
		if not _shown_flags.has(flag) and bool(has_flag.call(flag)):
			_shown_flags[flag] = true
			_card = card
			open()
			return true
	return false


func current_card() -> Dictionary:
	return _card.duplicate()


func refresh() -> void:
	title_label.text = str(_card.get("title", ""))
	subtitle_label.text = str(_card.get("subtitle", ""))
	body_label.text = str(_card.get("body", ""))


func _on_return() -> void:
	close()
	action_requested.emit(&"return-to-title")
