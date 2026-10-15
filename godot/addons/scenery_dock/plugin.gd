@tool
extends EditorPlugin
## The Scenery dock (docs/godot/PROPS.md): every scenery prop of the `cell-props` and `details`
## palettes by its picture, by category and with a name search. Drag a picture into the 2D view and
## Godot places the prop's scene there as a node; this plugin then moves it under the edited
## world's `Scenery` node (made when missing) and gives it the size chosen in the dock (its root's
## scale), in one step Ctrl+Z undoes. While dragging, Godot's own preview of the prop is shown at
## that size too. Painting stays for the mass of small scenery; this is for the props to place and
## nudge one by one.
##
## Also leaves the palette pictures out of exported games (palette_export.gd).
##
## Owner: world (props).

const Dock := preload("res://addons/scenery_dock/scenery_dock.gd")
const PaletteExport := preload("res://addons/scenery_dock/palette_export.gd")
## The node placed props go under, a child of the world's root.
const CONTAINER := "Scenery"

var _dock: Control
var _export: EditorExportPlugin
## The drag in flight: {scene, size}, until the drag ends.
var _pending := {}
## The props the drag's drop placed in the edited scene.
var _dropped: Array[Node] = []


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Scenery"
	_dock.set(&"prepare_drop", _prepare_drop)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	get_tree().node_added.connect(_on_node_added)
	_export = PaletteExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	if _export != null:
		remove_export_plugin(_export)
		_export = null
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not _pending.is_empty():
		# Godot has dropped the prop (or the drag was cancelled) by now
		_finish_drop.call_deferred(_pending.duplicate(), _dropped.duplicate())
		_pending = {}
		_dropped.clear()


## Readies a drag of `scene` at `size`. False when no 2D scene is being edited.
func _prepare_drop(scene: String, size: float) -> bool:
	if not EditorInterface.get_edited_scene_root() is Node2D:
		return false
	_pending = {"scene": scene, "size": size}
	_dropped.clear()
	return true


## While a drag is in flight: Godot's preview of the prop (outside the edited scene) takes the
## dock's size at once; the prop dropped into the edited scene is kept for _finish_drop.
func _on_node_added(node: Node) -> void:
	if _pending.is_empty() or node.scene_file_path != _pending["scene"] or not node is Node2D:
		return
	var root := EditorInterface.get_edited_scene_root()
	if root != null and root.is_ancestor_of(node):
		_dropped.append(node)
	else:
		(node as Node2D).scale *= float(_pending["size"])


## Moves the dropped props under the world's Scenery node, where they stood, at the dock's size
## (one undoable step; the Scenery node is made when missing).
func _finish_drop(pending: Dictionary, dropped: Array[Node]) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var nodes := dropped.filter(func(node: Node) -> bool: return is_instance_valid(node) and node.is_inside_tree() \
			and root != null and root.is_ancestor_of(node))
	if nodes.is_empty():
		return
	var size := float(pending["size"])
	var undo := get_undo_redo()
	undo.create_action("Place in Scenery")
	var container := root.get_node_or_null(CONTAINER) as Node2D
	if container == null:
		container = Node2D.new()
		container.name = CONTAINER
		container.y_sort_enabled = true
		undo.add_do_method(root, &"add_child", container, true)
		undo.add_do_method(container, &"set_owner", root)
		undo.add_do_reference(container)
		undo.add_undo_method(root, &"remove_child", container)
	for node: Node2D in nodes:
		var parent := node.get_parent()
		if parent != container:
			undo.add_do_method(node, &"reparent", container, true)
			undo.add_do_method(node, &"set_owner", root)
			# undo runs backwards: back to its parent first, then its owner again
			undo.add_undo_method(node, &"set_owner", root)
			undo.add_undo_method(node, &"reparent", parent, true)
		if not is_equal_approx(size, 1.0):
			undo.add_do_property(node, &"scale", node.scale * size)
			undo.add_undo_property(node, &"scale", node.scale)
	undo.commit_action()
