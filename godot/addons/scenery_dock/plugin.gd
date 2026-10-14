@tool
extends EditorPlugin
## The Scenery dock (docs/godot/PROPS.md): every scenery prop of the `cell-props` and `details`
## palettes by its picture, by category and with a name search. Drag a picture into the 2D view and
## Godot places the prop's scene there as a node (select it, move it freely, edit it in the
## Inspector) under the edited world's `Scenery` node, made when missing, at the size chosen in
## the dock (its root's scale). Painting stays for the mass of small scenery; this is for the props
## to place and nudge one by one.
##
## Owner: world (props).

const Dock := preload("res://addons/scenery_dock/scenery_dock.gd")
## The node placed props go under, a child of the world's root.
const CONTAINER := "Scenery"

var _dock: Control
## The drag in flight: {scene, size, container}, until its prop lands or the drag ends.
var _pending := {}


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Scenery"
	_dock.set(&"prepare_drop", _prepare_drop)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# the drop (if any) has placed its node by now
		_pending = {}


## Readies a drag of `scene` at `size`: selects the world's Scenery node for the drop. False when no
## 2D scene is being edited.
func _prepare_drop(scene: String, size: float) -> bool:
	if not _select_container():
		return false
	_pending = {"scene": scene, "size": size, "container": EditorInterface.get_selection().get_selected_nodes()[0]}
	return true


## The dropped prop: gets the dock's size.
func _on_node_added(node: Node) -> void:
	if _pending.is_empty() or node.scene_file_path != _pending["scene"] or node.get_parent() != _pending["container"]:
		return
	var size: float = _pending["size"]
	_pending = {}
	if node is Node2D and not is_equal_approx(size, 1.0):
		(node as Node2D).scale *= size


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
