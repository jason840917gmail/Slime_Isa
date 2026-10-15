@tool
extends EditorPlugin
## The strike preview (BODY_SHAPES.md "Editing the strike animations"): adds strike_inspector.gd, which puts
## strike_preview.gd above a StrikeAnimation's fields in the Inspector.

const StrikeInspector := preload("res://addons/strike_preview/strike_inspector.gd")

var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	_inspector = StrikeInspector.new()
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	if _inspector != null:
		remove_inspector_plugin(_inspector)
		_inspector = null
