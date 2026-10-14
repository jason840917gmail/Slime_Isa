@tool
extends EditorPlugin
## The Scenery dock (docs/godot/PROPS.md): every scenery prop of the `cell-props` and `details`
## palettes by its picture, by category and with a name search. Drag a picture into the 2D view and
## Godot places the prop's scene there as a node (select it, move it freely, edit it in the
## Inspector) under the edited world's `Scenery` node, made when missing. Painting stays for the
## mass of small scenery; this is for the props to place and nudge one by one.
##
## Owner: world (props).

const Dock := preload("res://addons/scenery_dock/scenery_dock.gd")
## The node placed props go under, a child of the world's root.
const CONTAINER := "Scenery"

var _dock: Control


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Scenery"
	_dock.set(&"prepare_drop", _select_container)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


## Selects the edited world's Scenery node (making it, undoably, when missing), so the prop dropped
## next lands under it. False when no 2D scene is being edited.
func _select_container() -> bool:
	var root := EditorInterface.get_edited_scene_root() as Node2D
	if root == null:
		return false
	var container := root.get_node_or_null(CONTAINER) as Node2D
	if container == null:
		container = Node2D.new()
		container.name = CONTAINER
		container.y_sort_enabled = true
		var undo := get_undo_redo()
		undo.create_action("Add the Scenery node")
		undo.add_do_method(root, &"add_child", container, true)
		undo.add_do_method(container, &"set_owner", root)
		undo.add_do_reference(container)
		undo.add_undo_method(root, &"remove_child", container)
		undo.commit_action()
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(container)
	return true
