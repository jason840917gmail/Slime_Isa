extends Panel
## Converted ModalRoot (runtime spec section 4.21): a panel that is shown when
## `open`, stops the mouse, and emits `close_requested` on Escape (`ui_cancel`)
## while open. Focus trapping and first-button focus belong to the Phase 3 UI.
##
## Owner: converter builder.

signal close_requested

## Phaser `open`; mirrors `visible`.
var open: bool:
	get:
		return visible
	set(value):
		visible = value


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit()
