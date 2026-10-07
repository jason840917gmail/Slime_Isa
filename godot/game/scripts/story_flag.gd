extends Node
## Scene script `game.story-flag` (Phaser `features/scripts/StoryFlagScript.ts`): sets a saved
## story flag (`RunState.set_flag`) when its `set` handler runs, so authored pieces (a pressure
## plate's `pressed`, for example) move the story on without code. The converter connects the
## JSON handler `set` to `on_set` (Object already has a `set`).
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")

## JSON `flagId`.
@export var flag_id: String = ""


## Handler `set` (any payload).
func on_set(_payload: Variant = null) -> void:
	var run := Services.run()
	if not flag_id.is_empty() and run != null:
		run.set_flag(flag_id)
