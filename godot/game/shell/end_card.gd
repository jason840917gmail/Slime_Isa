extends "res://game/shell/shell_menu.gd"
## A chapter's end card (Phaser `features/shell/EndCardSurfacePort.ts`, `content/story/endCards.ts`,
## `ui/end-card.scene.json`): shown the moment its story flag is first set during play, never for a
## flag the run already had when the world loaded. "Return to title" saves and goes to the title.
## Escape never closes it. The Shell watches `RunState.story_flag_changed` and calls `check_flags`.
##
## Owner: shell.

## "return-to-title".
signal action_requested(action_id: StringName)

## END_CARDS (content/story/endCards.ts): {flag_id, title, subtitle, body}. Since 2026-11-19 the
## Chapter 2 card is gone and Release 1's card shows when the Crystal Colossus falls (his fall sets
## `chapter-3-complete`: RunState `record_boss_defeated`, quests spec 14.6).
const CARDS: Array[Dictionary] = [
	{
		"flag_id": "chapter-3-complete",
		"title": "The first three Pearls",
		"subtitle": "The end of Release 1",
		"body": "Three Pearls are won back, and the Wellspring remembers how to shine. From here the story goes on as you explore the lands you have found: bring every Pearl home and look for what is still hidden. More of the world opens in later releases. Your run is saved when you return to the title.",
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
