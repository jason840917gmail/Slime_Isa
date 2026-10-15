@tool
extends EditorInspectorPlugin
## Puts the strike preview (strike_preview.gd) above the fields of a StrikeAnimation (game/characters/strikes/).

const AnimationType := preload("res://game/shapes/strike_animation.gd")
const StrikePreview := preload("res://addons/strike_preview/strike_preview.gd")


func _can_handle(object: Object) -> bool:
	return object is AnimationType


func _parse_begin(object: Object) -> void:
	var preview := StrikePreview.new()
	preview.strike = object as AnimationType
	add_custom_control(preview)
